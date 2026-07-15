# Contract: Golden-Fixture Schema — HDFC vectors (+ the `period_start` delta)

**Feature**: `003-hdfc-cc-parser` | **Date**: 2026-07-15
**Consumers**: `core/crates/kaname-core/tests/parity.rs`. Extends the reusable schema defined in
`../../002-icici-cc-parser/contracts/golden-fixture.md`. This slice adds **two HDFC vectors** and
**one backward-compatible field** (`period_start`) to the harness `Expected`.

---

## Location & naming

```text
fixtures/<bank_code_lower>/<account_kind>/<name>.json
# this slice:
fixtures/hdfc/credit_card/year_end.json    # ported from the web characterization vector
fixtures/hdfc/credit_card/monthly.json     # fabricated; expected CAPTURED from a live web-engine run
```

All data MUST be synthetic or fully redacted (fabricated merchant/amount/masked-PAN) — never real
account data (FR-027, SC-012).

---

## Schema (delta from the ICICI contract)

The schema is **unchanged except** for one optional field, so the ICICI fixture is untouched:

```json
{
  "lines": ["<one statement text line per element>", "..."],
  "full_text": "<the full extracted statement text, \\n-joined>",
  "expected": {
    "rows": [
      { "date": "YYYY-MM-DD", "amount": "<decimal STRING>", "direction": "Credit | Debit",
        "currency": "INR", "description_raw": "<exact engine output>" }
    ],
    "period_start": "YYYY-MM-DD | null",   // NEW — omitted by ICICI (defaults to null); REQUIRED for HDFC
    "period_end":   "YYYY-MM-DD | null",
    "card_last4":   "<4 digits> | null",
    "errored_lines": ["<raw unparseable line>", "..."]
  }
}
```

**Field rules** (unchanged from the ICICI contract, plus):
- `period_start` is a new ISO-8601 string, re-parsed via `NaiveDate::parse_from_str`. Harness:
  `#[serde(default)]` ⇒ absent = `None`. HDFC populates it; ICICI omits it (stays `None`). This is
  the **only** harness code change beyond the two case rows (plan Complexity Tracking, research D10).
- `amount` remains a **JSON string** (never a number) → `Decimal::from_str`, so no `f64` touches
  money and scale is exact (`10610.00`) (FR-009, SC-006).
- `description_raw` MUST equal what the reader emits **exactly** (byte-for-byte). For HDFC the
  trailing masked card number (year-end) and the leading `C` (monthly) are **not** part of it.

---

## The HDFC `year_end.json` vector (ported)

Ported from the web engine's `_HDFC_LINES`/`_HDFC_TEXT`
(`tests/unit/ingestion/statement_readers/test_cc_reader_characterization.py`); `expected`
captured from a live `hdfc.reader.read_lines(...)` run.

- `lines`:
  1. `16-Apr-2025 ONLINE TRF - PYMT RECD - THANK YOU 10,610.00 CR 526873XXXXXX9070`
  2. `04-Apr-2025 WWW EXAMPLE COM GURGAON 1,071.00 DR 526873XXXXXX9070`
- `full_text` contains `HDFC Bank Credit Cards`, `Account Summary for the period from APRIL-25 to
  MARCH-26`, `Card Number XXXX6873XXXXXX9070`, then the two lines (`\n`-joined).
- `expected.rows`:
  1. `{ date: "2025-04-16", amount: "10610.00", direction: "Credit", currency: "INR", description_raw: "ONLINE TRF - PYMT RECD - THANK YOU" }`
  2. `{ date: "2025-04-04", amount: "1071.00", direction: "Debit", currency: "INR", description_raw: "WWW EXAMPLE COM GURGAON" }`
- `expected.period_start`: `"2025-04-01"`  ·  `expected.period_end`: `"2026-03-31"`
- `expected.card_last4`: `"9070"`  ·  `expected.errored_lines`: `[]`

---

## The HDFC `monthly.json` vector (fabricated; expected captured live)

Entirely synthetic. The `expected` MUST be captured by running the web reader (never
hand-derived — FR-026); the values below are the captured ground truth to reproduce.

- `lines`:
  1. `15/05/2026| 13:30 EXAMPLE MERCHANT BANGALORE C 1,639.00`
  2. `20/05/2026| 09:05 CC PAYMENT RECEIVED + C 6,738.00`
- `full_text` contains `HDFC Bank Credit Card`, `Billing Period 15 May, 2026 - 14 Jun, 2026`,
  `Card Number XXXX1234XXXXXX5678`, then the two lines (`\n`-joined).
- `expected.rows`:
  1. `{ date: "2026-05-15", amount: "1639.00", direction: "Debit", currency: "INR", description_raw: "EXAMPLE MERCHANT BANGALORE" }`
  2. `{ date: "2026-05-20", amount: "6738.00", direction: "Credit", currency: "INR", description_raw: "CC PAYMENT RECEIVED" }`
- `expected.period_start`: `"2026-05-15"`  ·  `expected.period_end`: `"2026-06-14"`
- `expected.card_last4`: `"5678"`  ·  `expected.errored_lines`: `[]`

> **How the monthly ground truth was captured** (reproduce in implementation):
> ```python
> # in finance-tracker-phase/backend, with PYTHONPATH=$PWD and the project venv
> from app.services.ingestion.statement_readers import hdfc
> st = hdfc.reader.read_lines(monthly_lines, monthly_full_text)
> # → row0 Debit 1639.00 "EXAMPLE MERCHANT BANGALORE"; row1 Credit 6738.00 "CC PAYMENT RECEIVED";
> #   period_start 2026-05-15; period_end 2026-06-14; card_last4 5678
> ```
> Row 0 is a spend (no `+` ⇒ Debit); row 1 is a payment (leading `+` ⇒ Credit) — proving the
> monthly leading-`+` rule (SC-005, US3-S3/S4).

---

## Harness behavior (contract)

1. Load each `fixtures/hdfc/credit_card/<...>.json` via `env!("CARGO_MANIFEST_DIR")` +
   `../../../fixtures`.
2. Call `read_hdfc_statement` over `lines` + `full_text` (the **same** function for both vectors
   — the composite auto-selects the layout; SC-004).
3. Assert `statement.lines.len() == expected.rows.len()`, then field-by-field per row (date,
   amount, direction, currency, description_raw), plus `period_start`, `period_end`, `card_last4`,
   `errored_lines`. Any mismatch **fails** (parity guard — FR-025/026, SC-010).
4. Re-run and assert identical output (determinism — SC-009).

## Adding a future fixture
Drop `fixtures/<bank>/<kind>/<name>.json` and add one `Case` row (label, reader, relative path).
The schema is now stable through `period_start`; no further harness code change is expected for
subsequent line-reader banks.
