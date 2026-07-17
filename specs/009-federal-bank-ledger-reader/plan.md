# Implementation Plan: Federal Bank (Savings/Current) Ledger Reader — the Third Balance-Ledger Reference Reader

**Branch**: `009-federal-bank-ledger-reader` | **Date**: 2026-07-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/009-federal-bank-ledger-reader/spec.md`

## Summary

Add a **Federal Bank savings/current** balance-ledger reader to `kaname-core` as **pure configuration** on the already-landed ledger base — the **leanest ledger slice yet**. It mirrors `statement/hdfc_bank.rs` exactly, contributing only Federal's per-issuer configuration (one document gate, **two** first-match-wins anchor regexes — a `DD-MON-YYYY` **classic** template and a `DD/MM/YYYY` **Fi/Epifi neobank** template — plus opening-balance/period/account patterns) and **two golden fixtures**. Federal prints a trailing `Cr`/`Dr` on every row that marks the **balance's** sign; the anchor **consumes but ignores** it, and direction stays **delta-derived** (fall = debit, rise = credit; row 1 anchored on the printed opening balance). An optional `S`-prefixed Tran ID is captured as the row **serial** and kept out of the narration.

**Zero new infrastructure, zero new dependencies, zero new shared helpers.** `account_tail_last4` already exists in `common.rs` (from slice 008); the ledger base already supports multi-anchor first-match-wins, two-column loose-integer amounts, separate `serial` capture, and `GRAND TOTAL`-into-narration stitching; the dates `%d-%b-%Y` / `%d/%m/%Y` / `%Y-%m-%d` are all already in `DATE_FORMATS`. The reader shares `BANK_CODE = "FEDERAL"` with the landed Scapia credit-card reader (`statement/federal.rs`); they coexist cleanly (different module, struct, trait, and FFI names) exactly as ICICI and HDFC already do (one issuer code, two account kinds), separated by their `claims` gates. The engine is exposed to Swift over the existing UniFFI bridge via `read_federal_bank_statement` + `federal_bank_claims`, reusing `check_balance_chain`. Behaviour is pinned **byte-for-byte** to the proven web engine (`federal_bank.py`) by two golden parity vectors, both RECONCILED.

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.**
**Storage**: N/A (no persistence this slice; encrypted SQLite/SQLCipher is out of scope)
**Testing**: `cargo test` (unit in `federal_bank.rs` + `tests/parity.rs` — two Federal golden vectors with per-row ledger fields, a per-fixture balance-chain RECONCILED test, determinism, and the bank-vs-card `federal_bank_claims` split); **Swift Testing** (`import KanameCore`) for a "core ↔ Swift Federal bank parse + balance chain" test over the UniFFI bridge
**Target Platform**: iOS 18+ (device `aarch64-apple-ios`; simulator `aarch64-apple-ios-sim` + `x86_64-apple-ios`); core is platform-agnostic
**Project Type**: Mobile — Rust core + native SwiftUI app (monorepo `core/` + `ios/`)
**Performance Goals**: parse + chain check are sub-millisecond pure functions over a handful of lines; no throughput target this slice
**Constraints**: 100% on-device, ZERO network in the parse/chain path (FR-028–033, SC-012); deterministic (FR-029, SC-014); money is `rust_decimal::Decimal`, never `f64` (FR-011, SC-011) — the only floats are the reused `Word.x0/x1` layout points (**not exercised**: Federal sets no `column_split_x`); direction from the balance **delta** (row 1: printed opening), **never** the trailing `Cr`/`Dr` marker, the amount's sign/magnitude, or the printed column (FR-007/008, SC-004); Apache-2.0, no GPL/AGPL/LGPL, **no new deps** (FR-037)
**Scale/Scope**: **1 new reader** (`statement/federal_bank.rs`, mirroring `hdfc_bank.rs`) + **1 `mod.rs` line** (`pub mod federal_bank;`); **2 exported FFI functions** (`read_federal_bank_statement`, `federal_bank_claims`) reusing `check_balance_chain`, plus their `lib.rs` re-exports; **0 new records/enums/FFI types**; **0 new shared helpers**; **0 base changes**; **2 golden fixtures** under `fixtures/federal/bank_account/` + **2 `Case` rows** + **1 per-fixture balance-chain assertion** (**no** harness schema change); **0 new dependencies**; no new app UI.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against **Kaname Constitution v1.0.0**. **Result: PASS (no violations, no deviations).**

| Principle | Gate | Status | Evidence |
|-----------|------|--------|----------|
| **I. Data Privacy & Sovereignty** (NON-NEGOTIABLE) | Free/core path is 100% on-device, zero network I/O, no telemetry; privacy-egress test covers it | ✅ PASS | Pure function over already-extracted text; no I/O, no clock, no global state. No networking dependency added (FR-031/032/033). The existing privacy-egress gate is extended to the Federal bank parse path (SC-012). |
| **II. Local-First Shared Engine** | Logic in `kaname-core`, reused via UniFFI; pure/deterministic; no embedded PDF engine; money = `Decimal`, explicit direction | ✅ PASS | Reader lives in `kaname-core` and is exposed over the existing UniFFI bridge (FR-030). Accepts `lines` + `full_text` + `first_row_words` — the core never opens a PDF (FR-028). Money is `rust_decimal::Decimal`; direction is an explicit `Direction` derived from the balance delta, **not** the trailing `Cr`/`Dr` (FR-007/008/011). |
| **III. Open-Core & Permissive Licensing** | Apache-2.0, no copyleft, no secrets, deps justified | ✅ PASS | No new dependency; no secrets/keys/endpoints; nothing that could be unlocked by a fork (FR-037). |
| **IV. Native Experience & Accessibility** | Latest HIG, SwiftUI, Dynamic Type/Dark Mode/VoiceOver on new/changed screens | ➖ N/A | Engine-only slice; **no** user-facing surface is added (FR-038 conditional not triggered; Assumptions §"No new UI required"). If a trivial demo surface is later added it must follow HIG + a11y. |
| **V. Test-First & Parity** | Golden-fixture parity vs the web engine; test-first; `cargo test` + Swift Testing; privacy-egress test | ✅ PASS | Two synthetic Federal vectors ported from `federal_bank.py` into `fixtures/federal/bank_account/`, reproduced byte-for-byte; a failing golden test precedes the behaviour (FR-034/036, SC-001/002/014). Balance chain RECONCILED for both (FR-027, SC-003). |

**Security & Privacy Constraints**: no third-party SDK, no network I/O; fixtures are fully synthetic/redacted (fabricated payers, amounts, account numbers — FR-035); no secrets committed; **no new dependency** (prefer stdlib + already-audited crates). ✅ PASS

**iOS Local Verification Gate** (applies at implement time): `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`; `swiftlint --strict` + `swift-format lint --strict`; `tuist generate`; simulator build + Swift Testing; privacy-egress test. **Ordering note**: rebuild the core xcframework via `make core-xcframework` **before** `tuist generate` so the new FFI symbols are visible to the iOS target (see quickstart). ✅ Plannable, no blockers.

**Initial Constitution Check: PASS.** No entry required in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/009-federal-bank-ledger-reader/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output — locked decisions + empirical parity checks
├── data-model.md        # Phase 1 output — reused records + FederalBankReader config values
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
│   │   ├── federal_bank.rs     # NEW — FederalBankReader: LedgerReaderConfig (mirrors hdfc_bank.rs)
│   │   ├── federal.rs          # UNCHANGED — Scapia CC reader (FederalReader: LineReaderConfig), shares BANK_CODE "FEDERAL"
│   │   ├── hdfc_bank.rs        # THE TEMPLATE — copied structurally, not modified
│   │   ├── ledger_reader.rs    # UNCHANGED — reused base (anchors, stitching, row-1 bootstrap, amount-as-check)
│   │   ├── balance_chain.rs    # UNCHANGED — reused check()
│   │   ├── common.rs           # UNCHANGED — reused account_tail_last4 / parse_date / parse_amount
│   │   ├── base.rs             # UNCHANGED — reused ParsedStatement / LedgerMetadata / DirectionSource / Word
│   │   └── mod.rs              # +1 line: `pub mod federal_bank;`
│   ├── ffi.rs                  # +2 exports: read_federal_bank_statement, federal_bank_claims (reuse check_balance_chain)
│   └── lib.rs                  # +2 names in the `pub use ffi::{…}` re-export
└── tests/
    └── parity.rs              # +2 Case rows + parse_federal_bank wrapper + 1 per-fixture balance-chain test (no schema change)

fixtures/federal/
├── credit_card/basic.json     # UNCHANGED — landed Scapia CC fixture (do NOT disturb)
└── bank_account/              # NEW sibling dir
    ├── classic.json           # NEW golden vector (3 rows, RECONCILED)
    └── fi.json                # NEW golden vector (2 rows, RECONCILED)

ios/                           # Swift Testing: 1 "core ↔ Swift Federal bank parse + chain" test (mirrors HDFC)
```

