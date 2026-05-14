//! `GET /health` — liveness + uptime. Always 200 if the process is up.

use crate::state::AppState;
use axum::{extract::State, routing::get, Json, Router};
use serde::Serialize;
use std::sync::Arc;

#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: &'static str,
    pub uptime_seconds: u64,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/health", get(handler))
}

pub async fn handler(State(state): State<Arc<AppState>>) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        uptime_seconds: state.uptime_seconds(),
    })
}
