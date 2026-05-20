#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ENVIRONMENT="$(env_name "${1:-}")"

check_file() {
  local file="$1"
  [[ -f "$file" ]] || die "missing metadata file: $file"
}

if [[ "$ENVIRONMENT" == "testnet" ]]; then
  check_file "$ROOT_DIR/hyperlane/registry/chains/basesepolia/metadata.yaml"
  check_file "$ROOT_DIR/hyperlane/registry/chains/basesepolia/addresses.yaml"
  check_file "$ROOT_DIR/hyperlane/registry/chains/sentrixtestnet/metadata.yaml"
  grep -q 'chainId: 84532' "$ROOT_DIR/hyperlane/registry/chains/basesepolia/metadata.yaml" || die "Base Sepolia chainId mismatch"
  grep -q 'chainId: 7120' "$ROOT_DIR/hyperlane/registry/chains/sentrixtestnet/metadata.yaml" || die "Sentrix Testnet chainId mismatch"
  grep -q 'staticMessageIdMultisigIsmFactory: "0xfc6e546510dC9d76057F1f76633FCFfC188CB213"' "$ROOT_DIR/hyperlane/registry/chains/basesepolia/addresses.yaml" || die "Base Sepolia MultisigISM factory mismatch"
  grep -q 'mailbox: "0x9741D99270aF14D4baca0e387B6ac0500b9a288F"' "$ROOT_DIR/hyperlane/registry/chains/sentrixtestnet/addresses.yaml" || die "Sentrix Testnet mailbox mismatch"
else
  check_file "$ROOT_DIR/hyperlane/registry/chains/base/metadata.yaml"
  check_file "$ROOT_DIR/hyperlane/registry/chains/sentrixmainnet/metadata.yaml"
  grep -q 'chainId: 8453' "$ROOT_DIR/hyperlane/registry/chains/base/metadata.yaml" || die "Base mainnet chainId mismatch"
  grep -q '\${SENTRIX_MAINNET_CHAIN_ID}' "$ROOT_DIR/hyperlane/registry/chains/sentrixmainnet/metadata.yaml" || true
fi

grep -q 'decimals: 6' "$(warp_config "$ENVIRONMENT")" || die "warp config must preserve 6 decimals"
echo "metadata ok: $ENVIRONMENT"
