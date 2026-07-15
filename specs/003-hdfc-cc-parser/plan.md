# Implementation Plan: Import an HDFC Credit-Card Statement On-Device (Second Real Parser, Two Layouts)

**Branch**: `003-hdfc-cc-parser` | **Date**: 2026-07-15 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/003-hdfc-cc-parser/spec.md`
**Milestone**: P2 (next slice) — the second real statement parser in the shared engine

## Summary

Port the web engine's **HDFC credit-card** reader into `kaname-core` (Rust) as a **pure,
deterministic** parse that turns already-extracted text lines + full text into a
`ParsedStatement`. HDFC is a **composite, two-layout** reader — a **year-end consolidated**
layout (`DD-Mon-YYYY <desc> <amount> DR|CR`) and a **monthly co-brand** layout
(`DD/MM/YYYY| HH:MM <merchant> [+ ]C <amount>`) — behind a single entry point that tries the
year-end layout first and falls back to monthly, so the caller never picks a layout (FR-003/004).

This slice **reuses — does not rebuild** — everything the ICICI slice (`002-icici-cc-parser`)
landed: the `LineReaderConfig` trait + `read_lines` seam, the `ParsedStatement`/
`ParsedTransaction` records, the `parse_amount`/`parse_date`/`find_last4` (incl. the **anchor**
path) and `polarity::classify` helpers, the golden-fixture parity harness, the UniFFI bridge
(`Decimal`/`NaiveDate` custom types + `Direction` enum), and the privacy-egress gate + CI. HDFC
adds only **three small, reusable engine-internal pieces** (FR-020): an ordered **multi-layout
composite** helper `read_lines_first_match` (in `line_reader.rs`), a **month-name-and-year →
month-end** date helper `month_year_end` (in `common.rs`), and a **monthly leading-`+` credit**
direction rule (in `hdfc.rs`; deliberately *not* `classify`). It is exposed to Swift as
`read_hdfc_statement` + `hdfc_claims`, mirroring the ICICI surface.

**Technical approach** (details in [`research.md`](./research.md); the web engine is the source
of truth and was **executed** to capture ground truth for **both** vectors):

- **Port faithfully** from `finance-tracker-phase/backend/app/services/ingestion/statement_readers/hdfc.py`
  → new `statement/hdfc.rs`. Two zero-sized configs — `HdfcYearEndReader` and
  `HdfcMonthlyReader` — implement the existing `LineReaderConfig` trait, share one `enrich`, and
  are composed by `read_lines_first_match(&[&year_end, &monthly], lines, full_text)` (mirrors the
  web `HdfcCreditCardReader.read_lines`: return the first statement whose `lines` are non-empty,
  else the last empty statement). **Claim markers**: `HDFC Bank Credit Card` /
  `HDFC Bank Credit Cards` (`BANK_CODE = "HDFC"`).
- **Reuse the ICICI foundations as-is**: `read_lines`, records, `common`/`polarity` helpers, the
  `find_last4(text, Some("Card Number"))` anchor path (already implemented, untested by ICICI),
  the parity harness, and the UniFFI custom types. **No new dependency** (runtime *or* dev):
  `serde_json` (dev-only, harness) already exists from the ICICI slice.
- **New shared helpers** (small, reusable, per FR-020): `month_year_end(token) -> Option<NaiveDate>`
  in `common.rs`; `read_lines_first_match(cfgs: &[&dyn LineReaderConfig], …)` in `line_reader.rs`
  (enabled by relaxing `read_lines`/`claims` to `C: LineReaderConfig + ?Sized` — backward-compatible).
- **Two golden fixtures** under `fixtures/hdfc/credit_card/`: (1) `year_end.json` **ported** from
  the web characterization vector; (2) `monthly.json` **fabricated** (synthetic merchant/amount/
  masked PAN) with its `expected` **captured from a live web-engine run** (never hand-derived —
  FR-026). Both are pinned byte-for-byte by `tests/parity.rs` via **two new case-table rows**,
  both calling the **same** `read_hdfc_statement` (proving auto-selection). The harness gains one
  minimal, backward-compatible field — `period_start` — because HDFC is the first reader to
  populate it (see Complexity Tracking + research D10).
- **Verified before writing this plan** (throwaway build on the pinned crates —
  `regex 1`, `chrono 0.4`, `rust_decimal 1`): both HDFC row regexes reproduce Python's captures
  byte-for-byte (incl. the year-end trailing card number being ignored and the monthly leading
  `C`/`+`); the two layouts' row regexes are **mutually exclusive** (safe ordering);
  `month_year_end` computes month-end via chrono (`MARCH-26 → 2026-03-31`, leap `FEB-24 →
  2024-02-29`, `BOGUS-99 → None`); and the `&[&dyn LineReaderConfig]` + `?Sized` composite
  pattern compiles. Ground truth for both vectors captured from `hdfc.reader.read_lines(...)`.
  Evidence in [`research.md`](./research.md) (D3–D10).

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.**
**Storage**: N/A (no persistence this slice; encrypted SQLite/SQLCipher is out of scope)
**Testing**: `cargo test` (unit + `tests/parity.rs` golden harness for **both** HDFC vectors + determinism); **Swift Testing** (`import KanameCore`) for a "core ↔ Swift HDFC parse" test (both layouts)
**Target Platform**: iOS 18+ (device `aarch64-apple-ios`; simulator `aarch64-apple-ios-sim` + `x86_64-apple-ios`); core is platform-agnostic
**Project Type**: Mobile — Rust core + native SwiftUI app (monorepo `core/` + `ios/`)
**Performance Goals**: parse is a sub-millisecond pure function over a handful of lines; the composite tries ≤2 layouts; no throughput target this slice
**Constraints**: 100% on-device, ZERO network in the parse path (FR-018/022/024, SC-008); deterministic (FR-019, SC-009); money is `Decimal`, never `f64` (FR-009); direction from the statement, never the amount's sign — **both** layouts (FR-010/011/012, SC-005); Apache-2.0, no GPL/AGPL/LGPL, **no new deps** (FR-029)
**Scale/Scope**: 1 new composite reader (2 layout configs) + 3 small reusable helpers; 0 new records; 2 exported functions; 2 golden fixtures + 2 harness rows (+1 harness field); 0 new dependencies; no new app UI

## Constitution Check

*GATE: evaluated before Phase 0 and re-checked after Phase 1. Constitution v1.0.0.*

| Principle / Gate | Verdict | Evidence & how this plan complies |
|---|---|---|
| **I. Data Privacy & Sovereignty** (NON-NEGOTIABLE) — free/core = 100% on-device, zero network, no telemetry | ✅ PASS | The HDFC parse path is pure Rust over in-memory `Vec<String>` + `String` — no sockets, HTTP, async runtime, or file/PDF I/O (FR-018/022). It **inherits the existing privacy-egress gate** (`make core-privacy-audit`) unchanged; **confirmed no new networking dependency** (in fact **no new dependency at all** — see III), so the shipped `cargo tree -e normal` graph is byte-identical. The determinism/purity parity test now also covers the two HDFC vectors (FR-019/024, SC-008/009). No telemetry/analytics/crash reporter added (FR-023). |
| **II. Local-First Shared Engine** — pure, deterministic, platform-agnostic Rust core via UniFFI; money never float; explicit polarity; no PDF engine in core | ✅ PASS | HDFC **reuses** the `read_lines` seam and never opens a PDF (FR-018). Determinism **verified** (both row regexes and `month_year_end` are pure; `chrono`/`regex` are locale-independent — research D3/D4/D5). Amounts are `rust_decimal::Decimal`, scale preserved, never `f64`, and the monthly Rupee-glyph `C` is a literal outside the amount group so it never enters the number (FR-008/009, SC-006). Direction comes from the statement in **both** layouts — year-end via the explicit `DR`/`CR` marker (`classify(desc, dir, None)`), monthly via the **leading `+`** rule — **never** the amount's sign (FR-010/011/012). New reuse seams `read_lines_first_match` + `month_year_end` land in the shared subsystem for later multi-layout banks (FR-020). |
| **III. Open-Core & Permissive Licensing** — client Apache-2.0; GPL/AGPL/LGPL forbidden; no secrets | ✅ PASS | No secrets/keys/endpoints (FR-029). **NO new runtime OR dev dependency** — HDFC is built entirely from crates already in the graph (`regex`, `rust_decimal`, `chrono`, `serde`, `uniffi`; dev `serde_json`). Nothing copyleft enters the tree; the privacy audit's `cargo tree` surface re-confirms it. |
| **IV. Native Experience & Accessibility** — latest HIG, SwiftUI, Dynamic Type, Dark Mode, VoiceOver | ✅ PASS (N/A UI) | This is an **engine slice with no new user-facing surface** (app-side PDF import, file picker, Share Extension are explicitly out of scope — spec Out of Scope, FR-031 conditional). The only app-side artifact is an optional Swift Testing suite. If a demo surface is later added it MUST follow HIG + a11y; none is added here. |
| **V. Test-First & Parity** — failing test precedes behavior; `cargo test` + Swift Testing; privacy-egress test | ✅ PASS | **Golden-fixture parity, both layouts**: the web engine's synthetic HDFC **year-end** vector is ported and the **monthly** vector's `expected` is **captured from a live web-engine run** (FR-025/026), then reproduced **exactly** by `tests/parity.rs` (SC-010). **Test-first**: the two failing golden tests precede the port (FR-028; tasks sequence red→green). Core via `cargo test`; the bridge via a "core ↔ Swift HDFC parse" suite. Privacy-egress + determinism guards extended to HDFC. |
| **iOS Local Verification Gate** — cargo fmt/clippy/test; swiftlint + swift-format; tuist generate; simulator build+test | ✅ PASS | Ordering **unchanged**: `make core-xcframework` runs **before** `tuist generate` (Makefile `ios-gen: core-xcframework`; CI builds the xcframework first). The two new exports are purely additive to the bindings. `macos-15` stays pinned for the iOS job; the **iPhone 16** simulator (OS=latest) is the `xcodebuild` destination; the core (ubuntu) job's privacy audit is inherited (FR-030). |
| **Security & Privacy Constraints** — no network SDKs in core paths; deps reviewed & justified; synthetic fixtures; no committed secrets | ✅ PASS | No network SDK anywhere; the audit proves it structurally and **no dependency review is needed** (no new dep). All fixture data is **synthetic/redacted** — the year-end vector uses fabricated merchants + masked PAN `…9070`; the monthly vector is entirely fabricated (`EXAMPLE MERCHANT`, `…5678`) (FR-027, SC-012). No secrets; `.env*` remain ignored. |

**Initial gate result: PASS** — **zero new dependencies**, zero unjustified violations. No NEEDS
CLARIFICATION remain (the approach is locked by the requester and confirmed with a live
web-engine run + a scratch Rust build — see `research.md`). Two small, backward-compatible
enabling changes (relax `read_lines` to `?Sized`; add a `period_start` field to the parity
harness) are **design notes, not violations** (Complexity Tracking). Cleared to Phase 0/1.

## Project Structure

### Documentation (this feature)

```text
specs/003-hdfc-cc-parser/
├── plan.md                  # This file (/speckit.plan)
├── research.md              # Phase 0 — decisions D1–D13 (all unknowns resolved, with evidence)
├── data-model.md            # Phase 1 — reused records, the two layout configs, composite + helpers, harness delta
├── contracts/
│   ├── engine-ffi.md        # Phase 1 — the additive UniFFI Swift boundary (read_hdfc_statement, hdfc_claims)
│   └── golden-fixture.md    # Phase 1 — the two HDFC vectors + the +period_start harness-schema delta
├── quickstart.md            # Phase 1 — build, verify, run the parity + privacy gates, capture monthly ground truth
├── checklists/              # (pre-existing) spec-quality checklist(s)
└── tasks.md                 # Phase 2 — created by /speckit.tasks (NOT here)
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── Cargo.toml                        # UNCHANGED — no new dependency (runtime or dev)
├── uniffi.toml                       # UNCHANGED — Decimal → Foundation.Decimal map reused
├── src/
│   ├── lib.rs                        # + re-export read_hdfc_statement, hdfc_claims
│   ├── model.rs                      # UNCHANGED — Direction (uniffi::Enum) reused
│   ├── ffi.rs                        # + #[uniffi::export] read_hdfc_statement, hdfc_claims (custom types reused)
│   ├── statement/
│   │   ├── mod.rs                    # + pub mod hdfc;
│   │   ├── base.rs                   # UNCHANGED — ParsedStatement/ParsedTransaction (period_start already a field)
│   │   ├── common.rs                 # + month_year_end(token) -> Option<NaiveDate>  (NEW shared helper)
│   │   ├── polarity.rs               # UNCHANGED — classify reused for the year-end DR/CR marker
│   │   ├── line_reader.rs            # + read_lines_first_match(&[&dyn LineReaderConfig], …); read_lines/claims → `?Sized`
│   │   ├── icici.rs                  # UNCHANGED
│   │   └── hdfc.rs                   # NEW — HdfcYearEndReader + HdfcMonthlyReader + shared enrich + composite
│   └── bin/uniffi-bindgen.rs         # UNCHANGED
└── tests/
    └── parity.rs                     # + `period_start` in Expected (backward-compatible) + 2 HDFC case rows + hdfc_claims test

