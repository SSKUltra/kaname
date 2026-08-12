# Implementation Plan: Statement Import — the First End-to-End Vertical

**Branch**: `016-statement-import-vertical` | **Date**: 2026-08-12 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/016-statement-import-vertical/spec.md`

## Summary

A person picks a statement PDF from Files; the app extracts its text natively with PDFKit,
the Rust engine identifies the issuer and parses it, the transactions are written to the
SQLCipher-encrypted on-device store, and the person sees an import summary. This is the first
slice that joins every shipped layer into one user-visible flow.

Everything the engine needs already exists: ten statement readers, the balance-chain and
reconciliation checks, cross-source de-duplication, the deterministic categorization stack,
and the encrypted store. **Four things are added**, and nothing is rebuilt:

1. **An issuer dispatcher inside the engine** — `detect_issuer(full_text) -> Option<Issuer>`
   and `read_statement(issuer, lines, full_text, line_words) -> Result<ParsedStatement, _>`,
   backed by a static 10-entry registry. `Issuer` is a **record** (not an enum) carrying an
   opaque `id`, an engine-supplied `display_name`, the `bank_code`, and a `StatementKind`.
   The app asks one question and issues one instruction; an eleventh bank costs zero app lines.
2. **A deterministic tie-break** — candidates are ordered by `(kind_rank, id)`, ledger before
   card. This is not hypothetical: **3 of the 13 shipped golden fixtures are claimed by two
   readers today**, and ledger-first resolves all three correctly.
3. **Schema v6 — one `ALTER TABLE accounts ADD COLUMN last4 TEXT`.** The v5 `statements`
   table already satisfies FR-026 field-for-field; what is missing is account identity, since
   FR-021/FR-024 key on issuer + last-4 and `accounts` has no such column.
4. **`Store::import_statement` — an atomic import.** The three existing `insert_*` methods each
   auto-commit, so a mid-import failure would strand an account, a statement record and N
   transactions. FR-031/SC-006 demand all-or-nothing, and only Rust owns the connection.

Platform-side: a `StatementTextExtractor` PDFKit seam producing `lines` / `fullText` /
`lineWords`, an `ImportService` actor running the whole pipeline off the main thread with
cancellation, and the empty-state → progress → summary UI on the iOS 26 Liquid Glass baseline.

**No new runtime or dev dependency** is proposed.

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`,
`thiserror`, `uniffi 0.32` (proc-macro, no UDL), `rusqlite` + bundled SQLCipher
(CommonCrypto on Apple, LibTomCrypt on Linux — **never** OpenSSL); dev-only `serde_json 1`.
iOS: SwiftUI, Foundation, **PDFKit** (first-party Apple SDK framework, newly *linked* — not a
dependency addition), Tuist, Swift Testing. **No new runtime OR dev dependency.**
**Storage**: encrypted on-device SQLCipher store, forward-only `PRAGMA user_version`
migrations, **schema v5 → v6** (one `ADD COLUMN`); key in the iOS Keychain via the shipped
`KeyStore`/`StoreLocator`
**Testing**: `cargo test` (unit + parity golden harness + store behavioural) for the engine;
Swift Testing (`import Testing`, `@Test`) over the UniFFI bridge + snapshot/accessibility for
the app. TDD, RED → GREEN. All fixtures synthetic.
**Target Platform**: iOS **26.0** deployment target (all three Tuist targets and
`build-xcframework.sh`) — Liquid Glass is unconditional; **no `#available(iOS 26, *)` gates,
no `.ultraThinMaterial` fallbacks, no hand-rolled blur, anywhere**
**Project Type**: Mobile app (native iOS UI) over a shared, platform-agnostic Rust engine
**Performance Goals**: a 200-transaction statement imports without the UI becoming
unresponsive at any point, and cancels within 2 s of being asked (SC-008); open → summary in
under 60 s and at most 4 taps (SC-001)
**Constraints**: **zero** network I/O on the entire path (Constitution I, non-negotiable);
money is exact decimal at every hop and never a float; the core reads no wall clock (every
timestamp is a caller-supplied parameter); the core never opens a PDF; every failure path
leaves the store byte-identical (SC-006); no statement content, amount, account identifier or
password may reach a log (FR-042)
**Scale/Scope**: 10 issuers today (6 card, 4 ledger) growing without app changes; one file per
import; ~7 new engine surfaces, 1 migration, ~6 new Swift types, 5 new views

*(No `NEEDS CLARIFICATION` remains — see [`research.md`](./research.md) R1–R13.)*

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v2.0.0.

