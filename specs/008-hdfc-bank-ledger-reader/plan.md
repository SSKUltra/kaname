# Implementation Plan: Read an HDFC Bank (Savings/Current) Statement On-Device — the Second Balance-Ledger Reference Reader (HDFC Config on the Existing Ledger Base, Two Export Layouts)

**Branch**: `008-hdfc-bank-ledger-reader` | **Date**: 2026-07-16 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/008-hdfc-bank-ledger-reader/spec.md`
**Milestone**: P2 — the **second** bank-account (balance-ledger) reader, after the ICICI reference reader that landed the reusable base (slice 007)

## Summary

Add **HDFC savings/current** as the **second configuration** on the balance-ledger base that landed in slice 007
(`statement/ledger_reader.rs` + `statement/balance_chain.rs` + `statement/icici_bank.rs`). This is a
**config-on-an-existing-base** slice: the reusable base (anchor recognition against an **ordered** pattern
list, delta-derived direction, printed-amount-as-independent-check, narration stitching, row-1 bootstrap,
errored-vs-suspect) and the **balance-chain check**, the **parity harness**, and the **privacy-egress gate**
are **reused UNCHANGED**. HDFC contributes only its **per-issuer configuration** plus **two golden fixtures**.

HDFC is the **first** bank reader to exercise **two export layouts behind one reader**, selected by the base's
already-supported **first-match-wins ordered anchor list**:

1. **COMPACT** — `DD/MM/YY` (2-digit-year) rows ending `… <alphanumeric ref> <value-date DD/MM/YY> <amount>
   <balance>`; a single printed amount; the reference is captured as the `serial`; the opening balance comes
   from the **end-of-statement summary row**.
2. **DETAILED** — `DD/MM/YYYY` (4-digit-year) rows with explicit **Withdrawals**/**Deposits** columns (the
   empty side prints `0.00`) then the closing balance; an inline `Opening Balance : <amount>`.

The **only** genuinely new *shared* code is a tiny **`account_tail_last4(text, primary)`** helper factored into
`common.rs` (try a per-bank primary account regex → trailing 4; else the longest standalone ≥9-digit run →
trailing 4). `icici_bank.rs` is refactored to call it (behaviour-preserving; the ICICI golden fixture stays
GREEN). **Zero new dependencies; zero networking.**

This is a **determinism / parity** slice (Constitution Principle V): behaviours are ported faithfully from the
web engine (`hdfc_bank.py`) and the on-device engine must reproduce **two** reference ground truths
**byte-for-byte**, including the web-engine narration-stitching quirks. The platform boundary is unchanged:
**text extraction is native**; the Rust core **never opens a PDF**.

> ⚠️ **One open decision blocks a clean `/speckit.tasks`** — see [**Open Decisions**](#open-decisions-needs-your-sign-off)
> and research **[D8](./research.md)**. Empirical verification (Rust `regex`/`chrono` 0.4.45, against both ground
> truths) shows the shared `parse_date` order (`%d/%m/%Y` **before** `%d/%m/%y`) misparses the **compact**
> 2-digit-year dates as year **0026** (Rust `chrono`'s `%Y` greedily accepts 2 digits; Python's `%Y` requires 4,
> which is why the web ground truth is `2026-…`). The fix is a **one-line reorder** of `DATE_FORMATS` in
> `common.rs` — a **second, minimal, shared change** beyond the authorised `account_tail_last4`. It needs your
> sign-off because it widens the locked "one shared change" footprint. **Everything else is verified green.**

**Technical approach** (details in [`research.md`](./research.md); every value below confirmed against the
persisted ground truth `hdfc-bank-ground-truth.json` **and** an out-of-repo Rust `regex`+`chrono`+`rust_decimal`
replica of the base run over both fixtures — 63/63 assertions green with the date reorder applied):

- **Port faithfully** from
  `finance-tracker-phase/backend/app/services/ingestion/statement_readers/hdfc_bank.py` →
  `statement/hdfc_bank.rs`, mirroring `statement/icici_bank.rs` (the template). The module diff is mechanical.
- **One new shared helper** in `common.rs`: `pub fn account_tail_last4(text: &str, primary: &Regex) ->
  Option<String>` — `primary` capture group 1 → trailing 4; else the longest `\d{9,}` run → trailing 4 (moves
  the existing `last4` + `DIGIT_RUN_RE` fallback out of `icici_bank.rs`). **Refactor** `icici_bank.rs` to call
  it with ICICI's own primary regex `(?i)Account\s+(?:Number|No\.?)\s*:?\s*([0-9]{6,})` — behaviour-preserving
  (verified: `000401000123456 → 3456`). This is the **only** new shared code.
- **New reader** `statement/hdfc_bank.rs` — zero-sized `HdfcBankReader impl LedgerReaderConfig` with **two**
  anchors returned in order `[COMPACT, DETAILED]`:
  - COMPACT `^(?P<date>\d{2}/\d{2}/\d{2})\s+(?P<desc>.*?)\s+(?P<serial>[A-Za-z0-9]{6,})\s+\d{2}/\d{2}/\d{2}\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$`
  - DETAILED `^(?P<date>\d{2}/\d{2}/\d{4})\s+(?P<desc>.*?)\s+(?P<withdrawal>[\d,]+\.\d{2})\s+(?P<deposit>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$`
  - `BANK_CODE "HDFC"`; `claim_all ["HDFC"]`; `claim_any ["WithdrawalAmt","Savings Account Details","Statementof account"]`.
  - `opening_balance_re` `(?i)(?:Opening Balance\s*:\s*|OpeningBalance\b[^\n]*\n\s*)([\d,]+\.\d{2})` — matches
    **both** the detailed inline form **and** the compact end-summary form **across a newline** (group 1 in
    both alts). No `closing_balance_re`; no `column_split_x`.
  - `enrich` = period `(?i)From\s*:\s*(\d{2}/\d{2}/\d{4})\s+To\s*:?\s*(\d{2}/\d{2}/\d{4})` → `parse_date`;
    `card_last4 = account_tail_last4(full_text, HDFC_ACCOUNT_RE)` with `HDFC_ACCOUNT_RE`
    `(?i)Account\s*(?:Number|No\.?)\s*:?\s*X*([0-9]{4,})` (optional masked `X*` prefix, **4+** digits — differs
    from ICICI). Wire `mod.rs` (`pub mod hdfc_bank;`).
- **FFI** (`ffi.rs` + `lib.rs` re-exports) — add `read_hdfc_bank_statement(lines: Vec<String>, full_text:
  String, first_row_words: Vec<Word>) -> ParsedStatement` (wraps `read_ledger_lines(&HdfcBankReader, …)`) and
  `hdfc_bank_claims(full_text: String) -> bool` (wraps `claims_ledger(&HdfcBankReader, …, "HDFC")`). **Reuse**
  the already-exported `check_balance_chain`. No new types cross the FFI (all reused from slice 007). Rebuild
  via `make core-xcframework` **before** `tuist generate` (iOS gate ordering; iPhone 16 sim; macos-15 CI).
- **Parity harness** (`tests/parity.rs`) — **no schema change** (already extended in 007). Add a
  `parse_hdfc_bank` wrapper (calls `read_hdfc_bank_statement` with an empty `Vec<Word>`) and **two** `Case`
  rows (compact + detailed), plus a balance-chain test asserting `check_balance_chain(each HDFC fixture) ==
  Reconciled` (0 suspects, no row-1 fallback).
- **Two golden fixtures** under `fixtures/hdfc/bank_account/`: `compact.json` and `detailed.json` — both
  RECONCILED, period `2026-04-01 → 2026-04-30`, account last-4 `3425`, printed opening `100000.00` / closing
  `145000.00`, `errored []`. Narration strings reproduced **byte-for-byte** incl. the stitched header/summary
  quirks (verified — see research D5/D6).

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.**
**Storage**: N/A (no persistence this slice; encrypted SQLite/SQLCipher is out of scope)
**Testing**: `cargo test` (unit in `hdfc_bank.rs` + `tests/parity.rs` — two HDFC golden vectors with per-row ledger fields, a balance-chain RECONCILED test per fixture, determinism, and the bank-vs-card `hdfc_bank_claims` split); **Swift Testing** (`import KanameCore`) for a "core ↔ Swift HDFC bank parse + balance chain" test over the UniFFI bridge
**Target Platform**: iOS 18+ (device `aarch64-apple-ios`; simulator `aarch64-apple-ios-sim` + `x86_64-apple-ios`); core is platform-agnostic
**Project Type**: Mobile — Rust core + native SwiftUI app (monorepo `core/` + `ios/`)
**Performance Goals**: parse + chain check are sub-millisecond pure functions over a handful of lines; no throughput target this slice
**Constraints**: 100% on-device, ZERO network in the parse/chain path (FR-028–030, SC-012); deterministic (FR-026, SC-014); money is `rust_decimal::Decimal`, never `f64` (FR-010, SC-011) — the only floats are the reused `Word.x0/x1` layout points (not exercised: HDFC sets no `column_split_x`); direction from the balance **delta** (row 1: printed opening), **never** the amount's sign/magnitude/column (FR-007/013, SC-006); Apache-2.0, no GPL/AGPL/LGPL, **no new deps** (FR-034)
**Scale/Scope**: **1 new reader** (`hdfc_bank.rs`) + **1 new shared helper** (`account_tail_last4` in `common.rs`, + a behaviour-preserving `icici_bank.rs` refactor); **2 exported FFI functions** (`read_hdfc_bank_statement`, `hdfc_bank_claims`) reusing `check_balance_chain`; **0 new records/enums/FFI types**; **2 golden fixtures** + **2 `Case` rows** + 2 balance-chain assertions (**no** harness schema change); **0 new dependencies**; no new app UI. **Pending decision**: a **1-line `DATE_FORMATS` reorder** in `common.rs` (see Open Decisions).

## Constitution Check

*GATE: evaluated before Phase 0 and re-checked after Phase 1. Constitution v1.0.0.*

| Principle / Gate | Verdict | Evidence & how this plan complies |
|---|---|---|
| **I. Data Privacy & Sovereignty** (NON-NEGOTIABLE) — free/core = 100% on-device, zero network, no telemetry | ✅ PASS | The whole HDFC bank-account parse **and** the reused balance chain are pure Rust over an in-memory `Vec<String>` + `String` (+ an empty `Vec<Word>`) — no sockets, HTTP, async runtime, or file/PDF I/O (FR-025/028). The core **never opens a PDF**. **Inherits the existing privacy-egress gate** (`make core-privacy-audit`) unchanged; **no new dependency at all** (see III), so the shipped `cargo tree -e normal` graph is byte-identical. Determinism/purity parity now also cover the two HDFC vectors (FR-026, SC-012/014). No telemetry/analytics/crash reporter (FR-029). |
| **II. Local-First Shared Engine** — pure, deterministic, platform-agnostic Rust core via UniFFI; money never float; explicit polarity; no PDF engine | ✅ PASS | HDFC is a **configuration** on the reused base (FR-003/020) — no base capability added; the two layouts are just an **ordered** anchor list the base already supports. Determinism is structural (`LazyLock<Regex>` statics; pure `parse_amount`/`parse_date`; locale-independent `chrono`/`regex`) (FR-026). **Money is `Decimal`, never `f64`** — amounts, balances, deltas all `Decimal` (FR-010); no geometry is exercised (HDFC sets no `column_split_x`). Direction is **delta-derived**, row-1 opening-anchored, recorded via `direction_source`, **never** from the amount's sign/column (FR-007/013, SC-006). The core embeds **no** PDF engine (FR-025). |
| **III. Open-Core & Permissive Licensing** — client Apache-2.0; GPL/AGPL/LGPL forbidden; no secrets | ✅ PASS | No secrets/keys/endpoints (FR-034). **NO new runtime OR dev dependency** — the reader, the shared tail helper, and the fixtures are built entirely from crates already in the graph (`regex`, `rust_decimal`, `chrono`, `serde`, `uniffi`; dev `serde_json`). Nothing copyleft enters the tree; the privacy audit's `cargo tree` surface re-confirms it. |
| **IV. Native Experience & Accessibility** — latest HIG, SwiftUI, Dynamic Type, Dark Mode, VoiceOver | ✅ PASS (N/A UI) | **Engine slice, no new user-facing surface** — app-side PDF text/geometry extraction (PDFKit), the file-import UI, and the Share Extension are out of scope (FR-035 is conditional). The only app-side artifact is a Swift Testing suite. Any later demo surface MUST follow HIG + a11y; none is added here. |
| **V. Test-First & Parity** — failing test precedes behaviour; `cargo test` + Swift Testing; privacy-egress test | ✅ PASS | **Golden-fixture parity**: the web engine's synthetic HDFC **compact** and **detailed** characterization vectors are **ported** to `fixtures/hdfc/bank_account/{compact,detailed}.json` (FR-031) and reproduced **exactly** — rows with dates/amounts/directions/**stitched** descriptions, per-row balance/delta/direction_source/serial/matches/suspect, printed opening/closing, period, account last-4, **and** a RECONCILED chain per fixture (SC-001/002/003). **Test-first**: the two failing golden `Case` rows + the balance-chain tests + the bank-vs-card `hdfc_bank_claims` split precede the port (FR-033). All fixture data is **synthetic/redacted** (FR-032). |
| **iOS Local Verification Gate** — cargo fmt/clippy/test; swiftlint + swift-format; tuist generate; simulator build+test | ✅ PASS | Ordering **unchanged**: `make core-xcframework` runs **before** `tuist generate` (Makefile `ios-gen: core-xcframework`). The two new exports reuse the **existing** `Decimal`/`NaiveDate` bridges and existing records/enums — **no new FFI type**. `macos-15` stays pinned for the iOS job; the **iPhone 16** simulator (`OS=latest`) is the `xcodebuild` destination; the core (ubuntu) job's privacy audit is inherited (FR-027/035). |
| **Security & Privacy Constraints** — no network SDKs in core paths; deps reviewed & justified; synthetic fixtures; no committed secrets | ✅ PASS | No network SDK anywhere; the audit proves it structurally and **no dependency review is needed** (no new dep). All fixture data is **synthetic/redacted** — fabricated payers (`EXAMPLEMERCHANT`, `EXAMPLEEMPLOYER`), amounts, and a synthetic account number `50100359253425` → last-4 `3425` (FR-032, SC-009). No secrets; `.env*` remain ignored. |

**Initial gate result: PASS (no Constitution violation), with ONE open decision.** The slice adds **zero
dependencies**, embeds **no PDF engine**, and keeps **money in `Decimal`**. Its genuine additions are (a) the
authorised **`account_tail_last4`** shared helper (a small DRY refactor that also de-duplicates
`icici_bank.rs`, keeping its fixture GREEN), and (b) **[pending your sign-off]** a **1-line reorder** of
`common.rs::DATE_FORMATS` required for the compact 2-digit-year dates to parse correctly in Rust `chrono`
(root cause and evidence in **research D8**). Both are recorded in **Complexity Tracking**. The date reorder is
a **shared-code change beyond the locked "one shared change"**, so per the requester's instruction it is
surfaced as a decision rather than self-resolved. No other NEEDS CLARIFICATION remain — the approach is locked
by the requester and confirmed against the persisted ground truth, the web-engine source, and an out-of-repo
Rust replica (see [`research.md`](./research.md)).

## Project Structure

### Documentation (this feature)

```text
specs/008-hdfc-bank-ledger-reader/
├── plan.md                  # This file (/speckit.plan)
├── research.md              # Phase 0 — decisions D1–D9 (incl. D8: the DATE_FORMATS ordering decision)
├── data-model.md            # Phase 1 — the HdfcBankReader config, the account_tail_last4 helper, reused types, harness rows
├── contracts/
│   ├── engine-ffi.md        # Phase 1 — additive UniFFI surface (read_hdfc_bank_statement, hdfc_bank_claims) reusing check_balance_chain; NO new FFI types
│   ├── reader-config.md     # Phase 1 — the HdfcBankReader LedgerReaderConfig contract (2 anchors, opening/period/account patterns) + the shared account_tail_last4 helper + the icici_bank refactor
│   └── golden-fixture.md    # Phase 1 — the two HDFC vectors (compact + detailed) + the 2 Case rows (no schema change)
├── quickstart.md            # Phase 1 — build, verify, run the parity + balance-chain + privacy gates
├── checklists/              # (pre-existing) spec-quality checklist
└── tasks.md                 # Phase 2 — created by /speckit.tasks (NOT here)
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── Cargo.toml                        # UNCHANGED — no new dependency (runtime or dev)
├── uniffi.toml                       # UNCHANGED — Decimal → Foundation.Decimal map reused
├── src/
│   ├── lib.rs                        # + re-export read_hdfc_bank_statement, hdfc_bank_claims (check_balance_chain already exported)
│   ├── model.rs                      # UNCHANGED — Direction reused
│   ├── ffi.rs                        # + #[uniffi::export] read_hdfc_bank_statement (Vec<Word>), hdfc_bank_claims; check_balance_chain reused
│   ├── statement/
│   │   ├── mod.rs                    # + pub mod hdfc_bank;
│   │   ├── base.rs                   # UNCHANGED — records/enums from slice 007 reused as-is
│   │   ├── ledger_reader.rs          # UNCHANGED — the base is reused (ordered anchors, two-column amount, stitching, row-1)
│   │   ├── balance_chain.rs          # UNCHANGED — the integrity check is reused
│   │   ├── common.rs                 # CHANGED — + pub fn account_tail_last4(text, primary) (moves last4 + DIGIT_RUN_RE here); [PENDING] reorder DATE_FORMATS: %d/%m/%y before %d/%m/%Y
│   │   ├── icici_bank.rs             # CHANGED (refactor) — call common::account_tail_last4 with ICICI's ACCOUNT_RE (drop local last4/DIGIT_RUN_RE/account_tail); behaviour-preserving, fixture stays GREEN
│   │   ├── icici.rs / hdfc.rs / sbi.rs / yes.rs / federal.rs  # UNCHANGED — existing readers
│   │   └── hdfc_bank.rs              # NEW — zero-sized HdfcBankReader impl LedgerReaderConfig (2 anchors [compact, detailed]; opening/period/account patterns; enrich)
│   └── bin/uniffi-bindgen.rs         # UNCHANGED
└── tests/
    └── parity.rs                     # CHANGED (additive) — + parse_hdfc_bank wrapper + 2 Case rows (compact, detailed) + 2 balance-chain RECONCILED assertions + an hdfc_bank_claims accept/reject test; NO schema change (already extended in 007)

fixtures/
└── hdfc/bank_account/
    ├── compact.json                  # NEW — ported synthetic HDFC compact vector (2 rows; serials; summary-row opening; RECONCILED)
    └── detailed.json                 # NEW — ported synthetic HDFC detailed vector (2 rows; empty serials; inline opening; RECONCILED)

ios/Tests/
└── HdfcBankParseTests.swift          # NEW — "core ↔ Swift HDFC bank parse + balance chain" Swift Testing suite (over the UniFFI bridge)

Makefile                              # UNCHANGED — inherits core-test / core-privacy-audit / ios-test
.github/workflows/ci.yml              # UNCHANGED — inherits the core + iOS gates
```

**Structure Decision**: Keep the **monorepo mobile** layout (`core/` Rust + `ios/` SwiftUI) and mirror the web
engine 1:1 — `hdfc_bank.py → statement/hdfc_bank.rs` — so the port is a mechanical, reviewable diff modelled
directly on `statement/icici_bank.rs`. HDFC is a **per-issuer config** on the **unchanged** base
(`ledger_reader.rs`) and **unchanged** chain (`balance_chain.rs`): a zero-sized `struct` implementing
`LedgerReaderConfig`, distinguished from the existing HDFC **credit-card** reader (`hdfc.rs`) by its `claims`
gate. The sole new **shared** code — `account_tail_last4` — lives in `common.rs` alongside the existing
`parse_amount`/`parse_date`/`find_last4`, and `icici_bank.rs` is refactored to consume it (proving the helper
generalises, per FR-022). Exported FFI functions stay in `ffi.rs`; generated Swift + `KanameCoreFFI.xcframework`
remain git-ignored artifacts rebuilt by `make core-xcframework` (before `tuist generate`).

## Open Decisions (needs your sign-off)

> This is the single item the requester asked to have surfaced rather than self-answered. It does **not**
> violate the constitution; it widens the **locked shared-change footprint** by one line, so it is your call.

**OD-1 — Reorder `common.rs::DATE_FORMATS` so `%d/%m/%y` precedes `%d/%m/%Y` (fixes the compact dates).**

- **Symptom (verified, Rust `chrono` 0.4.45 — kaname's resolved version):** the shared `parse_date` tries
  `%d/%m/%Y` **first**, and Rust `chrono`'s `%Y` **greedily accepts a 2-digit year**, so `parse_from_str
  ("01/04/26", "%d/%m/%Y") = Ok(0026-04-01)` — it wins before `%d/%m/%y` is ever tried. The compact rows would
  therefore carry **`0026-04-01` / `0026-04-16`**, failing parity against the ground-truth **`2026-…`**.
- **Root cause:** a Python↔Rust `%Y` divergence. Python's `strptime('01/04/26','%d/%m/%Y')` **raises**
  (its `%Y` requires 4 digits), so the web engine falls through to `%d/%m/%y` → `2026-04-01` — which is why the
  ground truth is `2026-…`. The two formats *are* both present in `common.rs` (as the spec assumed), but the
  **ordering** makes `%d/%m/%y` unreachable for pure 2-digit-year slash tokens in Rust.
- **Proposed fix (recommended):** move `"%d/%m/%y"` above `"%d/%m/%Y"` in `DATE_FORMATS`. **Verified safe:**
  Rust `%d/%m/%y` **cleanly rejects** 4-digit years (`Err`, "trailing input"), so `01/04/2026` /
  `19/04/2026` still resolve via `%d/%m/%Y`; every existing reader's token (dotted, dash, month-name, ISO) is
  unaffected. With the reorder my out-of-repo Rust replica reproduces **both** HDFC fixtures **byte-for-byte
  (63/63 assertions green)**.
- **Why it's a decision, not a self-answer:** you locked the slice's *only* new shared code to
  `account_tail_last4` (FR-022/023). This adds a **second** shared touch (a 1-line reorder) to `common.rs`.
  It's small and arguably a latent-bug fix, but it changes shared behaviour, so it's yours to approve.
- **Alternatives (worse):** (a) a per-config date hook on the base → **base change** (forbidden — base is
  reused unchanged); (b) normalising the compact `date` group before parse → no such hook exists in
  `find_anchors`; (c) leaving it → the compact fixture cannot go green. A one-line spec/Assumption note
  (FR-023) is also warranted to record the ordering nuance.

**If you approve OD-1**, `/speckit.tasks` proceeds as planned. **If you prefer a different resolution**, say so
and I'll re-plan the date handling accordingly.

## Complexity Tracking

> **No constitution violations.** The slice adds **no dependency**, embeds **no PDF engine**, and keeps money
> in `Decimal`. Its genuine additions are recorded here with the simpler alternative and why it is rejected.

| Item | Why (in scope this slice) | Why the alternative is rejected |
|---|---|---|
| **New shared helper `account_tail_last4(text, primary)` in `common.rs`** (+ a behaviour-preserving `icici_bank.rs` refactor to consume it) | HDFC's account regex (optional masked `X*` prefix, 4+ digits) differs from ICICI's while the ≥9-digit fallback is identical across banks; a per-bank primary + shared fallback is the faithful port and serves later Federal/AU readers (FR-018/022). Factoring it into `common.rs` DRYs the two banks. | Duplicating the fallback (longest `\d{9,}` run + `last4`) in every bank reader would drift and re-implement identical logic per issuer — the exact duplication the shared helper exists to prevent. The refactor keeps `icici_bank.rs`'s fixture **GREEN** (verified `000401000123456 → 3456`), so it is behaviour-preserving. |
| **[PENDING OD-1] 1-line reorder of `common.rs::DATE_FORMATS`** (`%d/%m/%y` before `%d/%m/%Y`) | Required for the **compact** 2-digit-year dates to parse to `2026-…` in Rust `chrono` (whose `%Y` greedily matches 2 digits) — otherwise they misparse to `0026-…` and fail parity (research D8, verified). | A base date-hook or input normalisation would require changing the **reused-unchanged** base; leaving it breaks the compact fixture. The reorder is the minimal, verified-safe fix — but it is a **second shared touch**, so it is gated on your sign-off (Open Decisions). |
| **HDFC returns two anchors from `anchor_res()`** (`[COMPACT, DETAILED]`, first-match-wins) | HDFC ships two export layouts; the base already tries an **ordered** anchor list (this is the first config to supply >1) (FR-003/006). The 2-digit vs 4-digit year makes them mutually exclusive (verified: neither row matches the other's anchor). | A separate reader per layout would double the claims/FFI/fixture surface for one issuer and hide the layout choice from the base's existing ordered-anchor mechanism. One reader + two anchors is the faithful, minimal shape. |

## Phase status

- **Phase 0 — Research**: ✅ complete → [`research.md`](./research.md) (D1–D9). All values accounted for
  against the persisted `hdfc-bank-ground-truth.json`, the web-engine `hdfc_bank.py`, and an out-of-repo Rust
  `regex`+`chrono`+`rust_decimal` replica of the base run over **both** fixtures (compact + detailed): the two
  rows each, `serial`s (`0000600000000001` / `CITIN26653417445`; empty for detailed), the **stitched**
  narrations (incl. the compact row-2 summary quirk and both row-0 column headers), printed opening
  `100000.00` (compact from the summary row across `\n`; detailed inline) / closing `145000.00`, period
  `2026-04-01 → 2026-04-30` (optional colon), account last-4 `3425`, and RECONCILED per fixture — **all green
  with OD-1 applied**. The **one** open item is **D8/OD-1** (the `DATE_FORMATS` reorder), surfaced for your
  sign-off.
- **Phase 1 — Design & Contracts**: ✅ complete → [`data-model.md`](./data-model.md),
  [`contracts/engine-ffi.md`](./contracts/engine-ffi.md),
  [`contracts/reader-config.md`](./contracts/reader-config.md),
  [`contracts/golden-fixture.md`](./contracts/golden-fixture.md),
  [`quickstart.md`](./quickstart.md); agent context refreshed via
  `.specify/scripts/bash/update-agent-context.sh copilot`.
- **Phase 1 re-check (post-design Constitution Check)**: ✅ PASS — the design adds **no new dependency**,
  **no new FFI type**, embeds **no PDF engine**, keeps **money in `Decimal`**, and derives **direction from the
  balance delta** with an auditable `direction_source`. The two golden vectors + the string-based `Decimal`
  fixtures + determinism/purity + dependency-audit gates actively **reinforce** the no-float-money,
  determinism, and privacy principles. The base, the chain check, the parity-harness schema, and the privacy
  gate are **reused unchanged**. The two additive touches (the `account_tail_last4` helper + the pending
  `DATE_FORMATS` reorder) are recorded in Complexity Tracking; only OD-1 needs a decision.
- **Phase 2 — Tasks**: ⏭️ NOT done here. After OD-1 is confirmed, run `/speckit.tasks` to generate `tasks.md`,
  ordered test-first per Principle V: write the two golden fixtures + the two failing parity `Case` rows + the
  balance-chain RECONCILED tests + the bank-vs-card `hdfc_bank_claims` split → `common.rs`
  (`account_tail_last4` + [OD-1] `DATE_FORMATS` reorder) + `icici_bank.rs` refactor (keep GREEN) →
  `statement/hdfc_bank.rs` (the HDFC config) → FFI exports (`read_hdfc_bank_statement` + `hdfc_bank_claims`) +
  `lib.rs` re-exports + `mod.rs` wiring → Swift bridge test → run the inherited privacy/iOS gates.
