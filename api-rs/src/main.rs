//! Binary entry point. CLI:
//!
//! ```text
//! cargo run -p sentrix-bridge-api -- serve --bind 127.0.0.1:8090
//! cargo run -p sentrix-bridge-api -- serve --bind 0.0.0.0:8090 --testnet
//! ```

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use sentrix_bridge_api::{
    config::{Network, RuntimeConfig},
    deployments::{default_dir, Deployments},
    router, AppState,
};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(name = "sentrix-bridge-api", version, about = "Read-only HTTP status API for sentrix-bridge.")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Start the HTTP server.
    Serve {
        /// Bind address. Default 127.0.0.1:8090 — flip to 0.0.0.0:8090 for
        /// remote access. Read-only API, but the operator owns the firewall.
        #[arg(long, default_value = "127.0.0.1:8090")]
        bind: SocketAddr,

        /// Inspect testnet (default = mainnet). Mirrors the watcher-rs flag.
        #[arg(long)]
        testnet: bool,

        /// Override the deployments directory. Defaults to `./deployments`.
        #[arg(long)]
        deployments_dir: Option<PathBuf>,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let cli = Cli::parse();
    match cli.cmd {
        Cmd::Serve {
            bind,
            testnet,
            deployments_dir,
        } => {
            let network = if testnet { Network::Testnet } else { Network::Mainnet };
            let mut config = RuntimeConfig::from_env(network);
            if let Some(d) = deployments_dir {
                config.deployments_dir = d.to_string_lossy().into_owned();
            }

            let deployments_path = if config.deployments_dir.is_empty() {
                default_dir()
            } else {
                PathBuf::from(&config.deployments_dir)
            };
            let deployments = Deployments::load(&deployments_path)
                .with_context(|| format!("loading deployments from {:?}", deployments_path))?;
            tracing::info!(
                routes = deployments.routes.len(),
                files = deployments.raw.len(),
                "deployments loaded"
            );

            let state = Arc::new(AppState::new(config, deployments));
            let app = router(state);

            tracing::info!(%bind, "sentrix-bridge-api listening");
            let listener = tokio::net::TcpListener::bind(bind)
                .await
                .with_context(|| format!("binding {}", bind))?;
            axum::serve(listener, app).await.context("axum::serve")?;
        }
    }

    Ok(())
}
