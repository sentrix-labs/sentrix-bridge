//! sentrix-bridge-api
//!
//! Minimal read-only HTTP API exposing the live state of the sentrix-bridge
//! Hyperlane v3 deployment. No private keys, no signing — every endpoint is
//! either a static read of `deployments/*.json` or an `eth_call` against a
//! public RPC.
//!
//! Endpoints (see `routes/` and the crate README for full curl examples):
//!
//! * `GET /health`            — process liveness + uptime
//! * `GET /status`            — top-level bridge state summary
//! * `GET /routes`            — all routes derived from `deployments/*.json`
//! * `GET /routes/:id`        — single route detail
//! * `GET /messages`          — recent dispatched/processed messages (TODO)
//! * `GET /messages/:id`      — single message detail (TODO)
//! * `GET /unsafe-config`     — every route currently flagged unsafe
//! * `GET /fresh-user-flow`   — last verified WSRX wrap → bridge → mint run
//! * `GET /readiness`         — production-readiness checklist (Phase 4 gate)
//!
//! Same crate-isolation pattern as `watcher-rs/` — no workspace, builds from
//! its own `Cargo.toml`.

pub mod config;
pub mod deployments;
pub mod readiness;
pub mod routes;
pub mod state;

pub use config::{Network, RuntimeConfig};
pub use state::AppState;

use axum::Router;
use std::sync::Arc;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;

/// Build the full axum router. Exposed so integration tests can call it
/// directly via `tower::ServiceExt::oneshot` without binding a real socket.
pub fn router(state: Arc<AppState>) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        .merge(routes::health::router())
        .merge(routes::status::router())
        .merge(routes::routes_endpoint::router())
        .merge(routes::messages::router())
        .merge(routes::unsafe_config::router())
        .merge(routes::fresh_user_flow::router())
        .merge(routes::readiness::router())
        .with_state(state)
        .layer(cors)
        .layer(TraceLayer::new_for_http())
}
