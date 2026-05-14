# Single-signer bootstrap policy — Sentrix Bridged USDC

> **This is honest disclosure of an operational choice, not a security claim.**
> Phase 1 + Phase 2 of the Bridged USDC build run on a single-signer setup —
> specifically a 1-of-1 Gnosis Safe ("SentrixSafe") with the operator as
> sole signer. Threshold expansion to N-of-M is a graduation milestone, not
> a launch requirement. Raw EOA is acceptable as a fallback if a Safe cannot
> be deployed for some reason, but Safe is preferred.

## Why single-signer at bootstrap

Sentrix is currently a solo-operator project. There are no co-signers to recruit
for a meaningful multisig threshold. The three paths available are:

1. **Fake multisig** — deploy a 3-of-5 Safe where the operator holds all
   5 keys across different "personas". Looks decentralized in a block
   explorer. Provides zero actual key distribution security. Adds
   operational friction (multi-step proposal/sign flow for every action)
   without buying anything.

2. **Raw operator EOA** — single private key, no smart-contract wrapper.
   Simplest, lowest gas. But: rotating the key means changing the address
   in every role assignment + every consumer contract. Painful when
   eventually upgrading to multisig.

3. **1-of-1 Gnosis Safe ("SentrixSafe")** — smart-contract wallet with
   operator as sole signer. Functionally same single-signer trust model
   as path 2. Critical advantage: signer key can be rotated WITHOUT
   changing the Safe's address. When co-signers are eventually recruited,
   threshold goes from 1-of-1 to 2-of-3 to N-of-M with no role-address
   migration.

**We choose path 3 — 1-of-1 SentrixSafe.**

