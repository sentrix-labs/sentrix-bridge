# `src/stablecoin/` — TESTNET REFERENCE ONLY · NOT CIRCLE BRIDGED USDC STANDARD COMPATIBLE

> **Stop. Do not use this for the canonical bridged USDC path.**

The contracts in this directory (`SentrixBridgedUSDC.sol` "sUSDC" +
`SourceChainVault.sol`) were an early PoC. They are kept as a reference for
the tooling shakedown (Foundry + OZ remap + role tests) but **must not become
Sentrix's canonical bridged USDC.**

## Why this PoC is INCOMPATIBLE with Circle Bridged USDC Standard

| Requirement | This PoC | Circle Standard | Compatible? |
|---|---|---|---|
| Solidity version | 0.8.33 | **0.6.12** (FiatToken canonical) | **NO** |
| Proxy pattern | None (non-upgradeable) | **AdminUpgradeabilityProxy** (Circle-specific) | **NO** |
| Roles | DEFAULT_ADMIN_ROLE, BRIDGE_MINTER_ROLE, MINTER_ADMIN_ROLE, PAUSER_ROLE (4) | `admin`, `owner`, `masterMinter`, `pauser`, `blacklister`, `rescuer` (6) + minters | **NO** |
| Mint pattern | Per-minter allowance cap (custom) | masterMinter → configureMinter(minter, allowance) | Conceptually similar, but role layout differs |
| Blacklist | None | Required (FiatToken built-in) | **NO** |
| Rescuer | None | Required (FiatToken built-in) | **NO** |
| Initialization | Constructor only | initialize / initializeV2 / initializeV2_1 / initializeV2_2 (proxy + implementation) | **NO** |
| `transferUSDCRoles(address)` | Not present | Required on bridge contract | **NO** |
| `burnLockedUSDC()` | Not present | Required on source bridge | **NO** |

## "Why not just refactor it?"

Per Circle's spec: **"the bridged token contract must not be upgraded to a new
or different implementation at any time, outside of subsequent FiatToken
versions authored by Circle."**

If we deploy `SentrixBridgedUSDC` (this PoC) to mainnet and then later try to
upgrade to Circle's FiatTokenV2_2, the token is **forever ineligible** for
the bridge-to-native upgrade path. Once deployed wrong, no retrofit.

## What replaces this

See `src/circle-bridged/` (new directory) and `docs/stablecoin/`:
- `CIRCLE_STANDARD_PLAN.md`
- `ARCHITECTURE.md`
- `MIGRATION_FROM_POC.md`

The canonical Sentrix bridged USDC will use **Circle's `circlefin/stablecoin-evm`
FiatTokenV2_2 unchanged** behind their `AdminUpgradeabilityProxy`, with
Sentrix-side source bridge that exposes Circle's required hooks.

## What this PoC IS useful for

- Foundry/remap/test framework shakedown (35/35 tests pass — verified tooling
  works on Sentrix's solc 0.8.33 + OZ 4.9.5 stack).
- Risk-register baseline (`docs/stablecoin/SECURITY_NOTES.md` is largely reusable
  with extensions for Circle-specific risks).
- Relayer/backend design (`docs/stablecoin/BRIDGE_RELAYER_DESIGN.md` is
  transport-agnostic and applies to the Circle-compatible build too).

## What to do with this folder

- Do not deploy to mainnet.
- Do not document publicly as the Sentrix bridged USDC. It is internal scaffolding.
- Keep until the Circle-compatible build replaces it functionally, then archive.

---

Last revised: 2026-05-14 — at the point of branching `feat/circle-bridged-usdc-standard`.
