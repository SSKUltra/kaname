# Phase 1 — Data Model: SBI Card Credit-Card Parser (single layout)

**Feature**: `004-sbi-cc-parser` | **Date**: 2026-07-15
**Scope**: The types this slice introduces, reuses, and configures. SBI adds **no new record**,
**no new shared helper**, and **no new dependency** — it reuses the ICICI/HDFC slices'
`ParsedStatement`/`ParsedTransaction`, `Direction`, and helpers, and adds exactly **one** layout
config.

---

## Reused records (unchanged) — the parse output

### `Direction` (reused) — `uniffi::Enum`
`enum Direction { Debit, Credit }` (in `model.rs`). Carries polarity; the amount sign is never
used. For SBI, direction comes from the **terminal single-letter `C`/`D` marker** via
`classify(desc, dir, None)` (`C → Credit`, `D → Debit`).

### `ParsedTransaction` (reused, unchanged) — `uniffi::Record`
One successfully-parsed row (`base.rs`). No field change for SBI.

| Field | Rust type | Wire → Swift | SBI notes |
|---|---|---|---|
| `value_date` | `NaiveDate` | `String` (ISO-8601) | `%d %b %y` day-first (`21 Apr 26 → 2026-04-21`), via the **existing** `parse_date` (FR-003). |
| `amount` | `Decimal` | `String` (base-10) → `Foundation.Decimal` | Exact, **non-negative**, scale preserved (`82900.00`); Indian grouping stripped (FR-006/007, SC-005). |
| `direction` | `Direction` | `Direction` | From the terminal `C`/`D` marker (FR-008/009). |
| `currency` | `String` | `String` | Constant **`"INR"`** (FR-004). |
| `description_raw` | `String` | `String` | Trimmed row description, ≤240 codepoints. **Asserted byte-for-byte** by the harness (D3). |
| `bank_code` | `String` | `String` | `"SBI_CARD"`. |

### `ParsedStatement` (reused, unchanged) — `uniffi::Record`
The full result of reading one statement (`base.rs`). **No field change** — `period_start` already
exists (added by HDFC) and SBI populates it.

| Field | Rust type | Wire → Swift | SBI notes |
|---|---|---|---|
| `bank_code` | `String` | `String` | `"SBI_CARD"`. |
| `lines` | `Vec<ParsedTransaction>` | `[ParsedTransaction]` | Rows matching `_ROW_RE`; may be empty (no rows → empty, no error). |
| `errored_lines` | `Vec<String>` | `[String]` | Shape-matching rows that failed date/amount parse; ≤240 cp; never a panic (FR-014). |
| `period_start` | `Option<NaiveDate>` | `String?` | `parse_date(g1)` of the `Statement Period` line (`2026-04-22`) (FR-010). |
| `period_end` | `Option<NaiveDate>` | `String?` | `parse_date(g2)` of the `Statement Period` line (`2026-05-21`) (FR-010). |
| `card_last4` | `Option<String>` | `String?` | `find_last4(full_text, Some("Credit Card Number"))`; **`None`** when < 4 trailing digits are visible (FR-011/012). |
| `confidence` | `f64` | `Double` | Default `1.0` (unchanged). |

> **No `#[derive]`/schema change** ⇒ no `uniffi.toml` change and no new UniFFI record. The FFI is
> purely additive (two functions — see `contracts/engine-ffi.md`).

---

## New internal type (the SBI port) — one config, one free enrich

### `statement/sbi.rs` — a single zero-sized config, structured like `icici.rs`

```rust
pub const BANK_CODE: &str = "SBI_CARD";
const CLAIM_MARKERS: &[&str] = &["SBI Card", "GSTIN of SBI Card"];

// Ported byte-for-byte from sbi_card.py `_ROW_RE`; terminal C/D anchored at `$`.
static ROW_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(
    r"^(?P<date>\d{2} [A-Za-z]{3} \d{2})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>[CD])$"
).unwrap());

// Ported from `_PERIOD_RE` (case-insensitive).
static PERIOD_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(
    r"(?i)Statement Period:\s*(\d{2} [A-Za-z]{3} \d{2})\s+to\s+(\d{2} [A-Za-z]{3} \d{2})"
).unwrap());

pub struct SbiReader;   // zero-sized; all state is in the statics above
```

**`SbiReader: impl LineReaderConfig`**

| Member | Value |
|---|---|
| `bank_code()` | `"SBI_CARD"` |
| `claim_markers()` | `CLAIM_MARKERS` |
| `row_re()` | `&ROW_RE` |
| `direction(caps, desc)` | `classify(desc, caps.name("dir").map(\|m\| m.as_str()), None)` — **reuses `polarity`** (FR-008/009), identical to `icici.rs` |
| `enrich(st, full_text)` | the free `enrich` below |

Uses the default `date_group`/`desc_group`/`amount_group` (`"date"`/`"desc"`/`"amount"`). The row
and period regexes compile once via `std::sync::LazyLock` (determinism, no recompilation).

