//! Stuck-message detection.
//!
//! Walks the last `stuck_lookback_blocks` blocks on the origin Mailbox for
//! `Dispatch(address sender, uint32 destination, bytes32 recipient, bytes
//! message)`-style logs (we read the `DispatchId(bytes32 messageId)` event
//! since it's a stable single-topic indicator), then checks the destination
//! Mailbox for `ProcessId(bytes32 messageId)` events that match.
//!
//! Reality check: this is best-effort. Public RPC providers cap
//! `eth_getLogs` block ranges (Sepolia public nodes typically allow ~5k
//! blocks). When the call fails we return an empty Vec rather than aborting
//! the whole report — better to deliver partial data than nothing.

use alloy::network::Ethereum;
use alloy::primitives::B256;
use alloy::providers::Provider;
use alloy::rpc::types::Filter;
use alloy::sol;
use alloy::sol_types::SolEvent;
use std::collections::HashSet;

use super::parse_address;
use crate::config::RuntimeConfig;
use crate::report::{StuckCheck, StuckMessage};

sol! {
    event DispatchId(bytes32 messageId);
    event ProcessId(bytes32 messageId);
}

/// Scan for stuck messages. Returns:
///
/// * `Scanned { messages }` — both sides answered; the list is the
///   final verdict (possibly empty)
/// * `Skipped { reason }`   — at least one prerequisite RPC failed; we
///   intentionally do NOT guess. Pre-fix, a destination
///   `eth_blockNumber` failure defaulted dest_head to 0, which then
///   marked every recent dispatch as stuck — a false alarm operators
///   chased multiple times.
pub async fn scan<S, T>(
    cfg: &RuntimeConfig,
    origin_chain: u64,
    origin_mailbox: &str,
    destination_chain: u64,
    destination_mailbox: &str,
    origin_provider: S,
    destination_provider: T,
) -> StuckCheck
where
    S: Provider<Ethereum> + Clone + 'static,
    T: Provider<Ethereum> + Clone + 'static,
{
    let origin_addr = match parse_address(origin_mailbox) {
        Ok(a) => a,
        Err(e) => {
            return StuckCheck::Skipped {
                reason: format!("invalid origin mailbox address: {e}"),
            };
        }
    };
    let dest_addr = match parse_address(destination_mailbox) {
        Ok(a) => a,
        Err(e) => {
            return StuckCheck::Skipped {
                reason: format!("invalid destination mailbox address: {e}"),
            };
        }
    };

    let origin_head = match origin_provider.get_block_number().await {
        Ok(h) => h,
        Err(e) => {
            return StuckCheck::Skipped {
                reason: format!("origin eth_blockNumber failed: {e}"),
            };
        }
    };
    let from_block = origin_head.saturating_sub(cfg.stuck_lookback_blocks);

    let dispatch_filter = Filter::new()
        .address(origin_addr)
        .from_block(from_block)
        .to_block(origin_head)
        .event_signature(DispatchId::SIGNATURE_HASH);

    let dispatch_logs = match origin_provider.get_logs(&dispatch_filter).await {
        Ok(l) => l,
        Err(e) => {
            // Public RPCs commonly cap eth_getLogs range; treat that as
            // a skip with reason rather than a "no stuck messages" fact.
            tracing::warn!("origin getLogs failed (provider likely caps range): {e}");
            return StuckCheck::Skipped {
                reason: format!("origin getLogs failed: {e}"),
            };
        }
    };

    if dispatch_logs.is_empty() {
        return StuckCheck::Scanned { messages: Vec::new() };
    }

    // Destination block height is required to even know how far back to
    // look for ProcessId logs. If the destination RPC is down we cannot
    // tell stuck from in-flight — skip with reason.
    let dest_head = match destination_provider.get_block_number().await {
        Ok(h) => h,
        Err(e) => {
            tracing::warn!("destination eth_blockNumber failed: {e}");
            return StuckCheck::Skipped {
                reason: format!("destination eth_blockNumber failed: {e}"),
            };
        }
    };
    let dest_filter = Filter::new()
        .address(dest_addr)
        .from_block(dest_head.saturating_sub(cfg.stuck_lookback_blocks))
        .to_block(dest_head)
        .event_signature(ProcessId::SIGNATURE_HASH);

    let processed_ids: HashSet<B256> = match destination_provider.get_logs(&dest_filter).await {
        Ok(logs) => logs
            .into_iter()
            .filter_map(|log| log.topics().get(1).copied())
            .collect(),
        Err(e) => {
            tracing::warn!("destination getLogs failed: {e}");
            // Without destination data we can't decide what's stuck.
            return StuckCheck::Skipped {
                reason: format!("destination getLogs failed: {e}"),
            };
        }
    };

    let mut stuck = Vec::new();
    for log in dispatch_logs {
        let Some(id) = log.topics().get(1).copied() else {
            continue;
        };
        if processed_ids.contains(&id) {
            continue;
        }
        let block = log.block_number.unwrap_or(0);
        let age = origin_head.saturating_sub(block);
        // Heuristic: only surface anything older than 32 blocks; younger
        // than that and we're racing a fresh dispatch + relayer.
        if age < 32 {
            continue;
        }
        stuck.push(StuckMessage {
            origin_chain,
            destination_chain,
            message_id: format!("{id:#x}"),
            origin_tx: log
                .transaction_hash
                .map(|h| format!("{h:#x}"))
                .unwrap_or_default(),
            origin_block: block,
            age_blocks: age,
        });
    }

    StuckCheck::Scanned { messages: stuck }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_addr_round_trips() {
        let a = parse_address("0x9741D99270aF14D4baca0e387B6ac0500b9a288F").unwrap();
        let s = format!("{a:#x}");
        assert!(s.starts_with("0x"));
    }
}
