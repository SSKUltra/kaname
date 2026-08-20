---
description: "Task list for 020-categorize"
---

# Tasks: Categorize — deciding what a transaction was

**Input**: Design documents from `/specs/020-categorize/`
**Prerequisites**: `plan.md` (required), `spec.md` (required), `research.md`, `data-model.md`, `contracts/engine-categorize.md`, `contracts/platform-categorize.md`, `quickstart.md`
**Governing**: `.specify/memory/constitution.md` (Principles I–VII), `AGENTS.md`, `specs/020-categorize/plan.md` § *Spec amendments*, § *Judgement calls*

**Tests: MANDATORY.** The engine half of this feature is written test-first — a task that writes an assertion always precedes the task that makes it pass, and this list says which. The platform half is written test-alongside, but no platform task is complete until its assertion has been *watched failing* against a deliberate break. **No test in this slice may be disabled, skipped, or `#if`-ed out to get a gate green.** A test that cannot pass is a finding, not a nuisance.

**Organization**: Tasks are grouped by the seven-pull-request delivery order fixed in `plan.md` § *Delivery order*. That order is not advisory: PR A closes a live correctness defect and every later PR reads the predicate it introduces, PR B's memory is consulted by the write path PR A builds, and PRs D–F are the only surfaces a person ever sees. Each PR is independently shippable, independently green, and independently revertible.

| PR | Title | Tasks | Delivers | Depends on |
|----|-------|-------|----------|------------|
| **A** | The engine's answer to the defect 🔒 | T001–T040 | schema v8, the three predicates, the corrected write path, the `detect_transfers` guard | — |
| **B** | The memory 🔒 | T041–T074 | `merchant_portion` derivation, `merchant_memory`, preview/apply | A |
| **C** | The read side 🔒 | T075–T089 | uncategorized counts, the worklist query, the plan-shape assertions | A, B |
| **D** | Correcting one transaction 🎯 | T090–T115 | `ios/Sources/Categorize/`, the picker, the detail entry point | A, C |
| **E** | The memory and the second action | T116–T133 | the memory offer, the second action, the stale set | B, D |
| **F** | The worklist | T134–T152 | the uncategorized worklist, its empty states | C, D, E |
| **G** | Proved, not asserted | T153–T176 | audits, sweeps, the break ledger, the honest deferrals | A–F |

🔒 = engine-only, no Swift changes, gated by `make core-lint && make core-test`.
🎯 = first PR a person can see.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: genuinely parallelizable — different file, no dependency on an incomplete task. Absent [P] means *do not start this until the task above it is done*.
- **[Story]**: `[US1]`–`[US7]` for user-story phases; setup, foundational, and polish tasks carry no story label.
- Every task names the concrete file path it touches and the FR/SC id or named contract assertion it satisfies.

## Path Conventions

- Engine: `core/crates/kaname-core/src/`, tests in `core/crates/kaname-core/tests/`, fixtures in `fixtures/`
- Platform: `ios/Sources/`, unit tests in `ios/Tests/`, UI tests in `ios/UITests/`
- New platform code for this feature lives in `ios/Sources/Categorize/` (a new directory)
- Scripts: `scripts/`; gates: `Makefile`

## Non-negotiables encoded in this list

