//! Production-readiness checklist. Mirrors the `Phase 4 — Mainnet` gate list
//! in `docs/multichain-roadmap.md` so the API and the doc don't drift.
//!
//! Each item: `name`, `status` (`pass` | `fail` | `pending`), `description`.

use serde::Serialize;

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Pass,
    Fail,
    Pending,
}

#[derive(Debug, Clone, Serialize)]
pub struct ReadinessItem {
    pub name: &'static str,
    pub status: Status,
    pub description: &'static str,
}

/// The checklist literal. Items map 1:1 to the Phase 4 gate in the roadmap;
/// when an item closes, flip its status here AND tick the box in the doc.
pub fn checklist() -> Vec<ReadinessItem> {
    vec![
        ReadinessItem {
            name: "sentrix#580 closed",
            status: Status::Pass,
            description: "EVM value-transfer + gas-fix forks activated on testnet h=3,787,000 and mainnet h=1,748,900 (binary v2.2.11). Closed 2026-05-13.",
        },
        ReadinessItem {
            name: "Phase 2 production ISM live on testnet >= 7 days",
            status: Status::Pending,
            description: "Replace NoopIsm with MultisigIsm on both sides of the Sepolia route + run validator + relayer agents 24/7. See docs/multisigism-setup.md.",
        },
        ReadinessItem {
            name: "External audit pass",
            status: Status::Pending,
            description: "Audit firm TBD. Code4rena contest is a candidate. Scope: bridge contracts (Mailbox + ISM + warp-route).",
        },
        ReadinessItem {
            name: "Public mainnet faucet for SRX -> ETH gas bootstrap",
            status: Status::Pending,
            description: "So users have ETH on the foreign side to receive minted wSRX. Open question: who funds and rate-limits.",
        },
        ReadinessItem {
            name: "LayerZero Labs assigns real EID",
            status: Status::Pending,
            description: "Currently EndpointV2 uses placeholder eid=40998. See sentrix-bridge#2.",
        },
        ReadinessItem {
            name: "Insurance / treasury policy for bridge custody",
            status: Status::Pending,
            description: "Operator's call. Options: self-insure, Nexus Mutual cover, capped TVL with circuit-breaker.",
        },
        ReadinessItem {
            name: "Hyperlane validator + relayer agents running 24/7",
            status: Status::Pending,
            description: "Currently every relay is manual (`Mailbox.process` from operator wallet). Production swap is gated on the agent runbook.",
        },
        ReadinessItem {
            name: "Reverse-direction (Sepolia -> Sentrix) verified",
            status: Status::Pending,
            description: "Phase 0 demo is one-way. Reciprocal config + a successful return trip needed before mainnet.",
        },
    ]
}
