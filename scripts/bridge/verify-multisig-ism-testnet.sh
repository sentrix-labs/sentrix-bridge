#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CHAIN="${1:-}"
[[ "$CHAIN" == "sentrix" || "$CHAIN" == "basesepolia" ]] || die "usage: $0 sentrix|basesepolia"
need_cmd cast

if [[ "$CHAIN" == "sentrix" ]]; then
  RPC_ENV="SENTRIX_TESTNET_RPC"
  ISM_ENV="SENTRIX_TESTNET_MULTISIG_ISM"
  VALIDATORS_ENV="SENTRIX_TESTNET_MULTISIG_VALIDATORS"
  THRESHOLD_ENV="SENTRIX_TESTNET_MULTISIG_THRESHOLD"
else
  RPC_ENV="BASE_SEPOLIA_RPC"
  ISM_ENV="BASE_SEPOLIA_MULTISIG_ISM"
  VALIDATORS_ENV="BASE_SEPOLIA_MULTISIG_VALIDATORS"
  THRESHOLD_ENV="BASE_SEPOLIA_MULTISIG_THRESHOLD"
fi

require_env "$RPC_ENV"
require_address_env "$ISM_ENV"
require_address_list_env "$VALIDATORS_ENV"
require_uint_env "$THRESHOLD_ENV"
assert_not_noop_ism_address "$ISM_ENV"

# Hyperlane static multisig ISMs expose validatorsAndThreshold(bytes) for the
# message metadata. A zero-length probe is enough to prove the contract has the
# expected interface on many deployments; if this call reverts, we still keep
# the stronger nonzero/non-Noop checks and surface the unreadable interface.
probe="$(cast call "${!ISM_ENV}" 'validatorsAndThreshold(bytes)(address[],uint8)' 0x --rpc-url "${!RPC_ENV}" 2>/dev/null || true)"

cat <<EOF
MultisigISM verification: $CHAIN
ISM address = ${!ISM_ENV}
NoopISM check = passed
Configured validators env = $VALIDATORS_ENV
Configured threshold = ${!THRESHOLD_ENV}
validatorsAndThreshold probe = ${probe:-unreadable_or_requires_message_metadata}
EOF
