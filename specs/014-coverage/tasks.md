---
description: "Task list — On-Device Statement Coverage Map (coverage.rs: the pure, clock-free rolling-24-month GAP/PARTIAL/COVERED + needsReview classifier ported from the web engine's coverage.py; std HashMap + chrono::Datelike only; zero new dependency)"
---

# Tasks: On-Device Statement Coverage Map — the Pure Rolling-24-Month GAP / PARTIAL / COVERED + needsReview Classifier

**Input**: Design documents from `/specs/014-coverage/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/{coverage.md, engine-ffi.md, golden-fixture.md}`, `quickstart.md`

**Tests**: REQUIRED and **TEST-FIRST** (Constitution Principle V). The new golden fixture, the failing Rust
parity test, and the failing Swift bridge test are authored **RED, before** the `coverage.rs` classifier that
greens them. The `expected_months` are the **locked ground truth captured from a live web-engine run** of
`coverage.py` (`month_window` + the GAP/PARTIAL/COVERED + needsReview classification, pinned at
`COVERAGE_MONTHS = 24`): for `fixtures/coverage/basic.json` (`today = 2026-06-14`) the 24 entries are
`2026-01` Covered/false, `2026-02` Covered/true, `2026-04` Partial/false, `2026-05` Covered/false, and the
other **20** window months Gap/false — and `month_window(2026-06-14, 24)` = `["2024-07", …, "2026-06"]`.

**Port source of truth** (faithful, byte-for-byte with the golden vector): the web engine's `coverage.py`
(`month_window(today, count)` + `compute_coverage`), pinned at `COVERAGE_MONTHS = 24`. This slice is the
on-device analogue of the **pure classifier only** — the DB aggregation the web `coverage.py` does from its
`transactions`/`statements` tables stays on the platform, which supplies the **pre-aggregated per-account
facts** (spec Assumptions, Out of Scope, FR-013). It slots into the core as a **new top-level module**
`coverage.rs`, a sibling to `dedup.rs`, exactly as `dedup.rs` sat beside `reconcile.rs`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: `US1`=map (GAP/PARTIAL/COVERED, 24 oldest-first) · `US2`=needsReview · `US3`=covered-via-txn ·
  `US4`=window/determinism · `US5`=bridge/no-new-infra · `US6`=golden parity · `US7`=privacy-egress.
  Setup/Polish carry no story label.
- Exact file paths are included in every task.

## ♻️ REUSE — do NOT re-create

Coverage is a **new, independent classification concern** delivered as a **new top-level module** + its bridge,
plugging into the shipped foundations unchanged (mirroring how `dedup.rs` reused the P1 foundations). Do **not**
rebuild any of these:

- `src/ffi.rs` — the `uniffi::custom_type!(NaiveDate, String, …)` (`ffi.rs:38`) is **reused verbatim** for the
  `today` parameter + the record date fields (**no `uniffi.toml` change**); the new export mirrors the
  `cross_source_duplicates` wrapper (`ffi.rs:62–68`) exactly, including the name-clash handling.
- `src/lib.rs` — the module list (`lib.rs:22–25`) and the crate-root re-export blocks (`lib.rs:27–41`); add
  `pub mod coverage;` and the new FFI fn + coverage types beside the existing `dedup::{…}` / `ffi::{…}` re-exports.
- `tests/parity.rs` — the golden-fixture harness; add a **separate, coverage-only** loader + one test. The
  statement `Fixture`/`Expected`/`CASES` (`parity.rs:22–…`) and the dedup `DedupFixture`/`cross_source_dedup_matches_expected`
  (`parity.rs:499–557`) and **every** current test are **untouched**.
- `chrono::NaiveDate` — the shared date type (ISO-string custom type). Reused for `today`,
  `StatementCoverage.period_end`, and `TransactionCoverage.date`. **No new custom type.**
- The **privacy-egress gate** (`make core-privacy-audit`) + CI — inherited unchanged (**no new dependency** →
  byte-identical shipped `cargo tree`; the classifier uses only `std::collections::HashMap` + `chrono::Datelike`).
- `src/model.rs` / `src/statement/*` / every reader — **untouched** (coverage does not touch `Transaction`,
  `Direction`, or any parser; it operates on its own input-fact records).

