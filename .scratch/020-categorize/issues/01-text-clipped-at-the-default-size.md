# 01 — `.textClipped` fires on the shipping row at the **default** text size, and the fixture is what hid it

**Status:** ready-for-human (the exclusion is recorded and scoped; the design question behind it
is `019/03`'s, and is still not this slice's to settle)

**Found:** 2026-08-20, by A18/A20 — the first accessibility audits ever run against a list seeded
with **`unfiled`**. iPhone 16 simulator, iOS 26, Light and Dark, `content_size large` (the
default). PR F, `020-categorize`.

---

## What happened

A18 audits the front door carrying the worklist's door, then the worklist behind it, at the
**default** text size with every type but `.contrast`. It went red on the second audit:

```
Text of this element may be clipped at larger Dynamic Type sizes.   element = nil
```

Which reads exactly like a defect in the surface PR F added.

## It is not the narrowing, and it is not new

Three probes, one launch each, `.textClipped` alone, all at the default text size:

| Probe | Verdict |
|---|---|
| `unfiled` front door (with the worklist door on it) | **passes** |
| `unfiled` → **the whole, unnarrowed 018 list** | **fails** — same verdict, `element = nil` |
| `unfiled` → the worklist | **fails** — same verdict |
| `small` → the whole, unnarrowed 018 list | **passes** |

The middle row is the finding. **018's shipped list fails this audit at the default text size
against `unfiled`, with nothing of PR F on the screen.** What changed is not the code but the
fixture: `small`'s descriptions are `SYNTHETIC MERCHANT 01`; `unfiled`'s are `SYNTHETIC UNFILED
MERCHANT 01`, eight characters longer, against a description capped at **two lines** by
`TransactionRowLayout.descriptionLineLimit` and an account line capped at **one line at every
size** (`accountNameLineLimit == 1`).

## Why the cap is there, and why it stays

`019/03` records it in full: the account line leads with the masked digits and is deliberately
one line, because that is the only part of the identity which tells two cards of one product
apart (`.scratch/018-transaction-list/issues/04`), and the amount never yields at any size
(FR-021). The auditor is right that the text clips. The app decided that it should, and put the
whole identity in the row's spoken label — which is what a screen reader reads.

⚠️ **The auditor is also evaluating a layout that does not exist at the size it is warning
about.** It grows the text inside the *current* layout; `TransactionRowLayout` changes shape at
accessibility sizes — vertical axis, three description lines — so "may be clipped at larger
Dynamic Type sizes" is a claim about an arrangement the app never draws. That was the argument
for excluding the type at XXXL, and this ticket is the discovery that it holds at the default
size too. Only `small`'s short descriptions had ever hidden it.

## What was done

`.textClipped` is excluded from the **list** half of A18–A21 and from nothing else. In
particular it still runs over:

- the front door and the worklist's door on it — where it caught a **real** defect during this
  same session: the door drawn as `Label(sentence, systemImage:)` was reported clipped at the
  default size, naming its own `StaticText`. Drawn as a plain `Text`, the way the account rows
  beside it are drawn, the verdict goes away. That is the third time this repository has taken
  that verdict at the default size and the second time it was right (020 PR D found two).
- every other audit type on both surfaces, at both sizes, in Light and Dark.

## What is not done

Nobody has looked at a row of `unfiled` at XXXL **by eye** and said whether the truncation it
draws is acceptable. `019/03` asks the same question of `small` and it is still open. A single
photograph of both would settle both tickets; it needs a person and a phone, and it is not a
gate.
