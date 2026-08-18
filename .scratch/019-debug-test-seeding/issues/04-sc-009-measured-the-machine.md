# 04 — SC-009's five seconds measured the machine, not the seed

**Status:** resolved (the criterion is unchanged; how it is measured is)

**Found:** 2026-08-18, when `make a11y-sweep` failed on a test that had passed twice in
`make ios-test` the same afternoon, against the same build.

---

## The number that moved

| Run | Launch → first row |
|---|---|
| `make ios-test`, 019 PR B | **4.63 s** |
| `make ios-test`, 019 PR C | **4.65 s** |
| `make a11y-sweep`, eleven minutes into a loaded run | **7.98 s** ⛔ |

Same code, same six rows, a 70% spread and a red gate. SC-009 asks for five seconds and the
assertion was a bare wall clock, so what it actually measured was how busy the machine was.

This repository has already learned this once, in the other language:
`core/tests/history_perf.rs::s5` is a wall-clock bound, is flaky under CPU contention, and the
handoff warns not to chase an `s5` failure before re-running it on a quiet machine. This was the
same mistake one language over.

## Why shrinking the scenario would not have helped

Research R15 names the remedy in advance — *if a synchronous seed in `init()` is slow enough to be
felt, shrink `deep`, do not move the seed off the launch path* — and that remedy is still right for
the case it was written for. But it does not apply here: `small` is **six rows**, and six rows do
not take four seconds to write. Almost all of the figure was app launch and a navigation push,
neither of which this slice added.

## ⚠️ And then it failed again on CI, by six ten-thousandths of a second

The differential was the right idea with the wrong endpoints. It timed the unseeded launch to a
**ready front door** and the seeded launch all the way to a **row on the list** — so the
"difference" carried a navigation push and an XCUITest element query as well as the seed. On CI's
slower runner:

```
seed-timing: unseeded launch 4.46s, seeded launch to first row 7.46s, seed + navigation 3.00s
XCTAssertLessThan failed: ("3.0005640983581543") is not less than ("3.0")
```

**Failing by 0.0006 s is not a measurement, it is a coin toss** — and the number it was policing
was mostly navigation. Measured locally afterwards: the navigation alone is ~3.3 s of it.

The lesson generalises past this test: *a differential is only honest if both sides end at the
same place.* Comparing "launch" against "launch, then go somewhere else" measures the somewhere
else.

## What it measures now

Both launches are timed to **the same screen** — the front door, ready — so the difference is the
seed and nothing else: one of them had to write a history on the way.

```
seed-timing: unseeded launch 4.32s, seeded launch 5.28s (the seed itself 0.96s),
             and on to the first row 8.57s
```

**0.96 s** for writing a six-row history through `Store.importStatement` and opening SQLCipher for
the first time in the process. The bound is 3.0 s — three times the measurement, which is the
headroom a number taken on somebody else's machine needs.

The whole journey to a row is still printed and still asserted, generously (20 s), because a
collapse should fail something. It is a smoke alarm, not a stopwatch.

## ⚠️ Third observation: on CI the noise is bigger than the signal

The corrected version passes on CI, and prints this:

```
seed-timing: unseeded launch 6.37s, seeded launch 5.84s (the seed itself -0.53s)
```

**Negative.** The seeded launch was *faster* than the unseeded one — which cannot be true, and is
not a defect: launch-to-launch variance on a loaded runner (±1 s) is larger than the thing being
measured (~1 s). The first launch of a pair also pays for costs the second does not: app install,
first-run warm-up, the automation session coming up.

So the assertion is doing what it should — it would still catch a seed that started costing five
seconds — but **the printed number is not a measurement on a loaded machine**, and nobody should
quote it from a CI log. The local figure (0.96 s, on a quiet Mac) is the one to compare against.

**The remedy, for whoever next touches this**: launch once and *discard* it before timing the
baseline, so both measured launches are warm. It was not done here because the assertion already
holds and the fix costs a full CI cycle to verify — but the negative reading is the tell, and it
is written down rather than left for somebody to rediscover as a puzzle.

## What a later scenario author should watch

`seed-timing:` in the log, and specifically **the seed itself**. If seeding starts costing seconds
rather than a second, R15's remedy applies and the scenario shrinks — because the alternative, an
asynchronous seed, is a race with the first screenshot and FR-002 forbids it.
