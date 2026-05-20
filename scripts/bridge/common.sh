#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SENTRIX_TESTNET_SAFE="0xc9D7a61D7C2F428F6A055916488041fD00532110"
SENTRIX_AUTHORITY_SIGNER_EOA="0xa25236925bc10954e0519731cc7ba97f4bb5714b"
SENTRIX_TESTNET_NOOP_ISM="0x28834AA535F3130f0F60571Ac7a813195aE56eC6"
BASE_SEPOLIA_USDC_CANONICAL="0x036CbD53842c5426634e7929541eC2318f3dCF7e"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

warn() {
  echo "WARNING: $*" >&2
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
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

require_address_list_env() {
  local name="$1"
  require_env "$name"
  IFS=',' read -r -a values <<< "${!name}"
  [[ "${#values[@]}" -gt 0 ]] || die "$name must contain at least one address"
  local seen=","
  for value in "${values[@]}"; do
    [[ "$value" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "$name contains non-address entry: $value"
    [[ "$(lower "$value")" != "0x0000000000000000000000000000000000000000" ]] || die "$name contains zero address"
    local lc
    lc="$(lower "$value")"
    [[ "$seen" != *",$lc,"* ]] || die "$name contains duplicate validator address: $value"
    seen="$seen$lc,"
  done
}

require_uint_env() {
  local name="$1"
  require_env "$name"
  [[ "${!name}" =~ ^[0-9]+$ ]] || die "$name must be an integer"
}

assert_not_noop_ism_address() {
  local name="$1"
  require_address_env "$name"
  [[ "$(lower "${!name}")" != "$(lower "$SENTRIX_TESTNET_NOOP_ISM")" ]] || die "$name is NoopIsm and is blocked"
}

validate_testnet_owner_policy() {
  require_address_env OWNER_ADDRESS
  require_address_env SENTRIX_SAFE_ADDRESS
  [[ "$(lower "$OWNER_ADDRESS")" == "$(lower "$SENTRIX_SAFE_ADDRESS")" ]] || die "OWNER_ADDRESS must equal SENTRIX_SAFE_ADDRESS"
  [[ "$(lower "$OWNER_ADDRESS")" == "$(lower "$SENTRIX_TESTNET_SAFE")" ]] || die "OWNER_ADDRESS must be Sentrix Testnet Safe $SENTRIX_TESTNET_SAFE"
  [[ "$(lower "$OWNER_ADDRESS")" != "$(lower "$SENTRIX_AUTHORITY_SIGNER_EOA")" ]] || die "OWNER_ADDRESS must be SentrixSafe, not authority signer EOA"
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
  if [[ "$env" == "testnet" ]]; then
    rm -rf "$out_dir/registry/chains/base" "$out_dir/registry/chains/sentrixmainnet"
  else
    rm -rf "$out_dir/registry/chains/basesepolia" "$out_dir/registry/chains/sentrixtestnet"
  fi
  find "$out_dir/registry" -type f -name '*.yaml' -print0 | while IFS= read -r -d '' file; do
    local rendered="$file.rendered"
    envsubst < "$file" > "$rendered"
    mv "$rendered" "$file"
  done

  envsubst < "$(warp_config "$env")" > "$out_dir/registry/deployments/warp_routes/${warp_id}-deploy.yaml"
}
