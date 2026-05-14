#!/usr/bin/env bash
# Sanity check: fail (exit 2) if any deployment in deployments/*.json
# references NoopIsm without an explicit `unsafe_demo: true` flag.
#
# Designed for CI gating + pre-commit. Reads only local JSON, no chain RPC.
#
# Convention:
#   "interchainSecurityModule": "0x...NoopIsm address..."
# is OK only inside an object that ALSO has:
#   "unsafe_demo": true
# anywhere as a sibling key. Otherwise this script flags the route as a
# production-shape config that's still pointing at NoopIsm.
#
# Add `"unsafe_demo": true` to the ISM-bearing object to suppress.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_DIR="$REPO_ROOT/deployments"

if [ ! -d "$DEPLOY_DIR" ]; then
    echo "check-noopism: no deployments/ dir at $DEPLOY_DIR — nothing to check"
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "check-noopism: jq required but not found in PATH"
    exit 1
fi

failures=0

# Extract every NoopIsm address occurrence + its parent object's
# unsafe_demo flag if any. Recurses into deployments/ subdirs so per-network
# files (e.g. deployments/sepolia/foo.json) are also covered.
while IFS= read -r -d '' f; do
    # Find every key whose value mentions "NoopIsm" (case-insensitive) in
    # either the address comment or the address itself. The deployments
    # JSON marks NoopIsm references in comments / labels.
    #
    # Fail closed on parse errors: a malformed JSON file should not be
    # silently treated as "no NoopIsm refs". Capture stderr + exit code.
    jq_err=$(mktemp)
    if ! matches=$(jq -c '
        .. | objects | select(
            (.note? // "" | test("NoopIsm"; "i"))
            or (.label? // "" | test("NoopIsm"; "i"))
            or (.ism? // "" | test("NoopIsm"; "i"))
            or (.defaultIsm? // "" | test("NoopIsm"; "i"))
            or (.interchainSecurityModule? // "" | test("NoopIsm"; "i"))
        )
    ' "$f" 2>"$jq_err"); then
        echo ""
        echo "FAIL: ${f#$REPO_ROOT/} — jq parse error:"
        sed 's/^/    /' "$jq_err"
        failures=$((failures + 1))
        rm -f "$jq_err"
        continue
    fi
    rm -f "$jq_err"

    if [ -z "$matches" ]; then
        continue
    fi

    while IFS= read -r m; do
        unsafe_demo=$(echo "$m" | jq -r '.unsafe_demo // false')
        if [ "$unsafe_demo" != "true" ]; then
            echo ""
            echo "FAIL: ${f#$REPO_ROOT/} — NoopIsm reference without unsafe_demo: true"
            echo "  object: $(echo "$m" | jq -c '. | with_entries(select(.value | type != "object" and type != "array"))')"
            failures=$((failures + 1))
        fi
    done <<< "$matches"
done < <(find "$DEPLOY_DIR" -type f -name '*.json' -print0)

if [ "$failures" -gt 0 ]; then
    echo ""
    echo "check-noopism: $failures unsafe NoopIsm reference(s) found"
    echo "  — add 'unsafe_demo: true' to the parent object to suppress (testnet/demo only)"
    echo "  — OR swap to MultisigIsm per docs/multisigism-setup.md"
    exit 2
fi

echo "check-noopism: OK — no unguarded NoopIsm references"
exit 0