**The only NEW code**: a new file `src/coverage.rs` (the `CoverageState` enum + `StatementCoverage` /
`TransactionCoverage` / `MonthCoverage` records + `COVERAGE_MONTHS` + the pure `month_window` + `compute_coverage`
+ unit tests); `pub mod coverage;` + one `#[uniffi::export]` wrapper in `ffi.rs` + `lib.rs` re-exports; one new
fixture (`fixtures/coverage/basic.json`, a **new shape**); a coverage loader + one parity test; and one Swift
bridge test. **No new dependency** (runtime *or* dev); **no `uniffi.toml`/`model.rs`/reader change**; **no money**
(no `Decimal`, no `f64`).

## 🎯 The classifier — the whole decision surface (contracts/coverage.md, data-model.md)

`compute_coverage(today: NaiveDate, statements: &[StatementCoverage], transactions: &[TransactionCoverage]) -> Vec<MonthCoverage>`:

1. `window = month_window(today, COVERAGE_MONTHS)` — 24 `"YYYY-MM"` labels, **oldest first**, ending at `today`'s
   calendar month.
2. `earliest` = **first day of the oldest window month** (`NaiveDate::from_ymd_opt(window[0][..4] as i32,
   window[0][5..7] as u32, 1)`).
3. `txn_by_month: HashMap<String, bool>` (month → `has_full`): for each transaction with `date >= earliest`,
   key = `"{:04}-{:02}"` of `(date.year(), date.month())`, **OR-in** `from_full_statement`.
4. `stmt_by_month: HashMap<String, bool>` (month → `needs_review`): for each statement with `period_end >=
   earliest`, key from `period_end`, **OR-in** `needs_review`.
5. For each `label` in `window` (in window order): **COVERED** iff `covered_by_statement || (has_txn && has_full)`
   → `needs_review = *stmt_by_month.get(label).unwrap_or(&false)`; else **PARTIAL** iff `has_txn` → `false`; else
   **GAP** → `false`. (`has_txn = txn_by_month.contains_key`, `has_full = *txn_by_month.get(..).unwrap_or(&false)`,
   `covered_by_statement = stmt_by_month.contains_key`.)

`month_window(today, count)`: read `today.year()` / `today.month()` (`chrono::Datelike`); for `count` iterations
push `format!("{year:04}-{month:02}")` then decrement the month (wrap `1 → 12`, `year -= 1`); `reverse()`.

**Invariants**: exactly 24, oldest first (for **any** input) · two COVERED paths (statement fact **or**
full-statement transaction) · COVERED precedence over PARTIAL, PARTIAL over GAP · `needsReview` from **statements
only** (OR over the month's statement facts, read **only** on the COVERED branch; PARTIAL/GAP + covered-via-txn-only
= `false`) · transaction→month of `date`, statement→month of `period_end` · out-of-window (`< earliest`) and
future-month facts ignored · read-only (borrows `&`, never mutates/reorders/persists) · pure/total/deterministic
(no I/O, network, **clock**, locale, global state; empty input ⇒ 24 GAP/false; never panics) · **no money**
(dates/states only — no `Decimal`, no `f64`).

## ⚠️ Local gotchas (apply throughout)

- **Constitution II — the core NEVER reads the wall-clock**: `today` is a **required parameter**. `month_window`
  uses `today.year()` / `today.month()` only; never call `chrono::Local::now()` / `Utc::now()` (FR-003, SC-006).
- **Name clash (research D7)**: the FFI wrapper `compute_coverage` **shadows** the pure
  `coverage::compute_coverage`. So `ffi.rs` imports only the coverage **types** (not the pure fn) and calls it
  **fully-qualified** (`crate::coverage::compute_coverage(today, &statements, &transactions)`); `lib.rs` re-exports
  only the **FFI** `compute_coverage` (`pub use ffi::compute_coverage;`) — **NOT** `coverage::compute_coverage`.
  `tests/parity.rs` and Swift both use the FFI-exported one via `kaname_core::compute_coverage`.
- **`coverage.rs` is a brand-NEW module** — `pub mod coverage;` must be added to `lib.rs` **when the file is
  created** (T006) or the crate (and its unit tests) won't compile. `fixtures/coverage/` is a **NEW directory**
  (a new fixture *shape*), created in T003.
- **Determinism despite `HashMap` (research D11)**: the output order comes from iterating the `window` `Vec` (not
  the two `HashMap`s), so `HashMap` iteration order never reaches the result — output is byte-identical across runs.
