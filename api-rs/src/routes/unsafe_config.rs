//! `GET /unsafe-config` — every route currently flagged unsafe (NoopIsm or
//! similar). Empty array == no flagged routes (still 200).

use crate::deployments::Route;
use crate::state::AppState;
use axum::{extract::State, routing::get, Json, Router};
use serde::Serialize;
use std::sync::Arc;

#[derive(Debug, Serialize)]
pub struct UnsafeConfigResponse {
    pub count: usize,
    pub routes: Vec<Route>,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/unsafe-config", get(handler))
}

pub async fn handler(State(state): State<Arc<AppState>>) -> Json<UnsafeConfigResponse> {
    let routes: Vec<Route> = state
        .deployments
        .unsafe_routes()
        .into_iter()
        .cloned()
        .collect();
    Json(UnsafeConfigResponse {
        count: routes.len(),
        routes,
    })
}
