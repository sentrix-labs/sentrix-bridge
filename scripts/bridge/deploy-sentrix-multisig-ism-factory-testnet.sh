#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MODE="${1:---dry-run}"
[[ "$MODE" == "--dry-run" || "$MODE" == "--deploy" ]] || die "usage: $0 --dry-run|--deploy"

require_env SENTRIX_TESTNET_RPC

if [[ "$MODE" == "--dry-run" ]]; then
  echo "Dry run only. Review then run:"
  echo "ALLOW_TESTNET_MULTISIG_ISM_DEPLOY=1 $0 --deploy"
  echo
  echo "Will deploy StaticMessageIdMultisigIsmFactory on Sentrix Testnet only."
  echo "Required deploy env: HYP_KEY present in shell/local secret source."
  exit 0
fi

[[ "${ALLOW_TESTNET_MULTISIG_ISM_DEPLOY:-}" == "1" ]] || die "set ALLOW_TESTNET_MULTISIG_ISM_DEPLOY=1"
[[ -z "${ALLOW_MAINNET_ISM_DEPLOY:-}" ]] || die "mainnet ISM deploy guard must not be set"
HL_KEY_ENV="HYP_""KEY"
require_env "$HL_KEY_ENV"

DEPLOYER_PK="${!HL_KEY_ENV}" forge script scripts/DeployMessageIdMultisigIsmFactory.s.sol:DeployMessageIdMultisigIsmFactory \
  --rpc-url "$SENTRIX_TESTNET_RPC" \
  --broadcast \
  --legacy
