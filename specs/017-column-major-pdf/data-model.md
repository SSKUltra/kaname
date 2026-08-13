# Phase 1 Data Model: Column-Major PDF Extraction Fidelity

**Feature**: `017-column-major-pdf` | **Spec**: [`spec.md`](./spec.md) | **Research**: [`research.md`](./research.md)

This slice adds **no** persisted entity and **no** schema migration (research R9). Everything below
is either an in-memory value produced during extraction, a static registry record, or a committed
test vector. The store stays at **schema v6**.

---

## 1. Extraction-time values (platform, Swift — `ios/Sources/Import/`)

### `PositionedWord` (new, internal to `PDFKitStatementTextExtractor`)

One atomic word of a page with the geometry needed to place it in a row.

| Field | Type | Notes |
|---|---|---|
| `text` | `String` | A maximal non-separator UTF-16 run of `page.string`. Never split, never rewritten. |
| `range` | `Range<Int>` | UTF-16 range in the page string. Used as the deterministic tie-break key. |
| `xMin`, `xMax` | `CGFloat` | From the first / last usable glyph bounds. |
| `yExtent` | `ClosedRange<CGFloat>?` | Union of usable glyph ink extents. `nil` ⇒ no usable geometry (research R2/R6). |

**Validation.** A glyph contributes only when `!bounds.isNull && bounds.minY.isFinite && bounds.maxY.isFinite && bounds.height > 0.5` — the shipped guard, unchanged. A word with `yExtent == nil` is *not* dropped (FR-007); it joins the band of the nearest preceding word in text order.

### `Zone` (new, internal)

A vertical slab of a page separated from its neighbours by a full-height gutter (research R4).

| Field | Type | Notes |
|---|---|---|
| `xRange` | `Range<CGFloat>` | Gutter-bounded. |
| `words` | `[PositionedWord]` | Every word whose `[xMin, xMax]` falls in `xRange`. |

**Invariant.** Zones partition the page's words: every word is in exactly one zone. One zone is the
normal case; the multi-zone path exists for side-by-side panels.

### `RowBand` (new, internal) — **the unit this slice exists to recover**

| Field | Type | Notes |
|---|---|---|
| `extent` | `ClosedRange<CGFloat>` | Union of member `yExtent`s, capped at `2.0 ×` the page's median word height. |
| `words` | `[PositionedWord]` | Ordered by `(xMin, range.lowerBound)`. |

**Membership rule.** A word joins the current band iff `overlap > min(heights) / 4` (the shipped
`sharesARow`) **and** the union would not exceed the cap. Otherwise it opens a new band.

**Ordering.** Bands are emitted per zone by descending `extent.upperBound`, then ascending first
member `xMin`, then ascending `range.lowerBound`. This is a **total** order — FR-009 / SC-007.

### `ExtractedText` (existing — shape unchanged, semantics sharpened)

```swift
struct ExtractedText: Equatable, Sendable {
    let lines: [String]        // one entry per RowBand, in page then zone then band order
    let fullText: String       // lines.joined(separator: "\n")
    let lineWords: [LineWords] // now for EVERY reconstructed line (research R11), not page 1 only
}
```

| Field | Change | Requirement |
|---|---|---|
| `lines` | One line per **printed row**, not per text-layer newline. Words joined by exactly one `U+0020`; trailing separators trimmed. | FR-001, FR-004, FR-005 |
| `fullText` | Derived, unchanged rule | FR-007 |
| `lineWords` | Now emitted for every line of every page (pages in geometry fallback contribute none) | FR-008, FR-011 |

**Invariants asserted by tests**

- **Lossless** — the multiset of non-whitespace characters in `lines` equals that of the page
  strings (FR-007).
- **Deterministic** — extracting the same file twice yields byte-identical `lines` and
  `lineWords` (FR-009, SC-007).
- **No fabrication** — no reconstructed line contains words from two different printed rows
  (FR-006), and no document yields more transactions than it prints (SC-003).
