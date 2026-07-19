# Quickstart — On-Device Statement Coverage Map (build & verify)

**Feature**: `014-coverage` | **Date**: 2026-07-19
Walkthrough to build, test, and verify the slice locally, honoring the iOS Local Verification Gate ordering
(xcframework **before** `tuist generate`). Commands run from the repo root unless noted. This is the pure port of
the web engine's `coverage.py` (`month_window` + the GAP/PARTIAL/COVERED + `needsReview` classification) into a
**new top-level `coverage.rs`** module: it **reuses** every existing gate, the shared `NaiveDate` date type, the
parity harness, and the UniFFI bridge, and adds **no new runtime or dev dependency** (`std::collections::HashMap`
+ `chrono::Datelike` only). The core **never reads the wall-clock** — `today` is a parameter.

---

## Prerequisites
- Toolchain per `rust-toolchain.toml` (stable + iOS targets) and `make bootstrap` (tuist, swiftlint,
  swift-format). iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`.
- Local Xcode: an **"iPhone 16"** simulator (the `-destination …,name=iPhone 16,OS=latest` used by
  `make ios-test` must exist).
- `cargo` on PATH (`source "$HOME/.cargo/env"` if needed).

## 0. Ground truth (already captured & verified — no live run needed)
The coverage behaviour is the locked ground truth from the web engine's `coverage.py` (`month_window` +
`compute_coverage`, `COVERAGE_MONTHS = 24`). The **window** and the **reference-scenario classification** were
re-confirmed by simulating the locked algorithm (research "Verification"):

| `month_window(2026-06-14, 24)` | result |
|---|---|
| length | `24` |
| `[0]` (oldest) | `"2024-07"` |
| `[23]` (newest) | `"2026-06"` |

Reference scenario — `today = 2026-06-14`; statements `2026-05-16`/needs_review **false** + `2026-02-28`/**true**;
transactions `2026-04-10`/from_full **false** + `2026-05-05`/**true** + `2026-01-20`/**true**; `earliest =
2024-07-01`:

| Month | State / needsReview | Why |
|---|---|---|
| `2026-01` | **Covered / false** | full-statement txn only (`2026-01-20`), no statement fact → `needsReview` defaults false |
| `2026-02` | **Covered / true** | needs-review statement `2026-02-28` |
| `2026-04` | **Partial / false** | alert-only txn `2026-04-10`, no full statement |
| `2026-05` | **Covered / false** | statement `2026-05-16` (needs_review false) + full-statement txn `2026-05-05` |
| the other **20** | **Gap / false** | no fact |

24 entries total, 20 GAP, 0 misclassifications. The exact golden-fixture bytes (24 `expected_months`) are in
`contracts/golden-fixture.md`.

## 1. Core — format, lint, test (test-first)
```bash
make core-test      # cargo test --all --all-features → coverage.rs unit tests + tests/parity.rs (coverage/basic.json) + determinism
make core-lint      # cargo fmt --check + clippy -D warnings
```
Expected:
- `coverage.rs` unit tests pass — `month_window(2026-06-14, 24)` has 24 labels with `[0]=="2024-07"` /
  `[23]=="2026-06"` and is deterministic; `compute_coverage` on the reference scenario asserts the 4 non-GAP
  months + a GAP + total 24; **empty input → 24 GAP**; an out-of-window / future-month fact is ignored; a month
  **COVERED via a full-statement txn only** has `needsReview == false`.
- Parity harness reproduces the web-engine output **exactly**: `coverage_map_matches_expected` loads
  `coverage/basic.json`, builds the typed inputs (parse ISO dates), calls `compute_coverage`, and asserts the 24
  entries equal `expected_months`. The statement `CASES`, the dedup loader/test, and all prior parity tests are
  **untouched**.

## 2. Privacy-egress gate (inherited — must stay green)
```bash
make core-privacy-audit   # cargo tree denylist over kaname-core's shipped (default, -e normal) deps
```
Expected: `privacy-egress: OK (no networking crate in kaname-core deps)`. This slice adds **no dependency**
(`std::HashMap` + `chrono::Datelike` only), so the shipped graph is byte-identical to before — the gate must
remain green with zero changes, and it covers the new `compute_coverage` path (pure, on-device, zero network,
zero clock — FR-003/014/016).

## 3. Build the engine xcframework (MUST precede tuist generate)
```bash
make core-xcframework     # compiles device+sim slices, runs uniffi-bindgen, lipo, create-xcframework
```
Produces `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift` (git-ignored) — now also
exporting `computeCoverage`, the `CoverageState` enum (`.gap`/`.partial`/`.covered`), and the `StatementCoverage`
/ `TransactionCoverage` / `MonthCoverage` records. `NaiveDate` fields cross as ISO-8601 `String`s via the existing
custom type; **no `uniffi.toml` change**.

## 4. iOS — generate, lint, test
```bash
make lint                 # swiftlint --strict + swift-format lint --strict
make ios-test             # ios-gen (depends on core-xcframework) → xcodebuild … -destination 'name=iPhone 16' test
```
Expected: the "core ↔ Swift coverage map" suite (`ios/Tests/CoverageTests.swift`) passes — build
`[StatementCoverage]` + `[TransactionCoverage]` for the reference scenario, call
`computeCoverage(today: "2026-06-14", statements:, transactions:)`, assert `count == 24`, and (indexing by
`month`) assert `2026-05` `.covered`/false, `2026-02` `.covered`/true, `2026-04` `.partial`, `2026-01`
`.covered`/false, and a sample GAP month `.gap`. `CoverageState` surfaces as `.gap`/`.partial`/`.covered`; records
as `periodEnd`/`needsReview`, `date`/`fromFullStatement`, `month`/`state`/`needsReview`.

> **swift-format `[Spacing]`**: no trailing inline `//` comment after code — put any comment on its own line
> **above** the statement, or `make lint` fails.

