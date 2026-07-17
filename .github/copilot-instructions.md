# Kaname — Copilot instructions

Kaname (要, "the key") is the **privacy-first, local-first** iOS client for personal
finance, shipped by **BeaconBrain**. This repo is the **open-source client** (Apache-2.0).
Premium/cloud features are server-gated and live in a separate closed backend.

## Golden rules
1. **Privacy is non-negotiable.** Free/core features run **100% on-device** with **no
   network I/O**. Never add analytics, crash reporting, or "phone-home" to free paths.
   Premium cloud features (sync/AI/AA) are opt-in and validated server-side — do not
   stub or client-gate them here.
2. **No secrets in the client.** No API keys, tokens, or private endpoints. The client
   is public; assume every line is readable by a competitor.
3. **Money is never a float.** Use `Decimal` (Swift) / `rust_decimal::Decimal` (Rust).
4. **Determinism + parity.** The engine must reproduce the web engine's behaviour
   against ported golden fixtures (see `fixtures/`).

## Architecture
- `core/` — Rust workspace (`kaname-core`): parsing, categorization, dedup, reconcile.
  Platform-agnostic, exposed to Swift via **UniFFI** (wired in P1). Pure & testable.
- `ios/` — SwiftUI app (Tuist-managed). Native UI + platform concerns.
  **PDF text extraction is native** (PDFKit → lines + word x-positions) and feeds the
  Rust parser seam `read_lines(lines, full_text, first_row_words)`. Do **not** embed a
  PDF engine in Rust.
- `fixtures/` — golden test vectors ported from the web engine.

## Conventions
- **Swift**: SwiftUI + latest HIG (SF Symbols, Dynamic Type, Dark Mode, VoiceOver).
  Lint with `swiftlint --strict`; format with `swift-format`. 4-space indent, ≤120 cols.
- **Rust**: `cargo fmt` + `cargo clippy -D warnings`. Small, pure functions; unit-tested.
- **Tests**: Swift Testing (`import Testing`, `@Test`) + snapshot/XCUITest for UI;
  `cargo test` for the core. TDD for the engine.

## Local Verification Gate (run before every PR)
- Core: `make core-lint && make core-test` (fmt check, clippy, tests).
- iOS: `make lint && make ios-test` (SwiftLint, swift-format lint, `tuist generate`,
  simulator build + tests).

## Workflow
This repo uses **GitHub Spec Kit** (`.specify/` + `.github/prompts/speckit.*`). For new
features: `speckit.specify` → `speckit.plan` → `speckit.tasks` → `speckit.implement`.
The constitution is `.specify/memory/constitution.md` — it wins over any other guidance.

UI polish work should apply the `make-interfaces-feel-better` skill.

## Active Technologies
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 deployment target + UniFFI `0.32` (new); existing `rust_decimal`, `chrono`, `serde`, `regex`, `csv`; iOS: SwiftUI, Foundation, Tuist (project gen), Swift Testing (001-rust-swift-bridge)
- N/A (no persistence in this slice; encrypted SQLite/SQLCipher arrives P2+) (001-rust-swift-bridge)
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target + existing `regex 1.12`, `rust_decimal 1.42`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; **new dev-only** `serde_json` (fixture harness). No new runtime deps. (002-icici-cc-parser)
- N/A (no persistence this slice; encrypted SQLite/SQLCipher is out of scope) (002-icici-cc-parser)
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.** (003-hdfc-cc-parser)
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.** (004-sbi-cc-parser)
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.** (005-yes-cc-parser)
- Rust (stable, per `rust-toolchain.toml`; verified on rustc 1.96.1) + Swift 5.x / SwiftUI, iOS 18 target + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.** (006-federal-cc-parser)
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.** (007-bank-account-ledger-reader)
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.** (008-hdfc-bank-ledger-reader)
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.** (009-federal-bank-ledger-reader)

## Recent Changes
- 001-rust-swift-bridge: Added Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 deployment target + UniFFI `0.32` (new); existing `rust_decimal`, `chrono`, `serde`, `regex`, `csv`; iOS: SwiftUI, Foundation, Tuist (project gen), Swift Testing
