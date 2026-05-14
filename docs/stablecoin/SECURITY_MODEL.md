# Security model — Sentrix Bridged USDC

> **NOT official Circle USDC.** Circle has not approved Sentrix.
> Bridged forms of USDC are subject to risks not present in native USDC.
> This document enumerates those risks.

## Trust model

This system is **trusted-party**, not trustless, in Phase 1 and Phase 2:

- **Phase 1 (operator single-sig bridge):** the operator EOA is the source of
  truth for cross-chain message verification. Compromise of the operator key
  = compromise of the bridge. See `SINGLE_SIG_BOOTSTRAP_POLICY.md`.
- **Phase 2 (Hyperlane MultisigIsm bridge):** the configured MultisigIsm
  validator set is the source of truth for cross-chain message verification.
  Compromise of the threshold = compromise of the bridge. (Source bridge
  admin still single-sig operator EOA until Phase 3b.)
- **Phase 3b+ (multisig admin):** operator multisig replaces single-sig EOA
  for admin / pauser / role-control. Bridge transactions still verified by
  Hyperlane MultisigIsm.
- **Phase 4 (Circle native USDC):** the bridge is dissolved; Circle is the
  trusted issuer of native USDC. Trust shifts to Circle.

There is NO trustless intermediate state. Honest disclosure of this is a
hard requirement of the design.

## Risk register

Severity scale:
- **CRIT** — chain-killing for bridged USDC.
- **HIGH** — drain or supply mismatch up to the bridge's locked balance.
- **MED** — bounded loss per user / per period.
- **LOW** — nuisance.

### R1: Operator key compromise — CRIT

| | |
|---|---|
| Impact | Attacker can drain locked USDC via unauthorized `release`, mint unlimited USDC.e via FiatToken minter role transfer, or upgrade the bridge to malicious implementation. |
| Mitigation on-chain | Role separation (admin vs operator vs pauser). In Phase 1 single-sig bootstrap, each role on a SEPARATE EOA (different physical keys per role family). In Phase 3b+, replace with multisig. |
| Mitigation off-chain | Operator key in HSM / hardware wallet. Encrypted seed-phrase backup in two geographically separate locations. Different keys for source-chain vs Sentrix-chain. Different keys for admin vs operator vs pauser. Per earned-rule `feedback_no_wallet_txt_in_chat`: NEVER plaintext, NEVER in chat. |
| Status | Phase 1: single-sig bootstrap per `SINGLE_SIG_BOOTSTRAP_POLICY.md`. Phase 3b: multisig migration milestone. |

### R2: Hyperlane MultisigIsm validator compromise — HIGH (Phase 2+)

| | |
|---|---|
| Impact | Attacker who controls M-of-N validators can forge inbound messages, minting USDC.e without corresponding source-chain lock. |
| Mitigation on-chain | M-of-N threshold ≥ 3 production. Validators on independent infrastructure. |
| Mitigation off-chain | Different cloud providers per validator. Different sign-key storage methods. Recruit external validators (not all operator-controlled) over time. |
| Status | Decentralization roadmap pending. Phase 2 deploys with all-operator validators + clear disclosure. |

### R3: FiatToken proxy admin compromise — CRIT

| | |
|---|---|
| Impact | Attacker who compromises the proxy `admin` can upgrade the FiatToken implementation to malicious code, draining all bridged USDC.e holders. |
| Mitigation on-chain | Proxy `admin` is a SEPARATE address from `owner` per Circle's spec — defense in depth. Phase 1: separate operator EOA. Phase 3b+: separate multisig. |
| Mitigation off-chain | Proxy admin key in cold storage (hardware wallet, accessed only for upgrades). Phase 1 single-sig acceptable IF the key is genuinely cold (offline, used only rarely, recovery procedure documented). Phase 3b: cold-storage multisig. |
| Status | Phase 1: cold-storage single-sig per `SINGLE_SIG_BOOTSTRAP_POLICY.md`. Phase 3b+: multisig. |

### R4: Reserve mismatch (supply > locked) — HIGH

| | |
|---|---|
| Impact | If `FiatToken.totalSupply() > sourceBridge.totalLocked()`, USDC.e is unbacked. Token loses 1:1 peg. |
| Mitigation on-chain | None directly. The bridge cannot self-check across chains. |
| Mitigation off-chain | Reserve monitor (`watcher-rs`) compares on a 60-second loop. Auto-pause both sides on mismatch. |
| Status | Reserve monitor design specified in `BRIDGE_RELAYER_DESIGN.md`. Implementation in `watcher-rs` is pending. |

### R5: Source-chain reorg post-mint — HIGH

| | |
|---|---|
| Impact | Source chain reorgs past a deposit that was already minted on Sentrix. Source bridge no longer holds collateral; bridge is unbacked by the reorged amount. |
| Mitigation on-chain | None. Reorg detection is off-chain. |
| Mitigation off-chain | Set CONFIRMATION_DEPTH conservatively: Ethereum mainnet 32 blocks, Sepolia 5 blocks. Re-validate `(tx_hash, block_number)` after mint; alert + pause if reorg detected post-mint. |
| Status | Documented; off-chain implementation pending. |

