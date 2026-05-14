# Migration from sUSDC PoC to Circle Bridged USDC Standard

## TL;DR

The sUSDC PoC in `src/stablecoin/` is **not** Sentrix's canonical bridged
USDC. It is incompatible with Circle's Bridged USDC Standard and was never
intended to be the production token.

The canonical path lives at `src/circle-bridged/`, uses
Circle's FiatTokenV2_2 unchanged on Sentrix, and a Sentrix-built upgradeable
source bridge on Ethereum / Sepolia.

This doc explains what's reusable and what isn't.

## Why the sUSDC PoC must be replaced

| Aspect | sUSDC PoC (`src/stablecoin/`) | Circle Standard requirement |
|---|---|---|
| Solidity version | 0.8.33 | 0.6.12 (FiatToken canonical) |
| Proxy | None (non-upgradeable) | AdminUpgradeabilityProxy (Circle-specific) |
| Roles | 4 custom (admin/minter/minterAdmin/pauser) | 6 Circle (admin/owner/masterMinter/pauser/blacklister/rescuer) + configurable minters |
| Mint pattern | Per-minter `mintAllowance` cap | masterMinter→configureMinter(minter, allowance) |
| Blacklist | Absent | Required (FiatToken built-in) |
| Rescuer | Absent | Required |
| Initialization | Constructor | `initialize` + `initializeV2` + `initializeV2_1` + `initializeV2_2` on proxy AND impl |
| Upgrade path to Circle native | Forfeited if deployed | Preserved if standard followed |

Per Circle's spec (`bridged_USDC_standard.md`): "Bridged USDC Standard must
be incorporated PRIOR to deploying a bridged USDC token contract as it
cannot be retroactively applied." Deploying sUSDC to mainnet would
**permanently forfeit** the future Circle handoff path for that token.

## What from the PoC is reusable

| Component | Reusable? | How |
|---|---|---|
| `docs/stablecoin/BRIDGE_RELAYER_DESIGN.md` | YES | Off-chain relayer + monitoring design is transport-agnostic. Applies to the Circle build verbatim. |
| `docs/stablecoin/SECURITY_NOTES.md` (PoC) | PARTIAL | Risk register translates; SECURITY_MODEL.md (this doc set) extends with Circle-specific risks. PoC version retained for reference. |
| `lib/openzeppelin-contracts-v4` + `lib/openzeppelin-contracts-upgradeable` + `lib/forge-std` | YES | Required for the source bridge (OZ upgradeable). |
| `remappings.txt` (fixed OZ paths) | YES | The repair done during PoC setup is required for the new build too. |
| `watcher-rs/` + `api-rs/` + `subgraph/` | YES | Bridge monitoring infrastructure extends to the Circle-compatible path. |
| `scripts/DeployMultisigIsm.s.sol` | YES | Reused for Phase 2 Hyperlane MultisigIsm setup. |
| Existing Hyperlane testnet deployment under `deployments/` | YES | Foundation for Phase 2 wiring. |
| Foundry config (`foundry.toml`) | YES | Solc 0.8.33 default works for our 0.8 source bridge. Circle's FiatToken builds separately at 0.6.12 in `circlefin/stablecoin-evm`. |
| Test framework patterns (vm.prank, proxy initialization, role grants) | YES | Translated to `test/circle-bridged/`. |

## What from the PoC is NOT reusable

| Component | Replaced by |
|---|---|
| `src/stablecoin/SentrixBridgedUSDC.sol` | FiatTokenV2_2 from `circlefin/stablecoin-evm` (deployed separately via Hardhat) |
| `src/stablecoin/SourceChainVault.sol` | `src/circle-bridged/source/SentrixUSDCSourceBridge.sol` (upgradeable + Circle hooks) |
| `src/interfaces/ISentrixBridgedUSDC.sol` | `src/circle-bridged/interfaces/IFiatToken.sol` |
| `src/interfaces/ISourceChainVault.sol` | `src/circle-bridged/interfaces/ICircleBridgedUSDCSource.sol` + `ICircleBridgedUSDCPausable.sol` |
| `test/stablecoin/*` | `test/circle-bridged/*` |
| `scripts/stablecoin/Deploy*.s.sol` | New scripts under `scripts/circle-bridged/` (pending) + Circle's Hardhat scripts for FiatToken |
| `docs/stablecoin/README.md` (PoC) | `docs/stablecoin/CIRCLE_STANDARD_PLAN.md` |

## Migration steps

### Already done in this branch (`feat/circle-bridged-usdc-standard`)

1. Marked `src/stablecoin/` deprecated (see `src/stablecoin/DEPRECATED.md`).
2. Created `src/circle-bridged/` with:
   - `interfaces/ICircleBridgedUSDCSource.sol` (mandates Circle hooks)
   - `interfaces/ICircleBridgedUSDCPausable.sol`
   - `interfaces/IFiatToken.sol` (ABI to talk to Circle's FiatToken)
   - `source/SentrixUSDCSourceBridge.sol` (upgradeable, Circle-compatible source bridge)
   - `mocks/MockUSDC.sol`
3. Created `test/circle-bridged/SentrixUSDCSourceBridge.t.sol` (20 tests, all pass).
4. Wrote new docs: `CIRCLE_STANDARD_PLAN.md`, `ARCHITECTURE.md`,
   `HYPERLANE_EVALUATION.md`, `DEPLOYMENT_RUNBOOK.md`, `SECURITY_MODEL.md`,
   this doc, and `CIRCLE_HANDOFF_READINESS.md`.

### Still pending (Phase 1B work)

1. Deploy scripts for `SentrixUSDCSourceBridge` (proxy + impl + initialize).
2. Deploy scripts for FiatTokenV2_2 + AdminUpgradeabilityProxy on Sentrix
   testnet (using Circle's Hardhat repo, NOT this Foundry repo).
3. Integration tests that deploy a mock FiatToken on a forked Sentrix testnet
   and exercise the full deposit→mint→burn→release loop.
4. `watcher-rs` extension to monitor the Circle-built bridge (`totalLocked`
   vs `totalSupply` reconciliation, reorg watcher, dedup table).
5. Provision operator EOAs on Sepolia + Sentrix testnet (HSM-backed). Multisig deployment is Phase 3b graduation item per SINGLE_SIG_BOOTSTRAP_POLICY.md.

### Phase 2 work (Hyperlane wiring)

6. Inherit `SentrixUSDCSourceBridge` from Hyperlane's `MailboxClient`.
7. Implement `dispatch` on outbound (deposit) and `handle` on inbound (release).
8. Deploy HypFiatToken on Sentrix.
9. masterMinter calls `configureMinter(HypFiatToken_address, cap)` on FiatToken.
10. Set ISM = MultisigIsm with operator validators.
11. Enroll remote routers.

### Phase 3 (mainnet)

12. External audit.
13. Decentralize MultisigIsm validator set.
14. Mainnet deploy (mirror of testnet).

### Phase 4 (Circle handoff, if/when approved)

15. Circle's process per `CIRCLE_STANDARD_PLAN.md` §"Phase 4".

## Operator decision: keep or delete sUSDC PoC?

**Recommendation: keep until Phase 1B testnet deploy proves the new path.**

After testnet deploy of the Circle-compatible path is healthy, the sUSDC
PoC can be deleted (or moved to an `archive/` folder for historical
reference). The tests and risk register learnings have already been
transferred to the new path; the PoC contracts add no further value.
