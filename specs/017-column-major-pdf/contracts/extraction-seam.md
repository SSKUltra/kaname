# Contract: Native Text Extraction (platform seam)

**Feature**: `017-column-major-pdf` | **Owner**: `ios/Sources/Import/StatementTextExtractor.swift`

The core never opens a PDF (Constitution II, FR-032). This is the whole of the platform's
obligation to the engine, and it is what changes in this slice.

---

## Surface (unchanged shape)

```swift
protocol StatementTextExtractor: Sendable {
    func extract(from url: URL, password: String?) throws -> ExtractedText
}

struct ExtractedText: Equatable, Sendable {
    let lines: [String]
    let fullText: String
    let lineWords: [LineWords]
}
```

The **type signature does not change**. The *meaning* of `lines` changes from "what the PDF text
layer called a line" to "what the statement printed as a row", and `lineWords` widens from page 1
to every page.

---

## Obligations

| # | Obligation | Requirement |
|---|---|---|
| E1 | Each entry of `lines` is exactly the words printed on **one visual row**, joined by a single `U+0020`, trailing separators trimmed. | FR-001, FR-005 |
| E2 | The PDF text layer's newlines have **no** authority: the extractor may both split and join relative to them. | FR-002 |
| E3 | Row membership is decided by printed position only, never by emission order or grouping. | FR-003 |
| E4 | Words within a line appear in printed left-to-right order; lines appear in printed top-to-bottom order, page by page. | FR-004, FR-008 |
| E5 | No line contains words from two different printed rows. | FR-006 |
| E6 | Every non-whitespace character the text layer yields appears in exactly one line. | FR-007 |
| E7 | The same file always yields byte-identical `lines` and `lineWords`. | FR-009, SC-007 |
| E8 | A page whose geometry cannot be trusted falls back — **for that page only** — to the text layer's newline split, and contributes no `lineWords`. | FR-010 |
| E9 | `LineWords.lineIndex` indexes `lines`; its `words` are that line's words, in order, with the x-extents at which they were printed. | FR-011 |
| E10 | No statement content reaches a log, a diagnostic, a crash report or a file. | FR-034 |
| E11 | No network call, directly or transitively. Enforced by `scripts/import-path-audit.sh`. | FR-033, SC-009 |
| E12 | A 42-page document extracts off the main thread and honours cancellation within 2 s. | FR-035, SC-008 |

---

## Algorithm (normative, so the tests can pin it)

Per page:

1. **Guard** — `page.string` is non-nil and `page.numberOfCharacters == page.string.utf16.count`,
   and at least one glyph yields usable bounds. Otherwise → E8 fallback.
2. **Words** — split the page string into maximal non-separator UTF-16 runs
   (`unit <= 0x20 || unit == 0x00A0` is a separator). Each word takes `xMin`/`xMax` from
   `PDFSelection.bounds(for:)` over its own range, and `yExtent` from `characterBounds(at:)` read at
   an index **reduced by the number of `U+000A` before it** — PDFKit inserts those breaks into
   `string` and they stand for no glyph — reduced further to the row *most* of the word's glyphs
   agree on. A rect is usable iff `!isNull && minX/maxX/minY/maxY.isFinite && height > 0.5`. Where
   the two sources' `xMin` disagree by more than about one character at the median, the page's glyph
   indices cannot be reconciled and the selection box supplies both axes. **See research R17 — this
   supersedes the glyph-union rule and is the difference between reading a column-major page and
   scrambling it.**
3. **Zones** — project every word's `[xMin, xMax]` onto the x-axis; a maximal x-interval no word
   overlaps and at least `4 ×` the page's median space width wide is a *candidate* gutter, and is a
   gutter only if **no row band has words on both sides of it** (bands are formed once over the
   whole page for this test, then re-formed within each zone). Gutters partition the page into
   zones, emitted left-to-right. One zone is the normal case. **See research R18** — without the
   crossing test, a ledger's continuation page, which prints rows and nothing else, is cut along
   every one of its own column gaps.
4. **Bands** — within a zone, sort words by `(-yMax, xMin, utf16Start)` and sweep: a word joins the
   current band iff it overlaps the band by more than a quarter of the shorter height **and** the
   resulting union does not exceed `2.0 ×` the page's median word height; otherwise it opens a new
   band.
5. **Emit** — per band, sort members by `(xMin, utf16Start)` and join with one space; append the
   line and its `LineWords`.
6. **Orphans** — a word with no usable `yExtent` joins the band of the nearest preceding word in
   text order (never dropped — E6).

Every comparison is over values PDFKit returns verbatim; no floating-point accumulation occurs, so
E7 holds across runs.

---

## Non-obligations (deliberate)

- The extractor does **not** know what an issuer, a transaction, a date or an amount is. Nothing
  issuer-specific may enter it — the bug is structural, and per-issuer knowledge lives in the
  engine's readers.
- It does **not** attempt to reconcile a row against printed totals. That is the engine's job and
  already ships.
- It does **not** report why a page fell back. Silence is the contract: FR-026 forbids engine
  internals reaching a person, and FR-034 forbids diagnostics carrying content.

---

## Tests that pin this contract

| Test | Asserts |
|---|---|
| `ExtractionFidelityTests` (existing, **expectations unmodified**) | FR-028 — the slice-016 tight-layout merge case still resolves; round-trips still equal direct parses |
| `ExtractionFidelityTests` + both-hazards document | FR-030 — merged rows split and split columns joined in one pass |
| `StatementTextExtractorTests` (extended) | E5–E9: losslessness, determinism, per-page fallback, index consistency, band cap |
| `GeometryFixtureTests` (new) | E1–E4 end-to-end for all ten issuers, plus non-vacuity vs the legacy split |
| `ImportCancellationTests` (extended) | E12 |
| `scripts/import-path-audit.sh` (existing) | E11 |
