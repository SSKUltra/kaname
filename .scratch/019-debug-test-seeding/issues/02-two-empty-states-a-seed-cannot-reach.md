# 02 — Two empty states a seed cannot reach, and why that is the engine being right

**Status:** ready-for-human (a verdict, not a defect — it needs a decision about coverage, not a fix)

**Found:** 2026-08-18, answering **T058** (`specs/019-debug-test-seeding/tasks.md`), which asked
whether `EmptyKind.nothingToShowAnywhere` is reachable by a seed at all. It is not — and while
establishing that, a **second** case turned out to be unreachable for the same reason.

---

## The rule that makes them unreachable

`EmptyKind.decide` (`ios/Sources/Transactions/TransactionListModels.swift`) is consulted only
when the rendered page is **empty**. Two of its six cases require a store to hold rows and show
none of them:

| Case | Requires |
|---|---|
| `nothingToShowAnywhere` | zero live rows **store-wide**, and ≥ 1 account with `hasOnlyExcludedRows` |
| `accountNothingToShow(name:)` | the filtered account has `hasOnlyExcludedRows`, and **no other account has live rows** |

And here is the engine fact that closes both: **every supersession leaves a live winner.** The
import path has exactly two routes to an excluded row —

1. **Re-import.** `link_reimported_rows_in` (`store.rs`) supersedes the **incoming** row and
   keeps the one the account already had. The winner is live, in that same account.
2. **Cross-source de-duplication.** `find_duplicates_in` walks accounts in `rowid` order and
   supersedes the **later** account's row. The winner is live, in an earlier account.

`is_deleted` has no write path in `store.rs`'s API at all (research R8, FR-008a), so there is no
third route. Therefore:

- A store with any transaction in it has **at least one live row**, so "zero live rows
  store-wide with an account holding excluded rows" is a contradiction. `nothingToShowAnywhere`
  is unreachable. ⛔
- An account can only hold nothing but excluded rows if **another account holds the winners**,
  so "no other account has live rows" is false whenever the precondition is true.
  `accountNothingToShow` is unreachable. ⛔

Both are unreachable **by construction**, exactly as `nothingImported` is (FR-039a, research R9)
— and for a better reason: they describe stores the engine's own de-duplication cannot produce.

## What was attempted before concluding it

`deep` gained a fifth statement — `SYNTHETIC CARD FIVE`, a card whose every row the ledger
already had. It is the only shape the import path can produce that reaches
`hasOnlyExcludedRows`, and it does: the account reports **0** live rows and holds three. Filtered
to, it renders **`accountEmptyOthersHaveRows(statementWasEmpty: false)`** — "There's nothing to
show for SYNTHETIC CARD FIVE. Other accounts have transactions." — because the ledger holding the
winners is precisely what makes the refinement true.

That is asserted on a rendered screen by
`SeededEmptyStateUITests.testAnAccountWhoseEveryRowWasSupersededSaysThereIsNothingToShow`, so the
*state* has coverage; it is the *case name* T056 predicted that turned out to be the wrong one.

⚠️ **No write path was acquired to make either case reachable.** FR-008a forbids the seed holding
a power the import pipeline lacks, and a seeded store no person could have is a screen no person
could see — which would make an audit of it meaningless.

## Where the coverage stands

Six `EmptyKind` cases, honestly counted:

| Case | Reached on a rendered screen? |
|---|---|
| `noTransactionsAnywhere` | ✅ `barren` — two statements, no transactions in either |
| `accountStatementEmpty(name:)` | ✅ `barren`, filtered to one of its two accounts |
| `accountEmptyOthersHaveRows(statementWasEmpty: true)` | ✅ `deep`'s zero-row card, filtered to |
| `accountEmptyOthersHaveRows(statementWasEmpty: false)` | ✅ `deep`'s echo card, filtered to |
| `nothingToShowAnywhere` | ⛔ unreachable — this ticket |
| `accountNothingToShow(name:)` | ⛔ unreachable — this ticket |

**Four of six audited against a rendered screen; two unreachable by any seed.** SC-007 is met
unevenly, by design, and this is the record saying so rather than a "100%" that would not be
true. The two unreachable cases keep their unit coverage in
`ios/Tests/TransactionEmptyStateTests.swift`, which reaches them through `EmptyKind.decide` with
constructed summaries — real coverage of the decision, lesser coverage of the screen.

**Recommended remedy**, unchanged from FR-039a's: host-render them in `KanameTests` with the
existing double (PR D, T080). That gives each branch its first execution against a rendered view,
though not a `performAccessibilityAudit`, which is an `XCUIApplication` API.

## What is *not* being claimed

That the branches are dead. A later slice that adds a delete path, or an alert-source import that
supersedes without a winner, makes both reachable immediately — which is why neither branch should
be removed, and why this is a ticket rather than a deletion.
