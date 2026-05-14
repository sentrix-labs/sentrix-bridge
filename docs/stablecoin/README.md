# Stablecoin docs index

> **NOT official Circle USDC.** Circle has not approved Sentrix.
> This directory holds the canonical Circle Bridged USDC Standard plan +
> the legacy sUSDC PoC reference (deprecated, testnet-only).

## Canonical direction (read these)

| Doc | Purpose |
|---|---|
| [`CIRCLE_STANDARD_PLAN.md`](CIRCLE_STANDARD_PLAN.md) | Phased plan for Circle Bridged USDC Standard compliance |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Contract layout, role topology, flows |
| [`BOOTSTRAP_ROLE_HOLDER.md`](BOOTSTRAP_ROLE_HOLDER.md) | Canonical bootstrap policy — SentrixSafe |
| [`HYPERLANE_EVALUATION.md`](HYPERLANE_EVALUATION.md) | Phase 2 transport assessment (HypFiatToken) |
| [`DEPLOYMENT_RUNBOOK.md`](DEPLOYMENT_RUNBOOK.md) | Step-by-step deploy procedure |
| [`SECURITY_MODEL.md`](SECURITY_MODEL.md) | Risk register (20 risks) — canonical |
| [`MIGRATION_FROM_POC.md`](MIGRATION_FROM_POC.md) | What's reused / replaced from the sUSDC PoC |
| [`CIRCLE_HANDOFF_READINESS.md`](CIRCLE_HANDOFF_READINESS.md) | Pre-Circle-engagement checklist |

## Legacy / reference (do not deploy as canonical)

| Doc | Status |
|---|---|
| [`BRIDGE_RELAYER_DESIGN.md`](BRIDGE_RELAYER_DESIGN.md) | Reused (transport-agnostic backend design) |
| [`SECURITY_NOTES.md`](SECURITY_NOTES.md) | sUSDC PoC risk register — superseded by `SECURITY_MODEL.md` for Circle Standard |
| [`SINGLE_SIG_BOOTSTRAP_POLICY.md`](SINGLE_SIG_BOOTSTRAP_POLICY.md) | Deprecated stub — pointer to `BOOTSTRAP_ROLE_HOLDER.md` |

The sUSDC PoC contracts at `src/stablecoin/` are kept as a tooling-shakedown
reference (Foundry + OZ remap + role tests). They are NOT Sentrix's canonical
bridged USDC. See `src/stablecoin/DEPRECATED.md` for the banner.

## Quick orientation

1. **What this branch ships**: scaffold for Circle Bridged USDC Standard compliance.
   - Token contract: **Circle's `FiatTokenV2_2` unchanged** (solc 0.6.12, `AdminUpgradeabilityProxy`)
   - Source bridge contract: `src/circle-bridged/source/SentrixUSDCSourceBridge.sol` (upgradeable, Circle hooks)
   - Tests: `test/circle-bridged/` (20 tests passing)
   - Naming target: "Bridged USDC (Sentrix)" / `USDC.e`
2. **Bootstrap role holder**: `SentrixSafe` (Sentrix Labs' own Safe-like contract from `sentrix-labs/canonical-contracts`).
   - Sentrix mainnet: `0x6272dC0C842F05542f9fF7B5443E93C0642a3b26`
   - Sentrix testnet: `0xc9D7a61D7C2F428F6A055916488041fD00532110`
   - Source-chain Safe: NOT yet deployed (Sepolia first per `BOOTSTRAP_ROLE_HOLDER.md`)
   - Currently 1-of-1; expand threshold N-of-M when co-signers recruited
3. **What is NOT in this branch**:
   - Deploy scripts for the source bridge proxy (Phase 1B)
   - Hyperlane Mailbox integration (Phase 2)
   - `watcher-rs` extension for the new bridge (Phase 1B)
   - Any mainnet deploy
4. **Disclaimers**:
   - NOT official Circle USDC.
   - Circle has not approved Sentrix.
   - Circle has the option, not the obligation, to upgrade.
   - Phase 1 + Phase 2 are explicitly trusted-party (single source of truth = SentrixSafe → Authority).

## Tests

```bash
cd /home/sentriscloud/sentrix-bridge

# Circle Standard scaffold (canonical)
forge test --match-path "test/circle-bridged/*" --skip "DeployMultisigIsm" --skip "DeployLZ"
# Expected: 20 tests passed

# Legacy sUSDC PoC (testnet reference only)
forge test --match-path "test/stablecoin/*" --skip "DeployMultisigIsm" --skip "DeployLZ"
# Expected: 35 tests passed
```

## Open the PR

Branch is pushed to `origin/feat/circle-bridged-usdc-standard`. Open the PR
when ready for review:

```bash
unset GH_TOKEN && gh pr create \
  --repo sentrix-labs/sentrix-bridge \
  --base main \
  --head feat/circle-bridged-usdc-standard \
  --title "feat(stablecoin): Circle Bridged USDC Standard scaffold + SentrixSafe canonical" \
  --body-file docs/stablecoin/CIRCLE_STANDARD_PLAN.md
```
