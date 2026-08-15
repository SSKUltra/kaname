# 02 — G5 fails: the active account filter is unreadable at accessibility text sizes

**Status:** resolved

**Found:** 2026-08-15, on the simulator, running **G5** of the manual gate
(`specs/018-transaction-list/quickstart.md` § *The manual, release-blocking gate*) for the first
time. Content size `accessibility-extra-extra-extra-large`, Dark Mode.
**Belongs to:** `018-transaction-list` — `ios/Sources/Transactions/TransactionListView.swift`,
`scopeMenu` and the clear button.
**Severity:** ⛔ **G5 fails**, and with it SC-012. FR-038 requires the current scope to be stated;
at accessibility sizes it is not.

## What is on screen

With the list filtered to *ICICI Amazon Pay Credit Card, ending 7742*:

- The scope chip reads **`ICIC…`** on the first line and **`·····…`** on the second. Both the
  account name and its masked last-4 are truncated past the point of meaning — **a person cannot
  tell what the list is filtered to**, and the mask degrades into a row of dots.
- The clear button wraps and hyphenates as **`Show all ac-count s`** across four lines, with an
  orphaned `s`, and the pill grows tall enough to cover list content.

Evidence: `../evidence/g5-filter-chrome-and-clipped-row-xxxl.png`.

## Why

```swift
} label: {
    VStack(alignment: .leading, spacing: 1) {
        Text(model.scopeTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
        if let subtitle = model.scopeSubtitle {
            Text(subtitle).font(.caption).monospacedDigit().lineLimit(1)
        }
    }
}
```

Both `Text`s are hard `.lineLimit(1)` inside a bar that keeps its horizontal layout at every text
size, so the only thing that can give is the string. The clear button has **no** line limit, so
it does the opposite and expands without bound. Nothing in the bar reflows for
`dynamicTypeSize.isAccessibilitySize`.

## What is *not* broken

`.accessibilityLabel(model.scopeAnnouncement)` is applied to the chip, so **VoiceOver still
announces the full sentence** — verified through Accessibility Inspector. G5's announcement half
passes; only its visual half fails. Do not "fix" this by changing the announcement.

The scope **menu** renders both ICICI cards in full, with their last-4s, at the same text size.
The information is available; only the bar's presentation of it is not.

## The fix

Reflow the filter chrome at accessibility sizes rather than truncating inside it. The usual
shapes, in preference order:

1. Stack the bar vertically when `dynamicTypeSize.isAccessibilitySize`, giving each label the
   full width — the account name may then wrap to two or three lines and stay readable.
2. If a horizontal layout must be kept, `.truncationMode(.middle)` on the name preserves the
   discriminating tail, and the mask line should be dropped rather than ellipsised — `·····…`
   states nothing.
3. Give the clear button a symbol-plus-label form that collapses to `xmark.circle` with an
   accessibility label at accessibility sizes.

## How to prove it

`TransactionFilterTests` already owns the scope surface. Add a case at
`.dynamicTypeSize(.accessibility5)` asserting the rendered chip contains the last-4, and watch it
fail against today's `lineLimit(1)` before trusting it.

---

## Resolution — 2026-08-15, commit `3151e5b`

**Fixed, and pinned.** The bar now takes a *decision* instead of letting the string be the only
thing that can give: `FilterChromeLayout` (`TransactionListModels.swift`), pure and provable in
exactly the shape `TransactionRowLayout` already established — no `View`, no environment, no
rendering, so the automatable half of SC-013 is covered without a screen.

**What it decides**, at accessibility sizes:

- **The chip inverts.** `scopeLines(title:subtitle:)` returns `[mask, name]` rather than
  `[name, mask]`. The mask leads, is `isPrimary`, is one line, and is never middle-truncated —
  a mask with its middle removed is a different mask. The name follows in what is left, with
  `truncationMode(.middle)` so both of its ends survive.
- **The clear button drops its words** (`clearButtonShowsTitle == false`) and renders
  `xmark.circle`, keeping `TransactionListStrings.clearFilter` as an explicit
  `.accessibilityLabel` on the *button* — stated there rather than left to the label style, so
  what a person hears cannot change with the text size that hid the words.

**A deviation from this ticket's preference order, on purpose.** Option 1 (stack the bar
vertically) was **not** taken. Stacking multiplies the bar's height, and issue `03` is a
*clipping* failure caused by that exact height — the two tickets pull in opposite directions and
03 is the more serious. Option 3 alone frees most of the bar's width, which is what the chip
actually lacked, and it *shrinks* the bar rather than growing it. Options 2 and 3 are both in.

