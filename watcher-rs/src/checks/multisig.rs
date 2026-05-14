//! MultisigIsm validator-set + threshold inspection.
//!
//! Hyperlane's `IMultisigIsm.validatorsAndThreshold(bytes)` takes a message
//! body and returns the validator set plus threshold *for that message's
//! origin domain*. For a watcher we don't have a real message; we craft a
//! minimal Hyperlane v3 message header pointing at the origin domain we
//! want to query and pass that.
//!
//! v3 message layout (packed):
//!   uint8   version
//!   uint32  nonce
//!   uint32  originDomain
//!   bytes32 sender
//!   uint32  destinationDomain
//!   bytes32 recipient
//!   bytes   body
//!
//! We only need the header bytes — the validator-set logic in stock Hyperlane
//! MultisigIsm reads originDomain only.

use alloy::network::Ethereum;
use alloy::primitives::{Address, Bytes, B256};
use alloy::providers::Provider;
use anyhow::Result;

use super::IMultisigIsm;
use crate::report::MultisigInfo;

pub fn synth_message(origin_domain: u32, destination_domain: u32) -> Bytes {
    let mut buf = Vec::with_capacity(77);
    buf.push(3u8); // version
    buf.extend_from_slice(&0u32.to_be_bytes()); // nonce
    buf.extend_from_slice(&origin_domain.to_be_bytes());
    buf.extend_from_slice(B256::ZERO.as_slice()); // sender
    buf.extend_from_slice(&destination_domain.to_be_bytes());
    buf.extend_from_slice(B256::ZERO.as_slice()); // recipient
    // empty body
    Bytes::from(buf)
}

pub async fn fetch<P>(
    ism: Address,
    origin_domain: u32,
    destination_domain: u32,
    provider: P,
) -> Result<MultisigInfo>
where
    P: Provider<Ethereum> + Clone + 'static,
{
    let body = synth_message(origin_domain, destination_domain);
    let multisig = IMultisigIsm::new(ism, provider);
    let res = multisig.validatorsAndThreshold(body).call().await?;
    let validators = res._0;
    let threshold = res._1;
    Ok(MultisigInfo {
        validator_count: validators.len(),
        threshold,
        validators: validators.iter().map(|a| format!("{a:#x}")).collect(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn synth_message_has_canonical_layout() {
        let m = synth_message(7120, 11155111);
        // 1 + 4 + 4 + 32 + 4 + 32 = 77 bytes.
        assert_eq!(m.len(), 77);
        assert_eq!(m[0], 3); // version
        // origin domain at offset 5..9
        assert_eq!(&m[5..9], &7120u32.to_be_bytes());
        // destination domain at offset 41..45
        assert_eq!(&m[41..45], &11155111u32.to_be_bytes());
    }
}
