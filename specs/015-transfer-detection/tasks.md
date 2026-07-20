---
description: "Task list — On-Device Transfer (Self-Transfer) Detection (transfer.rs: the pure, clock-free outflow-anchored greedy matcher — ±1-day / ±₹1.00 tolerance envelope + token-Jaccard narration_similarity + the web _score — ported from the web engine's transfer_detector.py pure subset; std sets + chrono + rust_decimal ToPrimitive only; zero new runtime OR dev dependency; money stays Decimal, only the confidence score is f64)"
---

# Tasks: On-Device Transfer (Self-Transfer) Detection — the Pure Deterministic Pairing of Opposite-Direction Cross-Account Rows into Self-Transfer / Credit-Card Bill-Payment Pairs

**Input**: Design documents from `/specs/015-transfer-detection/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/{transfer.md, engine-ffi.md, golden-fixture.md}`, `quickstart.md`

**Tests**: REQUIRED and **TEST-FIRST** (Constitution Principle V). The new golden fixture, the failing Rust
parity test, and the failing Swift bridge test are authored **RED, before** the `transfer.rs` matcher that greens
them. The `expected_pairs` are the **locked ground truth captured from a live run of the web engine's pure helpers**
(`transfer_detector.py`'s `_narration_similarity` + `_score` + the ±1-day / ±₹1.00 envelope + the outflow-anchored
greedy claim from `detect_pairs_for_user` / `_best_counterpart`; the SQL path is not ported): for
`fixtures/transfer/basic.json` the **20-row** nine-scenario pool yields **exactly 5 pairs** in anchor `(date, id)`
order — `s1-out→s1-in` `1.0285714285714285`, `s2-out→s2-in` `0.8200000000000001`, `s7-out→s7-in-a` `1.05`,
`s8-out→s8-in-a` `1.2`, `s9-out→s9-in` (cc=true) `1.0333333333333334` — and **4 guards** (S3 amount-drift, S4
date-drift, S5 same-direction, S6 same-account) produce none. Every `score` is compared with **exact `f64` `==`**
(the port reproduces the web bits — research D5).

**Port source of truth** (faithful, byte-for-byte with the golden vector): the web engine's
`transfer_detector.py` **pure subset** — `_narration_similarity` (token-Jaccard on the raw lowercased,
whitespace-split description), `_score` (`max(0, 1 − 0.2·date_diff − 0.2·amount_diff + 0.2·sim)`, floored at 0.0,
**not** capped at 1.0), the ±1-day / ±₹1.00 tolerance envelope, and the outflow-anchored greedy selection with the
`(date_diff, amount_diff, -narration_similarity, id)` tuple. This slice is the on-device analogue of the **pure
pairing only** — every DB/persistence concern of the web `transfer_detector.py` (`transfer_group_id`/`is_transfer`
writes, the "Self Transfer" / "Credit Card Bill Payment" category get-or-create, audit events, the
optimistic-concurrency `_claim_pair`/SAVEPOINT race handling, cross-user filtering, and the `match_window_days`
email-parse override) stays **platform-side** (spec Assumptions, Out of Scope, FR-014/016). It slots into the core
as a **new top-level module** `transfer.rs`, a sibling to `dedup.rs` and `coverage.rs`, exactly as `coverage.rs` sat
beside `dedup.rs`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: `US1`=pair a self-transfer (P1) · `US2`=never pair non-transfers / the four guards (P2) ·
  `US3`=deterministic tiebreaks — narration then id (P3) · `US4`=credit-card-payment flag (P4) ·
  `US5`=confidence `score` (P5) · `US6`=greedy single-claim + anchor ordering (P6) · `US7`=bridge / no-new-infra
  (P7) · `US8`=golden-fixture parity (P8) · `US9`=privacy-egress (P9). Setup/Polish carry no story label.
- Exact file paths are included in every task.

## ♻️ REUSE — do NOT re-create

Transfer detection is a **new, independent ingestion-signal concern** delivered as a **new top-level module** + its
bridge, plugging into the shipped foundations unchanged (mirroring how `coverage.rs` reused the P1 + dedup
foundations). Do **not** rebuild any of these:

- `src/ffi.rs` — the `uniffi::custom_type!(Decimal, String, …)` (`ffi.rs:32`) and
  `uniffi::custom_type!(NaiveDate, String, …)` (`ffi.rs:39`) are **reused verbatim** for `amount` / `date` (**no
  `uniffi.toml` change**); the new export mirrors the `cross_source_duplicates` (`ffi.rs:63–69`) / `compute_coverage`
  (`ffi.rs:75–82`) wrappers exactly, including the name-clash handling (types-only import + fully-qualified call).
- `src/lib.rs` — the module list (`lib.rs:22–26`) and the crate-root re-export blocks (`lib.rs:28–45`); add
  `pub mod transfer;` and the new FFI fn + transfer types beside the existing `coverage::{…}` / `ffi::{…}` re-exports.
- `tests/parity.rs` — the golden-fixture harness; add a **separate, transfer-only** loader + one test. The statement
  `Fixture`/`Expected`/`CASES`, the dedup `DedupFixture`/`cross_source_dedup_matches_expected` (`parity.rs:501–557`),
  the coverage `CoverageFixture`/`coverage_map_matches_expected` (`parity.rs:560–627`), and **every** current test are
  **untouched**.
- `src/model.rs` — the `Direction` enum (`Debit` = outflow / `Credit` = inflow) is reused **unchanged** for
  `TransferInput.direction`; `Transaction` is untouched. **No `model.rs` change.**
- `rust_decimal::Decimal` (money + the `Decimal::ONE` ±₹1 tolerance) and `chrono::NaiveDate` (dates) — the shared
  types, reused via the already-registered custom types. **No new custom type.**
