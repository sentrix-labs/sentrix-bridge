#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

env_name() {
  case "${1:-}" in
    testnet|mainnet) printf '%s\n' "$1" ;;
    *) die "usage: $0 testnet|mainnet [args]" ;;
  esac
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "missing env var: $name"
}

require_address_env() {
  local name="$1"
  require_env "$name"
  [[ "${!name}" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "$name is not an EVM address"
}

assert_chain_id() {
  local rpc="$1"
  local expected="$2"
  local actual
  actual="$(cast chain-id --rpc-url "$rpc" 2>/dev/null || true)"
  [[ "$actual" == "$expected" ]] || die "chain id mismatch for $rpc: expected $expected, got ${actual:-unreachable}"
}

assert_erc20_decimals() {
  local rpc="$1"
  local token="$2"
  local expected="$3"
  local actual
  actual="$(cast call "$token" 'decimals()(uint8)' --rpc-url "$rpc" 2>/dev/null || true)"
  [[ "$actual" == "$expected" ]] || die "decimals mismatch for $token: expected $expected, got ${actual:-unreadable}"
}

warp_config() {
  local env="$1"
  printf '%s/hyperlane/warp-routes/base-usdc-sentrix-susdc/%s.yaml\n' "$ROOT_DIR" "$env"
}

deployment_file() {
  local env="$1"
  printf '%s/deployments/base-usdc-susdc-%s.json\n' "$ROOT_DIR" "$env"
}

hyperlane_cli() {
  if command -v hyperlane >/dev/null 2>&1; then
    hyperlane "$@"
    return
  fi

  local cli_dir="$ROOT_DIR/hyperlane/hyperlane-monorepo/typescript/cli"
  if [[ -f "$cli_dir/dist/cli.js" ]]; then
    corepack pnpm@10.30.2 --dir "$cli_dir" hyperlane "$@"
    return
  fi

  die "missing Hyperlane CLI. Install @hyperlane-xyz/cli or run scripts/bridge/prepare-hyperlane-cli.sh"
}

prepare_rendered_warp_registry() {
  local env="$1"
  local out_dir="$2"
  local warp_id="$3"

  mkdir -p "$out_dir/registry" "$out_dir/registry/deployments/warp_routes/${warp_id%/*}"
  cp -R "$ROOT_DIR/hyperlane/registry/chains" "$out_dir/registry/"
  find "$out_dir/registry" -type f -name '*.yaml' -print0 | while IFS= read -r -d '' file; do
    local rendered="$file.rendered"
    envsubst < "$file" > "$rendered"
    mv "$rendered" "$file"
  done

  envsubst < "$(warp_config "$env")" > "$out_dir/registry/deployments/warp_routes/${warp_id}-deploy.yaml"
}
