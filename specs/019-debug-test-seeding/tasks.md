---
description: "Task list for 019-debug-test-seeding"
---

# Tasks: DEBUG-Only Test Seeding — Let an Automated Run Reach a Screen That Has Data In It

**Input**: Design documents from `/specs/019-debug-test-seeding/`
**Prerequisites**: `spec.md` (FR-001–FR-049, SC-001–SC-017, US1–US6, **including § *Amendments after `/speckit.plan`***), `plan.md`, `research.md` (R1–R20, evidence E1–E5), `data-model.md`, `contracts/seeded-launch.md` (L/S/D/E/A assertions), `contracts/release-absence-audit.md` (both scans, the self-check, the five breaks), `quickstart.md`
**Governing**: `.specify/memory/constitution.md` (wins over everything), `.scratch/HANDOFF.md`, `specs/018-transaction-list/tasks.md` (the house style this list follows)

**Tests**: **MANDATORY**, not optional — and in this slice they run in *two* directions. Constitution Principle V requires RED → GREEN for every behaviour, so each named assertion (`contracts/seeded-launch.md` §4) is written before the code that satisfies it. But the **gates themselves are also written test-first**: an absence proof that has only ever been green proves nothing, so every scan in this list has a numbered task that watches it turn red before it is trusted (FR-030, FR-038, SC-005, SC-006).

**No test in this slice may be disabled.** Not `@Test(.disabled(…))`, not `#[ignore]`, not `XCTSkip`, not commented out. T091 greps for the escape hatches.

**Organization**: Tasks are grouped by **PR**, and within a PR by **user story**, because `plan.md` § *Delivery order* is mandatory rather than advisory. ⚠️ **The order here deliberately inverts 018's.** 018 was forced to ship the engine first because the xcframework is resolved at Tuist generation time. Nothing crosses the FFI here, so the ordering is chosen for a different reason: **the proof that the seeding path cannot ship is built and watched failing before the seeding path exists.** The price is paid before the capability is bought — and if the gate cannot be made to work, the slice stops at PR A with nothing that fabricates financial data having been written.

| PR | Tasks | Stories | Why here |
|---|---|---|---|
| **A — The absence proof, first** 🔒 | T001–T025 | none (Setup + Foundational) — it **pre-pays US2** | Merges first, against a **stub** `DebugSeed/` whose only job is to be found. Reviewing the proof on its own is the only way to see the self-check fail honestly (break 5) |
| **B — The seeding path** 🎯 | T026–T048 | US1 (P1), US4 (P4) | The first PR where a test sees a transaction. The gate from A is already watching it — which is the intended feeling |
| **C — What the coverage was for** | T049–T079 | US5 (P5), US3 (P3), US2 (P2) + US1's audit completion | The defects only reproduce on a populated screen. **A5 and A7 watched failing against reinstated `018/02` and `018/03`** live here — the point of the slice |
| **D — Honesty and hand-back** | T080–T101 | US6 (P6) + Polish | The manual gate cannot be honestly shrunk until C has established which of G1–G14 a machine now covers |

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no shared state, no dependency on an incomplete task)
- **[Story]**: `[US1]`…`[US6]`. Setup, Foundational and Polish tasks carry **no** story label.
- Every task names an exact file path.

## Path Conventions

Two-layer repo — and this slice lands **entirely on the platform side** (`plan.md` § *Structure Decision*, research R2):

- **Engine**: `core/` — **UNTOUCHED**. Zero files, zero exports, zero migrations. Schema stays **v7**.
- **App**: `ios/Sources/DebugSeed/` (new, every file inside `#if DEBUG`), `ios/Sources/KanameApp.swift` (3 lines), `ios/Project.swift` (1 line)
- **Tests**: `ios/UITests/` (the seeded suites), `ios/Tests/` (one host-rendered empty state)
- **Gates**: repo-root `Makefile`, `scripts/import-path-audit.sh`, `scripts/release-absence-audit.sh` (new), `.github/workflows/ci.yml`
- `ios/Project.swift` uses `sources: ["Sources/**"]` / `["Tests/**"]` / `["UITests/**"]` globs, so **`ios/Sources/DebugSeed/` needs no project-file edit to be compiled into the app**. The *one* line this slice adds to `Project.swift` exists for a different reason: to compile `SeedScenarios.swift` into `KanameUITests` as well, so the app and the test share one literal (R11, FR-010).

## Non-negotiables encoded in this list

1. **⚠️ PR A merges first, against a stub.** The absence proof is built, wired into CI, and watched failing against all five deliberate breaks (T011–T015) **before** a line of real seeding code exists. Inverting this — building the capability and proving its absence afterwards — is how a DEBUG-only fabrication path ships.
2. **⚠️ `make core-xcframework` is NOT required and no Rust file is touched.** Research R2: `core/scripts/build-xcframework.sh` runs `cargo build --release` **once** and links that single artifact into both Xcode configurations, so no Rust construct can be present in DEBUG and absent from Release. **No task in this list edits `core/`, `ffi.rs`, or any `#[uniffi::export]`, and no task adds a migration.** `make ios-gen` is still required (it depends on `core-xcframework` in the `Makefile`, which is fine — that dependency rebuilds, it does not change the engine). If a task ever seems to need `ffi.rs`, stop: the answer is Swift, not a rebuild.
3. **⚠️ The v7 non-change is recorded deliberately**, per 017's precedent — T002 at the start and T093 at the end. A migration here would have been the tell that seeding had stopped going through the front door (`data-model.md` §1, research R18).
4. **⚠️ `ios/Sources/Import/ImportService.swift` is at 398 of 400 SwiftLint lines** and `make lint` is `--strict`. **No task in any PR touches it.** T094 re-checks `wc -l` at the end. If a task wants a line there, move code out instead.
5. **New code lives in `ios/Sources/DebugSeed/`, and the directory choice is a gate decision, not a tidiness one.** It sits inside the scan root that `import-path-audit.sh`'s networking **and** bank-literal scans already cover, so "zero network I/O on the seed path" (FR-033/SC-011) and "no scenario names a real issuer" (FR-011/SC-012) are enforced mechanically the moment the directory exists (research R7).
6. **⚠️ FR-043a's two CI gaps close in PR A, not later.** CI has **never** run `make import-audit` — nine scans, including the networking scan that is the platform half of Principle I, have only ever run on somebody's laptop (T017). And CI's `swift-format lint` covers `Sources Tests` while `make lint` covers `Sources Tests UITests`, which is where this slice's centre of gravity is (T019). Adding a tenth scan to a gate CI does not run would be an odd thing to have decided on purpose.
7. **⚠️ Never run the core and iOS gates concurrently.** `core/tests/history_perf.rs::s5` is a wall-clock bound and is flaky under CPU contention. This slice adds no core test but does add a 16-second Xcode build to the gate; a person who parallelises to win it back pays for it in a flaky `s5`. Every GATE task in this list states the sequence explicitly.
8. **Every PR ends on the Local Verification Gate**: `make core-lint && make core-test`, **wait**, then `make lint && make ios-test`, plus `make import-audit` and (from PR A) `make release-audit`.
9. **Money is a base-10 decimal string in the declaration and a `Decimal` everywhere after.** `Decimal(1234.56)` goes through a `Double`; `Decimal(string:)` is exact (`data-model.md` §3). Every declared amount stays **below ₹1,00,000** and every seeded launch pins `-AppleLocale en_IN`, because `.currency(code:)` groups by locale (R16).
10. **No assertion names an id** (`mint_id` is `lower(hex(randomblob(16)))`) and **no assertion computes a total** — a scenario declares two currencies on purpose, and a test that summed them would be the defect the aggregate scan exists to prevent, written where that scan does not reach (`data-model.md` §9, R6, R20).
11. **This slice builds no corpus and no generator.** `make perf-corpus`, its `10000-rows/`, `200-rows/` and `gate/` outputs, and the quickstart's three manual techniques are **unchanged** (FR-046). If a task appears to need a new PDF, scope has drifted.
12. **FR-008a is settled**: **deleted rows** and **transfer-flagged rows** are excluded from every scenario. `is_deleted` has no write path in `store.rs`'s API and `is_transfer` is written only by `detect_transfers`, which `import-path-audit.sh` bans the app from calling. No task acquires either power. Both exclusions are recorded (T090), not worked around.

---

# PR A — The absence proof, first 🔒

*The tenth scan; `scripts/release-absence-audit.sh` with its self-check; `make release-audit`; the CI wiring FR-043a demands; and the **five deliberate breaks watched red** — all against a stub `ios/Sources/DebugSeed/` file that does nothing. **No story label**: there is nothing to prove absent yet except the shape of the thing, which is exactly why this is the honest place to review the proof.*

## Phase 1: Setup

**Purpose**: A green baseline, the artifact facts measured on *this* machine rather than inherited from the research pass, and a stub for the gate to find.

