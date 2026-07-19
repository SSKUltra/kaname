# Contract: Coverage Classifier (`coverage::month_window` + `coverage::compute_coverage`) — internal Rust seam

**Feature**: `014-coverage` | **Date**: 2026-07-19
**Module**: `kaname-core::coverage`

The pure, in-memory **rolling-24-month GAP / PARTIAL / COVERED + `needsReview`** classifier — the on-device port
of the web engine's `coverage.py` (`month_window` + the classification loop). This is a **stable behaviour
contract**: given a `today` date and two pre-aggregated fact lists, `compute_coverage` returns exactly **24**
month entries (oldest first), each with a `"YYYY-MM"` label, a state, and a `needsReview` flag; and it is **pure,
deterministic, total**, and **never reads the wall-clock**. No database, no clock, no new dependency, no money.

---

## `coverage::month_window` — the deterministic rolling window

```rust
pub fn month_window(today: NaiveDate, count: u32) -> Vec<String>
```

**Input**: `today` (by value; `Copy`), `count`. **Output**: `count` `"YYYY-MM"` labels, **oldest first**, ending
at `today`'s calendar month.

**Algorithm (exact web order)**: read `today.year()` / `today.month()` (`chrono::Datelike`); for `count`
iterations push `format!("{year:04}-{month:02}")` then decrement the month (wrap `1 → 12`, `year -= 1`);
`reverse()`.

- Derived from the `today` **parameter** — **never** reads the wall-clock (FR-003).
- A `today` on the first or last day of a month yields the same window (the day is ignored; FR-002, US4-3).
- **Reference**: `month_window(2026-06-14, 24)` = `["2024-07", …, "2026-06"]` (24 labels; `[0] == "2024-07"`,
  `[23] == "2026-06"`) (FR-002, SC-002).

---

## `coverage::compute_coverage` — the classifier

```rust
pub fn compute_coverage(
    today: NaiveDate,
    statements: &[StatementCoverage],
    transactions: &[TransactionCoverage],
) -> Vec<MonthCoverage>
```

**Inputs**: `today` (by value) and two **borrowed** slices — `statements` (one `StatementCoverage { period_end,
needs_review }` per imported statement) and `transactions` (one `TransactionCoverage { date, from_full_statement }`
per transaction), each already scoped to **one account** by the caller. Neither is mutated.

**Output**: `Vec<MonthCoverage>` — **exactly 24** entries, **oldest first** (one per window label), each
`MonthCoverage { month, state, needs_review }`.

### Steps (pinned to the web loop)

1. `window = month_window(today, COVERAGE_MONTHS)` (`COVERAGE_MONTHS == 24`).
2. `earliest` = **first day of the oldest window month** = `NaiveDate::from_ymd_opt(window[0][..4] as i32,
   window[0][5..7] as u32, 1)`.
3. `txn_by_month: HashMap<String, bool>` (month → `has_full`): for each transaction with `date >= earliest`,
   key = `"{:04}-{:02}"` of `(date.year(), date.month())`, **OR-in** `from_full_statement`.
4. `stmt_by_month: HashMap<String, bool>` (month → `needs_review`): for each statement with `period_end >=
   earliest`, key from `period_end`, **OR-in** `needs_review`.
5. For each `label` in `window`, classify (table below).

### Classification (per window label)

| Condition (in order) | `state` | `needs_review` |
|---|---|---|
| `covered_by_statement \|\| (has_txn && has_full)` | `Covered` | `*stmt_by_month.get(label).unwrap_or(&false)` |
| else `has_txn` | `Partial` | `false` |
| else | `Gap` | `false` |

where `has_txn = txn_by_month.contains_key(label)`, `has_full = *txn_by_month.get(label).unwrap_or(&false)`,
`covered_by_statement = stmt_by_month.contains_key(label)`.

### Guards & attribution (the whole decision surface)

| Aspect | Rule |
|---|---|
| **COVERED path (a)** | a **statement** fact whose `period_end` falls in the month (`covered_by_statement`) |
| **COVERED path (b)** | a **transaction** in the month whose `from_full_statement` is true (`has_txn && has_full`) |
| **PARTIAL** | not COVERED **and** the month has ≥ 1 transaction (`has_txn`) |
| **GAP** | not COVERED and no transaction |
| **`needsReview`** | OR over the month's **statement** facts' `needs_review`, read **only** on the COVERED branch; PARTIAL/GAP always `false`; COVERED-via-txn-only defaults `false` |
| **Transaction month** | calendar month of `date` |
| **Statement month** | calendar month of `period_end` |
| **Out-of-window fact** | `date`/`period_end` `< earliest` → **skipped** (never affects a label) |
| **Future-month fact** | passes `earliest` but its `"YYYY-MM"` key is not in `window` → **never represented** |

