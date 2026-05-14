# Single-signer bootstrap policy — SUPERSEDED

> **THIS DOC IS SUPERSEDED.** See `BOOTSTRAP_ROLE_HOLDER.md` for the canonical
> bootstrap role holder policy.

## Why this stub

Earlier sessions used "single-sig EOA" and "1-of-1 multisig" interchangeably.
After auditing the repo + founder-private notes (2026-05-14), the canonical
bootstrap role holder was confirmed to be **SentrixSafe** — Sentrix Labs'
own Safe-like multi-sig contract from `sentrix-labs/canonical-contracts`,
currently 1-of-1 with the operator's Authority as sole owner.

`BOOTSTRAP_ROLE_HOLDER.md` replaces this doc's terminology. Read that one
instead.

## What was right in this doc

- The trust model (single-signer) is accurate during bootstrap.
- The honest disclosure principle stands.
- The N-of-M graduation roadmap (Phase 3b+) stands.
- The key hygiene checklist (HSM, geographic backup, role-family separation)
  applies to the operator's Authority key that controls SentrixSafe.

## What was misleading

- This doc called the bootstrap holder "EOA" or "1-of-1 multisig"
  ambiguously. The actual holder is the SentrixSafe contract — a single
  smart-contract address that wraps the Authority signing key.
- Raw EOA was proposed as fallback. Acceptable, but not the default per
  operator's established pattern.

For the canonical policy + Phase 3a/3b/3c progression, env vars, and Circle
role mapping, see `BOOTSTRAP_ROLE_HOLDER.md`.
