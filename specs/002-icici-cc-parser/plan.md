# Implementation Plan: Import an ICICI Credit-Card Statement On-Device (First Real Parser)

**Branch**: `002-icici-cc-parser` | **Date**: 2026-07-08 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/002-icici-cc-parser/spec.md`
**Milestone**: P2 (first slice) — the first real statement parser in the shared engine

## Summary

Port the web engine's ICICI credit-card statement reader into `kaname-core` (Rust) as a
**pure, deterministic** parse seam that turns already-extracted text lines + full text into
a `ParsedStatement` (transactions with date, exact `Decimal` amount, explicit `Direction`,
currency, description; plus billing-period end and card last-4). PDF text extraction stays
**native** (iOS PDFKit) — the engine never embeds a PDF engine (FR-015). The slice also
lands two reusable foundations every later reader inherits: a **"one transaction per line"**
reader (`LineReaderConfig` + `read_lines`) and a **golden-fixture parity harness** that pins
the on-device engine byte-for-byte to the proven web engine (Principle V). It is exposed to
Swift over the existing UniFFI bridge and guarded by an automated **privacy-egress** gate.

**Technical approach** (details in [`research.md`](./research.md); the web engine is the
source of truth and was executed to capture ground truth):

- **Port faithfully** from `finance-tracker-phase/backend/app/services/ingestion/statement_readers/`:
  `_common.py` → `statement/common.rs` (`parse_amount`, `parse_date`, `find_last4`);
  `polarity.py` → `statement/polarity.rs` (`classify(...) -> Direction`);
  `_line_reader.py` → `statement/line_reader.rs` (`LineReaderConfig` trait + generic
  `read_lines` seam); `base.py` → `statement/base.rs` (`ParsedStatement`/`ParsedTransaction`,
  only the fields this slice needs); `icici.py` → `statement/icici.rs` (`IciciReader`).
  **Do NOT port** pdfplumber (`extract_pages_text/extract_lines/extract_tables/full_text`) —
  extraction is native (FR-015).
- **Reuse the P1 bridge as-is**: UniFFI 0.32 proc-macro/no-UDL; the `Decimal`↔`String`↔Swift
  `Foundation.Decimal` and `NaiveDate`↔ISO-8601-`String` custom types already declared in
  `ffi.rs` + `uniffi.toml`; the existing `#[derive(uniffi::Enum)] Direction`. Add
  `#[derive(uniffi::Record)]` to the two new records and export
  `read_icici_statement(lines, full_text) -> ParsedStatement` and
  `icici_claims(full_text) -> bool`.
- **Golden fixture** (synthetic ICICI vector) ported into repo-root `fixtures/` as
  self-contained JSON; a Rust integration test (`tests/parity.rs`) reproduces the web
  engine's output **exactly** (the reusable harness). Amounts stored/compared as **strings**
  → `Decimal` (never float), preserving scale (`10.20`).
