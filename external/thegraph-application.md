# The Graph — Chain Integration Application Draft

The Graph hosted service (and the official Sentrix subgraph studio) doesn't yet support Sentrix Chain. This doc pre-writes the chain integration request so operator can submit when ready.

## Submission channels

The Graph chain integration goes through one of:
1. **Discord** — `#chain-integration` channel on The Graph's Discord (`https://discord.gg/graphprotocol`). Drop a structured message + ping core team.
2. **GitHub Discussions** — `github.com/graphprotocol/protocol-network/discussions` (or `graph-node/discussions` for technical onboarding).
3. **Forum post** — `forum.thegraph.com` under "Network Operations" or "Protocol".

Discord is fastest for first contact; forum post follows for the formal request with the structured data below.

## Application body

> ### Request: Sentrix Chain integration to The Graph hosted service
>
> Hello Graph team,
>
> Sentrix Labs is requesting integration of Sentrix Chain into The Graph hosted service (and subsequent decentralized network listing). Sentrix is a Rust-implemented EVM-compatible L1 in active production on both mainnet and testnet.
>
> #### Chain identity
>
> | Field | Mainnet | Testnet |
> |---|---|---|
> | Network name | Sentrix Chain | Sentrix Testnet |
> | Chain ID (EVM) | 7119 | 7120 |
> | RPC endpoint | https://rpc.sentrixchain.com | https://testnet-rpc.sentrixchain.com |
> | Archive RPC | https://rpc.sentrixchain.com (full state retention) | https://testnet-rpc.sentrixchain.com |
> | WebSocket | (none yet — JSON-RPC over HTTPS only) | (same) |
> | Block explorer | https://scan.sentrixchain.com (EIP-3091) | https://testnet-scan.sentrixchain.com |
> | Native token | SRX | SRX (testnet) |
> | Consensus | Voyager DPoS+BFT (Tendermint-style, single-block finality) | Same |
> | Block time | ~2.0-2.5s mainnet (WAN-jitter floor) | ~0.3s testnet |
> | EVM | revm 38, Solidity 0.8.x, Cancun-enabled | Same |
> | Codebase | github.com/sentrix-labs/sentrix (BUSL-1.1) | Same |
>
> #### Sample contracts already deployed on Sentrix Chain
>
> The canonical-contracts suite at `github.com/sentrix-labs/canonical-contracts` is deployed on both mainnet and testnet:
>
> - WSRX (Wrapped SRX, WETH9-pattern): mainnet `0x4693b113e523A196d9579333c4ab8358e2656553`
> - Multicall3 (canonical): mainnet `0xFd4b34b5763f54a580a0d9f7997A2A993ef9ceE9`
> - SentrixSafe (1-of-1 multisig): mainnet `0x6272dC0C842F05542f9fF7B5443E93C0642a3b26`
> - SentrixV2Factory (sentrix-dex V2 fork): mainnet `0xC5344f0DDE0B9916217449Ad9222e446475aD936`
>   - Standard UniV2 PairCreated + Pair Swap/Mint/Burn/Sync events
>   - INIT_CODE_HASH `0xf7d8b4d1ce6c92cb3ce6b366dfb5977578db74e308b88facd5966df9e2a029dd`
>
> #### First subgraph
>
> Sentrix Labs is preparing a canonical subgraph for sentrix-dex (UniV2-fork) ready for deployment as soon as graph-node supports Sentrix. Repo: `github.com/sentrix-labs/sentrix-bridge` directory `subgraph/` (Phase 1 scope: PairCreated + Swap + Mint + Burn + Sync; full schema + AssemblyScript handlers committed).
>
> Once supported, we expect 5-10 additional subgraphs in the first 6 months (CoinBlast launchpad, staking events via system precompile, future lending protocol, NFT marketplace).
>
> #### Why integrate Sentrix
>
> - Active production chain — both mainnet and testnet operational since 2026-04.
> - EVM-compatible; standard ABI + event semantics — no graph-node EVM patch needed.
> - Sentrix Labs commits to running a public graph-node alongside The Graph hosted service (operator-side, on existing infrastructure).
> - Working live cross-chain bridge to Ethereum via Hyperlane (`sentrix-labs/sentrix-bridge`) demonstrates ecosystem maturity.
>
> #### What we need from The Graph
>
> 1. **graph-node EVM provider config** — add Sentrix to your network list with the RPC + archive endpoints above.
> 2. **Hosted service onboarding** — once graph-node supports Sentrix, we'd like to deploy via `https://thegraph.com/hosted-service/dashboard`.
> 3. **Decentralized network listing** (longer-term) — once the protocol upgrades to indexing rewards on new chains.
>
> #### Sentrix Labs contact
>
> - GitHub: `github.com/sentrix-labs` (organization)
> - Email: (operator to fill, deferred from public draft)
> - Discord / Telegram: (operator to fill before submission)
>
> Happy to provide additional info or jump on a sync call. Thanks!
>
> — Sentrix Labs