fixtures/
└── hdfc/credit_card/
    ├── year_end.json                 # NEW — ported synthetic year-end vector (from the web characterization vector)
    └── monthly.json                  # NEW — fabricated monthly vector; expected CAPTURED from a live web-engine run

ios/Tests/
└── HDFCParseTests.swift              # NEW — "core ↔ Swift HDFC parse" (both layouts + wrong-issuer) Swift Testing suite

Makefile                              # UNCHANGED — HDFC inherits core-test / core-privacy-audit / ios-test
.github/workflows/ci.yml              # UNCHANGED — HDFC inherits the core + iOS gates
```

**Structure Decision**: Keep the **monorepo mobile** layout (`core/` Rust + `ios/` SwiftUI) and
the `statement/` module that mirrors the web engine 1:1 — `hdfc.py → statement/hdfc.rs` — so the
port is a mechanical, reviewable diff. HDFC introduces **no new record and no new dependency**;
the composite lives in `hdfc.rs` and leans on one new generic helper in `line_reader.rs`
(`read_lines_first_match`) and one in `common.rs` (`month_year_end`), both placed in the shared
subsystem for reuse by later multi-layout banks (FR-020). Exported FFI functions stay in `ffi.rs`
(pure reader logic stays FFI-free and unit-testable). Generated Swift + `KanameCoreFFI.xcframework`
remain git-ignored artifacts rebuilt by `make core-xcframework` (before `tuist generate`).

## Complexity Tracking

> No constitution violations and **no new dependencies**. The table records the two small,
> backward-compatible enabling changes for transparency; neither adds a dependency or violates a
> principle.

| Addition | Why Needed | Simpler Alternative Rejected Because |
|----------|------------|--------------------------------------|
| Relax `read_lines`/`claims` to `C: LineReaderConfig + ?Sized` and add `read_lines_first_match(cfgs: &[&dyn LineReaderConfig], …)` | HDFC is the first **multi-layout** reader: one entry point must try the year-end config then the monthly config (heterogeneous types) and return the first with rows, else the last empty one (FR-003/004). Dynamic dispatch over `&dyn LineReaderConfig` needs the `?Sized` relaxation. Placed in `line_reader.rs` so later multi-layout banks reuse it (FR-020). | *Duplicate the read loop per layout in `hdfc.rs`* — rejected: copies the seam, no reuse, drifts from the web's composite. *An `enum` of layouts* — rejected: not extensible to future banks; `&[&dyn …]` mirrors the web's tuple-of-readers exactly. The relaxation is **backward-compatible** (existing `read_lines(&IciciReader, …)` still compiles) and adds no dependency. |
| Add `period_start: Option<String>` (`#[serde(default)]`) to the parity harness `Expected` + one assertion | HDFC is the **first** reader to populate `period_start` (year-end `2025-04-01`; monthly `2026-05-15`); parity must pin it byte-for-byte (SC-003, US6-AC1). ICICI omits it → `serde(default)` = `None`, and ICICI's `period_start` is already `None`, so the change is **backward-compatible** and the ICICI fixture is untouched. | *Assert `period_start` only in a separate `hdfc.rs` unit test* — rejected: the parity harness is the byte-for-byte regression guard the spec names (US6-AC1); leaving `period_start` unpinned there would let a regression slip. This is the **only** harness code delta beyond the two case-table rows; the JSON schema stays additive. |

