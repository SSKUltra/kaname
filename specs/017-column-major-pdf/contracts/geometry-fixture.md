# Contract: Geometry Fixtures (generated, synthetic, non-vacuous)

**Feature**: `017-column-major-pdf` | **Location**: `fixtures/geometry/*.json`
**Renderer + assertions**: `ios/Tests/GeometryFixtureTests.swift` (+ a small renderer helper)

This is the evidence format for the slice. It exists because **every existing fixture supplies
pre-split `lines`** and therefore tests the readers while *assuming* the extraction that actually
failed. A geometry fixture is rendered into a real PDF, opened by the real platform PDF engine, and
run through the real dispatcher and the real reader — so the extractor is under test too.

Grounded in `docs/adr/0004-unknown-bank-ingestion.md` § *Amendment (2026-08-13)*: **a signature
generates a fixture**. A signature carries no values, so a document rendered from it is *synthetic
by construction* — nothing is stripped, so nothing can survive stripping.

---

## Schema

```jsonc
{
  "_comment": "Synthetic. Fabricated merchants/amounts/dates/card numbers. Geometry mirrors the <issuer> column-major layout. Header literals are the reader's own published claim markers.",
  "issuer_id": "YES_KIWI_CARD",
  "kind": "credit_card",                   // credit_card | bank_account
  "signature": {
    "page_size": [595.0, 842.0],           // A4 points
    "font_size": 9.0,
    "row_pitch": 21.3,                     // baseline-to-baseline, points
    "first_row_y": 520.0,
    "date_format": "DD/MM/YYYY",           // DD/MM/YYYY | DD/MM/YY | DD-MMM-YYYY
    "columns": [
      { "role": "date",        "x": 40.0,  "align": "left"  },
      { "role": "description", "x": 96.0,  "align": "left"  },
      { "role": "amount",      "x": 470.0, "align": "right" },
      { "role": "direction",   "x": 520.0, "align": "left"  }
    ]
  },
  "header_lines": [                        // drawn above the table; claim markers live here
    "YES BANK KLICK",
    "Statement for YES BANK Card Number 3561XXXXXXXX6686",
    "Statement Period: 17/04/2026 To 16/05/2026"
  ],
  "footer_lines": [
    "Current Purchases / Cash Advance & Other Charges : Rs. 100.00 Dr",
    "Payment & Credits Received : Rs. 9,000.00 Cr"
  ],
  "rows": [
    { "date": "29/04/2026", "description": "PAYMENT RECEIVED BBPS - Ref No: RT0001", "amount": "9,000.00", "direction": "Cr" },
    { "date": "19/04/2026", "description": "UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores", "amount": "100.00", "direction": "Dr" }
  ],
  "expected": {
    "issuer_id": "YES_KIWI_CARD",
    "transactions": [
      { "date": "2026-04-29", "amount": "9000.00", "direction": "Credit", "description_raw": "PAYMENT RECEIVED BBPS - Ref No: RT0001" },
      { "date": "2026-04-19", "amount": "100.00",  "direction": "Debit",  "description_raw": "UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores" }
    ],
    "legacy_max_transactions": 0           // non-vacuity: the pre-slice path must read at most this many
  }
}
```

Bank-account fixtures use the ledger roles instead: `date`, `description`, `reference`,
`withdrawal`, `deposit`, `balance`, and their `expected.transactions` additionally declare the
printed opening/closing balances the balance chain must recover.

---

## Rendering rules (what makes the fixture reproduce the bug)

| # | Rule | Why |
|---|---|---|
| R1 | Cells are drawn **column-major** — every cell of column 1 top-to-bottom, then column 2, and so on. | This is what makes the platform text layer emit the page column-major. Drawing row-major would produce a fixture that passes both before and after the fix, proving nothing. |
| R2 | Each cell is drawn at its column's `x` and its row's `y = first_row_y - index * row_pitch`, with the declared font size. | Reproduces real column x-positions and row bands (FR-036). |
| R3 | Header and footer lines are drawn as ordinary single-column text lines. | They carry the claim markers, and they must be recognisable through the reshaping (US2). |
| R4 | The PDF is rendered to a temporary file at test time and deleted afterwards. | No binary artefact enters the repository. |
| R5 | At least one fixture per kind uses a `row_pitch` tight enough that the text layer *merges* adjacent rows, **and** a column-major draw order. | FR-030 — both hazards in one document. |

