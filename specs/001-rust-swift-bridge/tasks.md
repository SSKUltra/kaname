---
description: "Task list for feature 001-rust-swift-bridge"
---

# Tasks: Prove the App Is Powered by the Shared On-Device Engine

**Input**: Design documents from `/specs/001-rust-swift-bridge/`
**Prerequisites**: `plan.md` (required), `spec.md` (required), `research.md` (D1–D10),
`data-model.md`, `contracts/engine-ffi.md`, `quickstart.md`

**Tests**: INCLUDED and **test-first** — mandated by Constitution **Principle V** and
FR-014/FR-015. The failing **Rust unit test for `normalize_transaction`** and the failing
Swift **"core ↔ Swift round-trip"** test are authored **before** the code that makes them
pass. Test tasks are marked **(TEST-FIRST ⚠️)** and must be **red** before their
implementation task runs.

> ⚠️ **LOCAL GOTCHA (Xcode 26)** — the `iPhone 16` simulator the gate uses is **not**
> created by default locally. Create it once before any `xcodebuild`/`make ios-test` run:
> `xcrun simctl create "iPhone 16" "iPhone 16"` (see **T002**). CI's `macos-15` already
> provides it. Do **not** downgrade the runner: Homebrew `tuist` aborts on `macos-14`
> (exit 134) — `macos-15` stays pinned (research D6).

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: `[US1]`/`[US2]`/`[US3]` — the user story a task serves (Setup/Foundational/Polish carry no story label)
- Every task names an exact file path and is independently verifiable

## Ordering note (how the plan's file-map maps to these phases)

The plan's file-map is the backbone; it is realized inside the mandatory **user-story +
priority** structure with **test-first** enforced per story:

- **Bridge plumbing** (UniFFI deps/bindgen/`setup_scaffolding!`/`engine_version()` export
  → `KanameCoreFFI.xcframework` build → Tuist `KanameCore` wiring) is **Foundational** —
  every story rides on it (plan file-map items 1–3).
- **Behavioral slices** are grouped by story: **US1** = the version *display* (item 4);
  **US2** = the typed *round-trip* (`model.rs` derives + `ffi.rs` custom types +
  `normalize_transaction`); **US3** = the automated proof + green CI (item 6).
- **Tests** (item 5) are **hoisted** ahead of the code they cover (Principle V), so they
  appear at the top of each story rather than in one late block.
- **Setup** owns `.gitignore` (item 7) + local toolchain/simulator.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Local prerequisites and artifact hygiene. No engine/app behavior yet.

- [ ] T001 [P] Verify the toolchain via `make bootstrap` (rustup, tuist, swiftlint, swift-format) and confirm the three iOS Rust targets from `rust-toolchain.toml` are installed: `rustup target list --installed | grep -E 'aarch64-apple-ios($|-sim)|x86_64-apple-ios'` (expect `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`).
- [ ] T002 [P] **(Xcode 26 gotcha)** Create the local simulator the gate targets: `xcrun simctl create "iPhone 16" "iPhone 16"` (idempotent; append `|| true`). Verify with `xcrun simctl list devices | grep "iPhone 16"`.
- [ ] T003 [P] Update `/.gitignore`: add `ios/Generated/` and `ios/Frameworks/*.xcframework` so the UniFFI-generated Swift and the built xcframework stay git-ignored build artifacts (research D7). Verify `git check-ignore ios/Generated/KanameCore.swift ios/Frameworks/KanameCoreFFI.xcframework` prints both paths.

---

## Phase 2: Foundational (Blocking Prerequisites — the UniFFI bridge)

**Purpose**: Stand up the Rust↔Swift bridge that **every** user story depends on:
UniFFI scaffolding + a seed export (`engine_version`), the `KanameCoreFFI.xcframework`
build, and the Tuist `KanameCore` module. `normalize_transaction` (US2 behavior) is
deliberately **not** here — the bridge is proven first with the version string alone.

