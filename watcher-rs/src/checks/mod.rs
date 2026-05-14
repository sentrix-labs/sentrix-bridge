//! Check modules. Every entry point is `async fn` over an alloy provider
//! handle and a `RuntimeConfig`; nothing reaches out to disk or the network
//! before being explicitly invoked.

pub mod balance;
pub mod multisig;
pub mod noopism;
pub mod rpc;
pub mod stuck;

use alloy::network::Ethereum;
use alloy::primitives::Address;
use alloy::providers::{DynProvider, Provider, ProviderBuilder};
use alloy::sol;
use anyhow::{anyhow, Context, Result};
use serde::Deserialize;
use std::path::Path;
use std::str::FromStr;

use crate::config::RuntimeConfig;
use crate::report::{MailboxReport, Report, RouteReport};

// Build a minimal HTTP provider. We use `DynProvider` so the same handle
// type flows through every check helper without leaking an enormous generic
// chain.
pub fn http_provider(rpc_url: &str) -> Result<DynProvider<Ethereum>> {
    let url = rpc_url
        .parse()
        .with_context(|| format!("invalid RPC URL: {rpc_url}"))?;
    let provider = ProviderBuilder::new().connect_http(url);
    Ok(provider.erased())
}

// ---- Hyperlane / warp ABI fragments. We only need the read-only ones. ----

sol! {
    #[sol(rpc)]
    interface IMailbox {
        function localDomain() external view returns (uint32);
        function defaultIsm() external view returns (address);
        function defaultHook() external view returns (address);
    }

    #[sol(rpc)]
    interface ISmExposing {
        function interchainSecurityModule() external view returns (address);
    }

    #[sol(rpc)]
    interface IMultisigIsm {
        function validatorsAndThreshold(bytes calldata _message) external view returns (address[] memory, uint8);
    }

    #[sol(rpc)]
    interface IErc20Lite {
        function totalSupply() external view returns (uint256);
        function balanceOf(address account) external view returns (uint256);
    }

    #[sol(rpc)]
    interface IModuleType {
        function moduleType() external view returns (uint8);
    }
}

/// Minimal struct shapes for `deployments/*.json`. We deserialize only the
/// fields we touch so the JSON can grow without breaking the watcher.
#[derive(Debug, Deserialize)]
pub struct HyperlaneTestnetFile {
    #[serde(rename = "chainId")]
    pub chain_id: u64,
    pub contracts: TestnetContracts,
}

#[derive(Debug, Deserialize)]
pub struct TestnetContracts {
    #[serde(rename = "Mailbox")]
    pub mailbox: ContractEntry,
    #[serde(rename = "NoopIsm")]
    pub noop_ism: ContractEntry,
}

#[derive(Debug, Deserialize)]
pub struct HyperlaneSepoliaFile {
    #[serde(rename = "chainId")]
    pub chain_id: u64,
    #[serde(rename = "preDeployedHyperlane")]
    pub pre_deployed: SepoliaPreDeployed,
    #[serde(rename = "ourDeployments")]
    pub our_deployments: SepoliaOurDeployments,
}

#[derive(Debug, Deserialize)]
pub struct SepoliaPreDeployed {
    #[serde(rename = "Mailbox")]
    pub mailbox: String,
}

#[derive(Debug, Deserialize)]
pub struct SepoliaOurDeployments {
    #[serde(rename = "NoopIsm")]
    pub noop_ism: ContractEntry,
}

#[derive(Debug, Deserialize)]
pub struct ContractEntry {
    pub address: String,
}

#[derive(Debug, Deserialize)]
pub struct WarpRouteFile {
    #[serde(rename = "workingPath")]
    pub working_path: WorkingPath,
    #[serde(rename = "sentrixTestnet")]
    pub sentrix_testnet: WarpSide,
    pub sepolia: WarpSide,
}

#[derive(Debug, Deserialize)]
pub struct WorkingPath {
    pub components: WarpComponents,
}

#[derive(Debug, Deserialize)]
pub struct WarpComponents {
    #[serde(rename = "WSRX_sentrix")]
    pub wsrx_sentrix: String,
    #[serde(rename = "HypERC20Collateral_sentrix")]
    pub hyperc20_collateral_sentrix: String,
    #[serde(rename = "HypERC20_wSRX_sepolia")]
    pub hyperc20_sepolia: String,
}

#[derive(Debug, Deserialize)]
pub struct WarpSide {
    #[serde(rename = "chainId")]
    pub chain_id: u64,
    /// Optional — present on testnet, absent on Sepolia (HypERC20 lives in
    /// `workingPath.components` instead). We tolerate either shape.
    #[serde(rename = "HypNative")]
    pub hyp_native: Option<String>,
    /// Optional opt-in: when `true`, suppress the NoopIsm warning for this
    /// route. Currently nothing in deployments JSON sets this; documented
    /// here so operators have a knob.
    #[serde(default, rename = "unsafeDemo")]
    pub unsafe_demo: bool,
    /// Per-side ISM type from JSON config (`ism: "0x... (NoopIsm)"`). We
    /// re-derive on-chain in `checks::noopism`; this is just a hint.
    #[serde(default)]
    pub config: Option<serde_json::Value>,
}

