---
description: "Task list — Cross-Source De-Duplication (dedup.rs: the pure, in-memory L3 CANONICAL + L4 FUZZY matcher over two Transaction lists; hand-rolled Jaro-Winkler + normalize_narration; zero new dependency)"
---

# Tasks: Recognise the Same Purchase Across Two Sources On-Device — the Pure CANONICAL + FUZZY Cross-Source De-Duplicator

**Input**: Design documents from `/specs/013-cross-source-dedup/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/{cross-source-dedup.md, engine-ffi.md, golden-fixture.md}`, `quickstart.md`

**Tests**: REQUIRED and **TEST-FIRST** (Constitution Principle V). The new golden fixture, the failing Rust
parity test, and the failing Swift bridge test are authored **RED, before** the `dedup.rs` matcher +
helpers that green them. The `expected_matches` are the **locked ground truth captured from a live
web-engine run** (`normaliser.py` + `deduplicator.py` L3/L4 + `rapidfuzz` Jaro-Winkler):
`expected_matches = [{0,0,Canonical}, {1,1,Fuzzy}, {4,4,Canonical}]` for `fixtures/dedup/cross_source/basic.json`
(five scenarios, three survivors). The `normalize_narration` reference outputs and the Jaro-Winkler
reference values below are likewise pinned ground truth.

**Port source of truth** (faithful, byte-for-byte with the golden vectors):
`/Users/ssk/Projects/finance-tracker-phase/backend/app/services/ingestion/normaliser.py` (`normalise_narration`)
and `deduplicator.py` (the **L3 CANONICAL** + **L4 FUZZY** rungs only), with the similarity ported from
`rapidfuzz`'s Jaro-Winkler; pinned by `backend/tests/unit/ingestion/test_deduplicator.py`. This slice is the
on-device analogue of the web ladder's **two database-free rungs** and **nothing else** (L1/L2/L5 +
SUPERSEDE need a DB / merchant catalog / persistence → Out of Scope, FR-012). It slots beside the shipped
`reconcile.rs` exactly as `reconcile` sat beside `balance_chain`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: `US1`=canonical · `US2`=fuzzy · `US3`=multiplicity · `US4`=threshold-protection ·
  `US5`=read-only identify · `US6`=deterministic ladder · `US7`=golden parity · `US8`=bridge ·
  `US9`=privacy-egress. Setup/Polish carry no story label.
- Exact file paths are included in every task.

## ♻️ REUSE — do NOT re-create

The matcher **extends the existing `dedup` module** and plugs into the shipped foundations unchanged,
mirroring `reconcile.rs`. Do **not** rebuild any of these:

- `src/model.rs` — the shared `Transaction` (`date: NaiveDate`, `description: String`, `amount: Decimal`,
  `direction: Direction`) and `Direction` enum are **reused verbatim** (`model.rs:12/19`, both already
  derive `serde` + `uniffi`). **No field change.** The matcher only **reads** these rows.
- `src/dedup.rs` — the existing `normalize_description` + `dedup_fingerprint` (the coarser L2 EXACT-hash
  analogue, `dedup.rs:12/22`) are **kept unchanged** and **not** wired into the L3/L4 matcher. The new
  `normalize_narration` is a **separate, distinct** function — do **not** merge the two (research D2).
- `src/ffi.rs` — the `Decimal`/`NaiveDate` custom types + `Transaction` import (`ffi.rs:9`) are reused
  (**no `uniffi.toml` change**); the new export mirrors `reconcile_statement` (`ffi.rs:177–180`).
- `src/lib.rs` — the crate-root re-export block (`lib.rs:27–38`); add the new FFI fn + dedup types beside
  the existing `dedup::{…}` / `reconcile::{…}` re-exports.
- `tests/parity.rs` — the golden-fixture harness; add a **separate, dedup-only** loader + one test. The
  statement `Fixture`/`Expected`/`CASES` (`parity.rs:22–82`) and **every** current test are **untouched**.
- The **privacy-egress gate** (`make core-privacy-audit`) + CI — inherited unchanged (**no new
  dependency** → byte-identical shipped `cargo tree`; the Jaro-Winkler is hand-rolled).

