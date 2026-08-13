---
description: "Task list for 016-statement-import-vertical"
---

# Tasks: Statement Import — the First End-to-End Vertical

**Input**: Design documents from `/specs/016-statement-import-vertical/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/engine-ffi.md`, `contracts/platform-seams.md`, `quickstart.md`
**Governing**: `.specify/memory/constitution.md` (wins over everything), `.scratch/HANDOFF.md` §4–§7, `.github/skills/swiftui-liquid-glass/SKILL.md`

**Tests**: **MANDATORY**, not optional. Constitution Principle V and `.scratch/HANDOFF.md` §4 require test-first (RED → GREEN) for all engine behaviour. Every Rust behaviour below lands as a failing `cargo test` before its implementation task, and the test task is sequenced immediately before the implementation task that makes it pass.

**Design**: The tasks-template's Figma phase is written against a "Constitution Principle IX" that **does not exist in Kaname's constitution** (v2.0.0 has six principles, I–VI; there is no Figma tooling in this repo). It is replaced by **Phase 2.5**, a real design-contract gate: the visual contract for this slice is `contracts/platform-seams.md` §3 + `research.md` R13, and it is signed off before any UI task starts.

**Organization**: Tasks are grouped by user story (US1–US7) so each story is independently completable and testable. **US1 is the MVP** — the walking skeleton.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no shared state, no dependency on an incomplete task)
- **[Story]**: `[US1]`…`[US7]`. Setup, Foundational, Design and Polish tasks carry **no** story label.
- Every task names an exact file path.

## Path Conventions

Two-layer repo (`plan.md` → Project Structure):

- **Engine**: `core/crates/kaname-core/src/`, `core/crates/kaname-core/tests/`
- **App**: `ios/Sources/`, `ios/Tests/`, `ios/Project.swift`
- **Fixtures**: `fixtures/<bank>/<kind>/*.json` — **synthetic only, always** (Constitution I, FR-043, SC-011)
- **Gates**: repo-root `Makefile`

## Non-negotiables encoded in this list

1. **⚠️ Deadlock hazard sequenced first.** `categorize_account` (`core/crates/kaname-core/src/store.rs:656`) and `find_duplicates` (`store.rs:785`) each call `self.lock()` on their first line, and `std::sync::Mutex` is **not reentrant**. A composite `import_statement` that holds the connection lock and then calls either **deadlocks silently, only on the happy path with a real import**. Phase 2A splits them into `*_in(tx, …)` helpers — a pure refactor with existing tests staying green — and it lands **before** `Store::import_statement` (Phase 2D). This is verified fact, not a precaution.
2. **⚠️ FFI build ordering.** `make core-xcframework` **must** run before `tuist generate` whenever the FFI surface changes. It is an explicit task (T044, T093) — never a bare `tuist generate`; always go through `make ios-gen` / `make ios-test`.
3. **R1 issuer registry is product-owner-approved and implemented verbatim** (T024), including `FEDERAL_CARD` = **"Scapia Credit Card"** and `YES_CARD` = **"Kiwi (YES Bank) Credit Card"**.
4. **The three known dispatcher collisions get a named regression test** (T020): `fixtures/federal/bank_account/classic.json`, `fixtures/federal/bank_account/fi.json` (both `FEDERAL_CARD` + `FEDERAL_BANK`) and `fixtures/icici/bank_account/basic.json` (`ICICI_CARD` + `ICICI_BANK`) must each resolve to the **ledger**.
5. **iOS 26 / Liquid Glass**: never `#available(iOS 26, *)`, never `.ultraThinMaterial` or hand-rolled blur, never glass on dense numeric rows; every amount and count uses `.monospacedDigit()`.
6. **Zero network I/O** anywhere on this path; `make core-privacy-audit` stays green and an app-side source audit is added.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish a green baseline, the local simulator, the PDFKit link, and the new engine module — before a single behaviour changes.

- [x] T001 Establish the green pre-change baseline: `export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"` then run `make core-lint && make core-test && make core-privacy-audit` from the repo-root `Makefile`; record the passing test count so any later regression is attributable.
- [x] T002 [P] Create the simulator `make ios-test` targets locally: `xcrun simctl create "iPhone 16" "iPhone 16"` (see the `ios-test` target in `Makefile`).
- [x] T003 [P] Re-run the claim-replay proof in `specs/016-statement-import-vertical/quickstart.md` §3 and confirm **exactly three** AMBIG lines (`fixtures/federal/bank_account/classic.json`, `fixtures/federal/bank_account/fi.json`, `fixtures/icici/bank_account/basic.json`) before writing any dispatcher code — this is the empirical basis for T020.
- [x] T004 [P] Link PDFKit: add `.sdk(name: "PDFKit", type: .framework)` to the `Kaname` target's dependencies in `ios/Project.swift` (first-party Apple SDK framework; nothing enters the Rust crate graph).
- [x] T005 Declare the new engine submodule: add `pub mod registry;` to `core/crates/kaname-core/src/statement/mod.rs` and create an empty `core/crates/kaname-core/src/statement/registry.rs` so the workspace stays compiling.

**Checkpoint**: Baseline green, simulator present, PDFKit linked, module declared.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The engine surfaces and Swift seams that **every** user story depends on: the deadlock refactor, schema v6, the dispatcher, the atomic import, the regenerated FFI, and the empty Swift scaffolding.

**⚠️ CRITICAL**: No user story work can begin until Phase 2 is complete.

### Phase 2A — ⚠️ Deadlock-hazard refactor (MUST land before any composite store write)

> `std::sync::Mutex` is not reentrant. This block is **not optional and not cosmetic**. It is sequenced ahead of `Store::import_statement` deliberately (see Non-negotiable 1).

- [x] T006 Create `core/crates/kaname-core/tests/store_import.rs` with the characterisation test `categorize_then_find_duplicates_over_one_store_is_stable`, capturing today's `categorize_account` + `find_duplicates` behaviour end-to-end. A pure refactor has no RED step — this is the refactor's safety net and it must be **GREEN against unmodified code** before T007.
- [x] T007 ⚠️ Extract `fn categorize_account_in(tx: &rusqlite::Transaction<'_>, account_id: &str) -> Result<CategorizeSummary, StoreError>` in `core/crates/kaname-core/src/store.rs`, and rewrite the public `Store::categorize_account` (`store.rs:656`) as a thin `lock → transaction → categorize_account_in → commit` wrapper with identical behaviour.
- [x] T008 ⚠️ Extract `fn find_duplicates_in(tx: &rusqlite::Transaction<'_>) -> Result<DedupSummary, StoreError>` in `core/crates/kaname-core/src/store.rs`, and rewrite the public `Store::find_duplicates` (`store.rs:785`) as the same thin wrapper.
- [x] T009 Add the permanent guard `both_in_helpers_run_on_one_transaction_without_relocking` to `core/crates/kaname-core/tests/store_import.rs`: call `categorize_account_in` **and** `find_duplicates_in` on a single `rusqlite::Transaction` — exactly the shape `import_statement` will use. **Assert completion under a timeout, never by simply returning**: run the body on a `std::thread::spawn`, hand the result back over a `std::sync::mpsc::channel`, and assert `rx.recv_timeout(Duration::from_secs(10))` is `Ok`, failing with an explicit "deadlock: the `*_in` helpers re-locked the connection" message on `RecvTimeoutError::Timeout`. A guard that merely hangs would stall CI until the runner's global timeout and surface as a generic cancellation rather than a named failing test — it must fail **fast and legibly**. (The 10s budget is ~100× the whole suite's current runtime, so it cannot flake on a slow runner.) Two implementation notes: **(a)** the thread closure must be `'static`, so pass the temp-DB *path* in and `Store::open` **inside** the spawned thread — `std::thread::scope` is not an option because a scoped thread joins on scope exit, which reintroduces the very hang this test exists to catch; **(b)** on timeout the spawned thread stays blocked on the mutex and is deliberately never joined, which is correct — the test process is exiting with a failure anyway.
- [x] T010 Run `make core-fmt && make core-test` and confirm `core/crates/kaname-core/tests/store_categorization.rs` and `core/crates/kaname-core/tests/store_dedup.rs` are **unchanged and still green** — proof the refactor changed no behaviour.

