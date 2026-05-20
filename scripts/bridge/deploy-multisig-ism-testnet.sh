#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CHAIN="${1:-}"
MODE="${2:---dry-run}"
[[ "$CHAIN" == "sentrix" || "$CHAIN" == "basesepolia" ]] || die "usage: $0 sentrix|basesepolia --dry-run|--deploy"
[[ "$MODE" == "--dry-run" || "$MODE" == "--deploy" ]] || die "usage: $0 sentrix|basesepolia --dry-run|--deploy"

if [[ "$CHAIN" == "sentrix" ]]; then
  RPC_ENV="SENTRIX_TESTNET_RPC"
  FACTORY_ENV="SENTRIX_TESTNET_MULTISIG_ISM_FACTORY"
  VALIDATORS_ENV="SENTRIX_TESTNET_MULTISIG_VALIDATORS"
  THRESHOLD_ENV="SENTRIX_TESTNET_MULTISIG_THRESHOLD"
  BROADCAST_ARGS=(--legacy)
else
  RPC_ENV="BASE_SEPOLIA_RPC"
  FACTORY_ENV="BASE_SEPOLIA_MULTISIG_ISM_FACTORY"
  VALIDATORS_ENV="BASE_SEPOLIA_MULTISIG_VALIDATORS"
  THRESHOLD_ENV="BASE_SEPOLIA_MULTISIG_THRESHOLD"
  BROADCAST_ARGS=()
fi

if [[ "$MODE" == "--dry-run" ]]; then
  echo "Dry run only. Review then run:"
  echo "ALLOW_TESTNET_MULTISIG_ISM_DEPLOY=1 $0 $CHAIN --deploy"
  echo
  echo "Required env:"
  echo "- $RPC_ENV"
  echo "- $FACTORY_ENV"
  echo "- $VALIDATORS_ENV"
  echo "- $THRESHOLD_ENV"
  echo "- HYP_KEY (deploy mode only, local shell env only)"
  echo
  if [[ -n "${!FACTORY_ENV:-}" ]]; then
    echo "Will deploy StaticMessageIdMultisigIsm via factory ${!FACTORY_ENV}"
  else
    echo "Factory env is not set yet."
  fi
  echo "Validators env: $VALIDATORS_ENV"
  echo "Threshold env: $THRESHOLD_ENV=${!THRESHOLD_ENV:-unset}"
  echo "Deploy-only mode: SWAP_TARGETS is intentionally not set"
  exit 0
fi

[[ "${ALLOW_TESTNET_MULTISIG_ISM_DEPLOY:-}" == "1" ]] || die "set ALLOW_TESTNET_MULTISIG_ISM_DEPLOY=1"
require_env "$RPC_ENV"
require_address_env "$FACTORY_ENV"
require_address_list_env "$VALIDATORS_ENV"
require_uint_env "$THRESHOLD_ENV"
HL_KEY_ENV="HYP_""KEY"
require_env "$HL_KEY_ENV"
[[ -z "${ALLOW_MAINNET_WARP_DEPLOY:-}" ]] || die "mainnet deploy guard must not be set for testnet MultisigISM deployment"
validate_testnet_owner_policy

MULTISIG_ISM_FACTORY="${!FACTORY_ENV}" \
MULTISIG_ISM_VALIDATORS="${!VALIDATORS_ENV}" \
MULTISIG_ISM_THRESHOLD="${!THRESHOLD_ENV}" \
DEPLOY_ONLY=1 \
DEPLOYER_PK="${!HL_KEY_ENV}" \
forge script scripts/DeployMultisigIsm.s.sol:DeployMultisigIsm \
  --rpc-url "${!RPC_ENV}" \
  --broadcast \
  "${BROADCAST_ARGS[@]}"
