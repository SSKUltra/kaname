# Implementation Plan: Reconcile a Credit-Card Statement Against Its Own Printed Totals On-Device — the Credit-Card Counterpart to the Shipped Bank-Ledger Balance-Chain; Completes the Ported Reconciliation Layer

**Branch**: `012-cc-reconciliation` | **Date**: 2026-07-19 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/012-cc-reconciliation/spec.md`
**Milestone**: P2 (engine port) — the **credit-card counterpart** of the already-shipped bank-ledger balance-chain integrity check, and the **last remaining piece** of the web engine's per-statement reconciliation layer

## Summary

Port the web engine's per-statement **credit-card reconciliation** (`reconciliation.py`) into
`kaname-core` (Rust) as a **pure, deterministic** check over the shared `ParsedStatement`, exactly
mirroring the already-shipped bank-ledger **balance-chain** check (`balance_chain.rs`). After the app
reads a credit-card statement, the check tells a person whether the transactions the engine extracted
**actually add up to what the statement itself claims** — catching a mis-parse or a dropped row **before
the data is trusted**. It reuses the shared statement/transaction types, the exact-decimal money type,
the golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate, and adds **no new
runtime OR dev dependency** and **no new shared engine helper** beyond the check itself and two
printed-total fields.

The check computes, over **all** read rows using exact `Decimal` money, the sum of the **DEBIT** rows
(`read_debits`) and the **CREDIT** rows (`read_credits`) and reconciles them in **three tiers** (the
pinned web-engine ladder), returning a verdict plus a typed **audit detail**:

1. **Primary** — if the statement carries **at least one** printed per-statement total
   (`printed_total_debits` and/or `printed_total_credits`), each **present** total is compared to its
   read sum within a **₹1.00** tolerance; **RECONCILED** iff every present total is within tolerance,
   else **NEEDS_REVIEW**. The opening→closing fallback is **never** consulted when any printed total is
   present.
2. **Fallback** — else if **both** a printed opening **and** a printed closing balance are present,
   compare the read balance change (`read_debits − read_credits`) to the printed change
   (`closing − opening`) within the same ₹1.00 tolerance → **RECONCILED / NEEDS_REVIEW**.
3. **Neutral** — else, a neutral **"not reconciled (no balance)"** outcome that is **explicitly
   distinct** from NEEDS_REVIEW (a statement whose totals could not be extracted is an *unknown*, never
   a *mismatch*), carrying the reason `"no printed totals extracted"`.

In every case **all read rows are retained** — reconciliation is a read-only trust signal that never
drops, mutates, or reorders a transaction.

To make the primary check fire on real reader output, this slice also **surfaces the printed
debit/credit totals** from the **two** credit-card readers that print them — **Yes Bank / Kiwi**
(`yes.rs`) and **IOB** (`iob.rs`) — lifting the deliberate `printed_total_*` carve-out those readers
currently carry (slices `005`/`011`). The **other four** card readers (ICICI, HDFC, SBI,
Federal/Scapia) print no such totals and therefore correctly produce the **neutral** outcome — behaviour
this slice **verifies**, not a gap to fill.

**This slice is the credit-card analogue of `balance_chain` and slots into the same seams.** It is
delivered as: **one new check module** (`statement/reconcile.rs` — `ReconcileStatus` enum +
`ReconcileResult` record + `reconcile(&ParsedStatement)`), **two new fields** on `ParsedStatement`
(`printed_total_debits` / `printed_total_credits: Option<Decimal>`), **two reader enrichments** (Yes +
IOB), **golden-fixture extensions** (the Yes/IOB vectors + a no-totals neutral vector reusing ICICI),
**one bridge export** (`reconcile_statement`, mirroring `check_balance_chain`), **the parity cases**,
and **a Swift bridge test** — with **no new dependency** and **no other shared-engine change**.

**Two deliberate design decisions** distinguish this from a naïve full port:

1. **Three-way outcome as `status: Option<ReconcileStatus>`.** The web engine returns
   `RECONCILED` / `NEEDS_REVIEW` / a neutral `None`. The Rust check mirrors that precisely with a
   **two-variant** `ReconcileStatus { Reconciled, NeedsReview }` carried as `Option<ReconcileStatus>` in
   the result — **`None` is the neutral "no balance" outcome**, structurally impossible to conflate with
   `Some(NeedsReview)` (FR-004, US3, SC-006). See D2 in [`research.md`](./research.md).
2. **`printed_total_spend` is NOT ported.** The web `ParsedStatement` also carries a
   `printed_total_spend`, but **reconciliation never reads it**; adding it would ship a field with no
   consumer. Consistent with `base.rs`'s "only the fields this slice needs" doctrine, this slice adds
   **only** `printed_total_debits` / `printed_total_credits` (the two totals the check compares). See D9
   + the Complexity Tracking note.

**Technical approach** (details in [`research.md`](./research.md); the web engine is the source of
truth — `reconciliation.py`, `test_reconciliation.py`, `test_statement_reconciliation.py`, `yes_kiwi.py`
and `iob.py` were read as ground truth and the three new regexes were **verified against the real
`regex`/`rust_decimal` crates** before writing this plan):

- **New check module** `statement/reconcile.rs`, structured **identically to `balance_chain.rs`**:
  - `pub enum ReconcileStatus { Reconciled, NeedsReview }` — `#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]`.
  - `pub struct ReconcileResult` — `#[derive(Debug, Clone, PartialEq, uniffi::Record)]` with **typed
    fields mirroring the web `detail` dict** (the same pattern `ChainResult` uses instead of a dynamic
    dict): `status: Option<ReconcileStatus>`; `read_debits: Decimal`, `read_credits: Decimal` (always
    set); `printed_debits: Option<Decimal>`, `printed_credits: Option<Decimal>` (primary path);
    `expected_balance_change: Option<Decimal>`, `computed_balance_change: Option<Decimal>` (fallback
    path); `reason: Option<String>` (neutral path → `Some("no printed totals extracted")`).
  - `pub fn reconcile(statement: &ParsedStatement) -> ReconcileResult` — `tolerance = Decimal::new(100,
    2)` (= 1.00, the same constant `balance_chain` uses); `read_debits`/`read_credits` are `Σ line.amount`
    by `line.direction`; then the three-tier ladder above. **Unit tests** mirror `test_reconciliation.py`
    plus the spec's edge cases (tolerance boundary, one-total-present, both-present-one-mismatch,
    primary-over-fallback, only-one-balance→neutral, empty-rows→0.00).
