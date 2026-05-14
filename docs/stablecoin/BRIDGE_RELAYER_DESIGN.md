# Bridge relayer design — Sentrix Bridged USDC (sUSDC)

This document specifies the off-chain backend that operates the bridge between
a source-chain `SourceChainVault` and the Sentrix `SentrixBridgedUSDC` token.
The on-chain contracts in `src/stablecoin/` are **trusted-party** — they do not
verify cross-chain proofs themselves; the relayer is responsible for that.

Throughout this doc the relayer is the off-chain process that holds the
`BRIDGE_MINTER_ROLE` key on Sentrix and the `OPERATOR_ROLE` key on the source
chain. In a production deployment those keys live behind a multisig (e.g.
Gnosis Safe) and the relayer assembles transactions for signing rather than
broadcasting directly.

## 1. Roles in the system

| Role | Holder | Permission |
|---|---|---|
| User | EOA / smart wallet | Deposit on source chain; burn on Sentrix |
| Relayer | Backend service | Observe events on both chains, propose mint / release transactions |
| Bridge minter | Smart contract address (or multisig) | Hold `BRIDGE_MINTER_ROLE` on `SentrixBridgedUSDC`, gated by `mintAllowance` |
| Vault operator | Smart contract address (or multisig) | Hold `OPERATOR_ROLE` on `SourceChainVault`, releases collateral |
| Admin | Multisig | Configure roles, set caps, pause |

## 2. Deposit flow (source chain -> Sentrix mint)

```
user                source-chain Vault                relayer                  Sentrix sUSDC
  | -- deposit() ----->|                                  |                          |
  |                    | -- emit Deposit -------------- > |                          |
  |                    | (Vault holds locked collateral)  |                          |
  |                    |                                  | wait CONFIRMATION_DEPTH  |
  |                    |                                  | poll for reorg           |
  |                    |                                  | dedup by depositId       |
  |                    |                                  | submit bridgeMint() ---> |
  |                    |                                  |                          | mint to recipient
  |                    |                                  | (mint allowance reduced) |
  |                    |                                  | mark deposit processed   |
```

### 2.1 Source-chain event watcher

For each supported source chain (initial: Sepolia testnet, future: Ethereum
mainnet) the relayer runs an event watcher subscribed to `Deposit` events on
the configured `SourceChainVault` address.

- Subscription via WebSocket RPC (`eth_subscribe` / `logs` filter).
- Fallback: HTTP polling every `POLL_INTERVAL_SECS` (default 5s) on the latest
  block. The two subscriptions run concurrently; the same event seen twice is
  deduplicated by `(depositId, sourceChainId)`.
- On each new event, write a row to the `deposits` table with status `seen`.

### 2.2 Confirmation depth per source chain

The relayer must NOT submit a `bridgeMint` until the source-chain block
containing the `Deposit` event is sufficiently buried under newer blocks.

| Source chain | Confirmation depth (blocks) | Notes |
|---|---|---|
| Ethereum Sepolia | 5 | Test bridge, small chain, fast finality |
| Ethereum mainnet | 32 (1 PoS epoch) | Production target |
| Base mainnet | 64 | L2 needs deeper depth pre-fault-proof |
| Arbitrum One | 64 | Same reasoning |

These are operator-tunable via the `bridge_config` table; see schema below.

### 2.3 Reorg handling

After a `Deposit` event has reached confirmation depth, the relayer rechecks
that the same `(transactionHash, logIndex)` is still present at the original
block number. If the canonical chain has reorganized past the event, the
deposit is reverted in the relayer DB (status `reorged`) and no mint is issued.

If a `bridgeMint` was already submitted but later the source-chain block
reorged out: this is a **HIGH-severity divergence** — the Sentrix supply now
exceeds the locked collateral. Emit an `RESERVE_MISMATCH` alert immediately and
freeze the bridge (call `pause()` on the Sentrix token). Recovery: see
`SECURITY_NOTES.md` reserve-mismatch section.

### 2.4 Idempotency

Each `Deposit` event has a `depositId` that is monotonic per-vault. The
relayer keeps a `processed_events` table keyed by
`(sourceChainId, vaultAddress, depositId)`. Every prospective mint checks this
table first and short-circuits if already processed. Database row insert uses
UNIQUE constraint to ensure single-writer semantics even under retry.

### 2.5 Mint transaction submission

For each confirmed, unprocessed deposit:

1. Build a `bridgeMint(depositId, sourceChainId, recipient, amount)`
   transaction targeting the Sentrix `SentrixBridgedUSDC` contract.
2. Estimate gas; abort if estimate fails (likely contract paused or allowance
   exhausted).
3. Sign with the bridge-minter key (or assemble for multisig).
4. Submit via the configured Sentrix RPC.
5. Wait for inclusion + 1 confirmation block on Sentrix.
6. On success: update `deposits` row status to `minted`, write `processed_events`.
7. On failure: increment `retry_count`, exponential backoff; after
   `MAX_RETRIES` (default 8) escalate to `failed_mint` alert.