### Phase 2B — Schema v6 (`accounts.last4`), forward-only

- [x] T011 RED: add `migrating_v5_to_v6_preserves_existing_rows` to the `#[cfg(test)] mod tests` block in `core/crates/kaname-core/src/store.rs`, mirroring `migrating_v4_to_v5_preserves_existing_rows` (`store.rs:1718`): build a **populated** v5 DB (accounts + transactions + statements rows), open it, assert `PRAGMA user_version == 6`, every pre-existing row is intact, and `accounts.last4` exists and is `NULL`.
- [x] T012 RED: add `reopening_a_v6_store_is_a_no_op` to `core/crates/kaname-core/tests/store.rs` beside `migration_is_idempotent_across_reopens` (`tests/store.rs:189`) — re-open must not re-run the migration or alter a row.
- [x] T013 GREEN: add `const SCHEMA_V6: &str = "ALTER TABLE accounts ADD COLUMN last4 TEXT;"` and bump `const SCHEMA_VERSION: i64` from `5` to `6` in `core/crates/kaname-core/src/store.rs:41`.
- [x] T014 GREEN: add the `6 => { tx.execute_batch(SCHEMA_V6).map_err(StoreError::migration) }` arm to `apply_migration` in `core/crates/kaname-core/src/store.rs:907`, following the shipped v2/v3/v4/v5 pattern exactly.
- [x] T015 GREEN: add `last4: Option<String>` to `NewAccount` (`core/crates/kaname-core/src/store.rs:218`) and `StoredAccount` (`store.rs:229`).
- [x] T016 GREEN: thread `last4` through `Store::insert_account` (`core/crates/kaname-core/src/store.rs:413`) and `Store::list_accounts` (`store.rs:434`) — insert the column, read it back.
- [x] T017 Run `make core-fmt && make core-test`: T011 and T012 GREEN, and **no** shipped store test regressed. `statements` is untouched — the v5 table already satisfies FR-026 (research R6). Targets live in the repo-root `Makefile`.

### Phase 2C — The issuer dispatcher (registry, tie-break, unified parse)

- [x] T018 RED: create `core/crates/kaname-core/tests/dispatcher.rs` with the registry invariants `registry_ids_are_unique_and_total`, `registry_display_names_are_non_empty`, and `registry_bank_code_matches_the_backing_reader_constant` (uniqueness of `id` is what makes the `(kind_rank, id)` order total — research R3 §1).
- [x] T019 RED: add the detection semantics to `core/crates/kaname-core/tests/dispatcher.rs` — `detect_issuer_returns_none_for_an_unclaimed_document` (FR-013), `detect_issuer_is_deterministic_over_repeated_calls` (FR-015), and `ledger_beats_card_on_a_doubly_claimed_document` (FR-014).
- [x] T020 RED: add the **named collision regression** `ledger_wins_for_the_three_doubly_claimed_golden_fixtures` to `core/crates/kaname-core/tests/dispatcher.rs`, asserting `detect_issuer` returns `FEDERAL_BANK` for `fixtures/federal/bank_account/classic.json` and `fixtures/federal/bank_account/fi.json`, and `ICICI_BANK` for `fixtures/icici/bank_account/basic.json`. These three are claimed by two readers **today** (verified, T003) — this test is what stops a future reader change silently regressing it.
- [x] T021 [P] RED: add `detect_issuer_resolves_every_golden_fixture_to_its_expected_issuer` to `core/crates/kaname-core/tests/parity.rs` — the SC-002 (100% attribution) gate across all 13 synthetic fixtures.
- [x] T022 [P] GREEN: add the `LineWords { line_index: u32, words: Vec<Word> }` `uniffi::Record` to `core/crates/kaname-core/src/statement/base.rs` (`Word` unchanged) and re-export it from `core/crates/kaname-core/src/lib.rs`.
- [x] T023 GREEN: add `StatementKind` (`uniffi::Enum`, `CreditCard` | `BankAccount`), `Issuer` (`uniffi::Record` — `id`, `display_name`, `bank_code`, `kind`) and `ReaderError::UnknownIssuer { id }` (`uniffi::Error`, via the shipped `thiserror`) to `core/crates/kaname-core/src/ffi.rs`.
- [x] T024 GREEN: implement `struct ReaderEntry` and the private `static REGISTRY: &[ReaderEntry]` with all **ten** entries in `core/crates/kaname-core/src/statement/registry.rs`, transcribing the `research.md` R1 table **verbatim** — including `FEDERAL_CARD` → "Scapia Credit Card" and `YES_CARD` → "Kiwi (YES Bank) Credit Card". No `supported_issuers()` export (FR-012).
- [x] T025 GREEN: implement `kind_rank(BankAccount) = 0` / `kind_rank(CreditCard) = 1` and the `detect_issuer` selection — evaluate every entry's `claims`, return `None` if zero claim, otherwise the minimum under `(kind_rank, id)` — in `core/crates/kaname-core/src/statement/registry.rs`.
- [x] T026 GREEN: export `#[uniffi::export] pub fn detect_issuer(full_text: String) -> Option<Issuer>` from `core/crates/kaname-core/src/ffi.rs`, delegating to the registry.
- [x] T027 Run `make core-fmt && make core-test`: T018–T021 GREEN, including the three-fixture collision regression. Targets live in the repo-root `Makefile`.
- [x] T028 RED: add the ten equivalence tests `read_statement_matches_the_legacy_per_bank_reader_byte_for_byte` (one per issuer) to `core/crates/kaname-core/tests/dispatcher.rs`, comparing `read_statement(issuer, …)` against the corresponding shipped `read_<bank>_statement(…)` output field-for-field.
- [x] T029 RED: add `read_statement_rejects_an_unknown_issuer_id` (→ `ReaderError::UnknownIssuer`), `read_statement_ignores_line_words_for_card_issuers`, and `read_statement_forwards_only_the_anchor_row_geometry` to `core/crates/kaname-core/tests/dispatcher.rs` (research R5).
- [x] T030 [P] GREEN: add the additive helper `pub(crate) fn first_anchor_index<C: LedgerReaderConfig + ?Sized>(cfg: &C, lines: &[String]) -> Option<usize>` to `core/crates/kaname-core/src/statement/ledger_reader.rs`, built on the existing `find_anchors`. `read_ledger_lines` and all four `LedgerReaderConfig` impls stay **unchanged**.
- [x] T031 GREEN: implement per-entry parse dispatch in `core/crates/kaname-core/src/statement/registry.rs` — `CreditCard` → `read_lines(cfg, &lines, &full_text)` ignoring `line_words`; `BankAccount` → resolve `first_anchor_index`, forward only that row's `Word`s (empty when absent), then `read_ledger_lines`.
- [x] T032 GREEN: export `#[uniffi::export] pub fn read_statement(issuer: Issuer, lines: Vec<String>, full_text: String, line_words: Vec<LineWords>) -> Result<ParsedStatement, ReaderError>` from `core/crates/kaname-core/src/ffi.rs`.
- [x] T033 [P] Add a synthetic `line_words` block to `fixtures/icici/bank_account/basic.json` (an **additive, optional** field the parity harness tolerates when absent) so T029's anchor-row forwarding is proven against a real ledger fixture. Synthetic geometry only — no real statement, ever.
- [x] T034 Run `make core-fmt && make core-test`: T028–T029 GREEN; all ten legacy `read_*_statement` exports and their parity assertions unchanged. Targets live in the repo-root `Makefile`.

