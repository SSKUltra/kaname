# Contract: Golden-Fixture Schema — IOB vector

**Feature**: `011-iob-cc-reader` | **Date**: 2026-07-17
**Consumers**: `core/crates/kaname-core/tests/parity.rs`. Reuses the schema defined in
`../../002-icici-cc-parser/contracts/golden-fixture.md` and extended (with `period_start`,
`#[serde(default)]`) by `../../003-hdfc-cc-parser/contracts/golden-fixture.md` (reused by
`004`/`005`/`006`). This slice adds **one IOB vector** and **no schema/harness change** — and, like the
ICICI vector, **omits** `period_start` (→ `None`).

---

## Location & naming

```text
fixtures/<bank_code_lower>/<account_kind>/<name>.json
# this slice:
fixtures/iob/credit_card/basic.json   # ported from the web characterization vector
```

All data MUST be synthetic or fully redacted (fabricated merchants/amounts/masked-PAN) — never real
account data (FR-025, SC-004).

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
    "period_end":   "YYYY-MM-DD | null",
    "card_last4":   "<4 digits> | null",
    "errored_lines": ["<raw unparseable line>", "..."]
  }
}
```

**Field rules**:
- `amount` is a **JSON string** (never a number) → `Decimal::from_str`, so no `f64` touches money and
  scale is exact (`1000.00`, `3500.00`) (FR-007, SC-006).
- `direction` is the enum variant name `"Credit"` / `"Debit"` (no serde rename — `model.rs:12–15`).
- `description_raw` MUST equal what the reader emits **exactly** (byte-for-byte); the terminal `Dr`/`Cr`
  marker and the amount are **not** part of it.
- **`period_start` is OMITTED** — IOB prints no period range, so it is absent. `Expected.period_start`
  is `#[serde(default)]`, so omission deserializes to `None`; the harness then asserts
  `statement.period_start == None` (SC-003). (Equivalently `"period_start": null` — omission is used
  here to mirror the ground-truth vector and the ICICI precedent.)
- `period_end` / `card_last4` are required keys (the harness fields are not `#[serde(default)]`):
  `period_end = "2026-04-20"` (from `Stmt Date : 20-APR-2026`), `card_last4 = "0042"` (from the inline
  masked PAN `123456XXXXXX0042`).
- **No printed-total keys** appear anywhere in `expected` — the reconciliation totals are out of scope
  and structurally absent (FR-013, SC-013). Note the `full_text` **does** include the `ACCOUNT SUMMARY`
  block and its values row; the fixture proves those figures are ignored.

---

## The IOB `basic.json` vector (ported)

Ported from the web engine's synthetic IOB characterization vector; the `expected` values are the
locked characterization ground truth (rows/dates/amounts/direction/description, plus `period_end =
parse_date(Stmt Date)` and `card_last4 = find_last4(full_text, Some("Credit Card Number"))`, per
`iob.py` `_enrich`). The two IOB-specific derivations were **re-confirmed by running the real
`kaname-core` helpers** (plan Summary; research D4/D7 + "Verification harness"): uppercase-month `%b`
parsing and `find_last4 → "0042"` (no bleed from the adjacent limits).

- `lines` (15 — the non-empty stripped `splitlines()` of `full_text`; only the two `DD-MON-YYYY … Dr|Cr`
  lines match `_ROW_RE`):
  header/metadata/summary lines + `31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr` +
  `04-APR-2026 ExampleStorePurchase 3,500.00 Dr`.
- `full_text` contains the `INDIAN OVERSEAS BANK …` header, `Stmt Date: 20-APR-2026`, the
  `iobnet.co.in` e-mail (claim marker), `Credit Card Number …` + inline `123456XXXXXX0042 16000 25091.5`,
  the `ACCOUNT SUMMARY` block (present but not scraped), then the two transaction lines and the
  `Total Purchase` / end-of-statement markers (`\n`-joined, trailing `\n`).
- `expected.rows`:
  1. `{ date: "2026-03-31", amount: "1000.00", direction: "Credit", currency: "INR", description_raw: "ExampleRefundMerchant" }`
  2. `{ date: "2026-04-04", amount: "3500.00", direction: "Debit",  currency: "INR", description_raw: "ExampleStorePurchase" }`
- `expected.period_end`: `"2026-04-20"`  ·  `expected.card_last4`: `"0042"`  ·
  `expected.errored_lines`: `[]`  ·  `period_start`: **omitted → `None`**

**Exact fixture bytes to write in implementation** (`fixtures/iob/credit_card/basic.json`):