## 3. Withdrawal flow (Sentrix burn -> source-chain release)

```
user                Sentrix sUSDC                  relayer            source-chain Vault
  | -- burnForWithdrawal -> |                          |                  |
  |                         | emit WithdrawRequested ->|                  |
  |                         | (tokens burned)          |                  |
  |                         |                          | wait CONF_DEPTH  |
  |                         |                          | dedup by widId   |
  |                         |                          | submit release()  >|
  |                         |                          |                  | transfer collateral
  |                         |                          | mark processed   |
```

### 3.1 Sentrix event watcher

Same mechanics as 2.1 but listening for `WithdrawRequested` on the token.

### 3.2 Sentrix confirmation depth

| Chain | Depth | Notes |
|---|---|---|
| Sentrix testnet | 3 | Light testing |
| Sentrix mainnet | 12 | Mainnet target post-stabilization |

### 3.3 Release transaction

1. Build `release(withdrawalId, recipient, amount)` against
   `SourceChainVault`.
2. Sign with `OPERATOR_ROLE` key (multisig).
3. Submit; track via `withdrawals` table mirroring the deposit table.

## 4. Database schema (PostgreSQL recommended)

```sql
CREATE TABLE deposits (
    id                  BIGSERIAL PRIMARY KEY,
    source_chain_id     BIGINT NOT NULL,
    vault_address       BYTEA  NOT NULL,
    deposit_id_onchain  NUMERIC(78,0) NOT NULL,
    tx_hash             BYTEA NOT NULL,
    log_index           INT   NOT NULL,
    block_number        BIGINT NOT NULL,
    depositor           BYTEA NOT NULL,
    recipient           BYTEA NOT NULL,
    token               BYTEA NOT NULL,
    amount              NUMERIC(78,0) NOT NULL,
    destination_chain   BIGINT NOT NULL,
    status              TEXT  NOT NULL,        -- seen | confirmed | minting | minted | reorged | failed
    retry_count         INT   NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_chain_id, vault_address, deposit_id_onchain)
);

CREATE TABLE withdrawals (
    id                  BIGSERIAL PRIMARY KEY,
    sentrix_chain_id    BIGINT NOT NULL,
    token_address       BYTEA  NOT NULL,
    withdrawal_id_onchain NUMERIC(78,0) NOT NULL,
    tx_hash             BYTEA NOT NULL,
    block_number        BIGINT NOT NULL,
    sender              BYTEA NOT NULL,
    recipient           BYTEA NOT NULL,
    amount              NUMERIC(78,0) NOT NULL,
    destination_chain   BIGINT NOT NULL,
    status              TEXT  NOT NULL,        -- seen | confirmed | releasing | released | failed
    retry_count         INT   NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (sentrix_chain_id, token_address, withdrawal_id_onchain)
);

CREATE TABLE processed_events (
    chain_id       BIGINT NOT NULL,
    contract_addr  BYTEA  NOT NULL,
    event_id       NUMERIC(78,0) NOT NULL,
    processed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (chain_id, contract_addr, event_id)
);

CREATE TABLE bridge_config (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by TEXT
);
-- Example rows:
--   ('confirmation_depth.1',     '32')     -- Ethereum mainnet
--   ('confirmation_depth.11155111', '5')   -- Sepolia
--   ('max_retries',              '8')
--   ('mint_per_user_daily_cap',  '5000000000')  -- 5,000 sUSDC

CREATE TABLE reserve_snapshots (
    id           BIGSERIAL PRIMARY KEY,
    snapshot_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_chain_id   BIGINT NOT NULL,
    vault_address     BYTEA  NOT NULL,
    vault_locked      NUMERIC(78,0) NOT NULL,    -- totalLocked() reading
    sentrix_chain_id  BIGINT NOT NULL,
    token_address     BYTEA  NOT NULL,
    sentrix_supply    NUMERIC(78,0) NOT NULL,    -- totalSupply() reading
    delta             NUMERIC(78,0) NOT NULL,    -- vault_locked - sentrix_supply
    alert_emitted     BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE admin_actions (
    id           BIGSERIAL PRIMARY KEY,
    action       TEXT NOT NULL,             -- pause | unpause | role_grant | role_revoke | allowance_set
    chain_id     BIGINT NOT NULL,
    contract_addr BYTEA NOT NULL,
    operator     BYTEA NOT NULL,
    payload      JSONB,
    tx_hash      BYTEA,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE relayer_jobs (
    id           BIGSERIAL PRIMARY KEY,
    job_type     TEXT NOT NULL,             -- mint | release | reserve_check
    payload      JSONB NOT NULL,
    status       TEXT NOT NULL,             -- queued | in_progress | done | failed
    attempts     INT NOT NULL DEFAULT 0,
    last_error   TEXT,
    next_attempt_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## 5. Reserve accounting + monitoring

The bridge is solvent iff:

```
SourceChainVault.totalLocked() >= SentrixBridgedUSDC.totalSupply()
```

(equality in steady state; vault may temporarily exceed supply when a deposit
is confirmed but mint hasn't landed yet, but supply must NEVER exceed vault).

The relayer runs a `reserve_check` job every `RESERVE_CHECK_INTERVAL` (default
60s) that:

1. Queries `vault.totalLocked()` on the source chain.
2. Queries `token.totalSupply()` on Sentrix.
3. Writes a `reserve_snapshots` row with the delta.
4. If `sentrix_supply > vault_locked + tolerance` (tolerance = 0): emit
   `RESERVE_MISMATCH` alert + auto-pause the Sentrix token via the configured
   admin path.

A small persistent positive delta (`vault_locked > sentrix_supply`) is normal
when there are deposits in flight. A persistent NEGATIVE delta is a
production-stop event.

## 6. Failure modes + alerts

| Event | Source | Alert | Auto-action |
|---|---|---|---|
| Mint tx fails N times | mint job retries exhausted | `BRIDGE_FAILED_MINT` | none |
| Release tx fails N times | release job retries exhausted | `BRIDGE_FAILED_RELEASE` | none |
| Reserve mismatch | reserve check | `RESERVE_MISMATCH` | pause Sentrix token |
| Source-chain reorg past confirmed deposit | reorg detector | `BRIDGE_REORG_POST_MINT` | pause Sentrix token |
| Vault paused (external) | event watcher | `VAULT_PAUSED` | halt deposit minting |
| Mint allowance < 10% of daily volume | health check | `BRIDGE_ALLOWANCE_LOW` | request replenishment |

Alerts route to Telegram + email + on-call PagerDuty equivalent.

## 7. Key management

### 7.1 Bridge minter key (Sentrix side)

- Held by a multisig contract (Gnosis Safe on Sentrix). Recommended threshold
  2-of-3 for testnet bootstrap, 3-of-5 for mainnet.
- The relayer submits multisig **proposals**, not direct transactions, when
  the role-holder is a multisig.
- For testnet PoC bootstrap, single EOA is acceptable BUT the private key MUST
  live in an HSM (AWS KMS / GCP KMS / hardware HSM / cloud secrets manager
  with rotation).
- NEVER store the private key in plain text, in source code, or in any file
  that ends up in a commit. Per [operator memory `feedback_no_wallet_txt_in_chat`](../../README.md#security-references).

### 7.2 Vault operator key (source chain)

- Same model as 7.1. Source-chain key is more sensitive because it controls
  release of REAL USDC.
- In production, the `OPERATOR_ROLE` MUST be a multisig contract address, not
  an EOA.

### 7.3 Relayer hot wallet

The relayer needs a small amount of gas funds on both chains to pay tx fees
when submitting through a multisig sponsor. This hot wallet is allowed to
hold ETH / SRX, NOT USDC / sUSDC.

- Hot wallet balance threshold alert at `BRIDGE_LOW_GAS`.
- Auto-top-up from a controlled source if balance drops below threshold.

## 8. Operator runbook (one-page)

| Symptom | Action |
|---|---|
| `RESERVE_MISMATCH` fires | (1) Confirm via cast call: `cast call $VAULT "totalLocked()"` vs `cast call $TOKEN "totalSupply()"`. (2) If real, the token is auto-paused — confirm. (3) Halt the relayer. (4) Begin incident response. |
| `BRIDGE_FAILED_MINT` | Inspect last error in `relayer_jobs`. Common causes: allowance exhausted (replenish via MINTER_ADMIN_ROLE), token paused, RPC outage. |
| `BRIDGE_FAILED_RELEASE` | Inspect last error. Common: insufficient vault balance (someone moved real USDC out — investigate), RPC outage. |
| `BRIDGE_REORG_POST_MINT` | Page on-call immediately. Pause token. Begin incident response. |
| `BRIDGE_ALLOWANCE_LOW` | MINTER_ADMIN_ROLE calls `setMintAllowance(minter, new_amount)`. Document in `admin_actions`. |
| Vault paused unexpectedly | Audit deposits queue — none should be in `minting` state at the same time vault is paused without operator intent. |
| Long-time-no-deposit | Health, not an incident. Watcher heartbeat still firing? |

For each alert there must be a one-page incident response playbook stored in
`docs/stablecoin/runbooks/` (to be written before mainnet flip).

## 9. Operational checklist before flipping the bridge live

- [ ] All contract roles set to multisig addresses (no EOA in production)
- [ ] Multisig threshold + signer set documented
- [ ] Reserve check cron running
- [ ] Reserve mismatch auto-pause tested on testnet
- [ ] Confirmation depth per source chain configured
- [ ] Retry / alert routes verified end-to-end on testnet
- [ ] Database backups configured (point-in-time recovery)
- [ ] Key rotation procedure rehearsed
- [ ] Caps configured: initial daily cap, per-tx cap, per-user cap
- [ ] External audit of the on-chain contracts passed
- [ ] Public status page deployed
- [ ] One-page runbook for each alert type
