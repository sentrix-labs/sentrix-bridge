//! Parse `deployments/hyperlane-*.json` into a normalised route list.
//!
//! The on-disk JSON is operator-friendly (free-form notes, deploy txs,
//! per-network sections) so we keep the raw `serde_json::Value` around for
//! pass-through endpoints, and project a small typed `Route` view on top
//! for `/routes` and `/unsafe-config` which need a uniform shape.

use anyhow::{Context, Result};
use serde::Serialize;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize)]
pub struct Route {
    /// Stable slug used in `/routes/:id`.
    pub id: String,
    /// Human-readable label.
    pub name: String,
    /// e.g. "warp" or "message".
    pub kind: &'static str,
    /// Origin chain id (Hyperlane domain == chain id in v3).
    pub origin_chain_id: u64,
    pub origin_name: String,
    pub destination_chain_id: u64,
    pub destination_name: String,
    /// Source-side token contract (collateral or native wrapper). None for
    /// pure message-passing routes.
    pub source_token: Option<String>,
    /// Destination-side token contract (synthetic mint). None for pure
    /// message-passing routes.
    pub destination_token: Option<String>,
    /// ISM type as advertised by the deployment JSON note ("NoopIsm",
    /// "MultisigIsm", "AggregationIsm", or "unknown").
    pub ism_type_origin: String,
    pub ism_type_destination: String,
    /// True if any side uses NoopIsm or is otherwise flagged unsafe.
    pub unsafe_flag: bool,
    /// Free-form reasons populated when `unsafe_flag` is true.
    pub unsafe_reasons: Vec<String>,
}

#[derive(Debug)]
pub struct Deployments {
    pub routes: Vec<Route>,
    /// Raw JSON keyed by file-stem ("hyperlane-sepolia",
    /// "hyperlane-testnet", "hyperlane-warp-route", "testnet").
    pub raw: BTreeMap<String, serde_json::Value>,
}

impl Deployments {
    /// Load every `*.json` under `dir`. Missing dir = empty deployment set
    /// (don't crash the API — the operator may have moved the dir).
    pub fn load(dir: &Path) -> Result<Self> {
        let mut raw: BTreeMap<String, serde_json::Value> = BTreeMap::new();
        if dir.exists() {
            for entry in fs::read_dir(dir).with_context(|| format!("reading {:?}", dir))? {
                let entry = entry?;
                let path = entry.path();
                if path.extension().and_then(|s| s.to_str()) != Some("json") {
                    continue;
                }
                let stem = path
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("")
                    .to_string();
                let bytes = fs::read(&path).with_context(|| format!("reading {:?}", path))?;
                let val: serde_json::Value = serde_json::from_slice(&bytes)
                    .with_context(|| format!("parsing {:?}", path))?;
                raw.insert(stem, val);
            }
        }

        let routes = derive_routes(&raw);

        Ok(Self { routes, raw })
    }

    /// Test helper — build a Deployments from in-memory raw JSON without
    /// touching the filesystem.
    pub fn from_raw(raw: BTreeMap<String, serde_json::Value>) -> Self {
        let routes = derive_routes(&raw);
        Self { routes, raw }
    }

    pub fn route_by_id(&self, id: &str) -> Option<&Route> {
        self.routes.iter().find(|r| r.id == id)
    }

    pub fn unsafe_routes(&self) -> Vec<&Route> {
        self.routes.iter().filter(|r| r.unsafe_flag).collect()
    }
}

/// Best-effort path to the deployments dir relative to CWD.
pub fn default_dir() -> PathBuf {
    PathBuf::from("deployments")
}

