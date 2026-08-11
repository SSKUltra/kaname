# 05 — Coverage persistence (engine→store wiring)

**Status:** needs-triage

**What to build:** wire the **already-ported, parity-locked** coverage map
(`coverage::compute_coverage`) to the encrypted store, so a person can see which of the rolling
24 months of their history are GAP / PARTIAL / COVERED. Unlike dedup/transfer, coverage needs
**new facts the store doesn't hold yet** — a `statements` table and per-transaction provenance
— so this slice is as much "persist statements" as it is "wire coverage". No engine changes.
Design of record: `.scratch/persistence/spec.md`; the `coverage.rs` seam.

**Blocked by:** #01 encrypted-store bootstrap (done).

## Open decision (settle with the user before implementing)

1. **`statements` table shape.** Coverage reads one `StatementCoverage { period_end,
   needs_review }` per imported statement. Decide the persisted row: `id, account_id,
   period_start, period_end, needs_review, source, created_at`? This is a **foundational schema
   addition** (statements are new to the store) — and it may deserve to be its own sub-slice
   ("import → persist a statement row") that coverage then reads. Decide whether to split.
2. **Transaction provenance.** Coverage's other fact is `TransactionCoverage { date,
   from_full_statement }`. Persist a `statement_id` FK on `transactions` (richer, future-proof —
   derive `from_full_statement` from it) vs a bare `from_full_statement` boolean.
3. **Read-only surface.** Expose `store.coverage(account_id, today) -> Vec<MonthCoverage>` —
   `today` is an **explicit param** (the core reads no wall-clock; the platform passes it).

## Sketch (post-triage)

- Schema vN: `CREATE TABLE statements` + `ALTER TABLE transactions ADD COLUMN statement_id`
  (and/or `from_full_statement`).
- Insert/list statements; `store.coverage(account_id, today)` loads the facts → runs
  `compute_coverage` → returns the month entries (no write-back — coverage is a report).
- Behavioural tests (temp DB): a directly-imported statement ⇒ COVERED; piecemeal rows ⇒
  PARTIAL; empty month ⇒ GAP; a needs-review statement badges its month; window is clock-free
  (pass `today`).

## Deferred
The coverage UI (P3); backfill prompts; anything network.
