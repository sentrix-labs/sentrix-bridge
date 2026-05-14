//! `GET /routes` and `GET /routes/:id` — list every route derived from
//! `deployments/*.json` and serve a single-route detail.

use crate::deployments::Route;
use crate::state::AppState;
use axum::extract::Path;
use axum::http::StatusCode;
use axum::{extract::State, routing::get, Json, Router};
use serde::Serialize;
use std::sync::Arc;

#[derive(Debug, Serialize)]
pub struct RoutesResponse {
    pub count: usize,
    pub routes: Vec<Route>,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/routes", get(list))
        .route("/routes/{id}", get(detail))
}

pub async fn list(State(state): State<Arc<AppState>>) -> Json<RoutesResponse> {
    let routes = state.deployments.routes.clone();
    Json(RoutesResponse {
        count: routes.len(),
        routes,
    })
}

pub async fn detail(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<Json<Route>, (StatusCode, Json<serde_json::Value>)> {
    match state.deployments.route_by_id(&id) {
        Some(r) => Ok(Json(r.clone())),
        None => Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({
                "error": "route_not_found",
                "id": id,
            })),
        )),
    }
}
