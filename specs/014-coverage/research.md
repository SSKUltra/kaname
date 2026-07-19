# Phase 0 — Research: On-Device Statement Coverage Map (the pure `coverage.py` port; zero new deps)

**Feature**: `014-coverage` | **Date**: 2026-07-19
**Method**: The web engine is the source of truth. Its `coverage.py` — the `month_window(today, count)` helper and
the `compute_coverage` classification loop (the GAP / PARTIAL / COVERED + `needsReview` decision), pinned at
`COVERAGE_MONTHS = 24` — and its parity test (`test_statement_coverage`) were **read as ground truth**. The two
ported functions (`month_window` label generation and the `compute_coverage` classification) were **verified**
against a throwaway simulation of the locked algorithm on the reference scenario (run, then discarded — repo left
clean). Every decision below is a faithful port or a justified, verified idiomatic mapping.

All NEEDS CLARIFICATION are resolved; the approach was **locked by the requester** and confirmed here with
evidence. **Headline finding: this slice needs no new dependency and no new shared engine helper beyond the
classifier, the window helper, and their input/output types — it adds a new top-level `coverage.rs` module and is
exposed exactly like `cross_source_duplicates`. The only non-mechanical points are the FFI-wrapper name-clash
(D7), the `Serialize`/`Deserialize` derives added so the fixture harness can deserialize expected entries (D5),
and the `earliest`-cutoff month attribution that ignores out-of-window and future-month facts (D8).**

---

## D1 — New top-level `coverage.rs` module (sibling to `dedup.rs`)

**Decision**: Add a **new top-level module** `core/crates/kaname-core/src/coverage.rs` (wired with `pub mod
coverage;` in `lib.rs`), holding the `CoverageState` enum, the `StatementCoverage` / `TransactionCoverage` input
records, the `MonthCoverage` output record, `COVERAGE_MONTHS = 24`, and the pure `month_window` /
`compute_coverage` functions + unit tests. Reuse, unchanged: the shared `chrono::NaiveDate` date type, the
parity harness (`tests/parity.rs`), the UniFFI bridge (`ffi.rs` + `uniffi.toml`), and the privacy-egress gate +
CI. The one FFI export lives in `ffi.rs`, as `cross_source_duplicates` / `reconcile_statement` /
`check_balance_chain` do.

**Rationale**: Coverage is a **distinct classification concern** from parsing (`statement/*`), reconciliation
(`statement/reconcile.rs`), the balance-chain (`statement/balance_chain.rs`), and cross-source de-dup
(`dedup.rs`). A dedicated sibling module keeps the diff surgical and self-contained and mirrors how each prior
check got its own home. The requester's locked design specifies "top-level like `dedup.rs`", which this follows
exactly.

**Alternatives**: Folding coverage into `statement/` — rejected: it is not a statement reader and does not use
the `ParsedStatement`/`Word` machinery. Folding into `dedup.rs` — rejected: unrelated logic; the module is named
for de-dup. A submodule under a new `analytics/` tree — rejected: unnecessary nesting for one classifier + one
helper + three types.

---

## D2 — Port `month_window(today, count)` verbatim (Datelike + decrement-then-reverse)

**Decision**: `pub fn month_window(today: NaiveDate, count: u32) -> Vec<String>` — the exact port of the web
`month_window`:

```rust
pub fn month_window(today: NaiveDate, count: u32) -> Vec<String> {
    let mut year = today.year();      // chrono::Datelike
    let mut month = today.month();    // 1..=12
    let mut labels = Vec::with_capacity(count as usize);
    for _ in 0..count {
        labels.push(format!("{year:04}-{month:02}"));
        if month == 1 {
            month = 12;
            year -= 1;
        } else {
            month -= 1;
        }
    }
    labels.reverse();                 // oldest first
    labels
}
```

Start at `today`'s `(year, month)`; push `"{:04}-{:02}"` for `count` iterations, decrementing the month each
step (wrapping `1 → 12`, year − 1); then `reverse()` so the result is **oldest first**. Uses only
`chrono::Datelike` (`today.year()`, `today.month()`) — no wall-clock, no locale.

**Rationale**: This is a 1:1 port of the web helper. Building the labels from `today`'s calendar month (not the
day) means a `today` on the first or last of the month yields the same window (FR-002, spec US4 scenario 3). The
zero-padded `{:04}-{:02}` `"YYYY-MM"` format matches the web string keys exactly, which is what the classifier and
the fixture compare against.

