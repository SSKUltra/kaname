# Phase 1 — Data Model: Yes Bank (Kiwi) Credit-Card Parser (single layout)

**Feature**: `005-yes-cc-parser` | **Date**: 2026-07-15
**Scope**: The types this slice introduces, reuses, and configures. Yes adds **no new record**,
**no new shared helper**, and **no new dependency** — it reuses the ICICI/HDFC/SBI slices'
`ParsedStatement`/`ParsedTransaction`, `Direction`, and helpers, and adds exactly **one** layout
config. The Rust output model deliberately carries **no printed-total fields** (reconciliation
carve-out, FR-013).

---

## Reused records (unchanged) — the parse output

### `Direction` (reused) — `uniffi::Enum`
`enum Direction { Debit, Credit }` (in `model.rs`). Carries polarity; the amount sign is never used.
For Yes, direction comes from the **terminal two-letter `Dr`/`Cr` marker** via `classify(desc, dir,
None)` (`Cr → Credit`, `Dr → Debit`).

### `ParsedTransaction` (reused, unchanged) — `uniffi::Record`
One successfully-parsed row (`base.rs`). No field change for Yes.

| Field | Rust type | Wire → Swift | Yes notes |
|---|---|---|---|
| `value_date` | `NaiveDate` | `String` (ISO-8601) | `%d/%m/%Y` day-first (`29/04/2026 → 2026-04-29`), via the **existing** `parse_date` (FR-003). |
| `amount` | `Decimal` | `String` (base-10) → `Foundation.Decimal` | Exact, **non-negative**, scale preserved (`9000.00`); Indian grouping stripped (FR-006/007, SC-005). |
| `direction` | `Direction` | `Direction` | From the terminal `Dr`/`Cr` marker (FR-008/009). |
| `currency` | `String` | `String` | Constant **`"INR"`** (FR-004). |
| `description_raw` | `String` | `String` | Trimmed row description (incl. any merchant-category text), ≤240 codepoints. **Asserted byte-for-byte** by the harness (D3). |
| `bank_code` | `String` | `String` | `"YES"`. |

### `ParsedStatement` (reused, unchanged) — `uniffi::Record`
The full result of reading one statement (`base.rs`). **No field change** — `period_start` already
exists (added by HDFC, reused by SBI) and Yes populates it. **Crucially, there are NO
`printed_total_*` fields** — the reconciliation totals the web reader scrapes are not part of this
model (FR-013, D10).

| Field | Rust type | Wire → Swift | Yes notes |
|---|---|---|---|
| `bank_code` | `String` | `String` | `"YES"`. |
| `lines` | `Vec<ParsedTransaction>` | `[ParsedTransaction]` | Rows matching `_ROW_RE`; may be empty (no rows → empty, no error). |
| `errored_lines` | `Vec<String>` | `[String]` | Shape-matching rows that failed date/amount parse; ≤240 cp; never a panic (FR-014). |
| `period_start` | `Option<NaiveDate>` | `String?` | `parse_date(g1)` of the `<date> To <date>` match (`2026-04-17`) (FR-010). |
| `period_end` | `Option<NaiveDate>` | `String?` | `parse_date(g2)` of the `<date> To <date>` match (`2026-05-16`) (FR-010). |
| `card_last4` | `Option<String>` | `String?` | `find_last4(full_text, Some("Card Number"))` → **`"6686"`** for `3561XXXXXXXX6686`; `None` when < 4 trailing digits visible (FR-011/012). |
| `confidence` | `f64` | `Double` | Default `1.0` (unchanged). |

> **Explicitly absent (reconciliation carve-out, FR-013/SC-013)**: `printed_total_debits` /
> `printed_total_credits`. These exist in the **web** `ParsedStatement` but are **not** ported here;
> `statement/yes.rs` MUST NOT reintroduce them (no `_DEBITS_RE`/`_CREDITS_RE`, no assignments).

