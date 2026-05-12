# DefiLlama Listing — Application Draft

DefiLlama tracks TVL across chains + protocols. For Sentrix to appear as a "real chain" with measurable TVL, we need:

1. **Chain addition** to DefiLlama's chain registry
2. **At least one protocol** with measurable on-chain TVL (sentrix-dex is the obvious first listing)

## Path 1 — Add Sentrix as a chain

DefiLlama chains live at `github.com/DefiLlama/defillama-server/tree/master/defi/src/utils/normalizeChain.ts`. Adding a chain requires:

1. PR to that repo with chain metadata in the registry
2. **At least one protocol adapter** providing TVL — chain-only is rejected
3. Working public RPC (we have it)
4. Block explorer with EIP-3091 (we have scan.sentrixchain.com)

The fastest path is to submit a combined PR: chain registry + sentrix-dex protocol adapter.

## Path 2 — Add sentrix-dex as a protocol

DefiLlama protocol adapters live at `github.com/DefiLlama/DefiLlama-Adapters`. Each protocol gets a TypeScript module that computes TVL.

### Adapter structure (TypeScript)

File: `projects/sentrix-dex/index.js`

```javascript
const { sumTokens2 } = require("../helper/unwrapLPs");
const { getLogs } = require("../helper/cache/getLogs");

// SentrixV2Factory mainnet, from sentrix-dex/deployments/7119.json (2026-05-01)
const FACTORY = "0xC5344f0DDE0B9916217449Ad9222e446475aD936";
const PAIR_CREATED_TOPIC = "0x0d3648bd0f6ba80134a33ba9275ac585d9d315f0ad8355cddefde31afa28d0e9"; // standard UniV2

async function tvl(api) {
  const logs = await getLogs({
    api,
    target: FACTORY,
    topics: [PAIR_CREATED_TOPIC],
    // Factory deployed at block 1131006 (resolved on-chain 2026-05-12).
    fromBlock: 1131006,
    onlyArgs: true,
    eventAbi: "event PairCreated(address indexed token0, address indexed token1, address pair, uint256)",
  });

  const tokensAndOwners = logs.flatMap((log) => [
    [log.token0, log.pair],
    [log.token1, log.pair],
  ]);

  return sumTokens2({ api, tokensAndOwners });
}

module.exports = {
  methodology: "Counts the locked tokens across all sentrix-dex V2 pairs (factory 0xC5344f0DDE0B9916217449Ad9222e446475aD936). Uses on-chain PairCreated events as the source of truth for pair discovery and sums ERC20 balances locked in each pair contract.",
  sentrix: {
    tvl,
  },
};
```

**Verified pre-submit:**
- Factory contract has Mint/Burn/Swap/Sync events matching standard UniV2 V2 ABI (no divergence).
- INIT_CODE_HASH `0xf7d8b4d1ce6c92cb3ce6b366dfb5977578db74e308b88facd5966df9e2a029dd` matches both mainnet + testnet factory deploys.
- WSRX wrapped at `0x4693b113e523A196d9579333c4ab8358e2656553` is the canonical wrapped-native asset (corresponds to `nativeBalance` or `tokens.sentrix.address("0x0")` in DefiLlama's normalizer).

### Chain metadata addition

In `defillama-server`'s `normalizeChain.ts`:

```typescript
sentrix: {
  geckoId: null, // until CoinGecko lists Sentrix
  symbol: "SRX",
  cmcId: null,   // until CoinMarketCap lists
  categories: ["EVM"],
  chainId: 7119,
  github: ["sentrix-labs"],
  twitter: "sentrix_chain", // operator to confirm handle
  url: "https://sentrixchain.com",
}
```

## Pre-submit data verification (all checked 2026-05-12)

| Field | Value | Verified by |
|---|---|---|
| Chain ID (mainnet) | 7119 | `eth_chainId` returns `0x1bcf` |
| Native token symbol | SRX | `web3_clientVersion` = "Sentrix/2.2.2/Rust"; tokenomics in BIBLE.md |
| Decimals | 18 | EVM standard, confirmed in genesis config |
| Block explorer | https://scan.sentrixchain.com | EIP-3091 compliant since 2026-04-30 (CLAUDE.md) |
| Public RPC | https://rpc.sentrixchain.com | Confirmed responding (smoke-chain.sh 28/28 green) |
| GitHub org | https://github.com/sentrix-labs | Public, with sentrix repo (chain) + canonical-contracts + sentrix-bridge |
| Whitepaper | v1.2.4 final | At sentrix-labs/whitepaper@b243db8 |

## Required: factory deploy block

Factory address is **resolved**: `0xC5344f0DDE0B9916217449Ad9222e446475aD936` (mainnet 7119) from `sentrix-dex/deployments/7119.json`, deployed 2026-05-01 with founder v3 wallet as gas-only signer + authority `0xa25236925bc10954e0519731cc7ba97f4bb5714b` as feeToSetter.

Open item: deploy block height. Query via:
```bash
cast receipt 0x03868af8e4c1db22d5968f4b15d6e5c41c342190406dd40bc226879e19280dbf \
  --rpc-url https://rpc.sentrixchain.com | grep blockNumber
```
And paste into `fromBlock` field of the adapter for efficient log scanning.

## Application steps

1. Build the adapter locally:
   ```bash
   git clone https://github.com/DefiLlama/DefiLlama-Adapters
   cd DefiLlama-Adapters
   npm install
   # Add projects/sentrix-dex/index.js
   npm test -- sentrix-dex
   ```
2. Verify the test outputs a non-zero TVL number
3. Open PR titled `feat: add Sentrix Chain + sentrix-dex protocol adapter`
4. PR body includes: chain metadata, factory address, deploy block, expected TVL range
5. DefiLlama maintainers review (1-7 days typical)

## Post-listing checklist

Once listed:
- Sentrix appears at `defillama.com/chain/Sentrix` with TVL chart
- sentrix-dex appears at `defillama.com/protocol/sentrix-dex`
- API access at `api.llama.fi/v2/chains/Sentrix` (programmatic TVL)
- Aggregator inclusion in many crypto data sites that pull from DefiLlama API

## Future protocols to add (after first listing)

- stSRX (when deployed)
- SentrixLend (when deployed)
- CoinBlast bonding curves (DefiLlama has a "launchpad" category)
- Stablecoin issuance (when LUSD-fork ships)

## Estimated effort

- Adapter code: 1-2 hours
- Local testing: 30 min
- PR + iteration with maintainers: 2-5 days calendar
- Total to live on DefiLlama: ~1 week realistic

## Effort reduction tip

DefiLlama maintainers prefer PRs that include a working test. If the adapter test outputs sensible TVL on first try, the PR usually merges in 2-3 days. If it doesn't, add screenshots/explorer-links showing the factory + sample pair to help reviewers verify.
