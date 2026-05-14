//! `GET /readiness` — production-readiness checklist as JSON.

use crate::readiness;
use crate::state::AppState;
use axum::{extract::State, routing::get, Json, Router};
use serde::Serialize;
use std::sync::Arc;

#[derive(Debug, Serialize)]
pub struct ReadinessResponse {
    pub items: Vec<readiness::ReadinessItem>,
    pub pass_count: usize,
    pub pending_count: usize,
    pub fail_count: usize,
    pub overall: &'static str,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/readiness", get(handler))
}

pub async fn handler(State(_state): State<Arc<AppState>>) -> Json<ReadinessResponse> {
    let items = readiness::checklist();
    let pass = items.iter().filter(|i| i.status == readiness::Status::Pass).count();
    let pending = items
        .iter()
        .filter(|i| i.status == readiness::Status::Pending)
        .count();
    let fail = items.iter().filter(|i| i.status == readiness::Status::Fail).count();
    let overall = if fail > 0 {
        "fail"
    } else if pending > 0 {
        "pending"
    } else {
        "pass"
    };

    Json(ReadinessResponse {
        items,
        pass_count: pass,
        pending_count: pending,
        fail_count: fail,
        overall,
    })
}
