//! `eth_blockNumber` + `eth_chainId` against an RPC. Used for both Sentrix
//! and Sepolia. We deliberately do NOT enforce that chain_id matches a
//! hard-coded expected value here — config-level mismatches are surfaced by
//! the caller (e.g. `--testnet` flag with a mainnet RPC). This check just
//! reports facts.
//!
//! Each call is wrapped in `tokio::time::timeout(RPC_TIMEOUT)`. The
//! underlying alloy provider also has a reqwest-level timeout (see
//! `super::http_provider`), but a belt-and-braces cap here keeps the
//! probe bounded even if a future provider implementation skips the
//! reqwest layer (e.g. mocked client in tests).

use alloy::network::Ethereum;
use alloy::providers::Provider;
use tokio::time::timeout;

use super::RPC_TIMEOUT;
use crate::report::RpcReport;

pub async fn probe<P>(url: &str, provider: P) -> RpcReport
where
    P: Provider<Ethereum>,
{
    let mut report = RpcReport {
        url: url.to_string(),
        ok: false,
        block: None,
        chain_id: None,
        error: None,
    };

    match timeout(RPC_TIMEOUT, provider.get_block_number()).await {
        Ok(Ok(b)) => report.block = Some(b),
        Ok(Err(e)) => {
            report.error = Some(format!("eth_blockNumber: {e}"));
            return report;
        }
        Err(_) => {
            report.error = Some(format!(
                "eth_blockNumber: timed out after {}s",
                RPC_TIMEOUT.as_secs()
            ));
            return report;
        }
    }
    match timeout(RPC_TIMEOUT, provider.get_chain_id()).await {
        Ok(Ok(c)) => report.chain_id = Some(c),
        Ok(Err(e)) => {
            report.error = Some(format!("eth_chainId: {e}"));
            return report;
        }
        Err(_) => {
            report.error = Some(format!(
                "eth_chainId: timed out after {}s",
                RPC_TIMEOUT.as_secs()
            ));
            return report;
        }
    }
    report.ok = true;
    report
}
