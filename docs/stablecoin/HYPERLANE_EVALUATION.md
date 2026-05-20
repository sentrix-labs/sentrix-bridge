# Hyperlane evaluation for Bridged USDC transport

> Conclusion up front: **Hyperlane is the right transport for Phase 2.** The
> `HypFiatToken` extension was built specifically for Circle's FiatToken
> contracts. Integration is clean. Phase 1 stays operator-EOA-driven (single-sig bootstrap per BOOTSTRAP_ROLE_HOLDER.md)
> until MultisigIsm rollout + audit complete.

## What Hyperlane offers

Source: `https://docs.hyperlane.xyz/docs/protocol/warp-routes/warp-routes-overview`
+ `https://docs.hyperlane.xyz/docs/protocol/warp-routes/warp-routes-types`.

- **Modular ISM** — each warp route picks its own security module. We use
  `StaticMessageIdMultisigIsm` (already has deploy script at
  `scripts/DeployMultisigIsm.s.sol`).
- **Permissionless deployment** — no Hyperlane Foundation approval to add a
  new chain or warp route. Sentrix already has Hyperlane infra deployed (see
  `deployments/`).
- **HypFiatToken extension** — `hyperlane-monorepo/solidity/contracts/token/extensions/HypFiatToken.sol`.
  Calls `IFiatToken.mint(recipient, amount)` on inbound and `IFiatToken.burn(amount)`
  on outbound. EXACT MATCH for Circle's FiatToken interface.

## HypFiatToken interface verified

The contract source (`pragma solidity >=0.8.0`) imports `IFiatToken`:

```solidity
interface IFiatToken is IERC20 {
    function burn(uint256 _amount) external;
    function mint(address _to, uint256 _amount) external returns (bool);
    function minterAllowance(address _minter) external view returns (uint256);
    function isMinter(address _minter) external view returns (bool);
}
```

That interface is identical to FiatTokenV1's minter API (`circlefin/stablecoin-evm/contracts/v1/FiatTokenV1.sol`).
So HypFiatToken (0.8) can talk to FiatToken proxy (0.6.12) via ABI — different
compilers, same on-chain contract interaction.

## Integration steps

### Sentrix (destination) side

1. Deploy FiatTokenV2_2 + AdminUpgradeabilityProxy + initialization (per
   `circlefin/stablecoin-evm/migrations/`).
2. Deploy HypFiatToken contract with `_fiatToken = FiatToken proxy address`,
   `_mailbox = Sentrix Hyperlane Mailbox address`.
3. `masterMinter` calls `FiatToken.configureMinter(HypFiatToken_address, initialAllowance)`.
4. HypFiatToken is now a configured minter with allowance.
5. Set `HypFiatToken.interchainSecurityModule = MultisigIsm`.
6. Enroll remote routers on HypFiatToken (`HypFiatToken.enrollRemoteRouter(sourceDomain, sourceBridgeAddress)`).

### Sepolia (source) side

Two architectural choices for Phase 2:

**Option A — HypERC20Collateral as the source bridge.** Stock Hyperlane.
Locks USDC on Sepolia, sends Hyperlane message, HypFiatToken on Sentrix
mints. SIMPLE but lacks Circle's `transferUSDCRoles` + `burnLockedUSDC` hooks
on the source side — these would need to live in a SEPARATE wrapper contract
or be added via a wrapping pattern.

**Option B — Custom `SentrixUSDCSourceBridge` (current scaffold) + Hyperlane
Mailbox direct integration.** Custom bridge holds USDC + Circle hooks +
sends Hyperlane messages directly via Mailbox. SOMEWHAT MORE CODE but the
hooks are in the right place.

**Recommendation: Option B.** The Circle Bridged USDC Standard requires
`transferUSDCRoles` + `burnLockedUSDC` on the source bridge contract. Stock
HypERC20Collateral lacks them. A wrapper around HypERC20Collateral adds a
layer of indirection that complicates the role transfer at upgrade time.
The custom bridge (current scaffold) is cleaner.

