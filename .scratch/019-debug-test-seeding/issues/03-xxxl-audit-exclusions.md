# 03 — At XXXL the shipping list fails `.textClipped` and `.dynamicType`, and one of them is right

**Status:** ready-for-human (the exclusions are recorded and scoped; the design question behind
them is real and is not this slice's to settle)

**Found:** 2026-08-18, by A2/A4/A5 — the first accessibility audits ever run against a **populated**
transaction list at `AccessibilityXXXL`. `small` seeded, iPhone 16 simulator, iOS 26, Light and
Dark.

---

## What the auditor says

At the default text size the populated list is clean (A1, A3 — every type but `.contrast`, which
`issues/01` covers). At `AccessibilityXXXL` it is not:

```
Text of this element may be clipped at larger Dynamic Type sizes.   ×5
User will not be able to change the font size of this element       ×4
```

Every one of them arrives with `element == nil`, so none can be attributed or scoped.

## One of them is correct, and the app decided it

The row's account line is `.lineLimit(1)` at **every** size — `TransactionRowLayout
.accountNameLineLimit == 1`, pinned by `TransactionRowLayoutTests`. At XXXL that line reads:

```
···· 0006 · SYNT…
```

It is genuinely truncated, and it is truncated **on purpose**:
`.scratch/018-transaction-list/issues/04` is the ticket that put the masked digits first,
precisely so that the part which tells two cards of one product apart is the part that survives.
The auditor is right that the text clips. The app's answer is that it should, and that the whole
identity is in the row's spoken label, which is what a screen reader reads.

The amount is `.fixedSize(horizontal: true, vertical: false)` for the same kind of reason —
FR-021: the amount never yields, at any size, for any magnitude. That is a plausible source of
`.dynamicType`, though with no element on the issue it cannot be confirmed.

## What was measured before excluding anything

| Probe | `.textClipped` |
|---|---|
| As shipped, XXXL | 5 |
| Account line's `lineLimit` removed | 4 |
| **Every** `lineLimit` in the row removed (description, account, category) | 4 |

Removing the caps does not clear it, so `lineLimit` is not the whole story — and removing them
would in any case undo 018's decisions rather than answer them.

## What was done

The XXXL audits (A2, A4, A5) run every type **except** `.contrast`, `.textClipped` and
`.dynamicType`, stated at the declaration site in `SeededAccessibilityUITests`. What still runs at
XXXL is what XXXL actually breaks in practice: `.elementDetection`, `.hitRegion`,
`.sufficientElementDescription` and `.trait` — elements that vanish, controls too small to hit,
controls a screen reader cannot name. The default-size audits are **not** reduced.

⚠️ **The cost of that exclusion is exactly the instrument FR-038 wanted.** `.textClipped` was the
type research R10 nominated to catch `018/02`'s truncating filter chip. It cannot: on this screen
it is already red at XXXL, by design, so it cannot discriminate the defect from the shipping
state. See `issues/04` — the defect is caught instead by a sharper instrument that reads what was
actually drawn.

## The design question this leaves open

**Should a row truncate an account name at `AccessibilityXXXL` at all?** At that size the row is
already a `VStack`, so letting the account line wrap costs nothing structurally, and the auditor,
018/04's ticket and this finding are three different arguments about the same line. That is a
design decision with a unit test pinned to it (`accountNameLineLimit == 1` at every size), and it
belongs to whoever owns the row's layout — not to a slice about test seeding. It is written down
here so the next person to open that file finds the argument already assembled.