**⚠️ CRITICAL**: No user story (US1/US2/US3) can begin until this phase completes and
`import KanameCore` resolves.

- [ ] T004 Add UniFFI to `core/crates/kaname-core/Cargo.toml`: `uniffi = { version = "0.32" }` under `[dependencies]`; add a `cli` feature (`[features] cli = ["uniffi/cli"]`) and a gated bindgen bin (`[[bin]] name = "uniffi-bindgen"`, `path = "src/bin/uniffi-bindgen.rs"`, `required-features = ["cli"]`) so shipped static/cdylib slices do **not** pull `clap` (research D1/D4). Verify `cargo metadata` resolves uniffi 0.32.
- [ ] T005 [P] Create `core/crates/kaname-core/src/bin/uniffi-bindgen.rs` with `fn main() { uniffi::uniffi_bindgen_main() }` — pins the generator to the exact `uniffi` dep (research D4). Verify `cargo build --features cli --bin uniffi-bindgen` succeeds.
- [ ] T006 [P] Create `core/crates/kaname-core/uniffi.toml` with the Swift custom-type map: `[bindings.swift.custom_types.Decimal]` → `type_name = "Decimal"`, `imports = ["Foundation"]`, `lift = "Decimal(string: {}, locale: Locale(identifier: \"en_US_POSIX\"))!"`, `lower = "String(describing: {})"` (research D2). (Inert until the Rust `Decimal` custom type lands in US2; safe to create now.)
- [ ] T007 [P] Wire `core/crates/kaname-core/src/lib.rs`: add `uniffi::setup_scaffolding!();`, change `engine_version()` to return an owned `String` (`env!("CARGO_PKG_VERSION").to_string()`) and annotate it `#[uniffi::export]` (research D3). Keep the existing `exposes_engine_version` test green (still non-empty) and refresh the stale `## P1 TODO` doc comment. (`mod ffi;` is added later in **T015** with `ffi.rs`.) Verify `cargo test -p kaname-core` passes.
- [ ] T008 Create `core/scripts/build-xcframework.sh` (executable) implementing research D4/quickstart §1: (1) `cargo build --release` for `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`; (2) generate Swift bindings in library mode (`cargo run --features cli --bin uniffi-bindgen -- generate --library <built-lib> --language swift --out-dir ios/Generated`) → `KanameCore.swift` + C header + `module.modulemap`; (3) `lipo` the two simulator arches into one universal `libkaname_core.a`; (4) `xcodebuild -create-xcframework` (device slice + universal-sim slice + headers/modulemap) → `ios/Frameworks/KanameCoreFFI.xcframework`; (5) place generated Swift at `ios/Generated/KanameCore.swift`.
- [ ] T009 [P] Extend `/Makefile`: add a `core-xcframework` target that runs `core/scripts/build-xcframework.sh`, add it to `.PHONY`, and make `ios-gen` depend on it (`ios-gen: core-xcframework`) so the xcframework is always built **before** `tuist generate` (research D5 ordering constraint).
- [ ] T010 [P] Wire `ios/Project.swift` (research D5): declare the binary `.xcframework("Frameworks/KanameCoreFFI.xcframework")`; add a `KanameCore` framework target whose `sources = ["Generated/**"]` and that links the xcframework; make both the `Kaname` app target and the `KanameTests` target `dependencies: [.target(name: "KanameCore")]`. Remove the stale `// P1: add the KanameCore.xcframework …` comment.
- [ ] T011 Foundational checkpoint: run `make core-xcframework` then `make ios-gen`, and build the app on the **iPhone 16** simulator (`xcodebuild -workspace ios/Kaname.xcworkspace -scheme Kaname -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' build`). Confirm `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/KanameCore.swift` are produced and the `KanameCore` framework compiles/links as an app dependency (`engineVersion()` available; no app import yet — US1 adds the first one).

**Checkpoint**: The bridge exists and `import KanameCore` resolves — US1/US2/US3 may begin.

