# Phase 1 — Data Model: HDFC Credit-Card Parser (two layouts)

**Feature**: `003-hdfc-cc-parser` | **Date**: 2026-07-15
**Scope**: The types this slice introduces, reuses, and configures. HDFC adds **no new record**
and **no new dependency** — it reuses the ICICI slice's `ParsedStatement`/`ParsedTransaction`,
`Direction`, and helpers, and adds two layout configs + a composite + two small helpers.

---

## Reused records (unchanged) — the parse output

### `Direction` (reused) — `uniffi::Enum`
`enum Direction { Debit, Credit }` (in `model.rs`). Carries polarity; the amount sign is never
used. For HDFC, year-end direction comes from the `DR`/`CR` marker (via `classify`) and monthly
direction from the leading `+` (a dedicated rule).

### `ParsedTransaction` (reused, unchanged) — `uniffi::Record`
One successfully-parsed row (`base.rs`). No field change for HDFC.

| Field | Rust type | Wire → Swift | HDFC notes |
|---|---|---|---|
| `value_date` | `NaiveDate` | `String` (ISO-8601) | Year-end `%d-%b-%Y` (`16-Apr-2025`); monthly `%d/%m/%Y`, day-first (`15/05/2026`) (FR-006). |
| `amount` | `Decimal` | `String` (base-10) → `Foundation.Decimal` | Exact, **non-negative**, scale preserved (`10610.00`); the monthly Rupee-glyph `C` is excluded (FR-008/009, SC-006). |
| `direction` | `Direction` | `Direction` | From the statement, both layouts (FR-010/011/012). |
| `currency` | `String` | `String` | Constant **`"INR"`** (FR-006). |
| `description_raw` | `String` | `String` | Trimmed row description, ≤240 codepoints. **Asserted byte-for-byte** by the harness (D3/D4/D10). |
| `bank_code` | `String` | `String` | `"HDFC"`. |

### `ParsedStatement` (reused, unchanged) — `uniffi::Record`
The full result of reading one statement (`base.rs`). **No field change** — crucially,
`period_start` **already exists** (ICICI leaves it `None`; **HDFC populates it**).

| Field | Rust type | Wire → Swift | HDFC notes |
|---|---|---|---|
| `bank_code` | `String` | `String` | `"HDFC"`. |
| `lines` | `Vec<ParsedTransaction>` | `[ParsedTransaction]` | Rows from the layout that matched; may be empty (no rows → empty, no error). |
| `errored_lines` | `Vec<String>` | `[String]` | Shape-matching rows that failed date/amount parse; ≤240 cp; never a panic (FR-017). |
| `period_start` | `Option<NaiveDate>` | `String?` | **Now populated by HDFC**: year-end = first day of the opening month; monthly = the Billing-Period start (FR-013/014). |
| `period_end` | `Option<NaiveDate>` | `String?` | Year-end = last day of the closing month; monthly = the Billing-Period end (FR-013/014). |
| `card_last4` | `Option<String>` | `String?` | `find_last4(full_text, Some("Card Number"))` (FR-015). |
| `confidence` | `f64` | `Double` | Default `1.0` (unchanged). |

> **No `#[derive]`/schema change** ⇒ no `uniffi.toml` change and no new UniFFI record. The FFI is
> purely additive (two functions — see `contracts/engine-ffi.md`).

---

## New internal types & helpers (the HDFC port)

### `statement/hdfc.rs` — two configs, one shared enrich, one composite

```rust
pub const BANK_CODE: &str = "HDFC";
const CLAIM_MARKERS: &[&str] = &["HDFC Bank Credit Card", "HDFC Bank Credit Cards"];

pub struct HdfcYearEndReader;   // zero-sized
pub struct HdfcMonthlyReader;   // zero-sized
```

**`HdfcYearEndReader: impl LineReaderConfig`**

| Member | Value |
|---|---|
| `bank_code()` | `"HDFC"` |
| `claim_markers()` | `CLAIM_MARKERS` |
| `row_re()` | `^(?P<date>\d{2}-[A-Za-z]{3}-\d{4})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>DR\|CR)\b` |
| `direction(caps, desc)` | `classify(desc, caps.name("dir").map(str), None)` — reuses `polarity` (FR-011) |
| `enrich(st, full_text)` | shared `enrich` (below) |

**`HdfcMonthlyReader: impl LineReaderConfig`**

| Member | Value |
|---|---|
| `bank_code()` | `"HDFC"` |
| `claim_markers()` | `CLAIM_MARKERS` |
| `row_re()` | `^(?P<date>\d{2}/\d{2}/\d{4})\s*\|?\s*\d{1,2}:\d{2}\s+(?P<desc>.+?)\s+(?P<dir>\+\s*)?C\s*(?P<amount>[\d,]+\.\d{2})\b` |
| `direction(caps, _desc)` | `if caps.name("dir").map_or("", str).trim().starts_with('+') { Credit } else { Debit }` — **NEW rule, not `classify`** (FR-012) |
| `enrich(st, full_text)` | shared `enrich` (below) |

Both use the default `date_group`/`desc_group`/`amount_group` (`"date"`/`"desc"`/`"amount"`).
Row regexes compiled once via `std::sync::LazyLock` (determinism, no recompilation).

**Shared `enrich(statement, full_text)`** (ported from the web `_enrich`):
- `_PERIOD_RE = (?i)period from\s+([A-Za-z]+-\d{2})\s+to\s+([A-Za-z]+-\d{2})` → if match:
  `period_end = month_year_end(g2)`; `period_start = month_year_end(g1).and_then(|d| d.with_day(1))`.