### R6: Double-mint (relayer error) — HIGH

| | |
|---|---|
| Impact | Same deposit processed twice → unbacked supply. |
| Mitigation on-chain | FiatToken's `minterAllowance` caps total mint per allowance period. |
| Mitigation off-chain | `processed_events` table with UNIQUE constraint on `(chain_id, vault_address, deposit_id)`. |
| Status | Schema specified in `BRIDGE_RELAYER_DESIGN.md`. |

### R7: Double-release (operator error) — HIGH

| | |
|---|---|
| Impact | Same withdrawal processed twice → bridge over-draws locked balance, eventually reverts but loses USDC to the first attacker. |
| Mitigation on-chain | `release` checks `amount <= totalLocked`. |
| Mitigation off-chain | Mirror dedup table for withdrawals. |
| Status | Schema specified. |

### R8: Blacklister abuse — MED

| | |
|---|---|
| Impact | Circle's FiatToken contract has a `blacklister` role that can freeze any address from sending/receiving. A compromised or malicious blacklister can target users. |
| Mitigation on-chain | Per Circle's standard: `blacklister` is a separate role from `owner` / `masterMinter`. |
| Mitigation off-chain | Blacklister multisig. Public commit to "blacklister used only on legal compulsion or in confirmed exploit response". Transparency log of any blacklist event. |
| Status | Operational rule. |

### R9: Rescuer abuse — MED

| | |
|---|---|
| Impact | Circle's FiatToken has a `rescuer` role that can transfer arbitrary ERC20 tokens trapped in the FiatToken contract. A compromised or malicious rescuer could steal those tokens (but NOT USDC.e itself). |
| Mitigation on-chain | Rescuer is a separate role. |
| Mitigation off-chain | Multisig. |
| Status | Inherent to FiatToken design. Documented. |

### R10: Pauser misuse / availability — MED

| | |
|---|---|
| Impact | Pauser can freeze the bridged token indefinitely, halting all transfers. |
| Mitigation on-chain | Pauser is a separate role. |
| Mitigation off-chain | Multisig. Public commit to "pause only for incidents". Transparency log of every pause event with reason. |
| Status | Operational rule. |

### R11: Circle hook misuse (`burnLockedUSDC` / `transferUSDCRoles` granted prematurely) — HIGH

| | |
|---|---|
| Impact | If `CIRCLE_BURN_ROLE` is granted to an attacker address before Circle actually initiates the upgrade, attacker can burn the bridge's locked USDC, destroying user funds without a corresponding mint. If `CIRCLE_ROLE_TRANSFER_ROLE` is granted to an attacker, attacker can transfer the FiatToken owner + proxy admin to themselves on the destination chain. |
| Mitigation on-chain | Roles default to empty. Admin grants them only at upgrade time. |
| Mitigation off-chain | The admin multisig MUST verify Circle's specified addresses via Circle's official channel before granting. Multi-source verification (Circle Discord + email + smart contract signature). |
| Status | Operational discipline. Critical step in Phase 4 runbook. |

### R12: Upgradeable bridge admin compromise — CRIT

| | |
|---|---|
| Impact | If the source bridge's upgrade admin is compromised, attacker can replace the bridge implementation with malicious code, e.g. removing `release` access control or draining via a fake `burnLockedUSDC`. |
| Mitigation on-chain | ERC1967Proxy upgrade authority lives on DEFAULT_ADMIN_ROLE. Phase 1: 1-of-1 SentrixSafe (single-signer). Phase 3b+: multisig. |
| Mitigation off-chain | Phase 1: admin EOA in cold storage (hardware wallet, used only for upgrades). Phase 3b: multisig with high threshold + hardware-wallet signers. Time-lock recommended for any upgrade (24-72h) regardless of phase. |
| Status | Time-lock not in current scaffold. Add before mainnet (Phase 3a or 3b). |

### R13: Private key storage — CRIT

| | |
|---|---|
| Impact | If any role's private key leaks, see R1–R3. |
| Mitigation off-chain | All operator-controlled keys in HSM / cloud KMS / hardware wallet. NEVER plaintext. NEVER in chat or scrollback (per `feedback_no_wallet_txt_in_chat`). |
| Status | Operational rule. |

### R14: Storage layout drift on upgrade — HIGH

| | |
|---|---|
| Impact | An upgrade that re-orders or removes existing storage slots corrupts existing state. |
| Mitigation on-chain | Storage `__gap[40]` reserved. New state appended, never inserted. |
| Mitigation off-chain | Run `forge inspect storage-layout` before/after every upgrade. Diff must show only additions. |
| Status | Documented; must enforce in deploy runbook. |

### R15: Mainnet ↔ testnet divergence — HIGH (Circle eligibility)

| | |
|---|---|
| Impact | Circle's Bridged USDC Standard requires testnet and mainnet configurations to mirror. Drift = ineligible for native upgrade. |
| Mitigation off-chain | Same role addresses (or same multisig structure), same FiatToken version, same proxy admin pattern, same initialization values, same compiler settings. |
| Status | Operational rule. Document mirror-check in pre-deploy checklist. |

