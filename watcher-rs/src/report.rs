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
    pub stuck_messages: Vec<StuckMessage>,
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

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WsrxInvariant {
    pub wsrx_total_supply_sentrix: String,
    pub wsrx_locked_in_collateral: String,
    pub hyperc20_total_supply_sepolia: String,
    /// `wsrx_locked_in_collateral - hyperc20_total_supply_sepolia`. Stored as
    /// a signed decimal string so JS consumers don't truncate u256.
    pub drift_wei: String,
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
