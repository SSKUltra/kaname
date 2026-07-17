# Implementation Plan: AU Small Finance Bank (Savings/Current) Ledger Reader — the Fourth and Final Balance-Ledger Reference Reader

**Branch**: `010-au-bank-ledger-reader` | **Date**: 2026-07-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/010-au-bank-ledger-reader/spec.md`

## Summary

Add an **AU Small Finance Bank savings/current** balance-ledger reader to `kaname-core` as **pure configuration** on the already-landed ledger base — the **leanest ledger slice of the family** and the **fourth and final** bank-account reader (after ICICI, HDFC, Federal). It mirrors `statement/icici_bank.rs` (which likewise overrides `claim_any` + `closing_balance_re`), contributing only AU's per-issuer configuration (one document gate, **one** anchor regex, opening/closing/period patterns, and an account-number extractor) plus **one** golden fixture.

AU's two twists are both absorbed by the **unchanged** base: (1) it prints **no** per-row Dr/Cr marker — direction is delta-derived (fall = debit, rise = credit; row 1 anchored on the printed opening balance), and the `UPI/DR`/`UPI/CR` tokens are ordinary narration text (the counterparty's leg), never a signal; (2) each row prints a **Debit** column and a **Credit** column where the empty side is a literal **dash** `-` — the base's `loose_amount("-") → None` makes `anchor_amount` pick the non-dash side, exactly as the Fi/HDFC `0`-empty layout does.

**Zero new infrastructure, zero new dependencies, zero new shared helpers, zero base changes.** `account_tail_last4` already exists in `common.rs`; the date `%d %b %Y` is already in `DATE_FORMATS`; the two-column loose-amount path, opening bootstrap, `is_balance_line` narration-skip, and errored-vs-suspect handling all already exist. AU introduces a **new** `BANK_CODE = "AU"` and is the **sole** reader under it (this client has no AU credit-card reader). The engine is exposed to Swift over the existing UniFFI bridge via `read_au_bank_statement` + `au_bank_claims`, reusing `check_balance_chain`. Behaviour is pinned **byte-for-byte** to the proven web engine (`au_bank.py`) by one golden parity vector, RECONCILED.

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.**
**Storage**: N/A (no persistence this slice; encrypted SQLite/SQLCipher is out of scope)
**Testing**: `cargo test` (unit in `au_bank.rs` + `tests/parity.rs` — one AU golden vector with per-row ledger fields, a balance-chain RECONCILED test, determinism, and the bank-vs-card `au_bank_claims` split); **Swift Testing** (`import KanameCore`) for a "core ↔ Swift AU bank parse + balance chain" test over the UniFFI bridge
**Target Platform**: iOS 18+ (device `aarch64-apple-ios`; simulator `aarch64-apple-ios-sim` + `x86_64-apple-ios`); core is platform-agnostic
**Project Type**: Mobile — Rust core + native SwiftUI app (monorepo `core/` + `ios/`)
**Performance Goals**: parse + chain check are sub-millisecond pure functions over ~15 lines; no throughput target this slice
**Constraints**: 100% on-device, ZERO network in the parse/chain path (FR-030/031/032, SC-010); deterministic (FR-028, SC-012); money is `rust_decimal::Decimal`, never `f64` (FR-010, SC-009) — the only floats are the reused `Word.x0/x1` layout points (**not exercised**: AU sets no `column_split_x`); direction from the balance **delta** (row 1: printed opening), **never** the `UPI/DR`/`UPI/CR` narration text, the amount's sign/magnitude, or the printed column (FR-006/007, SC-003); Apache-2.0, no GPL/AGPL/LGPL, **no new deps** (FR-036)
**Scale/Scope**: **1 new reader** (`statement/au_bank.rs`, mirroring `icici_bank.rs`) + **1 `mod.rs` line** (`pub mod au_bank;`); **2 exported FFI functions** (`read_au_bank_statement`, `au_bank_claims`) reusing `check_balance_chain`, plus their `lib.rs` re-exports; **0 new records/enums/FFI types**; **0 new shared helpers**; **0 base changes**; **1 golden fixture** under `fixtures/au/bank_account/` + **1 `Case` row** + **1 balance-chain assertion** (**no** harness schema change); **0 new dependencies**; no new app UI.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against **Kaname Constitution v1.0.0**. **Result: PASS (no violations, no deviations).**

| Principle | Gate | Status | Evidence |
|-----------|------|--------|----------|
| **I. Data Privacy & Sovereignty** (NON-NEGOTIABLE) | Free/core path is 100% on-device, zero network I/O, no telemetry; privacy-egress test covers it | ✅ PASS | Pure function over already-extracted text; no I/O, no clock, no global state. No networking dependency added (FR-030/031). The existing privacy-egress gate is extended to the AU bank parse path (FR-032, SC-010). |
| **II. Local-First Shared Engine** | Logic in `kaname-core`, reused via UniFFI; pure/deterministic; no embedded PDF engine; money = `Decimal`, explicit direction | ✅ PASS | Reader lives in `kaname-core` and is exposed over the existing UniFFI bridge (FR-029). Accepts `lines` + `full_text` + `first_row_words` — the core never opens a PDF (FR-027). Money is `rust_decimal::Decimal`; direction is an explicit `Direction` derived from the balance delta, **not** the `UPI/DR`/`UPI/CR` narration text (FR-006/007/010). |
| **III. Open-Core & Permissive Licensing** | Apache-2.0, no copyleft, no secrets, deps justified | ✅ PASS | No new dependency; no secrets/keys/endpoints; nothing that could be unlocked by a fork (FR-036). |
| **IV. Native Experience & Accessibility** | Latest HIG, SwiftUI, Dynamic Type/Dark Mode/VoiceOver on new/changed screens | ➖ N/A | Engine-only slice; **no** user-facing surface is added (FR-037 conditional not triggered; Assumptions §"No new UI required"). If a trivial demo surface is later added it must follow HIG + a11y. |
| **V. Test-First & Parity** | Golden-fixture parity vs the web engine; test-first; `cargo test` + Swift Testing; privacy-egress test | ✅ PASS | One synthetic AU vector ported from `au_bank.py` into `fixtures/au/bank_account/`, reproduced byte-for-byte; a failing golden test precedes the behaviour (FR-033/035, SC-001/012). Balance chain RECONCILED (FR-026, SC-002). |

**Security & Privacy Constraints**: no third-party SDK, no network I/O; the fixture is fully synthetic/redacted (fabricated payers, amounts, account number — FR-034); no secrets committed; **no new dependency** (prefer stdlib + already-audited crates). ✅ PASS

**iOS Local Verification Gate** (applies at implement time): `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`; `swiftlint --strict` + `swift-format lint --strict`; `tuist generate`; simulator build (iPhone 16) + Swift Testing; privacy-egress test. **Ordering note**: rebuild the core xcframework via `make core-xcframework` **before** `tuist generate` so the new FFI symbols are visible to the iOS target (see quickstart). CI runs the same on `macos-15`. ✅ Plannable, no blockers.

**Initial Constitution Check: PASS.** No entry required in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/010-au-bank-ledger-reader/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output — locked decisions + empirical parity checks (real crates)
├── data-model.md        # Phase 1 output — reused records + AuBankReader config values
├── quickstart.md        # Phase 1 output — build/test/verify (core→FFI→iOS gate ordering)
├── contracts/
│   └── ffi.md           # Phase 1 output — UniFFI surface + claim gate + parity-harness contract
├── checklists/          # (pre-existing) requirement checklists
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── src/
│   ├── statement/
│   │   ├── au_bank.rs          # NEW — AuBankReader: LedgerReaderConfig (mirrors icici_bank.rs)
│   │   ├── icici_bank.rs       # THE TEMPLATE — copied structurally (claim_any + closing_balance_re), not modified
│   │   ├── federal_bank.rs     # SECONDARY TEMPLATE — enrich()/account_tail shape
│   │   ├── ledger_reader.rs    # UNCHANGED — reused base (anchors, loose_amount dash→None, stitching, row-1 bootstrap, printed_closing = last anchor)
│   │   ├── balance_chain.rs    # UNCHANGED — reused check()
│   │   ├── common.rs           # UNCHANGED — reused account_tail_last4 / parse_date (%d %b %Y) / parse_amount
│   │   ├── base.rs             # UNCHANGED — reused ParsedStatement / LedgerMetadata / DirectionSource / Word
│   │   └── mod.rs              # +1 line: `pub mod au_bank;`
│   ├── ffi.rs                  # +2 exports: read_au_bank_statement, au_bank_claims (reuse check_balance_chain)
│   └── lib.rs                  # +2 names in the `pub use ffi::{…}` re-export
└── tests/
    └── parity.rs              # +1 Case row + parse_au_bank wrapper + 1 balance-chain test (no schema change)

fixtures/au/                    # NEW issuer subtree (AU has no credit_card sibling in this client)
└── bank_account/
    └── savings.json           # NEW golden vector (2 rows, RECONCILED)

ios/                           # Swift Testing: 1 "core ↔ Swift AU bank parse + chain" test (mirrors Federal)
```

