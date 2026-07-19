---
description: "Task list — Credit-Card Statement Reconciliation (reconcile.rs: the CC counterpart to balance_chain; two printed-total fields + Yes/IOB enrichments; zero new dependency)"
---

# Tasks: Reconcile a Credit-Card Statement Against Its Own Printed Totals On-Device

**Input**: Design documents from `/specs/012-cc-reconciliation/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/{engine-ffi.md, reconcile.md, golden-fixture.md}`, `quickstart.md`

**Tests**: REQUIRED and **TEST-FIRST** (Constitution Principle V). The extended golden fixtures, the
failing Rust parity assertions + reconcile parity tests, and the failing Swift bridge test are authored
**RED, before** the `reconcile.rs` engine + reader enrichments that green them. The `expected` values are
the **locked ground truth captured from a live web-engine run** (`reconciliation.py` + `yes_kiwi.py` +
`iob.py`): Yes printed debits `100.00` / credits `9000.00` (read `100.00`/`9000.00` → RECONCILED); IOB
printed debits `3500.00` / credits `1000.00` (read `3500.00`/`1000.00` → RECONCILED); a no-totals
statement → neutral (`status None`, `reason "no printed totals extracted"`); a mismatch → NEEDS_REVIEW.

**Port source of truth** (faithful, byte-for-byte with the golden vectors):
`/Users/ssk/Projects/finance-tracker-phase/backend/app/services/ingestion/reconciliation.py`
(the `reconcile` function) + the two readers' printed-total scrapes in `yes_kiwi.py` / `iob.py`, pinned by
`tests/unit/ingestion/test_reconciliation.py` and `tests/integration/test_statement_reconciliation.py`.
This slice is the **credit-card analogue of `balance_chain.rs`** and slots into the same seams.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: `US1`=verdict · `US2`=surface Yes/IOB totals · `US3`=neutral-distinct · `US4`=balance
  fallback · `US5`=explain+retain · `US6`=counterpart/no-new-infra · `US7`=golden parity · `US8`=bridge ·
  `US9`=privacy-egress. Setup/Polish carry no story label.
- Exact file paths are included in every task.

## ♻️ REUSE — do NOT re-create

Reconciliation plugs into the shipped foundations unchanged and mirrors `balance_chain.rs`. Do **not**
rebuild any of these:

- `statement/base.rs` — `ParsedStatement` / `ParsedTransaction` records. `printed_opening_balance` /
  `printed_closing_balance` (used by the fallback) **already exist** (`base.rs:94/97`, from the ledger
  work). This slice adds **only** `printed_total_debits` / `printed_total_credits`. **`printed_total_spend`
  is deliberately NOT ported** (no consumer — plan D9 / Complexity Tracking).
- `statement/balance_chain.rs` — the sibling check; **unchanged** and untouched. `reconcile.rs` is a new
  sibling structured identically (enum + `uniffi::Record` result with typed detail + a pure `check`-style
  fn + `Decimal::new(100, 2)` inclusive tolerance).
- `statement/common.rs` — `parse_amount` (`common.rs:58`), reused by the Yes/IOB enrich scrapes.
- `statement/line_reader.rs` — the `read_lines` / `LineReaderConfig` seam + the `enrich` hook, reused
  verbatim (Yes/IOB already implement `LineReaderConfig`).
- `ffi.rs` — the `Decimal`/`NaiveDate` custom types + `Direction` enum (**no `uniffi.toml` change**);
  `reconcile_statement` mirrors `check_balance_chain` (`ffi.rs:167–170`).
- `tests/parity.rs` — the golden-fixture harness; extend `Expected` with two `#[serde(default)]` optional
  fields + assertions and add three reconcile tests. **Do NOT rewrite the harness.**
- The **privacy-egress gate** (`make core-privacy-audit`) + CI — inherited unchanged (**no new
  dependency** → byte-identical shipped `cargo tree`).

