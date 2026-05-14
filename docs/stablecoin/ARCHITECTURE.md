# Sentrix Bridged USDC — Architecture

> **NOT official Circle USDC.** Circle has not approved Sentrix.
> This document is the engineering plan for a Bridged USDC Standard-compatible deployment.

## Contracts

```
ETHEREUM SEPOLIA (testnet) / Ethereum mainnet (later)        SENTRIX 7120 / 7119
────────────────────────────────────────────────             ──────────────────

  Native USDC                                                FiatTokenV2_2 implementation
  (Circle-deployed, existing)                                (Circle's source code,
       │                                                      solc 0.6.12, optimizer 10M)
       │ user.approve(SourceBridgeProxy)                            │
       v                                                            │ delegatecall via
  SentrixUSDCSourceBridge (Sentrix-built, upgradeable)             │
       │ Proxy: ERC1967 (OZ) initially.                             v
       │ At handover Circle gets ownership of                AdminUpgradeabilityProxy
       │ the destination FiatToken proxy, not this           (Circle's exact proxy)
       │ source bridge.                                       Address = canonical USDC.e
       │
       │ Hyperlane Mailbox (Phase 2)
       │ or OPERATOR_ROLE EOA (Phase 1)                  Operator EOA holds:
       v                                                        owner, masterMinter,
                                                                pauser, blacklister,
        Hyperlane Mailbox + MultisigIsm                         rescuer, proxy admin
        (Phase 2 onward)                                        (single-sig bootstrap;
                                                                 see SINGLE_SIG_BOOTSTRAP_POLICY.md)
       │                                                        masterMinter configures
       │                                                        HypFiatToken (or Phase 1
       v                                                        operator EOA) as
                                                                a minter with allowance.
        HypFiatToken (Hyperlane extension,
        solc ^0.8.0) on Sentrix
        - wrappedToken = FiatToken proxy address
        - is configured as a minter on FiatToken
        - on inbound: mint(recipient, amount)
        - on outbound: takes user's USDC.e + burn(amount)
```

## Role topology

### Sentrix FiatToken proxy (canonical bridged USDC token)

| Role | Initial holder | Phase 4 (Circle handoff) |
|---|---|---|
| `admin` (proxy-level, AdminUpgradeabilityProxy) | 1-of-1 SentrixSafe (single-signer Phase 1-3a; threshold expansion at Phase 3b+) | Transferred to Circle |
| `owner` (implementation-level) | 1-of-1 SentrixSafe (single-signer Phase 1-3a; threshold expansion at Phase 3b+) | Transferred to Circle via `transferUSDCRoles` |
| `masterMinter` | 1-of-1 SentrixSafe (single-signer Phase 1-3a; threshold expansion at Phase 3b+) | Removed (Circle removes minters first, then takes owner) |
| `pauser` | 1-of-1 SentrixSafe (single-signer Phase 1-3a; threshold expansion at Phase 3b+) | Transferred to Circle |
| `blacklister` | 1-of-1 SentrixSafe (single-signer Phase 1-3a; threshold expansion at Phase 3b+) | Transferred to Circle |
| `rescuer` | 1-of-1 SentrixSafe (single-signer Phase 1-3a; threshold expansion at Phase 3b+) | Transferred to Circle |
| `minters` (configured) | Phase 1: 1-of-1 SentrixSafe (single-signer). Phase 2+: HypFiatToken contract address | Removed by partner before role transfer |

### Source bridge (`SentrixUSDCSourceBridge`)

| Role | Initial holder | Notes |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | 1-of-1 SentrixSafe (single-signer Phase 1-3a; threshold expansion at Phase 3b+) | Can grant/revoke all other roles |
| `OPERATOR_ROLE` | Phase 1: 1-of-1 SentrixSafe (single-signer Phase 1-3a; threshold expansion at Phase 3b+). Phase 2: Hyperlane handler contract | Calls `release` |
| `PAUSER_ROLE` | 1-of-1 SentrixSafe (single-signer Phase 1-3a; threshold expansion at Phase 3b+) | Pauses bridging |
| `CIRCLE_BURN_ROLE` | EMPTY until Circle requests | Granted by admin at upgrade time to Circle-specified address |
| `CIRCLE_ROLE_TRANSFER_ROLE` | EMPTY until Circle requests | Granted by admin at upgrade time to Circle-specified address |

### Off-chain (relayer + monitoring)

