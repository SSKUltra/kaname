# 03 — An `XCTSkip` in an audit helper could have skipped two accessibility audits, silently

**Status:** resolved (PR G, T168) — the skip is now an `XCTUnwrap`, and the sweep that follows
reports **0 skipped**

**Found:** 2026-08-20, by **T168** — "assert this slice added no `XCTSkip`… A test that cannot
pass is a finding, not a nuisance." It was found by taking that sentence literally and grepping,
which is the only reason it was found at all. PR G, `020-categorize`.

---

## What it was

`SeededAccessibilityUITests.openMemoryOffer` — the helper that launches `crossing`, corrects a
row and waits for the memory offer — opened with:

```swift
guard let subject = SeedScenario.crossing.expectedMemorySubjectRow else {
    throw XCTSkip("the crossing scenario declares no memory")
}
```

It is reached by **five** tests, four of which are the accessibility audits over the memory offer
and the second action (Light and Dark, default and `AccessibilityXXXL`).

## Why it matters more than a style nit

`expectedMemorySubjectRow` returns `nil` when the subject row does not survive **de-duplication**
— and `crossing` is deliberately built on the one pair cross-source dedup compares, a ledger
against a card. The quickstart's gotcha 6 says so in as many words: *"`crossing` must dodge dedup
… or one gets eaten and the blast radius is wrong before anyone tests it."*

So the `nil` branch is not hypothetical — it is the documented failure mode of this exact
scenario. And on that branch the audits would have reported **skipped**, which in a CI summary is
indistinguishable from a surface that was audited and found clean. **SC-016's "zero findings"
would have been vacuously true for two of the four new surfaces.**

⚠️ It was also **inconsistent with its own siblings**: the identical guard in
`CategorizeSecondActionUITests` (twice) and in `auditCategorizeSurfaces` uses `XCTFail`. One
guard, three call sites, two different verdicts.

## The fix

```swift
let subject = try XCTUnwrap(
    SeedScenario.crossing.expectedMemorySubjectRow,
    "the crossing scenario declares no live memory subject, so neither memory surface was audited")
```

`XCTUnwrap` records a failure **and** throws, which is exactly the semantics wanted: the audit
goes red rather than quietly not happening, and the helper still stops before touching a screen
that is not in the state it assumes.

## The evidence, and one claim withdrawn

`make a11y-sweep` after the change: **`TEST SUCCEEDED`, 57 UI tests, 0 failures,
`skippedTests: 0`**. `make ios-test` after the change: **410 passed, 0 failed**, and the whole
UI bundle green. All five tests that reach the helper now run and pass.

⚠️ **What this does *not* prove, and was briefly claimed before being checked.** PR F's gate
reported "**2 skipped**", and the obvious inference — that those two were this `XCTSkip` firing —
is **wrong**. The two skips are in the **unit** target, both pre-date 020, and both are correct:

| Skipped test | Guard | Why it is right |
|---|---|---|
| `KeyStoreTests/databaseFileIsProtected()` | `.enabled(if: ProcessInfo…["SIMULATOR_UDID"] == nil)` | the data-protection class is only meaningful on a real device (`ed60204`) |
| `ReferenceSetVerification/readsTheReferenceSet()` | `.enabled(if: directory != nil)` | the reference set is local and opt-in — `make reference-check` (`776d2aa`) |

So this `XCTSkip` was **latent**: a silent-skip branch on a documented failure mode, never
observed firing. That makes it a smaller finding than it first looked and **not a smaller fix** —
the branch guards four accessibility audits, and its condition is the one thing `crossing` is
documented as being able to lose.

⚠️ **And the arithmetic is its own lesson: a skip count is not self-explanatory.** Two numbers
that both read "2 skipped" had nothing to do with each other, and the only way to tell was
`xcrun xcresulttool get test-results tests` and the names.

## The lesson worth carrying

**A skip is a green run.** This repository already knows that a suite which never ran reports
success (019's `make ios-gen` trap); this is the same failure one layer in — a *test* that never
ran, inside a suite that did. When a precondition is genuinely impossible, fail; when the test is
deliberately conditional, say so declaratively with `.enabled(if:)`, the way the two legitimate
skips above do, so the condition is on the test rather than buried in a shared helper.
`XCTSkip` in a helper says neither, and hides the condition from every caller.