## 5. Full local gate (what CI runs)
```bash
make core-lint && make core-test && make core-privacy-audit && make lint && make ios-test
```
CI mirrors this unchanged: the **core** job (ubuntu) runs the privacy audit; the **iOS** job stays on `macos-15`
and builds the xcframework before `tuist generate`.

---

## Try the classifier (ad-hoc, optional)
The classifier is pure — a tiny Rust snippet exercises all three states without the app:
```rust
use kaname_core::{compute_coverage, CoverageState, MonthCoverage, StatementCoverage, TransactionCoverage};
use chrono::NaiveDate;

let d = |s: &str| NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap();

let statements = vec![
    // COVERED via a statement fact; needsReview false.
    StatementCoverage { period_end: d("2026-05-16"), needs_review: false },
    // COVERED via a statement fact; needsReview true.
    StatementCoverage { period_end: d("2026-02-28"), needs_review: true },
];
let transactions = vec![
    // PARTIAL: alert-only (not from a full statement).
    TransactionCoverage { date: d("2026-04-10"), from_full_statement: false },
    // COVERED path (b): co-occurs with the 2026-05 statement.
    TransactionCoverage { date: d("2026-05-05"), from_full_statement: true },
    // COVERED path (b) only: no statement fact for 2026-01 → needsReview defaults false.
    TransactionCoverage { date: d("2026-01-20"), from_full_statement: true },
];

let map = compute_coverage(d("2026-06-14"), &statements, &transactions);
assert_eq!(map.len(), 24);                 // exactly 24, oldest first
assert_eq!(map.first().unwrap().month, "2024-07");
assert_eq!(map.last().unwrap().month, "2026-06");
let by_month = |m: &str| map.iter().find(|e| e.month == m).unwrap().clone();
assert_eq!(by_month("2026-01"), MonthCoverage { month: "2026-01".into(), state: CoverageState::Covered, needs_review: false });
assert_eq!(by_month("2026-02"), MonthCoverage { month: "2026-02".into(), state: CoverageState::Covered, needs_review: true });
assert_eq!(by_month("2026-04").state, CoverageState::Partial);
assert_eq!(by_month("2026-05"), MonthCoverage { month: "2026-05".into(), state: CoverageState::Covered, needs_review: false });
assert_eq!(by_month("2026-03").state, CoverageState::Gap);
```
> Note: this ad-hoc snippet calls the FFI-exported `kaname_core::compute_coverage` with `&statements` /
> `&transactions` (the crate root re-exports the FFI wrapper). Over the bridge, Swift passes owned arrays.

## Add another coverage vector (future scenarios)
1. Add a sibling `fixtures/coverage/*.json` (or extend `basic.json`), dates as **ISO strings**, per
   `contracts/golden-fixture.md`.
2. Capture the `expected_months` from the pinned `coverage.py` logic (`month_window` + the classification loop),
   then point the parity loader at the new file (or parameterise it) and run `make core-test`.
3. `coverage.rs` needs **no change** — the classifier is fact-source-agnostic (it takes `today` + the two fact
   lists).

## Troubleshooting
- **`cargo` not found**: `source "$HOME/.cargo/env"`.
- **`xcodebuild` can't find a destination**: create the "iPhone 16" simulator in Xcode.
- **Swift can't see `computeCoverage`/`CoverageState`/`MonthCoverage`**: rebuild `make core-xcframework` before
  `tuist generate` (generated Swift is an artifact).
- **`make lint` fails on `CoverageTests.swift`**: a trailing inline `//` comment after code violates swift-format
  `[Spacing]` — move it to its own line above the statement.
- **Name clash building the crate root** (`compute_coverage` defined twice): only the **FFI** `compute_coverage`
  is re-exported at the crate root (`pub use ffi::compute_coverage;`); the pure `coverage::compute_coverage` is
  **not** re-exported, and `ffi.rs` imports only the coverage **types** (not the pure fn) and calls it
  fully-qualified (research D7). `tests/parity.rs` and Swift both use the FFI-exported one.
- **The map has ≠ 24 entries**: the output is built by iterating the 24-label `window` (not the fact maps) — check
  `compute_coverage` iterates `window`, and `COVERAGE_MONTHS == 24`.
- **A month is COVERED but should be PARTIAL (or vice-versa)**: COVERED requires a statement fact in the month
  **or** a transaction with `from_full_statement == true`; an alert-only transaction (`from_full_statement ==
  false`) is PARTIAL. Check the `from_full_statement` OR-in and the `covered_by_statement || (has_txn &&
  has_full)` order.
- **`needsReview` set on a PARTIAL/GAP month, or on a full-txn-only COVERED month**: `needsReview` is read **only**
  on the COVERED branch, as `*stmt_by_month.get(label).unwrap_or(&false)` — a month with no statement fact
  defaults `false` (research D4). PARTIAL/GAP always `false`.
- **An old fact changed a month it shouldn't**: facts before `earliest` (first day of the oldest window month) are
  skipped by the `>= earliest` guard; a future-month fact has no `window` label and never appears (research D8).
- **Determinism worry (`HashMap` order)**: the output order comes from iterating the `window` `Vec`, not the map,
  so `HashMap` iteration order never reaches the result — output is byte-identical across runs (research D11).
- **The core read the clock**: it must not — `today` is a parameter; `month_window` uses `today.year()` /
  `today.month()` only. Never call `chrono::Local::now()` (Constitution II).
- **Privacy audit false positive**: this slice adds no dep; if a networking crate appears, that's an unrelated
  regression — the gate is working.
