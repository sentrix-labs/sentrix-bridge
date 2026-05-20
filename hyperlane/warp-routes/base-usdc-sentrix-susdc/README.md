# Base USDC to Sentrix sUSDC Warp Route

This directory contains Hyperlane CLI-compatible deployment configs for the official Sentrix bridged USDC route.

## Route

- Base Sepolia USDC `0x036CbD53842c5426634e7929541eC2318f3dCF7e` -> Sentrix Testnet `sUSDC`
- Base Mainnet USDC `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` -> Sentrix Mainnet `sUSDC`
- `sUSDC` metadata: `Sentrix Bridged USDC`, symbol `sUSDC`, decimals `6`

## Security Position

The route is non-custodial at the user level: users approve and transfer USDC into the Base collateral router; Hyperlane-verified messages mint synthetic sUSDC on Sentrix; reverse transfers burn sUSDC and release USDC from the Base collateral router.

Do not use NoopIsm for value. Sentrix Testnet currently has a known NoopIsm in `deployments/hyperlane-testnet.json`; use this route for config validation only until MultisigIsm or stronger verification is active.

## Deployment Order

1. Fill `.env` from `.env.example`.
2. Run `scripts/bridge/check-env.sh testnet`.
3. Run `scripts/bridge/check-chain-metadata.sh testnet`.
4. Ensure Base Sepolia Hyperlane core addresses are set.
5. Replace Sentrix Testnet NoopIsm with MultisigIsm or explicitly limit to zero-value smoke testing.
6. Run `scripts/bridge/deploy-base-usdc-warp-testnet.sh --dry-run`.
7. Run deployment only after dry-run output is reviewed.

Mainnet uses the same process but is blocked until the checklist in `docs/bridge/base-usdc-susdc-hyperlane.md` is complete.
