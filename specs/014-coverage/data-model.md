# Phase 1 — Data Model: On-Device Statement Coverage Map

**Feature**: `014-coverage` | **Date**: 2026-07-19
**Scope**: The types and functions this slice introduces, reuses, and configures — all inside a **new top-level
`coverage` module** + its bridge. It adds **two pure functions** (`month_window` + `compute_coverage`), **one
enum** (`CoverageState`), **two input records** (`StatementCoverage`, `TransactionCoverage`), **one output
record** (`MonthCoverage`), **one constant** (`COVERAGE_MONTHS`), **one FFI wrapper**, **one golden fixture**, and
**tests** — with **no new dependency**, **no `uniffi.toml` change**, and **no reader/`model.rs`/`base.rs`
change**. It reuses the shared `chrono::NaiveDate` date type (ISO-string custom type), the parity harness, and the
UniFFI bridge. No money is involved, so no `Decimal`/`f64` appears in the module.

---

## New types — `core/crates/kaname-core/src/coverage.rs`

### `CoverageState` (NEW) — `uniffi::Enum`

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum CoverageState {
    Gap,
    Partial,
    Covered,
}
```

A month's coverage classification → Swift `.gap` / `.partial` / `.covered`. Fieldless, so `Copy` + `Eq` are safe.
Derives mirror `Direction` (`model.rs`) / `DedupLayer` (`dedup.rs`) **plus** `Serialize`/`Deserialize` so the
fixture harness can deserialize `"Gap"`/`"Partial"`/`"Covered"` straight into the enum (serde maps unit variants
to their name strings) — the same test-serialisation convenience 013 applied to `DedupLayer`.

### `StatementCoverage` (NEW) — `uniffi::Record` — one **input** fact per imported statement

```rust
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StatementCoverage {
    pub period_end: NaiveDate,
    pub needs_review: bool,
}
```

| Field | Rust type | Wire → Swift | Meaning |
|---|---|---|---|
| `period_end` | `NaiveDate` | `String` (ISO-8601) → `periodEnd: String` | the statement's billing period-end; attributes it to that calendar month |
| `needs_review` | `bool` | `Bool` → `needsReview: Bool` | the run was incomplete (PARTIAL) or failed reconciliation |

### `TransactionCoverage` (NEW) — `uniffi::Record` — one **input** fact per transaction

```rust
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct TransactionCoverage {
    pub date: NaiveDate,
    pub from_full_statement: bool,
}
```

| Field | Rust type | Wire → Swift | Meaning |
|---|---|---|---|
| `date` | `NaiveDate` | `String` (ISO-8601) → `date: String` | the transaction's date; attributes it to that calendar month |
| `from_full_statement` | `bool` | `Bool` → `fromFullStatement: Bool` | it came from a full statement (vs a piecemeal live alert) |

### `MonthCoverage` (NEW) — `uniffi::Record` — one **output** entry per window month

```rust
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct MonthCoverage {
    pub month: String,
    pub state: CoverageState,
    pub needs_review: bool,
}
```

| Field | Rust type | Wire → Swift | Meaning |
|---|---|---|---|
| `month` | `String` | `String` → `month: String` | the `"YYYY-MM"` label |
| `state` | `CoverageState` | `CoverageState` → `state` | `Gap` / `Partial` / `Covered` |
| `needs_review` | `bool` | `Bool` → `needsReview: Bool` | true only on a COVERED month backed by a needs-review statement fact |

Derives mirror `CrossSourceMatch`/`ReconcileResult` (`Debug/Clone/PartialEq/uniffi::Record`) **plus**
`Serialize`/`Deserialize` so the parity harness can deserialize an `expected_months` array directly (its `state`
field relies on `CoverageState`'s serde derives). Serde on the output record + its enum is a **test convenience**;
it does not change the FFI surface.

### Constant (NEW, public)

```rust
pub const COVERAGE_MONTHS: u32 = 24; // the rolling window length (web COVERAGE_MONTHS)
```

---

## New functions — `coverage.rs`

### `month_window` (NEW, `pub`) — the deterministic rolling window

```rust
pub fn month_window(today: NaiveDate, count: u32) -> Vec<String>
```

**Algorithm (exact web order — D2)**: read `today.year()` / `today.month()` (`chrono::Datelike`); for `count`
iterations push `format!("{year:04}-{month:02}")` then decrement the month (wrapping `1 → 12`, `year -= 1`);
`reverse()` for oldest-first. Pure, total, deterministic — **never reads the wall-clock** (the window is derived
from the `today` **parameter**). Retains the `count` parameter (web signature) for testability; the coverage map
always passes `COVERAGE_MONTHS`.

- **Inputs**: `today: NaiveDate` (by value; `Copy`), `count: u32`.
- **Output**: `Vec<String>` of `count` `"YYYY-MM"` labels, **oldest first**, ending at `today`'s calendar month.
- **Reference**: `month_window(2026-06-14, 24)` = `["2024-07", …, "2026-06"]` (`[0] == "2024-07"`, `[23] ==
  "2026-06"`).

### `compute_coverage` (NEW, `pub`) — the classifier

```rust
pub fn compute_coverage(
    today: NaiveDate,
    statements: &[StatementCoverage],
    transactions: &[TransactionCoverage],
) -> Vec<MonthCoverage>
```

**Inputs**: `today` (by value), and two **borrowed** slices of the input facts. Neither is mutated.

**Output**: `Vec<MonthCoverage>` — exactly **24** entries, **oldest first** (one per `window` label).

**Algorithm (exact web order — D3)**:

1. `let window = month_window(today, COVERAGE_MONTHS);`
2. `let earliest = NaiveDate::from_ymd_opt(window[0][..4].parse::<i32>().unwrap(),
   window[0][5..7].parse::<u32>().unwrap(), 1).unwrap();` — the first day of the oldest window month.
3. **`txn_by_month: HashMap<String, bool>`** (month → `has_full`): for each `t` in `transactions` with `t.date >=
   earliest`, `key = format!("{:04}-{:02}", t.date.year(), t.date.month())`, **OR-in** `t.from_full_statement`.
4. **`stmt_by_month: HashMap<String, bool>`** (month → `needs_review`): for each `s` in `statements` with
   `s.period_end >= earliest`, `key` from `s.period_end`, **OR-in** `s.needs_review`.
5. For each `label` in `window`:
   - `has_txn = txn_by_month.contains_key(label)`
   - `has_full = *txn_by_month.get(label).unwrap_or(&false)`
   - `covered_by_statement = stmt_by_month.contains_key(label)`
   - **COVERED** iff `covered_by_statement || (has_txn && has_full)` →
     `needs_review = *stmt_by_month.get(label).unwrap_or(&false)`
   - else **PARTIAL** iff `has_txn` → `needs_review = false`
   - else **GAP** → `needs_review = false`

The `OR-in` bucket preserves the web `map[key] = map.get(key, False) or flag` semantics (e.g.
`let e = txn_by_month.entry(key).or_insert(false); *e = *e || t.from_full_statement;`).

- Uses `std::collections::HashMap` (std) + `chrono::Datelike`. **No new dependency.**
- **Pure / deterministic / total** — never reads the clock; never panics on empty input; identical inputs ⇒
  identical output (the output order comes from iterating `window`, not the maps, so `HashMap` iteration order is
  irrelevant).

**Invariants**

- **Exactly 24, oldest first**: the output is one entry per `window` label, in `window` order (FR-001, SC-001).
- **Two COVERED paths**: a statement fact in the month **or** a full-statement transaction in the month (FR-005).
- **PARTIAL vs GAP**: PARTIAL iff any transaction and not COVERED; else GAP (FR-006).
- **`needsReview` from statements only**: the month's OR-of-statement-`needs_review`, read **only** on the COVERED
  branch; PARTIAL/GAP are always `false`; a month COVERED only via a full-statement transaction defaults `false`
  (FR-007, D4).
- **Month attribution**: transaction → month of `date`; statement → month of `period_end` (FR-008).
- **Out-of-window / future facts ignored**: facts before `earliest` are skipped; facts in a future month have no
  `window` label and never appear (FR-009, D8).

---

## Reused types (unchanged)

### `chrono::NaiveDate` — the shared date type (ISO-string custom type)

Reused for `StatementCoverage.period_end`, `TransactionCoverage.date`, and the `today` parameter. Crosses UniFFI
as an ISO-8601 (`%Y-%m-%d`) `String` via the **already-registered** `uniffi::custom_type!(NaiveDate, String, …)`
in `ffi.rs`. **No new custom type, no `uniffi.toml` change** (D8). No `Decimal`/money type is used by this slice.

---

## FFI wrapper — `ffi.rs` (EXTEND)

```rust
use crate::coverage::{MonthCoverage, StatementCoverage, TransactionCoverage}; // TYPES only — not the pure fn

