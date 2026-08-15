# 06 — The import summary's title truncates to "Import comp…" at the default text size

**Status:** ready-for-agent

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
