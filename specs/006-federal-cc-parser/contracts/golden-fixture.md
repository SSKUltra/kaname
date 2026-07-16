# Contract: Golden-Fixture Schema — Federal vector

**Feature**: `006-federal-cc-parser` | **Date**: 2026-07-16
**Consumers**: `core/crates/kaname-core/tests/parity.rs`. Reuses the schema defined in
`../../002-icici-cc-parser/contracts/golden-fixture.md` and extended (with `period_start`) by
`../../003-hdfc-cc-parser/contracts/golden-fixture.md` (reused by `004-sbi-cc-parser` and
`005-yes-cc-parser`). This slice adds **one Federal vector** and **no schema/harness change** —
`period_start` is already present and asserted.

---

## Location & naming

```text
fixtures/<bank_code_lower>/<account_kind>/<name>.json
# this slice:
fixtures/federal/credit_card/basic.json   # ported from the web characterization vector
```

All data MUST be synthetic or fully redacted (fabricated merchant/amount/masked-PAN) — never real
account data (FR-024, SC-002).

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
  scale is exact (`324.45`, `2353.13`) (FR-009, SC-006).
- `description_raw` MUST equal what the reader emits **exactly** (byte-for-byte); the `HH:MM` time, the
  leading `+`, the `₹`, and the amount are **not** part of it.
- `period_start`/`period_end` are ISO-8601 strings, re-parsed via `NaiveDate::parse_from_str`. Harness
  uses `#[serde(default)]` (already added by HDFC) so this is **not** a schema change.
- `card_last4` is `"4836"` here (the fully-masked PAN `XXXXXXXXXXXX4836`, recovered by the **un-anchored**
  `find_last4(full_text, None)`).
- **Character encoding**: the fixture strings use the **actual** middle-dot **U+00B7** (`·`) as the
  date/time separator and the **actual** rupee sign **U+20B9** (`₹`) before each amount — not escapes
  or ASCII substitutes. The file is UTF-8.

---

## The Federal `basic.json` vector (ported)

Ported from the web engine's synthetic Federal characterization vector; the `expected` values are the
locked characterization ground truth (rows/dates/amounts/direction/description, plus
`period_start`/`period_end` = `parse_date(g1/g2)` of the `_CYCLE_RE` match and
`card_last4 = find_last4(full_text, None)`, per `federal_scapia.py` `_enrich`). **Re-confirmed by
running the proposed `FederalReader` against the real `kaname-core` helpers** (plan Summary; research
"Verification harness").

- `lines`:
  1. `29-04-2026·16:18 Billpayment Payment +₹324.45`
  2. `24-04-2026·06:03 ExampleMerchantTokyo ₹2,353.13`
- `full_text` contains `Scapia by Federal Bank`, then
  `XXXXXXXXXXXX4836 20Apr2026-19May2026`, then the two lines (`\n`-joined).
- `expected.rows`:
  1. `{ date: "2026-04-29", amount: "324.45",  direction: "Credit", currency: "INR", description_raw: "Billpayment Payment" }`
  2. `{ date: "2026-04-24", amount: "2353.13", direction: "Debit",  currency: "INR", description_raw: "ExampleMerchantTokyo" }`
- `expected.period_start`: `"2026-04-20"`  ·  `expected.period_end`: `"2026-05-19"`
- `expected.card_last4`: `"4836"`  ·  `expected.errored_lines`: `[]`

**Exact fixture bytes to write in implementation** (`fixtures/federal/credit_card/basic.json` — the `·`
below is U+00B7 and the `₹` is U+20B9):

```json
{
  "_comment": "Synthetic Federal Bank / Scapia credit-card golden vector (no real data). Ported from the web engine's Federal characterization vector; values captured from a run of the proposed FederalReader against the real kaname-core helpers. Single layout: DD-MM-YYYY<middot U+00B7>HH:MM <description> [+]<rupee U+20B9><amount>. Direction: leading '+' => Credit (Scapia notation), else the shared description-language classifier (else Debit). card_last4 is 4836 from the fully-masked PAN XXXXXXXXXXXX4836 via the UN-ANCHORED find_last4 (no textual anchor). Billing cycle 20Apr2026-19May2026 parses via the shared %d%b%Y format. amount/date are strings (re-parsed to Decimal/NaiveDate - never float). The middot separator and rupee sign are the actual U+00B7 / U+20B9 characters.",
  "lines": [
    "29-04-2026·16:18 Billpayment Payment +₹324.45",
    "24-04-2026·06:03 ExampleMerchantTokyo ₹2,353.13"
  ],
  "full_text": "Scapia by Federal Bank\nXXXXXXXXXXXX4836 20Apr2026-19May2026\n29-04-2026·16:18 Billpayment Payment +₹324.45\n24-04-2026·06:03 ExampleMerchantTokyo ₹2,353.13",
  "expected": {
    "rows": [
      {
        "date": "2026-04-29",
        "amount": "324.45",
        "direction": "Credit",
        "currency": "INR",
        "description_raw": "Billpayment Payment"
      },
      {
        "date": "2026-04-24",
        "amount": "2353.13",
        "direction": "Debit",
        "currency": "INR",
        "description_raw": "ExampleMerchantTokyo"
      }
    ],
    "period_start": "2026-04-20",
    "period_end": "2026-05-19",
    "card_last4": "4836",
    "errored_lines": []
  }
}
```

> **Direction note**: row 0 is a credit **because of the leading `+`** (`+₹324.45`) — its description
> `Billpayment Payment` is **not** a recognized credit phrase, so without the `+` it would classify as a
> debit; the `+` is decisive (US3-AC1). Row 1 has **no** `+` and no credit words → debit via the shared
> classifier's default (US3-AC2). Direction is never taken from the amount's sign/magnitude (SC-004).
>
> **Amount note**: `+₹324.45` and `₹2,353.13` normalize to strings `"324.45"` / `"2353.13"` (the `₹`,
> the `+`, and the thousands comma stripped; scale preserved) (SC-006).
>
> **Separator note**: the `·` between the date and `HH:MM` is the middle dot U+00B7 and is matched by
> the row regex's unescaped `.` (any single char) — the row is recognized encoding-robustly (FR-004,
> SC-005), and the `16:18`/`06:03` time never appears in the parsed date or description.

---

## Harness behaviour (contract)

1. Load `fixtures/federal/credit_card/basic.json` via `env!("CARGO_MANIFEST_DIR")` + `../../../fixtures`.
2. Call `read_federal_statement` over `lines` + `full_text`.
3. Assert `statement.lines.len() == expected.rows.len()`, then field-by-field per row (date, amount,
   direction, currency, description_raw), plus `period_start`, `period_end`, `card_last4`,
   `errored_lines`. Any mismatch **fails** (parity guard — FR-023, SC-010).
4. Re-run and assert identical output (determinism — SC-009).

This is delivered by **one new `Case` row** (`label: "Federal"`, `parse: read_federal_statement`,
`rel_path: "federal/credit_card/basic.json"`) in the existing case table — **no harness struct or
assertion change** (the `period_start` field and its assertion already exist). A `federal_claims`
accept/reject test mirrors the existing `icici_claims`/`hdfc_claims`/`sbi_claims`/`yes_claims` tests.
With Federal green, all five credit-card issuers reproduce their golden vectors — the set is complete
(SC-012).

## Adding a future fixture
Drop `fixtures/<bank>/<kind>/<name>.json` and add one `Case` row (label, reader, relative path). The
schema is stable through `period_start`; Federal is the **third** proof (after SBI and Yes) — and the
final credit-card issuer — that a new bank is a **one-fixture + one-row** addition.
