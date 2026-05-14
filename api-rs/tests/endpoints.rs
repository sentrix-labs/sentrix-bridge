//! Endpoint shape tests. Dispatch HTTP requests directly against the axum
//! `Router` via `tower::ServiceExt::oneshot` — no real network, no real RPC.
//!
//! Covers /health, /status, /routes, /routes/:id, /unsafe-config,
//! /fresh-user-flow, /readiness, and both /messages variants.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use sentrix_bridge_api::{
    config::{Network, RuntimeConfig},
    deployments::Deployments,
    router, AppState,
};
use serde_json::Value;
use std::collections::BTreeMap;
use std::sync::Arc;
use tower::ServiceExt;

fn fixture_state() -> Arc<AppState> {
    let mut raw: BTreeMap<String, Value> = BTreeMap::new();
    raw.insert(
        "hyperlane-sepolia".into(),
        serde_json::json!({
            "ourDeployments": { "NoopIsm": { "address": "0xabc" } }
        }),
    );
    raw.insert(
        "hyperlane-testnet".into(),
        serde_json::json!({
            "contracts": { "NoopIsm": { "address": "0xdef" } }
        }),
    );
    raw.insert(
        "hyperlane-warp-route".into(),
        serde_json::json!({
            "status": "PROTOCOL-PROVEN-BUT-USER-ENTRY-BROKEN",
            "sentrixTestnet": {
                "HypNative": "0xea0bC1f6141E0B0604B9bE19E260338973Fd6dD7",
                "config": { "ism": "0x28834A (NoopIsm)" }
            },
            "sepolia": {
                "HypERC20_wSRX": "0xC4BDE56bCAadfDbD6fBad685b65628f05994e5a8",
                "config": { "ism": "0x1b11f1 (NoopIsm)" }
            }
        }),
    );

    let config = RuntimeConfig {
        network: Network::Testnet,
        sentrix_rpc: "https://testnet-rpc.sentrixchain.com".into(),
        sepolia_rpc: "https://ethereum-sepolia.publicnode.com".into(),
        deployments_dir: "deployments".into(),
        fresh_user_flow_path: "/nonexistent/path/fresh.json".into(),
    };
    let deployments = Deployments::from_raw(raw);
    Arc::new(AppState::new(config, deployments))
}

async fn body_json(resp: axum::response::Response) -> Value {
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).expect("response body is JSON")
}

#[tokio::test]
async fn get_health_returns_ok_and_uptime() {
    let app = router(fixture_state());
    let resp = app
        .oneshot(Request::builder().uri("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    assert_eq!(json["status"], "ok");
    assert!(json["uptime_seconds"].is_u64());
}

#[tokio::test]
async fn get_status_returns_summary() {
    let app = router(fixture_state());
    let resp = app
        .oneshot(Request::builder().uri("/status").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    assert_eq!(json["network"], "testnet");
    assert_eq!(json["route_count"], 2);
    assert_eq!(json["unsafe_route_count"], 2);
    assert!(json["routes"].is_array());
    assert!(json["rpc_health"]["status"].is_string());
    assert!(json["wsrx_invariant"]["status"].is_string());
    assert!(json["stuck_message_count"]["status"].is_string());
}

#[tokio::test]
async fn get_routes_lists_all() {
    let app = router(fixture_state());
    let resp = app
        .oneshot(Request::builder().uri("/routes").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    assert_eq!(json["count"], 2);
    let ids: Vec<&str> = json["routes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["id"].as_str().unwrap())
        .collect();
    assert!(ids.contains(&"warp-wsrx-sepolia"));
    assert!(ids.contains(&"msg-sentrix-testnet-sepolia"));
}

#[tokio::test]
async fn get_route_detail_hits_and_misses() {
    let app = router(fixture_state());
    let hit = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/routes/warp-wsrx-sepolia")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(hit.status(), StatusCode::OK);
    let json = body_json(hit).await;
    assert_eq!(json["id"], "warp-wsrx-sepolia");
    assert_eq!(json["unsafe_flag"], true);

    let miss = app
        .oneshot(
            Request::builder()
                .uri("/routes/does-not-exist")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(miss.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn get_unsafe_config_lists_flagged_routes() {
    let app = router(fixture_state());
    let resp = app
        .oneshot(
            Request::builder()
                .uri("/unsafe-config")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    assert_eq!(json["count"], 2);
}

#[tokio::test]
async fn get_fresh_user_flow_unknown_when_file_missing() {
    let app = router(fixture_state());
    let resp = app
        .oneshot(
            Request::builder()
                .uri("/fresh-user-flow")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    assert_eq!(json["status"], "unknown");
    assert!(json["last_verified"].is_null());
}

#[tokio::test]
async fn get_readiness_returns_checklist() {
    let app = router(fixture_state());
    let resp = app
        .oneshot(
            Request::builder()
                .uri("/readiness")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    let items = json["items"].as_array().expect("items is array");
    assert!(items.len() >= 7, "checklist has >= 7 items");
    for item in items {
        assert!(item["name"].is_string());
        assert!(item["status"].is_string());
        assert!(item["description"].is_string());
    }
    assert!(json["overall"].is_string());
}

#[tokio::test]
async fn get_messages_list_returns_pending_envelope() {
    let app = router(fixture_state());
    let resp = app
        .oneshot(
            Request::builder()
                .uri("/messages?since=100&limit=10")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    assert_eq!(json["status"], "pending_implementation");
    assert_eq!(json["limit"], 10);
}

#[tokio::test]
async fn get_message_detail_returns_pending_envelope() {
    let app = router(fixture_state());
    let resp = app
        .oneshot(
            Request::builder()
                .uri("/messages/0xdeadbeef")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    assert_eq!(json["status"], "pending_implementation");
    assert_eq!(json["id"], "0xdeadbeef");
}