- **`ParsedStatement` gains two fields** (`base.rs`) after `printed_closing_balance`, both
  `Option<Decimal>`, defaulting to `None` in `ParsedStatement::new`:
  `printed_total_debits` / `printed_total_credits`. The module doc-comment (which currently says the
  reconciliation `printed_*` totals "arrive with a later slice") is updated — that later slice is now.
  **`printed_total_spend` is deliberately not added** (D9).
- **Yes reader enrichment** (`yes.rs`) — two new `LazyLock<Regex>` statics ported from `yes_kiwi.py`
  and populated in `enrich` (a present total is surfaced only when its label and value are on the same
  extracted line; else left absent):
  - `DEBITS_RE = (?i)Purchases[^\n]*?Rs\.?\s*([\d,]+\.\d{2})\s*Dr`
  - `CREDITS_RE = (?i)Payment\s*&?\s*Credits Received[^\n]*?Rs\.?\s*([\d,]+\.\d{2})\s*Cr`
  The module-doc carve-out paragraph ("printed totals … intentionally not ported") is rewritten to
  "surfaced for reconciliation". A reader unit test asserts the totals on the extended sample.
- **IOB reader enrichment** (`iob.rs`) — one new `LazyLock<Regex>` static ported from `iob.py`
  `_SUMMARY_RE` (`IGNORECASE|DOTALL` → `(?is)`), setting `printed_total_credits` from group `credits`
  and `printed_total_debits` from group `debits`:
  - `SUMMARY_RE = (?is)ACCOUNT SUMMARY\b.*?(?P<prev>[\d,]+(?:\.\d+)?)\s+(?P<credits>[\d,]+\.\d{2})\s+(?P<debits>[\d,]+\.\d{2})\s+(?P<fees>[\d,]+(?:\.\d+)?)\s+(?P<total>[\d,]+(?:\.\d+)?)`
  The module-doc carve-out paragraph is rewritten. A reader unit test asserts the totals (the existing
  fixture `full_text` already carries the `ACCOUNT SUMMARY` block).
