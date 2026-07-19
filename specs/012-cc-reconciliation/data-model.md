# Phase 1 — Data Model: Credit-Card Statement Reconciliation

**Feature**: `012-cc-reconciliation` | **Date**: 2026-07-19
**Scope**: The types this slice introduces, extends, reuses, and configures. Reconciliation adds **one
new check module** (a status enum + a typed result record + a pure function), **two new fields** on
`ParsedStatement`, and **no new shared helper** and **no new dependency**. It reuses the landed slices'
`ParsedStatement`/`ParsedTransaction`/`Direction`, the exact-decimal `Decimal` money type, the parity
harness, and the UniFFI bridge. The web engine's `printed_total_spend` is **deliberately not** added
(reconciliation never reads it — FR-011, plan D9).

---

## Extended record (the parse output gains two fields)

### `ParsedStatement` (EDIT — two additive fields) — `uniffi::Record`

The full result of reading one statement (`base.rs`). Gains **two** `Option<Decimal>` fields **after
`printed_closing_balance`**, both defaulting to `None` in `ParsedStatement::new` (so all ten readers and
every existing fixture are unaffected; only Yes + IOB populate them). The module doc-comment — which
currently says the reconciliation `printed_*` totals "arrive with a later slice" — is updated (that
slice is now).

| Field | Rust type | Wire → Swift | Notes |
|---|---|---|---|
| `bank_code` | `String` | `String` | Unchanged. |
| `lines` | `Vec<ParsedTransaction>` | `[ParsedTransaction]` | Unchanged. The check sums over **all** of these; never mutates/drops them (FR-003). |
| `errored_lines` | `Vec<String>` | `[String]` | Unchanged. |
| `period_start` | `Option<NaiveDate>` | `String?` | Unchanged. |
| `period_end` | `Option<NaiveDate>` | `String?` | Unchanged. |
| `card_last4` | `Option<String>` | `String?` | Unchanged. |
| `printed_opening_balance` | `Option<Decimal>` | `String?` | **Reused unchanged** — the fallback's opening anchor (bank-ledger field). |
| `printed_closing_balance` | `Option<Decimal>` | `String?` | **Reused unchanged** — the fallback's closing anchor. |
| **`printed_total_debits`** | **`Option<Decimal>`** | **`String?`** | **NEW** — the statement's printed per-statement **debit** total; `None` unless the reader prints it (Yes/IOB). Compared to `read_debits` in the primary tier (FR-011/012/013). |
| **`printed_total_credits`** | **`Option<Decimal>`** | **`String?`** | **NEW** — the statement's printed per-statement **credit** total; `None` unless the reader prints it (Yes/IOB). Compared to `read_credits` in the primary tier. |
| `confidence` | `f64` | `Double` | Unchanged (default `1.0`). |

```rust
// base.rs — added after printed_closing_balance; defaulted to None in ParsedStatement::new.
pub printed_total_debits: Option<Decimal>,
pub printed_total_credits: Option<Decimal>,
```

> **Deliberately absent — `printed_total_spend`** (FR-011, plan D9): the web `ParsedStatement` carries a
> `printed_total_spend`, but **reconciliation never reads it**, so it is **not** added — consistent with
> `base.rs`'s "only the fields this slice needs" doctrine. `base.rs` MUST NOT introduce it.

> **Additive record change** ⇒ every reader that does not set the two fields (ICICI, HDFC, SBI,
> Federal/Scapia) leaves them `None` via the `ParsedStatement::new` default; no reader code changes
> except Yes + IOB. The `uniffi::Record` derive picks up the two fields → the generated Swift
> `ParsedStatement` gains `printedTotalDebits: String?` / `printedTotalCredits: String?`.

### `ParsedTransaction` (reused, unchanged) — `uniffi::Record`

One parsed row (`base.rs`). **No field change.** The check reads `amount` (`Decimal`) and `direction`
(`Direction`) per row; `ledger` is `None` for credit-card rows.

### `Direction` (reused, unchanged) — `uniffi::Enum`

`enum Direction { Debit, Credit }` (`model.rs`). Selects which running sum a row's `amount` adds to
(`Debit → read_debits`, `Credit → read_credits`). Read from the row's own `Dr`/`Cr` marker — **never**
re-derived from the amount's sign (FR-002).

---

## New types (the reconcile check) — `statement/reconcile.rs`

Structured **identically to `balance_chain.rs`**: a status enum + a typed result record + one pure
function over `&ParsedStatement`, with a module comment.

