---
description: "Task list for 017-column-major-pdf"
---

# Tasks: Column-Major PDF Extraction Fidelity

**Input**: Design documents from `/specs/017-column-major-pdf/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md` (R1–R16), `data-model.md`,
`contracts/extraction-seam.md`, `contracts/engine-recognition.md`,
`contracts/geometry-fixture.md`, `quickstart.md`
**Governing**: `.specify/memory/constitution.md` **v2.0.0** (wins over everything),
`.scratch/HANDOFF.md`, `.github/skills/swiftui-liquid-glass/SKILL.md`

**Tests**: **MANDATORY, not optional.** Constitution Principle V requires test-first (RED → GREEN).
Every behaviour below lands as a failing test *before* the task that makes it pass, and the test
task is sequenced immediately before its implementation task.

**Design**: The tasks-template's Figma phase (Principle IX) **does not apply** — Kaname's
constitution has six principles (I–VI) and there is no Figma tooling in this repo. More
importantly, **this slice adds no UI**: no screen, no message, no accessibility surface changes
(plan.md § Constitution Check IV, SC-012). Phase 2.5 is therefore omitted deliberately.

**Organization**: Tasks are grouped by user story (US1–US6) so each story is independently
completable and testable. **US2 is delivered first** — see the ordering constraint below. It is not
the MVP; it is the load-bearing prerequisite of the MVP.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no shared state, no dependency on an incomplete task)
- **[Story]**: `[US1]`…`[US6]`. Setup, Foundational and Polish tasks carry **no** story label.
- Every task names an exact file path.

## Path Conventions

Two-layer repo (`plan.md` → *Project Structure*):

- **Engine**: `core/crates/kaname-core/src/statement/`, `core/crates/kaname-core/tests/`
- **App**: `ios/Sources/Import/`, `ios/Tests/`, `ios/Project.swift`
- **Fixtures**: `fixtures/geometry/*.json` — **synthetic only, always** (Constitution I, FR-039, SC-010)
- **Gates**: repo-root `Makefile`

---

## ⚠️ Non-negotiables encoded in this list

1. **🔒 MANDATORY DELIVERY ORDER — recognition (US2) lands BEFORE extraction (US1).**
   Research **R16** measured the reverse order: reshaped rows with literal markers turned **11 of
   13** real documents into "not recognised". Recognition-first is safe because the new matching is
   a *superset* of today's for every shipped fixture, so `main` is never worse at any commit. This
   is why **Phase 3 and Phase 4 (US2, PR A + PR B) precede Phase 5 (US1, PR C)** even though US1 is
   the higher-priority story. Do not reorder.
2. **🔒 Gate G7 ships in the SAME PR as the identity-region change (PR A).** Whitespace-insensitive
   matching widens *every* bare-institution marker at once — `hdfc_bank::CLAIM_ALL` is literally
   `["HDFC"]`, and `AU-statment-savings.pdf` is measured to contain `HDFC` inside a UPI
   description. The identity-region projection is what makes the widening safe, and G7 is what
   proves it. **T012/T013 and T023–T028 land together.** Never widen in one PR and fence in another.
3. **⛔ T119 is BLOCKED on an external input (R15).** The exact AU account-kind header literal
   cannot be read from this repository. Its recorded fallback is *defer that one task*: the AU
   file keeps reporting "format not recognised yet" (FR-025) — honest, not wrong. Nothing else in
   the slice depends on it.
4. **Every geometry fixture must be non-vacuous (A4/FR-037/SC-011).** A fixture that passes against
   the pre-slice extraction proves nothing and is deleted or fixed, never kept. This is the exact
   blind spot that let eighteen green fixtures coexist with total failure on real statements.
5. **Fixtures are drawn COLUMN-MAJOR (R1).** Row-major drawing produces a fixture that passes
   before *and* after the fix. Getting this wrong silently voids the entire evidence phase.
6. **Local Verification Gate before every PR** (Constitution § iOS Local Verification Gate):
   `make core-lint && make core-test` for Rust, `make lint && make ios-test` for iOS, plus
   `make core-privacy-audit && make import-audit`. `make core-xcframework` **must** precede
   `tuist generate` — always go through `make ios-gen` / `make ios-test`, never a bare `tuist generate`.
7. **No real statement, and no fragment of one, enters the repository** (FR-039) — not as a
   fixture, not as a test resource, not in a comment, not in a commit message.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish a green, *recorded* baseline and the empty scaffolding, before a single
behaviour changes.

- [x] T001 Establish the green pre-change baseline: `export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"` then run `make core-lint && make core-test && make core-privacy-audit && make import-audit` from the repo-root `Makefile`; record the passing test count in the PR description so any later regression is attributable
- [x] T002 [P] Declare the new engine submodule: add `pub mod claim;` to `core/crates/kaname-core/src/statement/mod.rs` and create an empty `core/crates/kaname-core/src/statement/claim.rs` so the workspace stays compiling
- [x] T003 [P] Create `fixtures/geometry/` with a `fixtures/geometry/README.md` stating the privacy rules P1–P5 from `specs/017-column-major-pdf/contracts/geometry-fixture.md` (fabricated content only; header literals come from the reader's own published claim markers; card numbers masked with invented last-four)
- [x] T004 [P] Confirm the iOS test loop runs locally: `xcrun simctl create "iPhone 16" "iPhone 16"` if absent, then `make ios-gen` (which runs `make core-xcframework` first, per the `ios-gen` target in `Makefile`)

**Checkpoint**: Baseline recorded and green; `claim.rs` declared; fixture directory exists.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Pin what "before this slice" means, on both sides of the seam. Both PR A and PR C
assert against these pins, so neither can start until they exist.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T005 Capture the pre-slice recognition baseline as data: add a `fixture_issuer_baseline` table (fixture relative path → resolved issuer id) covering every fixture under `fixtures/` to `core/crates/kaname-core/tests/dispatcher.rs`, generated from the current `detect_issuer`, and assert it — this table *is* gate G6 (FR-013, SC-004) and must be written while `main` is still unchanged
- [x] T006 [P] Pin the legacy extraction path permanently: document `PDFKitStatementTextExtractor.split(_:)` in `ios/Sources/Import/StatementTextExtractor.swift` as the frozen model of the pre-slice text-layer newline split, keep it `static` and test-visible, and add a comment stating it exists to serve assertion A4 (non-vacuity) forever and must not be deleted when the extractor is rewritten
- [x] T007 [P] Record the pre-slice `ExtractionFidelityTests` expectations as untouchable: add a header comment to `ios/Tests/ExtractionFidelityTests.swift` naming FR-028/SC-005 and stating that `cardLines`, `ledgerLines` and every existing expectation in this file are **frozen** for this slice — extensions may be added, existing expectations may not be edited

**Checkpoint**: The "before" state is pinned on both sides. User story work can begin.

---

## Phase 3: User Story 2 — Reshaping the text does not lose the issuer (Priority: P2) 🔒 SHIPS FIRST — PR A

**Goal**: Make claim matching whitespace-insensitive and scope it to an **identity region** (the
document minus its transaction rows), so that when rows are reshaped in Phase 5 no issuer is lost —
and so the widening cannot manufacture a false claim.

**Independent Test**: For every supported issuer, run `detect_issuer` over both the pre-existing
golden vector text and text with the markers' whitespace mangled (extra spaces, no spaces, a column
gap inside the phrase), and confirm both identify the same issuer; then confirm a statement for
issuer X whose descriptions name issuer Y still resolves to X.

