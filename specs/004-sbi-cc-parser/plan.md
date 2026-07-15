# Implementation Plan: Import an SBI Card Credit-Card Statement On-Device (Third Real Parser, Zero New Engine Infrastructure)

**Branch**: `004-sbi-cc-parser` | **Date**: 2026-07-15 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/004-sbi-cc-parser/spec.md`
**Milestone**: P2 (next slice) — the third real statement parser in the shared engine

## Summary

Port the web engine's **SBI Card credit-card** reader into `kaname-core` (Rust) as a **pure,
deterministic** parse that turns already-extracted text lines + full text into a
`ParsedStatement`. SBI is a **clean single-layout** reader — one row shape
`DD Mon YY <details> <amount> C|D` (a day-first date, description, amount, and a **terminal
single-letter `C`/`D` direction marker**) — that drops straight into the existing
`read_lines(&cfg, lines, full_text)` seam, exactly like ICICI's `read_icici_statement`.

This slice is the **simplest yet**: it **reuses — and adds nothing to** — the shared engine
infrastructure. Unlike HDFC (`003`), which added `read_lines_first_match` (composite multi-layout)
and `month_year_end` (a date helper) and a monthly leading-`+` rule, **SBI adds no new shared
helper at all**. Its `DD Mon YY` date format is **already** in the shared `DATE_FORMATS`
(`common.rs:26`, commented "SBI"), and its single-letter `C`/`D` markers are **already** in the
shared polarity tables (`CR_MARKERS` contains `"C"`, `DR_MARKERS` contains `"D"` — `polarity.rs:11–12`).
SBI is therefore delivered as: **one new reader config** (`statement/sbi.rs`), **two FFI exports**
(`read_sbi_statement` + `sbi_claims`, mirroring ICICI/HDFC), **one golden fixture**, and **one
parity `Case` row** — with **no new dependency** (runtime *or* dev) and **no change** to any shared
helper, record, seam, or the harness schema.

**Technical approach** (details in [`research.md`](./research.md); the web engine is the source of
truth and was **executed** to capture ground truth; the port was **verified against the real
`kaname-core` helpers** before writing this plan):

- **Port faithfully** from
  `finance-tracker-phase/backend/app/services/ingestion/statement_readers/sbi_card.py`
  → new `statement/sbi.rs`. One **zero-sized** `SbiReader` implements the existing
  `LineReaderConfig` trait, structured **identically to `icici.rs`**: `bank_code()`,
  `claim_markers()`, `row_re()` (via `LazyLock`), `direction()` = `classify(desc, dir, None)`, and a
  free `enrich()`. **`BANK_CODE = "SBI_CARD"`**; **claim markers** `"SBI Card"` /
  `"GSTIN of SBI Card"`.
- **Reuse the ICICI/HDFC foundations as-is**: the `read_lines`/`claims` seam (`line_reader.rs`), the
  `ParsedStatement`/`ParsedTransaction` records (`base.rs`, where `period_start` is **already** a
  field), `parse_amount`/`parse_date`/**`find_last4(text, Some("Credit Card Number"))`**
  (`common.rs`), `polarity::classify` (`polarity.rs`), the parity harness (`tests/parity.rs`, which
  **already asserts `period_start`**), and the UniFFI bridge (`ffi.rs` + `uniffi.toml`:
  `Decimal`/`NaiveDate` custom types + `Direction` enum). **No new dependency** (runtime *or* dev).
- **Row regex** (`LazyLock<Regex>`), ported byte-for-byte from `_ROW_RE`:
  `^(?P<date>\d{2} [A-Za-z]{3} \d{2})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>[CD])$`
  — the single-letter `C`/`D` marker sits **at the end**, anchored at `$`. Direction =
  `classify(desc, caps.name("dir"), None)` (the same `marker_direction` behavior ICICI uses).
- **Enrich** (ported from `_enrich`): period from
  `_PERIOD_RE = (?i)Statement Period:\s*(\d{2} [A-Za-z]{3} \d{2})\s+to\s+(\d{2} [A-Za-z]{3} \d{2})`
  → `period_start = parse_date(g1)`, `period_end = parse_date(g2)` (both via the existing
  `%d %b %y`); `card_last4 = find_last4(full_text, Some("Credit Card Number"))`.
- **One golden fixture** `fixtures/sbi_card/credit_card/basic.json`, **ported** from the web
  characterization vector (`_SBI_LINES`/`_SBI_TEXT` in `test_cc_reader_characterization.py`), pinned
  byte-for-byte by **one new `Case` row** in `tests/parity.rs` calling `read_sbi_statement`. The
  harness needs **no code/schema change** — `period_start` was already added (and asserted) by the
  HDFC slice.
- **Verified before writing this plan** (throwaway build path-depending on the **real** crate, on
  the pinned toolchain): the SBI `SbiReader` — using the shared `read_lines` seam and the shared
  `parse_date`/`parse_amount`/`find_last4`/`classify` helpers unchanged — reproduces the golden
  vector **exactly**: rows `2026-04-21 / 643.00 / Credit / "CARD CASHBACK CREDIT"` and
  `2026-05-20 / 82900.00 / Debit / "APPLE INDIA STORE MUMBAI IN"`; `period_start 2026-04-22`;
  `period_end 2026-05-21`; **`card_last4 None`** (the mask `XXXX XXXX XXXX XX61` exposes only two
  trailing digits); and it claims its own doc while rejecting ICICI/HDFC. Evidence in
  [`research.md`](./research.md) (D3–D9).

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.**
**Storage**: N/A (no persistence this slice; encrypted SQLite/SQLCipher is out of scope)
**Testing**: `cargo test` (unit + `tests/parity.rs` golden harness for the SBI vector + determinism + wrong-issuer); **Swift Testing** (`import KanameCore`) for a "core ↔ Swift SBI parse" test
**Target Platform**: iOS 18+ (device `aarch64-apple-ios`; simulator `aarch64-apple-ios-sim` + `x86_64-apple-ios`); core is platform-agnostic
**Project Type**: Mobile — Rust core + native SwiftUI app (monorepo `core/` + `ios/`)
**Performance Goals**: parse is a sub-millisecond pure function over a handful of lines; single layout (one pass); no throughput target this slice
**Constraints**: 100% on-device, ZERO network in the parse path (FR-015/016/019, SC-007); deterministic (FR-016, SC-008); money is `Decimal`, never `f64` (FR-006/007); direction from the terminal `C`/`D` marker, never the amount's sign or the description (FR-008/009, SC-004); Apache-2.0, no GPL/AGPL/LGPL, **no new deps** (FR-025)
**Scale/Scope**: 1 new single-layout reader config; **0 new shared helpers**; 0 new records; 2 exported functions; 1 golden fixture + 1 harness `Case` row (**0 harness schema/code change**); 0 new dependencies; no new app UI

## Constitution Check

*GATE: evaluated before Phase 0 and re-checked after Phase 1. Constitution v1.0.0.*

| Principle / Gate | Verdict | Evidence & how this plan complies |
|---|---|---|
| **I. Data Privacy & Sovereignty** (NON-NEGOTIABLE) — free/core = 100% on-device, zero network, no telemetry | ✅ PASS | The SBI parse path is pure Rust over an in-memory `Vec<String>` + `String` — no sockets, HTTP, async runtime, or file/PDF I/O (FR-015/019). It **inherits the existing privacy-egress gate** (`make core-privacy-audit`) unchanged; **confirmed no new networking dependency** — in fact **no new dependency at all** (see III), so the shipped `cargo tree -e normal` graph is byte-identical. The determinism/purity parity test now also covers the SBI vector (FR-016, SC-007/008). No telemetry/analytics/crash reporter added (FR-020). |
| **II. Local-First Shared Engine** — pure, deterministic, platform-agnostic Rust core via UniFFI; money never float; explicit polarity; no PDF engine in core | ✅ PASS | SBI **reuses** the `read_lines` seam and never opens a PDF (FR-015). Determinism **verified** (the row regex, `parse_date`, `find_last4`, `classify` are pure; `chrono`/`regex` are locale-independent — research D3–D6). Amounts are `rust_decimal::Decimal`, scale preserved, never `f64` (FR-006/007, SC-005). Direction comes from the statement's **terminal `C`/`D` marker** via `classify(desc, dir, None)` — **never** the amount's sign or the description's wording (FR-008/009, SC-004; verified the `C`/`D` marker wins even when the description contains "CREDIT"). **No new shared helper is added** — the `DD Mon YY` format and `C`/`D` markers are already in the shared subsystem (FR-017, SC-010). |
| **III. Open-Core & Permissive Licensing** — client Apache-2.0; GPL/AGPL/LGPL forbidden; no secrets | ✅ PASS | No secrets/keys/endpoints (FR-025). **NO new runtime OR dev dependency** — SBI is built entirely from crates already in the graph (`regex`, `rust_decimal`, `chrono`, `serde`, `uniffi`; dev `serde_json`). Nothing copyleft enters the tree; the privacy audit's `cargo tree` surface re-confirms it. |
| **IV. Native Experience & Accessibility** — latest HIG, SwiftUI, Dynamic Type, Dark Mode, VoiceOver | ✅ PASS (N/A UI) | This is an **engine slice with no new user-facing surface** (app-side PDF import, file picker, Share Extension are explicitly out of scope — spec Out of Scope, FR-027 conditional). The only app-side artifact is an optional Swift Testing suite. If a demo surface is later added it MUST follow HIG + a11y; none is added here. |
| **V. Test-First & Parity** — failing test precedes behavior; `cargo test` + Swift Testing; privacy-egress test | ✅ PASS | **Golden-fixture parity**: the web engine's synthetic SBI vector is **ported** (FR-022) and reproduced **exactly** by `tests/parity.rs` (SC-001/003/009). **Test-first**: the failing golden test (+ `sbi_claims` wrong-issuer test) precedes the port (FR-024; tasks sequence red→green). Core via `cargo test`; the bridge via a "core ↔ Swift SBI parse" suite. Privacy-egress + determinism guards extended to SBI. All fixture data is **synthetic/redacted** (FR-023). |
| **iOS Local Verification Gate** — cargo fmt/clippy/test; swiftlint + swift-format; tuist generate; simulator build+test | ✅ PASS | Ordering **unchanged**: `make core-xcframework` runs **before** `tuist generate` (Makefile `ios-gen: core-xcframework`; CI builds the xcframework first). The two new exports are purely additive to the bindings (records reused → no new Swift type). `macos-15` stays pinned for the iOS job; the **iPhone 16** simulator (OS=latest) is the `xcodebuild` destination; the core (ubuntu) job's privacy audit is inherited (FR-026). |
| **Security & Privacy Constraints** — no network SDKs in core paths; deps reviewed & justified; synthetic fixtures; no committed secrets | ✅ PASS | No network SDK anywhere; the audit proves it structurally and **no dependency review is needed** (no new dep). All fixture data is **synthetic/redacted** — fabricated merchants (`CARD CASHBACK CREDIT`, `APPLE INDIA STORE MUMBAI IN`), amounts, and a masked card number `XXXX XXXX XXXX XX61` (FR-023, SC-012). No secrets; `.env*` remain ignored. |

**Initial gate result: PASS** — **zero new dependencies, zero new shared helpers, zero harness
schema change**, zero unjustified violations. No NEEDS CLARIFICATION remain (the approach is locked
by the requester and confirmed with a live web-engine run + a verification build against the real
`kaname-core` helpers — see `research.md`). There is **nothing** in the Complexity Tracking table:
this is a pure drop-in. Cleared to Phase 0/1.

## Project Structure

### Documentation (this feature)

```text
specs/004-sbi-cc-parser/
├── plan.md                  # This file (/speckit.plan)
├── research.md              # Phase 0 — decisions D1–D9 (all unknowns resolved, with evidence)
├── data-model.md            # Phase 1 — reused records, the single SBI config, reused helpers, harness row
├── contracts/
│   ├── engine-ffi.md        # Phase 1 — the additive UniFFI Swift boundary (read_sbi_statement, sbi_claims)
│   └── golden-fixture.md    # Phase 1 — the SBI vector (reuses the period_start-stable harness schema)
├── quickstart.md            # Phase 1 — build, verify, run the parity + privacy gates
├── checklists/              # (pre-existing) spec-quality checklist(s)
└── tasks.md                 # Phase 2 — created by /speckit.tasks (NOT here)
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── Cargo.toml                        # UNCHANGED — no new dependency (runtime or dev)
├── uniffi.toml                       # UNCHANGED — Decimal → Foundation.Decimal map reused
├── src/
│   ├── lib.rs                        # + re-export read_sbi_statement, sbi_claims
│   ├── model.rs                      # UNCHANGED — Direction (uniffi::Enum) reused
│   ├── ffi.rs                        # + #[uniffi::export] read_sbi_statement, sbi_claims (custom types reused)
│   ├── statement/
│   │   ├── mod.rs                    # + pub mod sbi;
│   │   ├── base.rs                   # UNCHANGED — ParsedStatement/ParsedTransaction (period_start already a field)
│   │   ├── common.rs                 # UNCHANGED — parse_date "%d %b %y" + find_last4 anchor path already present
│   │   ├── polarity.rs               # UNCHANGED — classify + CR/DR markers already include "C"/"D"
│   │   ├── line_reader.rs            # UNCHANGED — read_lines/claims seam reused verbatim
│   │   ├── icici.rs                  # UNCHANGED
│   │   ├── hdfc.rs                   # UNCHANGED
│   │   └── sbi.rs                    # NEW — SbiReader (single config) + free enrich, structured like icici.rs
│   └── bin/uniffi-bindgen.rs         # UNCHANGED
└── tests/
    └── parity.rs                     # + 1 SBI Case row (+ optional sbi_claims accept/reject test); NO schema change

