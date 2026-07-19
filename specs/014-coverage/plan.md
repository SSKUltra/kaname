# Implementation Plan: On-Device Statement Coverage Map — the Pure Rolling-24-Month GAP / PARTIAL / COVERED + needsReview Classifier, Ported From the Web Engine's `coverage.py` (No Database, No Clock, No New Dependency)

**Branch**: `014-coverage` | **Date**: 2026-07-19 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/014-coverage/spec.md`
**Milestone**: P2 (engine port) — the coverage-map piece of the ingestion layer, alongside the already-shipped
balance-chain, reconciliation, and cross-source de-duplication signals; the first signal that answers *"which
months of my history are fully imported?"*

## Summary

Port the web engine's `coverage.py` — the `month_window` helper and the GAP / PARTIAL / COVERED + `needsReview`
classification — into `kaname-core` (Rust) as a **pure, deterministic, total** classifier over pre-aggregated
per-account facts. For one account, over the **rolling 24 months** ending at the current month, it labels each
month as **COVERED** (a full statement covers it), **PARTIAL** (only piecemeal transactions, no full statement),
or **GAP** (nothing known), and sets a **needsReview** badge on COVERED months whose directly-imported statement
run was incomplete or failed reconciliation. It returns exactly **24** entries, **oldest first**.

Because the on-device engine has **no local store yet** and the core must be **pure and deterministic** (never
reads the wall-clock — Constitution Principle II), the classifier takes its inputs **explicitly**: a **`today`**
date (supplied by the platform), a list of **statement facts** (one per imported statement: a billing
**period-end** date + a **needsReview** flag), and a list of **transaction facts** (one per transaction: a
**date** + a **from-full-statement** flag). The platform (which owns aggregation/persistence) supplies the facts;
the engine owns only the deterministic classification.

The port reproduces `coverage.py` **exactly** (Constitution Principle V), including:

1. **`month_window(today, count)`** — `count` labels of the form `"YYYY-MM"`, starting at `today`'s calendar
   month and decrementing (wrapping `1 → 12`, year − 1), then **reversed** to oldest-first
   (`month_window(2026-06-14, 24)` = `["2024-07", …, "2026-06"]`).
2. **`compute_coverage(today, statements, transactions)`** — build the 24-label window, take the **first day of
   the oldest window month** as the `earliest` cutoff, bucket facts into per-month maps (transactions →
   `month → has_full` via a logical OR of `from_full_statement`; statements → `month → needs_review` via a
   logical OR of `needs_review`), then classify each window label:
   - **COVERED** iff a statement fact falls in the month **OR** a transaction in the month is from a full
     statement; its `needsReview` = the month's OR-of-statement-needs_review (default `false`).
   - else **PARTIAL** iff the month has any transaction; else **GAP**. PARTIAL/GAP always `needsReview = false`.

**Zero new dependency.** The classifier uses only `std::collections::HashMap` and `chrono::Datelike` (`year()`,
`month()`) on the shared `NaiveDate` type — both already in the graph. It reuses the shared date type, the
golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate — the same foundations the ten
readers, balance-chain, reconciliation, and cross-source de-dup use. No money is involved (coverage classifies
dates/states), so the "money is never a float" rule has no comparison here.

**Delivered as a small, surgical diff — a new top-level module + its bridge + a golden fixture + tests:**

- **`core/crates/kaname-core/src/coverage.rs`** (NEW top-level module, sibling to `dedup.rs`): the
  `CoverageState` enum, the `StatementCoverage` / `TransactionCoverage` input records, the `MonthCoverage` output
  record, `COVERAGE_MONTHS = 24`, the pure `month_window` and `compute_coverage` functions, and unit tests.
- **`ffi.rs`** — one `#[uniffi::export] pub fn compute_coverage(today, statements, transactions)` wrapper that
  calls the pure `crate::coverage::compute_coverage(today, &statements, &transactions)` (mirrors how
  `cross_source_duplicates` / `reconcile_statement` wrap their pure core).
- **`lib.rs`** — `pub mod coverage;`, re-export the **FFI** `compute_coverage`, and re-export the coverage types
  + the `month_window` helper (for the parity/unit tests). The pure `coverage::compute_coverage` is **not**
  re-exported at the crate root (name clash with the FFI wrapper).
