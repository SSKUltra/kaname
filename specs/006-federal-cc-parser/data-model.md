# Phase 1 — Data Model: Federal Bank / Scapia Credit-Card Parser (single layout)

**Feature**: `006-federal-cc-parser` | **Date**: 2026-07-16
**Scope**: The types this slice introduces, reuses, and configures. Federal adds **no new record**,
**no new shared helper**, and **no new dependency** — it reuses the ICICI/HDFC/SBI/Yes slices'
`ParsedStatement`/`ParsedTransaction`, `Direction`, and helpers, and adds exactly **one** layout
config. There is **no** reconciliation carve-out (the web `_enrich` is already cycle + last-4 only).

---

## Reused records (unchanged) — the parse output

### `Direction` (reused) — `uniffi::Enum`
`enum Direction { Debit, Credit }` (in `model.rs`). Carries polarity; the amount sign is never used.
For Federal, direction comes from Scapia's **leading `+`** (→ `Credit`) and, when absent, the **shared
description-language classifier** `classify(desc, None, None)` (credit words → `Credit`; else `Debit`).

### `ParsedTransaction` (reused, unchanged) — `uniffi::Record`
One successfully-parsed row (`base.rs`). No field change for Federal.

| Field | Rust type | Wire → Swift | Federal notes |
|---|---|---|---|
| `value_date` | `NaiveDate` | `String` (ISO-8601) | `%d-%m-%Y` day-first (`29-04-2026 → 2026-04-29`), via the **existing** `parse_date` (FR-003). The `HH:MM` time is consumed by the layout, never stored (FR-005). |
| `amount` | `Decimal` | `String` (base-10) → `Foundation.Decimal` | Exact, **non-negative**, scale preserved (`324.45`, `2353.13`); the rupee glyph, any leading `+`, and Indian grouping are stripped (FR-008/009, SC-006). |
| `direction` | `Direction` | `Direction` | Leading `+` → `Credit`; else `classify(desc, None, None)` (FR-010/011). |
| `currency` | `String` | `String` | Constant **`"INR"`** (FR-006). |
| `description_raw` | `String` | `String` | Trimmed row description (e.g. `Billpayment Payment`, `ExampleMerchantTokyo`), ≤240 codepoints; excludes the time, the `+`, the `₹`, and the amount. **Asserted byte-for-byte** by the harness (D3). |
| `bank_code` | `String` | `String` | `"FEDERAL"`. |

### `ParsedStatement` (reused, unchanged) — `uniffi::Record`
The full result of reading one statement (`base.rs`). **No field change** — `period_start` already
exists (added by HDFC, reused by SBI/Yes) and Federal populates it.

| Field | Rust type | Wire → Swift | Federal notes |
|---|---|---|---|
| `bank_code` | `String` | `String` | `"FEDERAL"`. |
| `lines` | `Vec<ParsedTransaction>` | `[ParsedTransaction]` | Rows matching `ROW_RE`; may be empty (no rows → empty, no error). |
| `errored_lines` | `Vec<String>` | `[String]` | Shape-matching rows that failed date/amount parse; ≤240 cp; never a panic (FR-015). |
| `period_start` | `Option<NaiveDate>` | `String?` | `parse_date(g1)` of the `_CYCLE_RE` match (`20Apr2026 → 2026-04-20`), via `%d%b%Y` (FR-012). |
| `period_end` | `Option<NaiveDate>` | `String?` | `parse_date(g2)` of the `_CYCLE_RE` match (`19May2026 → 2026-05-19`), via `%d%b%Y` (FR-012). |
| `card_last4` | `Option<String>` | `String?` | `find_last4(full_text, None)` — **un-anchored** → **`"4836"`** for `XXXXXXXXXXXX4836`; `None` when no masked card is present (FR-013/014). |
| `confidence` | `f64` | `Double` | Default `1.0` (unchanged). |

> **No `#[derive]`/schema change** ⇒ no `uniffi.toml` change and no new UniFFI record. The FFI is
> purely additive (two functions — see `contracts/engine-ffi.md`).

---

## New internal type (the Federal port) — one config, one enrich

### `statement/federal.rs` — a single zero-sized config, structured like `sbi.rs`/`yes.rs`

