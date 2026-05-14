//! Runtime config — RPC endpoints + which network we're inspecting.
//!
//! Defaults come from the public chain RPCs documented at
//! sentrixchain.com. Operator-private endpoints are read from env so we
//! never bake a key into the binary.

use serde::{Deserialize, Serialize};
use std::env;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Network {
    Mainnet,
    Testnet,
}

impl Network {
    pub fn as_str(self) -> &'static str {
        match self {
            Network::Mainnet => "mainnet",
            Network::Testnet => "testnet",
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct RuntimeConfig {
    pub network: Network,
    /// Sentrix Chain RPC (mainnet or testnet depending on `network`).
    pub sentrix_rpc: String,
    /// Sepolia RPC. Only the testnet warp route uses this; for mainnet we
    /// keep it as a placeholder so future Ethereum-mainnet routes can drop in.
    pub sepolia_rpc: String,
    /// Path to the directory containing `hyperlane-*.json` deployments.
    /// Resolved relative to the binary's CWD by default (the repo root).
    pub deployments_dir: String,
    /// Path to the static fresh-user-flow status file.
    pub fresh_user_flow_path: String,
}

impl RuntimeConfig {
    pub fn from_env(network: Network) -> Self {
        let sentrix_rpc = match network {
            Network::Mainnet => env::var("SENTRIX_RPC_URL")
                .unwrap_or_else(|_| "https://rpc.sentrixchain.com".to_string()),
            Network::Testnet => env::var("SENTRIX_TESTNET_RPC_URL")
                .unwrap_or_else(|_| "https://testnet-rpc.sentrixchain.com".to_string()),
        };
        let sepolia_rpc = env::var("SEPOLIA_RPC_URL")
            // Public Sepolia endpoint as a non-keyed default. Operators
            // should point this at their own Alchemy/Infura URL via env.
            .unwrap_or_else(|_| "https://ethereum-sepolia.publicnode.com".to_string());
        let deployments_dir =
            env::var("BRIDGE_DEPLOYMENTS_DIR").unwrap_or_else(|_| "deployments".to_string());
        let fresh_user_flow_path = env::var("BRIDGE_FRESH_USER_FLOW_PATH")
            .unwrap_or_else(|_| "api-rs/data/fresh-user-flow.json".to_string());

        Self {
            network,
            sentrix_rpc,
            sepolia_rpc,
            deployments_dir,
            fresh_user_flow_path,
        }
    }
}
