# Circle Bridged USDC Standard plan — Sentrix Chain

> **This is NOT official Circle USDC. Circle has not approved Sentrix.**
> **Circle's option to upgrade is at their discretion, not obligation.**

## What is Bridged USDC Standard

Source: `https://github.com/circlefin/stablecoin-evm/blob/master/doc/bridged_USDC_standard.md`

A specification for deploying a bridged form of USDC on an EVM chain that
**preserves a future upgrade path** to native USDC issued by Circle, if and
only if both parties later agree.

Key property: **must be incorporated BEFORE deploying the bridged USDC token
contract. It cannot be retroactively applied.** Deploying an incompatible
custom ERC20 (like the sUSDC PoC) forfeits the upgrade path forever for that
deployment.

## Hard requirements (verified against Circle source)

### Token contract

| Requirement | Detail |
|---|---|
| Source | `circlefin/stablecoin-evm` — FiatTokenV2_2 (latest) |
| Solidity | **0.6.12** (exact — `pragma solidity 0.6.12;` in FiatTokenV2_2.sol) |
| Optimizer runs | **10,000,000** (or lower only if technical limit) |
| Proxy | Circle's `AdminUpgradeabilityProxy` (NOT OZ Transparent proxy) |
| Initialization | All four must be called on the proxy storage at deployment: `initialize`, `initializeV2`, `initializeV2_1`, `initializeV2_2`. Should also be called on the implementation directly to prevent third-party hijack. |
| Roles | 6 roles: `admin` (proxy-level), `owner`, `masterMinter`, `pauser`, `blacklister`, `rescuer`. Plus configurable `minters` (added by masterMinter). |
| Upgrades | **NEVER upgrade the token contract** outside subsequent Circle-authored FiatToken versions. |
| Naming | "Bridged USDC (Sentrix)" / `USDC.e` (Circle's recommended convention). |

### Source bridge contract

| Requirement | Detail |
|---|---|
| Upgradeable | Yes — Bridge contract MUST be upgradeable (per spec). |
| `burnLockedUSDC()` | Exposed function, callable only by Circle-specified address. Burns the bridge's locked USDC equal to bridged supply on destination chain. |
| `transferUSDCRoles(address)` | Exposed function, callable only by a (possibly different) Circle-specified address. Transfers FiatToken owner + proxy admin to Circle. |
| Pausable | Must be able to pause USDC bridging (supply lock for upgrade choreography). |
| Implementation order | Circle recommends deferring the burn + transfer functions to a later contract upgrade, after Circle and partner agree to proceed. We implement them up front (scaffolded) for clarity; the scaffold ensures the upgrade path is preserved even if functions are stubs at first. |

### Destination bridge contract

Same pausable requirement as source. Mints/burns USDC on Sentrix via the
FiatToken's masterMinter → configureMinter pathway.

### Operational requirements

- Testnet ↔ mainnet must **mirror exactly**: same configuration, same role
  layout, same FiatToken version. Mismatch = ineligible for native upgrade.
- Partner team must understand the bridge design and be able to explain it to
  Circle's diligence team.
- Build artifacts (compiler metadata JSON) must be extractable for Circle's
  bytecode verification.

## Why this PLAN, not a custom ERC20

A simple custom ERC20 (like sUSDC) gives us:
- Less code → easier audit
- More flexible (custom roles, custom rate limits)
- Faster to ship

But it forfeits:
- The future upgrade-to-native USDC path with Circle
- Circle endorsement under their Alliance / Bridged USDC programs
- Trustless contract verification (Circle won't recognize a non-FiatToken contract as compatible bridged USDC)

For Sentrix's stated goal (canonical bridged USDC eligible for future Circle
review), the custom ERC20 path is wrong. We use Circle's contracts unmodified.

## Three-phase implementation

### Phase 1 — Testnet (current scope)

- Deploy FiatTokenV2_2 unchanged on Sentrix testnet (chain 7120) via Circle's
  Hardhat-based scripts from `circlefin/stablecoin-evm` (Node 20.9.0, Yarn
  1.22.19, Foundry@f625d0f per their README).
- Use `AdminUpgradeabilityProxy` (Circle's, not OZ's).
- Initialize with 1-of-1 SentrixSafe as `owner`, `masterMinter`, `pauser`,
  `blacklister`, `rescuer`. Proxy `admin` can be the same EOA OR (best
  practice) a separate operator-held EOA for role-family separation. Single-sig
  bootstrap policy applies — see `BOOTSTRAP_ROLE_HOLDER.md`. Multisig is
  a Phase 3+ graduation milestone, not a Phase 1 launch requirement.
- Deploy `SentrixUSDCSourceBridge` (this repo, `src/circle-bridged/source/`,
  scaffold complete) on Sepolia behind ERC1967Proxy.
- Wire by manual relayer: 1-of-1 SentrixSafe holds OPERATOR_ROLE on source bridge,
  manually verifies cross-chain events and calls `release` on source and
  `mint` on destination (via masterMinter → bridge minter address).
- Mint allowance is set by masterMinter for the destination bridge address —
  initial cap kept small (e.g. 10,000 USDC) for testnet bootstrap.
- Both pausable.
- Both expose Circle hooks (`burnLockedUSDC`, `transferUSDCRoles`) gated by
  roles that initially have NO holders (granted by admin near upgrade time).

### Phase 2 — Hyperlane integration

Replace manual relayer with Hyperlane HypFiatToken on Sentrix side and a
Hyperlane-driven source bridge. Source bridge stops accepting `release()`
from operator EOA and instead accepts it only from the Hyperlane Mailbox
after MultisigIsm validation. SentrixSafe still holds emergency pause and
upgrade authority (single-sig bootstrap policy continues through Phase 2).

See `HYPERLANE_EVALUATION.md` for the integration analysis.

### Phase 3 — Mainnet bake + external audit + Circle outreach

- External audit (firm TBD — Code4rena or similar).
- Mainnet deploy following Phase 1+2 design exactly.
- Conservative caps initially.
- Circle outreach (email already drafted at `~/founder-private/CIRCLE_OUTREACH_2026_05_14.md`).
- Reserve monitoring + auto-pause in `watcher-rs`.

### Phase 4 — Circle handoff (optional, if and when Circle approves)

Per Circle's spec:
1. Pause bridging both sides.
2. Reconcile in-flight transfers.
3. Admin grants `CIRCLE_ROLE_TRANSFER_ROLE` to Circle's specified address.
4. Circle calls `transferUSDCRoles(circleAddress)`.
5. Admin grants `CIRCLE_BURN_ROLE` to Circle's other specified address.
6. Circle grants the source bridge a zero-allowance minter role on real USDC.
7. Circle calls `burnLockedUSDC()`.
8. Circle upgrades the FiatToken proxy implementation to native USDC.
9. Token contract address stays the same; holders + integrations unaffected.

## What we do NOT promise

- We do NOT claim Circle approval.
- We do NOT claim this is native USDC.
- We do NOT claim the upgrade path will be exercised — Circle has the option,
  not the obligation.
- We do NOT use Circle's branding without the "Bridged" qualifier.

## References

- Spec: `circlefin/stablecoin-evm/doc/bridged_USDC_standard.md`
- Reference contract: `circlefin/stablecoin-evm/contracts/v2/FiatTokenV2_2.sol`
- Reference deployment scripts: `circlefin/stablecoin-evm/migrations/`
- Circle blog: `https://www.circle.com/blog/bridged-usdc-standard`
- Circle CCTP (future): `https://developers.circle.com/cctp`
- Hyperlane HypFiatToken: `hyperlane-monorepo/solidity/contracts/token/extensions/HypFiatToken.sol`

## Sister docs

- `ARCHITECTURE.md` — contract layout, role topology, flows
- `HYPERLANE_EVALUATION.md` — Hyperlane transport assessment
- `DEPLOYMENT_RUNBOOK.md` — step-by-step deploy
- `SECURITY_MODEL.md` — risk register + Circle-specific risks
- `MIGRATION_FROM_POC.md` — what's reusable from sUSDC PoC, what isn't
- `CIRCLE_HANDOFF_READINESS.md` — checklist before approaching Circle
