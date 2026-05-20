#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ENVIRONMENT="$(env_name "${1:-}")"
need_cmd jq

jq '{
  name,
  status,
  source: {chain, chainId, collateralToken, router, mailbox},
  destination: {chain, chainId, syntheticTokenName, syntheticTokenSymbol, syntheticDecimals, router, mailbox},
  security,
  caps
}' "$(deployment_file "$ENVIRONMENT")"
