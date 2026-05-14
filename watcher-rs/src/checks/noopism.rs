//! NoopIsm detection on warp-route contracts.
//!
//! Strategy: call `interchainSecurityModule()` on the source warp contract.
//! If the returned address matches a known NoopIsm (loaded from
//! `deployments/hyperlane-{testnet,sepolia}.json`), and the route isn't
//! tagged `unsafeDemo: true`, raise `NoopIsm-on-warp-route-unsafe`.
//!
//! Why on the source-side warp contract: the ISM that matters for inbound
//! verification lives on the *destination* mailbox, but warp-route apps
//! usually override the mailbox default ISM via `interchainSecurityModule`.
//! Reading the override on the source side gives us the local operator's
//! intent; the destination side gets its own row in the routes array.

use alloy::network::Ethereum;
use alloy::primitives::Address;
use alloy::providers::Provider;

use super::{classify_ism, parse_address, ISmExposing};
use crate::report::RouteReport;

#[allow(clippy::too_many_arguments)]
pub async fn scan_route<P>(
    id: &str,
    source_chain: u64,
    destination_chain: u64,
    source_contract: &str,
    destination_contract: &str,
    unsafe_demo: bool,
    known_noop_isms: &[Address],
    provider: P,
) -> RouteReport
where
    P: Provider<Ethereum> + Clone + 'static,
{
    let mut report = RouteReport {
        id: id.to_string(),
        source_chain,
        destination_chain,
        source_contract: source_contract.to_string(),
        destination_contract: destination_contract.to_string(),
        ism_address: None,
        ism_type: "Unknown".to_string(),
        multisig: None,
        unsafe_demo,
        unsafe_flags: Vec::new(),
        error: None,
    };

    let address = match parse_address(source_contract) {
        Ok(a) => a,
        Err(e) => {
            report.error = Some(e.to_string());
            return report;
        }
    };

    let warp = ISmExposing::new(address, provider);
    let ism_addr = match warp.interchainSecurityModule().call().await {
        Ok(a) => a,
        Err(e) => {
            // Many warp routes leave ISM unset → fall back to mailbox
            // default ISM. We surface that as a soft error rather than a
            // safety-positive.
            report.error = Some(format!("interchainSecurityModule: {e}"));
            return report;
        }
    };

    report.ism_address = Some(format!("{ism_addr:#x}"));
    let (ism_type, mut flags) = classify_ism(ism_addr, known_noop_isms);
    report.ism_type = ism_type;

    // Only suppress the warning when the route is explicitly tagged demo.
    if unsafe_demo {
        flags.clear();
    }
    report.unsafe_flags = flags;

    report
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloy::primitives::address;

    #[test]
    fn classify_returns_noop_when_address_matches() {
        let noop = address!("28834AA535F3130f0F60571Ac7a813195aE56eC6");
        let (ism_type, flags) = classify_ism(noop, &[noop]);
        assert_eq!(ism_type, "NoopIsm");
        assert_eq!(flags, vec!["NoopIsm-on-warp-route-unsafe"]);
    }

    #[test]
    fn classify_returns_unknown_when_address_does_not_match() {
        let unknown = address!("0000000000000000000000000000000000001234");
        let known_noop = address!("28834AA535F3130f0F60571Ac7a813195aE56eC6");
        let (ism_type, flags) = classify_ism(unknown, &[known_noop]);
        assert_eq!(ism_type, "Unknown");
        assert!(flags.is_empty());
    }
}
