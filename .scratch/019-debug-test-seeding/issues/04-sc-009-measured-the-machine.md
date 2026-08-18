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

## What it measures now

The seeded launch is compared with an **unseeded** launch taken moments earlier on the same
simulator, and the assertion is on the difference — which is what SC-009 is about, and the number
that would grow if a scenario grew:

```
seed-timing: unseeded launch 3.30s, seeded launch to first row 4.72s, seed + navigation 1.42s
```

**1.42 s** for writing a six-row history through `Store.importStatement`, opening SQLCipher for
the first time in the process, and pushing one navigation destination — measured under
`make a11y-sweep`, i.e. on the *loaded* machine that produced the 7.98 s figure.

The absolute figure is still printed and still asserted, generously (15 s), because a collapse
should fail something. It is a smoke alarm, not a stopwatch.

## What a later scenario author should watch

`seed-timing:` in the log, and specifically its third number. If seeding starts costing seconds
rather than a second, R15's remedy applies and the scenario shrinks — because the alternative, an
asynchronous seed, is a race with the first screenshot and FR-002 forbids it.