**Free `enrich(statement, full_text)`** (ported from the web `_enrich`):
- if `PERIOD_RE` matches: `period_start = parse_date(g1)`; `period_end = parse_date(g2)`.
- always: `card_last4 = find_last4(full_text, Some("Credit Card Number"))`.

**Thin accessors** (used by `ffi.rs`):
```rust
pub fn read_sbi(lines: &[String], full_text: &str) -> ParsedStatement {
    read_lines(&SbiReader, lines, full_text)          // single layout → direct, like ICICI
}
pub fn sbi_claims_text(full_text: &str) -> bool {
    claims(&SbiReader, full_text, BANK_CODE)
}
```
> Equivalently, `ffi.rs` may call `read_lines(&SbiReader, …)` / `claims(&SbiReader, …, "SBI_CARD")`
> inline, exactly as it does for ICICI. Either shape is acceptable; the reader logic stays FFI-free
> and unit-testable.

---

## Reused shared helpers (UNCHANGED — no new helper added)

| Helper | Location | SBI use |
|---|---|---|
| `read_lines(&cfg, lines, full_text)` / `claims(&cfg, text, code)` | `line_reader.rs` | The seam, reused verbatim (single layout — no composite). |
| `parse_date(token)` | `common.rs` | `%d %b %y` **already present** (`common.rs:26`). |
| `parse_amount(raw)` | `common.rs` | Exact `Decimal`, Indian grouping, scale preserved. |
| `find_last4(text, anchor)` | `common.rs` | Anchor `"Credit Card Number"`; **already implemented** (exercised by HDFC). |
| `classify(desc, marker, None)` | `polarity.rs` | `C`/`D` **already** in `CR_MARKERS`/`DR_MARKERS` (`polarity.rs:11–12`). |
| `ParsedStatement` / `ParsedTransaction` / `Direction` | `base.rs` / `model.rs` | Output records + polarity enum, reused. |

> **Contrast with HDFC**: HDFC had to add `read_lines_first_match` (`line_reader.rs`) and
> `month_year_end` (`common.rs`) and a monthly leading-`+` rule. **SBI adds none of these** — every
> helper it needs already exists (FR-017, SC-010).

---

## Fixture / harness types (test-only, `tests/parity.rs`)

The `Fixture`/`Expected`/`ExpectedRow` structs are **reused unchanged** — the harness already gained
`period_start` (`#[serde(default)]`) and asserts it (from the HDFC slice). SBI adds **one `Case`
row**; there is **no harness code/schema change**:

```rust
const CASES: &[Case] = &[
    Case { label: "ICICI",         parse: read_icici_statement, rel_path: "icici/credit_card/basic.json" },
    Case { label: "HDFC year-end", parse: read_hdfc_statement,  rel_path: "hdfc/credit_card/year_end.json" },
    Case { label: "HDFC monthly",  parse: read_hdfc_statement,  rel_path: "hdfc/credit_card/monthly.json" },
    Case { label: "SBI",           parse: read_sbi_statement,   rel_path: "sbi_card/credit_card/basic.json" }, // NEW — the only harness change
];
```

Amounts/dates stay **strings**, re-parsed via `Decimal::from_str`/`NaiveDate::parse_from_str` (never
`f64`). An `sbi_claims` accept/reject test mirrors the existing `icici_claims`/`hdfc_claims` tests
(FR-002, SC-002).

---

## State & lifecycle

Stateless and pure. One call = `lines + full_text` → `ParsedStatement`, a single pass over the
input lines; no persistence, no shared-state mutation, no ordering dependence beyond input line
order. Repeated calls on identical input yield identical results (FR-016; asserted by the
determinism test over the SBI vector).

## Validation rules (traceability)

| Rule | Source |
|---|---|
| Recognize via `SBI Card` / `GSTIN of SBI Card` marker; never claim another issuer | FR-001/002, SC-002 |
| Single layout `DD Mon YY <details> <amount> C\|D`; one transaction per row | FR-003, SC-001 |
| Each row carries date, amount, direction, description, `INR` | FR-004 |
| Ignore non-transaction lines (headers/summaries/balances/totals) | FR-005 |
| Amount exact, non-negative, scale-preserved, Indian grouping, never float | FR-006/007, SC-005 |
| Direction from the terminal `C`/`D` marker (`C→credit`, `D→debit`); never amount sign or description | FR-008/009, SC-004 |
| Period via `Statement Period:` → `parse_date` both ends | FR-010, SC-003 |
| Card last-4 via `Credit Card Number` anchor when ≥4 trailing digits; else **absent**, never fabricated | FR-011/012, SC-003 |
| Missing metadata → `None`, transactions still returned | FR-013, US4-AC4 |
| Unparseable row → `errored_lines` (≤240 cp), never abort/drop | FR-014, SC-006 |
| No PDF/file I/O; already-extracted text in, result out; reuse seam + helpers; **no new shared helper** | FR-015/017, SC-010 |
| Deterministic; identical input ⇒ identical output | FR-016, SC-008 |
| Expose `read_sbi_statement` + `sbi_claims` over UniFFI, mirroring ICICI/HDFC | FR-018 |
