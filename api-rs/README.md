# sentrix-bridge-api

Read-only HTTP status API for the sentrix-bridge Hyperlane v3 deployment. No private keys, no signing — every endpoint is either a static read of `deployments/*.json` or (TODO) an `eth_call` against a public RPC.

Same crate-isolation pattern as the sister `watcher-rs/` crate — its own `Cargo.toml`, no workspace.

## Build and run

```bash
# from the repo root
cd api-rs

# default — mainnet config, bind 127.0.0.1:8090
cargo run --release -- serve

# testnet config, all-interfaces bind
cargo run --release -- serve --bind 0.0.0.0:8090 --testnet

# point at a different deployments directory
cargo run --release -- serve --deployments-dir ../deployments
```

Build:

```bash
cargo build --release
```

Tests:

```bash
cargo test
```

## Endpoints

All responses are JSON. CORS is permissive (`Access-Control-Allow-Origin: *`) — same model as the chain RPC.

### `GET /health`

Liveness check. Always 200 if the process is up.

```bash
curl -s http://127.0.0.1:8090/health | jq
```

```json
{ "status": "ok", "uptime_seconds": 42 }
```

### `GET /status`

Top-level bridge state summary — counts, per-route summary, RPC + invariant + stuck-message slots (last three are TODO; return `"status": "unknown"` until the alloy probes land).

```bash
curl -s http://127.0.0.1:8090/status | jq
```

```json
{
  "network": "mainnet",
  "uptime_seconds": 42,
  "sentrix_rpc": { "configured": true },
  "sepolia_rpc": { "configured": true },
  "route_count": 2,
  "unsafe_route_count": 2,
  "routes": [{ "id": "msg-sentrix-testnet-sepolia", "...": "..." }],
  "rpc_health":         { "status": "unknown", "note": "..." },
  "wsrx_invariant":     { "status": "unknown", "note": "..." },
  "stuck_message_count":{ "status": "unknown", "count": 0, "note": "..." }
}
```

> Bare RPC URLs are intentionally omitted from this response — operators may
> point `SENTRIX_RPC_URL` / `SEPOLIA_RPC_URL` at keyed Infura/Alchemy
> endpoints. Endpoint config is reported as `{ "configured": true | false }`;
> the URL string itself only appears in tracing logs.

### `GET /routes`

List every route derived from `deployments/hyperlane-*.json`.

```bash
curl -s http://127.0.0.1:8090/routes | jq
```

```json
{
  "count": 2,
  "routes": [
    {
      "id": "warp-wsrx-sepolia",
      "name": "wSRX warp route Sentrix Testnet <-> Sepolia",
      "kind": "warp",
      "origin_chain_id": 7120,
      "origin_name": "sentrix-testnet",
      "destination_chain_id": 11155111,
      "destination_name": "sepolia",
      "source_token": "0xea0bC1f6141E0B0604B9bE19E260338973Fd6dD7",
      "destination_token": "0xC4BDE56bCAadfDbD6fBad685b65628f05994e5a8",
      "ism_type_origin": "NoopIsm",
      "ism_type_destination": "NoopIsm",
      "unsafe_flag": true,
      "unsafe_reasons": ["Sentrix Testnet side uses NoopIsm", "..."]
    }
  ]
}
```

### `GET /routes/:id`

Single-route detail. 404 on unknown id.

```bash
curl -s http://127.0.0.1:8090/routes/warp-wsrx-sepolia | jq
curl -s http://127.0.0.1:8090/routes/msg-sentrix-testnet-sepolia | jq
```

### `GET /messages?since=BLOCK&limit=N`

Recent dispatched/processed Hyperlane messages. **TODO** — returns a `pending_implementation` envelope with the same shape every list endpoint will use; UI clients can wire against it now.

```bash
curl -s 'http://127.0.0.1:8090/messages?since=3393000&limit=20' | jq
```

```json
{
  "status": "pending_implementation",
  "since": 3393000,
  "limit": 20,
  "messages": [],
  "note": "live Mailbox event scan not wired yet — see TODO in routes/messages.rs"
}
```

