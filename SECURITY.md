# Security policy

## Secrets

- **Never commit `.env` or any file containing a private key.** `.gitignore` blocks `.env*` patterns.
- The deployer key for bridge contracts and the relayer signer key live off-repo. Reference them via env vars (`DEPLOYER_PRIVATE_KEY`, `RELAYER_PRIVATE_KEY`) only — never inline in scripts.
- If you suspect a leak, rotate the key immediately and notify `security@sentrixchain.com`.

## Vulnerability disclosure

Email **`security@sentrixchain.com`** with reproducer + impact assessment, or open a private GitHub Security Advisory at <https://github.com/sentrix-labs/sentrix-bridge/security/advisories/new>.

We acknowledge within 24 hours and provide an initial assessment within 72 hours.

Do not file public issues for security bugs.

## Current state

Sentrix Bridge is currently a **manual-relay** bridge between Sentrix Testnet and Sepolia, built on Hyperlane v3 with a `NoopIsm`. Production hardening — `MultisigIsm`, 24/7 agents, audited UI, formal third-party audit — is still in progress. Treat anything labelled `Beta` here as pre-audit code; do not bridge value you are not willing to lose.

## Scope

In scope:

- Bridge contracts in `hyperlane/` and `external/`
- Deploy and relay scripts in `scripts/`
- `foundry.toml` and CI workflow
- Subgraph indexing logic in `subgraph/`

Out of scope (covered elsewhere):

- Sentrix node / consensus (`sentrix-labs/sentrix`)
- Canonical contracts (`sentrix-labs/canonical-contracts`)
- Hyperlane core library itself — report upstream to Hyperlane
