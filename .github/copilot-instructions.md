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

## UI baseline — iOS 26 + Liquid Glass

The app's deployment target is **iOS 26.0** (all Tuist targets + `build-xcframework.sh`),
chosen so **Liquid Glass is unconditional**. Never write `#available(iOS 26, *)` gates,
fallback branches, or hand-rolled `.ultraThinMaterial` / blur imitations. Apply the
`swiftui-liquid-glass` skill (`.github/skills/swiftui-liquid-glass/`) for any SwiftUI work,
alongside `make-interfaces-feel-better` for polish.

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
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.** (010-au-bank-ledger-reader)
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.** (011-iob-cc-reader)
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.** (012-cc-reconciliation)
- N/A (no persistence this slice; persisting the verdict / encrypted SQLite is explicitly out of scope) (012-cc-reconciliation)
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency** (Jaro-Winkler is hand-rolled) (013-cross-source-dedup)
- N/A (no persistence this slice; encrypted SQLite/SQLCipher and any stored de-dup state are explicitly out of scope) (013-cross-source-dedup)
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency** (`std::collections::HashMap` + `chrono::Datelike` only) (014-coverage)
- N/A (no persistence this slice; the platform supplies the pre-aggregated facts; encrypted SQLite/SQLCipher and any on-device aggregation are explicitly out of scope) (014-coverage)
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency** (token-Jaccard + the score are hand-rolled with `std` + `rust_decimal`'s `ToPrimitive::to_f64`) (015-transfer-detection)
- N/A (no persistence this slice; `transfer_group_id`/`is_transfer` persistence and all DB concerns are explicitly out of scope, platform-side; encrypted SQLite/SQLCipher arrives in a later phase) (015-transfer-detection)
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, **iOS 26 target** (Liquid Glass unconditional — no `#available` gates, no `.ultraThinMaterial` fallbacks) + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `thiserror`, `uniffi 0.32`, `rusqlite`/SQLCipher; dev-only `serde_json 1` (already present, fixture harness); iOS links first-party **PDFKit**. **No new runtime OR dev dependency.** (016-statement-import-vertical)
- Encrypted on-device SQLCipher store, forward-only `PRAGMA user_version` migrations — **schema v5 → v6** (`ALTER TABLE accounts ADD COLUMN last4 TEXT`), plus a new atomic `Store::import_statement` (one transaction: account → statement → transactions → categorize → dedup) (016-statement-import-vertical)
- Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, **iOS 26 target** + existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `thiserror`, `uniffi 0.32`, `rusqlite`/SQLCipher; dev-only `serde_json 1`; iOS links first-party **PDFKit** + **UIKit/CoreGraphics** (`UIGraphicsPDFRenderer`, test-only). **No new runtime OR dev dependency.** (017-column-major-pdf)
- Unchanged — encrypted on-device SQLCipher store at **schema v6**; this slice adds no migration and no persisted field (persisting `issuer_id` is deliberately deferred, see `specs/017-column-major-pdf/research.md` R9) (017-column-major-pdf)
- **PDF text extraction is geometry-first**: the platform's text-layer newlines carry no authority — words are grouped into printed row bands by vertical overlap, so extraction can both split merged rows and join split columns. Claim markers are matched whitespace-insensitively against an *identity region* (the document minus its transaction rows), never the raw full text. The registry names credit cards per **card product** (`<INSTITUTION>_<PRODUCT>_CARD`) and bank accounts per **bank** (`<INSTITUTION>_BANK`); `bank_code` is always the bare institution. (017-column-major-pdf)

## Recent Changes
- 017-column-major-pdf: Geometry-first PDF row reconstruction (platform) + whitespace-insensitive, identity-region claim matching and card-product registry granularity (engine). No new deps, no FFI change, no schema change.
- 001-rust-swift-bridge: Added Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 deployment target + UniFFI `0.32` (new); existing `rust_decimal`, `chrono`, `serde`, `regex`, `csv`; iOS: SwiftUI, Foundation, Tuist (project gen), Swift Testing
