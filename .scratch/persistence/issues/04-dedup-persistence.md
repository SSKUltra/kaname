# 04 — Dedup persistence (engine→store wiring)

**Status:** needs-triage

**What to build:** wire the **already-ported, parity-locked** cross-source de-duplicator
(`dedup::cross_source_duplicates`) to the encrypted store — run it over stored rows and
**persist the supersede state** so a transaction imported from two sources (a bank ledger and
a credit-card statement) isn't double-counted. No engine changes; fresh SQLite plumbing proven
by behavioural tests (like slices 02–03). Design of record: `.scratch/persistence/spec.md`
("Out of Scope": *feeding … dedup … from persisted rows and saving their results*); the
`dedup.rs` seam.

**Blocked by:** #01 encrypted-store bootstrap (done). Independent of #03.

## Open decision (settle with the user before implementing)

1. **"existing vs incoming" at store scope.** The pure fn compares **two ordered lists**
   (`existing`, `incoming`) and returns index matches; in the store, de-dup is **cross-account**
   (e.g. bank ledger vs CC statement). Define what maps to which list — by account import
   order? oldest-account-as-`existing`? all-pairs across accounts? — because it decides which
   row survives and which is flagged.
2. **Supersede persistence shape.** A link on `transactions` (`superseded_by TEXT REFERENCES
   transactions(id)` + `dedup_layer TEXT` for Canonical/Fuzzy) vs a separate `duplicates`
   table; and whether the loser is soft-deleted (`is_deleted = 1`) or just linked.

## Sketch (post-triage)

- Schema v4: the duplicate link chosen above (mirror the v2/v3 `ALTER TABLE … ADD COLUMN`).
- `store.find_duplicates()` (cross-account): load candidate rows → run
  `cross_source_duplicates` → persist the link/flag in one transaction; idempotent (skip rows
  already linked). Mirror the `categorize_account` / `detect_transfers` write-back pattern.
- `StoredTransaction` gains the link fields for readback.
- Behavioural tests (temp DB): a canonical dup + a fuzzy dup across accounts are linked; a
  genuine repeat survives (multiplicity-aware); idempotent re-run; readback.

## Deferred
Undo/merge UI; a “review duplicates” surface (P3); any network/cloud reconciliation.
