//! sentrix-bridge-watcher CLI entry.

use anyhow::Result;
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use tracing_subscriber::EnvFilter;

use sentrix_bridge_watcher::checks::build_report;
use sentrix_bridge_watcher::config::{Network, RuntimeConfig};
use sentrix_bridge_watcher::report::Report;

#[derive(Parser, Debug)]
#[command(
    name = "sentrix-bridge-watcher",
    version,
    about = "Read-only safety + route health monitor for sentrix-bridge."
)]
struct Cli {
    /// Use Sentrix Testnet defaults instead of Mainnet.
    #[arg(long, global = true)]
    testnet: bool,

    /// Override the Sentrix RPC URL (defaults to env SENTRIX_RPC_URL or
    /// the public mainnet/testnet RPC).
    #[arg(long, global = true, value_name = "URL")]
    sentrix_rpc: Option<String>,

    /// Override the Sepolia RPC URL (defaults to env SEPOLIA_RPC_URL or a
    /// public Sepolia RPC).
    #[arg(long, global = true, value_name = "URL")]
    sepolia_rpc: Option<String>,

    /// Override the deployments/ directory location (defaults to
    /// `<repo-root>/deployments`).
    #[arg(long, global = true, value_name = "DIR")]
    deployments_dir: Option<PathBuf>,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// Run every check + emit a full report.
    Status {
        /// Emit the machine-readable JSON instead of the human view.
        #[arg(long)]
        json: bool,
    },
    /// Run only the NoopIsm warp-route audit.
    CheckNoopism {
        #[arg(long)]
        json: bool,
    },
    /// Run only the wSRX 1:1 invariant.
    CheckBalance {
        #[arg(long)]
        json: bool,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .with_target(false)
        .init();

    let cli = Cli::parse();
    let network = if cli.testnet {
        Network::Testnet
    } else {
        Network::Mainnet
    };
    let cfg = RuntimeConfig::build(
        network,
        cli.sentrix_rpc,
        cli.sepolia_rpc,
        cli.deployments_dir,
    );

    let report = build_report(&cfg).await?;

    match cli.command {
        Command::Status { json } => emit(&report, json),
        Command::CheckNoopism { json } => {
            let routes = serde_json::json!({
                "timestamp": report.timestamp,
                "routes": report.routes,
                "warnings": report
                    .warnings
                    .iter()
                    .filter(|w| w.contains("NoopIsm"))
                    .collect::<Vec<_>>(),
            });
            if json {
                println!("{}", serde_json::to_string_pretty(&routes)?);
            } else {
                pretty_routes(&report);
            }
        }
        Command::CheckBalance { json } => {
            if json {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&report.wsrx_invariant)?
                );
            } else {
                pretty_balance(&report);
            }
        }
    }

    Ok(())
}

fn emit(report: &Report, json: bool) {
    if json {
        match serde_json::to_string_pretty(report) {
            Ok(s) => println!("{s}"),
            Err(e) => eprintln!("serialize report: {e}"),
        }
    } else {
        pretty(report);
    }
}

fn pretty(report: &Report) {
    println!("== sentrix-bridge-watcher · {} ==", report.network);
    println!("timestamp: {}", report.timestamp);
    println!();
    println!("Sentrix RPC  {}  block={:?}  chain_id={:?}",
        rpc_status(report.sentrix_rpc.ok),
        report.sentrix_rpc.block,
        report.sentrix_rpc.chain_id,
    );
    println!("Sepolia RPC  {}  block={:?}  chain_id={:?}",
        rpc_status(report.sepolia_rpc.ok),
        report.sepolia_rpc.block,
        report.sepolia_rpc.chain_id,
    );
    println!();
    for m in &report.mailboxes {
        println!(
            "Mailbox {} @ {}  localDomain={:?}  matches={:?}",
            m.label, m.address, m.local_domain, m.local_domain_matches
        );
        if let Some(e) = &m.error {
            println!("  error: {e}");
        }
    }
    println!();
    pretty_routes(report);
    println!();
    pretty_balance(report);
    if !report.stuck_messages.is_empty() {
        println!();
        println!("Stuck messages (origin -> destination):");
        for s in &report.stuck_messages {
            println!(
                "  {} -> {}  age={}b  msg={}",
                s.origin_chain, s.destination_chain, s.age_blocks, s.message_id
            );
        }
    }
    if !report.warnings.is_empty() {
        println!();
        println!("WARNINGS:");
        for w in &report.warnings {
            println!("  - {w}");
        }
    } else {
        println!();
        println!("No warnings.");
    }
}

fn rpc_status(ok: bool) -> &'static str {
    if ok {
        "OK "
    } else {
        "FAIL"
    }
}

fn pretty_routes(report: &Report) {
    println!("Routes:");
    for r in &report.routes {
        let flag_str = if r.unsafe_flags.is_empty() {
            "ok".to_string()
        } else {
            r.unsafe_flags.join(",")
        };
        println!(
            "  {} ({} -> {})  ism={}  type={}  [{}]",
            r.id,
            r.source_chain,
            r.destination_chain,
            r.ism_address.clone().unwrap_or_default(),
            r.ism_type,
            flag_str
        );
        if let Some(e) = &r.error {
            println!("    error: {e}");
        }
    }
}

fn pretty_balance(report: &Report) {
    match &report.wsrx_invariant {
        Some(inv) => {
            let status = if inv.ok { "ok" } else { "DRIFT" };
            println!(
                "wSRX invariant [{}]  collateral={}  hyperc20_sepolia={}  drift={}",
                status, inv.wsrx_locked_in_collateral, inv.hyperc20_total_supply_sepolia, inv.drift_wei
            );
            if let Some(e) = &inv.error {
                println!("  error: {e}");
            }
        }
        None => println!("wSRX invariant: not checked (warp deployment file missing)"),
    }
}
