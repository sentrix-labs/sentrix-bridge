//! `GET /messages` and `GET /messages/:id` — Hyperlane Mailbox messages.
//!
//! Both endpoints are TODOs in this scaffold. They return a 200 with a
//! `pending_implementation` envelope so callers can wire UI now and the API
//! shape stays stable when the alloy event scan lands.
//!
//! The full implementation needs:
//!   * subscribe / `eth_getLogs` for Mailbox `Dispatch` and `ProcessId` events
//!     on both Sentrix Mailbox and the destination Mailbox
//!   * pagination cursor — likely (chain_id, block, log_index)
//!   * per-message status: `dispatched` -> `processing` -> `delivered`
//!
//! Watcher-rs has the Mailbox ABI scaffolded; share that module once it lands.

use crate::state::AppState;
use axum::extract::{Path, Query, State};
use axum::routing::get;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Debug, Deserialize)]
pub struct MessagesQuery {
    /// Block number to start from (inclusive). Defaults to "tip - 5000".
    #[serde(default)]
    pub since: Option<u64>,
    /// Page size cap. Default 50, max 200.
    #[serde(default)]
    pub limit: Option<u32>,
}

#[derive(Debug, Serialize)]
pub struct MessagesResponse {
    pub status: &'static str,
    pub since: Option<u64>,
    pub limit: u32,
    pub messages: Vec<MessageStub>,
    pub note: &'static str,
}

#[derive(Debug, Serialize)]
pub struct MessageStub {}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/messages", get(list))
        .route("/messages/{id}", get(detail))
}

pub async fn list(
    State(_state): State<Arc<AppState>>,
    Query(q): Query<MessagesQuery>,
) -> Json<MessagesResponse> {
    // Clamp on both ends — `limit=0` would silently return an empty page and
    // make callers think they hit the end of history.
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    Json(MessagesResponse {
        status: "pending_implementation",
        since: q.since,
        limit,
        messages: Vec::new(),
        note: "live Mailbox event scan not wired yet — see TODO in routes/messages.rs",
    })
}

#[derive(Debug, Serialize)]
pub struct MessageDetailResponse {
    pub status: &'static str,
    pub id: String,
    pub note: &'static str,
}

pub async fn detail(
    State(_state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Json<MessageDetailResponse> {
    Json(MessageDetailResponse {
        status: "pending_implementation",
        id,
        note: "single-message lookup not wired yet — see TODO in routes/messages.rs",
    })
}
