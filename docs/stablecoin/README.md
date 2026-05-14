# Sentrix Bridged USDC (sUSDC) — testnet PoC

A minimal, auditable bridged stablecoin for Sentrix Chain.

> **This is NOT official Circle USDC.** The contracts in `src/stablecoin/` do
> not carry Circle's reserve backing or Circle's brand. They are a Sentrix-issued
> ERC20 token (`sUSDC`) backed 1:1 by USDC locked in a Sentrix-operated vault
> on the source chain. See `SECURITY_NOTES.md` for the trust model.

## What this is

- A 6-decimal ERC20 (`Sentrix Bridged USDC` / `sUSDC`) deployable on Sentrix
  testnet (chain 7120) or mainnet (chain 7119).
- A companion vault (`SourceChainVault`) deployable on a source chain (Sepolia
  for testing, Ethereum mainnet eventually) that locks real USDC.
- An off-chain relayer that observes events on both sides and submits the
  bridge mint / collateral release transactions.

## What this is NOT

- Not Circle USDC.
- Not Circle's `FiatTokenV2_2` from `circlefin/stablecoin-evm`. That contract
  is the Bridged USDC Standard reference implementation and has a different
  role layout + UUPS upgradeability that this PoC intentionally skips.
- Not yet integrated with Hyperlane / LayerZero / Wormhole / CCTP. The bridge
  transport is the off-chain relayer (`watcher-rs` extension).

## Architecture

```
                          SOURCE CHAIN (Sepolia / Ethereum mainnet)
                          ─────────────────────────────────────────
  User                                                  SourceChainVault
   |  deposit(recipient, amount, dst=7119)                |
   | ───────────────────────────────────────────────────> |  collateral locked
   |                                                      |  emit Deposit(...)
   |                                                      |
                                                          v
                                              relayer (watcher-rs) observes,
                                              waits confirmation depth,
                                              dedups, submits mint
                                                          v
                          SENTRIX CHAIN (7119 / 7120)
                          ─────────────────────────────
  User                                                  SentrixBridgedUSDC
   |  bridgeMint(depositId, srcChain, recipient, amount)  |
   | <─────────────────────────────────────────────────── |  sUSDC minted
                                                          |
   |  burnForWithdrawal(recipient, amount, dst)           |
   | ───────────────────────────────────────────────────> |  burn + emit
                                                          |  WithdrawRequested
                                                          |
                                              relayer observes, dedups,
                                              submits release on vault
                                                          v
                          SOURCE CHAIN
                          ────────────
                                                  SourceChainVault.release(...)
                                                  collateral returned
```

## Files

| Path | Purpose |
|---|---|
| `src/stablecoin/SourceChainVault.sol` | Locks ERC20 collateral on source chain. |
| `src/stablecoin/SentrixBridgedUSDC.sol` | Bridged ERC20 stablecoin on Sentrix. |
| `src/interfaces/ISourceChainVault.sol` | Vault interface. |
| `src/interfaces/ISentrixBridgedUSDC.sol` | Token interface. |
| `test/stablecoin/SourceChainVault.t.sol` | Vault test suite (15 tests). |
| `test/stablecoin/SentrixBridgedUSDC.t.sol` | Token test suite (20 tests). |
| `test/stablecoin/mocks/MockERC20.sol` | Mintable mock used in tests. |
| `scripts/stablecoin/DeploySourceChainVault.s.sol` | Vault deploy script. |
| `scripts/stablecoin/DeploySentrixBridgedUSDC.s.sol` | Token deploy script. |
| `docs/stablecoin/BRIDGE_RELAYER_DESIGN.md` | Off-chain relayer spec. |
| `docs/stablecoin/SECURITY_NOTES.md` | Risk register + mitigations. |

## Roles

### `SourceChainVault`

| Role | Purpose |
|---|---|
| `DEFAULT_ADMIN_ROLE` | Grant/revoke other roles. Multisig REQUIRED. |
| `OPERATOR_ROLE` | Release locked collateral after verified Sentrix burn. Multisig REQUIRED. |
| `PAUSER_ROLE` | Pause/unpause deposits + releases. |

### `SentrixBridgedUSDC`

| Role | Purpose |
|---|---|
| `DEFAULT_ADMIN_ROLE` | Grant/revoke other roles. Multisig REQUIRED. |
| `BRIDGE_MINTER_ROLE` | Call `bridgeMint`. Gated by per-minter allowance. |
| `MINTER_ADMIN_ROLE` | Configure mint allowances. |
| `PAUSER_ROLE` | Pause/unpause transfers, mint, burn. |

## Build + test

