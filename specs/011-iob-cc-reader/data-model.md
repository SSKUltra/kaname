# Phase 1 — Data Model: Indian Overseas Bank (IOB) Credit-Card Parser (single layout)

**Feature**: `011-iob-cc-reader` | **Date**: 2026-07-17
**Scope**: The types this slice introduces, reuses, and configures. IOB adds **no new record**,
**no new shared helper**, and **no new dependency** — it reuses the landed slices'
`ParsedStatement`/`ParsedTransaction`, `Direction`, and helpers, and adds exactly **one** layout
config. The Rust output model deliberately carries **no printed-total fields** (reconciliation
carve-out, FR-013) and **no `period_start`** for IOB (no range printed, FR-010).

---

## Reused records (unchanged) — the parse output

### `Direction` (reused) — `uniffi::Enum`
`enum Direction { Debit, Credit }` (in `model.rs`). Carries polarity; the amount sign/magnitude is
never used. For IOB, direction comes from the **terminal two-letter `Dr`/`Cr` marker** via
`classify(desc, dir, None)` (`Cr → Credit`, `Dr → Debit`).

### `ParsedTransaction` (reused, unchanged) — `uniffi::Record`
One successfully-parsed row (`base.rs`). No field change for IOB.

| Field | Rust type | Wire → Swift | IOB notes |
|---|---|---|---|
| `value_date` | `NaiveDate` | `String` (ISO-8601) | `%d-%b-%Y` day-first with an **uppercase** month (`31-MAR-2026 → 2026-03-31`), via the **existing** case-insensitive `parse_date` (FR-003, D4). |
| `amount` | `Decimal` | `String` (base-10) → `Foundation.Decimal` | Exact, **non-negative**, scale preserved (`1000.00`, `3500.00`); Indian grouping stripped (FR-006/007, SC-006). |
| `direction` | `Direction` | `Direction` | From the terminal `Dr`/`Cr` marker (FR-008/009). |
| `currency` | `String` | `String` | Constant **`"INR"`** (FR-004). |
| `description_raw` | `String` | `String` | Trimmed row description, ≤240 codepoints. **Asserted byte-for-byte** by the harness (`ExampleRefundMerchant`, `ExampleStorePurchase`) (D3). |
| `bank_code` | `String` | `String` | `"IOB"`. |
| `ledger` | `Option<LedgerMetadata>` | `LedgerMetadata?` | **`None`** — IOB is a credit-card reader; ledger metadata is only for bank-account rows. |

### `ParsedStatement` (reused, unchanged) — `uniffi::Record`
The full result of reading one statement (`base.rs`). **No field change.** Two fields are deliberately
left at their `None` default for IOB: `period_start` (no range printed) and **there are NO
`printed_total_*` fields at all** (reconciliation totals are not part of this model — FR-013, D10).

| Field | Rust type | Wire → Swift | IOB notes |
|---|---|---|---|
| `bank_code` | `String` | `String` | `"IOB"`. |
| `lines` | `Vec<ParsedTransaction>` | `[ParsedTransaction]` | Rows matching `_ROW_RE`; may be empty (no rows → empty, no error). Two rows for the golden vector. |
| `errored_lines` | `Vec<String>` | `[String]` | Shape-matching rows that failed date/amount parse; ≤240 cp; never a panic (FR-016). Empty for the golden vector. |
| `period_start` | `Option<NaiveDate>` | `String?` | **`None`** — IOB prints no period range; never fabricated (FR-010, D6). |
| `period_end` | `Option<NaiveDate>` | `String?` | `parse_date(g1)` of the `Stmt Date : <date>` match → **`2026-04-20`** (FR-010). |
| `card_last4` | `Option<String>` | `String?` | `find_last4(full_text, Some("Credit Card Number"))` → **`"0042"`** from the inline masked PAN `123456XXXXXX0042`; **not** digits from the adjacent limits `16000`/`25091.5` (FR-011, D7). `None` when no PAN found (FR-012). |
| `printed_opening_balance` | `Option<Decimal>` | `String?` | **`None`** — credit-card statement (ledger-only field). |
| `printed_closing_balance` | `Option<Decimal>` | `String?` | **`None`** — credit-card statement (ledger-only field). |
| `confidence` | `f64` | `Double` | Default `1.0` (unchanged). |

