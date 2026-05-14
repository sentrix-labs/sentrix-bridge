//! Runtime configuration: which RPCs, which deployments file, which network.
//!
//! RPC URLs come from (highest precedence first):
//! 1. CLI flag (`--sentrix-rpc`, `--sepolia-rpc`)
//! 2. Env vars (`SENTRIX_RPC_URL`, `SEPOLIA_RPC_URL`)
//! 3. Public defaults (mainnet / testnet RPCs that already appear in the
//!    bridge README — no secret material)
//!
//! We deliberately do not parse `.env` files here; the operator already loads
//! their environment via `direnv` / `dotenv` at the shell level. Keeping the
//! watcher dotenv-free avoids accidentally consuming `.env.production` keys.

use std::path::{Path, PathBuf};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Network {
    /// Sentrix Mainnet (chainId 7119).
    Mainnet,
    /// Sentrix Testnet (chainId 7120) — the only chain that currently has a
    /// live Hyperlane deployment.
    Testnet,
}

impl Network {
    pub fn sentrix_chain_id(self) -> u64 {
        match self {
            Network::Mainnet => 7119,
            Network::Testnet => 7120,
        }
    }

    pub fn default_sentrix_rpc(self) -> &'static str {
        match self {
            Network::Mainnet => "https://rpc.sentrixchain.com",
            Network::Testnet => "https://testnet-rpc.sentrixchain.com",
        }
    }

    pub fn wsrx_address(self) -> &'static str {
        match self {
            Network::Mainnet => "0x4693b113e523A196d9579333c4ab8358e2656553",
            Network::Testnet => "0x85d5E7694AF31C2Edd0a7e66b7c6c92C59fF949A",
        }
    }
}

#[derive(Clone, Debug)]
pub struct RuntimeConfig {
    pub network: Network,
    pub sentrix_rpc: String,
    pub sepolia_rpc: String,
    pub deployments_dir: PathBuf,
    /// How many recent blocks to scan when looking for stuck Dispatches.
    pub stuck_lookback_blocks: u64,
}

impl RuntimeConfig {
    pub fn build(
        network: Network,
        sentrix_rpc_override: Option<String>,
        sepolia_rpc_override: Option<String>,
        deployments_dir: Option<PathBuf>,
    ) -> Self {
        let sentrix_rpc = sentrix_rpc_override
            .or_else(|| std::env::var("SENTRIX_RPC_URL").ok())
            .unwrap_or_else(|| network.default_sentrix_rpc().to_string());
        let sepolia_rpc = sepolia_rpc_override
            .or_else(|| std::env::var("SEPOLIA_RPC_URL").ok())
            // Public Sepolia fallback. Operator should override via env when
            // they want their Infura/Alchemy URL — we never embed keys.
            .unwrap_or_else(|| "https://ethereum-sepolia-rpc.publicnode.com".to_string());

        let deployments_dir = deployments_dir
            .or_else(|| std::env::var("BRIDGE_DEPLOYMENTS_DIR").ok().map(PathBuf::from))
            .unwrap_or_else(default_deployments_dir);

        Self {
            network,
            sentrix_rpc,
            sepolia_rpc,
            deployments_dir,
            stuck_lookback_blocks: 5_000,
        }
    }

    pub fn deployments_path(&self, name: &str) -> PathBuf {
        self.deployments_dir.join(name)
    }
}

fn default_deployments_dir() -> PathBuf {
    // Walk up from CARGO_MANIFEST_DIR (./watcher-rs) to find ../deployments.
    // Falls back to ./deployments if invoked from the bridge root directly.
    let here = Path::new(env!("CARGO_MANIFEST_DIR"));
    let parent = here.parent().unwrap_or(here);
    let candidate = parent.join("deployments");
    if candidate.exists() {
        candidate
    } else {
        PathBuf::from("deployments")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mainnet_defaults_resolve_to_public_rpc() {
        let cfg = RuntimeConfig::build(Network::Mainnet, None, None, Some(PathBuf::from("/tmp")));
        assert_eq!(cfg.sentrix_rpc, "https://rpc.sentrixchain.com");
        assert_eq!(cfg.network.sentrix_chain_id(), 7119);
    }

    #[test]
    fn testnet_defaults_resolve_to_public_rpc() {
        let cfg = RuntimeConfig::build(Network::Testnet, None, None, Some(PathBuf::from("/tmp")));
        assert_eq!(cfg.sentrix_rpc, "https://testnet-rpc.sentrixchain.com");
        assert_eq!(cfg.network.sentrix_chain_id(), 7120);
    }

    #[test]
    fn cli_override_wins() {
        let cfg = RuntimeConfig::build(
            Network::Testnet,
            Some("http://localhost:8545".into()),
            None,
            Some(PathBuf::from("/tmp")),
        );
        assert_eq!(cfg.sentrix_rpc, "http://localhost:8545");
    }
}