This is consistent with the operator's same call for the SentrixSafe
treasury multisig (per the operator's earned-rule memory: "stay on 1-of-1
SentrixSafe. N-of-M expansion happens organically when co-signers
recruited").

Raw EOA (path 2) is fallback-acceptable if the Safe cannot be deployed
(e.g., Safe contracts not on Sepolia yet, or operator chooses to manage
without the Safe overhead at deploy time). Same trust model, less
flexibility for future migration.

## What changes between this policy and the original "multisig required" docs

| Doc | Original | This policy |
|---|---|---|
| `CIRCLE_STANDARD_PLAN.md` | "All roles on operator multisig" | "All roles on operator EOA. Multisig is a Phase 3 graduation item." |
| `ARCHITECTURE.md` role table | Multisig in every row | Operator EOA in every row, "Phase 3 → multisig" annotation |
| `DEPLOYMENT_RUNBOOK.md` Step 0 | "Deploy two Gnosis Safes first" | "Have one funded operator EOA, key in HSM/hardware wallet" |
| `SECURITY_MODEL.md` | R1, R3, R12 reference multisig as mitigation | Updated to reflect single-sig bootstrap reality + roadmap |
| `CIRCLE_HANDOFF_READINESS.md` | "All 6 roles on multisigs" gating Circle engagement | Multisig is required before Circle handoff (Phase 4), not before Phase 1/2 testnet bootstrap. |

## What this DOES NOT change

- The contracts themselves. They accept ANY address as role holder
  (multisig or EOA). No code change needed — the "multisig required" was
  always policy, never enforced on-chain.
- The future Circle handoff requirement. Circle's Bridged USDC Standard
  spec says nothing about multisig vs EOA on the partner side; their concern
  is the role layout + functions exposed. Single-sig bootstrap does not
  forfeit Circle eligibility.
- The legal / regulatory considerations. Single-sig means the operator
  individually carries personal liability for the bridge. Multisig
  distributes that across signers. Operator accepts this tradeoff knowingly.

## Honest risk profile (single-sig bootstrap)

Trust model: **trusted-party with single point of compromise on the operator's
private key**.

| Risk | Single-sig impact | Multisig impact (Phase 3+) |
|---|---|---|
| Operator key leaks | Bridge fully compromised. Attacker can drain locked USDC + mint unlimited USDC.e + upgrade contracts. | Attacker needs M-of-N keys. Each independent. |
| Operator coerced / extorted | Forced single-sig = attacker wins. | Forced single signer = bridge stalls but other signers can intervene. |
| Operator unavailable (medical / travel / death) | Bridge frozen until key recovery / rotation. Partial recovery only via deploy of new instance. | M-1 other signers can continue operations. |
| Operator mistake (wrong tx) | Mistake executes. | M-of-N review can catch. |
| Insider attack | Nothing stopping (operator IS the only signer). | Requires colluding signers. |

**These risks are real.** Mitigation rests entirely on the operator's personal
key hygiene + recovery plan. See "Key hygiene checklist" below.

## Key hygiene checklist (operator must follow)

This is the minimum bar for running single-sig at bootstrap. Failure on any
of these = bridge security is below acceptable.

- [ ] **Operator key in HSM or hardware wallet.** Never in plaintext file, never
  in scrollback / chat / commit. Per earned-rule: `feedback_no_wallet_txt_in_chat`.
- [ ] **Separate keys per chain.** Source-chain (Ethereum/Sepolia) operator EOA
  is a DIFFERENT key from Sentrix operator EOA. Compromise of one ≠ compromise
  of both. Compromise of either still compromises the bridge but limits
  cross-chain attack surface.
- [ ] **Separate keys per role family.** If running multiple roles (admin,
  operator, pauser), at minimum split admin from operator. Admin = cold
  storage hardware wallet, used rarely. Operator = day-to-day signing key,
  can be HSM-online. Pauser = emergency-response key, accessible quickly.
- [ ] **Backup the key** — encrypted seed phrase in two geographically
  separate locations (e.g., safety deposit box + trusted relative's safe).
- [ ] **Document recovery procedure** in operator-private notes (not public).
  Include: who has access to backup locations, in what circumstances,
  recovery steps for each role.
- [ ] **Rotate keys** if operator suspects exposure (any time the key was on
  a compromised machine, even briefly).
- [ ] **Monitor for activity** — alert on any role-changing transaction not
  initiated by the operator within 30 seconds. Telegram / SMS alert.
- [ ] **NEVER paste private keys into chat (AI, Slack, email, anywhere).**
  Per earned-rule: leaks via chat scrollback are catastrophic and permanent.

## Roadmap to multisig (Phase 3 graduation)

Multisig becomes worth deploying when:

1. **Co-signers exist.** Not the operator under different names. Actual
   independent humans / entities with their own key custody.
2. **TVL is meaningful.** Below ~$100K bridged USDC, the cost of multisig
   operations (every tx is M-of-N signed) exceeds the security gain. Above
   $1M, single-sig becomes the bottleneck.
3. **Operational maturity.** Multisig requires runbooks for proposal/sign/
   execute flows. If operator can't yet commit to those operationally, defer.

Suggested progression:

| Phase | Multisig state |
|---|---|
| Phase 1 testnet bootstrap | 1-of-1 operator EOA (this policy) |
| Phase 2 Hyperlane wiring testnet | 1-of-1 operator EOA |
| Phase 3a mainnet bootstrap | 1-of-1 operator EOA + audited contracts. Capped TVL. |
| Phase 3b co-signer recruit | 2-of-3 multisig (operator + 1-2 trusted parties) |
| Phase 3c full multisig | 4-of-7 multisig with independent signers |
| Phase 4 Circle handoff | Multisig REQUIRED for the handoff transactions. Circle expects this. |

## What to communicate publicly

When the bridge launches, the public docs / status page MUST state plainly:

> "Sentrix Bridge currently runs on a single-sig operator key during
> bootstrap. The operator key is held in [HSM type] with [N-location]
> backup. Multisig migration is planned for Phase 3 once independent
> co-signers are recruited. Until then, the bridge is a trusted-party
> bridge with a single point of compromise; users should understand this
> trust model before bridging."

No hand-waving. No "decentralized multisig" implications. Operator carries
the trust.

## What Circle needs to see (for the eventual Phase 4 handoff)

Per Circle's spec, the partner team must demonstrate "a solid understanding
of the bridge design and be prepared to provide guidance on bridge-related
technical details." The spec does NOT require multisig at deployment time.
Circle's blockchain due diligence likely WILL request multisig before
agreeing to native USDC upgrade, because they're going to trust the partner
with role-transfer transactions.

So: single-sig is acceptable for Phase 1-3a. Multisig becomes a Phase 4
prerequisite when engaging Circle for the handoff. Plan the migration
accordingly.

## What the contracts enforce (unchanged by this policy)

The contracts at `src/circle-bridged/` accept ANY address (EOA or contract)
as role holder via `_grantRole`. There is no on-chain multisig check. The
policy is operational, not code-enforced. This was a deliberate design
choice: the contract should support both single-sig and multisig without
needing redeployment.

## TL;DR

- Bootstrap = single-sig operator EOA. Disclosed clearly.
- Code unchanged. No multisig check on-chain.
- Multisig is a Phase 3+ graduation milestone.
- Key hygiene checklist above is the minimum bar.
- This DOES NOT block Circle handoff path, but Circle will likely want
  multisig before they engage.