- The **privacy-egress gate** (`make core-privacy-audit`) + CI — inherited unchanged (**no new dependency** →
  byte-identical shipped `cargo tree`; the matcher uses only `std` token sets, `chrono` `NaiveDate` subtraction, and
  `rust_decimal`'s `ToPrimitive::to_f64`).
- `dedup.rs` / `statement/*` / every reader — **untouched**. In particular, transfer's `narration_similarity`
  (token-Jaccard) MUST **not** call `dedup::normalize_narration` or reuse `dedup`'s Jaro-Winkler helpers (research
  D4 — the key porting gotcha).

**The only NEW code**: a new file `src/transfer.rs` (the `TransferInput` + `TransferPair` records, the
`DATE_TOLERANCE_DAYS` const, the pure `detect_transfers` matcher, the private `narration_similarity` + `score`
helpers, and unit tests); `pub mod transfer;` + one `#[uniffi::export]` wrapper in `ffi.rs` + `lib.rs` re-exports;
one new fixture (`fixtures/transfer/basic.json`, a **new shape**); a transfer loader + one parity test; and one
Swift bridge test. **No new dependency** (runtime *or* dev); **no `uniffi.toml`/`model.rs`/`base.rs`/reader/`Cargo.toml`
change**.

## 🎯 The matcher — the whole decision surface (contracts/transfer.md, data-model.md)

`detect_transfers(rows: &[TransferInput]) -> Vec<TransferPair>` — the pure port of `detect_pairs_for_user` +
`_best_counterpart`, minus SQL:

1. **Anchors** = indices of `Direction::Debit` (outflow) rows, **sorted ascending by `(date, id)`**
   (`rows[i].date.cmp(&rows[j].date).then_with(|| rows[i].id.cmp(&rows[j].id))`).
2. **Consumed** = `vec![false; rows.len()]`, indexed by row position.
3. For each anchor `a` in order: `if consumed[a] { continue; }`. Build the **candidate set** = every index `c` with
   **all** guards below. If empty, `continue`.
4. **Best** = `min_by` over the candidates on the tuple `(date_diff, amount_diff, -narration_similarity, id)` —
   `di.cmp(&dj).then_with(|| ai.cmp(&aj)).then_with(|| sj.partial_cmp(&si).unwrap()).then_with(|| rows[i].id.cmp(&rows[j].id))`.
5. **Claim** both `a` and `best` (`consumed`), and **emit** a `TransferPair`. Pairs are pushed in anchor order → the
   output is naturally ordered by anchor `(date, id)`.

**Candidate eligibility (the whole guard surface)** — a candidate `c` is eligible iff **ALL** hold:
`!consumed[c]` · `rows[c].account_id != rows[a].account_id` (different account) · `rows[c].direction ==
Direction::Credit` (opposite direction / inflow) · `(rows[a].date - rows[c].date).num_days().abs() <=
DATE_TOLERANCE_DAYS` (`= 1`, inclusive) · `(rows[a].amount - rows[c].amount).abs() <= Decimal::ONE` (±₹1.00,
inclusive). Failing **any** guard ⇒ ineligible; **no** eligible candidate ⇒ the anchor emits **no pair**.

**Emitted pair**: `outflow_id = rows[a].id` · `inflow_id = rows[best].id` · `is_credit_card_payment =
rows[a].is_credit_card || rows[best].is_credit_card` (either leg a card) · `score = score(date_diff, amount_diff,
sim)` for the chosen best.

`narration_similarity(a, b)`: token-level **Jaccard** on the **raw lowercased, whitespace-split** descriptions —
`|A ∩ B| / |A ∪ B|` as f64 over the token **sets**; **0.0** if either string is empty or yields no tokens.
`score(date_diff, amount_diff, sim)`: `(((1.0 - 0.2·date_diff) - 0.2·amount_diff_f64) + 0.2·sim).max(0.0)` with
`amount_diff_f64 = amount_diff.to_f64().unwrap_or(0.0)` — exact Python left-to-right op order.

**Invariants**: anchor = outflows only, `(date, id)` order · greedy single-claim (each row in ≤ 1 pair) via the
shared `consumed` vector; earliest anchor wins a contested inflow · selection = min `(date_diff ↑, amount_diff ↑,
similarity ↓, id ↑)` (unique `id` ⇒ strict total order) · `is_credit_card_payment` = OR of the two legs ·
`score` floored at 0.0, **not** capped at 1.0 · output ordered by anchor `(date, id)` · pure/total/deterministic
(no I/O, network, **clock**, locale, global state; empty / no-outflow input ⇒ empty `Vec`; never panics — the two
`unwrap`s are safe: candidates non-empty, similarity finite in `[0,1]`) · **money exact** (`Decimal` + `Decimal::ONE`);
only `score` is `f64`.

## ⚠️ Local gotchas (apply throughout)

- **`narration_similarity` is DISTINCT from de-dup (research D4 — THE gotcha)**: raw-token **Jaccard** on the
  lowercased, whitespace-split description — **no** prefix/RRN/refnum stripping, **set**-Jaccard not character
  Jaro-Winkler. It must **not** call `dedup::normalize_narration` or reuse `dedup`'s `jaro`/`jaro_winkler` (FR-008).
- **`score` is floored at 0.0 but NOT capped at 1.0 (research D5)**: live same-day/same-amount pairs with narration
  overlap legitimately exceed 1.0 (`1.0285714285714285` / `1.05` / `1.2` / `1.0333333333333334`). Do **not** add a
  `.min(1.0)`. Keep the **exact Python left-to-right op order** `((1.0 - 0.2·date_diff) - 0.2·amount_diff_f64) +
  0.2·sim` and `amount_diff.to_f64().unwrap_or(0.0)` — reordering the additions changes the last ULP and breaks the
  exact-`==` parity assertion.