- **Wiring**: `statement/mod.rs` gains `pub mod reconcile;` (kept near `polarity`/`sbi`). `ffi.rs` gains
  `#[uniffi::export] pub fn reconcile_statement(statement: ParsedStatement) -> ReconcileResult {
  reconcile(&statement) }` (with `use crate::statement::reconcile::{reconcile, ReconcileResult};`),
  mirroring `check_balance_chain`. `lib.rs` adds `reconcile_statement` to the `pub use ffi::{…}` list and
  `pub use statement::reconcile::{ReconcileResult, ReconcileStatus};`.
- **Fixtures**: `fixtures/yes/credit_card/basic.json` — extend `full_text` with two lines after
  "Statement Period:" (`Current Purchases / Cash Advance & Other Charges : Rs. 100.00 Dr` and
  `Payment & Credits Received : Rs. 9,000.00 Cr`) and add `printed_total_debits: "100.00"` /
  `printed_total_credits: "9000.00"` to `expected` (rows/period/last4 unchanged; `_comment` updated).
  `fixtures/iob/credit_card/basic.json` — **no `full_text` change** (it already carries the `ACCOUNT
  SUMMARY` block); add `printed_total_debits: "3500.00"` / `printed_total_credits: "1000.00"` to
  `expected` (`_comment` updated).
- **Parity harness** (`tests/parity.rs`) — extend `Expected` with `#[serde(default)]
  printed_total_debits: Option<String>` / `printed_total_credits: Option<String>` and assert them in
  `assert_matches_expected` via the existing `parse_dec` (all other CC fixtures omit them → `None`,
  unchanged). Add reconcile parity tests using `reconcile_statement` + `ReconcileStatus`:
  `yes_statement_reconciles`, `iob_statement_reconciles`, and
  `statement_without_printed_totals_is_neutral` (loads `icici/credit_card/basic.json` → `status == None`,
  `reason == Some("no printed totals extracted")`).
- **Swift bridge test** — new `ios/Tests/ReconcileTests.swift` (Swift Testing) exercising
  `reconcileStatement(statement:)`: a read Yes statement → `.status == .reconciled` with printed totals
  surfaced; an IOB statement → `.reconciled`; an ICICI statement (no totals) → `.status == nil`
  (neutral). `status` surfaces as `ReconcileStatus?`. Requires `make core-xcframework` **before**
  `tuist generate`.
- **Verified before writing this plan** (throwaway test against the **real** `regex`/`rust_decimal`
  crates, then removed — repo left clean): the three new regexes extract the locked ground truth from
  the exact fixture `full_text` — YES `debits=100.00` / `credits=9000.00`; IOB `credits=1000.00` /
  `debits=3500.00` (with `prev=345.50`, `fees=0`, `total=2,845.50`). The current core suite is green
  (**63 unit + 13 parity tests**). Evidence in [`research.md`](./research.md) (D4/D10/D11 + Verification
  harness).

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.**
**Storage**: N/A (no persistence this slice; persisting the verdict / encrypted SQLite is explicitly out of scope)
**Testing**: `cargo test` (`reconcile.rs` + reader unit tests; `tests/parity.rs` golden harness — extended Yes/IOB vectors + three reconcile parity tests + determinism); **Swift Testing** (`import KanameCore`) for a "core ↔ Swift reconcile" bridge test
**Target Platform**: iOS 18+ (device `aarch64-apple-ios`; simulator `aarch64-apple-ios-sim` + `x86_64-apple-ios`); core is platform-agnostic
**Project Type**: Mobile — Rust core + native SwiftUI app (monorepo `core/` + `ios/`)
**Performance Goals**: reconcile is a sub-millisecond pure function — two linear passes summing a handful of rows; no throughput target this slice
**Constraints**: 100% on-device, ZERO network in the reconcile path (FR-020/022, SC-016); deterministic (FR-018, SC-013); all money (`read_*` sums, printed totals, balances, changes, and the ₹1.00 tolerance) is `Decimal`, never `f64` (FR-017, SC-012); direction is read from each row's already-decided `Dr`/`Cr` marker, never re-derived from an amount's sign (FR-002); the neutral outcome MUST NOT equal NEEDS_REVIEW (FR-004, SC-006); primary-over-fallback precedence (FR-005, SC-008); rows never dropped (FR-003, SC-009); Apache-2.0, no GPL/AGPL/LGPL, **no new deps** (FR-028)
**Scale/Scope**: 1 new check module (enum + record + `reconcile`); **2 new `ParsedStatement` fields**; **0 new shared helpers**; 2 reader enrichments (Yes + IOB); 1 bridge export (`reconcile_statement`); 2 fixtures extended + 1 no-totals vector reused; 1 harness `Expected` extension + 3 reconcile parity tests; 1 Swift bridge test; 0 new dependencies; no new app UI. **Completes the ported per-statement reconciliation layer.**

