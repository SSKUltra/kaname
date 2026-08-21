# 05 — `testSeedingDoesNotMakeTheLaunchSlow`'s 20-second backstop is a wall clock, and it fails on a slow runner

**Status:** resolved (2026-08-21) — **option 2**, the machine-relative ratio, with `K` chosen
from four measured points. ⚠️ **A second finding came out of the measurement and is NOT fixed —
see *The delta is confounded* below.**

**Found:** 2026-08-20, by PR #44's CI run — the first run of the sharded workflow. Shard 2 went
red; nothing about the shard split touched this test. It cost a 23-minute job and a re-run.

---

## What happened

```
ios/UITests/SeedContractUITests.swift:139: error:
  -[KanameUITests.SeedContractUITests testSeedingDoesNotMakeTheLaunchSlow]
  : XCTAssertLessThan failed: ("20.206465005874634") is not less than ("20.0")
  - a seeded launch took 20.206465005874634s to show a row
```

**It failed by 1%** — 206 milliseconds over a 20-second bound.

## Why this is the same finding as `019/issues/04`, one bound out

The test's own comment block is unusually clear-eyed about this, and is worth quoting because it
predicted the failure mode exactly:

> The second version compared it against an unseeded launch — right idea, wrong endpoints. […] on
> CI's slower runner it came to `3.0005640983581543` against a 3.0 bound. **Failing by six
> ten-thousandths of a second is not a measurement, it is a coin toss.**

That lesson produced the *good* assertion — the seed's own cost, measured as the difference
between two launches to the **same** screen, which cancels the machine out. But a second,
"generous" assertion survived beside it: the whole journey to a row, under a flat 20 seconds,
"there to catch a collapse, not to police a millisecond".

**A generous absolute bound is still an absolute bound**, and 20 s is not generous on a
GitHub-hosted `macos-26-arm64` runner (3 cores, 7 GB) that is booting a simulator, installing an
app, seeding a store through the real import path and rendering a list. The repo already knows
this in general — `AGENTS.md` and `history_perf::s5` say a wall clock measures the machine — and
this is the third time it has been paid for.

## What it is protecting, and why that matters to the fix

The **delta** assertion is the real gate: it is what notices a scenario growing until seeding is
slow. It cancels the runner out and cannot flake on machine speed.

The **20 s** assertion catches "a collapse" — the seeded journey becoming pathological in a way
the delta would not show (e.g. both launches slowing equally). That is a real thing to want, and
deleting it outright loses something.

## Options, in the order they should be considered

1. **Raise the bound to something a slow runner cannot reach** (60 s?) and say in the comment
   that the number is a collapse detector, not a performance budget. Keeps the intent, ends the
   flakiness. ⚠️ The current 20 s reads like a budget precisely because it is close to the
   observed value.
2. **Scale the bound off the *unseeded* launch already measured in the same test** — e.g. the
   seeded journey may not exceed `N ×` the unseeded launch. This is the same trick the delta
   assertion uses, applied to the backstop, and it cannot flake on machine speed at all.
   **Probably the right answer**, and it needs no new measurement.
3. **Delete it** and rely on the delta. Simplest; loses the collapse case.
4. **Move it out of CI** into the manual/perf gate, the way `018/06`'s timings live.

⚠️ **Do not** "fix" it by re-running until green. That is what has happened twice now, and it is
why this file exists.

## Related

- `.scratch/020-categorize/issues/04` — the *other* flake in this same bundle
  (`testAnUnrecognisedScenarioNameNeverReachesTheForeground`, a crash report with two spellings).
  Between them, `SeedContractUITests` holds both known CI flakes in the repository.
- `.scratch/019-debug-test-seeding/issues/04` — the original wall-clock lesson that produced this
  test's current shape.

---

## How it was resolved (2026-08-21)

**Option 2**, as ranked. The delta assertion is untouched; the flat `20.0` became
`baseline * 5`, and the message now names the ratio so a future failure is diagnosable.

**`K` was measured, not guessed** — four points, deliberately from both ends of the range:

| Where | unseeded | to first row | **ratio** |
|---|---:|---:|---:|
| CI runner (the failure) | 6.93s | 20.21s | **2.92** |
| Developer machine | 5.02s | 6.10s | 1.22 |
| Developer machine | 3.24s | 5.79s | 1.79 |
| Developer machine | 4.11s | 6.00s | 1.46 |

`K = 5` clears the worst observed by 71%. ⚠️ **The spread matters in the direction you would not
guess**: the tap-to-row leg is dominated by XCUITest's own full-tree query, which is roughly
*constant* rather than proportional to machine speed — so on a fast machine the ratio rises. A `K`
picked only from the CI number could have flaked from the other end.

**Watched failing**: `K` lowered to 1.2 turned it red at a measured ratio of 1.458, with the
message naming the ratio.

🚨 **The real collapse detector was there all along** and is worth knowing: the
`waitForExistence(timeout: 30)` above this assertion fails on its own if a row never arrives. This
bound only covers the narrow band between *degrading* and *gone*, which is precisely why it can
afford to be generous.

## 🚨 The delta is confounded — a second finding, not fixed

Measuring for `K` turned up something the ticket did not go looking for. The **delta** assertion —
`toFrontDoor - baseline < 3.0`, the one this file called "the real gate" — measured **`-1.44s`** on
one local run and **`-0.59s`** on another. **The seeded launch was faster than the unseeded
baseline.**

The cause is ordering: the unseeded launch runs **first** and pays the cold-start costs (install,
first-launch warmup) that the second launch does not. So the baseline is systematically inflated,
and the delta is measuring warmup as much as seeding.

**What that means**: the delta would stay green through a real seeding regression of up to roughly
the size of the warmup it is absorbing. On CI, where the app is already warm by the second launch,
it read `0.45s` — plausible. Locally it goes negative, which is not a plausible measurement of
anything.

It is **left alone deliberately**: fixing it is a design decision (warm the app first? discard the
first launch? measure the seed in-process?), it is not what this ticket was opened for, and
changing an assertion's meaning while resolving a different one is how a gate quietly stops
meaning what its name says. **Filed here rather than fixed, with the numbers, so the next person
starts from evidence.**