```bash
# Operator's existing setup already has lib/forge-std, lib/openzeppelin-contracts-v4,
# and lib/openzeppelin-contracts-upgradeable. If starting fresh:
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v4.9.5

# Compile only the stablecoin contracts (skip operator's existing LZ deploy scripts
# which depend on the LayerZero-v2 submodule that may not be cloned locally):
forge build src/stablecoin/ src/interfaces/

# Run the test suite (35 tests across both contracts):
forge test --match-path "test/stablecoin/*" --skip "DeployMultisigIsm" --skip "DeployLZ"
```

Expected output: `35 tests passed, 0 failed, 0 skipped`.

## Deployment

### 1. Deploy SourceChainVault on Sepolia (testnet)

```bash
export DEPLOYER_PK=0x...                                        # source-chain deployer EOA / multisig signer
export COLLATERAL_TOKEN=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238  # Sepolia USDC (verify before use)
export VAULT_ADMIN=0x...           # multisig recommended
export VAULT_OPERATOR=0x...        # multisig REQUIRED for production
export VAULT_PAUSER=0x...

forge script scripts/stablecoin/DeploySourceChainVault.s.sol \
  --rpc-url $SEPOLIA_RPC \
  --broadcast \
  --verify
```

Mainnet (Ethereum chain 1): set `ALLOW_MAINNET_DEPLOY=1` AND ensure all role
holders are multisigs.

### 2. Deploy SentrixBridgedUSDC on Sentrix testnet

```bash
export DEPLOYER_PK=0x...
export TOKEN_ADMIN=0x...           # multisig
export TOKEN_MINTER_ADMIN=0x...    # multisig
export TOKEN_PAUSER=0x...
export INITIAL_MINTER=0x...        # bridge minter contract OR relayer EOA
export INITIAL_ALLOWANCE=10000000000   # 10,000 sUSDC (6 decimals)

forge script scripts/stablecoin/DeploySentrixBridgedUSDC.s.sol \
  --rpc-url sentrix_testnet \
  --broadcast
```

Sentrix mainnet (chain 7119): set `ALLOW_MAINNET_DEPLOY=1`.

### 3. Wire the relayer

Configure the relayer (extension of `watcher-rs/`) with:
- Source-chain RPC + vault address.
- Sentrix RPC + token address.
- Bridge minter key (HSM-backed).
- Confirmation depth per chain (see `BRIDGE_RELAYER_DESIGN.md` §2.2).
- Database connection.

## Naming recommendation

| Candidate | Verdict |
|---|---|
| `USDC.e` | **Reject for this PoC**. This convention is associated with chains where Circle has endorsed the bridge (Avalanche, Polygon zkEVM, etc.). Using it on an unendorsed bridge can mislead users. |
| `wUSDC` | Generic. Workable but less distinctive. |
| `Bridged USDC` | Clear as a name but ambiguous as a symbol. |
| `Sentrix Bridged USDC` (name) + `sUSDC` (symbol) | **Recommended.** Distinct, unambiguous, signals provenance. |
| `sUSDC` | Recommended as ticker. Concise, distinct from real USDC. |

Recommendation: deploy as `name = "Sentrix Bridged USDC"`, `symbol = "sUSDC"`.
Documented in the constructor; can be changed before deployment but should be
locked in for testnet bake.

## Production-readiness checklist

- [ ] All role holders are multisigs (no EOA in production)
- [ ] External audit of `SourceChainVault` + `SentrixBridgedUSDC`
- [ ] Reserve-check loop running in `watcher-rs` (auto-pause on mismatch)
- [ ] Reorg watcher running for each source chain
- [ ] Per-deposit dedup table (`processed_events`) in production DB
- [ ] Confirmation depth configured per source chain
- [ ] Mint allowance + caps documented and tuned to expected volume
- [ ] Status page deployed showing reserve delta + recent bridge activity
- [ ] On-call rotation + per-alert runbook
- [ ] Mainnet deploy guard tested (`ALLOW_MAINNET_DEPLOY` gating)
- [ ] Disaster-recovery playbook rehearsed on testnet

## Legal / branding warning

- Do NOT call this token "USDC" without qualifier in user-facing surfaces. The
  word "USDC" without "Bridged" or "Sentrix" prefix implies Circle issuance.
- Add a visible disclaimer everywhere the symbol appears (bridge UI, DEX
  listing, docs): "Sentrix-bridged USDC. Not Circle USDC. Backed 1:1 by USDC
  locked in a Sentrix-operated vault on Ethereum."
- If/when Circle agrees to upgrade this to native USDC under the Bridged USDC
  Standard, the entire token contract must be redeployed because this PoC is
  non-upgradeable.

## Security references

- Risk register: `SECURITY_NOTES.md`
- Relayer + DB design: `BRIDGE_RELAYER_DESIGN.md`
- Internal audit log: `docs/bridge/Audit.internal`
- Circle Bridged USDC Standard: https://www.circle.com/blog/bridged-usdc-standard
- Circle reference implementation: https://github.com/circlefin/stablecoin-evm
