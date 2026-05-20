# Deployment runbook — Sentrix Bridged USDC

> Use ONLY for testnet (Sentrix 7120 + Sepolia) until Phase 3 mainnet sign-off.
> Mainnet deploy is gated on completing the `CIRCLE_HANDOFF_READINESS.md` checklist.

## Prerequisites

### Tooling

- Node 20.9.0 (per `circlefin/stablecoin-evm/.nvmrc`)
- Yarn 1.22.19
- Foundry — pinned to the version in Circle's repo's `package.json` (currently `f625d0fa7c51e65b4bf1e8f7931cd1c6e2e285e9`). Sentrix's local `forge --version` is `1.6.0-v1.7.0` which is newer but should be ABI-compatible for these contracts. Verify before mainnet.
- A funded deployer EOA on both Sepolia and Sentrix testnet. Keep private key in HSM / encrypted keystore — never plaintext.

### Operator key setup (one-time, before any deployment)

Phase 1 / Phase 2 runs on single-sig operator EOAs per
`BOOTSTRAP_ROLE_HOLDER.md`. Multisig is a Phase 3b graduation
milestone, not a Phase 1 launch requirement.

Provision:

1. **Source-chain operator key (Sepolia / Ethereum):** holds
   `DEFAULT_ADMIN_ROLE`, `OPERATOR_ROLE`, `PAUSER_ROLE` on the source
   bridge. Different physical key from #2 (role-family separation).
2. **Sentrix-chain operator key:** holds FiatToken `admin`, `owner`,
   `masterMinter`, `pauser`, `blacklister`, `rescuer`. Best practice:
   split `admin` (proxy) from `owner` (impl) into two distinct EOAs even
   when both held by operator — so a compromise of one doesn't pwn both.

Key custody:
- HSM (AWS KMS / Google Cloud KMS / Ledger / Trezor) — NEVER plaintext.
- Encrypted seed-phrase backup in two geographically separate locations.
- Per earned-rule `feedback_no_wallet_txt_in_chat`: NEVER paste private
  keys or mnemonics into chat / scrollback / logs.

Multisig migration plan (later, see `BOOTSTRAP_ROLE_HOLDER.md`):
threshold 2-of-3 when first co-signer recruited, 4-of-7 by Phase 3c.

## Step 1 — Clone Circle's `stablecoin-evm` (NOT a submodule of this repo)

```bash
cd ~
git clone https://github.com/circlefin/stablecoin-evm.git
cd stablecoin-evm
nvm use
npm i -g yarn@1.22.19
yarn install
```

Why not a submodule: Circle's repo includes Hardhat + their own build
pipeline. Vendoring it into `sentrix-bridge` would create a multi-tool
project (Foundry + Hardhat) which complicates CI and audit. Keep them
separate; deploy from the Circle repo, configure address on Sentrix bridge.

## Step 2 — Compile FiatTokenV2_2 (Sentrix-bound)

In `stablecoin-evm` working tree:

```bash
yarn compile
# Verify exact solc version + optimizer:
grep -A 3 "solidity" hardhat.config.ts | head -10
# Expected:
#   version: "0.6.12"
#   runs: 10000000
```

Capture the compiler metadata JSON (auto-generated under `artifacts/` after
`yarn compile`). This is the artifact Circle expects for verification at
upgrade time.

## Step 3 — Deploy FiatTokenV2_2 implementation on Sentrix testnet

```bash
cd ~/stablecoin-evm
# Edit migrations/direct/4_initial_setup.js OR write a custom Hardhat script
# that:
# 1. Deploys FiatTokenV2_2 (implementation only)
# 2. Calls initialize(), initializeV2(), initializeV2_1(), initializeV2_2()
#    on the implementation directly with THROWAWAY values
#    (per Circle docs: prevents anyone hijacking the implementation)

# Set RPC + deployer
export RPC_URL=https://testnet-rpc.sentrixchain.com
export DEPLOYER_PK=...   # HSM-backed key

# Deploy implementation
yarn hardhat run scripts/deploy-implementation.js --network sentrix_testnet

# Record the implementation address. Verify on scan.sentrixchain.com.
```

