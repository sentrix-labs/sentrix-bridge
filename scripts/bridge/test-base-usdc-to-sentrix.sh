#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ENVIRONMENT="$(env_name "${1:-testnet}")"
[[ "$ENVIRONMENT" == "testnet" ]] || die "mainnet test transfer blocked"
need_cmd cast
need_cmd jq

require_env BASE_SEPOLIA_RPC
require_env SENTRIX_TESTNET_RPC
require_address_env BASE_USDC_SEPOLIA

DEPLOYMENT="$(deployment_file testnet)"
ROUTER="$(jq -r '.source.router // empty' "$DEPLOYMENT")"
SUSDC="$(jq -r '.destination.router // empty' "$DEPLOYMENT")"
[[ "$ROUTER" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "missing Base Sepolia collateral router in $DEPLOYMENT"
[[ "$SUSDC" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "missing Sentrix Testnet synthetic router/token in $DEPLOYMENT"

assert_erc20_decimals "$BASE_SEPOLIA_RPC" "$BASE_USDC_SEPOLIA" "6"
assert_erc20_decimals "$SENTRIX_TESTNET_RPC" "$SUSDC" "6"

cat <<EOF
Readiness ok for manual test:
1. Approve Base router $ROUTER to spend exact USDC amount.
2. Call Hyperlane warp transfer from Base Sepolia to Sentrix domain 7120.
3. Confirm MessageDispatched on Base mailbox.
4. Confirm relayer delivery and sUSDC balance on Sentrix.

This script does not sign transactions or print keys.
EOF
