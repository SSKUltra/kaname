# Implementation Plan: Import a Federal Bank / Scapia Credit-Card Statement On-Device (Fifth and Final Credit-Card Parser — the Most Distinctive Layout, Zero New Engine Infrastructure)

**Branch**: `006-federal-cc-parser` | **Date**: 2026-07-16 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/006-federal-cc-parser/spec.md`
**Milestone**: P2 (next slice) — the fifth and final credit-card parser, completing the credit-card set

## Summary

Port the web engine's **Federal Bank / Scapia** credit-card reader into `kaname-core` (Rust) as a
**pure, deterministic** parse that turns already-extracted text lines + full text into a
`ParsedStatement`. Federal is the **most distinctive of the five** credit-card layouts — one row shape
`DD-MM-YYYY<sep>HH:MM <description> [+]₹<amount>` where the date joins an `HH:MM` transaction time by a
single **middle-dot separator** (U+00B7), the amount is **prefixed by the rupee glyph** (₹, U+20B9),
and a **leading `+`** immediately before the amount is Scapia's own credit notation (there is **no**
`Dr`/`Cr` column) — yet it still drops straight into the existing `read_lines(&cfg, lines, full_text)`
seam, exactly like ICICI's `read_icici_statement`, SBI's `read_sbi_statement`, and Yes's
`read_yes_statement`.

This slice is the **third clean single-layout drop-in after SBI and Yes**, and it **completes the
credit-card set** (ICICI, HDFC, SBI, Yes already landed). It **reuses — and adds nothing to** — the
shared engine infrastructure. Like SBI (`004`) and Yes (`005`), **Federal adds no new shared helper at
all**, and it adds **no new dependency**:

- Its row date format `%d-%m-%Y` is **already** in the shared `DATE_FORMATS` — `common.rs:24` reads
  `"%d-%m-%Y",  // 24-04-2026 (Scapia/Federal)` — and its space-stripped billing-cycle format `%d%b%Y`
  is **already** present too — `common.rs:31` reads `"%d%b%Y",    // 20Apr2026 (Scapia billing cycle,
  space-stripped)`. Both were pre-seeded for exactly this reader; **no Federal-specific date code**.
- Its credit-word direction fallback reuses the **shared polarity classifier** `classify(desc, None,
  None)` (`polarity.rs`), unchanged.
- Its `card_last4` is recovered by the **existing** `find_last4` with **no anchor** (whole-text scan),
  already implemented and exercised by the other readers.

Federal is therefore delivered as: **one new reader config** (`statement/federal.rs`), **two FFI
exports** (`read_federal_statement` + `federal_claims`, mirroring ICICI/HDFC/SBI/Yes), **one golden
fixture** (`fixtures/federal/credit_card/basic.json`), and **one parity `Case` row** in
`tests/parity.rs` (+ one `federal_claims` accept/reject test) — with **no change** to any shared
helper, record, seam, or the harness schema.

**Federal's one bespoke behaviour** is its direction rule, and it lives **entirely in the reader**, not
in shared polarity: a leading `+` before the amount → `Direction::Credit`; otherwise the shared
`classify(description, None, None)` decides from the description language (credit words → credit; else
debit). This mirrors the web `_direction` fn and is structurally the **same pattern HDFC's monthly
layout already uses** (its `direction` inspects a leading-`+` capture rather than a `Dr`/`Cr` marker) —
so it is a proven, precedented in-reader rule, not new shared infrastructure. Unlike ICICI/SBI/Yes
(which pass a `Dr`/`Cr`/`C`/`D` marker into the shared classifier via `classify(desc, marker, None)`),
Federal has **no** such marker column, so it must decide `+`-credit locally and only fall back to
`classify(desc, None, None)`.

**Technical approach** (details in [`research.md`](./research.md); the web engine is the source of
truth — `federal_scapia.py` was **read as ground truth**, and the port was **verified against the real
`kaname-core` helpers** on the pinned stable toolchain before writing this plan):

- **Port faithfully** from
  `finance-tracker-phase/backend/app/services/ingestion/statement_readers/federal_scapia.py`
  → new `statement/federal.rs`. One **zero-sized** `FederalReader` implements the existing
  `LineReaderConfig` trait, structured **identically to `sbi.rs`/`yes.rs`**: `bank_code()`,
  `claim_markers()`, `row_re()` (via `LazyLock`), a **Federal-local** `direction()`, and an `enrich()`
  (cycle + un-anchored last-4). **`BANK_CODE = "FEDERAL"`**; **claim markers** `("Scapia", "Federal
  Bank")`.
