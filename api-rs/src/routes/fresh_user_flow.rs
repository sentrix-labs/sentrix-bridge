//! `GET /fresh-user-flow` — current status of the WSRX deposit -> wrap ->
//! bridge -> mint flow on testnet. Reads from a static config file the
//! operator updates after each successful run. Missing file is fine — return
//! `{ "status": "unknown", "last_verified": null }`.

use crate::state::AppState;
use axum::{extract::State, routing::get, Json, Router};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::{fs, path::Path};

#[derive(Debug, Serialize, Deserialize)]
pub struct FreshUserFlowResponse {
    pub status: String,
    pub last_verified: Option<String>,
    /// Optional pass-through fields the operator may add to the JSON file
    /// (tx hashes, recipient, amount). Kept as raw JSON so we don't have to
    /// chase schema changes.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub detail: Option<serde_json::Value>,
}

impl FreshUserFlowResponse {
    pub fn unknown() -> Self {
        Self {
            status: "unknown".into(),
            last_verified: None,
            detail: None,
        }
    }
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/fresh-user-flow", get(handler))
}

pub async fn handler(State(state): State<Arc<AppState>>) -> Json<FreshUserFlowResponse> {
    let path = Path::new(&state.config.fresh_user_flow_path);
    Json(read_or_unknown(path))
}

fn read_or_unknown(path: &Path) -> FreshUserFlowResponse {
    if !path.exists() {
        return FreshUserFlowResponse::unknown();
    }
    match fs::read(path) {
        Ok(bytes) => match serde_json::from_slice::<FreshUserFlowResponse>(&bytes) {
            Ok(r) => r,
            Err(e) => {
                tracing::warn!(error = %e, "fresh-user-flow.json malformed; returning unknown");
                FreshUserFlowResponse::unknown()
            }
        },
        Err(e) => {
            tracing::warn!(error = %e, "fresh-user-flow.json read failed; returning unknown");
            FreshUserFlowResponse::unknown()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn missing_file_is_unknown() {
        let r = read_or_unknown(Path::new("/nonexistent/path/fresh.json"));
        assert_eq!(r.status, "unknown");
        assert!(r.last_verified.is_none());
    }

    #[test]
    fn malformed_file_is_unknown() {
        let dir = tempdir();
        let p = dir.join("bad.json");
        std::fs::File::create(&p).unwrap().write_all(b"{not json").unwrap();
        let r = read_or_unknown(&p);
        assert_eq!(r.status, "unknown");
    }

    fn tempdir() -> std::path::PathBuf {
        let mut p = std::env::temp_dir();
        p.push(format!("api-rs-fresh-{}", std::process::id()));
        std::fs::create_dir_all(&p).unwrap();
        p
    }
}