1. **`cargo` is not on the default PATH.** Every engine task assumes `export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"` in the shell. A "command not found" here is an environment problem, not a code problem.
2. **⚠️ Never run `make core-test` and `make ios-test` concurrently.** `core/tests/history_perf.rs::s5` is a wall-clock assertion and goes flaky under CPU contention. Run engine gates and platform gates in sequence, always. `make ios-test` also cannot run concurrently with itself (019's lesson).
3. **⚠️ Any task that adds or changes an `#[uniffi::export]` surface is followed by a task running `make core-xcframework` *then* `make ios-gen`** — in that order, never a bare `tuist generate` (`AGENTS.md:88-92`). The symptom of skipping it is `cannot find 'X' in scope` in Swift: a Swift error that is not a Swift problem. Do not debug the Swift.
4. **⚠️ Any task that adds a *new file* — Swift source or test — is followed by a task running `make ios-gen`.** `Project.swift` declares `sources: ["Sources/**"]`, which resolves at *generation* time. A new test file that was never regenerated into the target does not run, and a suite that never ran **reports success**. This bit 019 twice. It is structural here.
5. **🚨 `NULL NOT IN ('PERSON','PERSON_MEMORY')` evaluates to `NULL`, not `TRUE`.** The naive guard therefore discards every row `import_statement` just inserted (its bulk insert writes `NULL, NULL` literally) — every import would land wholly uncategorized and **nothing would error**. The `ENGINE_MAY_DECIDE` predicate must keep its `IS NULL OR` arm. Its regression test **C2** is a separate task from **C1**, and C1 passing proves nothing: C1 stays green against the broken guard.
6. **🚨 `detect_transfers` is guarded on `transfer_group_id IS NULL` alone** and can overwrite a person's decision with `TRANSFER_DETECTOR`. Fixed in PR A. It is unreachable from the shipping app (scan 9 bans `detectTransfers` in Swift), so it needs a Rust-only test — a UI test cannot reach it.
7. **⚠️ `git checkout -- ios/Sources` is not how you revert a deliberate break** while the fix itself is uncommitted. It reverts to `HEAD` and takes the fix with it. Either commit the fix first (`git add -A && git commit -m "wip"`) and then break, or copy the tree aside (`cp -R ios/Sources /tmp/sources-backup`) and restore from the copy. The same hazard applies to `git checkout -- core/`. Never break first and hope.
8. **`ios/Sources/Import/ImportService.swift` is at 398 of its 400-line budget.** Zero lines may be added to it (FR-073, SC-023). `ios/Sources/Transactions/TransactionListModels.swift` at 332 is next at risk.
9. **Use `IS` / `IS NOT`, never `=` / `!=`, against nullable `categorised_by`.** `categorised_by = 'PERSON'` is `NULL` for an un-decided row, and `NULL` is not `TRUE`.
10. **No floats anywhere in money.** Amounts are integer paise end to end (Principle II).

---

# PR A — The engine's answer to the defect 🔒

*Schema v8, the three predicates, the corrected write path, and the `detect_transfers` guard. No Swift changes. This PR pre-pays US2 (a decision is never overwritten) and closes the engine half of US7 (migration). Both 🚨 findings are fixed here.*

## Phase 1: Setup and baseline

**Purpose**: establish the number every later "still green" claim is relative to, and find the sites the fix must reach.

- [x] T001 Export `PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"`, run `make core-lint && make core-test` at `HEAD` and record the pass count and duration in the PR description. Every later "still green" is relative to this number, not to a feeling.
- [x] T002 [P] Survey `core/crates/kaname-core/src/store.rs` and enumerate, in the PR description, every SQL site that (a) filters live rows or (b) writes `category_id` / `categorised_by`. This list is the input to T024 and T028 — a guard that reaches only the site the test happened to exercise is not a fix.
- [x] T003 [P] Create `core/crates/kaname-core/tests/store_correction.rs` with the module header and the `tests/common` harness import, no assertions yet. (A new Rust integration test file is discovered by cargo automatically — the `make ios-gen` trap in non-negotiable 4 is Swift-only.)
- [x] T004 [P] Confirm the store's current `user_version` is 7 and locate the migration ladder's insertion point in `core/crates/kaname-core/src/store.rs`; record the line in the PR description.
- [x] T005 [P] Add a helper to `core/crates/kaname-core/tests/common/` that builds a **v7** store containing rows in every provenance state (`NULL`, `'PERSON'`, `'PERSON_MEMORY'`, `'TRANSFER_DETECTOR'`, and each engine tier). G1 is worth nothing if the fixture only has one state in it.

**Checkpoint**: baseline green recorded, write sites enumerated, v7 fixture available.

## Phase 2: Schema v8 — the migration [US7]

**Purpose**: add `merchant_memory` and the partial index without touching a single existing row. RED first — every assertion below is watched failing before T010 exists.

- [x] T006 [US7] RED **G2** in `core/crates/kaname-core/tests/store.rs`: after migration `user_version == 8`, `merchant_memory` exists and is empty, and `idx_txn_unanswered_account_date` exists. Run `make core-test`, watch it fail, record the failure text.
- [x] T007 [US7] RED **G1** in `core/crates/kaname-core/tests/store.rs`: open the T005 v7 store, migrate, and assert every row's `category_id`, `amount`, `date`, `description`, `account_id` and `categorised_by` is **byte-identical** (FR-047, SC-014). Watch it fail.
- [x] T008 [US7] RED **G3** in `core/crates/kaname-core/tests/store.rs`: a migration failure leaves `user_version` at 7 and no partial object behind (FR-048, SC-015). Watch it fail.
- [x] T009 [US7] RED **G4** in `core/crates/kaname-core/tests/store.rs`: a migrated v8 store opens and behaves identically to a fresh v8 store. Watch it fail.
- [x] T010 [US7] GREEN: add the v7→v8 migration to `core/crates/kaname-core/src/store.rs` — `CREATE TABLE merchant_memory(merchant_portion TEXT PRIMARY KEY, category_id TEXT NOT NULL REFERENCES categories(id)) STRICT` and `CREATE INDEX idx_txn_unanswered_account_date ...` per `data-model.md` §1. **Additive only**: no `ALTER TABLE`, no row read, no row written — which is what makes FR-047 / SC-014 true by construction rather than by luck.
- [x] T011 [US7] Declare the three predicates in `core/crates/kaname-core/src/store.rs`, each spelled **exactly once** as a constant per `contracts/engine-categorize.md` §5: `LIVE` (unchanged), `UNANSWERED` = `category_id IS NULL AND categorised_by IS NULL`, `ENGINE_MAY_DECIDE` = `(categorised_by IS NULL OR categorised_by NOT IN ('PERSON','PERSON_MEMORY'))`. ⚠️ Use `IS` / `IS NOT`, never `=` / `!=` — see non-negotiable 9.
- [x] T012 [US7] STRUCTURAL assertion in `core/crates/kaname-core/tests/store.rs`: the created index's `WHERE` clause, read back from `sqlite_master`, is the **byte-identical concatenation** of `LIVE` and `UNANSWERED` (`contracts/engine-categorize.md` §5.1). This is the contract's one unnumbered requirement and it is the only thing that stops the index and the query drifting apart silently.
- [x] T013 [US7] Behaviour test for the predicates in `core/crates/kaname-core/tests/store.rs`: `UNANSWERED` excludes a `'PERSON'` deliberate blank; `ENGINE_MAY_DECIDE` **admits** a `NULL`-provenance row. Run `make core-test` — G1–G4 and both structural assertions green.

**Checkpoint**: schema v8 exists, the predicates are spelled once, migration is proved non-destructive.

## Phase 3: The write path — a person's decision, recorded [US1] [US2]

**Purpose**: give the engine a way to record a correction, in one transaction, with `'PERSON'` provenance.

- [x] T014 [US1] RED **C6** in `core/crates/kaname-core/tests/store_correction.rs`: `set_transaction_category` on an unknown id returns `NotFound` and writes nothing. Watch it fail (the function does not exist).
- [x] T015 [US1] RED **C3** in `core/crates/kaname-core/tests/store_correction.rs`: correct to `None` → `category_id IS NULL`, `categorised_by = 'PERSON'`, and a re-import leaves it alone. A deliberate blank is protected as strongly as a category. Watch it fail.
- [x] T016 [US1] GREEN: implement `set_transaction_category(id, category_id: Option<String>, remember: bool)` in `core/crates/kaname-core/src/store.rs`, writing `category_id` and `categorised_by = 'PERSON'` inside **one** `rusqlite::Transaction`. `remember` is accepted and deliberately ignored in this PR — the memory lands in PR B — and the doc comment says so, so the next reader does not think it is a bug.
- [x] T017 [US1] GREEN: add `CorrectionOutcome` (`contracts/engine-categorize.md` §2.1) and the `NotFound` error variant in `core/crates/kaname-core/src/model.rs`.
- [x] T018 [US1] Export `set_transaction_category` and `CorrectionOutcome` over `#[uniffi::export]` in `core/crates/kaname-core/src/ffi.rs`. First FFI surface change of the slice.
- [x] T019 ⚠️ **BUILD** — run `make core-xcframework` **then** `make ios-gen`, in that order. Never a bare `tuist generate` (`AGENTS.md:88-92`). If Swift later says `cannot find 'setTransactionCategory' in scope`, that is this task not having been run — do not debug the Swift.
- [x] T020 [US1] Run `make core-test` — C3 and C6 green.

**Checkpoint**: a correction can be recorded. It is not yet protected.

## Phase 4: 🚨 The guard — `categorize_account_in` [US2]

**Purpose**: stop the engine overwriting a person's decision on re-import — and prove the *naive* fix is worse than no fix.

> 🚨 **Read this before writing the guard.** `NULL NOT IN ('PERSON','PERSON_MEMORY')` evaluates to `NULL`, not `TRUE`. `import_statement`'s bulk insert writes `NULL, NULL` literally (`store.rs:855-870`), so a guard spelled `categorised_by NOT IN (...)` discards **every row the import just inserted**. Every import would land wholly uncategorized, and **nothing would error**. This is research R10.

- [x] T021 [US2] RED 🔴 **C1** in `core/crates/kaname-core/tests/store_correction.rs`: correct a row, re-run `import_statement` for that account, assert `category_id` and `categorised_by = 'PERSON'` are unchanged.
- [x] T022 [US2] Watch **C1** fail against shipped behaviour and record the failure text in the PR description. `categorize_account_in`'s unconditional `UPDATE` (`store.rs:1304`) writes `NULL, NULL` over the correction. **If C1 passes here, the test is not reaching the write path** — fix the test, not the expectation.
- [x] T023 [US2] RED **C2** in `core/crates/kaname-core/tests/store_correction.rs`, as its **own task, separate from C1**: after a fresh import into an empty store, the count of rows with a non-null `category_id` is **greater than zero**. This assertion is **green today**; it is written now so that T026's break has something to turn red. ⚠️ **The queue is explicit about why C1 is not enough: C1 passes against the broken naive guard.** A slice that only had C1 would ship R10's trap with a green suite.
- [x] T024 [US2] GREEN: add `ENGINE_MAY_DECIDE` to `categorize_account_in`'s `UPDATE ... WHERE` in `core/crates/kaname-core/src/store.rs`, **keeping the `categorised_by IS NULL OR` arm**. Reference the predicate constant from T011; do not re-spell the SQL.
- [x] T025 [US2] Run `make core-test` — C1 and C2 both green, and every existing suite (`store_import.rs`, `store_categorization.rs`, `store_dedup.rs`, `parity.rs`) still green.
- [x] T026 🚨 **DELIBERATE BREAK** — in `core/crates/kaname-core/src/store.rs`, replace the guard with the naive `categorised_by NOT IN ('PERSON','PERSON_MEMORY')`. Expected: **C2 RED and C1 still GREEN**. Observing exactly that pair is the point of this task. Revert. ⚠️ Commit the fix first (`git add -A && git commit -m "wip: guard"`) or copy `core/` aside — `git checkout -- core/` reverts to `HEAD` and would take the fix with it.
- [x] T027 **DELIBERATE BREAK** — remove `ENGINE_MAY_DECIDE` from the selection in `load_account_transactions` in `core/crates/kaname-core/src/store.rs`. Expected: **C1 RED**. Revert as above. (Two sites, two breaks: the guard must hold on both the read that feeds the categorizer and the write that lands its answer.)
- [x] T028 [US2] Extend the guard to every remaining write site enumerated in T002, in `core/crates/kaname-core/src/store.rs`, each referencing the `ENGINE_MAY_DECIDE` constant.
- [x] T029 [US2] Add a structural assertion in `core/crates/kaname-core/tests/store_correction.rs`: no `UPDATE` of `category_id` or `categorised_by` exists in `src/store.rs` without either `ENGINE_MAY_DECIDE` or an explicit `'PERSON'`-writing comment. A source-level assertion is what keeps the next `UPDATE` from being written without the guard.
- [x] T030 [US2] Run `make core-test`.

**Checkpoint**: 🚨 finding (a) is closed and its trap has a named regression test of its own.

## Phase 5: 🚨 The transfer detector's guard [US2]

> 🚨 `detect_transfers`'s `UPDATE` is guarded on `transfer_group_id IS NULL` **only** (`store.rs:1160-1166`). It can overwrite a person's decision with `'TRANSFER_DETECTOR'`. ⚠️ This path is **unreachable from the shipping app** — `import-path-audit.sh` scan 9 bans `detectTransfers` in Swift and this slice does not wire it up (018 R18 stays open). So it needs a **Rust-only** test; no UI test can ever reach it.

- [x] T031 [US2] RED 🔴 **T1** in `core/crates/kaname-core/tests/store_transfer.rs`: correct a row, then run `detect_transfers` over a store where that row is a valid transfer leg. The correction stands.
- [x] T032 [US2] Watch **T1** fail against shipped behaviour and record the failure text.
- [x] T033 [US2] RED **T2** in `core/crates/kaname-core/tests/store_transfer.rs`: for a store with no `'PERSON'` rows, transfer detection finds the same pairs, forms the same groups and returns the same summary counts as before (FR-075). Green today — written now so T035 has something to keep honest.
- [x] T034 [US2] GREEN: add the provenance arm to `detect_transfers`' `UPDATE` guard in `core/crates/kaname-core/src/store.rs`, referencing `ENGINE_MAY_DECIDE`.
- [x] T035 **DELIBERATE BREAK** — remove the provenance arm again. Expected: **T1 RED, T2 GREEN**. Revert (commit-first or copy-aside).
- [x] T036 [US2] Record in the PR description that this hole was unreachable in the shipping app and is still fixed, with the reason: the guarantee belongs to the engine, not to the absence of a caller (plan § *Judgement calls* §3).

**Checkpoint**: 🚨 finding (b) is closed.

## Phase 6: PR A close-out

- [x] T037 Record the deliberate deferrals in the PR description: **C4** and **C7** move to PR B (the memory table has no writer yet), **C5** moves to PR C (the uncategorized narrowing does not exist yet). A deferral with a reason is a plan; a deferral without one is a gap.
- [x] T038 Run `make core-fmt` then `make core-lint` over `core/crates/kaname-core/`.
- [x] T039 **GATE** — `make core-lint && make core-test`. ⚠️ Do **not** run concurrently with `make ios-test`: `core/tests/history_perf.rs::s5` is wall-clock and goes flaky under CPU contention.
- [x] T040 **GATE** — `make core-privacy-audit`, and confirm this PR touched no Swift: `git --no-pager diff --stat origin/main... -- ios/` is empty.

## PR A — RECORDED

*What the queue said would happen, what actually happened, and the four places they differed.*

**Baseline (T001)**: 310 tests, `make core-lint` clean, `make core-test` 7.0 s wall.
**After PR A**: **324 tests** (+14), lint clean, `core-privacy-audit` OK, no tracked Swift file
touched (`ios/Generated/` and `ios/Frameworks/` are gitignored, so T019's rebuild leaves the tree
engine-only, as intended).

**The two 🚨 findings, both watched failing first.**

- 🔴 **C1 failed against shipped behaviour** exactly as research R10 predicted. Recorded failure:
  `left: (Some("FOOD_AND_DINING"), Some("T1_SOURCE_CATEGORY"))` against
  `right: (Some("GROCERIES"), Some("PERSON"))` — the re-import's source-category map wrote
  straight over the person's correction.
- 🔴 **T1 failed against shipped behaviour** too: `left: Some("CREDIT_CARD_BILL_PAYMENT")` against
  `right: Some("SHOPPING")`. The transfer detector erased a decision, on a path
  `import-path-audit.sh` scan 9 makes unreachable from the app. Fixed anyway — the guarantee
  belongs to the engine, not to the current absence of a caller.
- 🚨 **T026's break produced precisely the predicted pair**: with the naive
  `categorised_by NOT IN ('PERSON', 'PERSON_MEMORY')`, **C2 went red and C1 stayed green**.
  `NULL NOT IN (…)` is `NULL`, every row the import had just inserted was discarded, and nothing
  errored. This is why C2 is a test of its own and not a line inside C1.

**Four deviations from the queue, each a case of believing the codebase.**

1. **T027's break did not turn C1 red — it turned nothing red.** Removing `ENGINE_MAY_DECIDE`
   from `load_account_transactions` leaves C1 green, because the *write*-site guard already
   blocks the overwrite on its own. The two guards are not independent, and the queue assumed
   they were. Rather than delete the load-site guard as redundant or leave an unpinned line of
   code, PR A adds **C8** (`the_summary_counts_only_rows_the_engine_may_decide`): without the
   load guard the stack loads a corrected row, decides a category for it, reports it as
   `categorized`, and then writes nothing — a summary describing work it did not do. Under the
   break C8 reads `left: (1, 1)`, `right: (0, 1)`. The load-site guard now has an assertion that
   is red without it.
2. **G1–G4 live in `src/store.rs`'s `mod tests`, not `tests/store.rs`.** Every migration test in
   the repository is there (`migrating_v6_to_v7_preserves_existing_rows` and its five siblings),
   and the structural assertions need `LIVE`, `UNANSWERED`, `ENGINE_MAY_DECIDE` and
   `apply_migration`, none of which are public. Putting them where the queue said would have
   meant exporting four private items to satisfy a filename. T005's v7 fixture is therefore an
   in-module helper, `v7_store_with_every_provenance_state`, carrying **nine** rows across all
   six provenance states plus a deliberate blank.
3. **`SCHEMA_V8` uses plain `CREATE TABLE` / `CREATE INDEX`, not `IF NOT EXISTS`** as
   `data-model.md` §1.1 wrote them. v7 established the discipline and
   `reopening_a_v8_store_is_a_no_op` depends on it: a second open that re-ran the migration must
   *fail*, not silently succeed. `IF NOT EXISTS` would have made that test vacuous.
4. **Three existing tests pinned the head schema version at 7** and were updated to 8
   (`migration_is_idempotent_across_reopens`, `reopening_a_v6_store_is_a_no_op`,
   `schema_is_at_current_version_and_migration_is_idempotent`), and
   `reopening_a_v7_store_is_a_no_op` was **renamed** to `…v8…`: it never opened a v7 store, it
   opened a store at head and asserted the head version, so its name had been wrong since v7.

**T029 was watched failing too.** The source-level assertion
(`every_category_update_in_the_store_is_guarded`) went red under T035's break, which is the only
evidence that a structural test bites at all.

**T037 — deliberate deferrals, with reasons.** **C4** and **C7** move to PR B: there is no memory
writer yet, and `set_transaction_category` accepts `remember` and ignores it (documented in the
method, so the next reader does not read it as a bug). **C5** moves to PR C: the uncategorized
narrowing does not exist yet. `UNANSWERED` and `PERSON_MEMORY` are declared in PR A and carry
`#[allow(dead_code)]` with the pull request that consumes each named — `UNANSWERED` because it is
half of the v8 index's `WHERE` and must be the same bytes as the reads that land in PR C, and
`PERSON_MEMORY` because a reserved pair with only one half declared is how the other half gets
re-invented as a bare literal.

**One finding for PR D.** `ios/Tests/TransactionHistoryServiceTests.swift`'s
`everyStoreFailureMapsToTheSameThing` lists the `StoreError` cases by hand and is now one case
short of the "every" in its name. Nothing is wrong today — `TransactionListError.init(mapping:)`
takes `_: Error` and discards it, so there is no exhaustive switch and no build break — but the
list should gain `.NotFound` in PR D, where Swift is touched anyway.

---

# PR B — The memory 🔒

*`merchant_portion` derivation, the `merchant_memory` table, and preview/apply. Engine-only. This is the engine half of US3 — "the app remembers what I told it". `categorize.rs` and `dedup.rs` are **not modified**: the memory is consulted by the store *beside* the categorization stack, before it.*

## Phase 7: Derivation — `merchant.rs` [US3]

**Purpose**: turn a narration into the portion a memory can be keyed on, deterministically, with its known weaknesses written down rather than hidden.

- [x] T041 [P] [US3] Create `fixtures/categorization/merchant_portion.json` per `data-model.md` §7 — narration in, expected portion out, one case per shape named in FR-027a–FR-027e. 🚨 **No real VPA, no real UPI handle, no real account number** (Principle I): every value is synthetic and must look it.
- [x] T042 [P] [US3] Create `core/crates/kaname-core/tests/merchant_portion.rs` with the harness import and the fixture loader, no assertions yet.
- [x] T043 [US3] RED **P3** and **P4** in `core/crates/kaname-core/tests/merchant_portion.rs`: every FR-027d case returns `None`, and the empty string and a whitespace-only string return `None` **without panicking**. Watch both fail.
- [x] T044 [US3] RED **P1** in `core/crates/kaname-core/tests/merchant_portion.rs`: every case in `fixtures/categorization/merchant_portion.json` (FR-027e), driven from the file so adding a case adds an assertion. Watch it fail.
- [x] T045 [US3] RED 🚨 **P2** in `core/crates/kaname-core/tests/merchant_portion.rs`: the four `UPI-SWIGGY-*` shapes yield **one identical portion**. This is the assertion that catches SC-008's failure mode — a memory that can only ever match the row it came from. Watch it fail.
- [x] T046 [US3] RED **P5** in `core/crates/kaname-core/tests/merchant_portion.rs`: research R15's three priced limitations asserted **as they actually behave** — `NEFT-N123-EMPLOYER…` → `n123 employer`, `MTR1924 LALBAGH` → `lalbagh`, `swiggy` ≠ `swiggy bangalore` — each with a comment naming R15. A fixture that encodes known weaknesses is what tells the next person when they change.
- [x] T047 [US3] RED **P6** in `core/crates/kaname-core/tests/merchant_portion.rs`: `fixtures/dedup/cross_source/basic.json` still passes **unedited** — `normalize_narration` did not move and dedup did not change shape underneath this.
- [x] T048 [US3] GREEN: create `core/crates/kaname-core/src/merchant.rs` with a free `fn merchant_portion(&str) -> Option<String>` implementing the four ordered steps of `data-model.md` §4 — normalize via the **unchanged** `dedup::normalize_narration`; split on the separator set, in which `@` and `.` are **deliberately not separators**; drop the 69-word closed stop-list plus pure-numeric and single-character segments; keep the first **2** segments. Register the module in `core/crates/kaname-core/src/lib.rs`. ⚠️ Do not modify `categorize.rs` or `dedup.rs`.
- [x] T049 [US3] Export `merchant_portion` over `#[uniffi::export]` in `core/crates/kaname-core/src/ffi.rs` (FR-021, FR-076 — the Swift side derives nothing).
- [x] T050 ⚠️ **BUILD** — `make core-xcframework` then `make ios-gen`. FFI surface changed.
- [x] T051 **DELIBERATE BREAK** — change the kept-segment count from 2 to 3 in `core/crates/kaname-core/src/merchant.rs`. Expected: **P2 RED** (the four Swiggy shapes stop collapsing to one portion). Revert, then `make core-test` — P1–P6 green.

**Checkpoint**: a narration reliably yields a portion, and its limits are recorded in tests.

## Phase 8: The memory table and its consultation [US3]

**Purpose**: one row per merchant portion, written in the same transaction as the correction, consulted *before* the stack.

- [x] T052 [P] [US3] Create `core/crates/kaname-core/tests/merchant_memory.rs` with the harness import, no assertions yet.
- [x] T053 [US3] RED **M3** in `core/crates/kaname-core/tests/merchant_memory.rs`: correct the same merchant twice to different categories → `merchant_memory` has exactly **one** row and it names the **second** category (FR-031, FR-033). Watch it fail.
- [x] T054 [US3] RED **M11** in `core/crates/kaname-core/tests/merchant_memory.rs`: `list_merchant_rules()` returns the same thing before and after memories exist (FR-035, plan § *Judgement calls* §1 — a memory is not a rule and must not appear as one).
- [x] T055 [US3] GREEN: upsert into `merchant_memory` inside `set_transaction_category`'s existing transaction when `remember` is true, in `core/crates/kaname-core/src/store.rs`. The `PRIMARY KEY` is what makes M3 true — an `INSERT OR REPLACE` on the portion, not an append.
- [x] T056 **DELIBERATE BREAK** — drop the `PRIMARY KEY` from `merchant_memory` in the v8 migration in `core/crates/kaname-core/src/store.rs` and re-migrate a fresh store. Expected: **M3 RED** (two rows for one merchant). Revert, re-migrate, re-run.
- [x] T057 [US3] RED **C4** (deferred from PR A) in `core/crates/kaname-core/tests/store_correction.rs`: correct to `None` with `remember: true` → `memory_formed == false` and `merchant_memory` unchanged. Nothing is remembered about a deliberate blank.
- [x] T058 [US3] RED **C7** (deferred from PR A) in `core/crates/kaname-core/tests/store_correction.rs`: a category and a memory are written in one transaction — force a failure on the second write and assert the first is rolled back.
- [x] T059 [US3] GREEN: make the correction-plus-memory write atomic in `core/crates/kaname-core/src/store.rs`; C4 and C7 green.
- [x] T060 [US3] RED **M1** in `core/crates/kaname-core/tests/merchant_memory.rs`: form a memory, import a new statement containing that merchant → the new rows land in the remembered category with `categorised_by = 'PERSON_MEMORY'` (FR-030).
- [x] T061 [US3] RED **M2** in `core/crates/kaname-core/tests/merchant_memory.rs`: a memory beats a CC narration rule **and** a T1 builtin for the same row (FR-032). This test is what plan § *Judgement calls* §2 actually encodes — write the judgement call's sentence into the test as a comment.
- [x] T062 [US3] GREEN: consult `merchant_memory` in `core/crates/kaname-core/src/store.rs` **beside** the categorization stack and **before** it, per `contracts/engine-categorize.md` §5. ⚠️ Do not add a tier to `categorize.rs`; a memory is not a rule.

**Checkpoint**: the app remembers, and the memory wins.

## Phase 9: Preview and apply — the second action [US3]

**Purpose**: state the blast radius, then apply exactly the set that was previewed — nothing more, nothing else.

- [x] T063 **DELIBERATE BREAK** — consult the memory *after* the categorization stack in `core/crates/kaname-core/src/store.rs`. Expected: **M2 RED** (the CC rule wins). Revert. This is the break that proves ordering is behaviour, not style.
- [x] T064 [US3] RED **M4** in `core/crates/kaname-core/tests/merchant_memory.rs`: `preview_memory_application` never includes a `'PERSON'` row (FR-035d) — a hand-corrected row is not collateral.
- [x] T065 [US3] RED **M5** in `core/crates/kaname-core/tests/merchant_memory.rs`: `preview` → `apply` writes exactly the previewed rows with `'PERSON_MEMORY'` and returns the previewed count.
- [x] T066 [US3] RED 🚨 **M7** in `core/crates/kaname-core/tests/merchant_memory.rs`: `preview` → `apply` with a **trimmed** id list returns `StaleSet` and writes nothing. This is the assertion that proves FR-035b is enforced **in the engine**, so that no present or future interface can turn the second action into a bulk edit.
- [x] T067 [US3] RED **M6** in `core/crates/kaname-core/tests/merchant_memory.rs`: `preview` → delete/insert a matching row → `apply` returns `StaleSet` and **writes nothing** (FR-035f).
- [x] T068 [US3] RED **M8** in `core/crates/kaname-core/tests/merchant_memory.rs`: `apply` twice — the second writes 0 and changes nothing (FR-035h).
- [x] T069 [US3] RED **M9** in `core/crates/kaname-core/tests/merchant_memory.rs`: `apply` where one row's write would fail → nothing is written (FR-035g).
- [x] T070 [US3] RED **M10** in `core/crates/kaname-core/tests/merchant_memory.rs`: a memory's category is deleted → the foreign key means the memory cannot exist → nothing is applied (FR-034).
- [x] T071 [US3] GREEN: implement `preview_memory_application(portion) -> MemoryImpact` and `apply_memory_application(portion, expecting: Vec<String>) -> Result<u32>` in `core/crates/kaname-core/src/store.rs`. `apply` **recomputes the affected set and compares it for set equality** with `expecting` — not a subset check, not a length check — and returns `StaleSet` on any difference (`contracts/engine-categorize.md` §2.4).
- [x] T072 [US3] Export both functions and the `MemoryImpact` / `StaleSet` types over `#[uniffi::export]` in `core/crates/kaname-core/src/ffi.rs`.
- [x] T073 ⚠️ **BUILD** — `make core-xcframework` then `make ios-gen`. FFI surface changed.
- [x] T074 **DELIBERATE BREAK** — change the set-equality check in `apply_memory_application` to a **subset** check. Expected: **M7 RED**, M5/M6/M8 green. Revert. (A subset check is the shape this bug takes in the wild: it looks careful and it silently permits a trimmed list.)
- [x] T075 **DELIBERATE BREAK** — remove the recompute-and-compare entirely and apply `expecting` verbatim. Expected: **M6 RED**. Revert.
- [x] T076 **GATE** — `make core-fmt && make core-lint && make core-test`. ⚠️ Never concurrently with `make ios-test`.

## PR B — RECORDED

*What the queue said would happen, what actually happened, and the five places they differed.*

**Baseline (PR A close)**: 324 tests. **After PR B**: **348 tests** (+24), `make core-fmt` /
`make core-lint` clean, `make core-test` green in one clean run (exit 0, no `FAILED`). Six
derivation tests, two `merchant.rs` unit tests, eleven memory tests (M1–M11), C4 and C7, and the
three shared `tests/common` assertions that every new integration-test binary re-runs.
**No tracked Swift file touched** — `ios/Generated/` and `ios/Frameworks/*.xcframework` are
git-ignored build artifacts, so the two mandatory `make core-xcframework && make ios-gen` runs
(T050, T073) leave the tree clean.

**The five places the queue and reality differed. Every one of them is the queue being wrong in a
way that would have looked like success.**

1. 🚨 **T051's break turns P1 and P5 red — not P2, and P2 is what the queue named.** Keeping 3
   segments instead of 2 changes `synthetic cafe` → `synthetic cafe coffee` and `n123 employer` →
   `n123 employer private`, but the four `UPI-SWIGGY-*` shapes each have exactly **one** surviving
   segment, so they still collapse to one portion and **P2 stays green**. Had the break been run
   and only P2 watched, it would have read as "the break didn't take" and the maximum count would
   have looked untested. The break that *does* reach P2 was run instead and is the more
   informative one: **stop discarding reference tokens** (drop the entirely-digits rule, raise
   `REFERENCE_DIGITS` out of reach) and P2 fails with `swiggy 123456` against `swiggy` — SC-008's
   exact failure mode, a memory that can only ever match the row it came from. **What actually
   protects SC-008 is the reference-token discard, not the segment count.** Both breaks are
   recorded; both were reverted.
2. **T056's break fails harder than predicted, and better.** Dropping the `PRIMARY KEY` does not
   produce "two rows for one merchant": SQLite refuses the write outright with `ON CONFLICT clause
   does not match any PRIMARY KEY or UNIQUE constraint`, so **M3 goes red at the first
   correction**. The constraint is not merely relied upon by the upsert, it is *required* by it —
   a stronger guarantee than the queue assumed, and one that cannot decay silently.
3. **C7 passed on its first run**, because T055's implementation was already one transaction. A
   test that has never been red proves nothing, so the atomicity was broken on purpose — commit
   the row update, then open a second transaction for the memory — and C7 went red with
   `(Some("GROCERIES"), Some("PERSON")) != (Some("FOOD_AND_DINING"), Some("T1_SOURCE_CATEGORY"))`:
   the correction survived a failed memory write. Reverted. T059 was therefore satisfied by T055
   rather than by new code, which is recorded rather than dressed up as a separate step.
4. ⚠️ **M6 cannot be staged by importing another matching row.** The first attempt did exactly
   what T067 says ("delete/insert a matching row") by importing one — and the assertion "a refused
   apply writes nothing" failed **for a legitimate reason**: an import re-categorizes the
   account's undecided rows, so the *import* applied the memory to two of the previewed rows
   before `apply_memory` was ever called. The test cannot tell that apart from a partial apply.
   M6 now removes a row instead (`is_deleted = 1`, direct SQL — the route the public API
   deliberately does not offer), and the comment in the test says why. **This is also a real fact
   about the feature**: a preview goes stale simply because an import happened, and `StaleSet` is
   what a person meets when it does.
5. **A trigger body cannot carry a bound parameter** (`trigger cannot use variables`), so M9's
   "refuse one row's write" trigger inlines the id with `format!`. A test-harness detail, recorded
   because the failure message names neither the trigger nor the parameter.

**Two naming discrepancies in the design documents, resolved toward the contract.**
`tasks.md` T071/T074 call the second function `apply_memory_application`;
`contracts/engine-categorize.md` §2.4 and `data-model.md` §3.4 both call it **`apply_memory`**,
and that is what shipped. Likewise T072 and T049 say to export in `src/ffi.rs`: the free
`merchant_portion` **is** exported there (as the owned-`String` wrapper, following
`detect_issuer`'s established shape, with `merchant::merchant_portion(&str)` staying pure for
Rust callers), but `Store`'s methods and the `uniffi::Record` types are exported from `store.rs`,
exactly as `data-model.md` §3.4 says — there was no choice to make.

**One documentation defect, carried rather than hidden.** Research R14 calls the stop-list "69
words" and then lists **76**. The list is what is fixed in full, so the list is what shipped; a
unit test now pins `STOP_WORDS.len() == 76`, asserts no duplicates and asserts every entry is
lower-case (an upper-case entry would silently never match, since segments are lower-cased by
normalization). `merchant.rs`'s doc comment names the discrepancy so the next reader does not
"fix" the list to match the prose.

**Three decisions worth carrying into PR C and PR D.**

- **`apply_memory`'s write is guarded on `PERSON`, not on `ENGINE_MAY_DECIDE`** — deliberately.
  This write *is* a person deciding, so it must be able to replace an earlier `PERSON_MEMORY`
  (FR-031a: a later offer includes the rows the previous one changed), while never touching a
  hand correction. Spelling it `AND categorised_by IS NOT '{PERSON}'` also keeps
  `every_category_update_in_the_store_is_guarded` honest: the statement says whose decision it is
  in the same words the affected-set predicate does. Using `ENGINE_MAY_DECIDE` here would have
  made a second offer silently write 0 rows.
- **The affected set is computed by one function, `affected_by_memory_in`**, called by both the
  preview and the apply. The staleness check is only meaningful if the two answer the same
  question; two spellings would make the agreement a coincidence. The portion match cannot be
  SQL — it is derived in Rust per row — so the query narrows and Rust matches.
- **`categorize.rs` and `dedup.rs` are untouched**, as FR-027c requires. The memory is read in
  `categorize_account_in` *before* the stack (`load_merchant_memories` beside the catalog and the
  rules), and P6 plus the unchanged `fixtures/dedup/cross_source/basic.json` and
  `fixtures/categorization/basic.json` are the proof.

**Deferred, with reasons.** C5 still belongs to PR C (T085) — the uncategorized set does not exist
yet. `HistoryRow.category_id`, `HistoryQuery.uncategorized_only` and `uncategorized_count()` are
untouched here; PR B added no read-side narrowing and no plan-shape assertion.

---

# PR C — The read side 🔒

*The uncategorized narrowing, `uncategorized_count()`, and the plan-shape assertions. Engine-only. This is the engine half of US4 — "show me only what I have not decided yet".*

## Phase 10: The narrowed query [US4]

**Purpose**: one query, two axes, and a count that cannot drift from the page it counts.

- [x] T077 [US4] Add `uncategorized_only: bool` (defaulting to `false`) to `HistoryQuery` in `core/crates/kaname-core/src/model.rs`. A default of `false` is what makes FR-046 cheap: every existing caller keeps its exact behaviour.
- [x] T078 [US4] RED **H1** in `core/crates/kaname-core/tests/history_paging.rs`: with `uncategorized_only: false`, pages are **byte-identical** to today (FR-046). Green today by construction — written first so T091's and PR F's breaks have something to turn red.
- [x] T079 [US4] RED **H2** in `core/crates/kaname-core/tests/history_paging.rs`: with `uncategorized_only: true`, the result is exactly `LIVE ∧ UNANSWERED` — and a `'PERSON'` deliberate blank is **excluded** (plan § *Spec amendments* §1). Watch it fail.
- [x] T080 [US4] RED **H3** in `core/crates/kaname-core/tests/history_paging.rs`: the narrowing composes with `account_id` — both axes, one query (FR-039).
- [x] T081 [US4] RED **H4** in `core/crates/kaname-core/tests/history_paging.rs`: paging across a narrowed set is stable and complete — no row seen twice, none skipped (FR-040).
- [x] T082 [US4] RED **H6** in `core/crates/kaname-core/tests/history_paging.rs`: `HistoryRow.category_id` is populated and matches `category_name`'s category. (This is what lets the picker mark the current category by id rather than by display-name match — platform rule K3.)
- [x] T083 [US4] RED **H5** in `core/crates/kaname-core/tests/history_paging.rs`: `uncategorized_count()` equals the number of rows a full narrowed walk returns. The two definitions cannot drift because they are spelled from the same `UNANSWERED` constant — this test is the proof, and it is the reason T011 spells it once.
- [x] T084 [US4] GREEN: narrow `PAGE_SQL` and add `uncategorized_count()` in `core/crates/kaname-core/src/store.rs`, both referencing the `UNANSWERED` constant from T011. No second spelling of the predicate anywhere.
- [x] T085 [US4] RED then GREEN **C5** (deferred from PR A) in `core/crates/kaname-core/tests/store_correction.rs`: a corrected row is **not** in the uncategorized set, whether it carries a category or a deliberate blank (plan § *Spec amendments* §1). C5 could not be written in PR A because the uncategorized set did not exist; this task is where the deferral is paid.
- [x] T086 [US4] Export `uncategorized_count` and the new query field over `#[uniffi::export]` in `core/crates/kaname-core/src/ffi.rs`.
- [x] T087 ⚠️ **BUILD** — `make core-xcframework` then `make ios-gen`. FFI surface changed.

**Checkpoint**: the narrowed read exists and its count is the same question asked once.

## Phase 11: Plan shape [US4]

> ⚠️ **The trap in this phase.** The count's *optimal* plan **is** a `SCAN` — of a partial index containing only the rows being counted, which is exactly what makes it get cheaper as the person works through the worklist. `history_perf.rs::s1` carries a blanket "no step contains SCAN" rule. **Q3 must not inherit it.** A copy-paste of `s1` here is red for the correct query, and the tempting fix is to weaken `s1`. Do neither: `s1` and `s2` are not edited, not weakened and not excepted.

- [x] T088 [US4] RED **Q1** in `core/crates/kaname-core/tests/history_perf.rs`: `s1` and `s2` are **unchanged and still green** after v8 — `PAGE_SQL`'s plan is byte-identical (research R13). Run them; do not touch them.
- [x] T089 [US4] RED **Q2** in `core/crates/kaname-core/tests/history_perf.rs`: the narrowed page's plan contains a `SEARCH` on a **named** index and no `TEMP B-TREE`.
- [x] T090 [US4] RED ⚠️ **Q3** in `core/crates/kaname-core/tests/history_perf.rs`: `uncategorized_count()`'s plan **names `idx_txn_unanswered_account_date`**. Assert the index **name**, not the absence of `SCAN`. Add a comment above the test saying why, so the next person who copies `s1` into this file stops.
- [x] T091 **DELIBERATE BREAK** — drop `idx_txn_unanswered_account_date` from the v8 migration in `core/crates/kaname-core/src/store.rs` and re-migrate. Expected: **Q3 RED, `s1` and `s2` still GREEN**. Revert and re-migrate. (If `s1` also goes red, the index is doing something Q1 said it would not.)
- [x] T092 [US4] Record in the PR description: research R13's plans were measured with **system SQLite 3.45.3, not the SQLCipher build**. Q1–Q3 assert against the **real store**, which is what actually settles it — and say plainly what they do not settle (see T178).
- [x] T093 **GATE** — `make core-lint && make core-test`. ⚠️ Never concurrently with `make ios-test` — `s5` is wall-clock.


---

## PR C — RECORDED

*What the queue said would happen, what actually happened, and the four places they differed.*

**Baseline (PR B close)**: 348 tests. **After PR C**: **358 tests** (+10) — H1–H6, Q1–Q3 and the
deferred C5. `make core-lint` clean, `make core-test` green in one run (19 binaries, 0 failures),
`make lint` clean (99 files, 0 violations) and `make ios-test` **TEST SUCCEEDED** (33 UI tests).

**T092 — what Q1–Q3 settle, and what they do not (the record T178 asks for).** Research R13's plan
survey was taken on **system SQLite 3.45.3**, not the SQLCipher build the engine links. Q1–Q3 now
assert against the **real store**, and they reproduce R13's predicted shapes exactly:

```text
Q2 narrowed page: ["SEARCH t USING INDEX idx_txn_unanswered_account_date (account_id=? AND date<?)"]
Q3 count:         ["SCAN transactions USING INDEX idx_txn_unanswered_account_date"]
```

That settles **three** queries — `PAGE_SQL`, `PAGE_SQL_UNANSWERED` and `UNCATEGORIZED_COUNT_SQL` —
on one corpus shape (8 accounts, 10,000 rows) at one SQLCipher version on one machine. It does not
settle the rest of R13's survey, any other statement in the store, or how any of them plan on a
device. Three green tests are not a survey and are not recorded as one.

**The four places the queue and reality differed.**

1. 🚨 **PR C could not be engine-only, and the queue says it is.** `HistoryRow` gaining
   `category_id` (T082) breaks **every Swift memberwise construction of it** — ten call sites
   across seven files — because uniffi generates an initializer with no default for a new field.
   The alternative was `#[uniffi(default = None)]`, which would have kept the Swift tree
   compiling untouched; it was **rejected**, because a test double that can silently omit a fact
   the engine always populates is exactly the quiet failure this repository keeps finding. The ten
   sites now state their category id, and the two that carry a name carry an id beside it.
2. ⚠️ **`Q2` does not gate the v8 index — only `Q3` does.** T091's break (drop
   `idx_txn_unanswered_account_date`) was run and turned **Q3 red with `s1`, `s2` and `Q1` green**,
   as predicted. What was *not* predicted: **Q2 also stayed green**, because the narrowed page
   falls back to `idx_txn_live_account_date`, which is still a `SEARCH` on a named index with no
   `TEMP B-TREE`. Q2 is a gate on the *shape* of the narrowed read, not on the index existing. If
   Q3 is ever weakened, nothing else in the suite notices the index going missing.
