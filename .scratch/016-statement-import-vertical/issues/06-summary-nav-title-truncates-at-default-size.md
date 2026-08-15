# 06 — The import summary's title truncates to "Import comp…" at the default text size

**Status:** resolved

**Found:** 2026-08-15, on the simulator, on the very first summary screen of **T129** — at the
**default** Dynamic Type size, with no accessibility setting enabled.
**Belongs to:** `016-statement-import-vertical` — `ios/Sources/Import/ImportSummaryView.swift`.
**Severity:** Cosmetic, but it is the first screen a person sees after their first import, and it
is broken out of the box rather than only at an accessibility size.

## What happens

`ImportSummaryView` renders an inline navigation title with a button on each side:

```swift
.navigationTitle("Import complete")
.navigationBarTitleDisplayMode(.inline)
.toolbar {
    ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDismiss) }
    ToolbarItem(placement: .cancellationAction) { Button("Import another", action: onImportAnother) }
}
```

`"Import another"` is a wide leading item and `"Done"` a trailing one, so the inline title is
left with too little width and renders as **`Import comp…`**. Reproduced on iPhone 16, iOS 26.5,
at the default content size category; it degrades further at accessibility sizes.

## Why it matters more than it looks

The truncated string is the screen's only statement of what happened. A person who has just
handed the app a bank statement is being told "Import comp…" — and the two readings that
suggests, *complete* and *company*, are not equally reassuring.

## Options

- Shorten the leading button. **"Another"** or an SF Symbol (`doc.badge.plus`) with an
  accessibility label carrying the full phrase; the title then fits.
- Drop the inline title and let the summary's own content carry the message — the account row
  already names the issuer, and `Section("Imported")` already labels the figures.
- Move "Import another" out of the toolbar and into the content, below the figures, where it is
  a next action rather than a chrome button competing with the title.

## How to prove it

A snapshot test of `ImportSummaryView` at the default size asserting the title renders in full.
It must be watched failing against today's toolbar before it is trusted.

---

## Resolution — 2026-08-16, on the simulator

**Fixed** by this ticket's third option: "Import another" left the toolbar and became a row in
the content, below the figures. The title now renders **"Import complete"** in full at the
default text size. Evidence:
`../evidence/issue-06-resolved-title-in-full-action-in-content.png`.

**It was nearly fixed by deleting the button**, on the holder's reasoning — that "Done" lands on
the front door, whose own "Import a statement" opens the same picker, so the shortcut costs one
tap and no capability. The reasoning is sound and the code was written that way. **It was wrong
anyway**, because of one line in the spec:

> **FR-035**: The person MUST be able to dismiss the summary **and start another import from it**.

"From it" is explicit. Removing the control would have quietly traded a functional requirement
for a cosmetic fix, which is the kind of trade that is invisible three months later. Moving it
into the content satisfies both: FR-035 keeps its shortcut, and the title gets its width back.

**Why the content is the better home anyway**, beyond the title:

- It can **wrap**. A toolbar button cannot, which is why it degraded further at accessibility
  sizes — this fix therefore closes the accessibility half of the ticket too, not just the
  default-size half.
- It sits **below the notices**, so an integrity warning or a "nothing recognised" notice is
  passed on the way to importing again, rather than skipped by a control in the chrome.
- It reads as a **next action** rather than a control competing with "Done" for the same glance.

**Proof** — `ImportMessageAuditTests.theSummaryKeepsOneToolbarAction`, which pins the *cause*
rather than the string: exactly one `ToolbarItem`, no `.cancellationAction`, no leading or
principal placement — **and** that the action still exists in the content and the view still
takes something to run it, because a pin that only banned the toolbar button would be satisfied
by deleting FR-035's capability altogether. Both halves were watched failing:

| Break | Went red |
|---|---|
| the shipped toolbar, crowding the title again | 2 issues |
| the content row deleted instead of moved | 1 issue |

⚠️ **One thing the audit had to learn.** Its first version scanned the raw source and failed
against the fix's own comment, which names the button it moved. It now strips comment lines: an
audit that cannot tell a banned control from the sentence explaining why it moved is an audit
that punishes writing things down.

⚠️ **`specs/016-statement-import-vertical/tasks.md` T064 still describes the button as
toolbar-placed.** It is a completed-task record rather than a live instruction, so it was left as
written; FR-035 in `spec.md` is unchanged and is satisfied.
