#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MODE="${1:---check}"
[[ "$MODE" == "--check" || "$MODE" == "--deploy" ]] || die "usage: $0 [--check|--deploy]"

need_cmd grep

WARP_CONFIG="$(warp_config testnet)"
DEPLOYMENT="$(deployment_file testnet)"
[[ -f "$WARP_CONFIG" ]] || die "missing warp config: $WARP_CONFIG"
[[ -f "$DEPLOYMENT" ]] || die "missing deployment manifest: $DEPLOYMENT"

validate_testnet_owner_policy
require_env BASE_SEPOLIA_RPC
require_env SENTRIX_TESTNET_RPC
require_address_env SENTRIX_TESTNET_MAILBOX
require_address_env BASE_SEPOLIA_MAILBOX
require_address_env SENTRIX_TESTNET_ISM
require_address_env BASE_SEPOLIA_ISM
require_address_env SENTRIX_TESTNET_MULTISIG_ISM
require_address_env BASE_SEPOLIA_MULTISIG_ISM
assert_not_noop_ism_address SENTRIX_TESTNET_ISM
assert_not_noop_ism_address BASE_SEPOLIA_ISM
assert_not_noop_ism_address SENTRIX_TESTNET_MULTISIG_ISM
assert_not_noop_ism_address BASE_SEPOLIA_MULTISIG_ISM

[[ "$(lower "$SENTRIX_TESTNET_ISM")" == "$(lower "$SENTRIX_TESTNET_MULTISIG_ISM")" ]] || die "SENTRIX_TESTNET_ISM must equal SENTRIX_TESTNET_MULTISIG_ISM"
[[ "$(lower "$BASE_SEPOLIA_ISM")" == "$(lower "$BASE_SEPOLIA_MULTISIG_ISM")" ]] || die "BASE_SEPOLIA_ISM must equal BASE_SEPOLIA_MULTISIG_ISM"
[[ "${SENTRIX_TESTNET_ISM_KIND:-}" == "MultisigIsm" || "${SENTRIX_TESTNET_ISM_KIND:-}" == "ProductionGradeIsm" ]] || die "SENTRIX_TESTNET_ISM_KIND must be MultisigIsm or ProductionGradeIsm"
[[ "${BASE_SEPOLIA_ISM_KIND:-}" == "MultisigIsm" || "${BASE_SEPOLIA_ISM_KIND:-}" == "ProductionGradeIsm" ]] || die "BASE_SEPOLIA_ISM_KIND must be MultisigIsm or ProductionGradeIsm"

USDC="${BASE_SEPOLIA_USDC:-${BASE_USDC_SEPOLIA:-}}"
[[ -n "$USDC" ]] || die "missing env var: BASE_SEPOLIA_USDC"
[[ "$USDC" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "BASE_SEPOLIA_USDC is not an EVM address"
[[ "$(lower "$USDC")" == "$(lower "$BASE_SEPOLIA_USDC_CANONICAL")" ]] || die "BASE_SEPOLIA_USDC must be Circle Base Sepolia USDC"

grep -q 'token: "0x036CbD53842c5426634e7929541eC2318f3dCF7e"' "$WARP_CONFIG" || die "warp config Base Sepolia USDC token mismatch"
grep -q 'name: "Sentrix Bridged USDC"' "$WARP_CONFIG" || die "warp config sUSDC name mismatch"
grep -q 'symbol: "sUSDC"' "$WARP_CONFIG" || die "warp config sUSDC symbol mismatch"
grep -q 'decimals: 6' "$WARP_CONFIG" || die "warp config must configure 6 decimals"

for name in BASE_MAINNET_RPC SENTRIX_MAINNET_RPC BASE_MAINNET_MAILBOX BASE_MAINNET_ISM SENTRIX_MAINNET_MAILBOX SENTRIX_MAINNET_ISM ALLOW_MAINNET_WARP_DEPLOY; do
  [[ -z "${!name:-}" ]] || die "$name must not be used in the testnet deployment path"
done

if [[ "$MODE" == "--deploy" ]]; then
  [[ "${ALLOW_TESTNET_WARP_DEPLOY:-}" == "1" ]] || die "set ALLOW_TESTNET_WARP_DEPLOY=1 to deploy testnet warp route"
  HL_KEY_ENV="HYP_""KEY"
  require_env "$HL_KEY_ENV"
fi

if command -v cast >/dev/null 2>&1; then
  assert_chain_id "$BASE_SEPOLIA_RPC" "${BASE_SEPOLIA_CHAIN_ID:-84532}"
  assert_chain_id "$SENTRIX_TESTNET_RPC" "${SENTRIX_TESTNET_CHAIN_ID:-7120}"
  assert_erc20_decimals "$BASE_SEPOLIA_RPC" "$USDC" "6"
else
  warn "cast not found; skipped RPC chain-id and USDC decimals checks"
fi

cat <<EOF
Base USDC -> Sentrix sUSDC warp config ok: testnet only
Base Sepolia USDC = $USDC
Base Sepolia mailbox = $BASE_SEPOLIA_MAILBOX
Base Sepolia ISM = $BASE_SEPOLIA_ISM
Sentrix Testnet mailbox = $SENTRIX_TESTNET_MAILBOX
Sentrix Testnet ISM = $SENTRIX_TESTNET_ISM
sUSDC name = Sentrix Bridged USDC
sUSDC symbol = sUSDC
sUSDC decimals = 6
owner/admin = $OWNER_ADDRESS
NoopISM = blocked
EOF
