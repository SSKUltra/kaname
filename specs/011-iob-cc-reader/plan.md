# Implementation Plan: Import an Indian Overseas Bank (IOB) Credit-Card Statement On-Device (Sixth & Final Credit-Card Parser, Zero New Engine Infrastructure; Corrects IOB Miscategorization)

**Branch**: `011-iob-cc-reader` | **Date**: 2026-07-17 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/011-iob-cc-reader/spec.md`
**Milestone**: P2 (final credit-card slice) — the **sixth and last** credit-card statement parser, completing the full set of **ten** statement readers (6 credit-card + 4 bank-account)

## Summary

Port the web engine's **Indian Overseas Bank (IOB)** credit-card reader into `kaname-core` (Rust) as a
**pure, deterministic** parse that turns already-extracted text lines + full text into a
`ParsedStatement`. IOB is a **clean single-layout** reader — one row shape
`DD-MON-YYYY <merchant> <amount> Dr|Cr` (a day-first date with an **uppercase** three-letter month,
description, amount, and a **terminal two-letter `Dr`/`Cr` direction marker**) — that drops straight
into the existing `read_lines(&cfg, lines, full_text)` seam, exactly like SBI's `read_sbi_statement`
and Yes's `read_yes_statement`.

This slice is the **third clean single-layout drop-in after SBI and Yes**, and it **reuses — and adds
nothing to** — the shared engine infrastructure. Like SBI (`004`) and Yes (`005`), **IOB adds no new
shared helper at all**. Its `DD-MON-YYYY` date with an uppercase month (e.g. `31-MAR-2026`) is parsed
by the shared date parser's **already-present, case-insensitive** `%d-%b-%Y` format (`common.rs:28` —
`chrono`'s `%b` month table is case-insensitive, so uppercase `MAR`/`APR` parse), and its two-letter
`Dr`/`Cr` markers are **already** in the shared polarity tables (`normalise_marker` strips to
`DR`/`CR`; `CR_MARKERS` contains `"CR"`, `DR_MARKERS` contains `"DR"` — `polarity.rs:11–12`). IOB is
therefore delivered as: **one new reader config** (`statement/iob.rs`), **two FFI exports**
(`read_iob_statement` + `iob_claims`, mirroring SBI/Yes/Federal), **one golden fixture**, **one parity
`Case` row** (+ a claims accept/reject test), and **two roadmap-doc corrections** — with **no new
dependency** (runtime *or* dev) and **no change** to any shared helper, record, seam, or the harness
schema. Landing IOB **completes the planned set of six credit-card readers** and, with the four
bank-account readers, **all ten statement readers**.

**Two deliberate scope decisions** distinguish this port from a naïve full port:

1. **Reconciliation carve-out (mirrors Yes).** The web engine's IOB `_enrich` *also* scrapes the
   `ACCOUNT SUMMARY` block's **printed** per-statement `Payment / Credits` and `Purchases / Debits`
   totals (`_SUMMARY_RE` → `printed_total_credits` / `printed_total_debits`) for a future
   reconciliation feature. Those printed-total fields are **intentionally not ported** — they are
   **not** in the Rust `ParsedStatement`, and the IOB `enrich` here is **only billing-cycle end +
   last-4** (FR-013, US5, SC-013). This keeps IOB identically shaped to the landed
   ICICI/HDFC/SBI/Yes/Federal credit-card readers (none expose printed totals) and draws a clean
   boundary for the later reconciliation slice. See D10 in [`research.md`](./research.md) and the
   Complexity Tracking note.
2. **No `period_start` (IOB prints no period range).** Unlike SBI/Yes (which read a `<from> to <to>`
   range and populate both ends), IOB prints only a single `Stmt Date : 20-APR-2026`. The engine uses
   it as the billing-cycle **end** (`period_end`) and leaves `period_start` **unset** (never
   fabricated) — a faithful port of `iob.py`, whose `_enrich` sets only `period_end` (FR-010, US4). See
   D6.

This slice also carries a **documentation correction in scope**: `docs/HANDOFF.md` and
`docs/kaname-ios-plan.md` currently list IOB (`iob.py` / `iob`) under the **bank-account** readers. IOB
is a **credit-card** reader (line-based, `account_kind="credit_card"`, no ledger reader), so this slice
**moves IOB to the credit-card list and removes it from the bank-account list in both files** (FR-014,
FR-015, US6, SC-014) — leaving the inventory consistent at six credit-card + four bank-account readers.

**Technical approach** (details in [`research.md`](./research.md); the web engine is the source of
truth — `iob.py` was **read as ground truth**, and the two IOB-specific behaviours were **verified
against the real `kaname-core` helpers** before writing this plan):

- **Port faithfully** from
  `finance-tracker-phase/backend/app/services/ingestion/statement_readers/iob.py` → new
  `statement/iob.rs`. One **zero-sized** `IobReader` implements the existing `LineReaderConfig` trait,
  structured **identically to `yes.rs`/`sbi.rs`**: `bank_code()`, `claim_markers()`, `row_re()` (via
  `LazyLock`), `direction()` = `classify(desc, dir, None)`, and a free `enrich()`. **`BANK_CODE =
  "IOB"`**; **claim markers** `("INDIAN OVERSEAS BANK", "iobnet.co.in")` (two markers). A module comment
  records the reconciliation carve-out (mirroring `yes.rs`).
- **Reuse the landed foundations as-is**: the `read_lines`/`claims` seam (`line_reader.rs`), the
  `ParsedStatement`/`ParsedTransaction` records (`base.rs`), `parse_amount`/`parse_date`/**`find_last4(text,
  Some("Credit Card Number"))`** (`common.rs`), `polarity::classify` (`polarity.rs`), the parity
  harness (`tests/parity.rs`), and the UniFFI bridge (`ffi.rs` + `uniffi.toml`: `Decimal`/`NaiveDate`
  custom types + `Direction` enum). **No new dependency** (runtime *or* dev).
- **Row regex** (`LazyLock<Regex>`), ported byte-for-byte from `_ROW_RE`:
  `^(?P<date>\d{2}-[A-Za-z]{3}-\d{4})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>Dr|Cr)$`
  — the two-letter `Dr`/`Cr` marker sits **at the end**, anchored at `$`. Direction =
  `classify(desc, caps.name("dir"), None)` (the same `marker_direction` behaviour SBI/Yes use).
- **Enrich** (ported from `_enrich`, **minus** the reconciliation scrape): billing-cycle end from
  `STMT_DATE_RE = (?i)Stmt Date\s*:\s*(\d{2}-[A-Za-z]{3}-\d{4})` → `period_end = parse_date(g1)` (via
  the existing case-insensitive `%d-%b-%Y`); `card_last4 = find_last4(full_text, Some("Credit Card
  Number"))`. **`period_start` is left unset** (no range printed). **The `_SUMMARY_RE` printed-total
  lines are deliberately NOT ported** (D10; FR-013).
- **One golden fixture** `fixtures/iob/credit_card/basic.json`, **ported** from the web
  characterization vector, pinned byte-for-byte by **one new `Case` row** in `tests/parity.rs` calling
  `read_iob_statement` (placed with the credit-card cases). The harness needs **no code/schema change**
  — `period_start` is `#[serde(default)]` (added by HDFC), so a fixture that **omits** it deserializes
  to `None`, exactly as the ICICI vector already does.
- **Two roadmap-doc edits** (`docs/HANDOFF.md`, `docs/kaname-ios-plan.md`) move IOB from the
  bank-account list to the credit-card list — doc-only, no build/test impact (FR-014/015).
- **Verified before writing this plan** (throwaway integration test against the **real** `kaname-core`
  helpers on the pinned stable toolchain, then removed): the shared `parse_date` reads the uppercase
  months (`31-MAR-2026 → 2026-03-31`, `04-APR-2026 → 2026-04-04`, `20-APR-2026 → 2026-04-20`) with the
  existing `%d-%b-%Y`, and `find_last4(full_text, Some("Credit Card Number"))` returns **`"0042"`** from
  the inline masked PAN `123456XXXXXX0042` **without bleeding** digits from the adjacent limit figures
  `16000 25091.5`. The full core suite is green (60 unit + 12 parity tests). Evidence in
  [`research.md`](./research.md) (D3–D11 + Verification harness).

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.**
**Storage**: N/A (no persistence this slice; encrypted SQLite/SQLCipher is out of scope)
**Testing**: `cargo test` (unit + `tests/parity.rs` golden harness for the IOB vector + determinism + wrong-issuer `iob_claims`); **Swift Testing** (`import KanameCore`) for a "core ↔ Swift IOB parse" test
**Target Platform**: iOS 18+ (device `aarch64-apple-ios`; simulator `aarch64-apple-ios-sim` + `x86_64-apple-ios`); core is platform-agnostic
**Project Type**: Mobile — Rust core + native SwiftUI app (monorepo `core/` + `ios/`)
**Performance Goals**: parse is a sub-millisecond pure function over a handful of lines; single layout (one pass); no throughput target this slice
**Constraints**: 100% on-device, ZERO network in the parse path (FR-021/023, SC-009); deterministic (FR-018, SC-010); money is `Decimal`, never `f64` (FR-006/007); direction from the terminal `Dr`/`Cr` marker, never the amount's sign/magnitude or the description (FR-008/009, SC-005); Apache-2.0, no GPL/AGPL/LGPL, **no new deps** (FR-027); **printed-total reconciliation fields excluded** (FR-013, SC-013); **`period_start` left unset** (FR-010)
**Scale/Scope**: 1 new single-layout reader config; **0 new shared helpers**; 0 new records; 2 exported functions; 1 golden fixture + 1 harness `Case` row (**0 harness schema/code change**); 2 roadmap-doc corrections; 0 new dependencies; no new app UI. **Completes the 10-reader set (6 CC + 4 bank).**

## Constitution Check

*GATE: evaluated before Phase 0 and re-checked after Phase 1. Constitution v1.0.0.*

| Principle / Gate | Verdict | Evidence & how this plan complies |
|---|---|---|
| **I. Data Privacy & Sovereignty** (NON-NEGOTIABLE) — free/core = 100% on-device, zero network, no telemetry | ✅ PASS | The IOB parse path is pure Rust over an in-memory `Vec<String>` + `String` — no sockets, HTTP, async runtime, or file/PDF I/O (FR-017/021). It **inherits the existing privacy-egress gate** (`make core-privacy-audit`) unchanged; **no new dependency at all** (see III), so the shipped `cargo tree -e normal` graph is byte-identical. The determinism/purity parity test now also covers the IOB vector (FR-018, SC-009/010). No telemetry/analytics/crash reporter added (FR-022). |
| **II. Local-First Shared Engine** — pure, deterministic, platform-agnostic Rust core via UniFFI; money never float; explicit polarity; no PDF engine in core | ✅ PASS | IOB **reuses** the `read_lines` seam and never opens a PDF (FR-017). Determinism **verified** (the row/stmt-date regexes, `parse_date`, `find_last4`, `classify` are pure; `chrono`/`regex` are locale-independent). Amounts are `rust_decimal::Decimal`, scale preserved, never `f64` (FR-006/007, SC-006). Direction comes from the statement's **terminal `Dr`/`Cr` marker** via `classify(desc, dir, None)` — **never** the amount's sign/magnitude or the description's wording (FR-008/009, SC-005; the `Cr` 1000.00 refund is credit and the larger `Dr` 3500.00 purchase is debit). **No new shared helper is added** — the case-insensitive `%d-%b-%Y` format and `Dr`/`Cr` markers are already in the shared subsystem (FR-019, SC-012). |
| **III. Open-Core & Permissive Licensing** — client Apache-2.0; GPL/AGPL/LGPL forbidden; no secrets | ✅ PASS | No secrets/keys/endpoints (FR-027). **NO new runtime OR dev dependency** — IOB is built entirely from crates already in the graph (`regex`, `rust_decimal`, `chrono`, `serde`, `uniffi`; dev `serde_json`). Nothing copyleft enters the tree; the privacy audit's `cargo tree` surface re-confirms it. |
| **IV. Native Experience & Accessibility** — latest HIG, SwiftUI, Dynamic Type, Dark Mode, VoiceOver | ✅ PASS (N/A UI) | This is an **engine slice with no new user-facing surface** (app-side PDF import, file picker, Share Extension are explicitly out of scope — spec Out of Scope, FR-029 conditional). The only app-side artifact is an optional Swift Testing suite. If a demo surface is later added it MUST follow HIG + a11y; none is added here. |
| **V. Test-First & Parity** — failing test precedes behaviour; `cargo test` + Swift Testing; privacy-egress test | ✅ PASS | **Golden-fixture parity**: the web engine's synthetic IOB vector is **ported** (FR-024) and reproduced **exactly** by `tests/parity.rs` (SC-001/003/011). **Test-first**: the failing golden test (+ `iob_claims` wrong-issuer test) precedes the port (FR-026; tasks sequence red→green). Core via `cargo test`; the bridge via a "core ↔ Swift IOB parse" suite. Privacy-egress + determinism guards extended to IOB. All fixture data is **synthetic/redacted** (fabricated merchants, amounts, masked PAN `123456XXXXXX0042`) (FR-025). |
| **Scope carve-out — reconciliation excluded** (Principle II shape discipline; spec US5/FR-013/SC-013) | ✅ PASS | The web `_enrich` scrapes printed debit/credit totals (`_SUMMARY_RE`) into `printed_total_credits`/`printed_total_debits`. Those fields **do not exist** in the Rust `ParsedStatement` (`base.rs` ports only period + last-4; the `printed_*` totals "arrive with a later slice") and the IOB `enrich` **must not** add them. **Verified**: with the `ACCOUNT SUMMARY` printed-total lines present in `full_text`, the parse returns only rows + `period_end` + last-4 (no printed totals anywhere). This is a deliberate scope *reduction* (fewer fields than the source), not a violation — it keeps IOB identical in shape to the five landed credit-card readers. |
| **iOS Local Verification Gate** — cargo fmt/clippy/test; swiftlint + swift-format; tuist generate; simulator build+test | ✅ PASS | Ordering **unchanged**: `make core-xcframework` runs **before** `tuist generate` (Makefile `ios-gen: core-xcframework`; CI builds the xcframework first). The two new exports are purely additive to the bindings (records reused → no new Swift type). `macos-15` stays pinned for the iOS job; the **iPhone 16** simulator (`OS=latest`) is the `xcodebuild` destination; the core (ubuntu) job's privacy audit is inherited (FR-028). |
| **Security & Privacy Constraints** — no network SDKs in core paths; deps reviewed & justified; synthetic fixtures; no committed secrets | ✅ PASS | No network SDK anywhere; the audit proves it structurally and **no dependency review is needed** (no new dep). All fixture data is **synthetic/redacted** — fabricated merchants (`ExampleRefundMerchant`, `ExampleStorePurchase`), amounts, and a masked card number `123456XXXXXX0042` (FR-025, SC-004). No secrets; `.env*` remain ignored. |
| **Docs correction in scope** (spec US6/FR-014/FR-015/SC-014) | ✅ PASS | Moving IOB from the bank-account list to the credit-card list in `docs/HANDOFF.md` and `docs/kaname-ios-plan.md` makes the roadmap match reality (IOB is a `credit_card` line reader with no ledger reader). Doc-only, no code/build impact; independently verifiable by inspecting both files (six CC + four bank readers). |

**Initial gate result: PASS** — **zero new dependencies, zero new shared helpers, zero harness schema
change**, zero unjustified violations. The two scope decisions (printed-total reconciliation fields
excluded; `period_start` left unset) are deliberate, spec-mandated behaviours (US5/FR-013; US4/FR-010),
verified to produce output identical in shape to the landed readers — documented below in Complexity
Tracking for visibility, not because either is a violation. No NEEDS CLARIFICATION remain (the approach
is locked by the requester and confirmed with a verification build against the real `kaname-core`
helpers — see `research.md`). Cleared to Phase 0/1.

## Project Structure

### Documentation (this feature)

```text
specs/011-iob-cc-reader/
├── plan.md                  # This file (/speckit.plan)
├── research.md              # Phase 0 — decisions D1–D11 (all unknowns resolved, with evidence)
├── data-model.md            # Phase 1 — reused records, the single IOB config, reused helpers, harness row
├── contracts/
│   ├── engine-ffi.md        # Phase 1 — the additive UniFFI Swift boundary (read_iob_statement, iob_claims)
│   └── golden-fixture.md    # Phase 1 — the IOB vector (period_start omitted → None; card_last4 0042)
├── quickstart.md            # Phase 1 — build, verify, run the parity + privacy gates; the doc correction
├── checklists/              # (pre-existing) spec-quality checklist(s)
└── tasks.md                 # Phase 2 — created by /speckit.tasks (NOT here)
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── Cargo.toml                        # UNCHANGED — no new dependency (runtime or dev)
├── uniffi.toml                       # UNCHANGED — Decimal → Foundation.Decimal map reused
├── src/
│   ├── lib.rs                        # + re-export read_iob_statement, iob_claims
│   ├── model.rs                      # UNCHANGED — Direction (uniffi::Enum) reused
│   ├── ffi.rs                        # + #[uniffi::export] read_iob_statement, iob_claims (custom types reused)
│   ├── statement/
│   │   ├── mod.rs                    # + pub mod iob;
│   │   ├── base.rs                   # UNCHANGED — ParsedStatement/ParsedTransaction (NO printed_total_* fields)
│   │   ├── common.rs                 # UNCHANGED — parse_date "%d-%b-%Y" (case-insensitive %b) + find_last4 anchor path already present
│   │   ├── polarity.rs               # UNCHANGED — classify + CR/DR markers already include "CR"/"DR"
│   │   ├── line_reader.rs            # UNCHANGED — read_lines/claims seam reused verbatim
│   │   ├── sbi.rs                    # UNCHANGED
│   │   ├── yes.rs                    # UNCHANGED (the template mirrored)
│   │   └── iob.rs                    # NEW — IobReader (single config) + free enrich (period_end + last4 ONLY), structured like yes.rs
│   └── bin/uniffi-bindgen.rs         # UNCHANGED
└── tests/
    └── parity.rs                     # + 1 IOB Case row (with the CC cases) + iob_claims accept/reject test; NO schema change

fixtures/
└── iob/credit_card/
    └── basic.json                    # NEW — ported synthetic IOB vector (period_start omitted → None; card_last4 "0042")

ios/Tests/
└── IobParseTests.swift               # NEW — "core ↔ Swift IOB parse" (+ wrong-issuer) Swift Testing suite

docs/
├── HANDOFF.md                        # EDIT — move `iob.py` from the bank-account list to the credit-card list (FR-014)
└── kaname-ios-plan.md                # EDIT — move `iob` from the bank-account list to the credit-card list (FR-015)

Makefile                              # UNCHANGED — IOB inherits core-test / core-privacy-audit / ios-test
.github/workflows/ci.yml              # UNCHANGED — IOB inherits the core + iOS gates
```

**Structure Decision**: Keep the **monorepo mobile** layout (`core/` Rust + `ios/` SwiftUI) and the
`statement/` module that mirrors the web engine 1:1 — `iob.py → statement/iob.rs` — so the port is a
mechanical, reviewable diff. IOB introduces **no new record, no new shared helper, and no new
dependency**; the reader is a single zero-sized config that leans entirely on the existing seam and
helpers. The reader's `enrich` populates **only** `period_end` (from the lone `Stmt Date`) and
`card_last4` — `period_start` is left unset (no range printed), and the web reader's `printed_total_*`
scrape is deliberately dropped (FR-010/013). Exported FFI functions stay in `ffi.rs` (pure reader logic
stays FFI-free and unit-testable). Generated Swift + `KanameCoreFFI.xcframework` remain git-ignored
artifacts rebuilt by `make core-xcframework` (before `tuist generate`). The two doc edits are in
`docs/` and are independent of the build.

## Complexity Tracking

> **No constitution violations.** IOB adds **no new dependency**, **no new shared helper**, **no new
> record**, and **no harness schema/code change** — it is a pure single-layout drop-in reusing the
> seam, helpers, harness, bridge, and privacy gate that ICICI built and HDFC/SBI/Yes/Federal extended.
> Two items are worth recording for visibility — both are deliberate scope *decisions*, not added
> complexity or violations.

| Item | Why (in scope this slice) | Why the alternative is rejected |
|---|---|---|
| **Printed-total reconciliation fields NOT ported** (`printed_total_credits` / `printed_total_debits`, from the web `_SUMMARY_RE`) | The Rust `ParsedStatement` (`base.rs`) intentionally ports **only** the fields this milestone needs (rows + period + last-4); the five landed credit-card readers expose **no** printed totals. IOB's `enrich` therefore does **period_end + last-4 only** (FR-013, US5, SC-013). Mirrors the Yes carve-out exactly. | Porting the printed-total scrape would (a) add `ParsedStatement` fields no landed reader uses, (b) ship a **half-built reconciliation surface** with no consumer, and (c) break shape-parity with the other five credit-card readers. Reconciliation is a dedicated later slice; the totals belong there. Verified: with the `ACCOUNT SUMMARY` totals present, the IOB parse returns only rows + `period_end` + last-4. |
| **`period_start` left unset** (IOB prints no period range) | `iob.py` `_enrich` sets **only** `period_end` from the lone `Stmt Date`; there is no `<from> to <to>` range to read, so fabricating a start would be inventing data (FR-010, US4). The `ParsedStatement.period_start` field already exists (HDFC) and simply stays at its `None` default. | Deriving a start (e.g. `period_end − 1 month`) would fabricate metadata the statement does not print — a determinism/faithfulness violation. The fixture **omits** `period_start` (→ `None` via `#[serde(default)]`), structurally proving it is absent, exactly as the ICICI vector does. |

## Phase status

- **Phase 0 — Research**: ✅ complete → [`research.md`](./research.md) (D1–D11; all unknowns resolved;
  ground truth read from `iob.py`; the two IOB-specific behaviours — uppercase-month `%b` parsing and
  the inline masked-PAN `find_last4 "0042"` (no bleed) — **verified against the real `kaname-core`
  helpers** on the pinned toolchain; full suite green).
- **Phase 1 — Design & Contracts**: ✅ complete → [`data-model.md`](./data-model.md),
  [`contracts/engine-ffi.md`](./contracts/engine-ffi.md),
  [`contracts/golden-fixture.md`](./contracts/golden-fixture.md), [`quickstart.md`](./quickstart.md);
  agent context refreshed via `.specify/scripts/bash/update-agent-context.sh copilot`.
- **Phase 1 re-check (post-design Constitution Check)**: ✅ PASS — the design adds **no new
  dependency**, **no new shared helper**, and no new violation; the golden vector + the string-based
  `Decimal` fixture + the determinism/purity + dependency-audit gates actively **reinforce** the
  no-float-money, determinism, and privacy principles. The two scope decisions (reconciliation
  carve-out; `period_start` unset) are recorded in Complexity Tracking as deliberate reductions. The
  doc correction is doc-only and independently verifiable.
- **Phase 2 — Tasks**: ⏭️ NOT done here. Run `/speckit.tasks` to generate `tasks.md`, ordered
  test-first per Principle V: write the golden fixture + failing parity `Case` row (+ `iob_claims`
  wrong-issuer test) → `statement/iob.rs` (single config + free enrich = `period_end` + last-4,
  mirroring `yes.rs`) → FFI exports (`read_iob_statement` + `iob_claims`) + `lib.rs` re-exports +
  `mod.rs` `pub mod iob;` → Swift bridge test → the two roadmap-doc corrections → run the inherited
  privacy/iOS gates.
