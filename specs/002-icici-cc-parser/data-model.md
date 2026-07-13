# Phase 1 — Data Model: ICICI Credit-Card Parser

**Feature**: `002-icici-cc-parser` | **Date**: 2026-07-08
**Scope**: The types introduced/reused by this slice, their fields, validation rules, and how
they cross the UniFFI boundary. Ported from the web engine's `base.py` (records) with only the
fields this slice needs (reconciliation/balance fields are out of scope — omitted).

---

## Entities

### `Direction` (reused, unchanged) — `uniffi::Enum`

`enum Direction { Debit, Credit }` — already defined in `model.rs`. Carries polarity so amount
sign is never used. Derived from the statement's Dr/Cr indication (see `classify`).

| Rust | Swift |
|---|---|
| `Direction::Debit` / `Direction::Credit` | `.debit` / `.credit` |

---

### `ParsedTransaction` (NEW) — `uniffi::Record`

One successfully-parsed statement row. Ported from the web engine's `ParsedTransaction`,
reduced to this slice's fields.

| Field | Rust type | Wire → Swift | Rules / notes |
|---|---|---|---|
| `value_date` | `NaiveDate` | `String` (ISO-8601) → `String` | Parsed via `parse_date`; the transaction date (FR-004). |
| `amount` | `Decimal` | `String` (base-10) → `Foundation.Decimal` | Exact, **non-negative**, scale preserved (`10.20`); never `f64` (FR-006/007). |
| `direction` | `Direction` | `Direction` enum | From the statement, never the amount sign (FR-008). |
| `currency` | `String` | `String` | Constant **`"INR"`** this slice (FR-004). |
| `description_raw` | `String` | `String` | Trimmed row description, **truncated to 240 codepoints** (D12). Includes the leading serial (D4). |
| `bank_code` | `String` | `String` | `"ICICI"`. |

Derives: `#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]`.

> **Naming**: distinct from the existing normalized `Transaction` (date/description/amount/
> direction) used by `dedup`. `ParsedTransaction` is the *raw reader output*; a later slice may
> map it into `Transaction`. Both coexist.

---

### `ParsedStatement` (NEW) — `uniffi::Record`

The full result of reading one statement. Ported from `base.py`'s `ParsedStatement`, **omitting**
the out-of-scope reconciliation fields (`printed_opening_balance`, `printed_closing_balance`,
`printed_total_spend`, `printed_total_debits`, `printed_total_credits`).

| Field | Rust type | Wire → Swift | Rules / notes |
|---|---|---|---|
| `bank_code` | `String` | `String` | `"ICICI"`. |
| `lines` | `Vec<ParsedTransaction>` | `[ParsedTransaction]` | Cleanly-parsed rows, in input order. May be empty (no rows → empty, no error). |
| `errored_lines` | `Vec<String>` | `[String]` | Raw text of rows that matched the shape but failed date/amount parse; each **≤240 codepoints** (FR-014). Never causes a panic/abort. |
| `period_start` | `Option<NaiveDate>` | `String?` | Unused this slice (left `None`); kept for reader reuse/coverage later. |
| `period_end` | `Option<NaiveDate>` | `String?` | Statement (closing) date → billing-period end when found; else `None` (FR-011/013). |
| `card_last4` | `Option<String>` | `String?` | Last 4 of the masked PAN when found; else `None` (FR-012/013). |
| `confidence` | `f64` | `Double` | Defaults to `1.0` (ported); not lowered this slice. |

Derives: `#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]`.
Constructor defaults `lines`/`errored_lines` empty, options `None`, `confidence = 1.0`.

---

## Internal (non-FFI) types

### `LineReaderConfig` (trait) + `read_lines` / `claims` (functions)

The reusable "one transaction per text line" seam (FR-017). See `research.md` D2 for the exact
signature. Not exported over FFI — it's the engine-internal reuse point every future CC reader
implements. `read_lines` is the pure heart of the parse; the FFI wrapper just calls it.

