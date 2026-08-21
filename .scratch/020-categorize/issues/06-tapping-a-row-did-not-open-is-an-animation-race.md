# 06 — "tapping a row did not open the transaction" is an animation race, not a broken row

**Status:** resolved (2026-08-21) — `XCUIElement.tapWhenSettled()` in
`ios/UITests/SettledTap.swift`, used at every tap that follows an animation

**Found:** 2026-08-21, on `main` (run `32452725396`, shard 4). It passed locally, passed in the
previous three CI runs, and passed on re-run of the identical commit.

---

## What happened

```
ios/UITests/CategorizeSecondActionUITests.swift:97: error:
  -[KanameUITests.CategorizeSecondActionUITests testDecliningTheSecondActionLeavesTheCorrectionAlone]
  : XCTAssertTrue failed - tapping a row did not open the transaction
```

## The repo already knows what this is

`CategorizeWorklistUITests.answerEveryRowOfTheWorklist` carries the diagnosis in a comment,
written when the same thing bit PR F:

> ⚠️ And it **waits for the list to be the length it should be** before reaching for the next row.
> The correction, the offer's dismissal and the list's re-read are three animations deep; a row
> tapped while the one above it is still leaving is a tap that lands on nothing and reports
> "tapping a row did not open the transaction" — **a sentence that reads exactly like a broken row
> and is not.**

So the message is a known false alarm, the mechanism is understood, and **the fix already exists
in one suite and was never applied to the others.**

## Why it surfaced now

Nothing about the shard split touches this test. What changed is *which machine* it ran on: a
GitHub-hosted `macos-26-arm64` runner is 3 cores, and the run in question was one of five macOS
jobs the same workflow had just dispatched. The animations take longer; the tap lands earlier
relative to them.

## The fix

`CategorizeWorklistUITests` waits for the list to reach its expected length before reaching for a
row. `CategorizeSecondActionUITests`, `CategorizeDetailUITests` and `CategorizeMemoryUITests`
reach for rows directly after an action that animates. Lift the wait into `SeededLaunch` — beside
`dismissMemoryOffer`, which exists for exactly this class of problem — and use it everywhere a row
is tapped after something moved.

⚠️ **Do not** fix it with a sleep. The existing helper waits on *the list being the length it
should be*, which is a statement about the app's state; a sleep is a statement about the machine,
and this ticket exists because statements about the machine do not survive a different machine.

## The wider point — this is the third

`SeedContractUITests` holds two (`issues/04`, a crash report with two spellings; `issues/05`, a
20-second wall clock that fails by 1%) and this is the third. **All three are timing or
machine-speed assumptions, and all three read like product defects when they fire.**

Sharding made them cheaper to retry — a 17-minute shard instead of a 40-minute job — but it did
not make them rarer, and it slightly raised the chance that *some* shard lands on a slow runner.
The three together are now the dominant cost of a red CI run, and they are worth a session.
