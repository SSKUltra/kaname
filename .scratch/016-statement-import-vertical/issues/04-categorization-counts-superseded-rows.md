# 04 — Categorization walks and counts superseded rows, breaking the live rule

**Status:** ready-for-agent

**Found:** 2026-08-15, on the simulator, running **T129** (`quickstart.md` §5) to completion for
the second time. Importing the same 3-row statement three times made the summary read
`Transactions 3, Categorized 3, Left uncategorized 6` — nine rows accounted for by an import
that wrote three.
**Belongs to:** the engine — `core/crates/kaname-core/src/store.rs`, `load_account_transactions`.
**Severity:** ⚠️ **A live-rule violation of exactly the class `3ba7890` fixed on the front door.**
It inflates a figure on the one screen whose whole purpose is that a person can trust it.

## What is wrong

`load_account_transactions` (`store.rs:1706-1716`) is the candidate load for
`categorize_account_in`. Its predicate is:

```sql
WHERE account_id = ?1 AND is_deleted = 0 AND is_transfer = 0 ORDER BY rowid
```

It filters `is_deleted = 0` and **omits `superseded_by IS NULL`** — half of the live rule.

The live rule is a compile-time literal in the same file:

```rust
macro_rules! live_predicate { () => { "is_deleted = 0 AND superseded_by IS NULL" }; }
const LIVE: &str = live_predicate!();
```

Every other read that means *"the rows the person actually has"* uses it in full —
`PAGE_SQL` (`store.rs:212`), `account_summaries` (`store.rs:1815`), and both dedup candidate
loads (`store.rs:1353`, `store.rs:1357`). `load_account_transactions` is the **only** outlier.

## Why it fires on every re-import

`Store::import_statement` runs, in one transaction and in this order:

1. insert the statement's rows,
2. `link_reimported_rows_in` — points the repeats at the rows they duplicate via `superseded_by`,
3. `categorize_account_in` — **loads every non-deleted row, superseded ones included**,
4. `find_duplicates_in`.

So step 3 always sees the losers step 2 just created.

## What it costs

- **The summary lies about scale.** Three imports of a 3-row statement report
  `Categorized 3 / Left uncategorized 6` — nine rows, six of which no screen will ever show.
  Observed; screenshot in the session evidence.
- **Category writes land on invisible rows.** Harmless to the data, wasted work on the import
  path that SC-006 constrains, and it grows with every re-import.
- **It will mislead the next reader of these figures.** The columns are `categorized` /
  `uncategorized` on `CategorizeSummary`; nothing in the type says "including rows that lost a
  de-duplication".

## The fix

Add the missing half to the predicate, ideally by building it from `live_predicate!()` so the
literal cannot drift again:

```rust
concat!("... WHERE account_id = ?1 AND ", live_predicate!(), " AND is_transfer = 0 ORDER BY rowid")
```

## How to prove it

A `cargo test` over a real store: import a statement, import the **same** statement again, and
assert `categorized + uncategorized` equals the account's **live** row count, not its raw one.
That test must be watched failing against the current predicate before it is trusted — it goes
green by accident if the fixture has no duplicates.