**The only NEW code**: `statement/reconcile.rs` (enum + result record + `reconcile()` + unit tests), two
`ParsedStatement` fields (`base.rs`), the Yes (`yes.rs`) + IOB (`iob.rs`) enrich regexes + reader unit
tests, one `#[uniffi::export]` (`reconcile_statement`) + `lib.rs` re-exports, `pub mod reconcile;` in
`statement/mod.rs`, fixture `expected`/`full_text` extensions, three parity tests, and one Swift bridge
test. **No new dependency** (runtime *or* dev); **no other shared-engine change**.

## 🎯 The three-tier ladder — the whole decision surface (contracts/reconcile.md)

`reconcile(&ParsedStatement) -> ReconcileResult`, tolerance `Decimal::new(100, 2)` (= 1.00, inclusive
`<=`). `read_debits`/`read_credits` = `Σ line.amount` by `line.direction`, set in **every** outcome.

1. **Primary** — `if printed_total_debits.is_some() || printed_total_credits.is_some()`: each **present**
   total passes iff `(read − printed).abs() <= tolerance`; `Some(Reconciled)` iff every present passes,
   else `Some(NeedsReview)`; set `printed_debits`/`printed_credits`. Fallback **never** consulted.
2. **Fallback** — else if **both** `printed_opening_balance` and `printed_closing_balance` are present:
   `expected = closing − opening`, `computed = read_debits − read_credits`; `Some(Reconciled)` iff
   `(computed − expected).abs() <= tolerance`, else `Some(NeedsReview)`; set
   `expected_balance_change`/`computed_balance_change`.
3. **Neutral** — else: `status = None`, `reason = Some("no printed totals extracted")`.

`status: Option<ReconcileStatus>` — **`None` is neutral, structurally distinct from `Some(NeedsReview)`**.
Rows are never dropped/mutated/reordered. Money is exact `Decimal`, never `f64`.

## ⚠️ Local gotchas (apply throughout)

- **`make core-xcframework` MUST run before `tuist generate`** (`ios-gen: core-xcframework`) — the
  generated Swift + `KanameCoreFFI.xcframework` are rebuilt artifacts; run it after the FFI surface
  changes (new `reconcile_statement` + `ReconcileResult`/`ReconcileStatus` types).
- **The iOS CI job stays pinned to `macos-15`**; the local `xcodebuild` destination is the **"iPhone 16"**
  simulator (`OS=latest`).
- **swift-format `[Spacing]` rejects trailing inline comments** — in `ReconcileTests.swift` any comment
  goes on its **own line**, never trailing after code.
- **rustfmt reformats edits** — after each `edit`, run `make core-fmt` then re-view before the next edit
  (arrays/asserts/imports get re-wrapped).
- Money is **`Decimal`, never `f64`**; Indian grouping stripped and scale preserved
  (`9,000.00 → 9000.00`). Direction comes from each row's own `Dr`/`Cr` marker — reconciliation only
  **reads** `amount` + `direction`, never re-derives them. **No new dependency**.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm invariants so every later task lands cleanly and the gates stay green. No behavior yet.

- [ ] T001 [P] Confirm the **no-new-dependency** invariant: `core/crates/kaname-core/Cargo.toml` stays **UNCHANGED** (runtime `regex`/`rust_decimal`/`chrono`/`serde`/`uniffi` + dev-only `serde_json` already present) — this slice adds **zero** deps (FR-028, SC-017). Note that `fixtures/yes/credit_card/` and `fixtures/iob/credit_card/` already exist (no new dirs). Ref: plan §Summary, `contracts/golden-fixture.md`.
- [ ] T002 [P] Verify local prerequisites & gotchas (no code): `cargo` on PATH (`export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"`); an **"iPhone 16" simulator** exists in Xcode; recall `make core-xcframework` precedes `tuist generate`, the iOS CI job is pinned to **`macos-15`**, and **swift-format `[Spacing]` forbids trailing inline comments**. Ref: `quickstart.md` §Prerequisites/§Troubleshooting.

