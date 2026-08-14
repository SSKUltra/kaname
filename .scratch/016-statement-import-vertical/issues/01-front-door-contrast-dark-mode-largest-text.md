# 01 — The front door fails the Dark Mode contrast audit at the largest text size

**Status:** ready-for-human

**Found:** 2026-08-14, during `018-transaction-list` PR B (T069's gate).
**Belongs to:** `016-statement-import-vertical` — its screen, its manual accessibility gate
(T123), its automated audit suite (`ios/UITests/ImportFrontDoorUITests.swift`).
**Severity:** ⚠️ **`make ios-test` is red on unmodified `main` today.** Every slice after this
one inherits a gate it cannot pass, so this blocks more than the screen it is about.

## What fails

```
xcodebuild -only-testing:KanameUITests/ImportFrontDoorUITests test

AUDIT ISSUE type=XCUIAccessibilityAuditType(rawValue: 1)
  detail=Contrast failed for SwiftUI.AccessibilityNode
  element=StaticText, {{24.0, 467.0}, {345.0, 621.3}},
  label: 'Import a statement PDF from your bank and Kaname reads the transactions in it,
          sorts them into categories, and checks the figures add up.'

-[ImportFrontDoorUITests testTheFrontDoorPassesTheAuditInDarkModeAtTheLargestTextSize]:
  Contrast failed
```

The element is `ImportEmptyStateView.explanation` (`ios/Sources/Import/ImportEmptyStateView.swift`).

## It is not 018's doing — verified, not assumed

The whole 018 working tree was stashed, `make ios-gen` re-run against clean `main`, and that
single test run on its own. **It fails identically**, down to the same element at the same
frame `{{24, 467}, {345, 621.3}}`.

It was **green when it was written** (`ebfbcf0`, "audit the axes a person should not have to
remember", whose own handoff note records "All green on the front door"). Nothing has touched
that screen since. The likeliest cause is therefore an Xcode / simulator-runtime update — iOS
26.5's scroll edge effects are the obvious suspect — rather than a code change.

## What the evidence points at

At `UICTContentSizeCategoryAccessibilityXXXL` the explanation is **621 pt tall on an 852 pt
screen**, so it necessarily scrolls under the bottom bar that holds "Import a statement". A
screenshot of that state shows the last visible line rendered **faded** where it passes behind
the bar — the system's soft scroll-edge effect. Faded white text is what the auditor measures,
and it is right to fail it: those words really are half-legible on the device.

Note the element's frame extends to y = 1088, past the bottom of the screen, so the auditor may
also be sampling a region that is not rendered at all. Whether that is a second, separate
problem is not established.

## What was already tried, and reverted

Both were attempted from 018 and **both reverted** — recorded so nobody spends the time twice:

| Attempt | Result |
|---|---|
| `.safeAreaInset(edge: .bottom)` → `.safeAreaBar(edge: .bottom)` on `ImportEmptyStateView` | **No change.** The reported element frame was byte-identical before and after. The bar does own its inset; the text is simply taller than the viewport and still scrolls behind it. |
| `.scrollEdgeEffectStyle(.hard, for: .bottom)` on the `ScrollView` | **Worse.** `testTheFrontDoorSurvivesTheLargestAccessibilityTextSize` (light mode) went red too, so the hard edge introduced a second failure rather than removing the first. |

## Why it needs a person

The three plausible resolutions are design decisions, not mechanical fixes, and two of them
change what the first-run screen says:

1. **Shorten or restructure the explanation** so it is not taller than the screen at the largest
   size — two shorter paragraphs, or the privacy promise behind a disclosure. This is copy the
   constitution treats as content, not decoration: it is the reason a person hands Kaname their
   statements, so it is not an agent's to trim.
2. **Change the bottom bar** so nothing scrolls behind it at accessibility sizes — let the action
   move into the scrolling content at those sizes, for instance. Costs a layout branch on text
   size.
3. **Judge it an auditor artifact** and suppress that one issue in `performAccessibilityAudit`'s
   handler. ⚠️ Only defensible with **eyes on the device** — the screenshot suggests a genuine
   legibility problem, so this would have to be disproved rather than assumed. It is also
   exactly the kind of suppression that makes an audit stop meaning anything.

It belongs with **T123**, 016's never-run manual gate (Reduce Transparency, VoiceOver, and the
five screens behind an import), because that is the pass where a person is already looking at
this screen at this text size.

## Related, and still open

- The **parked `StaticText '1'` at `{32, 724}`** finding on the accounts list — same screen
  family, same "content under the bottom bar at accessibility sizes" shape. 018 removed its
  suspected cause (`ImportedAccountsView` is no longer a `LabeledContent`, and now chooses its
  axis by the same proven rule the transaction row uses), but the finding was never reproduced,
  so it is not closed by that.
- 018's own manual accessibility gate has the same root limitation: `performAccessibilityAudit`
  runs against a launched app and cannot reach any screen behind an import. The **DEBUG-only
  seeding hook** is the decision that would close all of it at once, and it is still deferred
  (016's T115, 018's out-of-scope list).

## Comments

_2026-08-14_ — Filed from 018 PR B rather than fixed there. 018's gate T069 is left **unchecked**
with a pointer here: a gate ticked green while it is red is worth less than no gate at all.