**⚠️ This phase must be merged before Phase 5 (research R16).** T012/T013 (gate G7) must be in the
same PR as T023–T028 (the widening).

### Tests for User Story 2 (write FIRST, confirm RED) ⚠️

- [ ] T008 [P] [US2] Unit tests for C1 whitespace-insensitive comparison in `core/crates/kaname-core/src/statement/claim.rs` (`#[cfg(test)]`): `"Statement of Transactions"`, `"Statement  of Transactions"` and `"StatementofTransactions"` are the same marker; ASCII-lowercasing only; no punctuation stripping, no stemming; normalization applied identically to haystack and marker
- [ ] T009 [P] [US2] Unit tests for C2 `identity_region` in `core/crates/kaname-core/src/statement/claim.rs`: a line is row-like (and excluded) iff it contains a date matching `\d{2}/\d{2}/\d{4}`, `\d{2}/\d{2}/\d{2}` or `\d{2}-[A-Za-z]{3}-\d{4}` **and** an amount matching `[\d,]+\.\d{2}`; a header line carrying a date but no amount survives; a total line carrying an amount but no date survives
- [ ] T010 [P] [US2] Unit tests for C2 `header_region` in `core/crates/kaname-core/src/statement/claim.rs`: the first 15 non-excluded lines only; a marker on line 16 does not match; output is normalized per C1
- [ ] T011 [P] [US2] Purity/determinism tests for `claim.rs` (FR-015): identical input yields identical output across repeated calls; no clock, locale or I/O reachable from either function
- [ ] T012 [P] [US2] **Gate G7 — cross-bank false claim (FR-014)** in `core/crates/kaname-core/tests/dispatcher.rs`: a synthetic AU-shaped ledger whose transaction descriptions contain the literal `HDFC` inside a UPI narration resolves to `AU_BANK`, **not** `HDFC_BANK`; this models the measured AU/HDFC hazard and must be RED before T024
- [ ] T013 [P] [US2] **Gate G7 (second case) — identify by title, not by spend (FR-047)** in `core/crates/kaname-core/tests/dispatcher.rs`: a synthetic HDFC card statement whose descriptions repeat `Swiggy` ~40 times but whose title line does **not** name the product must not be product-claimed off the transaction rows; the title-line case must be
- [ ] T014 [P] [US2] Whitespace-tolerance regression in `core/crates/kaname-core/tests/dispatcher.rs`: the shipped HDFC ledger markers `WithdrawalAmt` and `Statementof account` match whether or not their spaces are present, in both spellings (research R7 — these literals lost their spaces to a *different* extractor)
- [ ] T015 [P] [US2] No-new-claim test (FR-014) in `core/crates/kaname-core/tests/dispatcher.rs`: a document no issuer claimed before the widening is still unclaimed after it; `detect_issuer` returns `None` and never panics on arbitrary input
- [ ] T016 [P] [US2] Header-split recognition test in `core/crates/kaname-core/tests/dispatcher.rs`: a header phrase printed as two columns and rejoined with a single space still resolves to the same issuer (US2 scenario 3)

### Implementation for User Story 2 (PR A)

