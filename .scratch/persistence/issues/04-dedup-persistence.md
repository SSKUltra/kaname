# 04 — Dedup persistence (engine→store wiring)

**Status:** resolved (shipped — schema v4 duplicate link + `find_duplicates` write-back)

**What to build:** wire the **already-ported, parity-locked** cross-source de-duplicator
(`dedup::cross_source_duplicates`) to the encrypted store — run it over stored rows and
**persist the supersede state** so a transaction imported from two sources (a bank ledger and
a credit-card statement) isn't double-counted. No engine changes; fresh SQLite plumbing proven
by behavioural tests (like slices 02–03). Design of record: `.scratch/persistence/spec.md`
("Out of Scope": *feeding … dedup … from persisted rows and saving their results*); the
`dedup.rs` seam.

**Blocked by:** #01 encrypted-store bootstrap (done). Independent of #03.

## Settled decisions (triage)

1. **"existing vs incoming" at store scope → oldest account first.** Accounts are ordered by
   `created_at` (tie-break on `id` for determinism); rows belonging to **earlier-created**
   accounts form `existing`, rows from the later account form `incoming`. The survivor is
   therefore the row from the account that was imported first, and it stays stable across
   re-runs. Same-account rows are never compared (a genuine repeat on one statement is not a
   cross-source duplicate).
2. **Supersede persistence → link-only columns on `transactions`.** `superseded_by TEXT
   REFERENCES transactions(id)` + `dedup_layer TEXT` (`Canonical`/`Fuzzy`). The loser is
   **linked, not soft-deleted** — `is_deleted` stays untouched, so the link is reversible and
   the list/UI layer decides what to hide. No separate `duplicates` table.

## Sketch

- Schema v4: `ALTER TABLE transactions ADD COLUMN superseded_by TEXT REFERENCES
  transactions(id)` + `ADD COLUMN dedup_layer TEXT` (mirror the v2/v3 forward-only pattern;
  constant/NULL defaults so it runs on a populated table).
- `store.find_duplicates()` (cross-account): load every non-deleted row with
  `superseded_by IS NULL`, joined to its account, ordered by account `created_at` → walk
  accounts oldest-first, comparing each account's rows (`incoming`) against the accumulated
  earlier rows (`existing`) via `cross_source_duplicates` → persist
  `superseded_by`/`dedup_layer` on the loser in one write transaction, guarded by
  `WHERE id = ? AND superseded_by IS NULL`. Mirrors the `categorize_account` /
  `detect_transfers` write-back pattern.
- New FFI record `DedupSummary { duplicates_linked: u32, canonical: u32, fuzzy: u32 }`.
- `StoredTransaction` gains `superseded_by: Option<String>` + `dedup_layer: Option<DedupLayer>`
  for readback (`NewTransaction` unchanged).
- Behavioural tests (temp DB, `tests/store_dedup.rs`): a canonical dup + a fuzzy dup across
  accounts are linked to the older account's row; a genuine same-account repeat survives
  (multiplicity-aware); no false positives; idempotent re-run links 0; deleted rows excluded;
  readback. Plus the v3→v4 upgrade unit test in `store.rs`. One Swift bridge test.

## Deferred
Undo/merge UI; a “review duplicates” surface (P3); any network/cloud reconciliation.
