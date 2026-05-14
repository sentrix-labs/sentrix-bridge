//! wSRX 1:1 invariant.
//!
//! On Sentrix, the HypERC20Collateral contract holds wSRX tokens equal to
//! the supply of HypERC20 (wSRX) on Sepolia. If anyone bypasses the
//! collateral and mints / burns directly on Sepolia, drift opens and the
//! bridge becomes under-collateralized.
//!
//! We verify:
//!   collateral.balanceOf(WSRX) == hyperc20_sepolia.totalSupply()
//!
//! Note: we ALSO surface `WSRX.totalSupply()` (Sentrix-side) for context but
//! do not enforce it equals the collateral balance — random users hold
//! wSRX outside the bridge, that's fine.

use alloy::network::Ethereum;
use alloy::primitives::U256;
use alloy::providers::Provider;

use super::{parse_address, IErc20Lite};
use crate::config::RuntimeConfig;
use crate::report::{InvariantStatus, WsrxInvariant};

#[allow(clippy::too_many_arguments)]
pub async fn check_invariant<S, T>(
    _cfg: &RuntimeConfig,
    wsrx_sentrix: &str,
    collateral_sentrix: &str,
    hyperc20_sepolia: &str,
    sentrix_provider: S,
    sepolia_provider: T,
) -> WsrxInvariant
where
    S: Provider<Ethereum> + Clone + 'static,
    T: Provider<Ethereum> + Clone + 'static,
{
    let mut report = WsrxInvariant {
        wsrx_total_supply_sentrix: "0".to_string(),
        wsrx_locked_in_collateral: "0".to_string(),
        hyperc20_total_supply_sepolia: "0".to_string(),
        drift_wei: "0".to_string(),
        status: InvariantStatus::Unknown,
        ok: false,
        error: None,
    };

    let (wsrx_addr, collateral_addr, sepolia_addr) = match (
        parse_address(wsrx_sentrix),
        parse_address(collateral_sentrix),
        parse_address(hyperc20_sepolia),
    ) {
        (Ok(a), Ok(b), Ok(c)) => (a, b, c),
        _ => {
            report.error = Some("invalid address in deployments JSON".into());
            return report;
        }
    };

    let wsrx = IErc20Lite::new(wsrx_addr, sentrix_provider.clone());
    let sepolia = IErc20Lite::new(sepolia_addr, sepolia_provider.clone());

    let wsrx_total = match wsrx.totalSupply().call().await {
        Ok(v) => v,
        Err(e) => {
            // Couldn't fetch — leave status as Unknown, surface why.
            report.error = Some(format!("wsrx.totalSupply: {e}"));
            return report;
        }
    };
    let collateral_balance = match wsrx.balanceOf(collateral_addr).call().await {
        Ok(v) => v,
        Err(e) => {
            report.error = Some(format!("wsrx.balanceOf(collateral): {e}"));
            return report;
        }
    };
    let sepolia_supply = match sepolia.totalSupply().call().await {
        Ok(v) => v,
        Err(e) => {
            report.error = Some(format!("sepolia hyperc20.totalSupply: {e}"));
            return report;
        }
    };

    report.wsrx_total_supply_sentrix = wsrx_total.to_string();
    report.wsrx_locked_in_collateral = collateral_balance.to_string();
    report.hyperc20_total_supply_sepolia = sepolia_supply.to_string();
    report.drift_wei = signed_drift(collateral_balance, sepolia_supply);
    // Both numbers came back. Now we can call Ok vs Drift.
    //
    // Two zeros is technically "equal" but the bridge has known traffic so
    // 0/0 is overwhelmingly an RPC-call-returned-empty-data symptom on the
    // collateral side — treat it as Drift so the operator looks closer.
    if collateral_balance == sepolia_supply && collateral_balance != U256::ZERO {
        report.status = InvariantStatus::Ok;
        report.ok = true;
    } else {
        report.status = InvariantStatus::Drift;
        report.ok = false;
    }
    report
}

/// Format the signed drift `collateral - sepolia_supply` as a decimal
/// string. We can't just `to_string()` a U256 difference because it
/// underflows when the bridge is over-issued on Sepolia (which is the
/// alarming direction we most want to detect).
fn signed_drift(collateral: U256, sepolia: U256) -> String {
    if collateral >= sepolia {
        (collateral - sepolia).to_string()
    } else {
        let abs = sepolia - collateral;
        format!("-{abs}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn drift_zero_when_equal() {
        assert_eq!(signed_drift(U256::from(100u64), U256::from(100u64)), "0");
    }

    #[test]
    fn drift_positive_when_collateral_exceeds_supply() {
        assert_eq!(signed_drift(U256::from(150u64), U256::from(100u64)), "50");
    }

    #[test]
    fn drift_negative_when_supply_exceeds_collateral() {
        assert_eq!(signed_drift(U256::from(100u64), U256::from(150u64)), "-50");
    }

    // Sanity that the WSRX mainnet address parses cleanly. Belongs in the
    // balance module because parse_address is the gate for every on-chain
    // call here.
    #[test]
    fn wsrx_mainnet_address_parses() {
        let a = parse_address("0x4693b113e523A196d9579333c4ab8358e2656553").unwrap();
        assert_eq!(format!("{a:?}").to_lowercase().len(), 42);
    }
}