---

## Assertions every fixture must pass

| # | Assertion | Requirement |
|---|---|---|
| A1 | `detectIssuer(fullText:)` over the extracted text returns `expected.issuer_id`. | US2, FR-013 |
| A2 | The parsed transactions equal `expected.transactions` exactly — same count, order, dates, exact decimals, directions, descriptions. | FR-017, FR-018, SC-001 |
| A3 | The count does not exceed the number of printed `rows`. | FR-006, SC-003 |
| A4 | **Non-vacuity**: parsing the *legacy* extraction of the same document — `PDFKitStatementTextExtractor.split(fullText)`, i.e. the text layer's own newlines — yields at most `legacy_max_transactions`, which must be **strictly less** than `expected.transactions.count`. | FR-037, SC-011 |
| A5 | Importing the same rendered document twice yields byte-identical lines and identical transactions. | FR-009, SC-007 |
| A6 | Every fixture declares at least one debit and at least one credit, and every direction matches. | FR-019, SC-006 |
| A7 | The extracted lines lose no non-whitespace character of the page text. | FR-007 |

A4 is what converts a one-time observation into a standing gate: a fixture that passes against the
pre-slice extractor is deleted or fixed, never kept.

---

## Coverage required by FR-038

| Issuer | Kind | Date format | Notes |
|---|---|---|---|
| `AU_BANK` | bank_account | DD/MM/YYYY | Also carries the C5 header phrase once supplied (research R15) |
| `FEDERAL_BANK` | bank_account | DD/MM/YYYY | |
| `HDFC_BANK` | bank_account | DD/MM/YY | Header exercises `WithdrawalAmt` / `Statementof account` whitespace tolerance |
| `ICICI_BANK` | bank_account | DD/MM/YYYY | Multi-page (proves FR-008 beyond page 1) |
| `FEDERAL_SCAPIA_CARD` | credit_card | DD/MM/YYYY | |
| `HDFC_SWIGGY_CARD` | credit_card | DD-MMM-YYYY | Descriptions repeat `Swiggy` — must not identify by spend (FR-047) |
| `ICICI_AMAZONPAY_CARD` | credit_card | DD/MM/YYYY | |
| `IOB_RUPAY_CARD` | credit_card | DD-MMM-YYYY | No date-bearing line in the emitted text layer |
| `SBI_CASHBACK_CARD` | credit_card | DD/MM/YYYY | Descriptions name rival SBI products (FR-044) |
| `YES_KIWI_CARD` | credit_card | DD/MM/YYYY | The validated reference case: 0 of 4 rows pre-slice |

Plus two non-issuer vectors:

- **Both-hazards** (R5 above) — FR-030.
- **Cross-bank false claim** — a statement for issuer X whose descriptions name issuer Y, modelled
  on the measured AU/HDFC case; must resolve to X (FR-014, gate G7).

---

## Privacy rules (non-negotiable)

| # | Rule | Requirement |
|---|---|---|
| P1 | Every merchant, amount, date, account number and card number is **fabricated**. | FR-036, SC-010 |
| P2 | Header and marker literals come from the reader's **own published claim markers**, never harvested from a contributor's or holder's document. | ADR-0004 amendment, FR-039 |
| P3 | Every added file is reviewed to confirm it carries no token lifted from a real statement — including in `_comment` fields and commit messages. | FR-039 |
| P4 | No real statement, and no fragment of one, enters the repository in any form. | FR-039 |
| P5 | Card numbers are written masked (`3561XXXXXXXX6686` style) and the last four are invented. | FR-036 |
