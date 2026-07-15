# Contract: Golden-Fixture Schema — SBI vector

**Feature**: `004-sbi-cc-parser` | **Date**: 2026-07-15
**Consumers**: `core/crates/kaname-core/tests/parity.rs`. Reuses the schema defined in
`../../002-icici-cc-parser/contracts/golden-fixture.md` and extended (with `period_start`) by
`../../003-hdfc-cc-parser/contracts/golden-fixture.md`. This slice adds **one SBI vector** and
**no schema/harness change** — `period_start` is already present and asserted.

---

## Location & naming

```text
fixtures/<bank_code_lower>/<account_kind>/<name>.json
# this slice:
fixtures/sbi_card/credit_card/basic.json   # ported from the web characterization vector
```

All data MUST be synthetic or fully redacted (fabricated merchant/amount/masked-PAN) — never real
account data (FR-023, SC-012).

---

## Schema (unchanged — reuses the period_start-stable harness)

```json
{
  "lines": ["<one statement text line per element>", "..."],
  "full_text": "<the full extracted statement text, \\n-joined>",
  "expected": {
    "rows": [
      { "date": "YYYY-MM-DD", "amount": "<decimal STRING>", "direction": "Credit | Debit",
        "currency": "INR", "description_raw": "<exact engine output>" }
    ],
    "period_start": "YYYY-MM-DD | null",
    "period_end":   "YYYY-MM-DD | null",
    "card_last4":   "<4 digits> | null",
    "errored_lines": ["<raw unparseable line>", "..."]
  }
}
```

**Field rules**:
- `amount` is a **JSON string** (never a number) → `Decimal::from_str`, so no `f64` touches money and
  scale is exact (`82900.00`) (FR-007, SC-005).
- `description_raw` MUST equal what the reader emits **exactly** (byte-for-byte); the terminal
  `C`/`D` marker and the amount are **not** part of it.
- `period_start`/`period_end` are ISO-8601 strings, re-parsed via `NaiveDate::parse_from_str`.
  Harness uses `#[serde(default)]` (already added by HDFC) so this is **not** a schema change.
- `card_last4` is `null` here (the masked card exposes only two trailing digits — never fabricated).

---

## The SBI `basic.json` vector (ported)

Ported from the web engine's `_SBI_LINES`/`_SBI_TEXT`
(`tests/unit/ingestion/statement_readers/test_cc_reader_characterization.py`); the `expected` values
are the locked characterization ground truth (rows/dates/amounts/last4/period_end confirmed by the
web test; `period_start` is `parse_date(g1)` of the same `Statement Period` line, per `sbi_card.py`
`_enrich`). Re-confirmed by running the proposed `SbiReader` against the real `kaname-core` helpers
(plan Summary; research "Verification harness").

- `lines`:
  1. `21 Apr 26 CARD CASHBACK CREDIT 643.00 C`
  2. `20 May 26 APPLE INDIA STORE MUMBAI IN 82,900.00 D`
- `full_text` contains `GSTIN of SBI Card`, `Credit Card Number XXXX XXXX XXXX XX61`,
  `for Statement Period: 22 Apr 26 to 21 May 26`, then the two lines (`\n`-joined).
- `expected.rows`:
  1. `{ date: "2026-04-21", amount: "643.00",   direction: "Credit", currency: "INR", description_raw: "CARD CASHBACK CREDIT" }`
  2. `{ date: "2026-05-20", amount: "82900.00", direction: "Debit",  currency: "INR", description_raw: "APPLE INDIA STORE MUMBAI IN" }`
- `expected.period_start`: `"2026-04-22"`  ·  `expected.period_end`: `"2026-05-21"`
- `expected.card_last4`: `null`  ·  `expected.errored_lines`: `[]`

**Exact fixture bytes to write in implementation** (`fixtures/sbi_card/credit_card/basic.json`):

```json
{
  "_comment": "Synthetic SBI Card credit-card golden vector (no real data). Ported from the web engine's test_cc_reader_characterization.py _SBI case; values captured from sbi_card.reader.read_lines. Single layout: DD Mon YY <details> <amount> C|D, terminal single-letter C/D marker (C=Credit, D=Debit). card_last4 is null because the masked card XXXX XXXX XXXX XX61 exposes only two trailing digits (never fabricated). amount/date are strings (re-parsed to Decimal/NaiveDate — never float).",
  "lines": [
    "21 Apr 26 CARD CASHBACK CREDIT 643.00 C",
    "20 May 26 APPLE INDIA STORE MUMBAI IN 82,900.00 D"
  ],
  "full_text": "GSTIN of SBI Card\nCredit Card Number XXXX XXXX XXXX XX61\nfor Statement Period: 22 Apr 26 to 21 May 26\n21 Apr 26 CARD CASHBACK CREDIT 643.00 C\n20 May 26 APPLE INDIA STORE MUMBAI IN 82,900.00 D",
  "expected": {
    "rows": [
      {
        "date": "2026-04-21",
        "amount": "643.00",
        "direction": "Credit",
        "currency": "INR",
        "description_raw": "CARD CASHBACK CREDIT"
      },
      {
        "date": "2026-05-20",
        "amount": "82900.00",
        "direction": "Debit",
        "currency": "INR",
        "description_raw": "APPLE INDIA STORE MUMBAI IN"
      }
    ],
    "period_start": "2026-04-22",
    "period_end": "2026-05-21",
    "card_last4": null,
    "errored_lines": []
  }
}
```

> **Direction note**: row 0 is a credit (terminal `C`) and row 1 a debit (terminal `D`) — direction
> comes from the statement's own marker, not the description (row 0's description even contains the
> word "CREDIT", which is irrelevant to the classification). Row 1's amount `82,900.00` is written
> with a thousands separator in the input and normalizes to the string `"82900.00"` (scale
> preserved) in `expected` (SC-004/005).

---

## Harness behavior (contract)

1. Load `fixtures/sbi_card/credit_card/basic.json` via `env!("CARGO_MANIFEST_DIR")` +
   `../../../fixtures`.
2. Call `read_sbi_statement` over `lines` + `full_text`.
3. Assert `statement.lines.len() == expected.rows.len()`, then field-by-field per row (date, amount,
   direction, currency, description_raw), plus `period_start`, `period_end`, `card_last4`,
   `errored_lines`. Any mismatch **fails** (parity guard — FR-022, SC-009).
4. Re-run and assert identical output (determinism — SC-008).

This is delivered by **one new `Case` row** (`label: "SBI"`, `parse: read_sbi_statement`,
`rel_path: "sbi_card/credit_card/basic.json"`) in the existing case table — **no harness struct or
assertion change** (the `period_start` field and its assertion already exist). An `sbi_claims`
accept/reject test mirrors the existing `icici_claims`/`hdfc_claims` tests.

## Adding a future fixture
Drop `fixtures/<bank>/<kind>/<name>.json` and add one `Case` row (label, reader, relative path). The
schema is stable through `period_start`; no further harness code change is expected for subsequent
line-reader banks — SBI is the proof that a new bank is a **one-fixture + one-row** addition.