- **New golden fixture** `fixtures/coverage/basic.json` — a new fixture **shape** (`today` + statement facts +
  transaction facts + the expected 24 month entries), not a statement.
- **Parity harness** (`tests/parity.rs`) — a coverage fixture loader + one `coverage_map_matches_expected` test;
  the existing statement `CASES` and every other test are untouched.
- **Swift bridge test** `ios/Tests/CoverageTests.swift` (Swift Testing) — GAP / PARTIAL / COVERED and both
  `needsReview` values over the bridge.

**One design point worth stating up front** (detail in [`research.md`](./research.md)): the FFI wrapper is named
`compute_coverage` and therefore **shadows** the pure `coverage::compute_coverage`. To avoid a name clash the
bridge module imports only the coverage **types** (not the pure function) and calls the pure function
**fully-qualified**; `lib.rs` re-exports only the FFI wrapper at the crate root. This is the exact precedent set
by `cross_source_duplicates` in slice 013 (research D-FFI).

**Verified before writing this plan** (a throwaway simulation of the locked algorithm, run then discarded — repo
left clean): `month_window(2026-06-14, 24)` yields 24 labels with `[0] = "2024-07"` and `[23] = "2026-06"`; and
the reference scenario (statements period-end `2026-05-16`/false + `2026-02-28`/true; transactions `2026-04-10`
alert + `2026-05-05` full + `2026-01-20` full; `today = 2026-06-14`) classifies **exactly** `2026-01`
COVERED/false, `2026-02` COVERED/true, `2026-04` PARTIAL/false, `2026-05` COVERED/false, and the other **20**
months GAP/false (24 total, 0 misclassifications). Evidence is captured in [`research.md`](./research.md)
(Verification).

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency** (`std::collections::HashMap` + `chrono::Datelike` only)
**Storage**: N/A (no persistence this slice; the platform supplies the pre-aggregated facts; encrypted SQLite/SQLCipher and any on-device aggregation are explicitly out of scope)
**Testing**: `cargo test` (`coverage.rs` unit tests + `tests/parity.rs` golden harness + determinism) and Swift Testing (`ios/Tests/CoverageTests.swift`); the privacy-egress audit stays green
**Target Platform**: iOS 18+ (device + simulator) via the UniFFI bridge; the engine itself is platform-agnostic (Android/desktop later)
**Project Type**: Mobile — shared Rust core (`kaname-core`) + native SwiftUI app (`ios/`)
**Performance Goals**: deterministic, on-device; the classifier is `O(|statements| + |transactions| + 24)` over statement/transaction-scale inputs — not a perf-critical path this slice (correctness + parity are the goals)
**Constraints**: pure & deterministic (**never reads the wall-clock** — `today` is a parameter — no network/locale/global state, no file/DB/PDF I/O); no money is computed (dates/states only); zero network (privacy-egress gate); no new deps; Apache-2.0, no copyleft
**Scale/Scope**: two in-memory fact lists of statement/transaction scale (~10⁰–10³ rows) + one `today` date; one new module with two pure functions + three types + one const + one bridge export + one fixture + tests

## Constitution Check

*GATE: evaluated before Phase 0 and re-checked after Phase 1 design. All gates PASS.*

- **I. Data Privacy & Sovereignty (NON-NEGOTIABLE)** — **PASS.** The classifier is pure and on-device: building
  the window, bucketing facts, and labelling months touch **no network, no clock, no locale, no file, no
  database**. It adds no telemetry/analytics/ad/crash SDK. The existing automated **privacy-egress test**
  (`make core-privacy-audit`) covers the new path — this slice adds **no dependency**, so the shipped dependency
  graph is byte-identical (FR-014/015/016, SC-010/012).
- **II. Local-First Shared Engine** — **PASS.** The logic lives in `kaname-core` as pure, deterministic functions
  over the shared `NaiveDate` type, reused across platforms via UniFFI. **The core never reads the wall-clock —
  `today` is a required parameter** (FR-003, SC-006); identical inputs always yield identical output. No money is
  involved (dates/states only), so the exact-`Decimal` rule has no comparison here. No PDF engine, no database
  (FR-011/013).
