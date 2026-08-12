# 05 — Coverage persistence (engine→store wiring)

**Status:** resolved (shipped — schema v5 `statements` + provenance + `store.coverage`)

**What to build:** wire the **already-ported, parity-locked** coverage map
(`coverage::compute_coverage`) to the encrypted store, so a person can see which of the rolling
24 months of their history are GAP / PARTIAL / COVERED. Unlike dedup/transfer, coverage needs
**new facts the store doesn't hold yet** — a `statements` table and per-transaction provenance
— so this slice is as much "persist statements" as it is "wire coverage". No engine changes.
Design of record: `.scratch/persistence/spec.md`; the `coverage.rs` seam.

**Blocked by:** #01 encrypted-store bootstrap (done).

## Settled decisions (triage)

0. **Scope → one slice.** The `statements` table has no consumer without coverage, and one
   migration is cleaner than two, so introducing statements and wiring `compute_coverage` ship
   together.
1. **`statements` row → the full row.** `id, account_id, bank_code, period_start, period_end,
   needs_review, source, created_at`. `period_start` is nullable (readers don't always recover
   it); `source` is an enum-ish TEXT (`'Statement'` / `'Alert'`) with a CHECK. This mirrors
   `ParsedStatement` and future-proofs the import-history surface, even though
   `compute_coverage` reads only `period_end` + `needs_review`.
2. **Provenance → `statement_id` FK.** `ALTER TABLE transactions ADD COLUMN statement_id TEXT
   REFERENCES statements(id)` (nullable — a live-alert row has none). `from_full_statement` is
   **derived**, not stored: a row is from a full statement when its `statement_id` resolves to a
   statement whose `source` is `'Statement'`. No redundant flag to drift.
3. **Read-only surface.** `store.coverage(account_id, today) -> Vec<MonthCoverage>` — coverage
   is a **report**, not a write-back, and `today` is an explicit param (the core reads no
   wall-clock, Constitution II).

## Sketch

- Schema v5: `CREATE TABLE statements` (the full row above) + `ALTER TABLE transactions ADD
  COLUMN statement_id TEXT REFERENCES statements(id)`.
- `insert_statement(NewStatement) -> String` / `list_statements(account_id)`; `NewTransaction`
  gains an optional `statement_id` so an imported row can be attributed at insert time.
- `store.coverage(account_id, today)` loads one `StatementCoverage` per statement and one
  `TransactionCoverage` per non-deleted row (`from_full_statement` derived by the join) → runs
  the pure `compute_coverage` → returns the 24 `MonthCoverage` entries. No write-back.
- Behavioural tests (temp DB): a statement's period-end month ⇒ COVERED; piecemeal rows with no
  statement ⇒ PARTIAL; an empty month ⇒ GAP; a `needs_review` statement badges its month; an
  `'Alert'`-source statement does **not** make its rows COVERED; the window is clock-free
  (passing a different `today` slides it); deleted rows excluded. Plus the v4→v5 upgrade unit
  test and one Swift bridge test.

## Deferred
The coverage UI (P3); backfill prompts; anything network.
