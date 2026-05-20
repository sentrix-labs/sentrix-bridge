#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

umask 077

if ! git check-ignore -q .env; then
  echo "ERROR: .env is not ignored; refusing to generate wallet" >&2
  exit 1
fi

command -v openssl >/dev/null 2>&1 || {
  echo "ERROR: missing required command: openssl" >&2
  exit 1
}
command -v cast >/dev/null 2>&1 || {
  echo "ERROR: missing required command: cast" >&2
  exit 1
}

PK="0x$(openssl rand -hex 32)"
ADDR="$(cast wallet address --private-key "$PK")"

touch .env
chmod 600 .env

TMP=".env.tmp.$$"
awk '
  BEGIN { skip = 0 }
  /^[[:space:]]*HYP_KEY=/ { next }
  /^[[:space:]]*HYP_DEPLOYER_ADDRESS=/ { next }
  { print }
' .env > "$TMP"

{
  printf '\n# Local Hyperlane deployer. Do not commit this file.\n'
  printf 'HYP_KEY=%s\n' "$PK"
  printf 'HYP_DEPLOYER_ADDRESS=%s\n' "$ADDR"
} >> "$TMP"

mv "$TMP" .env
chmod 600 .env

unset PK

echo "HYP deployer address: $ADDR"
echo "Wrote HYP_KEY and HYP_DEPLOYER_ADDRESS to local .env"
echo "Fund this address with Sentrix Testnet SRX and Base Sepolia ETH before deployment."
