# Base Sepolia USDC to Sentrix Testnet sUSDC

This route is separate from the existing Sentrix Testnet `<->` Sepolia `wSRX`
route. The old `wSRX` route is useful as a reference for artifact layout,
verification scripts, and operator runbooks, but it must not be reused as USDC
infrastructure.

## Reference Route

Existing `wSRX` route:

- Sentrix WSRX: `0x85d5E7694AF31C2Edd0a7e66b7c6c92C59fF949A`
- Sentrix router: `0xfb8190927034c447Fc29B1cfbF4f4F000969bb32`
- Sepolia synthetic wSRX/router: `0xC4BDE56bCAadfDbD6fBad685b65628f05994e5a8`
- Sentrix ISM: `0x28834AA535F3130f0F60571Ac7a813195aE56eC6` (`NoopIsm`)
- Sepolia ISM: `0x1b11f19EbB371A88AF8be0B5B4a7bAa5b471246d` (`NoopIsm`)

That route is smoke-test only. NoopIsm accepts messages without production-grade
validator verification and is forbidden for the USDC route.

## Target Route

- Source chain: Base Sepolia
- Destination chain: Sentrix Testnet
- Source collateral token: Base Sepolia USDC `0x036CbD53842c5426634e7929541eC2318f3dCF7e`
- Destination synthetic token name: `Sentrix Bridged USDC`
- Destination synthetic token symbol: `sUSDC`
- Decimals: `6`
- Owner/admin: SentrixSafe `0xc9D7a61D7C2F428F6A055916488041fD00532110`
- Required ISM: MultisigIsm or stronger

sUSDC is bridged USDC on Sentrix, backed 1:1 by USDC locked on the Base route.
It is not Circle-native USDC on Sentrix.

## Current Blocker

The route is not deployed yet. The repo does not currently contain deployed
MultisigIsm addresses for this route:

- Sentrix Testnet MultisigIsm factory: pending
- Sentrix Testnet MultisigIsm: pending
- Base Sepolia MultisigIsm: pending

Deployment must wait until the local Hyperlane deployer has gas on both chains:

- Sentrix Testnet SRX
- Base Sepolia ETH

Do not fill `BASE_SEPOLIA_ISM` or `SENTRIX_TESTNET_ISM` with NoopIsm or a
placeholder. Use only verified MultisigIsm or stronger ISM addresses.

## Config Files

- `hyperlane/registry/chains/basesepolia/metadata.yaml`
- `hyperlane/registry/chains/basesepolia/addresses.yaml`
- `hyperlane/registry/chains/sentrixtestnet/metadata.yaml`
- `hyperlane/registry/chains/sentrixtestnet/addresses.yaml`
- `hyperlane/warp-routes/base-usdc-sentrix-susdc/testnet.yaml`
- `hyperlane/isms/base-usdc-sentrix-susdc/testnet.yaml`
- `deployments/base-usdc-susdc-testnet.json`

## Validation

Load local env without printing secrets:

```bash
set -a
source .env
set +a
```

Validate route config:

```bash
scripts/bridge/validate-base-usdc-warp-testnet.sh --check
```

This blocks if:

- Base Sepolia RPC or Sentrix Testnet RPC is missing.
- Base Sepolia USDC is not `0x036CbD53842c5426634e7929541eC2318f3dCF7e`.
- Owner/admin is not SentrixSafe.
- Owner/admin is the authority signer EOA.
- sUSDC decimals are not configured as `6`.
- ISM is NoopIsm.
- MultisigIsm addresses are missing.
- Mainnet env/path is selected.

## Dry Run

```bash
scripts/bridge/deploy-base-usdc-warp-testnet.sh --dry-run
```

The dry run validates config and prints the deployment command. It does not
deploy contracts.

## Deploy

Deploy testnet only after MultisigIsm is deployed and verified:

```bash
ALLOW_TESTNET_WARP_DEPLOY=1 scripts/bridge/deploy-base-usdc-warp-testnet.sh --deploy
```

Do not run this while any route ISM is NoopIsm. Do not run it for mainnet.

## Resume After Funding

After funding the local deployer, run:

```bash
set -a
source .env
set +a

scripts/bridge/validate-multisig-ism-testnet.sh --check
scripts/bridge/deploy-sentrix-multisig-ism-factory-testnet.sh --dry-run
scripts/bridge/deploy-multisig-ism-testnet.sh sentrix --dry-run
scripts/bridge/deploy-multisig-ism-testnet.sh basesepolia --dry-run
```

Deploy testnet ISM components only after those dry-runs pass:

```bash
ALLOW_TESTNET_MULTISIG_ISM_DEPLOY=1 scripts/bridge/deploy-sentrix-multisig-ism-factory-testnet.sh --deploy
ALLOW_TESTNET_MULTISIG_ISM_DEPLOY=1 scripts/bridge/deploy-multisig-ism-testnet.sh sentrix --deploy
ALLOW_TESTNET_MULTISIG_ISM_DEPLOY=1 scripts/bridge/deploy-multisig-ism-testnet.sh basesepolia --deploy
```

## Verify After Deploy

After deployment artifacts are filled with real router/token addresses:

```bash
scripts/bridge/verify-base-usdc-warp-testnet.sh --check
```

The verifier checks router code, mailbox wiring, route ISM, owner/admin,
Base collateral token, sUSDC name/symbol/decimals, and remote router
enrollment.

## Smoke Test

Only after verification passes, use small testnet amounts:

```bash
scripts/bridge/test-base-usdc-to-sentrix.sh
scripts/bridge/test-sentrix-susdc-to-base.sh
```

Do not use real mainnet USDC. Do not run smoke tests while NoopIsm is active.

## Production Blockers

- MultisigIsm or stronger ISM verified on both directions.
- Relayer running 24/7 with alerting.
- Validator/ISM agents running 24/7 where required.
- `perTxCap` implemented and verified.
- `dailyCap` implemented and verified.
- `totalMintCap` implemented and verified.
- Monitor locked Base USDC vs minted Sentrix sUSDC.
- Monitor failed and pending Hyperlane messages.
- Incident runbook ready.
- Public docs must not claim Circle-native USDC on Sentrix.
- Mainnet route must not use NoopIsm.