**Checkpoint**: No manifest change needed; toolchain + simulator + CI ordering understood.

---

## Phase 2: Test-First Foundation (⚠️ Principle V — author RED before ANY reconcile/enrich code)

**Purpose**: Pin the on-device engine to the proven web engine **before** writing it. These are the parity
(US7), verdict (US1), surface (US2), and bridge (US8) tests that protect the slice; they MUST be **RED**
at the end of this phase (`reconcile_statement` / the two `printed_total_*` fields do not exist yet).

**⚠️ CRITICAL**: No engine code (Phase 3+) until T003–T006 exist and are verified failing (compile-fail is
acceptable RED for the Rust harness; the Swift test won't build until Phase 4).

- [ ] T003 [P] [US2] [US7] Extend the Yes golden vector `fixtures/yes/credit_card/basic.json`: insert **two** printed-total lines into `full_text` immediately after the `Statement Period: …` line — `Current Purchases / Cash Advance & Other Charges : Rs. 100.00 Dr` and `Payment & Credits Received : Rs. 9,000.00 Cr` (these are **not** transaction rows; `lines` stays the two existing rows). Add to `expected`: `"printed_total_debits": "100.00"` and `"printed_total_credits": "9000.00"`. Leave `rows`/`period_start`/`period_end`/`card_last4`/`errored_lines` byte-for-byte unchanged (FR-014, SC-011). Update the `_comment` (drop "printed-totals … not modeled (later slice)"). Amounts are **JSON strings** (re-parsed to `Decimal`). 100% synthetic. Ref: `contracts/golden-fixture.md` §Yes, ground truth `reconcile_ground_truth.json`.
- [ ] T004 [P] [US2] [US7] Extend the IOB golden vector `fixtures/iob/credit_card/basic.json`: **NO `full_text`/`lines` change** (the `ACCOUNT SUMMARY` values row `345.50 1,000.00 3,500.00 0 2,845.50` is already present). Add to `expected`: `"printed_total_debits": "3500.00"` and `"printed_total_credits": "1000.00"` (the 3rd figure = debits, the 2nd = credits). Update the `_comment` (drop the "reconciliation printed-totals … not modeled" carve-out note). Ref: `contracts/golden-fixture.md` §IOB.
- [ ] T005 [US7] Extend the parity harness `core/crates/kaname-core/tests/parity.rs` → **RED**: (a) add to `Expected` (`parity.rs:29–44`) two fields `#[serde(default)] printed_total_debits: Option<String>` and `#[serde(default)] printed_total_credits: Option<String>`, and assert them in `assert_matches_expected` (mirror the `printed_opening_balance` block at `parity.rs:210–220`, using the existing `parse_dec`) — all other CC fixtures omit them → `None`, unchanged. (b) Add three tests: `yes_statement_reconciles` and `iob_statement_reconciles` (call `read_yes_statement`/`read_iob_statement` then `reconcile_statement(statement)`; assert `status == Some(ReconcileStatus::Reconciled)`, `read_debits`/`read_credits` and `printed_debits`/`printed_credits` equal the ground truth via `Decimal::from_str`), and `statement_without_printed_totals_is_neutral` (load `icici/credit_card/basic.json`, `reconcile_statement` → `status == None`, `reason == Some("no printed totals extracted")`). (c) Extend the `use kaname_core::{…}` import list with `reconcile_statement`, `ReconcileResult`, `ReconcileStatus`. ⚠️ **Verify RED**: `make core-test` fails to **compile** (fields/functions/types absent). Ref: `contracts/reconcile.md` §Golden behaviour, `data-model.md`.
- [ ] T006 [P] [US1] [US8] Author the **RED** Swift bridge test `ios/Tests/ReconcileTests.swift` — "core ↔ Swift reconciliation" (`import Foundation` / `import KanameCore` / `import Testing`), mirroring the balance-chain usage in `ios/Tests/AUBankParseTests.swift`: read a Yes statement (extended `fullText` incl. the two printed-total lines) via `readYesStatement(...)`, then `let result = reconcileStatement(statement: statement)`; assert `result.status == .reconciled`, and `statement.printedTotalDebits`/`printedTotalCredits` surface `100.00`/`9000.00` as exact `Decimal(string:locale: en_US_POSIX)`. A second `@Test`: read an IOB statement via `readIobStatement(...)` → `reconcileStatement(...).status == .reconciled`. A third `@Test`: read an ICICI statement (no totals) via `readIciciStatement(...)` → `reconcileStatement(...).status == nil` (neutral). ⚠️ **swift-format `[Spacing]`**: comments on their own line. ⚠️ **Verify RED**: won't build until Phase 4 regenerates the xcframework. Ref: `contracts/engine-ffi.md` §Contract tests (Swift).

**Checkpoint**: Fixtures extended; Rust parity harness RED (won't compile); Swift bridge test RED. Test-first satisfied — engine code may now begin.

---

## Phase 3: User Stories 1–6 — the engine (Priority: P1–P6) 🎯 MVP

**Goal**: Add the two printed-total fields, the `reconcile()` three-tier check, and the Yes/IOB
enrichments — greening the Rust parity + reconcile tests. This one engine phase lands the behaviors US1
(verdict), US2 (surface totals), US3 (neutral), US4 (fallback), US5 (explain+retain) and US6 (counterpart)
all verify.

**Independent Test**: `reconcile_statement(read_yes_statement(yes.lines, yes.full_text))` returns
`Some(Reconciled)`; a no-totals statement returns neutral `None` — with no network in the path.

- [ ] T007 [US2] [US4] Add the two printed-total fields to `core/crates/kaname-core/src/statement/base.rs`: in `ParsedStatement` (after `printed_closing_balance`, `base.rs:97`) add `pub printed_total_debits: Option<Decimal>,` and `pub printed_total_credits: Option<Decimal>,` with doc comments (the statement's own printed per-statement totals, surfaced only by Yes/IOB; `None` otherwise — drive the primary reconcile check). Initialize both to `None` in `ParsedStatement::new` (`base.rs:103–115`). Update the module `//!` doc (`base.rs:5–6`) — the reconciliation `printed_*` totals no longer "arrive with a later slice"; that slice is now (the fallback `printed_opening/closing_balance` already exist). **Do NOT add `printed_total_spend`** (plan D9). This is a `uniffi::Record` field addition (two new optional fields → Swift `printedTotalDebits`/`printedTotalCredits`). Ref: `data-model.md` §ParsedStatement, plan §technical-approach.
- [ ] T008 [US1] [US3] [US4] [US5] [US6] Create `core/crates/kaname-core/src/statement/reconcile.rs` and add `pub mod reconcile;` to `core/crates/kaname-core/src/statement/mod.rs` (near `pub mod polarity;`/`pub mod sbi;`, keeping order). Structure **identically to `balance_chain.rs`**:
  - `pub enum ReconcileStatus { Reconciled, NeedsReview }` — `#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]`.
  - `pub struct ReconcileResult` — `#[derive(Debug, Clone, PartialEq, uniffi::Record)]`: `status: Option<ReconcileStatus>`; `read_debits: Decimal`, `read_credits: Decimal`; `printed_debits: Option<Decimal>`, `printed_credits: Option<Decimal>`; `expected_balance_change: Option<Decimal>`, `computed_balance_change: Option<Decimal>`; `reason: Option<String>`. Doc each field (which tier sets it), mirroring `ChainResult`.
  - `pub fn reconcile(statement: &ParsedStatement) -> ReconcileResult` — `let tolerance = Decimal::new(100, 2);`; fold `read_debits`/`read_credits` over `statement.lines` by `Direction::Debit`/`Direction::Credit` (empty → `Decimal::ZERO`/`dec!(0.00)`); then the three-tier ladder from `contracts/reconcile.md` (primary → fallback → neutral). Rows are only read, never touched (FR-003).
  - A `//!` module doc: the CC counterpart to `balance_chain`, ported from `reconciliation.py`, pure/on-device.
  Ref: `contracts/reconcile.md` (full spec + truth table), `data-model.md` §ReconcileResult, `balance_chain.rs` as the template.
- [ ] T009 [US1] [US3] [US4] [US5] Add `#[cfg(test)] mod tests` to `reconcile.rs` mirroring `test_reconciliation.py` + the spec edge cases (build small `ParsedStatement`s with hand-set fields; `dec!` amounts): `totals_match → Reconciled`; `debit_mismatch → NeedsReview` (+ assert `read_debits`/`printed_debits` in the detail); `half_rupee_within_tolerance → Reconciled`; `exactly_one_rupee_boundary → Reconciled`; `only_one_total_present` (credit-only present → verdict rests on it); `both_present_one_mismatch → NeedsReview`; `balance_change_fallback → Reconciled` (opening 1000/closing 1300, debit 500/credit 200); `primary_takes_precedence_over_fallback` (printed total present + balances present → fallback fields stay `None`); `only_one_balance_is_neutral → None`; `no_totals_is_neutral_none` (+ `reason == "no printed totals extracted"`); `empty_rows_sum_zero`. Assert `status` **and** the relevant typed detail fields; compare money by `Decimal` value-equality. Ref: `contracts/reconcile.md` §Unit tests, `test_reconciliation.py`.
- [ ] T010 [US2] Port the Yes printed-total scrape into `core/crates/kaname-core/src/statement/yes.rs`: add two `static … : LazyLock<Regex>` — `DEBITS_RE = (?i)Purchases[^\n]*?Rs\.?\s*([\d,]+\.\d{2})\s*Dr` and `CREDITS_RE = (?i)Payment\s*&?\s*Credits Received[^\n]*?Rs\.?\s*([\d,]+\.\d{2})\s*Cr` (ported byte-for-byte from `yes_kiwi.py:26–29`). In `enrich` (`yes.rs:55–61`) set `statement.printed_total_debits = DEBITS_RE.captures(full_text).and_then(|c| parse_amount(&c[1]));` and the credit analogue (import `parse_amount` alongside `find_last4`/`parse_date`). A present total is surfaced **only** when its label+value are on the same extracted line; else left `None`. **Rewrite the module `//!` carve-out paragraph** (`yes.rs:8–10`) — printed totals are now surfaced for reconciliation. Extend the reader's `#[cfg(test)]` `sample()` `full_text` with the two printed-total lines and add a unit test asserting `printed_total_debits == Some(dec!(100.00))` and `printed_total_credits == Some(dec!(9000.00))` while the existing row/period/last-4 asserts still pass. Ref: `data-model.md` §yes.rs, `yes_kiwi.py`.
- [ ] T011 [US2] Port the IOB `ACCOUNT SUMMARY` scrape into `core/crates/kaname-core/src/statement/iob.rs`: add one `static SUMMARY_RE: LazyLock<Regex>` = `(?is)ACCOUNT SUMMARY\b.*?(?P<prev>[\d,]+(?:\.\d+)?)\s+(?P<credits>[\d,]+\.\d{2})\s+(?P<debits>[\d,]+\.\d{2})\s+(?P<fees>[\d,]+(?:\.\d+)?)\s+(?P<total>[\d,]+(?:\.\d+)?)` (ported from `iob.py:41–47`; `IGNORECASE|DOTALL` → `(?is)`). In `enrich` (`iob.rs:60–65`) set `printed_total_credits` from group `"credits"` and `printed_total_debits` from group `"debits"` via `parse_amount` (import it). **Rewrite the module `//!` carve-out paragraph** (`iob.rs:11–14`). Add a unit test on the existing `sample()` (whose `full_text` already carries the `ACCOUNT SUMMARY` block) asserting `printed_total_debits == Some(dec!(3500.00))` and `printed_total_credits == Some(dec!(1000.00))`. Ref: `data-model.md` §iob.rs, `iob.py`.
- [ ] T012 [US1] [US8] Add the FFI export in `core/crates/kaname-core/src/ffi.rs` (mirror `check_balance_chain` at `ffi.rs:167–170`): `use crate::statement::reconcile::{reconcile, ReconcileResult};` with the other statement imports, then `#[uniffi::export] pub fn reconcile_statement(statement: ParsedStatement) -> ReconcileResult { reconcile(&statement) }` (total, never panics). Re-export in `core/crates/kaname-core/src/lib.rs`: add `reconcile_statement` to the `pub use ffi::{…}` block (`lib.rs:28–34`) and add `pub use statement::reconcile::{ReconcileResult, ReconcileStatus};` beside the `balance_chain` re-export (`lib.rs:36`). Depends on T008. Ref: `contracts/engine-ffi.md`.
- [ ] T013 [US7] **Green the engine side**: `make core-fmt`, then `make core-test` — the parity harness (T005: Yes/IOB `printed_total_*` assertions + the three reconcile tests) now **PASSES**, `reconcile.rs`/`yes.rs`/`iob.rs` unit tests pass, and **all prior parity stays green** (other CC fixtures deserialize the new fields as `None`) — then `make core-lint` (clippy `-D warnings` + fmt check). Verify **RED→GREEN** for the Rust side. Ref: `quickstart.md` §Engine.

**Checkpoint**: The engine surfaces the Yes/IOB printed totals and reconciles all three verdicts; Rust parity + reconcile + reader unit tests are green. US1–US6 functional on the Rust side (Swift bridge greened in Phase 4).

---

## Phase 4: UniFFI bridge — regenerate the xcframework + green the Swift test (US8)

**Goal**: Surface `reconcile_statement` + `ReconcileResult`/`ReconcileStatus` + the two new
`ParsedStatement` fields to Swift and green the bridge test.

- [ ] T014 [US8] Run `make core-xcframework` to rebuild `ios/Frameworks/KanameCoreFFI.xcframework` + the generated Swift (git-ignored artifacts), now exposing `reconcileStatement(statement:)`, the `ReconcileResult` record, the `ReconcileStatus` enum (`.reconciled` / `.needsReview`, surfaced optional), and `ParsedStatement.printedTotalDebits`/`printedTotalCredits`. ⚠️ **MUST run before `tuist generate`**. Ref: `contracts/engine-ffi.md` §Stability.
- [ ] T015 [US8] Run `make ios-test` (`ios-gen` → `core-xcframework` → `tuist generate` → `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test`) to **green** `ios/Tests/ReconcileTests.swift` (T006): Yes → `.reconciled` with printed totals surfaced; IOB → `.reconciled`; ICICI → `status == nil` (neutral). ⚠️ **Local: create the "iPhone 16" simulator first.** Verify **RED→GREEN**. Ref: `quickstart.md` §iOS.

**Checkpoint**: US1/US8 delivered end-to-end (Rust engine + Swift bridge). A person's credit-card statement → a trust verdict, on-device.

---

## Phase 5: Verification of the remaining stories (US3, US4, US5, US6, US9) & polish

**Purpose**: Confirm the stories whose behavior already landed in Phase 3 are independently verified, and
run the full gate. Most of these are assertions already authored in T009/T005 — this phase makes their
coverage explicit and closes the constitution gates.

- [ ] T016 [P] [US3] Confirm the **neutral-distinct** guarantee (FR-004, SC-006): the `no_totals_is_neutral_none` unit test (T009) + the `statement_without_printed_totals_is_neutral` parity test (T005) assert `status == None` and that it is **not** `Some(NeedsReview)`; add (if not already present in T009) an explicit `assert_ne!(neutral.status, Some(ReconcileStatus::NeedsReview))`. Optionally assert in `reconcile.rs` tests that all four no-total readers (ICICI/HDFC/SBI/Federal) would produce neutral (the ICICI parity case already covers one). Ref: spec US3, `contracts/reconcile.md`.
- [ ] T017 [P] [US5] Confirm **explain + never-drop** (FR-003/010, SC-009/010): ensure a `reconcile.rs` unit test builds a 3-row statement that yields `NeedsReview` and asserts the input `statement.lines.len()` is unchanged after `reconcile` (borrowed `&`, so structurally guaranteed — assert it anyway), and that each outcome's typed detail carries its numbers (primary: read+printed; fallback: expected+computed; neutral: reason). Ref: spec US5, `test_statement_reconciliation.py` (rows retained on NEEDS_REVIEW).
- [ ] T018 [P] [US6] Confirm **counterpart / no-new-infra** (FR-016, SC-017): review the change set — exactly `reconcile.rs` + two `base.rs` fields + `yes.rs`/`iob.rs` enrich + one `ffi.rs` export + `lib.rs`/`mod.rs` wiring + two fixtures + `parity.rs` + one Swift test; `Cargo.toml` unchanged (no new dep); `balance_chain.rs` untouched; `printed_total_spend` absent. Ref: plan §Complexity Tracking.
- [ ] T019 [US9] Run `make core-privacy-audit` — assert **no networking crate** enters the shipped graph (the reconcile path is pure/on-device; FR-020..022, SC-016). Inherited gate, must stay green.
- [ ] T020 Run the **full Local Verification Gate** end-to-end: `make core-lint core-test core-privacy-audit lint ios-test` — all green (fmt/clippy, Rust unit+parity, privacy audit, SwiftLint + swift-format lint, `tuist generate`, simulator build + Swift Testing). This is the mandatory pre-PR gate. Ref: `quickstart.md` §Gate, constitution §iOS Local Verification Gate.

**Checkpoint**: All nine user stories verified; every gate green. Ready for PR.

---

## Phase 6: Delivery

- [ ] T021 Commit in **two** commits on `012-cc-reconciliation`: (1) `feat(core): …` — the engine + fixtures + parity (`base.rs`, `reconcile.rs`, `mod.rs`, `yes.rs`, `iob.rs`, `ffi.rs`, `lib.rs`, the two fixtures, `parity.rs`); (2) `test(ios): …` — `ios/Tests/ReconcileTests.swift`. Include the `Co-authored-by: Copilot` trailer. Do NOT commit generated artifacts (`ios/Generated/`, `ios/Frameworks/*.xcframework` are git-ignored).
- [ ] T022 Open the PR (`gh pr create`), watch CI (Rust on `ubuntu-latest`, iOS on `macos-15`) to green, then `gh pr merge --rebase --delete-branch` and `git remote prune origin`. Compute the PR number from `gh pr list` (not 1:1 with the slice number — chore PRs consume numbers). Checkpoint with the user at the slice boundary.

---

## Dependencies & parallelism

- **Phase 2 (T003–T006)** is all `[P]`-parallel except T005 (parity) which references the fixtures (author fixtures T003/T004 first, then T005). All must be RED before Phase 3.
- **Phase 3**: T007 (fields) → T008 (reconcile module) → T009 (its tests); T010/T011 (Yes/IOB enrich, `[P]` — different files) depend on T007; T012 (FFI) depends on T008; T013 (green) depends on T007–T012.
- **Phase 4**: T014 → T015, depend on Phase 3 green.
- **Phase 5**: T016–T019 `[P]` after Phase 3/4; T020 (full gate) after all.
- **Phase 6**: after T020 green.

## Story → task coverage

| Story | Tasks |
|---|---|
| US1 verdict | T006, T008, T009, T012, T015 |
| US2 surface Yes/IOB totals | T003, T004, T007, T010, T011 |
| US3 neutral-distinct | T005, T009, T016 |
| US4 balance fallback | T007, T008, T009 |
| US5 explain + retain | T009, T017 |
| US6 counterpart / no-new-infra | T008, T018 |
| US7 golden parity | T003, T004, T005, T013 |
| US8 bridge | T006, T012, T014, T015 |
| US9 privacy-egress | T019, T020 |
