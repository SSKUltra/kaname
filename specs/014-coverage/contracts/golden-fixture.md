# Contract: Golden-Fixture Schema — coverage-map vectors (NEW shape)

**Feature**: `014-coverage` | **Date**: 2026-07-19
**Consumers**: `core/crates/kaname-core/tests/parity.rs` (a new coverage loader + one test; the statement `CASES`
and the dedup loader/test are untouched).

The classifier's input is a **`today` date + two pre-aggregated fact lists** (not a statement) — so this slice
introduces a **new fixture shape** under `fixtures/coverage/`, distinct from the per-statement
`lines`/`full_text`/`expected.rows` schema and the dedup `existing`/`incoming`/`expected_matches` schema. It adds
**one file** (`basic.json`); no existing fixture changes. All dates are **ISO-8601 strings** (re-parsed to
`NaiveDate`); states are `"Gap"`/`"Partial"`/`"Covered"`; all data synthetic (fabricated dates/states — no real
account data). No amounts/money appear.

---

## Schema

```jsonc
{
  "_comment": "string — provenance + scenario notes (synthetic, no real data)",
  "today": "YYYY-MM-DD",                 // the reference date; the window ends at its calendar month
  "statements": [                        // one fact per imported statement
    { "period_end": "YYYY-MM-DD", "needs_review": <bool> }
  ],
  "transactions": [                      // one fact per transaction
    { "date": "YYYY-MM-DD", "from_full_statement": <bool> }
  ],
  "expected_months": [                   // exactly 24, oldest first (the window months)
    { "month": "YYYY-MM", "state": "Gap|Partial|Covered", "needs_review": <bool> }
  ]
}
```

**Field rules**

- `today`, `period_end`, `date` → `NaiveDate::parse_from_str(_, "%Y-%m-%d")` (ISO strings only — no ambiguity).
- `needs_review`, `from_full_statement` → `bool` directly.
- Each `statements` object maps to `StatementCoverage { period_end, needs_review }`; each `transactions` object to
  `TransactionCoverage { date, from_full_statement }`.
- `expected_months` mirrors `MonthCoverage` (`month` / `state` / `needs_review`), **oldest first**, **exactly 24**
  entries. `state` deserialises to `CoverageState` (`"Gap"`/`"Partial"`/`"Covered"`) via its serde derives.

---

## `fixtures/coverage/basic.json` — exact bytes to write (in implementation, test-first)

Verified end-to-end against the locked algorithm (research Verification): the scenario
(`today = 2026-06-14`; statements `2026-05-16`/false + `2026-02-28`/true; transactions `2026-04-10`/false +
`2026-05-05`/true + `2026-01-20`/true; `earliest = 2024-07-01`) produces exactly `2026-01` Covered/false,
`2026-02` Covered/true, `2026-04` Partial/false, `2026-05` Covered/false, and the other **20** months Gap/false
(24 total).

```json
{
  "_comment": "Synthetic on-device coverage-map golden vector (no real data). Ports the web engine's coverage.py (month_window + the GAP/PARTIAL/COVERED + needsReview classification), pinned at COVERAGE_MONTHS=24. Inputs: a `today` date + pre-aggregated per-account statement facts (period_end + needs_review) and transaction facts (date + from_full_statement); the platform supplies the facts, the engine classifies. All dates are ISO strings (re-parsed to NaiveDate); state Gap|Partial|Covered. Scenario (expected_months captured from the pinned coverage.py logic): today 2026-06-14 → window 2024-07..2026-06 (earliest 2024-07-01). statements: 2026-05-16 needs_review false, 2026-02-28 needs_review true. transactions: 2026-04-10 from_full_statement false (alert-only), 2026-05-05 true (full statement), 2026-01-20 true (full statement). Outcomes: 2026-01 Covered/false (full-statement txn only, no statement fact → needsReview defaults false); 2026-02 Covered/true (needs-review statement); 2026-04 Partial/false (alert-only txn, no full statement); 2026-05 Covered/false (statement needs_review false + full-statement txn); all other 20 window months Gap/false.",
  "today": "2026-06-14",
  "statements": [
    { "period_end": "2026-05-16", "needs_review": false },
    { "period_end": "2026-02-28", "needs_review": true }
  ],
  "transactions": [
    { "date": "2026-04-10", "from_full_statement": false },
    { "date": "2026-05-05", "from_full_statement": true },
    { "date": "2026-01-20", "from_full_statement": true }
  ],
  "expected_months": [
    { "month": "2024-07", "state": "Gap", "needs_review": false },
    { "month": "2024-08", "state": "Gap", "needs_review": false },
    { "month": "2024-09", "state": "Gap", "needs_review": false },
    { "month": "2024-10", "state": "Gap", "needs_review": false },
    { "month": "2024-11", "state": "Gap", "needs_review": false },
    { "month": "2024-12", "state": "Gap", "needs_review": false },
    { "month": "2025-01", "state": "Gap", "needs_review": false },
    { "month": "2025-02", "state": "Gap", "needs_review": false },
    { "month": "2025-03", "state": "Gap", "needs_review": false },
    { "month": "2025-04", "state": "Gap", "needs_review": false },
    { "month": "2025-05", "state": "Gap", "needs_review": false },
    { "month": "2025-06", "state": "Gap", "needs_review": false },
    { "month": "2025-07", "state": "Gap", "needs_review": false },
    { "month": "2025-08", "state": "Gap", "needs_review": false },
    { "month": "2025-09", "state": "Gap", "needs_review": false },
    { "month": "2025-10", "state": "Gap", "needs_review": false },
    { "month": "2025-11", "state": "Gap", "needs_review": false },
    { "month": "2025-12", "state": "Gap", "needs_review": false },
    { "month": "2026-01", "state": "Covered", "needs_review": false },
    { "month": "2026-02", "state": "Covered", "needs_review": true },
    { "month": "2026-03", "state": "Gap", "needs_review": false },
    { "month": "2026-04", "state": "Partial", "needs_review": false },
    { "month": "2026-05", "state": "Covered", "needs_review": false },
    { "month": "2026-06", "state": "Gap", "needs_review": false }
  ]
}
```

