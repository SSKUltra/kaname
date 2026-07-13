# Contract: Golden-Fixture Schema (reusable parity harness)

**Feature**: `002-icici-cc-parser` | **Date**: 2026-07-08
**Consumers**: `core/crates/kaname-core/tests/parity.rs` (this slice) and every future reader
port. This defines the JSON schema the reusable parity harness loads. It is the on-device
equivalent of the web engine's characterization vectors (Constitution Principle V).

---

## Location & naming

```text
fixtures/<bank_code_lower>/<account_kind>/<name>.json
# this slice:
fixtures/icici/credit_card/basic.json
```

Refines `fixtures/README.md` for **line-based** readers: a single self-contained JSON bundles
input + expected. Word x-positions (README's `input/`) are **not** needed for CC line readers —
they belong to the future bank-ledger reader. All data MUST be synthetic or fully redacted
(fabricated merchant/amount/masked-PAN) — never real account data (FR-022, SC-003).

---

## Schema

```json
{
  "lines": ["<one statement text line per element>", "..."],
  "full_text": "<the full extracted statement text, \\n-joined>",
  "expected": {
    "rows": [
      {
        "date": "YYYY-MM-DD",
        "amount": "<decimal as STRING, scale preserved, e.g. \"10.20\">",
        "direction": "Credit | Debit",
        "currency": "INR",
        "description_raw": "<exact engine output, incl. any leading serial>"
      }
    ],
    "period_end": "YYYY-MM-DD | null",
    "card_last4": "<4 digits> | null",
    "errored_lines": ["<raw unparseable line>", "..."]
  }
}
```

**Field rules**
- `amount` is a **JSON string**, re-parsed via `rust_decimal::Decimal::from_str` — **never** a
  JSON number, so no `f64` ever touches money and scale (`10.20`) is exact (FR-007, SC-005).
- `date` / `period_end` are ISO-8601 strings re-parsed via `NaiveDate::parse_from_str`.
- `direction` deserializes into the `Direction` enum (`"Credit"`/`"Debit"`).
- `description_raw` MUST equal what the reader emits **exactly** — for ICICI this **includes the
  leading serial** (e.g. `"4262 BBPS Payment received"`); see `research.md` D4.
- `errored_lines` defaults to `[]` (via `#[serde(default)]`) when omitted.

---

## The ICICI `basic.json` vector (this slice)

- `lines`:
  1. `29/04/2026 4262 BBPS Payment received 0 13,628.36 CR`
  2. `26/05/2026 1814 Fee on gaming transaction 0 10.20`
- `full_text` contains `ICICI Bank`, `Statement Date May 28, 2026`, `4315XXXXXXXX1002`, then the
  two lines (`\n`-joined) — mirroring the web engine's `_ICICI_TEXT`.
- `expected.rows`:
  1. `{ date: "2026-04-29", amount: "13628.36", direction: "Credit", currency: "INR", description_raw: "4262 BBPS Payment received" }`
  2. `{ date: "2026-05-26", amount: "10.20", direction: "Debit", currency: "INR", description_raw: "1814 Fee on gaming transaction" }`
- `expected.period_end`: `"2026-05-28"`
- `expected.card_last4`: `"1002"`
- `expected.errored_lines`: `[]`

> These values were captured from a **live run of the web-engine reader** (not hand-derived):
> `icici.reader.read_lines(_ICICI_LINES, _ICICI_TEXT)`.

---

## Harness behavior (contract)

1. Load `fixtures/<...>.json` (path via `env!("CARGO_MANIFEST_DIR")` + `../../../fixtures`).
2. Call the reader over `lines` + `full_text`.
3. Assert `statement.lines.len() == expected.rows.len()`, then field-by-field equality per row
   (date, amount, direction, currency, description_raw), plus `period_end`, `card_last4`,
   `errored_lines`. Any mismatch **fails** the test (parity guard — FR-021, SC-009).
4. Re-run and assert identical output (determinism — SC-008).

## Adding a future fixture
Drop a new `fixtures/<bank>/<kind>/<name>.json` and register it in the harness's case table
(label, reader, relative path). No harness code change beyond one row — the schema is stable.
