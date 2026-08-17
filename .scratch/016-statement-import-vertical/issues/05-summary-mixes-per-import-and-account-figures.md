# 05 — The import summary mixes per-import figures with account-wide ones

**Status:** resolved

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

---

## Resolution — 2026-08-17, by the holder's decision: **separate them, visibly**

Of the three readings this ticket set out, the holder chose the one that keeps both facts and
costs the engine nothing: **two sections, each captioned with the set it counts.**

```
Imported                     ← this statement
  Transactions          6
  Duplicates skipped    6

This account                 ← the whole account
  Categorized           0
  Left uncategorized    6
  Counted across every transaction in this account,
  not only the statement you just imported.
```

Evidence: `../evidence/issue-05-resolved-two-sections-with-captioned-scope.png`, taken on a
**re-import** — the case that makes the two scopes differ, and the one a first import into a new
account cannot show.

**The grouping is data, not layout.** `ImportSummary.importedFigures` and `.accountFigures`
decide which figure counts what; the view only renders them. Where a `Section` happens to put a
row is not something a unit test can see — which is exactly why this shipped and why no test
caught it for the whole of 016 — but which list a figure is in is. The caption and both headings
also joined `ImportMessageAuditTests.everySentence`, so they are held to the same honesty rules
as every other sentence in the flow.

**Proof** — `ios/Tests/ImportSummaryScopeTests.swift`, five tests, three breaks watched going red:

| Break | Went red |
|---|---|
| the account figures back under `Imported` (the shipped mix) | *The account's own position is never counted as an outcome of the import* |
| a figure silently dropped in the split | *Every figure the summary can show belongs to exactly one scope* + the count test |
| the second section reusing the first heading | *The account's figures are captioned with the set they count* |

The middle one matters most: the obvious way to "fix" a mixed section is to delete the awkward
rows, and that would have passed a test that only checked the first section's contents.

⚠️ **This fix exposed a second defect, filed as `issues/07`.** With the account-wide figures gone,
the `Imported` section reads `Transactions 6` beside `Duplicates skipped 6` for a **six-row**
statement whose re-import added **nothing**. `transactions_inserted` is
`request.transactions.len()` — rows *read from the document*, not rows the account gained. It was
always wrong; four mixed numbers were simply hiding it.
