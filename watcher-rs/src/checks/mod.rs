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
use std::time::Duration;

use crate::config::RuntimeConfig;
use crate::report::{InvariantStatus, MailboxReport, Report, RouteReport};

/// Hard cap on every RPC round-trip. Public Sepolia nodes occasionally
/// hang for minutes; without a timeout the entire watcher run blocks and
/// the api-rs `/status` endpoint stops returning. 10s is comfortably
/// above any healthy provider's p99 and short enough to fit inside an
/// alerting cycle.
pub const RPC_TIMEOUT: Duration = Duration::from_secs(10);

/// Build a reqwest client with the watcher's standard timeouts. We use
/// alloy's re-exported reqwest crate (`alloy::transports::http::reqwest`)
/// so the type matches what `ProviderBuilder::connect_reqwest` expects —
/// adding a top-level `reqwest = "0.12"` dep would compile a separate
/// reqwest version and `connect_reqwest` would refuse it.
pub fn http_client() -> Result<alloy::transports::http::reqwest::Client> {
    alloy::transports::http::reqwest::Client::builder()
        .timeout(RPC_TIMEOUT)
        .connect_timeout(RPC_TIMEOUT)
        .build()
        .context("build reqwest client with timeout")
}

// Build a minimal HTTP provider. We use `DynProvider` so the same handle
// type flows through every check helper without leaking an enormous generic
// chain. The provider is wired through a reqwest client with an explicit
// timeout (see `RPC_TIMEOUT`) so a stalled RPC can't hang the run.
pub fn http_provider(rpc_url: &str) -> Result<DynProvider<Ethereum>> {
    let url = rpc_url
        .parse()
        .with_context(|| format!("invalid RPC URL: {rpc_url}"))?;
    let client = http_client()?;
    let provider = ProviderBuilder::new().connect_reqwest(client, url);
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

/// Load a deployments JSON and, on failure, log a WARN + remember the
/// reason in `warnings` so the report doesn't go out clean while we're
/// secretly skipping every route. Returns `None` only when the file
/// genuinely couldn't be loaded.
fn load_deployment_or_warn<T, F>(
    path: &Path,
    label: &str,
    loader: F,
    warnings: &mut Vec<String>,
) -> Option<T>
where
    F: FnOnce(&Path) -> Result<T>,
{
    match loader(path) {
        Ok(v) => Some(v),
        Err(e) => {
            // Chain the anyhow context (`read X` / `parse X`) into one
            // line so operators see WHY, not just that the file was
            // missing.
            let detail = format!("{e:#}");
            tracing::warn!(target: "watcher", "load {label} ({}) failed: {detail}", path.display());
            warnings.push(format!(
                "deployment file {} ({}) load failed: {detail}",
                label,
                path.display()
            ));
            None
        }
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

    // Collect warnings up-front so deployment-load failures surface in
    // the final report instead of being silently dropped via `.ok()`.
    let mut warnings: Vec<String> = Vec::new();

    let testnet = load_deployment_or_warn(
        &testnet_path,
        "hyperlane-testnet.json",
        load_hyperlane_testnet,
        &mut warnings,
    );
    let sepolia = load_deployment_or_warn(
        &sepolia_path,
        "hyperlane-sepolia.json",
        load_hyperlane_sepolia,
        &mut warnings,
    );
    let warp = load_deployment_or_warn(
        &warp_path,
        "hyperlane-warp-route.json",
        load_warp_route,
        &mut warnings,
    );

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
    // `warnings` was already initialized above so deployment-load failures
    // could be appended; keep accumulating into the same vec here.

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
        // Only emit the "drift" warning when the check actually got both
        // numbers and they disagreed. RPC/ABI failures land in
        // `Unknown` and surface as a separate "could not check" warning
        // so operators don't get paged about imaginary drift during a
        // public Sepolia outage.
        match inv.status {
            InvariantStatus::Ok => {}
            InvariantStatus::Drift => warnings.push(format!(
                "wSRX invariant drift: collateral={} hyperc20={} drift={}",
                inv.wsrx_locked_in_collateral, inv.hyperc20_total_supply_sepolia, inv.drift_wei
            )),
            InvariantStatus::Unknown => warnings.push(format!(
                "wSRX invariant could not be evaluated: {}",
                inv.error.as_deref().unwrap_or("unknown reason")
            )),
        }
    }

    // ---- Stuck-message scan (best effort; skip + reason on RPC error)

    let stuck = match (testnet.as_ref(), sepolia.as_ref()) {
        (Some(t), Some(s)) => {
            stuck::scan(
                cfg,
                t.chain_id,
                &t.contracts.mailbox.address,
                s.chain_id,
                &s.pre_deployed.mailbox,
                sentrix_provider.clone(),
                sepolia_provider.clone(),
            )
            .await
        }
        _ => crate::report::StuckCheck::Skipped {
            reason: "deployments JSON missing testnet or sepolia mailbox".into(),
        },
    };
    let stuck_messages: Vec<_> = stuck.messages().to_vec();
    match &stuck {
        crate::report::StuckCheck::Scanned { messages } if !messages.is_empty() => {
            warnings.push(format!(
                "{} dispatched messages with no matching destination process",
                messages.len()
            ));
        }
        crate::report::StuckCheck::Skipped { reason } => {
            warnings.push(format!("stuck-message scan skipped: {reason}"));
        }
        _ => {}
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
        stuck,
        warnings,
    })
}

