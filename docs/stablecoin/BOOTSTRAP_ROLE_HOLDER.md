# Bootstrap role holder — SentrixSafe

> **Updates and supersedes `SINGLE_SIG_BOOTSTRAP_POLICY.md` for terminology.**
> The bootstrap role holder model is **SentrixSafe** — Sentrix Labs' custom
> multi-signature wallet contract from `sentrix-labs/canonical-contracts`.
> Not Gnosis Safe, not raw EOA, not a chain-validator-set multisig.

## What SentrixSafe is

- Source: `sentrix-labs/canonical-contracts/contracts/SentrixSafe.sol` (BUSL-1.1).
- Gnosis-Safe-**inspired** but stripped down — no modules, no guards, no
  fallback handler. Just the "execute-from-N-of-M-owners core."
- Threshold-configurable; owners approve via off-chain EIP-712 typed
  signatures; on-chain `execTransaction` verifies signatures against the
  sorted owner list, then performs the call.
- Currently runs as **1-of-1**: the operator's Authority address is the sole
  owner. Expandable to N-of-M via `addOwner()` + `changeThreshold()`.

## What SentrixSafe is NOT

- NOT Gnosis Safe (deliberately not SDK-compatible).
- NOT a chain-validator-set multisig. Sentrix consensus validators are NOT
  bridge signers. SentrixSafe owners are independent of validator set.
- NOT a protocol-controlled address (it has actual owners, not a no-key
  system account).
- NOT raw EOA. It's a smart contract that wraps the operator's signing key
  so that key rotation + future N-of-M expansion can happen without
  changing the SentrixSafe address that's wired into every privileged role.

## Existing deployments

| Network | Chain ID | SentrixSafe address |
|---|---|---|
| Sentrix mainnet | 7119 | `0x6272dC0C842F05542f9fF7B5443E93C0642a3b26` |
| Sentrix testnet | 7120 | `0xc9D7a61D7C2F428F6A055916488041fD00532110` |
| Sepolia | 11155111 | NOT YET DEPLOYED — deploy before source-chain Phase 1 |
| Ethereum mainnet | 1 | NOT YET DEPLOYED — Phase 3 only |

Operator's Authority sole-owner address (public, signer of SentrixSafe txns):
`0xa25236925bc1…` (full address in private notes; the private key itself
is operator-held and never disclosed).

## Why use SentrixSafe for the Circle Bridged USDC roles

1. **Same address survives signer rotation.** The Authority key can be
   rotated by adding the new key as a SentrixSafe owner + removing the
   old key, without changing any wired role assignment in FiatToken
   proxy or source bridge.
2. **Same address survives threshold expansion.** When the operator
   recruits co-signers, threshold goes 1→2→3 without changing any role
   wiring.
3. **Consistent with existing Sentrix ecosystem.** SentrixSafe already
   holds Strategic Reserve migration authority (per
   `founder-private/CANONICAL_ADDRESSES.md`), holds existing LayerZero
   EndpointV2 ownership (per `.env.example` `SENTRIX_SAFE`), and is the
   pattern documented in `sentrix-labs/whitepaper`.
4. **No validator-set entanglement.** Bridge signing flows through Safe
   owners, not chain consensus validators. Critical separation of
   concerns.

## Mapping to Circle Bridged USDC Standard roles

### Sentrix-side (chain 7120 / 7119) — FiatTokenV2_2 proxy

| FiatToken role | Bootstrap holder |
|---|---|
| `admin` (AdminUpgradeabilityProxy) | SentrixSafe |
| `owner` (impl-level) | SentrixSafe |
| `masterMinter` | SentrixSafe (will configure HypFiatToken or bridge handler as minter via `configureMinter`) |
| `pauser` | SentrixSafe |
| `blacklister` | SentrixSafe |
| `rescuer` | SentrixSafe |

All six roles point to the same SentrixSafe address by default. Operator
may split if/when separating role families is desired; the contracts allow
arbitrary mappings.

### Source-chain side (Sepolia, later Ethereum) — `SentrixUSDCSourceBridge`

| Source bridge role | Bootstrap holder |
|---|---|
| `DEFAULT_ADMIN_ROLE` | SentrixSafe on source chain |
| `OPERATOR_ROLE` | SentrixSafe on source chain (Phase 1) → Hyperlane Mailbox handler (Phase 2 optional) |
| `PAUSER_ROLE` | SentrixSafe on source chain |
| `CIRCLE_BURN_ROLE` | EMPTY at deploy. Granted by admin only at Circle handoff time to Circle-specified address. |
| `CIRCLE_ROLE_TRANSFER_ROLE` | EMPTY at deploy. Granted by admin only at Circle handoff time to Circle-specified address. |

