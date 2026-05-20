#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MONO_DIR="$ROOT_DIR/hyperlane/hyperlane-monorepo"
CLI_DIR="$MONO_DIR/typescript/cli"
[[ -d "$CLI_DIR" ]] || die "vendored Hyperlane CLI not found at $CLI_DIR"
need_cmd corepack

if [[ -f "$CLI_DIR/dist/cli.js" ]]; then
  echo "Hyperlane CLI already built: $CLI_DIR/dist/cli.js"
  exit 0
fi

echo "Installing/building vendored Hyperlane workspace. This is local build output and does not deploy anything."
corepack pnpm@10.30.2 --dir "$MONO_DIR" install --frozen-lockfile
corepack pnpm@10.30.2 --dir "$MONO_DIR" build --filter @hyperlane-xyz/cli...
