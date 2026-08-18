# 07 — The pinned date heading has no background, so it renders over the row beneath it

**Status:** resolved (2026-08-17, by 019 PR B)

> **Resolved.** The heading now carries `.frame(maxWidth: .infinity, alignment: .leading)` and
> `.background(Color(.systemBackground))` — the opaque background this ticket's own analysis names,
> which FR-068 permits because what it bans is *material*, not opacity. Two things worth carrying
> forward. It was **reproduced by a machine at the default text size in twelve seconds**, by the
> first `performAccessibilityAudit` ever run against a populated list (019 A1), where a person had
> needed XXXL and forty minutes of manual gate to see it — the audit reported it as `.textClipped`
> plus a contrast verdict, and both went away with the background. And the heading's colour was
> **also** wrong for a separate reason: T116's `.foregroundStyle(.primary)` was a no-op, because
> the bare `.primary` is the *hierarchical* style and resolved against the grey already in force.
> See `.scratch/019-debug-test-seeding/issues/01`.

**Found:** 2026-08-16, on the simulator, while running **G2** to closure (`issues/03`). Content
size `accessibility-extra-extra-extra-large`, Dark Mode, list filtered to one account, scrolled.
**Belongs to:** `018-transaction-list` — `TransactionListView.rows`, the `Section` header.
**Severity:** Legibility, at accessibility sizes only. **Not** a wrong number and not a blocked
task, so it is not release-blocking on its face — but G6 says *"no text on text"* and this is text
on text, so it needs a verdict rather than a shrug.
**Unrelated to `02`, `03` and `04`.** It is visible in their evidence but is not caused by them:
the header has rendered this way since US1, and nothing in `3151e5b` or the vertical-bar fix
touches a `Section` header.

## What is on screen

`../evidence/issue-03-resolved-last-row-clears-the-bar-xxxl.png`, top of frame. The pinned
heading **"1 September 2025"** is drawn over the row scrolling beneath it, and the row's own
**"SYNTHETIC MERCHANT"** is legible *through* it — two strings occupying the same pixels, one
grey, one ghosted white:

```
1 September       ← heading, pinned
SYNTHETIC         ← the row underneath, showing through
2025
MERCHANT
```

At the **default** text size the same screen looks fine, because a heading is one short line and
the row scrolls past it quickly. At XXXL the heading is two lines and ~130 pt tall, so there is a
large band of overlap and it persists for the whole scroll.

## Why it happens

`.listStyle(.plain)` pins section headers (which is deliberate and is what G8 tests — FR-034),
and the header carries `.foregroundStyle(.primary)` from T116 but **no background of its own**.
Whatever the system draws behind a pinned plain-list header is not opaque enough here to hide
2 5pt-tall white glyphs moving underneath it.

## Why it is not obviously a defect

The heading is *pinned*, which is the behaviour FR-034 asks for and G8 passed on. Content moving
under a pinned header is normal; the question is only whether the header is opaque enough to stay
readable while it does. At smaller sizes it is. So this may be a **size-dependent** failure of an
otherwise correct design, and the fix may be as small as an explicit background on the header.

⚠️ **But an explicit background is not free here.** FR-068 keeps material and glass away from the
list — a person reads figures against an opaque surface — so the background has to be *opaque*,
not `.thinMaterial`, and it has to be the list's own background colour in both appearances. That
is a real design decision, which is why this is `needs-triage` and not `ready-for-agent`.

## How to prove it, whichever way it is decided

A rendered check is the only honest one, so it belongs on the manual gate beside G8: at XXXL, with
a list scrolled so a row passes under a heading, **no glyph of the row may be legible inside the
heading's band**. The `gate/` corpus (`issues/03`) reaches this state in two flicks.

## What is *not* wrong

The heading's **content** is right — "1 September 2025" carries the year because it is not the
current year (G4 passed), and `groupAnnouncement` still announces the heading with its count. This
is only about what is drawn behind it.