- **Index-consistent** — `LineWords.lineIndex` indexes `lines`, and the words listed are exactly
  the words of that line, in the same order (FR-011).

### `ExtractionFailure` (existing) — unchanged

`notAPDF` · `passwordRequired` · `wrongPassword` · `noExtractableText` · `unreadable`. No case is
added: a page whose geometry cannot be trusted is a **fallback**, not a failure (research R6).

---

## 2. Engine records (Rust — `core/crates/kaname-core/src/statement/`)

### `ClaimEvidence` (new enum)

| Variant | Meaning | Rule |
|---|---|---|
| `ProductProven` | The document itself names the card product, read from the header region | Required for every card entry of an institution that has more than one card entry (FR-050/FR-051) |
| `BankLevel` | The claim matches any card from that institution | Legal **only** while that institution has exactly one card entry |

Bank-account entries are always `BankLevel` by construction — FR-042 identifies accounts per bank.

### `ReaderEntry` (existing, one field added)

| Field | Type | Change |
|---|---|---|
| `id` | `&'static str` | **Renamed** for all six card entries — `<INSTITUTION>_<PRODUCT>_CARD` (FR-052) |
| `display_name` | `&'static str` | **Renamed** for four card entries to name the product (FR-041/FR-043) |
| `bank_code` | `&'static str` | Institution only; `sbi::BANK_CODE` `"SBI_CARD"` → `"SBI"` (FR-046/FR-053) |
| `kind` | `StatementKind` | unchanged |
| `evidence` | `ClaimEvidence` | **new** (FR-050) |
| `claims` | `fn(&str) -> bool` | Now receives the **identity region**, not raw `full_text` (research R7) |
| `read` | `fn(&[String], &str, &[LineWords]) -> ParsedStatement` | unchanged — no reader's parsing behaviour changes (FR-043) |

### Registry after this slice (full future state — FR-052)

| id | `bank_code` | display name | kind | evidence |
|---|---|---|---|---|
| `AU_BANK` | `AU` | AU Small Finance Bank Account | BankAccount | BankLevel |
| `FEDERAL_BANK` | `FEDERAL` | Federal Bank Account | BankAccount | BankLevel |
| `HDFC_BANK` | `HDFC` | HDFC Bank Account | BankAccount | BankLevel |
| `ICICI_BANK` | `ICICI` | ICICI Bank Account | BankAccount | BankLevel |
| `FEDERAL_SCAPIA_CARD` | `FEDERAL` | Scapia Credit Card | CreditCard | BankLevel |
| `HDFC_SWIGGY_CARD` | `HDFC` | HDFC Swiggy Credit Card | CreditCard | **ProductProven** |
| `ICICI_AMAZONPAY_CARD` | `ICICI` | ICICI Amazon Pay Credit Card | CreditCard | BankLevel |
| `IOB_RUPAY_CARD` | `IOB` | IOB RuPay Credit Card | CreditCard | BankLevel |
| `SBI_CASHBACK_CARD` | `SBI` | SBI Cashback Credit Card | CreditCard | BankLevel |
| `YES_KIWI_CARD` | `YES` | Kiwi (YES Bank) Credit Card | CreditCard | BankLevel |

`FEDERAL_BANK` and `FEDERAL_SCAPIA_CARD` deliberately share `bank_code = FEDERAL` — same
institution, different statement kind. That is FR-046 working, not a collision.

**Structural rules, enforced mechanically**

- **FR-051** — for every `bank_code` with ≥ 2 `CreditCard` entries, all must be `ProductProven`.
  Today no institution has two, so every `BankLevel` above is legal; adding an `HDFC_INFINIA_CARD`
  beside `HDFC_SWIGGY_CARD` fails the build until both prove their product.
- **FR-052** — every id matches `^[A-Z0-9]+_BANK$` or `^[A-Z0-9]+_[A-Z0-9]+_CARD$`, and its
  institution prefix equals its `bank_code`.
- **FR-053** — no `bank_code` contains `_CARD`, `_BANK` or any product token.
- **FR-016** — no `CreditCard` entry claims a bank-account golden fixture and no `BankAccount`
  entry claims a credit-card one (test-only; research R10).