#[uniffi::export]
pub fn compute_coverage(
    today: NaiveDate,
    statements: Vec<StatementCoverage>,
    transactions: Vec<TransactionCoverage>,
) -> Vec<MonthCoverage> {
    crate::coverage::compute_coverage(today, &statements, &transactions)
}
```

Takes **owned** `Vec`s (UniFFI convention) and `today` **by value** (`NaiveDate: Copy`); calls the pure function
with borrowed slices. The wrapper name `compute_coverage` **shadows** the pure function, so `ffi.rs` imports only
the coverage **types** and calls the pure fn **fully-qualified** (D7). Mirrors `cross_source_duplicates` /
`reconcile_statement`.

## Crate re-exports — `lib.rs` (EXTEND)

```rust
pub mod coverage;
// …
pub use ffi::{/* …existing… */ compute_coverage};
pub use coverage::{CoverageState, MonthCoverage, StatementCoverage, TransactionCoverage, month_window};
```

Re-exports the **FFI** `compute_coverage` (the bridge wrapper) + the coverage types + the `month_window` helper
(for the parity/unit tests). The pure `coverage::compute_coverage` is **not** re-exported at the crate root (name
clash — D7); `tests/parity.rs` uses the FFI-exported one via `kaname_core::compute_coverage`.

---

## Parity fixture types — `tests/parity.rs` (EXTEND, additive)

A **new, coverage-only** loader (the statement `Fixture`/`Expected`/`CASES` and the dedup loader are untouched):

```rust
#[derive(Deserialize)]
struct CoverageFixture {
    today: String,
    statements: Vec<StmtRow>,
    transactions: Vec<TxnRow>,
    expected_months: Vec<ExpectedMonth>,
}

