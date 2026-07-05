# Implementation Plan: Prove the App Is Powered by the Shared On-Device Engine

**Branch**: `001-rust-swift-bridge` | **Date**: 2026-07-05 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/001-rust-swift-bridge/spec.md`
**Milestone**: P1 (roadmap) — wire the Rust ↔ Swift bridge

## Summary

Establish the end-to-end on-device bridge so the SwiftUI app calls real, deterministic
functions from the shared `kaname-core` (Rust) engine and displays a value the engine
produced. Two functions are exposed first: `engine_version()` (the visible proof-of-life)
and `normalize_transaction()` (a typed, structured round-trip over the real domain —
`Direction` enum + `Transaction` record, with money as exact `Decimal`, never float).

**Technical approach** (locked in `research.md`): add **UniFFI 0.32** to `kaname-core`
via the modern **proc-macro / no-UDL** path (`uniffi::setup_scaffolding!()` +
`#[uniffi::export]` + `#[derive(uniffi::Record/Enum)]`); bridge `rust_decimal::Decimal`
and `chrono::NaiveDate` as **remote custom types** over a `String` wire (Swift sees a
native `Decimal`); build **`KanameCoreFFI.xcframework`** for device + universal-simulator
via `uniffi-bindgen` + `lipo` + `xcodebuild -create-xcframework` (new `make
core-xcframework`); expose it through a Tuist **`KanameCore`** framework target so app +
tests `import KanameCore`; surface the version in a HIG-compliant, accessible root screen;
and keep the iOS Local Verification Gate + CI green by building the xcframework **before**
`tuist generate`.

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 deployment target
**Primary Dependencies**: UniFFI `0.32` (new); existing `rust_decimal`, `chrono`, `serde`, `regex`, `csv`; iOS: SwiftUI, Foundation, Tuist (project gen), Swift Testing
**Storage**: N/A (no persistence in this slice; encrypted SQLite/SQLCipher arrives P2+)
**Testing**: `cargo test` (core); **Swift Testing** (`import Testing`) for the app + the "core ↔ Swift round-trip"
**Target Platform**: iOS 18+ (device `aarch64-apple-ios`; simulator `aarch64-apple-ios-sim` + `x86_64-apple-ios`)
**Project Type**: Mobile — Rust core + native SwiftUI app (monorepo `core/` + `ios/`)
**Performance Goals**: version visible within ~1 s of first render (SC-001); round-trip is a sub-millisecond pure call
**Constraints**: 100% on-device, ZERO network on this path (FR-006, SC-005); deterministic (FR-008); money is `Decimal`, never `f64` (FR-010); Apache-2.0 client, no GPL/AGPL/LGPL deps (FR-011)
**Scale/Scope**: 2 exported functions, 1 enum + 1 record + 2 custom types, 1 augmented screen, 1 new framework target, 1 Makefile target, 1 CI step

## Constitution Check

*GATE: evaluated before Phase 0 and re-checked after Phase 1. Constitution v1.0.0.*

