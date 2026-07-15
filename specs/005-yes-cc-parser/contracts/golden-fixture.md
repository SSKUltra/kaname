# Contract: Golden-Fixture Schema — Yes vector

**Feature**: `005-yes-cc-parser` | **Date**: 2026-07-15
**Consumers**: `core/crates/kaname-core/tests/parity.rs`. Reuses the schema defined in
`../../002-icici-cc-parser/contracts/golden-fixture.md` and extended (with `period_start`) by
`../../003-hdfc-cc-parser/contracts/golden-fixture.md` (reused by `004-sbi-cc-parser`). This slice adds
**one Yes vector** and **no schema/harness change** — `period_start` is already present and asserted.

---

## Location & naming

```text
fixtures/<bank_code_lower>/<account_kind>/<name>.json
# this slice:
fixtures/yes/credit_card/basic.json   # ported from the web characterization vector
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
  scale is exact (`9000.00`) (FR-007, SC-005).
- `description_raw` MUST equal what the reader emits **exactly** (byte-for-byte); the terminal
  `Dr`/`Cr` marker and the amount are **not** part of it, but the merchant-category text **is**.
- `period_start`/`period_end` are ISO-8601 strings, re-parsed via `NaiveDate::parse_from_str`. Harness
  uses `#[serde(default)]` (already added by HDFC) so this is **not** a schema change.
- `card_last4` is `"6686"` here (the mask `3561XXXXXXXX6686` exposes four trailing digits).
- **No printed-total keys** appear anywhere in `expected` — the reconciliation totals are out of scope
  and structurally absent (FR-013, SC-013).

---

## The Yes `basic.json` vector (ported)

Ported from the web engine's synthetic Yes characterization vector; the `expected` values are the
locked characterization ground truth (rows/dates/amounts/direction/description, plus
`period_start`/`period_end` = `parse_date(g1/g2)` of the `<date> To <date>` line and
`card_last4 = find_last4(full_text, Some("Card Number"))`, per `yes_kiwi.py` `_enrich`). **Re-confirmed
by running the proposed `YesReader` against the real `kaname-core` helpers** (plan Summary; research
"Verification harness").

- `lines`:
  1. `29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr`
  2. `19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr`
- `full_text` contains `YES BANK KLICK`,
  `Statement for YES BANK Card Number 3561XXXXXXXX6686`,
  `Statement Period: 17/04/2026 To 16/05/2026`, then the two lines (`\n`-joined).
- `expected.rows`:
  1. `{ date: "2026-04-29", amount: "9000.00", direction: "Credit", currency: "INR", description_raw: "PAYMENT RECEIVED BBPS - Ref No: RT0001" }`
  2. `{ date: "2026-04-19", amount: "100.00",  direction: "Debit",  currency: "INR", description_raw: "UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores" }`
- `expected.period_start`: `"2026-04-17"`  ·  `expected.period_end`: `"2026-05-16"`
- `expected.card_last4`: `"6686"`  ·  `expected.errored_lines`: `[]`

**Exact fixture bytes to write in implementation** (`fixtures/yes/credit_card/basic.json`):

```json
{
  "_comment": "Synthetic Yes Bank (Kiwi) credit-card golden vector (no real data). Ported from the web engine's Yes characterization vector; values captured from a run of the proposed YesReader against the real kaname-core helpers. Single layout: DD/MM/YYYY <details ... Ref No> <Merchant Category> <amount> Dr|Cr, terminal two-letter Dr/Cr marker (Cr=Credit, Dr=Debit). card_last4 is 6686 because the masked card 3561XXXXXXXX6686 exposes four trailing digits. amount/date are strings (re-parsed to Decimal/NaiveDate — never float). Reconciliation carve-out: no printed_total_* keys (out of scope, FR-013).",
  "lines": [
    "29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr",
    "19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr"
  ],
  "full_text": "YES BANK KLICK\nStatement for YES BANK Card Number 3561XXXXXXXX6686\nStatement Period: 17/04/2026 To 16/05/2026\n29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr\n19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr",
  "expected": {
    "rows": [
      {
        "date": "2026-04-29",
        "amount": "9000.00",
        "direction": "Credit",
        "currency": "INR",
        "description_raw": "PAYMENT RECEIVED BBPS - Ref No: RT0001"
      },
      {
        "date": "2026-04-19",
        "amount": "100.00",
        "direction": "Debit",
        "currency": "INR",
        "description_raw": "UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores"
      }
    ],
    "period_start": "2026-04-17",
    "period_end": "2026-05-16",
    "card_last4": "6686",
    "errored_lines": []
  }
}
```

> **Direction note**: row 0 is a credit (terminal `Cr`) and row 1 a debit (terminal `Dr`) — direction
> comes from the statement's own marker, not the description. Row 0's description begins with
> `PAYMENT RECEIVED` (a credit keyword) which agrees with the `Cr` marker here, but the **marker** is
> the authority (a `Dr`-marked `PAYMENT RECEIVED …` row would be a debit — see the direction-from-marker
> contract test). Row 1's amount `100.00` and row 0's `9,000.00` normalize to strings `"100.00"` /
> `"9000.00"` (scale preserved; thousands separator stripped) (SC-004/005).
>
> **Merchant-category note**: row 1's `Miscellaneous Stores` (between the reference number and the
> amount) is part of `description_raw`, not a separate field (US1-AC3).

---

## Harness behaviour (contract)

1. Load `fixtures/yes/credit_card/basic.json` via `env!("CARGO_MANIFEST_DIR")` + `../../../fixtures`.
2. Call `read_yes_statement` over `lines` + `full_text`.
3. Assert `statement.lines.len() == expected.rows.len()`, then field-by-field per row (date, amount,
   direction, currency, description_raw), plus `period_start`, `period_end`, `card_last4`,
   `errored_lines`. Any mismatch **fails** (parity guard — FR-022, SC-009).
4. Re-run and assert identical output (determinism — SC-008).

This is delivered by **one new `Case` row** (`label: "Yes Bank"`, `parse: read_yes_statement`,
`rel_path: "yes/credit_card/basic.json"`) in the existing case table — **no harness struct or
assertion change** (the `period_start` field and its assertion already exist). A `yes_claims`
accept/reject test mirrors the existing `icici_claims`/`hdfc_claims`/`sbi_claims` tests. Because
`expected` has no printed-total keys, the harness structurally proves the reconciliation carve-out
(SC-013).

## Adding a future fixture
Drop `fixtures/<bank>/<kind>/<name>.json` and add one `Case` row (label, reader, relative path). The
schema is stable through `period_start`; no further harness code change is expected for subsequent
line-reader banks — Yes is the second proof (after SBI) that a new bank is a **one-fixture + one-row**
addition.
