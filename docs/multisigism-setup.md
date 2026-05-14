# MultisigIsm setup — replacing NoopIsm

The Phase 0 testnet route uses Hyperlane's `NoopIsm` — every inbound message is accepted with zero verification. Fine for demonstrating the dispatch + process flow, **fatal** for value bridging. This runbook covers the swap to `MultisigIsm`, where m-of-n trusted validators must co-sign each message before the destination Mailbox accepts it.

Tracked as [issue #3](https://github.com/sentrix-labs/sentrix-bridge/issues/3). Stays in **plan / dry-run** state until the validator set is finalized — actual deploy is operator-triggered.

## What MultisigIsm does

Each message a destination chain accepts must come with:

1. A `MessageId` (keccak256 of the message envelope).
2. A merkle root of the source Mailbox's MerkleTreeHook for that height.
3. ≥ `threshold` signatures from the configured validator set, each signing `(MessageId, merkleRoot, sourceMailbox, sourceDomain)`.

The verifier replays the signatures on-chain, compares the recovered addresses against the configured set, and rejects if fewer than `threshold` match.

Concretely: an attacker who controls the relayer (or anyone calling `Mailbox.process(...)`) still can't forge messages — they'd need to compromise `threshold` validator private keys simultaneously.

## Decisions the operator owns

These must be settled before deployment:

1. **Validator set per destination.** Same n validators across all chains, or per-chain rotation?
2. **Threshold (m).** 2-of-3 is common for testnet, 3-of-5 or 4-of-7 for mainnet.
3. **Validator hosts.** Operator's existing infra? Sentrix Foundation validators? External operators?
4. **Recovery policy.** What happens if a validator key is lost or compromised? Hyperlane MultisigIsm requires a redeploy to rotate the set — there's no on-chain rotation function. Practically: deploy a fresh MultisigIsm with the new set, update each TestRecipient / warp-route contract's `interchainSecurityModule` pointer.

Default recommendation for the testnet bake:

- 2-of-3 threshold
- Three Sentrix Foundation-controlled keys (separate from the chain's validator signing keys — fresh keys, fresh hosts)
- Same set on both Sentrix Testnet and Sepolia sides

## Deploy steps

### 1. Generate validator keys

Each validator runs on its own host. Keep keys off the deploy host — generate locally, transfer ciphertext or use HSM:

```bash
# Per validator. Sentrix's wallet CLI works for this — same secp256k1 curve.
sentrix wallet new --out /tmp/validator-1.keystore
# Repeat for validator-2, validator-3. Note the addresses.
```

Record the validator addresses + label them by host (`validator-1@vps-X`, etc.) in a private operator doc — not in this repo.

### 2. Deploy MultisigIsm on each side

```bash
# Sentrix Testnet side
export DEPLOYER_PK=<sentrix-testnet-deployer-key>
export VALIDATORS="0xaaa...,0xbbb...,0xccc..."   # comma-separated
export THRESHOLD=2
forge script hyperlane/scripts/DeployMultisigIsm.s.sol:DeployMultisigIsm \
  --rpc-url sentrix_testnet \
  --broadcast \
  --legacy

# Sepolia side (same validator set, same threshold)
forge script hyperlane/scripts/DeployMultisigIsm.s.sol:DeployMultisigIsm \
  --rpc-url sepolia \
  --broadcast
```

The deployed addresses go into `deployments/hyperlane-{testnet,sepolia}.json` alongside the existing NoopIsm entries — keep the old NoopIsm address around for reference; don't overwrite history.

### 3. Run validator agents

Each validator host runs Hyperlane's `validator` binary (Rust, from `hyperlane-monorepo/rust`). The agent:

- Subscribes to the source Mailbox's `Dispatch` events.
- Signs every observed message with its configured key.
- Posts signatures to the configured signature store (S3 / Cloudflare R2 / GCS / local filesystem).

Config skeleton (per validator):

```yaml
chains:
  sentrixtestnet:
    name: sentrixtestnet
    domain: 7120
    rpcUrls: [{ http: https://testnet-rpc.sentrixchain.com }]
    blocks: { reorgPeriod: 1 }      # Sentrix has single-block finality
    mailbox: 0x9741D99270aF14D4baca0e387B6ac0500b9a288F
    merkleTreeHook: 0x6A192C8fEA612CA3aa204035e51F6a624b0F1467
  sepolia:
    name: sepolia
    domain: 11155111
    rpcUrls: [{ http: https://ethereum-sepolia-rpc.publicnode.com }]
    blocks: { reorgPeriod: 14 }     # Sepolia uses Casper-FFG finality
    mailbox: 0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766
    merkleTreeHook: 0x4917a9746A7B6E0A57159cCb7F5a6744247f2d0d

originChainName: sentrixtestnet     # this validator signs Sentrix→other messages
validator:
  key: file:///etc/hyperlane/validator-1.json
checkpointSyncer:
  type: s3
  bucket: sentrix-hyperlane-signatures
  region: us-east-1
```

Run one validator instance per origin chain — i.e. each validator host runs two processes if you bridge in both directions. (Or: dedicate validators per direction, depending on operator preference.)

### 4. Run relayer agent

A single relayer host watches the signature store, collects ≥ threshold signatures per message, and submits to the destination Mailbox's `process(...)`. Hyperlane's `relayer` binary handles this:

```yaml
relayChains: [sentrixtestnet, sepolia]
allowLocalCheckpointSyncers: false
db: /var/lib/hyperlane/relayer-db
gasPaymentEnforcement:
  - type: none                      # testnet: free relays. Mainnet: configure InterchainGasPaymaster
```

The relayer is permissionless in principle — anyone can run one — but typically the bridge operator runs the canonical one.

### 5. Swap ISM pointer on TestRecipient AND warp-route contracts

Once the agent network is healthy + signatures landing in the store, point
**every** consumer at the new MultisigIsm. The original Phase 0 runbook only
covered the TestRecipient demo contracts — the warp-route contracts
(`HypERC20Collateral` on Sentrix Testnet + `HypERC20` wSRX on Sepolia) also
default to NoopIsm and MUST be flipped before any value crosses, otherwise
anyone can mint wSRX on Sepolia without locking SRX on Sentrix once TVL > 0.

```bash
# === Sepolia side ===
# 5a. TestRecipient (demo only)
cast send 0x843fA9...258 "setInterchainSecurityModule(address)" <MultisigIsm-Sepolia> \
  --rpc-url sepolia --private-key $DEPLOYER_PK

# 5b. HypERC20 wSRX mint contract (PRODUCTION — value bridge)
cast send 0xC4BDE56bCAadfDbD6fBad685b65628f05994e5a8 \
  "setInterchainSecurityModule(address)" <MultisigIsm-Sepolia> \
  --rpc-url sepolia --private-key $DEPLOYER_PK

# === Sentrix Testnet side ===
# 5c. TestRecipient (demo only)
cast send 0x1feBBD...CfF4c4 "setInterchainSecurityModule(address)" <MultisigIsm-SentrixTestnet> \
  --rpc-url sentrix_testnet --private-key $DEPLOYER_PK --legacy

# 5d. HypERC20Collateral SRX-lock contract (PRODUCTION — value bridge)
cast send 0xfb8190927034c447Fc29B1cfbF4f4F000969bb32 \
  "setInterchainSecurityModule(address)" <MultisigIsm-SentrixTestnet> \
  --rpc-url sentrix_testnet --private-key $DEPLOYER_PK --legacy
```

Verify each swap landed (must echo back the new MultisigIsm address, NOT
`0x000…000` and NOT the old NoopIsm address):

```bash
# Sepolia warp-route ISM
cast call 0xC4BDE56bCAadfDbD6fBad685b65628f05994e5a8 \
  "interchainSecurityModule()(address)" --rpc-url sepolia
# expect: <MultisigIsm-Sepolia>

# Sentrix Testnet warp-route ISM
cast call 0xfb8190927034c447Fc29B1cfbF4f4F000969bb32 \
  "interchainSecurityModule()(address)" --rpc-url sentrix_testnet
# expect: <MultisigIsm-SentrixTestnet>

# Same for both TestRecipients (sanity check the demo path too)
cast call 0x843fA9...258 "interchainSecurityModule()(address)" --rpc-url sepolia
cast call 0x1feBBD...CfF4c4 "interchainSecurityModule()(address)" --rpc-url sentrix_testnet
```

If any of the four still returns the NoopIsm address, the swap was missed —
re-run the corresponding `cast send` before any user-facing announcement.

### 6. Re-verify cross-chain message

Same dispatch script as before — no manual `process(...)` this time, the relayer handles it. End-to-end success when:

- Validator agents log "signed message <id>" for each dispatch.
- Relayer logs "submitted <id> to destination" after collecting ≥ threshold sigs.
- Destination TestRecipient emits `Handled(...)` log.

## Failure modes to test before mainnet

Before considering this production-ready, deliberately break things:

| Scenario | Expected behaviour |
|---|---|
| Stop one validator (n-1 left signing) | Messages still relay if `n-1 >= threshold`. |
| Stop `n - threshold + 1` validators | Relayer stalls; messages queue but don't process. Auto-recovers when enough validators restart. |
| Relayer goes down | Messages queue at the signature store. When relayer restarts, it drains the backlog. No data loss. |
| Send malformed message body | Destination handler reverts; relayer logs the failure; cross-chain state isn't corrupted. |
| Forge a signature with random key | MultisigIsm rejects; message doesn't process. |

Run each for at least 24 h before considering Phase 2 complete.

## Why this is not yet deployed

The operator hasn't finalized the validator set. The runbook is written so a future session can act on it as soon as the validator set is decided — no further investigation needed at that point, just key generation + script invocation.
