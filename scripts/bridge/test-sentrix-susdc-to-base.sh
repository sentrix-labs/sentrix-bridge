#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ENVIRONMENT="$(env_name "${1:-testnet}")"
[[ "$ENVIRONMENT" == "testnet" ]] || die "mainnet reverse test blocked"
need_cmd jq

DEPLOYMENT="$(deployment_file testnet)"
BASE_ROUTER="$(jq -r '.source.router // empty' "$DEPLOYMENT")"
SENTRIX_ROUTER="$(jq -r '.destination.router // empty' "$DEPLOYMENT")"
[[ "$BASE_ROUTER" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "missing Base Sepolia collateral router in $DEPLOYMENT"
[[ "$SENTRIX_ROUTER" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "missing Sentrix Testnet synthetic router in $DEPLOYMENT"

cat <<EOF
Reverse route readiness ok for manual test:
1. On Sentrix, call transferRemote toward Base Sepolia domain 84532.
2. Confirm sUSDC is burned from sender on Sentrix.
3. Confirm Hyperlane message delivery to Base Sepolia.
4. Confirm USDC is released from Base router $BASE_ROUTER to recipient.

This script does not sign transactions or print keys.
EOF