pub fn parse_address(s: &str) -> Result<Address> {
    Address::from_str(s.trim()).map_err(|e| anyhow!("invalid address {s:?}: {e}"))
}

pub fn load_hyperlane_testnet(path: &Path) -> Result<HyperlaneTestnetFile> {
    let raw = std::fs::read_to_string(path)
        .with_context(|| format!("read {}", path.display()))?;
    serde_json::from_str(&raw).with_context(|| format!("parse {}", path.display()))
}

pub fn load_hyperlane_sepolia(path: &Path) -> Result<HyperlaneSepoliaFile> {
    let raw = std::fs::read_to_string(path)
        .with_context(|| format!("read {}", path.display()))?;
    serde_json::from_str(&raw).with_context(|| format!("parse {}", path.display()))
}

pub fn load_warp_route(path: &Path) -> Result<WarpRouteFile> {
    let raw = std::fs::read_to_string(path)
        .with_context(|| format!("read {}", path.display()))?;
    serde_json::from_str(&raw).with_context(|| format!("parse {}", path.display()))
}

/// Read `localDomain` / `defaultIsm` / `defaultHook` from a Mailbox. Returns
/// the populated MailboxReport, never panics — RPC failures land in
/// `report.error`.
pub async fn inspect_mailbox<P>(
    label: &str,
    addr: &str,
    expected_chain_id: u64,
    provider: P,
) -> MailboxReport
where
    P: Provider<Ethereum> + Clone + 'static,
{
    let mut report = MailboxReport {
        label: label.to_string(),
        address: addr.to_string(),
        chain_id: expected_chain_id,
        local_domain: None,
        default_ism: None,
        default_hook: None,
        local_domain_matches: None,
        error: None,
    };

    let address = match parse_address(addr) {
        Ok(a) => a,
        Err(e) => {
            report.error = Some(e.to_string());
            return report;
        }
    };

    let mailbox = IMailbox::new(address, provider);

    match mailbox.localDomain().call().await {
        Ok(domain) => {
            report.local_domain = Some(domain as u64);
            report.local_domain_matches = Some(domain as u64 == expected_chain_id);
        }
        Err(e) => report.error = Some(format!("localDomain: {e}")),
    }
    if let Ok(addr) = mailbox.defaultIsm().call().await {
        report.default_ism = Some(format!("{addr:#x}"));
    }
    if let Ok(addr) = mailbox.defaultHook().call().await {
        report.default_hook = Some(format!("{addr:#x}"));
    }

    report
}

/// Tag computed from the resolved-on-chain ISM address. Centralized so
/// every check uses the same names — `unsafe_flags` strings are part of the
/// JSON contract.
pub fn classify_ism(actual: Address, known_noop_isms: &[Address]) -> (String, Vec<String>) {
    if known_noop_isms.iter().any(|a| *a == actual) {
        (
            "NoopIsm".to_string(),
            vec!["NoopIsm-on-warp-route-unsafe".to_string()],
        )
    } else {
        // Fall back to the raw module-type byte read elsewhere; here we
        // just say "unknown" so the operator looks at the address.
        ("Unknown".to_string(), vec![])
    }
}