### Phase 2D — `Store::import_statement` (atomic) — depends on Phase 2A and 2B

- [x] T035 RED: add `import_statement_writes_account_statement_and_transactions_in_one_transaction` and `import_statement_is_atomic_on_failure` to `core/crates/kaname-core/tests/store_import.rs` — the second forces a mid-write failure and asserts row counts across `accounts`/`statements`/`transactions` **and** `PRAGMA user_version` are byte-identical to the pre-import state (FR-031, SC-006).
- [x] T036 RED: add `import_statement_derives_every_timestamp_from_request_now` (FR-027 — the core reads no wall clock) and `import_statement_writes_no_statements_row_when_no_period_and_no_transactions` (research R6, product-owner judgement call) to `core/crates/kaname-core/tests/store_import.rs`.
- [x] T037 GREEN: add `ImportAccountTarget` (`uniffi::Enum`), `NewImportTransaction`, `ImportRequest` and `ImportOutcome` (`uniffi::Record`) to `core/crates/kaname-core/src/store.rs`, exactly per `contracts/engine-ffi.md` §4.
- [x] T038 GREEN: implement `#[uniffi::export] impl Store { pub fn import_statement(&self, request: ImportRequest) -> Result<ImportOutcome, StoreError> }` in `core/crates/kaname-core/src/store.rs` as **one** SQLite transaction: resolve-or-create account → insert `statements` row → insert every transaction with `statement_id` + timestamps → `categorize_account_in(tx, …)` → `find_duplicates_in(tx, …)` → COMMIT, with full ROLLBACK on any failure. It calls the `*_in` helpers from T007/T008 — **never** the public locking methods.
- [x] T039 GREEN: re-export `ImportAccountTarget`, `NewImportTransaction`, `ImportRequest` and `ImportOutcome` from `core/crates/kaname-core/src/lib.rs`.
- [x] T040 Run `make core-fmt && make core-test`: T035–T036 GREEN and the happy path completes without hanging (the deadlock guard, T009, is now exercised for real). Targets live in the repo-root `Makefile`.

### Phase 2E — Engine verification gate + FFI regeneration

- [x] T041 **GATE** `make core-lint` (cargo fmt --check + clippy -D warnings) from the repo-root `Makefile`.
- [x] T042 **GATE** `make core-test` — the whole engine suite, unit + parity + store. Targets live in the repo-root `Makefile`.
- [x] T043 **GATE** `make core-privacy-audit` — no networking crate, no `openssl-sys` in the shipped graph. Zero new dependencies were added, so this must stay green unchanged. Targets live in the repo-root `Makefile`.
- [x] T044 ⚠️ **FFI ordering** `make core-xcframework` — regenerates `ios/Generated/` and the xcframework. This slice changes the FFI surface (`Issuer`, `StatementKind`, `LineWords`, `ReaderError`, `detect_issuer`, `read_statement`, `import_statement`, `NewAccount.last4`), so this **must** run before any `tuist generate`. Targets live in the repo-root `Makefile`.
- [x] T045 Update the shipped Swift call sites for the widened `NewAccount`/`StoredAccount` in `ios/Tests/StoreTests.swift` (and any other `NewAccount(` construction under `ios/`) to supply `last4:`.
- [x] T046 **GATE** `make ios-gen && make ios-test` — never a bare `tuist generate`. All 20 shipped Swift suites must be green **before** any new Swift is written. Targets live in the repo-root `Makefile`.

### Phase 2F — Swift seams scaffolding (types only, no behaviour)

- [x] T047 [P] Create `ios/Sources/Import/ImportModels.swift` with `ImportStage`, `ImportSummary`, `IntegrityOutcome` (`.agrees` | `.needsReview` | `.nothingToCheck`) and `ImportFailure` (`.notAPDF`, `.passwordRequired`, `.wrongPassword`, `.noExtractableText`, `.unreadable`, `.unrecognizedIssuer`, `.cancelled`, `.storageUnavailable`) per `data-model.md` §4.
- [x] T048 [P] Create `ios/Sources/Import/ImportFailureView.swift` — one plain-language terminal view (SF Symbol + one hand-written sentence + "Try another file"). No interpolated engine text, no `localizedDescription`, no error code (FR-034, SC-007).
- [x] T049 [P] Create `ios/Sources/Import/StatementTextExtractor.swift` with the `StatementTextExtractor` protocol, `ExtractedText { lines, fullText, lineWords }` and `ExtractionFailure` — **no** PDFKit implementation yet.
- [x] T050 [P] Create `ios/Sources/Import/ImportService.swift` with the `actor ImportService` skeleton (`private var inFlight: Task<ImportSummary, Error>?` and the `run(url:password:onStage:)` signature) — no pipeline body yet.
- [x] T051 [P] Create `ios/Sources/Import/ImportViewModel.swift` with the `@MainActor @Observable final class ImportViewModel` skeleton holding stage / summary / failure state only (research R9).
- [x] T052 **GATE** `make lint` — swiftlint --strict + swift-format lint over the new files. Remember: swift-format `[Spacing]` rejects trailing inline comments; put comments on their own line. Targets live in the repo-root `Makefile`.

**Checkpoint**: The engine is complete and gated, the FFI is regenerated, the Swift seams exist. User story work can now begin.

---

## Phase 2.5: Design contract (UI features only)

**Purpose**: Fix the visual and copy contract before any UI is built. Kaname has no Figma tooling and no "Principle IX"; the visual contract of record is `contracts/platform-seams.md` §3 plus the R13 application-point table.

- [x] T053 [Design] Walk the R13 Liquid Glass application-point table in `specs/016-statement-import-vertical/research.md` against `.github/skills/swiftui-liquid-glass/SKILL.md`, and confirm per-view: glass on the empty-state CTA and the progress capsule only; the summary as a plain `.sheet`; **opaque** figure rows; `AccountPickerView` a standard dense `List`. Record any deviation as a note in this file before building — do not edit the FINAL artifacts.
- [x] T054 [Design] Write the copy deck: the exact user-facing sentence for **every** `ImportFailure` case and for each of the three `IntegrityOutcome` states, as string constants in `ios/Sources/Import/ImportModels.swift`. Every sentence is hand-written; the only engine-supplied string allowed on screen is `Issuer.display_name` (FR-033, FR-034, SC-007).
- [x] T055 [Design] Trace the state machine in `specs/016-statement-import-vertical/data-model.md` §5 against the four-tap path (SC-001) and confirm every edge — including `.passwordRequired → prompt → retry/cancel` and `Summary` with zero transactions — has a defined destination before UI work begins.