3. **The predicate is spelled once by a macro, not by the constant.** T084 says both readers
   reference the `UNANSWERED` constant; a `const` cannot be interpolated into another `const`, so
   `PAGE_SQL` and `PAGE_SQL_UNANSWERED` are two expansions of one new `page_sql!` macro and the
   count is `UNCATEGORIZED_COUNT_SQL`, built from `live_predicate!()` + `unanswered_predicate!()`.
   There is still exactly one spelling of each rule in the crate; `UNANSWERED` keeps its
   `#[allow(dead_code)]` because it is now a *name* for the rule rather than a reader of it.
   **H1 pins `PAGE_SQL`'s full text** so the refactor could not have changed a byte in silence —
   it is the assertion that made the macro safe to introduce.
4. **T085's C5 passed on its first run**, because T084 had already satisfied it. It was therefore
   broken on purpose — the provenance arm removed from `unanswered_predicate!()` — and **C5 and H2
   both went red**, with H2's message naming the deliberate blank. ⚠️ **H5 stayed green under that
   break**, correctly: it asserts the count and the list agree, and under the break they agreed on
   the wrong set. H5 is a drift gate, never a correctness one, and reading it as the latter would
   be a mistake in PR F.

**One FFI-surface note, repeating PR B's.** T086 says to export in `src/ffi.rs`;
`#[uniffi::export] impl Store` in `store.rs` already covers every `pub fn`, so `uncategorizedCount`
and `HistoryQuery.uncategorizedOnly` (with its Swift default `= false`, which is why the one
shipped Swift caller needed no edit) appeared in the bindings from the mandatory
`make core-xcframework` → `make ios-gen` run (T087). There was no separate export to write.