**Verified**: `month_window(2026-06-14, 24)` = 24 labels, `[0] == "2024-07"`, `[23] == "2026-06"` (Verification
below; FR-002, SC-002).

**Alternatives**: A `chrono`-arithmetic subtraction of months — rejected: more surface area (month subtraction is
not a first-class `chrono` op and would need `checked_sub_months`/`Months`), and the decrement-then-reverse loop
is the literal web algorithm (parity). Returning typed `(year, month)` pairs — rejected: the web keys, the map
lookups, the fixture, and the output label are all the `"YYYY-MM"` **string**, so we keep the string.

---

## D3 — Port `compute_coverage` classification verbatim (earliest cutoff, two maps, precedence loop)

**Decision**: `pub fn compute_coverage(today: NaiveDate, statements: &[StatementCoverage], transactions:
&[TransactionCoverage]) -> Vec<MonthCoverage>` — the exact port of the `coverage.py` classification (its lines
84–100):

1. `let window = month_window(today, COVERAGE_MONTHS);` (24 labels, oldest first).
2. `earliest` = the **first day of the oldest window month**:
   `NaiveDate::from_ymd_opt(window[0][..4].parse::<i32>().unwrap(), window[0][5..7].parse::<u32>().unwrap(),
   1).unwrap()`.
3. Build `txn_by_month: HashMap<String, bool>` (month → **has_full**): for each transaction with `date >=
   earliest`, key `= format!("{:04}-{:02}", date.year(), date.month())`, **OR-in** `from_full_statement`.
4. Build `stmt_by_month: HashMap<String, bool>` (month → **needs_review**): for each statement with `period_end
   >= earliest`, key from `period_end`, **OR-in** `needs_review`.
5. For each `label` in `window`:
   - `has_txn = txn_by_month.contains_key(label)`;
   - `has_full = *txn_by_month.get(label).unwrap_or(&false)`;
   - `covered_by_statement = stmt_by_month.contains_key(label)`;
   - if `covered_by_statement || (has_txn && has_full)` →
     `MonthCoverage { month: label.clone(), state: Covered, needs_review: *stmt_by_month.get(label).unwrap_or(&false) }`;
   - else if `has_txn` → `{ Partial, needs_review: false }`;
   - else → `{ Gap, needs_review: false }`.

Uses `std::collections::HashMap` (std) + `chrono::Datelike`. The `OR-in` bucket is
`*map.entry(key).or_insert(false) = *map.get(&key).unwrap_or(&false) || flag;` (or the equivalent
`entry(...).or_insert(false)` update), preserving the web's `map[key] = map.get(key, False) or flag` semantics.

**Rationale**: A direct transcription of the pinned web loop. The two COVERED paths (a statement fact in the
month, **or** a full-statement transaction in the month) reproduce FR-005; PARTIAL-when-any-transaction /
GAP-otherwise reproduces FR-006; the OR-of-flags per month reproduces the "multiple facts in one month" edge case
(spec Edge Cases). Iterating over `window` (not over the maps) guarantees exactly **24** entries, oldest first,
regardless of input (FR-001, SC-001, SC-007).

**Verified**: On the reference scenario the loop yields `2026-01` COVERED/false, `2026-02` COVERED/true, `2026-04`
PARTIAL/false, `2026-05` COVERED/false, other 20 GAP/false (Verification below; FR-005/006, SC-003).

**Alternatives**: Classifying by iterating the fact maps and back-filling GAPs — rejected: iterating the window is
the web order and trivially guarantees the 24-entry, oldest-first invariant. A single combined map — rejected: the
two facts carry different booleans (`has_full` vs `needs_review`) and are keyed independently, exactly as the web
keeps `txn_by_month` and `stmt_by_month` separate.

---

## D4 — `needsReview` comes from statements only (never from transaction-only coverage)

**Decision**: A month's `needsReview` is `*stmt_by_month.get(label).unwrap_or(&false)` — the **logical OR** over
the directly-imported statement facts attributed to that month — and it is read **only on the COVERED branch**.
PARTIAL and GAP months are always `needsReview = false`. A month COVERED **solely** via a full-statement
transaction (no statement fact for that month) therefore has `needsReview = false` (its `stmt_by_month` lookup
misses → default `false`).