**Why the mask, and not the name.** At the largest size the widest chip this bar can offer holds
a handful of characters. There is no truncation of a card product's full name that is still a
name — so the question is not *how* to truncate but *which fact gets the space*, and the answer
is the four digits, the only part of an account's identity that discriminates between two cards
of one product. It is the same answer issue `04` reaches for the row, which is why the two rhyme.

**What was not touched.** `.accessibilityLabel(model.scopeAnnouncement)` on the chip — this
ticket said not to "fix" the announcement, and it was not; the menu; the standard sizes, which
`theStandardSizesAreUnchanged` now holds byte-for-byte, because a fix is not licence to improve
a surface that passed its gate.

**Proof** — `ios/Tests/FilterChromeLayoutTests.swift`, a new suite (the chrome tests would have
pushed `TransactionFilterTests.swift` to 448 lines, past the 400-line limit). Seven tests, and
these were **watched failing** before they were trusted:

| Break | Went red |
|---|---|
| `clearButtonShowsTitle = true` always | *The clear button drops its words exactly at the accessibility sizes* (5 issues) |
| `scopeLines` never inverts | *At every accessibility size the chip leads with the masked digits* (25 issues) |
| `maximumScopeLines` 3 → 6 | *The chip can never grow past three lines, at any size* (5 issues) |
| the bar stops calling `chrome.…` | *The row and the bar draw their decisions…* (the W5 source pin) |

That last one is the join this repo kept needing: a pure decision is only worth something while
the view still asks for it, so `TransactionAccessibilityTests` now reads
`TransactionListView.swift` and fails if the bar stops consulting the layout.

⚠️ **The visual half still belongs to a person.** These tests prove the decision, not the
rendering — no unit test can measure a frame (FR-075). G5's visual half closes on a re-run at
`accessibility-extra-extra-extra-large`, which is booked with issue `03`'s G2 re-run, since both
need the same screen at the same setting.

---

## ⛔ Reopened, then resolved — 2026-08-16, on the simulator

**The fix above was wrong, and the gate caught it.** Re-running G5 at
`accessibility-extra-extra-extra-large` in Dark Mode with the filter applied, the chip read:

```
•••• 77…
ICICI  Ama…Card
```

The clear button *had* collapsed to `xmark.circle` as designed, and the name *was* middle-
truncated as designed — but **the mask itself truncated**, which is the one thing the whole fix
existed to prevent. Evidence: `../evidence/issue-02-second-failure-mask-truncated-xxxl.png`.

**Why the first fix could not have worked, in numbers.** At the largest text size `•••• 7742` in
`.subheadline.weight(.semibold)` wants roughly **280 pt**; the collapsed glass clear button wants
roughly **110 pt**; the bar's own horizontal padding is **32 pt**. That is ~420 pt of demand on a
**393 pt** screen. **No ordering of the two facts fits them side by side** — inverting the chip
changed *which* fact got truncated, not *whether* one did.

**The decision above — "option 1 was declined because stacking grows the bar" — was reasoning
about the wrong constraint.** Width was binding, not height. This ticket's own first preference
was correct, and the deviation recorded above is withdrawn.

**What actually fixed it:** `FilterChromeLayout.axis`. At accessibility sizes the bar is a
`VStack` and the chip gets the full width; below them it is the `HStack` it always was. With
361 pt to work in, the chip renders **`•••• 7742` over `ICICI Amazon Pay Credit Card` in full** —
the name does not even need its middle truncation at this size, and the clear `⊗` sits below.

✅ **G5 passes**, both halves — `../evidence/issue-02-resolved-vertical-bar-xxxl.png`.

**The lesson worth keeping.** Every assertion in `FilterChromeLayoutTests` passed against the
broken bar, because they prove *which fact leads*, and the bar led with the mask exactly as
asked — it simply had nowhere to put it. **A pure layout decision cannot see a width.** That is
not a flaw in the approach; it is the boundary of it, and it is the reason FR-075 puts the
rendering on a manual gate. The axis is now pinned by `theBarStacksAtTheAccessibilitySizes`
(watched failing against `axis = .horizontal`) and by the W5 source pin (watched failing against
a view that stops asking) — but what *found* it was a person at XXXL, and nothing cheaper would
have.
