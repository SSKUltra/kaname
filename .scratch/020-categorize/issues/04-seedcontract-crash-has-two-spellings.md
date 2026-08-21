# 04 — `testAnUnrecognisedScenarioNameNeverReachesTheForeground` is flaky on CI: the crash has two spellings

**Status:** resolved (2026-08-21) — the matcher now absorbs both spellings, and the verdict it
must *not* absorb was watched still firing

**Found:** 2026-08-20, by PR #43's CI run. It cost **37m42s** of CI, a re-run of **39m49s**, and
would have cost the next person the same. `020-categorize` PR G, but the test is **019's** and
the defect predates this slice entirely.

---

## What happened

The iOS CI job failed with one test red:

```
ios/UITests/SeedContractUITests.swift:80: error:
  -[KanameUITests.SeedContractUITests testAnUnrecognisedScenarioNameNeverReachesTheForeground]
  : Failed to get background assertion for target app with pid 37573: No failure details provided
```

Re-run on the identical commit: **passed** (81.3 s, against 11.8 s in the failing run — the
runner was much slower the second time, which is the opposite of what one would guess).

## Why it fails, precisely

The test proves that an unrecognised `KANAME_SEED_SCENARIO` **fails the launch** rather than
falling back to an empty app — because an accessibility audit reporting success against a blank
screen is the worst thing 019 could have shipped (FR-006, SC-016).

The app therefore *crashes on purpose*, and XCUITest reports that crash as a test failure of its
own. The test absorbs exactly that one report and nothing else:

```swift
options.issueMatcher = { $0.compactDescription.contains("crashed") }
```

⚠️ **The narrowness is deliberate and must be preserved** — the comment above it says so: a
broader expectation would swallow `XCTAssertNotEqual(app.state, .runningForeground)`, which is
the verdict the test exists to reach.

**But the same event has (at least) two spellings**, and the matcher only knows one:

| Run | What XCUITest reported | Absorbed? |
|---|---|---|
| 019, run `32135326095` | `in.beaconbrain.kaname crashed in <external symbol>` | ✅ yes |
| 020 PR G, run `32388813072` | `Failed to get background assertion for target app with pid 37573` | ❌ **no** → red |

Both are the same fact — the target app is gone — surfaced through different subsystems
depending on how far the launch got before the runner noticed. The second spelling appears when
the app dies early enough that the automation session never gets a background assertion for it.

## The fix

Widen the matcher to the *event*, not to one of its phrasings, and say why in the comment:

```swift
// Both spellings are the same fact — the target app is gone — and which one arrives depends on
// how far the launch got before the runner noticed. Matching only "crashed" made this test flaky
// on CI (issues/04). It is still narrow: it absorbs XCUITest's report *about the app being gone*
// and nothing else, so the state assertion below is still a real assertion.
options.issueMatcher = {
    let text = $0.compactDescription
    return text.contains("crashed") || text.contains("Failed to get background assertion")
}
```

⚠️ **Do not** be tempted by `options.isStrict = false` plus a matcher-less expectation, or by
wrapping the whole test — that is exactly the "swallow the verdict" shape the current comment
warns against, and it would make the test pass whether or not the launch failed.

## Verifying it

The failure cannot be reproduced on demand — it is timing-dependent on the runner. What *can* be
checked cheaply is that the widened matcher still absorbs the ordinary spelling and still leaves
the real assertion live: temporarily make the seed accept `does-not-exist` (return `.empty`
instead of failing) and watch the test go red on `XCTAssertNotEqual(app.state, .runningForeground)`
rather than passing quietly. That is the break worth watching here.

## Why it was not fixed in PR #43

CI went green on the re-run and the PR was merged on that. Editing a test after a green 40-minute
gate buys another 40-minute gate, and the change deserves its own watch-it-fail (above) rather
than being tacked onto a documentation PR. **The 37 minutes are already spent; the next person
should not spend them again**, which is what this file is for.