⚠️ **The wall-clock gates were re-run on a machine under load, and the baseline was measured
rather than assumed.** `make core-test` was green in one clean run; a later re-run of
`history_perf` alone failed `s4` (worst page 73.7 ms against a 25 ms budget, median 4.4 ms — one
outlier page) and `s5`, on a host showing **load average 120** with an unrelated `ffmpeg` at 392%
CPU. Rather than declare it noise, `HEAD` was stashed to and measured under the same load: **`s4`
fails there too, and worse — worst page 127.2 ms.** The failure is the machine, not this pull
request, and that is what the comparison is for. `s3`–`s7` are only meaningful on a quiet host.

**Deferred, unchanged.** `018/06`'s three device timings still need a phone (T176), and nothing in
PR C touches them.

---

# PR D — Correcting one transaction 🎯

*The first PR a person can see: `ios/Sources/Categorize/`, the detail surface, the picker, and the tappable row. Delivers US1 (correct one transaction) and US5 (the correction is visible immediately).*

## Phase 12: Widen the audit scope before any code lands there

**Purpose**: four of `import-path-audit.sh`'s ten scans are scoped to `ios/Sources/Transactions/`. New code in `ios/Sources/Categorize/` would be **unwatched** by exactly the scans that exist to watch it. Widen first, prove the widening reaches, then write the code.

