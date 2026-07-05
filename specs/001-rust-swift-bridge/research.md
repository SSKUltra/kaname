# Phase 0 Research: Rust ↔ Swift Bridge (UniFFI)

**Feature**: `001-rust-swift-bridge` | **Date**: 2026-07-05
**Input**: `spec.md`, Kaname Constitution v1.0.0, `docs/HANDOFF.md` §4 (P1), `docs/kaname-ios-plan.md` §3/§6/§9

This document resolves every technical unknown needed to plan the thin end-to-end
bridge. Each decision is grounded in the constitution (which wins over everything),
the locked decisions in the handoff/plan docs, and the current UniFFI toolchain.

---

## D1 — Binding mechanism & UniFFI version

- **Decision**: Use **UniFFI `0.32`** (latest; published 2026-06-30) with the **modern
  proc-macro / no-UDL** flow: `uniffi::setup_scaffolding!()` in `lib.rs` plus
  `#[uniffi::export]` on functions and `#[derive(uniffi::Record)]` / `#[derive(uniffi::Enum)]`
  on types. No `.udl` file, no `build.rs`, no `include_scaffolding!()`.
- **Rationale**: The constitution mandates UniFFI for the shared-core boundary
  (Principle II) and the handoff locks it (§2). The proc-macro path is the upstream-
  recommended approach for new crates — it keeps the interface definition co-located
  with the Rust source (single source of truth) and eliminates UDL/scaffolding drift.
  The crate is already `crate-type = ["staticlib","cdylib","lib"]`, i.e. FFI-ready.
- **Alternatives considered**:
  - *UDL-first UniFFI* — rejected: duplicates type definitions in `.udl` + Rust and
    needs `build.rs`; more moving parts for no benefit on a greenfield crate.
  - *Hand-written C FFI + a manual Swift shim* — rejected: no typed Swift, error-prone
    manual memory management, and it abandons the Android/desktop reuse story.
  - *swift-bridge crate* — rejected: UniFFI is the constitution- and handoff-locked
    choice and is what Android (Kotlin) reuse will also lean on.

---

## D2 — Crossing `Decimal` (and dates) without floats

The round-trip must carry the real domain type (`Transaction`) whose `amount` is a
`rust_decimal::Decimal` and whose `date` is a `chrono::NaiveDate`. Neither is a UniFFI
builtin, and both live in **external crates** (they are UniFFI **remote** types).

- **Decision**: Declare both as UniFFI **remote custom types** bridged over the FFI as
  **`String`** (exact base-10 / ISO-8601 text — never `f64`):

  ```rust
  uniffi::custom_type!(Decimal, String, {
      remote,
      lower: |d| d.to_string(),
      try_lift: |s| s.parse::<Decimal>().map_err(Into::into),
  });

  uniffi::custom_type!(NaiveDate, String, {
      remote,
      lower: |d| d.format("%Y-%m-%d").to_string(),
      try_lift: |s| NaiveDate::parse_from_str(&s, "%Y-%m-%d").map_err(Into::into),
  });
  ```