- **III. Open-Core & Permissive Licensing** — **PASS.** No secrets, keys, or private endpoints. Apache-2.0 clean:
  **no new runtime OR dev dependency** (the classifier uses only `std::collections::HashMap` and
  `chrono::Datelike`, both already present), so no copyleft (GPL/AGPL/LGPL) risk is introduced (FR-021, SC-011/012).
- **IV. Native Experience & Accessibility** — **N/A this slice.** No UI is introduced (engine + bridge + tests
  only); the coverage map's **visual surface is a later P3 app slice** (spec Out of Scope). If/when that surface
  lands it must follow the latest HIG + Dynamic Type/Dark Mode/VoiceOver (FR-023).
- **V. Test-First & Parity** — **PASS.** Behaviour is pinned to the web engine (`coverage.py`: `month_window` +
  the classification loop) and proven test-first: a golden fixture (`fixtures/coverage/basic.json`), a
  parity-harness test (`coverage_map_matches_expected`), `coverage.rs` unit tests (window reference output +
  determinism + the reference scenario + empty input + out-of-window facts + statement-only vs full-txn
  `needsReview`), and a Swift bridge test. All fixture/test data is synthetic (fabricated dates/states) (FR-017..
  FR-020, SC-003/007/008).

**iOS Local Verification Gate**: unchanged and honored — `make core-lint && make core-test &&
make core-privacy-audit && make lint && make ios-test`, with `make core-xcframework` **before** `tuist generate`
(baked into `make ios-gen`). See [`quickstart.md`](./quickstart.md).

**Result**: **PASS** (no violations). The only nuance recorded in Complexity Tracking is scope — this is
deliberately the **portable subset** of the web coverage feature (the pure classifier over pre-aggregated facts;
the DB aggregation the web `coverage.py` does from its `transactions`/`statements` tables stays on the platform).

## Project Structure

### Documentation (this feature)

```text
specs/014-coverage/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — decisions, alternatives, verification evidence
├── data-model.md        # Phase 1 — CoverageState, StatementCoverage, TransactionCoverage, MonthCoverage, fns
├── quickstart.md        # Phase 1 — build & verify walkthrough (iOS gate ordering)
├── contracts/           # Phase 1 — behaviour + FFI + golden-fixture contracts
│   ├── coverage.md            # the pure month_window + compute_coverage behaviour contract
│   ├── engine-ffi.md          # the UniFFI Swift surface (computeCoverage + the 4 types)
│   └── golden-fixture.md      # the NEW coverage fixture schema + exact bytes for basic.json
├── checklists/          # (pre-existing) requirements checklist
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── src/
│   ├── coverage.rs      # NEW top-level module (sibling to dedup.rs): CoverageState, StatementCoverage,
│   │                    #   TransactionCoverage, MonthCoverage, COVERAGE_MONTHS, month_window,
│   │                    #   compute_coverage, unit tests
│   ├── ffi.rs           # EXTEND: + #[uniffi::export] compute_coverage wrapper (imports coverage TYPES only,
│   │                    #   calls the pure fn fully-qualified to avoid the name clash)
│   ├── lib.rs           # EXTEND: pub mod coverage; re-export ffi::compute_coverage +
│   │                    #   coverage::{CoverageState, MonthCoverage, StatementCoverage, TransactionCoverage,
│   │                    #   month_window}
│   ├── model.rs         # REUSED unchanged — Transaction, Direction (not needed by coverage, untouched)
│   └── statement/       # REUSED unchanged — readers, balance_chain, reconcile
└── tests/
    └── parity.rs        # EXTEND: + coverage fixture loader + coverage_map_matches_expected

fixtures/
└── coverage/
    └── basic.json       # NEW fixture shape: { today, statements[], transactions[], expected_months[] }

ios/
└── Tests/
    └── CoverageTests.swift    # NEW Swift Testing bridge test

.github/copilot-instructions.md   # regenerated by update-agent-context.sh (+ `iOS 18 targe` typo fix)
```