- [x] T094 Widen scans **5** (second opinion), **6** (filter persistence), **7** (aggregates) and **8** (`.tint`) in `scripts/import-path-audit.sh` from `TRANSACTIONS_DIR="$SOURCES_DIR/Transactions"` to also cover `ios/Sources/Categorize/` (plan § *Judgement calls* §6). Widening the scope of a scan is not weakening it, so FR-056 / SC-022 hold. ⚠️ The scans must tolerate the directory not existing yet, and ⚠️ must not use `grep -c` or end a pipeline in a bare `grep` under `set -euo pipefail`.
- [x] T095 Run `make import-audit` — all ten scans green with the widened scope, before `ios/Sources/Categorize/` contains anything.
- [x] T096 **DELIBERATE BREAK** — create a throwaway `ios/Sources/Categorize/__scope_probe.swift` containing a `.filter { … }` applied to a returned page and a `.reduce` over `AccountSummary`. Expected: **scans 5/6/7 RED**. Delete the file and re-run. This is the only task that proves the widened scope actually reaches the new directory — a widening that silently missed would look exactly like a clean audit for the rest of the slice.

**Checkpoint**: the new directory is watched before it exists.

## Phase 13: Unit assertions — no simulator, no seeding [US1]

- [x] T097 [P] [US1] RED **U1** in `ios/Tests/CategoryCatalogTests.swift`: `CategoryCatalog.grouped` groups by `Category.classification`, deterministically, for an empty catalog, a single-classification catalog and the full one (K2, K6, FR-017).
- [x] T098 [P] [US1] RED **U3** in `ios/Tests/CategorizeStringsTests.swift`: `CategorizeStrings` contains no banned engine vocabulary — `T1`, `T2`, `stage`, `rule`, `heuristic`, `merchant map`, `provenance`, `tier` — asserted over the **whole table**, not a sample (T3, FR-029, SC-007).
- [x] T099 [P] [US1] RED **U4** in `ios/Tests/TransactionScopeTests.swift`: `TransactionScope` round-trips through `Hashable`/`Codable`, and two scopes differing only in `uncategorizedOnly` are **not equal** and do not collide in the nav stack.
- [x] T100 ⚠️ **BUILD** — `make ios-gen` (three new test files), then `make ios-test`. **Confirm in the test log that all three suites actually RAN and are RED.** `sources: ["Sources/**"]` resolves at generation time; a suite that never ran reports success. This bit 019 twice. ⚠️ Never concurrently with `make core-test`.

## Phase 14: The new surface [US1] [US5]

- [x] T101 [US1] Create `ios/Sources/Categorize/CategorizeStrings.swift` (rules T1–T4). ⚠️ `uncategorized` is **referenced** from `TransactionListStrings.uncategorized` (`TransactionListStrings.swift:65`), never redeclared — two spellings of that word is precisely the defect FR-002 / SC-002 exists to prevent. ⚠️ swift-format `[Spacing]` rejects trailing inline comments; put explanations above the line.
- [x] T102 [US1] Create `ios/Sources/Categorize/TransactionScope.swift` — `struct TransactionScope: Hashable, Codable { var filter: AccountFilter; var uncategorizedOnly: Bool }` (contract §2). `AccountFilter` is **reused unchanged**, not reimplemented. It lives here rather than beside `AccountFilter` because `TransactionListModels.swift` is at 332 lines and next at risk.
- [x] T103 [US1] Create `ios/Sources/Categorize/CategoryCatalog.swift` — `grouped(_:)` is **pure**: `[Category]` in, grouped array out, no engine call, no state (K2, FR-076).
- [x] T104 ⚠️ **BUILD** — `make ios-gen` (three new Swift files), then `make ios-test` — U1, U3 and U4 green.
- [x] T105 [US1] Create `ios/Sources/Categorize/CategorizeService.swift` — the actor seam of contract §1. Every method is a **thin pass-through to one engine call**: it must not filter, count, sum, group, sort by a derived key, or take a second opinion about anything the engine returned (FR-076, FR-077, FR-078). `uncategorizedCount()` in particular returns the engine's number verbatim.
- [x] T106 [US1] Create `ios/Sources/Categorize/TransactionDetailView.swift` (rules D1–D6): the transaction's own facts and its current category or the app's one word for having none (D1, D2); no engine vocabulary (D3, FR-029); `Decimal` formatting with tabular figures carried from 018 (D4); Liquid Glass unconditionally — no `#available(iOS 26, *)`, no `.ultraThinMaterial`, `.glassProminent` only via `Theme.swift` (D5, FR-063, SC-021); one primary action reachable without scrolling at default Dynamic Type (D6, FR-004).
- [x] T107 [US1] Create `ios/Sources/Categorize/CategoryPickerView.swift` (rules K1, K3–K7): every category the engine knows, grouped by the **engine's** classification (K1, FR-016); the current category marked by `HistoryRow.category_id`, **never** by display-name match (K3, FR-005); choosing dismisses and the new category is visible without a manual refresh (K5, FR-006, SC-003).
- [x] T108 ⚠️ **BUILD** — `make ios-gen` (three new Swift files).
- [x] T109 [US1] Make the transaction row a `NavigationLink` in `ios/Sources/Transactions/TransactionRowView.swift` (R1, FR-003). ⚠️ The row's **visual layout does not change** — no chevron, no inset (R3, FR-046) — and the tap target is the full row, ≥44×44pt (R4, FR-062).
- [x] T110 [US1] Preserve the row's combined accessibility element (`.accessibilityElement(children: .combine)`, `TransactionRowView.swift:36-38`) and assert it in `ios/Tests/TransactionAccessibilityTests.swift`: the sentence VoiceOver reads must **not** fragment into per-label pieces because the row gained a link (R2, FR-060, SC-016).
- [x] T111 [US1] Change `ios/Sources/RootView.swift:16-33`'s `.navigationDestination(for: AccountFilter.self)` to `for: TransactionScope.self`. The nav **value type** changes; the nav **behaviour** does not. ⚠️ There is exactly **one** destination for the transaction list — a second `.navigationDestination` for a "just uncategorized" list would give the same screen two identities and two back-stack behaviours.
- [x] T112 ⚠️ **BUILD** — `make ios-gen` then `make ios-test`.

**Checkpoint**: a person can open a transaction and change its category.

## Phase 15: Seeded UI [US1] [US5]

- [x] T113 [US1] Add the `unfiled` scenario to `ios/Sources/DebugSeed/SeedScenarios.swift` (inside its existing `#if DEBUG`, appended to `declared` at line 116) — uncategorized rows across at least one statement (FR-066). Declare its expectations in `ios/Sources/DebugSeed/SeedExpectations.swift`. ⚠️ The declared uncategorized count must be asserted against the **engine's** answer, not the author's belief about what the engine will do. ⚠️ Pin `en_IN`, keep amounts under ₹1,00,000, at least one statement.
- [x] T114 ⚠️ **BUILD** — `make ios-gen`, then `make ios-test`. ⚠️ A seeded store **outlives** the suite that wrote it: reset with the `empty` scenario in teardown.
- [x] T115 [US1] [US5] **X1** and **X2** in a new `ios/UITests/CategorizeDetailUITests.swift`: tap a row → the detail surface appears with that row's facts; change a category → the detail surface **and** the list both show the new one without a manual refresh (FR-006, SC-003). ⚠️ Launch via `ios/UITests/SeededLaunch.swift` with the **bare** `KANAME_SEED_SCENARIO` key — the `TEST_RUNNER_` prefix is for app-hosted unit tests and is silently never delivered to a UI test. ⚠️ The contract names scenario `basic`, which **does not exist** — the declared set is `empty`, `small`, `deep`, `barren`. Use `small` and record the contract erratum in the PR description. ⚠️ Never assert a total by counting cells: a `List` renders a screenful, and a date heading is a cell too.
- [x] T116 ⚠️ **BUILD** — `make ios-gen` (new UI test file), then `make ios-test`, and **confirm the new suite ran**. Note that `KanameUITests` does not glob `Sources/**`: it hand-lists `UITests/**` plus `SeedScenarios.swift` and `SeedExpectations.swift`, so a new UI test file still needs generation and a new *seed* file needs the target's list checked.
- [x] T117 **DELIBERATE BREAK** — reinstate the defect: make `CategoryPickerView` resolve the current category by display-name match instead of by `category_id` (K3), and give two categories the same display name in the catalog double. Expected: the K3 assertion and X2 **RED**. ⚠️ Revert per non-negotiable 7 — commit the fix first, or `cp -R ios/Sources /tmp/sources-backup` and restore from the copy. `git checkout -- ios/Sources` reverts to `HEAD` and takes the uncommitted fix with it. Then `make ios-gen`.

## Phase 16: PR D close-out

- [x] T118 [US1] Implement and assert **K4** — "no category" is an **offered choice**, not only an implicit state (FR-007) — in `ios/Sources/Categorize/CategoryPickerView.swift` with the assertion in `ios/Tests/CategoryPickerTests.swift`. ⚠️ K4 has **no named X assertion** in contract §11.2; this task is its only coverage, which is why it is called out here rather than folded into T107. Run `make ios-gen` for the new test file.
- [x] T119 [US1] Accessibility over the detail surface and the picker in `ios/UITests/SeededAccessibilityUITests.swift`: default and XXXL Dynamic Type, Light and Dark, VoiceOver reachable, ≥44pt targets (K7, R2, R4, FR-060–FR-062, SC-016). ⚠️ Exclude `.contrast` everywhere (`019/01`) and `.textClipped` / `.dynamicType` at XXXL (`019/03`); ⚠️ a label cannot demonstrate a truncation — XCUITest reports a `Text`'s string, not its glyphs — so if a long category name must be shown not to clip, geometry has to carry it (`ios/Tests/GeometryFixtureTests.swift`).
- [x] T120 Confirm `ios/Sources/Import/ImportService.swift` is **unchanged**: `git --no-pager diff --stat origin/main... -- ios/Sources/Import/ImportService.swift` is empty (FR-073, SC-023). It is at 398 of 400 lines; zero lines may be added. Confirm no new file is over budget via `make lint`.
- [x] T121 **GATE** — `make lint && make ios-test && make import-audit`. ⚠️ Never concurrently with `make core-test`, and `make ios-test` cannot run concurrently with itself.


---

## PR D — RECORDED

*What the queue said would happen, what actually happened, and the six places they differed.*