**The only NEW code**: `dedup.rs` gains `normalize_narration` + 4 `LazyLock<Regex>` statics, a private
hand-rolled `jaro` + `jaro_winkler` + `JARO_WINKLER_THRESHOLD`, the `DedupLayer` enum + `CrossSourceMatch`
record, the pure `cross_source_duplicates` matcher, and unit tests; one `#[uniffi::export]` wrapper in
`ffi.rs` + `lib.rs` re-exports; one new fixture (`fixtures/dedup/cross_source/basic.json`, a **new shape**);
a dedup loader + one parity test; and one Swift bridge test. **No new dependency** (runtime *or* dev); **no
`uniffi.toml`/`model.rs`/reader change**.

## 🎯 The two-layer ladder — the whole decision surface (contracts/cross-source-dedup.md)

`cross_source_duplicates(existing: &[Transaction], incoming: &[Transaction]) -> Vec<CrossSourceMatch>`.
Precompute `normalize_narration` for every row once (two `Vec<String>`). `consumed: Vec<bool>` over
`existing` enforces multiplicity. For each `incoming[i]` **in order**:

1. **Canonical pass** (tried **first**) — the **first unconsumed** `existing[e]` (existing order) with
   **all** of: `date ==` (identical, 0-day) · `amount.normalize() ==` (exact `Decimal` value, `250.00` ==
   `250.0`) · `direction ==` · **60-char prefix** of the two normalised narrations equal
   (`s.chars().take(60).collect::<String>()`). Hit → push `{i, e, Canonical}`, `consumed[e]=true`, next `i`.
2. **Fuzzy pass** (only if canonical found nothing) — the first unconsumed `existing[e]` with: `amount ==`
   (`normalize`) · `direction ==` · `(d_e − d_i).num_days().abs() <= 1` (±1 day inclusive) ·
   `jaro_winkler(&norm_e, &norm_i) >= JARO_WINKLER_THRESHOLD` (0.92, **inclusive**). Hit → push
   `{i, e, Fuzzy}`, `consumed[e]=true`, next `i`.
3. **No hit** → `incoming[i]` is a **survivor** (emit nothing; absent from the result).

**Invariants**: canonical precedence · first-unconsumed-wins tie-break · each existing consumed at most once
(surplus repeats survive) · read-only (borrows `&`, never mutates/drops/reorders/merges/persists) ·
pure/total/deterministic (no I/O, network, clock, locale, global state; empty either side ⇒ empty; never
panics) · money is exact `Decimal`, a Jaro-Winkler similarity is `f64` (a [0,1] score), **never** money.

## ⚠️ Local gotchas (apply throughout)

- **The Jaro-Winkler unit tests assert the reference values by rounding to 4 dp, NOT by `==`** (research
  D5). `0.9232` (`fine dining`/`fine dine`) and `0.9846` (`swiggy order`/`swiggy orders`) are **4-dp
  roundings of repeating decimals** (raw `0.92323232…`, `0.98461538…`) → `== 0.9232` / `== 0.9846` **fail**.
  Use `fn round4(v: f64) -> f64 { (v * 10_000.0).round() / 10_000.0 }`. `0.95`/`0.92`/`0.9125` happen to
  land on their f64 literal, but assert **all six via `round4`** for uniformity. The `>= 0.92` **decision**
  uses the **raw** f64 and is exact/robust at the inclusive boundary (`amazon`/`amazon pay`
  `0.92000000000000004 >= 0.92` → match; `acme corp`/`acme corporation` `0.91249999999999998 < 0.92` → no).
- **`normalize_narration` strips the leading prefix in a LOOP until stable**, not a single pass — stacked
  prefixes collapse (`"UPI/POS Coffee Day" → "coffee day"`). Exact web order: `trim` → loop{strip one
  `LEADING_PREFIX` + `trim`} → remove `RRN\d+` → collapse whitespace → strip **trailing** 10–16-digit
  refnum → `to_lowercase` → `trim` (research D2).
- **Name clash**: only the **FFI** `cross_source_duplicates` is re-exported at the crate root
  (`pub use ffi::cross_source_duplicates;`); the pure `dedup::cross_source_duplicates` is **NOT** re-exported
  (research D9). `tests/parity.rs` and Swift both use the FFI-exported one via `kaname_core::cross_source_duplicates`.
