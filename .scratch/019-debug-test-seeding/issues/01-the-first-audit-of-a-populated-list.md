# 01 — What the first accessibility audit of a populated list found

**Status:** ready-for-human (two defects **fixed**; one instrument question **open**, carried to
PR C's T074)

**Found:** 2026-08-17, by `SeededTransactionListUITests.testThePopulatedListPassesTheSystem
AccessibilityAudit` (A1) — the first `performAccessibilityAudit` ever run against a transaction
list with transactions in it. The whole slice exists so this run could happen; it found three
things on its first execution, which is the answer to "was the coverage worth building".

Default text size, Light, `small` seeded, unfiltered, iPhone 16 simulator, iOS 26.

---

## 1. The date heading rendered grey — ⛔ **defect, fixed**

`TransactionListView`'s `Section` header carried `.foregroundStyle(.primary)`, added by 018's
T116 for exactly this reason. **It was a no-op.** The bare `.primary` in a `foregroundStyle` is
`HierarchicalShapeStyle.primary` — "the most prominent level *of whatever style is already in
force*" — and the style already in force on a plain-list header is the de-emphasised grey the
header wanted in the first place. So the heading shipped grey on white at roughly 3.5:1, and the
auditor said so: *"Contrast is not high enough … unless font size is larger"*.

**Fix:** `.foregroundStyle(Color.primary)` — the absolute label colour. Confirmed by eye
(screenshots before and after) and by the auditor's verdict changing.

⚠️ **The general lesson is worth more than the fix.** A semantic style (`.primary`,
`.background`) resolves *relative to its context*; an absolute one (`Color.primary`,
`Color(.systemBackground)`) does not. Every "I set the colour and nothing happened" in this
codebase is a candidate for the same mistake, and no unit test can see it: `ThemeContrastTests`
computes ratios from the tokens, and the token here was never the problem.

## 2. The pinned heading had nothing behind it — ⛔ **defect, fixed** (closes `018/07`)

`.scratch/018-transaction-list/issues/07` parked this as `needs-triage` because "the obvious fix
(an opaque background) runs into FR-068's ban on material in the list". It does not: FR-068 bans
**material**, and prescribes opacity. The header now carries
`.frame(maxWidth: .infinity, alignment: .leading)` and `.background(Color(.systemBackground))`.

Measured effect on the audit: **5 issues → 3**. It removed one contrast verdict *and* the
`.textClipped` verdict — the heading was the clipped element too.

⚠️ 018/07 was found by a person at XXXL after forty minutes of manual gate. It was reproduced
here at the **default** text size by a machine, in twelve seconds, on the first run.

## 3. Three `Contrast failed` verdicts that name no element — ❓ **open, instrument question**

After the two fixes, three remain. Every one arrives with `issue.element == nil`, so none can be
attributed, and none can be scoped in a suppression.

**What was measured, rather than assumed:**

| Probe | Contrast issues |
|---|---|
| As shipped (before fixes) | 4 |
| Heading `Color.primary` | 4 |
| Heading opaque background | 3 |
| Heading text `.hidden()` as well | 3 — *not the heading* |
| Scope chip's label forced to `Color.primary` | 4 — *not the label's colour* |
| `.scrollEdgeEffectStyle(.hard, for: .bottom)` on the list | 4 — *not the scroll edge fade* |
| Bar's `.background(.background)` → `Color(.systemBackground)` | 3 — *not the bar's backdrop* |
| `.buttonStyle(.glass)` → `.bordered` on the scope chip | 2 |
| **Filter bar removed entirely** | **0** |
| The front door's accounts list (same combined rows, no bar) | **0** |

And the pixels, computed from the audit's own screenshot with a WCAG luminance formula: the
chip's text is `#134E4A` on `#FFFFFF` — **9.48:1**, twice the 4.5:1 threshold.

So the verdicts are about the bottom bar, they are not about any colour this app chose, and the
screen a person sees is readable. That is as far as this run can honestly take it.

**Why no suppression was written.** The front door has one (016 `issues/01`), it is narrow, and
it is scoped by the failing element's frame. Here there is no element — and, decisively, **the
real heading defect in §1 also arrived with `element == nil`**. A rule saying "ignore the
contrast issues the auditor cannot name" would have hidden the very defect that proved this audit
was worth running. A suppression that would have suppressed the finding is not a suppression.

**What was done instead.** A1 audits every type *except* `.contrast`, says so at the assertion
site in as many words, and points here. `.textClipped`, `.dynamicType`, `.elementDetection`,
`.hitRegion`, `.sufficientElementDescription` and `.trait` all still run against the populated
list — including `.textClipped`, which is the instrument FR-038 needs for `018/02`.

**Where it goes.** PR C's **T074** is already the task for deciding what this auditor can and
cannot see, with the standing instruction that the criterion is never weakened and the defect is
never re-parked. This is the second question for it, and the probe table above is the evidence it
should start from. If the verdict is "the auditor cannot resolve a Liquid Glass backdrop", the
remedy named in advance is T075's: **a sharper instrument** — a measured contrast assertion over
the screenshot, of the kind computed by hand above — not a weaker criterion.

## What is *not* wrong

The row itself. Description, account identity, category and amount all pass at full contrast, in
both the audit and the pixels, and no audit type other than contrast raised anything against a
row at the default size.