Save the implementation address. Will be used in Step 4.

## Step 4 — Deploy FiatTokenProxy + initialize through proxy

```bash
# Roles for initialization. Phase 1: SentrixSafe (currently 1-of-1).
# Phase 3b+: multisig addresses. See BOOTSTRAP_ROLE_HOLDER.md.
export FIATTOKEN_NAME="Bridged USDC (Sentrix)"
export FIATTOKEN_SYMBOL=USDC.e
export FIATTOKEN_DECIMALS=6
export FIATTOKEN_CURRENCY=USD
export ADMIN_ADDR=...           # 1-of-1 SentrixSafe — proxy admin (can be same as OWNER or separate)
export OWNER_ADDR=...           # 1-of-1 SentrixSafe — impl owner
export MASTER_MINTER_ADDR=...   # 1-of-1 SentrixSafe — master minter
export PAUSER_ADDR=...          # operator EOA
export BLACKLISTER_ADDR=...     # operator EOA
export RESCUER_ADDR=...         # operator EOA

# 1. Deploy FiatTokenProxy(implementationAddress) — proxy.admin defaults to deployer EOA
# 2. As deployer EOA, call proxy.changeAdmin(ADMIN_ADDR) IMMEDIATELY
#    (the deployer EOA loses any privileged proxy access after this point)
# 3. Call initialize(...) through the proxy (FiatTokenV2_2 ABI):
#    initialize(name, symbol, currency, decimals, masterMinter, pauser, blacklister, owner)
# 4. Call initializeV2(name)  - re-sets the EIP-712 name
# 5. Call initializeV2_1(rescuer)
# 6. Call initializeV2_2([], symbol)
# 7. As OWNER_ADDR, call updateRescuer(RESCUER_ADDR)
```

Verify post-deployment:
- `proxy.admin()` == ADMIN_ADDR
- `fiatToken.owner()` == OWNER_ADDR
- `fiatToken.masterMinter()` == MASTER_MINTER_ADDR
- `fiatToken.pauser()` == PAUSER_ADDR
- `fiatToken.blacklister()` == BLACKLISTER_ADDR
- `fiatToken.rescuer()` == RESCUER_ADDR
- `fiatToken.name()` == "Bridged USDC (Sentrix)"
- `fiatToken.symbol()` == "USDC.e"
- `fiatToken.decimals()` == 6
- `fiatToken.totalSupply()` == 0

Record:
- Implementation address
- Proxy address (this is the **canonical USDC.e address** — never changes,
  including across the future Circle upgrade)
- All role addresses

## Step 5 — Deploy SentrixUSDCSourceBridge on Sepolia

From `sentrix-bridge/` (this repo):

```bash
# Compile
forge build src/circle-bridged/

# Deploy via Foundry script (when scripts/circle-bridged/Deploy*.s.sol added)
export SEPOLIA_RPC=https://sepolia.infura.io/v3/...
export DEPLOYER_PK=...
export SOURCE_USDC=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238  # Sepolia USDC (VERIFY)
export SENTRIX_CHAIN_ID=7120
export SOURCE_ADMIN=...      # source-chain operator EOA
export SOURCE_OPERATOR=...   # source-chain operator EOA (Phase 1)
export SOURCE_PAUSER=...     # source-chain operator EOA

# 1. Deploy SentrixUSDCSourceBridge implementation
# 2. Deploy ERC1967Proxy(impl, abi.encodeWithSelector(initialize.selector, usdc, sentrixChainId, admin, operator, pauser))
# 3. Verify proxy.admin() inheritance + roles via cast call
```

(Deploy script is a Phase 1B task — operator should write following the same
pattern as `scripts/stablecoin/DeploySentrixBridgedUSDC.s.sol` but for the
proxy + impl pair.)