### Invariants

- **Exactly 24, oldest first**: one entry per window label, in window order, for any input (FR-001, SC-001).
- **COVERED precedence**: COVERED wins over PARTIAL when both a full-coverage signal and other transactions exist;
  PARTIAL wins over GAP when any transaction exists (spec Edge Cases).
- **Multiple facts in one month**: `needsReview` is the logical OR over that month's statement facts; a month is
  COVERED regardless of how many facts establish it (spec Edge Cases).
- **`needsReview` from statements only**: never raised by transaction-only coverage (FR-007, D4, SC-005).
- **Read-only**: `statements`/`transactions` are borrowed `&` and never mutated, dropped, reordered, or persisted.
- **Purity / totality**: no I/O, no network/**clock**/locale, no global mutable state, no file/DB/PDF; identical
  input ⇒ identical output; empty input ⇒ 24 GAP/false; never panics (FR-003/011, SC-006/007).
- **No money**: coverage classifies dates/states only — no `Decimal`, no `f64` (spec Assumptions).

---

## Golden behaviour (verified end-to-end — the parity target)

Fixture `fixtures/coverage/basic.json` (exact bytes in [`golden-fixture.md`](./golden-fixture.md)), one scenario
run through the locked algorithm (verified — research Verification):

`today = 2026-06-14`; statements `2026-05-16`/needs_review **false** + `2026-02-28`/**true**; transactions
`2026-04-10`/from_full **false** + `2026-05-05`/**true** + `2026-01-20`/**true**; `earliest = 2024-07-01`.

| Month | Why | Result |
|---|---|---|
| `2026-01` | full-statement txn only (`2026-01-20`), no statement fact | **Covered / false** |
| `2026-02` | statement fact `2026-02-28`, needs_review **true** | **Covered / true** |
| `2026-04` | alert-only txn `2026-04-10`, no full statement | **Partial / false** |
| `2026-05` | statement `2026-05-16` (needs_review false) **and** full-statement txn `2026-05-05` | **Covered / false** |
| the other **20** window months | no fact | **Gap / false** |

24 entries total, 20 GAP, 0 misclassifications (SC-003/004/005).

---

## Unit tests (`coverage.rs`) — mirroring the web logic + the spec edge cases

- **`month_window`**: `month_window(2026-06-14, 24)` has 24 labels, `[0] == "2024-07"`, `[23] == "2026-06"`;
  determinism (same input → same output); a `today` on the 1st/last of the month yields the same window
  (FR-002, SC-002, US4).
- **`compute_coverage` reference scenario**: assert the 4 non-GAP months (`2026-01` Covered/false, `2026-02`
  Covered/true, `2026-04` Partial/false, `2026-05` Covered/false), at least one GAP, and total == 24 (SC-003).
- **Empty input** (`&[]`, `&[]`) → 24 GAP/false, no panic (SC-007).
- **Out-of-window / future fact ignored**: a fact before `earliest` or in a future month changes none of the 24
  entries (FR-009).
- **COVERED-via-full-txn-only → `needsReview` false**: a month covered only by a `from_full_statement` transaction
  (no statement fact) is Covered/false; a month with only alert transactions is Partial (SC-004, D4).
- **Determinism**: re-running the reference scenario yields identical output (SC-006).

Comparison is by `CoverageState`/`bool`/`String` value-equality (no `Decimal`, no `f64`).

---

## Relationship to the shipped checks (the reuse contract)

| | `reconcile::reconcile` / `dedup::cross_source_duplicates` | `coverage::compute_coverage` |
|---|---|---|
| Input | `&ParsedStatement` / two `&[Transaction]` | `today: NaiveDate` + two fact slices |
| Purity | pure/deterministic/total | pure/deterministic/total (**never reads the clock**) |
| Money | exact `Decimal` | **none** (dates/states only) |
| Result | typed record(s) | `Vec<MonthCoverage>` (always 24) |
| FFI wrapper | `reconcile_statement` / `cross_source_duplicates` | `compute_coverage` (types-only import to avoid the name clash) |
| New dependency | none | none (`std::HashMap` + `chrono::Datelike`) |

The web `coverage.py`'s **DB aggregation** (grouping a `transactions`/`statements` store per account) is **not**
ported — the platform supplies the pre-aggregated facts (spec Assumptions, Out of Scope, FR-013). When an
on-device store lands, aggregation can move into the core without changing this classifier's behaviour.