| Principle / Gate | Verdict | Evidence & how this plan complies |
|---|---|---|
| **I. Data Privacy & Sovereignty** (NON-NEGOTIABLE) — free/core = 100% on-device, zero network, no telemetry | ✅ PASS | Version + round-trip are pure functions in `kaname-core`; no `std::net`, sockets, HTTP crate, async runtime. App adds no network entitlement / no `NSAppTransportSecurity` / no analytics / no crash reporter (FR-006/FR-007). Privacy-egress addressed at dependency + entitlement level (research D8); full runtime monitor deferred to P2 where real I/O appears. |
| **II. Local-First Shared Engine** — pure, deterministic, platform-agnostic Rust core via UniFFI; money never float; no PDF engine in core | ✅ PASS | Logic lives in `kaname-core`, exposed via UniFFI (D1); functions are pure/deterministic (D3, FR-008); `Decimal` crosses as exact base-10 `String` → Swift `Decimal` (D2, FR-010); no PDF engine, no platform I/O added (PDF extraction remains native, out of scope — FR-009). |
| **III. Open-Core & Permissive Licensing** — client Apache-2.0; GPL/AGPL/LGPL forbidden; no secrets | ⚠️ PASS *(1 justified dependency)* | Client stays Apache-2.0; no secrets/keys/endpoints added (FR-011). New dep **`uniffi` is MPL-2.0** — a file-level (weak) copyleft that is **not** in the forbidden {GPL, AGPL, LGPL} set and is App Store-compatible (ships in Firefox iOS). `rust_decimal`/`chrono`/`serde` are permissive (MIT/Apache-2.0). Recorded in **Complexity Tracking**; tasks will run a license audit of transitive deps (SC-008). |
| **IV. Native Experience & Accessibility** — latest HIG, SwiftUI, SF Symbols, Dynamic Type, Dark Mode, VoiceOver | ✅ PASS | Version augments the branded root view (SF Symbol `key.fill`), system fonts + Dynamic Type, semantic colors (Dark Mode), explicit `accessibilityLabel` for VoiceOver (D9, FR-012, SC-006); `make-interfaces-feel-better` polish applied. |
| **V. Test-First & Parity** — failing test precedes behavior; `cargo test` + Swift Testing; privacy-egress test | ✅ PASS | Rust test for `normalize_transaction` and the Swift "core ↔ Swift round-trip" are written **first** (D10, FR-014/FR-015). Golden-fixture parity is N/A this slice (P2), but determinism is tested (SC-004). |
| **iOS Local Verification Gate** — cargo fmt/clippy/test; swiftlint + swift-format; tuist generate; simulator build+test | ✅ PASS | Preserved and extended: `make core-xcframework` runs **before** `tuist generate` locally and in CI (D5/D6). `macos-15` stays pinned. |
| **Security & Privacy Constraints** — no network SDKs in core paths; deps reviewed & justified; no committed secrets | ✅ PASS | Only additions are UniFFI (build/bindings) + generated code; no network SDK; artifacts git-ignored; no secrets (D7). |

**Initial gate result: PASS** (one justified new dependency; zero unjustified violations).
No NEEDS CLARIFICATION remain (see `research.md`). Cleared to proceed to Phase 0/1.

## Project Structure

### Documentation (this feature)

```text
specs/001-rust-swift-bridge/
├── plan.md              # This file (/speckit.plan)
├── research.md          # Phase 0 — decisions D1–D10 (all unknowns resolved)
├── data-model.md        # Phase 1 — entities & FFI type/boundary map
├── contracts/
│   └── engine-ffi.md    # Phase 1 — the UniFFI Swift boundary contract
├── quickstart.md        # Phase 1 — build + verify walkthrough
├── checklists/          # (pre-existing) spec quality checklist(s)
└── tasks.md             # Phase 2 — created by /speckit.tasks (NOT here)
```

### Source Code (repository root)

```text
core/                                    # Rust cargo workspace
├── Cargo.toml                           # workspace (unchanged)
└── crates/kaname-core/
    ├── Cargo.toml                       # + uniffi 0.32 dep; + [[bin]] uniffi-bindgen (cli feature)
    ├── uniffi.toml                      # NEW — Swift custom-type map (Decimal → Foundation.Decimal)
    └── src/
        ├── lib.rs                       # + uniffi::setup_scaffolding!(); engine_version() -> String; `mod ffi;`
        ├── model.rs                     # + #[derive(uniffi::Enum)] Direction; #[derive(uniffi::Record)] Transaction
        ├── dedup.rs                     # (unchanged) normalize_description reused
        ├── ffi.rs                       # NEW — custom_type!(Decimal/NaiveDate) decls + #[uniffi::export] normalize_transaction
        └── bin/uniffi-bindgen.rs        # NEW — pinned bindgen entrypoint

core/scripts/
└── build-xcframework.sh                 # NEW — compile targets → bindgen → lipo → create-xcframework

ios/                                     # SwiftUI app (Tuist-generated project)
├── Project.swift                        # + KanameCoreFFI.xcframework binary + KanameCore framework target
├── Sources/
│   ├── KanameApp.swift                  # (unchanged)
│   └── RootView.swift                   # + accessible engine-version display
├── Tests/
│   └── KanameTests.swift                # + "core ↔ Swift round-trip" + version-display tests
├── Generated/KanameCore.swift           # NEW (git-ignored) — UniFFI-generated Swift bindings
└── Frameworks/KanameCoreFFI.xcframework # NEW (git-ignored) — built by make core-xcframework

Makefile                                 # + core-xcframework; ios-gen depends on it
.github/workflows/ci.yml                 # + build xcframework in the macos-15 ios job before tuist generate
.gitignore                               # + ios/Generated/, ios/Frameworks/*.xcframework
```