### `ReconcileStatus` (NEW) — `uniffi::Enum`

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ReconcileStatus {
    Reconciled,
    NeedsReview,
}
```

A **two-variant** enum → Swift `.reconciled` / `.needsReview`. The **neutral** "no balance" outcome is
**not** a variant here — it is represented by `ReconcileResult.status == None` (see D2). Derives mirror
`ChainStatus` exactly (`Copy` + `Eq` are safe for a fieldless enum).

### `ReconcileResult` (NEW) — `uniffi::Record`

```rust
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ReconcileResult {
    pub status: Option<ReconcileStatus>,
    pub read_debits: Decimal,
    pub read_credits: Decimal,
    pub printed_debits: Option<Decimal>,
    pub printed_credits: Option<Decimal>,
    pub expected_balance_change: Option<Decimal>,
    pub computed_balance_change: Option<Decimal>,
    pub reason: Option<String>,
}
```

The verdict + a **typed audit detail** mirroring the web `detail` dict (the pattern `ChainResult` uses
instead of a dynamic dict — FR-010). No `Copy`/`Eq` (it holds `Decimal`/`String`), matching
`ChainResult`.

| Field | Rust type | Wire → Swift | Set on | Meaning |
|---|---|---|---|---|
| `status` | `Option<ReconcileStatus>` | `ReconcileStatus?` | always | `Some(.reconciled)` / `Some(.needsReview)` / **`nil` (neutral)** (FR-001/004, D2). |
| `read_debits` | `Decimal` | `String` → `Foundation.Decimal` | **always** | Σ `amount` where `direction == Debit`; `0.00` for no rows (FR-002). |
| `read_credits` | `Decimal` | `String` → `Foundation.Decimal` | **always** | Σ `amount` where `direction == Credit`; `0.00` for no rows. |
| `printed_debits` | `Option<Decimal>` | `String?` | primary | the printed debit total compared; `None` off the primary path. |
| `printed_credits` | `Option<Decimal>` | `String?` | primary | the printed credit total compared; `None` off the primary path. |
| `expected_balance_change` | `Option<Decimal>` | `String?` | fallback | `closing − opening`; `None` off the fallback path. |
| `computed_balance_change` | `Option<Decimal>` | `String?` | fallback | `read_debits − read_credits`; `None` off the fallback path. |
| `reason` | `Option<String>` | `String?` | neutral | `Some("no printed totals extracted")`; `None` on the primary/fallback paths. |

**Field-population matrix by tier** (an "×" means the field is `Some`/set; blank means `None`):

| Tier | `status` | `read_debits`/`read_credits` | `printed_debits`/`printed_credits` | `expected_`/`computed_balance_change` | `reason` |
|---|---|---|---|---|---|
| **Primary** | `Some(Reconciled\|NeedsReview)` | × | × (each present total echoed) | | |
| **Fallback** | `Some(Reconciled\|NeedsReview)` | × | | × | |
| **Neutral** | `None` | × | | | × `"no printed totals extracted"` |

### `reconcile` (NEW) — pure function

```rust
pub fn reconcile(statement: &ParsedStatement) -> ReconcileResult
```

- `let tolerance = Decimal::new(100, 2);` — the same `1.00` constant `balance_chain` uses (D4).
- `read_debits = Σ line.amount where line.direction == Direction::Debit`;
  `read_credits = Σ line.amount where line.direction == Direction::Credit` (D5).
- **Primary** — `if statement.printed_total_debits.is_some() || statement.printed_total_credits.is_some()`:
  check each **present** total with `(read − printed).abs() <= tolerance`; `status = Some(Reconciled)`
  iff all present pass else `Some(NeedsReview)`; set `printed_debits`/`printed_credits` from the
  statement; leave the fallback fields + `reason` `None` (D6).
- **Fallback** — `else if statement.printed_opening_balance.is_some() &&
  statement.printed_closing_balance.is_some()`: `expected = closing − opening`,
  `computed = read_debits − read_credits`; `status = Some(Reconciled)` iff
  `(computed − expected).abs() <= tolerance` else `Some(NeedsReview)`; set
  `expected_balance_change`/`computed_balance_change` (D7).
- **Neutral** — `else`: `status = None`, `reason = Some("no printed totals extracted".to_string())` (D8).

**Purity**: no I/O, no clock/locale, no mutation of `statement` (borrowed `&`); identical input ⇒
identical output (FR-018, SC-013). Never panics (empty rows fold to `0.00`).

### Unit tests (`reconcile.rs`, mirroring `test_reconciliation.py` + the spec edge cases)

`totals-match → Reconciled`; `debit-mismatch → NeedsReview` (+ detail read/printed); `0.50-within-tol →
Reconciled`; `exactly-1.00-boundary → Reconciled`; `only-one-total-present`; `both-present-one-mismatch
→ NeedsReview`; `balance-change fallback → Reconciled`; `primary-takes-precedence-over-fallback`;
`only-one-balance → neutral`; `no-totals → neutral (None) with reason`; `empty-rows sums 0.00`.

---

## Reader enrichment changes (Yes + IOB) — no new helper

### `statement/yes.rs` (EDIT) — two new statics + `enrich` populates the fields

```rust
// Rust-escaped ports of yes_kiwi.py; the [^\n]*? keeps label + value on the SAME extracted line.
static DEBITS_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)Purchases[^\n]*?Rs\.?\s*([\d,]+\.\d{2})\s*Dr").unwrap());
static CREDITS_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)Payment\s*&?\s*Credits Received[^\n]*?Rs\.?\s*([\d,]+\.\d{2})\s*Cr").unwrap()
});
```

In `enrich` (after the existing period/last-4 lines):
```rust
statement.printed_total_debits = DEBITS_RE.captures(full_text).and_then(|c| parse_amount(&c[1]));
statement.printed_total_credits = CREDITS_RE.captures(full_text).and_then(|c| parse_amount(&c[1]));
```
Module-doc rewrite: the "printed totals … out of scope … intentionally not ported" paragraph becomes
"surfaced for reconciliation". **Verified** (plan D10): `100.00` / `9000.00` (thousands separator
stripped by `parse_amount`). A reader unit test asserts the totals on the extended sample.

### `statement/iob.rs` (EDIT) — one new static + `enrich` populates the fields

```rust
// Port of iob.py _SUMMARY_RE (IGNORECASE|DOTALL → (?is)); credits = 2nd figure, debits = 3rd.
static SUMMARY_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?is)ACCOUNT SUMMARY\b.*?(?P<prev>[\d,]+(?:\.\d+)?)\s+(?P<credits>[\d,]+\.\d{2})\s+(?P<debits>[\d,]+\.\d{2})\s+(?P<fees>[\d,]+(?:\.\d+)?)\s+(?P<total>[\d,]+(?:\.\d+)?)",
    )
    .unwrap()
});
```

In `enrich`:
```rust
if let Some(summary) = SUMMARY_RE.captures(full_text) {
    statement.printed_total_credits = parse_amount(&summary["credits"]);
    statement.printed_total_debits = parse_amount(&summary["debits"]);
}
```
Module-doc carve-out paragraph rewritten. **Verified** (plan D11): `credits 1000.00`, `debits 3500.00`
(with `prev 345.50`, `fees 0`, `total 2,845.50`). A reader unit test asserts the totals (the existing
fixture `full_text` already carries the `ACCOUNT SUMMARY` block).

> Both readers reuse the **existing** `parse_amount` (`common.rs`) and `std::sync::LazyLock<Regex>`
> pattern — **no new shared helper**. Direction/rows/dates/last-4/period are **byte-for-byte unchanged**
> (FR-014); only the two printed-total fields are added.

---

## Reused shared helpers (UNCHANGED — no new helper added)

| Helper / type | Location | Reconcile use |
|---|---|---|
| `parse_amount(raw)` | `common.rs` | Yes/IOB capture-group → `Decimal` (thousands stripped, scale preserved). |
| `Decimal` + `Decimal::new(100, 2)` | `rust_decimal` | Exact money + the `1.00` tolerance (same as `balance_chain`). |
| `ParsedStatement` / `ParsedTransaction` / `Direction` | `base.rs` / `model.rs` | The check's input + per-row `amount`/`direction`. |
| `read_lines(&cfg, …)` seam | `line_reader.rs` | Unchanged — Yes/IOB still parse via it; only `enrich` grows. |
| Parity harness `Fixture`/`Expected`/`ExpectedRow` | `tests/parity.rs` | `Expected` gains two `#[serde(default)]` fields (below); otherwise reused. |
| `Decimal`/`NaiveDate` custom types + `Direction` enum | `ffi.rs` + `uniffi.toml` | The bridge for `reconcile_statement` + the two new fields. |