#### T053 outcome — R13 walked against the skill

Every R13 row is confirmed as written; no row changes. Three notes settled before building:

- **N1 — `ImportFailureView` is not in the R13 table.** It is a terminal screen with exactly
  one action, so its "Try another file" button takes `.buttonStyle(.glassProminent)`: the
  skill's "single primary action on a screen" rule, and "at most one prominent element per
  screen" still holds because it is a screen, not an overlay on the empty state.
- **N2 — the progress capsule holds two glass surfaces**, the capsule itself and the Cancel
  `Button(.glass)`. Both live in the one `GlassEffectContainer(spacing:)` and both use the
  **capsule** shape, satisfying the container rule and the consistent-shape rule. The
  `ProgressView` and stage `Text` are plain children — they are not separately glassed.
- **N3 — no explicit `.tint(_:)` anywhere in this slice.** `.glassProminent` supplies the
  accent for the one primary action per screen, so the "tint sparingly" rule holds without a
  per-view decision, and FR-047's "no debit/credit colour on tinted glass" holds structurally
  because the summary reports counts, never signed amounts.

#### T055 outcome — state machine traced

The four-tap path (SC-001) is: **1** Import CTA → **2** select the file → **3** confirm in the
picker → **4** Dismiss the summary. Nothing in US1 adds a fifth tap: the FR-024 account picker
is reachable only from the ambiguous branch (US4), never from the fresh-install path, and an
unprotected statement requires no typing. Four edges needed a defined destination:

- **E1 — dismissing the document picker returns to `Idle` silently.** It is not `.cancelled`:
  that case ("Import stopped. Nothing was saved.") belongs to the Cancel button on an
  in-flight import. Backing out of a picker the person opened by accident must not be
  answered with a failure screen.
- **E2 — `.passwordRequired` and `.wrongPassword` never render `ImportFailureView`.** Both are
  handled on the prompt path: `.passwordRequired` presents the `.alert` with a `SecureField`;
  `.wrongPassword` re-presents that same alert carrying its sentence, so "retry" means try
  another password, not pick another file. Cancelling the alert → `Idle`, and the binding is
  cleared on disappear (FR-008).
- **E3 — `ReaderError.UnknownIssuer` maps to `.unreadable`.** It is unreachable by
  construction (the app hands back only an `Issuer` that `detect_issuer` minted) and is a
  programmer error, so it must never surface as `.unrecognizedIssuer`, which is a real and
  different user-facing meaning.
- **E4 — `Summary` with `transactionsImported == 0` is a terminal success** and takes the same
  two exits as any other summary: Dismiss → `Idle`, "Import another" → `Picking` (FR-020,
  FR-035). Its integrity row follows `IntegrityOutcome` as usual — a statement with nothing to
  check against renders no integrity row at all.

In US1's scope, account resolution covers only the unambiguous cases: exactly one candidate →
attach (FR-021), zero → create and flag `accountIsNew` (FR-022). The `nil`-last-4 and ≥2
candidate branches are US4 (T091–T094) and must never silently guess in the meantime.


**Checkpoint**: Visual treatment, copy and state machine settled — UI implementation may begin.

---

## Phase 3: User Story 1 — Import a statement and see what landed (Priority: P1) 🎯 MVP

**Goal**: A person picks a supported statement PDF and, with no further input, sees an import summary; the transactions are already persisted in the encrypted store and already categorized.

**Independent Test**: Fresh install, no accounts. Import one synthetic supported statement PDF. Confirm the summary reports the correct account, period and transaction count; relaunch and confirm the transactions are still readable from the encrypted store; confirm zero network requests occurred.

### Tests for User Story 1 (RED first) ⚠️

- [x] T056 [US1] RED: create `ios/Tests/ImportPipelineTests.swift` (Swift Testing, `@Test`) exercising the full bridge against a temp SQLCipher DB using a golden fixture's `lines`/`fullText`: `importsASupportedCardStatementEndToEnd`, `importsASupportedBankLedgerWithCorrectDirections` (US1 §3), `persistsAcrossAReopenOfTheStore` (US1 §2), `reportsTheCategorizedSplit` (US1 §4), and `carriesAmountsAsExactDecimals` round-tripping `0`, `999999999999.99` and `0.000000001` with exact equality (US1 §6, FR-028).
- [x] T057 [P] [US1] RED: create `scripts/import-path-audit.sh` plus an `import-audit` target in the repo-root `Makefile` that fails if any networking symbol (`URLSession`, `URLRequest`, `NWConnection`, `CFNetwork`, `Network`) appears anywhere under `ios/Sources/Import/` — the automated SC-004 / FR-041 verification.

### Implementation for User Story 1

- [x] T058 [US1] Implement `PDFKitStatementTextExtractor.extract(from:password:)`'s happy path in `ios/Sources/Import/StatementTextExtractor.swift`: `fullText` = each `PDFPage.string` concatenated and page-separated by `\n`; `lines` = `fullText` split on newlines with **no reshaping** (the ten shipped readers are fixture-locked to exactly this contract).
- [x] T059 [US1] Implement `lineWords` production (**page 1 only**) in `ios/Sources/Import/StatementTextExtractor.swift`: whitespace-split each line, locate each word's character range in the page string, map through `PDFPage.characterBounds(at:)` taking `minX` of the first and `maxX` of the last character. **Bounds-check every index**; on any mismatch emit **no** `LineWords` entry for that line (degrades honestly to `Row1Provisional` → needs-review, never a wrong direction — research R5/R8).
- [x] T060 [US1] Implement the `ImportService.run` pipeline body in `ios/Sources/Import/ImportService.swift`: `extract` → `detectIssuer(fullText:)` → `readStatement(issuer:lines:fullText:lineWords:)` → integrity check → resolve account → `store.importStatement(request:)` → `ImportSummary`. All of it inside the actor, off the main thread (FR-036).
- [x] T061 [US1] Implement account resolution as **pure data comparison** in `ios/Sources/Import/ImportService.swift`: `listAccounts().filter { $0.bankCode == issuer.bankCode && $0.isCreditCard == (issuer.kind == .creditCard) && $0.last4 == parsed.cardLast4 }`. No bank name, no bank list, no per-issuer branch (FR-012, SC-010).
- [x] T062 [US1] Build the `ImportRequest` in `ios/Sources/Import/ImportService.swift`: `period_end` from the parse else max parsed `value_date`; `period_start` nullable; `needs_review`; `source = .statement`; `now` as a caller-supplied ISO-8601 string (FR-027 — the engine reads no clock).
- [x] T063 [US1] Map every thrown `StoreError` / `ReaderError` / `ExtractionFailure` to an `ImportFailure` case **at the actor boundary** in `ios/Sources/Import/ImportService.swift`, so no engine text can reach the UI (FR-034, SC-007).
- [x] T064 [US1] Create `ios/Sources/Import/ImportSummaryView.swift`: presented as a `.sheet` (system chrome gets glass for free, not re-skinned); **opaque grouped figure rows, never glassed** (FR-047); issuer `display_name` + last-4 always shown (FR-033); period omitted when the parse recovered none; `.monospacedDigit()` on every count (FR-045); Dismiss and "Import another" (FR-035).
- [x] T065 [US1] Wire stage / summary / failure state through `ios/Sources/Import/ImportViewModel.swift`, keeping the only main-thread work as rendering.
- [x] T066 [US1] Replace the engine-version placeholder in `ios/Sources/RootView.swift` with the minimal real flow: a single Import action → `.fileImporter` restricted to one PDF (FR-003) → `ImportService` → the summary sheet. (US7 replaces this with the full empty state.)
- [x] T067 [US1] **GATE** `make lint`. Targets live in the repo-root `Makefile`.
- [x] T068 [US1] **GATE** `make ios-gen && make ios-test` — T056 GREEN. Targets live in the repo-root `Makefile`.
- [x] T069 [US1] **GATE** `make import-audit && make core-privacy-audit` — zero network I/O on the whole path. Targets live in the repo-root `Makefile`.