## Constitution Check

*GATE: evaluated before Phase 0 and re-checked after Phase 1. Constitution v1.0.0.*

| Principle / Gate | Verdict | Evidence & how this plan complies |
|---|---|---|
| **I. Data Privacy & Sovereignty** (NON-NEGOTIABLE) — free/core = 100% on-device, zero network, no telemetry | ✅ PASS | The reconcile path is pure Rust over an in-memory `ParsedStatement` — summing rows and comparing `Decimal`s; no sockets, HTTP, async runtime, or file/PDF I/O (FR-020). It **inherits the existing privacy-egress gate** (`make core-privacy-audit`) unchanged, and adds **no dependency at all** (see III), so the shipped `cargo tree -e normal` graph is byte-identical. The determinism/parity harness now also covers the reconcile verdict (FR-018/022, SC-013/016). No telemetry/analytics/crash reporter added (FR-021). |
| **II. Local-First Shared Engine** — pure, deterministic, platform-agnostic Rust core via UniFFI; money never float; explicit polarity; no PDF engine in core | ✅ PASS | `reconcile` is a **pure function over the shared `ParsedStatement`** returning a typed result — the exact shape of the shipped `check_balance_chain` (FR-016/019). It never opens a PDF (text is pre-extracted; FR-018). All money — `read_debits`/`read_credits`, printed totals, opening/closing balances, expected/computed change, and the `Decimal::new(100, 2)` tolerance — is `rust_decimal::Decimal`, **never `f64`** (FR-017, SC-012). Direction is read from each row's **already-decided** `Dr`/`Cr` marker (`line.direction`), never re-derived from an amount's sign (FR-002). **No new shared helper** — the sums, the tolerance idiom, and the two-field extension all reuse existing types (FR-016, SC-017). |
| **III. Open-Core & Permissive Licensing** — client Apache-2.0; GPL/AGPL/LGPL forbidden; no secrets | ✅ PASS | No secrets/keys/endpoints (FR-028). **NO new runtime OR dev dependency** — reconcile is built entirely from crates already in the graph (`regex`, `rust_decimal` for the check; the two new reader regexes reuse `regex`; `serde_json` dev-only harness). Nothing copyleft enters the tree; the privacy audit's `cargo tree` surface re-confirms it (SC-018). |
| **IV. Native Experience & Accessibility** — latest HIG, SwiftUI, Dynamic Type, Dark Mode, VoiceOver | ✅ PASS (N/A UI) | This is an **engine + bridge + tests slice with no new user-facing surface** — surfacing the verdict in the app (a "needs review" indicator, an audit-detail view) is a later, native step (spec Out of Scope). The only app-side artifact is the `ReconcileTests.swift` Swift Testing suite. If a demo surface is later added it MUST follow HIG + a11y (FR-030); none is added here. |
| **V. Test-First & Parity** — failing test precedes behaviour; `cargo test` + Swift Testing; privacy-egress test | ✅ PASS | **Golden-fixture parity**: the web engine's reconciliation is the pinned source of truth (`reconciliation.py` + `test_reconciliation.py` + `test_statement_reconciliation.py`); the three verdicts are reproduced exactly by `tests/parity.rs` (RECONCILED for the extended Yes/IOB vectors; neutral for a no-totals ICICI vector) plus `reconcile.rs` unit tests covering the mismatch, tolerance boundary, one-total, both-present-one-mismatch, fallback, primary-over-fallback, only-one-balance, and empty-rows cases (FR-023/024, SC-001/014). **Test-first**: the failing golden/parity tests precede the behaviour (FR-027). Core via `cargo test`; the bridge via the "core ↔ Swift reconcile" suite (FR-019, SC-015). Privacy-egress + determinism guards extended to reconcile. All fixture data is **synthetic/redacted** (FR-026). |
| **Scope decision — `printed_total_spend` NOT ported** (Principle II shape discipline; plan Summary/D9) | ✅ PASS | The web `ParsedStatement` carries a `printed_total_spend`, but **reconciliation never reads it**; per `base.rs`'s "only the fields this slice needs" doctrine, this slice adds **only** the two totals the check compares (`printed_total_debits` / `printed_total_credits`). A deliberate scope *reduction* (fewer fields than the source), recorded in Complexity Tracking for visibility — not a violation. |
| **iOS Local Verification Gate** — cargo fmt/clippy/test; swiftlint + swift-format; tuist generate; simulator build+test | ✅ PASS | Ordering **unchanged**: `make core-xcframework` runs **before** `tuist generate` (Makefile `ios-gen: core-xcframework`; CI builds the xcframework first). The one new export + the two new records/enum are purely additive to the bindings (a new `ReconcileResult`/`ReconcileStatus` Swift type; the `ParsedStatement` record gains two optional fields). `macos-15` stays pinned for the iOS job; the **iPhone 16** simulator (`OS=latest`) is the `xcodebuild` destination; the core (ubuntu) job's privacy audit is inherited (FR-029). **swift-format `[Spacing]`**: `ReconcileTests.swift` keeps comments on their own line (no trailing inline `//` after code). |
| **Security & Privacy Constraints** — no network SDKs in core paths; deps reviewed & justified; synthetic fixtures; no committed secrets | ✅ PASS | No network SDK anywhere; the audit proves it structurally and **no dependency review is needed** (no new dep). All fixture data is **synthetic/redacted** — fabricated merchants/amounts, masked PANs `3561XXXXXXXX6686` / `123456XXXXXX0042`, and synthetic printed totals (FR-026). No secrets; `.env*` remain ignored. |

