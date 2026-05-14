# sentrix-bridge-watcher

Read-only safety + route health monitor for the `sentrix-bridge` Hyperlane v3
deployment.

The watcher reads `deployments/*.json` from this repo, walks every Mailbox +
warp-route contract, and emits a single structured report. It does no
signing, holds no keys, and is safe to run from CI or a cron timer.

## Run

From the repo root:

```bash
# Mainnet defaults (https://rpc.sentrixchain.com)
cargo run --manifest-path watcher-rs/Cargo.toml -- status

# Testnet
cargo run --manifest-path watcher-rs/Cargo.toml -- status --testnet

# Machine-readable
cargo run --manifest-path watcher-rs/Cargo.toml -- status --testnet --json

# Single-check shortcuts
cargo run --manifest-path watcher-rs/Cargo.toml -- check-noopism --testnet
cargo run --manifest-path watcher-rs/Cargo.toml -- check-balance --testnet
```

Or with the binary on `$PATH`:

```bash
sentrix-bridge-watcher status --testnet --json
```

## Configuration

| Source | Variable | Default |
|---|---|---|
| CLI flag | `--sentrix-rpc` | `https://rpc.sentrixchain.com` (mainnet) / `https://testnet-rpc.sentrixchain.com` (testnet) |
| CLI flag | `--sepolia-rpc` | `https://ethereum-sepolia-rpc.publicnode.com` |
| CLI flag | `--deployments-dir` | `<repo-root>/deployments` |
| Env | `SENTRIX_RPC_URL` | overrides default if no flag given |
| Env | `SEPOLIA_RPC_URL` | overrides default if no flag given |
| Env | `BRIDGE_DEPLOYMENTS_DIR` | overrides default if no flag given |

Operator's Infura/Alchemy keys go in env, never on the CLI (CLI values land
in shell history). The watcher never writes to disk.

## Checks

| # | Check | Module | Notes |
|---|---|---|---|
| 1 | Route enumeration from `deployments/*.json` | `checks::mod` | warp + reverse warp + HypNative |
| 2 | NoopIsm detection on each warp route | `checks::noopism` | Suppressed by `unsafeDemo: true` per-side |
| 3 | MultisigIsm validator-set + threshold | `checks::multisig` | Helper present; only invoked when an ISM exposes `validatorsAndThreshold` |
| 4 | Mailbox `localDomain` / `defaultIsm` / `defaultHook` | `checks::mod::inspect_mailbox` | Compares localDomain to expected chain id |
| 5 | wSRX 1:1 invariant | `checks::balance` | `collateral.balanceOf(WSRX) == hyperc20_sepolia.totalSupply()` |
| 6 | Sentrix RPC liveness | `checks::rpc` | `eth_blockNumber` + `eth_chainId` |
| 7 | Sepolia RPC liveness | `checks::rpc` | same |
| 8 | Stuck `Dispatch` without matching `ProcessId` | `checks::stuck` | Best-effort; capped by RPC `getLogs` range |

Anything that should page lands in the top-level `warnings` array.

## Sample JSON output

```json
{
  "timestamp": "2026-05-14T12:00:00.000Z",
  "network": "testnet",
  "sentrix_rpc": {
    "url": "https://testnet-rpc.sentrixchain.com",
    "ok": true,
    "block": 3787001,
    "chain_id": 7120
  },
  "sepolia_rpc": {
    "url": "https://ethereum-sepolia-rpc.publicnode.com",
    "ok": true,
    "block": 10844500,
    "chain_id": 11155111
  },
  "mailboxes": [
    {
      "label": "sentrix-testnet-mailbox",
      "address": "0x9741D99270aF14D4baca0e387B6ac0500b9a288F",
      "chain_id": 7120,
      "local_domain": 7120,
      "default_ism": "0x28834aa535f3130f0f60571ac7a813195ae56ec6",
      "default_hook": "0x6a192c8fea612ca3aa204035e51f6a624b0f1467",
      "local_domain_matches": true
    }
  ],
  "routes": [
    {
      "id": "warp-wsrx-sentrix-to-sepolia",
      "source_chain": 7120,
      "destination_chain": 11155111,
      "source_contract": "0xfb8190927034c447Fc29B1cfbF4f4F000969bb32",
      "destination_contract": "0xC4BDE56bCAadfDbD6fBad685b65628f05994e5a8",
      "ism_address": "0x28834aa535f3130f0f60571ac7a813195ae56ec6",
      "ism_type": "NoopIsm",
      "unsafe_demo": false,
      "unsafe_flags": ["NoopIsm-on-warp-route-unsafe"]
    }
  ],
  "wsrx_invariant": {
    "wsrx_total_supply_sentrix": "1000000000000000",
    "wsrx_locked_in_collateral": "1000000000000000",
    "hyperc20_total_supply_sepolia": "1000000000000000",
    "drift_wei": "0",
    "ok": true
  },
  "stuck_messages": [],
  "warnings": [
    "warp-wsrx-sentrix-to-sepolia: NoopIsm-on-warp-route-unsafe"
  ]
}
```

## Build

```bash
cargo build --release --manifest-path watcher-rs/Cargo.toml
```

`cargo test --manifest-path watcher-rs/Cargo.toml` runs the unit tests
(JSON shape, NoopIsm classifier, drift maths, MultisigIsm message synth,
config defaults). Tests don't hit the network.

## Deliberately out of scope

- Signing / sending transactions (read-only by design).
- Loading `.env` files — operator already does that at the shell.
- Cross-checking LayerZero V2 endpoint state (LZ stack is still placeholder
  pending official EID assignment).
- Subscribing to live Mailbox events — the watcher is a one-shot poller.
  Wire it into a cron / systemd timer for periodic checks.
