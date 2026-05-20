#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[[ "${1:---check}" == "--check" ]] || die "usage: $0 --check"
need_cmd jq
need_cmd cast

validate_testnet_owner_policy
require_env BASE_SEPOLIA_RPC
require_env SENTRIX_TESTNET_RPC
require_address_env SENTRIX_TESTNET_MAILBOX
require_address_env SENTRIX_TESTNET_ISM
require_address_env BASE_SEPOLIA_ISM
assert_not_noop_ism_address SENTRIX_TESTNET_ISM
assert_not_noop_ism_address BASE_SEPOLIA_ISM

SENTRIX_DEFAULT_ISM="$(cast call "$SENTRIX_TESTNET_MAILBOX" 'defaultIsm()(address)' --rpc-url "$SENTRIX_TESTNET_RPC" 2>/dev/null || true)"
if [[ -n "$SENTRIX_DEFAULT_ISM" ]]; then
  [[ "$(lower "$SENTRIX_DEFAULT_ISM")" != "$(lower "$SENTRIX_TESTNET_NOOP_ISM")" ]] || die "Sentrix Mailbox default ISM is NoopIsm"
fi

DEPLOYMENT="$(deployment_file testnet)"
BASE_ROUTER="$(jq -r '.source.router // empty' "$DEPLOYMENT")"
SENTRIX_ROUTER="$(jq -r '.destination.router // empty' "$DEPLOYMENT")"

check_router() {
  local label="$1"
  local router="$2"
  local rpc="$3"
  local expected_ism="$4"

  if [[ ! "$router" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    warn "$label router missing in deployment manifest; skipping route contract checks"
    return
  fi

  local ism owner
  ism="$(cast call "$router" 'interchainSecurityModule()(address)' --rpc-url "$rpc" 2>/dev/null || true)"
  [[ -n "$ism" ]] || die "$label router ISM unreadable"
  [[ "$(lower "$ism")" == "$(lower "$expected_ism")" ]] || die "$label router ISM mismatch: expected $expected_ism got $ism"
  [[ "$(lower "$ism")" != "$(lower "$SENTRIX_TESTNET_NOOP_ISM")" ]] || die "$label router still uses NoopIsm"

  owner="$(cast call "$router" 'owner()(address)' --rpc-url "$rpc" 2>/dev/null || true)"
  [[ -n "$owner" ]] || die "$label router owner unreadable"
  [[ "$(lower "$owner")" == "$(lower "$SENTRIX_TESTNET_SAFE")" ]] || die "$label router owner must be SentrixSafe; got $owner"
  [[ "$(lower "$owner")" != "$(lower "$SENTRIX_AUTHORITY_SIGNER_EOA")" ]] || die "$label router owner is authority signer EOA"
}

check_router "Base Sepolia" "$BASE_ROUTER" "$BASE_SEPOLIA_RPC" "$BASE_SEPOLIA_ISM"
check_router "Sentrix Testnet" "$SENTRIX_ROUTER" "$SENTRIX_TESTNET_RPC" "$SENTRIX_TESTNET_ISM"

cat <<EOF
ISM verification ok: testnet only
Sentrix Mailbox = $SENTRIX_TESTNET_MAILBOX
Sentrix Mailbox default ISM = ${SENTRIX_DEFAULT_ISM:-unreadable_or_not_checked}
Configured Sentrix route ISM = $SENTRIX_TESTNET_ISM
Configured Base Sepolia route ISM = $BASE_SEPOLIA_ISM
Required route owner = $SENTRIX_TESTNET_SAFE
EOF