**Initial gate result: PASS** — **zero new dependencies, zero new shared helpers**, zero unjustified
violations. The one scope decision (`printed_total_spend` excluded) is a deliberate, doctrine-consistent
reduction, recorded in Complexity Tracking for visibility, not a violation. No NEEDS CLARIFICATION
remain — the approach is locked by the requester and confirmed with a verification run of the three new
regexes against the real crates (see `research.md`). Cleared to Phase 0/1.

## Project Structure

### Documentation (this feature)

```text
specs/012-cc-reconciliation/
├── plan.md                  # This file (/speckit.plan)
├── research.md              # Phase 0 — decisions D1–D14 (all unknowns resolved, with verified evidence)
├── data-model.md            # Phase 1 — the new check module + two ParsedStatement fields, reused records, harness extension
├── contracts/
│   ├── engine-ffi.md        # Phase 1 — the additive UniFFI Swift boundary (reconcile_statement, ReconcileResult/ReconcileStatus, two new fields)
│   ├── reconcile.md         # Phase 1 — the reconcile check behaviour contract (three tiers, tolerance, precedence, neutral, audit detail)
│   └── golden-fixture.md    # Phase 1 — extended Yes/IOB vectors + the no-totals neutral vector + reconcile parity cases
├── quickstart.md            # Phase 1 — build, verify, run the parity + privacy gates; the bridge test
├── checklists/              # (pre-existing) spec-quality checklist(s)
└── tasks.md                 # Phase 2 — created by /speckit.tasks (NOT here)
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── Cargo.toml                        # UNCHANGED — no new dependency (runtime or dev)
├── uniffi.toml                       # UNCHANGED — Decimal → Foundation.Decimal map reused
├── src/
│   ├── lib.rs                        # + re-export reconcile_statement; + pub use statement::reconcile::{ReconcileResult, ReconcileStatus}
│   ├── model.rs                      # UNCHANGED — Direction (uniffi::Enum) reused for the row sums
│   ├── ffi.rs                        # + #[uniffi::export] reconcile_statement (mirrors check_balance_chain; custom types reused)
│   ├── statement/
│   │   ├── mod.rs                    # + pub mod reconcile; (near polarity/sbi)
│   │   ├── base.rs                   # EDIT — ParsedStatement gains printed_total_debits/printed_total_credits: Option<Decimal> (default None); module doc updated; NO printed_total_spend
│   │   ├── balance_chain.rs          # UNCHANGED — the bank-ledger counterpart this check mirrors
│   │   ├── common.rs                 # UNCHANGED — parse_amount reused by the two reader regexes
│   │   ├── polarity.rs               # UNCHANGED
│   │   ├── line_reader.rs            # UNCHANGED — reader seam reused verbatim
│   │   ├── yes.rs                    # EDIT — + DEBITS_RE/CREDITS_RE statics; enrich sets printed totals; module doc rewritten; + reader unit test
│   │   ├── iob.rs                    # EDIT — + SUMMARY_RE static; enrich sets printed totals; module doc rewritten; + reader unit test
│   │   └── reconcile.rs              # NEW — ReconcileStatus + ReconcileResult + reconcile(&ParsedStatement); unit tests (mirrors balance_chain.rs)
│   └── bin/uniffi-bindgen.rs         # UNCHANGED
└── tests/
    └── parity.rs                     # EDIT — Expected gains printed_total_* (serde default) + asserts them; + 3 reconcile parity tests; NO other schema change

fixtures/
├── yes/credit_card/
│   └── basic.json                    # EDIT — full_text + 2 printed-total lines; expected + printed_total_debits "100.00" / printed_total_credits "9000.00"; _comment updated
└── iob/credit_card/
    └── basic.json                    # EDIT — expected + printed_total_debits "3500.00" / printed_total_credits "1000.00" (NO full_text change); _comment updated
# fixtures/icici/credit_card/basic.json — UNCHANGED (reused as the no-totals neutral vector)

ios/Tests/
└── ReconcileTests.swift              # NEW — "core ↔ Swift reconcile" Swift Testing suite (reconciled / neutral / totals surfaced)

Makefile                              # UNCHANGED — reconcile inherits core-test / core-privacy-audit / ios-test
.github/workflows/ci.yml              # UNCHANGED — reconcile inherits the core + iOS gates
```