- **`make core-xcframework` MUST run before `tuist generate`** (`ios-gen: core-xcframework`) — the generated
  Swift + `KanameCoreFFI.xcframework` are rebuilt artifacts; run it after the FFI surface changes (new
  `crossSourceDuplicates` + `DedupLayer`/`CrossSourceMatch` types).
- **The iOS CI job stays pinned to `macos-15`**; the local `xcodebuild` destination is the **"iPhone 16"**
  simulator (`OS=latest`).
- **swift-format `[Spacing]` rejects trailing inline comments** — in `CrossSourceDedupTests.swift` any
  comment goes on its **own line above** the code, never trailing after it.
- **rustfmt reformats edits** — after each `edit`, run `make core-fmt` then re-view before the next edit
  (arrays/asserts/imports get re-wrapped).
- Money is **`Decimal`, never `f64`**; amount equality is `a.amount.normalize() == b.amount.normalize()`
  (value equality, scale-insensitive), never string/`f64` compare. Direction is **`Direction` equality**,
  never re-derived from the amount's sign. A Jaro-Winkler *similarity* is legitimately `f64` (research D4).
  **No new dependency.**

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm invariants so every later task lands cleanly and the gates stay green. No behavior yet.

- [ ] T001 [P] Confirm the **no-new-dependency** invariant: `core/crates/kaname-core/Cargo.toml` stays **UNCHANGED** (runtime `regex`/`rust_decimal`/`chrono`/`serde`/`uniffi` + dev-only `serde_json` already present) — this slice adds **zero** deps (the Jaro-Winkler is hand-rolled, not a crate; FR-010/023, SC-016/017). Note that `fixtures/dedup/cross_source/` is a **NEW** directory (a new fixture *shape*), created in T003. Ref: plan §Summary/§Complexity Tracking, `contracts/golden-fixture.md`.
- [ ] T002 [P] Verify local prerequisites & gotchas (no code): `cargo` on PATH (`export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"`); an **"iPhone 16" simulator** exists in Xcode; recall `make core-xcframework` precedes `tuist generate`, the iOS CI job is pinned to **`macos-15`**, **swift-format `[Spacing]` forbids trailing inline comments**, and the **Jaro-Winkler reference values are asserted by 4-dp rounding, not `==`** (research D5). Ref: `quickstart.md` §Prerequisites/§Troubleshooting.

**Checkpoint**: No manifest/`uniffi.toml`/`model.rs` change needed; toolchain + simulator + CI ordering + the 4-dp assertion nuance understood.

---

## Phase 2: Test-First Foundation (⚠️ Principle V — author RED before ANY dedup engine code)

**Purpose**: Pin the on-device matcher to the proven web engine **before** writing it. These are the parity
(US7), canonical (US1), fuzzy (US2), multiplicity (US3), and bridge (US8) tests that protect the slice; they
MUST be **RED** at the end of this phase (`cross_source_duplicates` / `CrossSourceMatch` / `DedupLayer` /
`normalize_narration` do not exist yet).

