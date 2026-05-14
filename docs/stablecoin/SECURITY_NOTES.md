# Security notes — sUSDC PoC (LEGACY, SUPERSEDED)

> **This document is the risk register for the legacy `src/stablecoin/` sUSDC
> PoC. It is SUPERSEDED by `SECURITY_MODEL.md` for the canonical Circle
> Bridged USDC Standard path.**
>
> Most risks listed here translate directly to the Circle Standard build, but
> the role layout differs (sUSDC = 4 custom roles; Circle = 6 standard roles)
> and SECURITY_MODEL.md adds Circle-specific risks (R8 blacklister abuse,
> R9 rescuer abuse, R11 Circle hook misuse, R15 mainnet↔testnet divergence,
> R16 solc version drift, R17 compiler metadata, R21 single-signer
> concentration).
>
> Keep this doc as a reference for the sUSDC PoC contracts. For canonical
> Sentrix Bridged USDC risk register, read `SECURITY_MODEL.md`.

---

This document enumerates the security model of the `SourceChainVault` +
`SentrixBridgedUSDC` system in `src/stablecoin/`. The model is intentionally
**trusted**, not trustless. Every risk below either has an on-chain mitigation
in code, an off-chain mitigation in `BRIDGE_RELAYER_DESIGN.md`, or an explicit
TBD that must be closed before mainnet.

## 0. Headline disclaimer

`SentrixBridgedUSDC` is **NOT** Circle USDC. It does NOT carry Circle reserve
backing. It is a Sentrix-issued ERC20 backed 1:1 by USDC locked in
`SourceChainVault` on a source chain (Sepolia for testnet, eventually Ethereum
mainnet). For Circle-issued bridged USDC see
https://www.circle.com/blog/bridged-usdc-standard and Circle's reference
implementation at https://github.com/circlefin/stablecoin-evm.

The PoC is intentionally minimal and is NOT compatible with Circle's
upgrade-to-native-USDC path. That path requires a UUPS proxy with a specific
role layout (masterMinter, controller, pauser, blacklister, rescuer) which
this contract does not implement.

## 1. Risk register

Severity scale: **CRIT** = chain-killing; **HIGH** = bridge-killing;
**MED** = user fund loss bounded by cap; **LOW** = nuisance.

### R1: Admin key compromise — CRIT

| | |
|---|---|
| Impact | Attacker can grant themselves any role, replace the bridge minter, pause/unpause, drain via release. |
| On-chain mitigation | `DEFAULT_ADMIN_ROLE` SHOULD be a multisig (NOT enforced on-chain — the constructor accepts any address). |
| Off-chain mitigation | Deploy with multisig. Audit constructor args before broadcast. |
| Implementation status | Code: no enforcement. Deployment-time: operator MUST use multisig. Documented in deploy script comments. |

### R2: Relayer compromise — HIGH

| | |
|---|---|
| Impact | Attacker submits arbitrary `bridgeMint` calls within the minter's allowance. Maximum loss = `mintAllowance(compromised_minter)`. |
| On-chain mitigation | Mint allowance cap. Pausable. Role can be revoked by admin. |
| Off-chain mitigation | Relayer key in HSM. Multisig submission, not direct broadcast. Reserve check auto-pause. |
| Implementation status | Allowance cap: enforced in `SentrixBridgedUSDC.bridgeMint`. Multisig: deployment-time operator responsibility. Reserve check: see `BRIDGE_RELAYER_DESIGN.md` §5. |

### R3: Bridge minter compromise (slow drain) — HIGH

| | |
|---|---|
| Impact | If the BRIDGE_MINTER_ROLE address itself is compromised but the relayer software is not, the attacker can mint up to the remaining allowance. |
| On-chain mitigation | Allowance is depleted per mint. MINTER_ADMIN_ROLE can revoke. PAUSER_ROLE can pause globally. |
| Off-chain mitigation | Reserve check auto-pause within `RESERVE_CHECK_INTERVAL` (default 60s). |
| Implementation status | Code: allowance enforced. Reserve check: design only, must be implemented in `watcher-rs` before production. |

### R4: Fake deposit event (forged log) — N/A

| | |
|---|---|
| Impact | Hypothetically: attacker forges a `Deposit` event on the source chain to trick the relayer into minting. |
| On-chain mitigation | Not applicable — the relayer never trusts an `eth_getLogs` response without verifying it came from the configured vault address AND was included in a finalized block. |
| Off-chain mitigation | Verify event source address. Verify block finality. Re-read after CONFIRMATION_DEPTH. |
| Implementation status | Design specified. Must be implemented in `watcher-rs`. |