**Structure Decision**: Keep the **monorepo mobile** layout (`core/` Rust + `ios/` SwiftUI) and the
`statement/` module that mirrors the web engine 1:1 — `reconciliation.py → statement/reconcile.rs`,
placed **beside its counterpart `balance_chain.rs`** — so the port is a mechanical, reviewable diff and
the two per-statement trust signals (bank-ledger + credit-card) live side by side. The check is a
**pure function over the shared `ParsedStatement`**, exported over the existing UniFFI bridge exactly as
`check_balance_chain` is; the reader logic (the two enrichments) stays in `yes.rs`/`iob.rs` and is
FFI-free and unit-testable, with `ffi.rs` wiring only the one new export. The `ParsedStatement` record
gains **two** optional fields (the totals the check compares); **`printed_total_spend` is deliberately
excluded** (no consumer). Generated Swift + `KanameCoreFFI.xcframework` remain git-ignored artifacts
rebuilt by `make core-xcframework` (before `tuist generate`).

## Complexity Tracking

> **No constitution violations.** Reconciliation adds **no new dependency**, **no new shared helper**,
> and **no new project structure** — it is the credit-card analogue of the shipped `balance_chain` and
> slots into the same seams (the shared `ParsedStatement`, the parity harness, the UniFFI bridge, the
> privacy gate). Three items are worth recording for visibility — the first is a deliberate scope
> *decision*, the other two are new-but-minimal, spec-mandated additions.