- [ ] T017 [US2] Implement `normalize_for_claim(&str) -> String` in `core/crates/kaname-core/src/statement/claim.rs` — lowercase then remove every Unicode whitespace character; pure, deterministic, one allocation per normalized marker (C1)
- [ ] T018 [US2] Implement `claim_contains(haystack_normalized: &str, marker: &str) -> bool` in `core/crates/kaname-core/src/statement/claim.rs` (C1)
- [ ] T019 [US2] Implement `identity_region(full_text: &str) -> String` in `core/crates/kaname-core/src/statement/claim.rs` — split into lines, drop row-like lines per T009's rule, normalize per C1 (C2)
- [ ] T020 [US2] Implement `header_region(full_text: &str) -> String` in `core/crates/kaname-core/src/statement/claim.rs` — the first 15 identity lines, normalized (C2, FR-044/FR-047)
- [ ] T021 [US2] Route `line_reader::claims` in `core/crates/kaname-core/src/statement/line_reader.rs` through `claim::claim_contains`, receiving the identity region instead of raw `full_text`
- [ ] T022 [US2] Route `ledger_reader::claims_ledger` in `core/crates/kaname-core/src/statement/ledger_reader.rs` through the same path
- [ ] T023 [US2] Route `hdfc::hdfc_claims` in `core/crates/kaname-core/src/statement/hdfc.rs` through the shared claim path, matching its product title against `header_region` rather than the whole document (FR-047)
- [ ] T024 [US2] Compute the identity region **once per `detect_issuer` call** in `core/crates/kaname-core/src/statement/registry.rs` and pass it to every `claims` fn; keep the FFI signature `detect_issuer(full_text) -> Option<Issuer>` unchanged (C6)
- [ ] T025 [US2] Confirm T008–T016 are now GREEN and that gate G6 (T005) still passes with **identical** per-fixture issuer resolution: `cd core && cargo test --test dispatcher` over `core/crates/kaname-core/tests/dispatcher.rs` (FR-013, SC-004)
- [ ] T026 [US2] Verify no reader's parsing behaviour changed: `core/crates/kaname-core/tests/parity.rs` passes with **unmodified expectations** (FR-029, FR-043)
- [ ] T027 [US2] Run the engine gate for PR A: `make core-lint && make core-test && make core-privacy-audit`
- [ ] T028 [US2] Open PR A containing exactly: `claim.rs`, `line_reader.rs`, `ledger_reader.rs`, `hdfc.rs`, `registry.rs`, and gates G6/G7 — **the widening and its fence in one PR** (non-negotiable #2)

**Checkpoint**: Recognition is whitespace-insensitive and identity-scoped; every previously
recognised document still resolves to the same issuer; the cross-bank false claim is fenced. `main`
is strictly no worse than before. **Phase 5 is now unblocked.**

---

## Phase 4: User Story 2 (continued) — The registry names card products (Priority: P2) — PR B

**Goal**: Identify credit cards at **card-product** granularity, make `bank_code` the bare
institution everywhere, declare each claim's evidence, and resolve competing claims by specificity —
without changing what any reader parses.

**Independent Test**: Every golden fixture resolves to the same reader as before (modulo the renamed
ids), the three doubly-claimed fixtures still resolve to the ledger, and adding a hypothetical
second card entry for an institution whose existing entry is `BankLevel` fails the build.

**Depends on**: Phase 3 merged (PR A). Independent of extraction — may proceed in parallel with
Phase 5 once PR A is in, but must land before Phase 9's fixtures, which reference the new ids.

### Tests for User Story 2 registry work (write FIRST, confirm RED) ⚠️

- [ ] T029 [P] [US2] **Gate G1** in `core/crates/kaname-core/tests/dispatcher.rs`: for every `bank_code` with ≥ 2 `CreditCard` entries, every one of them must be `ProductProven`; include a compile-time-shaped table so adding an `HDFC_INFINIA_CARD` beside `HDFC_SWIGGY_CARD` fails the build (FR-051)
- [ ] T030 [P] [US2] **Gate G2** in `core/crates/kaname-core/tests/dispatcher.rs`: no fixture under `fixtures/` is claimed by two `ProductProven` card entries (FR-048)
- [ ] T031 [P] [US2] **Gate G3** in `core/crates/kaname-core/tests/dispatcher.rs`: every registry id matches `^[A-Z0-9]+_BANK$` or `^[A-Z0-9]+_[A-Z0-9]+_CARD$`, and its institution prefix equals its `bank_code` (FR-052)
- [ ] T032 [P] [US2] **Gate G4** in `core/crates/kaname-core/tests/dispatcher.rs`: no `bank_code` contains `_CARD`, `_BANK` or any product token (FR-046, FR-053)
- [ ] T033 [P] [US2] **Gate G5** in `core/crates/kaname-core/tests/dispatcher.rs`: no `CreditCard` entry claims a bank-account golden fixture and no `BankAccount` entry claims a credit-card one — **test-only, never a runtime rule** (FR-016, research R10)
- [ ] T034 [P] [US2] Specificity-ordering test in `core/crates/kaname-core/tests/dispatcher.rs`: candidates order by `(kind_rank, evidence_rank, id)`; assert explicitly that `fixtures/federal/bank_account/classic.json`, `fixtures/federal/bank_account/fi.json` and `fixtures/icici/bank_account/basic.json` still resolve to the **ledger** (FR-013 — `evidence_rank` is inserted *after* `kind_rank` precisely so these three are untouched)

### Implementation for User Story 2 registry work (PR B)

- [ ] T035 [US2] Add `pub enum ClaimEvidence { ProductProven, BankLevel }` and `fn evidence_rank(ClaimEvidence) -> u8` to `core/crates/kaname-core/src/statement/registry.rs` (C3)
- [ ] T036 [US2] Add the `evidence` field to `ReaderEntry` in `core/crates/kaname-core/src/statement/registry.rs` and populate all ten entries per `data-model.md` § *Registry after this slice* — only `HDFC_SWIGGY_CARD` is `ProductProven` (FR-050, FR-045)
- [ ] T037 [US2] Apply the six card renames in `core/crates/kaname-core/src/statement/registry.rs`: `FEDERAL_CARD`→`FEDERAL_SCAPIA_CARD`, `HDFC_CARD`→`HDFC_SWIGGY_CARD` ("HDFC Swiggy Credit Card"), `ICICI_CARD`→`ICICI_AMAZONPAY_CARD` ("ICICI Amazon Pay Credit Card"), `IOB_CARD`→`IOB_RUPAY_CARD` ("IOB RuPay Credit Card"), `SBI_CARD`→`SBI_CASHBACK_CARD` ("SBI Cashback Credit Card"), `YES_CARD`→`YES_KIWI_CARD` (FR-041, FR-043, FR-052)
- [ ] T038 [US2] Fix `BANK_CODE` in `core/crates/kaname-core/src/statement/sbi.rs`: `"SBI_CARD"` → `"SBI"` (FR-053)
- [ ] T039 [US2] Update the matching literal at `core/crates/kaname-core/src/ffi.rs:231` (`claims(&SbiReader, &full_text, "SBI_CARD")`) to `"SBI"` so the legacy FFI claim path agrees with the registry
- [ ] T040 [US2] Change `detect_issuer`'s `min_by_key` in `core/crates/kaname-core/src/statement/registry.rs` from `(kind_rank, id)` to `(kind_rank, evidence_rank, id)` (FR-048)
- [ ] T041 [US2] Update asserted ids in `core/crates/kaname-core/tests/dispatcher.rs` (including the `registry_bank_code_matches_the_backing_reader_constant` table) — ids change, **expectations do not** (FR-029)
- [ ] T042 [US2] Update asserted ids in `core/crates/kaname-core/tests/parity.rs` — ids only; every parsed result stays byte-for-byte identical (FR-029, SC-005)
- [ ] T043 [P] [US2] Update the id references in `docs/adr/0004-unknown-bank-ingestion.md` and `.scratch/HANDOFF.md` to the renamed entries
- [ ] T044 [US2] Confirm `scripts/import-path-audit.sh` still passes — its bank-literal check reads literals out of the registry and must need no change (contract C4)
- [ ] T045 [US2] Run the engine gate for PR B: `make core-lint && make core-test && make core-privacy-audit && make import-audit`

**Checkpoint**: The registry names products, `bank_code` is the bare institution everywhere, G1–G5
are enforced mechanically, and no reader parses anything differently.

---

## Phase 5: User Story 1 — A real statement imports all of its transactions (Priority: P1) 🎯 THE SLICE — PR C

**Goal**: Rewrite extraction so each **printed row** arrives as one line, regardless of how the PDF
text layer chopped it — joining columns it split and splitting rows it merged, in one pass.

**Independent Test**: Render a synthetic column-major document per the geometry-fixture contract,
import it through the real extractor, the real dispatcher and the real reader, and assert the
transaction count, dates, exact decimal amounts and directions against the vector's declared
expectations — and assert the *legacy* path reads strictly fewer.

**🔒 Depends on Phase 3 being MERGED (research R16).** Starting the rewrite before PR A is on `main`
reproduces the measured 11-of-13 regression.

### Tests for User Story 1 (write FIRST, confirm RED) ⚠️

- [ ] T046 [P] [US1] Create the column-major renderer `ios/Tests/GeometryFixtureRenderer.swift`: decode the `fixtures/geometry/*.json` schema (signature, columns, header_lines, footer_lines, rows, expected) and draw it with `UIGraphicsPDFRenderer` to a temporary file — **column-major (R1)**: every cell of column 1 top-to-bottom, then column 2, and so on; cell at `x = column.x`, `y = first_row_y - index * row_pitch`; header/footer drawn as ordinary single-column lines (R2, R3); the file is deleted after the test (R4)
- [ ] T047 [P] [US1] Add the pilot vector `fixtures/geometry/yes_kiwi_card.json` — the validated reference case from research R12 (35 column positions, 21.3 pt row pitch, `DD/MM/YYYY`), `issuer_id: "YES_KIWI_CARD"`, four rows with at least one debit and one credit, header literals taken from `yes.rs`'s own published claim markers, everything else fabricated, `expected.legacy_max_transactions: 0`
- [ ] T048 [US1] Create `ios/Tests/GeometryFixtureTests.swift` asserting A1–A7 for every file in `fixtures/geometry/`: A1 `detectIssuer` returns `expected.issuer_id`; A2 parsed transactions equal `expected.transactions` exactly; A3 count ≤ printed `rows`; A4 **non-vacuity** — parsing `PDFKitStatementTextExtractor.split(fullText)` of the same document yields at most `legacy_max_transactions`, which must be strictly less than `expected.transactions.count`; A5 double import is byte-identical; A6 ≥1 debit and ≥1 credit with every direction matching; A7 no non-whitespace character lost
- [ ] T049 [US1] **Confirm RED**: run `ios/Tests/GeometryFixtureTests.swift` against the unmodified `ios/Sources/Import/StatementTextExtractor.swift` and record that the pilot vector reads **0 of 4** rows — this is the reported bug reproduced under test (quickstart § *Smoke test* step 2, FR-037)
- [ ] T050 [P] [US1] Extend `ios/Tests/StatementTextExtractorTests.swift` with the E6 losslessness invariant: the multiset of non-whitespace characters across `lines` equals that of the page strings (FR-007)
- [ ] T051 [P] [US1] Extend `ios/Tests/StatementTextExtractorTests.swift` with the E7 determinism invariant: extracting the same file twice yields byte-identical `lines` **and** `lineWords` (FR-009, SC-007)
- [ ] T052 [P] [US1] Extend `ios/Tests/StatementTextExtractorTests.swift` with the band-cap test: a band's union may not exceed `2.0 ×` the page's median word height, so a wide table on tight leading cannot swallow the row above or below (research R3, spec Edge Cases)
- [ ] T053 [P] [US1] Extend `ios/Tests/StatementTextExtractorTests.swift` with the E8 per-page fallback test: a page whose geometry cannot be trusted falls back to the text layer's newline split **for that page only** and contributes no `lineWords`, while its sibling pages still reconstruct (FR-010, research R6)
- [ ] T054 [P] [US1] Extend `ios/Tests/StatementTextExtractorTests.swift` with the E9 index-consistency test: `LineWords.lineIndex` indexes `lines`, and the listed words are exactly that line's words, in the same order, with the x-extents at which they were printed (FR-011)
- [ ] T055 [P] [US1] Extend `ios/Tests/StatementTextExtractorTests.swift` with the all-page `lineWords` test: a multi-page document emits `lineWords` for lines on pages 2+, not page 1 only (FR-008, research R11)
- [ ] T056 [P] [US1] Extend `ios/Tests/StatementTextExtractorTests.swift` with the zoning test: two side-by-side panels separated by a full-height gutter do not produce interleaved nonsense rows (research R4, spec Edge Cases)

### Implementation for User Story 1 (PR C)

- [ ] T057 [US1] Add the `PositionedWord` value (`text`, `range`, `xMin`, `xMax`, `yExtent`) to `ios/Sources/Import/StatementTextExtractor.swift` and build it per page: split the page string into maximal non-separator UTF-16 runs (`unit <= 0x20 || unit == 0x00A0`), taking `xMin`/`xMax` from the first/last usable glyph bounds and `yExtent` from the union of usable ink extents; a glyph is usable iff `!isNull && minY.isFinite && maxY.isFinite && height > 0.5` (the shipped guard, unchanged) — contract E-Algorithm step 2, data-model § `PositionedWord`
- [ ] T058 [US1] Add the `Zone` value and gutter detection to `ios/Sources/Import/StatementTextExtractor.swift`: project every word's `[xMin, xMax]` onto the x-axis; a maximal x-interval no word overlaps and at least `4 ×` the page's median space width wide is a gutter; gutters partition the page into zones emitted left-to-right; zones must **partition** the words — every word in exactly one zone (E-Algorithm step 3, research R4)
- [ ] T059 [US1] Add the `RowBand` value and the band sweep to `ios/Sources/Import/StatementTextExtractor.swift`: within a zone, sort words by `(-yMax, xMin, utf16Start)` and sweep — a word joins the current band iff it overlaps by more than a quarter of the shorter height (the shipped `sharesARow`) **and** the resulting union does not exceed `2.0 ×` the page's median word height; otherwise it opens a new band (E-Algorithm step 4, FR-003, FR-006)
- [ ] T060 [US1] Handle orphans in `ios/Sources/Import/StatementTextExtractor.swift`: a word with no usable `yExtent` joins the band of the nearest **preceding word in text order** and is never dropped (E-Algorithm step 6, FR-007)
- [ ] T061 [US1] Emit lines in `ios/Sources/Import/StatementTextExtractor.swift`: per band, sort members by `(xMin, utf16Start)` and join with exactly one `U+0020`, trimming trailing separators; bands ordered by descending `extent.upperBound`, then ascending first-member `xMin`, then ascending `range.lowerBound` — a **total** order (E1, E4, FR-005, FR-009, research R5)
- [ ] T062 [US1] Emit `lineWords` for **every** reconstructed line of **every** page in `ios/Sources/Import/StatementTextExtractor.swift`, replacing the page-1-only behaviour; pages in geometry fallback contribute none (FR-008, FR-011, research R11)
- [ ] T063 [US1] Implement the per-page trust guard in `ios/Sources/Import/StatementTextExtractor.swift`: `page.string` non-nil, `page.numberOfCharacters == page.string.utf16.count`, and at least one glyph yielding usable bounds — otherwise fall back to the newline split **for that page only**, silently (E8, FR-010, FR-034 — the extractor deliberately reports nothing about why a page fell back)
- [ ] T064 [US1] Keep `PDFKitStatementTextExtractor.split(_:)` in `ios/Sources/Import/StatementTextExtractor.swift` intact and reachable after the rewrite (T006's pin) — assertion A4 depends on it forever
- [ ] T065 [US1] Confirm T048's `ios/Tests/GeometryFixtureTests.swift` is now **GREEN** for the pilot vector, with A4 still proving the legacy path reads strictly fewer (FR-037, SC-011)
- [ ] T066 [US1] Confirm `ios/Tests/ExtractionFidelityTests.swift` passes with **unmodified expectations** — the slice-016 tight-layout merge case must still resolve (FR-028, SC-005)
- [ ] T067 [US1] Run the full gate for PR C: `make core-lint && make core-test && make lint && make ios-test && make import-audit`

**Checkpoint**: A column-major statement imports every transaction it prints. The pilot vector went
from 0 of 4 to 4 of 4, and the legacy path still reads 0 — the fixture is provably non-vacuous.

---

## Phase 6: User Story 3 — The money keeps its meaning after reshaping (Priority: P3)

**Goal**: A reconstructed row says what the printed row says — the amount is the amount, the
`Dr`/`Cr` marker sits where the reader expects it relative to the amount, a withdrawal never becomes
a deposit, and a description never swallows the next column's figure.

**Independent Test**: Import synthetic column-major documents containing both a debit and a credit
for both statement kinds — including a bank ledger whose direction comes from the running-balance
delta and the withdrawal/deposit column position — and assert every direction against the vector's
declared expectation.

**Depends on**: Phase 5.

### Tests for User Story 3 (write FIRST, confirm RED) ⚠️

- [ ] T068 [P] [US3] Direction-marker placement test in `ios/Tests/GeometryFixtureTests.swift`: for a card vector whose `direction` column sits to the right of `amount`, the reconstructed line places the `Dr`/`Cr` marker in the same position relative to the amount as it was printed (FR-020, US3 scenario 1)
- [ ] T069 [P] [US3] Ledger direction test in `ios/Tests/GeometryFixtureTests.swift`: for a bank-account vector, the amount and balance land in the correct columns and the derived direction matches the printed ledger (FR-019, US3 scenario 2)
- [ ] T070 [P] [US3] Row-1 bootstrap test in `ios/Tests/GeometryFixtureTests.swift`: for a multi-page ledger vector whose first anchor row is **not** on page 1, the reported word positions still describe where the figures were printed, so the withdrawal-vs-deposit column bootstrap remains correct rather than degrading to `Row1Provisional` (FR-011, US3 scenario 3, research R11)
- [ ] T071 [P] [US3] Column-separability test in `ios/Tests/StatementTextExtractorTests.swift`: two adjacent columns pushed together by reshaping remain two values separated by a single space and are never concatenated into one unsplittable token (FR-005, US3 scenario 4)
- [ ] T072 [P] [US3] Blank-column test in `ios/Tests/GeometryFixtureTests.swift`: a ledger row printing only one of the withdrawal/deposit columns must not shift the remaining values into the wrong slots (spec Edge Cases)
- [ ] T073 [P] [US3] Amount-shape test in `ios/Tests/StatementTextExtractorTests.swift`: amounts printed with a currency symbol, in parentheses, or with a trailing minus are not mistaken for a column boundary and are not split into two tokens (spec Edge Cases)

### Implementation for User Story 3

- [ ] T074 [US3] Fix any column-slot or marker-placement defect T068–T073 expose in `ios/Sources/Import/StatementTextExtractor.swift`'s band ordering or join rule — **no issuer-specific knowledge may enter the extractor** (contract § Non-obligations); if a defect is genuinely reader-side, fix it in the reader and record why
- [ ] T075 [US3] Assert the engine's integrity checks run over the newly readable rows and report their verdicts as they do today: extend `ios/Tests/ImportIntegrityTests.swift` with a geometry-rendered document so the bank balance chain and the credit-card reconciliation against printed totals are exercised end-to-end (FR-023)
- [ ] T076 [US3] Byte-identical re-import test in `ios/Tests/GeometryFixtureTests.swift` (assertion A5): importing the same rendered document twice yields identical lines *and* identical transactions, with money exact `Decimal` at every hop (FR-021, SC-007)
- [ ] T077 [US3] Run the gate: `make core-test && make lint && make ios-test`

**Checkpoint**: No direction is inverted; no value lands in the wrong column; money is exact and
re-import is byte-identical.

---

## Phase 7: User Story 4 — The opposite failure stays fixed (Priority: P4)

**Goal**: One algorithm both **splits** rows the text layer merged and **joins** columns it split —
simultaneously, on the same page, with neither capability re-opening the other's bug.

**Independent Test**: Run the existing extraction-fidelity suite unchanged, then add a document
exhibiting both hazards at once and confirm both are resolved in one pass.

**Depends on**: Phase 5.

### Tests for User Story 4 (write FIRST, confirm RED) ⚠️

- [ ] T078 [P] [US4] Add `fixtures/geometry/both_hazards.json`: a `row_pitch` tight enough that the text layer *merges* adjacent rows **and** a column-major draw order, so one document carries both hazards (R5, FR-030); declare `legacy_max_transactions` strictly below the expected count
- [ ] T079 [US4] Extend `ios/Tests/ExtractionFidelityTests.swift` with the both-hazards document — **adding** a case, leaving every existing expectation untouched (FR-028, FR-030, T007's pin)
- [ ] T080 [P] [US4] Unchanged-document test in `ios/Tests/ExtractionFidelityTests.swift`: a single-column document that already extracted correctly still produces exactly the transactions it produced before — reshaping never alters a document that was already read correctly (US4 scenario 3)
- [ ] T081 [P] [US4] Over-join test in `ios/Tests/GeometryFixtureTests.swift` (assertion A3): no vector produces **more** transactions than it prints; an address block printed beside a summary box at the same height must not be fused into a fake row (FR-006, SC-003, spec Edge Cases)
- [ ] T082 [P] [US4] Wrapped-narration test in `ios/Tests/GeometryFixtureTests.swift`: a description too long for its column continues on the next visual row and must stay **two** lines, so the ledger's existing narration stitching keeps working (spec Edge Cases)
- [ ] T083 [P] [US4] Repeating header/footer test in `ios/Tests/GeometryFixtureTests.swift`: a page header or footer sharing a band with the first or last row is not absorbed into a transaction (spec Edge Cases)

### Implementation for User Story 4

- [ ] T084 [US4] Resolve any defect T078–T083 expose in the band sweep or zoning in `ios/Sources/Import/StatementTextExtractor.swift`, keeping the outcome deterministic where horizontal and vertical grouping disagree (spec Edge Cases — "must not silently prefer the wrong one")
- [ ] T085 [US4] Run the gate and confirm the slice-016 parity proof still passes unmodified: `make core-test && make lint && make ios-test`

**Checkpoint**: Both hazards resolve in one pass; the slice-016 fix is not re-opened.

---

## Phase 8: User Story 5 — A layout it still cannot read says so (Priority: P5)

**Goal**: Preserve, through a change that reshapes the very text these judgements are made from, the
honest-failure behaviour shipped in slice 016 — never an unreadable statement presented as an empty
one, never engine internals in a message.

**Independent Test**: Import a document whose geometry cannot be trusted, a document no issuer
claims, and a supported-issuer document in an uncovered layout variant, and confirm each produces
its own plain-language outcome and imports nothing silently.

**Depends on**: Phase 5.

### Tests for User Story 5 (write FIRST, confirm RED) ⚠️

- [ ] T086 [P] [US5] Untrusted-geometry test in `ios/Tests/ImportPipelineTests.swift`: a document whose character positions disagree with its text (ligatures / unusual encodings) falls back safely and yields either a correct import or an honest failure — never a confidently wrong transaction (FR-010, US5 scenario 1)
- [ ] T087 [P] [US5] Nothing-recognised test in `ios/Tests/ImportPipelineTests.swift`: a recognised issuer from which no transaction can be read reports "nothing could be recognised" **unless** the statement's own printed figures confirm it is genuinely empty (FR-024, preserved from slice 016)
- [ ] T088 [P] [US5] Genuinely-empty test in `ios/Tests/ImportPipelineTests.swift`: a statement legitimately containing zero transactions is still reportable as a **successful** zero-transaction import and does not become "nothing recognised" as a side effect of reshaping (FR-031, spec Edge Cases)
- [ ] T089 [P] [US5] Unclaimed-document test in `ios/Tests/ImportPipelineTests.swift`: nothing is written to the store and the person is told the format is not recognised yet (FR-025, FR-027)
- [ ] T090 [P] [US5] Store-untouched test in `ios/Tests/ImportStoreIntegrityTests.swift`: every failure path on this slice leaves the encrypted store exactly as it was (FR-027, US5 scenario 5)
- [ ] T091 [US5] Message-audit test in `ios/Tests/ImportMessageAuditTests.swift`: **zero** user-visible messages are added or changed by this slice, and none contains a reader name, an error code or raw error text (FR-026, SC-012)

### Implementation for User Story 5

- [ ] T092 [US5] Fix any honest-failure regression T086–T091 expose in `ios/Sources/Import/ImportService.swift`, **without adding a new user-visible message** — SC-012 holds by construction and must keep holding
- [ ] T093 [US5] Run the gate: `make lint && make ios-test && make import-audit`

**Checkpoint**: Every failure is still honest, still silent about internals, and still leaves the
store untouched.

---

## Phase 9: User Story 6 — The fix is proven without a single real statement entering the repository (Priority: P6) — PR D

**Goal**: Complete the synthetic evidence: all ten issuer vectors, both statement kinds, both date
formats, the cross-bank false-claim vector, and the standing non-vacuity gate.

**Independent Test**: Inspect every file added by this slice for real merchant names, amounts, dates
and account numbers; confirm every vector fails against the pre-slice extraction; confirm the local
verification path works against an arbitrary directory without writing any content anywhere.

**Depends on**: Phase 4 (the renamed ids these vectors assert) and Phase 5 (the behaviour they
assert against).

### Fixture vectors (all [P] — different files, all asserted by the T048 harness) ⚠️

- [ ] T094 [P] [US6] `fixtures/geometry/au_bank.json` — bank_account, `DD/MM/YYYY`, ledger roles (date/description/reference/withdrawal/deposit/balance), declares printed opening and closing balances; header literals from `au_bank.rs`'s published `CLAIM_ALL`/`CLAIM_ANY` only (the C5 header phrase is added later by T119 if it arrives)
- [ ] T095 [P] [US6] `fixtures/geometry/federal_bank.json` — bank_account, `DD/MM/YYYY`
- [ ] T096 [P] [US6] `fixtures/geometry/hdfc_bank.json` — bank_account, `DD/MM/YY`; header deliberately exercises the `WithdrawalAmt` / `Statementof account` whitespace tolerance from Phase 3
- [ ] T097 [P] [US6] `fixtures/geometry/icici_bank.json` — bank_account, `DD/MM/YYYY`, **multi-page** so it proves FR-008 beyond page 1
- [ ] T098 [P] [US6] `fixtures/geometry/federal_scapia_card.json` — credit_card, `DD/MM/YYYY`
- [ ] T099 [P] [US6] `fixtures/geometry/hdfc_swiggy_card.json` — credit_card, `DD-MMM-YYYY`; the title line names the product and the descriptions repeat `Swiggy`, so it must identify by title and not by spend (FR-047, the `ProductProven` case)
- [ ] T100 [P] [US6] `fixtures/geometry/icici_amazonpay_card.json` — credit_card, `DD/MM/YYYY`
- [ ] T101 [P] [US6] `fixtures/geometry/iob_rupay_card.json` — credit_card, `DD-MMM-YYYY`, drawn so that **no** emitted text-layer line carries a date (US1 scenario 4)
- [ ] T102 [P] [US6] `fixtures/geometry/sbi_cashback_card.json` — credit_card, `DD/MM/YYYY`; descriptions name rival SBI products, so the product must not be read from the rows (FR-044)
- [ ] T103 [P] [US6] `fixtures/geometry/cross_bank_false_claim.json` — a statement for issuer X whose transaction descriptions name institution Y, modelled on the measured AU/HDFC case; must resolve to X (FR-014, the geometry counterpart of gate G7)

### Evidence gates and privacy review

- [ ] T104 [US6] Confirm every vector in `fixtures/geometry/` added by T094–T103 declares `legacy_max_transactions` **strictly less** than `expected.transactions.count`, and that A4 in `ios/Tests/GeometryFixtureTests.swift` fails loudly if it does not — a vector that passes against the pre-slice extractor is deleted or fixed, never kept (FR-037, SC-011)
- [ ] T105 [US6] Confirm coverage per FR-038 with a test in `ios/Tests/GeometryFixtureTests.swift` that fails if any of the ten registry ids has no vector, if either statement kind is missing, or if either of `DD-MMM-YYYY` / `DD/MM/YYYY` is unrepresented
- [ ] T106 [US6] Extend the same coverage test in `ios/Tests/GeometryFixtureTests.swift` to fail if any `fixtures/geometry/*.json` declares fewer than one debit or fewer than one credit (assertion A6, SC-006)
- [ ] T107 [US6] **Privacy review of every file added by this slice** (SC-010, FR-039): read each `fixtures/geometry/*.json` — including `_comment` fields — and each new Swift/Rust file, and confirm no merchant, amount, date, account number or card number can be traced to a real statement; card numbers are masked with invented last-four (P5); header literals are the readers' own published claim markers (P2); record the review in the PR description
- [ ] T108 [US6] Run the full gate for PR D: `make core-lint && make core-test && make lint && make ios-test && make core-privacy-audit && make import-audit`

**Checkpoint**: All ten issuers, both kinds, both date formats, both hazards and the cross-bank case
are pinned by synthetic vectors that provably fail against the pre-slice extraction.

---

## Phase 10: Polish, Gates & Sign-off — PR E

**Purpose**: Close the success criteria that neither CI nor a fixture can close: the human-run
reference pass, performance and cancellation, and the documentation trail.

- [ ] T109 [P] Add `ios/Tests/ReferenceSetVerification.swift`: a suite **skipped by default**, running only when `KANAME_REFERENCE_DIR` is set; for each PDF in that directory it runs the real extractor and the real dispatcher and prints exactly two facts — the issuer display name and the transaction count. It writes **nothing**: not to the repository, not to the store, not to a file, not to a log, not to the network, and it never prints a line of statement text, a merchant, an amount, a date or an account number (FR-040, FR-034, research R13)
- [ ] T110 Add a `reference-check` target to the repo-root `Makefile` (`make reference-check DIR=…`) that sets `KANAME_REFERENCE_DIR` and runs only `ReferenceSetVerification`; add it to `.PHONY`
- [ ] T111 [P] Extend `ios/Tests/ImportCancellationTests.swift` with the E12 obligation: a 40+-page rendered document extracts off the main thread with `Task.checkCancelled()` between pages and honours cancellation within **2 s** (FR-035, SC-008, research R14)
- [ ] T112 [P] Add a per-page cost assertion in `ios/Tests/StatementTextExtractorTests.swift` that `characterBounds(at:)` is called at most once per non-separator UTF-16 unit — i.e. the shipped call volume is not regressed by a per-word PDFKit re-query (research R14)
- [ ] T113 Verify SC-009 end to end: `make core-privacy-audit && make import-audit` are green and zero network requests occur anywhere on the path (FR-033)
- [ ] T114 [P] Update `AGENTS.md` and `.scratch/HANDOFF.md` with the new extraction contract (lines are printed rows, `lineWords` is all-page), the renamed registry ids, and the `claim.rs` identity-region rule
- [ ] T115 [P] Record the deferred decision in `docs/adr/0004-unknown-bank-ingestion.md`: `issuer_id` persistence (schema v7) is **deliberately deferred** and must land before first release (research R9)
- [ ] T116 **Human-run reference pass (SC-002 — the slice cannot be signed off without it)**: the reference-set holder runs `make reference-check DIR=/path/to/their/own/statements` and records **counts only** in the PR description, in the manner of slice 016's T123/T129. Target: statements importing zero transactions falls from **10 to 0**; statements whose issuer is unrecognised falls from **2** to at most those covered by the open questions
- [ ] T117 Walk `specs/017-column-major-pdf/quickstart.md` § *Definition of done* and tick every box, or record why a box cannot be ticked
- [ ] T118 Run the complete Local Verification Gate one final time: `make core-lint && make core-test && make core-privacy-audit && make import-audit && make lint && make ios-test`

### ⛔ Blocked task (external input required)

- [ ] T119 ⛔ **BLOCKED on research R15** — add the exact account-kind header literal that `AU-statment-savings.pdf` prints to `au_bank::CLAIM_ANY` in `core/crates/kaname-core/src/statement/au_bank.rs`, and add that phrase to the header block of `fixtures/geometry/au_bank.json` (T094).
  - **Blocked by**: the literal cannot be read from this repository — the file is private. Only the reference-set holder can supply it (research R15, contract C5).
  - **Constraints when it arrives**: the literal MUST come from the **header region**, MUST state the account kind or document title, MUST NOT be a bare institution name (that is the identity-region hazard), and MUST NOT be a token copied from a transaction row.
  - **Ships with**: gate G7 (T012/T013) green, and the AU geometry vector carrying the phrase.
  - **Where it rides**: PR B if the literal is available by then; otherwise PR E; otherwise its own follow-up.
  - **Recorded fallback if never supplied**: defer this task alone. `AU-statment-savings.pdf` keeps reporting "format not recognised yet" (FR-025) — honest, not wrong. **No other task in this slice depends on it**, and SC-002's "at most the number covered by the open scope questions" clause already accounts for it.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Setup)**: no dependencies — start immediately
- **Phase 2 (Foundational)**: depends on Phase 1 — **blocks every user story** (it pins what "before" means)
- **Phase 3 (US2, PR A)**: depends on Phase 2. **Blocks Phase 5.** 🔒
- **Phase 4 (US2, PR B)**: depends on Phase 3 merged. Blocks Phase 9 (its vectors assert the new ids). May run in parallel with Phase 5.
- **Phase 5 (US1, PR C)**: depends on **Phase 3 being merged** (research R16). Blocks Phases 6, 7, 8, 9.
- **Phase 6 (US3)**, **Phase 7 (US4)**, **Phase 8 (US5)**: each depends on Phase 5; mutually independent
- **Phase 9 (US6, PR D)**: depends on Phase 4 **and** Phase 5
- **Phase 10 (PR E)**: depends on all of the above; T116 depends on an external human

### The one ordering constraint that is not negotiable

```text
Phase 3 (recognition)  ──merged──▶  Phase 5 (extraction)
        PR A                                PR C
```

Shipping C before A is the measured **11-of-13** regression (research R16). There must never be a
commit on `main` with reshaped text and literal markers.

### Within Phase 3, one more grouping is not negotiable

`T012`, `T013` (gate G7) and `T017`–`T024` (the widening) are **one PR**. The widening without its
fence re-opens the AU/HDFC false-claim hazard on every bare-institution marker at once.

### Within each user story

- Tests are written and confirmed **RED** before the implementation task that makes them GREEN
- Values/types before the algorithms that use them (T057 → T058 → T059 → T060 → T061)
- Engine before platform where the platform asserts against engine ids
- Gate run closes each phase

### Parallel opportunities

- **Phase 1**: T002, T003, T004 in parallel
- **Phase 2**: T006, T007 in parallel
- **Phase 3 tests**: T008–T016 all in parallel (`claim.rs` unit tests and `dispatcher.rs` gates are separate concerns; if two authors touch `dispatcher.rs`, serialise T012–T016)
- **Phase 4 tests**: T029–T034 all in parallel
- **Phase 5 tests**: T046, T047 in parallel; then T050–T056 in parallel once the harness exists
- **Phase 6**: T068–T073 in parallel
- **Phase 7**: T078, T080–T083 in parallel
- **Phase 8**: T086–T090 in parallel
- **Phase 9**: T094–T103 — **ten independent fixture files, the largest parallel block in the slice**
- **Phase 10**: T109, T111, T112, T114, T115 in parallel
- **Across phases**: Phase 4 (PR B) and Phase 5 (PR C) can be worked simultaneously by two people once PR A is merged

---

## Parallel Example: Phase 9 (the fixture block)

```bash
# Ten independent JSON vectors, no shared file, all asserted by the same harness:
Task: "fixtures/geometry/au_bank.json — bank_account, DD/MM/YYYY, ledger roles"
Task: "fixtures/geometry/federal_bank.json — bank_account, DD/MM/YYYY"
Task: "fixtures/geometry/hdfc_bank.json — bank_account, DD/MM/YY, whitespace-tolerance header"
Task: "fixtures/geometry/icici_bank.json — bank_account, DD/MM/YYYY, multi-page"
Task: "fixtures/geometry/federal_scapia_card.json — credit_card, DD/MM/YYYY"
Task: "fixtures/geometry/hdfc_swiggy_card.json — credit_card, DD-MMM-YYYY, ProductProven"
Task: "fixtures/geometry/icici_amazonpay_card.json — credit_card, DD/MM/YYYY"
Task: "fixtures/geometry/iob_rupay_card.json — credit_card, DD-MMM-YYYY, no date-bearing line"
Task: "fixtures/geometry/sbi_cashback_card.json — credit_card, DD/MM/YYYY, rival products in rows"
Task: "fixtures/geometry/cross_bank_false_claim.json — issuer X, descriptions naming Y"
```

---

## Parallel Example: Phase 3 (recognition tests, all RED first)

```bash
Task: "C1 whitespace-insensitive comparison unit tests in core/crates/kaname-core/src/statement/claim.rs"
Task: "C2 identity_region row-like exclusion unit tests in core/crates/kaname-core/src/statement/claim.rs"
Task: "C2 header_region 15-line cap unit tests in core/crates/kaname-core/src/statement/claim.rs"
Task: "Gate G7 AU/HDFC cross-bank false claim in core/crates/kaname-core/tests/dispatcher.rs"
Task: "Gate G7 HDFC Swiggy identify-by-title-not-by-spend in core/crates/kaname-core/tests/dispatcher.rs"
```

---

## Implementation Strategy

### The delivery increment is not the priority order

The MVP of this slice — the thing a person notices — is **US1 (Phase 5)**. But US1 cannot ship
first: reshaping without recognition was measured to break 11 of 13 documents. So the delivery
increments are:

1. **Phase 1 + 2** → the "before" state is pinned on both sides
2. **Phase 3 (PR A)** → recognition widened and fenced. *User-visible change: none.* `main` is
   provably no worse — every fixture resolves identically.
3. **Phase 4 (PR B)** → registry names products. *User-visible change: card statements are labelled
   by product instead of by bank.* No parsing changes.
4. **Phase 5 (PR C)** → 🎯 **the slice**. *User-visible change: statements that reported "no
   spending" import their rows.*
5. **Phase 6 + 7 + 8** → the money is right, the old bug stays fixed, the failures stay honest
6. **Phase 9 (PR D)** → the evidence becomes a standing gate
7. **Phase 10 (PR E)** → the human-run pass closes SC-002 and the slice is signed off

### Stop-and-validate points

- **After Phase 3**: `make core-test` green **and** every fixture's issuer unchanged. If any issuer
  moved, stop — do not proceed to Phase 5.
- **After T049**: `GeometryFixtureTests` must be **RED** with a transaction count of 0. If it is
  green before the rewrite, the fixture is vacuous — it was probably drawn row-major (R1). Fix the
  fixture before writing a line of extractor code.
- **After Phase 5**: `ExtractionFidelityTests` green with unmodified expectations. If it needed an
  expectation edited, the slice-016 bug has been re-opened.
- **After T116**: zero-transaction files must be **0**. If not, the geometry vectors modelled the
  layouts wrongly — which is precisely why spec Q3 chose Option A and made this a human gate.

### Parallel team strategy

1. One person completes Phase 1 + 2 + 3 (PR A) — it is on the critical path and nothing else may start
2. Once PR A merges: **Developer A** takes Phase 4 (PR B, engine), **Developer B** takes Phase 5
   (PR C, platform) — different languages, different files, no overlap
3. Once PR C merges: Phases 6, 7 and 8 fan out to three people
4. Phase 9's ten fixtures fan out arbitrarily wide
5. Phase 10 converges; T116 waits on the reference-set holder

---

## Notes

- `[P]` = different files, no dependencies, no shared state
- `[Story]` maps a task to a spec user story for traceability; Setup, Foundational and Polish carry none
- Verify tests fail before implementing — a test that was never RED proves nothing (this slice
  exists because eighteen green fixtures coexisted with total failure)
- Commit after each task or logical group; keep PR boundaries exactly as § *Delivery order* defines them
- **Never** run a bare `tuist generate` — always `make ios-gen` / `make ios-test`, so
  `make core-xcframework` runs first
- No task in this slice adds a user-visible message, a screen, a dependency, an FFI shape change or
  a schema migration. If a task seems to need one, stop and re-read `plan.md` § *Constitution Check*