## Pre-submission verification

Before sending, verify:
- Mainnet RPC responsive — `curl -X POST https://rpc.sentrixchain.com -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'` → returns `0x1bcf` ✓ (verified 2026-05-12)
- Mainnet has at least 6 months of state retention or full archive — Sentrix runs without aggressive pruning per chain config; effectively archive RPC at v2.2.2.
- Public canonical contracts deployed + verified at `verify.sentrixchain.com` (Sourcify-compatible).
- Sample subgraph builds locally against the Sentrix manifest in `sentrix-bridge/subgraph/`.

## Self-host fallback (if calendar block too long)

If The Graph hosted service onboarding stretches beyond 1-2 months:

1. Deploy `graph-node` Rust binary on operator infrastructure alongside existing services
2. Postgres backing store
3. IPFS daemon (self-hosted)
4. graph-cli deploys subgraphs to `https://stats.sentrixchain.com:8000/subgraphs/name/sentrix-labs/sentrix-dex` (or similar)
5. Public GraphQL endpoint mirrors The Graph's API surface — dApp builders can switch URL only

Self-host doesn't get The Graph's ecosystem benefits (curated indexer network, decentralized rewards), but unblocks dApp dev immediately.

## Estimated timeline

- Discord first contact → response in 1-3 days
- Forum post follow-up → 1 week
- graph-node + hosted service support → 1-3 months typical for new EVM chains
- Decentralized network listing → 6-12 months (depends on Graph protocol upgrades)

## Backup plans

| Phase | If The Graph delays | Plan B |
|---|---|---|
| First 2 weeks | No response | Self-host graph-node, ship subgraph anyway |
| 1-2 months | Discord cold | Forum post + ping known Graph team members on Twitter |
| 3-6 months | Still no integration | Lean on self-host + offer to whitepaper-co-author "permissionless graph-node on EVM L1s" |

## Resources to share with The Graph team

- `github.com/sentrix-labs/sentrix-bridge/blob/main/subgraph/README.md` — Phase 1 scope
- `github.com/sentrix-labs/sentrix-bridge/blob/main/subgraph/subgraph.yaml` — manifest with verified addresses
- `github.com/sentrix-labs/sentrix` — chain source (BUSL-1.1)
- `https://scan.sentrixchain.com` — block explorer (EIP-3091 compliant)

## Pre-submit checklist

- [ ] Chain on Chainlist (operator submits separately — see `chainlist-pr-data.md`)
- [ ] At least one verified contract on chain (canonical-contracts already deployed + Sourcify-verified)
- [ ] Stable RPC endpoint (currently `rpc.sentrixchain.com` — single endpoint; would benefit from 2-3 geographically-distributed RPC providers before formal Graph integration)
- [ ] Public GitHub org for the chain (`sentrix-labs` ✓)
- [ ] Sample subgraph ready (drafted in `sentrix-bridge/subgraph/` ✓)