### `IdentityText` (new, derived — not a stored type)

The projection of a document that recognition is allowed to see (research R7).

| Rule | Detail |
|---|---|
| Input | `lines` (or `full_text` split) |
| Excluded | any **row-like** line: contains a date (`DD/MM/YYYY`, `DD/MM/YY`, `DD-MMM-YYYY`) **and** an amount (`[\d,]+\.\d{2}`) |
| Normalization | lowercase, then remove all Unicode whitespace |
| Header sub-region | the first 15 non-excluded lines — the only region a `ProductProven` claim may match (FR-044/FR-047) |

**Invariants.** Pure, deterministic, allocation-bounded; identical input ⇒ identical output
(FR-015). Computed once per `detect_issuer` call.

### Untouched engine records

`ParsedStatement`, `ParsedTransaction`, `LedgerMetadata`, `DirectionSource`, `Word`, `LineWords`,
`Issuer`, `StatementKind`, `ReaderError` — **no shape change**. The reader seam stays
`read_lines(lines, full_text, first_row_words)` (FR-032), money stays `rust_decimal::Decimal`
(FR-021), and direction stays explicit (FR-019).

---

## 3. Test vectors (committed, synthetic)

### `GeometryFixture` — `fixtures/geometry/<issuer>.json`

The generative vector defined by [`contracts/geometry-fixture.md`](./contracts/geometry-fixture.md).
Summary of its entities:

| Entity | Fields | Notes |
|---|---|---|
| **LayoutSignature** | `page_size`, `columns[]`, `row_pitch`, `first_row_y`, `date_format`, `font_size` | Geometry only — **no values** (ADR-0004 §5) |
| **Column** | `x`, `align`, `role` (`date`/`description`/`reference`/`amount`/`direction`/`withdrawal`/`deposit`/`balance`) | `x` in PDF points; role drives which fabricated content is drawn |
| **HeaderBlock** | `lines[]` | Literals taken from the reader's **own published claim markers**, never harvested (FR-039) |
| **Row** | per-column cell strings | Wholly fabricated merchants, amounts, dates, account/card numbers |
| **Expectation** | `issuer_id`, `transactions[]` (date, amount, direction, description), `min_legacy_shortfall` | Assertion 3 of research R12 |

**Validation rules**

- Every fixture declares at least one **debit** and one **credit** (SC-006).
- `expected.transactions.len()` equals the number of printed rows — no row may be omitted from the
  expectation (SC-003).
- The rendered document MUST be drawn **column-major** so the platform text layer emits it that
  way; a fixture whose legacy-path transaction count is not strictly lower than its new-path count
  fails the suite (FR-037/SC-011 — non-vacuity).
- Coverage: all ten issuers, both statement kinds, both date formats `DD-MMM-YYYY` and
  `DD/MM/YYYY` (FR-038).
- At least one fixture exhibits **both** hazards — tight leading that the text layer merges *and*
  columns it emits separately (FR-030).
- At least one fixture per confusable pair names a rival institution **inside its transaction
  descriptions** and must still resolve to its own issuer (FR-014, research R15).

### Reference-set report (never committed)

Produced by the human-run gate (research R13). One record per file, in memory and on the operator's
console only: `{ file_name, issuer_display_name, transaction_count }`. **No** date, amount,
merchant, account number or extracted line may appear (FR-034/FR-039).

---

## 4. State transitions

Extraction has one state machine, per **page**:

```text
page → geometry trusted?
        ├─ yes → words → zones → row bands → lines + lineWords
        └─ no  → text-layer newline split → lines, no lineWords     (research R6, FR-010)
```

Recognition, per **document**:

```text
lines → identity region → normalized → claim match per entry
      → candidates ordered by (kind_rank, evidence_rank, id)
      → Some(issuer) | None                                          (FR-025, FR-048)
```

Neither path has a persistent state, a clock, a locale dependency or an I/O call. Both are pure and
deterministic (FR-015, Constitution II).
