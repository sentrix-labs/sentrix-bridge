# sentrix-bridge

Cross-chain bridge integration for Sentrix Chain. Two bridge protocols live in parallel:

- **Hyperlane v3** — message-passing + warp routes (token bridging). First working route: **Sentrix Testnet ↔ Sepolia**. Status: protocol layer verified, production security pending.
- **LayerZero V2** — endpoint stack deployed on Sentrix Testnet, awaiting LayerZero Labs chain assignment + production DVN/Executor wiring.

> **Safety status — TESTNET ONLY.** Both routes are demonstration deployments. The Hyperlane testnet route uses `NoopIsm` (no validation), so an attacker can forge any inbound message. Do **not** bridge value through this stack until the production security path lands. See [#3 — production MultisigIsm setup](https://github.com/sentrix-labs/sentrix-bridge/issues/3) and [#5 — re-verify user-entry path](https://github.com/sentrix-labs/sentrix-bridge/issues/5).

## Verified flows

### Hyperlane v3 — Sentrix Testnet (7120) → Sepolia (11155111)

Two flows verified on-chain:

**1. Message delivery (Hello-World demo, 2026-05-12 commit `531ff64`).** A `MessageDispatched` event on Sentrix Testnet's Mailbox landed at Sepolia's TestRecipient as `Handled("HELLO SEPOLIA FROM SENTRIX TESTNET via Hyperlane", originDomain=7120)` after a manual relay (`process(...)`) from our deployer wallet.

| Side | Mailbox | Our deployments |
|---|---|---|
| Sentrix Testnet | `0x9741D99270aF14D4baca0e387B6ac0500b9a288F` | NoopIsm `0x28834A...e56eC6` · MerkleTreeHook `0x6A192C...0F1467` · TestRecipient `0x1feBBD...CfF4c4` |
| Sepolia | `0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766` (pre-deployed by Hyperlane Labs) | NoopIsm `0x1b11f1...246d` · TestRecipient `0x843fA9...258` |

**2. Token value transfer (wSRX warp route).** `0.001 SRX` wrapped → bridged → minted as `0.001 wSRX` on Sepolia (`HypERC20.balanceOf(recipient) == 1e15` post-relay). Bridge tx `0x4e2582…f9f63` Sentrix-side, mint tx `0x0c1af7…66d56f` Sepolia-side, both `status=1`.

| Component | Address | Side |
|---|---|---|
| `WSRX9` (wrap contract) | `0x85d5E7694AF31C2Edd0a7e66b7c6c92C59fF949A` | Sentrix Testnet |
| `HypERC20Collateral` | `0xfb8190927034c447Fc29B1cfbF4f4F000969bb32` | Sentrix Testnet |
| `HypERC20` (wSRX mint) | `0xC4BDE56bCAadfDbD6fBad685b65628f05994e5a8` | Sepolia |

> **Honest limitation on flow #2:** the demo worked because the deployer already held wSRX. Fresh users have to call `WSRX9.deposit{value: amount}()` to wrap SRX → wSRX, and that step is currently blocked by the upstream chain bug [sentrix-labs/sentrix#580](https://github.com/sentrix-labs/sentrix/issues/580) (EVM payable internal-call gate zeros `msg.value` on broadcast). Bridging works end-to-end *if* you already hold wSRX; user onboarding does not until #580 closes. Detail + tx evidence in `deployments/hyperlane-warp-route.json`.

Full deployment metadata in `deployments/hyperlane-{testnet,sepolia,warp-route}.json`.

### LayerZero V2 — Sentrix Testnet endpoint stack

| Contract | Address | Notes |
|---|---|---|
| `EndpointV2` | `0x00e47A4b45D0147fA2D23D7021b44353966943D9` | eid=40998 placeholder — awaiting LayerZero Labs assignment ([#2](https://github.com/sentrix-labs/sentrix-bridge/issues/2)) |
| `SendUln302` | `0x507a78066d661Ddc5dfc24fd35b598B94e286A07` | registered in endpoint |
| `ReceiveUln302` | `0x8DDDA8aac82049b39a44F0132B8A62388852f86b` | registered in endpoint |

Production stack (PriceFeed, Executor, Treasury, DVN) deferred — tracked in [#4](https://github.com/sentrix-labs/sentrix-bridge/issues/4).

## Multi-chain roadmap

Per-destination bridge status is tracked in [`docs/multichain-roadmap.md`](docs/multichain-roadmap.md). Current state at a glance:

| Destination | Hyperlane | LayerZero V2 | Status |
|---|---|---|---|
| Sepolia (Ethereum testnet) | ✅ message verified | — | Phase 0 demo only |
| BSC Testnet | — | — | Planned (Phase 1) |
| Polygon Amoy | — | — | Planned (Phase 1) |
| Base Sepolia | — | — | Planned (Phase 1) |
| Arbitrum Sepolia | — | — | Planned (Phase 1) |
| Optimism Sepolia | — | — | Planned (Phase 1) |

Mainnet expansion is **gated on** (a) production MultisigIsm + agent infrastructure, (b) resolution of [sentrix-labs/sentrix#580](https://github.com/sentrix-labs/sentrix/issues/580) (the EVM value-passing bug that breaks the user-entry path), and (c) an external audit pass.

## Setup

```bash
# 1. Clone LayerZero V2 upstream (third-party, not vendored)
git clone https://github.com/LayerZero-Labs/LayerZero-v2.git
cd LayerZero-v2
corepack enable && yarn install --mode=skip-build  # PnP install, lifecycle scripts skipped
cd ..

# 2. Install forge deps (OZ v4 + forge-std as direct clones)
mkdir -p lib && cd lib
git clone --depth 1 --branch v4.8.3 https://github.com/OpenZeppelin/openzeppelin-contracts.git openzeppelin-contracts-v4
git clone --depth 1 https://github.com/foundry-rs/forge-std.git
cd ..

# 3. Build
forge build
```

The `.env.example` lists every variable the scripts touch — copy to `.env` and fill in your testnet-only deployer key + RPC URLs.

## Deploy + verify

### LayerZero V2 core (Sentrix Testnet)

```bash
export DEPLOYER_PK=<sentrix-testnet-deployer-private-key>
forge script scripts/DeployLZ-SentrixTestnet.s.sol:DeployLZSentrixTestnet \
  --rpc-url sentrix_testnet \
  --broadcast \
  --skip-simulation \
  --legacy
```

Deploys `EndpointV2(eid=40998, owner=deployer)`, `SendUln302`, `ReceiveUln302`, registers both libraries.

> Sentrix's `eth_getBlockByNumber(full=true)` returns short tx-hash arrays where foundry's fork-initializer expects full tx objects. If `forge script` errors on fork instantiation, fall back to direct `cast send --create` — pattern documented in [`docs/runbook-step2-broadcast.md`](docs/runbook-step2-broadcast.md).

### Hyperlane testnet round-trip

```bash
# 1. Sentrix Testnet stack
forge script hyperlane/scripts/DeployHyperlaneSentrixTestnet.s.sol --rpc-url sentrix_testnet --broadcast --legacy

# 2. Sepolia stack
forge script hyperlane/scripts/DeployHyperlaneSepolia.s.sol --rpc-url sepolia --broadcast

# 3. Dispatch from Sentrix → Sepolia
forge script hyperlane/scripts/DispatchToSepolia.s.sol --rpc-url sentrix_testnet --broadcast --legacy

# 4. Manual relay on Sepolia
forge script hyperlane/scripts/ProcessOnSepolia.s.sol --rpc-url sepolia --broadcast
```

Both `Dispatch` (Sentrix side) and `Handle` (Sepolia side) emit on the canonical Mailbox contracts and are observable via tx hash + explorer URL in `deployments/hyperlane-warp-route.json`.

## Layout

| Path | Purpose |
|---|---|
| `foundry.toml` | Build config: Sentrix RPC endpoints + LZ + OZ v4 remappings (PnP store paths) |
| `scripts/DeployLZ-SentrixTestnet.s.sol` | LZ V2 core deployment to Sentrix Testnet |
| `hyperlane/` | Hyperlane v3 deploy scripts + monorepo submodule |
| `deployments/*.json` | Per-network deployment metadata (addresses, tx hashes, deployer notes) |
| `docs/` | Runbooks + LayerZero Labs application draft + multichain roadmap |
| `subgraph/` | Source-of-truth subgraph for chain analytics (separate concern from bridge — kept here for org convenience) |
| `LayerZero-v2/` *(gitignored)* | Third-party clone — `github.com/LayerZero-Labs/LayerZero-v2` |
| `lib/` *(gitignored)* | OZ v4 + forge-std clones for foundry remappings |

## Open issues

| # | Title | Status |
|---|---|---|
| [#2](https://github.com/sentrix-labs/sentrix-bridge/issues/2) | Track Sentrix EID assignment from LayerZero Labs | Application drafted, awaiting submission |
| [#3](https://github.com/sentrix-labs/sentrix-bridge/issues/3) | Hyperlane production MultisigIsm setup | Runbook drafted, validator-set TBD |
| [#4](https://github.com/sentrix-labs/sentrix-bridge/issues/4) | LZ — deploy PriceFeed + Executor + Treasury + DVN for production | Scoping |
| [#5](https://github.com/sentrix-labs/sentrix-bridge/issues/5) | Re-verify cross-chain user-entry path after sentrix-labs/sentrix#580 closes | Blocked on upstream chain bug |

## License

| Path | License |
|---|---|
| Deploy scripts, runbooks, configs, subgraph (this repo) | BUSL-1.1 (matches the chain repo) |
| `LayerZero-v2/` (clone-instruction in Setup; gitignored — NOT redistributed here) | LZBL-1.2 upstream (LayerZero Business License — converts to GPL v2 on Dec 14, 2027) |
| `lib/openzeppelin-contracts-v4/` (clone-instruction in Setup; gitignored) | MIT upstream (OpenZeppelin) |
| `lib/forge-std/` (clone-instruction in Setup; gitignored) | MIT upstream (Foundry) |