| Item | Why (in scope this slice) | Why the alternative is rejected |
|---|---|---|
| **`printed_total_spend` NOT ported** (present on the web `ParsedStatement`) | Reconciliation **never reads** `printed_total_spend`; `base.rs` ports **only the fields this slice needs**. Adding only `printed_total_debits` / `printed_total_credits` keeps the model minimal and matches the two values the check compares (plan Summary, D9). | Porting it (naïve faithfulness) would add a field with **no consumer** — dead surface that invites future misuse and diverges from the "only fields this slice needs" doctrine. It can be added by the slice that actually needs it. |
| **Two new `ParsedStatement` fields** (`printed_total_debits` / `printed_total_credits: Option<Decimal>`) | Required by FR-011 — the primary check compares the read sums against the issuer's **printed** totals, and those totals must live on the shared model. Defaulted to `None` in `ParsedStatement::new`, so all ten readers and every existing fixture are unaffected; only Yes + IOB populate them. | Threading the totals as a separate side-channel would fragment the parsed-statement model and complicate the bridge/parity harness. Two `Option<Decimal>` fields (mirroring the existing `printed_opening/closing_balance`) is the minimal, consistent extension. |
| **New `ReconcileStatus` enum + `ReconcileResult` record** | The check must return a three-way verdict + a typed audit detail across the UniFFI bridge — the exact `ChainStatus` / `ChainResult` shape the shipped balance-chain uses (FR-001/010/016/019). `status: Option<ReconcileStatus>` encodes the neutral outcome as `None`, distinct from `Some(NeedsReview)` (FR-004). | A dynamic `detail` dict (as the web engine uses) does not cross UniFFI cleanly and loses type safety; a three-variant enum would fold the neutral "unknown" into the same space as the two real verdicts, blurring FR-004's hard distinction. The `Option<two-variant>` + typed record is the shipped, proven pattern. |

## Phase status

- **Phase 0 — Research**: ✅ complete → [`research.md`](./research.md) (D1–D14; all unknowns resolved;
  ground truth read from `reconciliation.py`/`test_reconciliation.py`/`yes_kiwi.py`/`iob.py`; the three
  new regexes **verified against the real `regex`/`rust_decimal` crates** — YES `100.00`/`9000.00`, IOB
  `3500.00`/`1000.00`; core suite green at 63 unit + 13 parity tests).
- **Phase 1 — Design & Contracts**: ✅ complete → [`data-model.md`](./data-model.md),
  [`contracts/engine-ffi.md`](./contracts/engine-ffi.md), [`contracts/reconcile.md`](./contracts/reconcile.md),
  [`contracts/golden-fixture.md`](./contracts/golden-fixture.md), [`quickstart.md`](./quickstart.md);
  agent context refreshed via `.specify/scripts/bash/update-agent-context.sh copilot`.
- **Phase 1 re-check (post-design Constitution Check)**: ✅ PASS — the design adds **no new
  dependency** and **no new shared helper**; the golden verdicts + the string-based `Decimal` fixtures +
  the determinism/purity + dependency-audit gates actively **reinforce** the no-float-money,
  determinism, and privacy principles. The one scope decision (`printed_total_spend` excluded) is
  recorded in Complexity Tracking as a deliberate reduction.
- **Phase 2 — Tasks**: ⏭️ NOT done here. Run `/speckit.tasks` to generate `tasks.md`, ordered
  test-first per Principle V: extend the Yes/IOB fixtures + `Expected` (printed totals) and add the
  failing reconcile parity tests (RECONCILED ×2 + neutral) → `statement/reconcile.rs` (enum + record +
  `reconcile`, mirroring `balance_chain.rs`) + its unit tests → the two `ParsedStatement` fields
  (`base.rs`) → the Yes + IOB `enrich` regexes + reader unit tests → `mod.rs` `pub mod reconcile;`, the
  `reconcile_statement` FFI export + `lib.rs` re-exports → the Swift bridge test → run the inherited
  privacy/iOS gates.
