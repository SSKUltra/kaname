# 07 — "Transactions" counts rows read from the document, not rows the account gained

**Status:** resolved

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

---

## Resolution — 2026-08-17, by the holder's decision: **report net-new**

Of the two readings, the holder chose the one that answers the question a person re-importing
actually has — *did anything change?* — rather than the cheaper relabel that would only have
stopped the arithmetic being nonsense.

**Engine.** `ImportOutcome` now carries three figures where it carried one:

| Field | Means |
|---|---|
| `rows_read` | every transaction printed in the document (was `transactions_inserted`) |
| `transactions_added` | how many of them the account **gained** |
| `rows_superseded` | the rest — rows of this statement that lost to a row already held |

`rows_read == transactions_added + rows_superseded`, always, so the two numbers a person is shown
account for the document in front of them.

⚠️ **`transactions_added` is counted from the rows, not derived.** `count_live_statement_rows_in`
runs a `COUNT(*)` over this statement's rows after **every** linking pass, built from
`live_predicate!()` like every other read that means "the rows the person has". Deriving it from
`reimported` would have missed a row lost to *cross-source* de-duplication; deriving it from
`duplicates_linked` would have counted links made elsewhere in the store, because that figure is
store-wide. Both derivations are right in the common case and wrong in the interesting one.

`duplicates_linked` is unchanged and stays store-wide — callers that measure the de-duplicator
still want it — but it is documented as such and is deliberately **not** what the summary shows.

**Client.** `ImportSummary.transactionsAdded` / `.rowsAlreadyHeld`, rendered as
**"Transactions added"** and **"Already in Kaname"**. A re-import of the six-row `gate/` statement
now reads `0` and `6`. Evidence:
`../evidence/issue-07-resolved-reimport-adds-nothing.png`.

**Proof** — `importing_the_same_statement_twice_does_not_double_history` now asserts all three
figures and that they sum. **Watched failing**: with `transactions_added = rows_read` — the
behaviour this ticket describes — it goes red at the `transactions_added` assertion. A
single-import fixture passes whatever the field means, which is why the re-import test is the one
that had to carry it.

⚠️ **The rename was the point, not a tidy-up.** `transactions_inserted` was read as "rows added"
by every caller including the screen, and it never meant that. Renaming it to `rows_read` makes
the old mistake unspellable; there is no longer a field whose name promises something it does not
count.