---

## FFI surface (additive — `ffi.rs` + `lib.rs`)

```rust
// ffi.rs — mirrors check_balance_chain.
use crate::statement::reconcile::{reconcile, ReconcileResult};

#[uniffi::export]
pub fn reconcile_statement(statement: ParsedStatement) -> ReconcileResult {
    reconcile(&statement)
}
```
`statement/mod.rs` gains `pub mod reconcile;`. `lib.rs` adds `reconcile_statement` to the
`pub use ffi::{…}` list and `pub use statement::reconcile::{ReconcileResult, ReconcileStatus};`. The
`ParsedStatement` record + `Decimal` custom type are reused; `ReconcileResult`/`ReconcileStatus` derive
`uniffi` so bindgen emits their Swift types. **No `uniffi.toml` change.**

---

## Fixture / harness types (test-only, `tests/parity.rs`)

`Expected` gains two optional fields (the same `#[serde(default)]` pattern the ledger balance fields
use), asserted via the existing `parse_dec` closure:

```rust
#[derive(Deserialize)]
struct Expected {
    // … existing fields …
    #[serde(default)]
    printed_total_debits: Option<String>,
    #[serde(default)]
    printed_total_credits: Option<String>,
}
```
In `assert_matches_expected`:
```rust
assert_eq!(statement.printed_total_debits, expected.printed_total_debits.as_deref().map(parse_dec),
    "{label}: printed_total_debits");
assert_eq!(statement.printed_total_credits, expected.printed_total_credits.as_deref().map(parse_dec),
    "{label}: printed_total_credits");
```
All CC fixtures except Yes/IOB **omit** the keys → `None` (unchanged). Three reconcile tests are added
(`yes_statement_reconciles`, `iob_statement_reconciles`, `statement_without_printed_totals_is_neutral`)
using `reconcile_statement` + `ReconcileStatus` (D13). Amounts stay **strings**, re-parsed via
`Decimal::from_str` (never `f64`).

