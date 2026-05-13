# Multi-chain bridge roadmap

Tracks the destination chains we want Sentrix bridged into, the bridge protocol(s) targeted per chain, and the current status of each route.

## Phase 0 — Demo (testnet only)

Goal: prove the protocol layer works end-to-end across one foreign chain. Done.

| Destination | Protocol | Status | Notes |
|---|---|---|---|
| Sepolia (Ethereum testnet) | Hyperlane v3 | ✅ Message verified `2026-05-12` | NoopIsm. `deployments/hyperlane-{testnet,sepolia}.json` |

## Phase 1 — Testnet multi-destination (next)

Goal: each Sentrix Testnet ↔ <foreign testnet> route deployed + a single roundtrip message verified. No value flow yet; production agents still pending.

### Selection criteria

Pick foreign testnets where (a) Hyperlane has pre-deployed core contracts so we don't have to deploy both sides, (b) free faucet ETH is reachable, (c) the foreign testnet's mainnet is somewhere we'd actually want to bridge to next.

| Destination | Hyperlane core deployed? | Faucet | Why |
|---|---|---|---|
| BSC Testnet (chain 97) | ✅ in `@hyperlane-xyz/registry` | testnet.bnbchain.org | Highest-volume non-EVM-fork chain; tied to BNB launchpad ecosystem |
| Polygon Amoy (chain 80002) | ✅ in `@hyperlane-xyz/registry` | faucet.polygon.technology | Replaces Mumbai; major L2 |
| Base Sepolia (chain 84532) | ✅ in `@hyperlane-xyz/registry` | bridge.base.org/deposit (sepolia bridge) | Coinbase L2, big dev community |
| Arbitrum Sepolia (chain 421614) | ✅ in `@hyperlane-xyz/registry` | bridge.arbitrum.io (sepolia bridge) | Largest L2 by TVL |
| Optimism Sepolia (chain 11155420) | ✅ in `@hyperlane-xyz/registry` | superchain faucet | OP Stack, second-largest L2 |

Order is operator's call. Default proposal: BSC Testnet first (highest signal-to-noise for a launchpad chain), then the four L2 sepolias in TVL order.

### Per-destination checklist (template)

For each new destination:

1. Deploy `Mailbox` + `NoopIsm` + `TestRecipient` + `MerkleTreeHook` on the foreign testnet via the appropriate Hyperlane script. (If pre-deployed by Hyperlane Labs, skip Mailbox + use the registry address.)
2. Update `hyperlane/scripts/DispatchTo<Chain>.s.sol` with the destination domain ID.
3. Dispatch test message from Sentrix Testnet → foreign chain.
4. Manual relay (`process(...)`) on foreign chain Mailbox using the deployer wallet.
5. Verify `Handle(messageBody)` log on foreign TestRecipient with `originDomain = 7120`.
6. Commit `deployments/hyperlane-<chain>.json` with addresses + tx hashes + explorer URLs.
7. Update this file's status table.

## Phase 2 — Production security (gate)

The Phase 1 demo runs on `NoopIsm` — anyone can process any message. Cannot bridge real value through this. Phase 2 swaps NoopIsm for production ISM per destination:

- **MultisigIsm** — m-of-n trusted validator signature aggregation. Runbook at `docs/multisigism-setup.md`. Validator set is operator's call.
- **AggregationIsm** — multiple ISMs in series (e.g. MultisigIsm + MerkleRootMultisigIsm). Higher security, more gas.
- **ProtocolFee + InterchainGasPaymaster** — wire so dispatchers pay relay gas at dispatch time, freeing the protocol-funded "courtesy relay" we currently rely on.

Per-destination Phase 2 checklist:

1. Recruit validators (operator's call — likely Sentrix Foundation validator set initially).
2. Deploy `MultisigIsm` on each side with the validator set.
3. Run validator agent (Hyperlane's `validator` binary) per validator host, configured for both chains.
4. Run relayer agent (Hyperlane's `relayer` binary) — relays valid signed messages automatically, no manual `process(...)` call.
5. Re-verify message round-trip end-to-end via the agent network. No human in the loop.
6. Replace `interchainSecurityModule` on test recipients from NoopIsm → MultisigIsm.

## Phase 3 — Token bridging (Warp Routes)

Hyperlane Warp Routes wrap an ERC-20 (or native token) as a synthetic on the destination side. Two variants:

- **HypERC20Collateral** (source) ↔ **HypERC20** (destination): lock canonical token on source, mint synthetic on destination. Used when source has a real ERC-20.
- **HypNative** (source) ↔ **HypERC20** (destination): same pattern but for native gas tokens. Used for SRX → wrapped-SRX.

**Unblocked 2026-05-13** — [sentrix-labs/sentrix#580](https://github.com/sentrix-labs/sentrix/issues/580) closed. EVM value-transfer + gas-fix forks activated on testnet h=3,787,000 and mainnet h=1,748,900 (binary v2.2.11). `HypNative.transferRemote(...)` now functional on the native path; the WSRX wrap workaround remains as an alternative but is no longer required.

## Phase 4 — Mainnet (gated on audit)

Cannot proceed until:

- [x] sentrix-labs/sentrix#580 closed (2026-05-13)
- [ ] Phase 2 production-ISM live on testnet ≥ 7 days with no halt-class incidents
- [ ] External audit pass (firm TBD — Code4rena contest is a candidate)
- [ ] Public mainnet faucet for SRX→ETH gas bootstrap (so users have ETH to receive on the foreign side)
- [ ] LayerZero Labs has assigned a real EID (currently placeholder 40998)
- [ ] Insurance / treasury policy for bridge contract custody decided

Mainnet rollout is per-destination — one chain at a time, with bake periods between, not all at once.

## LayerZero V2 path

LayerZero V2 is the parallel track. Sentrix Testnet has the endpoint stack live (see README). The blockers for LZ V2 mainnet adoption are different from Hyperlane's:

- LayerZero Labs needs to assign a real EID (#2) — placeholder 40998 cannot peer with other chains' real endpoints.
- Production stack (PriceFeed, Executor, Treasury, DVN) needs deploy + wire (#4).
- DVN (Decentralized Verifier Network) coverage decision: self-run DVN vs use LayerZero Labs DVN vs third-party DVNs like Polyhedra. Operator's call once #2 lands.

LayerZero V2 destination matrix follows the same chains as Hyperlane (Sepolia, BSC Testnet, etc.) — they don't conflict; users can pick either bridge.

## Status journal

- **2026-05-12** Phase 0 demo route Sepolia ↔ Sentrix Testnet verified. Both protocol stacks deployed. LayerZero Labs application drafted.
- **2026-05-13** Multichain roadmap doc created. Issues #2-#5 tracked.