**Structure Decision**: Keep the existing **monorepo mobile** layout (`core/` Rust +
`ios/` SwiftUI) from `docs/kaname-ios-plan.md` §5 — no new top-level projects. All engine
logic stays in `kaname-core`; the app consumes it only through the generated `KanameCore`
Swift module backed by `KanameCoreFFI.xcframework`. Generated Swift + the xcframework are
build artifacts (git-ignored), regenerated by `make core-xcframework`, consistent with the
already-ignored Tuist `*.xcworkspace`.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| New runtime dependency **`uniffi` 0.32 (MPL-2.0)** linked into the app binary | The constitution (Principle II) and locked decisions (`HANDOFF.md` §2) mandate UniFFI as the Rust↔Swift binding mechanism and the cross-platform reuse path (Kotlin/JS later). UniFFI generates type-safe Swift and manages FFI memory. | *Hand-written C FFI + manual Swift shim* — rejected: no type safety, manual/unsafe memory management, no multi-platform reuse, higher regression risk. *`swift-bridge`* — rejected: not the constitution-locked choice and no Kotlin story. |
| **MPL-2.0** license introduced (not Apache-2.0) | MPL-2.0 is UniFFI's upstream license; the runtime `uniffi_core` links into the shipped binary. | MPL-2.0 is **file-level weak copyleft**, explicitly **not** in the constitution's forbidden set {GPL, AGPL, LGPL}, and is App Store-distributable (obligations are satisfied by unmodified upstream source availability; Firefox iOS ships it). No permissive-only equivalent provides UniFFI's capability. Tasks will confirm no *transitive* GPL/AGPL/LGPL creeps in (SC-008). |
| New build tooling (`uniffi-bindgen` bin, `build-xcframework.sh`, extra CI step) | Producing a device+simulator xcframework + Swift bindings reproducibly requires a build step, and it must run before `tuist generate`. | *Commit prebuilt binaries* — rejected (opaque, non-reproducible, bloats a public repo). *`cargo-swift`* — noted as fallback but emits a SwiftPM package, which fights our Tuist setup. |

## Phase status

- **Phase 0 — Research**: ✅ complete → [`research.md`](./research.md) (D1–D10; all NEEDS CLARIFICATION resolved).
- **Phase 1 — Design & Contracts**: ✅ complete → [`data-model.md`](./data-model.md),
  [`contracts/engine-ffi.md`](./contracts/engine-ffi.md), [`quickstart.md`](./quickstart.md);
  agent context updated via `.specify/scripts/bash/update-agent-context.sh copilot`.
- **Phase 1 re-check (post-design Constitution Check)**: ✅ PASS — the design introduces no
  new violations beyond the single justified `uniffi` dependency already tracked above; the
  chosen `String`/`Decimal` bridge actively *reinforces* the no-float-money and determinism
  principles.
- **Phase 2 — Tasks**: ⏭️ NOT done here. Run `/speckit.tasks` to generate `tasks.md`
  (ordered: UniFFI wiring → xcframework build → Tuist wiring → test-first Rust/Swift →
  UI → CI), each task test-first per Principle V.