- **`make core-xcframework` MUST run before `tuist generate`** (`ios-gen: core-xcframework`) — the generated Swift
  + `KanameCoreFFI.xcframework` are rebuilt artifacts; run it after the FFI surface changes (new `computeCoverage`
  + `CoverageState`/`StatementCoverage`/`TransactionCoverage`/`MonthCoverage`).
- **The iOS CI job stays pinned to `macos-15`**; the local `xcodebuild` destination is the **"iPhone 16"**
  simulator (`OS=latest`) — create it in Xcode first.
- **swift-format `[Spacing]` rejects trailing inline comments** — in `CoverageTests.swift` any comment goes on its
  **own line above** the code, never trailing after it.
- **rustfmt reformats edits** — after each `edit`, run `make core-fmt` then re-view before the next edit
  (arrays/asserts/imports get re-wrapped).
- **No money, no new dependency**: `coverage.rs` uses only `std::collections::HashMap` + `chrono::Datelike`
  (both already in the graph); comparison is by `CoverageState`/`bool`/`String` value-equality — **no `Decimal`,
  no `f64`**. `core/crates/kaname-core/Cargo.toml` stays **UNCHANGED**.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm invariants so every later task lands cleanly and the gates stay green. No behavior yet.

- [ ] T001 [P] [US5] Confirm the **no-new-dependency / no-new-infra** invariant: `core/crates/kaname-core/Cargo.toml` stays **UNCHANGED** (runtime `regex`/`rust_decimal`/`chrono`/`serde`/`uniffi` + dev-only `serde_json` already present) — this slice adds **zero** deps (`std::collections::HashMap` + `chrono::Datelike` only) and **no** new shared engine helper beyond the classifier, `month_window`, and their types (FR-010/021, SC-011/012). Note that `coverage.rs` is a **NEW** top-level module (sibling to `dedup.rs`) and `fixtures/coverage/` is a **NEW** directory (a new fixture *shape*), both created in later tasks. Ref: plan §Summary/§Structure Decision, `data-model.md` §Reuse contract.
- [ ] T002 [P] Verify local prerequisites & gotchas (no code): `cargo` on PATH (`export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"`); an **"iPhone 16" simulator** exists in Xcode; recall `make core-xcframework` precedes `tuist generate`, the iOS CI job is pinned to **`macos-15`**, **swift-format `[Spacing]` forbids trailing inline comments**, the **core never reads the wall-clock** (`today` is a parameter — Constitution II), and the **`compute_coverage` name clash** is handled by a types-only import + fully-qualified call in `ffi.rs` (research D7). Ref: `quickstart.md` §Prerequisites/§Troubleshooting.

**Checkpoint**: No manifest/`uniffi.toml`/`model.rs` change needed; toolchain + simulator + CI ordering + the clock-free + name-clash nuances understood.

---

## Phase 2: Test-First Foundation (⚠️ Principle V — author RED before ANY coverage engine code)

**Purpose**: Pin the on-device classifier to the proven web engine **before** writing it. These are the golden
parity (US6), map (US1), needsReview (US2), covered-via-txn (US3), window (US4), and bridge (US5) tests that
protect the slice; they MUST be **RED** at the end of this phase (`compute_coverage` / `MonthCoverage` /
`CoverageState` / `StatementCoverage` / `TransactionCoverage` do not exist yet).