### Scenario coverage (why each fact exists)

| Fact | Attributed month | Exercises | Effect on that month |
|---|:-:|---|---|
| statement `2026-05-16` needs_review **false** | `2026-05` | COVERED path (a) + `needsReview` false | **Covered / false** |
| statement `2026-02-28` needs_review **true** | `2026-02` | COVERED path (a) + `needsReview` **true** | **Covered / true** |
| txn `2026-04-10` from_full **false** | `2026-04` | PARTIAL (alert-only, no full statement) | **Partial / false** |
| txn `2026-05-05` from_full **true** | `2026-05` | COVERED path (b) co-occurring with a statement (COVERED precedence) | (already Covered / false) |
| txn `2026-01-20` from_full **true** | `2026-01` | COVERED path (b) **only** (no statement fact) → `needsReview` defaults false | **Covered / false** |

This single vector pins all three states (GAP × 20, PARTIAL, COVERED), **both** `needsReview` values, the two
COVERED paths (statement-fact vs full-statement-transaction), the statement-only `needsReview` default (`2026-01`
Covered/false), and the oldest-first 24-entry window (`2024-07` → `2026-06`) — covering FR-017/018 and SC-003/004/
005 in one file. (Empty-input GAP-only, out-of-window/future-fact exclusion, and the `month_window` endpoints are
pinned by the `coverage.rs` unit tests.)

---

## Parity harness behaviour (contract)

A **new, coverage-only** loader + test is added to `tests/parity.rs`; the existing statement `Fixture` /
`Expected` / `CASES`, the dedup loader/test, and every current test are **unchanged**.

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

#[test]
fn coverage_map_matches_expected() {
    let raw = std::fs::read_to_string(format!(
        "{}/../../../fixtures/coverage/basic.json", env!("CARGO_MANIFEST_DIR")
    )).unwrap();
    let fx: CoverageFixture = serde_json::from_str(&raw).unwrap();
    let iso = |s: &str| NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap();
    let today = iso(&fx.today);
    let statements: Vec<StatementCoverage> = fx.statements.iter()
        .map(|s| StatementCoverage { period_end: iso(&s.period_end), needs_review: s.needs_review })
        .collect();
    let transactions: Vec<TransactionCoverage> = fx.transactions.iter()
        .map(|t| TransactionCoverage { date: iso(&t.date), from_full_statement: t.from_full_statement })
        .collect();
    let got = compute_coverage(today, statements, transactions);
    let want: Vec<MonthCoverage> = fx.expected_months.iter()
        .map(|m| MonthCoverage { month: m.month.clone(), state: m.state, needs_review: m.needs_review })
        .collect();
    assert_eq!(got, want, "coverage map must equal the golden expected_months");
}
```

- Imports `compute_coverage`, `MonthCoverage`, `StatementCoverage`, `TransactionCoverage`, `CoverageState` from
  `kaname_core` (alongside the existing statement + dedup imports). `CoverageState` deserialises directly from the
  `state` string (it derives `serde::Deserialize` — see `data-model.md` D5).
- Dates are re-parsed from ISO strings via `NaiveDate::parse_from_str`; comparison is by
  `CoverageState`/`bool`/`String` value-equality (no `Decimal`, no `f64`); re-running yields identical results
  (determinism, SC-006). Any mismatch **fails** (parity guard — FR-017/020).
- No existing fixture or statement/dedup parity assertion changes; the new file is additive and lives under a new
  `fixtures/coverage/` subtree. All data synthetic/redacted (FR-019).

> **Note**: `CoverageState` must be deserialisable from the `state` string, and `MonthCoverage` from the
> `expected_months` objects. Per the locked design, `CoverageState` derives `Serialize`/`Deserialize` (mapping
> `"Gap"`/`"Partial"`/`"Covered"`) and `MonthCoverage` derives them too — so an `expected_months` entry
> deserialises straight into the `ExpectedMonth` row above (or into `MonthCoverage` directly). This is a
> test-serialisation convenience; it does not affect the FFI surface (mirrors `Direction` in `model.rs` and the
> serde-on-`DedupLayer` note in slice 013).