---

## Phase 3: User Story 1 — See the real engine version in the app (Priority: P1) 🎯 MVP

**Goal**: The root screen shows the engine's version (e.g. "Engine v0.1.0") sourced live
from `engineVersion()` — the visible proof-of-life that the app is powered by the shared
engine, presented HIG-compliantly (Dynamic Type, Dark Mode, VoiceOver) per research D9.

**Independent Test**: Launch on the iPhone 16 sim → the version shows on first render;
bump the crate version, rebuild, relaunch → the displayed value changes with **no** edit
to app UI text (SC-002); it still shows in Airplane Mode (SC-005).

### Tests for User Story 1 (test-first) ⚠️

> Write this test FIRST and confirm it is **red** before T013.

- [ ] T012 [US1] **(TEST-FIRST ⚠️)** In `ios/Tests/KanameTests.swift` add `import KanameCore` and a Swift Testing `@Test` asserting: `engineVersion()` is non-empty **and** `RootView`'s version label is derived from it (e.g. `RootView().versionLabel == "Engine v\(engineVersion())"`). Must **fail** (no `versionLabel` yet). (Contract: engine-ffi.md → "engineVersion() … equals what the UI displays".)

### Implementation for User Story 1

- [ ] T013 [US1] Implement the accessible version display in `ios/Sources/RootView.swift` per research D9: retain the branded `ContentUnavailableView` (SF Symbol `key.fill`, "Kaname"); expose a testable `var versionLabel: String { "Engine v\(engineVersion())" }`; render it as a `.footnote`/`.caption`-styled `Text` using system fonts + Dynamic Type and **semantic** colors (Dark Mode-correct); add `.accessibilityLabel("Engine version \(engineVersion())")` for VoiceOver; if the version is empty, show branding only — never a fabricated value (FR-013). Makes **T012** green. Verify `make ios-test` passes on iPhone 16.
- [ ] T014 [US1] Independent-test checkpoint (manual + SC proof): run on the **iPhone 16** simulator; confirm the version renders within ~1 s of first render (SC-001); bump `version` in `core/crates/kaname-core/Cargo.toml`, run `make core-xcframework ios-gen`, relaunch → displayed value changes with **no** UI-text edit (SC-002); toggle Airplane Mode → still shows (SC-005); sanity-check largest Dynamic Type size + VoiceOver announcement + Dark Mode (SC-006). Revert the version bump.

**Checkpoint**: US1 is fully functional and independently demoable — the MVP.

---

## Phase 4: User Story 2 — A typed value round-trips through the engine exactly (Priority: P2)

**Goal**: A `Transaction` originates in the app, crosses to the engine via
`normalizeTransaction`, and returns **exactly** the engine-computed value — `description`
normalized (Unicode-uppercased + whitespace-collapsed), and `amount`/`date`/`direction`
preserved with no lossy conversion; money is a Swift `Decimal`, never a float.

**Independent Test**: From the app/test, send known typed inputs (incl. boundary: `0`,
very large, high-precision decimals, Unicode text) to `normalizeTransaction` and assert
the returned record equals exactly what the engine computed, repeatably (deterministic).

### Tests for User Story 2 (test-first) ⚠️

> Author BOTH tests FIRST and confirm they are **red** before T017/T018/T019.