### Hyperlane wiring (Phase 2 work)

Source bridge needs to:
1. Inherit from Hyperlane's `Router` or `MailboxClient` base.
2. On `deposit`: build a `TokenMessage` with `(recipient, amount)` and call
   `Mailbox.dispatch(sentrixDomain, recipientHypFiatToken, message)`.
3. On inbound message (withdrawal from Sentrix): receive via Mailbox →
   parse `TokenMessage` → `release(amount, recipient)`.

Storage layout for Phase 2 upgrade: append new state to the existing `__gap`
slot. Run storage-layout diff before deploying upgrade.

## What Hyperlane does NOT give us

- Built-in rate limiting per chain/period. Must add at FiatToken minter
  allowance level OR add custom rate limiter to source bridge.
- Automated reorg recovery. Source-chain reorg post-mint = supply mismatch
  requiring operator intervention. Reserve monitor catches this.
- Decentralized validator set out-of-the-box. We provide our own set of
  validators initially; decentralize over time (see `SECURITY_MODEL.md`).
- Built-in upgrade path to Circle native USDC. Hyperlane is just the
  transport — the Circle handoff happens on the FiatToken proxy + source
  bridge contracts independently.

## Comparison with LayerZero / Wormhole for USDC

| | Hyperlane | LayerZero OFT v2 | Wormhole NTT |
|---|---|---|---|
| FiatToken-specific adapter | YES (HypFiatToken) | Possible via OFT Adapter, less clean | Possible via Hub-and-Spoke, less clean |
| Permissionless deploy | YES | Needs EID from LZ Labs | Needs Guardian onboarding (unclear) |
| Built-in rate limit | NO | NO | **YES** |
| Existing Sentrix infra | YES (deployed testnet) | Partial (placeholder EID 40998) | None |
| Compatibility with Circle's standard role hooks | Clean | Adds another role-holder layer | Adds another role-holder layer |
| Maturity | High | Highest (largest ecosystem) | High |

For **canonical bridged USDC** on Sentrix, Hyperlane wins on FiatToken fit +
infrastructure already in place. LZ and Wormhole are reserved for **SRX
multichain** (not in scope for this doc; see `docs/multichain-roadmap.md`).

## Decision

- **Phase 1 (testnet):** No Hyperlane integration yet. Operator EOA holds
  OPERATOR_ROLE on source bridge and minter role on Sentrix FiatToken. All
  cross-chain action is operator-signed. Clearly testnet-only.
- **Phase 2 (testnet → mainnet):** Wire Hyperlane Mailbox into the source
  bridge. Deploy HypFiatToken on Sentrix. Transfer FiatToken minter role
  from operator EOA to HypFiatToken contract. Operator EOA (single-sig bootstrap) retains
  emergency pause + upgrade authority.
- **Phase 3+:** Decentralize the MultisigIsm validator set.
- **Phase 4 (Circle handoff, if approved):** Hyperlane is the transport;
  Circle takes the FiatToken proxy + native upgrade is independent of
  Hyperlane.

## Implementation TODOs (Phase 2 work, not in current scaffold)

1. Inherit `SentrixUSDCSourceBridge` from Hyperlane's `MailboxClient`.
2. Add `dispatch(...)` call inside `deposit()`.
3. Add `handle(...)` override to receive Hyperlane messages and call
   `release()` internally.
4. Migrate OPERATOR_ROLE from operator EOA to Mailbox address; keep
   emergency-operator fallback if Hyperlane misbehaves.
5. Deploy HypFiatToken on Sentrix with FiatToken proxy as the wrapped token.
6. masterMinter calls `configureMinter(HypFiatToken_address, cap)` on
   FiatToken proxy.
7. Enroll remote routers on both sides.
8. Set ISM = MultisigIsm with operator-controlled validator set initially.
9. Storage layout diff before upgrading the source bridge proxy.
10. Reserve check now covers HypFiatToken mint allowance + bridge balance + total supply across all three values.