| Principle | Verdict | Evidence in this design |
|---|---|---|
| **I. Data Privacy & Sovereignty (NON-NEGOTIABLE)** | ✅ PASS | The whole path — pick, extract, detect, parse, check, persist, categorize, summarize — is on-device. Zero network I/O (FR-041); no analytics, crash reporting or telemetry added. No new crate, so `make core-privacy-audit` (denylists networking crates and `openssl-sys`) is unaffected. Data at rest stays in the SQLCipher store with the Keychain key. **No account, entitlement check or server call appears on this path** — the account requirement is milestone P4 and is explicitly excluded. Passwords are never persisted (FR-008); nothing sensitive is logged (FR-042). |
| **II. Local-First Shared Engine** | ✅ PASS | The dispatcher, tie-break, readers, integrity checks, dedup, categorization and storage all live in `kaname-core` and are reused verbatim. **The core still never opens a PDF** — PDFKit stays platform-side and feeds the reader seam. `detect_issuer` and `read_statement` are pure and deterministic: no clock, no locale, no network, no global mutable state. Every timestamp crosses as `ImportRequest.now` (FR-027). Money is `rust_decimal::Decimal` → base-10 `String` → `Foundation.Decimal`; polarity is carried by an explicit `Direction`, never by an amount's sign. |
| **III. Open-Core & Permissive Licensing** | ✅ PASS | No new dependency at all, so no licence surface changes and no copyleft risk. No secrets, no API keys, no endpoints, no entitlement logic. |
| **IV. Native Experience & Accessibility** | ✅ PASS | SwiftUI on the iOS 26 baseline with unconditional Liquid Glass applied per `.github/skills/swiftui-liquid-glass/SKILL.md`: glass on the floating CTA and the progress capsule, **never** on dense numeric rows; system chrome not re-skinned; at most one prominent element per screen. Amounts and counts use `.monospacedDigit()` (FR-045). Dynamic Type through the largest sizes, Dark Mode, Reduce Transparency / Increase Contrast, and full VoiceOver are release gates (FR-044/046, SC-009). |
| **V. Test-First & Parity** | ✅ PASS | TDD, RED → GREEN, for the dispatcher, the v6 migration and `import_statement`. A new parity test asserts every golden fixture resolves through `detect_issuer` to its expected issuer — the guard that catches today's three collisions. Ten equivalence tests prove `read_statement` is byte-identical to the legacy per-bank reader. The privacy-egress test still passes. All fixtures synthetic; unusable-document PDFs are generated at test time, not committed (FR-043, SC-011). |
| **VI. Free/Paid Boundary** | ✅ PASS | Statement import, parsing, categorization, dedup and reconciliation are explicitly **free** because they run fully on-device. Nothing on this path is gated, metered, or server-validated. No AI, no Account Aggregator, no sync — all excluded by the spec's Out of Scope. |
| **Security & Privacy Constraints** | ✅ PASS | No third-party SDK is added. PDFKit is a first-party Apple system framework that performs no network I/O, no fingerprinting and no data collection, and adds nothing to the crate graph. Fixtures are synthetic. No secrets committed. |
| **Development Workflow & Quality Gates** | ✅ PASS | Spec Kit flow; the full iOS Local Verification Gate applies. Because the FFI surface changes, `make core-xcframework` **must** precede `tuist generate` — `make ios-gen` already encodes this. |

**Result: PASS — no violations, no justifications required. Complexity Tracking is empty.**

### Post-Phase-1 re-evaluation

Re-checked after `research.md`, `data-model.md`, `contracts/` and `quickstart.md`:

- ✅ Still **zero** new dependencies. PDFKit is linked, not vendored.
- ✅ The engine stays pure — the dispatcher adds a static registry and a total ordering; no
  clock, no I/O, no interior mutability.
- ✅ Schema v6 is a single constant-default `ADD COLUMN`, the same shape as the shipped v2/v3/v4
  migrations, applied by the existing forward-only runner. The `statements.period_end NOT NULL`
  rebuild was **deliberately rejected** (research R6) because it would force the shared
  `migrate()` runner to disable foreign-key enforcement — a needless risk to the one piece of
  code that must never lose data.
- ✅ `Store::import_statement` **increases** constitutional compliance rather than costing it: it
  is the only way FR-031/SC-006 ("byte-identical after any failure") can be honoured, since
  Swift cannot open a transaction on a Rust-owned connection.
- ⚠️ One design constraint surfaced and is documented as mandatory: `std::sync::Mutex` is not
  reentrant, so `categorize_account` and `find_duplicates` must be split into `*_in(tx, …)`
  helpers before `import_statement` calls them, or the happy path deadlocks.

**Result: PASS. Complexity Tracking remains empty.**

## Project Structure

### Documentation (this feature)