**Structure Decision**: Mobile shared-core layout (unchanged). Coverage is a **new, independent classification
concern** (distinct from parsing/reconcile/dedup), so it gets its **own top-level module** `coverage.rs` — a
sibling to `dedup.rs` — exactly as the requester specified, rather than being wedged into an unrelated module.
The FFI wrapper + re-exports follow the `cross_source_duplicates` precedent exactly (including the deliberate
non-re-export of the pure function to avoid the name clash). Only the files listed above change; no reader,
`model.rs`, `base.rs`, `uniffi.toml`, `Cargo.toml`, or CI change.

## Complexity Tracking

> No Constitution **violations**. The single nuance below is a deliberate **scope** decision (a faithful subset),
> not a principle violation, and is recorded per Governance for reviewer clarity.

| Nuance | Why (this slice) | Why the rest is correctly excluded |
|---|---|---|
| Ports **only** the pure classifier (`month_window` + the GAP/PARTIAL/COVERED + `needsReview` loop), **not** the web `coverage.py`'s DB aggregation | The classifier is the **only part that is pure and store-free** — it needs just `today` + two in-memory fact lists. The platform (which owns persistence) supplies the **pre-aggregated** facts the web engine queries from its `transactions`/`statements` tables | The **aggregation** (SQL over a `transactions`/`statements` store, per-account grouping) needs the encrypted SQLite/SQLCipher store that is a later phase; the **HTTP endpoint** is a web concern; **cross-account** attribution is out of scope (the caller scopes facts to one account). When a store lands, aggregation can move into the core **without changing the classifier's behaviour** (spec Assumptions, Out of Scope, FR-013) |
| Coverage gets a **new top-level module** (`coverage.rs`) rather than joining an existing one | Coverage is a distinct concern from parsing/reconcile/dedup; a sibling module mirrors `dedup.rs` and keeps the diff surgical | Reusing `dedup.rs`/`statement/*` would conflate unrelated logic; the module is ~1 classifier + 1 window helper + 3 types + tests |

## Phase 0 — Outline & Research

The approach is **locked** by the requester and pinned to the web engine (`coverage.py`); there are **no NEEDS
CLARIFICATION** items. Phase 0 records the decisions, the alternatives rejected, and the byte-for-byte
verification of the two ported functions (`month_window` label generation and the `compute_coverage` reference
scenario). See [`research.md`](./research.md) for the decision log and the Verification section.

**Output**: [`research.md`](./research.md) — complete, all unknowns resolved, verification evidence attached.

## Phase 1 — Design & Contracts

- **Data model** — [`data-model.md`](./data-model.md): the `CoverageState` enum, the `StatementCoverage` /
  `TransactionCoverage` input records, the `MonthCoverage` output record, `COVERAGE_MONTHS = 24`, the
  `month_window` and `compute_coverage` functions (window generation via `Datelike`; the `earliest` cutoff; the
  two per-month `HashMap`s; the classification loop), plus the reused `NaiveDate` type and the parity fixture
  types.
- **Contracts** — [`contracts/`](./contracts):
  - `coverage.md` — the pure classifier's stable behaviour contract (`month_window` label rule; the two COVERED
    paths; PARTIAL/GAP; the `needsReview` OR-from-statements-only rule; the `earliest` cutoff; determinism/
    totality).
  - `engine-ffi.md` — the UniFFI Swift surface (`computeCoverage(today:statements:transactions:)`,
    `CoverageState`, `StatementCoverage`, `TransactionCoverage`, `MonthCoverage`).
  - `golden-fixture.md` — the **new** coverage fixture schema and the exact `basic.json` bytes (the verified 24
    expected entries).
- **Agent context** — run `.specify/scripts/bash/update-agent-context.sh copilot` to refresh
  `.github/copilot-instructions.md` with this slice's tech line (then apply the known `iOS 18 targe` → `iOS 18
  target` fix; see the report).

**Output**: `data-model.md`, `contracts/*`, `quickstart.md`, and the refreshed agent context file.

## Phase 2 — (Not executed here)

`/speckit.tasks` will turn these artifacts into an ordered `tasks.md`. This command stops after Phase 1.