**Baseline (PR C close)**: 358 core tests, 33 UI tests. **After PR D**: **39 UI tests** and five new
unit suites (`CategoryCatalogTests`, `CategorizeStringsTests`, `TransactionScopeTests`,
`CategoryPickerTests`, `SeedCategoryExpectationTests`). `make lint` clean (**111 files**, 0
violations), `make import-audit` **ten scans green with the widened scope**, `ImportService.swift`
**unchanged at 398 lines** (T120: `git diff` empty), and every new file inside the 400-line limit.

**The six places the queue and reality differed.**

1. 🚨 **The widened scan forbids the picker from sorting the catalog — and it is right.** The
   first draft of `CategoryCatalog.grouped` sorted each group's categories by name; scan 5 bans
   `\bsorted\b` in the directories it watches, and widening it to `Categorize/` (T094) is what
   asked the question. `list_categories()` already reads `ORDER BY rowid`, so the catalog arrives
   in one fixed sequence every launch and a Swift-side sort would have been a second opinion about
   an order the engine settled — 018's whole lesson, in miniature. The grouping now **preserves**
   the engine's order, and U1's determinism case was rewritten from "any order it arrives in" to
   "the same catalog, twice, in the engine's own order", which is the property that actually
   matters and the one a careless `Dictionary(grouping:)` breaks.
2. 🚨 **A row that becomes a link stops being a `StaticText` and becomes a `Button`.** Adding the
   `NavigationLink` turned **018's `SeededTransactionListUITests` red**, which read exactly like
   R2 being violated — "the row lost its combined element". It had not: probing the tree showed
   the whole sentence intact on the cell's **button**, with the description, account, category and
   amount still underneath it as separate texts. Nothing a person hears changed; what changed is
   the element *kind*, and 018's helper identified a row by "the first `StaticText` inside the
   cell". `SeededLaunch.visibleLabels` now reads the sentence wherever it is. ⚠️ Both modifier
   placements — the combine on the link, and on the link's content — were measured and behave
   identically, so the placement is **not** load-bearing and the comment says so rather than
   inventing a rule.
3. 🚨 **T110's source scan passed while the behaviour regressed.** It asserts the row's source
   contains `.accessibilityElement(children: .combine)` and its label — which it did, throughout.
   Only the seeded run could tell the difference. The scan is kept (it catches the
   `.opacity(0)` hidden-link trick, which would pass a screenshot and leave an empty second
   element on every row) but it is **not** the R2 gate, and the queue implied it was.
4. 🚨 **The system auditor found four real Dynamic Type defects on the new surfaces, at the
   default text size, in Light and in Dark** — the first audit ever run against them, exactly the
   return 019 was bought for. Each was watched, fixed and re-run: a `Section("string")` header
   ("User will not be able to change the font size of this element"); a `Text` carrying a bare
   `.accessibilityLabel` (the category value — fixed by drawing it as a *fact* like the other
   four, so the screen has one way of stating a fact instead of two); a prominent `Button` inside
   a `List` row (fixed by moving the action into a `.safeAreaBar`, which also satisfies D6 at
   **every** text size rather than only the default one); and — the one that took four attempts —
   a **titled toolbar button**. `Button("Cancel")`, `Button { } label: { Text }`, and dropping the
   redundant `.buttonStyle(.glass)` all failed; the same button with an SF Symbol and a spoken
   label passes. ⚠️ A titled toolbar button appears to be flagged by the system regardless of how
   its label is built, and no other audited screen in this repository has one.
5. ⚠️ **T117's break turns the K3 unit assertion red — and X2 stays GREEN.** The queue predicted
   both. X2 changes a category; the *mark* on the current one is not on its path, so the display-
   name defect is invisible to it. Only `CategoryPickerTests` catches it, which is the entire
   reason K3 was extracted onto `CategoryChoice.isCurrent` as a pure rule instead of living
   privately inside the view. (Reverted from `/tmp/sources-backup-020`, per non-negotiable 7 — the
   fix was uncommitted, so `git checkout -- ios/Sources` would have taken it.)
6. **The contract's `basic` scenario does not exist** (erratum, as T115 anticipated): the declared
   set is `empty`, `small`, `deep`, `barren` and now `unfiled`. X1/X2 use `small` — one account,
   six rows, every one of them unanswered, which is the starting position both need.

**Three smaller things worth carrying.**

- **PR D could not begin with a RED that runs.** U1/U3/U4 name types that do not exist, and a
  compile error stops the whole target, so nothing runs and "confirm the suites RAN" (T100) is
  unsatisfiable. Deliberately wrong stubs were written first — a `CategorizeStrings` saying
  "Stage 2 rule applied", a `TransactionScope` ignoring its own narrowing, a `CategoryCatalog`
  putting everything in one group — and **all three suites ran and failed for their intended
  reasons** before the real implementations landed.
- **`AccountFilter` gained `Codable`** — one word, no new line, because synthesized `Codable` for
  an enum with associated values cannot be declared in an extension in another file. It is still
  reused, not reimplemented.
- **The `unfiled` seed is checked against the engine, not against itself** (T113). Its declared
  worklist is asserted equal to `uncategorizedCount()` in an *app-hosted unit* test — a UI-test
  bundle links neither the app nor `KanameCore`, so nothing over there can ask the engine
  anything — and the same test runs over **all five** declared scenarios.

⚠️ **The first full `make ios-test` did not complete green, and the reason was measured rather
than assumed.** It took **18,322 s** (five hours) on a host at load average 20–120 and ended with
one failure: `SeededEmptyStateUITests.testTheFilterReachesItsFourStates`, whose message is
`Failed to swipe up CollectionView: Timed out while synthesizing event` — the simulator could not
deliver a gesture. Every test in that suite was re-run and **passed individually**, at 24 s,
985 s, 1,075 s, 1,537 s and 3,145 s for work that normally takes 15–25 s.

✅ **`make ios-test` completed green on a quiet host, after the record above was written.**
**297 unit tests in 59 suites + 39 UI tests, 0 failures, exit 0 — in 782 s.** The same commit that
had taken **18,322 s** and failed one gesture took **13 minutes**: 23× faster, nothing changed but
the load average (18–120 → 3.7). The two runs together are the measurement, and they are kept
side by side deliberately — a five-hour run ending in `Timed out while synthesizing event` is what
this suite looks like on a busy machine, and the next person to see it should re-run before
debugging anything.

**Deferred, unchanged.** `018/06`'s three device timings still need a phone (T176).

---

# PR E — The memory and the second action

*The memory offer and the one-memory application. Delivers the platform half of US3. This is the surface most able to become something the spec forbids, so its rules are asserted twice — once in the view and once, decisively, in the engine.*

## Phase 17: The two new seed scenarios [US3]

> ⚠️ **Both scenarios can be eaten by de-duplication before anyone tests anything.** `repeated` puts one merchant in two statements of one account — vary the amounts or the dates or dedup supersedes the copies and the memory has one row to match. `crossing` puts a ledger and a card across two accounts — 🚨 that is **exactly** the pair cross-source dedup compares (two credit cards never de-duplicate; the source-kind guard compares a ledger against a card and nothing else), so its rows must differ in amount or date or the blast radius will be wrong before it was ever asserted.

- [ ] T122 [US3] Add the `repeated` scenario to `ios/Sources/DebugSeed/SeedScenarios.swift` — one merchant appearing across **two statements of one account** (FR-066), with amounts or dates varied per the warning above.
- [ ] T123 [US3] Add the `crossing` scenario to `ios/Sources/DebugSeed/SeedScenarios.swift` — one merchant across **two accounts**, a ledger and a card, with amounts or dates varied.
- [ ] T124 [US3] Declare both scenarios' expectations in `ios/Sources/DebugSeed/SeedExpectations.swift`, **derived from the engine's answer**, not authored by hand.
- [ ] T125 ⚠️ **BUILD** — `make ios-gen`, then `make ios-test`; confirm `SeedContractUITests` still passes with the expanded declared set.

## Phase 18: The memory offer [US3]

- [ ] T126 [US3] Create `ios/Sources/Categorize/MemoryOfferView.swift` (rules M1–M5): after a correction the app states, in the person's words and showing the **derived merchant portion**, what it will remember (M1, FR-026, FR-026a); the offer can be **declined** and declining leaves the correction fully intact and protected (M2, FR-028); the portion shown is `merchant_portion(narration)` **from the engine** — the Swift side derives nothing (M4, FR-021, FR-076); no engine vocabulary (M5, FR-029).
- [ ] T127 ⚠️ **BUILD** — `make ios-gen`.
- [ ] T128 [US3] **X4** in a new `ios/UITests/CategorizeMemoryUITests.swift` over `repeated`: the memory offer names the merchant portion and can be declined, and the correction survives the decline. Then `make ios-gen` and confirm the suite ran.
- [ ] T129 [US3] Assert **M3** in `ios/Tests/MemoryOfferTests.swift`: when derivation returns nothing, or the correction was to *no category*, the app says plainly there is nothing to remember and offers no memory — it must **not** show an empty or degenerate portion (FR-027d, plan § *Spec amendments* §3). Run `make ios-gen` for the new test file.

## Phase 19: The second action [US3]

> 🚨 Q1-D's second action applies **exactly one memory** — the one just formed. Everything below exists to keep it from becoming a bulk editor.

- [ ] T130 [US3] Create `ios/Sources/Categorize/SecondActionView.swift` (rules S1–S7): states the blast radius **before** the person agrees — how many transactions and which accounts, from `MemoryImpact` (S1, FR-035a, FR-035c, SC-026); offers **no choice of which transactions** — no checkboxes, no multi-select, no "select all" (S2, FR-035b, SC-028); the counts and accounts shown are `MemoryImpact`'s, unmodified — the view does not count, filter or re-derive (S3, FR-043, FR-078); on confirm calls `applyMemory(portion, expecting: impact.transactionIds)` with the ids from the preview it showed, unmodified (S4, FR-035f); declining leaves the memory formed and the correction intact (S7, FR-028).
- [ ] T131 ⚠️ **BUILD** — `make ios-gen`.
- [ ] T132 [US3] **X5** in a new `ios/UITests/CategorizeSecondActionUITests.swift` over `crossing`: the screen states a count **and** account names before confirmation, and there is **no** multi-select control on it. Then `make ios-gen` and confirm the suite ran.
- [ ] T133 [US3] Assert **S5** in `ios/Tests/CategorizeServiceTests.swift` with a doubled service: a `StaleSet` error is surfaced as a person-legible "things changed, take another look", **nothing is written**, and it is **not** retried silently with a fresh set (FR-035f, SC-027).
- [ ] T134 ⚠️ **BUILD** — `make ios-gen` then `make ios-test`; confirm both new suites ran.
- [ ] T135 [US3] Record in the PR description that **S2 is a UI rule and is not the enforcement**. The enforcement is engine-side set equality (`contracts/engine-categorize.md` §2.4, test **M7**, task T066). A UI without a checkbox proves nothing about a future UI (SC-028).
- [ ] T136 [US3] Assert **S6** in `ios/Tests/CategorizeServiceTests.swift`: given a preview that contains no `'PERSON'` row, rows the person corrected by hand are neither counted nor changed — the view merely displays the engine's truth (FR-035d, SC-031, engine test M4).
- [ ] T137 [US3] Record plan § *Judgement calls* §2 where a reader of `MemoryOfferView.swift` will find it: a memory beats a rule, and the offer's wording must not promise more than engine test **M2** asserts.
- [ ] T138 **DELIBERATE BREAK** — make `SecondActionView` pass a **trimmed** id list to `applyMemory`. Expected: the engine returns `StaleSet`, the S5 path fires and **nothing is written**. Revert per non-negotiable 7, then `make ios-gen`. This break proves S4 end-to-end and, more importantly, proves the engine — not the view — is where the guarantee lives.
- [ ] T139 [US3] Accessibility over `MemoryOfferView` and `SecondActionView` in `ios/UITests/SeededAccessibilityUITests.swift`: default and XXXL, Light and Dark, zero findings for the audit types that run (X8, FR-060–FR-062, SC-016). `.contrast` excluded (`019/01`); `.textClipped` / `.dynamicType` excluded at XXXL (`019/03`).
- [ ] T140 **GATE** — `make lint && make ios-test && make import-audit`. ⚠️ Never concurrently with `make core-test`.