```text
specs/016-statement-import-vertical/
├── plan.md                       # This file
├── spec.md                       # FINAL — Clarifications are settled constraints
├── research.md                   # Phase 0 — R1–R13, all decisions with source evidence
├── data-model.md                 # Phase 1 — entities, schema v6, state transitions
├── contracts/
│   ├── engine-ffi.md             # Phase 1 — the Rust/UniFFI surface added
│   └── platform-seams.md         # Phase 1 — the Swift protocols, actor and UI surfaces
├── quickstart.md                 # Phase 1 — build order, gates, gotchas, smoke test
└── tasks.md                      # Phase 2 — NOT created by /speckit.plan
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── src/
│   ├── statement/
│   │   ├── registry.rs           # NEW — 10-entry ReaderEntry registry + (kind_rank, id) order
│   │   ├── ledger_reader.rs      # + first_anchor_index() (additive; read_ledger_lines unchanged)
│   │   ├── line_reader.rs        # unchanged
│   │   ├── base.rs               # + LineWords record (Word unchanged)
│   │   ├── balance_chain.rs      # unchanged — reused
│   │   ├── reconcile.rs          # unchanged — reused
│   │   └── {icici,hdfc,sbi,yes,iob,federal,
│   │        icici_bank,hdfc_bank,federal_bank,au_bank}.rs   # ALL unchanged
│   ├── ffi.rs                    # + Issuer, StatementKind, ReaderError,
│   │                             #   detect_issuer, read_statement
│   │                             #   (the 10 legacy read_*/`*_claims` exports stay)
│   ├── store.rs                  # + SCHEMA_V6, ImportRequest/Outcome/AccountTarget,
│   │                             #   import_statement, categorize_account_in,
│   │                             #   find_duplicates_in, NewAccount.last4
│   ├── lib.rs                    # + re-exports
│   ├── categorize.rs dedup.rs coverage.rs transfer.rs model.rs   # unchanged — reused
└── tests/
    ├── parity.rs                 # + detect_issuer resolves every golden fixture
    ├── dispatcher.rs             # NEW — registry totality, tie-break, equivalence ×10
    └── store_import.rs           # NEW — v5→v6 migration, import atomicity, re-import

ios/
├── Project.swift                 # + .sdk(name: "PDFKit", type: .framework)
├── Sources/
│   ├── RootView.swift            # replaced by the real flow
│   ├── Import/                   # NEW
│   │   ├── StatementTextExtractor.swift   # protocol + PDFKit impl + ExtractionFailure
│   │   ├── ImportService.swift            # actor: pipeline, stages, cancellation
│   │   ├── ImportModels.swift             # ImportStage/Summary/Failure/IntegrityOutcome
│   │   ├── ImportEmptyStateView.swift     # glassProminent CTA
│   │   ├── ImportProgressView.swift       # GlassEffectContainer capsule + Cancel
│   │   ├── ImportSummaryView.swift        # sheet; opaque figure rows
│   │   ├── AccountPickerView.swift        # FR-024 disambiguation
│   │   └── PasswordPromptView.swift       # FR-007; password never stored
│   └── Persistence/{KeyStore,StoreLocator}.swift   # unchanged — reused
└── Tests/
    ├── ImportPipelineTests.swift          # NEW — end-to-end over the bridge
    ├── StatementTextExtractorTests.swift  # NEW — 5 failure paths, generated PDFs
    ├── ImportAccessibilityTests.swift     # NEW — Dynamic Type / VoiceOver / Reduce Transparency
    └── *ParseTests.swift, StoreTests.swift, …   # unchanged — must stay green

fixtures/<bank>/<kind>/*.json     # the 13 existing synthetic vectors; extended, never replaced
```

**Structure Decision**: The repo's established two-layer split — a shared Rust engine
(`core/crates/kaname-core/`) exposed via UniFFI, and a native SwiftUI app (`ios/`) that owns
only UI and platform I/O. This slice does not introduce a new layer, module system or project.
The dispatcher lands beside the readers it dispatches to (`src/statement/registry.rs`), the
atomic import lands in the file that owns the only database connection (`src/store.rs`), and
all new platform code is contained in one new folder (`ios/Sources/Import/`) so the PDFKit
import and the pipeline actor each appear in exactly one place.

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified.

**Not applicable — the Constitution Check passed with no violations, before and after Phase 1.**

## Judgement calls for the product owner

Two decisions were made on the product owner's behalf. Both are cheap to reverse and neither
touches a settled Clarification.

1. **The ten `Issuer.display_name` strings** (research R1) — **RESOLVED 2026-08-12**: the
   product owner reviewed the table and approved it with two corrections, now applied in
   research R1: `FEDERAL_CARD` → **"Scapia Credit Card"** and `YES_CARD` → **"Kiwi (YES Bank)
   Credit Card"**. Because FR-033 makes the app render this verbatim, the wording *is* the
   product. Implement the R1 table verbatim.
2. **An import that recovers neither a statement period nor any transaction writes no
   `statements` row** (research R6). There is nothing to attribute it to, and an unattributable
   row would corrupt the coverage map. Every other case still records the import. The
   alternative — making `statements.period_end` nullable — needs a full SQLite table rebuild
   with foreign-key enforcement temporarily disabled, which would restructure the shared
   migration runner; that is deliberately deferred to its own slice if wanted.