#[derive(Deserialize)]
struct StmtRow { period_end: String, needs_review: bool }

#[derive(Deserialize)]
struct TxnRow { date: String, from_full_statement: bool }

#[derive(Deserialize)]
struct ExpectedMonth { month: String, state: CoverageState, needs_review: bool }
```

- `today` / `period_end` / `date` are ISO **strings**, re-parsed via `NaiveDate::parse_from_str(_, "%Y-%m-%d")`
  (no ambiguity). `bool` flags deserialize directly. `state` deserializes into `CoverageState` via its serde
  derives (`"Gap"`/`"Partial"`/`"Covered"`).
- The loader builds `Vec<StatementCoverage>` / `Vec<TransactionCoverage>` from the typed rows, calls
  `compute_coverage(today, statements, transactions)` (the FFI-exported wrapper via `kaname_core`), and asserts
  the returned `Vec<MonthCoverage>` equals the 24 `expected_months` (built into `MonthCoverage` values, or
  compared field-by-field). Imports `compute_coverage`, `MonthCoverage`, `StatementCoverage`,
  `TransactionCoverage`, `CoverageState` from `kaname_core`.

---

## Swift surface (generated by UniFFI) — `ios/Tests/CoverageTests.swift` consumes

| Rust | Swift (generated) |
|---|---|
| `enum CoverageState { Gap, Partial, Covered }` | `.gap` / `.partial` / `.covered` |
| `struct StatementCoverage { period_end: NaiveDate, needs_review: bool }` | `StatementCoverage(periodEnd: String, needsReview: Bool)` |
| `struct TransactionCoverage { date: NaiveDate, from_full_statement: bool }` | `TransactionCoverage(date: String, fromFullStatement: Bool)` |
| `struct MonthCoverage { month: String, state: CoverageState, needs_review: bool }` | `MonthCoverage(month: String, state: CoverageState, needsReview: Bool)` |
| `fn compute_coverage(today, statements, transactions) -> Vec<MonthCoverage>` | `computeCoverage(today: String, statements: [StatementCoverage], transactions: [TransactionCoverage]) -> [MonthCoverage]` |

`NaiveDate` fields cross as ISO-8601 `String`s (`"2026-05-16"`). Field/case names are lower-camel-cased by UniFFI.

---

## Relationship to the shipped checks (the reuse contract)

| | `dedup::cross_source_duplicates` | `coverage::compute_coverage` |
|---|---|---|
| Input | `&[Transaction]` × 2 | `today: NaiveDate` + `&[StatementCoverage]` + `&[TransactionCoverage]` |
| Purity | pure/deterministic/total | pure/deterministic/total (**never reads the clock**) |
| Money | exact `Decimal` (similarity is `f64`) | **none** (classifies dates/states — no `Decimal`, no `f64`) |
| Result | `Vec<CrossSourceMatch>` | `Vec<MonthCoverage>` (always 24) |
| FFI wrapper | `cross_source_duplicates` (ffi) wraps `dedup::…` | `compute_coverage` (ffi) wraps `coverage::…` (name-clash → types-only import) |
| New dependency | none (hand-rolled Jaro-Winkler) | none (`std::HashMap` + `chrono::Datelike`) |
| Module | extends `dedup.rs` | **new** `coverage.rs` (sibling) |
