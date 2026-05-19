#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ENVIRONMENT="$(env_name "${1:-}")"
need_cmd jq
need_cmd cast

DEPLOYMENT="$(deployment_file "$ENVIRONMENT")"
SRC_ROUTER="$(jq -r '.source.router // empty' "$DEPLOYMENT")"
DST_ROUTER="$(jq -r '.destination.router // empty' "$DEPLOYMENT")"
SRC_TOKEN="$(jq -r '.source.collateralToken' "$DEPLOYMENT")"

if [[ "$ENVIRONMENT" == "testnet" ]]; then
  require_env BASE_SEPOLIA_RPC
  require_env SENTRIX_TESTNET_RPC
  SRC_RPC="$BASE_SEPOLIA_RPC"
  DST_RPC="$SENTRIX_TESTNET_RPC"
else
  [[ "${ALLOW_MAINNET_MONITOR:-}" == "1" ]] || die "set ALLOW_MAINNET_MONITOR=1 for mainnet monitoring"
  require_env BASE_MAINNET_RPC
  require_env SENTRIX_MAINNET_RPC
  SRC_RPC="$BASE_MAINNET_RPC"
  DST_RPC="$SENTRIX_MAINNET_RPC"
fi

SRC_BLOCK="$(cast block-number --rpc-url "$SRC_RPC" 2>/dev/null || echo unreachable)"
DST_BLOCK="$(cast block-number --rpc-url "$DST_RPC" 2>/dev/null || echo unreachable)"

echo "source_rpc_block=$SRC_BLOCK"
echo "sentrix_rpc_block=$DST_BLOCK"

if [[ "$SRC_ROUTER" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  LOCKED="$(cast call "$SRC_TOKEN" 'balanceOf(address)(uint256)' "$SRC_ROUTER" --rpc-url "$SRC_RPC" 2>/dev/null || echo unreadable)"
  echo "base_collateral_usdc_balance=$LOCKED"
else
  echo "base_collateral_usdc_balance=router_not_configured"
fi

if [[ "$DST_ROUTER" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  SUPPLY="$(cast call "$DST_ROUTER" 'totalSupply()(uint256)' --rpc-url "$DST_RPC" 2>/dev/null || echo unreadable)"
  DECIMALS="$(cast call "$DST_ROUTER" 'decimals()(uint8)' --rpc-url "$DST_RPC" 2>/dev/null || echo unreadable)"
  echo "sentrix_susdc_total_supply=$SUPPLY"
  echo "sentrix_susdc_decimals=$DECIMALS"
else
  echo "sentrix_susdc_total_supply=router_not_configured"
fi

echo "pending_messages=not_implemented"
echo "failed_messages=not_implemented"
echo "relayer_health=check_hyperlane_agent_metrics"
echo "cap_usage=check_caps_after_cap_wrapper_or_hook_is_deployed"