| Role | Purpose |
|---|---|
| Watcher (`watcher-rs`) | Observes Deposit / Burn events on both chains, validates confirmation depth, dedups, submits operator-signed `release` / `mint` |
| Reserve monitor | Compares source vault balance vs destination total supply, auto-pause on mismatch |
| Reorg watcher | Re-validates confirmed events after CONFIRMATION_DEPTH, alerts on reorg-past-mint |
| Status API (`api-rs`) | Exposes `/status`, `/readiness` for public status page |

## Flows

### Deposit (Sepolia → Sentrix)

1. User: `usdc.approve(SourceBridgeProxy, amount)`
2. User: `SourceBridge.deposit(recipient, amount)`
3. Bridge: `usdc.safeTransferFrom(user, this, amount)` — locks USDC
4. Bridge: emits `Deposit(depositId, sentrixChainId, depositor, recipient, amount, nonce)`
5. Relayer observes, waits CONFIRMATION_DEPTH, dedups by depositId
6. Phase 1 relayer: signs and submits `FiatToken.mint(recipient, amount)` from operator EOA which has minter role
7. Phase 2 Hyperlane: source emits Hyperlane message; HypFiatToken on Sentrix receives + calls `FiatToken.mint`

### Withdrawal (Sentrix → Sepolia)

1. User: `FiatToken.approve(HypFiatToken or operator)` then trigger burn
   - Phase 1: operator burns via custom flow (user transfers to operator wallet, operator burns + signals)
   - Phase 2: user calls `HypFiatToken.transferRemote(destination, recipient, amount)` which burns + emits Hyperlane message
2. Source bridge receives the message (Phase 2) or operator (Phase 1)
3. Source bridge: `release(withdrawalId, recipient, amount)` — sends USDC back to user

### Pause (any time)

1. PAUSER_ROLE holder calls `pauseBridging()` on source bridge
2. Equivalent: pauser calls `pause()` on FiatToken proxy on Sentrix
3. Deposits + releases + mints + burns + transfers blocked until unpause

### Reserve reconciliation

1. Watcher reads `usdc.balanceOf(SourceBridgeProxy)` and `FiatToken.totalSupply()` on Sentrix
2. Expects `balance >= totalSupply` (positive delta during in-flight deposits is normal)
3. If `totalSupply > balance + tolerance`: **alert + auto-pause**
4. Reconciliation log table written every 60s (see `BRIDGE_RELAYER_DESIGN.md`)

### Future Circle handoff (Phase 4, if Circle approves)

1. Operator + Circle agree (legal + technical due diligence pass)
2. Operator pauses bridging both sides + reconciles in-flight
3. Operator removes all configured minters on FiatToken
4. Operator's admin grants `CIRCLE_ROLE_TRANSFER_ROLE` to Circle's specified address (X)
5. X calls `SourceBridge.transferUSDCRoles(circleAddress)` — Phase 2 implementation cross-chain dispatches to destination bridge which calls `FiatToken.transferOwnership(circle)` + `FiatTokenProxy.changeAdmin(circle)`
6. Operator's admin grants `CIRCLE_BURN_ROLE` to Circle's other specified address (Y)
7. Circle grants the source bridge a zero-allowance minter role on Ethereum USDC
8. Y calls `SourceBridge.burnLockedUSDC()` — burns the bridge's full balance
9. Circle calls `FiatTokenProxy.upgradeTo(circleNativeUSDCImpl)` — upgrade complete
10. Sentrix bridged USDC.e now == native USDC

## Storage layout (source bridge)

Standard OZ upgradeable inheritance: `AccessControlUpgradeable` + `PausableUpgradeable` +
`ReentrancyGuardUpgradeable` + custom state. Storage gap `[40]` reserved for future
upgrades.

When upgrading the source bridge (e.g. to add Hyperlane message handler), MUST NOT
re-order or remove existing storage slots — append new state to the gap.

## What is NOT in this design

- A custom ERC20 bridged USDC. We use Circle's FiatToken unchanged.
- Trustless bridge in Phase 1. Phase 1 is operator EOA trusted; Phase 2
  introduces Hyperlane MultisigIsm.
- CCTP integration. Defer until Sentrix is on Circle's supported chain list.
- LayerZero or Wormhole for USDC. Reserved for SRX multichain.
- On-chain rate limiting (yet). Caps live at the masterMinter level — the
  destination FiatToken's masterMinter sets allowance for the minter (Phase 1
  operator or Phase 2 HypFiatToken). Rate-limit-per-period is a Phase 3+
  enhancement.
