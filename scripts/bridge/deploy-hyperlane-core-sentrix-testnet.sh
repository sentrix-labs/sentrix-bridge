#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MODE="${1:---plan}"
[[ "$MODE" == "--plan" || "$MODE" == "--deploy" ]] || die "usage: $0 --plan|--deploy"

if [[ "$MODE" == "--plan" ]]; then
  cat <<'PLAN'
Sentrix Testnet Hyperlane core status:
- Mailbox exists in deployments/hyperlane-testnet.json.
- MerkleTreeHook exists in deployments/hyperlane-testnet.json.
- Current default ISM is NoopIsm and is unsafe for value.

Safe plan:
1. Deploy MultisigIsm for Sentrix Testnet with independent validator keys.
2. Configure Mailbox default ISM or per-route ISM to MultisigIsm.
3. Deploy or verify ValidatorAnnounce and gas/default hook addresses.
4. Run validator + relayer agents.
5. Re-run Base USDC Warp dry-run and verify route enrollment.

This script will not deploy unless called with --deploy and ALLOW_SENTRIX_TESTNET_CORE_DEPLOY=1.
PLAN
  exit 0
fi

[[ "${ALLOW_SENTRIX_TESTNET_CORE_DEPLOY:-}" == "1" ]] || die "set ALLOW_SENTRIX_TESTNET_CORE_DEPLOY=1 to deploy core"
need_cmd hyperlane
require_env SENTRIX_TESTNET_RPC
require_address_env OWNER_ADDRESS

die "deployment intentionally not automated yet; use Hyperlane CLI with reviewed core config and commit resulting addresses"
