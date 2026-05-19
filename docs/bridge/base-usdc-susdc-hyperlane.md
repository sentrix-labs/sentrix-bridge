# Base USDC to Sentrix sUSDC Hyperlane Warp Route

## Architecture

The target route is a 1:1 bridged USDC asset, not an algorithmic stablecoin and not SRX-backed debt.

- Base: Circle native USDC is locked in a Hyperlane ERC20 collateral router.
- Sentrix: Hyperlane synthetic ERC20 is deployed as `Sentrix Bridged USDC` / `sUSDC` with `6` decimals.
- Base -> Sentrix: user approves Base USDC, sends through the collateral router, Hyperlane verifies the message, Sentrix mints sUSDC to the recipient.
- Sentrix -> Base: user sends sUSDC through the Sentrix router, sUSDC burns, Hyperlane verifies the message on Base, Base router releases USDC.

Warning text for every UI surface:

> sUSDC is bridged USDC on Sentrix, backed 1:1 by USDC locked on Base through the official Sentrix bridge route.

## Current Repo State

Existing Sentrix Testnet Hyperlane core:

- Mailbox: `0x9741D99270aF14D4baca0e387B6ac0500b9a288F`
- MerkleTreeHook: `0x6A192C8fEA612CA3aa204035e51F6a624b0F1467`
- Default ISM: `0x28834AA535F3130f0F60571Ac7a813195aE56eC6`

The current ISM is NoopIsm and is unsafe for value. It is acceptable for zero-value smoke tests only. Deploy MultisigIsm or stronger verification before any funded route test.

## Config Files

- `hyperlane/registry/chains/basesepolia/metadata.yaml`
- `hyperlane/registry/chains/base/metadata.yaml`
- `hyperlane/registry/chains/sentrixtestnet/metadata.yaml`
- `hyperlane/registry/chains/sentrixmainnet/metadata.yaml`
- `hyperlane/warp-routes/base-usdc-sentrix-susdc/testnet.yaml`
- `hyperlane/warp-routes/base-usdc-sentrix-susdc/mainnet.yaml`
- `hyperlane/warp-routes/base-usdc-sentrix-susdc/cap-policy.json`
- `deployments/base-usdc-susdc-testnet.json`
- `deployments/base-usdc-susdc-mainnet.json`

## Deployment Flow

Testnet first:

1. Fill `.env` from `.env.example`.
2. Run `scripts/bridge/check-env.sh testnet`.
3. Run `scripts/bridge/check-chain-metadata.sh testnet`.
4. Run `scripts/bridge/prepare-hyperlane-cli.sh` if no global Hyperlane CLI is available.
5. Run `scripts/bridge/deploy-hyperlane-core-sentrix-testnet.sh --plan`.
6. Replace NoopIsm with MultisigIsm or explicitly keep the route zero-value.
7. Run `scripts/bridge/deploy-base-usdc-warp-testnet.sh --dry-run`.
8. Deploy with `ALLOW_TESTNET_WARP_DEPLOY=1` only after review.
9. Record router/token addresses in `deployments/base-usdc-susdc-testnet.json`.
10. Run `scripts/bridge/verify-deployments.sh testnet`.
11. Run both transfer direction tests manually with small amounts.

The deploy script renders a temporary Hyperlane registry and deploys route id `sUSDC/basesepolia-sentrixtestnet`, which matches the registry-based Warp Route flow in recent Hyperlane CLI versions.

Mainnet:

- Mainnet deploy is blocked until the testnet checklist passes, a MultisigIsm is active, monitoring is live, cap controls are implemented, and ownership is multisig/SentrixSafe.

## Required Tests

- Base Sepolia USDC approval succeeds.
- Base Sepolia USDC is locked in the collateral router.
- Hyperlane message is emitted.
- Relayer delivers the message.
- Sentrix Testnet sUSDC is minted to the recipient.
- sUSDC balance equals bridged amount.
- Sentrix reverse transfer burns sUSDC.
- Base Sepolia USDC is released to the recipient.
- Wrong chain ID fails.
- Wrong token fails.
- Wrong router fails.
- Paused bridge blocks transfer if a pause hook/wrapper is active.
- Cap exceeded fails if a cap hook/wrapper is active.
- Decimals remain `6`.
- Unauthorized mint fails.
- Unauthorized release fails.

## Frontend Integration

Bridge UI should add:

