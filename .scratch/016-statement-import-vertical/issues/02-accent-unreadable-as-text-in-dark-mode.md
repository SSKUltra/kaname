# 02 — The accent is unreadable as text in Dark Mode (2.35:1)

**Status:** resolved

**Found:** 2026-08-15, on a real iPhone 17 Pro Max (iOS 26.6), during 018's manual gate — the
holder read the import summary sheet in Dark Mode and could barely see "Done" and
"Import another".
**Belongs to:** `016-statement-import-vertical` — `ios/Sources/Theme.swift` and
`ImportSummaryView` are both its code.
**Severity:** ⚠️ A **WCAG AA failure on shipped UI**, and it will fail 018's G7 when that is
run. It is not the same defect as issue 01, but it is the same family: colour chosen for one
role and used in another.

## What is wrong

`Color.kanameAccent` (`ios/Sources/Theme.swift`) is the app's single tint, applied globally by
`KanameApp.swift:10`. Measured against the backgrounds it is actually drawn on:

| Use | Ratio | AA (4.5:1 text) |
|---|---|---|
| Light mode, accent **as text** on white | 9.48:1 | ✅ |
| **Dark mode, accent as text on black** | **2.90:1** | ❌ |
| **Dark mode, accent as text on a sheet (`#1C1C1E`)** | **2.35:1** | ❌ |
| **Dark mode, accent as text on `#2C2C2E`** | **1.92:1** | ❌ |
| Either mode, **white text on** the accent (a filled button) | 7.25 / 9.48:1 | ✅ |

The last row is the one the palette was designed for, and `Theme.swift`'s own doc comment says
so: *"These two values clear 4.5:1 **against white**"*. That reasoning is sound for
`.glassProminent`, where the accent is a **fill** carrying white text. It was never true for the
accent as a **foreground**, which is what every plain and toolbar button does with it:

- `ImportSummaryView.swift:67` — "Done" (`.confirmationAction`)
- `ImportSummaryView.swift:70` — "Import another" (`.cancellationAction`)
- `ImportEmptyStateView.swift:31` — `.foregroundStyle(.tint)`
- every `.buttonStyle(.glass)` label in the transaction list's filter chrome

## Why the Dark Mode value makes it worse, not better

The two variants are `#134E4A` (light) and `#17615B` (dark) — the dark one is barely lighter.
For a **fill** that is right: the surface stays dark, white text stays legible. For a
**foreground** it is exactly backwards — in Dark Mode a foreground has to move *toward* the
light end to separate from a dark background, and this one does not. One colour is being asked
to serve two roles whose requirements point in opposite directions.

## The fix, and the decision inside it

Not "pick a lighter green": decide whether the accent is one token or two.

1. **Two tokens** (recommended) — `kanameAccentFill` (today's values, unchanged, for
   `.glassProminent`) and `kanameAccentText`, whose Dark Mode value is lightened until it clears
   4.5:1 on `#1C1C1E` and Increase Contrast. Costs one type and an audit rule that says which is
   which. It is also what the system does: `Color.accentColor` on a dark background is a *bright*
   blue, not the fill colour.
2. **One token, re-tuned** — lighten the Dark Mode value enough to work as text, and accept that
   the prominent button's fill becomes lighter with it (white-on-fill contrast **falls** as it
   lightens — at some point the fill needs dark text, which is a bigger change than it sounds).
3. **Stop tinting text** — leave plain buttons at `.primary`. Cheapest, and loses the app's
   colour identity everywhere except the one prominent button.

⚠️ Whatever is chosen must be **measured, not eyeballed**, in both appearances and with Increase
Contrast on, and it should land with a test that computes the ratio from the token itself so the
next palette change cannot quietly reintroduce this.

## Evidence

Ratios above are WCAG 2.1 relative luminance, computed from the two literals in
`ios/Sources/Theme.swift:14–15` against the system's own dark surfaces. The holder's report is
the ground truth they confirm: *"In dark mode the text on import another or Done in green is not
very visible."*

---

## Resolved — 2026-08-15

**Option 1 was taken: two tokens.** `ios/Sources/Theme.swift` now carries
`UIColor.kanameAccentText` (the app tint, everything drawn as text or a symbol) and
`UIColor.kanameAccentFill` (the fill behind a prominent action's white label, values unchanged).

| Appearance | Text token | Worst surface | Was |
|---|---|---|---|
| Light | `#134E4A` | 8.49:1 on `#F2F2F7` | 8.49:1 |
| Light + Increase Contrast | `#0B3634` | higher | — |
| **Dark** | **`#3FBFAF`** | **5.02:1 on `#3A3A3C`** | **2.35:1** ❌ |
| **Dark + Increase Contrast** | **`#5EEAD4`** | **7.67:1** | — |

The palette now also answers Increase Contrast, which it did not before.

**Two guards, so it cannot come back:**

1. `ios/Tests/ThemeContrastTests.swift` computes WCAG 2.1 ratios **from the tokens themselves**,
   over every appearance × contrast the system can produce, and asserts the two tokens are
   distinct in Dark Mode and that each *fails* the other's job — which is the argument for having
   two, written as a test. Reverting the Dark Mode value reproduces the reported defect exactly:
   **2.3475:1**, the same number, watched going red.
2. `scripts/import-path-audit.sh` gained a ninth scan: `.buttonStyle(.glassProminent)` may appear
   only in `Theme.swift`. Everywhere else uses `prominentAction()`, which applies the style and
   the fill token **together** — a bare `.glassProminent` would inherit the app tint, which is now
   the *text* token, and put a white label on light teal at 2.26:1. Also watched failing.

⚠️ **Not verified on a device yet.** The ratios are computed, not photographed; the holder should
re-check the import summary sheet in Dark Mode, and this is a prerequisite for 018's G7.