> Note: `uniffi` (MPL-2.0) and dev-only `serde_json` (MIT/Apache-2.0) were justified in prior
> slices; **this slice adds neither a runtime nor a dev dependency.**

## Phase status

- **Phase 0 — Research**: ✅ complete → [`research.md`](./research.md) (D1–D13; all unknowns
  resolved; both vectors' ground truth captured from a live web-engine run; port mechanics
  verified in a throwaway Rust build on the pinned crates).
- **Phase 1 — Design & Contracts**: ✅ complete → [`data-model.md`](./data-model.md),
  [`contracts/engine-ffi.md`](./contracts/engine-ffi.md),
  [`contracts/golden-fixture.md`](./contracts/golden-fixture.md),
  [`quickstart.md`](./quickstart.md); agent context refreshed via
  `.specify/scripts/bash/update-agent-context.sh copilot`.
- **Phase 1 re-check (post-design Constitution Check)**: ✅ PASS — the design adds **no new
  dependency** and no new violation; the two golden vectors + the string-based `Decimal` fixtures
  + the determinism/purity + dependency-audit gates actively **reinforce** the no-float-money,
  determinism, and privacy principles. The `period_start` field and `?Sized` relaxation are
  backward-compatible.
- **Phase 2 — Tasks**: ⏭️ NOT done here. Run `/speckit.tasks` to generate `tasks.md`, ordered
  test-first per Principle V: capture monthly ground truth from the web engine → write both
  golden fixtures + failing parity rows (+`period_start`) → `month_year_end` (common) →
  `read_lines_first_match` + `?Sized` (line_reader) → `hdfc.rs` (two configs + shared enrich +
  monthly `+` rule + composite) → FFI exports + lib re-exports → Swift bridge test → run the
  inherited privacy/iOS gates.
