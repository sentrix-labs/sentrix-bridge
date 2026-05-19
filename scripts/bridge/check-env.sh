#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ENVIRONMENT="$(env_name "${1:-}")"
need_cmd cast

require_address_env OWNER_ADDRESS
require_address_env SENTRIX_SAFE_ADDRESS
require_env BRIDGE_PER_TX_CAP_USDC
require_env BRIDGE_DAILY_CAP_USDC
require_env BRIDGE_TOTAL_MINT_CAP_USDC

if [[ "$ENVIRONMENT" == "testnet" ]]; then
  require_env BASE_SEPOLIA_RPC
  require_env SENTRIX_TESTNET_RPC
  : "${BASE_SEPOLIA_CHAIN_ID:=84532}"
  : "${SENTRIX_TESTNET_CHAIN_ID:=7120}"
  require_address_env BASE_USDC_SEPOLIA
  [[ "$BASE_USDC_SEPOLIA" == "0x036CbD53842c5426634e7929541eC2318f3dCF7e" ]] || die "BASE_USDC_SEPOLIA must be Circle Base Sepolia USDC"
  assert_chain_id "$BASE_SEPOLIA_RPC" "$BASE_SEPOLIA_CHAIN_ID"
  assert_chain_id "$SENTRIX_TESTNET_RPC" "$SENTRIX_TESTNET_CHAIN_ID"
  assert_erc20_decimals "$BASE_SEPOLIA_RPC" "$BASE_USDC_SEPOLIA" "6"
else
  require_env BASE_MAINNET_RPC
  require_env SENTRIX_MAINNET_RPC
  : "${BASE_MAINNET_CHAIN_ID:=8453}"
  require_env SENTRIX_MAINNET_CHAIN_ID
  require_address_env BASE_USDC_MAINNET
  [[ "$BASE_USDC_MAINNET" == "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" ]] || die "BASE_USDC_MAINNET must be Circle Base mainnet USDC"
  assert_chain_id "$BASE_MAINNET_RPC" "$BASE_MAINNET_CHAIN_ID"
  assert_chain_id "$SENTRIX_MAINNET_RPC" "$SENTRIX_MAINNET_CHAIN_ID"
  assert_erc20_decimals "$BASE_MAINNET_RPC" "$BASE_USDC_MAINNET" "6"
fi

echo "env ok: $ENVIRONMENT"