- [ ] T015 [P] [US2] **(TEST-FIRST ⚠️ — Rust)** Create `core/crates/kaname-core/src/ffi.rs` with a `#[cfg(test)] mod tests` unit test for `normalize_transaction` and add `mod ffi;` to `core/crates/kaname-core/src/lib.rs` so it compiles: assert `description` is Unicode-uppercased + whitespace-collapsed (e.g. `"  Café  René "` → `"CAFÉ RENÉ"`); `amount` (incl. `dec!(0)`, a very large value, and a high-precision value), `date`, and `direction` are preserved **exactly**; and repeated calls yield identical output (determinism). The test calls `normalize_transaction` (still absent) so it must **fail to compile/red**. Verify red via `cargo test -p kaname-core`.
- [ ] T016 [P] [US2] **(TEST-FIRST ⚠️ — Swift)** Add the "core ↔ Swift round-trip" `@Test` in `ios/Tests/KanameTests.swift` (`import KanameCore`): build a `Transaction` (Foundation `Decimal` amount incl. `0`/large/high-precision, ISO-8601 `date` string, `Direction`, Unicode `description`), call `normalizeTransaction(input:)`, and assert `result.description == <uppercased+collapsed>` **and** `result.amount == input.amount` (Decimal value-equality), `result.date == input.date`, `result.direction == input.direction`, across boundary inputs. Must **fail** (symbol not yet in generated bindings). (Contract: engine-ffi.md → "core ↔ Swift round-trip".)

### Implementation for User Story 2

- [ ] T017 [P] [US2] Add UniFFI derives in `core/crates/kaname-core/src/model.rs`: `#[derive(uniffi::Enum)]` on `Direction` and `#[derive(uniffi::Record)]` on `Transaction`, keeping existing derives (`Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize` / `Debug, Clone, PartialEq, Serialize, Deserialize`) and the `new`/`signed_amount` methods (UniFFI ignores non-exported methods). Note: the `Transaction` `Record` derive compiles **only once T018** registers the `Decimal`/`NaiveDate` custom types (every field must be a UniFFI type) — land T017 + T018 together.
- [ ] T018 [US2] In `core/crates/kaname-core/src/ffi.rs` (created in T015), add `uniffi::custom_type!(Decimal, String, { remote, lower: |d| d.to_string(), try_lift: |s| s.parse::<Decimal>().map_err(Into::into) })` and `uniffi::custom_type!(NaiveDate, String, { remote, lower: |d| d.format("%Y-%m-%d").to_string(), try_lift: |s| NaiveDate::parse_from_str(&s, "%Y-%m-%d").map_err(Into::into) })`, plus `#[uniffi::export] pub fn normalize_transaction(input: Transaction) -> Transaction` that runs the existing `normalize_description` on `description` and echoes `date`/`amount`/`direction` unchanged (research D2/D3). (`mod ffi;` was already wired in T015.) Makes **T015** green — verify `make core-test` + `make core-lint`.
- [ ] T019 [US2] Regenerate + wire the Swift side to green **T016**: run `make core-xcframework` (regenerates `ios/Generated/KanameCore.swift` with `normalizeTransaction`, `Transaction`, `Direction`, and the `Decimal` custom type), confirm `ios/Frameworks/KanameCoreFFI.xcframework` rebuilt, verify `uniffi.toml`'s Decimal `lift` uses `en_US_POSIX` (deterministic separator — FR-008), then `make ios-test` on the **iPhone 16** simulator. Makes **T016** green.

**Checkpoint**: US1 **and** US2 both work independently — the typed round-trip is exact,
deterministic, and float-free across the boundary.

---

## Phase 5: User Story 3 — Automated proof and a green verification gate (Priority: P3)

**Goal**: The round-trip is a durable, CI-protected guarantee. The xcframework is built in
CI before `tuist generate`, no copyleft/network creeps in, and the full gate is green so
the bridge cannot silently regress.

**Independent Test**: Run the suite + gates; the round-trip tests pass and assert exact
equality; breaking round-trip fidelity turns them red; CI (core + iOS jobs) is green.

