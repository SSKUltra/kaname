# Implementation Plan: Import a Yes Bank (Kiwi) Credit-Card Statement On-Device (Fourth Real Parser, Zero New Engine Infrastructure)

**Branch**: `005-yes-cc-parser` | **Date**: 2026-07-15 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/005-yes-cc-parser/spec.md`
**Milestone**: P2 (next slice) — the fourth real statement parser in the shared engine

## Summary

Port the web engine's **Yes Bank / Kiwi credit-card** reader into `kaname-core` (Rust) as a **pure,
deterministic** parse that turns already-extracted text lines + full text into a `ParsedStatement`.
Yes is a **clean single-layout** reader — one row shape
`DD/MM/YYYY <details … Ref No> <Merchant Category> <amount> Dr|Cr` (a day-first date, description,
amount, and a **terminal two-letter `Dr`/`Cr` direction marker**) — that drops straight into the
existing `read_lines(&cfg, lines, full_text)` seam, exactly like ICICI's `read_icici_statement` and
SBI's `read_sbi_statement`.

This slice is a **second clean single-layout drop-in after SBI**: it **reuses — and adds nothing to**
— the shared engine infrastructure. Like SBI (`004`), **Yes adds no new shared helper at all**. Its
`DD/MM/YYYY` date format is **already** in the shared `DATE_FORMATS` (`common.rs:21`, already
commented **"(ICICI, Yes)"** — the very `%d/%m/%Y` ICICI uses), and its two-letter `Dr`/`Cr` markers
are **already** in the shared polarity tables (`normalise_marker` strips to `DR`/`CR`; `CR_MARKERS`
contains `"CR"`, `DR_MARKERS` contains `"DR"` — `polarity.rs:11–12`). Yes is therefore delivered as:
**one new reader config** (`statement/yes.rs`), **two FFI exports** (`read_yes_statement` +
`yes_claims`, mirroring ICICI/HDFC/SBI), **one golden fixture**, and **one parity `Case` row** — with
**no new dependency** (runtime *or* dev) and **no change** to any shared helper, record, seam, or the
harness schema.

**One deliberate scope carve-out** distinguishes this port from a naïve full port: the web engine's
Yes `_enrich` *also* scrapes the statement's **printed** per-statement debit/credit totals
(`_DEBITS_RE` / `_CREDITS_RE` → `printed_total_debits` / `printed_total_credits`) for a future
reconciliation feature. Those printed-total fields are **intentionally not ported** — they are **not**
in the Rust `ParsedStatement`, and the Yes `enrich` here is **only period + last-4** (FR-013, US5,
SC-013). This keeps the Yes reader identically shaped to the already-landed ICICI/HDFC/SBI credit-card
readers (none expose printed totals) and draws a clean boundary for the later reconciliation slice.
See the carve-out decision in [`research.md`](./research.md) (D10) and the Complexity Tracking note.

**Technical approach** (details in [`research.md`](./research.md); the web engine is the source of
truth — `yes_kiwi.py` was **read as ground truth**, and the port was **verified against the real
`kaname-core` helpers** before writing this plan):

- **Port faithfully** from
  `finance-tracker-phase/backend/app/services/ingestion/statement_readers/yes_kiwi.py`
  → new `statement/yes.rs`. One **zero-sized** `YesReader` implements the existing
  `LineReaderConfig` trait, structured **identically to `sbi.rs`/`icici.rs`**: `bank_code()`,
  `claim_markers()`, `row_re()` (via `LazyLock`), `direction()` = `classify(desc, dir, None)`, and a
  free `enrich()`. **`BANK_CODE = "YES"`**; **claim markers** `("YES BANK",)` (single marker).
- **Reuse the ICICI/HDFC/SBI foundations as-is**: the `read_lines`/`claims` seam (`line_reader.rs`),
  the `ParsedStatement`/`ParsedTransaction` records (`base.rs`, where `period_start` is **already** a
  field), `parse_amount`/`parse_date`/**`find_last4(text, Some("Card Number"))`** (`common.rs`),
  `polarity::classify` (`polarity.rs`), the parity harness (`tests/parity.rs`, which **already asserts
  `period_start`**), and the UniFFI bridge (`ffi.rs` + `uniffi.toml`: `Decimal`/`NaiveDate` custom
  types + `Direction` enum). **No new dependency** (runtime *or* dev).
- **Row regex** (`LazyLock<Regex>`), ported byte-for-byte from `_ROW_RE`:
  `^(?P<date>\d{2}/\d{2}/\d{4})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>Dr|Cr)$`
  — the two-letter `Dr`/`Cr` marker sits **at the end**, anchored at `$`. Direction =
  `classify(desc, caps.name("dir"), None)` (the same `marker_direction` behaviour ICICI/SBI use).
- **Enrich** (ported from `_enrich`, **minus** the reconciliation scrape): period from
  `_PERIOD_RE = (?i)(\d{2}/\d{2}/\d{4})\s+To\s+(\d{2}/\d{2}/\d{4})`
  → `period_start = parse_date(g1)`, `period_end = parse_date(g2)` (both via the existing
  `%d/%m/%Y`); `card_last4 = find_last4(full_text, Some("Card Number"))`. **The `_DEBITS_RE` /
  `_CREDITS_RE` printed-total lines are deliberately NOT ported** (D10; FR-013).
- **One golden fixture** `fixtures/yes/credit_card/basic.json`, **ported** from the web
  characterization vector, pinned byte-for-byte by **one new `Case` row** in `tests/parity.rs` calling
  `read_yes_statement`. The harness needs **no code/schema change** — `period_start` was already added
  (and asserted) by the HDFC slice and reused by SBI.
- **Verified before writing this plan** (throwaway crate path-depending on the **real** `kaname-core`,
  on the pinned stable toolchain): the `YesReader` — using the shared `read_lines` seam and the shared
  `parse_date`/`parse_amount`/`find_last4`/`classify` helpers unchanged — reproduces the golden vector
  **exactly**: rows `2026-04-29 / 9000.00 / Credit / "PAYMENT RECEIVED BBPS - Ref No: RT0001"` and
  `2026-04-19 / 100.00 / Debit / "UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores"`;
  `period_start 2026-04-17`; `period_end 2026-05-16`; **`card_last4 "6686"`**; `errored_lines []`; and
  it claims its own doc while rejecting ICICI/SBI text (and a wrong `bank_code`). Evidence in
  [`research.md`](./research.md) (D3–D10 + Verification harness).

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.**
**Storage**: N/A (no persistence this slice; encrypted SQLite/SQLCipher is out of scope)
**Testing**: `cargo test` (unit + `tests/parity.rs` golden harness for the Yes vector + determinism + wrong-issuer); **Swift Testing** (`import KanameCore`) for a "core ↔ Swift Yes parse" test
**Target Platform**: iOS 18+ (device `aarch64-apple-ios`; simulator `aarch64-apple-ios-sim` + `x86_64-apple-ios`); core is platform-agnostic
**Project Type**: Mobile — Rust core + native SwiftUI app (monorepo `core/` + `ios/`)
**Performance Goals**: parse is a sub-millisecond pure function over a handful of lines; single layout (one pass); no throughput target this slice
**Constraints**: 100% on-device, ZERO network in the parse path (FR-015/016/019, SC-007); deterministic (FR-016, SC-008); money is `Decimal`, never `f64` (FR-006/007); direction from the terminal `Dr`/`Cr` marker, never the amount's sign or the description (FR-008/009, SC-004); Apache-2.0, no GPL/AGPL/LGPL, **no new deps** (FR-025); **printed-total reconciliation fields excluded** (FR-013, SC-013)
**Scale/Scope**: 1 new single-layout reader config; **0 new shared helpers**; 0 new records; 2 exported functions; 1 golden fixture + 1 harness `Case` row (**0 harness schema/code change**); 0 new dependencies; no new app UI

## Constitution Check

*GATE: evaluated before Phase 0 and re-checked after Phase 1. Constitution v1.0.0.*

| Principle / Gate | Verdict | Evidence & how this plan complies |
|---|---|---|
| **I. Data Privacy & Sovereignty** (NON-NEGOTIABLE) — free/core = 100% on-device, zero network, no telemetry | ✅ PASS | The Yes parse path is pure Rust over an in-memory `Vec<String>` + `String` — no sockets, HTTP, async runtime, or file/PDF I/O (FR-015/019). It **inherits the existing privacy-egress gate** (`make core-privacy-audit`) unchanged; **no new dependency at all** (see III), so the shipped `cargo tree -e normal` graph is byte-identical. The determinism/purity parity test now also covers the Yes vector (FR-016, SC-007/008). No telemetry/analytics/crash reporter added (FR-020). |
| **II. Local-First Shared Engine** — pure, deterministic, platform-agnostic Rust core via UniFFI; money never float; explicit polarity; no PDF engine in core | ✅ PASS | Yes **reuses** the `read_lines` seam and never opens a PDF (FR-015). Determinism **verified** (the row/period regexes, `parse_date`, `find_last4`, `classify` are pure; `chrono`/`regex` are locale-independent). Amounts are `rust_decimal::Decimal`, scale preserved, never `f64` (FR-006/007, SC-005). Direction comes from the statement's **terminal `Dr`/`Cr` marker** via `classify(desc, dir, None)` — **never** the amount's sign or the description's wording (FR-008/009, SC-004; verified `Dr` wins even when the description contains "PAYMENT RECEIVED"/"REFUND"/"CASHBACK"). **No new shared helper is added** — the `%d/%m/%Y` format and `Dr`/`Cr` markers are already in the shared subsystem (FR-017, SC-010). |
| **III. Open-Core & Permissive Licensing** — client Apache-2.0; GPL/AGPL/LGPL forbidden; no secrets | ✅ PASS | No secrets/keys/endpoints (FR-025). **NO new runtime OR dev dependency** — Yes is built entirely from crates already in the graph (`regex`, `rust_decimal`, `chrono`, `serde`, `uniffi`; dev `serde_json`). Nothing copyleft enters the tree; the privacy audit's `cargo tree` surface re-confirms it. |
| **IV. Native Experience & Accessibility** — latest HIG, SwiftUI, Dynamic Type, Dark Mode, VoiceOver | ✅ PASS (N/A UI) | This is an **engine slice with no new user-facing surface** (app-side PDF import, file picker, Share Extension are explicitly out of scope — spec Out of Scope, FR-027 conditional). The only app-side artifact is an optional Swift Testing suite. If a demo surface is later added it MUST follow HIG + a11y; none is added here. |
| **V. Test-First & Parity** — failing test precedes behaviour; `cargo test` + Swift Testing; privacy-egress test | ✅ PASS | **Golden-fixture parity**: the web engine's synthetic Yes vector is **ported** (FR-022) and reproduced **exactly** by `tests/parity.rs` (SC-001/003/009). **Test-first**: the failing golden test (+ `yes_claims` wrong-issuer test) precedes the port (FR-024; tasks sequence red→green). Core via `cargo test`; the bridge via a "core ↔ Swift Yes parse" suite. Privacy-egress + determinism guards extended to Yes. All fixture data is **synthetic/redacted** (FR-023). |
| **Scope carve-out — reconciliation excluded** (Principle II shape discipline; spec US5/FR-013/SC-013) | ✅ PASS | The web `_enrich` scrapes printed debit/credit totals (`_DEBITS_RE`/`_CREDITS_RE`) into `printed_total_debits`/`printed_total_credits`. Those fields **do not exist** in the Rust `ParsedStatement` (`base.rs` ports only period + last-4; the `printed_*` totals "arrive with a later slice") and the Yes `enrich` **must not** add them. **Verified**: with printed-total lines present in `full_text`, the parse returns only rows + period + last-4 (no printed totals anywhere). This is a deliberate scope *reduction* (fewer fields than the source), not a constitution violation — it keeps Yes identical in shape to the landed ICICI/HDFC/SBI readers. |
| **iOS Local Verification Gate** — cargo fmt/clippy/test; swiftlint + swift-format; tuist generate; simulator build+test | ✅ PASS | Ordering **unchanged**: `make core-xcframework` runs **before** `tuist generate` (Makefile `ios-gen: core-xcframework`; CI builds the xcframework first). The two new exports are purely additive to the bindings (records reused → no new Swift type). `macos-15` stays pinned for the iOS job; the **iPhone 16** simulator (`OS=latest`) is the `xcodebuild` destination; the core (ubuntu) job's privacy audit is inherited (FR-026). |
| **Security & Privacy Constraints** — no network SDKs in core paths; deps reviewed & justified; synthetic fixtures; no committed secrets | ✅ PASS | No network SDK anywhere; the audit proves it structurally and **no dependency review is needed** (no new dep). All fixture data is **synthetic/redacted** — fabricated merchants (`PAYMENT RECEIVED BBPS - Ref No: RT0001`, `UPI_EXAMPLE STORE IND …`), amounts, and a masked card number `3561XXXXXXXX6686` (FR-023, SC-012). No secrets; `.env*` remain ignored. |

**Initial gate result: PASS** — **zero new dependencies, zero new shared helpers, zero harness
schema change**, zero unjustified violations. The single scope carve-out (printed-total reconciliation
fields) is a deliberate, spec-mandated *reduction* (US5/FR-013), verified to produce output identical
in shape to the landed readers — it is documented below in Complexity Tracking for visibility, not
because it is a violation. No NEEDS CLARIFICATION remain (the approach is locked by the requester and
confirmed with a verification build against the real `kaname-core` helpers — see `research.md`).
Cleared to Phase 0/1.

## Project Structure

### Documentation (this feature)

```text
specs/005-yes-cc-parser/
├── plan.md                  # This file (/speckit.plan)
├── research.md              # Phase 0 — decisions D1–D10 (all unknowns resolved, with evidence)
├── data-model.md            # Phase 1 — reused records, the single Yes config, reused helpers, harness row
├── contracts/
│   ├── engine-ffi.md        # Phase 1 — the additive UniFFI Swift boundary (read_yes_statement, yes_claims)
│   └── golden-fixture.md     # Phase 1 — the Yes vector (reuses the period_start-stable harness schema)
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
│   ├── lib.rs                        # + re-export read_yes_statement, yes_claims
│   ├── model.rs                      # UNCHANGED — Direction (uniffi::Enum) reused
│   ├── ffi.rs                        # + #[uniffi::export] read_yes_statement, yes_claims (custom types reused)
│   ├── statement/
│   │   ├── mod.rs                    # + pub mod yes;
│   │   ├── base.rs                   # UNCHANGED — ParsedStatement/ParsedTransaction (NO printed_total_* fields; period_start already a field)
│   │   ├── common.rs                 # UNCHANGED — parse_date "%d/%m/%Y" (already commented "ICICI, Yes") + find_last4 anchor path already present
│   │   ├── polarity.rs               # UNCHANGED — classify + CR/DR markers already include "CR"/"DR"
│   │   ├── line_reader.rs            # UNCHANGED — read_lines/claims seam reused verbatim
│   │   ├── icici.rs                  # UNCHANGED
│   │   ├── hdfc.rs                   # UNCHANGED
│   │   ├── sbi.rs                    # UNCHANGED
│   │   └── yes.rs                    # NEW — YesReader (single config) + free enrich (period + last4 ONLY), structured like sbi.rs
│   └── bin/uniffi-bindgen.rs         # UNCHANGED
└── tests/
    └── parity.rs                     # + 1 Yes Case row (+ optional yes_claims accept/reject test); NO schema change