### R5: Source-chain reorg past mint — HIGH

| | |
|---|---|
| Impact | A `Deposit` event reaches CONFIRMATION_DEPTH, the relayer mints on Sentrix, then the source chain reorgs and the original block is no longer canonical. The Sentrix supply now exceeds locked collateral. |
| On-chain mitigation | None directly — reorg detection is off-chain. |
| Off-chain mitigation | Set CONFIRMATION_DEPTH conservatively per chain (Ethereum mainnet: 32 blocks ≈ 1 epoch finality). Continuous reorg watcher that re-validates `(tx_hash, block_number)` after mint. On detection: alert + pause. |
| Implementation status | Confirmation depths documented per chain. Reorg watcher: design only. |

### R6: Double mint (same depositId processed twice) — HIGH

| | |
|---|---|
| Impact | Relayer mints `amount` of sUSDC twice from a single source-chain deposit. |
| On-chain mitigation | None — the contract trusts the relayer. |
| Off-chain mitigation | `processed_events` table with UNIQUE constraint on `(chain_id, contract_addr, event_id)`. |
| Implementation status | Schema specified. Must be implemented. |

### R7: Double withdrawal (release called twice for same widId) — HIGH

| | |
|---|---|
| Impact | Vault releases the same amount twice. |
| On-chain mitigation | None — the vault trusts the operator. |
| Off-chain mitigation | Mirror of R6 for withdrawals. `processed_events` UNIQUE constraint. |
| Implementation status | Schema specified. Must be implemented. |

### R8: Vault drain (operator key controls full vault) — CRIT |

| | |
|---|---|
| Impact | An OPERATOR_ROLE holder can call `release(any_widId, attacker, totalLocked())` and drain the vault. |
| On-chain mitigation | OPERATOR_ROLE SHOULD be a multisig. Constructor does not enforce. |
| Off-chain mitigation | Multisig threshold ≥ 3-of-5 in production. Reserve check would detect imbalance after the drain (too late for the funds, in time to pause minting). |
| Implementation status | Code: no enforcement. Deployment-time: operator MUST use multisig with ≥ 3 signers. |

### R9: Mint allowance exhaustion — LOW

| | |
|---|---|
| Impact | Legitimate users have funds locked on source chain but cannot receive sUSDC because allowance hit zero. |
| On-chain mitigation | MINTER_ADMIN_ROLE replenishes via `setMintAllowance`. |
| Off-chain mitigation | Health monitor alerts when allowance drops below 10% of recent daily volume. |
| Implementation status | Alert defined. Replenishment is manual via multisig. |

### R10: Unlimited mint risk — MED (mitigated) |

| | |
|---|---|
| Impact | If `setMintAllowance(minter, type(uint256).max)` is ever called, the corresponding minter can mint unbounded supply. |
| On-chain mitigation | The cap is a `uint256` and no on-chain ceiling. MINTER_ADMIN_ROLE must be operator-trusted multisig. |
| Off-chain mitigation | Document the operational rule "never set allowance to type(uint256).max". Reserve check catches the mismatch within RESERVE_CHECK_INTERVAL. |
| Implementation status | Documented. No on-chain ceiling; could add a `MAX_MINT_ALLOWANCE` constant if operator wants defense-in-depth. |

### R11: Reserve mismatch — HIGH

| | |
|---|---|
| Impact | sUSDC supply exceeds source-chain locked collateral. Token loses 1:1 backing. |
| On-chain mitigation | None on-chain. |
| Off-chain mitigation | Reserve check loop (`BRIDGE_RELAYER_DESIGN.md` §5). Auto-pause on positive mismatch. |
| Implementation status | Design specified. Must be implemented. |

### R12: Pause/blacklist centralization — MED |

| | |
|---|---|
| Impact | PAUSER_ROLE holder can halt all transfers indefinitely. This contract does NOT include blacklist; if added later, blacklister can freeze individual addresses. |
| On-chain mitigation | Pause is binary (no time-lock). |
| Off-chain mitigation | PAUSER_ROLE is multisig. Public commit to pause-only-for-incidents policy. Status page documents pause events. |
| Implementation status | Code: roles separated (PAUSER ≠ ADMIN). Operational: multisig + transparency. |

### R13: Upgradeability risk — LOW (avoided)