**Structure Decision**: Mobile monorepo (`core/` Rust engine + `ios/` SwiftUI app), already established by slices 001–008. This slice touches only the Rust core (`statement/federal_bank.rs`, `mod.rs`, `ffi.rs`, `lib.rs`, `tests/parity.rs`), two new fixtures under `fixtures/federal/bank_account/`, and one mirrored Swift Testing case. It exactly follows the ICICI (007) and HDFC (008) bank-ledger precedents.

## Complexity Tracking

> No Constitution violations — this section is informational only.

This is a **pure additive reader + fixtures** slice and the **leanest ledger drop-in to date** — even leaner than HDFC (008), which had to factor out the `account_tail_last4` shared helper. This slice adds **NO shared code at all**:

| Dimension | This slice |
|-----------|-----------|
| New base capability | **0** — multi-anchor first-match-wins, loose two-column integer amounts, `serial` capture, and `GRAND TOTAL`-into-narration stitching all already exist |
| New shared helpers | **0** — `account_tail_last4` already in `common.rs` (008) |
| New dependencies | **0** (runtime and dev) |
| New date formats | **0** — `%d-%b-%Y`, `%d/%m/%Y`, `%Y-%m-%d` all already in `DATE_FORMATS` |
| New FFI records/enums | **0** — reuses `ParsedStatement` / `Word` / `ChainResult` |
| Files modified in base | **0** — `ledger_reader.rs`, `balance_chain.rs`, `common.rs`, `base.rs` untouched |
| Net new surface | 1 reader module, `pub mod` line, 2 FFI fns + re-exports, 2 fixtures, 2 `Case` rows + 1 chain test |

