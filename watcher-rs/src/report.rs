//! Wire-format types for the JSON report.
//!
//! The schema is consumed by `api-rs` (and any downstream alerting) so it
//! deliberately avoids enums-with-payload and keeps `unsafe_flags` as plain
//! string tags — easier to grep, easier to evolve without bumping consumers.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Report {
    pub timestamp: DateTime<Utc>,
    pub network: String,
    pub sentrix_rpc: RpcReport,
    pub sepolia_rpc: RpcReport,
    pub mailboxes: Vec<MailboxReport>,
    pub routes: Vec<RouteReport>,
    pub wsrx_invariant: Option<WsrxInvariant>,
    /// Flat list of definitely-stuck messages. Empty when the scan ran
    /// and saw nothing OR when the scan was skipped — use `stuck.kind`
    /// to disambiguate.
    pub stuck_messages: Vec<StuckMessage>,
    /// Three-way scan result: scanned vs skipped (with reason). New in
    /// PR #19; clients that only care about the count can keep reading
    /// `stuck_messages`.
    pub stuck: StuckCheck,
    /// Top-level warnings — anything that should page an operator. Empty
    /// vector means everything we could check passed.
    pub warnings: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RpcReport {
    pub url: String,
    pub ok: bool,
    pub block: Option<u64>,
    pub chain_id: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MailboxReport {
    pub label: String,
    pub address: String,
    pub chain_id: u64,
    pub local_domain: Option<u64>,
    pub default_ism: Option<String>,
    pub default_hook: Option<String>,
    pub local_domain_matches: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RouteReport {
    pub id: String,
    pub source_chain: u64,
    pub destination_chain: u64,
    pub source_contract: String,
    pub destination_contract: String,
    pub ism_address: Option<String>,
    pub ism_type: String,
    /// When the route is `MultisigIsm`, surface the signer count + threshold.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub multisig: Option<MultisigInfo>,
    pub unsafe_demo: bool,
    pub unsafe_flags: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MultisigInfo {
    pub validator_count: usize,
    pub threshold: u8,
    pub validators: Vec<String>,
}

/// Three-way result for the wSRX invariant:
///
/// * `Ok`      — both sides fetched, numbers match
/// * `Drift`   — both sides fetched, numbers DON'T match (real alarm)
/// * `Unknown` — at least one RPC/ABI/address call failed; we cannot
///   conclude either way
///
/// Pre-fix the watcher collapsed `Drift` and `Unknown` into a single
/// "drift" warning. That misled operators into chasing imaginary drift
/// during Sepolia public-RPC outages. PR #19 split them.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum InvariantStatus {
    Ok,
    Drift,
    Unknown,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WsrxInvariant {
    pub wsrx_total_supply_sentrix: String,
    pub wsrx_locked_in_collateral: String,
    pub hyperc20_total_supply_sepolia: String,
    /// `wsrx_locked_in_collateral - hyperc20_total_supply_sepolia`. Stored as
    /// a signed decimal string so JS consumers don't truncate u256.
    pub drift_wei: String,
    /// Three-way: ok / drift / unknown. New in PR #19; downstream
    /// `api-rs` should branch on this instead of bare `ok`.
    pub status: InvariantStatus,
    /// Retained for backward-compat with downstream JSON consumers
    /// (`api-rs`, alerting). True iff `status == Ok`.
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StuckMessage {
    pub origin_chain: u64,
    pub destination_chain: u64,
    pub message_id: String,
    pub origin_tx: String,
    pub origin_block: u64,
    pub age_blocks: u64,
}

/// Result of the stuck-message scan. Pre-fix the watcher swallowed
/// destination-RPC failures, defaulted dest_head to 0, and then
/// classified everything as stuck. Now the failure surfaces as
/// `Skipped { reason }` so an alerting consumer can distinguish "no
/// stuck messages" from "we couldn't tell".
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum StuckCheck {
    /// The scan completed; `messages` is the (possibly empty) list of
    /// dispatched-but-not-processed messages older than the heuristic
    /// threshold.
    Scanned { messages: Vec<StuckMessage> },
    /// The scan was skipped because at least one prerequisite RPC call
    /// failed. We don't know if anything is stuck — operator should
    /// re-run after the upstream provider recovers.
    Skipped { reason: String },
}

impl StuckCheck {
    /// View the messages list, returning an empty slice when the scan
    /// was skipped. Convenience for callers that just want "did we see
    /// anything definitely stuck".
    pub fn messages(&self) -> &[StuckMessage] {
        match self {
            StuckCheck::Scanned { messages } => messages,
            StuckCheck::Skipped { .. } => &[],
        }
    }

    pub fn is_skipped(&self) -> bool {
        matches!(self, StuckCheck::Skipped { .. })
    }
}

impl Default for StuckCheck {
    fn default() -> Self {
        StuckCheck::Scanned { messages: Vec::new() }
    }
}