- **Name clash (research D9)**: the FFI wrapper `detect_transfers` **shadows** the pure `transfer::detect_transfers`.
  So `ffi.rs` imports only the transfer **types** (`use crate::transfer::{TransferInput, TransferPair};` — **not** the
  pure fn) and calls it **fully-qualified** (`crate::transfer::detect_transfers(&rows)`); `lib.rs` re-exports only the
  **FFI** `detect_transfers` (`pub use ffi::detect_transfers;`) + the transfer types (`pub use transfer::{TransferInput,
  TransferPair};`) — **NOT** `transfer::detect_transfers`. `tests/parity.rs` and Swift both use the FFI-exported one
  via `kaname_core::detect_transfers` (owned `Vec`). Exact `compute_coverage` (014) / `cross_source_duplicates` (013)
  precedent.
- **`transfer.rs` is a brand-NEW module** — `pub mod transfer;` must be added to `lib.rs` **when the file is
  created** (T006) or the crate (and its unit tests) won't compile. `fixtures/transfer/` is a **NEW directory** (a new
  fixture *shape*), created in T003.
- **`Decimal::ONE`, not `dec!`**: the ±₹1.00 amount tolerance uses the `rust_decimal` associated const `Decimal::ONE`
  directly in the matcher; `rust_decimal_macros::dec!` stays in **tests only** (research D7).
- **The core NEVER reads the wall-clock (Constitution II)**: `detect_transfers` takes **only** the row pool — there is
  **no `today` parameter** and no clock/locale/DB access. `date_diff` is derived from the two rows' `date`s (FR-012).
- **Determinism despite `HashSet` (research D8/D11)**: the token sets feed **only** intersection/union **counts**, and
  candidate selection is a strict total order over row indices (unique `id`), so `HashSet`/iteration order never
  reaches the result — output is byte-identical across runs (SC-009).
- **`make core-xcframework` MUST run before `tuist generate`** (`ios-gen: core-xcframework`) — the generated Swift +
  `KanameCoreFFI.xcframework` are rebuilt artifacts; run it after the FFI surface changes (new `detectTransfers` +
  `TransferInput`/`TransferPair`).
- **The iOS CI job stays pinned to `macos-15`**; the local `xcodebuild` destination is the **"iPhone 16"** simulator
  (`OS=latest`) — create it in Xcode first.
- **swift-format `[Spacing]` rejects trailing inline comments** — in `TransferDetectionTests.swift` any comment goes on
  its **own line above** the code, never trailing after it.
- **rustfmt reformats edits** — after each `edit`, run `make core-fmt` then re-view before the next edit
  (arrays/asserts/imports/comparators get re-wrapped).
- **No new dependency**: `transfer.rs` uses only `std` (token `HashSet`, `Vec`, sort, `cmp`/`partial_cmp`), `chrono`
  (`NaiveDate` subtraction → `num_days`), and `rust_decimal` (`Decimal` arithmetic, `Decimal::ONE`, `ToPrimitive::to_f64`)
  — all already in the graph. `core/crates/kaname-core/Cargo.toml` stays **UNCHANGED**. Money is exact `Decimal`; only
  the confidence `score` is `f64`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm invariants so every later task lands cleanly and the gates stay green. No behavior yet.