- **Swift presentation**: Configure `uniffi.toml` so the `Decimal` bridge type surfaces
  as a native `Foundation.Decimal` in Swift (honoring the constitution's "Decimal in
  Swift" mandate). Leave `NaiveDate` as a Swift `String` (ISO-8601) — a `Date` is a
  point-in-time and is a poor fit for a calendar date; the ISO string is the faithful,
  lossless representation.

  ```toml
  [bindings.swift.custom_types.Decimal]
  type_name = "Decimal"
  imports = ["Foundation"]
  lift  = "Decimal(string: {}, locale: Locale(identifier: \"en_US_POSIX\"))!"
  lower = "String(describing: {})"
  ```

- **Rationale**: A `String` bridge is **exact and deterministic** for base-10 money and
  ISO dates — it categorically cannot introduce floating-point error (satisfies FR-004,
  FR-010, SC-003). `rust_decimal::Decimal: Display + FromStr` and
  `NaiveDate: Display + FromStr` (both ISO-8601), so the converters are trivial and
  lossless. Swift value-equality on `Decimal` is exact, so the round-trip test can assert
  `==` on the decimal without string-format ambiguity.
- **Money-fidelity note (must land in tasks)**: parse the bridge string with the fixed
  `en_US_POSIX` locale so the decimal separator is always `.` regardless of device
  locale (determinism / FR-008). The exact-equality assertion compares Swift `Decimal`
  values (not their string descriptions).
- **Alternatives considered**:
  - *Carry `amount` as a plain `String`, no custom type* — rejected: weakens the
    "Decimal in Swift" story the constitution asks for; the custom type is cheap.
  - *Carry money in integer minor units (`i64` paise)* — rejected: lossy for >2dp inputs
    and this slice does not functionally exercise money; a `Decimal` is the honest type.
  - *Bridge `Decimal` as `f64`* — **forbidden** by the constitution (Principle II) and
    FR-010. Never.

---

## D3 — Shape of the deterministic typed round-trip

- **Decision**: Reuse the **existing domain**. Add `#[derive(uniffi::Enum)]` to
  `Direction` and `#[derive(uniffi::Record)]` to `Transaction`, then export one pure,
  deterministic function:

  ```rust
  #[uniffi::export]
  pub fn engine_version() -> String;               // was &'static str → owned String for FFI

  #[uniffi::export]
  pub fn normalize_transaction(input: Transaction) -> Transaction;
  ```

  `normalize_transaction` runs the existing `normalize_description` on `description`
  (whitespace-collapse + Unicode uppercase) and **preserves `date`, `amount`, and
  `direction` exactly**. It is pure — no clock, no locale, no global state.

- **Rationale**: This exercises the *real* engine types (an **enum**, a **record**, a
  **`Decimal`**, a **`NaiveDate`**, and a `String`) end-to-end — exactly the shapes P2
  parsers will push across the boundary, so it de-risks the most. It proves both faces
  of the round-trip contract:
  - **Computation crosses back** — `description` is transformed non-trivially
    (`"  Café  René "` → `"CAFÉ RENÉ"`), so the value cannot be a constant (US2, FR-005).
  - **Exact preservation** — `amount` / `date` / `direction` echo unchanged, giving a
    crisp boundary-input assertion (zero, very large, many-dp, Unicode) with no lossy
    conversion (US2 scenarios 3–4, FR-004).
  - **Determinism** — same input ⇒ same output every call (FR-008, SC-004). Rust
    `str::to_uppercase` is Unicode-default-case mapping, **locale-independent**.
- **`engine_version` signature change**: UniFFI cannot export a `&'static str` return;
  change `engine_version()` to return an owned `String` (still `env!("CARGO_PKG_VERSION")`,
  `.to_string()`). Existing Rust callers/tests are unaffected (still non-empty). This
  keeps the engine as the single source of truth for the version (FR-002).
- **Alternatives considered**:
  - *Dedicated FFI DTO (`TransactionDraft` with `date: String`)* — rejected: duplicates
    the domain and proves less; the remote-custom-type cost for `NaiveDate` is tiny.
  - *Normalize the `amount` too (e.g. `Decimal::normalize`)* — rejected for this slice:
    echoing `amount` unchanged gives the cleanest exactness assertion; the `description`
    transform already proves non-constant computation.
  - *Expose only `engine_version()`* — rejected: a version string alone "could be a
    constant" (spec US2 rationale); a typed round-trip is required by FR-003/FR-005.

---

## D4 — Building `KanameCore` as an XCFramework

- **Decision**: Build reproducibly from the CLI (no GUI, no Xcode project juggling):
  1. **Compile** the static lib for the three locked targets (already in
     `rust-toolchain.toml`): `aarch64-apple-ios` (device),
     `aarch64-apple-ios-sim` + `x86_64-apple-ios` (simulator).
  2. **Generate Swift bindings** in library mode from a built artifact using UniFFI's
     Swift bindgen (`uniffi-bindgen-swift` / `uniffi-bindgen generate --library … --language swift`):
     produces `KanameCore.swift` (high-level API), a C header, and a `module.modulemap`.
  3. **`lipo`** the two simulator arches into one universal simulator static lib.
  4. **`xcodebuild -create-xcframework`** with the device slice + universal-simulator
     slice + headers/modulemap → `KanameCoreFFI.xcframework`.
  - Drive it from a `core/scripts/build-xcframework.sh` invoked by a new Makefile target
    **`make core-xcframework`**.
- **Bindgen tooling**: add an in-crate `src/bin/uniffi-bindgen.rs`
  (`fn main() { uniffi::uniffi_bindgen_main() }`) enabled via the `uniffi` **`cli`**
  feature, so the generator version is pinned to the exact `uniffi` dependency
  (reproducible). Shipping static libs are built with default features (no `cli` /
  no `clap`), so the tool deps do not bloat the app binary.
- **Rationale**: The manual `uniffi-bindgen` + `xcodebuild -create-xcframework` flow is
  the most controllable and is what a Tuist (non-SwiftPM) project wants — it yields a
  plain binary artifact + a generated Swift file we can wire explicitly.
- **Alternatives considered**:
  - *`cargo-swift`* — rejected as the primary path: it is excellent but opinionated
    toward emitting a **SwiftPM package**; our app is **Tuist**-generated and wants an
    explicit xcframework + a generated-source file. Keep as a fallback/experiment.
  - *Commit a prebuilt xcframework* — rejected: large binary churn in a public repo and
    non-reproducible provenance; see D7.

---

## D5 — Wiring the framework into the Tuist iOS project

- **Decision**: Two-layer wiring so app code can `import KanameCore`:
  - `KanameCoreFFI.xcframework` — the compiled Rust static lib + C header + modulemap
    (the low-level FFI module the generated Swift talks to). Referenced by Tuist via
    `.xcframework(path:)`.
  - A **Tuist framework target `KanameCore`** whose sole source is the generated
    `KanameCore.swift` and which links `KanameCoreFFI.xcframework`. The app target and
    `KanameTests` depend on `KanameCore`, so `import KanameCore` works in `RootView`
    and in the round-trip test.
- **Rationale**: UniFFI's generated high-level Swift must be *compiled into* a Swift
  module; the xcframework carries only the C/FFI layer. A thin `KanameCore` framework
  target is the idiomatic Tuist way to expose a single importable module and keeps the
  generated source out of the app target's own sources.
- **Ordering constraint (critical)**: `tuist generate` resolves the xcframework path at
  generation time, so **`make core-xcframework` MUST run before `tuist generate`** in
  every flow (local `make ios-*` and CI). Encode this as a Make dependency
  (`ios-gen: core-xcframework`).
- **Alternatives considered**:
  - *Compile the generated Swift straight into the app target* (no `KanameCore` module)
    — simpler, but then there is no `import KanameCore` and the test would
    `@testable import Kaname`; rejected for weaker module boundaries.
  - *Bundle the high-level Swift inside the xcframework* — rejected: requires building a
    Swift framework per slice; more complex than a Tuist source target.

---

## D6 — CI: obtaining the xcframework, keeping the gate green

- **Decision**: Build the xcframework **inside the existing `ios` job** on `macos-15`,
  before `tuist generate`:
  1. Install Rust + `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`.
  2. `make core-xcframework` (cache cargo + the per-target build dirs).
  3. existing steps: SwiftLint, swift-format, `tuist generate`, simulator build + test.
  - The Linux `core` job is unchanged (it cannot build Apple targets; it keeps running
    `cargo fmt`/`clippy`/`test`, which now also compile the UniFFI scaffolding).
- **Rationale**: Apple-target builds need macOS + Xcode, which only the `ios` job has.
  Building in-job is the simplest correct option and needs no cross-job artifact plumbing.
- **Alternatives considered**:
  - *Separate `xcframework` job that uploads an artifact the `ios` job downloads* —
    viable and slightly more parallel, but adds artifact plumbing; note it as a future
    optimization if `ios` job time grows.
- **`macos-15` stays pinned** — do not relitigate: Homebrew `tuist` is built for macOS 15
  and aborts on `macos-14` (`libswiftSynchronization.dylib`, exit 134) per handoff §5.

---

## D7 — What is committed vs generated (git-ignore policy)

- **Decision**: Treat the xcframework and generated Swift as **build artifacts**
  (git-ignored), produced reproducibly by `make core-xcframework` — mirroring how the
  Tuist `*.xcworkspace` is already generated and git-ignored.
  - Git-ignore: `KanameCoreFFI.xcframework/`, the generated `KanameCore.swift`, and the
    Rust per-target build output. Recommended locations: `ios/Generated/KanameCore.swift`
    and `ios/Frameworks/KanameCoreFFI.xcframework` (both ignored).
  - Commit: `core/scripts/build-xcframework.sh`, the `uniffi.toml`, the `Makefile`
    target, the `Project.swift` wiring, and the CI step.
- **Rationale**: Keeps a public repo free of large, opaque, non-reproducible binaries and
  of machine-generated Swift that would churn on every version bump. Provenance is the
  script + pinned `uniffi`, not a checked-in blob (satisfies SC-008 review-ability).
- **Alternatives considered**:
  - *Commit generated Swift for IDE ergonomics* — rejected: churns on every build; the
    script regenerates it deterministically.

---

## D8 — Privacy-egress verification for this path

- **Decision**: Meet the constitution's privacy-egress gate at two cheap, meaningful
  levels for this slice (full runtime packet monitoring is deferred to the P2 parser
  fixtures where real I/O risk appears):
  - **Core (Rust)**: the version + round-trip functions are pure (no `std::net`, no
    sockets, no async runtime, no HTTP crate). Add/keep a guard that the core's
    dependency tree introduces **no networking crate**, and a unit test documenting the
    path is pure/deterministic.
  - **iOS**: the app adds **no** network entitlement, **no** `NSAppTransportSecurity`
    exception, and **no** networking API on the launch/version/round-trip path. No
    analytics/crash-reporter/ad SDK is added (FR-007).
- **Rationale**: This slice's path is trivially network-free by construction; asserting
  it at the dependency + entitlement level is proportionate and durable, and reserves a
  heavier egress monitor for when parsing/storage lands (P2).
- **Alternatives considered**:
  - *Full XCUITest network monitor now* — rejected as disproportionate for a pure path;
    revisit in P2 per the constitution's privacy-egress fixture plan.

---

## D9 — Native display of the engine version (HIG / a11y)

- **Decision**: Keep the branded `ContentUnavailableView` (SF Symbol `key.fill`, "Kaname")
  and surface the engine version as a labeled, secondary caption (e.g. a `footnote`/
  `caption` styled `Text("Engine v\(engineVersion())")` under the description, or in a
  toolbar). Use system fonts + Dynamic Type, semantic colors (Dark Mode-correct), and an
  explicit `accessibilityLabel` (e.g. "Engine version 0.1.0") so VoiceOver announces it.
- **Rationale**: Satisfies FR-001/FR-012, SC-001/SC-006, and Principle IV without adding
  UI dependencies; retains Kaname branding per the spec's display-placement assumption.
- **Failure handling**: the FFI `engine_version()` returns a non-optional `String`; the
  binding cannot fail for a present, embedded framework. Defensively, if the value were
  empty, the UI must not fabricate one — show the brand without a version rather than a
  fake (FR-013, edge case "empty version string").
- **Alternatives considered**:
  - *Replace the placeholder entirely* — rejected: spec says augment, retain branding.

---

## D10 — Test-first sequencing & the local gate

- **Decision**: Author tests before behavior (Principle V, FR-014):
  - **Rust**: a failing `cargo test` for `normalize_transaction` (known vectors incl.
    Unicode/zero/large-dp) precedes its implementation.
  - **Swift**: a failing **Swift Testing** `@Test` "core ↔ Swift round-trip" that builds
    a `Transaction`, calls `normalizeTransaction`, and asserts the returned record equals
    exactly the engine-computed value (description transformed; amount/date/direction
    exact) — plus a test asserting the displayed version equals `engineVersion()`.
  - **Gate order**: `make core-xcframework` → `cargo fmt/clippy/test` → `swiftlint`/
    `swift-format` → `tuist generate` → simulator build + Swift Testing.
- **Rationale**: Enforces the constitution's test-first mandate and the iOS Local
  Verification Gate; the round-trip test is the durable regression guard for the bridge.

---

## Local environment gotchas (carried from handoff §5)

- **Toolchain not installed locally** — run `make bootstrap` (rustup, tuist, swiftlint,
  swift-format) before the gate; local macOS is 26.x (newer than CI's `macos-15`).
- **Xcode 26 simulator** — the `iPhone 16` destination must exist locally; create it
  explicitly (`xcrun simctl create "iPhone 16" …`) or the `xcodebuild` destination fails.
  CI's `macos-15` already provides it.
- **SwiftLint `trailing_comma`** stays disabled (conflicts with swift-format) — do not
  re-enable.
- **Tuist** generates `Kaname.xcworkspace` (git-ignored); run `make ios-gen` before Xcode.

---

## Resolved unknowns summary

| # | Unknown | Resolution |
|---|---------|-----------|
| D1 | Binding tech / version | UniFFI 0.32, proc-macro, no UDL |
| D2 | Decimal/date across FFI | Remote custom types, `String` bridge, Swift `Decimal` |
| D3 | Round-trip shape | Reuse `Direction`+`Transaction`; `normalize_transaction` |
| D4 | XCFramework build | `uniffi-bindgen` + `lipo` + `xcodebuild -create-xcframework` |
| D5 | Tuist wiring | `KanameCoreFFI.xcframework` + `KanameCore` framework target |
| D6 | CI acquisition | Build in `ios` job on `macos-15` before `tuist generate` |
| D7 | Commit vs generate | Artifacts git-ignored; script + `uniffi.toml` committed |
| D8 | Privacy-egress | Dependency + entitlement level assertion (full monitor → P2) |
| D9 | Native version display | Augment branded root view; Dynamic Type + VoiceOver |
| D10 | Test-first order | Failing Rust + Swift tests precede behavior |

**All NEEDS CLARIFICATION items are resolved. Ready for Phase 1.**