### `IciciReader` (zero-sized struct) — `impl LineReaderConfig`

| Member | Value |
|---|---|
| `bank_code()` | `"ICICI"` |
| `claim_markers()` | `["ICICI Bank"]` |
| `row_re()` | `^(?P<date>\d{2}/\d{2}/\d{4})\d*\s+(?P<desc>.+?)(?:\s+\d+)?\s+(?P<amount>[\d,]+\.\d{2})(?:\s+(?P<dir>CR))?$` |
| `direction(caps, desc)` | `classify(desc, caps.name("dir").map(str), None)` |
| `enrich(st, full_text)` | `st.period_end = STMT_DATE_RE.captures(full_text) → parse_date(g1)`; `st.card_last4 = find_last4(full_text)` |

`STMT_DATE_RE = \b([A-Z][a-z]{2,8} \d{1,2}, \d{4})\b`. Regexes compiled once (e.g. via
`std::sync::LazyLock`) for determinism and to avoid recompilation.

### Helpers in `statement/common.rs`

- `parse_amount(raw: &str) -> Option<Decimal>` (D5)
- `parse_date(raw: &str) -> Option<NaiveDate>` over `DATE_FORMATS` (D6)
- `find_last4(text: &str, anchor: Option<&str>) -> Option<String>` (D7)
- `truncate_chars(s: &str, max: usize) -> String` (codepoint-safe, D12) — in `base.rs`

### `statement/polarity.rs`

- `classify(description: &str, dr_cr_marker: Option<&str>, amount_cell: Option<&str>) -> Direction`
- `normalise_marker(&str) -> Option<Direction>`; `is_parenthesised_credit(&str) -> bool`
- const `CREDIT_KEYWORDS` (functional). Marker sets `CR_MARKERS`/`DR_MARKERS` (D8).

---

## Fixture / harness types (test-only, `tests/parity.rs`)

Deserialized from the golden JSON with `serde_json` (dev-dependency). Amounts/dates are
**strings** and re-parsed with `Decimal::from_str` / `NaiveDate::parse_from_str` so no `f64`
touches money and comparison is exact.

```rust
#[derive(Deserialize)] struct Fixture { lines: Vec<String>, full_text: String, expected: Expected }
#[derive(Deserialize)] struct Expected {
    rows: Vec<ExpectedRow>,
    period_end: Option<String>,          // ISO-8601
    card_last4: Option<String>,
    #[serde(default)] errored_lines: Vec<String>,
}
#[derive(Deserialize)] struct ExpectedRow {
    date: String, amount: String, direction: Direction, // serde: "Credit"/"Debit"
    currency: String, description_raw: String,
}
```

The harness asserts, for each `ExpectedRow` vs the produced `ParsedTransaction`:
`value_date == parse(date)`, `amount == Decimal::from_str(amount)`, `direction`, `currency`,
`description_raw` all equal; and statement-level `period_end`/`card_last4`/`errored_lines` match.

---

## State & lifecycle

Stateless and pure. One call = `lines + full_text` → `ParsedStatement`. No persistence, no
mutation of shared state, no ordering dependence beyond the input line order. Repeated calls on
identical input yield identical results (FR-016; asserted by the determinism test).

## Validation rules (traceability)

| Rule | Source |
|---|---|
| Amount exact, non-negative, scale-preserved, never float | FR-006/007, SC-005 |
| Direction from statement marker/keyword, never amount sign | FR-008/009/010, SC-004 |
| Non-transaction lines ignored (no txn, no error) | FR-005 |
| Unparseable row → `errored_lines` (≤240 cp), never abort/drop | FR-014, SC-006 |
| Missing metadata → `None`, never fabricated | FR-013, US3-S3 |
| No PDF/file I/O; already-extracted text in, result out | FR-015 |
| Deterministic; identical input ⇒ identical output | FR-016, SC-008 |
| Currency `"INR"` | FR-004 |