- [ ] T001 [P] [US7] Confirm the **no-new-dependency / no-new-infra** invariant: `core/crates/kaname-core/Cargo.toml` stays **UNCHANGED** (runtime `regex`/`rust_decimal`/`chrono`/`serde`/`uniffi` + dev-only `serde_json` already present) — this slice adds **zero** deps (`std` token sets + `chrono` `NaiveDate` subtraction + `rust_decimal`'s `Decimal::ONE`/`ToPrimitive::to_f64` only) and **no** new shared engine helper beyond the matcher, `narration_similarity`/`score`, and their types (FR-013/024, SC-013). Note that `transfer.rs` is a **NEW** top-level module (sibling to `dedup.rs`/`coverage.rs`) and `fixtures/transfer/` is a **NEW** directory (a new fixture *shape*), both created in later tasks. Ref: plan §Summary/§Structure Decision, `data-model.md` §Reuse contract.
- [ ] T002 [P] Verify local prerequisites & gotchas (no code): `cargo` on PATH (`source "$HOME/.cargo/env"` if needed); an **"iPhone 16" simulator** exists in Xcode; recall `make core-xcframework` precedes `tuist generate`, the iOS CI job is pinned to **`macos-15`**, **swift-format `[Spacing]` forbids trailing inline comments**, the **core never reads the wall-clock** (the row pool is the only input — there is no `today`; Constitution II), the **`detect_transfers` name clash** is handled by a types-only import + fully-qualified call in `ffi.rs` (research D9), **`narration_similarity` is token-Jaccard DISTINCT from `dedup`** (research D4), and **`score` is floored at 0.0 but NOT capped at 1.0** with the exact left-to-right op order (research D5). Ref: `quickstart.md` §Prerequisites/§Troubleshooting.

**Checkpoint**: No manifest/`uniffi.toml`/`model.rs` change needed; toolchain + simulator + CI ordering + the clock-free + name-clash + similarity/score nuances understood.

---

## Phase 2: Test-First Foundation (⚠️ Principle V — author RED before ANY transfer engine code)

**Purpose**: Pin the on-device matcher to the proven web engine **before** writing it. These are the golden parity
(US8) and bridge (US7) tests that protect the slice; they MUST be **RED** at the end of this phase (`detect_transfers`
/ `TransferInput` / `TransferPair` do not exist yet).

**⚠️ CRITICAL**: No engine code (Phase 3+) until T003–T005 exist and are verified failing (compile-fail is acceptable
RED for the Rust harness; the Swift test won't build until Phase 4).

- [ ] T003 [P] [US8] Create the **new-shape** golden fixture `fixtures/transfer/basic.json` (new directory) — the **exact bytes** from `contracts/golden-fixture.md` §"Exact bytes": the `_comment` provenance string, a `rows` array of **exactly 20** objects (each `{ id, account_id, is_credit_card, date, amount, direction, description }` — `amount` a decimal **STRING** re-parsed to `Decimal` (never a float), `date` ISO-8601, `direction` exactly `"Debit"`/`"Credit"`), and an `expected_pairs` array of **exactly 5** objects (`{ outflow_id, inflow_id, is_credit_card_payment, score }`) in anchor `(date, id)` order: `s1-out→s1-in`/false/**1.0285714285714285**, `s2-out→s2-in`/false/**0.8200000000000001**, `s7-out→s7-in-a`/false/**1.05**, `s8-out→s8-in-a`/false/**1.2**, `s9-out→s9-in`/**true**/**1.0333333333333334**. Write it **verbatim** (2-space indent, one object per line — matching the dedup/coverage fixtures); **do NOT hand-edit `score`** (it is the locked, bit-identical, round-trip-stable ground truth). The 20 rows encode all 9 scenarios (S1 matched pair, S2 within-tolerance, S3 amount-drift → none, S4 date-drift → none, S5 same-direction → none, S6 same-account → none, S7 narration tiebreak, S8 id tiebreak, S9 credit-card payment), with per-scenario-isolated amounts (≥ ₹1000 apart) so greedy claiming never crosses scenarios. **100% synthetic** (fabricated ids/accounts/dates/amounts/narrations — no real data; FR-022). Ref: `contracts/golden-fixture.md` §"Exact bytes", `contracts/transfer.md` §Golden behaviour.
- [ ] T004 [US8] Extend the parity harness `core/crates/kaname-core/tests/parity.rs` → **RED** with a **separate, transfer-only** loader + one test, appended after the coverage loader/test (`parity.rs:560–627`); the statement `Fixture`/`Expected`/`CASES`, the dedup `DedupFixture`/`cross_source_dedup_matches_expected` (`parity.rs:501–557`), the coverage `CoverageFixture`/`coverage_map_matches_expected` (`parity.rs:560–627`), and every existing test are **untouched**. Add `#[derive(Deserialize)]` structs `TransferFixture { rows: Vec<TransferInputRow>, expected_pairs: Vec<ExpectedPair> }`, `TransferInputRow { id: String, account_id: String, is_credit_card: bool, date: String, amount: String, direction: Direction, description: String }`, `ExpectedPair { outflow_id: String, inflow_id: String, is_credit_card_payment: bool, score: f64 }`; and `#[test] fn transfer_detection_matches_expected()` that reads `{CARGO_MANIFEST_DIR}/../../../fixtures/transfer/basic.json`, deserializes, builds `Vec<TransferInput>` (parse `date` via `NaiveDate::parse_from_str(_, "%Y-%m-%d")`, `amount` via `Decimal::from_str`, `direction` via its serde derive), calls `detect_transfers(rows)` (the **FFI-exported** wrapper — owned `Vec`), and `assert_eq!` against the `expected_pairs` mapped into `Vec<TransferPair>` — the `score` field compared with **exact `f64` `==`** (copy the loader from `data-model.md` §Parity fixture types / `contracts/golden-fixture.md` §Parity harness). Extend the `use kaname_core::{…}` import list (`parity.rs:12–20`) with `detect_transfers`, `TransferInput`, `TransferPair` (`Direction` at `parity.rs:18`, `NaiveDate` at `parity.rs:11`, `Decimal` at `parity.rs:21`, `FromStr` at `parity.rs:9`, `serde::Deserialize` at `parity.rs:22` already imported). ⚠️ **Verify RED**: `make core-test` fails to **compile** (the fn/types don't exist / aren't re-exported yet). Depends on T003. Ref: `contracts/golden-fixture.md` §Parity harness, `data-model.md` §Parity fixture types.
- [ ] T005 [P] [US7] Author the **RED** Swift bridge test `ios/Tests/TransferDetectionTests.swift` — "core ↔ Swift transfer detection" (`import Foundation` / `import KanameCore` / `import Testing`), mirroring `ios/Tests/CrossSourceDedupTests.swift` + `ios/Tests/CoverageTests.swift`. Build a small `[TransferInput]` — a **self-transfer** pair (a `.debit` outflow on `acct-a` + a `.credit` inflow on `acct-b`, same date/amount, both `isCreditCard: false`) and a **credit-card-payment** pair (a `.debit` outflow on a bank account + a `.credit` inflow on a card account, one leg `isCreditCard: true`) — with `amount` via `Decimal(string:locale:)` (`Locale(identifier: "en_US_POSIX")`), `date` as an ISO-8601 `String`, `direction` `.debit`/`.credit`. Call `let pairs = detectTransfers(rows: rows)`. `@Test`: assert the self-transfer pair links the two ids with `isCreditCardPayment == false`; the card pair has `isCreditCardPayment == true`; each exposes a `score` (a `Double`). Fields surface as `outflowId`/`inflowId`/`isCreditCardPayment`/`score`; input as `isCreditCard`. ⚠️ **swift-format `[Spacing]`**: comments on their own line above the code, never trailing. ⚠️ **Verify RED**: won't build until Phase 4 regenerates the xcframework. Ref: `contracts/engine-ffi.md` §Contract tests (Swift), `data-model.md` §Swift surface, `quickstart.md` §4.

**Checkpoint**: Fixture written (20 rows, 5 pairs); Rust parity harness RED (won't compile); Swift bridge test RED. Test-first satisfied — engine code may now begin.

---

## Phase 3: User Stories 1–6 & 8 — the engine (Priority: P1–P6, P8) 🎯 MVP

**Goal**: Add the `transfer.rs` module — the `TransferInput`/`TransferPair` records, `DATE_TOLERANCE_DAYS`, the pure
`narration_similarity` + `score` helpers, the `detect_transfers` matcher, and unit tests — then wire the FFI + crate-root
re-exports, greening the Rust parity + `transfer.rs` unit tests. This one engine phase lands US1 (pair), US2 (guards),
US3 (tiebreaks), US4 (card flag), US5 (score), US6 (greedy/order), and US8 (golden parity) on the Rust side (Swift
bridge greened in Phase 4). `transfer.rs` is one file, so T006–T010 are **sequential** (same file, not `[P]`).

**Independent Test**: `detect_transfers(&rows)` over the golden pool returns the 5 pairs (`s1-out→s1-in`,
`s2-out→s2-in`, `s7-out→s7-in-a`, `s8-out→s8-in-a`, `s9-out→s9-in`) with the exact ids, `is_credit_card_payment`
flags, and `score`s, in anchor `(date, id)` order — and the four guards (S3–S6) produce none — with no
network/clock/locale/DB in the path.

- [ ] T006 [US1] [US4] [US5] Create `core/crates/kaname-core/src/transfer.rs` (NEW file) with the module `//!` doc (pure port of the web `transfer_detector.py` pairing subset over one already-parsed row pool; no clock/DB; money exact `Decimal`, only `score` is `f64`) and the types + const: `use std::collections::HashSet; use chrono::NaiveDate; use rust_decimal::Decimal; use rust_decimal::prelude::ToPrimitive; use crate::model::Direction;` — `pub struct TransferInput { pub id: String, pub account_id: String, pub is_credit_card: bool, pub date: NaiveDate, pub amount: Decimal, pub direction: Direction, pub description: String }` and `pub struct TransferPair { pub outflow_id: String, pub inflow_id: String, pub is_credit_card_payment: bool, pub score: f64 }` — each `#[derive(Debug, Clone, PartialEq, uniffi::Record)]` (mirrors `CrossSourceMatch`/`StatementCoverage`/`MonthCoverage`; **no serde** — the parity harness builds them from typed rows); `pub const DATE_TOLERANCE_DAYS: i64 = 1;`. **Also add `pub mod transfer;` to `core/crates/kaname-core/src/lib.rs`** (beside `pub mod dedup;`/`pub mod coverage;`, `lib.rs:22–26`) so the new module compiles. ⚠️ Money stays `Decimal`; only `score` is `f64`. Ref: `data-model.md` §New types, `contracts/engine-ffi.md` §Types.
- [ ] T007 [US3] [US5] Add `fn narration_similarity(a: &str, b: &str) -> f64` (**private**) to `core/crates/kaname-core/src/transfer.rs`, ported **1:1** from the web `_narration_similarity` (research D4): token-level **Jaccard** on the **raw lowercased, whitespace-split** descriptions — lowercase each into an owned `String`, build `HashSet<&str>` from `split_whitespace()`, return `0.0` if either set is empty else `(intersection count) as f64 / (union count) as f64`. **DISTINCT** from `dedup::normalize_narration` + Jaro-Winkler — no prefix/RRN/refnum stripping, **set**-Jaccard not character Jaro-Winkler; **must not** call `normalize_narration` or reuse `dedup`'s Jaro helpers. Add `#[cfg(test)]` unit tests: a known overlap (e.g. `"neft to hdfc salary account"` vs `"neft from icici"` → `1.0/7.0`; `"neft to hdfc bank xx1234"` vs `"neft from icici bank xx5678"` → `0.25`), identical strings → `1.0`, disjoint → `0.0`, and **empty / whitespace-only** either side → `0.0` (no panic). Verify with `cargo test -p kaname-core transfer::`. Ref: `data-model.md` §narration_similarity, `contracts/transfer.md` §narration_similarity, research D4, FR-008, spec Edge Cases.
- [ ] T008 [US5] Add `fn score(date_diff: i64, amount_diff: Decimal, sim: f64) -> f64` (**private**) to `core/crates/kaname-core/src/transfer.rs`, ported **1:1** from the web `_score` (research D5): `(((1.0 - (0.2 * date_diff as f64)) - (0.2 * amount_diff_f64)) + (0.2 * sim)).max(0.0)` where `amount_diff_f64 = amount_diff.to_f64().unwrap_or(0.0)`. **Preserve the exact Python left-to-right op order** (parenthesised as shown) → bit-identical f64 across x86_64/arm64; **floored at 0.0, NOT capped at 1.0**. Add `#[cfg(test)]` unit tests: same-day/same-amount + narration overlap `s` → equals `1.0 + 0.2*s` (uncapped, `> 1.0` when `s > 0`, e.g. `score(0, dec!(0), 1.0/7.0) == 1.0285714285714285`); a large date/amount drift that would go negative → floored at `0.0`; `score(1, Decimal::from_str("0.50").unwrap(), 0.6) == 0.8200000000000001` (the S2 value). ⚠️ Do **not** add `.min(1.0)`; do **not** reorder the additions. Verify with `cargo test -p kaname-core transfer::`. Ref: `data-model.md` §score, `contracts/transfer.md` §score, research D5, FR-010, SC-006.
- [ ] T009 [US1] [US2] [US3] [US4] [US6] Add `pub fn detect_transfers(rows: &[TransferInput]) -> Vec<TransferPair>` to `core/crates/kaname-core/src/transfer.rs`, implementing the matcher (research D6, exact web order): collect the `Direction::Debit` anchor indices and **sort ascending by `(date, id)`** (`rows[i].date.cmp(&rows[j].date).then_with(|| rows[i].id.cmp(&rows[j].id))`); `let mut consumed = vec![false; rows.len()];`; for each anchor `a` (skip if `consumed[a]`) build the **candidate index set** (every `c` with `!consumed[c]` ∧ `rows[c].account_id != rows[a].account_id` ∧ `rows[c].direction == Direction::Credit` ∧ `(rows[a].date - rows[c].date).num_days().abs() <= DATE_TOLERANCE_DAYS` ∧ `(rows[a].amount - rows[c].amount).abs() <= Decimal::ONE`); if empty `continue`; pick `best` via `min_by` on the comparator `di.cmp(&dj).then_with(|| ai.cmp(&aj)).then_with(|| sj.partial_cmp(&si).unwrap()).then_with(|| rows[i].id.cmp(&rows[j].id))` (date_diff ↑, amount_diff ↑ (`Decimal` Ord), similarity ↓, id ↑); mark `consumed[a] = true; consumed[best] = true;` and push `TransferPair { outflow_id: rows[a].id.clone(), inflow_id: rows[best].id.clone(), is_credit_card_payment: rows[a].is_credit_card || rows[best].is_credit_card, score: score(date_diff, amount_diff, sim) }` (for the chosen best). Borrows `&` (read-only), pure/total (never panics — candidates non-empty; similarity finite); output ordered by anchor `(date, id)` (push order). ⚠️ Use `Decimal::ONE` (not `dec!`) for the ±₹1 tolerance; the core takes **no `today`** and reads no clock. Ref: `contracts/transfer.md` §detect_transfers, `data-model.md` §detect_transfers, research D6/D7/D8.
- [ ] T010 [US1] [US2] [US3] [US4] [US5] [US6] Extend `#[cfg(test)] mod tests` in `core/crates/kaname-core/src/transfer.rs` for `detect_transfers` (build small pools with `NaiveDate::from_ymd_opt` + `dec!`; `dec!` is test-only): **matched pair** (S1, same day/amount, non-card) and **within-tolerance** (S2, 1 day + ₹0.50) → exactly one pair each; **inclusive boundary** — exactly 1 day / exactly ₹1.00 pair, 2 days / ₹1.01 do not (FR-004, SC-002); **the four guards** (S3 amount drift > ₹1, S4 date drift > 1 day, S5 same-direction, S6 same-account) → **zero** pairs each (FR-006, SC-003); **narration tiebreak** (S7: closer-narration inflow, higher Jaccard, wins) and **id tiebreak** (S8: identical date/amount/narration → lowest id) (FR-007, SC-004); **card flag** (S9: either-leg-card → `is_credit_card_payment == true`; both non-card → `false`) (FR-009, SC-005); **score** (same-day/same-amount → `1 + 0.2·sim` uncapped; large drift → floored `0.0`) (FR-010, SC-006); **greedy single-claim** (two outflows both eligible for one inflow → the earlier anchor by `(date, id)` claims it, the later is unpaired, the inflow is in exactly one pair) (FR-005, SC-007); **empty / no-outflow input** → 0 pairs, no panic; **determinism** — re-run (and a shuffled input order) yields identical output (SC-009); **output order** by anchor `(date, id)` (SC-008). Comparison by `TransferPair` value-equality; `score` by **exact `f64` `==`**. Verify with `cargo test -p kaname-core transfer::`. Ref: `contracts/transfer.md` §Unit tests, `data-model.md` §Invariants, spec Edge Cases, SC-001..SC-009.
- [ ] T011 [US7] Wire the FFI + crate-root re-exports. In `core/crates/kaname-core/src/ffi.rs` add (mirroring the `cross_source_duplicates`/`compute_coverage` wrappers, `ffi.rs:63–69`/`75–82`): `use crate::transfer::{TransferInput, TransferPair};` (**TYPES only — not the pure fn**, near `ffi.rs:9–11`), then `#[uniffi::export] pub fn detect_transfers(rows: Vec<TransferInput>) -> Vec<TransferPair> { crate::transfer::detect_transfers(&rows) }` (owned `Vec` per UniFFI; call the pure fn **fully-qualified**; total, never panics; the `Decimal`/`NaiveDate` custom types already registered at `ffi.rs:32`/`39` carry `amount`/`date`). In `core/crates/kaname-core/src/lib.rs`: add `detect_transfers` to the `pub use ffi::{…}` block (`lib.rs:34–41`) and add `pub use transfer::{TransferInput, TransferPair};`. ⚠️ Do **NOT** `pub use transfer::detect_transfers` — it name-clashes with the FFI wrapper (research D9). Depends on T009. Ref: `contracts/engine-ffi.md` §Exported function, `data-model.md` §FFI wrapper / §Crate re-exports.
- [ ] T012 [US8] **Green the engine side**: `make core-fmt`, then `make core-test` — the parity test (T004: `transfer_detection_matches_expected` → the 5 golden `expected_pairs`, `score` exact-`==`) now **PASSES**, the `transfer.rs` unit tests (T007/T008/T010) pass, and **all prior parity + statement + dedup + coverage tests stay green** — then `make core-lint` (clippy `-D warnings` + fmt check). Verify **RED→GREEN** for the Rust side. Ref: `quickstart.md` §1.

**Checkpoint**: The engine pairs opposite-direction cross-account rows within the ±1-day/±₹1.00 envelope, honors the four guards / the deterministic tiebreaks / the card flag / the uncapped-but-floored score / greedy single-claim / anchor ordering, and reproduces the golden vector exactly; Rust parity + `transfer.rs` unit tests are green. US1–US6 + US8 functional on the Rust side (Swift bridge greened in Phase 4).

---

## Phase 4: UniFFI bridge — regenerate the xcframework + green the Swift test (US7)

**Goal**: Surface `detect_transfers` + the two transfer records to Swift and green the bridge test. `Decimal` /
`NaiveDate` / `Direction` are reused unchanged → **no `uniffi.toml` change**.

- [ ] T013 [US7] Run `make core-xcframework` to rebuild `ios/Frameworks/KanameCoreFFI.xcframework` + the generated `ios/Generated/kaname_core.swift` (git-ignored artifacts), now exposing `detectTransfers(rows:)`, the `TransferInput` record (`id`/`accountId`/`isCreditCard`/`date`/`amount`/`direction`/`description`), and the `TransferPair` record (`outflowId`/`inflowId`/`isCreditCardPayment`/`score`). `amount` crosses as a base-10 `String` → Swift `Decimal`, `date` as an ISO-8601 `String`, `direction` via the existing `Direction` enum, `score` as a native `Double`. ⚠️ **MUST run before `tuist generate`**. Ref: `contracts/engine-ffi.md` §Stability, `quickstart.md` §3.
- [ ] T014 [US7] Run `make ios-test` (`ios-gen` → `core-xcframework` → `tuist generate` → `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test`) to **green** `ios/Tests/TransferDetectionTests.swift` (T005): the self-transfer pair links the two ids with `isCreditCardPayment == false`, the card pair has `isCreditCardPayment == true`, and a `score` (`Double`) is readable. ⚠️ **Local: create the "iPhone 16" simulator first.** Verify **RED→GREEN**. Ref: `quickstart.md` §4.

**Checkpoint**: US1 + US4 + US7 delivered end-to-end (Rust engine + Swift bridge). A person's own money movements between their own accounts are recognised as single internal transfers (Self Transfer vs Credit Card Bill Payment), on-device, over the bridge.

---

## Phase 5: Verification of the remaining stories (US2, US3, US4, US5, US6, US9) & polish

**Purpose**: Confirm the stories whose behavior already landed in Phase 3 are independently verified, and run the full
gate. Most of these are assertions already authored in T007/T008/T010/T004 — this phase makes their coverage explicit
and closes the constitution gates.

- [ ] T015 [P] [US2] Confirm **never pair non-transfers** (FR-006, SC-003): the `transfer.rs` unit tests (T010) + the fixture guards (S3 amount-drift ₹500, S4 date-drift 4 days, S5 same-direction, S6 same-account — all producing **no** pair, T003) assert zero pairs for each near-miss, and the **inclusive boundary** (exactly 1 day / exactly ₹1.00 pair; 2 days / ₹1.01 do not) holds. Add (if not already in T010) an explicit assertion for each of the four guards in isolation. Ref: spec US2, `contracts/transfer.md` §Candidate eligibility.
- [ ] T016 [P] [US3] Confirm **deterministic tiebreaks** (FR-007, SC-004): the T010 unit tests + the fixture's S7 (`s7-out` pairs `s7-in-a`, Jaccard `0.25`, over `s7-in-b`, Jaccard `0.0`) and S8 (`s8-out` pairs `s8-in-a`, the lowest id, among three identical `sim 1.0` candidates) pin the narration-then-id resolution of the `(date_diff, amount_diff, -narration_similarity, id)` tuple; note the unique-`id` final tiebreak makes the comparator a strict total order (matches Python `min`). Ref: spec US3, `contracts/transfer.md` §Selection tuple, research D7.
- [ ] T017 [P] [US4] Confirm the **credit-card-payment flag** (FR-009, SC-005): the T010 unit test + the fixture's S9 (`s9-in` on a card account, `is_credit_card=true` → pair `is_credit_card_payment == true`) vs the non-card pairs (S1/S2/S7/S8 → `false`, T003) pin the either-leg-card OR rule; the Swift test (T005/T014) also reads the flag over the bridge. Ref: spec US4, `contracts/transfer.md` §Emitted pair.
- [ ] T018 [P] [US5] Confirm the **confidence score** (FR-010, SC-006): the `score` unit tests (T008: `1 + 0.2·sim` uncapped, floor at `0.0`) + the parity test (T004: all 5 `expected_pairs` `score`s compared with **exact `f64` `==`**, including the four `> 1.0` values `1.0285714285714285`/`1.05`/`1.2`/`1.0333333333333334` and S2's `< 1` `0.8200000000000001`) pin the web `_score` bit-for-bit; confirm no `.min(1.0)` cap and the exact left-to-right op order. Ref: spec US5, `contracts/transfer.md` §score, research D5.
- [ ] T019 [P] [US6] Confirm **greedy single-claim + anchor ordering** (FR-002/003/005, SC-007/008): the T010 unit tests (two outflows contest one inflow → earlier anchor by `(date, id)` claims it, the later is unpaired, the inflow appears in exactly one pair; output ordered by anchor `(date, id)`) + the parity test (T004: the 5 pairs emitted in `s1, s2, s7, s8, s9` order) pin the whole-list behaviour; confirm the shared `consumed` vector keeps each row in ≤ 1 pair. Ref: spec US6, `contracts/transfer.md` §Invariants.
- [ ] T020 [US9] Run `make core-privacy-audit` — assert **no networking crate** enters the shipped graph (the transfer path is pure/on-device; FR-017/019, SC-012). This slice adds **no dependency**, so the shipped `cargo tree` is byte-identical; the inherited gate must stay green and now covers `detect_transfers` (zero network, zero clock, zero DB). Ref: spec US9, `quickstart.md` §2.
- [ ] T021 Run the **full Local Verification Gate** end-to-end: `make core-lint core-test core-privacy-audit lint ios-test` — all green (fmt/clippy, Rust unit+parity, privacy audit, SwiftLint + swift-format lint, `tuist generate` after the xcframework, simulator build + Swift Testing). This is the mandatory pre-PR gate. Ref: `quickstart.md` §5, constitution §iOS Local Verification Gate, FR-025, SC-014.

**Checkpoint**: All nine user stories verified; every gate green. Ready for the maintainer to commit & open the PR.

---

## Phase 6: Delivery (maintainer commits)

- [ ] T022 [Maintainer] **Hand off — the maintainer (not the agent) commits.** Do NOT auto-commit. Present the completed, gate-green diff for the maintainer to commit on `015-transfer-detection`, suggested as **two** logical commits: (1) `feat(core): …` — the matcher + fixture + parity (`core/crates/kaname-core/src/transfer.rs`, `src/ffi.rs`, `src/lib.rs`, `fixtures/transfer/basic.json`, `core/crates/kaname-core/tests/parity.rs`); (2) `test(ios): …` — `ios/Tests/TransferDetectionTests.swift`. Generated artifacts (`ios/Generated/`, `ios/Frameworks/*.xcframework`) are git-ignored and MUST NOT be committed. The maintainer opens/merges the PR and watches CI (Rust on `ubuntu-latest`, iOS on `macos-15`) to green.

---

## Dependencies & parallelism

- **Phase 1 (T001–T002)**: both `[P]` (read-only confirmations, independent) — no code.
- **Phase 2 (T003–T005)**: T003 (fixture) and T005 (Swift test) are `[P]`-parallel (independent files); T004 (parity)
  reads the fixture → author T003 first, then T004. All three must be RED before Phase 3.
- **Phase 3 (T006–T012)**: T006 → T007 → T008 → T009 → T010 are the **same file** (`transfer.rs`) so **sequential**
  (not `[P]`); T009 uses T007 (`narration_similarity`) + T008 (`score`); T011 (FFI/re-exports, touches `ffi.rs`+`lib.rs`)
  depends on T009; T012 (green) depends on T004 + T006–T011.
- **Phase 4**: T013 → T014, depend on Phase 3 green (T013 rebuilds the xcframework; T014 needs it before `tuist generate`).
- **Phase 5**: T015–T019 `[P]` (verification, mostly already-authored assertions) after Phase 3/4; T020 after
  Phase 3; T021 (full gate) after all.
- **Phase 6 (T022)**: maintainer, after T021 green.

## Story → task coverage

| Story | Tasks |
|---|---|
| US1 pair a self-transfer (P1) | T003, T004, T005, T006, T009, T010, T012, T013, T014 |
| US2 never pair non-transfers / guards (P2) | T003, T009, T010, T012, T015 |
| US3 deterministic tiebreaks — narration then id (P3) | T003, T007, T009, T010, T012, T016 |
| US4 credit-card-payment flag (P4) | T003, T005, T006, T009, T010, T012, T014, T017 |
| US5 confidence score (P5) | T003, T006, T008, T010, T012, T018 |
| US6 greedy single-claim + anchor ordering (P6) | T003, T009, T010, T012, T019 |
| US7 bridge / no-new-infra (P7) | T001, T005, T011, T013, T014 |
| US8 golden-fixture parity (P8) | T003, T004, T012 |
| US9 privacy-egress (P9) | T020, T021 |

## Implementation strategy

**MVP = Phase 1 → Phase 2 → Phase 3 → Phase 4** delivers the whole transfer signal end-to-end: US1 (pair) + US2
(guards) + US3 (tiebreaks) + US4 (card flag) + US5 (score) + US6 (greedy/order) + US8 (golden parity) on the Rust
side, then US7 (bridge) to Swift — the recognition that money moved between the user's own accounts, on-device.
US9 (privacy) is the inherited gate confirmed at T020/T021. Build strictly **test-first** (Phase 2 RED before Phase 3
GREEN): author the golden fixture verbatim, then the failing parity + Swift tests, then implement the pure
`transfer.rs` (a **new top-level** module, sibling to `dedup.rs`/`coverage.rs`) with the name-clash-safe FFI wrapper,
adding **zero** new dependencies. The core **never reads the wall-clock** — the row pool is the only input; money
stays exact `Decimal` and only the confidence `score` is `f64`.

## Notes

- `[P]` tasks = different files, no dependencies on an unfinished task.
- `[Story]` labels map each task to the spec's nine user stories for traceability.
- Every behavior is pinned test-first to the web `transfer_detector.py` pure subset; verify RED (T003–T005) before
  GREEN (T006+).
- Money is exact `Decimal` (with `Decimal::ONE` for the ±₹1 tolerance); the **only** `f64` is the confidence
  `score` — it is not money (Constitution II).
- **Do NOT commit** — the maintainer commits (T022). Stop at any checkpoint to validate a story independently.
- Avoid: reading the wall-clock, re-exporting the pure `detect_transfers` (name clash), conflating
  `narration_similarity` with `dedup`'s `normalize_narration` + Jaro-Winkler, capping `score` at 1.0 or reordering
  its additions, trailing inline Swift comments, and any new dependency / `uniffi.toml` / `model.rs` / reader /
  `Cargo.toml` change.