- **Privacy-egress gate**: `make core-privacy-audit` (a `cargo tree` denylist over
  `kaname-core`'s **shipped, default-feature** dependency graph — zero networking crates) +
  a determinism/purity test in the parity harness. Wired into CI's `core` job. No new tool
  (`cargo-deny` considered and deferred — see Complexity Tracking).
- **Verified before writing this plan**: the Rust `regex` crate reproduces Python's exact
  lazy-quantifier captures; `find_last4` works without lookaround (manual neighbor check);
  `Decimal::from_str` preserves scale; `chrono` parses `%d/%m/%Y` and `%b %d, %Y`
  locale-independently. Details + evidence in `research.md` (D3–D6).

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target
**Primary Dependencies**: existing `regex 1.12`, `rust_decimal 1.42`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; **new dev-only** `serde_json` (fixture harness). No new runtime deps.
**Storage**: N/A (no persistence this slice; encrypted SQLite/SQLCipher is out of scope)
**Testing**: `cargo test` (unit + `tests/parity.rs` golden harness + determinism/purity); **Swift Testing** (`import KanameCore`) for the "core ↔ Swift ICICI parse" test
**Target Platform**: iOS 18+ (device `aarch64-apple-ios`; simulator `aarch64-apple-ios-sim` + `x86_64-apple-ios`); core is platform-agnostic
**Project Type**: Mobile — Rust core + native SwiftUI app (monorepo `core/` + `ios/`)
**Performance Goals**: parse is a sub-millisecond pure function over a handful of lines; no throughput target this slice
**Constraints**: 100% on-device, ZERO network in the parse path (FR-018/020, SC-007); deterministic (FR-016, SC-008); money is `Decimal`, never `f64` (FR-007); direction from statement, never amount sign (FR-008); Apache-2.0, no GPL/AGPL/LGPL (FR-024)
**Scale/Scope**: 1 issuer reader + reusable line-reader; 2 new records; 2 exported functions; 1 golden fixture + harness; 1 privacy-audit script + CI step; 1 Swift test suite. No new app UI.

## Constitution Check

*GATE: evaluated before Phase 0 and re-checked after Phase 1. Constitution v1.0.0.*

| Principle / Gate | Verdict | Evidence & how this plan complies |
|---|---|---|
| **I. Data Privacy & Sovereignty** (NON-NEGOTIABLE) — free/core = 100% on-device, zero network, no telemetry | ✅ PASS | The parse path is pure Rust over in-memory `Vec<String>` + `String` — no sockets, HTTP, async runtime, or file/PDF I/O (FR-015/018). **New automated privacy-egress gate**: `make core-privacy-audit` fails if any networking crate appears in `kaname-core`'s shipped (default-feature, `-e normal`) dependency tree, plus a determinism/purity test in the harness (research D9, satisfies FR-020/SC-007). No telemetry/analytics/crash reporter added (FR-019). `serde_json` is **dev-only** (never linked into the app). |
| **II. Local-First Shared Engine** — pure, deterministic, platform-agnostic Rust core via UniFFI; money never float; explicit polarity; no PDF engine in core | ✅ PASS | All logic in `kaname-core`; seam takes already-extracted `lines + full_text` and never opens a PDF (FR-015). Determinism **verified** (identical input ⇒ identical output; `chrono`/`regex` are locale-independent — research D3/D6, FR-016). Amounts are `rust_decimal::Decimal`, scale preserved, never `f64` (FR-006/007). `Direction` comes from the statement's Dr/Cr marker → keyword → default Debit, **never** the amount's sign (FR-008/009/010). Reusable `LineReaderConfig`/`read_lines` (FR-017). |
| **III. Open-Core & Permissive Licensing** — client Apache-2.0; GPL/AGPL/LGPL forbidden; no secrets | ✅ PASS | No secrets/keys/endpoints (FR-024). **No new runtime dependency.** Only addition is **`serde_json` (MIT/Apache-2.0), a dev-dependency** for the test harness — permissive, not copyleft, not shipped in the app binary. Recorded in Complexity Tracking; the privacy audit’s command surface also confirms no copyleft crate enters the shipped tree. |
| **IV. Native Experience & Accessibility** — latest HIG, SwiftUI, Dynamic Type, Dark Mode, VoiceOver | ✅ PASS (N/A UI) | This is an **engine slice with no new user-facing surface** (app-side PDF import, file picker, Share Extension, and UI are explicitly out of scope — spec Assumptions/Out of Scope, FR-026 conditional). The only app-side artifact is a Swift Testing test. If a demo surface is later added it MUST follow HIG + a11y; none is added here. |
| **V. Test-First & Parity** — failing test precedes behavior; `cargo test` + Swift Testing; privacy-egress test | ✅ PASS | **Golden-fixture parity**: the web engine's synthetic ICICI vector is ported to `fixtures/` and reproduced **exactly** by `tests/parity.rs` (FR-021, SC-009). **Test-first**: the failing golden/Swift tests precede the port (FR-023, tasks will sequence red→green). Core via `cargo test`; the bridge via Swift Testing “core ↔ Swift ICICI parse”. Privacy-egress test is a first-class deliverable (FR-020). |
| **iOS Local Verification Gate** — cargo fmt/clippy/test; swiftlint + swift-format; tuist generate; simulator build+test | ✅ PASS | Unchanged ordering preserved: `make core-xcframework` runs **before** `tuist generate` (Makefile `ios-gen: core-xcframework`; CI builds the xcframework before generate). Adds `make core-privacy-audit` to the core gate. `macos-15` stays pinned for the iOS job; local Xcode 26 needs an explicit “iPhone 16” simulator (research D11). |
| **Security & Privacy Constraints** — no network SDKs in core paths; deps reviewed & justified; synthetic fixtures; no committed secrets | ✅ PASS | No network SDK anywhere; the audit proves it structurally. All fixture data is **synthetic/redacted** (fabricated merchant, amount, and masked PAN — FR-022, SC-003 uses `1002`). The one new (dev) dependency is reviewed & justified. No secrets; `.env*` remain ignored. |

**Initial gate result: PASS** — one justified **dev-only** dependency (`serde_json`); zero
unjustified violations. No NEEDS CLARIFICATION remain (the approach is locked; ground truth
captured from the web engine — see `research.md`). Cleared to proceed to Phase 0/1.

## Project Structure

### Documentation (this feature)

```text
specs/002-icici-cc-parser/
├── plan.md                  # This file (/speckit.plan)
├── research.md              # Phase 0 — decisions D1–D13 (all unknowns resolved, with evidence)
├── data-model.md            # Phase 1 — entities, FFI type map, reader/harness types
├── contracts/
│   ├── engine-ffi.md        # Phase 1 — the new UniFFI Swift boundary (read_icici_statement, icici_claims, records)
│   └── golden-fixture.md     # Phase 1 — the reusable golden-fixture JSON schema (all future readers)
├── quickstart.md            # Phase 1 — build, verify, run the parity + privacy gates, add a fixture
├── checklists/              # (pre-existing) spec-quality checklist(s)
└── tasks.md                 # Phase 2 — created by /speckit.tasks (NOT here)
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── Cargo.toml                        # + serde_json (DEV-dependency only — fixture harness)
├── uniffi.toml                       # (unchanged) Decimal → Foundation.Decimal map reused
├── src/
│   ├── lib.rs                        # + pub mod statement; re-export ParsedStatement/ParsedTransaction
│   ├── model.rs                      # (unchanged) Direction (uniffi::Enum) reused
│   ├── dedup.rs                      # (unchanged)
│   ├── ffi.rs                        # + #[uniffi::export] read_icici_statement, icici_claims (custom types reused)
│   ├── statement/                    # NEW — the reader subsystem (mirrors the web engine layout)
│   │   ├── mod.rs                    #   module doc + re-exports
│   │   ├── base.rs                   #   ParsedStatement, ParsedTransaction (#[derive(uniffi::Record)]); MAX_RAW = 240
│   │   ├── common.rs                 #   parse_amount, parse_date (+ DATE_FORMATS), find_last4 (no lookaround)
│   │   ├── polarity.rs               #   classify(desc, dr_cr, amount_cell) -> Direction; marker/keyword sets
│   │   ├── line_reader.rs            #   LineReaderConfig trait + read_lines() generic seam (FR-017)
│   │   └── icici.rs                  #   IciciReader: row regex, "ICICI Bank" claim, enrich (period_end + last4)
│   └── bin/uniffi-bindgen.rs         # (unchanged)
└── tests/
    └── parity.rs                     # NEW — golden-fixture parity harness + determinism/purity + wrong-issuer + malformed-row

core/scripts/
├── build-xcframework.sh              # (unchanged)
└── privacy-egress-audit.sh           # NEW — assert no networking crate in kaname-core's shipped (default) dep tree

fixtures/
└── icici/credit_card/
    └── basic.json                    # NEW — synthetic ICICI golden vector (lines + full_text + expected)

ios/Tests/
└── ICICIParseTests.swift             # NEW — "core ↔ Swift ICICI parse" Swift Testing suite (over the synthetic lines)

Makefile                              # + core-privacy-audit (wired into the core gate)
.github/workflows/ci.yml              # + run make core-privacy-audit in the core job
```

**Structure Decision**: Keep the **monorepo mobile** layout (`core/` Rust + `ios/` SwiftUI).
The reader subsystem lives under a new `statement/` module that **mirrors the web engine's
file layout** (`common`/`polarity`/`line_reader`/`base`/`icici`) so future porting slices map
1:1 to their Python source. New records `ParsedStatement`/`ParsedTransaction` live in
`statement/base.rs` (the web engine's `base.py`), reuse the existing `Direction`, and are the
only new UniFFI records. The exported FFI functions stay in `ffi.rs` (the P1 “boundary”
module), keeping the pure reader logic FFI-free and unit-testable. Generated Swift +
`KanameCoreFFI.xcframework` remain git-ignored artifacts rebuilt by `make core-xcframework`.

## Complexity Tracking

| Addition | Why Needed | Simpler Alternative Rejected Because |
|----------|------------|--------------------------------------|
| **`serde_json`** as a **`[dev-dependencies]`** entry (test harness only) | The golden-fixture parity harness deserializes the synthetic ICICI vector (`fixtures/**/*.json`) so parity is data-driven and reusable across all future readers (FR-021). JSON is human-inspectable and matches the web repo's fixture style. | *Hand-rolled Rust literal / embedded const* — rejected: not data-driven, no reuse across readers, easy to drift from the web vector. *RON/TOML* — rejected: no existing dep either, and JSON best mirrors the web fixtures. `serde_json` is **not shipped** (dev-only, `-e normal` audit excludes it), is **MIT/Apache-2.0** (no copyleft), and adds no runtime/privacy surface. |
| **New CI/Make gate** `core-privacy-audit` (`cargo tree` denylist script) | FR-020 makes the privacy-egress assertion a first-class, automated deliverable of this slice; Rust cannot cheaply assert “no syscalls,” so we prove it structurally (no networking crate can even be present) + behaviorally (determinism). | *`cargo-deny`* — considered; it could enforce banned crates **and** license policy **and** advisories in one tool. **Deferred**: it introduces a new binary + config for a single-parser slice; the `cargo tree` script needs zero new tooling. Recommend adopting `cargo-deny` in a dedicated supply-chain-gate slice where license + advisory enforcement is also wired (higher one-time value). |

> Note: `uniffi` (MPL-2.0) was the only runtime-license item and was already justified and
> tracked in the P1 plan; this slice adds **no** new runtime dependency.

## Phase status

- **Phase 0 — Research**: ✅ complete → [`research.md`](./research.md) (D1–D13; all unknowns
  resolved, key assumptions verified against a live run of the web engine + a scratch Rust build).
- **Phase 1 — Design & Contracts**: ✅ complete → [`data-model.md`](./data-model.md),
  [`contracts/engine-ffi.md`](./contracts/engine-ffi.md),
  [`contracts/golden-fixture.md`](./contracts/golden-fixture.md),
  [`quickstart.md`](./quickstart.md); agent context refreshed via
  `.specify/scripts/bash/update-agent-context.sh copilot`.
- **Phase 1 re-check (post-design Constitution Check)**: ✅ PASS — the design adds no new
  runtime dependency and no new violation; the string-based `Decimal` fixture and the
  determinism/purity + dependency-audit gates actively **reinforce** the no-float-money,
  determinism, and privacy principles.
- **Phase 2 — Tasks**: ⏭️ NOT done here. Run `/speckit.tasks` to generate `tasks.md`
  (ordered test-first per Principle V: golden fixture + failing parity test → common helpers →
  polarity → line-reader → ICICI reader → FFI export → privacy audit + CI → Swift bridge test).