> **Explicitly absent (reconciliation carve-out, FR-013/SC-013)**: `printed_total_credits` /
> `printed_total_debits`. These exist in the **web** IOB reader's writes (via `_SUMMARY_RE`) but there
> are **no such fields** in the Rust `ParsedStatement`; `statement/iob.rs` MUST NOT reintroduce them
> (no `_SUMMARY_RE`, no assignments).

> **No `#[derive]`/schema change** ⇒ no `uniffi.toml` change and no new UniFFI record. The FFI is
> purely additive (two functions — see `contracts/engine-ffi.md`).

---

## New internal type (the IOB port) — one config, one free enrich

### `statement/iob.rs` — a single zero-sized config, structured like `yes.rs`

```rust
pub const BANK_CODE: &str = "IOB";
const CLAIM_MARKERS: &[&str] = &["INDIAN OVERSEAS BANK", "iobnet.co.in"];

// Ported byte-for-byte from iob.py `_ROW_RE`; DD-MON-YYYY (uppercase month) + terminal Dr/Cr at `$`.
static ROW_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(
    r"^(?P<date>\d{2}-[A-Za-z]{3}-\d{4})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>Dr|Cr)$"
).unwrap());

// Ported from `_STMT_DATE_RE` (case-insensitive; tolerant of spacing around the colon). The lone
// statement date is the billing-cycle END; IOB prints no period range (no period_start).
static STMT_DATE_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(
    r"(?i)Stmt Date\s*:\s*(\d{2}-[A-Za-z]{3}-\d{4})"
).unwrap());

pub struct IobReader;   // zero-sized; all state is in the statics above
```

**`IobReader: impl LineReaderConfig`**

| Member | Value |
|---|---|
| `bank_code()` | `"IOB"` |
| `claim_markers()` | `CLAIM_MARKERS` (two markers: `"INDIAN OVERSEAS BANK"`, `"iobnet.co.in"`) |
| `row_re()` | `&ROW_RE` |
| `direction(caps, desc)` | `classify(desc, caps.name("dir").map(\|m\| m.as_str()), None)` — **reuses `polarity`** (FR-008/009), identical to `yes.rs`/`sbi.rs` |
| `enrich(st, full_text)` | the free `enrich` below (**`period_end` + last-4 only**) |

Uses the default `date_group`/`desc_group`/`amount_group` (`"date"`/`"desc"`/`"amount"`). The row and
stmt-date regexes compile once via `std::sync::LazyLock` (determinism, no recompilation).

**Free `enrich(statement, full_text)`** (ported from the web `_enrich`, **minus** the reconciliation
scrape — D10; and setting **only** `period_end` — D6):
- if `STMT_DATE_RE` matches: `statement.period_end = parse_date(g1)`. **`period_start` is never set**
  (stays `None`).
- always: `card_last4 = find_last4(full_text, Some("Credit Card Number"))`.
- **NOT** ported: `printed_total_credits` / `printed_total_debits` (no `_SUMMARY_RE`).

**FFI entry points** (in `ffi.rs`, inline like SBI/Yes):
```rust
#[uniffi::export]
pub fn read_iob_statement(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_lines(&IobReader, &lines, &full_text)          // single layout → direct, like SBI/Yes
}
#[uniffi::export]
pub fn iob_claims(full_text: String) -> bool {
    claims(&IobReader, &full_text, "IOB")
}
```
> The reader logic (`IobReader` + `enrich`) stays in `statement/iob.rs` and is FFI-free and
> unit-testable; `ffi.rs` only wires the two exports. `lib.rs` re-exports both; `statement/mod.rs` gains
> `pub mod iob;`. **No `first_row_words` parameter** — this is a credit-card line reader, not a ledger
> reader.

---

## Reused shared helpers (UNCHANGED — no new helper added)

| Helper | Location | IOB use |
|---|---|---|
| `read_lines(&cfg, lines, full_text)` / `claims(&cfg, text, code)` | `line_reader.rs` | The seam, reused verbatim (single layout — no composite). |
| `parse_date(token)` | `common.rs` | `%d-%b-%Y` **already present** (`common.rs:28`); `chrono` `%b` is **case-insensitive** so uppercase `MAR`/`APR` parse (D4, verified). |
| `parse_amount(raw)` | `common.rs` | Exact `Decimal`, Indian grouping, scale preserved. |
| `find_last4(text, anchor)` | `common.rs` | Anchor `"Credit Card Number"`; **already implemented** (exercised by SBI). Whole-text fallback recovers `"0042"` from the inline PAN with no bleed (D7, verified). |
| `classify(desc, marker, None)` | `polarity.rs` | `Dr`/`Cr` normalise to `DR`/`CR`, **already** in `DR_MARKERS`/`CR_MARKERS` (`polarity.rs:11–12`). |
| `ParsedStatement` / `ParsedTransaction` / `Direction` | `base.rs` / `model.rs` | Output records + polarity enum, reused. |

