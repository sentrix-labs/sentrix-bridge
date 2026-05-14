//! `eth_blockNumber` + `eth_chainId` against an RPC. Used for both Sentrix
//! and Sepolia. We deliberately do NOT enforce that chain_id matches a
//! hard-coded expected value here — config-level mismatches are surfaced by
//! the caller (e.g. `--testnet` flag with a mainnet RPC). This check just
//! reports facts.

use alloy::network::Ethereum;
use alloy::providers::Provider;

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

    match provider.get_block_number().await {
        Ok(b) => report.block = Some(b),
        Err(e) => {
            report.error = Some(format!("eth_blockNumber: {e}"));
            return report;
        }
    }
    match provider.get_chain_id().await {
        Ok(c) => report.chain_id = Some(c),
        Err(e) => {
            report.error = Some(format!("eth_chainId: {e}"));
            return report;
        }
    }
    report.ok = true;
    report
}
