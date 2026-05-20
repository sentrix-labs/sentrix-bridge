#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WARP="$ROOT_DIR/deployments/hyperlane-warp-route.json"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2
    exit 1
  }
}

need_cmd jq
need_cmd cast

SENTRIX_RPC="${SENTRIX_RPC:-${SENTRIX_TESTNET_RPC:-https://testnet-rpc.sentrixchain.com}}"
SEPOLIA_RPC="${SEPOLIA_RPC:-${SEPOLIA_RPC_URL:-https://ethereum-sepolia-rpc.publicnode.com}}"

WSRX="$(jq -r '.workingPath.components.WSRX_sentrix' "$WARP")"
COLLATERAL="$(jq -r '.workingPath.components.HypERC20Collateral_sentrix' "$WARP")"
HYPERC20_SEPOLIA="$(jq -r '.workingPath.components.HypERC20_wSRX_sepolia' "$WARP")"
SENTRIX_MAILBOX="$(jq -r '.sentrixTestnet.config.mailbox' "$WARP")"
SEPOLIA_MAILBOX="$(jq -r '.sepolia.config.mailbox' "$WARP")"
SENTRIX_NOOP="$(jq -r '.sentrixTestnet.config.ism' "$WARP" | sed 's/ .*//')"
SEPOLIA_NOOP="$(jq -r '.sepolia.config.ism' "$WARP" | sed 's/ .*//')"

echo "route = wSRX Sentrix Testnet <-> Sepolia"
echo "status = $(jq -r '.status' "$WARP")"
echo "sentrix_rpc_chain_id = $(cast chain-id --rpc-url "$SENTRIX_RPC")"
echo "sepolia_rpc_chain_id = $(cast chain-id --rpc-url "$SEPOLIA_RPC")"
echo "wsrx_sentrix = $WSRX"
echo "collateral_sentrix = $COLLATERAL"
echo "hyperc20_wsrx_sepolia = $HYPERC20_SEPOLIA"
echo "sentrix_mailbox = $SENTRIX_MAILBOX"
echo "sepolia_mailbox = $SEPOLIA_MAILBOX"

echo "sentrix_collateral_ism = $(cast call "$COLLATERAL" 'interchainSecurityModule()(address)' --rpc-url "$SENTRIX_RPC" 2>/dev/null || echo unreadable)"
echo "sepolia_hyperc20_ism = $(cast call "$HYPERC20_SEPOLIA" 'interchainSecurityModule()(address)' --rpc-url "$SEPOLIA_RPC" 2>/dev/null || echo unreadable)"
echo "sentrix_expected_noop = $SENTRIX_NOOP"
echo "sepolia_expected_noop = $SEPOLIA_NOOP"

echo "sentrix_remote_11155111 = $(cast call "$COLLATERAL" 'routers(uint32)(bytes32)' 11155111 --rpc-url "$SENTRIX_RPC" 2>/dev/null || echo unreadable)"
echo "sepolia_remote_7120 = $(cast call "$HYPERC20_SEPOLIA" 'routers(uint32)(bytes32)' 7120 --rpc-url "$SEPOLIA_RPC" 2>/dev/null || echo unreadable)"

echo "wsrx_decimals = $(cast call "$WSRX" 'decimals()(uint8)' --rpc-url "$SENTRIX_RPC" 2>/dev/null || echo unreadable)"
echo "sepolia_wsrx_decimals = $(cast call "$HYPERC20_SEPOLIA" 'decimals()(uint8)' --rpc-url "$SEPOLIA_RPC" 2>/dev/null || echo unreadable)"
echo "sepolia_wsrx_total_supply = $(cast call "$HYPERC20_SEPOLIA" 'totalSupply()(uint256)' --rpc-url "$SEPOLIA_RPC" 2>/dev/null || echo unreadable)"

echo
echo "SAFETY: This route is TESTNET ONLY and currently uses NoopISM per deployment artifact."
echo "SAFETY: Use only for smoke tests. Do not call it production-grade and do not bridge real value."
