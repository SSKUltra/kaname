# 02 — G5 fails: the active account filter is unreadable at accessibility text sizes

**Status:** ready-for-agent

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
