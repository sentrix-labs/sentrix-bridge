# Sentrix Subgraph — The Graph integration sketch

Subgraph manifest + schema sketch for indexing Sentrix on-chain activity via The Graph (or self-hosted graph-node).

**Language:** AssemblyScript (strict TypeScript subset compiled to WebAssembly). NOT regular TypeScript — has no closures, no exceptions, requires explicit type conversions.

**Stack:**
- `subgraph.yaml` — manifest defining data sources (contracts, events, block ranges)
- `schema.graphql` — GraphQL entity types
- `src/*.ts` — AssemblyScript event handlers that read events + write entities

## Phase 1 scope — sentrix-dex (V2 pairs)

Mirrors Uniswap's official V2 subgraph pattern, adapted for Sentrix's `dex.sentrixchain.com` contracts.

### Entities

- `Pair { id, token0, token1, reserve0, reserve1, totalSupply, txCount, createdAtTimestamp, createdAtBlock }`
- `Token { id, symbol, name, decimals, totalLiquidity, tradeVolumeUSD }`
- `Swap { id, pair, sender, amount0In, amount1In, amount0Out, amount1Out, to, timestamp, blockNumber, transaction }`
- `Mint { id, pair, sender, amount0, amount1, liquidity, to, timestamp }`
- `Burn { id, pair, sender, amount0, amount1, liquidity, to, timestamp }`
- `PairDayData { id, date, pair, dailyVolumeToken0, dailyVolumeToken1, totalSupply, reserveUSD }`
- `SentrixDayData { id, date, dailyVolumeUSD, totalLiquidityUSD, txCount }`

### Data sources

- `Factory` — sentrix-dex V2 factory (TBD address)
  - Event: `PairCreated(address,address,address,uint256)`
- Template: `Pair` — instantiated dynamically per pair
  - Events: `Swap`, `Mint`, `Burn`, `Sync` (for reserve updates)

### Block range

Start at the factory deploy block on mainnet (7119). Operator to confirm by running:
```bash
cast call --rpc-url https://rpc.sentrixchain.com <factory> "PAIR_HASH()(bytes32)"  # if exposed
# OR
cast logs --rpc-url https://rpc.sentrixchain.com --from-block 1 --to-block latest --address <factory>
```

## Phase 2 scope — CoinBlast launchpad

Mirrors the existing indexer's CoinBlast handling.

### Entities

- `LaunchpadToken { id, name, symbol, creator, createdAt, curveAddress, totalRaised, graduated, currentPrice }`
- `Trade { id, token, trader, side, amountSRX, amountToken, price, timestamp, txHash }`

### Data sources

- `CoinBlastFactory` — mainnet `0x___` (from canonical-contracts/deployments/7119.json — TODO operator to confirm; CoinBlastFactory not yet in canonical-contracts deploy)
- Template: `CoinBlastCurve` — per-token bonding curve

## Phase 3 scope — staking + validator events

Reads chain-native events from the Sentrix runtime. Note: these are NOT standard EVM events (they come from the Voyager DPoS+BFT layer, not contracts).

Will require either:
- A "system precompile" contract that emits standard EVM events on validator changes (operator to evaluate)
- OR a custom indexer extension (graph-node fork that reads non-EVM logs from sentrix-grpc)

Phase 3 is deferred until system-precompile design is in place.

## Self-hosted graph-node

The Graph hosted service does not support Sentrix (chain 7119) yet — would need to either:

1. **Apply to The Graph for chain support** — typically 1-3 months calendar, requires demand signal
2. **Self-host graph-node** — Rust binary, deploy on vps6 alongside indexer-rs

For self-hosting:

```bash
# graph-node config (operator to wire)
ethereum: "sentrix:https://rpc.sentrixchain.com"
ipfs: "https://api.thegraph.com/ipfs/"  # or self-host IPFS
postgres-url: "postgres://...@vps6:5432/graph"
```

Deploy subgraph via graph-cli:
```bash
graph deploy --node http://localhost:8020/ --ipfs http://localhost:5001 sentrix-labs/sentrix-dex
```

Public query endpoint at: `http://stats.sentrixchain.com:8000/subgraphs/name/sentrix-labs/sentrix-dex`

## Files this sketch provides

- `subgraph.yaml` — manifest skeleton (data source = sentrix-dex Factory, addresses TBD)
- `schema.graphql` — entity schema for Phase 1
- `src/factory.ts` — PairCreated handler sketch
- `src/pair.ts` — Swap / Mint / Burn / Sync handler sketches

Each file commented with `TODO: confirm with operator` where verified addresses are needed.

## Estimated effort

- Phase 1 (sentrix-dex): 2-3 days for first deployable subgraph
- Phase 2 (CoinBlast): 1-2 days additional
- Phase 3 (staking): deferred pending design

## Quality bar

- All event signatures match actual Solidity contracts (cross-check against `~/canonical-contracts/contracts/*.sol`)
- All schema field types match Solidity types (uint256 → BigInt, address → Bytes)
- Mappings use the canonical `@graphprotocol/graph-ts` helpers (no homegrown decoders)
- Test on testnet (chain 7120, addresses in `canonical-contracts/deployments/7120.json`) before mainnet
