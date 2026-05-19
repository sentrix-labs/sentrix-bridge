#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ENVIRONMENT="$(env_name "${1:-}")"
need_cmd jq
need_cmd cast

DEPLOYMENT="$(deployment_file "$ENVIRONMENT")"
[[ -f "$DEPLOYMENT" ]] || die "missing deployment file: $DEPLOYMENT"

SRC_CHAIN_ID="$(jq -r '.source.chainId' "$DEPLOYMENT")"
DST_DECIMALS="$(jq -r '.destination.syntheticDecimals' "$DEPLOYMENT")"
[[ "$DST_DECIMALS" == "6" ]] || die "destination synthetic decimals must be 6"

if [[ "$ENVIRONMENT" == "testnet" ]]; then
  [[ "$SRC_CHAIN_ID" == "84532" ]] || die "source chain must be Base Sepolia"
  if [[ -n "${BASE_SEPOLIA_RPC:-}" && -n "${SENTRIX_TESTNET_RPC:-}" ]]; then
    assert_chain_id "$BASE_SEPOLIA_RPC" "84532"
    assert_chain_id "$SENTRIX_TESTNET_RPC" "7120"
  else
    echo "rpc_check=skipped_missing_BASE_SEPOLIA_RPC_or_SENTRIX_TESTNET_RPC"
  fi
else
  [[ "${ALLOW_MAINNET_VERIFY:-}" == "1" ]] || die "set ALLOW_MAINNET_VERIFY=1 for mainnet verification"
  [[ "$SRC_CHAIN_ID" == "8453" ]] || die "source chain must be Base mainnet"
fi

SRC_TOKEN="$(jq -r '.source.collateralToken' "$DEPLOYMENT")"
SRC_ROUTER="$(jq -r '.source.router // empty' "$DEPLOYMENT")"
DST_ROUTER="$(jq -r '.destination.router // empty' "$DEPLOYMENT")"

[[ "$SRC_TOKEN" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "invalid source collateral token"
[[ -z "$SRC_ROUTER" || "$SRC_ROUTER" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "invalid source router"
[[ -z "$DST_ROUTER" || "$DST_ROUTER" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "invalid destination router"

echo "deployment manifest ok: $ENVIRONMENT"
echo "note: fill router addresses after Hyperlane CLI deployment, then rerun for on-chain router/ISM checks"
