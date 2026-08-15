# 05 — The import summary mixes per-import figures with account-wide ones

**Status:** needs-triage

**Found:** 2026-08-15, on the simulator, running **T129** (`quickstart.md` §5) to completion.
**Belongs to:** `016-statement-import-vertical` — `ImportSummaryView`, and
`Store::import_statement`'s `ImportOutcome`.
**Severity:** A trust defect on a trust screen. Not a wrong number in isolation — a wrong
*scope*, under a heading that states the scope.
**Related:** issue `04`, which makes the same figures additionally count invisible rows. Fixing
04 does **not** fix this: the mismatch survives it whenever a second, *different* statement is
imported into an existing account.

## What is on screen

The section is headed **"Imported"** and reads:

| Row | Scope |
|---|---|
| Transactions | **this import** — `outcome.transactions_inserted` |
| Duplicates skipped | **this import** — `outcome.duplicates_linked` |
| Categorized | **the whole account** — `categorize_account_in(account_id)` |
| Left uncategorized | **the whole account** |

Observed after three imports of one 3-row statement: `Transactions 3`, `Duplicates skipped 3`,
`Categorized 3`, `Left uncategorized 6` — evidence
`../evidence/summary-mixed-scope-3-imported-9-counted.png`. A person reading four numbers under
one heading has no way to know two of them describe a different set from the other two, and they
do not sum.

## Why it happens

`ImportService.persist` (`ios/Sources/Import/ImportService.swift:165-176`) fills the summary from
one `ImportOutcome`, but the engine builds that record from two different scopes —
`request.transactions.len()` for the insert count, and `categorize_account_in(&tx, &account_id)`
for the categorization, which **recomputes every row in the account** by design ("Recomputes every
row, so it is idempotent", `store.rs:1085`).

The idempotent recompute is correct and should stay. What is missing is a per-import figure.

## The decision this needs

Both readings are defensible, which is why this is `needs-triage` rather than a fix:

- **Per-import** matches the heading and what the person just did: *"of the 3 rows I just added,
  1 was categorized"*. Costs the engine a way to report the categorization of a named statement.
- **Account-wide** answers a more useful question — *"how much of this account is still
  uncategorized?"* — but then the heading is wrong and it belongs in its own section, captioned
  as a state of the account rather than an outcome of the import.

Whichever is chosen, **the four figures must share one scope or be visibly separated.** A first
import into a new account cannot tell the two apart, which is why this shipped.
