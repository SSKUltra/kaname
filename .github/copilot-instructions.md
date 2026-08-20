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
- Rust (stable, per `rust-toolchain.toml`) + Swift 6 / SwiftUI, **iOS 26 target** + existing `rusqlite`/SQLCipher, `rust_decimal 1`, `chrono 0.4`, `uniffi 0.32`. **No new runtime OR dev dependency, in either language.** (018-transaction-list)
- Encrypted on-device SQLCipher store, **schema v6 → v7** — a single partial descending index `idx_txn_live_account_date ON transactions(account_id, date DESC) WHERE is_deleted = 0 AND superseded_by IS NULL`. No table, column, constraint or row changes; the least invasive migration in the store's history. (018-transaction-list)
- **The transaction list reads through two engine surfaces only**: `history_page(HistoryQuery) -> HistoryPage` (keyset-paged, k-way merge of one index-satisfied query per account; the account filter is the same query with k = 1) and `account_summaries()` (the live count, moved out of Swift). The live-row rule is one Rust constant `LIVE = "is_deleted = 0 AND superseded_by IS NULL"`, **byte-identical to the v7 index's WHERE clause**, so a read that forgets it loses its index and the plan-shape test goes red. The total order is `date DESC, account position in list_accounts(), transactions.rowid`. `Store::list_transactions` keeps its raw semantics — do not "fix" it. New platform code lives in `ios/Sources/Transactions/` because `ios/Sources/Import/ImportService.swift` is at exactly the 400-line SwiftLint limit. (018-transaction-list)
- Swift 6 / SwiftUI, **iOS 26 target**, Xcode 26.6 / iOS SDK 26.5; Rust **untouched** this slice + existing only — XCTest/XCUITest, Swift Testing, Tuist, SwiftLint, swift-format. **No new runtime OR dev dependency, in either language.** (019-debug-test-seeding)
- Encrypted on-device SQLCipher store at **schema v7 — unchanged, no migration**, and deliberately so: the seed writes through `Store::import_statement`, so it touches only columns v1–v7 already define. A migration here would have been the tell that seeding had stopped going through the front door. (019-debug-test-seeding)
- **DEBUG-only seeding is Swift-only, and cannot be otherwise**: `core/scripts/build-xcframework.sh` runs `cargo build --release` **once** and links that one artifact into both Xcode configurations, so `#[cfg(debug_assertions)]` is off in the DEBUG app and a cargo feature would compile into Release (research R2). All of it lives in `ios/Sources/DebugSeed/` inside `#if DEBUG`, requested via `XCUIApplication.launchEnvironment["KANAME_SEED_SCENARIO"]` (**not** the `TEST_RUNNER_` rule — that is for app-hosted unit tests), and written through the shipped `Store.importStatement`. The absence from Release is **proved twice**: a tenth scan in `scripts/import-path-audit.sh`, and `make release-audit`, which builds its own Release binary and **self-checks for a known-present symbol and literal first** — because `strip` takes the binary from 12,249 symbols to 157 and makes a naive scan vacuously green. (019-debug-test-seeding)
- Rust 1.90 (`rust-toolchain.toml`) + Swift 6 / SwiftUI, **iOS 26 target** — **both** layers touched this slice, unlike 019 + existing only. **No new runtime OR dev dependency, in either language**; the stale-set token is a list of ids rather than a digest specifically so no hashing crate is needed. (020-categorize)
- Encrypted on-device SQLCipher store, **schema v7 → v8** — one `CREATE TABLE merchant_memory(merchant_portion TEXT PRIMARY KEY, category_id TEXT NOT NULL REFERENCES categories(id)) STRICT` and one partial index `idx_txn_unanswered_account_date`. **No `ALTER TABLE`, no column added to `transactions`, no `CHECK` added, no existing row read or written** — so FR-047/SC-014 ("every existing transaction keeps its category, amount, date, description, account and provenance") are true by construction rather than by testing hard enough. (020-categorize)
- **A person's decision is a different kind of fact from an engine verdict, and the engine must be kept out of it.** Provenance is two reserved `categorised_by` values the engine can never produce — `PERSON` (by hand) and `PERSON_MEMORY` (carrying a memory) — guarded by one macro, `engine_may_decide!() = "(categorised_by IS NULL OR categorised_by NOT IN ('PERSON', 'PERSON_MEMORY'))"`, applied to `load_account_transactions` **and** `detect_transfers`' UPDATE. 🚨 The `IS NULL OR` is load-bearing: `NULL NOT IN (…)` is `NULL`, not `TRUE`, so the shorter spelling silently drops every row `import_statement` just inserted (its bulk insert writes `NULL, NULL` literally) and every import lands wholly uncategorized with no error. The memory is a **new** table, not the T2 `merchant_map` (whose matching is `contains`, which is outranked by the CC rules, and which is already exported by `list_merchant_rules()`); it is consulted by the store **beside** the stack, so `categorize.rs` and `dedup::normalize_narration` are **not modified** and the categorization and dedup fixtures cannot move. ⚠️ The uncategorized count's optimal plan **is** a `SCAN` of the partial index — a plan-shape test copied from `history_perf::s1`'s blanket "no SCAN" rule is red for the correct query. (020-categorize)

## Recent Changes
- 020-categorize: Correcting a category, and remembering the merchant. Engine gains schema v8 (`merchant_memory` + one partial index), a reserved `PERSON`/`PERSON_MEMORY` provenance, a `merchant.rs` derivation rule additive to `normalize_narration`, and an uncategorized narrowing + store-wide count in SQL. Fixes a shipped defect: `categorize_account_in` was overwriting every live row unconditionally, writing `NULL, NULL` when the stack had no answer. Six spec amendments recorded; `018/06` (device timings) and 018 R17/R18 remain open and untouched.
- 019-debug-test-seeding: DEBUG-only test seeding — a launch environment variable writes a named synthetic history through the shipped import path so UI tests finally see a populated transaction list. No Rust, no FFI, no migration. Three findings flagged, not worked around: `EmptyKind.nothingImported` is unreachable by any automated run of the shipping route (R9), and `is_deleted` / `is_transfer` have no writable path from the app (R8).
- 018-transaction-list: The transaction list — cross-account, date-grouped, keyset-paged, filterable. Engine gains schema v7 (one index) + `history_page` + `account_summaries`; the front-door count moves into SQL. Two shipped-code findings flagged, not fixed: cross-account dedup is non-deterministic (research R17), and `detectTransfers()` is called from no Swift file (R18).
- 017-column-major-pdf: Geometry-first PDF row reconstruction (platform) + whitespace-insensitive, identity-region claim matching and card-product registry granularity (engine). No new deps, no FFI change, no schema change.
- 001-rust-swift-bridge: Added Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 deployment target + UniFFI `0.32` (new); existing `rust_decimal`, `chrono`, `serde`, `regex`, `csv`; iOS: SwiftUI, Foundation, Tuist (project gen), Swift Testing