**⚠️ CRITICAL**: No engine code (Phase 3+) until T003–T005 exist and are verified failing (compile-fail is
acceptable RED for the Rust harness; the Swift test won't build until Phase 4).

- [ ] T003 [P] [US1] [US2] [US3] [US7] Create the **new-shape** golden fixture `fixtures/dedup/cross_source/basic.json` — the **exact bytes** from `contracts/golden-fixture.md` §"exact bytes to write": the `_comment` provenance string, an `existing` array (5 rows) + an `incoming` array (6 rows) of `{date, description, amount, direction}` (amounts are **JSON strings** → re-parsed to `Decimal`, never `f64`; `direction` `"Debit"`/`"Credit"`), and `expected_matches` = `[{incoming_index:0, existing_index:0, layer:"Canonical"}, {1,1,"Fuzzy"}, {4,4,"Canonical"}]`. The five scenarios: (0) canonical (same date/amt/dir + shared 60-char prefix `swiggy bangalore`); (1) fuzzy (+1-day skew, JW 0.95 ≥ 0.92); (2) below-threshold survivor (`acme corporation`/`acme corp` JW 0.9125 < 0.92); (3) direction-guard survivor (`netflix` Credit vs Debit); (4) canonical multiplicity match (`uber`); (5) surplus `uber` repeat → survivor (E4 already consumed). **100% synthetic.** ⚠️ Copy the bytes verbatim — this is the locked parity target. Ref: `contracts/golden-fixture.md`, `contracts/cross-source-dedup.md` §Golden behaviour.
- [ ] T004 [US7] Extend the parity harness `core/crates/kaname-core/tests/parity.rs` → **RED** with a **separate, dedup-only** loader + one test (the statement `Fixture`/`Expected`/`CASES` and every existing test **untouched**). Add `#[derive(Deserialize)]` structs `DedupFixture { existing: Vec<DedupRow>, incoming: Vec<DedupRow>, expected_matches: Vec<ExpectedMatch> }`, `DedupRow { date: String, description: String, amount: String, direction: Direction }`, `ExpectedMatch { incoming_index: u32, existing_index: u32, layer: DedupLayer }`; a `to_txns(&[DedupRow]) -> Vec<Transaction>` helper mapping each row via `Transaction::new(NaiveDate::parse_from_str(&r.date, "%Y-%m-%d").unwrap(), r.description.clone(), Decimal::from_str(&r.amount).unwrap(), r.direction)`; and `#[test] fn cross_source_dedup_matches_expected()` that reads `{CARGO_MANIFEST_DIR}/../../../fixtures/dedup/cross_source/basic.json`, deserializes, calls `cross_source_duplicates(to_txns(&fx.existing), to_txns(&fx.incoming))`, and `assert_eq!` against the mapped `Vec<CrossSourceMatch>` (copy the loader from `contracts/golden-fixture.md` §"Parity harness behaviour"). Extend the `use kaname_core::{…}` import list (`parity.rs:11–18`) with `cross_source_duplicates`, `CrossSourceMatch`, `DedupLayer` (`Transaction`/`Direction`/`Decimal`/`NaiveDate`/`FromStr` already imported). ⚠️ **Verify RED**: `make core-test` fails to **compile** (the fn/types don't exist). Depends on T003. Ref: `contracts/golden-fixture.md`, `data-model.md` §Parity loader.
- [ ] T005 [P] [US1] [US2] [US3] [US8] Author the **RED** Swift bridge test `ios/Tests/CrossSourceDedupTests.swift` — "core ↔ Swift cross-source dedup" (`import Foundation` / `import KanameCore` / `import Testing`), mirroring `ios/Tests/ReconcileTests.swift` + the `Transaction(date:description:amount:direction:)` construction in `ios/Tests/KanameTests.swift:35`. Build `[Transaction]` `existing` + `incoming` (dates as ISO `String`, amounts via `Decimal(string:locale: en_US_POSIX)`, `direction: .debit`/`.credit`); call `let matches = crossSourceDuplicates(existing: existing, incoming: incoming)`. `@Test` **canonical**: a same-date/amount/direction pair whose narrations differ only by whitespace/case → a match with `layer == .canonical` and the right `incomingIndex`/`existingIndex`. `@Test` **fuzzy**: a ≥0.92, ±1-day near-duplicate (e.g. `swiggy bangalore`/`swiggy bangaluru`, 0.95) → `layer == .fuzzy`. `@Test` **multiplicity**: two identical incoming vs **one** existing → **exactly one** match; the surplus incoming index is **absent** (survivor). ⚠️ **swift-format `[Spacing]`**: comments on their own line above the code. ⚠️ **Verify RED**: won't build until Phase 4 regenerates the xcframework. Ref: `contracts/engine-ffi.md` §Contract tests (Swift), `data-model.md` §Swift bridge test.

**Checkpoint**: Fixture written; Rust parity harness RED (won't compile); Swift bridge test RED. Test-first satisfied — engine code may now begin.

---

## Phase 3: User Stories 1–6 — the engine (Priority: P1–P6) 🎯 MVP

**Goal**: Add `normalize_narration`, the hand-rolled Jaro-Winkler, the `DedupLayer`/`CrossSourceMatch` types,
and the `cross_source_duplicates` two-layer matcher — greening the Rust parity + `dedup.rs` unit tests. This
one engine phase lands US1 (canonical), US2 (fuzzy), US3 (multiplicity), US4 (threshold-protection), US5
(read-only identify), and US6 (deterministic ladder) on the Rust side (Swift bridge greened in Phase 4).

**Independent Test**: `cross_source_duplicates(existing, incoming)` over the golden lists returns
`[{0,0,Canonical}, {1,1,Fuzzy}, {4,4,Canonical}]` — with no network/clock/locale in the path.

- [ ] T006 [US1] Add `pub fn normalize_narration(raw: &str) -> String` to `core/crates/kaname-core/src/dedup.rs`, backed by four `std::sync::LazyLock<Regex>` statics ported **1:1** from `normaliser.py`: `LEADING_PREFIX = (?i)^(POS\s|UPI[-/]|NEFT/|IMPS/|ACH/|BIL/|RTGS/|INT\.PD\./|TO TRANSFER-|BY TRANSFER-)`, `RRN = (?i)\bRRN\d+\b`, `TRAILING_REFNUM = \b[0-9]{10,16}\b\s*$`, `WHITESPACE = \s+` (import `regex::Regex` + `std::sync::LazyLock`). **Exact web order**: `trim` → **loop**{ `LEADING_PREFIX.replace(&s, "")` + `trim` } **until stable** → `RRN.replace_all(&s, "")` → `WHITESPACE.replace_all(&s, " ")` → `TRAILING_REFNUM.replace(&s, "")` → `to_lowercase()` → `trim`. Keep it **distinct** from `normalize_description` (do NOT merge). Add `#[cfg(test)]` unit tests asserting the five pinned reference outputs: `"UPI-SWIGGY-RRN1234"→"swiggy-"`, `"POS SWIGGY BANGALORE 12345678901234"→"swiggy bangalore"`, `"NEFT/ACME CORP/REF999"→"acme corp/ref999"`, `"BY TRANSFER-Salary Credit RRN5678"→"salary credit"`, `"SWIGGY  ORDER   9988776655"→"swiggy order"`; plus the stacked-prefix probe `"UPI/POS Coffee Day"→"coffee day"`. Verify with `cargo test -p kaname-core dedup::`. Ref: `data-model.md` §normalize_narration, research D2, `contracts/cross-source-dedup.md`.
- [ ] T007 [US2] [US4] Add the private hand-rolled similarity + threshold to `core/crates/kaname-core/src/dedup.rs`: `const JARO_WINKLER_THRESHOLD: f64 = 0.92;`, `fn jaro(a: &[char], b: &[char]) -> f64` (classic Jaro on `&[char]`; window `max(a.len(), b.len()) / 2 - 1` saturating, transpositions `/2`; `1.0` for two empty, `0.0` if either empty or no matches; else `(m/|a| + m/|b| + (m − t)/m) / 3`), and `fn jaro_winkler(a: &str, b: &str) -> f64` (collect both to `Vec<char>`; `prefix` = common leading chars **capped at 4**; `jaro + prefix as f64 * 0.1 * (1.0 − jaro)` — **UNGATED**, no `jaro > 0.7` boost gate; research D3). A similarity is `f64`, not money (D4). Add `#[cfg(test)]` unit tests asserting **all six** reference pairs via a `round4(v) = (v * 10_000.0).round() / 10_000.0` helper (**not `==`** — D5): `swiggy bangalore`/`swiggy bangaluru` → `0.95`, `amazon`/`amazon pay` → `0.92`, `acme corp`/`acme corporation` → `0.9125`, `fine dining`/`fine dine` → `0.9232`, `swiggy order`/`swiggy orders` → `0.9846`, identical → `1.0`; plus the two **raw-f64** threshold decisions `jaro_winkler("amazon","amazon pay") >= JARO_WINKLER_THRESHOLD` **true** and `jaro_winkler("acme corp","acme corporation") >= JARO_WINKLER_THRESHOLD` **false**. Verify with `cargo test -p kaname-core dedup::`. Ref: `data-model.md` §jaro/jaro_winkler, research D3/D5.
- [ ] T008 [US1] [US2] [US3] [US5] [US6] Add the result types + matcher to `core/crates/kaname-core/src/dedup.rs`: `pub enum DedupLayer { Canonical, Fuzzy }` — `#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]` (the `serde` derives make `"Canonical"`/`"Fuzzy"` deserialise directly in the fixture, mirroring `Direction` in `model.rs:12`; import `serde::{Deserialize, Serialize}`); `pub struct CrossSourceMatch { pub incoming_index: u32, pub existing_index: u32, pub layer: DedupLayer }` — `#[derive(Debug, Clone, PartialEq, uniffi::Record)]` (mirrors `ReconcileResult`); and `pub fn cross_source_duplicates(existing: &[Transaction], incoming: &[Transaction]) -> Vec<CrossSourceMatch>` implementing the two-layer ladder (research D7): precompute `normalize_narration` per row once into two `Vec<String>`, `let mut consumed = vec![false; existing.len()];`, then for each `incoming[i]` in order run the **canonical pass** (first unconsumed `e` with `date ==` **&&** `amount.normalize() ==` **&&** `direction ==` **&&** 60-char prefix `chars().take(60).collect::<String>()` equal) then, only on miss, the **fuzzy pass** (`amount ==` **&&** `direction ==` **&&** `(d_e − d_i).num_days().abs() <= 1` **&&** `jaro_winkler(&norm_e, &norm_i) >= JARO_WINKLER_THRESHOLD`), setting `consumed[e]=true` on a hit and emitting `CrossSourceMatch`; no hit → survivor. Borrows `&` (read-only), pure/total. Update the module `//!` doc to note the new pure L3/L4 matcher (the coarser `normalize_description`/`dedup_fingerprint` stay). Ref: `contracts/cross-source-dedup.md`, `data-model.md` §New function/types, research D6/D7/D8.
- [ ] T009 [US1] [US2] [US3] [US4] [US5] [US6] Extend `#[cfg(test)] mod tests` in `core/crates/kaname-core/src/dedup.rs` for `cross_source_duplicates` (build small `Transaction` lists with `NaiveDate::from_ymd_opt` + `dec!`): **canonical match** (same date/amt/dir, cosmetic narration diff → `{0,0,Canonical}`); **fuzzy at the inclusive 0.92 boundary** (`amazon`/`amazon pay`, ±1 day → `{_,_,Fuzzy}`); **below-threshold non-match** (`acme corp`/`acme corporation` → survives, empty result); **direction guard**, **amount guard**, and **2-day date guard** (each → survives); **multiplicity** (2 identical incoming vs 1 existing → exactly **1** match, the other survives, `existing_index` consumed once); **canonical-before-fuzzy precedence** (an incoming that could match one existing canonically and another only fuzzily → the canonical match is taken); **first-unconsumed-wins** (two existing both canonical-eligible → the earlier index wins); **determinism** (identical output on a second call). Assert money via `Decimal` value-equality; the borrowed inputs' `.len()` unchanged after the call. Verify with `cargo test -p kaname-core dedup::`. Ref: `contracts/cross-source-dedup.md` §Unit tests, `data-model.md` §Unit tests, `test_deduplicator.py`.
- [ ] T010 [US1] [US8] Wire the FFI + crate-root re-exports. In `core/crates/kaname-core/src/ffi.rs` add (mirroring `reconcile_statement`, `ffi.rs:177–180`): `use crate::dedup::{cross_source_duplicates, CrossSourceMatch};` alongside the other imports, then `#[uniffi::export] pub fn cross_source_duplicates(existing: Vec<Transaction>, incoming: Vec<Transaction>) -> Vec<CrossSourceMatch> { crate::dedup::cross_source_duplicates(&existing, &incoming) }` (total, never panics; `Transaction` already imported at `ffi.rs:9`). In `core/crates/kaname-core/src/lib.rs`: add `pub use ffi::cross_source_duplicates;` (the FFI wrapper — Swift entry) and `pub use dedup::{CrossSourceMatch, DedupLayer, normalize_narration};` beside the existing `dedup::{…}` re-export (`lib.rs:27`). ⚠️ Do **NOT** `pub use dedup::cross_source_duplicates` — it name-clashes with the FFI wrapper (research D9). Depends on T008. Ref: `contracts/engine-ffi.md`, `data-model.md` §FFI surface.
- [ ] T011 [US7] **Green the engine side**: `make core-fmt`, then `make core-test` — the parity test (T004: `cross_source_dedup_matches_expected` → `[{0,0,Canonical}, {1,1,Fuzzy}, {4,4,Canonical}]`) now **PASSES**, the `dedup.rs` unit tests (T006/T007/T009) pass, the existing `normalize_description`/`dedup_fingerprint` tests still pass, and **all prior parity + statement tests stay green** — then `make core-lint` (clippy `-D warnings` + fmt check). Verify **RED→GREEN** for the Rust side. Ref: `quickstart.md` §1.

**Checkpoint**: The engine identifies canonical + fuzzy cross-source duplicates, honors multiplicity/precedence/guards, and reproduces the golden vector exactly; Rust parity + `dedup.rs` unit tests are green. US1–US6 functional on the Rust side (Swift bridge greened in Phase 4).

---

## Phase 4: UniFFI bridge — regenerate the xcframework + green the Swift test (US8)

**Goal**: Surface `cross_source_duplicates` + `DedupLayer`/`CrossSourceMatch` to Swift and green the bridge
test. `Transaction`/`Direction` are reused unchanged → **no `uniffi.toml` change**.

- [ ] T012 [US8] Run `make core-xcframework` to rebuild `ios/Frameworks/KanameCoreFFI.xcframework` + the generated Swift (git-ignored artifacts), now exposing `crossSourceDuplicates(existing:incoming:)`, the `DedupLayer` enum (`.canonical`/`.fuzzy`), and the `CrossSourceMatch` record (`incomingIndex`/`existingIndex`/`layer`). ⚠️ **MUST run before `tuist generate`**. Ref: `contracts/engine-ffi.md` §Stability, `quickstart.md` §3.
- [ ] T013 [US8] Run `make ios-test` (`ios-gen` → `core-xcframework` → `tuist generate` → `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test`) to **green** `ios/Tests/CrossSourceDedupTests.swift` (T005): the canonical match (`layer == .canonical`), the fuzzy match (`layer == .fuzzy`), and the multiplicity survivor (2 identical incoming vs 1 existing → exactly one match, surplus index absent). ⚠️ **Local: create the "iPhone 16" simulator first.** Verify **RED→GREEN**. Ref: `quickstart.md` §4.

**Checkpoint**: US1/US2/US8 delivered end-to-end (Rust engine + Swift bridge). A person's purchase seen in two sources → recognised as **one**, on-device.

---

## Phase 5: Verification of the remaining stories (US3, US4, US5, US6, US9) & polish

**Purpose**: Confirm the stories whose behavior already landed in Phase 3 are independently verified, and run
the full gate. Most of these are assertions already authored in T009/T004 — this phase makes their coverage
explicit and closes the constitution gates.

- [ ] T014 [P] [US3] Confirm **multiplicity** (FR-003, SC-005): the `dedup.rs` multiplicity unit test (T009) + the fixture's incoming `#5` `uber` survivor (T003) assert that N incoming vs M existing identical rows yield exactly `min(N, M)` matches and each existing index is consumed **at most once** (`consumed: Vec<bool>`); add (if not already in T009) an explicit assertion that the surplus incoming index is **absent** from the result. Ref: spec US3, `contracts/cross-source-dedup.md` §Invariants.
- [ ] T015 [P] [US5] Confirm **read-only + explain** (FR-002/010, SC-009/010): ensure a `dedup.rs` unit test asserts each emitted `CrossSourceMatch` names the incoming row, the existing row, and the `layer`; and that both input slices are unchanged after the call (borrowed `&`, so structurally guaranteed — assert `existing.len()`/`incoming.len()` and a couple of row values anyway). Do **not** infer deletion/merge — the matcher only **identifies** (FR-002, US5). Ref: spec US5, `contracts/engine-ffi.md` §Consumer expectations.
- [ ] T016 [P] [US4] Confirm **threshold protection** (FR-008/009/011, SC-002/008/011): the below-threshold survivor (`acme corp`/`acme corporation`, JW 0.9125 < 0.92) + the direction/amount/2-day-date guards (all survive) are pinned by T009, and the fixture's `#2` (below-threshold) + `#3` (direction-guard) survivors by T003/T004. Confirm the `>= 0.92` decision is on the **raw** f64 (inclusive) and that a differing amount/direction or a ≥2-day gap never matches. Ref: spec US4, `contracts/cross-source-dedup.md` §Guards.
- [ ] T017 [P] [US6] Confirm the **deterministic ladder** (FR-004, SC-006/007/012): the canonical-before-fuzzy precedence, first-unconsumed-wins tie-break, and same-input→same-output determinism unit tests (T009) hold; note the parity `cross_source_dedup_matches_expected` (T004) is itself a determinism/precedence witness (canonical `0→0`/`4→4`, fuzzy `1→1`, in incoming order). Ref: spec US6, research D7.
- [ ] T018 [US9] Run `make core-privacy-audit` — assert **no networking crate** enters the shipped graph (the dedup path is pure/on-device; FR-016/018, SC-015). This slice adds **no dependency**, so the shipped `cargo tree` is byte-identical; the inherited gate must stay green and now covers `cross_source_duplicates`. Ref: spec US9, `quickstart.md` §2.
- [ ] T019 Run the **full Local Verification Gate** end-to-end: `make core-lint core-test core-privacy-audit lint ios-test` — all green (fmt/clippy, Rust unit+parity, privacy audit, SwiftLint + swift-format lint, `tuist generate`, simulator build + Swift Testing). This is the mandatory pre-PR gate. Ref: `quickstart.md` §5, constitution §iOS Local Verification Gate.

**Checkpoint**: All nine user stories verified; every gate green. Ready for PR.

---

## Phase 6: Delivery

- [ ] T020 Commit in **two** commits on `013-cross-source-dedup`: (1) `feat(core): …` — the engine + fixture + parity (`dedup.rs`, `ffi.rs`, `lib.rs`, `fixtures/dedup/cross_source/basic.json`, `tests/parity.rs`); (2) `test(ios): …` — `ios/Tests/CrossSourceDedupTests.swift`. Include the `Co-authored-by: Copilot` trailer. Do NOT commit generated artifacts (`ios/Generated/`, `ios/Frameworks/*.xcframework` are git-ignored).
- [ ] T021 Open the PR (`gh pr create`), watch CI (Rust on `ubuntu-latest`, iOS on `macos-15`) to green, then `gh pr merge --rebase --delete-branch` and `git remote prune origin`. Compute the PR number from `gh pr list` (not 1:1 with the slice number — chore PRs consume numbers). Checkpoint with the user at the slice boundary.

---

## Dependencies & parallelism

- **Phase 2 (T003–T005)**: T003 (fixture) and T005 (Swift test) are `[P]`-parallel (independent files);
  T004 (parity) references the fixture → author T003 first, then T004. All three must be RED before Phase 3.
- **Phase 3**: T006 (`normalize_narration`) and T007 (`jaro`/`jaro_winkler`) are both in `dedup.rs` (not
  `[P]` with each other — same file) and are prerequisites of T008 (the matcher uses both). T009 (matcher
  tests) depends on T008; T010 (FFI/re-exports) depends on T008; T011 (green) depends on T006–T010.
- **Phase 4**: T012 → T013, depend on Phase 3 green.
- **Phase 5**: T014–T017 `[P]` (verification, mostly already-authored assertions) after Phase 3/4; T018
  after Phase 3; T019 (full gate) after all.
- **Phase 6**: after T019 green.

## Story → task coverage

| Story | Tasks |
|---|---|
| US1 canonical | T003, T005, T006, T008, T009, T010, T011, T013 |
| US2 fuzzy | T003, T005, T007, T008, T009, T011, T013 |
| US3 multiplicity | T003, T005, T008, T009, T014 |
| US4 threshold-protection | T003, T007, T009, T016 |
| US5 read-only identify | T008, T009, T015 |
| US6 deterministic ladder | T008, T009, T017 |
| US7 golden parity | T003, T004, T011 |
| US8 bridge | T005, T010, T012, T013 |
| US9 privacy-egress | T018, T019 |

## Implementation strategy

**MVP = Phase 1 → Phase 3 → Phase 4** delivers US1 (canonical) + US2 (fuzzy) + US8 (bridge) end-to-end: the
smallest cross-source signal that recognises the same purchase in two sources on-device. US3–US6 land in the
same engine phase (they constrain *how* the two layers consume candidates) and are verified in Phase 5; US7
(golden parity) is the acceptance gate proven at T011; US9 (privacy) is the inherited gate confirmed at
T018/T019. Build strictly **test-first** (Phase 2 RED before Phase 3 GREEN), extend the existing `dedup`
module surgically beside `reconcile.rs`, and add **zero** new dependencies.