- [ ] T020 [US3] Add the xcframework build to CI in `/.github/workflows/ci.yml` (`ios` job, `macos-15`): before "Generate Xcode project", install Rust (`dtolnay/rust-toolchain@stable`) + `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`, cache cargo (`Swatinem/rust-cache@v2`, `workspaces: core`), and run `make core-xcframework`; keep `tuist generate` → SwiftLint/swift-format → simulator build+test after it (research D6). Keep `macos-15` pinned; leave the Linux `core` job unchanged (it now also compiles the UniFFI scaffolding).
- [ ] T021 [P] [US3] License audit (SC-008): from `core/`, run `cargo tree -e normal` (or `cargo deny check licenses`) and confirm the only new copyleft introduced is **MPL-2.0** (`uniffi`/`uniffi_core`) — a file-level weak copyleft that is **not** in the forbidden {GPL, AGPL, LGPL} set — and that no GPL/AGPL/LGPL crate appears transitively. Record the result against `plan.md` → Complexity Tracking.
- [ ] T022 [P] [US3] Privacy-egress guard (D8, FR-006/FR-007, SC-005): confirm `core/`'s dependency tree contains **no** networking crate (no `std::net`/socket/async-runtime/HTTP crate) — add a small guard/`#[test]` note in `core/crates/kaname-core/src/ffi.rs` documenting the version/round-trip path is pure & deterministic (determinism already asserted in T015); and confirm `ios/Project.swift` adds **no** network entitlement, **no** `NSAppTransportSecurity` exception, and **no** analytics/crash-reporter/ad SDK.
- [ ] T023 [US3] Regression-guard proof (US3 acceptance scenario 2): temporarily break round-trip fidelity (e.g. drop the `normalize_description` call or mutate `amount` in `core/crates/kaname-core/src/ffi.rs`), confirm **both** the Rust test (T015) and the Swift round-trip test (T016) go **red** via `make core-test` + `make ios-test`, then revert so the tree is green again.
- [ ] T024 [US3] CI green checkpoint (SC-007): push the branch and confirm both jobs pass — `core` (fmt/clippy/test incl. UniFFI scaffolding) and `ios` (rust targets → `make core-xcframework` → SwiftLint → swift-format → `tuist generate` → simulator build+test on `macos-15`).

**Checkpoint**: All three stories are independently functional and CI-protected.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup, docs, and the definitive local-gate assertion.

- [ ] T025 [P] Remove now-stale "wired in P1" TODO comments in `ios/Sources/KanameApp.swift` (and any remaining in `core/crates/kaname-core/src/lib.rs` / `ios/Project.swift`); if a bridge note is warranted, add a one-line pointer to `specs/001-rust-swift-bridge/quickstart.md` in `README.md`.
- [ ] T026 Run the `specs/001-rust-swift-bridge/quickstart.md` acceptance walkthrough end-to-end and tick every box in its §4 "What 'done' looks like" (version sourced from engine, version-change proof, Airplane-Mode, exact float-free round-trip, Dynamic Type/Dark Mode/VoiceOver, test-first tests present, all gates green, no secrets/telemetry/copyleft).
- [ ] T027 **FINAL — assert the whole iOS Local Verification Gate is green** (constitution "iOS Local Verification Gate"): on a clean tree with the **iPhone 16** simulator present, run and confirm all five pass — `make core-lint`, `make core-test`, `make lint`, `make ios-gen`, `make ios-test`. This is the definitive green-gate assertion required before PR.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies — start immediately.
- **Foundational (Phase 2)**: depends on Setup — **BLOCKS all user stories** (nothing can `import KanameCore` until T011 passes).
- **US1 (Phase 3)**, **US2 (Phase 4)**, **US3 (Phase 5)**: each depends only on Foundational; runnable in priority order (P1 → P2 → P3) or in parallel by different people once T011 is green. US3's `T023`/`T024` need US1+US2 tests to exist.
- **Polish (Phase 6)**: depends on all targeted stories being complete.

### Story independence

- **US1** needs only the seed export (`engineVersion()`) + the bridge — no round-trip code.
- **US2** adds the round-trip (`model.rs` derives + `ffi.rs`) and can be built/tested without touching US1's UI.
- **US3** is proof/CI/audit over whatever stories exist; `T020`/`T021`/`T022` don't depend on US1/US2 code, while `T023` exercises the US1/US2 tests.

