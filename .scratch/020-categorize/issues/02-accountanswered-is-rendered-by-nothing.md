# 02 — `EmptyKind.accountAnswered` is rendered by nothing, and no automated run reaches it

**Status:** ready-for-agent (small, well-understood, and the cost is a ~15-tap prologue, not a
design question)

**Found:** 2026-08-20, by **T183**'s hand-back walk — reading every FR-001–FR-078 and
SC-001–SC-036 for a discharging task id rather than trusting the traceability tables. PR G,
`020-categorize`.

---

## What is missing

`EmptyKind.accountAnswered(name:)` — *this account is finished, another one may not be* — is:

- **asserted as a value**: `TransactionWorklistEmptyStateTests:76` (`#expect(kind ==
  .accountAnswered(name: "Everyday Savings"))`) and `TransactionEmptyStateTests:175`;
- **asserted as a sentence**: `CategorizeStrings.finishedState(accountName:)` builds
  `"Nothing left to file in \(name)"` with `.clearFilter` as its way out;
- **rendered by nothing**, in any target, ever.

Its sibling `allAnswered` *is* reached — `CategorizeWorklistUITests
.testTheDoorShowsTheEnginesCountAndThenSaysTheWorkIsFinished` works a whole scenario to zero and
reads the finished sentence off a real screen.

## Why this is a gap and not a documented exclusion

**FR-070 does not cover it.** FR-070 is about states a seed **cannot** construct — the reason
`EmptyStateRenderingTests` exists for 018's three. This state is perfectly constructible: take a
scenario with two accounts, answer every row of one of them, and leave the filter on it.
`crossing` already has two accounts, two unanswered rows in each.

So this is a hole in:

- **SC-018** — "100% of the surfaces this slice adds are reachable by an automated run with zero
  human actions and zero files on the device", read strictly. Every *surface* is reachable; this
  *state* of one is not.
- **SC-035** — "100% of the reachable combinations of the account narrowing and the uncategorized
  narrowing have their own wording and their own coverage". It has its own wording. Its coverage
  is a unit assertion about an enum.

## What would close it

One UI test in `CategorizeWorklistUITests`, over `crossing`:

1. `SeededLaunch.launch(scenario: .crossing)`, open the worklist.
2. Filter to one account (`SeedScenario.menuLabel(for:)` names it the way the menu does).
3. Answer both of that account's rows — `SeededLaunch.chooseCategory` then
   `SeededLaunch.dismissMemoryOffer` each time. ⚠️ Wait for the list to be the length it should
   be between answers; `answerEveryRowOfTheWorklist`'s comment explains why a tap on a row that
   is still animating out reports "tapping a row did not open the transaction".
4. Assert the empty state reads `CategorizeStrings.accountFiledTitle(name)` and that
   **clearing the filter still finds work** — that last assertion is the whole difference
   between this state and `allAnswered`, and a test that omits it is testing the wording only.

⚠️ It needs `make ios-gen` only if it lands in a new file; inside `CategorizeWorklistUITests` it
does not.

## Why it was reported and not closed

T183's own instruction: *"Anything that is neither is a gap and is reported as one, not closed."*
PR G builds nothing. The cost is a fifteen-tap prologue to a two-line assertion, and whether that
is worth it belongs to whoever picks it up — not to the audit that found it.
