# Step 2 Broadcast Runbook — Deploy LZ V2 core to Sentrix Testnet

Prereqs: Step 1 prep complete (this repo built locally, `forge build` succeeds).

> **Key-handling rule.** Never `cat wallet.txt` to stdout, never pipe a
> plaintext key through `grep`/`awk`/`tee`. Plaintext in a pipeline lands
> in shell history, scrollback, terminal multiplexer buffers, and any
> tee'd log — and if the terminal session is being shared (chat, screen
> recording, support call) it leaks there too. Use `cast wallet
> decrypt-keystore --interactive` (TTY prompt, no echo) or
> `--password-file <path>` pointing at a 0600-perm file. The patterns
> below only feed the decrypted key into `DEPLOYER_PK` via process
> substitution — the plaintext never appears as a standalone shell token.

## 1. Load deployer private key

Pick one of:

### Option A — Faucet wallet (already premined with 100M SRX-test)

```bash
# Decrypt the faucet keystore. Interactive prompt — no password on the
# command line, no plaintext in shell history.
export DEPLOYER_PK=$(cast wallet decrypt-keystore \
  --interactive \
  ~/sentrix/secrets/faucets/testnet/keystore.json)

# Non-interactive variant (CI / scripted): point at a 0600 password file.
# The file must contain ONLY the password, no trailing newline noise.
#   chmod 600 ~/.config/sentrix/faucet-testnet.pw
# export DEPLOYER_PK=$(cast wallet decrypt-keystore \
#   --password-file ~/.config/sentrix/faucet-testnet.pw \
#   ~/sentrix/secrets/faucets/testnet/keystore.json)
```

### Option B — Fresh wallet + fund via faucet UI

```bash
# `cast wallet new` writes the new PK to stdout — run in a private TTY
# (no screen-share, no `tee`, no logged terminal). Persist by encrypting
# into a keystore immediately:
cast wallet new
# Then re-import that PK into a keystore file:
cast wallet import fresh-deployer --interactive
# Visit https://faucet.sentrixchain.com, drip to the printed address.
# Load DEPLOYER_PK from the keystore via Option A above.
```

## 2. Verify address has gas

```bash
DEPLOYER_ADDR=$(cast wallet address --private-key "$DEPLOYER_PK")
cast balance "$DEPLOYER_ADDR" --rpc-url sentrix_testnet
# Expect: at least 0.1 SRX-test (~100,000,000,000,000,000 wei)
```

## 3. Broadcast

```bash
cd ~/sentrix-bridge
forge script scripts/DeployLZ-SentrixTestnet.s.sol:DeployLZSentrixTestnet \
  --rpc-url sentrix_testnet \
  --broadcast \
  --skip-simulation \
  --legacy \
  -vvv
```

`--skip-simulation` is required: Sentrix's `eth_getBlockByNumber` returns short tx-hash arrays which foundry's simulation step can't decode. The deploy itself is unaffected — only the pre-broadcast simulation step.

## 4. Capture deployed addresses

Watch the script output for the final block:

```
=== Sentrix Testnet LayerZero V2 deployment complete ===
  EID:           40998
  EndpointV2:    0x___...
  SendUln302:    0x___...
  ReceiveUln302: 0x___...
```

Copy these into:
1. [`docs/lz-labs-application.md`](./lz-labs-application.md) — fill the "Deployed LayerZero V2 contracts (Testnet)" table.
2. Create `deployments/testnet.json` with `{ "eid": 40998, "endpointV2": "0x...", "sendUln302": "0x...", "receiveUln302": "0x..." }`.

## 5. Verify on explorer

Open `https://testnet-scan.sentrixchain.com/address/<address>` for each deployed contract. Confirm bytecode matches local artifact at `out/<Name>.sol/<Name>.json`.

## 6. Cleanup

```bash
unset DEPLOYER_PK
```

(`history -d` is unreliable — no-op in non-interactive shells, varies
across bash/zsh/HISTCONTROL settings, gives a false sense of safety.
Better: keep the keystore + interactive prompt pattern from §1 so no
plaintext key ever enters the shell as a token in the first place.)

## 7. Commit deployments

```bash
git add deployments/testnet.json docs/lz-labs-application.md
git commit -m "phase 0 step 2: LZ V2 core deployed to Sentrix Testnet, EID 40998 placeholder"
git push
```

## Expected gas spend

Approximate from the bytecode sizes:

| Contract | Bytecode | Deploy gas (est) | Cost @ 1 gwei |
|---|---|---|---|
| EndpointV2 | 21.7 KB | ~4.5M gas | ~0.0045 SRX-test |
| SendUln302 | 18.8 KB | ~4.0M gas | ~0.004 SRX-test |
| ReceiveUln302 | 9.1 KB | ~2.0M gas | ~0.002 SRX-test |
| `registerLibrary` × 2 | n/a | ~150k gas | ~0.0002 SRX-test |
| **Total** | — | **~10.7M gas** | **~0.011 SRX-test** |

Faucet wallet's 100M SRX-test budget is overkill; ~0.1 SRX-test is sufficient for the full Step 2 + a generous error budget.

## What this DOES NOT do

This step deploys + registers the protocol skeleton. It does NOT:
- Enable any cross-chain message routing (needs LZ Labs approval + DVN onboarding = Step 4-5).
- Quote fees for cross-chain sends (needs PriceFeed = Step 3).
- Deliver messages destination-side (needs Executor = Step 3).
- Verify inbound messages (needs DVN registration = Step 4).

Step 2's value is concrete deployable proof + addresses to put in the LZ Labs application form.

## Rollback

The deployed contracts are immutable. If a redeploy is needed (e.g. LZ Labs assigns a real EID and the placeholder 40998 won't match):
1. Re-run Step 2 with updated `SENTRIX_TESTNET_EID` constant in [`scripts/DeployLZ-SentrixTestnet.s.sol`](../scripts/DeployLZ-SentrixTestnet.s.sol).
2. Update `deployments/testnet.json` with new addresses.
3. The old contracts remain on-chain but become abandoned — operator can ignore.

No state migration required for Step 2 redeploy (no OApps yet wired to the abandoned endpoint).