### Within each phase / story (key edges)

- Foundational: **T004** → (T005 ∥ T006 ∥ T007) → **T008** → (T009 ∥ T010) → **T011**.
- US1: **T012 (red)** → **T013 (green)** → **T014**.
- US2: (**T015 red** ∥ **T016 red**) → **T017 + T018** (model derives + custom types + `normalize_transaction` compile together; green T015) → **T019** (greens T016). *T017 may be authored in parallel with the tests but only compiles paired with T018.*
- US3: **T020** → (T021 ∥ T022) → **T023** → **T024**.
- Test-first is non-negotiable: T012 before T013; T015 before T018; T016 before T019 (Principle V, FR-014/FR-015).

### Parallel opportunities

- **Setup**: T001, T002, T003 all `[P]`.
- **Foundational**: T005, T006, T007 `[P]` after T004; then T009, T010 `[P]` after T008.
- **US2**: T015, T016, T017 `[P]` (Rust test / Swift test / `model.rs` derives — three files).
- **US3**: T021, T022 `[P]` (license audit / privacy guard).
- **Polish**: T025 `[P]`.

---

## Parallel Example: Foundational file scaffolding (after T004)

```bash
# Three independent files, no ordering between them:
Task: "T005 Create core/crates/kaname-core/src/bin/uniffi-bindgen.rs"
Task: "T006 Create core/crates/kaname-core/uniffi.toml (Decimal → Foundation.Decimal)"
Task: "T007 Wire lib.rs: setup_scaffolding!() + #[uniffi::export] engine_version()->String"
```

## Parallel Example: User Story 2 (author both failing tests + derives together)

```bash
# Test-first tests + the independent model-derive edit run in parallel:
Task: "T015 [US2] Failing Rust test for normalize_transaction in core/.../src/ffi.rs"
Task: "T016 [US2] Failing Swift 'core ↔ Swift round-trip' test in ios/Tests/KanameTests.swift"
Task: "T017 [US2] uniffi::Enum/Record derives in core/crates/kaname-core/src/model.rs"
```

---

## Implementation Strategy

### MVP first (US1)

1. Phase 1 Setup → 2. Phase 2 Foundational (bridge + xcframework + Tuist, **T011** green)
   → 3. Phase 3 US1 (version display, test-first) → **STOP & VALIDATE** (T014) → demo the
   MVP: the app shows a live, engine-sourced version.

### Incremental delivery

- Foundational done → US1 (MVP: version) → US2 (typed round-trip) → US3 (automated proof +
  green CI). Each story adds value and stays independently testable; finish with Polish
  **T027** (whole gate green).

### Parallel team strategy

- Everyone lands Setup + Foundational together (it blocks all stories). Once **T011** is
  green: Dev A → US1, Dev B → US2, Dev C → US3 (T020–T022), converging on T023/T024 once
  the US1/US2 tests exist.

---

## Notes

- **[P]** = different files, no dependency on an incomplete task; **[Story]** maps a task to US1/US2/US3 for traceability.
- **Verify tests fail first** (T012, T015, T016) — a green "test-first" test proves nothing.
- **iPhone 16 simulator** must exist locally (T002) or every `xcodebuild`/`make ios-test` (T011, T013, T014, T019, T023, T027) fails its destination lookup; CI's `macos-15` provides it. Never downgrade CI to `macos-14` (tuist exit 134).
- **Money is never a float** — `Decimal` crosses as an exact base-10 `String` and surfaces as Swift `Foundation.Decimal` (FR-010, research D2).
- **Artifacts are git-ignored** — `ios/Generated/KanameCore.swift` and `ios/Frameworks/KanameCoreFFI.xcframework` are regenerated by `make core-xcframework`; only the script, `uniffi.toml`, Makefile/Project.swift/CI wiring are committed (research D7).
- Commit after each task or logical group; stop at any checkpoint to validate a story independently.