**Checkpoint**: 🎯 **MVP.** A person can put a real statement into Kaname and see what landed. Shippable on its own.

---

## Phase 4: User Story 2 — The app never needs to know which bank it is (Priority: P2)

**Goal**: The engine identifies the issuer; unrecognized documents are declined honestly; doubly-claimed documents are tie-broken deterministically by the engine and the winner is shown.

**Independent Test**: Import a supported statement, a text-bearing PDF no reader claims, and a doubly-claimed document. Confirm identify / decline / deterministic-disambiguate respectively, with **no** bank-specific branching anywhere in the app.

### Tests for User Story 2 (RED first) ⚠️

- [ ] T070 [US2] RED: add `detect_issuer_never_panics_on_arbitrary_input` to `core/crates/kaname-core/tests/dispatcher.rs` — empty string, multi-megabyte string, and byte-soup — proving the totality guarantee in `contracts/engine-ffi.md` §2.
- [ ] T071 [P] [US2] RED: create `ios/Tests/ImportIssuerAgnosticTests.swift`: an unclaimed document yields `.unrecognizedIssuer` with the store **byte-identical** (US2 §3); a doubly-claimed document resolves to the ledger and the summary carries the winning `display_name` (US2 §4); no message contains a reader name or error code (US2 §5).
- [ ] T072 [P] [US2] RED: extend `scripts/import-path-audit.sh` with a bank-literal check that fails if any of the ten registry `id`s, `bank_code`s or `display_name`s appears anywhere under `ios/Sources/` — the mechanical FR-012 / SC-010 guard.

### Implementation for User Story 2

- [ ] T073 [US2] Implement the unrecognized path in `ios/Sources/Import/ImportService.swift`: `detectIssuer` returning `nil` maps to `.unrecognizedIssuer` and **returns before any store call**, kept distinct from `.noExtractableText` (FR-006, FR-013).
- [ ] T074 [US2] Render the engine-supplied `Issuer.display_name` verbatim alongside the last-4 in `ios/Sources/Import/ImportSummaryView.swift`, unconditionally — so a tie-break outcome is always visible rather than silent (FR-014, FR-033).
- [ ] T075 [US2] Render the "not recognized yet" sentence for `.unrecognizedIssuer` in `ios/Sources/Import/ImportFailureView.swift`, sourced from the T054 copy deck.
- [ ] T076 [US2] **GATE** `make lint && make ios-test && make import-audit` — the bank-literal audit is the proof that adding an eleventh issuer costs zero app lines. Targets live in the repo-root `Makefile`.

**Checkpoint**: US1 and US2 both work independently. The app is provably bank-agnostic.

---

## Phase 5: User Story 3 — A file that cannot be read fails honestly (Priority: P3)

**Goal**: Image-only, password-protected, corrupt, non-PDF and unreadable files each produce their own plain-language message and leave the store byte-identical.

**Independent Test**: Import each of the four unusable inputs in turn and confirm each produces a distinct plain-language message and a byte-identical store.

### Tests for User Story 3 (RED first) ⚠️

- [ ] T077 [US3] RED: create `ios/Tests/StatementTextExtractorTests.swift` generating five PDFs **in-test** with `UIGraphicsPDFRenderer` — text-bearing, image-only, password-protected, truncated bytes, and a `.pdf`-named text file — and asserting the five `ExtractionFailure` cases. Generated, never committed: no binary fixtures and no route for a real statement to enter the repo (FR-043, SC-011).
- [ ] T078 [US3] RED: add the password paths to `ios/Tests/StatementTextExtractorTests.swift`: the correct password proceeds, a wrong one yields `.wrongPassword` with retry and cancel available, and the password is **absent** from the Keychain, the store and any log after the run (FR-008).
- [ ] T079 [P] [US3] RED: create `ios/Tests/ImportStoreIntegrityTests.swift` hashing the SQLCipher database file before and after **every** US3 failure path and asserting byte-identity (FR-031, SC-006).

### Implementation for User Story 3