- [x] T001 Establish the green pre-change baseline **sequentially**: `export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"`, then `make core-lint && make core-test`; **wait for it to finish** (`core/tests/history_perf.rs::s5` is wall-clock); then `make lint && make ios-test`; then `make import-audit`. Record the passing counts and the current **nine**-scan `import-audit` wall time in the PR description, so the tenth scan's cost (+0.005 s claimed) and any later regression are both attributable.
- [x] T002 [P] Record the **deliberate non-change** to the engine, per 017's precedent and `data-model.md` §1: confirm `git diff --stat main...HEAD -- core/` is empty, that `SCHEMA_VERSION` in `core/crates/kaname-core/src/store.rs` is still `7`, and that no `#[uniffi::export]` has been added or altered; write the finding and its reason (research R2 — a cargo feature or `#[cfg(debug_assertions)]` cannot express a DEBUG boundary, because one `cargo build --release` artifact is linked into both Xcode configurations) into the PR description. A schema or FFI change in this slice would be the tell that seeding had stopped going through the front door; recording its absence is what makes that check a habit rather than a hope.
- [x] T003 [P] ⚠️ **Measure the artifact facts before writing the script that depends on them.** Build a Release binary by hand — `xcodebuild -workspace ios/Kaname.xcworkspace -scheme Kaname -configuration Release -sdk iphonesimulator -derivedDataPath "$(mktemp -d)" CODE_SIGNING_ALLOWED=NO build` — and record: `nm -a` symbol count (research E4 measured **12,249**), whether `nm -a … | grep FilterChromeLayout` and `strings -a … | grep 'Show all accounts'` both hit (these are the self-check's two anchors — **if either does not hit on this machine, the anchors must change before T008 is written**), `xcodebuild -showBuildSettings`'s `DEPLOYMENT_POSTPROCESSING` (expected `NO`, which is why an unstripped `build` product still carries symbols), and the wall time (E1 measured **16.21 s** cold). An audit whose anchors were never checked is an audit that will fail as inconclusive on its first honest run.
- [x] T004 [P] Create the stub `ios/Sources/DebugSeed/DebugSeed.swift` — the whole file wrapped in `#if DEBUG` / `#endif`, containing an `enum DebugSeed` with a `static func applyIfRequested() {}` that does **nothing**, and a doc comment saying in as many words that this is a placeholder for PR B whose only job in PR A is to give the gate something to find. **Nothing calls it**: `ios/Sources/KanameApp.swift` is not touched in this PR. No `Project.swift` edit is needed — `sources: ["Sources/**"]` already covers the new directory.
- [x] T005 [P] **Prove the gap the tenth scan closes, before closing it.** With T004's stub present and its `#if DEBUG` **temporarily removed**, run `make import-audit` and confirm it still reports **OK** across all nine scans — i.e. today nothing in this repository notices a file under `ios/Sources/` that fabricates financial history outside a build guard. Record the passing output verbatim, then restore the guard. This is the RED that justifies the scan; a scan added without it is a scan nobody can show was ever needed.

**Checkpoint**: Baseline green and recorded; the Release binary's real symbol count, self-check anchors and build cost are measured on this machine; a stub exists; the gap is documented in the gate's own words.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Both absence proofs, their CI wiring, and the five observations that make them proofs rather than formalities. **No seeding code may be written until this phase is complete and green.**

### Phase 2A — Scan A: the tenth scan (source level, +0.005 s)

> It follows the shape of the existing nine exactly, because that shape is why they are readable: a rationale comment saying what the scan protects and why → the data → a `grep … || true` → a FAIL block naming the requirement → an `OK` line. ⚠️ **A bare `grep` must not end a pipeline and `grep -c` must not be used**: under `set -euo pipefail`, `grep` exits **1** when it finds nothing, which is the *passing* case, and kills the script. All nine existing scans end `|| true`; the tenth does too.

- [x] T006 GREEN: add the **tenth scan** to `scripts/import-path-audit.sh`, per `contracts/release-absence-audit.md` § *Scan A* — two directions in one block. **Forward**: every `*.swift` under `ios/Sources/DebugSeed/` must open with `#if DEBUG` within its first 20 lines, else FAIL naming FR-024. **Reverse**: `grep -rInE '\b(KANAME_SEED_SCENARIO|SeedScenario|DebugSeed)\b' "$SOURCES_DIR" --exclude-dir=DebugSeed | grep -v 'KanameApp.swift' || true` must be empty, else FAIL. The `KanameApp.swift` exclusion is narrow **on purpose** and must be commented as such — it is the one shipping file that legitimately names the surface, in three lines inside `#if DEBUG`; a second exclusion is a design smell and the answer is to move the code. Guard the whole block with `if [ -d "$SEED_DIR" ]` so the scan is a no-op on a checkout that predates the directory.
- [x] T007 **GATE** `make import-audit` — **ten** scans green with T004's guarded stub in place; the new `OK` line names `ios/Sources/DebugSeed`. Time the run and record the delta against T001's nine-scan baseline (the claim is +0.005 s; SC-014 depends on this gate staying a sub-second grep, which is why the 16-second half lives elsewhere).

### Phase 2B — Scan B: the artifact audit that builds its own artifact

> 🚨 **The trap this scan exists to avoid.** `-showBuildSettings` reports `STRIP_STYLE = all` and `STRIP_SWIFT_SYMBOLS = YES`, but `DEPLOYMENT_POSTPROCESSING = NO` — stripping runs on `install`/`archive`, not `build`. Measured (E4): **12,249 symbols before `strip -rSTx`, 157 after**, and a known shipping type vanishes from `strings` entirely. **A symbol scan over a stripped artifact is vacuously green.** It finds nothing because there is nothing to find, and reports success.

- [x] T008 Create `scripts/release-absence-audit.sh` per `contracts/release-absence-audit.md` § *Scan B*: `set -euo pipefail`; its own `mktemp -d` derived-data path with a `trap … EXIT`; **it builds its own artifact** with `xcodebuild -workspace ios/Kaname.xcworkspace -scheme Kaname -configuration Release -sdk iphonesimulator -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build`, never scanning an artifact somebody else produced; a **self-check** that finds T003's two anchors (`FilterChromeLayout` via `nm -a`, `Show all accounts` via `strings -a`) and **fails as `FAIL (inconclusive)`** if either is missing; then the absence itself over `DENYLIST=(DebugSeed SeedScenario SeedStatement SeedRow KANAME_SEED_SCENARIO applyIfRequested)` against **both** `nm` and `strings` (they fail differently — `strip` removed the symbol while the string literal survived), each `|| true`; FAIL blocks naming FR-025 and SC-004; and an OK line that **prints the symbol count it scanned**, because that is the number a reader checks when they suspect the gate has gone quiet. The header comment carries E4's two numbers so the next reader does not have to rediscover why the self-check is there.
- [x] T009 Add the `release-audit` target to the repo-root `Makefile` (`@bash scripts/release-absence-audit.sh`), with its `## Prove no seeding path is in the Release binary (~16s: it builds one)` help text, and add `release-audit` to the `.PHONY` line at `Makefile:1`. ⚠️ The script's `-workspace ios/Kaname.xcworkspace` assumes the workspace exists: make the script fail with a **named** message ("run `make ios-gen` first") rather than an `xcodebuild` stack trace, or give the target an `ios-gen` prerequisite — decide, and say which in the comment. It stays **out of** `make import-audit`: a 16-second build inside the cheap gate is the reason somebody stops running it (FR-028, SC-014).
- [x] T010 First honest run: `make release-audit` against T004's guarded stub. Record the build time, the scanned symbol count and the OK line verbatim in the PR description, and confirm the number matches T003's measurement — if the count has collapsed toward 157, the build action or the configuration is wrong and the next five tasks would all pass for the wrong reason.

### Phase 2C — ⚠️ The five deliberate breaks (FR-030, SC-005) — first-class tasks, each reverted in the same commit

> A gate that has only ever been green proves nothing about what it would catch. Each break below is **made, watched, recorded verbatim, and reverted**, and the audit is re-run green afterwards. Break 5 is the one that would be skipped and the one that matters most: it is the only test of whether the proof is a proof.

- [x] T011 **DELIBERATE BREAK 1 — the guard removed.** Delete the `#if DEBUG` / `#endif` from `ios/Sources/DebugSeed/DebugSeed.swift`. **Scan A must FAIL** naming the file and FR-024. Then run `make release-audit` and record what **Scan B** does. ⚠️ **Do not assume B goes red here**: the stub is `internal` and unreferenced, and a Release build with whole-module optimisation may emit no symbol and no literal for it at all. If B stays green, that is a **finding to record verbatim, not a denylist to weaken** — it means breaks 3 and 4 (a reference and a literal in a *shipping* file) are the two that actually reach the artifact, and PR C's T064 re-runs this break against the real, referenced path where the question is answered honestly. Revert in the same commit; re-run both gates green.
- [x] T012 **DELIBERATE BREAK 2 — the code moves house.** Copy the stub's `applyIfRequested` into a new unguarded file under `ios/Sources/Transactions/`. **Scan A must FAIL** on the reverse direction (a seeding symbol outside `DebugSeed/`, and `Transactions/` is not the excluded `KanameApp.swift`). Run `make release-audit` and record B's verdict. Revert in the same commit; re-run both gates green.
- [x] T013 **DELIBERATE BREAK 3 — a shipping file names the surface.** Add an unguarded reference to `SeedScenario` in `ios/Sources/RootView.swift`. **Scan A must FAIL**; **Scan B must FAIL too**, via a symbol or literal that a referenced-from-shipping-code path really does emit — record which of `nm`/`strings` caught it, because that is the evidence that the artifact half is not decorative. Revert in the same commit; re-run both gates green.
- [x] T014 **DELIBERATE BREAK 4 — the instruction as a plain literal.** Add the bare string `"KANAME_SEED_SCENARIO"` to a shipping file (`ios/Sources/Transactions/TransactionListStrings.swift` is the honest place to try it, since it is where literals live). **Scan A must FAIL**, and **Scan B must FAIL through `strings`** even if `nm` is silent — this is the break that proves why the script scans both. Revert in the same commit; re-run both gates green.
- [x] T015 🚨 **DELIBERATE BREAK 5 — the stripped copy. The break that makes "inconclusive" a distinguishable verdict.** Take the Release binary the audit builds, `cp` it and `strip -rSTx` the copy, point `scripts/release-absence-audit.sh` at that copy (a temporary `BIN=` override), and confirm the audit reports **`FAIL (inconclusive)`** and **not `OK`**. Record both symbol counts (`nm -a | wc -l`: expected ~12,249 before, **157** after) and the inconclusive message verbatim. If it reports `OK` here, the audit is decorative and every other task in this PR was theatre. Revert the override in the same commit; re-run green.
- [x] T016 Record all five observations — the break, the exact command, the verbatim failure message, and the revert — in `specs/019-debug-test-seeding/quickstart.md` § *How to watch the absence audit fail* and in the PR description. FR-030 requires the observation be **recorded**, not merely made; SC-005 asks for 100% of injected cases, so a break that behaved unexpectedly (see T011) is recorded as it happened rather than as it was predicted.

### Phase 2D — ⚠️ FR-043a: the CI gaps that predate this slice, closed here

> CI runs `core-privacy-audit` and has **never** run `make import-audit` — nine scans, including the networking scan that is the platform half of Principle I's guarantee, have only ever run on somebody's laptop (research R19). This slice is about to add a tenth scan whose entire value is that it fails a pull request. Both gaps close in this PR, for all ten scans, not just the new one.

- [x] T017 Add `make import-audit` to the `ios` job of `.github/workflows/ci.yml`. ⚠️ **The job sets `defaults.run.working-directory: ios`**, so a bare `- run: make import-audit` runs where there is no `Makefile`. Follow the pattern the `core-privacy-audit` and `core-xcframework` steps already use: `working-directory: ${{ github.workspace }}`. (The YAML sketch in `contracts/release-absence-audit.md` § *Wiring* omits this — the contract's intent is right and its snippet is short.) Place it after `Generate Xcode project` so the tree is in its normal state.
- [x] T018 Add `make release-audit` to the same job in `.github/workflows/ci.yml`, with the same `working-directory: ${{ github.workspace }}`, placed **after** the `tuist generate` step (the script needs `ios/Kaname.xcworkspace` to exist — see T009) and before or after `Build & test` as suits the log, and note its ~16 s cost in a comment so the next person to look at CI's runtime knows what it bought.
- [x] T019 Widen CI's lint step in `.github/workflows/ci.yml` from `swift-format lint --recursive --strict Sources Tests` to `… Sources Tests UITests`, matching `make lint` (`Makefile:150`). Every line in `ios/UITests/` is format-linted locally and not in CI today; this slice writes most of its code there.
- [x] T020 **Watch CI actually run them.** Push the branch, read the run, and confirm the `import-audit` step reports **ten** OK lines and the `release-audit` step reports its symbol count. Then push one throwaway commit carrying **break 4** (T014) and confirm **CI goes red on `make import-audit`** — a pull request, not a laptop, is where FR-029 says the regression must be caught. Record the run URLs; revert the throwaway commit.
- [x] T021 **Watch the widened lint catch something CI could not see yesterday.** Push a throwaway commit with a `swift-format`-violating line in `ios/UITests/ImportFrontDoorUITests.swift` (a trailing inline comment is the reliable one — `[Spacing]` rejects them) and confirm **CI's lint step fails**. Before T019 this file was linted only on a laptop. Record the run URL; revert.

### Phase 2E — PR A verification gate

- [x] T022 **GATE** `make core-lint && make core-test` — unchanged by this PR and required to stay so. ⚠️ **Wait for it to finish before starting T023**; `history_perf.rs::s5` is wall-clock and flaky under CPU contention.
- [x] T023 **GATE** `make lint && make ios-test` — `swiftlint --strict` and `swift-format lint --strict` now also see `ios/Sources/DebugSeed/DebugSeed.swift`; every shipped suite stays green, including `ios/UITests/ImportFrontDoorUITests.swift`'s `testAFreshInstallOffersNoRouteToAnEmptyTransactionList`, which is untouched and must remain so (FR-032, L1).
- [x] T024 **GATE** `make import-audit && make release-audit` — ten scans, then the artifact audit, both green against the guarded stub.
- [x] T025 Confirm what this PR did **not** touch, and record it: `git diff --stat main...HEAD -- core/` is empty (T002); `wc -l ios/Sources/Import/ImportService.swift` is unchanged at **398**; `ios/Project.swift` is unchanged (the `Sources/**` glob already covers the new directory — the one-line edit belongs to PR B and to a different requirement); `ios/Sources/KanameApp.swift` is unchanged (still 13 lines).

**Checkpoint**: 🔒 The price is paid. Two gates exist, one of them refuses to conclude anything unless it can first find something it knows is there; both have been watched failing against five injected cases; CI runs all ten scans for the first time in this repository's life and lints `UITests` for the first time too. **Nothing that fabricates financial data has been written yet.** If the slice stopped here, the repository would be strictly better off.

---

# PR B — The seeding path 🎯

*`DebugSeed/` for real, the three-line `#if DEBUG` block in `KanameApp.swift`, the one line in `Project.swift`, both named scenarios, `SeedContractUITests` (L1–L6) and the first seeded audit (S1–S3, A1). **US1, US4.***

## Phase 3: User Story 1 — An automated run opens a screen with a person's transactions on it (Priority: P1) 🎯 MVP

**Goal**: A launch that asks for a named, pre-declared synthetic history comes up with that history already in its own encrypted store, walks the route a person walks, lands on a populated transaction list, and lets the system auditor loose on it — no file, no picker, nobody in the room.

**Independent Test**: Run the UI suite with no human present and no file on the device; confirm it reaches a transaction list showing exactly the rows the named fixture declares — same count, same dates, same descriptions, same exact amounts, same accounts — and that `performAccessibilityAudit` runs against that rendered, populated screen.

### Tests for User Story 1 (RED first) ⚠️

- [x] T026 [P] [US1] RED: create `ios/UITests/SeedContractUITests.swift` with **L1–L6** (`contracts/seeded-launch.md` §4) — L1 a launch with **no** `KANAME_SEED_SCENARIO` still reaches the front door's empty state and offers no route to the list; L2 `KANAME_SEED_SCENARIO=small` reaches the foreground and the front door shows the seeded account; L3 no document picker is ever presented on a seeded launch; L4 `KANAME_SEED_SCENARIO=does-not-exist` **does not** reach the foreground; L5 a seeded launch reaches the populated list within **5 s**, measured from `app.launch()` to the first row element existing; L6 a non-seeded launch immediately after a seeded one performs **no** deletion. ⚠️ Set the **bare** key on `app.launchEnvironment` — the `TEST_RUNNER_` prefix rule applies to *unit* tests hosted in the app (`make reference-check`, `make perf-corpus`) and a prefixed variable here is never delivered, leaving the suite silently unseeded. **Observe RED**: against the stub, L2/L5 fail because nothing is seeded and L4 fails because nothing crashes.
- [x] T027 [P] [US1] RED: create `ios/UITests/SeededTransactionListUITests.swift` with **S1–S3 and A1** — S1 the list is reached from the front door's own toolbar control (`app.buttons["All transactions"]`, the same control a person taps; ⚠️ *not* `app.buttons["Transactions"]`, which the quickstart's smoke snippet names — `Transactions` is the navigation-bar title, per the shipped `testAFreshInstallOffersNoRouteToAnEmptyTransactionList`); S2 the number of row elements equals `scenario.expectedLiveRowCount` **and** equals the sum of `AccountSummary.liveTransactionCount`; S3 every declared live row is present, matched on its **full accessibility label** — the whole row is one element (`.accessibilityElement(children: .combine)`), and the label carries date with year, description, amount with currency, direction in words, account identity and category (R20); A1 `performAccessibilityAudit` over the populated list at default size in Light. **Observe RED.**

### Implementation for User Story 1

- [x] T028 [US1] Create `ios/Sources/DebugSeed/SeedScenarios.swift` — entirely inside `#if DEBUG` — with `SeedScenario`, `SeedStatement` and `SeedRow` exactly as `data-model.md` §2 declares them, plus the **`small`** scenario: 6 live rows, one account (`SYNTHETIC BANK ONE`, `···· 0006`), one currency, six consecutive days in a **prior calendar year** so a group heading must carry its year (gate G4, A8). Amounts are base-10 **strings** parsed with `Decimal(string:)` — never a `Decimal` literal, which goes through a `Double` — and every one stays **below ₹1,00,000** (R16). Account names, bank codes and descriptions follow the synthetic convention (`SYNTHETIC BANK ONE` / `SYNTH_BANK` / `SYNTHETIC MERCHANT NN`); the bank-literal scan already covers this directory and will fail the build if a registry literal appears (research R7).
- [x] T029 [US1] Add the **`deep`** scenario to `ios/Sources/DebugSeed/SeedScenarios.swift`: 4 statements (one a re-import), 3 accounts — a bank ledger, a credit card, and one whose statement declares **zero** rows — **160** live rows across the two populated accounts (`pageSize` is 50, so four pages with the last partial), **two** currencies (`INR`, `USD`) on rows of the *same* account, ≥ 1 date carrying rows in **two** accounts, ≥ 2 superseded rows (one by re-import, one cross-source), and both categorized and uncategorized rows. ⚠️ **The cross-source pair must be one bank ledger and one card**: after 018's source-kind guard (`store.rs:1448`) two cards never de-duplicate, **silently**. ⚠️ **The corpus must not eat itself** (018 R20): exactly the rows the scenario *intends* to collide may collide — every other row differs by description **and** amount, or by date. **No deleted rows and no transfer-flagged rows** — FR-008a, settled.
- [x] T030 [US1] Create `ios/Sources/DebugSeed/SeedScenarioBuilder.swift` (inside `#if DEBUG`): `SeedScenario → [ImportRequest]` built from `NewImportTransaction` with `Decimal(string:)` amounts, an explicit `direction`, the row's **own** currency, and `ImportRequest.now` taken from the scenario's declared instant — never a clock (FR-023). It also owns the expected-row maths the tests assert against: `expectedLiveRowCount` (declared rows minus declared supersessions), the expected accessibility label for each row derived from the **same** declaration by the app's own formatting where possible, and the expected order computed **once** by the engine's total order (`date DESC`, account position, insertion order). ⚠️ No id anywhere, and **no function that sums two amounts** — the aggregate ban's whole point, written where the shell scan does not reach (`data-model.md` §9).
- [x] T031 [US1] Replace the T004 stub with the real `ios/Sources/DebugSeed/DebugSeed.swift`, still entirely inside `#if DEBUG`, implementing `applyIfRequested()` exactly as `data-model.md` §8's lifecycle states: read `ProcessInfo.processInfo.environment["KANAME_SEED_SCENARIO"]` and **return immediately if absent** (nothing read, deleted, opened or written — FR-005, FR-022); resolve the name against the declared set and `fatalError("KANAME_SEED_SCENARIO=\(name): no such scenario. Declared: small, deep")` if unknown; delete `kaname.db` and its `-journal` / `-wal` / `-shm` sidecars from `StoreLocator.databaseURL`'s directory, leaving **the Keychain key untouched** so the store is re-minted under the app's own key (FR-017, SC-013, R12); then `StoreProvider.shared()` and one `store.importStatement(request)` per declared statement, **in declaration order** (order is the only ordering input and it is written down); `fatalError` on any throw. Nothing is caught, nothing degrades to an empty app.
- [x] T032 [US1] Add the three-line `#if DEBUG` block to `ios/Sources/KanameApp.swift`'s `init()` (the file has no `init()` today and is 13 lines, so this adds an `init()` plus the guarded call). This is the **only** edit to a shipping source in this slice, and it is the reason `KanameApp.swift` is the tenth scan's single narrow exclusion. `App.init()` is the entry point because FR-002 requires the history to be complete before any `View` body is evaluated and `StoreProvider.shared()` memoises the `Store` on first use.
- [x] T033 [US1] Add **one line** to `ios/Project.swift`: `Sources/DebugSeed/SeedScenarios.swift` joins the `KanameUITests` target's `sources` alongside `UITests/**`, so the bundle that asserts links the **same literal** the app writes (R11, FR-010 — drift has nowhere to happen). Then `make ios-gen` — **never a bare `tuist generate`**, which resolves the xcframework path at generation time.
- [x] T034 [US1] Add the shared seeded-launch helper to `ios/UITests/SeededTransactionListUITests.swift` (and use it from `SeedContractUITests.swift`): sets `launchEnvironment["KANAME_SEED_SCENARIO"]`, pins `-AppleLocale en_IN` and `-AppleLanguages (en)` on `launchArguments` (R16 — `.currency(code:)` takes its grouping from the locale, so an unpinned assertion is an assertion about the simulator's region), and asserts `app.wait(for: .runningForeground, timeout: 10)` — which is simultaneously the launch assertion and, per `contracts/seeded-launch.md` §3, the **failure detector** for a seed that could not be applied. A test that sets its own text size must put it back (`make ios-test` pins `content_size large` for a recorded false-failure reason).
- [x] T035 [US1] GREEN: L1–L6 in `ios/UITests/SeedContractUITests.swift` and S1–S3, A1 in `ios/UITests/SeededTransactionListUITests.swift` all pass. **Record the measured launch-to-first-row time** for SC-009 in the PR description — research R15 has *no* measured number for seeding 160 rows in `App.init()` and says so; this task is where the number comes from. If `deep` is slow enough to be felt, the remedy named in advance is to **shrink `deep`**, not to move the seed off the launch path (an asynchronous seed is a race with the first screenshot).
- [x] T036 [US1] ⚠️ Prove `deep` does not de-duplicate **itself** before anything measures against it — the 018 R20 lesson, restated. In `ios/UITests/SeededTransactionListUITests.swift`, against `ios/Sources/DebugSeed/SeedScenarios.swift`'s declaration: assert that the on-screen row count, `scenario.expectedLiveRowCount` and the sum of `AccountSummary.liveTransactionCount` are all the **same** number, and that the count of superseded rows equals exactly the number the scenario deliberately supersedes. A fixture that quietly collapses is a suite asserting against a fraction of what it claims.
- [x] T037 [US1] **DELIBERATE BREAK — the silent fallback.** Replace the unknown-name `fatalError` in `ios/Sources/DebugSeed/DebugSeed.swift` with a `return`, so an unrecognised scenario carries on into an empty app. **L4 must go red.** This is the single worst failure mode this slice can have — an accessibility audit reporting success against a blank screen — and FR-006/SC-016 exist to forbid it. Record the failure message verbatim; revert in the same commit; re-run green.
- [x] T038 [US1] **DELIBERATE BREAK — the fixture drifts.** Change one declared amount and one declared description in `ios/Sources/DebugSeed/SeedScenarios.swift`. **S3 must go red loudly** (and, once T042 lands, D4 with it). This is FR-010's whole claim — one declaration, assertions derived from it — proved rather than asserted. Record verbatim; revert in the same commit; re-run green.
- [x] T039 [US1] **GATE** `make lint` — `swiftlint --strict` (400-line files, 120 columns) and `swift-format lint --strict` over `Sources Tests UITests`. Confirm `wc -l ios/Sources/Import/ImportService.swift` is still **398**.
- [x] T040 [US1] **GATE** `make ios-gen && make ios-test` — T026 and T027 green; the shipped `ImportFrontDoorUITests` suite unchanged and still green, `testAFreshInstallOffersNoRouteToAnEmptyTransactionList` included (L1, FR-032).
- [x] T041 [US1] **GATE** `make import-audit && make release-audit` — the first run of both against the **real** seeding path rather than a stub. This is the moment PR A earns its keep: ten scans green, and the artifact audit reporting its symbol count with none of the six denylisted terms found.

**Checkpoint**: 🎯 **MVP.** An automated run reaches a populated transaction list with no file, no picker and nobody present, and the system auditor runs against it. The screen that took three slices to build is covered for the first time.

## Phase 4: User Story 4 — The same run, twice, is the same run (Priority: P4)

**Goal**: Ten runs on a container nobody cleans produce one screen. A seeded run inherits nothing and leaves nothing behind for a non-seeded one.

**Independent Test**: Run the same seeded scenario ten times consecutively without cleaning between runs and confirm count, contents and order are identical each time; run a non-seeded launch immediately after a seeded one and confirm it is a clean first-run app that deleted nothing.

- [x] T042 [P] [US4] RED: add **D1** and **D4** to `ios/UITests/SeededTransactionListUITests.swift` — D1 seeds `small` **10** consecutive times without cleaning the container and asserts an identical count, contents and order every time (SC-010); D4 is the drift assertion T038 breaks against, stated as its own test so a changed declaration fails loudly rather than passing against stale expectations. **Observe RED** by first pointing D1 at a build whose reset is disabled (see T045), so the assertion is known to be capable of failing.
- [x] T043 [P] [US4] RED: add **D2** and **D3** to `ios/UITests/SeededTransactionListUITests.swift` — D2 a seeded launch after a *different* seeded launch shows only the second scenario's rows (`small` then `deep`, then `deep` then `small`); D3 every declared date renders as declared under the pinned locale, on any machine and at any time of day (FR-023). **Observe RED.**
- [x] T044 [US4] GREEN: D1–D4 pass with the reset as T031 built it — unconditional *within* a seeded launch, and absent entirely from a non-seeded one. Record that `make ios-test`'s existing uninstall handles the container **between suites** while T031's in-app reset handles it **between tests in one suite**; the two are complementary, not redundant (R12).
- [x] T045 [US4] **DELIBERATE BREAK — the reset made conditional.** Change `ios/Sources/DebugSeed/DebugSeed.swift` to skip the deletion when `kaname.db` already exists. **D1 and D2 must go red** — the second seed accumulates on the first, which is exactly the "failures nobody can reproduce" US4 exists to prevent. Record verbatim; revert in the same commit; re-run green.
- [x] T046 [US4] **DELIBERATE BREAK — the reset made unconditional.** Move the deletion *outside* the `guard let scenario` in `ios/Sources/DebugSeed/DebugSeed.swift`, so every launch wipes. **L1 and L6 must go red** — a developer's own DEBUG build with their own imported data would be destroyed by opening the app, and FR-022 forbids anything being wiped except on an explicit seeded launch. Record verbatim; revert in the same commit; re-run green.
- [x] T047 [US4] **GATE** `make lint && make ios-test` — T042 and T043 green alongside T026/T027.
- [x] T048 [US4] **GATE** the full PR B verification gate before the PR opens: `make core-lint && make core-test` (**wait**), then `make lint && make ios-test`, then `make import-audit && make release-audit`. Record the counts.

**Checkpoint**: US1 and US4 are independently functional. A named history goes in, the same screen comes out every time, an unrecognised name fails the launch rather than a screenshot, and the absence proof has now watched real seeding code rather than a placeholder.

## PR B — RECORDED

**Gate, run sequentially (2026-08-17):** core lint + 16 suites green and `core/` untouched
(`git diff --stat -- core/` empty, `SCHEMA_VERSION` still 7, no `#[uniffi::export]` added);
`make lint` **0 violations** in 95 files and `ImportService.swift` still **398**; `make ios-test`
**275 unit tests in 53 suites** and **21 UI tests** green (6 front door, 6 `SeedContract`, 5
`SeededDeterminism`, 4 `SeededTransactionList`); `make import-audit` **ten scans, 0.296 s** —
the tenth now reports *"4 seeding file(s) under ios/Sources/DebugSeed, all #if DEBUG"*; `make
release-audit` **OK, 4,534 symbols scanned, 6 terms, 14.68 s** against the **real** path.

**SC-009 measured: 4.63 s** from `app.launch()` to the first row (`small`, printed by the test as
`seed-timing:`). Inside the 5 s bound but not comfortably — most of it is launch and navigation,
not the seed. ⚠️ A later scenario that grows `small`, or a slower machine, will fail this; the
remedy named in advance is to shrink the scenario, never to move the seed off the launch path.
**The `deep` walk costs 113 s on its own** and is why the UI suite is now 423 s.

**Six breaks watched red, each reverted in the same commit:**

| Break | Went red |
|---|---|
| T037 unknown-name `fatalError` → `return` | L4: `XCTAssertNotEqual failed: XCUIApplicationState(rawValue: 4)` — the app reached the foreground with an empty screen, the worst failure this slice can have |
| T038a a declared **amount and description** changed | ⚠️ **Nothing went red, and that is the correct answer** — see below |
| T038b a declared `expectedCategory` the engine will not assign | S3: `missing row: 15 February 2025, … , Groceries` |
| T045 reset made conditional on the file existing | D1 **and** D2 red — the second seed accumulated on the first |
| T046 reset moved outside the request | L6 red: *"the store the previous launch wrote is gone"*. ⚠️ L1 stayed **green**, honestly: an unconditional wipe still leaves a fresh-install screen, which is what L1 asserts. L6 is the assertion that has teeth here |
| (PR A's five, re-run in T041) | both audits green against the real path |

⚠️ **T038 as written cannot go red, and the reason is the requirement it was testing.** The app
and the suite compile the *same* declaration, so a coherent edit to an amount changes both sides
at once. That is FR-010 — "declared in one place, and what the tests expect derived from that same
declaration" — working exactly as specified, and the break proves it by failing to break anything.
What *can* drift is the half of the declaration that is a **claim about the engine** rather than
an input to it (`expectedCategory`), and that is what T038b breaks instead. Recorded rather than
smoothed over: a break that cannot go red is either a bad break or a bad requirement, and here it
is neither — it is a break aimed at a seam the design removed.

### 🚨 What the first audit of a populated list found — `.scratch/019-debug-test-seeding/issues/01`

The whole slice exists so A1 could run. It ran, and found three things on its first execution:

1. **The date heading rendered grey.** 018's T116 set `.foregroundStyle(.primary)` — and it was a
   **no-op**, because the bare `.primary` is the *hierarchical* style, "the most prominent level
   of whatever style is already in force", and what was in force on a plain-list header was the
   grey the header wanted. **Fixed** with `Color.primary`, the absolute label colour.
2. **The pinned heading had nothing behind it** — `.scratch/018-transaction-list/issues/07`,
   parked since 2026-08-16 as `needs-triage`, reproduced at the **default** text size by a machine
   in twelve seconds. **Fixed** with an opaque background, which is what that ticket's own
   resolution names; FR-068 bans *material* here and prescribes opacity. Audit issues 5 → 3.
3. **Three `Contrast failed` verdicts naming no element.** Open. Nine probes narrow them to the
   bottom filter bar (removing it: 4 → 0; the front door's accounts list: 0), the chip's own text
   measures **9.48:1** on the audit's own screenshot, and the chip's colour is not what they are
   about. A1 therefore audits every type **except** `.contrast` and says so at the assertion site.
   ⚠️ **A suppression was rejected**: every contrast issue here arrives with `element == nil`,
   **including the real defect in §1**, so "ignore the ones it cannot name" would have hidden the
   finding that proved the audit was worth running. The question goes to **T074**, which is already
   the task for deciding what this instrument can see, with T075's sharper instrument as the remedy.

### Deviations from the task text, each forced and each recorded

- **T030's expected-row maths lives in `SeedScenarios.swift` / `SeedExpectations.swift`, not in
  `SeedScenarioBuilder.swift`.** A UI-test bundle links neither the app nor `KanameCore`, so a file
  that imports the engine cannot be compiled into the bundle that asserts. The builder keeps its
  one job — `SeedStatement → ImportRequest` — and everything a test derives lives in the shared,
  Foundation-only files. For the same reason `SeedRow.direction` is a local `SeedDirection`.
- **T033's "one line" in `Project.swift` is two files, not one.** `SeedScenarios.swift` reached
  **414** lines, over SwiftLint's 400 limit under `--strict`, so the derivations moved to
  `SeedExpectations.swift` and both are listed in `KanameUITests`' sources. Split by role, not size.
- **T034's helper is `ios/UITests/SeededLaunch.swift`**, its own file, and D1–D4 + T036 are in
  `ios/UITests/SeededDeterminismUITests.swift` rather than inside the list suite — same reason.
- **A third scenario, `empty`, was declared** (zero statements: the reset without the seed). It is
  not scope drift, it is a hazard the suite creates: a seeded store **outlives the suite that wrote
  it**, and the shipped front-door audits assert a fresh install, so without a teardown reset a
  seeded suite makes `ImportFrontDoorUITests` audit an accounts list. It is the same trap
  `make ios-test`'s uninstall exists for, one layer down and expressible from inside a test.
- **The appearance is pinned per test** (`SeededLaunch.pin(.light, in:)`). `XCUIDevice.shared
  .appearance` is simulator-wide and outlives the run that set it — this suite was written against
  a screen that was Dark for exactly that reason. Same trap as `content_size`, one axis over.

### Two facts about the element tree, learned the hard way

- **A row's label is not on its cell.** Both a row and a date heading are `Cell`s with an empty
  label; the sentence hangs on a `StaticText` inside. They are told apart **structurally** — a
  row's combined element still has its parts under it, a heading is one line — never by wording,
  which would have started counting a row the day a description ended in "transactions".
- **A `List` renders a screenful, not a list.** Even `small`'s six rows do not all fit above the
  filter bar, so every count and every ordering assertion walks the list with `SeededLaunch.walk`,
  which collects rows and headings in **one** pass. Two passes was the first version, and it looked
  for a heading that had scrolled off half a minute earlier.

---

# PR C — What the coverage was for

*The remaining audits (A2–A6, A8), the filter's four states, paging over 160 rows, the currency and ordering assertions, the empty states — and the point of the whole slice: **A5 and A7 watched failing against reinstated `018/02` and `018/03`**, then reverted. **US5, US3, US2**, plus the completion of US1's audit coverage (the audits belong to US1's story but cannot be written until `deep` and the filter are exercised, which is why they land here).*

## Phase 5: User Story 5 — A run asks for the shape of history it needs (Priority: P5)

**Goal**: A run names the scenario that fits the question it is asking, instead of every run paying for the largest one. Six rows when the question is about the *end* of a list; 160 when it is about paging.

**Independent Test**: Confirm the small scenario's last row is reachable in a handful of swipes at the largest accessibility text size, and that the deep scenario's list pages more than once with no row duplicated, skipped or reordered across a boundary.

- [x] T049 [P] [US5] RED: add the paging assertions to `ios/UITests/SeededTransactionListUITests.swift` over `deep` — the list pages **more than once** (160 rows against a `pageSize` of 50 is four pages, the last partial, which also exercises the exhausted cursor), and across every page boundary **no row is duplicated, skipped or reordered** (SC-017, US5 AS-2). Match on accessibility labels, never on ids. **Observe RED.**
- [x] T050 [P] [US5] RED: add the small-scenario end-of-list assertion to `ios/UITests/SeededTransactionListUITests.swift` — at `AccessibilityXXXL`, scrolling reaches the **last** row within a handful of swipes and the run can assert about it (US5 AS-1). This is `018/03`'s lesson written into the capability: at XXXL the end of a ten-thousand-row list is hundreds of flicks away, and the gate was unrunnable until a six-row corpus existed. **Observe RED.**
- [x] T051 [P] [US5] RED: add the shape assertions over `deep` to `ios/UITests/SeededTransactionListUITests.swift` — **S5** the rendered order equals the declaration sorted by the engine's total order; two currencies appear on rows of the same account, each formatted with its **own** currency and **no figure anywhere combining them**; the same-date cross-account collision renders in `listAccounts()` order (the account tie-break). **Observe RED.**
- [x] T052 [US5] GREEN: T049–T051 in `ios/UITests/SeededTransactionListUITests.swift` pass. Record the measured page count and the actual swipe count for `small` at XXXL in the PR description — SC-017 asks for "a handful", and a number in the record is what lets a later scenario author see it grow.
- [x] T053 [US5] **DELIBERATE BREAK — a scenario that does not page.** Temporarily shrink `deep` in `ios/Sources/DebugSeed/SeedScenarios.swift` below the 50-row page size. **T049's "pages more than once" assertion must go red.** Without this, an assertion that merely walks a list would pass against a scenario that never paged at all, and FR-009's second half would be unproven. Record verbatim; revert in the same commit; re-run green.
- [x] T054 [US5] **GATE** `make lint && make ios-test`.

## Phase 6: User Story 3 — What the auditor sees is the shipping screen (Priority: P3)

**Goal**: The real encrypted store, the real engine reads, the real ordering, the real live-row rule, the real view. The only thing that differs from a person's install is how the rows got in.

**Independent Test**: Seed superseded rows and observe they never appear; confirm the front-door count equals the filtered row count; confirm no stub, double or in-memory substitute stands between the screen and the store on a seeded run.

- [x] T055 [P] [US3] RED: add **S4** and **S6** to `ios/UITests/SeededTransactionListUITests.swift` — S4 every declared **superseded** row is absent (both routes: the re-import and the cross-source bank↔card pair), and nothing undeclared is present; S6 the front-door count for an account equals the row count when the list is filtered to that account (US3 AS-2 — the property 018 built `account_summaries()` to make true). **Observe RED.**
- [x] T056 [P] [US3] RED: add **E1–E3** to `ios/UITests/SeededTransactionListUITests.swift` — E1 filtering to `deep`'s zero-transaction account while others have rows renders `accountEmptyOthersHaveRows(statementWasEmpty: true)`; E2 an account whose every row is superseded renders `accountNothingToShow`; E3 the filter's **four** states — unfiltered, filtered, filtered-to-an-account-with-nothing-live, and cleared — are each reached and asserted (FR-040, US5 AS-3). **Observe RED.**
- [x] T057 [US3] ⚠️ Add a third scenario, **`barren`**, to `ios/Sources/DebugSeed/SeedScenarios.swift` — two or more accounts whose statements each declare **zero** rows — and assert **E5**: the unfiltered list renders `EmptyKind.noTransactionsAnywhere`. **This is a finding, not a scope drift**: `EmptyKind.decide`'s unfiltered branch is only consulted when the store holds **no live rows at all**, which neither `small` nor `deep` can produce, so FR-039's "every person-reachable empty state" needs a scenario neither of R14's two can express. FR-013/SC-015 make this free — a scenario changes nothing compiled into a Release build — and `data-model.md` §6 anticipates it in as many words ("declared as a third scenario only if a task needs it"). Record the addition and its reason.
- [x] T058 [US3] 🚨 **DETERMINE: is `EmptyKind.nothingToShowAnywhere` reachable by a seed at all?** Reading `EmptyKind.decide` (`ios/Sources/Transactions/TransactionListModels.swift:178–204`) with FR-008a: that case requires **zero live rows store-wide** *and* at least one account with `hasOnlyExcludedRows`. Every supersession the import path can produce leaves a **live winner** somewhere, and `is_deleted` has **no write path** — so a store with excluded rows and no live rows may be unreachable through the front door, exactly as `nothingImported` is. Attempt it with a scenario; if it cannot be produced, **record it as a second FR-039a-shaped exception** — real coverage, lesser coverage, named as such — and cover it by host-rendering in PR D (T080). Do **not** acquire a write path to make it reachable: that would be seeding holding a power the import pipeline lacks, which is precisely what FR-008a forbids.
- [x] T059 [US3] GREEN: T055, T056 and T057 in `ios/UITests/SeededTransactionListUITests.swift` (against `ios/Sources/DebugSeed/SeedScenarios.swift`'s declarations) pass, and T058's verdict is recorded either way. State plainly in the PR description how many of the six `EmptyKind` cases are audited against a rendered screen, how many are executed-but-not-audited, and how many (if any) are unreachable — SC-007 is met **unevenly** by design, and the record says so rather than implying parity.
- [x] T060 [US3] Prove **FR-015 structurally**: no stub store, fake view model, test double or injected row list stands between the store and the screen on a seeded run. Grep `ios/Sources/DebugSeed/` for any type conforming to `TransactionHistoryReading` and for any construction of `TransactionListViewModel`; confirm the seeded path's only outputs are `Store.importStatement` calls, and that `ios/UITests/SeededTransactionListUITests.swift` observes the app **through XCUITest only** — it constructs no model and injects no rows. Record the check; if it is worth pinning mechanically, extend the tenth scan rather than writing a convention.
- [x] T061 [US3] Prove **FR-017 / SC-013** against the real container: after a seeded run, `xcrun simctl get_app_container booted in.beaconbrain.kaname data`, locate `Application Support/Kaname/kaname.db`, and confirm its first bytes are **not** the plaintext `SQLite format 3\0` header — the seeded store is SQLCipher-encrypted under the app's own Keychain key, because the seed deleted the file and never touched the key. Then grep every target (`ios/Sources`, `ios/Tests`, `ios/UITests`) for a hard-coded, bundled or exported key. Record both results.
- [x] T062 [US3] **DELIBERATE BREAK — the supersession that silently does not happen.** Temporarily declare `deep`'s cross-source pair as **two credit cards** (`isCreditCard: true` on both) in `ios/Sources/DebugSeed/SeedScenarios.swift`. After 018's source-kind guard (`store.rs:1448`), two cards never de-duplicate — so the supersession vanishes **with no error anywhere**, and **T036's `expectedLiveRowCount` assertion and E2 must go red**. This is the quickstart's named silent trap, watched rather than warned about: the fixture's own count is the only thing standing between a scenario author and a corpus that quietly stopped testing what it said. Record verbatim; revert in the same commit; re-run green.
- [x] T063 [US3] **GATE** `make lint && make ios-test`.

## Phase 7: User Story 2 — The path that makes this possible cannot ship (Priority: P2)

**Goal**: PR A's proof, re-run against a real seeding path rather than a stub — plus the one assertion that could not be made until the path existed: a Release build handed the instruction does exactly what it does without it.

**Independent Test**: Build for Release; run the absence check over both the sources and the built artifact and confirm it passes; launch that Release build with the seeding instruction and confirm nothing whatsoever is different; then deliberately re-enable the path, rebuild, and confirm the check fails.

- [x] T064 [US2] **Re-run deliberate breaks 1–4 against the real path** (T011–T014, now against `ios/Sources/DebugSeed/DebugSeed.swift`, `SeedScenarios.swift` and `SeedScenarioBuilder.swift` rather than a stub), one at a time, each reverted in the same commit. Record for **each** break which scan caught it and the verbatim message. ⚠️ This is where T011's open question is answered honestly: an unreferenced stub may be optimised away in Release, but the real path is reachable from `KanameApp.init()`, so break 1 should now reach the artifact. If it still does not, that is the finding — record it, keep the denylist, and say plainly that Scan A is the load-bearing half for that case.
- [x] T065 [US2] **Re-run deliberate break 5** (T015) against the real binary, using `scripts/release-absence-audit.sh`: `strip -rSTx` a copy, point the audit at it, confirm **`FAIL (inconclusive)`**, record both symbol counts. The self-check is the difference between a proof and a formality and it is re-proved once the thing it is proving absent actually exists.
- [x] T066 [US2] **FR-028 / SC-004 — the Release build handed the instruction.** Build Release for the simulator (the same configuration `scripts/release-absence-audit.sh` builds, exercising `ios/Sources/KanameApp.swift`'s guarded `init()`), install it, and launch it **twice**: once with `KANAME_SEED_SCENARIO=small` in its environment and once without. Confirm they are indistinguishable in 100% of tested states — **zero** seeded rows, **zero** crashes, **zero** diagnostics, and **zero** log lines mentioning the instruction (check with `xcrun simctl spawn booted log stream --predicate 'process == "Kaname"'` across both launches). Record the method and the result: this assertion is *about* the absence of a difference, so how it was looked for matters as much as what was found.
- [x] T067 [US2] **FR-031 / L7 — no user-reachable surface, in any build.** Confirm this slice added no menu item, gesture, settings toggle, URL scheme, shared-file or pasteboard trigger and no debug screen: grep `ios/Sources/` for `CFBundleURLTypes`, `onOpenURL`, `UIPasteboard` and any new user-visible string; confirm `ios/Sources/Transactions/TransactionListStrings.swift` is unchanged; and confirm the shipped `testAFreshInstallOffersNoRouteToAnEmptyTransactionList` still passes **unedited** (FR-032 — 018's FR-077 is satisfied by absence from the build, not by concealment; SC-014 — zero user-visible strings added or altered, zero expectation edits).
- [x] T068 [US2] **GATE** `make import-audit && make release-audit` — ten scans and the artifact audit, green against the complete seeding path.

## Phase 8: ⚠️ FR-038 / SC-006 — the new coverage watched failing (completes US1's audit)

> **The point of the slice.** 018's two parked defects are reinstated on purpose and the new coverage is watched going red against them. They need **different instruments**, because the iOS auditor's seven types — Contrast, ElementDetection, HitRegion, SufficientElementDescription, DynamicType, TextClipped, Trait — contain **no occlusion check** (research R10). ⚠️ **R10's claim that `performAccessibilityAudit` fires `.textClipped` for `018/02` is inferred from that type list, not observed** — it could not be run before the capability existed. T074 is where it is finally run, and T075 is the fallback the spec already chose: a **second geometry assertion**, never a weakened criterion.

- [x] T069 [US1] Add **A2–A4** to `ios/UITests/SeededTransactionListUITests.swift` — `performAccessibilityAudit` over the populated list at `AccessibilityXXXL` in Light (A2), at default size in Dark (A3), and at `AccessibilityXXXL` in Dark (A4). Set content size through `launchArguments` (`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`) and appearance through `XCUIDevice.shared.appearance`, restoring both in a teardown block, exactly as the shipped front-door suite does (SC-002).
- [x] T070 [US1] Add **A6** — the populated list audited under Increase Contrast, which only `simctl` can set. `make a11y-sweep` already runs `-only-testing:KanameUITests` with the setting on and restores it afterwards, so the new suite is picked up **without changing the target**; run `make a11y-sweep` and confirm the seeded tests appear in its output and pass. If the sweep needs a longer timeout for a seeded launch, adjust the test rather than the sweep (FR-037).
- [x] T071 [US1] Add **A8** to `ios/UITests/SeededTransactionListUITests.swift` — the group heading announced on entry carries the **year** for a prior-year date, which is why `small`'s six days sit in a prior calendar year (gate G4, 018 FR-035).
- [x] T072 [US1] Write **A5** and **A7**, the two FR-038 assertions, in `ios/UITests/SeededTransactionListUITests.swift`: **A5** is `performAccessibilityAudit` with a filter applied at `AccessibilityXXXL` — the exact state `018/02` failed in; **A7** is **geometry, not audit** — with `small` seeded and filtered, at `AccessibilityXXXL`, scrolled to the end, `XCTAssertLessThanOrEqual(lastRow.frame.maxY, filterBar.frame.minY)`. Both must pass against the current, fixed code before they are broken against — an assertion that is red for an unrelated reason proves nothing about the defect it names.
- [x] T073 [US1] **DELIBERATE BREAK — `018/02` reinstated.** Force `FilterChromeLayout.axis` to `.horizontal` in `ios/Sources/Transactions/TransactionListModels.swift:287` (the break the ticket's own resolution records as what produced `•••• 77…`, ~420 pt of demand on a 393 pt screen). Run the seeded suite at `AccessibilityXXXL` with a filter applied and **record what A5 does, verbatim** — including the audit issue's `auditType` if it fires. Revert in the same commit; re-run green.
- [x] T074 [US1] 🚨 **DETERMINE — does the auditor actually fire `.textClipped` for `018/02`?** This is the one question the planning pass could not answer, because answering it required this capability. Read T073's recorded output and decide: (a) A5 went red on `.textClipped` — R10's inference is confirmed, note it in `research.md` R10 as **observed** rather than inferred and proceed; or (b) A5 stayed green — the auditor does not see a chip truncating inside its own element, which is a finding about the instrument, not about the defect. Record the verdict verbatim either way, with the exact audit output. ⚠️ **Under no circumstances is the criterion weakened, and under no circumstances is the defect re-parked.**
- [x] T075 [US1] **FALLBACK (execute only if T074 lands on (b)) — a second geometry assertion, of A7's shape.** Add **A5b** to `ios/UITests/SeededTransactionListUITests.swift`: with `deep` seeded and filtered to the account with the longest declared name, at `AccessibilityXXXL`, assert the scope chip's rendered label **equals the declared scope string** (no `…`) and that its frame contains its text rather than clipping it. Then **watch A5b go red** against T073's same break, record verbatim, and revert. FR-038 asks for coverage that catches `018/02`; if the auditor is the wrong instrument, the answer is a sharper instrument.
- [x] T076 [US1] **DELIBERATE BREAK — `018/03` reinstated.** Restore `FilterChromeLayout.maximumScopeLines` to **6** in `ios/Sources/Transactions/TransactionListModels.swift:289` — the break `018/03`'s resolution records as the one that produced an unbounded bar slicing a row's amount. **A7 must go red**: the last row's `maxY` crosses the filter bar's `minY`. Record the verbatim failure, including both frames. Revert in the same commit; re-run green.
- [x] T077 [US1] Record FR-038 / SC-006's evidence — the two reinstated defects, the two instruments, the two verbatim failures, T074's verdict, and whether T075 was needed — in `specs/019-debug-test-seeding/quickstart.md` § *How FR-038's "watched failing" is actually carried out* and in the PR description. "Observed failing" is a claim about a record, not about a memory.
- [x] T078 [US1] Confirm `ios/UITests/ImportFrontDoorUITests.swift`'s `auditIgnoringContrastOverUnrenderedArea` was **not copied by reflex** to any seeded audit. It is a narrow suppression, proved in four recorded steps, about the front door's unrendered explanation text; a list scrolls, so its rows are inside the window. If any seeded audit turns out to need a suppression, it carries **its own** four-step proof, recorded the same way — and this task records that no suppression was needed, if none was.
- [x] T079 **GATE** the full PR C verification gate before the PR opens: `make core-lint && make core-test` (**wait** — `s5` is wall-clock), then `make lint && make ios-test`, then `make import-audit && make release-audit`, then `make a11y-sweep`. Record the counts.

**Checkpoint**: The populated list is audited across four size × appearance combinations plus Increase Contrast; the filter's four states, the paging, the currencies and the empty states are covered; and — the reason the slice exists — the new coverage has been **watched failing** against the two defects a person found by hand, with the instrument question that planning could not settle now settled by running it.

## PR C — RECORDED

**Gate (2026-08-18, run sequentially):** `core-lint` + **310 core tests** green with `core/`
untouched; `make lint` **0 violations in 99 files**; `make ios-test` **275 unit tests in 53
suites** and **33 UI tests** (up from 21 in PR B, and from 6 before this slice); `make
import-audit` ten scans; `make release-audit` **OK, 4,534 symbols**; `make a11y-sweep`
**33 UI tests green under Increase Contrast** — which is A6, and the seeded suites appear in it
without the target being touched.

**Six deliberate breaks watched red, each reverted in the same commit** — plus five re-run against
the real seeding path (T064/T065). See the table under *FR-038* below for the two that matter most.

| Break | Went red |
|---|---|
| T053 `deep` shrunk below the page size | `("46") is not greater than ("100") — the list never paged more than twice` |
| T062 the cross-source pair declared as two cards | E2: `("3") is not equal to ("0") — the echo card is meant to have nothing live`, **and** the shape suite's sequence assertion. The fixture's own arithmetic is what noticed a supersession that vanished in silence |
| T064 break 1 (guard removed, **real** path) | Scan A ⛔ FR-024 — and the **Release build failed**: `cannot find 'SeedScenario' in scope`. T011's open question is answered: against a referenced path the *compiler* is the third gate |
| T064 break 2 (code moved to `Sources/Transactions/`) | Scan A ⛔ reverse direction |
| T064 break 3 (guarded stub referenced from `RootView`) | Scan A ⛔, and the Release build again: `cannot find 'DebugSeed' in scope` |
| T064 break 4 (literal on an unused declaration) | Scan A ⛔ |
| T065 break 5 (audit pointed at a stripped copy) | `FAIL (inconclusive) — the binary carries no 'FilterChromeLayout' symbol`; **4,534 → 156** symbols measured |

### 🚨 FR-038 / SC-006 — what the "watched failing" actually taught (T072–T077)

Written up in full in `quickstart.md` § *What it turned out to be*, and R10 is now annotated
**OBSERVED**. Four corrections, all recorded rather than tidied away:

1. **Neither one-line break reproduces its defect.** Both 018 fixes were plural. `axis` →
   `.horizontal` alone left everything green; it needed `clearButtonShowsTitle` → `true` with it.
   `maximumScopeLines` → `6` alone left everything green too — the bound only bites when a name is
   long enough to want the lines.
2. **A fixture that cannot express a defect cannot watch a gate catch it.** `SYNTHETIC BANK ONE`
   is three short words and fits anywhere; both parked defects are defects of a *long name at a
   large text size*. `small`'s account is now **`SYNTHETIC INTERNATIONAL REWARDS BANK`**,
   permanently, and that is the single most transferable thing in this PR.
3. **T074's verdict is (b): the auditor does not see `018/02`.** Reinstated faithfully — chip
   reading `••••…` over `SYN-T…NE`, the ticket's screenshot reproduced — **A5 passed**. And
   `.textClipped` could not have discriminated it anyway: at XXXL this screen fires that type
   **by design** (`issues/03`).
4. **A label cannot show a truncation.** XCUITest reports a `Text`'s string, not its glyphs: with
   the screen reading `••••…` the element's label was still `•••• 0006`. An ellipsis assertion is
   inert, and anything built on labels would have passed while quoting the right answer back.

**What carries FR-038 is geometry, both times**, and both were watched red:

| Defect | Instrument | Recorded failure |
|---|---|---|
| `018/02` | **A5b** — the chip must hold more than two thirds of the window at accessibility sizes, because that is what going vertical *means* | `("163.0") is not greater than ("235.8") … so the bar did not go vertical` |
| `018/03` | **A7** — the bottom-most rendered row's `maxY` against the chip's `minY` | `("1121.0") is greater than ("456.7") — a row is underneath the filter bar` |

⚠️ A7 asserts **geometry before completeness**: the first version checked "the walk reached the
last row" first and reported a missing row where the defect is a *covered* one.

### Findings recorded rather than worked around

- **`issues/02` — two empty states no seed can reach.** T058 asked about
  `nothingToShowAnywhere`; the answer is that **it and `accountNothingToShow` are both
  unreachable**, because every supersession the import path can produce leaves a **live winner**
  (re-import keeps the held row; cross-source keeps the earlier account's), and `is_deleted` has
  no write path. **Four of six `EmptyKind` cases are now audited against a rendered screen**; two
  are unreachable and keep their unit coverage. No write path was acquired to force them — that is
  FR-008a's whole point.
- **`issues/03` — the XXXL audits exclude `.textClipped` and `.dynamicType`.** The shipping row
  caps its account line at one line so the masked digits survive (`018/04`) and fixes the amount's
  size (FR-021), so the auditor is **right** about at least one of them and red before any break.
  The exclusion is stated at the assertion site; the default-size audits are not reduced.
- **`issues/04` — SC-009 measured the machine.** The bare five-second wall clock read 4.65 s in
  `ios-test` and **7.98 s** in `a11y-sweep` — same build, same six rows. It now measures the
  **difference** against an unseeded launch: **1.42 s** for the seed plus one navigation, taken on
  the loaded machine that produced 7.98 s. The `history_perf::s5` lesson, one language over.

### Deviations from the task text

- **T036's deep walk moved** into `SeededHistoryShapeUITests`, where **one** traversal of `deep`
  (115 s, 31 swipes) now answers paging, ordering, duplication, currencies, supersession and the
  account tie-break together. Four separate tests would have cost the gate eight more minutes to
  re-answer questions one walk already answers.
- **The suites are four files, not one.** `SeededHistoryShapeUITests`, `SeededEmptyStateUITests`
  and `SeededAccessibilityUITests` join the list suite; T049–T072 name a single file that would
  have gone well past SwiftLint's 400-line limit.
- **`deep` gained a fifth statement** (`SYNTHETIC CARD FIVE`, a card whose every row the ledger
  already had). It is the only shape the import path can produce that reaches
  `hasOnlyExcludedRows`, and E2 needs it. Live rows stay **160**; declared supersessions go 2 → 5.
- **A5's substance is A5b.** T072 asked for `performAccessibilityAudit` with a filter applied; that
  test exists and passes, but it is not what catches `018/02`, and the record says so plainly
  rather than letting a green audit imply coverage it does not have.

### One process note, because it cost a whole sweep

A throwaway probe file (`ios/UITests/ZZProbe.swift`) was recreated during the `018/02`
investigation and **survived into a full `make a11y-sweep`**, where it ran as a 34th test. It was
harmless, and that is the point: nothing in the gate objects to a scratch file in a test target.
Delete probes in the same command that reads their output.

---

# PR D — Honesty and hand-back

*The `nothingImported` host-render, the rewrite of 018's manual gate record, the seeding instructions, the handoff, and the full gate. **US6 + Polish.** Lands last because the manual gate cannot be honestly shrunk until PR C has established exactly which of G1–G14 an automated run now covers.*

## Phase 9: User Story 6 — The manual gate shrinks, and says so in writing (Priority: P6)

**Goal**: The record says which forty minutes a machine now takes and which a person still must, and why — with nothing in the wording letting a reader believe CI covers the rest.

**Independent Test**: Read 018's recorded gate and confirm every step is marked either automated-by-this-slice with a named test, or still-manual with the reason it cannot be automated; confirm nothing claims SC-012 is closed.

- [x] T080 [P] [US6] Create `ios/Tests/EmptyStateRenderingTests.swift` (Swift Testing) — host-render `TransactionListView`'s `EmptyKind.nothingImported` state directly via `UIHostingController` with the existing `ios/Tests/TransactionListDoubles.swift`, asserting its wording and layout. **Plus `nothingToShowAnywhere` if T058 found it unreachable by seeding.** ⚠️ The file's doc comment must state, in as many words, that this yields **no `performAccessibilityAudit`** — that API is `XCUIApplication`-only — so these states are *executed and asserted* but not *audited*, and FR-039's coverage is therefore uneven. This takes `nothingImported`'s count of automated executions from **zero** to at least one (SC-007), which is the whole of the claim being made.
- [x] T081 [US6] Confirm what this slice did **not** do to reach that state: `EmptyKind.nothingImported`'s branch in `ios/Sources/Transactions/TransactionListModels.swift` is **not deleted** (it is correct and defensive), and `ios/Sources/RootView.swift`'s toolbar condition is **not changed** (doing so would make the state real and directly contradict the shipped `testAFreshInstallOffersNoRouteToAnEmptyTransactionList`). Run that shipped test and confirm it passes unedited. FR-039a, plan § *Judgement calls* §1, option (a).
- [x] T082 [US6] Record SC-007's **uneven** coverage explicitly — five (or four, if T058 found a second exception) `EmptyKind` cases audited against a rendered screen, the remainder executed-but-not-audited, with the structural reason for each: `nothingImported`'s precondition is exactly the condition under which the front door hides the route to it, read from the **same** `accountSummaries()` call. Write it in `specs/018-transaction-list/quickstart.md`'s gate record and in this slice's PR description. A "100%" that is not true is worse than a smaller number that is.
- [x] T083 [US6] **Rewrite** — not append to — `specs/018-transaction-list/quickstart.md` § *The manual, release-blocking gate*: for each of **G1–G14**, one of three verdicts with its evidence. **Automated**, naming the assertion (A1–A8, A5b if it exists, E1–E3, S2–S6, the geometry assertion); **still manual**, naming what an automated run cannot see; or **retired**, saying why the question stopped mattering. Per research R17's table: G1, G2, G4, G5, G7 and G8 become automated; G3 **splits** — presence automated via `.sufficientElementDescription`, meaningfulness still a person's judgement. Carry the two open defect tickets and `018/issues/06` forward **verbatim**; this slice does not fix them, it makes two of them catchable.
- [x] T084 [US6] In the same record (`specs/018-transaction-list/quickstart.md`), state **G10, G13 and G14** as remaining manual, with their reasons: G10 is a device rendering judgement over the full corpus; **G13 and G14 need a live import driven through the system document picker while the list is open** — the one interaction seeding structurally cannot stage, because avoiding the picker is its entire method. This is SC-008's amended arithmetic (six automated, **eight** remaining, under twenty minutes), settled by the spec's § *Amendments after `/speckit.plan`*; the record must match it exactly and must not reclassify a gate to hit a nicer number.
- [x] T085 [US6] **Measure** the shrunk gate rather than asserting it: run the eight remaining steps of `specs/018-transaction-list/quickstart.md` and record the actual elapsed time against SC-008's "under twenty minutes", together with the device, the iOS build, the app build commit and the date (FR-045). The forty-minute figure this slice is justified by came from a measurement (`018/issues/01`); the twenty-minute figure it claims deserves one too.
- [x] T086 [US6] **FR-044 wording audit** over `specs/018-transaction-list/quickstart.md`, `AGENTS.md`, `docs/HANDOFF.md` and every other doc this slice touches: nothing claims 018's **SC-012** is closed (`issues/06`'s three device timings still need a phone), and no wording suggests continuous integration enforces a step a person must still run. Grep for "CI", "automated" and "closed" in the changed sections and read each hit against what CI actually runs after T017–T019.
- [x] T087 [P] [US6] Update `AGENTS.md` with how to seed and the traps that cost time otherwise: the bare `KANAME_SEED_SCENARIO` key on `launchEnvironment` (**not** `TEST_RUNNER_`-prefixed, which is the *unit*-test rule and delivers nothing here); the pinned `en_IN` locale and the ₹1,00,000 amount ceiling; that two cards never de-duplicate, **silently**; that `ImportService.swift` has two lines of headroom and nothing may spend them; and that `make release-audit` builds its own binary and takes ~16 s.
- [x] T088 [P] [US6] Update the P3 status line in `docs/kaname-ios-plan.md`: the DEBUG-only test-seeding slice has landed, what it buys every later P3 screen (a populated screen an automated auditor can reach, at the cost of one scenario declaration), and that the categorize slice is next.
- [x] T089 [P] [US6] Update `.scratch/HANDOFF.md` with the new reusable seams — `KANAME_SEED_SCENARIO`, `ios/Sources/DebugSeed/`, the tenth scan, `make release-audit`, and the fact that CI now runs `make import-audit` for all ten scans and lints `UITests` — and carry the findings forward with their evidence: `is_deleted` has no write path; `is_transfer` is set only by a call the app is banned from making; `EmptyKind.nothingImported` (and, if T058 says so, `nothingToShowAnywhere`) is unreachable by construction.
- [x] T090 [P] [US6] Record **FR-008a's two exclusions** where the slice that closes them will find them — in `.scratch/HANDOFF.md` and in the rewritten gate record: a seed cannot express deleted rows or transfer-flagged rows, **not** because it was hard but because a fixture that can build states the product cannot is a fixture that tests fiction. They close when the categorize slice wires transfer detection, and when — if ever — deletion becomes something a person can do.

## Phase 10: Polish, gates and the record

- [x] T091 [P] Audit that **no test in this slice is disabled**: `grep -rn "\.disabled(\|#\[ignore\]\|XCTSkip" ios/Tests ios/UITests core/crates/kaname-core/tests` returns nothing added by this slice. In particular the seeded audits and the geometry assertion are live and green.
- [x] T092 [P] Audit every fixture this slice added — `ios/Sources/DebugSeed/SeedScenarios.swift` above all — and confirm it is **entirely synthetic**: no real merchant, no real statement or fragment of one, no real account identifier, no plausible real card last-4 pattern, no registry issuer literal (SC-012, FR-011, FR-035). `make import-audit`'s bank-literal scan already covers this directory; this task is the human half that a scan cannot do.
- [x] T093 [P] Final record of the **deliberate non-change** (017's precedent, closing what T002 opened): `git diff --stat main...HEAD -- core/` is empty across all four PRs; `SCHEMA_VERSION` is still **7**; no migration, no table, no column, no index, no `#[uniffi::export]`. Write it into `specs/019-debug-test-seeding/quickstart.md` § *Definition of done* and the final PR description — a slice that touched the engine here would have been a slice that stopped going through the front door.
- [x] T094 [P] Confirm `wc -l ios/Sources/Import/ImportService.swift` is **398**, unchanged by every PR in this slice, and that `ios/Sources/KanameApp.swift`'s only change is the three-line `#if DEBUG` block.
- [x] T095 **FULL GATE** `make core-lint` (repo-root `Makefile`).
- [x] T096 **FULL GATE** `make core-test` — unchanged by this slice and required to stay green. ⚠️ **Wait for it to finish before T097**; never run concurrently with the iOS gates (`history_perf.rs::s5`).
- [x] T097 **FULL GATE** `make lint` — `swiftlint --strict` and `swift-format lint --strict` over `Sources Tests UITests`.
- [x] T098 **FULL GATE** `make ios-gen && make ios-test` — never a bare `tuist generate`.
- [x] T099 **FULL GATE** `make import-audit` — **ten** scans, the tenth of them this slice's.
- [x] T100 **FULL GATE** `make release-audit` — the Release binary carries no seeding path, and the self-check found both anchors before saying so. Record the symbol count on the passing line.
- [x] T101 **FULL GATE** `make a11y-sweep` — Increase Contrast, now over a **populated** screen rather than an empty one, which is the single sentence this whole slice exists to be able to write.

**Checkpoint**: The capability is covered, the price is proved and has been watched being collected, the manual gate is shrunk in writing with its remaining eight steps and their reasons, and the three findings this slice discovered rather than caused are carried forward with their evidence.

## PR D — RECORDED

**Full gate (2026-08-18), run sequentially, one at a time:** `core-lint` clean and **310 core
tests** green; `make lint` **0 violations in 99 files**; `make ios-test` **278 unit tests in 54
suites** and **33 UI tests**, 0 failures; `make import-audit` **ten scans**; `make release-audit`
**OK, 4,534 symbols scanned, 6 terms**; `make a11y-sweep` **33 UI tests green under Increase
Contrast**, over a populated screen — the one sentence this whole slice exists to be able to write.

**T093, the deliberate non-change, closing what T002 opened:** `git diff --stat 72f9423 -- core/`
is **empty across all four PRs**; `SCHEMA_VERSION` is still **7**; no migration, no table, no
column, no index, and no `#[uniffi::export]` added or altered. **T094:** `ImportService.swift` is
still **398** lines and `KanameApp.swift`'s only change is the three-line `#if DEBUG` block.
**T091:** nothing in this slice is disabled — no `.disabled(`, no `#[ignore]`, no `XCTSkip`.
**T092:** every fixture name begins `SYNTHETIC`, every last-4 is `000N` (the convention
`make perf-corpus` already uses), and no registry issuer literal appears — the bank-literal scan
covers the directory mechanically, and this is the reading a scan cannot do.

### T080 — the three states no seed can reach, and what a hosted view will not tell you

`ios/Tests/EmptyStateRenderingTests.swift` host-renders `nothingImported`,
`nothingToShowAnywhere` and `accountNothingToShow`. Before it, the first of those had **zero**
automated executions of any kind. **Watched red** against `EmptyKind.decide` returning the wrong
case, which failed both halves: the state assertion and the rendering.

Three facts cost a rebuild each and are worth more than the test:

1. **A new file is in no target until `make ios-gen`.** The suite ran, reported *success*, and
   the run's total stayed at 275 — the same trap PR A hit from the other end, and the reason a
   count is checked rather than an exit code.
2. **`RunLoop.main.run(until:)` in an async `@MainActor` test is a deadlock**, not a wait: it
   occupies the actor the continuation needs, so the view sat on its `ProgressView` for two
   seconds and the assertions failed for a reason unrelated to the state. `Task.sleep` yields.
3. **A detached `UIWindow` has no display link.** SwiftUI drew it once and then stopped, so the
   view's own `.task` set the state back to `.loading`, finished, and nothing ever redrew the
   result. Attaching the window to the **host app's scene** fixed it.

⚠️ **And the assertion this file was specified to make cannot be made at all.** A hosted SwiftUI
view publishes **no `UILabel` and no accessibility label** — text is drawn, and the accessibility
tree materialises only when an assistive technology asks for it, which is why XCUITest can read a
row's sentence and a unit test cannot. So the wording is asserted through
`TransactionListStrings.emptyState(for:)` — the same function the view renders — and the rendering
proves the branch was taken and produced this state's shape. "Executed and asserted, **not
audited**" is the honest phrase, and it is in the file's own doc comment.

One thing the rendering did catch for free: `nothingImported` renders its action as a
`UIPlatformGlassInteractionView` and the other two as hosted buttons — design note **D2** showing
through, because the state with no accounts has no filter bar to compete with and takes the
prominent style.

### T085 — the shrunk gate is **not** measured, and the record says so

SC-008 claims **under twenty minutes**. That figure is unmeasured and this record will not assert
it: every one of the remaining steps needs a **physical iPhone** — G6 is a device setting with no
simulator control, G9–G12 are device timings, G13/G14 need a person driving a document picker —
and no device was available. Recorded as a deferral in
`specs/018-transaction-list/quickstart.md`, exactly as `018/issues/06` records its own.

⚠️ The forty-minute figure this slice was justified by came from a **measurement**. The twenty
deserves one too, and until it has one it is a claim, not a fact.

### T083/T084 — what the gate record now says

Six of fourteen automated (**G1, G2, G4, G5, G7, G8**), one split (**G3** — the sentence is
asserted, its meaningfulness is not), seven still manual (**G6, G9–G14**). Every verdict names
either the assertion that carries it or the reason a machine cannot see it, and **nothing claims
018's SC-012 is closed** — `issues/06`'s three device timings still need a phone (T086 audited the
wording across every touched document).

### One process note, and it cost a full gate run

`make ios-test` was started while a previous `make ios-test` was **still running**, so two
`xcodebuild test` invocations uninstalled and installed under each other on one simulator. The
result was four *front-door* failures — a fresh-install assertion finding an accounts list, and
two contrast audits against the wrong screen — that looked exactly like a real regression in code
this PR never touched. This list says "never run the core and iOS gates concurrently" in eight
places; it turns out **the iOS gate cannot be run concurrently with itself** either. Re-run alone:
green, first time.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies. T003 **blocks T008** (an audit whose self-check anchors were never measured is an audit that fails inconclusive on first run). T004 blocks T005–T007 and T011–T015.
- **Foundational (Phase 2)**: depends on Setup. **BLOCKS every user story.** Internally:
  - **2A (Scan A)** and **2B (Scan B)** are independent of each other — different files — but 2A is cheaper and lands first so 2C can watch both from one break.
  - **2C (the five breaks)** depends on 2A **and** 2B: four of the five must be watched against both scans.
  - **2D (CI)** depends on 2A and 2B existing as `make` targets; T020/T021 depend on the workflow edits.
  - **2E (gate)** depends on all of 2A–2D.
- **US1 (Phase 3)**: depends on all of Phase 2. T028 → T030 → T031; T031 → T032; T033 requires `make ios-gen` before any UI test runs. T037/T038 depend on the GREEN at T035.
- **US4 (Phase 4)**: depends on US1's seeding path. T042's honest RED depends on T045's break being available.
- **US5 (Phase 5)**: depends on `deep` (T029) and US1's list. Independent of US3.
- **US3 (Phase 6)**: depends on `deep` and the filter. T057/T058 depend on T056's empty-state suite existing.
- **US2 (Phase 7)**: depends on the **real** path existing (PR B) — it is PR A's proof re-run where it finally has something to find.
- **FR-038 (Phase 8)**: depends on US5's `AccessibilityXXXL` scrolling and US3's filter. **T075 depends on T074's verdict** and is executed only on outcome (b).
- **US6 (Phase 9)**: depends on Phases 5–8 being complete — the gate record cannot honestly say which of G1–G14 is automated until the assertions exist and have been watched failing.
- **Polish (Phase 10)**: depends on everything. T085 depends on T083/T084.

### User Story Dependencies

- **US1 (P1)** — Foundational only. **The MVP.**
- **US4 (P4)** — US1. Determinism of the path US1 built.
- **US5 (P5)** — US1 + `deep`. Independently testable.
- **US3 (P3)** — US1 + `deep`. Independent of US5.
- **US2 (P2)** — pre-paid by PR A against a stub; **closed** in PR C once there is a real path to prove absent. This is the deliberate inversion, and it is the point.
- **US6 (P6)** — every other story, because it is the bookkeeping of what they automated.

### Within Each Story

- RED test tasks are written and **must be observed failing** before their implementation task.
- Every gate is watched failing before it is trusted: T005 (the gap), T011–T015 (the five), T020/T021 (in CI), T037/T038, T045/T046, T053, T062, T073/T076 (FR-038's two).
- A story is complete only when its verification-gate tasks pass.
- ⚠️ Core gates and iOS gates run **sequentially**, never concurrently, in every gate task in this list.

### Parallel Opportunities

- **Setup**: T002, T003, T004, T005 in parallel (T003 and T004 touch nothing in common; T005 needs T004).
- **Foundational**: 2A (T006–T007, `scripts/import-path-audit.sh`) and 2B (T008–T010, `scripts/release-absence-audit.sh` + `Makefile`) are different files and fully parallel. **T011–T015 are strictly serial** — each is a break of the working tree and reverted in its own commit; two at once make neither observation trustworthy. T017–T019 are three edits to one workflow file: serialise the commits.
- **US1**: T026 and T027 are two new test files — fully parallel. T028/T029 (declarations) and T030 (builder) are the same file plus one new one — serialise T028 → T029 → T030.
- **US4**: T042 and T043 are independent test additions; the two breaks T045/T046 are serial.
- **US5 / US3**: T049–T051 are parallel; T055–T056 are parallel; the two phases touch the same test file, so staff them together only if the file's edits are serialised.
- **US6 / Polish**: T087, T088, T089, T090 are four different documents — fully parallel. T091–T094 are four independent audits — fully parallel.

---

## Parallel Example: Phase 2's two gates

```bash
# Two scripts, no shared state — launch together (but keep the five breaks serial):
Task: "Add the tenth scan to scripts/import-path-audit.sh (Scan A)"
Task: "Create scripts/release-absence-audit.sh with its self-check (Scan B)"
```

## Parallel Example: User Story 1's RED suites

```bash
# Two new UITest files against a path that does not exist yet:
Task: "RED ios/UITests/SeedContractUITests.swift (L1–L6)"
Task: "RED ios/UITests/SeededTransactionListUITests.swift (S1–S3, A1)"
```

---

## Implementation Strategy

### The price first (PR A)

1. Phase 1 — Setup (T001–T005), including the measurement that the audit's design depends on
2. Phase 2 — Foundational (T006–T025): both scans, the five breaks watched red, CI closed
3. **STOP and VALIDATE**: if the gate cannot be made to fail on all five injected cases, **the slice stops here** and nothing that fabricates financial data has been written. That is a real outcome, not a formality.

### MVP (PR A + PR B)

4. Phase 3 — User Story 1 (T026–T041)
5. **STOP and VALIDATE**: run US1's independent test — no human, no file, a populated list matching the declaration exactly, and an accessibility audit against a rendered screen with rows on it.
6. Phase 4 — User Story 4 (T042–T048). This is a shippable increment: the screen that took three slices to build is covered, and the coverage is reproducible.

### Incremental Delivery

PR A (the proof) → PR B (US1 MVP, US4) → PR C (US5, US3, US2 closed, FR-038 watched failing) → PR D (US6 + polish). Each PR adds value without breaking the last, and each ends on the full verification gate — core first, **then** iOS, plus `make import-audit` and `make release-audit`.

---

## Recommended PR split

**101 tasks**, one language, **zero** Rust files, **zero** FFI changes, **zero** migrations (schema stays v7), one new Swift directory of three files, one new script, one new `make` target, a tenth scan, three lines in `KanameApp.swift`, one line in `Project.swift`, and three CI steps. The delivery order below is **mandatory, not advisory** (`plan.md` § *Delivery order*).

| PR | Tasks | Contents | Why it stands alone |
|---|---|---|---|
| **A — The absence proof, first** 🔒 | **T001–T025** | The tenth scan in `scripts/import-path-audit.sh`; `scripts/release-absence-audit.sh` with the self-check that makes "inconclusive" a verdict; `make release-audit`; **the five deliberate breaks watched red** against a stub `DebugSeed/`; and FR-043a's CI wiring — `make import-audit` (which CI has **never** run, for any of its nine scans) plus `make release-audit`, with `swift-format` widened to `UITests` | Shell and YAML only. **Merges first, on purpose**: the price is paid before the capability is bought, and reviewing the proof against a stub is the only way to watch break 5 fail honestly. If this PR cannot be made to work, the slice stops and nothing has been written that fabricates financial data. |
| **B — The seeding path** 🎯 | **T026–T048** | `ios/Sources/DebugSeed/` for real — `applyIfRequested`, the file-level reset, the builder — the three-line `#if DEBUG` block in `KanameApp.swift`, the one line in `Project.swift`, both named scenarios, `SeedContractUITests` (L1–L6), the first seeded audit (S1–S3, A1), and determinism (D1–D4). US1, US4 | 🎯 The first PR where an automated test sees a transaction, and the natural place to stop and validate. Depends on A only in the sense that A's gate is already watching it — which is the intended feeling. |
| **C — What the coverage was for** | **T049–T079** | Paging over 160 rows, the small scenario's end-of-list, the currency and ordering assertions; the superseded rows, the count parity, the empty states and the filter's four states; the encrypted-store proof; **US2 closed** — the five breaks re-run against the real path and a Release build launched *with* the instruction; and the point of the slice, **A5 and A7 watched failing against reinstated `018/02` and `018/03`**, with T074 finally answering whether the auditor sees a clipped chip and T075 standing ready with a second geometry assertion if it does not. US5, US3, US2 + US1's audits | The defects only reproduce on a populated screen, so this cannot precede B. It is also the PR a reviewer should read most slowly: it contains the only evidence that the new coverage catches anything. Depends on B. |
| **D — Honesty and hand-back** | **T080–T101** | The `nothingImported` host-render (and a second exception if T058 finds one), the **rewrite** of 018's fourteen-step manual gate record with every step marked automated-with-its-assertion or manual-with-its-reason, SC-008's amended eight, the measured duration of what remains, the FR-044 wording audit, `AGENTS.md` / `docs/` / `.scratch/HANDOFF.md`, and the full seven-target gate. US6 + Polish | Lands last because the manual gate cannot be honestly shrunk until C has established which of G1–G14 a machine now covers. Bookkeeping — but bookkeeping that, left undone, means the forty minutes goes on being paid forever beside the automation that replaced most of it. |

**Ordering constraints across PRs**: A → B → C → D, strictly. Nothing here can run in parallel with anything else, because each PR's whole justification is the state the previous one left. Every PR runs the full Local Verification Gate — `make core-lint && make core-test`, **wait**, `make lint && make ios-test`, plus `make import-audit` and `make release-audit` — before it opens.

---

## Notes

- `[P]` = different files, no shared state, no dependency on an incomplete task.
- `[Story]` maps a task to its user story for traceability; Setup / Foundational / Polish tasks carry none. **PR A carries no story label although it pre-pays US2** — there is nothing to prove absent yet but the shape of the thing, and US2 closes in PR C where a real path exists to prove absent.
- **Verify every RED test actually fails before implementing it**, and every gate actually goes red before trusting it. This repository has learned twice that a green gate is not evidence: `018/02` passed every unit test in the repo while broken on screen, and 018's own task list records five and six deliberate breaks watched per phase for exactly this reason.
- **The deliberate breaks are T011–T015 (the absence proof, ×5), T020/T021 (in CI), T037, T038, T045, T046, T053, T062, T064/T065 (the five re-run against the real path), and T073/T076 (FR-038's two reinstated defects)** — plus T075's re-watch if T074 lands on (b). Each is reverted in the same commit and re-run green.
- **⚠️ Never run the core and iOS gates concurrently.** `core/tests/history_perf.rs::s5` is a wall-clock bound and flaky under CPU contention; this slice adds a 16-second Xcode build to the gate and a person who parallelises to win it back will pay for it there.
- **⚠️ `make ios-test`'s preamble uninstalls the app and pins `content_size large`**, both for recorded false-failure reasons. Leave it alone; a seeded test that sets its own text size **puts it back**.
- **⚠️ `make ios-test` and `make a11y-sweep` pin the `iPhone 16` simulator.** A suite run by hand on a different destination loses the uninstall and the text-size pin — which is exactly how a false failure was bought on 2026-08-16.
- **A bare `tuist generate` is never correct**: always `make ios-gen`.
- **`grep -c` must not be used and a bare `grep` must not end a pipeline** under `set -euo pipefail` — it exits 1 when it finds nothing, which is the passing case. Every scan ends `|| true`.
- **swift-format `[Spacing]` rejects trailing inline comments** — put comments on their own line. As of T019 this is enforced in CI for `UITests` too.
- **`cargo` is not on the default PATH**: `export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"` in every shell.
- **`ios/Sources/Import/ImportService.swift` is at 398 of 400 lines.** No task in this slice touches it; T094 re-checks.
- **Never** commit a real statement, a real merchant record or a real account identifier — in a scenario least of all, because a scenario is a statement somebody wrote by hand.
