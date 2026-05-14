#!/usr/bin/env bash
# Live-testnet fresh-user bridge verification.
#
# Walks the full SRX → wSRX → Hyperlane → Sepolia mint path with a brand
# new wallet, end-to-end. Prints each tx hash + the final wSRX balance on
# Sepolia.
#
# DO NOT run as part of CI — needs:
#   - real testnet SRX (faucet drip OK)
#   - real Sepolia ETH (Google Cloud faucet OK)
#   - operator-controlled relay wallet to call Mailbox.process(...)
#     unless validator+relayer agents are up
#
# Required env (read from .env.production or shell):
#   FRESH_USER_PK    fresh wallet privkey (testnet only — never mainnet)
#   RELAYER_PK       wallet with Sepolia ETH that calls Mailbox.process
#                    (post-MultisigIsm: omit; agents handle this)
#   SENTRIX_RPC      default https://testnet-rpc.sentrixchain.com
#   SEPOLIA_RPC      operator's Sepolia RPC (Infura/Alchemy URL)
#
# Reads constants from deployments/hyperlane-warp-route.json.
#
# Exit codes:
#   0 — full path verified, wSRX minted on Sepolia (only when steps 5+6
#       are performed by operator AND verified — currently never reached
#       automatically; script exits 4 after step 4 to flag manual follow-up)
#   2 — failure at a specific step (printed)
#   3 — config / env missing
#   4 — steps 1-4 broadcast OK, but mint verification (steps 5+6) NOT
#       run; operator must manually relay + verify before treating the
#       bridge as proven for this wallet

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WARP="$REPO_ROOT/deployments/hyperlane-warp-route.json"

[ -f "$WARP" ] || { echo "missing $WARP"; exit 3; }
command -v jq >/dev/null || { echo "jq required"; exit 3; }
command -v cast >/dev/null || { echo "cast (foundry) required"; exit 3; }

: "${FRESH_USER_PK:?FRESH_USER_PK required (testnet only)}"
: "${RELAYER_PK:?RELAYER_PK required for manual Mailbox.process step}"
SENTRIX_RPC="${SENTRIX_RPC:-https://testnet-rpc.sentrixchain.com}"
: "${SEPOLIA_RPC:?SEPOLIA_RPC required}"

WSRX=$(jq -r '.workingPath.components.WSRX_sentrix' "$WARP")
COLLATERAL=$(jq -r '.workingPath.components.HypERC20Collateral_sentrix' "$WARP")
HYPERC20_SEPOLIA=$(jq -r '.workingPath.components.HypERC20_wSRX_sepolia' "$WARP")
SENTRIX_MAILBOX=$(jq -r '.sentrixTestnet.config.mailbox' "$WARP")
SEPOLIA_MAILBOX=$(jq -r '.sepolia.config.mailbox' "$WARP")

FRESH_ADDR=$(cast wallet address --private-key "$FRESH_USER_PK")
SEPOLIA_DOMAIN=11155111

echo "=== fresh-user bridge verify ==="
echo "fresh wallet: $FRESH_ADDR"
echo "WSRX:         $WSRX"
echo "Collateral:   $COLLATERAL"
echo "HypERC20 Sep: $HYPERC20_SEPOLIA"
echo "Sentrix mbx:  $SENTRIX_MAILBOX"
echo "Sepolia mbx:  $SEPOLIA_MAILBOX"
echo

step() { echo; echo "--- $1 ---"; }

step "1. Verify fresh wallet has SRX (faucet drip first if 0)"
SRX_BAL=$(cast balance "$FRESH_ADDR" --rpc-url "$SENTRIX_RPC")
echo "Sentrix balance: $SRX_BAL wei"
if [ "$SRX_BAL" -lt 2000000000000000 ]; then
    echo "FAIL: fresh wallet needs ≥ 0.002 SRX (drip via testnet faucet first)"
    exit 2
fi

step "2. WSRX9.deposit{value: 1e15}() — wrap 0.001 SRX"
DEPOSIT_TX=$(cast send "$WSRX" "deposit()" --value 1000000000000000 \
    --rpc-url "$SENTRIX_RPC" --private-key "$FRESH_USER_PK" \
    --json | jq -r '.transactionHash')
echo "deposit tx: $DEPOSIT_TX"
WSRX_BAL=$(cast call "$WSRX" "balanceOf(address)(uint256)" "$FRESH_ADDR" --rpc-url "$SENTRIX_RPC")
echo "wSRX balance after wrap: $WSRX_BAL"
if [ "$WSRX_BAL" -lt 1000000000000000 ]; then
    echo "FAIL: WSRX deposit didn't credit (gate may be inactive — confirm via web3_clientVersion + chain height)"
    exit 2
fi

step "3. WSRX.approve(collateral, 1e15)"
APPROVE_TX=$(cast send "$WSRX" "approve(address,uint256)" "$COLLATERAL" 1000000000000000 \
    --rpc-url "$SENTRIX_RPC" --private-key "$FRESH_USER_PK" \
    --json | jq -r '.transactionHash')
echo "approve tx: $APPROVE_TX"

step "4. HypERC20Collateral.transferRemote(11155111, recipient32, 1e15)"
RECIPIENT_BYTES32=$(printf '0x000000000000000000000000%s' "${FRESH_ADDR#0x}" | tr 'A-Z' 'a-z')
BRIDGE_TX=$(cast send "$COLLATERAL" "transferRemote(uint32,bytes32,uint256)(bytes32)" \
    "$SEPOLIA_DOMAIN" "$RECIPIENT_BYTES32" 1000000000000000 \
    --rpc-url "$SENTRIX_RPC" --private-key "$FRESH_USER_PK" \
    --json | jq -r '.transactionHash')
echo "bridge tx: $BRIDGE_TX"

step "5. Wait + manual relay on Sepolia (skip if validator/relayer agents up)"
echo "OPERATOR ACTION (NOT YET RUN): extract message from Sentrix Mailbox Dispatch"
echo "event in $BRIDGE_TX, then call:"
echo "  $SEPOLIA_MAILBOX process(metadata=0x, message)  with RELAYER_PK"
echo "(Once MultisigIsm + relayer agent live, this step auto-fires. Today: manual.)"

step "6. Verify wSRX minted on Sepolia (operator follow-up)"
echo "OPERATOR ACTION (NOT YET RUN): after manual relay completes, run:"
echo "  cast call $HYPERC20_SEPOLIA 'balanceOf(address)(uint256)' $FRESH_ADDR --rpc-url \$SEPOLIA_RPC"
echo "Expected: 1000000000000000 (= 0.001 wSRX)"

echo
echo "=== broadcast complete; mint verification PENDING operator step 5+6 ==="
echo "Sentrix-side steps 1-4 broadcast OK (deposit + approve + transferRemote)."
echo "Sepolia-side steps 5+6 require operator action and were NOT performed by this"
echo "script. The end-to-end bridge is therefore NOT verified for this wallet yet."
echo
echo "Exiting 4 (broadcast-OK, verify-pending) so callers don't conflate this with"
echo "a full mint verification. Re-run with steps 5+6 done manually, then treat"
echo "this run as verified."
exit 4