> **No `#[derive]`/schema change** ⇒ no `uniffi.toml` change and no new UniFFI record. The FFI is
> purely additive (two functions — see `contracts/engine-ffi.md`).

---

## New internal type (the Yes port) — one config, one free enrich

### `statement/yes.rs` — a single zero-sized config, structured like `sbi.rs`

```rust
pub const BANK_CODE: &str = "YES";
const CLAIM_MARKERS: &[&str] = &["YES BANK"];

// Ported byte-for-byte from yes_kiwi.py `_ROW_RE`; terminal Dr/Cr anchored at `$`.
static ROW_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(
    r"^(?P<date>\d{2}/\d{2}/\d{4})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>Dr|Cr)$"
).unwrap());

// Ported from `_PERIOD_RE` (case-insensitive; NO "Statement Period:" prefix — just <date> To <date>).
static PERIOD_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(
    r"(?i)(\d{2}/\d{2}/\d{4})\s+To\s+(\d{2}/\d{2}/\d{4})"
).unwrap());

pub struct YesReader;   // zero-sized; all state is in the statics above
```

**`YesReader: impl LineReaderConfig`**

| Member | Value |
|---|---|
| `bank_code()` | `"YES"` |
| `claim_markers()` | `CLAIM_MARKERS` (single marker `"YES BANK"`) |
| `row_re()` | `&ROW_RE` |
| `direction(caps, desc)` | `classify(desc, caps.name("dir").map(\|m\| m.as_str()), None)` — **reuses `polarity`** (FR-008/009), identical to `sbi.rs`/`icici.rs` |
| `enrich(st, full_text)` | the free `enrich` below (**period + last-4 only**) |

Uses the default `date_group`/`desc_group`/`amount_group` (`"date"`/`"desc"`/`"amount"`). The row and
period regexes compile once via `std::sync::LazyLock` (determinism, no recompilation).

**Free `enrich(statement, full_text)`** (ported from the web `_enrich`, **minus** the reconciliation
scrape — D10):
- if `PERIOD_RE` matches: `period_start = parse_date(g1)`; `period_end = parse_date(g2)`.
- always: `card_last4 = find_last4(full_text, Some("Card Number"))`.
- **NOT** ported: `printed_total_debits` / `printed_total_credits` (no `_DEBITS_RE`/`_CREDITS_RE`).

**FFI entry points** (in `ffi.rs`, inline like ICICI/SBI):
```rust
#[uniffi::export]
pub fn read_yes_statement(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_lines(&YesReader, &lines, &full_text)          // single layout → direct, like ICICI/SBI
}
#[uniffi::export]
pub fn yes_claims(full_text: String) -> bool {
    claims(&YesReader, &full_text, "YES")
}
```
> The reader logic (`YesReader` + `enrich`) stays in `statement/yes.rs` and is FFI-free and
> unit-testable; `ffi.rs` only wires the two exports.

---

## Reused shared helpers (UNCHANGED — no new helper added)

| Helper | Location | Yes use |
|---|---|---|
| `read_lines(&cfg, lines, full_text)` / `claims(&cfg, text, code)` | `line_reader.rs` | The seam, reused verbatim (single layout — no composite). |
| `parse_date(token)` | `common.rs` | `%d/%m/%Y` **already present** (`common.rs:21`, already commented "ICICI, Yes"). |
| `parse_amount(raw)` | `common.rs` | Exact `Decimal`, Indian grouping, scale preserved. |
| `find_last4(text, anchor)` | `common.rs` | Anchor `"Card Number"`; **already implemented** (exercised by HDFC/SBI). |
| `classify(desc, marker, None)` | `polarity.rs` | `Dr`/`Cr` normalise to `DR`/`CR`, **already** in `DR_MARKERS`/`CR_MARKERS` (`polarity.rs:11–12`). |
| `ParsedStatement` / `ParsedTransaction` / `Direction` | `base.rs` / `model.rs` | Output records + polarity enum, reused. |