### `GET /messages/:id`

Single Hyperlane message lookup by 32-byte hash. **TODO**, same envelope shape.

```bash
curl -s http://127.0.0.1:8090/messages/0x4e2582c2704160dc4770fe24f9ab677ddce121ea36856507aa20108adebf9f63 | jq
```

### `GET /unsafe-config`

Every route currently flagged unsafe (NoopIsm or otherwise). Empty array == no flagged routes (still 200).

```bash
curl -s http://127.0.0.1:8090/unsafe-config | jq
```

```json
{
  "count": 2,
  "routes": [{ "id": "warp-wsrx-sepolia", "unsafe_reasons": ["..."], "...": "..." }]
}
```

### `GET /fresh-user-flow`

Status of the WSRX deposit → wrap → bridge → mint flow on testnet. Reads `data/fresh-user-flow.json` (operator updates after each successful run). Missing file returns `unknown`.

```bash
curl -s http://127.0.0.1:8090/fresh-user-flow | jq
```

```json
{
  "status": "unknown",
  "last_verified": null,
  "detail": { "note": "Operator updates this file after each successful run." }
}
```

To mark a run as passing, edit `data/fresh-user-flow.json`:

```json
{
  "status": "pass",
  "last_verified": "2026-05-14T10:30:00Z",
  "detail": {
    "wrap_tx_sentrix":   "0x...",
    "approve_tx_sentrix":"0x...",
    "bridge_tx_sentrix": "0x...",
    "mint_tx_sepolia":   "0x...",
    "amount_wei":        "1000000000000000",
    "recipient":         "0x..."
  }
}
```

### `GET /readiness`

Production-readiness checklist. Each item: `name`, `status` (`pass` | `fail` | `pending`), `description`. Mirrors the Phase 4 gate in `docs/multichain-roadmap.md` — when an item closes, flip its status here AND tick the box in the doc.

```bash
curl -s http://127.0.0.1:8090/readiness | jq
```

```json
{
  "items": [
    {
      "name": "sentrix#580 closed",
      "status": "pass",
      "description": "EVM value-transfer + gas-fix forks activated 2026-05-13."
    },
    {
      "name": "External audit pass",
      "status": "pending",
      "description": "Audit firm TBD. Code4rena contest is a candidate."
    }
  ],
  "pass_count": 1,
  "pending_count": 7,
  "fail_count": 0,
  "overall": "pending"
}
```

## Configuration

All overrides via env var:

| Env var                      | Default                                          | Notes                                         |
| ---------------------------- | ------------------------------------------------ | --------------------------------------------- |
| `SENTRIX_RPC_URL`            | `https://rpc.sentrixchain.com`                   | Mainnet                                       |
| `SENTRIX_TESTNET_RPC_URL`    | `https://testnet-rpc.sentrixchain.com`           | Used when `--testnet`                         |
| `SEPOLIA_RPC_URL`            | `https://ethereum-sepolia.publicnode.com`        | Public default; operators should swap in their own keyed endpoint |
| `BRIDGE_DEPLOYMENTS_DIR`     | `deployments`                                    | Path resolved relative to CWD                 |
| `BRIDGE_FRESH_USER_FLOW_PATH`| `api-rs/data/fresh-user-flow.json`               | Path resolved relative to CWD                 |
| `RUST_LOG`                   | `info`                                           | Standard `tracing-subscriber` filter          |

Operator-private RPC keys live in `.env.production` (gitignored), never committed.

## TODOs (deferred to follow-up PRs)

- `/messages` and `/messages/:id` — live Mailbox `Dispatch` / `ProcessId` event scan via alloy.
- `/status.rpc_health` — `eth_blockNumber` + `eth_chainId` probe on each RPC.
- `/status.wsrx_invariant` — cross-side `WSRX.totalSupply()` vs `HypERC20.totalSupply()`.
- `/status.stuck_message_count` — Dispatch events without matching ProcessId in last N blocks.

These share the same alloy provider scaffolding as `watcher-rs/`; once that lands there we can lift the implementation.