> **Same as SBI/Yes, unlike HDFC**: HDFC had to add `read_lines_first_match` and `month_year_end`.
> **IOB (like SBI/Yes) adds none of these** — every helper it needs already exists (FR-019, SC-012).

---

## Fixture / harness types (test-only, `tests/parity.rs`)

The `Fixture`/`Expected`/`ExpectedRow` structs are **reused unchanged**. Because `Expected.period_start`
is `#[serde(default)]`, a fixture that **omits** `period_start` deserializes to `None` — exactly how the
ICICI vector already behaves. IOB adds **one `Case` row** (placed with the credit-card cases, after
Federal/Scapia and before the bank-account cases); there is **no harness code/schema change**:

```rust
const CASES: &[Case] = &[
    // … existing CC cases (ICICI, HDFC ×2, SBI, Yes, Federal/Scapia) …
    Case { label: "Federal/Scapia", parse: read_federal_statement, rel_path: "federal/credit_card/basic.json" },
    Case { label: "IOB",            parse: read_iob_statement,      rel_path: "iob/credit_card/basic.json" }, // NEW — the only CASES change
    // … existing bank-account cases (ICICI/HDFC/Federal/AU bank) …
];
```

Amounts/dates stay **strings**, re-parsed via `Decimal::from_str`/`NaiveDate::parse_from_str` (never
`f64`). An `iob_claims_accepts_own_document_and_rejects_others` test mirrors the existing
`sbi_claims`/`yes_claims`/`federal_claims` tests (FR-002, SC-002). Because `expected` carries **no**
printed-total fields and **omits** `period_start`, the harness structurally proves both the carve-out
(SC-013) and the absent period start (SC-003).

---

## State & lifecycle

Stateless and pure. One call = `lines + full_text` → `ParsedStatement`, a single pass over the input
lines; no persistence, no shared-state mutation, no ordering dependence beyond input line order.
Repeated calls on identical input yield identical results (FR-018; asserted by the determinism test
over the IOB vector).

## Validation rules (traceability)

| Rule | Source |
|---|---|
| Recognize via `INDIAN OVERSEAS BANK` / `iobnet.co.in` markers; never claim another issuer | FR-001/002, SC-002 |
| Single layout `DD-MON-YYYY <merchant> <amount> Dr\|Cr`; one transaction per row | FR-003, SC-001 |
| Uppercase 3-letter month parses via the existing case-insensitive `%d-%b-%Y` | FR-003, US2-AC1, SC-001 |
| Each row carries date, amount, direction, description, `INR` | FR-004 |
| Ignore non-transaction lines (header, `Credit Card Number`, `ACCOUNT SUMMARY`, totals, `Total Purchase`, end marker) | FR-005, SC-007 |
| Amount exact, non-negative, scale-preserved, Indian grouping, never float | FR-006/007, SC-006 |
| Direction from the terminal `Dr`/`Cr` marker (`Cr→credit`, `Dr→debit`); never amount sign/magnitude or description | FR-008/009, SC-005 |
| Billing-cycle end via `(?i)Stmt Date\s*:\s*<date>` → `parse_date` | FR-010, SC-003 |
| **`period_start` left unset** (no range printed; never fabricated) | FR-010, SC-003 |
| Card last-4 via `Credit Card Number` anchor from the inline masked PAN (`123456XXXXXX0042 → "0042"`); never digits from adjacent limits; else **absent** | FR-011/012, SC-004 |
| Missing metadata → `None`, transactions still returned | FR-012, US4-AC4 |
| **Printed debit/credit totals NOT ported** — output model has no such fields | FR-013, SC-013 |
| Unparseable row → `errored_lines` (≤240 cp), never abort/drop | FR-016, SC-008 |
| No PDF/file I/O; already-extracted text in, result out; reuse seam + helpers; **no new shared helper** | FR-017/019, SC-012 |
| Deterministic; identical input ⇒ identical output | FR-018, SC-010 |
| Expose `read_iob_statement` + `iob_claims` over UniFFI, mirroring SBI/Yes/Federal | FR-020, SC-015 |
| Roadmap docs list IOB under credit-card, not bank-account (both files) | FR-014/015, SC-014 |
