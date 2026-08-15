# 03 — G2 fails: the filter bar clips row content at accessibility text sizes

**Status:** ready-for-human

**Found:** 2026-08-15, on the simulator, running **G2** of the manual gate for the first time.
Content size `accessibility-extra-extra-extra-large`, Dark Mode, list filtered to one account.
**Belongs to:** `018-transaction-list` — the `.safeAreaBar(edge: .bottom)` filter chrome in
`ios/Sources/Transactions/TransactionListView.swift`.
**Severity:** ⛔ **G2 fails.** G2 is the gate written specifically to catch the parked 016
finding (`StaticText '1'` at `{32, 724}`); this is the same failure mode on the new screen.
**Related:** issue `02`. The bar grows unbounded because the clear button has no line limit, so
02's fix will shrink this one — but the inset is a separate question and must be checked
independently.

## What is on screen

A transaction row's amount renders as **`−₹2,518.21` sliced horizontally through the glyphs** by
the top edge of the filter bar. The row is neither fully visible nor fully hidden: it is cut.

Evidence: `../evidence/g5-filter-chrome-and-clipped-row-xxxl.png`.

## Why it is a real failure and not just scrolled-under content

Content passing *beneath* a bottom bar during a scroll is normal and is not what G2 asks about.
This is different in two ways:

- The bar at this text size is tall enough that the list's content inset does not clear it, so
  the clipped row cannot be scrolled free of the bar at rest.
- The bar's pills are glass over the row, so what a person sees is a number with its bottom half
  removed — an amount that reads as a *different* amount is worse than one that is absent.

## The fix

The bar must contribute its **actual** height to the scroll content inset at every text size.
Once issue 02's reflow bounds the bar's growth, verify the inset again at
`accessibility-extra-extra-extra-large`: the last row of the list must be scrollable entirely
clear of the bar.

## How to prove it

A UI-level check is awkward because the populated list is unreachable from an automated run
(see issue `01` and FR-077). Until the DEBUG-only seeding slice lands, this is closed by
re-running G2 by hand at the largest size with a filter applied — and the re-run must include
the *filtered* case, because an unfiltered bar is shorter and passes.

---

## Status change — 2026-08-15, commit `3151e5b`: `ready-for-agent` → `ready-for-human`

**The cause is fixed; the verdict is not in.** This ticket named its own dependency — *"the bar
grows unbounded because the clear button has no line limit, so 02's fix will shrink this one —
but the inset is a separate question and must be checked independently"* — and that is exactly
where it now stands.

**What changed underneath it.** With `02` fixed, the bar can no longer grow without bound at any
text size:

- The clear button no longer wraps to four hyphenated lines; at accessibility sizes it is a
  single `xmark.circle`.
- The scope chip is capped at `FilterChromeLayout.maximumScopeLines` — **three** lines at
  accessibility sizes, two otherwise — and `theBarsHeightIsBounded` holds both the constant and
  the sum of the lines the chip will actually draw, at every one of the twelve text sizes. It was
  watched failing against a chip allowed six lines.

So the mechanism that produced a sliced `−₹2,518.21` is gone. **What has not been established is
that the inset now clears the bar**, because no automated run in this repo can reach a populated
transaction list (issue `01`, FR-077) and no unit test can measure a frame (FR-075).

**What remains, and it is small.** Re-run **G2** by hand at
`accessibility-extra-extra-extra-large`, Dark Mode, **with a filter applied** — an unfiltered bar
has no clear button, is shorter, and passes either way, which is the trap this ticket already
warned about. The last row of the list must be scrollable entirely clear of the bar *at rest*.

**Do it in the same sitting as G5**, whose visual half is open for the same reason: same screen,
same text size, same filter. Two gates, one setup. If G2 still fails, the remaining suspect is
`.safeAreaBar`'s inset itself rather than the bar's height, and the ticket should say so.
