//! `GET /status` — top-level bridge state summary.
//!
//! Returns counts and a brief per-route summary; for full route detail clients
//! should follow up to `/routes` or `/routes/:id`. RPC + WSRX-invariant +
//! stuck-message slots are reserved as TODO; an operator-readable summary is
//! more useful day-1 than a half-implemented invariant check.

use crate::deployments::Route;
use crate::state::AppState;
use axum::{extract::State, routing::get, Json, Router};
use serde::Serialize;
use std::sync::Arc;

#[derive(Debug, Serialize)]
pub struct StatusResponse {
    pub network: String,
    pub uptime_seconds: u64,
    /// RPC endpoint summaries. Raw URLs are kept server-side only — they may
    /// carry Infura/Alchemy keys when operators override the public defaults.
    /// Public response only reports whether the URL is configured + (later)
    /// whether the probe responded. Full URL stays in tracing logs.
    pub sentrix_rpc: RpcEndpoint,
    pub sepolia_rpc: RpcEndpoint,
    pub route_count: usize,
    pub unsafe_route_count: usize,
    pub routes: Vec<RouteSummary>,
    pub rpc_health: RpcHealth,
    pub wsrx_invariant: WsrxInvariant,
    pub stuck_message_count: StuckMessages,
}

#[derive(Debug, Serialize)]
pub struct RpcEndpoint {
    /// True iff a non-empty URL is set (env override or built-in default).
    pub configured: bool,
    /// Live-probe result. `None` until the alloy probe lands (see TODO below).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub responding: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct RouteSummary {
    pub id: String,
    pub kind: &'static str,
    pub origin_chain_id: u64,
    pub destination_chain_id: u64,
    pub ism_type_origin: String,
    pub ism_type_destination: String,
    pub unsafe_flag: bool,
}

#[derive(Debug, Serialize)]
pub struct RpcHealth {
    pub status: &'static str,
    pub note: &'static str,
}

#[derive(Debug, Serialize)]
pub struct WsrxInvariant {
    pub status: &'static str,
    pub note: &'static str,
}

#[derive(Debug, Serialize)]
pub struct StuckMessages {
    pub status: &'static str,
    pub count: u64,
    pub note: &'static str,
}

impl From<&Route> for RouteSummary {
    fn from(r: &Route) -> Self {
        Self {
            id: r.id.clone(),
            kind: r.kind,
            origin_chain_id: r.origin_chain_id,
            destination_chain_id: r.destination_chain_id,
            ism_type_origin: r.ism_type_origin.clone(),
            ism_type_destination: r.ism_type_destination.clone(),
            unsafe_flag: r.unsafe_flag,
        }
    }
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/status", get(handler))
}

pub async fn handler(State(state): State<Arc<AppState>>) -> Json<StatusResponse> {
    let routes = &state.deployments.routes;
    let unsafe_count = routes.iter().filter(|r| r.unsafe_flag).count();

    // Operator-private RPC URLs (may include Infura/Alchemy keys) only ever
    // appear in tracing logs, never in the public response.
    tracing::debug!(
        sentrix_rpc = %state.config.sentrix_rpc,
        sepolia_rpc = %state.config.sepolia_rpc,
        "status request — RPC endpoints"
    );

    Json(StatusResponse {
        network: state.config.network.as_str().to_string(),
        uptime_seconds: state.uptime_seconds(),
        sentrix_rpc: RpcEndpoint {
            configured: !state.config.sentrix_rpc.is_empty(),
            responding: None,
        },
        sepolia_rpc: RpcEndpoint {
            configured: !state.config.sepolia_rpc.is_empty(),
            responding: None,
        },
        route_count: routes.len(),
        unsafe_route_count: unsafe_count,
        routes: routes.iter().map(RouteSummary::from).collect(),
        // TODO(api-rs): wire alloy provider here for live eth_blockNumber +
        // eth_chainId on each side. Watcher-rs already has this scaffolded
        // behind config — once that lands, share the implementation.
        rpc_health: RpcHealth {
            status: "unknown",
            note: "live RPC probe not wired yet — see TODO in routes/status.rs",
        },
        // TODO(api-rs): WSRX.totalSupply() (sentrix) vs HypERC20.totalSupply()
        // (sepolia) cross-check. Same TODO as watcher-rs.
        wsrx_invariant: WsrxInvariant {
            status: "unknown",
            note: "wSRX 1:1 supply invariant not wired yet — see TODO in routes/status.rs",
        },
        // TODO(api-rs): scan Mailbox Dispatch events without matching
        // ProcessId on the destination side for the last N blocks.
        stuck_message_count: StuckMessages {
            status: "unknown",
            count: 0,
            note: "stuck-message scan not wired yet — see TODO in routes/status.rs",
        },
    })
}
