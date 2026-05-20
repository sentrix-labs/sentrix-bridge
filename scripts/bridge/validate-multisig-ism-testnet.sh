#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[[ "${1:---check}" == "--check" ]] || die "usage: $0 --check"

validate_testnet_owner_policy
require_env BASE_SEPOLIA_RPC
require_env SENTRIX_TESTNET_RPC
require_address_env SENTRIX_TESTNET_MAILBOX
require_address_env BASE_SEPOLIA_MAILBOX

if [[ -n "${SENTRIX_TESTNET_MULTISIG_ISM_FACTORY:-}" ]]; then
  require_address_env SENTRIX_TESTNET_MULTISIG_ISM_FACTORY
else
  warn "SENTRIX_TESTNET_MULTISIG_ISM_FACTORY is not set yet; deploy the Sentrix Testnet factory before deploying Sentrix MultisigISM"
fi
require_address_env BASE_SEPOLIA_MULTISIG_ISM_FACTORY
require_address_list_env SENTRIX_TESTNET_MULTISIG_VALIDATORS
require_address_list_env BASE_SEPOLIA_MULTISIG_VALIDATORS
require_uint_env SENTRIX_TESTNET_MULTISIG_THRESHOLD
require_uint_env BASE_SEPOLIA_MULTISIG_THRESHOLD

IFS=',' read -r -a sentrix_validators <<< "$SENTRIX_TESTNET_MULTISIG_VALIDATORS"
IFS=',' read -r -a base_validators <<< "$BASE_SEPOLIA_MULTISIG_VALIDATORS"
(( SENTRIX_TESTNET_MULTISIG_THRESHOLD > 0 )) || die "SENTRIX_TESTNET_MULTISIG_THRESHOLD must be > 0"
(( SENTRIX_TESTNET_MULTISIG_THRESHOLD <= ${#sentrix_validators[@]} )) || die "Sentrix threshold exceeds validator count"
(( BASE_SEPOLIA_MULTISIG_THRESHOLD > 0 )) || die "BASE_SEPOLIA_MULTISIG_THRESHOLD must be > 0"
(( BASE_SEPOLIA_MULTISIG_THRESHOLD <= ${#base_validators[@]} )) || die "Base Sepolia threshold exceeds validator count"

if [[ -n "${SENTRIX_TESTNET_MULTISIG_ISM:-}" ]]; then
  assert_not_noop_ism_address SENTRIX_TESTNET_MULTISIG_ISM
fi
if [[ -n "${BASE_SEPOLIA_MULTISIG_ISM:-}" ]]; then
  assert_not_noop_ism_address BASE_SEPOLIA_MULTISIG_ISM
fi

if command -v cast >/dev/null 2>&1; then
  assert_chain_id "$SENTRIX_TESTNET_RPC" "${SENTRIX_TESTNET_CHAIN_ID:-7120}"
  assert_chain_id "$BASE_SEPOLIA_RPC" "${BASE_SEPOLIA_CHAIN_ID:-84532}"
else
  warn "cast not found; skipped RPC chain-id checks"
fi

cat <<EOF
MultisigISM config ok: testnet only
Sentrix Testnet factory = ${SENTRIX_TESTNET_MULTISIG_ISM_FACTORY:-pending_deploy}
Sentrix Testnet validators = ${#sentrix_validators[@]}
Sentrix Testnet threshold = $SENTRIX_TESTNET_MULTISIG_THRESHOLD
Base Sepolia factory = $BASE_SEPOLIA_MULTISIG_ISM_FACTORY
Base Sepolia validators = ${#base_validators[@]}
Base Sepolia threshold = $BASE_SEPOLIA_MULTISIG_THRESHOLD
Route owner/admin = $OWNER_ADDRESS

No validator private keys are required by this validation script.
EOF