## Step 6 — Configure destination bridge minter on FiatToken

PHASE 1 (operator-driven):
```
# As masterMinter (operator EOA) on Sentrix:
fiatToken.configureMinter(operatorRelayerAddress, 10000_000000)  # 10,000 USDC cap

# Operator relayer is now allowed to mint up to 10K USDC.e per allowance
# refresh cycle.
```

PHASE 2 (Hyperlane):
```
# Replace operatorRelayerAddress with HypFiatToken contract address
fiatToken.configureMinter(hypFiatTokenAddress, 10000_000000)
fiatToken.removeMinter(operatorRelayerAddress)
```

## Step 7 — Smoke test (testnet)

1. Deposit 10 USDC on Sepolia: `usdc.approve(bridge); bridge.deposit(myAddrOnSentrix, 10_000000)`.
2. Watcher detects → operator EOA signs `fiatToken.mint(myAddrOnSentrix, 10_000000)`.
3. Verify `fiatToken.balanceOf(myAddrOnSentrix) == 10_000000` on Sentrix.
4. Reverse: `fiatToken.transfer(operatorAddr, 10_000000)` then operator burns
   and signals source bridge → `bridge.release(withdrawalId, myAddrOnSepolia, 10_000000)`.
5. Verify USDC returned on Sepolia.
6. Run reserve check: `bridge.totalLocked()` == `fiatToken.totalSupply()` (within in-flight tolerance).

## Step 8 — Pause + unpause test

1. `pauser.pauseBridging()` (source)
2. `fiatToken.pause()` (destination)
3. Verify deposits + mints + burns + transfers all revert
4. `pauser.unpauseBridging()` + `fiatToken.unpause()` to resume

## Step 9 — Circle hooks dry-run

DO NOT execute these unless Circle actually initiates the upgrade. Documented
here for runbook completeness.

```
# Admin grants Circle's specified burn address the role:
sourceBridge.grantRole(CIRCLE_BURN_ROLE, circleSpecifiedBurnAddr)

# Circle separately grants the source bridge a zero-allowance minter role
# on Ethereum USDC (Circle's action on the real USDC contract, not ours).

# Circle's burn address calls:
sourceBridge.burnLockedUSDC()

# Admin grants Circle's specified role-transfer address the role:
sourceBridge.grantRole(CIRCLE_ROLE_TRANSFER_ROLE, circleSpecifiedRoleAddr)

# Circle's role-transfer address calls:
sourceBridge.transferUSDCRoles(circleAddr)
# In Phase 2 this dispatches a cross-chain Hyperlane message that on the
# Sentrix side calls FiatToken.transferOwnership + FiatTokenProxy.changeAdmin.
# In Phase 1 this reverts with the documented "Phase 2: Hyperlane wiring required"
# message — Circle handoff requires Phase 2 first.
```

## Mainnet (Phase 3)

Same flow as testnet but:
- Replace Sepolia USDC address with Ethereum mainnet USDC (`0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`)
- Replace SENTRIX_CHAIN_ID with 7119
- Use mainnet RPC for Sentrix
- All role addresses are MAINNET keys, NEVER reuse testnet keys (Phase 3a may still be single-sig per `BOOTSTRAP_ROLE_HOLDER.md`; Phase 3b+ multisig)
- Set `ALLOW_MAINNET_DEPLOY=1` if deploy script has guard
- External audit must be complete first
- Run mirror test: testnet AND mainnet configurations must match exactly
  (per Circle Standard requirement for upgrade eligibility)

## Verification artifacts to keep

For Circle's future review:
- Compiler metadata JSON (auto-generated by Hardhat under `artifacts/`)
- Deployment transaction hashes for implementation + proxy + init calls
- All role-grant transaction hashes
- Initial minter configuration transaction hash
- Mainnet ↔ testnet configuration diff (must be near-empty)

Store at `~/founder-private/usdc-deploy-artifacts/` with date stamp. Do NOT
commit private deployment artifacts to the public bridge repo.
