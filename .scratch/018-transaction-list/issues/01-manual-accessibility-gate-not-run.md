# 01 — The manual accessibility gate has never been run, and the timed ones were eyeballed

**Status:** ready-for-human

**Deferred:** 2026-08-15, by the holder, explicitly and knowingly — *"lets skip this but add it
to a future ticket much later"* — after G9–G14 were exercised.
**Belongs to:** `018-transaction-list` — T139, § *The manual, release-blocking gate* in
`specs/018-transaction-list/quickstart.md`. What it says about seeding applies to every P3 screen
after it.
**Severity:** ⚠️ **SC-012 is not satisfied**, and 018 cannot honestly be called released until
it is. It does not block further development.

## What was run, and what was not

| Gate | State |
|---|---|
| **G13, G14** — import while scrolled and filtered; cancelled import | ✅ **Pass**, on device. The only evidence US8 works outside unit doubles. |
| **G10** — scroll the full corpus | ✅ No stalls, no persistent blank rows |
| **G9** — first screenful < 1 s | ⚠️ *"Felt instant."* Observed, **not measured** |
| **G11** — the 200-row comparison | ⚠️ Same, and the delete-and-reinstall it needs was not done |
| **G12** — filter apply/clear < 300 ms | ⚠️ Observed, **not measured** |
| **G1–G8** — the whole accessibility half | ⛔ **Never run** |

## Why "it felt instant" is not enough to close SC-012

It is a real signal — a screen that took two seconds would not feel instant — and it is recorded
as one. But 900 ms also feels instant, and **the reason the bound was written down was to stop a
later regression hiding behind a judgement**. A number is a thing the next person can compare
against; an impression is not.

G12's 300 ms is past what an unaided eye can time at all: it is eighteen frames.

## What closing it takes

**Roughly half an hour, and no code.** `quickstart.md` § *How to run G9–G14* has the runbook.

1. `make perf-corpus DIR=~/kaname-corpus` → eight statements, self-verifying.
2. `TUIST_DEVELOPMENT_TEAM=… make ios-gen`, then a **Release** build installed on a device,
   **launched from the home screen** — a session under Xcode's debugger pays a frame-budget tax
   that G9's one-second bound cannot afford.
3. **G9 / G12**: iOS Screen Recording, then step the video frame by frame in QuickTime. At 60 fps,
   one second is 60 frames and 300 ms is 18.
4. **G11**: delete the app — which deletes the encrypted store with it — reinstall, and import
   `200-rows/01-icici-1002.pdf` alone.
5. **G1–G8**: VoiceOver, largest Dynamic Type, Reduce Transparency, Increase Contrast + Dark
   Mode. Nothing here can be automated; `performAccessibilityAudit` covers the front door only,
   and it cannot set Reduce Transparency or Increase Contrast at all
   (`make a11y-sweep` sets the latter with `simctl`, for the simulator).
6. Fill § *Record here*, which is what actually satisfies SC-012.

⚠️ **A free Personal Team build expires after seven days.** The one installed on 2026-08-15 is
dead after **2026-08-22**; re-install before running.

## Why this will keep happening until the seeding slice lands

**No automated run can reach a populated transaction list at all.** The list is behind an import,
an import is behind the system document picker, and FR-077 forbids the DEBUG seeding hook that
would close it (T118, and `ios/UITests/…/testAFreshInstallOffersNoRouteToAnEmptyTransactionList`
asserts precisely that reachability fact). So every screen that shows a person's own data is
manual-gate-only, and each one adds another half hour of somebody's afternoon.

The DEBUG-only test-seeding slice — already scheduled before the categorize slice in
`docs/kaname-ios-plan.md` — is what changes that, and it is worth doing before the next P3
screen rather than after.

## One thing already fixed while this sat open

The Dark Mode contrast defect the holder found by eye during the same session (issue 02) would
have been G7's job. It was fixed and is now covered by `ios/Tests/ThemeContrastTests.swift`,
which computes the ratios from the tokens — so that particular G7 question is answered by a test
rather than by the gate.
