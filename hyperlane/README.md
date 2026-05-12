# Hyperlane Phase 0 — Parallel bridge path

Hyperlane v3 is **permissionless** — chain integration doesn't require approval from a central body (unlike LayerZero Labs). We can self-deploy + self-validate.

## Key facts

| Item | Value |
|---|---|
| License | Apache 2.0 (vs LZ's BUSL) |
| Domain ID | Convention is `chain_id` — Sentrix mainnet = 7119, testnet = 7120 |
| Solidity | `^0.8.33` (need solc 0.8.33; ours pins 0.8.24) |
| EVM version | Cancun (revm 37 ✓ supports) |
| Sources | `hyperlane-xyz/hyperlane-monorepo` (cloned at `hyperlane/hyperlane-monorepo/`, gitignored) |
| Architecture | Mailbox + Hook + ISM (Interchain Security Module) |

## Why parallel to LayerZero

LayerZero Labs application is a calendar block (2-6 weeks queue). Hyperlane has no equivalent gatekeeping — we deploy Mailbox + run our own validator agent immediately. Trade-off: Hyperlane TVL is ~10% of LZ's, smaller integration ecosystem, but **functional cross-chain demo can land in ~1-2 weeks** vs LZ's 4-8 week realistic timeline.

## Phase 0 status (2026-05-12, this commit)

- ✅ Cloned `hyperlane-monorepo`.
- ✅ Located `solidity/contracts/Mailbox.sol` + constructor signature.
- ⚠️ Build not yet working — needs yarn install setup similar to LayerZero (Hyperlane uses yarn workspaces; foundry remappings depend on `dependencies/` + `lib/` being populated).
- ⏸ Mailbox deploy on Sentrix Testnet — deferred to Phase 1.

## Phase 1 plan

1. `yarn install --mode=skip-build` inside `hyperlane-monorepo/`.
2. Resolve foundry remappings — likely similar PnP store dance to LayerZero.
3. Compile Mailbox + DefaultIsm (`solidity/contracts/isms/multisig/StaticMessageIdMultisigIsm.sol`) + Default Hook.
4. Deploy Mailbox on Sentrix Testnet via `cast send --create` (same RPC compat pattern as LZ).
5. Deploy MultisigIsm with single validator key (Sentrix-operated).
6. Run Hyperlane validator agent — likely in a docker container on operator infrastructure.
7. Deploy Mailbox on Sepolia testnet (their pre-deployed Mailbox at `0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766`).
8. Deploy reciprocal MultisigIsm on Sepolia configured to accept Sentrix-operated validator.
9. End-to-end test: send message Sentrix Testnet → Sepolia, verify delivery.

## Phase 2 plan

- Token wrapping (`HypERC20Collateral` for lock-and-mint SRX bridging).
- Submit to Hyperlane registry (`hyperlane-xyz/hyperlane-registry`) for ecosystem discoverability — not required, just helps.
- Coordinate with Hyperlane Discord for additional external validators if we want multi-sig security.

## License + attribution

This integration code is BUSL-1.1 matching the Sentrix chain repo. Hyperlane source remains Apache 2.0 in its own subtree.