**Structure Decision**: Mobile monorepo (`core/` Rust engine + `ios/` SwiftUI app), already established by slices 001–009. This slice touches only the Rust core (`statement/au_bank.rs`, `mod.rs`, `ffi.rs`, `lib.rs`, `tests/parity.rs`), one new fixture under `fixtures/au/bank_account/`, and one mirrored Swift Testing case. It exactly follows the ICICI (007), HDFC (008), and Federal (009) bank-ledger precedents.

## Complexity Tracking

> No Constitution violations — this section is informational only.

This is a **pure additive reader + one fixture** slice and the **leanest ledger drop-in of the family** — leaner than Federal (009), which shipped two templates. This slice adds **NO shared code at all**:

| Dimension | This slice |
|-----------|-----------|
| New base capability | **0** — single-anchor two-column loose amounts (dash side → `None`), opening bootstrap, `is_balance_line` narration-skip all already exist |
| New shared helpers | **0** — `account_tail_last4` already in `common.rs` |
| New dependencies | **0** (runtime and dev) |
| New date formats | **0** — `%d %b %Y` already in `DATE_FORMATS` |
| New FFI records/enums | **0** — reuses `ParsedStatement` / `Word` / `ChainResult` |
| Files modified in base | **0** — `ledger_reader.rs`, `balance_chain.rs`, `common.rs`, `base.rs` untouched |
| Net new surface | 1 reader module, `pub mod` line, 2 FFI fns + re-exports, 1 fixture, 1 `Case` row + 1 chain test |

