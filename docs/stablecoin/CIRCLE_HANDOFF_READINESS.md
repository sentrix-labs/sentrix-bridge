# Circle handoff readiness checklist

> **DO NOT contact Circle's compliance/legal team until this checklist is complete.**
> Premature contact wastes Circle's bandwidth and signals unreadiness.

## What "handoff readiness" means

The Bridged USDC Standard preserves Circle's **option** to upgrade Sentrix's
bridged USDC.e to native USDC. This checklist enumerates the prerequisites
that Circle's diligence team will look at if/when we ask.

Circle has the OPTION, not the OBLIGATION. Even with everything green, Circle
may decline. The checklist puts us in the strongest possible position.

## Phase 1 — On-chain prerequisites

### Token contract (Sentrix)

- [ ] FiatTokenV2_2 deployed from `circlefin/stablecoin-evm` unchanged
- [ ] Solidity 0.6.12, optimizer runs 10,000,000 (or documented lower bound)
- [ ] Compiler metadata JSON saved (`artifacts/build-info/*.json`)
- [ ] `AdminUpgradeabilityProxy` (Circle's, NOT OZ Transparent proxy)
- [ ] `initialize`, `initializeV2`, `initializeV2_1`, `initializeV2_2` called on the proxy
- [ ] Same four initialize functions also called on the implementation directly with throwaway values
- [ ] Token name = "Bridged USDC (Sentrix)"
- [ ] Token symbol = "USDC.e"
- [ ] Token decimals = 6
- [ ] Token currency = "USD"
- [ ] All 6 roles assigned to controlled addresses (Phase 1 single-sig EOAs acceptable per BOOTSTRAP_ROLE_HOLDER.md; multisig required before Phase 4 Circle handoff)
- [ ] Roles documented + verifiable on-chain via `cast call`

### Source bridge (Ethereum mainnet)

- [ ] Source bridge deployed behind ERC1967Proxy (or equivalent upgradeable proxy)
- [ ] Bridge is `Pausable` and exposes `pauseBridging` / `unpauseBridging`
- [ ] Bridge exposes `burnLockedUSDC()` with exact signature
- [ ] Bridge exposes `transferUSDCRoles(address)` with exact signature
- [ ] Both Circle-mandated functions gated by `CIRCLE_BURN_ROLE` and `CIRCLE_ROLE_TRANSFER_ROLE` respectively
- [ ] Both roles have NO holders by default (granted only at Circle's request)
- [ ] Bridge holds locked USDC equal to destination total supply at all times (within in-flight tolerance)

### Cross-chain wiring

- [ ] Hyperlane MultisigIsm production-grade (M-of-N ≥ 3-of-5, ideally with external validators)
- [ ] HypFiatToken deployed on Sentrix and configured as a minter on FiatToken
- [ ] Source bridge integrated with Hyperlane Mailbox (no operator EOA in mint path)
- [ ] Remote routers enrolled both directions
- [ ] Reorg watcher running
- [ ] Reserve reconciliation auto-pause active

## Phase 2 — Off-chain prerequisites

### Operational

- [ ] 60-second reserve check loop in `watcher-rs` running
- [ ] Public status page deployed (reserve delta, recent activity, pause history)
- [ ] Reorg watcher per source chain
- [ ] Dedup table operational under load test
- [ ] Per-alert runbook written and rehearsed
- [ ] On-call rotation
- [ ] Disaster-recovery playbook tested on testnet (forced reorg, validator outage, supply mismatch)

### Documentation

- [ ] `ARCHITECTURE.md` current
- [ ] `SECURITY_MODEL.md` current with all 20 risks
- [ ] `DEPLOYMENT_RUNBOOK.md` matches as-deployed state
- [ ] Public docs site has bridged USDC page clearly labeled "Bridged USDC, not Circle native USDC"
- [ ] Internal audit log up to date

### Compliance / legal

- [ ] Sentrix Labs has a legal entity (Singapore / BVI / Cayman recommended)
- [ ] Operator KYB-ready (can supply company docs to Circle)
- [ ] AML/KYC posture documented (initial bridged USDC is permissionless ERC20, but operator may need to demonstrate sanctions screening at bridge level)
- [ ] Terms of Service / risk disclosures live on Sentrix's USDC.e page
- [ ] User-facing warning: "NOT Circle USDC" prominently displayed

### External audit

- [ ] Source bridge audited by reputable firm (OpenZeppelin / Trail of Bits / Spearbit / Code4rena)
- [ ] FiatToken deployment verified bytecode-identical to Circle's published source
- [ ] Hyperlane HypFiatToken adapter audited or relying on Hyperlane's existing audit
- [ ] All audit findings remediated or accepted with documented rationale

### Track record

- [ ] Minimum 6 months operational on mainnet
- [ ] No security incidents during the operational window
- [ ] Reserve mismatch never observed beyond in-flight tolerance
- [ ] Pause history clean (or pauses fully transparent + post-mortems published)
- [ ] User volume + TVL demonstrate genuine adoption (Circle's bar is unclear publicly; presume $10M+ TVL minimum)

## Phase 3 — Pre-engagement with Circle

When all above green:

- [ ] Email Circle partnerships team: `partnerships@circle.com`
- [ ] Subject: "Native USDC upgrade discussion — Sentrix Chain"
- [ ] Include: TVL, monthly volume, audit reports, deployment addresses, runbook link
- [ ] Wait for Circle's response (weeks to months)
- [ ] If Circle agrees to enter diligence: provide compliance team access to documentation
- [ ] If Circle decides to proceed: Phase 4 begins

## Phase 4 — Circle handoff execution

Per `bridged_USDC_standard.md` §"How it works" + our `ARCHITECTURE.md`
§"Future Circle handoff":

1. [ ] Operator + Circle agree to proceed (legal + technical due diligence passed)
2. [ ] Operator + Circle agree on specific Circle addresses for burn role and role-transfer role (these MAY be different addresses)
3. [ ] Pause bridging both sides
4. [ ] Reconcile in-flight bridge activity
5. [ ] Operator removes all configured minters on FiatToken (including HypFiatToken)
6. [ ] Operator's admin grants `CIRCLE_ROLE_TRANSFER_ROLE` to Circle's role-transfer address (X)
7. [ ] X calls `SourceBridge.transferUSDCRoles(circleAddress)` which cross-chain dispatches the role transfer to destination
8. [ ] Verify on-chain: `FiatToken.owner() == circleAddress`, `FiatTokenProxy.admin() == circleAddress` (or as specified by Circle)
9. [ ] Operator's admin grants `CIRCLE_BURN_ROLE` to Circle's burn address (Y)
10. [ ] Circle separately grants the source bridge a zero-allowance minter role on Ethereum USDC (Circle's action, not ours)
11. [ ] Y calls `SourceBridge.burnLockedUSDC()`
12. [ ] Verify on-chain: source bridge USDC balance = 0
13. [ ] Circle calls `FiatTokenProxy.upgradeTo(circleNativeUSDCImpl)` — upgrade to native USDC
14. [ ] Verify on-chain: FiatToken implementation address matches Circle's published native USDC implementation
15. [ ] Update Sentrix docs: USDC.e → native USDC
16. [ ] Public announcement + post-mortem

## Things to communicate to Circle when engaging

- We deployed FiatTokenV2_2 unchanged. Build artifacts available.
- Our source bridge is upgradeable and exposes the two required functions.
- We use Hyperlane MultisigIsm for transport with [N] validators of which [M] are external.
- Bridged supply on Sentrix is [X] USDC.e backed 1:1 by [X] USDC locked on Ethereum mainnet at bridge address [Y].
- Reserve check has been continuously green for [N] months.
- We are Sentrix Labs, [legal entity], [jurisdiction], [KYB docs].
- We commit to Circle's diligence process. Decision is Circle's.

## What we will NOT do

- We will NOT pressure Circle.
- We will NOT publicly claim Circle is reviewing us before they confirm.
- We will NOT proceed with handoff under any threat or compromise — better to walk away than transfer roles to a wrong address.
- We will NOT modify the bridged token implementation after Circle's diligence begins (modifications can void eligibility).

## Honest assessment

Phase 4 handoff is **aspirational**, not promised. Circle's standard for
approval is high. Sentrix is a new L1; demonstrating the operational maturity
Circle needs takes years, not months. The right framing is "preserve the
option" — build to standard so the door stays open, but plan operationally as
if native USDC will not arrive.

The bridged USDC.e on Sentrix is useful regardless of the handoff status:
- Liquidity on Sentrix DEX
- Stablecoin payments
- DeFi composability

Native USDC would be a multiplier, not a prerequisite.
