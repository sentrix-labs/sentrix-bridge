#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MODE="${1:---dry-run}"
[[ "$MODE" == "--dry-run" || "$MODE" == "--deploy" ]] || die "usage: $0 --dry-run|--deploy"
WARP_ROUTE_ID="sUSDC/basesepolia-sentrixtestnet"

"$ROOT_DIR/scripts/bridge/check-chain-metadata.sh" testnet

if [[ "$MODE" == "--dry-run" ]]; then
  echo "Dry run command:"
  echo "scripts/bridge/deploy-base-usdc-warp-testnet.sh --deploy"
  echo
  echo "Review required before deploy:"
  echo "- Hyperlane CLI is installed globally or built with scripts/bridge/prepare-hyperlane-cli.sh."
  echo "- Base Sepolia mailbox/ISM env vars are set to real Hyperlane core addresses."
  echo "- Sentrix Testnet ISM is not NoopIsm for value-bearing tests."
  echo "- OWNER_ADDRESS and SENTRIX_SAFE_ADDRESS are multisig/SentrixSafe addresses."
  echo "- Deployment uses warp route id: $WARP_ROUTE_ID"
  exit 0
fi

[[ "${ALLOW_TESTNET_WARP_DEPLOY:-}" == "1" ]] || die "set ALLOW_TESTNET_WARP_DEPLOY=1 to deploy testnet warp route"
need_cmd envsubst
require_env HYP_KEY
require_env BASE_SEPOLIA_RPC
require_env SENTRIX_TESTNET_RPC
require_address_env BASE_SEPOLIA_MAILBOX
require_address_env BASE_SEPOLIA_ISM
require_address_env SENTRIX_TESTNET_ISM

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
prepare_rendered_warp_registry testnet "$TMP_DIR" "$WARP_ROUTE_ID"

HYP_KEY="$HYP_KEY" hyperlane_cli warp deploy \
  --registry "$TMP_DIR/registry" \
  --warp-route-id "$WARP_ROUTE_ID" \
  --yes \
  --verbosity debug