```rust
use std::sync::LazyLock;
use regex::{Captures, Regex};
use crate::model::Direction;
use crate::statement::base::ParsedStatement;
use crate::statement::common::{find_last4, parse_date};
use crate::statement::line_reader::LineReaderConfig;
use crate::statement::polarity::classify;

pub const BANK_CODE: &str = "FEDERAL";
const CLAIM_MARKERS: &[&str] = &["Scapia", "Federal Bank"];

// Ported byte-for-byte from federal_scapia.py `_ROW_RE`. The unescaped `.` matches the
// middot (U+00B7) date/time separator encoding-robustly (any single non-newline char);
// the literal `₹` (U+20B9) precedes — and is excluded from — the amount group; the
// `HH:MM` time is consumed by `\d{2}:\d{2}`; the optional leading `+` is captured as `sign`.
static ROW_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(
    r"^(?P<date>\d{2}-\d{2}-\d{4}).\d{2}:\d{2}\s+(?P<desc>.+?)\s+(?P<sign>\+)?₹(?P<amount>[\d,]+\.\d{2})$"
).unwrap());

// Ported from `_CYCLE_RE`: "20Apr2026-19May2026" (space-stripped range).
static CYCLE_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(
    r"(\d{1,2}[A-Za-z]{3}\d{4})\s*-\s*(\d{1,2}[A-Za-z]{3}\d{4})"
).unwrap());

pub struct FederalReader;   // zero-sized; all state is in the statics above
```

**`FederalReader: impl LineReaderConfig`**

| Member | Value |
|---|---|
| `bank_code()` | `"FEDERAL"` |
| `claim_markers()` | `CLAIM_MARKERS` (two markers `"Scapia"`, `"Federal Bank"`) |
| `row_re()` | `&ROW_RE` |
| `direction(caps, desc)` | **Federal-local**: `if caps.name("sign").map(\|m\| m.as_str()) == Some("+") { Direction::Credit } else { classify(desc, None, None) }` — reuses `polarity::classify` for the fallback (FR-010/011); same in-reader pattern as `hdfc.rs` `HdfcMonthly` |
| `enrich(st, full_text)` | the method below (**cycle + un-anchored last-4**) |

Uses the default `date_group`/`desc_group`/`amount_group` (`"date"`/`"desc"`/`"amount"`). The extra
`sign` group is **not** a seam default — it is read only by `direction` (the seam passes the full
`Captures`). The row and cycle regexes compile once via `std::sync::LazyLock` (determinism, no
recompilation).

**`enrich(&self, statement, full_text)`** (ported 1:1 from the web `_enrich`):
- if `CYCLE_RE` matches: `period_start = parse_date(&caps[1])`; `period_end = parse_date(&caps[2])`.
- always: `card_last4 = find_last4(full_text, None)` — **no anchor** (whole-text scan; the card is
  fully masked with no label).

**FFI entry points** (in `ffi.rs`, inline like ICICI/SBI/Yes):
```rust
#[uniffi::export]
pub fn read_federal_statement(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_lines(&FederalReader, &lines, &full_text)      // single layout → direct, like ICICI/SBI/Yes
}
#[uniffi::export]
pub fn federal_claims(full_text: String) -> bool {
    claims(&FederalReader, &full_text, "FEDERAL")
}
```
> The reader logic (`FederalReader` + `enrich`) stays in `statement/federal.rs` and is FFI-free and
> unit-testable; `ffi.rs` only wires the two exports (importing `FederalReader` and reusing the shared
> `read_lines`/`claims`).

---

## Reused shared helpers (UNCHANGED — no new helper added)

| Helper | Location | Federal use |
|---|---|---|
| `read_lines(&cfg, lines, full_text)` / `claims(&cfg, text, code)` | `line_reader.rs` | The seam, reused verbatim (single layout — no composite). |
| `parse_date(token)` | `common.rs` | `%d-%m-%Y` (row) **and** `%d%b%Y` (cycle) **already present** (`common.rs:24` and `:31`, both commented Scapia/Federal). |
| `parse_amount(raw)` | `common.rs` | Exact `Decimal`, `₹`/`+`/Indian grouping stripped, scale preserved. |
| `find_last4(text, anchor)` | `common.rs` | Called with `anchor = None` (whole text); **already implemented** (used by ICICI/HDFC/SBI/Yes). |
| `classify(desc, marker, amount_cell)` | `polarity.rs` | Called as `classify(desc, None, None)` — the description-language **fallback** when there is no leading `+`. |
| `ParsedStatement` / `ParsedTransaction` / `Direction` | `base.rs` / `model.rs` | Output records + polarity enum, reused. |