### R16: Solidity version drift — HIGH (Circle eligibility)

| | |
|---|---|
| Impact | Circle's Bridged USDC Standard requires FiatToken built from Circle source at solc 0.6.12 + optimizer runs 10M (or lower if technically required). Deploying a version-bumped or modified FiatToken = ineligible. |
| Mitigation off-chain | Use Circle's `circlefin/stablecoin-evm` repo unchanged. Capture compiler metadata. Do not fork. |
| Status | Enforced by following the runbook. |

### R17: Compiler metadata not captured — MED

| | |
|---|---|
| Impact | Without compiler metadata, Circle cannot verify bytecode parity at upgrade time → ineligible. |
| Mitigation off-chain | Save the `artifacts/build-info/*.json` from Hardhat after each deploy. Store at `~/founder-private/usdc-deploy-artifacts/`. |
| Status | Operational rule. |

### R18: Hyperlane Mailbox / ISM bug — HIGH (Phase 2+)

| | |
|---|---|
| Impact | A bug in Hyperlane's Mailbox or MultisigIsm could allow message forgery or replay. |
| Mitigation on-chain | Use audited Hyperlane v3 contracts unmodified. |
| Mitigation off-chain | Monitor Hyperlane security advisories. Reserve check catches downstream effect (unauthorized mint). |
| Status | Acceptable systemic risk; mitigated by reserve check. |

### R19: Single-operator centralization (validator set) — HIGH

| | |
|---|---|
| Impact | If all MultisigIsm validators are operator-controlled, the security model is effectively single-operator regardless of M-of-N threshold. Single point of compromise. |
| Mitigation off-chain | Decentralization roadmap: phase 2 = all-operator + transparency. Phase 3+ = onboard 2-3 external validators (RPC providers, community). Phase 4+ = fully decentralized. |
| Status | Roadmap committed; execution pending. |

### R21: Single-sig bootstrap concentration — HIGH

| | |
|---|---|
| Impact | Phase 1 + Phase 2 + Phase 3a deploy with single-sig operator EOAs (separate per role family but all controlled by the same operator). A single key compromise = full bridge compromise, irrecoverable by any other party. Operator unavailability (medical, travel, death) = bridge frozen. |
| Mitigation on-chain | Role-family key separation (admin / operator / pauser on different EOAs). Pausable. |
| Mitigation off-chain | Per `SINGLE_SIG_BOOTSTRAP_POLICY.md`: HSM-grade key custody, encrypted seed-phrase backup in two geographic locations, documented recovery procedure, monitoring + alerting on every role-changing tx, key rotation on any suspected exposure. Honest public disclosure of single-sig trust model. Multisig migration roadmap (Phase 3b). |
| Status | Acknowledged operational tradeoff. Disclosed publicly. Migration milestone defined. |

### R20: Token forks / re-deploys — MED

| | |
|---|---|
| Impact | If we ever re-deploy the FiatToken proxy with a new address (e.g. because of a deployment mistake), the original address remains as a "dead" bridged USDC. Users with USDC.e at the old address are stuck unless we provide a migration. |
| Mitigation off-chain | Test exhaustively on testnet before mainnet deploy. Never re-deploy a published proxy address. |
| Status | Operational discipline. |

## Operational summary

| Item | Phase 1 | Phase 2 | Phase 3 | Phase 4 |
|---|---|---|---|---|
| Cross-chain message verification | Operator multisig | Hyperlane MultisigIsm | Decentralized MultisigIsm | Circle native |
| Mint authority | Operator EOA (configured minter) | HypFiatToken contract | Same | Removed (Circle becomes minter) |
| Pauser | Operator multisig | Operator multisig | Operator multisig | Circle |
| Source bridge admin (upgrade) | Operator multisig | Operator multisig | Operator multisig + time-lock | Frozen (no further upgrades) |
| Reserve check | Manual | Auto (60s loop) | Auto + alert + auto-pause | N/A |
| Cap (USD-equivalent) | $10K total locked | $100K | $1M+ | Unbounded |

## What we are NOT doing

- No trustless production bridge claim. Every phase has trust assumptions; we
  disclose them.
- No on-chain rate-limiting yet. Caps live at FiatToken minter allowance + total locked.
- No insurance backstop. Operator personal coverage is not committed.
- No CCTP integration until Sentrix is on Circle's supported chain list.

## References

- `BRIDGE_RELAYER_DESIGN.md` — off-chain monitoring + dedup
- `CIRCLE_STANDARD_PLAN.md` — Circle spec compliance
- `DEPLOYMENT_RUNBOOK.md` — deploy procedure
- `ARCHITECTURE.md` — contract layout
- `HYPERLANE_EVALUATION.md` — Phase 2 transport
- `MIGRATION_FROM_POC.md` — what's reusable from sUSDC
- `CIRCLE_HANDOFF_READINESS.md` — pre-handoff checklist
