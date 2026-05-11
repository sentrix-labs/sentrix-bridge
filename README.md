# sentrix-bridge

Sentrix Chain ↔ external chain bridge integration prep. Tracks the LayerZero V2 integration path; future home for OFT (Omnichain Fungible Token) wrappers and any other bridge protocol work.

## Status

**Phase 0 — Step 1 prep.** Build pipeline working, deploy script written, awaiting testnet deployment + LayerZero Labs chain-integration form submission.

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

## Deploy LayerZero V2 core to Sentrix Testnet (chain 7120)

```bash
export DEPLOYER_PK=<sentrix-testnet-deployer-private-key>
forge script scripts/DeployLZ-SentrixTestnet.s.sol:DeployLZSentrixTestnet \
  --rpc-url sentrix_testnet \
  --broadcast \
  --skip-simulation \
  --legacy
```

Deploys:
- `EndpointV2(eid=40998, owner=deployer)`
- `SendUln302(endpoint, treasuryGasLimit=1_000_000, treasuryGasForFeeCap=1_000_000_000)`
- `ReceiveUln302(endpoint)`
- Registers both libraries in `EndpointV2.registerLibrary`.

EID 40998 is a placeholder until LayerZero Labs assigns the official Sentrix Testnet EID through their chain-integration process.

## Layout

| Path | Purpose |
|---|---|
| `foundry.toml` | Build config: Sentrix RPC endpoints + LZ + OZ v4 remappings (PnP store paths) |
| `scripts/DeployLZ-SentrixTestnet.s.sol` | LZ V2 core deployment to Sentrix Testnet |
| `LayerZero-v2/` *(gitignored)* | Third-party clone — `github.com/LayerZero-Labs/LayerZero-v2` |
| `lib/` *(gitignored)* | OZ v4 + forge-std clones for foundry remappings |

## What's deferred to Step 2+

- `PriceFeed` (upgradeable proxy pattern)
- `Executor` + `Treasury`
- DVN deployment + registration
- Cross-chain message wiring (Sentrix Testnet → Sepolia / BSC Testnet)
- OFT wrapper for SRX (testnet only)
- LayerZero Labs chain-integration application

## License

Deploy script + tooling: BUSL-1.1 (matches the Sentrix chain repo).
Cloned LayerZero V2 source: LZBL-1.2 (LayerZero Business License — converts to GPL v2 on Dec 14, 2027).