**Rationale**: This reproduces the web `stmt_by_month.get(label, False)` default exactly (spec Assumptions,
FR-007, US3). `needsReview` semantically means "a directly-imported statement **run** was incomplete (PARTIAL) or
failed reconciliation (NEEDS_REVIEW)"; a transaction that merely came from a full statement carries no such run
verdict, so it cannot raise the badge. Reading it only on the COVERED branch pins PARTIAL/GAP to `false`
structurally (they never touch `stmt_by_month`).

**Verified**: In the reference scenario `2026-05` is COVERED by both a statement (`period_end 2026-05-16`,
needs_review **false**) and a full-statement transaction, and comes out `needsReview = false`; `2026-01` is COVERED
**only** via a full-statement transaction (`2026-01-20`) with no statement fact, and comes out `needsReview =
false`; `2026-02` is COVERED by a needs-review statement (`2026-02-28`, true) and comes out `needsReview = true`
(Verification below; SC-004/005).

**Alternatives**: OR-ing a transaction-derived "review" signal — rejected: transactions carry no run verdict and
the web never does this (parity break). Defaulting `needsReview` on PARTIAL/GAP to anything but `false` — rejected:
contradicts FR-007.

---

## D5 — Types & derives (`CoverageState`, the two input records, `MonthCoverage`)

**Decision**: Four types in `coverage.rs`, with derives matching the codebase precedent (`Direction` /
`Transaction` in `model.rs`; `DedupLayer` / `CrossSourceMatch` in `dedup.rs`):

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum CoverageState { Gap, Partial, Covered }

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StatementCoverage { pub period_end: NaiveDate, pub needs_review: bool }

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct TransactionCoverage { pub date: NaiveDate, pub from_full_statement: bool }

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct MonthCoverage { pub month: String, pub state: CoverageState, pub needs_review: bool }

