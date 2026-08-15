# 01 — The manual accessibility gate has never been run, and the timed ones were eyeballed

**Status:** resolved

**Deferred:** 2026-08-15, by the holder, explicitly and knowingly — *"lets skip this but add it
to a future ticket much later"* — after G9–G14 were exercised.
**Resolved:** 2026-08-15, later the same day, on the simulator. **G1–G8 and G10 were run.** The
accessibility half — this ticket's subject — is closed. The three *timing* bounds it also
carried (G9, G11, G12) were **split out into `issues/06`**, because a simulator cannot evidence
them: they need a phone, not an audit.
**Belongs to:** `018-transaction-list` — T139, § *The manual, release-blocking gate* in
`specs/018-transaction-list/quickstart.md`. What it says about seeding applies to every P3 screen
after it.
**Severity:** ⚠️ **SC-012 is still not satisfied**, but nothing about it is *unrun* any more.
What blocks it is now concrete and separately tracked: two failing gates (`issues/02`,
`issues/03`) and three unmeasured timings (`issues/06`).

## Outcome

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
| **G9, G11, G12** — the timing bounds | ➡️ **Moved to `issues/06`.** Device-only; a simulator's frame timings are not evidence for them, so they were deliberately not attempted here. |

## What still stands between this and SC-012

Nothing here is unrun; three things are unfixed or unmeasured, and each has its own ticket:

| | |
|---|---|
| `issues/02` | ⛔ G5 — the active filter is unreadable at accessibility sizes |
| `issues/03` | ⛔ G2 — the filter bar clips a row's amount mid-glyph |
| `issues/06` | ⚠️ G9, G11, G12 — the three device timing bounds, never measured |

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