- else `_MONTHLY_PERIOD_RE = (?i)Billing Period\s+(\d{1,2}\s+[A-Za-z]{3,9},?\s+\d{4})\s*-\s*(\d{1,2}\s+[A-Za-z]{3,9},?\s+\d{4})`
  → `period_start = parse_date(g1.replace(',', ""))`; `period_end = parse_date(g2.replace(',', ""))`.
- always `statement.card_last4 = find_last4(full_text, Some("Card Number"))`.

**Composite accessors** (thin; used by `ffi.rs`):
```rust
pub fn read_hdfc(lines: &[String], full_text: &str) -> ParsedStatement {
    read_lines_first_match(&[&HdfcYearEndReader, &HdfcMonthlyReader], lines, full_text)
}
pub fn hdfc_claims_text(full_text: &str) -> bool {
    claims(&HdfcYearEndReader, full_text, BANK_CODE)   // both configs share markers
}
```

### `statement/line_reader.rs` — the reusable composite (NEW) + `?Sized` relaxation

```rust
pub fn read_lines<C: LineReaderConfig + ?Sized>(cfg: &C, lines: &[String], full_text: &str) -> ParsedStatement; // +?Sized
pub fn claims<C: LineReaderConfig + ?Sized>(cfg: &C, text: &str, bank_code: &str) -> bool;                       // +?Sized
pub fn read_lines_first_match(cfgs: &[&dyn LineReaderConfig], lines: &[String], full_text: &str) -> ParsedStatement; // NEW
```
`read_lines_first_match` returns the first config whose statement has non-empty `lines`, else the
last (enriched) empty statement (mirrors the web `HdfcCreditCardReader.read_lines`; research D2).
The `?Sized` relaxation is backward-compatible; the trait is object-safe.

### `statement/common.rs` — `month_year_end` (NEW shared helper)

```rust
pub fn month_year_end(token: &str) -> Option<NaiveDate>;
```
`token` like `"MARCH-26"`: month = first 3 letters (case-insensitive) via a `JAN..DEC` table;
year = `2000 + <2-digit yy>`; day = last day of that month (first day of next month minus one,
via chrono). Invalid month/year → `None`. Reuses the existing `parse_amount`/`parse_date`/
`find_last4` unchanged (research D7/D8/D9).

---

## Fixture / harness types (test-only, `tests/parity.rs`)

The `Fixture`/`Expected`/`ExpectedRow` structs are reused; **one field is added** to `Expected`
(backward-compatible), and **two case rows** are added:

```rust
#[derive(Deserialize)] struct Expected {
    rows: Vec<ExpectedRow>,
    #[serde(default)] period_start: Option<String>,  // NEW — ISO-8601; ICICI omits → None (backward-compatible)
    period_end: Option<String>,
    card_last4: Option<String>,
    #[serde(default)] errored_lines: Vec<String>,
}
// assert_matches_expected() gains: assert_eq!(statement.period_start, want_period_start, "{label}: period_start");

const CASES: &[Case] = &[
    Case { label: "ICICI",         parse: read_icici_statement, rel_path: "icici/credit_card/basic.json" },
    Case { label: "HDFC year-end", parse: read_hdfc_statement,  rel_path: "hdfc/credit_card/year_end.json" }, // NEW
    Case { label: "HDFC monthly",  parse: read_hdfc_statement,  rel_path: "hdfc/credit_card/monthly.json" },  // NEW
];
```
Both HDFC rows call the **same** `read_hdfc_statement` (the composite) — proving auto-selection
(SC-004). Amounts/dates stay **strings**, re-parsed via `Decimal::from_str`/`NaiveDate::parse_from_str`
(never `f64`). A `hdfc_claims` accept/reject test mirrors the existing `icici_claims` test (FR-002).

---

## State & lifecycle

Stateless and pure. One call = `lines + full_text` → `ParsedStatement`. The composite tries ≤2
layouts, each a pure pass over the same inputs; no persistence, no shared-state mutation, no
ordering dependence beyond input line order. Repeated calls on identical input yield identical
results (FR-019; asserted by the determinism test over both HDFC vectors).

## Validation rules (traceability)

| Rule | Source |
|---|---|
| Recognize via `HDFC Bank Credit Card(s)` marker; never claim another issuer | FR-001/002, SC-002 |
| Two layouts behind one reader; year-end first, monthly fallback; neither → empty, no error | FR-003/004, SC-004 |
| One transaction per row; ignore non-transaction lines | FR-005/007 |
| Amount exact, non-negative, scale-preserved, never float; monthly `C` excluded | FR-008/009, SC-006 |
| Direction from statement — year-end `DR`/`CR` (classify); monthly leading `+` (new rule); never amount sign | FR-010/011/012, SC-005 |
| Year-end period via `month_year_end` (last/first day); card last-4 via `Card Number` anchor | FR-013/015, SC-003 |
| Monthly period via `parse_date` on Billing Period | FR-014 |
| Missing metadata → `None`, never fabricated | FR-016, US4-S4 |
| Unparseable row → `errored_lines` (≤240 cp), never abort/drop | FR-017, SC-007 |
| No PDF/file I/O; already-extracted text in, result out; reuse seam + helpers | FR-018/020 |
| Deterministic; identical input ⇒ identical output | FR-019, SC-009 |
| Expose `read_hdfc_statement` + `hdfc_claims` over UniFFI, mirroring ICICI | FR-021 |