/// Stitch together the full `Report`. Each check is best-effort: a single
/// RPC fault yields a populated `error` field, never a panic.
pub async fn build_report(cfg: &RuntimeConfig) -> Result<Report> {
    use crate::report::Report;

    let sentrix_provider = http_provider(&cfg.sentrix_rpc)?;
    let sepolia_provider = http_provider(&cfg.sepolia_rpc)?;

    let testnet_path = cfg.deployments_path("hyperlane-testnet.json");
    let sepolia_path = cfg.deployments_path("hyperlane-sepolia.json");
    let warp_path = cfg.deployments_path("hyperlane-warp-route.json");

    let testnet = load_hyperlane_testnet(&testnet_path).ok();
    let sepolia = load_hyperlane_sepolia(&sepolia_path).ok();
    let warp = load_warp_route(&warp_path).ok();

    let sentrix_rpc = rpc::probe(&cfg.sentrix_rpc, sentrix_provider.clone()).await;
    let sepolia_rpc = rpc::probe(&cfg.sepolia_rpc, sepolia_provider.clone()).await;

    let mut mailboxes = Vec::new();
    if let Some(t) = testnet.as_ref() {
        mailboxes.push(
            inspect_mailbox(
                "sentrix-testnet-mailbox",
                &t.contracts.mailbox.address,
                t.chain_id,
                sentrix_provider.clone(),
            )
            .await,
        );
    }
    if let Some(s) = sepolia.as_ref() {
        mailboxes.push(
            inspect_mailbox(
                "sepolia-mailbox",
                &s.pre_deployed.mailbox,
                s.chain_id,
                sepolia_provider.clone(),
            )
            .await,
        );
    }

    // ---- Routes ----

    let mut routes: Vec<RouteReport> = Vec::new();
    let mut warnings: Vec<String> = Vec::new();

    // Collect known NoopIsm addresses for ISM classification.
    let mut noop_isms: Vec<Address> = Vec::new();
    if let Some(t) = testnet.as_ref() {
        if let Ok(a) = parse_address(&t.contracts.noop_ism.address) {
            noop_isms.push(a);
        }
    }
    if let Some(s) = sepolia.as_ref() {
        if let Ok(a) = parse_address(&s.our_deployments.noop_ism.address) {
            noop_isms.push(a);
        }
    }

    if let Some(w) = warp.as_ref() {
        // Sentrix → Sepolia warp route (HypERC20Collateral → HypERC20).
        let sentrix_warp = noopism::scan_route(
            "warp-wsrx-sentrix-to-sepolia",
            w.sentrix_testnet.chain_id,
            w.sepolia.chain_id,
            &w.working_path.components.hyperc20_collateral_sentrix,
            &w.working_path.components.hyperc20_sepolia,
            w.sentrix_testnet.unsafe_demo,
            &noop_isms,
            sentrix_provider.clone(),
        )
        .await;
        if !sentrix_warp.unsafe_flags.is_empty() && !sentrix_warp.unsafe_demo {
            warnings.push(format!(
                "{}: {}",
                sentrix_warp.id,
                sentrix_warp.unsafe_flags.join(", ")
            ));
        }
        routes.push(sentrix_warp);

        // Sepolia → Sentrix reverse route (HypERC20 → HypERC20Collateral).
        let sepolia_warp = noopism::scan_route(
            "warp-wsrx-sepolia-to-sentrix",
            w.sepolia.chain_id,
            w.sentrix_testnet.chain_id,
            &w.working_path.components.hyperc20_sepolia,
            &w.working_path.components.hyperc20_collateral_sentrix,
            w.sepolia.unsafe_demo,
            &noop_isms,
            sepolia_provider.clone(),
        )
        .await;
        if !sepolia_warp.unsafe_flags.is_empty() && !sepolia_warp.unsafe_demo {
            warnings.push(format!(
                "{}: {}",
                sepolia_warp.id,
                sepolia_warp.unsafe_flags.join(", ")
            ));
        }
        routes.push(sepolia_warp);

        // HypNative side route, when present.
        if let Some(hyp_native) = w.sentrix_testnet.hyp_native.as_ref() {
            let route = noopism::scan_route(
                "hypnative-sentrix-to-sepolia",
                w.sentrix_testnet.chain_id,
                w.sepolia.chain_id,
                hyp_native,
                &w.working_path.components.hyperc20_sepolia,
                w.sentrix_testnet.unsafe_demo,
                &noop_isms,
                sentrix_provider.clone(),
            )
            .await;
            if !route.unsafe_flags.is_empty() && !route.unsafe_demo {
                warnings.push(format!("{}: {}", route.id, route.unsafe_flags.join(", ")));
            }
            routes.push(route);
        }
    }

    // ---- wSRX 1:1 invariant ----

    let wsrx_invariant = if let Some(w) = warp.as_ref() {
        Some(
            balance::check_invariant(
                cfg,
                &w.working_path.components.wsrx_sentrix,
                &w.working_path.components.hyperc20_collateral_sentrix,
                &w.working_path.components.hyperc20_sepolia,
                sentrix_provider.clone(),
                sepolia_provider.clone(),
            )
            .await,
        )
    } else {
        None
    };
    if let Some(inv) = wsrx_invariant.as_ref() {
        if !inv.ok {
            warnings.push(format!(
                "wSRX invariant drift: collateral={} hyperc20={} drift={}",
                inv.wsrx_locked_in_collateral, inv.hyperc20_total_supply_sepolia, inv.drift_wei
            ));
        }
    }

    // ---- Stuck-message scan (best effort; skipped silently on RPC error)

    let stuck_messages = match (testnet.as_ref(), sepolia.as_ref()) {
        (Some(t), Some(s)) => stuck::scan(
            cfg,
            t.chain_id,
            &t.contracts.mailbox.address,
            s.chain_id,
            &s.pre_deployed.mailbox,
            sentrix_provider.clone(),
            sepolia_provider.clone(),
        )
        .await
        .unwrap_or_default(),
        _ => Vec::new(),
    };
    if !stuck_messages.is_empty() {
        warnings.push(format!(
            "{} dispatched messages with no matching destination process",
            stuck_messages.len()
        ));
    }

    Ok(Report {
        timestamp: chrono::Utc::now(),
        network: format!("{:?}", cfg.network).to_lowercase(),
        sentrix_rpc,
        sepolia_rpc,
        mailboxes,
        routes,
        wsrx_invariant,
        stuck_messages,
        warnings,
    })
}
