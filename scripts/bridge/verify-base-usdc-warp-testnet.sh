#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[[ "${1:---check}" == "--check" ]] || die "usage: $0 --check"
need_cmd jq
need_cmd cast

DEPLOYMENT="$(deployment_file testnet)"
[[ -f "$DEPLOYMENT" ]] || die "missing deployment manifest: $DEPLOYMENT"

validate_testnet_owner_policy
require_env BASE_SEPOLIA_RPC
require_env SENTRIX_TESTNET_RPC
require_address_env BASE_SEPOLIA_MAILBOX
require_address_env SENTRIX_TESTNET_MAILBOX
require_address_env BASE_SEPOLIA_ISM
require_address_env SENTRIX_TESTNET_ISM
assert_not_noop_ism_address BASE_SEPOLIA_ISM
assert_not_noop_ism_address SENTRIX_TESTNET_ISM

BASE_ROUTER="$(jq -r '.source.router // empty' "$DEPLOYMENT")"
SENTRIX_ROUTER="$(jq -r '.destination.router // empty' "$DEPLOYMENT")"
BASE_TOKEN="$(jq -r '.source.collateralToken // empty' "$DEPLOYMENT")"
SENTRIX_NAME="$(jq -r '.destination.syntheticTokenName // empty' "$DEPLOYMENT")"
SENTRIX_SYMBOL="$(jq -r '.destination.syntheticTokenSymbol // empty' "$DEPLOYMENT")"
SENTRIX_DECIMALS="$(jq -r '.destination.syntheticDecimals // empty' "$DEPLOYMENT")"

[[ "$(lower "$BASE_TOKEN")" == "$(lower "$BASE_SEPOLIA_USDC_CANONICAL")" ]] || die "deployment manifest Base collateral token mismatch"
[[ "$SENTRIX_NAME" == "Sentrix Bridged USDC" ]] || die "deployment manifest sUSDC name mismatch"
[[ "$SENTRIX_SYMBOL" == "sUSDC" ]] || die "deployment manifest sUSDC symbol mismatch"
[[ "$SENTRIX_DECIMALS" == "6" ]] || die "deployment manifest sUSDC decimals must be 6"

assert_chain_id "$BASE_SEPOLIA_RPC" "${BASE_SEPOLIA_CHAIN_ID:-84532}"
assert_chain_id "$SENTRIX_TESTNET_RPC" "${SENTRIX_TESTNET_CHAIN_ID:-7120}"
assert_erc20_decimals "$BASE_SEPOLIA_RPC" "$BASE_TOKEN" "6"

check_router() {
  local label="$1"
  local router="$2"
  local rpc="$3"
  local expected_mailbox="$4"
  local expected_ism="$5"

  [[ "$router" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "$label router missing in deployment manifest"

  local code mailbox ism owner
  code="$(cast code "$router" --rpc-url "$rpc" 2>/dev/null || true)"
  [[ -n "$code" && "$code" != "0x" ]] || die "$label router has no code"

  mailbox="$(cast call "$router" 'mailbox()(address)' --rpc-url "$rpc" 2>/dev/null || true)"
  [[ "$(lower "$mailbox")" == "$(lower "$expected_mailbox")" ]] || die "$label mailbox mismatch: expected $expected_mailbox got ${mailbox:-unreadable}"

  ism="$(cast call "$router" 'interchainSecurityModule()(address)' --rpc-url "$rpc" 2>/dev/null || true)"
  [[ "$(lower "$ism")" == "$(lower "$expected_ism")" ]] || die "$label ISM mismatch: expected $expected_ism got ${ism:-unreadable}"
  [[ "$(lower "$ism")" != "$(lower "$SENTRIX_TESTNET_NOOP_ISM")" ]] || die "$label uses blocked NoopISM"

  owner="$(cast call "$router" 'owner()(address)' --rpc-url "$rpc" 2>/dev/null || true)"
  [[ "$(lower "$owner")" == "$(lower "$SENTRIX_TESTNET_SAFE")" ]] || die "$label owner must be SentrixSafe; got ${owner:-unreadable}"
}

check_router "Base Sepolia" "$BASE_ROUTER" "$BASE_SEPOLIA_RPC" "$BASE_SEPOLIA_MAILBOX" "$BASE_SEPOLIA_ISM"
check_router "Sentrix Testnet" "$SENTRIX_ROUTER" "$SENTRIX_TESTNET_RPC" "$SENTRIX_TESTNET_MAILBOX" "$SENTRIX_TESTNET_ISM"

SENTRIX_TOKEN_DECIMALS="$(cast call "$SENTRIX_ROUTER" 'decimals()(uint8)' --rpc-url "$SENTRIX_TESTNET_RPC" 2>/dev/null || true)"
SENTRIX_TOKEN_NAME="$(cast call "$SENTRIX_ROUTER" 'name()(string)' --rpc-url "$SENTRIX_TESTNET_RPC" 2>/dev/null || true)"
SENTRIX_TOKEN_SYMBOL="$(cast call "$SENTRIX_ROUTER" 'symbol()(string)' --rpc-url "$SENTRIX_TESTNET_RPC" 2>/dev/null || true)"
[[ "$SENTRIX_TOKEN_DECIMALS" == "6" ]] || die "Sentrix sUSDC decimals mismatch: got ${SENTRIX_TOKEN_DECIMALS:-unreadable}"
[[ "$SENTRIX_TOKEN_NAME" == "Sentrix Bridged USDC" ]] || die "Sentrix sUSDC name mismatch: got ${SENTRIX_TOKEN_NAME:-unreadable}"
[[ "$SENTRIX_TOKEN_SYMBOL" == "sUSDC" ]] || die "Sentrix sUSDC symbol mismatch: got ${SENTRIX_TOKEN_SYMBOL:-unreadable}"

BASE_REMOTE="$(cast call "$BASE_ROUTER" 'routers(uint32)(bytes32)' 7120 --rpc-url "$BASE_SEPOLIA_RPC" 2>/dev/null || true)"
SENTRIX_REMOTE="$(cast call "$SENTRIX_ROUTER" 'routers(uint32)(bytes32)' 84532 --rpc-url "$SENTRIX_TESTNET_RPC" 2>/dev/null || true)"
[[ "$BASE_REMOTE" =~ ^0x[0-9a-fA-F]{64}$ ]] || die "Base router remote enrollment unreadable"
[[ "$SENTRIX_REMOTE" =~ ^0x[0-9a-fA-F]{64}$ ]] || die "Sentrix router remote enrollment unreadable"

cat <<EOF
Base USDC -> Sentrix sUSDC verification ok: testnet only
Base router = $BASE_ROUTER
Sentrix router/token = $SENTRIX_ROUTER
Base collateral token = $BASE_TOKEN
sUSDC = $SENTRIX_TOKEN_NAME / $SENTRIX_TOKEN_SYMBOL / decimals $SENTRIX_TOKEN_DECIMALS
Base mailbox = $BASE_SEPOLIA_MAILBOX
Sentrix mailbox = $SENTRIX_TESTNET_MAILBOX
Base ISM = $BASE_SEPOLIA_ISM
Sentrix ISM = $SENTRIX_TESTNET_ISM
Owner/admin = $SENTRIX_TESTNET_SAFE
NoopISM = blocked
EOF