- [ ] T080 [US3] Implement `.notAPDF` (`PDFDocument(url:) == nil`) and `.unreadable` (`startAccessingSecurityScopedResource()` returned `false`, or a read threw) in `ios/Sources/Import/StatementTextExtractor.swift` — never a crash, never a silent no-op (FR-009, FR-002, US3 §7).
- [ ] T081 [US3] Implement `.passwordRequired` keyed on **`doc.isLocked`** — never `doc.isEncrypted` — and `.wrongPassword` on `unlock(withPassword:) == false`, in `ios/Sources/Import/StatementTextExtractor.swift`. This satisfies the empty/owner-password edge case for free.
- [ ] T082 [US3] Implement `.noExtractableText` (document opens, every page's text is empty or whitespace) in `ios/Sources/Import/StatementTextExtractor.swift`, distinct from unrecognized-issuer (FR-006).
- [ ] T083 [US3] Wrap the **entire** extraction in `startAccessingSecurityScopedResource()` / `defer { stopAccessingSecurityScopedResource() }` in `ios/Sources/Import/StatementTextExtractor.swift`, covering the success, throw and cancellation paths (FR-002). The file is read into memory and never copied (FR-004).
- [ ] T084 [US3] Create `ios/Sources/Import/PasswordPromptView.swift` — a standard `.alert` with a `SecureField`, its binding cleared in `onDisappear`. The password is a parameter only: never a stored property, `@State` beyond the prompt, Keychain item, store row or log line (FR-008).
- [ ] T085 [US3] Wire password retry and cancel through `ios/Sources/Import/ImportService.swift` and `ios/Sources/Import/ImportViewModel.swift`, passing the password down the call stack and discarding it at the boundary.
- [ ] T086 [US3] Confirm each of the five failures renders its own distinct sentence in `ios/Sources/Import/ImportFailureView.swift`, drawn from the T054 copy deck — no shared generic message.
- [ ] T087 [US3] **GATE** `make lint && make ios-test` — T077–T079 GREEN. Targets live in the repo-root `Makefile`.

### Extraction fidelity — the silent-empty-import gap ⚠️ (added after PR C)

**Why this exists**: the ten readers are fixture-locked to the **web engine's** PDF extraction
(pdfplumber); iOS extracts with **PDFKit**, and nothing has yet proven the two produce the same
line shapes. A PR C probe against a differently-generated PDF found PDFKit **merging adjacent
lines**: the document was still identified as its issuer, but *zero* rows parsed and the app
reported "0 transactions" — a **success** under FR-020. A person whose statement PDFKit merges
would be told their statement had no spending. That is the one way this slice can currently
mislead, and it fails silently.

- [ ] T137 [US3] RED: create `ios/Tests/ExtractionFidelityTests.swift` — for a representative
      card fixture **and** a representative ledger fixture, render the fixture's `lines` into a
      PDF in-test with `UIGraphicsPDFRenderer`, extract it with `PDFKitStatementTextExtractor`,
      and assert `readStatement` over the *extracted* text yields the **same** transactions
      (dates, exact `Decimal` amounts, directions) as `readStatement` over the fixture lines
      fed directly. This is the parity proof that iOS extraction and the fixture contract
      agree. Generated, never committed (FR-043, SC-011). Include a **line-merge** case —
      rows laid out close enough that PDFKit joins them — and pin the *current* behaviour so
      the failure mode is documented rather than discovered by a person.
- [ ] T138 [US3] Make the empty result **honest**: a parse that recognised no transactions in a
      document that *did* carry extractable text must not read as "your statement had no
      spending". Surface it as its own summary state with its own hand-written sentence
      (copy deck, `ios/Sources/Import/ImportModels.swift`), distinct from both a genuinely
      empty statement and from `.unrecognizedIssuer`. Nothing is written that is wrong, so this
      is a **notice, not a failure** — FR-020 still holds. If the engine cannot distinguish the
      two cases from `ParsedStatement` alone, stop and raise it rather than guessing.
- [ ] T139 [US3] **GATE** `make lint && make ios-test` — T137 GREEN.

**Checkpoint**: Every unusable input fails honestly with the store untouched.

---

## Phase 6: User Story 4 — Importing the same statement twice does not corrupt history (Priority: P4)

**Goal**: Statements attach to the right account by issuer + last-4, accounts are created once, and a re-import links duplicates instead of doubling history.

**Independent Test**: Import the same synthetic statement twice; confirm one account, undoubled totals, and a summary that reports the duplicates skipped.

### Tests for User Story 4 (RED first) ⚠️

- [ ] T088 [US4] RED: add `import_statement_attaches_to_an_existing_account_by_issuer_and_last4` to `core/crates/kaname-core/tests/store_import.rs` (FR-021).
- [ ] T089 [US4] RED: add `import_statement_creates_the_account_and_reports_account_created` to `core/crates/kaname-core/tests/store_import.rs` (FR-022, US4 §5).
- [ ] T090 [US4] RED: add `importing_the_same_statement_twice_does_not_double_history` to `core/crates/kaname-core/tests/store_import.rs` — compare period totals after one import and after two, and assert `ImportOutcome.duplicates_linked` is non-zero and nothing was deleted or replaced (FR-025, SC-005).
- [ ] T091 [P] [US4] RED: create `ios/Tests/ImportAccountResolutionTests.swift` covering the FR-024 matrix — a `nil` last-4 with exactly one candidate attaches, with zero or ≥2 candidates asks the person, and never guesses.

### Implementation for User Story 4

- [ ] T092 [US4] Implement resolve-or-create with last-4 minting inside the transaction in `Store::import_statement` (`core/crates/kaname-core/src/store.rs`), honouring `ImportAccountTarget::Existing` / `::New`.
- [ ] T093 [US4] Implement the three-way FR-024 resolution in `ios/Sources/Import/ImportService.swift`: exactly one candidate → attach; zero or ≥2 with no recoverable last-4 → surface the candidate set for a human decision.
- [ ] T094 [US4] Create `ios/Sources/Import/AccountPickerView.swift` — a standard dense `List`, **not glassed** (FR-047) — letting the person pick or name the account.
- [ ] T095 [US4] Add the "new account" badge and the "N duplicates skipped" figure to `ios/Sources/Import/ImportSummaryView.swift`, both `.monospacedDigit()` (FR-022, FR-025, FR-033).
- [ ] T096 [US4] **GATE** `make core-fmt && make core-lint && make core-test` — T088–T090 GREEN. Targets live in the repo-root `Makefile`.
- [ ] T097 [US4] ⚠️ **GATE** `make core-xcframework && make ios-gen && make ios-test` — the engine binary changed, so the xcframework must be rebuilt **before** generation. T091 GREEN. Targets live in the repo-root `Makefile`.

**Checkpoint**: Account identity is correct and a re-import can no longer double a person's history.

---

## Phase 7: User Story 5 — The app tells the person whether the numbers add up (Priority: P5)

**Goal**: The shipped integrity checks are surfaced in plain language as three states — agrees, needs review, or nothing at all.

**Independent Test**: Import a reconciling statement and a deliberately non-reconciling one; confirm the two summaries differ in a way a non-technical person can act on.

### Tests for User Story 5 (RED first) ⚠️

- [ ] T098 [P] [US5] RED: create `ios/Tests/ImportIntegrityTests.swift` — a reconciling statement shows the positive confirmation; a non-reconciling one shows the warning, **still imports its transactions**, and persists `needs_review` (FR-019); a statement with no printed totals shows **nothing at all** (FR-017, US5 §3); the unreadable-row count is reported (FR-018).
- [ ] T099 [P] [US5] Add a synthetic non-reconciling fixture `fixtures/hdfc/credit_card/mismatched_totals.json` whose rows deliberately disagree with its printed totals. Synthetic only (FR-043, SC-011).

### Implementation for User Story 5

- [ ] T100 [US5] Implement the kind-driven check dispatch in `ios/Sources/Import/ImportService.swift`: `issuer.kind == .bankAccount ? checkBalanceChain(parsed) : reconcileStatement(parsed)` — an exhaustive switch on a closed two-variant enum, which is not per-issuer branching (research R4).
- [ ] T101 [US5] Map `ChainResult` / `ReconcileResult` onto the three-state `IntegrityOutcome` in `ios/Sources/Import/ImportModels.swift`, keeping `ReconcileStatus::None` as `.nothingToCheck` and never collapsing it into a pass or a fail.
- [ ] T102 [US5] Set `needs_review` in the `ImportRequest` when the integrity check says `NeedsReview` **or** `errored_lines` is non-empty, in `ios/Sources/Import/ImportService.swift` (FR-019).
- [ ] T103 [US5] Surface `unreadableRows` (= `errored_lines.count`) in `ios/Sources/Import/ImportSummaryView.swift`, so an incomplete import is never presented as a complete one (FR-018).
- [ ] T104 [US5] Render the integrity verdict in `ios/Sources/Import/ImportSummaryView.swift` as a `Label` — SF Symbol **plus** colour **plus** text on an opaque background, never material or colour alone (FR-046, FR-047), with `.nothingToCheck` rendering no row whatsoever.
- [ ] T105 [US5] **GATE** `make lint && make ios-test` — T098 GREEN. Targets live in the repo-root `Makefile`.

**Checkpoint**: A person can tell whether an import is trustworthy, in their own language.

---

## Phase 8: User Story 6 — A long import stays responsive and can be abandoned (Priority: P6)

**Goal**: The UI stays interactive and shows the stage; cancelling stops the import promptly and leaves no partial data.

**Independent Test**: Import a large multi-page statement, confirm the UI stays interactive with visible progress, cancel mid-parse, and confirm nothing was persisted.

### Tests for User Story 6 (RED first) ⚠️

- [ ] T106 [P] [US6] RED: create `ios/Tests/ImportCancellationTests.swift` — cancelling mid-parse yields `.cancelled` with the store byte-identical (US6 §3, FR-031); a second `run` while `inFlight` is rejected (FR-032); a simulated background/foreground cycle does not cancel the task and never leaves a stuck indicator (US6 §4).
- [ ] T107 [P] [US6] Add a 200-transaction synthetic fixture `fixtures/hdfc/credit_card/large_200.json` to exercise SC-008. Synthetic only.

### Implementation for User Story 6

- [ ] T108 [US6] Implement the `inFlight` guard in `ios/Sources/Import/ImportService.swift` so a double-tap on Import cannot start two conflicting writes (FR-032).
- [ ] T109 [US6] Add `try Task.checkCancellation()` at **every** stage boundary before the write in `ios/Sources/Import/ImportService.swift` — reading, identifying, parsing, checking, resolving. The single atomic write is deliberately uncancellable.
- [ ] T110 [US6] Emit `onStage(_:)` transitions for each `ImportStage` from `ios/Sources/Import/ImportService.swift` and publish them via `ios/Sources/Import/ImportViewModel.swift` (FR-037).
- [ ] T111 [US6] Create `ios/Sources/Import/ImportProgressView.swift`: a `GlassEffectContainer(spacing:)` holding a `ProgressView`, the stage `Text`, and a Cancel `Button(…).buttonStyle(.glass)`; `.glassEffect(.regular.interactive(), in: .capsule)` applied **after** padding and frame. `.interactive()` is honest here because Cancel is tappable. No `#available`, no `.ultraThinMaterial`.
- [ ] T112 [US6] Ensure the pipeline `Task` is owned by the `actor` and not by a view in `ios/Sources/Import/ImportService.swift`, so backgrounding cannot cancel it and the view model always reflects a terminal state (US6 §4).
- [ ] T113 [US6] Assert cancel-to-stopped is under **2 seconds** against `fixtures/hdfc/credit_card/large_200.json` in `ios/Tests/ImportCancellationTests.swift` (SC-008).
- [ ] T114 [US6] **GATE** `make lint && make ios-test` — T106 GREEN. Targets live in the repo-root `Makefile`.

**Checkpoint**: A long import is responsive, abandonable, and leaves no mess.

---

## Phase 9: User Story 7 — A first-run app explains itself instead of showing nothing (Priority: P7)

**Goal**: The first screen states what Kaname does and the privacy promise, offers exactly one action, and is fully accessible.

**Independent Test**: Launch a fresh install; confirm the empty state is present, legible at the largest Dynamic Type size, fully navigable by VoiceOver, and reaches the document picker in one tap.

### Tests for User Story 7 (RED first) ⚠️

- [ ] T115 [P] [US7] RED: create `ios/Tests/ImportAccessibilityTests.swift` covering every screen in the flow — largest accessibility Dynamic Type with nothing clipped or unreachable, Dark Mode, Reduce Transparency and Increase Contrast holding contrast, and VoiceOver announcing every control, count, amount and warning with no unlabelled element (FR-044, FR-046, SC-009).

### Implementation for User Story 7

- [ ] T116 [US7] Create `ios/Sources/Import/ImportEmptyStateView.swift`: what Kaname does, the "your data stays on this device" promise, and a single `Button(…).buttonStyle(.glassProminent)` in `.safeAreaInset(edge: .bottom)` — the screen's one prominent element (FR-039, R13).
- [ ] T117 [US7] Update `ios/Sources/RootView.swift` to switch between the empty state and the imported accounts once at least one import exists, keeping the Import action reachable from both (FR-040, US7 §3).
- [ ] T118 [US7] Confirm the primary action opens the system document picker in **one** tap in `ios/Sources/RootView.swift`, keeping the whole path within the 4-tap budget (SC-001, US7 §2).
- [ ] T119 [US7] Audit every count and amount across `ios/Sources/Import/` for `.monospacedDigit()` (FR-045).
- [ ] T120 [US7] Review every view under `ios/Sources/Import/` against `.github/skills/swiftui-liquid-glass/SKILL.md`: at most one tinted/prominent element per screen, no glass on dense rows, system chrome not re-skinned, no debit/credit colour signal on a tinted surface (FR-047).
- [ ] T121 [US7] Extend `scripts/import-path-audit.sh` with a hard failure on `#available(iOS 26`, `.ultraThinMaterial`, `UIVisualEffectView` or any hand-rolled blur anywhere under `ios/Sources/`.
- [ ] T122 [US7] **GATE** `make lint && make ios-test && make import-audit` — T115 GREEN. Targets live in the repo-root `Makefile`.
- [ ] T123 [US7] Run the manual accessibility gate in `specs/016-statement-import-vertical/quickstart.md` §6 on the simulator: largest Dynamic Type, Dark Mode, Reduce Transparency, Increase Contrast, VoiceOver.

**Checkpoint**: All seven stories are independently functional. The flow has a real front door.

---

## Phase 10: Polish & Cross-Cutting Concerns

- [ ] T124 [P] Create `ios/Tests/ImportMessageAuditTests.swift` asserting that no user-facing string in the flow contains an error code, a reader identifier, a `bank_code`, or `StoreError` / `ReaderError` text — the only engine-supplied string permitted on screen is `Issuer.display_name` (SC-007, FR-034).
- [ ] T125 [P] Update `.scratch/HANDOFF.md` §7 "Key reusable seams" with `detect_issuer`, `read_statement`, `first_anchor_index`, `Store::import_statement`, the `*_in` helpers and schema **v6** (the section still says v3).
- [ ] T126 [P] Update the P3 status line in `docs/kaname-ios-plan.md` to record that the import vertical has landed.
- [ ] T127 [P] Fix the `update-agent-context.sh` artefact in `.github/copilot-instructions.md`: `sed -i '' 's/iOS 18 targe$/iOS 18 target/g; s/iOS 18 targe /iOS 18 target /g' .github/copilot-instructions.md` (`.scratch/HANDOFF.md` §6).
- [ ] T128 Audit `fixtures/` and `ios/Tests/` and confirm every fixture added or edited by this slice is synthetic, that no PDF binary was committed, and that no real account identifier appears anywhere (Constitution I, FR-043, SC-011).
- [ ] T129 Run the manual smoke test in `specs/016-statement-import-vertical/quickstart.md` §5: the 4-tap path, force-quit and relaunch, the same-file re-import, then the full failure matrix (image-only, password right and wrong, corrupt, `.txt` renamed `.pdf`, a utility bill, cancel mid-parse).
- [ ] T130 **FULL GATE** `make core-lint` (`Makefile`).
- [ ] T131 **FULL GATE** `make core-test` (`Makefile`).
- [ ] T132 **FULL GATE** `make core-privacy-audit` (`Makefile`).
- [ ] T133 **FULL GATE** `make lint` (`Makefile`).
- [ ] T134 **FULL GATE** `make ios-gen` (`Makefile`) — depends on `core-xcframework`; never a bare `tuist generate`.
- [ ] T135 **FULL GATE** `make ios-test` (`Makefile`).
- [ ] T136 **FULL GATE** `make import-audit` (`Makefile`) — no networking symbol, no bank literal, no `#available`/`.ultraThinMaterial` under `ios/Sources/`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: depends on Setup. **BLOCKS every user story.** Internally:
  - **2A (deadlock refactor)** → **BLOCKS 2D**. Non-negotiable.
  - **2B (schema v6)** → **BLOCKS 2D** (`import_statement` writes `last4`).
  - **2C (dispatcher)** is independent of 2A/2B — different files, can run in parallel.
  - **2D (`import_statement`)** depends on **2A and 2B**.
  - **2E (gate + `core-xcframework`)** depends on 2B, 2C and 2D — the FFI surface must be final before regeneration.
  - **2F (Swift seams)** depends on 2E (`ios/Generated/` must exist).
- **Design (Phase 2.5)**: depends on Setup; **BLOCKS every UI task** in Phases 3–9.
- **User Stories (Phases 3–9)**: all depend on Phase 2 completing.
- **Polish (Phase 10)**: depends on every desired story being complete.

### User Story Dependencies

- **US1 (P1)** — depends only on Foundational. **The MVP.**
- **US2 (P2)** — depends on Foundational; reuses `ImportSummaryView` and `ImportFailureView` from US1/Foundational. Independently testable.
- **US3 (P3)** — depends on Foundational + the extractor from US1 (T058/T059). Independently testable.
- **US4 (P4)** — depends on Foundational; needs a successful import to exist, so in practice follows US1. Independently testable.
- **US5 (P5)** — depends on Foundational + the pipeline from US1. Independently testable.
- **US6 (P6)** — depends on Foundational + the pipeline from US1. Independently testable.
- **US7 (P7)** — depends on Foundational; replaces the minimal `RootView` from US1 (T066). Independently testable.

### Within Each Story

- RED test tasks are written and **must fail** before their implementation task.
- Engine before bridge; bridge before UI.
- `make core-xcframework` before any `tuist generate` whenever the FFI changed.
- A story is complete only when its verification-gate tasks pass.

### Parallel Opportunities

- **Setup**: T002, T003, T004 in parallel.
- **Foundational**: 2A/2B (both `store.rs`, strictly sequential) can run in parallel with **2C** (`registry.rs` / `ffi.rs` / `base.rs` / `ledger_reader.rs`). T021, T022, T030, T033 are `[P]` against their neighbours.
- **2F**: T047–T051 are five new files — fully parallel.
- **Stories**: once Phase 2 and 2.5 are done, US2, US3, US4, US5, US6 and US7 can be staffed in parallel; only US1 must go first because the others build on its pipeline body.
- **Polish**: T124–T127 in parallel.

---

## Parallel Example: Foundational Phase 2F

```bash
# Five new files, no shared state — launch together:
Task: "Create ios/Sources/Import/ImportModels.swift"
Task: "Create ios/Sources/Import/ImportFailureView.swift"
Task: "Create ios/Sources/Import/StatementTextExtractor.swift"
Task: "Create ios/Sources/Import/ImportService.swift"
Task: "Create ios/Sources/Import/ImportViewModel.swift"
```

## Parallel Example: User Story 1

```bash
# The pipeline test and the network audit touch different trees:
Task: "RED ios/Tests/ImportPipelineTests.swift"
Task: "RED scripts/import-path-audit.sh + Makefile import-audit target"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 — Setup (T001–T005)
2. Phase 2 — Foundational (T006–T052), **2A before 2D, always**
3. Phase 2.5 — Design contract (T053–T055)
4. Phase 3 — User Story 1 (T056–T069)
5. **STOP and VALIDATE**: run the US1 independent test — fresh install, one synthetic statement, correct summary, transactions survive a relaunch, zero network requests.
6. This is a shippable MVP: a person can get their financial history into Kaname.

### Incremental Delivery

Setup + Foundational + Design → US1 (MVP) → US2 (bank-agnostic honesty) → US3 (honest failures) → US4 (correct identity, no doubled history) → US5 (trust) → US6 (responsiveness) → US7 (front door + accessibility) → Polish. Each story adds value without breaking the previous ones, and each ends on its own verification gate.

---

## ⚠️ This slice is too large for one PR — recommended split

**136 tasks** across two languages, one migration, seven new FFI surfaces, ~10 new Swift types and 5 new views. `.scratch/HANDOFF.md` §4's "one slice per PR, two commits" convention does not survive contact with this slice: a single PR would mix a **silent-deadlock refactor**, a **schema migration**, a **new dispatcher**, a **new atomic write path** and **an entire UI flow** into one review — which is precisely the shape of change where a reviewer stops reading.

**Recommended: five PRs.** Each is independently reviewable, independently revertible, and ends on a full green gate.

| PR | Tasks | Contents | Why it stands alone |
|---|---|---|---|
| **PR A — Engine: store hardening** | T001, T006–T017, T035–T046 | The ⚠️ `*_in` deadlock refactor, schema v6, `Store::import_statement`, the FFI regeneration and the Swift call-site update | Highest-risk, smallest surface. The deadlock refactor and the migration deserve a reviewer's full attention and nothing else's. Rust-only + one test file. |
| **PR B — Engine: issuer dispatcher** | T003, T005, T018–T034 | `registry.rs`, `detect_issuer`, `read_statement`, `first_anchor_index`, the `(kind_rank, id)` tie-break, the **three-fixture collision regression**, the parity guard | Touches entirely different files from PR A, so the two can be developed in parallel and reviewed independently. The tie-break argument is a self-contained design review. |
| **PR C — MVP vertical** ✅ merged (#33) | T002, T004, T047–T069 | PDFKit link, the Swift seams, the extractor happy path, the `ImportService` pipeline, the summary sheet, the minimal `RootView`, the network audit | 🎯 The MVP. The first PR that is demoable, and the natural place to stop and validate. Depends on A **and** B. |
| **PR D — Honest failures & correct attribution** | T070–T097, **T137–T139** | US2 (bank-agnosticism, unrecognized, tie-break visibility) + US3 (the five extraction failures, password handling, **the PDFKit extraction-fidelity parity proof and the silent-empty-import notice**) + US4 (account identity, re-import dedup) | The three "don't corrupt or mislead" stories. Split further into **D1 (US2+US3)** and **D2 (US4)** if D exceeds ~600 changed lines — D2 also touches `store.rs`, so it may warrant its own review. |
| **PR E — Trust, responsiveness & the front door** | T098–T136 | US5 (integrity in plain language) + US6 (progress, cancellation, Liquid Glass capsule) + US7 (empty state, accessibility) + Polish | Almost entirely UI and copy; reviewed with a simulator open, against the Liquid Glass and accessibility gates rather than against engine logic. Split into **E1 (US5+US6)** and **E2 (US7+Polish)** if the accessibility sweep drags. |

**Ordering constraints across PRs**: A and B are independent and may land in either order (or in parallel), but **both must land before C**. D depends on C. E depends on C, and its US4-adjacent parts depend on D. Every PR runs the full Local Verification Gate before it opens, and every PR that changes the FFI surface (A, B, D) must run `make core-xcframework` before `make ios-gen`.

---

## Notes

- `[P]` = different files, no shared state, no dependency on an incomplete task.
- `[Story]` maps a task to its user story for traceability; Setup / Foundational / Design / Polish tasks carry none.
- **Verify every RED test actually fails before implementing it.** A test that passes on first write is a test that proves nothing.
- **`rustfmt` reformats your edits**: after a Rust edit run `make core-fmt` and re-read the file before the next edit — your `old_str` may no longer match (`.scratch/HANDOFF.md` §6).
- **swift-format `[Spacing]` rejects trailing inline comments** — put comments on their own line.
- **`cargo` is not on the default PATH**: `export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"` in every shell.
- **Never** commit a real statement, a real account identifier, or a PDF binary. US3's unusable documents are generated at test time with `UIGraphicsPDFRenderer`, never committed.
- Commit after each task or logical group; stop at any checkpoint to validate a story independently.