> **Same as SBI, unlike HDFC**: HDFC had to add `read_lines_first_match` and `month_year_end` and a
> monthly leading-`+` rule. **Yes (like SBI) adds none of these** — every helper it needs already
> exists (FR-017, SC-010).

---

## Fixture / harness types (test-only, `tests/parity.rs`)

The `Fixture`/`Expected`/`ExpectedRow` structs are **reused unchanged** — the harness already gained
`period_start` (`#[serde(default)]`) and asserts it (from the HDFC slice; reused by SBI). Yes adds
**one `Case` row**; there is **no harness code/schema change**:

```rust
const CASES: &[Case] = &[
    Case { label: "ICICI",         parse: read_icici_statement, rel_path: "icici/credit_card/basic.json" },
    Case { label: "HDFC year-end", parse: read_hdfc_statement,  rel_path: "hdfc/credit_card/year_end.json" },
    Case { label: "HDFC monthly",  parse: read_hdfc_statement,  rel_path: "hdfc/credit_card/monthly.json" },
    Case { label: "SBI Card",      parse: read_sbi_statement,   rel_path: "sbi_card/credit_card/basic.json" },
    Case { label: "Yes Bank",      parse: read_yes_statement,   rel_path: "yes/credit_card/basic.json" }, // NEW — the only harness change
];
```

Amounts/dates stay **strings**, re-parsed via `Decimal::from_str`/`NaiveDate::parse_from_str` (never
`f64`). A `yes_claims` accept/reject test mirrors the existing `icici_claims`/`hdfc_claims`/
`sbi_claims` tests (FR-002, SC-002). Because `expected` carries **no** printed-total fields, the
harness structurally proves the carve-out (SC-013).

---

## State & lifecycle

Stateless and pure. One call = `lines + full_text` → `ParsedStatement`, a single pass over the input
lines; no persistence, no shared-state mutation, no ordering dependence beyond input line order.
Repeated calls on identical input yield identical results (FR-016; asserted by the determinism test
over the Yes vector).

## Validation rules (traceability)

| Rule | Source |
|---|---|
| Recognize via `YES BANK` marker; never claim another issuer | FR-001/002, SC-002 |
| Single layout `DD/MM/YYYY <details … Ref No> <Merchant Category> <amount> Dr\|Cr`; one transaction per row | FR-003, SC-001 |
| Merchant-category text between Ref No and amount is part of the description | FR-003, US1-AC3 |
| Each row carries date, amount, direction, description, `INR` | FR-004 |
| Ignore non-transaction lines (headers/summaries/balances/totals) | FR-005 |
| Amount exact, non-negative, scale-preserved, Indian grouping, never float | FR-006/007, SC-005 |
| Direction from the terminal `Dr`/`Cr` marker (`Cr→credit`, `Dr→debit`); never amount sign or description | FR-008/009, SC-004 |
| Period via `(?i)<date> To <date>` → `parse_date` both ends | FR-010, SC-003 |
| Card last-4 via `Card Number` anchor when ≥4 trailing digits (`3561XXXXXXXX6686 → "6686"`); else **absent**, never fabricated | FR-011/012, SC-003 |
| Missing metadata → `None`, transactions still returned | FR-012, US4-AC3 |
| **Printed debit/credit totals NOT ported** — output model has no such fields | FR-013, SC-013 |
| Unparseable row → `errored_lines` (≤240 cp), never abort/drop | FR-014, SC-006 |
| No PDF/file I/O; already-extracted text in, result out; reuse seam + helpers; **no new shared helper** | FR-015/017, SC-010 |
| Deterministic; identical input ⇒ identical output | FR-016, SC-008 |
| Expose `read_yes_statement` + `yes_claims` over UniFFI, mirroring ICICI/HDFC/SBI | FR-018 |