fixtures/
└── sbi_card/credit_card/
    └── basic.json                    # NEW — ported synthetic SBI vector (from the web characterization vector)

ios/Tests/
└── SBIParseTests.swift               # NEW — "core ↔ Swift SBI parse" (+ wrong-issuer) Swift Testing suite

Makefile                              # UNCHANGED — SBI inherits core-test / core-privacy-audit / ios-test
.github/workflows/ci.yml              # UNCHANGED — SBI inherits the core + iOS gates
```

**Structure Decision**: Keep the **monorepo mobile** layout (`core/` Rust + `ios/` SwiftUI) and the
`statement/` module that mirrors the web engine 1:1 — `sbi_card.py → statement/sbi.rs` — so the port
is a mechanical, reviewable diff. SBI introduces **no new record, no new shared helper, and no new
dependency**; the reader is a single zero-sized config that leans entirely on the existing seam and
helpers. Exported FFI functions stay in `ffi.rs` (pure reader logic stays FFI-free and
unit-testable). Generated Swift + `KanameCoreFFI.xcframework` remain git-ignored artifacts rebuilt by
`make core-xcframework` (before `tuist generate`).

## Complexity Tracking

> **No entries.** SBI adds **no new dependency**, **no new shared helper**, **no new record**, and
> **no harness schema/code change** — it is a pure single-layout drop-in reusing the seam, helpers,
> harness, bridge, and privacy gate that ICICI built and HDFC extended. There is no constitution
> violation and no enabling change to justify. (The two backward-compatible enablers HDFC needed —
> `read_lines_first_match`/`?Sized` and the `period_start` harness field — already landed and are
> reused unchanged; SBI requires neither a new one nor a modification.)

## Phase status

- **Phase 0 — Research**: ✅ complete → [`research.md`](./research.md) (D1–D9; all unknowns resolved;
  ground truth captured from the web characterization test; the port **verified against the real
  `kaname-core` helpers** on the pinned toolchain — every golden value reproduced, including
  `card_last4 None`).
- **Phase 1 — Design & Contracts**: ✅ complete → [`data-model.md`](./data-model.md),
  [`contracts/engine-ffi.md`](./contracts/engine-ffi.md),
  [`contracts/golden-fixture.md`](./contracts/golden-fixture.md),
  [`quickstart.md`](./quickstart.md); agent context refreshed via
  `.specify/scripts/bash/update-agent-context.sh copilot`.
- **Phase 1 re-check (post-design Constitution Check)**: ✅ PASS — the design adds **no new
  dependency**, **no new shared helper**, and no new violation; the golden vector + the string-based
  `Decimal` fixture + the determinism/purity + dependency-audit gates actively **reinforce** the
  no-float-money, determinism, and privacy principles. Nothing in Complexity Tracking.
- **Phase 2 — Tasks**: ⏭️ NOT done here. Run `/speckit.tasks` to generate `tasks.md`, ordered
  test-first per Principle V: write the golden fixture + failing parity `Case` row (+ `sbi_claims`
  wrong-issuer test) → `statement/sbi.rs` (single config + free enrich, mirroring `icici.rs`) → FFI
  exports (`read_sbi_statement` + `sbi_claims`) + `lib.rs` re-exports + `mod.rs` `pub mod sbi;` →
  Swift bridge test → run the inherited privacy/iOS gates.