---

## State & lifecycle

Stateless and pure. `reconcile(&statement)` is two linear passes (the direction-partitioned sums) plus a
constant-time tier decision; no persistence, no shared-state mutation, no ordering dependence beyond the
row order (which does not affect the sums). Repeated calls on identical input yield identical results
(FR-018; asserted by determinism over the extended vectors). The reader `enrich` additions are likewise
pure single-pass regex scrapes over `full_text`.

---

## Validation rules (traceability)

| Rule | Source |
|---|---|
| Pure per-statement check → one of RECONCILED / NEEDS_REVIEW / neutral + audit detail | FR-001, SC-001 |
| Sums over **all** rows by direction; empty ⇒ 0.00; exact `Decimal` | FR-002, SC-012 |
| Read-only — never drop/mutate/reorder a row | FR-003, US5, SC-009 |
| Neutral outcome (`status None`) **≠** NEEDS_REVIEW | FR-004, US3, SC-006 |
| Any printed total present ⇒ primary path; fallback never consulted | FR-005, SC-008 |
| Per-side `(read − printed).abs() <= 1.00`; exactly 1.00 is within | FR-006, SC-004 |
| RECONCILED iff every **present** total passes; else NEEDS_REVIEW | FR-007, edge cases |
| Fallback: both balances present ⇒ `(computed − expected).abs() <= 1.00` | FR-008, SC-007 |
| One-or-neither balance ⇒ neutral (fallback needs both) | FR-009 |
| Audit detail per tier (read sums + printed totals / expected+computed change / reason) | FR-010, SC-010 |
| Model gains `printed_total_debits` / `printed_total_credits`, `None` when unprinted | FR-011 |
| Yes surfaces printed debit (Purchases…Dr) + credit (Payment & Credits Received…Cr); same-line only | FR-012, SC-011 |
| IOB surfaces printed credit (2nd) + debit (3rd) from ACCOUNT SUMMARY | FR-013, SC-011 |
| Other parsed fields byte-for-byte unchanged (only totals added) | FR-014, SC-011 |
| The four no-total readers reconcile to neutral (verify, don't invent totals) | FR-015, SC-006 |
| CC counterpart of `balance_chain`; reuse types/harness/bridge/gate; no new dep or shared helper | FR-016, SC-017 |
| All money exact `Decimal`, never float | FR-017, SC-012 |
| Pure & deterministic; no network/clock/locale/global state; no PDF/file I/O | FR-018, SC-013 |
| Reachable over UniFFI via `reconcile_statement`, mirroring `check_balance_chain` | FR-019, SC-015 |
| Zero network in the reconcile path; privacy-egress gate covers it | FR-020/022, SC-016 |
| No telemetry/analytics/crash reporter added | FR-021 |
| Web engine pinned as source of truth; ₹1.00, precedence, fallback, neutral reproduced exactly | FR-023, SC-001/014 |
| Golden vectors cover all three verdicts; Yes/IOB extended → RECONCILED | FR-024/025, SC-002/003/014 |
| Synthetic/redacted fixture data only | FR-026, SC-018 |
| Test-first (failing golden/parity precedes behaviour) | FR-027 |
| No secrets; Apache-2.0; no copyleft; **no new runtime/dev dependency** | FR-028, SC-018 |
| iOS Local Verification Gate + CI green | FR-029, SC-018 |