```json
{
  "_comment": "Synthetic Indian Overseas Bank (IOB) credit-card golden vector (no real data). Ported from the web engine's IOB characterization vector; the two IOB-specific derivations (uppercase-month %d-%b-%Y parsing; inline masked-PAN find_last4) were confirmed against the real kaname-core helpers. Single layout: DD-MON-YYYY <merchant> <amount> Dr|Cr, uppercase month (MAR/APR) parsed by the existing case-insensitive %d-%b-%Y; terminal two-letter Dr/Cr marker (Cr=Credit, Dr=Debit). period_end 2026-04-20 comes from 'Stmt Date: 20-APR-2026' (billing-cycle end); IOB prints no period range so period_start is omitted (deserializes to None). card_last4 is 0042 from the inline masked PAN 123456XXXXXX0042 (anchored on 'Credit Card Number'), never digits from the adjacent limits 16000 / 25091.5. amount/date are strings (re-parsed to Decimal/NaiveDate - never float). Reconciliation carve-out: the ACCOUNT SUMMARY printed totals are present in full_text but intentionally NOT modeled (no printed_total_* keys; out of scope, FR-013).",
  "lines": [
    "Monthly Statement",
    "INDIAN OVERSEAS BANK CREDIT CARD DIVISION",
    "Stmt No: 2026CC0000001 Stmt Date: 20-APR-2026 E-Mail: creditcard@iobnet.co.in",
    "YOUR CREDIT CARD STATEMENT",
    "Credit Card Number Cash Limit (as part of credit limit) Available Credit Limit",
    "123456XXXXXX0042 16000 25091.5",
    "ACCOUNT SUMMARY",
    "Previous Balance Payment / Credits Purchases / Debits Fee, Taxes and Interest Charge Total Outstanding",
    "- + + =",
    "345.50 1,000.00 3,500.00 0 2,845.50",
    "Date Transaction Details Amount Rs.",
    "31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr",
    "04-APR-2026 ExampleStorePurchase 3,500.00 Dr",
    "Total Purchase : 2845.50",
    "*********** End of Statement ***********"
  ],
  "full_text": "Monthly Statement\nINDIAN OVERSEAS BANK CREDIT CARD DIVISION\nStmt No: 2026CC0000001 Stmt Date: 20-APR-2026 E-Mail: creditcard@iobnet.co.in\nYOUR CREDIT CARD STATEMENT\nCredit Card Number Cash Limit (as part of credit limit) Available Credit Limit\n123456XXXXXX0042 16000 25091.5\nACCOUNT SUMMARY\nPrevious Balance Payment / Credits Purchases / Debits Fee, Taxes and Interest Charge Total Outstanding\n- + + =\n345.50 1,000.00 3,500.00 0 2,845.50\nDate Transaction Details Amount Rs.\n31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr\n04-APR-2026 ExampleStorePurchase 3,500.00 Dr\nTotal Purchase : 2845.50\n*********** End of Statement ***********\n",
  "expected": {
    "rows": [
      {
        "date": "2026-03-31",
        "amount": "1000.00",
        "direction": "Credit",
        "currency": "INR",
        "description_raw": "ExampleRefundMerchant"
      },
      {
        "date": "2026-04-04",
        "amount": "3500.00",
        "direction": "Debit",
        "currency": "INR",
        "description_raw": "ExampleStorePurchase"
      }
    ],
    "period_end": "2026-04-20",
    "card_last4": "0042",
    "errored_lines": []
  }
}
```

> **Direction note**: row 0 is a credit (terminal `Cr`) and row 1 a debit (terminal `Dr`) — direction
> comes from the statement's own marker, not the amount. The `Cr` refund is `1000.00` and the `Dr`
> purchase is the larger `3500.00`: **magnitude does not decide direction** (SC-005). Amounts
> `1,000.00` / `3,500.00` normalize to strings `"1000.00"` / `"3500.00"` (scale preserved; thousands
> separator stripped) (SC-006).
>
> **card_last4 note**: `123456XXXXXX0042` is printed **inline** with the limit figures
> `16000 25091.5`; `find_last4` returns `"0042"` (the masked PAN's trailing four), never `6000`/`5091`
> from the limits (D7, verified).
>
> **period_start note**: omitted on purpose (IOB prints no range). Do **not** add a fabricated start
> date; the harness asserts `period_start == None` via `#[serde(default)]` (SC-003).

---

## Harness behaviour (contract)

1. Load `fixtures/iob/credit_card/basic.json` via `env!("CARGO_MANIFEST_DIR")` + `../../../fixtures`.
2. Call `read_iob_statement` over `lines` + `full_text`.
3. Assert `statement.lines.len() == expected.rows.len()` (== 2), then field-by-field per row (date,
   amount, direction, currency, description_raw), plus `period_start` (**None**), `period_end`,
   `card_last4`, and `errored_lines` (**empty**). Any mismatch **fails** (parity guard — FR-024, SC-011).
   `printed_opening_balance`/`printed_closing_balance` are asserted `None` (default) by the shared
   harness.
4. Re-run and assert identical output (determinism — SC-010).

This is delivered by **one new `Case` row** (`label: "IOB"`, `parse: read_iob_statement`,
`rel_path: "iob/credit_card/basic.json"`) placed with the credit-card cases — **no harness struct or
assertion change**. An `iob_claims_accepts_own_document_and_rejects_others` test mirrors the existing
`sbi_claims`/`yes_claims`/`federal_claims` tests. Because `expected` has no printed-total keys and omits
`period_start`, the harness structurally proves both the reconciliation carve-out (SC-013) and the
absent period start (SC-003).

## Adding a future fixture
Drop `fixtures/<bank>/<kind>/<name>.json` and add one `Case` row (label, reader, relative path). The
schema is stable through `period_start`; IOB is the sixth credit-card proof that a new bank is a
**one-fixture + one-row** addition — and the final credit-card reader, completing the 10-reader set.
