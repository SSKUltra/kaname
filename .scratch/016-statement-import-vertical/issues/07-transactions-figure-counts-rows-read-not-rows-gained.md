# 07 — "Transactions" counts rows read from the document, not rows the account gained

**Status:** needs-triage

**Found:** 2026-08-17, on the simulator, verifying `issues/05`'s fix on a **re-import** of the
six-row `gate/01-icici-0006.pdf`.
**Belongs to:** the engine — `core/crates/kaname-core/src/store.rs`, `import_statement`'s
`ImportOutcome` — surfaced by `ImportSummaryView`.
**Severity:** A trust defect on the trust screen. A person who re-imports a statement is told
they imported six transactions when the account gained **none**.
**Related:** `issues/05`, which *exposed* it rather than caused it. It was always wrong; four
figures of two different scopes were hiding it.

## What is on screen

Re-importing a six-row statement, under one heading:

```
Imported
  Transactions          6
  Duplicates skipped    6
```

Six rows in the document; six reported as imported; six reported as skipped. The two numbers
describe the **same six rows** and invite the reading "twelve rows were handled". The account
gained nothing at all.

Evidence: `../evidence/issue-05-resolved-two-sections-with-captioned-scope.png`.

## Why it happens

```rust
transactions_inserted: request.transactions.len() as u32,
duplicates_linked: duplicates.duplicates_linked + reimported,
```

`transactions_inserted` is the length of what the **reader handed over** — every row printed in
the document — taken before `link_reimported_rows_in` supersedes the ones already held. It is
therefore "rows in this statement", and the summary labels it "Transactions" under a heading
reading "Imported".

On a **first** import the two readings coincide, which is why this survived 016's gate and
`issues/05`'s: every figure is correct exactly when nothing is duplicated.

## Why the client cannot fix it

Net-new is not derivable from what crosses the bridge. `duplicates_linked` is
`duplicates.duplicates_linked + reimported` — cross-source de-duplication **plus** re-import
supersession — so `transactionsInserted - duplicatesSkipped` is not the number of rows the
account gained, and subtracting them would produce a *different* wrong number that happens to be
right in the common case. The engine has to say what it means.

## The decision this needs

- **Report net-new.** Add a figure for rows the account actually gained (the live rows this
  statement contributed after supersession), and label the existing one honestly — "Rows in this
  statement" — or drop it. Costs an `ImportOutcome` field and its FFI, no new query: the number
  is already known inside the transaction where `reimported` is computed.
- **Or relabel only.** "Rows read" / "Already held", no engine change, and the arithmetic stops
  being nonsense. Cheaper, but it never tells a person the thing they actually want to know after
  a re-import: *did anything change?*

⚠️ Whichever is chosen, **`transactions_inserted` should be renamed** — it is read as "inserted"
by every caller and it is not that. `Store::import_statement` is the only writer, so the rename
is contained.

## How to prove it

A `cargo test` over a real store: import a statement, import the **same** statement again, and
assert the second outcome reports **zero** rows gained while still reporting six rows read. It
must be watched failing against today's `request.transactions.len()`, which reports six either
way — a single-import fixture passes whatever the field means.