> **Same as SBI/Yes, unlike HDFC**: HDFC had to add `read_lines_first_match` and `month_year_end`.
> **Federal (like SBI/Yes) adds none of these** — every helper it needs already exists (FR-018,
> SC-011). Federal's only bespoke logic (the leading-`+` direction test) lives in `federal.rs`, mirroring
> the landed `hdfc.rs` monthly rule — **not** a shared-subsystem change.

---

## Fixture / harness types (test-only, `tests/parity.rs`)

The `Fixture`/`Expected`/`ExpectedRow` structs are **reused unchanged** — the harness already gained
`period_start` (`#[serde(default)]`) and asserts it (from the HDFC slice; reused by SBI/Yes). Federal
adds **one `Case` row**; there is **no harness code/schema change**:

```rust
const CASES: &[Case] = &[
    Case { label: "ICICI",         parse: read_icici_statement,   rel_path: "icici/credit_card/basic.json" },
    Case { label: "HDFC year-end", parse: read_hdfc_statement,    rel_path: "hdfc/credit_card/year_end.json" },
    Case { label: "HDFC monthly",  parse: read_hdfc_statement,    rel_path: "hdfc/credit_card/monthly.json" },
    Case { label: "SBI Card",      parse: read_sbi_statement,     rel_path: "sbi_card/credit_card/basic.json" },
    Case { label: "Yes Bank",      parse: read_yes_statement,     rel_path: "yes/credit_card/basic.json" },
    Case { label: "Federal",       parse: read_federal_statement, rel_path: "federal/credit_card/basic.json" }, // NEW — the only harness change
];
```

Amounts/dates stay **strings**, re-parsed via `Decimal::from_str`/`NaiveDate::parse_from_str` (never
`f64`). A `federal_claims` accept/reject test mirrors the existing
`icici_claims`/`hdfc_claims`/`sbi_claims`/`yes_claims` tests (FR-002, SC-002). With Federal green, the
harness proves **all five** credit-card issuers reproduce their golden vectors (SC-012).

---

## State & lifecycle

Stateless and pure. One call = `lines + full_text` → `ParsedStatement`, a single pass over the input
lines; no persistence, no shared-state mutation, no ordering dependence beyond input line order.
Repeated calls on identical input yield identical results (FR-017; asserted by the determinism test
over the Federal vector).

## Validation rules (traceability)

| Rule | Source |
|---|---|
| Recognize via `Scapia`/`Federal Bank` marker; never claim another issuer | FR-001/002, SC-002 |
| Single layout `DD-MM-YYYY<sep>HH:MM <description> [+]₹<amount>`; one transaction per row | FR-003, SC-001 |
| Match the middot date/time separator (U+00B7) encoding-robustly as any single char | FR-004, SC-005 |
| `HH:MM` time is structural only — never in the date or description | FR-005, SC-005 |
| Each row carries date, amount, direction, description, `INR` | FR-006 |
| Ignore non-transaction lines (headers/summaries/balances/totals) | FR-007 |
| Amount exact, non-negative, scale-preserved, `₹`/`+`/Indian grouping stripped, never float | FR-008/009, SC-006 |
| Direction: leading `+` → Credit; else `classify(desc, None, None)`; never the amount's sign/magnitude | FR-010/011, SC-004 |
| Billing cycle via `_CYCLE_RE` → `parse_date` both ends (via `%d%b%Y`) | FR-012, SC-003 |
| Card last-4 via un-anchored `find_last4(full_text, None)` (`XXXXXXXXXXXX4836 → "4836"`); else **absent**, never fabricated | FR-013/014, SC-003 |
| Missing metadata → `None`, transactions still returned | FR-014, US4-AC3 |
| Unparseable row → `errored_lines` (≤240 cp), never abort/drop | FR-015, SC-007 |
| No PDF/file I/O; already-extracted text in, result out; reuse seam + helpers; **no new shared helper** | FR-016/018, SC-011 |
| Deterministic; identical input ⇒ identical output | FR-017, SC-009 |
| Expose `read_federal_statement` + `federal_claims` over UniFFI, mirroring ICICI/HDFC/SBI/Yes | FR-019 |
| All five credit-card issuers reproduce their golden vectors (set complete) | SC-012 |
