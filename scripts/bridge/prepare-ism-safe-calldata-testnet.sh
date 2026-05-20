#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CHAIN="${1:-}"
ROUTER="${2:-}"
NEW_ISM="${3:-}"
[[ "$CHAIN" == "sentrix" || "$CHAIN" == "basesepolia" ]] || die "usage: $0 sentrix|basesepolia <router> <new-ism>"
[[ "$ROUTER" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "router must be an EVM address"
[[ "$NEW_ISM" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "new-ism must be an EVM address"
[[ "$(lower "$NEW_ISM")" != "$(lower "$SENTRIX_TESTNET_NOOP_ISM")" ]] || die "new ISM is NoopIsm and is blocked"
[[ "${ALLOW_TESTNET_ISM_SAFE_CALLDATA:-}" == "1" ]] || die "set ALLOW_TESTNET_ISM_SAFE_CALLDATA=1 to generate Safe calldata"
need_cmd cast

validate_testnet_owner_policy

CALLDATA="$(cast calldata 'setInterchainSecurityModule(address)' "$NEW_ISM")"

cat <<EOF
network = testnet only
chain = $CHAIN
safe owner = $SENTRIX_SAFE_ADDRESS
target router = $ROUTER
new ISM = $NEW_ISM

Submit this transaction through SentrixSafe, not a deployer EOA:
to: $ROUTER
value: 0
data: $CALLDATA

After Safe execution, run:
scripts/bridge/verify-ism-testnet.sh --check
EOF