---

# PR F — The worklist

*The uncategorized worklist, its single door, and its empty states. Delivers the platform half of US4. This is the PR where a Swift second opinion would be most tempting and where the two widened scans finally earn their keep.*

## Phase 20: Empty states, pure [US4]

- [ ] T141 [US4] RED **U2** in `ios/Tests/TransactionEmptyStateTests.swift`: `EmptyKind.decide` returns the right case for **every row** of `data-model.md` §6 — including the states a seed cannot construct. This is where those states get covered; a state that only a unit test can reach is still a state (FR-042a, FR-042b).
- [ ] T142 [US4] GREEN: `EmptyKind.decide(summaries:filter:uncategorizedOnly:)` in `ios/Sources/Transactions/` gains `allAnswered` and `accountAnswered` and **stays a pure function** (L4).
- [ ] T143 [US4] Assert **L5** structurally in `ios/Tests/TransactionEmptyStateTests.swift`: **no new `AccountSummary` field**. "Live rows exist but the narrowed page is empty" ⇒ all answered — the inference is exact, so a stored flag would be a second source of truth (FR-078).
- [ ] T144 [US4] Implement **L1**, **L2** and **L3** in `ios/Sources/Transactions/TransactionListViewModel.swift`: carry `uncategorizedOnly` into `HistoryQuery`; it **never** filters a page it received (L1, FR-038, FR-076, SC-024); the narrowing composes with the account filter — both axes, one query (L2, FR-039); paging, cursors and infinite scroll are 018's, unchanged (L3, FR-040, FR-046).
- [ ] T145 ⚠️ **BUILD** — `make ios-gen` then `make ios-test`.

## Phase 21: The single door [US4]

- [ ] T146 [US4] Create `ios/Sources/Categorize/UncategorizedEntryPoint.swift` (rules E1–E5): a single door to the worklist, visible from the app's front door (E1, FR-041a); tapping pushes `TransactionScope(filter: .all, uncategorizedOnly: true)` (E4, FR-038).
- [ ] T147 [US4] Assert **E2** in `ios/Tests/UncategorizedEntryPointTests.swift`: the count is **store-wide** and comes from `uncategorizedCount()` — one engine call, no Swift arithmetic, no summing of `AccountSummary` (FR-041b, FR-043, SC-029). 018 deliberately moved the front door's count out of Swift into SQL; this is exactly where it would creep back.
- [ ] T148 ⚠️ **BUILD** — `make ios-gen` (new Swift file and new test file).
- [ ] T149 [US4] **X6** in a new `ios/UITests/CategorizeWorklistUITests.swift` over `unfiled`: the entry point shows a count, and after correcting every row it says the worklist is **finished, in a person's words**, rather than showing "0" (E3, FR-042b, SC-011).
- [ ] T150 [US4] **X7** in `ios/UITests/CategorizeWorklistUITests.swift` over `unfiled`: the narrowed list shows only unanswered rows and composes with an account filter (L1, L2, FR-039).
- [ ] T151 [US4] **X3** in `ios/UITests/CategorizeWorklistUITests.swift` over `unfiled`: set a category to "no category" → the row **leaves the worklist**. ⚠️ Contract §11.2 lists X3 among the detail-surface assertions, but it cannot be observed without the worklist — it is executed here, in PR F, and the PR description says so. This is the platform reflection of engine assertions **C5** and **H2** (a deliberate blank is answered).
- [ ] T152 ⚠️ **BUILD** — `make ios-gen` then `make ios-test`; **confirm the new UI suite ran** rather than reporting success without executing.
- [ ] T153 [US4] Assert **E5** in `ios/Tests/UncategorizedEntryPointTests.swift`: the count refreshes after a correction or a memory application, without a manual reload (SC-030).

## Phase 22: The breaks that only work now