fn derive_routes(raw: &BTreeMap<String, serde_json::Value>) -> Vec<Route> {
    let mut out = Vec::new();

    // 1. Plain Hyperlane message route Sentrix Testnet (7120) -> Sepolia
    //    (11155111). Both sides on NoopIsm per `hyperlane-sepolia.json`.
    if let (Some(sep), Some(testnet)) = (raw.get("hyperlane-sepolia"), raw.get("hyperlane-testnet"))
    {
        let sep_ism = ism_label(sep, "ourDeployments.NoopIsm").unwrap_or("unknown".into());
        let test_ism = ism_label(testnet, "contracts.NoopIsm").unwrap_or("unknown".into());

        let mut reasons = Vec::new();
        if sep_ism.contains("Noop") {
            reasons.push("Sepolia side uses NoopIsm — accepts any message".into());
        }
        if test_ism.contains("Noop") {
            reasons.push("Sentrix Testnet side uses NoopIsm — accepts any message".into());
        }

        out.push(Route {
            id: "msg-sentrix-testnet-sepolia".into(),
            name: "Sentrix Testnet -> Sepolia (message-passing demo)".into(),
            kind: "message",
            origin_chain_id: 7120,
            origin_name: "sentrix-testnet".into(),
            destination_chain_id: 11155111,
            destination_name: "sepolia".into(),
            source_token: None,
            destination_token: None,
            ism_type_origin: test_ism,
            ism_type_destination: sep_ism,
            unsafe_flag: !reasons.is_empty(),
            unsafe_reasons: reasons,
        });
    }

    // 2. Warp route — wSRX. Sentrix Testnet HypERC20Collateral wrapping the
    //    canonical WSRX9 -> Sepolia HypERC20.
    if let Some(warp) = raw.get("hyperlane-warp-route") {
        let source_token = warp
            .pointer("/sentrixTestnet/HypNative")
            .and_then(|v| v.as_str())
            .map(String::from)
            .or_else(|| {
                warp.pointer("/workingPath/components/HypERC20Collateral_sentrix")
                    .and_then(|v| v.as_str())
                    .map(String::from)
            });
        let destination_token = warp
            .pointer("/sepolia/HypERC20_wSRX")
            .and_then(|v| v.as_str())
            .map(String::from);

        let test_ism = warp
            .pointer("/sentrixTestnet/config/ism")
            .and_then(|v| v.as_str())
            .map(String::from)
            .unwrap_or_else(|| "unknown".into());
        let sep_ism = warp
            .pointer("/sepolia/config/ism")
            .and_then(|v| v.as_str())
            .map(String::from)
            .unwrap_or_else(|| "unknown".into());

        let mut reasons = Vec::new();
        if test_ism.contains("Noop") {
            reasons.push("Sentrix Testnet side uses NoopIsm".into());
        }
        if sep_ism.contains("Noop") {
            reasons.push("Sepolia side uses NoopIsm".into());
        }
        // Spec literal: warp-route status is "PROTOCOL-PROVEN-BUT-USER-ENTRY-BROKEN"
        // pre-2026-05-13. After #580 closed, fresh-user flow works on the
        // wSRX wrap path. Operator updates fresh-user-flow.json after each
        // successful run.
        if let Some(status) = warp.get("status").and_then(|v| v.as_str()) {
            if status.contains("BROKEN") {
                reasons.push(format!("warp route status: {}", status));
            }
        }

        out.push(Route {
            id: "warp-wsrx-sepolia".into(),
            name: "wSRX warp route Sentrix Testnet <-> Sepolia".into(),
            kind: "warp",
            origin_chain_id: 7120,
            origin_name: "sentrix-testnet".into(),
            destination_chain_id: 11155111,
            destination_name: "sepolia".into(),
            source_token,
            destination_token,
            ism_type_origin: simplify_ism_label(&test_ism),
            ism_type_destination: simplify_ism_label(&sep_ism),
            unsafe_flag: !reasons.is_empty(),
            unsafe_reasons: reasons,
        });
    }

    out
}

/// Pull an ISM label out of a deployment JSON given a dotted path
/// ("ourDeployments.NoopIsm"). Returns the contract type (e.g. "NoopIsm") if
/// found.
fn ism_label(val: &serde_json::Value, dotted: &str) -> Option<String> {
    let pointer = format!("/{}", dotted.replace('.', "/"));
    val.pointer(&pointer).and_then(|node| {
        // Either a string address (treat key name as type) or an object with
        // an `address` + `note`. We just want the type label.
        if node.is_object() {
            // Last segment of the dotted path is the contract type.
            dotted.split('.').next_back().map(String::from)
        } else if node.is_string() {
            dotted.split('.').next_back().map(String::from)
        } else {
            None
        }
    })
}

/// `0x28...e56eC6 (NoopIsm)` -> `NoopIsm`. Address-only -> `unknown`.
fn simplify_ism_label(raw: &str) -> String {
    if let Some(start) = raw.find('(') {
        if let Some(end) = raw.find(')') {
            if start < end {
                return raw[start + 1..end].to_string();
            }
        }
    }
    if raw.starts_with("0x") {
        "unknown".into()
    } else {
        raw.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> BTreeMap<String, serde_json::Value> {
        let mut m = BTreeMap::new();
        m.insert(
            "hyperlane-sepolia".into(),
            serde_json::json!({
                "ourDeployments": {
                    "NoopIsm": { "address": "0xabc", "note": "permissive" }
                }
            }),
        );
        m.insert(
            "hyperlane-testnet".into(),
            serde_json::json!({
                "contracts": {
                    "NoopIsm": { "address": "0xdef", "note": "permissive" }
                }
            }),
        );
        m.insert(
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
        m
    }

    #[test]
    fn derives_two_routes_from_fixture() {
        let d = Deployments::from_raw(fixture());
        assert_eq!(d.routes.len(), 2);
        let warp = d.route_by_id("warp-wsrx-sepolia").expect("warp present");
        assert_eq!(warp.kind, "warp");
        assert!(warp.unsafe_flag, "noop ism flagged");
        assert_eq!(warp.ism_type_destination, "NoopIsm");
    }

    #[test]
    fn unsafe_routes_lists_both() {
        let d = Deployments::from_raw(fixture());
        assert_eq!(d.unsafe_routes().len(), 2);
    }
}