- **Reuse the ICICI/HDFC/SBI/Yes foundations as-is**: the `read_lines`/`claims` seam
  (`line_reader.rs`), the `ParsedStatement`/`ParsedTransaction` records (`base.rs`, where `period_start`
  is **already** a field), `parse_amount`/`parse_date`/**`find_last4(text, None)`** (`common.rs`),
  `polarity::classify` (`polarity.rs`), the parity harness (`tests/parity.rs`, which **already asserts
  `period_start`**), and the UniFFI bridge (`ffi.rs` + `uniffi.toml`: `Decimal`/`NaiveDate` custom
  types + `Direction` enum). **No new dependency** (runtime *or* dev).
- **Row regex** (`LazyLock<Regex>`), ported byte-for-byte from `_ROW_RE`:
  `^(?P<date>\d{2}-\d{2}-\d{4}).\d{2}:\d{2}\s+(?P<desc>.+?)\s+(?P<sign>\+)?₹(?P<amount>[\d,]+\.\d{2})$`
  — the **unescaped `.`** after the date matches the middot separator **encoding-robustly** (Rust
  `regex`'s default `.` matches any single non-newline scalar, incl. U+00B7); the `HH:MM` time is
  consumed by `\d{2}:\d{2}` and never enters `desc`; the literal `₹` (a valid char in a raw UTF-8
  string literal `r"…₹…"`) precedes the amount group and is **excluded** from it. The named `date`/
  `desc`/`amount` groups match the seam's defaults; the extra `sign` group is read by the reader's
  `direction`.
- **Direction** (Federal-local; ported from `_direction`): `if caps.name("sign") == Some("+")
  → Direction::Credit else classify(description, None, None)`. The amount's value/sign is **never**
  consulted.
- **Enrich** (ported from `_enrich`): cycle from
  `_CYCLE_RE = (\d{1,2}[A-Za-z]{3}\d{4})\s*-\s*(\d{1,2}[A-Za-z]{3}\d{4})`
  → `period_start = parse_date(g1)`, `period_end = parse_date(g2)` (both via the existing `%d%b%Y`);
  `card_last4 = find_last4(full_text, None)` (**no anchor** — the card is fully masked
  `XXXXXXXXXXXX4836` with no textual label, so the loose masked-PAN matcher yields `"4836"`).
- **One golden fixture** `fixtures/federal/credit_card/basic.json`, **ported** from the web
  characterization vector (using the **actual** U+00B7 and U+20B9 characters), pinned byte-for-byte by
  **one new `Case` row** in `tests/parity.rs` calling `read_federal_statement`. The harness needs **no
  code/schema change** — `period_start` was already added (and asserted) by the HDFC slice and reused
  by SBI/Yes.
- **Verified before writing this plan** (throwaway crate path-depending on the **real** `kaname-core`,
  on the pinned stable toolchain): the `FederalReader` — using the shared `read_lines` seam and the
  shared `parse_date`/`parse_amount`/`find_last4`/`classify` helpers unchanged — reproduces the golden
  vector **exactly**: rows `2026-04-29 / 324.45 / Credit / "Billpayment Payment"` and
  `2026-04-24 / 2353.13 / Debit / "ExampleMerchantTokyo"`; `period_start 2026-04-20`;
  `period_end 2026-05-19`; **`card_last4 "4836"`**; `errored_lines []`; it claims its own doc while
  rejecting ICICI/HDFC/SBI/Yes text (and a wrong `bank_code`); the row matches encoding-robustly with
  the separator as `·`, a space, or `.`; and a no-`+` `refund/reversal received` row classifies Credit
  via the shared fallback. Evidence in [`research.md`](./research.md) (D1–D10 + Verification harness).

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`; verified on rustc 1.96.1) + Swift 5.x / SwiftUI, iOS 18 target
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.**
**Storage**: N/A (no persistence this slice; encrypted SQLite/SQLCipher is out of scope)
**Testing**: `cargo test` (unit + `tests/parity.rs` golden harness for the Federal vector + determinism + wrong-issuer); **Swift Testing** (`import KanameCore`) for a "core ↔ Swift Federal parse" test
**Target Platform**: iOS 18+ (device `aarch64-apple-ios`; simulator `aarch64-apple-ios-sim` + `x86_64-apple-ios`); core is platform-agnostic
**Project Type**: Mobile — Rust core + native SwiftUI app (monorepo `core/` + `ios/`)
**Performance Goals**: parse is a sub-millisecond pure function over a handful of lines; single layout (one pass); no throughput target this slice
**Constraints**: 100% on-device, ZERO network in the parse path (FR-016/017/020, SC-008); deterministic (FR-017, SC-009); money is `Decimal`, never `f64` (FR-008/009, SC-006); direction from Scapia's leading `+` else the shared description-language classifier, **never** the amount's sign/magnitude (FR-010/011, SC-004); encoding-robust single-char date/time separator (FR-004, SC-005); Apache-2.0, no GPL/AGPL/LGPL, **no new deps** (FR-026); **no new shared helper** (FR-018, SC-011)
**Scale/Scope**: 1 new single-layout reader config; **0 new shared helpers**; 0 new records; 2 exported functions; 1 golden fixture + 1 harness `Case` row (**0 harness schema/code change**); 0 new dependencies; no new app UI

## Constitution Check

*GATE: evaluated before Phase 0 and re-checked after Phase 1. Constitution v1.0.0.*

| Principle / Gate | Verdict | Evidence & how this plan complies |
|---|---|---|
| **I. Data Privacy & Sovereignty** (NON-NEGOTIABLE) — free/core = 100% on-device, zero network, no telemetry | ✅ PASS | The Federal parse path is pure Rust over an in-memory `Vec<String>` + `String` — no sockets, HTTP, async runtime, or file/PDF I/O (FR-016/020). It **inherits the existing privacy-egress gate** (`make core-privacy-audit`) unchanged; **no new dependency at all** (see III), so the shipped `cargo tree -e normal` graph is byte-identical. The determinism/purity parity tests now also cover the Federal vector (FR-017, SC-008/009). No telemetry/analytics/crash reporter added (FR-021). |
| **II. Local-First Shared Engine** — pure, deterministic, platform-agnostic Rust core via UniFFI; money never float; explicit polarity; no PDF engine in core | ✅ PASS | Federal **reuses** the `read_lines` seam and never opens a PDF (FR-016). Determinism **verified** (the row/cycle regexes, `parse_date`, `find_last4`, `classify` are pure; `chrono`/`regex` are locale-independent). Amounts are `rust_decimal::Decimal`, scale preserved, never `f64`; the rupee glyph and any leading `+` are stripped (FR-008/009, SC-006). Direction comes from Scapia's **leading `+`** and, failing that, the **shared description-language classifier** — **never** the amount's sign/magnitude (FR-010/011, SC-004; verified `+`→Credit, `refund/reversal received`→Credit, ordinary spend→Debit). **No new shared helper is added** — both date formats (`%d-%m-%Y`, `%d%b%Y`) and the polarity classifier are already in the shared subsystem; the one bespoke rule (leading-`+`) lives in `federal.rs` (FR-018, SC-011). |
| **III. Open-Core & Permissive Licensing** — client Apache-2.0; GPL/AGPL/LGPL forbidden; no secrets | ✅ PASS | No secrets/keys/endpoints (FR-026). **NO new runtime OR dev dependency** — Federal is built entirely from crates already in the graph (`regex`, `rust_decimal`, `chrono`, `serde`, `uniffi`; dev `serde_json`). Nothing copyleft enters the tree; the privacy audit's `cargo tree` surface re-confirms it. |
| **IV. Native Experience & Accessibility** — latest HIG, SwiftUI, Dynamic Type, Dark Mode, VoiceOver | ✅ PASS (N/A UI) | This is an **engine slice with no new user-facing surface** (app-side PDF import, file picker, Share Extension are explicitly out of scope — FR-028 is conditional). The only app-side artifact is an optional Swift Testing suite. If a demo surface is later added it MUST follow HIG + a11y; none is added here. |
| **V. Test-First & Parity** — failing test precedes behaviour; `cargo test` + Swift Testing; privacy-egress test | ✅ PASS | **Golden-fixture parity**: the web engine's synthetic Federal vector is **ported** (FR-023) and reproduced **exactly** by `tests/parity.rs` (SC-001/003/010). **Test-first**: the failing golden test (+ `federal_claims` wrong-issuer test) precedes the port (FR-025; tasks sequence red→green). Core via `cargo test`; the bridge via a "core ↔ Swift Federal parse" suite. Privacy-egress + determinism guards extended to Federal. All fixture data is **synthetic/redacted** (FR-024). |
| **iOS Local Verification Gate** — cargo fmt/clippy/test; swiftlint + swift-format; tuist generate; simulator build+test | ✅ PASS | Ordering **unchanged**: `make core-xcframework` runs **before** `tuist generate` (Makefile `ios-gen: core-xcframework`; CI builds the xcframework first). The two new exports are purely additive to the bindings (records reused → no new Swift type). `macos-15` stays pinned for the iOS job; the **iPhone 16** simulator (`OS=latest`) is the `xcodebuild` destination; the core (ubuntu) job's privacy audit is inherited (FR-027). |
| **Security & Privacy Constraints** — no network SDKs in core paths; deps reviewed & justified; synthetic fixtures; no committed secrets | ✅ PASS | No network SDK anywhere; the audit proves it structurally and **no dependency review is needed** (no new dep). All fixture data is **synthetic/redacted** — fabricated merchants (`Billpayment Payment`, `ExampleMerchantTokyo`), amounts, and a fully-masked card `XXXXXXXXXXXX4836` (FR-024, SC-002). No secrets; `.env*` remain ignored. |

**Initial gate result: PASS** — **zero new dependencies, zero new shared helpers, zero harness schema
change**, zero unjustified violations. Federal's single bespoke behaviour — the leading-`+` direction
rule — is confined to `federal.rs` (the same in-reader pattern HDFC's monthly layout already uses) and
is **not** a shared-subsystem change. No NEEDS CLARIFICATION remain (the approach is locked by the
requester and confirmed with a verification build against the real `kaname-core` helpers — see
[`research.md`](./research.md)). Cleared to Phase 0/1.

## Project Structure

### Documentation (this feature)

```text
specs/006-federal-cc-parser/
├── plan.md                  # This file (/speckit.plan)
├── research.md              # Phase 0 — decisions D1–D10 (all unknowns resolved, with evidence)
├── data-model.md            # Phase 1 — reused records, the single Federal config, reused helpers, harness row
├── contracts/
│   ├── engine-ffi.md        # Phase 1 — the additive UniFFI Swift boundary (read_federal_statement, federal_claims)
│   └── golden-fixture.md    # Phase 1 — the Federal vector (reuses the period_start-stable harness schema)
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
│   ├── lib.rs                        # + re-export read_federal_statement, federal_claims
│   ├── model.rs                      # UNCHANGED — Direction (uniffi::Enum) reused
│   ├── ffi.rs                        # + #[uniffi::export] read_federal_statement, federal_claims (custom types reused)
│   ├── statement/
│   │   ├── mod.rs                    # + pub mod federal;
│   │   ├── base.rs                   # UNCHANGED — ParsedStatement/ParsedTransaction (period_start already a field)
│   │   ├── common.rs                 # UNCHANGED — parse_date "%d-%m-%Y" AND "%d%b%Y" already present (commented Scapia/Federal); find_last4 no-anchor path already present
│   │   ├── polarity.rs               # UNCHANGED — classify(desc, None, None) reused for the fallback
│   │   ├── line_reader.rs            # UNCHANGED — read_lines/claims seam reused verbatim
│   │   ├── icici.rs                  # UNCHANGED
│   │   ├── hdfc.rs                   # UNCHANGED (its monthly leading-'+' rule is the precedent for Federal's)
│   │   ├── sbi.rs                    # UNCHANGED
│   │   ├── yes.rs                    # UNCHANGED
│   │   └── federal.rs                # NEW — FederalReader (single config) + enrich (cycle + un-anchored last4), structured like sbi.rs/yes.rs
│   └── bin/uniffi-bindgen.rs         # UNCHANGED
└── tests/
    └── parity.rs                     # + 1 Federal Case row (+ federal_claims accept/reject test); NO schema change

fixtures/
└── federal/credit_card/
    └── basic.json                    # NEW — ported synthetic Federal vector (actual U+00B7 middot + U+20B9 rupee bytes)

ios/Tests/
└── FederalParseTests.swift           # NEW — "core ↔ Swift Federal parse" (+ wrong-issuer) Swift Testing suite

Makefile                              # UNCHANGED — Federal inherits core-test / core-privacy-audit / ios-test
.github/workflows/ci.yml              # UNCHANGED — Federal inherits the core + iOS gates
```

**Structure Decision**: Keep the **monorepo mobile** layout (`core/` Rust + `ios/` SwiftUI) and the
`statement/` module that mirrors the web engine 1:1 — `federal_scapia.py → statement/federal.rs` — so
the port is a mechanical, reviewable diff. Federal introduces **no new record, no new shared helper,
and no new dependency**; the reader is a single zero-sized config that leans entirely on the existing
seam and helpers. It is a **single-layout** reader, so `read_federal_statement` wraps
`read_lines(&FederalReader, …)` **directly** (like `sbi.rs`/`yes.rs`) — **not** the HDFC
`read_lines_first_match` composite. The reader's `enrich` populates `period_start`/`period_end`/
`card_last4` (via the **un-anchored** `find_last4`). Exported FFI functions stay in `ffi.rs` (pure
reader logic stays FFI-free and unit-testable). Generated Swift + `KanameCoreFFI.xcframework` remain
git-ignored artifacts rebuilt by `make core-xcframework` (before `tuist generate`).

## Complexity Tracking

> **No constitution violations.** Federal adds **no new dependency**, **no new shared helper**, **no
> new record**, and **no harness schema/code change** — it is a pure single-layout drop-in reusing the
> seam, helpers, harness, bridge, and privacy gate that ICICI built and HDFC/SBI/Yes extended. Federal
> has **no reconciliation carve-out** (unlike Yes): the web `federal_scapia.py` `_enrich` already scopes
> to cycle + last-4 only, so the port is a 1:1 mechanical match with nothing dropped.

| Item | Why (in scope this slice) | Why the alternative is rejected |
|---|---|---|
| **Direction rule lives in `federal.rs`, not shared polarity** (leading `+` → Credit, else `classify(desc, None, None)`) | Scapia has **no** `Dr`/`Cr` column; a credit is signalled only by a leading `+`. The shared `classify` marker parameter expects letter markers (`DR`/`CR`/`C`/`D`), not `+`, so the `+` test must be local. This is the **same in-reader pattern HDFC's monthly layout uses** (FR-010, US3). | Adding a `+` case to the shared `normalise_marker`/`classify` would be a **new shared helper behaviour** for a one-issuer notation (violates FR-018/SC-011) and could leak `+`-as-credit into readers that don't want it. Keeping it in `federal.rs` is the precedented, minimal choice. |

## Phase status

- **Phase 0 — Research**: ✅ complete → [`research.md`](./research.md) (D1–D10; all unknowns resolved;
  ground truth read from `federal_scapia.py`; the port **verified against the real `kaname-core`
  helpers** on the pinned toolchain — every golden value reproduced, including the un-anchored
  `card_last4 "4836"`, the encoding-robust separator, and the `+`/fallback direction rule).
- **Phase 1 — Design & Contracts**: ✅ complete → [`data-model.md`](./data-model.md),
  [`contracts/engine-ffi.md`](./contracts/engine-ffi.md),
  [`contracts/golden-fixture.md`](./contracts/golden-fixture.md),
  [`quickstart.md`](./quickstart.md); agent context refreshed via
  `.specify/scripts/bash/update-agent-context.sh copilot`.
- **Phase 1 re-check (post-design Constitution Check)**: ✅ PASS — the design adds **no new
  dependency**, **no new shared helper**, and no new violation; the golden vector + the string-based
  `Decimal` fixture + the determinism/purity + dependency-audit gates actively **reinforce** the
  no-float-money, determinism, and privacy principles. The one in-reader direction rule is recorded in
  Complexity Tracking as a precedented (HDFC-monthly-style) choice, not a shared change.
- **Phase 2 — Tasks**: ⏭️ NOT done here. Run `/speckit.tasks` to generate `tasks.md`, ordered
  test-first per Principle V: write the golden fixture + failing parity `Case` row (+ `federal_claims`
  wrong-issuer test) → `statement/federal.rs` (single config + enrich = cycle + un-anchored last-4,
  mirroring `sbi.rs`/`yes.rs`, with the local `+`/fallback direction) → FFI exports
  (`read_federal_statement` + `federal_claims`) + `lib.rs` re-exports + `mod.rs` `pub mod federal;` →
  Swift bridge test → run the inherited privacy/iOS gates.