- [ ] T154 🚨 **DELIBERATE BREAK** — filter the received page inside `ios/Sources/Transactions/TransactionListViewModel.swift` instead of passing `uncategorizedOnly` into the query. Expected: `make import-audit` **scans 5 and 6 RED**, and **H1**/**X7** behaviour drifts. Revert per non-negotiable 7. This break is only meaningful because T094 widened the scans — run it and see them fire.
- [ ] T155 **DELIBERATE BREAK** — compute the entry point's count by summing `AccountSummary` in Swift in `ios/Sources/Categorize/UncategorizedEntryPoint.swift`. Expected: `make import-audit` **scan 7 RED** (and E2's assertion red). Revert, then `make ios-gen`.
- [ ] T156 [US4] Assert **L6**: with the narrowing off, 018's list is byte-identical in behaviour and appearance — run `ios/Tests/TransactionList*.swift` and `ios/UITests/SeededTransactionListUITests.swift` **unedited** (FR-046, SC-023). If any of them needed an edit to pass, that is a finding, not a chore.
- [ ] T157 **DELIBERATE BREAK** — reinstate the defect: make the worklist include `'PERSON'` deliberate blanks (drop the `categorised_by IS NULL` arm from the Swift-side scope, or point the query at `LIVE` alone). Expected: **X3 RED** and the platform reflection of **H2** RED. Revert per non-negotiable 7, then `make ios-gen`.
- [ ] T158 [US4] Accessibility over the entry point and the narrowed list in `ios/UITests/SeededAccessibilityUITests.swift`: default and XXXL, Light and Dark, zero findings for the audit types that run (X8). ⚠️ New coverage is not trusted until it has been **watched failing** — T157 is that watch for the worklist, T117 for the picker, T138 for the second action.
- [ ] T159 **GATE** — `make lint && make ios-test && make import-audit`. ⚠️ Never concurrently with `make core-test`.

---

# PR G — Proved, not asserted

*The audits, the sweeps, the break ledger, and the honest deferrals. Delivers US6 (the surfaces a machine checks) and closes US7's hand-back. Nothing new is built here; everything built is shown to hold — and what could not be shown is said plainly, which is the point of the last five tasks.*

## Phase 23: The audits [US6]

- [ ] T160 [US6] Build the audit matrix in `specs/020-categorize/quickstart.md`: every audit type that runs × every new surface, with the cells that are **not** audited named and reasoned. SC-016's "zero findings" is scoped to the audit types that actually run, and this table is where that scope is written down instead of implied.
- [ ] T161 [US6] Run `make a11y-sweep` over the new surfaces (`Makefile:145`, `xcrun simctl ui "iPhone 16" increase_contrast enabled`). ⚠️ **Increase Contrast cannot be set from XCUITest** — this sweep is the *only* mechanism, and it is **not** part of `make ios-test`. FR-065 is therefore satisfied across **two** targets (plan § *Spec amendments* §5). Record which surfaces were swept and the verdict.
- [ ] T162 [US6] Record which unit-level states are **executed and asserted but not audited**: a host-rendered SwiftUI view publishes no accessibility label, so an audit over it is vacuous. ⚠️ `RunLoop.main.run(until:)` inside an async `@MainActor` test deadlocks — use `Task.sleep`; ⚠️ a detached `UIWindow` has no display link — attach to the host app's scene (`ios/Tests/EmptyStateRenderingTests.swift` is the precedent).
- [ ] T163 [US6] Write the **break ledger** into `specs/020-categorize/quickstart.md` § *how to watch each gate fail*: every deliberate break in this queue (T026, T027, T035, T051, T056, T063, T074, T075, T091, T096, T117, T138, T154, T155, T157), the expected red, and the **observed** red with its failure text. A break whose observed red is missing is a break that was not run.
- [ ] T164 [US6] Run `make release-audit` (`scripts/release-absence-audit.sh`) — `DebugSeed`, `SeedScenarios.swift`, `SeedExpectations.swift` and the three new scenarios are absent from a Release build.
- [ ] T165 [US6] Run `make import-audit` — all ten scans, four of them (5, 6, 7, 8) now covering `ios/Sources/Categorize/` as well as `ios/Sources/Transactions/`.
- [ ] T166 [US6] File budgets: run `make lint` and confirm `ios/Sources/Import/ImportService.swift` is still **398** lines and no file in `ios/Sources/Categorize/` is over its budget (FR-073, SC-023).
- [ ] T167 [US6] Parity: `core/crates/kaname-core/tests/parity.rs` is unchanged and green, and **no fixture under `fixtures/` was edited to make anything pass**. `git --no-pager diff --stat origin/main... -- fixtures/` should show only `fixtures/categorization/merchant_portion.json` (added by T041).
- [ ] T168 [US6] No disabled tests: assert this slice added no `XCTSkip`, no `#if` that removes an assertion, and no `#[ignore]` Rust test. A test that cannot pass is a finding, not a nuisance.
- [ ] T169 [US6] Synthetic-data audit: no real VPA, no real UPI handle, no real account number, no real merchant identifier anywhere in `fixtures/` or `ios/Sources/DebugSeed/` (Principle I).
- [ ] T170 [US6] Wording audit: every new string in `ios/Sources/Categorize/CategorizeStrings.swift` **and** every scenario/expectation label in `ios/Sources/DebugSeed/` against the banned engine-vocabulary list (FR-029, SC-007, extending U3's reach beyond the strings table).
- [ ] T171 [US6] No floats in money: assert no `Double` or `Float` appears in any money path added by this slice, in `core/crates/kaname-core/src/merchant.rs`, `store.rs` and all of `ios/Sources/Categorize/` (Principle II).
- [ ] T172 [US6] Zero network: confirm this slice added no `URLSession`, no network entitlement and no host in `Info.plist` (Principle I).
- [ ] T173 [US6] Record the manual gate in `specs/020-categorize/quickstart.md`: which success criteria are signed by a **machine** and which by a **person**, one line each, with nothing in between.

## Phase 24: What is written down [US7]

- [ ] T174 [US7] Update `specs/020-categorize/quickstart.md` and `docs/` with the build-sequence lesson in the imperative: `#[uniffi::export]` changed ⇒ `make core-xcframework` **then** `make ios-gen`; a new file added ⇒ `make ios-gen`, because `sources: ["Sources/**"]` resolves at generation time and a suite that never ran reports success.
- [ ] T175 [US7] Record both 🚨 findings and their regression tests in `docs/`, so the next person meets them **before** the code: (a) `NULL NOT IN (…)` is `NULL` — the naive guard drops every freshly imported row and nothing errors; **C2** (T023) is its regression test and **C1 passing proves nothing**; (b) `detect_transfers` guarded on `transfer_group_id IS NULL` alone could erase a person's decision — **T1** (T031) is its regression test, and it is Rust-only because the path is unreachable from Swift.

## Phase 25: What cannot be done on this machine

> These are tasks, not footnotes. Each one is closed by **writing down what is not known**, in the manner of `019`'s T085. None of them is closed by an assertion, and none may be quietly dropped because it cannot be made green.

- [ ] T176 **DEFERRED — cannot be measured here.** The three device timings (`018/06`) need a physical phone; a simulator measures the host. Record in `specs/020-categorize/quickstart.md` § *what cannot be verified on this machine* that 018's SC-012 **stays unsigned** and that this slice did not sign it.
- [ ] T177 **DEFERRED — cannot be reproduced here.** `018/05`'s render-hang reopen conditions (a detail push over a deep list). State the conditions precisely so someone with the hardware can try them; do **not** claim they were met because nothing hung on this machine.
- [ ] T178 **UNMEASURABLE beyond Q1–Q3.** The real SQLCipher query plans. Q1–Q3 (T088–T090) assert against the real store and settle *those three* queries; research R13's wider plan survey was taken on system SQLite 3.45.3. Record exactly what Q1–Q3 settle and what remains unmeasured, rather than letting three green tests imply a survey.
- [ ] T179 🚨 **UNPROVABLE HERE BY DESIGN.** Whether the derivation rule is adequate for **real Indian narrations** cannot be determined in this repository, because no real VPA and no real UPI-handle shape exists in it — and correctly so (Principle I). What *is* known is research R15's three priced limitations, asserted in **P5** (T046). Record in `specs/020-categorize/quickstart.md` that the rule is proven against synthetic shapes only, that this is a deliberate limit and not an oversight, and what evidence would settle it (a person's own store, examined by that person, never exported).
- [ ] T180 **DEFERRED — an XCUITest limit, not a machine limit.** Increase Contrast cannot be set from within `make ios-test`. It is covered **only** by `make a11y-sweep` (T161), and FR-065 is satisfied across two targets (plan § *Spec amendments* §5). Record it as a permanent split, not a temporary gap.

## Phase 26: Hand-back

- [ ] T181 [US7] Record every schema and FFI surface change this slice made, in one place in `docs/`: `user_version` 7→8, `merchant_memory`, `idx_txn_unanswered_account_date`, and the six exported functions (`set_transaction_category`, `merchant_portion`, `preview_memory_application`, `apply_memory_application`, `uncategorized_count`, plus the `HistoryQuery.uncategorized_only` field).
- [ ] T182 **FINAL GATE** — in this order, never concurrently: `make core-lint && make core-test`; then `make lint && make ios-test`; then `make import-audit && make release-audit && make a11y-sweep`. ⚠️ `core/tests/history_perf.rs::s5` is wall-clock; ⚠️ `make ios-test` cannot run concurrently with itself.
- [ ] T183 [US6] [US7] Hand-back: walk `specs/020-categorize/spec.md` and confirm every FR-001–FR-078 and SC-001–SC-036 is either **satisfied with a task id** or **explicitly deferred with its reason** (T176–T180). Anything that is neither is a gap and is reported as one, not closed.

---

## Dependencies & Execution Order

**Between PRs** (the order in `plan.md` § *Delivery order*, which is not advisory):

```
A (engine: predicates, write path, guards)
├─→ B (engine: derivation, memory, preview/apply)   needs A's transaction and predicates
│   └─→ C (engine: narrowed read, count, plans)     needs A's UNANSWERED, B's memory rows for H5's fixtures
│       ├─→ D (platform: detail + picker)           needs C's HistoryRow.category_id and A's FFI
│       │   ├─→ E (platform: memory offer + second action)  needs B's FFI and D's surface
│       │   └─→ F (platform: worklist)              needs C's count, D's nav, E's refresh path
│       │       └─→ G (audits, sweeps, deferrals)   needs A–F
```

**Within PR A**: T001–T005 (setup) → T006–T013 (migration, RED before T010) → T014–T020 (write path) → T021–T030 (the guard; **T021/T023 before T024**) → T031–T036 (transfer guard) → T037–T040 (close-out).

**Within PR B**: T041–T047 (all REDs) → T048–T050 (GREEN + build) → T051 (break) → T052–T054 (REDs) → T055 (GREEN) → T056 (break) → T057–T058 (deferred REDs) → T059 (GREEN) → T060–T061 (REDs) → T062 (GREEN) → T063 (break) → T064–T070 (REDs) → T071–T073 (GREEN + build) → T074–T076.

**Within PR C**: T077 → T078–T083 (all REDs) → T084 (GREEN) → T085 (the PR A deferral) → T086–T087 (build) → T088–T090 (plan REDs) → T091 (break) → T092–T093.

**Within PR D**: T094–T096 **first** (widen the scans before code lands in the new directory) → T097–T100 (unit REDs + the generation trap) → T101–T112 (surface, with a build after every batch of new files) → T113–T117 (seed + UI) → T118–T121.

**Within PR E**: T122–T125 (seeds) → T126–T129 (offer) → T130–T138 (second action) → T139–T140.

**Within PR F**: T141–T145 (empty states) → T146–T153 (door + worklist) → T154–T158 (the breaks that only work once T094 widened the scans) → T159.

**Within PR G**: T160–T173 (audits, any order) → T174–T175 (docs) → T176–T180 (deferrals) → T181–T183.

**Hard ordering rules that override the above**:

1. Every `RED` task precedes the `GREEN` task that satisfies it. There are no exceptions in the engine PRs.
2. Every `#[uniffi::export]` change is immediately followed by its `make core-xcframework` → `make ios-gen` task: **T018→T019**, **T049→T050**, **T072→T073**, **T086→T087**.
3. Every new-file task is followed by a `make ios-gen` task before anything claims its assertions ran: **T097–T099→T100**, **T101–T103→T104**, **T105–T107→T108**, **T113→T114**, **T115→T116**, **T122–T124→T125**, **T126→T127**, **T130→T131**, **T133→T134**, **T146–T147→T148**, **T149–T151→T152**.
4. **T094 precedes every task that writes a file under `ios/Sources/Categorize/`.** A scan widened after the code exists has never been seen to fail on that code.
5. **T023 (C2) is not merged into T021 (C1).** They fail for different reasons and one of them does not fail at all against the bug it exists to catch.
6. No `make core-test` task runs concurrently with any `make ios-test` task, anywhere in this list.

## Parallel Example: PR A setup

```
# T002, T003, T004 and T005 touch different files and nothing depends on them yet:
T002  survey store.rs write sites          (PR description)
T003  create tests/store_correction.rs     (new file)
T004  confirm user_version 7               (read-only)
T005  add the v7 provenance fixture        (tests/common/)
```

## Parallel Example: PR D unit assertions

```
# Three new test files, three different suites, no shared state:
T097  ios/Tests/CategoryCatalogTests.swift
T098  ios/Tests/CategorizeStringsTests.swift
T099  ios/Tests/TransactionScopeTests.swift
# then T100 alone — make ios-gen, and confirm all three RAN.
```

## Parallel Example: PR B derivation REDs

```
# T041 (fixture) and T042 (test skeleton) are independent.
# T043–T047 all edit tests/merchant_portion.rs and are therefore NOT parallel.
```

⚠️ **Nothing in PR G is parallel with anything in PR G that runs a gate.** `make a11y-sweep` toggles a simulator-wide setting; running it beside `make ios-test` changes the thing being measured.

## Implementation Strategy

**MVP = PR A.** It ships no visible feature and it is still the most valuable pull request in the slice: it closes a defect where the app silently overwrites what a person told it, and it closes it in the only place the guarantee can live. Everything after it is the interface to a promise the engine already keeps.

**Incremental delivery**:

1. **A** — the promise. Engine-only, green, revertible.
2. **A+B** — the promise plus memory. Still invisible; still worth shipping, because the memory can be formed and applied by the next PR without a migration.
3. **A+B+C** — the read side. The last engine PR; after this, no schema changes.
4. **+D** — the first thing a person can *do*. This is the honest MVP for a user, and it is deliberately fourth.
5. **+E** — the app starts remembering.
6. **+F** — the worklist: the reason to open the app twice.
7. **+G** — the evidence.

**If time runs short**, stop after **D**. A person who can correct one transaction and see it stick has the whole promise of this feature, minus convenience. Stopping after **B** or **C** ships engine capability with no way to reach it, which is not a smaller feature — it is an unused one.

**Do not** reorder D before C, or E before B. Both inversions produce a surface that calls a function that does not exist, and the symptom is a Swift compile error that looks like a Swift problem (non-negotiable 3).

## Recommended PR split

| PR | Tasks | Count | Gate | Reviewer's first question |
|----|-------|-------|------|---------------------------|
| A | T001–T040 | 40 | `make core-lint && make core-test`, `make core-privacy-audit` | "Show me C2 failing against the naive guard while C1 stays green." |
| B | T041–T076 | 36 | `make core-fmt && make core-lint && make core-test` | "Show me M7 failing against a subset check." |
| C | T077–T093 | 17 | `make core-lint && make core-test` | "Show me Q3 naming the index, and s1 unedited." |
| D | T094–T121 | 28 | `make lint && make ios-test && make import-audit` | "Show me scans 5–7 firing on a file in `Categorize/`." |
| E | T122–T140 | 19 | `make lint && make ios-test && make import-audit` | "Show me the trimmed-id break returning `StaleSet`." |
| F | T141–T159 | 19 | `make lint && make ios-test && make import-audit` | "Show me the Swift-side filter turning scan 5 red." |
| G | T160–T183 | 24 | all of the above, in sequence | "Show me the break ledger with observed failure text." |
| | **Total** | **183** | | |

## Traceability

**Engine assertions** (`contracts/engine-categorize.md` §4 — 39 named, plus one unnumbered structural requirement in §5.1):

| Assertion | Task | Assertion | Task | Assertion | Task |
|---|---|---|---|---|---|
| C1 🔴 | T021, T022 | M1 | T060 | P1 | T044 |
| C2 🚨 | T023 | M2 | T061, T063 | P2 🚨 | T045, T051 |
| C3 | T015 | M3 | T053, T056 | P3 | T043 |
| C4 | T057 | M4 | T064 | P4 | T043 |
| C5 | T085 | M5 | T065 | P5 | T046 |
| C6 | T014 | M6 | T067, T075 | P6 | T047 |
| C7 | T058 | M7 🚨 | T066, T074 | G1 | T007 |
| T1 🔴 | T031, T032, T035 | M8 | T068 | G2 | T006 |
| T2 | T033 | M9 | T069 | G3 | T008 |
| H1 | T078 | M10 | T070 | G4 | T009 |
| H2 | T079 | M11 | T054 | Q1 | T088 |
| H3 | T080 | | | Q2 | T089 |
| H4 | T081 | | | Q3 ⚠️ | T090, T091 |
| H5 | T083 | | | §5.1 index byte-identity | T012 |
| H6 | T082 | | | predicate behaviour | T013 |

**Platform rules** (`contracts/platform-categorize.md` §3–§11):

| Rules | Task(s) |
|---|---|
| R1, R3, R4 | T109 |
| R2 | T110, T119 |
| D1–D6 | T106 |
| K1, K3, K5–K6 | T107 |
| K2 | T103 |
| K4 | T118 (⚠️ no named X assertion exists — see gap 5) |
| K7 | T119 |
| M1, M2, M4, M5 | T126 |
| M3 | T129 |
| S1–S4, S7 | T130 |
| S5 | T133, T138 |
| S6 | T136 |
| S2 (as a UI rule; enforcement is M7) | T130, T135 |
| E1, E4 | T146 |
| E2 | T147, T155 |
| E3 | T149 |
| E5 | T153 |
| L1, L2, L3 | T144, T154 |
| L4 | T141, T142 |
| L5 | T143 |
| L6 | T156 |
| T1–T4 | T101, T170 |
| U1 | T097 |
| U2 | T141 |
| U3 | T098 |
| U4 | T099 |
| X1, X2 | T115, T117 |
| X3 | T151, T157 (⚠️ moved to PR F — see gap 4) |
| X4 | T128 |
| X5 | T132, T138 |
| X6 | T149 |
| X7 | T150, T154 |
| X8 | T119, T139, T158, T161 |

**User stories**: US1 → T014–T020, T097–T121; US2 → T021–T036; US3 → T041–T076, T122–T140; US4 → T077–T093, T141–T159; US5 → T115, T119; US6 → T160–T173, T183; US7 → T006–T013, T174–T175, T181–T183.

## Notes

- `[P]` appears on 10 tasks. It is absent everywhere else on purpose: most of this list edits one of four files (`core/src/store.rs`, `tests/merchant_memory.rs`, `tests/merchant_portion.rs`, `ios/Sources/Categorize/*`) and two people editing `store.rs` in parallel is not parallelism.
- Every **DELIBERATE BREAK** task is a *first-class* task with an expected red and a revert, because a gate nobody has seen fail is a gate nobody has tested. There are 15 of them: T026, T027, T035, T051, T056, T063, T074, T075, T091, T096, T117, T138, T154, T155, T157.
- ⚠️ The revert instruction is the same everywhere and it is worth reading twice: **`git checkout -- ios/Sources` (or `core/`) reverts to `HEAD` and takes an uncommitted fix with it.** Commit the fix first, or copy the tree aside and restore from the copy. Never break first and hope.
- The two 🔴 assertions — **C1** (T021) and **T1** (T031) — fail against *shipped* behaviour. They are the reason this slice exists. If either passes when first written, the test is not reaching the code.
- **C2** (T023) is the assertion that is green when written. That is not a reason to skip it; it is the entire reason it exists, and T026 is where it earns its place.
- 019's lesson, encoded structurally rather than remembered: **a new file plus no `make ios-gen` equals a suite that reports success without running.** Thirteen tasks in this list exist only to close that gap.
