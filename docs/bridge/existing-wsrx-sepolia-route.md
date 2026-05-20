# Existing wSRX Sepolia Route

This repo already contains a working testnet Hyperlane Warp Route artifact for:

- Source/destination: Sentrix Testnet `<->` Ethereum Sepolia
- Asset: `wSRX`
- Sentrix token: `WSRX` at `0x85d5E7694AF31C2Edd0a7e66b7c6c92C59fF949A`
- Sentrix router: `HypERC20Collateral` at `0xfb8190927034c447Fc29B1cfbF4f4F000969bb32`
- Sepolia synthetic token/router: `HypERC20 wSRX` at `0xC4BDE56bCAadfDbD6fBad685b65628f05994e5a8`
- Artifact: `deployments/hyperlane-warp-route.json`

This is not the Base Sepolia USDC -> Sentrix sUSDC route. Do not redeploy this
route while investigating Base USDC work unless the artifact is proven invalid.

## Current Status

The route is protocol-proven but testnet-only:

- Sentrix Testnet mailbox: `0x9741D99270aF14D4baca0e387B6ac0500b9a288F`
- Sepolia mailbox: `0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766`
- Sentrix route ISM: `0x28834AA535F3130f0F60571Ac7a813195aE56eC6` (`NoopIsm`)
- Sepolia route ISM: `0x1b11f19EbB371A88AF8be0B5B4a7bAa5b471246d` (`NoopIsm`)

NoopIsm accepts messages without production-grade validator verification. Use
this route only for smoke tests and local/operator testnet validation. Do not
bridge real value, do not call it production-grade, and do not use this security
model for mainnet.

The artifact records a successful prior demo:

- Sentrix bridge tx: `0x4e2582c2704160dc4770fe24f9ab677ddce121ea36856507aa20108adebf9f63`
- Sepolia mint tx: `0x0c1af7f4cbe247006be72b35e60199810d227654f2498221c33f1661f166d56f`
- Verified minted balance: `0.001 wSRX`

The artifact also records a fresh-user blocker: wrapping native SRX to WSRX has
been affected by the Sentrix testnet EVM value-passing gate. Existing WSRX can
still exercise the Hyperlane route path, and zero-amount message proofs exist.

## Read-Only Verification

Run this first. It does not sign, deploy, or bridge:

```bash
scripts/bridge/verify-existing-wsrx-route.sh
```

Optional RPC overrides:

```bash
SENTRIX_RPC=https://testnet-rpc.sentrixchain.com \
SEPOLIA_RPC=<sepolia-rpc> \
scripts/bridge/verify-existing-wsrx-route.sh
```

Expected result:

- Sentrix chain ID is `7120`.
- Sepolia chain ID is `11155111`.
- Sentrix collateral ISM matches the artifact NoopIsm.
- Sepolia HypERC20 ISM matches the artifact NoopIsm.
- Enrolled remotes are readable.
- Decimals are `18`.

## Existing Test Runbook

The previous operator runbook is:

```bash
SENTRIX_RPC=https://testnet-rpc.sentrixchain.com \
SEPOLIA_RPC=<sepolia-rpc> \
FRESH_USER_PK=<local-testnet-only-private-key> \
RELAYER_PK=<local-testnet-only-relayer-private-key> \
scripts/runbooks/fresh-user-verify.sh
```

Do not commit or print the private keys. This script broadcasts testnet
transactions and currently exits with code `4` after Sentrix-side broadcast
steps because manual Sepolia relay and final mint verification are operator
follow-up steps.

## Shortest Safe Path

1. Run `scripts/bridge/verify-existing-wsrx-route.sh`.
2. If the route matches the artifact, reuse it for smoke testing instead of redeploying.
3. If a live test is needed, use `scripts/runbooks/fresh-user-verify.sh` with funded testnet-only wallets.
4. Treat any NoopIsm result as smoke-test-only.
5. Replace NoopIsm with MultisigIsm before any funded/value route testing.
6. Keep Base Sepolia USDC -> Sentrix sUSDC as a separate route and do not infer it exists from this wSRX artifact.

## Production Blockers

- Replace NoopIsm on both sides with MultisigIsm or a stronger ISM.
- Run validators and relayers 24/7 with alerting.
- Keep final route owner/admin on a Safe or equivalent multisig.
- Add caps before any value route: per-transaction, daily, and total minted supply.
- Monitor locked collateral vs minted supply.
- Monitor pending and failed Hyperlane messages.
- Keep mainnet deployment blocked until testnet validation and security review pass.