- Source chain: Base.
- Destination chain: Sentrix.
- Asset: sUSDC.
- Directions: `Base USDC -> Sentrix sUSDC` and `Sentrix sUSDC -> Base USDC`.
- Amount input fixed to 6 decimals.
- Approval step for Base USDC.
- Transfer step for Hyperlane Warp Route.
- Message status tracking from dispatch to delivery.
- Estimated gas/payment display.
- Base transaction links to BaseScan.
- Sentrix transaction links to Sentrix explorer.
- The warning text from the Architecture section.

Do not show a mint UI, admin UI, or manual release UI to users.

## Explorer And Token List Integration

After testnet deployment:

1. Add sUSDC to `sentrix-token-list` using the deployed Sentrix router/token address.
2. Add a placeholder sUSDC logo with clear `sUSDC` labeling.
3. Add explorer token metadata for name, symbol, decimals, and official bridge route.
4. Add docs pages:
   - How to bridge USDC from Base to Sentrix.
   - How to add SRX/sUSDC liquidity.
   - How to swap SRX with sUSDC.

Do not add placeholder token addresses to production token lists.

## DEX Integration

After the bridge test passes:

- Add SRX/sUSDC pair config to `sentrix-dex`.
- Prefer SRX/sUSDC for SRX price routing.
- Use SRX/sUSDT only as secondary routing when available.
- Seed liquidity only through normal LP deposits; no custody shortcut or protocol-owned invisible balance.
- Surface sUSDC as a bridged asset, not native Circle USDC.

## Monitoring Plan

Monitor:

- Base collateral router USDC balance.
- Sentrix sUSDC total supply.
- Invariant: `sUSDC totalSupply <= Base locked USDC`.
- Pending Hyperlane messages.
- Failed message delivery.
- Validator/relayer health.
- Base and Sentrix RPC health.
- Bridge latency.
- Daily bridged volume.
- Cap usage.
- Router owner and ISM address drift.

Use `scripts/bridge/monitor-bridge-health.sh testnet` as the first read-only check. Extend it with Hyperlane agent metrics and message indexing before mainnet.

## Security Checklist

- No private keys in repo.
- `.env.example` contains placeholders only.
- Chain IDs validated before every script path.
- Base USDC address pinned per environment.
- USDC decimals validated as `6`.
- sUSDC decimals validated as `6`.
- Mailbox addresses verified from registry/deployment manifests.
- Remote routers enrolled both directions.
- Owner/admin is SentrixSafe or multisig.
- EOA ownership, if used on testnet, is documented as beta risk.
- No arbitrary minting path.
- No arbitrary Base USDC release path.
- No admin function can withdraw user funds.
- MultisigIsm or stronger verification active before value.
- Relayer can affect liveness, not validity.
- Per-transaction, daily, and total mint caps are enforced before mainnet beta.
- Documentation-only caps are not sufficient; use a reviewed Hyperlane-compatible hook or wrapper if the selected Warp Route contracts cannot enforce all cap semantics directly.
- Pause path exists through Hyperlane-compatible hook/wrapper or documented emergency procedure.

## Mainnet Beta Checklist

- Testnet route passes both directions with real Base Sepolia USDC.
- NoopIsm removed from all value routes.
- Validator set is independent and threshold is documented.
- Relayer runs from monitored production infrastructure.
- SentrixSafe or multisig owns all routers and admin surfaces.
- Cap controls are deployed and tested:
  - `perTxCap`
  - `dailyCap`
  - `totalMintCap`
- Monitoring has alerting and runbook links.
- Explorer and token-list entries are correct.
- Frontend warning text is live.
- Incident drill completed.
- External security review complete.
- Explicit mainnet approval recorded.

## Incident Runbook

Severity 0: forged mint, unauthorized release, or invariant breach.

1. Pause route through the configured pause hook/wrapper or remove frontend entry if no on-chain pause is available.
2. Stop relayer delivery for the affected route.
3. Snapshot Base collateral balance, Sentrix sUSDC total supply, router owners, ISM addresses, and latest delivered messages.
4. Identify last valid message and first suspicious message.
5. Notify users that the route is paused and withdrawals may be delayed.
6. If synthetic supply exceeds locked collateral, do not resume until governance/multisig signs a remediation plan.
7. Rotate compromised keys and replace ISM/owner if needed.
8. Publish a postmortem with exact affected tx hashes and user impact.

Severity 1: relayer outage or stuck messages.

1. Keep route live if validity is not impacted.
2. Restart relayer or fail over to backup relayer.
3. Backfill message delivery.
4. Monitor latency until normal.

Severity 2: RPC degradation.

1. Switch configured RPC endpoint.
2. Confirm chain IDs after switching.
3. Re-run deployment verification.

Resume criteria:

- Invariant holds.
- ISM and router enrollment are correct.
- Relayer is healthy.
- Multisig signs resume decision.