/// Run ONLY the NoopIsm warp-route audit. Skips RPC liveness, mailbox
/// inspection, the wSRX invariant, and the stuck-message scan. Use when
/// the operator wants a tight low-quota probe (e.g. cron every minute)
/// or in CI where the full pipeline isn't needed.
pub async fn build_noopism_only(cfg: &RuntimeConfig) -> Result<Vec<RouteReport>> {
    let sentrix_provider = http_provider(&cfg.sentrix_rpc)?;
    let sepolia_provider = http_provider(&cfg.sepolia_rpc)?;

    let testnet_path = cfg.deployments_path("hyperlane-testnet.json");
    let sepolia_path = cfg.deployments_path("hyperlane-sepolia.json");
    let warp_path = cfg.deployments_path("hyperlane-warp-route.json");

    // We don't surface load warnings here — the focused command's caller
    // gets stdout JSON, and a failed load means an empty routes vec.
    // The full `status` command is the one that builds the warnings list.
    let testnet = load_hyperlane_testnet(&testnet_path).ok();
    let sepolia = load_hyperlane_sepolia(&sepolia_path).ok();
    let Some(warp) = load_warp_route(&warp_path).ok() else {
        return Ok(Vec::new());
    };

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

    let mut routes = Vec::new();
    routes.push(
        noopism::scan_route(
            "warp-wsrx-sentrix-to-sepolia",
            warp.sentrix_testnet.chain_id,
            warp.sepolia.chain_id,
            &warp.working_path.components.hyperc20_collateral_sentrix,
            &warp.working_path.components.hyperc20_sepolia,
            warp.sentrix_testnet.unsafe_demo,
            &noop_isms,
            sentrix_provider.clone(),
        )
        .await,
    );
    routes.push(
        noopism::scan_route(
            "warp-wsrx-sepolia-to-sentrix",
            warp.sepolia.chain_id,
            warp.sentrix_testnet.chain_id,
            &warp.working_path.components.hyperc20_sepolia,
            &warp.working_path.components.hyperc20_collateral_sentrix,
            warp.sepolia.unsafe_demo,
            &noop_isms,
            sepolia_provider.clone(),
        )
        .await,
    );
    if let Some(hyp_native) = warp.sentrix_testnet.hyp_native.as_ref() {
        routes.push(
            noopism::scan_route(
                "hypnative-sentrix-to-sepolia",
                warp.sentrix_testnet.chain_id,
                warp.sepolia.chain_id,
                hyp_native,
                &warp.working_path.components.hyperc20_sepolia,
                warp.sentrix_testnet.unsafe_demo,
                &noop_isms,
                sentrix_provider.clone(),
            )
            .await,
        );
    }
    Ok(routes)
}

/// Run ONLY the wSRX 1:1 invariant. Skips RPC liveness, mailbox
/// inspection, route classification, and the stuck-message scan.
pub async fn build_balance_only(
    cfg: &RuntimeConfig,
) -> Result<Option<crate::report::WsrxInvariant>> {
    let warp_path = cfg.deployments_path("hyperlane-warp-route.json");
    let Some(warp) = load_warp_route(&warp_path).ok() else {
        return Ok(None);
    };
    let sentrix_provider = http_provider(&cfg.sentrix_rpc)?;
    let sepolia_provider = http_provider(&cfg.sepolia_rpc)?;
    let inv = balance::check_invariant(
        cfg,
        &warp.working_path.components.wsrx_sentrix,
        &warp.working_path.components.hyperc20_collateral_sentrix,
        &warp.working_path.components.hyperc20_sepolia,
        sentrix_provider,
        sepolia_provider,
    )
    .await;
    Ok(Some(inv))
}