## Phase 0 — Outline & Research

**Output**: [research.md](./research.md). No `NEEDS CLARIFICATION` remained in Technical Context (this is a faithful port with a captured JSON ground truth), so Phase 0 instead **locks the ported decisions and de-risks the three Rust-semantics parity questions** the user flagged, with empirical evidence compiled against the crate's own dependency versions (chrono 0.4.45, rust_decimal 1.42.1, regex 1):

1. **Uppercase `%b` month** — `parse_date("08-APR-2026")` → `2026-04-08` (chrono matches month abbreviations case-insensitively). Classic dates parse; no new format needed. ✅
2. **Whole-number Fi amount vs 2-dp delta** — `Decimal::from_str_exact("5000") == (dec(95000.00) - dec(100000.00)).abs()` → `true` (rust_decimal compares by value across scales); `"5000".to_string()` stays `"5000"` (printed form preserved). ✅
3. **Anchor group splits** — the classic and Fi regexes capture `serial` out of `desc`, resolve the non-zero withdrawal/deposit column, and **do not** match the `GRAND TOTAL` line; opening/account/period patterns read both templates. ✅
4. **Narration stitch trace** — a hand-trace of the base's `stitch_narration` over both fixtures reproduces the ground truth byte-for-byte (classic row 2 folds row 1's continuation; classic row 3 folds its own continuation + `GRAND TOTAL`; Fi row 2 folds `MERCHANT \EXAM` + `Payment f/0000`). ✅
5. **Shared `FEDERAL` code coexistence** — module/struct/trait/FFI-name analysis confirms no clash with the landed Scapia CC reader. ✅
6. **Fixture serialization** — `direction_source` is stored as the Rust `Debug` spelling (`OpeningBalance`/`BalanceDelta`) and `direction` as `Debit`/`Credit` (the harness compares `format!("{:?}", …)` and serde-deserializes `Direction`), **not** the web engine's snake_case/UPPER — a required translation from the raw ground-truth JSON. ✅

## Phase 1 — Design & Contracts

**Prerequisites**: research.md complete.

**Outputs**:

1. **[data-model.md](./data-model.md)** — the reused output records (`ParsedStatement`, `ParsedTransaction`, `LedgerMetadata`, `DirectionSource`, `ChainResult`) with **no** schema change, plus the concrete `FederalBankReader` configuration values (bank code, claim markers, both anchor regexes, opening/period/account patterns) and the two fixtures' expected rows.
2. **[contracts/ffi.md](./contracts/ffi.md)** — the UniFFI surface contract: `read_federal_bank_statement(lines, full_text, first_row_words) -> ParsedStatement`, `federal_bank_claims(full_text) -> bool`, and the reused `check_balance_chain`; the `claims` document gate (all of `Federal Bank` + `Statement of Account`, bank code `FEDERAL`); and the parity-harness contract (two `Case` rows + per-fixture balance-chain assertion, no schema change).
3. **[quickstart.md](./quickstart.md)** — build/test/verify, including the **`make core-xcframework` before `tuist generate`** ordering, the parity + balance-chain + privacy gates, and the manual typo-check on `.github/copilot-instructions.md`.
4. **Agent context** — `.specify/scripts/bash/update-agent-context.sh copilot` appends the 009 tech line; if it reintroduces the `iOS 18 targe` typo, fix to `iOS 18 target` (left unstaged).

### Post-Design Constitution Re-Check

Re-evaluated after Phase 1: the design confirms **0 base changes, 0 new shared code, 0 new deps, 0 new FFI types**, direction strictly delta-derived (trailing `Cr`/`Dr` consumed-but-ignored), money exact `Decimal`, both fixtures RECONCILED, privacy path preserved. **Post-Design Constitution Check: PASS** — no new violations introduced; Complexity Tracking remains empty.

## Phase 2 — Next

`/speckit.tasks` will generate `tasks.md` (a dependency-ordered, test-first task list). **Not** produced by this command.