| | |
|---|---|
| Impact | If contracts were UUPS-upgradeable, the proxy admin could replace the implementation and inject malicious code. |
| On-chain mitigation | This PoC is intentionally **non-upgradeable**. No proxy. |
| Off-chain mitigation | N/A. |
| Implementation status | By design. For Circle Bridged USDC Standard compatibility this WILL need upgradeability — at that point a separate audit pass on the proxy + admin roles is required. |

### R14: Private key storage — HIGH

| | |
|---|---|
| Impact | If any role key is leaked, see R1 / R2 / R3 / R8. |
| On-chain mitigation | None possible. |
| Off-chain mitigation | All operator-controlled keys in HSM or cloud secret manager. NEVER plaintext. NEVER in chat or scrollback. Per operator memory rule `feedback_no_wallet_txt_in_chat`. |
| Implementation status | Operational rule. Verified before each deploy. |

### R15: Multisig requirement — HIGH

| | |
|---|---|
| Impact | If any privileged role is held by a single EOA in production, the system becomes a single-key bridge. Worst-case: R1 / R8. |
| On-chain mitigation | Constructor does not enforce that role holders are smart contracts (which would imply multisig). |
| Off-chain mitigation | Deployment checklist requires multisig addresses for `DEFAULT_ADMIN_ROLE`, `OPERATOR_ROLE`, `MINTER_ADMIN_ROLE`, `PAUSER_ROLE`. |
| Implementation status | Documented. Operator-enforced. |

### R16: Monitoring requirement — HIGH

| | |
|---|---|
| Impact | Without continuous monitoring, R5 / R6 / R7 / R11 go undetected long enough to drain the vault. |
| On-chain mitigation | None — by construction off-chain. |
| Off-chain mitigation | `watcher-rs` already exists in the repo. Must be extended to cover this bridge's events + reserve check. |
| Implementation status | Existing `watcher-rs` covers Hyperlane wSRX routes. Extension to sUSDC reserve check pending. |

### R17: Incident response — HIGH

| | |
|---|---|
| Impact | When an alert fires, every minute the operator takes to diagnose increases potential loss. |
| On-chain mitigation | `pause()` is single-call. Multisig should pre-approve a "pause-only" emergency signer. |
| Off-chain mitigation | Runbooks per alert. On-call rotation. Pre-rehearsed pause procedure. |
| Implementation status | Runbook stubs in `BRIDGE_RELAYER_DESIGN.md` §8. Full per-alert runbooks pending. |

### R18: 6-decimal assumption — LOW

| | |
|---|---|
| Impact | If the source-chain collateral token has different decimals than 6, the deposit→mint amount math drifts. |
| On-chain mitigation | Vault stores raw `amount` (no decimal conversion). Mint passes `amount` straight through. |
| Off-chain mitigation | Only configure vaults with 6-decimal collateral (USDC has 6 decimals). |
| Implementation status | Documented. Relayer config must reject non-6-decimal collateral. |

### R19: Reentrancy on deposit / release — LOW (mitigated)

| | |
|---|---|
| Impact | If the collateral token is a hostile ERC20 with hooks (ERC777-style), it could re-enter the vault during transfer. |
| On-chain mitigation | `ReentrancyGuard` on both `deposit` and `release`. SafeERC20 calls. CEI ordering (state updates before external call). |
| Off-chain mitigation | Vault only deployed with the canonical USDC contract (which has no hooks). |
| Implementation status | Code: nonReentrant + CEI in both functions. |

## 2. Status summary

| Severity | Count | Mitigated | Pending |
|---|---|---|---|
| CRIT | 2 | 0 on-chain (operator-enforced multisig) | Multisig deployment |
| HIGH | 8 | 3 on-chain | Reserve check, reorg watcher, dedup |
| MED | 3 | 2 on-chain | None blocking |
| LOW | 4 | 4 on-chain | None |

## 3. Production-readiness gating

Before any mainnet deployment of these contracts:

1. External audit (firm TBD — Code4rena candidate per existing
   `docs/bridge/Audit.internal`).
2. Reserve check implemented + tested on testnet.
3. Reorg watcher implemented + tested with a forced reorg simulation.
4. Dedup table operating under load test.
5. All privileged roles held by multisig contracts.
6. Per-alert runbook completed.
7. Public status page + incident-response playbook published.

## 4. References

- Operator-internal audit log: `docs/bridge/Audit.internal`
- Relayer design: `docs/stablecoin/BRIDGE_RELAYER_DESIGN.md`
- Existing watcher: `watcher-rs/`
- Operator memory rules (founder-private):
  - `feedback_no_wallet_txt_in_chat`
  - `feedback_pre_pr_public_repo_leak_grep`
  - `feedback_no_asumsi_verify_specifics`
