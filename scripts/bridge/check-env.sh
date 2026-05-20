#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ENVIRONMENT="$(env_name "${1:-}")"
MODE="${2:---check}"
[[ "$MODE" == "--check" || "$MODE" == "--deploy" ]] || die "usage: $0 testnet [--check|--deploy]"
[[ "$ENVIRONMENT" == "testnet" ]] || die "Base USDC -> Sentrix sUSDC deployment path is testnet-only; mainnet is blocked"

validate_testnet_owner_policy
require_address_env SENTRIX_TESTNET_MAILBOX
require_address_env SENTRIX_TESTNET_ISM
require_env BASE_SEPOLIA_RPC
require_env SENTRIX_TESTNET_RPC

NOOP_ISM_LC="$(lower "$SENTRIX_TESTNET_NOOP_ISM")"
ISM_LC="$(lower "$SENTRIX_TESTNET_ISM")"

if [[ -n "${BASE_SEPOLIA_USDC:-}" && -n "${BASE_USDC_SEPOLIA:-}" ]]; then
  [[ "$(lower "$BASE_SEPOLIA_USDC")" == "$(lower "$BASE_USDC_SEPOLIA")" ]] || die "BASE_SEPOLIA_USDC and BASE_USDC_SEPOLIA mismatch"
fi

USDC="${BASE_SEPOLIA_USDC:-${BASE_USDC_SEPOLIA:-}}"
[[ -n "$USDC" ]] || die "missing env var: BASE_SEPOLIA_USDC"
[[ "$USDC" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "BASE_SEPOLIA_USDC is not an EVM address"
[[ "$(lower "$USDC")" == "$(lower "$BASE_SEPOLIA_USDC_CANONICAL")" ]] || die "BASE_SEPOLIA_USDC must be Circle Base Sepolia USDC"

if [[ "$MODE" == "--deploy" ]]; then
  [[ "${ALLOW_TESTNET_WARP_DEPLOY:-}" == "1" ]] || die "set ALLOW_TESTNET_WARP_DEPLOY=1 to deploy testnet warp route"
  HL_KEY_ENV="HYP_""KEY"
  require_env "$HL_KEY_ENV"

  for name in BASE_MAINNET_RPC SENTRIX_MAINNET_RPC BASE_MAINNET_MAILBOX BASE_MAINNET_ISM SENTRIX_MAINNET_MAILBOX SENTRIX_MAINNET_ISM ALLOW_MAINNET_WARP_DEPLOY; do
    [[ -z "${!name:-}" ]] || die "$name must not be used in the testnet deployment path"
  done

  [[ "$ISM_LC" != "$NOOP_ISM_LC" ]] || die "SENTRIX_TESTNET_ISM is likely NoopIsm; funded/value bridge deployment is blocked"
  [[ "${SENTRIX_TESTNET_ISM_KIND:-}" == "MultisigIsm" || "${SENTRIX_TESTNET_ISM_KIND:-}" == "ProductionGradeIsm" ]] || die "SENTRIX_TESTNET_ISM_KIND must be MultisigIsm or ProductionGradeIsm for deploy"
  [[ "${BASE_SEPOLIA_ISM_KIND:-}" == "MultisigIsm" || "${BASE_SEPOLIA_ISM_KIND:-}" == "ProductionGradeIsm" ]] || die "BASE_SEPOLIA_ISM_KIND must be MultisigIsm or ProductionGradeIsm for deploy"
  assert_not_noop_ism_address BASE_SEPOLIA_ISM
fi

if [[ "$ISM_LC" == "$NOOP_ISM_LC" ]]; then
  warn "SENTRIX_TESTNET_ISM is likely NoopIsm / test-only. Do not use for funded bridge, real USDC, or mainnet."
fi

if command -v cast >/dev/null 2>&1; then
  : "${BASE_SEPOLIA_CHAIN_ID:=84532}"
  : "${SENTRIX_TESTNET_CHAIN_ID:=7120}"
  assert_chain_id "$BASE_SEPOLIA_RPC" "$BASE_SEPOLIA_CHAIN_ID"
  assert_chain_id "$SENTRIX_TESTNET_RPC" "$SENTRIX_TESTNET_CHAIN_ID"
  assert_erc20_decimals "$BASE_SEPOLIA_RPC" "$USDC" "6"
else
  warn "cast not found; skipped RPC chain-id and USDC decimals checks"
fi

cat <<EOF
network = testnet only
owner = SentrixSafe
owner address = $OWNER_ADDRESS
mailbox address = $SENTRIX_TESTNET_MAILBOX
ISM address = $SENTRIX_TESTNET_ISM
Base Sepolia USDC address = $USDC

NoopIsm is not production-grade. If the ISM warning appears above, this route
is limited to smoke tests / empty testnet validation and must not be used for
funded bridge testing.

Blocker checklist before funded/mainnet bridge:
- Replace NoopIsm with MultisigIsm or production-grade ISM.
- Keep route owner/admin as SentrixSafe, not deployer EOA.
- Run relayer and required validator/ISM agents 24/7.
- Enforce perTxCap, dailyCap, and totalMintCap on-chain or through reviewed route controls.
- Monitor Base locked collateral vs Sentrix sUSDC totalSupply.
- Mainnet remains blocked by default.
EOF