## Phase 0 — Outline & Research

**Output**: [research.md](./research.md). No `NEEDS CLARIFICATION` remained in Technical Context (a faithful port with a captured JSON ground truth), so Phase 0 instead **locks the ported decisions and de-risks the two user-flagged parity questions**, with empirical evidence compiled against the crate's own dependency versions (**regex 1.12.4, rust_decimal 1.42.1, chrono 0.4.45**, from `core/Cargo.lock`):

1. **Dash-marked empty column** — a scratch binary replicating the base's `anchor_amount`/`loose_amount` proved `loose_amount("-") = None`, so `anchor_amount` picks the non-dash side (row 1 → `5000.00` from Debit; row 2 → `10000.00` from Credit). **The base handles the dash with no change.** ✅ (the user's dash sanity-check)
2. **Printed closing balance** — `read_ledger_lines` sets it to the **last anchor's balance** unconditionally (`ledger_reader.rs:195`); the `Closing Balance(₹) : 223.34` header figure is only consumed by `is_balance_line` for narration-skip. So `printed_closing_balance = 16570.79` is the **intended parity value**, not `223.34`. ✅ (the user's printed-closing sanity-check)
3. **Anchor group splits** — the single regex captures `date`/`desc`/`withdrawal`/`deposit`/`balance`; the digit-bearing `…ref…tail` tokens stay in `desc`; the closing-header and footer lines do **not** match the anchor (exactly 2 rows). ✅
4. **Direction is delta-derived** — row 1 `−5000.00 ⇒ Debit` (narration has `UPI/DR`), row 2 `+10000.00 ⇒ Credit` (narration has `UPI/CR`); the tokens are ignored. ✅
5. **Narration stitch trace** — a hand-trace of the base's `stitch_narration` (anchors 9/12) reproduces the ground truth byte-for-byte (the `UPI/…` line above each anchor folds into that row; the footer folds into the last row). ✅
6. **Metadata & gate** — opening `11570.79`, period `2026-03-01 → 2026-05-31`, account last-4 `0042`, and the `aubank.in` + Savings/Current gate all verified on the real crates; `%d %b %Y` needs no new date format. ✅
7. **Fixture serialization** — `direction`/`direction_source` translate from the raw ground truth's `DEBIT`/`opening_balance` to the harness's `Debit`/`OpeningBalance`; every `serial` is `""`; the `₹` glyph is preserved. ✅

## Phase 1 — Design & Contracts

**Prerequisites**: research.md complete.

**Outputs**:

1. **[data-model.md](./data-model.md)** — the reused output records (`ParsedStatement`, `ParsedTransaction`, `LedgerMetadata`, `DirectionSource`, `ChainResult`) with **no** schema change, plus the concrete `AuBankReader` configuration values (bank code, claim markers, one anchor regex, opening/closing/period/account patterns) and the fixture's expected rows.
2. **[contracts/ffi.md](./contracts/ffi.md)** — the UniFFI surface contract: `read_au_bank_statement(lines, full_text, first_row_words) -> ParsedStatement`, `au_bank_claims(full_text) -> bool`, and the reused `check_balance_chain`; the `claims` document gate (all of `aubank.in` + any of `Savings Account`/`Current Account`, bank code `AU`); and the parity-harness contract (one `Case` row + balance-chain assertion, no schema change).
3. **[quickstart.md](./quickstart.md)** — build/test/verify, including the **`make core-xcframework` before `tuist generate`** ordering (iPhone 16 sim; `macos-15` CI), the parity + balance-chain + privacy gates, and the manual typo-check on `.github/copilot-instructions.md`.
4. **Agent context** — `.specify/scripts/bash/update-agent-context.sh copilot` appends the 010 tech line; if it reintroduces the `iOS 18 targe` typo, fix to `iOS 18 target` (left unstaged).

### Post-Design Constitution Re-Check

Re-evaluated after Phase 1: the design confirms **0 base changes, 0 new shared code, 0 new deps, 0 new FFI types**, direction strictly delta-derived (`UPI/DR`/`UPI/CR` narration ignored), the dash-empty column resolved by the unchanged `loose_amount`, `printed_closing_balance` pinned to the last anchor balance (`16570.79`, not the header `223.34`), money exact `Decimal`, the fixture RECONCILED, and the privacy path preserved. **Post-Design Constitution Check: PASS** — no new violations introduced; Complexity Tracking remains empty.

## Phase 2 — Next

`/speckit.tasks` will generate `tasks.md` (a dependency-ordered, test-first task list). **Not** produced by this command.