**Open operational decision** for source chain:
- **Option A (recommended):** deploy SentrixSafe on Sepolia first
  (`sentrix-labs/canonical-contracts/contracts/SentrixSafe.sol` is
  chain-agnostic — same bytecode works on any EVM chain). Initialize
  with the same Authority as sole owner. Roles point to it.
- **Option B (fallback):** use the Authority EOA address directly as
  source-bridge role holder. Less flexibility for future rotation /
  expansion, but acceptable for testnet bootstrap if Safe deployment
  on Sepolia is delayed.

Operator picks. Both paths preserve the Circle Standard compliance.

## Env var naming (matches existing `.env.example`)

Existing canonical:
```
SENTRIX_SAFE=0xc9D7a61D7C2F428F6A055916488041fD00532110   # testnet 7120
```

For the Circle Standard deploy, we ADD:
```
SENTRIX_SAFE_MAINNET=0x6272dC0C842F05542f9fF7B5443E93C0642a3b26   # mainnet 7119 — DO NOT USE for mainnet deploy yet
SOURCE_SAFE_SEPOLIA=                                              # set after deploying SentrixSafe on Sepolia
SOURCE_SAFE_ETHEREUM=                                             # Phase 3 only
```

Role-level defaults:
```
# Sentrix-side FiatToken roles default to SENTRIX_SAFE (testnet) or
# SENTRIX_SAFE_MAINNET (mainnet)
TOKEN_PROXY_ADMIN=${TOKEN_PROXY_ADMIN:-$SENTRIX_SAFE}
TOKEN_OWNER=${TOKEN_OWNER:-$SENTRIX_SAFE}
TOKEN_MASTER_MINTER=${TOKEN_MASTER_MINTER:-$SENTRIX_SAFE}
TOKEN_PAUSER=${TOKEN_PAUSER:-$SENTRIX_SAFE}
TOKEN_BLACKLISTER=${TOKEN_BLACKLISTER:-$SENTRIX_SAFE}
TOKEN_RESCUER=${TOKEN_RESCUER:-$SENTRIX_SAFE}

# Source-bridge roles default to SOURCE_SAFE_SEPOLIA (testnet) or
# SOURCE_SAFE_ETHEREUM (mainnet)
SOURCE_ADMIN=${SOURCE_ADMIN:-$SOURCE_SAFE_SEPOLIA}
SOURCE_OPERATOR=${SOURCE_OPERATOR:-$SOURCE_SAFE_SEPOLIA}
SOURCE_PAUSER=${SOURCE_PAUSER:-$SOURCE_SAFE_SEPOLIA}
```

## Deployer key

`DEPLOYER_PK` is used only for the deployment broadcast. It does NOT
retain any privileged role after deployment — the post-deploy state has
all roles pointing at SentrixSafe, and the deployer key is irrelevant
afterwards.

Per `feedback_no_wallet_txt_in_chat`: NEVER plaintext, NEVER in
scrollback, NEVER in commits.

## Future N-of-M expansion

When the operator recruits co-signers:

1. Identify co-signer public keys / hardware wallet addresses.
2. From SentrixSafe (with current Authority as sole owner), call
   `addOwner(newOwner, newThreshold)` for each. After enough co-signers
   are added and tested, `changeThreshold(M)` to N-of-M.
3. Bridge contract role wiring is unchanged — SentrixSafe address stays
   the same.
4. Update operational runbooks (proposer/signer/executor flow).
5. Public disclosure: status page reflects new threshold + signer set.

No bridge contract changes required. This is the entire benefit of using
a Safe-like wrapper from day 1.

## What this doc does NOT change

- Contract code: `SentrixUSDCSourceBridge.sol` accepts any address as
  role holder. SentrixSafe is a contract; its address is just an
  `address` parameter at init time. No on-chain check that it's a Safe
  vs an EOA.
- Test pass rate: still 20/20 on circle-bridged + 35/35 on legacy sUSDC.
- Circle Standard alignment: unchanged. Roles point to whatever the
  partner chooses; Circle's spec doesn't mandate Safe vs EOA.
- Phase plan: same Phase 1-4 progression as before.

## What this supersedes from previous docs

- `SINGLE_SIG_BOOTSTRAP_POLICY.md` discussed "1-of-1 Gnosis Safe / 1-of-1
  Safe / 1-of-1 SentrixSafe" interchangeably and offered raw EOA as
  fallback. **This doc fixes the terminology to SentrixSafe specifically.**
  Raw EOA fallback is still acceptable if Sepolia Safe is delayed, but
  Safe is the default per operator's existing pattern.
- Any earlier doc text that said "operator EOA" in a role-holder context
  should be read as "SentrixSafe" going forward. The contracts don't care
  either way (both are just addresses).