**⚠️ CRITICAL**: No engine code (Phase 3+) until T003–T005 exist and are verified failing (compile-fail is
acceptable RED for the Rust harness; the Swift test won't build until Phase 4).

- [ ] T003 [P] [US1] [US2] [US3] [US4] [US6] Create the **new-shape** golden fixture `fixtures/coverage/basic.json` (new directory) — the **exact bytes** from `contracts/golden-fixture.md` §"exact bytes to write": the `_comment` provenance string, `"today": "2026-06-14"`, a `statements` array (`{period_end:"2026-05-16", needs_review:false}`, `{period_end:"2026-02-28", needs_review:true}`), a `transactions` array (`{date:"2026-04-10", from_full_statement:false}`, `{date:"2026-05-05", from_full_statement:true}`, `{date:"2026-01-20", from_full_statement:true}`), and `expected_months` = **exactly 24** entries oldest-first `2024-07 … 2026-06` with `2026-01` Covered/false, `2026-02` Covered/true, `2026-04` Partial/false, `2026-05` Covered/false and the other **20** Gap/false. Dates are **ISO strings** (re-parsed to `NaiveDate`); `state` is `"Gap"`/`"Partial"`/`"Covered"`; `bool` flags direct. **100% synthetic** (fabricated dates/states — no real account data; FR-019). ⚠️ Copy the 24 bytes verbatim — this is the locked parity target captured from the live `coverage.py` run. Ref: `contracts/golden-fixture.md`, `contracts/coverage.md` §Golden behaviour.
- [ ] T004 [US6] Extend the parity harness `core/crates/kaname-core/tests/parity.rs` → **RED** with a **separate, coverage-only** loader + one test (the statement `Fixture`/`Expected`/`CASES` and the dedup `DedupFixture`/`cross_source_dedup_matches_expected` at `parity.rs:499–557` and every existing test **untouched**). Add `#[derive(Deserialize)]` structs `CoverageFixture { today: String, statements: Vec<StmtRow>, transactions: Vec<TxnRow>, expected_months: Vec<ExpectedMonth> }`, `StmtRow { period_end: String, needs_review: bool }`, `TxnRow { date: String, from_full_statement: bool }`, `ExpectedMonth { month: String, state: CoverageState, needs_review: bool }`; and `#[test] fn coverage_map_matches_expected()` that reads `{CARGO_MANIFEST_DIR}/../../../fixtures/coverage/basic.json`, deserializes, parses ISO dates via `NaiveDate::parse_from_str(_, "%Y-%m-%d")` into `Vec<StatementCoverage>` / `Vec<TransactionCoverage>`, calls `compute_coverage(today, statements, transactions)` (the FFI-exported wrapper — owned `Vec`s), and `assert_eq!` against the 24 `expected_months` mapped into `Vec<MonthCoverage>` (copy the loader from `contracts/golden-fixture.md` §"Parity harness behaviour"). Extend the `use kaname_core::{…}` import list (`parity.rs:12–18`) with `compute_coverage`, `CoverageState`, `MonthCoverage`, `StatementCoverage`, `TransactionCoverage` (`NaiveDate` at `parity.rs:10` and `serde::Deserialize` at `parity.rs:21` already imported). ⚠️ **Verify RED**: `make core-test` fails to **compile** (the fn/types don't exist). Depends on T003. Ref: `contracts/golden-fixture.md`, `data-model.md` §Parity fixture types.
- [ ] T005 [P] [US1] [US2] [US3] [US5] Author the **RED** Swift bridge test `ios/Tests/CoverageTests.swift` — "core ↔ Swift coverage map" (`import Foundation` / `import KanameCore` / `import Testing`), mirroring `ios/Tests/ReconcileTests.swift` + `ios/Tests/CrossSourceDedupTests.swift`. Build `[StatementCoverage]` (`StatementCoverage(periodEnd: "2026-05-16", needsReview: false)`, `StatementCoverage(periodEnd: "2026-02-28", needsReview: true)`) + `[TransactionCoverage]` (`TransactionCoverage(date: "2026-04-10", fromFullStatement: false)`, `TransactionCoverage(date: "2026-05-05", fromFullStatement: true)`, `TransactionCoverage(date: "2026-01-20", fromFullStatement: true)`); call `let map = computeCoverage(today: "2026-06-14", statements: statements, transactions: transactions)`. `@Test`: assert `map.count == 24`; index by `month` (`Dictionary(uniqueKeysWithValues: map.map { ($0.month, $0) })`) and assert `2026-05` `.covered`/`needsReview == false`, `2026-02` `.covered`/`needsReview == true`, `2026-04` `state == .partial`, `2026-01` `.covered`/`needsReview == false`, and a sample GAP month (e.g. `2026-03`) `state == .gap`; assert `map.first?.month == "2024-07"` and `map.last?.month == "2026-06"`. ⚠️ **swift-format `[Spacing]`**: comments on their own line above the code, never trailing. ⚠️ **Verify RED**: won't build until Phase 4 regenerates the xcframework. Ref: `contracts/engine-ffi.md` §Contract tests (Swift), `data-model.md` §Swift surface, `quickstart.md` §4.

**Checkpoint**: Fixture written; Rust parity harness RED (won't compile); Swift bridge test RED. Test-first satisfied — engine code may now begin.

---

## Phase 3: User Stories 1–4 & 6 — the engine (Priority: P1–P4, P6) 🎯 MVP

**Goal**: Add the `coverage.rs` module — the `CoverageState`/`StatementCoverage`/`TransactionCoverage`/`MonthCoverage`
types, `COVERAGE_MONTHS`, the pure `month_window` + `compute_coverage`, and unit tests — then wire the FFI + crate-root
re-exports, greening the Rust parity + `coverage.rs` unit tests. This one engine phase lands US1 (map), US2
(needsReview), US3 (covered-via-txn), US4 (window/determinism), and US6 (golden parity) on the Rust side (Swift
bridge greened in Phase 4). `coverage.rs` is one file, so T006–T009 are **sequential** (same file, not `[P]`).

**Independent Test**: `compute_coverage(2026-06-14, &statements, &transactions)` over the golden facts returns the
24 entries (`2026-01` Covered/false, `2026-02` Covered/true, `2026-04` Partial/false, `2026-05` Covered/false, 20
Gap/false) — with no network/clock/locale in the path.

- [ ] T006 [US1] [US2] [US3] Create `core/crates/kaname-core/src/coverage.rs` (NEW file) with the module `//!` doc (pure port of the web `coverage.py` classifier over pre-aggregated facts; no clock/DB/money) and the types + const: `use std::collections::HashMap; use chrono::{Datelike, NaiveDate}; use serde::{Deserialize, Serialize};`; `pub enum CoverageState { Gap, Partial, Covered }` — `#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]` (serde maps unit variants to `"Gap"`/`"Partial"`/`"Covered"` for the fixture, mirroring `Direction`/`DedupLayer`); `pub struct StatementCoverage { pub period_end: NaiveDate, pub needs_review: bool }` and `pub struct TransactionCoverage { pub date: NaiveDate, pub from_full_statement: bool }` — each `#[derive(Debug, Clone, PartialEq, uniffi::Record)]`; `pub struct MonthCoverage { pub month: String, pub state: CoverageState, pub needs_review: bool }` — `#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]`; `pub const COVERAGE_MONTHS: u32 = 24;`. **Also add `pub mod coverage;` to `core/crates/kaname-core/src/lib.rs`** (beside `pub mod dedup;`, `lib.rs:22`) so the new module compiles. ⚠️ No `Decimal`/`f64`. Ref: `data-model.md` §New types, `contracts/engine-ffi.md` §Types.
- [ ] T007 [US4] Add `pub fn month_window(today: NaiveDate, count: u32) -> Vec<String>` to `core/crates/kaname-core/src/coverage.rs`, ported **1:1** from the web `month_window` (research D2): read `today.year()` / `today.month()` (`Datelike`); for `count` iterations push `format!("{year:04}-{month:02}")` then decrement the month (wrap `1 → 12`, `year -= 1`); `reverse()` for oldest-first. Pure/total/deterministic — **never reads the wall-clock** (derived from the `today` parameter). Add `#[cfg(test)]` unit tests: `month_window(2026-06-14, 24)` has **24** labels with `[0] == "2024-07"` and `[23] == "2026-06"`; **determinism** (two calls with the same input are equal); a `today` on the **1st or last day** of the month yields the **same** window (the day is ignored). Verify with `cargo test -p kaname-core coverage::`. Ref: `data-model.md` §month_window, `contracts/coverage.md` §month_window, research D2, FR-002/003, SC-002.
- [ ] T008 [US1] [US2] [US3] Add `pub fn compute_coverage(today: NaiveDate, statements: &[StatementCoverage], transactions: &[TransactionCoverage]) -> Vec<MonthCoverage>` to `core/crates/kaname-core/src/coverage.rs`, implementing the classifier (research D3, exact web order): `let window = month_window(today, COVERAGE_MONTHS);`; `earliest` = first day of `window[0]`'s month via `NaiveDate::from_ymd_opt(window[0][..4].parse::<i32>().unwrap(), window[0][5..7].parse::<u32>().unwrap(), 1).unwrap()`; build `txn_by_month: HashMap<String, bool>` (for each txn with `date >= earliest`, key `format!("{:04}-{:02}", date.year(), date.month())`, **OR-in** `from_full_statement` via `let e = map.entry(key).or_insert(false); *e = *e || flag;`) and `stmt_by_month: HashMap<String, bool>` (same for statements with `period_end >= earliest`, OR-in `needs_review`); then for each `label` in `window` (iterate the **`window` Vec**, not the maps — determinism, D11): `has_txn`/`has_full`/`covered_by_statement` → **COVERED** iff `covered_by_statement || (has_txn && has_full)` with `needs_review = *stmt_by_month.get(label).unwrap_or(&false)`; else **PARTIAL** iff `has_txn` (`needs_review = false`); else **GAP** (`false`). Borrows `&` (read-only), pure/total (never panics on empty → 24 GAP). ⚠️ No `Decimal`/`f64`. Ref: `contracts/coverage.md` §compute_coverage, `data-model.md` §compute_coverage, research D3/D4/D8/D11.
- [ ] T009 [US1] [US2] [US3] [US4] Extend `#[cfg(test)] mod tests` in `core/crates/kaname-core/src/coverage.rs` for `compute_coverage` (build small fact lists with `NaiveDate::from_ymd_opt`): **reference scenario** (`today = 2026-06-14`; statements `2026-05-16`/false + `2026-02-28`/true; transactions `2026-04-10`/false + `2026-05-05`/true + `2026-01-20`/true) → assert the 4 non-GAP months (`2026-01` Covered/false, `2026-02` Covered/true, `2026-04` Partial/false, `2026-05` Covered/false), at least one GAP, and `len() == 24`; **empty input** (`&[]`, `&[]`) → 24 GAP/false, no panic; **out-of-window fact ignored** (a statement/txn before `earliest` changes none of the 24 entries); **future-month fact ignored** (a fact after `today`'s month has no window label); **COVERED-via-full-txn-only → needsReview false** (a month covered only by a `from_full_statement` txn, no statement fact, is Covered/false; a month with only alert txns is Partial); **determinism** (re-running the reference scenario yields identical output). Comparison by `CoverageState`/`bool`/`String` value-equality. Verify with `cargo test -p kaname-core coverage::`. Ref: `contracts/coverage.md` §Unit tests, `data-model.md` §Invariants, SC-003/004/005/006/007, FR-009.
- [ ] T010 [US1] [US5] Wire the FFI + crate-root re-exports. In `core/crates/kaname-core/src/ffi.rs` add (mirroring the `cross_source_duplicates` wrapper, `ffi.rs:62–68`): `use crate::coverage::{MonthCoverage, StatementCoverage, TransactionCoverage};` (**TYPES only — not the pure fn**), then `#[uniffi::export] pub fn compute_coverage(today: NaiveDate, statements: Vec<StatementCoverage>, transactions: Vec<TransactionCoverage>) -> Vec<MonthCoverage> { crate::coverage::compute_coverage(today, &statements, &transactions) }` (owned `Vec`s per UniFFI; `today` by value; call the pure fn **fully-qualified**; total, never panics; `NaiveDate` custom type already registered at `ffi.rs:38`). In `core/crates/kaname-core/src/lib.rs`: add `compute_coverage` to the `pub use ffi::{…}` block (`lib.rs:30–37`) and add `pub use coverage::{CoverageState, MonthCoverage, StatementCoverage, TransactionCoverage, month_window};`. ⚠️ Do **NOT** `pub use coverage::compute_coverage` — it name-clashes with the FFI wrapper (research D7). Depends on T008. Ref: `contracts/engine-ffi.md` §Exported function, `data-model.md` §FFI wrapper / §Crate re-exports.
- [ ] T011 [US6] **Green the engine side**: `make core-fmt`, then `make core-test` — the parity test (T004: `coverage_map_matches_expected` → the 24 golden `expected_months`) now **PASSES**, the `coverage.rs` unit tests (T007/T009) pass, and **all prior parity + statement + dedup tests stay green** — then `make core-lint` (clippy `-D warnings` + fmt check). Verify **RED→GREEN** for the Rust side. Ref: `quickstart.md` §1.

**Checkpoint**: The engine returns the 24-entry coverage map, honors the two COVERED paths / PARTIAL / GAP / needsReview / month attribution / out-of-window exclusion, and reproduces the golden vector exactly; Rust parity + `coverage.rs` unit tests are green. US1/US2/US3/US4/US6 functional on the Rust side (Swift bridge greened in Phase 4).

---

## Phase 4: UniFFI bridge — regenerate the xcframework + green the Swift test (US5)

**Goal**: Surface `compute_coverage` + the four coverage types to Swift and green the bridge test. `NaiveDate` is
reused unchanged → **no `uniffi.toml` change**.

- [ ] T012 [US5] Run `make core-xcframework` to rebuild `ios/Frameworks/KanameCoreFFI.xcframework` + the generated Swift (git-ignored artifacts), now exposing `computeCoverage(today:statements:transactions:)`, the `CoverageState` enum (`.gap`/`.partial`/`.covered`), and the `StatementCoverage` (`periodEnd`/`needsReview`), `TransactionCoverage` (`date`/`fromFullStatement`), `MonthCoverage` (`month`/`state`/`needsReview`) records. `NaiveDate` fields cross as ISO-8601 `String`s via the existing custom type. ⚠️ **MUST run before `tuist generate`**. Ref: `contracts/engine-ffi.md` §Stability, `quickstart.md` §3.
- [ ] T013 [US5] Run `make ios-test` (`ios-gen` → `core-xcframework` → `tuist generate` → `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test`) to **green** `ios/Tests/CoverageTests.swift` (T005): `count == 24`, `2026-05` `.covered`/false, `2026-02` `.covered`/true, `2026-04` `.partial`, `2026-01` `.covered`/false, a sample GAP `.gap`, and the oldest-first endpoints `2024-07`/`2026-06`. ⚠️ **Local: create the "iPhone 16" simulator first.** Verify **RED→GREEN**. Ref: `quickstart.md` §4.

**Checkpoint**: US1/US2/US3/US5 delivered end-to-end (Rust engine + Swift bridge). A person can see, on-device, which of the last 24 months are covered, partial, or empty — and which covered months need review.

---

## Phase 5: Verification of the remaining stories (US2, US3, US4, US7) & polish

**Purpose**: Confirm the stories whose behavior already landed in Phase 3 are independently verified, and run the
full gate. Most of these are assertions already authored in T007/T009/T004 — this phase makes their coverage
explicit and closes the constitution gates.

- [ ] T014 [P] [US2] Confirm the **needsReview** rule (FR-007, SC-005): the `coverage.rs` unit tests (T009) + the fixture (`2026-02` Covered/**true** vs `2026-05`/`2026-01` Covered/**false**, T003) assert needsReview is true **only** on a COVERED month backed by a needs-review statement fact (OR over that month's statements), and **always false** on PARTIAL/GAP and on a month COVERED only via a full-statement transaction. Add (if not already in T009) an explicit assertion that a PARTIAL and a GAP month both carry needsReview `false`. Ref: spec US2, `contracts/coverage.md` §Guards.
- [ ] T015 [P] [US3] Confirm **COVERED-via-full-statement-transaction** (FR-005/007, SC-004): the T009 unit test + the fixture's `2026-01` (full-statement txn only, no statement fact → Covered/false, T003) and `2026-04` (alert-only txn → Partial, T003) pin both COVERED path (b) and the PARTIAL fallback, with needsReview defaulting `false` for the transaction-only COVERED month. Ref: spec US3, `contracts/coverage.md` §Classification.
- [ ] T016 [P] [US4] Confirm the **deterministic, clock-free window** (FR-002/003, SC-002/006): the `month_window` unit tests (T007: 24 labels, `[0]=="2024-07"`, `[23]=="2026-06"`, determinism, 1st/last-day equivalence) hold; note the parity `coverage_map_matches_expected` (T004) is itself a determinism witness (24 oldest-first entries, `2024-07 … 2026-06`); confirm the classifier takes `today` as a parameter and reads no wall-clock (Constitution II). Ref: spec US4, `contracts/coverage.md` §month_window, research D2.
- [ ] T017 [US7] Run `make core-privacy-audit` — assert **no networking crate** enters the shipped graph (the coverage path is pure/on-device; FR-014/016, SC-010). This slice adds **no dependency**, so the shipped `cargo tree` is byte-identical; the inherited gate must stay green and now covers `compute_coverage` (zero network, zero clock). Ref: spec US7, `quickstart.md` §2.
- [ ] T018 Run the **full Local Verification Gate** end-to-end: `make core-lint core-test core-privacy-audit lint ios-test` — all green (fmt/clippy, Rust unit+parity, privacy audit, SwiftLint + swift-format lint, `tuist generate`, simulator build + Swift Testing). This is the mandatory pre-PR gate. Ref: `quickstart.md` §5, constitution §iOS Local Verification Gate, FR-022, SC-012.

**Checkpoint**: All seven user stories verified; every gate green. Ready for PR.

---

## Phase 6: Delivery

- [ ] T019 Commit in **two** commits on `014-coverage`: (1) `feat(core): …` — the classifier + fixture + parity (`core/crates/kaname-core/src/coverage.rs`, `src/ffi.rs`, `src/lib.rs`, `fixtures/coverage/basic.json`, `tests/parity.rs`); (2) `test(ios): …` — `ios/Tests/CoverageTests.swift`. Include the `Co-authored-by: Copilot` trailer. Do NOT commit generated artifacts (`ios/Generated/`, `ios/Frameworks/*.xcframework` are git-ignored).
- [ ] T020 Open the PR (`gh pr create`), watch CI (Rust on `ubuntu-latest`, iOS on `macos-15`) to green, then `gh pr merge --rebase --delete-branch` and `git remote prune origin`. Compute the PR number from `gh pr list` (not 1:1 with the slice number — chore PRs consume numbers). Checkpoint with the user at the slice boundary.

---

## Dependencies & parallelism

- **Phase 1 (T001–T002)**: both `[P]` (read-only confirmations, independent) — no code.
- **Phase 2 (T003–T005)**: T003 (fixture) and T005 (Swift test) are `[P]`-parallel (independent files); T004
  (parity) reads the fixture → author T003 first, then T004. All three must be RED before Phase 3.
- **Phase 3 (T006–T011)**: T006 → T007 → T008 → T009 are the **same file** (`coverage.rs`) so **sequential**
  (not `[P]`); T008 depends on T007 (`month_window`); T010 (FFI/re-exports) depends on T008; T011 (green) depends
  on T004 + T006–T010.
- **Phase 4**: T012 → T013, depend on Phase 3 green.
- **Phase 5**: T014–T016 `[P]` (verification, mostly already-authored assertions) after Phase 3/4; T017 after
  Phase 3; T018 (full gate) after all.
- **Phase 6**: after T018 green.

## Story → task coverage

| Story | Tasks |
|---|---|
| US1 map (GAP/PARTIAL/COVERED, 24 oldest-first) | T003, T005, T006, T008, T009, T010, T011, T013 |
| US2 needsReview | T003, T005, T006, T008, T009, T011, T013, T014 |
| US3 covered-via-txn | T003, T005, T006, T008, T009, T011, T013, T015 |
| US4 window / determinism | T003, T007, T009, T011, T016 |
| US5 bridge / no-new-infra | T001, T005, T010, T012, T013 |
| US6 golden parity | T003, T004, T011 |
| US7 privacy-egress | T017, T018 |

## Implementation strategy

**MVP = Phase 1 → Phase 2 → Phase 3 → Phase 4** delivers US1 (map) + US2 (needsReview) + US3 (covered-via-txn) +
US4 (window) + US5 (bridge) + US6 (golden parity) end-to-end: the smallest coverage signal that answers *"which
months of my history are fully imported?"* on-device. US7 (privacy) is the inherited gate confirmed at T017/T018.
Build strictly **test-first** (Phase 2 RED before Phase 3 GREEN), add the classifier as a **new top-level
`coverage.rs`** module (sibling to `dedup.rs`) with the name-clash-safe FFI wrapper, and add **zero** new
dependencies. The core **never reads the wall-clock** — `today` is a required parameter (Constitution II).

## Notes

- `[P]` tasks = different files, no dependencies on an unfinished task.
- `[Story]` labels map each task to the spec's seven user stories for traceability.
- Every behavior is pinned test-first to the web `coverage.py`; verify RED (T003–T005) before GREEN (T006+).
- Money is **not** involved — coverage classifies dates/states only (no `Decimal`, no `f64`).
- Commit after each logical group; stop at any checkpoint to validate a story independently.
- Avoid: reading the wall-clock, re-exporting the pure `compute_coverage` (name clash), trailing inline Swift
  comments, and any new dependency / `uniffi.toml` / `model.rs` / reader change.