pub const COVERAGE_MONTHS: u32 = 24;
```

- **`CoverageState`** is fieldless, so `Copy` + `Eq` are safe; it derives `Serialize`/`Deserialize` (serde maps
  the unit variants to the strings `"Gap"`/`"Partial"`/`"Covered"`) **and** `uniffi::Enum` (Swift
  `.gap`/`.partial`/`.covered`). Mirrors `Direction`/`DedupLayer`.
- **`StatementCoverage` / `TransactionCoverage`** are the two input facts, one per imported statement / one per
  transaction. They derive `Debug/Clone/PartialEq/uniffi::Record`. They do **not** need serde: the parity harness
  builds them from typed rows (parsing ISO dates), exactly as the dedup loader builds `Transaction` via
  `Transaction::new`.
- **`MonthCoverage`** additionally derives `Serialize`/`Deserialize` **so the fixture harness can deserialize the
  expected entries** directly (its `state: CoverageState` field relies on `CoverageState`'s serde derives). This
  is the same test-serialisation convenience 013 applied to `DedupLayer` (add serde so `"Canonical"`/`"Fuzzy"`
  deserialize) — here it is applied to the output record and its enum so an `expected_months` array
  deserialises straight into `Vec<MonthCoverage>`-shaped rows. It does not affect the FFI surface.

**Rationale**: `bool` flags cross UniFFI natively; `NaiveDate` crosses as an ISO string via the custom type
already registered in `ffi.rs` (D8); `String` month labels cross natively. The derive sets are the minimum that
the FFI, the tests, and the fixture need, matching existing types.

**Alternatives**: A typed `Month`/`YearMonth` value object instead of a `String` label — rejected: the web uses
the `"YYYY-MM"` string throughout (keys, output, fixture), and a string keeps parity and the map lookups trivial.
Serialising the two input records too — rejected: unnecessary; the loader constructs them from typed fields (the
fixture stores `period_end`/`date` as ISO strings that the loader parses to `NaiveDate`, mirroring the dedup
loader).

---

## D6 — `COVERAGE_MONTHS = 24`; the window helper keeps a `count` parameter for testability

**Decision**: Export `pub const COVERAGE_MONTHS: u32 = 24;`. `compute_coverage` always calls
`month_window(today, COVERAGE_MONTHS)`, but `month_window` retains its `count` parameter (matching the web
`month_window(today, count)` signature) so a unit test can pin a small window and the 24-month behaviour is a
single named constant.

**Rationale**: Matches the web `COVERAGE_MONTHS = 24` and its parameterised `month_window`. Keeping `count` a
parameter (rather than hard-coding 24 inside the helper) preserves the web signature and makes `month_window`
independently testable (spec Assumptions: "The window helper accepts a count for testability, but the coverage map
uses 24").

**Alternatives**: Hard-code 24 inside `month_window` — rejected: diverges from the web signature and reduces
testability.

---

## D7 — FFI wrapper name-clash: import coverage **types only**, call the pure fn fully-qualified

**Decision**: The exported bridge function is named `compute_coverage`, which **shadows** the pure
`coverage::compute_coverage`. To avoid the clash, `ffi.rs` imports only the coverage **types**
(`use crate::coverage::{MonthCoverage, StatementCoverage, TransactionCoverage};`) — **not** the pure function —
and calls it fully-qualified:

```rust
#[uniffi::export]
pub fn compute_coverage(
    today: NaiveDate,
    statements: Vec<StatementCoverage>,
    transactions: Vec<TransactionCoverage>,
) -> Vec<MonthCoverage> {
    crate::coverage::compute_coverage(today, &statements, &transactions)
}
```

The FFI takes **owned** `Vec`s (UniFFI passes owned collections) and `today` **by value** (`NaiveDate` is `Copy`),
then calls the pure function with borrowed slices `&statements` / `&transactions` and `today` by value —
mirroring how `cross_source_duplicates` (ffi) wraps `crate::dedup::cross_source_duplicates(&existing,
&incoming)`. `lib.rs` re-exports **only the FFI wrapper** at the crate root
(`pub use ffi::compute_coverage;`) plus the coverage **types + the `month_window` helper**
(`pub use coverage::{CoverageState, MonthCoverage, StatementCoverage, TransactionCoverage, month_window};`). The
pure `coverage::compute_coverage` is **not** re-exported at the crate root (name clash) — `tests/parity.rs` and
Swift use the FFI-exported one via `kaname_core::compute_coverage`.

**Rationale**: This is exactly the pattern 013 established (`pub use ffi::cross_source_duplicates;`, and the pure
`dedup::cross_source_duplicates` deliberately not re-exported). Passing `today` by value is correct because the
pure signature is `compute_coverage(today: NaiveDate, …)` (`NaiveDate: Copy`), so no `&today` is needed. The pure
function borrows the fact slices so the FFI's owned `Vec`s are passed as `&`.

**Alternatives**: Re-export both functions under different names — rejected: the requester's locked design fixes
the exported name as `compute_coverage`; aliasing would diverge from the pinned Swift name `computeCoverage` and
the 013 precedent. Making the pure fn take `&NaiveDate` — rejected: `NaiveDate` is `Copy`; by-value is idiomatic
and matches the locked signature.

---

## D8 — `NaiveDate` crosses as an ISO string (reuse the registered custom type); `earliest` cutoff ignores out-of-window & future facts

**Decision**: Reuse the **already-registered** `uniffi::custom_type!(NaiveDate, String, …)` in `ffi.rs`
(ISO-8601 `%Y-%m-%d` ↔ `String` ↔ Swift). `StatementCoverage.period_end`, `TransactionCoverage.date`, and the
`today` parameter all cross as ISO strings; `MonthCoverage.month` is already a `String`. **No `uniffi.toml`
change, no new custom type.** Fact attribution and out-of-window handling follow the web exactly:

- A **transaction** is attributed to the calendar month of its `date`; a **statement** to the month of its
  `period_end` (FR-008).
- A fact **before** `earliest` (the first day of the oldest window month) is **skipped** when building the maps
  (the `date >= earliest` / `period_end >= earliest` guard) → it never affects any label (FR-009, spec Edge
  Cases).
- A fact in a **future** month (beyond `today`'s month) passes the `earliest` guard and lands in the map, but its
  `"YYYY-MM"` key is **not in `window`**, so it is **never represented** in any of the 24 output entries (spec
  Edge Cases). The map still contains exactly the 24 window months in the output because the output is built by
  iterating `window`, not the maps.

**Rationale**: The custom type + the `earliest` cutoff + the window-driven output loop together reproduce the web
behaviour and the spec's edge cases without any new bridge machinery. No money is involved, so the `Decimal`
custom type is irrelevant here.

**Verified**: The reference scenario's earliest is `2024-07-01`; all its facts fall inside the window and are
represented; a hypothetical fact dated `2024-06-30` (before earliest) or `2026-07-xx` (a future month) does not
change any of the 24 entries (Verification below; FR-009).

**Alternatives**: A new date custom type or passing raw `(year, month)` — rejected: the ISO-string `NaiveDate`
custom type is already the bridge convention for every reader; reuse it. Clamping future facts differently —
rejected: the web simply never has a label for them; the window-driven loop already yields that.

---

## D9 — New golden-fixture **shape** under `fixtures/coverage/`; the parity loader is additive

**Decision**: Introduce a **new fixture shape** `fixtures/coverage/basic.json`:

```jsonc
{ "_comment", "today": "YYYY-MM-DD",
  "statements":   [ { "period_end": "YYYY-MM-DD", "needs_review": bool } ],
  "transactions": [ { "date": "YYYY-MM-DD", "from_full_statement": bool } ],
  "expected_months": [ { "month": "YYYY-MM", "state": "Gap|Partial|Covered", "needs_review": bool } ]  // ×24
}
```

Add a **new, coverage-only** loader + one test (`coverage_map_matches_expected`) to `tests/parity.rs`; the
existing statement `Fixture`/`Expected`/`CASES` and every current test (including the dedup loader/test) are
**untouched**. The loader deserialises into typed rows (`StmtRow { period_end: String, needs_review: bool }`,
`TxnRow { date: String, from_full_statement: bool }`, `ExpectedMonth { month: String, state: CoverageState,
needs_review: bool }`), parses the ISO dates to `NaiveDate`, builds the typed `StatementCoverage` /
`TransactionCoverage` inputs, calls `compute_coverage`, and asserts the returned `Vec<MonthCoverage>` equals the
24 expected entries.

**Rationale**: The classifier's input is `today` + two fact lists (not a statement), so it needs a shape distinct
from the per-statement `lines`/`full_text`/`expected.rows` schema — exactly as 013 added the two-list
`existing`/`incoming`/`expected_matches` shape under `fixtures/dedup/`. Dates are stored as ISO **strings** and
re-parsed (no ambiguity), all data synthetic (FR-018/019).

**Alternatives**: Reuse the statement fixture schema — rejected: wrong shape. Store `state` as an int — rejected:
the `"Gap"/"Partial"/"Covered"` strings deserialise straight into `CoverageState` via its serde derives and are
human-readable.

---

## D10 — No new dependency (`std::collections::HashMap` + `chrono::Datelike` only); no money → no `f64`/`Decimal` concern

**Decision**: The classifier uses only `std::collections::HashMap` (std) and `chrono::Datelike` (already a
transitive-and-direct dependency via `NaiveDate`). **No new runtime or dev dependency.** No monetary value is
computed anywhere in coverage — it classifies **dates and states** — so the "money is never a float" rule has no
comparison to make here (there is no `Decimal` and no `f64` in the module).

**Rationale**: FR-021 / SC-011 require zero new dependencies; the map + `Datelike` suffice. Unlike 013 (which
hand-rolled Jaro-Winkler to avoid `rapidfuzz`), coverage needs nothing beyond std + `chrono`, so there is not even
a hand-roll to justify.

**Alternatives**: A `BTreeMap` for deterministic map iteration — unnecessary: the output order comes from
iterating `window` (a `Vec`), not the map, so `HashMap`'s unordered iteration never reaches the output;
determinism is guaranteed regardless (D11). A date-math crate — rejected: `chrono` is already present and
sufficient.

---

## D11 — Purity, determinism, totality (never reads the clock; never panics on empty input)

**Decision**: `month_window` and `compute_coverage` are **pure, deterministic, and total**: no network, no
wall-clock (the window is derived from the `today` **parameter**), no locale, no global mutable state, no file/DB/
PDF I/O. Empty `statements` **and** empty `transactions` → 24 GAP/false entries (never a panic). The only
`unwrap`s are on `NaiveDate::from_ymd_opt(year, month, 1)` (a valid year/month always yields a valid first-of-
month) and the `window[0][..4]/[5..7]` parses (the labels are always `"YYYY-MM"` produced by `month_window`), both
of which are total by construction.

**Rationale**: Determinism is a Constitution gate (Principle II) and a correctness property of the whole feature
(FR-003, spec US4). Because the output is built by iterating the fixed 24-label `window`, the result is fully
determined by `(today, statements, transactions)` and is byte-identical across runs. `HashMap`'s randomised
iteration order is irrelevant (D10). Empty input hits only the GAP branch.

**Verified**: Re-running the reference scenario yields identical output; empty input yields 24 GAP/false
(Verification below; SC-006/007).

**Alternatives**: Reading `chrono::Local::now()` for `today` — **forbidden** (Constitution II; the whole point of
passing `today` in). Returning a `Result` — rejected: the function is total; a `Vec` is the honest type.

---

## D12 — Swift bridge test mirrors the `ReconcileTests` / `CrossSourceDedupTests` precedent

**Decision**: `ios/Tests/CoverageTests.swift` (Swift Testing, `import KanameCore`) builds the reference inputs
(`StatementCoverage(periodEnd: "2026-05-16", needsReview: false)` etc.; `TransactionCoverage(date: "2026-04-10",
fromFullStatement: false)` etc.), calls `computeCoverage(today: "2026-06-14", statements:, transactions:)`,
asserts `count == 24`, and — indexing the result by `month` — asserts `2026-05` `.covered`/false, `2026-02`
`.covered`/true, `2026-04` `.partial`, `2026-01` `.covered`/false, and a sample GAP month `.gap`. Any comment sits
on its **own line above** the code (swift-format `[Spacing]` forbids trailing inline `//`). Requires `make
core-xcframework` before `tuist generate`.

**Rationale**: Mirrors how `ReconcileTests`/`CrossSourceDedupTests` prove the bridge surface. Indexing by `month`
(a `Dictionary(uniqueKeysWithValues:)` keyed on `$0.month`) is the clean way to assert specific months regardless
of position, while `count == 24` pins the size. Swift lower-camel-cases the record fields
(`periodEnd`/`needsReview`/`fromFullStatement`) and the enum cases (`.gap`/`.partial`/`.covered`).

**Alternatives**: Asserting by array position — rejected: brittle; indexing by month label is clearer and matches
what a UI would do. Snapshot the whole 24 — unnecessary for a bridge smoke test (the parity harness already pins
all 24 on the Rust side).

---

## Verification (throwaway simulation of the locked algorithm — repo left clean)

To pin the fixture bytes and the unit-test expectations, the locked `month_window` + `compute_coverage` algorithm
was transcribed into a throwaway script and run on the reference scenario, then discarded (no file committed):

- **`month_window(2026-06-14, 24)`** → 24 labels, `[0] == "2024-07"`, `[23] == "2026-06"`. ✅ (FR-002, SC-002)
- **Reference scenario** — `today = 2026-06-14`; statements `period_end 2026-05-16`/needs_review **false** +
  `2026-02-28`/**true**; transactions `2026-04-10`/from_full **false** + `2026-05-05`/**true** +
  `2026-01-20`/**true**; `earliest = 2024-07-01` →
  - `2026-01` **Covered / false** (full-statement txn only; no statement fact → needsReview defaults false — D4)
  - `2026-02` **Covered / true** (statement fact, needs_review true)
  - `2026-04` **Partial / false** (alert-only txn, no full statement)
  - `2026-05` **Covered / false** (statement fact needs_review false **and** full-statement txn)
  - the other **20** months **Gap / false**
  - **24** total, **20** GAP, **0** misclassifications. ✅ (FR-005/006/007, SC-003/004/005)
- **Empty input** (`statements = []`, `transactions = []`) → 24 **Gap / false**, no panic. ✅ (SC-007)
- **Determinism** — re-running the reference scenario yields byte-identical output. ✅ (SC-006)
- **Out-of-window / future facts** — a fact dated before `2024-07-01` (skipped by the `>= earliest` guard) or in
  a future month (`2026-07…`, no matching `window` label) changes **none** of the 24 entries. ✅ (FR-009)

The exact 24-entry `expected_months` array these values produce is written verbatim into
`fixtures/coverage/basic.json` (bytes in [`contracts/golden-fixture.md`](./contracts/golden-fixture.md)).

**Output**: all unknowns resolved; the two ported functions are verified; the fixture and unit-test expectations
are pinned. Proceed to Phase 1.
