# LayerZero Labs Chain Integration — Sentrix Application Draft

Submit via `forms.layerzero.foundation` or LayerZero Discord `#chain-integration` channel.

## Chain Identity

| Field | Value |
|---|---|
| Chain name | Sentrix Chain |
| Mainnet chain ID (EVM) | 7119 |
| Testnet chain ID (EVM) | 7120 |
| Native token | SRX (18 decimals) |
| Consensus | Voyager DPoS+BFT (Tendermint-style 3-phase) |
| Block time (mainnet) | ~2.0-2.5 s/blk |
| Block time (testnet) | ~0.3-0.4 s/blk |
| Finality | Single-block (BFT instant finality at h+1) |
| EVM compatibility | revm 37, Solidity 0.8.x |
| Codebase | Open-source Rust L1, `github.com/sentrix-labs/sentrix` (BUSL-1.1) |

## Endpoints

| Network | RPC | Explorer |
|---|---|---|
| Mainnet | `https://rpc.sentrixchain.com` | `https://scan.sentrixchain.com` |
| Testnet | `https://testnet-rpc.sentrixchain.com` | `https://testnet-scan.sentrixchain.com` |

EVM JSON-RPC compatible; gRPC sidecar at `https://grpc.sentrixchain.com:443` (proto `sentrix.v1.Sentrix`).

## Deployed LayerZero V2 contracts (Testnet)

Deployed 2026-05-12 from `~/sentrix-bridge` commit `3f05d1e`. Both libraries registered in the endpoint registry.

| Contract | Address |
|---|---|
| EndpointV2 | `0x00e47A4b45D0147fA2D23D7021b44353966943D9` |
| SendUln302 | `0x507a78066d661Ddc5dfc24fd35b598B94e286A07` |
| ReceiveUln302 | `0x8DDDA8aac82049b39a44F0132B8A62388852f86b` |

Full metadata + tx hashes: [`deployments/testnet.json`](../deployments/testnet.json).
Block-explorer link: `https://testnet-scan.sentrixchain.com/address/<address>`.

Deployment script: [`scripts/DeployLZ-SentrixTestnet.s.sol`](../scripts/DeployLZ-SentrixTestnet.s.sol)

## Proposed EID

Requesting EID assignment for both networks. Current placeholder (testnet) = `40998`; this code path will be re-deployed once an official EID is issued.

## Security posture

- **Validator set:** 4-of-4 mainnet (will scale post-eco-readiness sprint). 4-of-4 testnet (docker stack on a single host for low-latency baking).
- **Consensus:** BFT 3-phase Tendermint-style with single-block finality. STATE-FP cross-validator fingerprints confirm state determinism. LastSignBytes guard prevents validator equivocation.
- **Slashing:** disabled until v2.3+ activation (consensus-jail height set to `u64::MAX` as operator caution).
- **Treasury / governance:** SentrixSafe 1-of-1 multisig (will expand to N-of-M organically; no committed timeline).
- **Audit history:** internal rust-reviewer audits at `audits/` in main repo; external audit budget aligned with TVL milestones.

## Why integrate Sentrix

- EVM-compatible chain with sub-1s testnet bt — competitive throughput floor for omnichain dApps.
- Open-source under BUSL-1.1 (transitions to OSI-approved license after Change Date).
- Solo-builder origin → highly responsive to integration needs (no committee delays).
- Growing ecosystem: scan.sentrixchain.com (custom Next.js explorer, EIP-3091 compliant), faucet, DEX (UniV2-fork live), CoinBlast token launchpad, Solux wallet — all on-chain on Sentrix.

## Contact

- Email: `(operator to fill before submit)`.
- GitHub: `github.com/sentrix-labs`, `github.com/Sentriscloud`.
- Discord / Telegram: `(operator to fill before submit)`.

## Open items before submit

- [ ] Step 2 broadcast — fill in deployed addresses table.
- [ ] Step 3 — deploy PriceFeed (upgradeable proxy), Executor, Treasury.
- [ ] Step 3 — set up Sentrix-operated DVN (stack DVN) signing keys + address.
- [ ] Mainnet stable observation window — recommended minimum 30 days uninterrupted before LZ Labs will assign mainnet EID.
- [ ] Identify Sentrix-side contact channels (Discord server, support email).
