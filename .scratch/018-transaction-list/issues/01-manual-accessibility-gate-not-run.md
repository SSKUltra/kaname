# 01 — The manual accessibility gate has never been run, and the timed ones were eyeballed

**Status:** ready-for-human

**Deferred:** 2026-08-15, by the holder, explicitly and knowingly — *"lets skip this but add it
to a future ticket much later"* — after G9–G14 were exercised.
**Partly closed:** 2026-08-15, later the same day, on the simulator. **G1–G8 and G10 have now
been run.** What remains is G9, G11 and G12 only — the three *timing* bounds, which a simulator
cannot evidence.
**Belongs to:** `018-transaction-list` — T139, § *The manual, release-blocking gate* in
`specs/018-transaction-list/quickstart.md`. What it says about seeding applies to every P3 screen
after it.
**Severity:** ⚠️ **SC-012 is still not satisfied**, but for a different reason than when this was
filed: the accessibility half is no longer unrun, it is **run and partly failing**. See
`issues/02` and `issues/03`, which are the actual blockers now. This ticket is reduced to the
three unmeasured timing bounds.

## What was run, and what was not

| Gate | State |
|---|---|
| **G13, G14** — import while scrolled and filtered; cancelled import | ✅ **Pass**, on device. The only evidence US8 works outside unit doubles. |
| **G10** — scroll the full corpus | ✅ No stalls, no persistent blank rows. Re-confirmed on the simulator over ~3,000 rows. |
| **G1** — amounts never truncated | ✅ **Pass** at `accessibility-XXXL`, 4+ screenfuls, both directions |
| **G2** — no row clipped by the bottom bar | ⛔ **FAILS** → `issues/03` |
| **G3** — VoiceOver reads a row as one sentence | ✅ **Pass**, verified through Accessibility Inspector |
| **G4** — heading carries the year when it is not the current one | ✅ **Pass**, both halves |
| **G5** — the filter is announced and clearable | ⛔ **FAILS visually** → `issues/02`. Announcement half passes. |
| **G6** — Reduce Transparency | ✅ **Pass** — chrome goes solid, no text on text |
| **G7** — Increase Contrast + Dark Mode | ✅ **Pass** — direction is a sign, never colour |
| **G8** — the date in view stays identifiable | ✅ **Pass** — the heading pins and updates |
| **G9** — first screenful < 1 s | ⚠️ *"Felt instant."* Observed, **not measured**. Device-only. |
| **G11** — the 200-row comparison | ⚠️ Same, and the delete-and-reinstall it needs was not done. Device-only. |
| **G12** — filter apply/clear < 300 ms | ⚠️ Observed, **not measured**. Device-only. |

## Why "it felt instant" is not enough to close SC-012

It is a real signal — a screen that took two seconds would not feel instant — and it is recorded
as one. But 900 ms also feels instant, and **the reason the bound was written down was to stop a
later regression hiding behind a judgement**. A number is a thing the next person can compare
against; an impression is not.

G12's 300 ms is past what an unaided eye can time at all: it is eighteen frames.

## What closing it takes

**Roughly twenty minutes on a device, and no code.** Only the three timing gates remain;
`quickstart.md` § *How to run G9–G14* has the runbook.

1. `make perf-corpus DIR=~/kaname-corpus` → eight statements, self-verifying.
2. `TUIST_DEVELOPMENT_TEAM=… make ios-gen`, then a **Release** build installed on a device,
   **launched from the home screen** — a session under Xcode's debugger pays a frame-budget tax
   that G9's one-second bound cannot afford.
3. **G9 / G12**: iOS Screen Recording, then step the video frame by frame in QuickTime. At 60 fps,
   one second is 60 frames and 300 ms is 18.
4. **G11**: delete the app — which deletes the encrypted store with it — reinstall, and import
   `200-rows/01-icici-1002.pdf` alone.
5. Fill § *Record here*, which is what actually satisfies SC-012.

⚠️ **A free Personal Team build expires after seven days.** The one installed on 2026-08-15 is
dead after **2026-08-22**; re-install before running.

## What the accessibility half cost, and what it found

It took about forty minutes on the simulator and found **four** defects that no automated gate in
this repo would have caught: `issues/02` (G5), `issues/03` (G2), `issues/04` (a row truncates away
the last-4, so two cards of one product are indistinguishable on screen while VoiceOver tells them
apart) and `issues/05` (a one-off main-thread render hang, sampled).

**Two things made it cheap, and are worth reusing:**

- **`xcrun simctl ui booted` drives three of the five axes.** `appearance`, `increase_contrast`
  and `content_size` can all be set from a script, so Dark Mode, Increase Contrast and every
  Dynamic Type size stop depending on anyone remembering to set them. **Reduce Transparency still
  cannot be set this way** — no `simctl` control, no test API — and needs Settings by hand.
- **Accessibility Inspector answers G3 and G5 better than VoiceOver does.** It reads an element's
  label straight off the simulator, reaches every screen behind an import, and gives a string you
  can paste into a ticket instead of a memory of what was spoken.

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