fixtures/
└── yes/credit_card/
    └── basic.json                    # NEW — ported synthetic Yes vector (from the web characterization vector)

ios/Tests/
└── YesParseTests.swift               # NEW — "core ↔ Swift Yes parse" (+ wrong-issuer) Swift Testing suite

Makefile                              # UNCHANGED — Yes inherits core-test / core-privacy-audit / ios-test
.github/workflows/ci.yml              # UNCHANGED — Yes inherits the core + iOS gates
```

**Structure Decision**: Keep the **monorepo mobile** layout (`core/` Rust + `ios/` SwiftUI) and the
`statement/` module that mirrors the web engine 1:1 — `yes_kiwi.py → statement/yes.rs` — so the port
is a mechanical, reviewable diff. Yes introduces **no new record, no new shared helper, and no new
dependency**; the reader is a single zero-sized config that leans entirely on the existing seam and
helpers. The reader's `enrich` populates **only** `period_start`/`period_end`/`card_last4` — the
web reader's `printed_total_*` scrape is deliberately dropped (FR-013). Exported FFI functions stay in
`ffi.rs` (pure reader logic stays FFI-free and unit-testable). Generated Swift +
`KanameCoreFFI.xcframework` remain git-ignored artifacts rebuilt by `make core-xcframework` (before
`tuist generate`).

## Complexity Tracking

> **No constitution violations.** Yes adds **no new dependency**, **no new shared helper**, **no new
> record**, and **no harness schema/code change** — it is a pure single-layout drop-in reusing the
> seam, helpers, harness, bridge, and privacy gate that ICICI built and HDFC/SBI extended. The one
> item worth recording is the **reconciliation carve-out** below — a deliberate *reduction* in scope,
> not an added complexity or a violation.

| Item | Why (in scope this slice) | Why the alternative (full port) is rejected |
|---|---|---|
| **Printed-total reconciliation fields NOT ported** (`printed_total_debits` / `printed_total_credits`, from the web `_DEBITS_RE`/`_CREDITS_RE`) | The Rust `ParsedStatement` (`base.rs`) intentionally ports **only** the fields this milestone needs (rows + period + last-4); the landed ICICI/HDFC/SBI readers expose **no** printed totals. Yes's `enrich` therefore does **period + last-4 only** (FR-013, US5, SC-013). | Porting the printed-total scrape would (a) add `ParsedStatement` fields no landed reader uses, (b) ship a **half-built reconciliation surface** with no consumer, and (c) break shape-parity with the other three credit-card readers. Reconciliation is a dedicated later slice; the totals belong there. Verified: with printed-total lines present, the Yes parse returns only rows + period + last-4. |

## Phase status

- **Phase 0 — Research**: ✅ complete → [`research.md`](./research.md) (D1–D10; all unknowns resolved;
  ground truth read from `yes_kiwi.py`; the port **verified against the real `kaname-core` helpers**
  on the pinned toolchain — every golden value reproduced, including `card_last4 "6686"` and the
  reconciliation carve-out).
- **Phase 1 — Design & Contracts**: ✅ complete → [`data-model.md`](./data-model.md),
  [`contracts/engine-ffi.md`](./contracts/engine-ffi.md),
  [`contracts/golden-fixture.md`](./contracts/golden-fixture.md),
  [`quickstart.md`](./quickstart.md); agent context refreshed via
  `.specify/scripts/bash/update-agent-context.sh copilot`.
- **Phase 1 re-check (post-design Constitution Check)**: ✅ PASS — the design adds **no new
  dependency**, **no new shared helper**, and no new violation; the golden vector + the string-based
  `Decimal` fixture + the determinism/purity + dependency-audit gates actively **reinforce** the
  no-float-money, determinism, and privacy principles. The reconciliation carve-out is recorded in
  Complexity Tracking as a deliberate reduction.
- **Phase 2 — Tasks**: ⏭️ NOT done here. Run `/speckit.tasks` to generate `tasks.md`, ordered
  test-first per Principle V: write the golden fixture + failing parity `Case` row (+ `yes_claims`
  wrong-issuer test) → `statement/yes.rs` (single config + free enrich = period + last-4, mirroring
  `sbi.rs`) → FFI exports (`read_yes_statement` + `yes_claims`) + `lib.rs` re-exports + `mod.rs`
  `pub mod yes;` → Swift bridge test → run the inherited privacy/iOS gates.
