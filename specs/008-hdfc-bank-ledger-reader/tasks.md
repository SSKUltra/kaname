---
description: "Task list — HDFC Bank (Savings/Current) Ledger Reader: a CONFIG-ON-AN-EXISTING-BASE slice (1 HDFC config + 1 shared account-tail helper + a behaviour-preserving ICICI refactor + a 1-line DATE_FORMATS reorder [OD-1, approved]); 2 golden fixtures; 2 FFI exports reusing check_balance_chain; zero new deps)"
---

# Tasks: Read an HDFC Bank (Savings/Current) Statement On-Device — the Second Balance-Ledger Reference Reader (HDFC config on the existing ledger base; two export layouts)

**Input**: Design documents from `/specs/008-hdfc-bank-ledger-reader/`
**Prerequisites**: `plan.md`, `spec.md` (US1–US10), `research.md` (D1–D9, incl. **D8/OD-1**), `data-model.md`,
`contracts/reader-config.md`, `contracts/engine-ffi.md`, `contracts/golden-fixture.md`, `quickstart.md`

**Tests**: REQUIRED and **TEST-FIRST** for this slice (Constitution Principle V, FR-033). The **two** golden
fixtures, the failing Rust parity `Case` rows (+ the two balance-chain RECONCILED tests + the `hdfc_bank_claims`
accept/reject split), and the failing Swift "core ↔ Swift HDFC bank parse + balance chain" test are all authored
**RED, before** the engine that greens them. The engine-side focused unit tests (compact serial + summary
opening, detailed non-zero column, claims split, and the `DATE_FORMATS`/`account_tail_last4` guards) land **with**
the GREEN engine per the requester's step 4d.

**Port source of truth** (faithful, byte-for-byte with the two golden vectors — the design is **LOCKED** in
`plan.md`/`data-model.md`/`contracts/`; do **not** re-derive it, just sequence it): the web engine's
`.../ingestion/statement_readers/hdfc_bank.py` (`BalanceLedgerStatementReader`), whose captured output is the
persisted ground truth `hdfc-bank-ground-truth.json`, verified end-to-end in an out-of-repo Rust replica (63/63
assertions green with OD-1 applied). **No live run needed** (`quickstart.md` §0/§6).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: `US1`=on-device parse (MVP) · `US2`=two layouts / first-match-wins · `US3`=delta direction /
  amount-as-check (+ two-column) · `US4`=opening balance per layout / opening-anchored row-1 · `US5`=narration
  stitching (incl. header/summary quirks) · `US6`=ledger metadata (serial / period / account last-4) ·
  `US7`=savings-vs-CC claim gate · `US8`=config-on-base + the one shared addition (`account_tail_last4`) ·
  `US9`=golden parity (2 vectors, both RECONCILED) · `US10`=privacy-egress + Swift bridge. Setup/Polish/Ship
  carry no label.
- Exact file paths are included in every task.

> **Note (this slice commits nothing during generation).** `/speckit.tasks` only writes this file. The **two**
> commits + PR #8 + `--rebase --delete-branch` merge are encoded as the final **Phase 15: Ship** and are executed
> by the implementer **only after** every gate is green (requester step 7).

## ♻️ REUSE — do NOT re-create (this slice adds 1 config + 1 shared helper + 2 FFI exports + 2 fixtures)

This is the **second bank config** on the balance-ledger base from slice 007. It adds **ZERO new dependency**
(runtime *or* dev), **zero new records/enums**, and **zero new FFI types**. Do **not** rebuild any of these — the
base, the chain check, the harness, and the privacy gate are **reused UNCHANGED**:

- `statement/ledger_reader.rs` — `trait LedgerReaderConfig` (`ledger_reader.rs:51`: `fn bank_code`, `fn claim_all`,
  `fn claim_any`, `fn anchor_res() -> Vec<&'static Regex>` **first-match-wins ordered list**, `fn
  opening_balance_re`/`fn closing_balance_re -> Option<&'static Regex>`, `fn column_split_x() -> Option<f64>`, `fn
  provisional_direction`, `fn enrich(&self, &mut ParsedStatement, &str)`, defaulted `fn account_tail -> None`),
  `read_ledger_lines` (`:126`), `claims_ledger` (`:93`), the two-column `anchor_amount`/`loose_amount`
  (`:238`/`:262`), `stitch_narration` (`:271`), `row1_direction`/`direction_from_x_position` (`:310`/`:342`). **No
  base change** — HDFC is the first config to return **>1** anchor.
- `statement/balance_chain.rs` — `pub fn check(statement: &ParsedStatement) -> ChainResult` (`:74`); `enum
  ChainStatus { Reconciled, NeedsReview }` (`:23`); `struct ChainResult { status, checked_rows, suspect_count,
  suspects, row1_direction_fallback, derived_opening_balance, derived_closing_balance, reason }` (`:41`). Reused
  **unchanged** (the ₹1.00 tolerance lives here only).
- `statement/base.rs` — records reused **unchanged**: `ParsedTransaction { value_date, amount, direction, currency,
  description_raw, bank_code, ledger: Option<LedgerMetadata> }` (`:68`); `ParsedStatement { bank_code, lines:
  Vec<ParsedTransaction>, errored_lines, period_start, period_end, card_last4, printed_opening_balance,
  printed_closing_balance, confidence }` (`:81`); `LedgerMetadata { balance, balance_delta, amount_matches_delta,
  is_suspect, direction_source, serial }` (`:55`); `DirectionSource` (`:27`); `Word { text, x0, x1 }` (`:44`).
- `statement/common.rs` — `parse_amount` (`:50`) / `parse_date` (`:58`). **Both** HDFC formats are already present:
  `%d/%m/%y` (`common.rs:22`) and `%d/%m/%Y` (`common.rs:21`) — but see **OD-1** below (they are in the **wrong
  order**). `find_last4` (`:141`, masked-PAN) is credit-card only and **NOT** used here.
- `ffi.rs` — the `Decimal`/`NaiveDate` custom-type bridges reused **unchanged** (**no `uniffi.toml` change**);
  `read_icici_bank_statement` (`:130`), `icici_bank_claims` (`:141`), and **`check_balance_chain(statement:
  ParsedStatement) -> ChainResult`** (`:149`) are the exact templates.
- `tests/parity.rs` — the golden-fixture harness with the `#[serde(default)]` optional-ledger schema
  (`Expected`/`ExpectedRow`/`ExpectedLedger` `:27`/`:45`/`:57`; `Case` `:68`; `CASES` `:74`; `parse_icici_bank`
  `:115`; `load_fixture` `:119`; `icici_bank_statement_balance_chain_reconciles` `:299`). **Already extended in
  007 — NO schema change here.** The **7** existing fixtures need **NO migration**.
- The **privacy-egress gate** (`make core-privacy-audit`, `Makefile:22`) and CI — inherited **unchanged** (**no new
  dependency** → byte-identical shipped `cargo tree` graph).

**The only NEW code**: `account_tail_last4` in `common.rs` (+ the **OD-1** `DATE_FORMATS` reorder); a
behaviour-preserving `icici_bank.rs` refactor; `statement/hdfc_bank.rs` (the HDFC config) + `mod.rs` wiring; **2**
`#[uniffi::export]` fns (`read_hdfc_bank_statement` / `hdfc_bank_claims`) + `lib.rs` re-exports; **2** golden
fixtures; **2** parity `Case` rows + **2** chain tests + a claim-split test; **1** Swift test. **No new dependency;
no new FFI type; `check_balance_chain` reused.**

## ⚠️ Grounding & local gotchas (apply throughout — the design docs drift from the landed symbols; use the REAL ones)

- **Naming drift → use the ACTUAL landed symbols.** The contracts say `LedgerRow` / `ChainReport` /
  `check_balance_chain(rows)` / `expected.rows`; the **real** code (slice 007) is:
  - the per-row type is **`ParsedTransaction`** (field **`value_date`**, not `date`), reached via
    **`ParsedStatement.lines`** (not `.rows`);
  - the chain fn is **`check_balance_chain(statement: ParsedStatement) -> ChainResult`** (takes the whole
    statement **by value**, not a row vector) and you assert **`result.status == ChainStatus::Reconciled`**;
  - the fixture **JSON** key **is** `expected.rows[]` (the harness maps `ExpectedRow` → `statement.lines[i]`; the
    JSON schema is unchanged — only the Rust struct field differs).
- **OD-1 is APPROVED (requester).** `common.rs` currently orders `DATE_FORMATS` as `%d/%m/%Y` (`:21`) **before**
  `%d/%m/%y` (`:22`). Rust `chrono`'s `%Y` greedily accepts 2-digit years, so `01/04/26` misparses to `0026-04-01`.
  **Reorder** so `%d/%m/%y` precedes `%d/%m/%Y` (`%d/%m/%y` cleanly **rejects** 4-digit years, so `01/04/2026`
  still resolves via `%d/%m/%Y`). This is a **second shared touch** beyond `account_tail_last4` — approved, and
  guarded by a `parse_date` regression test (T007) + the compact golden `Case` (T005) (research **D8**).
- **`make core-xcframework` MUST run before `tuist generate`** (`ios-gen: core-xcframework`, `Makefile:32`) — the
  generated Swift + `KanameCoreFFI.xcframework` are git-ignored **rebuilt** artifacts (`quickstart.md` §3).
- **Local Xcode needs an explicit "iPhone 16" simulator** for `make ios-test`
  (`xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'`, `Makefile:35`); CI pins
  **`macos-15`** for the iOS job.
- **Money is `Decimal`, never `f64`** — amounts, balances, deltas all `Decimal`; Indian grouping (`1,45,000.00`)
  is stripped and scale preserved (`145000.00`). The **only** `f64` on this surface is `Word.x0/x1` — **layout
  points, not money** — and HDFC sets **no `column_split_x`**, so no geometry is exercised (empty `Vec<Word>`).
  Fixture money is stored as **JSON strings**, re-parsed via `Decimal::from_str` (never float).
- **Direction is DELTA-DERIVED** in **both** layouts — `Debit` when the running balance falls, `Credit` when it
  rises; **never** the amount's sign/magnitude/column. Row 0 is anchored to the printed **opening balance**
  (`direction_source = OpeningBalance`); later rows use the running delta (`BalanceDelta`). HDFC exercises **no**
  x-position path (FR-013).
- **Two-place amount-vs-delta**: the **reader** records **exact** `amount == |delta|` (`amount_matches_delta`); the
  **₹1.00 tolerance** lives **ONLY** in `balance_chain::check`. Both HDFC fixtures reconcile (0 suspects).
- **`card_last4` is `"3425"`** via the shared **`account_tail_last4`** helper with HDFC's own primary regex
  (`(?i)Account\s*(?:Number|No\.?)\s*:?\s*X*([0-9]{4,})` — note `\s*` not `\s+`, optional masked `X*`, **4+**
  digits — differs from ICICI) → last-4; fallback longest `\d{9,}` run → last-4. **NOT** `find_last4`/masked-PAN.
- **Narration is intentionally "dirty"** — header/summary lines adjacent to a transaction are stitched into
  `description_raw` **byte-for-byte** to match the web engine (row 0's column header both layouts; the compact row
  1's trailing summary block). Do **not** trim/collapse/reorder — it would break parity (research **D4/D5**).
- **Encoding**: both fixtures are plain **ASCII/UTF-8** (no middot/rupee glyphs).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the invariants and prerequisites so every later task has a place to land and the gates stay
green. No behaviour yet.

- [ ] T001 [P] Confirm the **no-new-dependency** invariant: `core/crates/kaname-core/Cargo.toml` stays **UNCHANGED**
  (runtime `regex`/`rust_decimal`/`chrono`/`serde`/`uniffi` + dev-only `serde_json` already present) — this slice
  adds **zero** deps and **zero** new FFI types (FR-034, SC-010/012). Create the fixtures home directory
  `fixtures/hdfc/bank_account/` (alongside the existing `fixtures/hdfc/credit_card/`). Ref: `plan.md`
  §Summary/§Project Structure, `contracts/golden-fixture.md` §Fixture files.
- [ ] T002 [P] Verify local prerequisites & gotchas (no code): `cargo` on PATH (`source "$HOME/.cargo/env"`); iOS
  targets present (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`); an **"iPhone
  16" simulator** exists in Xcode; recall `make core-xcframework` precedes `tuist generate` (`Makefile:32`);
  confirm `common.rs` **already** carries `%d/%m/%y` (`:22`) and `%d/%m/%Y` (`:21`) but in the order that
  **triggers OD-1** (the reorder is T007). Ref: `quickstart.md` §Prerequisites, `plan.md` §Open Decisions.

**Checkpoint**: Fixtures home exists, manifest unchanged, toolchain ready, OD-1 target located.

---

## Phase 2: Test-First Foundation (⚠️ Principle V — author RED before ANY engine code)

**Purpose**: Pin the on-device engine to the proven web engine **before** writing it. These are the parity (US9),
chain (US9), claim-split (US7), and bridge (US1/US10) tests that **protect the whole slice**; they MUST be **RED**
at the end of this phase (`read_hdfc_bank_statement` / `hdfc_bank_claims` do not exist yet).

**⚠️ CRITICAL**: No engine code (Phase 3+) may be written until T003–T006 exist and are verified failing.

- [ ] T003 [P] [US9] Author the **ported** golden vector `fixtures/hdfc/bank_account/compact.json` — copy the
  **EXACT fixture bytes** pinned in `contracts/golden-fixture.md` §`compact.json` (do **not** hand-derive). `lines`
  = the 9 synthetic HDFC-compact lines (`HDFC BANK LIMITED`, `Statementof account`, `From : 01/04/2026 To :
  30/04/2026`, `AccountNo : 50100359253425`, the column header, the **2** `DD/MM/YY` anchor rows, then the
  2-line `OpeningBalance …` end-summary block); `full_text` = the `\n`-joined same (with a trailing `\n`).
  `expected.rows` = the **2** rows: row 0 `{2026-04-01, "5000.00", Debit, INR, description_raw
  "UPI-EXAMPLEMERCHANT Date Narration Chq./Ref.No. ValueDt WithdrawalAmt. DepositAmt. ClosingBalance", ledger{
  balance "95000.00", balance_delta "-5000.00", amount_matches_delta true, is_suspect false, direction_source
  "OpeningBalance", serial "0000600000000001"}}`; row 1 `{2026-04-16, "50000.00", Credit, INR, description_raw
  "NEFTCR-EXAMPLEEMPLOYER OpeningBalance DrCount CrCount Debits Credits ClosingBal 1,00,000.00 1 1 5,000.00
  50,000.00 1,45,000.00", ledger{ balance "145000.00", balance_delta "50000.00", amount_matches_delta true,
  is_suspect false, direction_source "BalanceDelta", serial "CITIN26653417445"}}`; `period_start "2026-04-01"`,
  `period_end "2026-04-30"`, `card_last4 "3425"`, `printed_opening_balance "100000.00"`,
  `printed_closing_balance "145000.00"`, `errored_lines []`. All money is **JSON strings** (re-parsed to
  `Decimal`, never `f64`); Indian grouping stripped, scale preserved. **100% synthetic/redacted** (FR-032,
  SC-009). Ref: `contracts/golden-fixture.md` §`compact.json`, research **D6**.
- [ ] T004 [P] [US9] Author the **ported** golden vector `fixtures/hdfc/bank_account/detailed.json` — copy the
  **EXACT fixture bytes** pinned in `contracts/golden-fixture.md` §`detailed.json`. `lines` = the 8 synthetic
  HDFC-detailed lines (`HDFC Bank`, `Savings Account Details`, `Statement From : 01/04/2026 To 30/04/2026`
  (**no** colon before `To`), `Account Number : 50100359253425`, `Opening Balance : 1,00,000.00 Limit : 0.00`
  (inline opening), the column header, the **2** `DD/MM/YYYY` two-column anchor rows). `expected.rows` = the **2**
  rows: row 0 `{2026-04-01, "5000.00", Debit, INR, description_raw "UPI-EXAMPLEMERCHANT Txn Date Narration
  Withdrawals Deposits Closing Balance", ledger{ balance "95000.00", balance_delta "-5000.00",
  amount_matches_delta true, is_suspect false, direction_source "OpeningBalance", serial ""}}`; row 1
  `{2026-04-20, "50000.00", Credit, INR, description_raw "UPI-EXAMPLEEMPLOYER salary", ledger{ balance
  "145000.00", balance_delta "50000.00", amount_matches_delta true, is_suspect false, direction_source
  "BalanceDelta", serial ""}}`; `period_start "2026-04-01"`, `period_end "2026-04-30"`, `card_last4 "3425"`,
  `printed_opening_balance "100000.00"`, `printed_closing_balance "145000.00"`, `errored_lines []`. Money as JSON
  strings; **synthetic/redacted**. Note the detailed **amount** is the **non-zero** of the Withdrawals/Deposits
  pair (the empty side prints `0.00`) and the **serial is empty** (no reference column). Ref:
  `contracts/golden-fixture.md` §`detailed.json`, research **D6**.
- [ ] T005 [US9] Extend the parity harness `core/crates/kaname-core/tests/parity.rs` → **RED** (**NO schema
  change** — the `#[serde(default)]` optional-ledger schema already landed in 007; do **NOT** touch the 7
  existing fixtures/cases):
  - Extend the `use kaname_core::{…}` block (`parity.rs:13`) to add `read_hdfc_bank_statement, hdfc_bank_claims`.
  - Add the wrapper `fn parse_hdfc_bank(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_hdfc_bank_statement(lines, full_text, Vec::new()) }` (empty geometry — HDFC sets no `column_split_x`),
    mirroring `parse_icici_bank` (`parity.rs:115`).
  - Add **two** `Case` rows to `CASES` (`parity.rs:74`, after the `icici/bank_account/basic.json` case):
    `Case { …, parse: parse_hdfc_bank, rel_path: "hdfc/bank_account/compact.json" }` and
    `Case { …, parse: parse_hdfc_bank, rel_path: "hdfc/bank_account/detailed.json" }`.
  - Add **two** dedicated chain tests mirroring `icici_bank_statement_balance_chain_reconciles` (`parity.rs:299`):
    `hdfc_bank_compact_statement_balance_chain_reconciles` and `hdfc_bank_detailed_statement_balance_chain_reconciles`
    — each `load_fixture(…)` → `read_hdfc_bank_statement(fx.lines, fx.full_text, Vec::new())` →
    `check_balance_chain(statement)` and assert `result.status == ChainStatus::Reconciled`, `result.suspect_count
    == 0`, `!result.row1_direction_fallback`, `result.checked_rows == 2` (SC-003).
  - Add `hdfc_bank_claims_accepts_bank_rejects_card` (mirror the per-bank claims tests, `parity.rs:240`+):
    `hdfc_bank_claims(compact.full_text) == true`, `hdfc_bank_claims(detailed.full_text) == true`, and `== false`
    for an HDFC **credit-card** style text (has `HDFC` but none of `WithdrawalAmt`/`Savings Account
    Details`/`Statementof account`) (SC-008).
  - ⚠️ **Verify RED**: `make core-test` **fails to compile** (`read_hdfc_bank_statement`/`hdfc_bank_claims`
    absent). Ref: `contracts/golden-fixture.md` §Parity harness rows, `contracts/engine-ffi.md` §Verification.
- [ ] T006 [P] [US1] Author the **RED** Swift bridge test `ios/Tests/HDFCBankParseTests.swift` — "core ↔ Swift
  HDFC bank parse + balance chain" (`import KanameCore`, Swift Testing), mirroring
  `ios/Tests/ICICIBankParseTests.swift`. Build each layout's `lines`/`fullText` with `[...].joined(separator:
  "\n")`; exact amounts via `Decimal(string:locale: Locale(identifier: "en_US_POSIX"))`; call
  `readHdfcBankStatement(lines:fullText:firstRowWords: [])` (empty geometry). Assert **both** layouts (2 rows
  each): `valueDate` (`"2026-04-01"`, then compact `"2026-04-16"` / detailed `"2026-04-20"`), delta-derived
  `.debit`/`.credit`, exact `Foundation.Decimal` amounts (`"5000.00"`/`"50000.00"` — single token for compact,
  the **non-zero** column for detailed), `descriptionRaw` (the stitched strings), per-row `ledger` — `balance`
  (`"95000.00"`/`"145000.00"`), `directionSource` (`.openingBalance`, `.balanceDelta`), `serial`
  (compact `"0000600000000001"`/`"CITIN26653417445"`; detailed `""`), `amountMatchesDelta`, `!isSuspect`; plus
  `printedOpeningBalance "100000.00"`, `printedClosingBalance "145000.00"`, `periodStart "2026-04-01"`, `periodEnd
  "2026-04-30"`, `cardLast4 "3425"`, `erroredLines.isEmpty`. Use `try #require(statement.lines.first)`. Assert
  `checkBalanceChain(statement:).status == .reconciled` (`suspectCount == 0`, `!row1DirectionFallback`,
  `checkedRows == 2`) for **both** fixtures. Assert `hdfcBankClaims(fullText:)` accepts **both** HDFC layouts and
  **rejects** an HDFC credit-card text. **Comments on their OWN line — never trailing after code** (swift-format
  `[Spacing]` rejects trailing inline comments). Amounts compared as exact `Foundation.Decimal` (never `Double`).
  ⚠️ **Verify RED**: won't build until the xcframework is regenerated with the exports in Phase 4. Ref:
  `contracts/engine-ffi.md` §Verification, `ios/Tests/ICICIBankParseTests.swift`.

**Checkpoint**: Both fixtures in place; Rust parity RED (2 `Case` rows + 2 chain tests + claim split won't
compile); Swift bridge test RED. Test-first satisfied — engine code may now begin.

---

## Phase 3: User Story 1 — Turn an HDFC savings/current statement into transactions, on-device (Priority: P1) 🎯 MVP

**Goal**: Recognize an HDFC **bank-account** statement (**either** export layout) and return one transaction per
ledger row (date, exact amount, **delta-derived** direction, INR, running balance, stitched description) — 100%
on-device. Building the engine here **also lands the behaviours** US2–US8 verify independently in Phases 5–11.

**Independent Test**: `read_hdfc_bank_statement(compact.lines, compact.full_text, vec![])` **and**
`…(detailed.lines, detailed.full_text, vec![])` each return the 2 expected rows, and `hdfc_bank_claims` accepts
both HDFC bank layouts / rejects an HDFC credit-card statement — with no network in the parse path.

> Engine landing order follows the plan's dependency chain (requester step 4a→4d): **common.rs (shared helper +
> OD-1 reorder) → icici_bank.rs refactor (keep GREEN) → hdfc_bank.rs (the HDFC config) + mod.rs → ffi.rs exports +
> lib.rs re-exports → `make core-fmt` then GREEN**. The design is **LOCKED** in `data-model.md`/`contracts/` —
> port it, don't re-derive it.

- [ ] T007 [US8] **(step 4a) Shared `common.rs` changes** in `core/crates/kaname-core/src/statement/common.rs`
  (research **D8**, `contracts/reader-config.md` §B/§D, `data-model.md` §1.2/§1.3):
  - **Add** `pub fn account_tail_last4(text: &str, primary: &Regex) -> Option<String>` — try `primary` capture
    group 1 → **trailing 4** of its digits; else the **longest** standalone run of `\d{9,}` (a module-private
    `DIGIT_RUN_RE` `LazyLock<Regex>`, `max_by_key(len)`, matching Python's `(?<!\d)(\d{9,})(?!\d)`) → trailing 4;
    else `None`. Bring the trailing-4 helper (`digits[len.saturating_sub(4)..]`) in alongside it. (This is the
    logic currently local to `icici_bank.rs:52/:62/:66` — it becomes the shared home; the `icici_bank.rs` copies
    are removed in T008.) `use regex::Regex;`.
  - **[OD-1, approved] Reorder `DATE_FORMATS`** so `"%d/%m/%y"` (`:22`) comes **before** `"%d/%m/%Y"` (`:21`) —
    Rust `chrono`'s `%Y` greedily accepts 2-digit years, so the compact `01/04/26` must reach `%d/%m/%y` first;
    `%d/%m/%y` cleanly rejects 4-digit years so `01/04/2026` still resolves via `%d/%m/%Y`. Update the adjacent
    comments accordingly. **No other format moves.**
  - **Unit tests** (`#[cfg(test)]`): a `DATE_FORMATS` **regression** test — `parse_date("01/04/26") ==
    NaiveDate 2026-04-01` **AND** `parse_date("01/04/2026") == NaiveDate 2026-04-01` (both correct after the
    reorder; the compact 2-digit and the detailed/period 4-digit paths); and `account_tail_last4` —
    `account_tail_last4("AccountNo : 50100359253425", &HDFC-style re) == Some("3425")`, the `\d{9,}` fallback on a
    bare long run, ICICI back-compat `…000401000123456 == Some("3456")`, and `None` when no digits run.
  - ⚠️ **Behaviour-preserving for existing readers**: no existing fixture parses a `DD/MM/YY` slash date, so the
    reorder cannot regress them; confirm in T011 (`make core-test` all-green). Ref: `contracts/reader-config.md`
    §B/§D, research **D8**, `data-model.md` §1.2/§1.3.
- [ ] T008 [P] [US8] **(step 4b) Behaviour-preserving ICICI refactor** —
  `core/crates/kaname-core/src/statement/icici_bank.rs`: replace the local account logic in `enrich`
  (`icici_bank.rs:119`, `statement.card_last4 = self.account_tail(full_text)`) with
  `common::account_tail_last4(full_text, &ACCOUNT_RE)`; **delete** the now-unused module-private `last4` (`:62`),
  `account_tail` (`:66`), the `account_tail` trait override (`:110`), and `DIGIT_RUN_RE` (`:52`). Keep
  `ACCOUNT_RE` (`:46`, ICICI's own `(?i)Account\s+(?:Number|No\.?)\s*:?\s*([0-9]{6,})`, unchanged). Add `use
  crate::statement::common::account_tail_last4;` (keep `parse_date`). **Invariant**: the ICICI golden fixture +
  the `icici_bank.rs` unit tests stay **GREEN** (`000401000123456 → 3456`; `parses_delta_directions_…` asserts
  `card_last4 == Some("3456")` at `icici_bank.rs:191`). Depends on T007. **[P] vs T009** (different file). Ref:
  `contracts/reader-config.md` §C, `plan.md` §Complexity Tracking.
- [ ] T009 [P] [US1] **(step 4c) The HDFC config — `core/crates/kaname-core/src/statement/hdfc_bank.rs` (NEW)** +
  wire `statement/mod.rs`. Port `hdfc_bank.py` to a **zero-sized** `pub struct HdfcBankReader;` `impl
  LedgerReaderConfig`, mirroring `IciciBankReader`. `pub const BANK_CODE: &str = "HDFC";`. Each regex a `static`
  built once via `LazyLock<Regex>` (exact patterns from `data-model.md §1.1` / `contracts/reader-config.md §A`):
  - `COMPACT_RE` `^(?P<date>\d{2}/\d{2}/\d{2})\s+(?P<desc>.*?)\s+(?P<serial>[A-Za-z0-9]{6,})\s+\d{2}/\d{2}/\d{2}\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$`
  - `DETAILED_RE` `^(?P<date>\d{2}/\d{2}/\d{4})\s+(?P<desc>.*?)\s+(?P<withdrawal>[\d,]+\.\d{2})\s+(?P<deposit>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$`
  - `OPENING_RE` `(?i)(?:Opening Balance\s*:\s*|OpeningBalance\b[^\n]*\n\s*)([\d,]+\.\d{2})` (matches the detailed
    **inline** form **and** the compact **end-summary** form **across `\n`** — Rust `regex` `\n`/`[^\n]` work
    without multiline/`(?s)`; group 1 in both alternatives)
  - `PERIOD_RE` `(?i)From\s*:\s*(\d{2}/\d{2}/\d{4})\s+To\s*:?\s*(\d{2}/\d{2}/\d{4})` (the `:?` after `To` is
    required — detailed omits the colon)
  - `HDFC_ACCOUNT_RE` `(?i)Account\s*(?:Number|No\.?)\s*:?\s*X*([0-9]{4,})` (**`\s*`** not `\s+`; optional masked
    `X*`; **4+** digits — differs from ICICI)
  - Trait methods: `fn bank_code()` → `BANK_CODE`; `fn claim_all()` → `&["HDFC"]`; `fn claim_any()` →
    `&["WithdrawalAmt", "Savings Account Details", "Statementof account"]`; **`fn anchor_res()` → `vec![&COMPACT_RE,
    &DETAILED_RE]`** (ordered, first-match-wins — HDFC is the first config with >1 anchor); `fn
    opening_balance_re()` → `Some(&OPENING_RE)`; **`fn closing_balance_re()` → `None`** (closing derived from the
    final row's balance); **`fn column_split_x()` → `None`** (no geometry); `fn enrich(&self, statement, full_text)`
    → `PERIOD_RE` groups 1&2 → `period_start`/`period_end` via `parse_date`, then `statement.card_last4 =
    account_tail_last4(full_text, &HDFC_ACCOUNT_RE)` (call the shared helper directly; do **not** override the
    trait `account_tail`). `use crate::statement::common::{account_tail_last4, parse_date};`,
    `use crate::statement::ledger_reader::LedgerReaderConfig;`, `use crate::statement::base::ParsedStatement;`.
  - **Wire** `core/crates/kaname-core/src/statement/mod.rs`: add `pub mod hdfc_bank;` (keep alphabetical — after
    `pub mod hdfc;`). No new re-export needed (`HdfcBankReader` is referenced by `ffi.rs` via its path).
  - **Focused unit tests** (`#[cfg(test)]`, driving `read_ledger_lines(&HdfcBankReader, …)` / `claims_ledger`):
    (a) **compact** layout parses the **alphanumeric serial** (`0000600000000001`, `CITIN26653417445`) and reads
    `printed_opening_balance == 100000.00` from the **end-summary** row across `\n` (not row-1's balance)
    (US6/US4); (b) **detailed** layout resolves the **non-zero** side of Withdrawals/Deposits as the amount
    (`5000.00` from withdrawals row 0; `50000.00` from deposits row 1) and reads the **inline** opening (US3/US4);
    (c) `claims_ledger(&HdfcBankReader, bank_text, "HDFC") == true` for both layouts and `== false` for an HDFC
    **credit-card** text and a wrong `bank_code` (US7). Depends on T007. **[P] vs T008** (different file). Ref:
    `contracts/reader-config.md` §A, `data-model.md` §1.1, research **D2–D6**.
- [ ] T010 [US1] **(step 4d) FFI exports + re-exports** — in `core/crates/kaname-core/src/ffi.rs`, mirroring
  `read_icici_bank_statement` (`ffi.rs:130`) / `icici_bank_claims` (`:141`): add
  `use crate::statement::hdfc_bank::HdfcBankReader;` then
  `#[uniffi::export] pub fn read_hdfc_bank_statement(lines: Vec<String>, full_text: String, first_row_words:
  Vec<Word>) -> ParsedStatement { read_ledger_lines(&HdfcBankReader, &lines, &full_text, &first_row_words) }` and
  `#[uniffi::export] pub fn hdfc_bank_claims(full_text: String) -> bool { claims_ledger(&HdfcBankReader,
  &full_text, "HDFC") }`. **Reuse** the already-exported `check_balance_chain` (`ffi.rs:149`) — do **not** add a
  second copy. Re-export both new fns in `core/crates/kaname-core/src/lib.rs` by extending the `pub use ffi::{…}`
  block (`lib.rs:28`, add `hdfc_bank_claims, read_hdfc_bank_statement`). No `uniffi.toml` change; no new type
  crosses the FFI. Depends on T009. Ref: `contracts/engine-ffi.md` §New exported functions/§`lib.rs` re-exports,
  research **D7**.
- [ ] T011 [US1] **Green the engine side**: run `make core-fmt` (rustfmt), then `make core-test` — the **two**
  HDFC parity `Case` rows (T005) now **PASS** for the compact + detailed vectors (2 rows each incl. ledger
  fields; `printed_opening 100000.00`/`closing 145000.00`; `period 2026-04-01→2026-04-30`; `card_last4 "3425"`;
  `errored_lines []`), the **two** `hdfc_bank_…_balance_chain_reconciles` tests (RECONCILED, 0 suspects, no
  fallback, `checked_rows == 2`), the `hdfc_bank_claims` split, the `common.rs` `DATE_FORMATS`/`account_tail_last4`
  guards, and the `hdfc_bank.rs` unit tests — while **all 7 prior parity cases (6 credit-card + ICICI bank) stay
  green** (fixtures untouched; ICICI `card_last4` still `"3456"` after the T008 refactor) — then `make core-lint`
  (fmt `--check` + clippy `-D warnings`). Verify **RED→GREEN** for the Rust harness. Ref: `quickstart.md` §1.

**Checkpoint**: The engine parses **both** golden HDFC statements, the balance chain reconciles each, and the Rust
parity + chain + claim-split + determinism + unit tests are green (Swift bridge greened in Phase 4). US1 is
functional on the Rust side; the ICICI refactor kept its fixture green.

---

## Phase 4: UniFFI bridge — regenerate the xcframework + green the Swift test (US1 / US10)

**Goal**: Surface the two new functions to Swift (reusing the existing types) and green the "core ↔ Swift HDFC
bank parse + balance chain" test for **both** layouts.

- [ ] T012 [US1] Run `make core-xcframework` to rebuild `ios/Frameworks/KanameCoreFFI.xcframework` +
  `ios/Generated/kaname_core.swift` (git-ignored artifacts) now exposing `readHdfcBankStatement` /
  `hdfcBankClaims` (reusing the existing `Word`, `LedgerMetadata`, `DirectionSource`, `ChainResult`,
  `ChainStatus`, `ParsedStatement` Swift types — **no new binding shape**, `uniffi.toml` untouched). ⚠️ **MUST run
  before `tuist generate`** (`Makefile:32`, `quickstart.md` §3). Ref: `contracts/engine-ffi.md` §Type inventory.
- [ ] T013 [US1] Run `make ios-test` (`ios-gen` → `core-xcframework` → `tuist generate` → `xcodebuild …
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test`) to **green**
  `ios/Tests/HDFCBankParseTests.swift` (T006) — both layouts (2 rows each) with exact `Foundation.Decimal`
  amounts, delta-derived `.debit`/`.credit`, per-row `ledger` (balance / `directionSource` / serial),
  `printedOpeningBalance 100000.00`, `printedClosingBalance 145000.00`, `periodStart`/`End`, `cardLast4 "3425"`,
  `checkBalanceChain(...).status == .reconciled` (suspectCount 0, no row-1 fallback, checkedRows 2), and
  `hdfcBankClaims` accept-both-layouts / reject-credit-card. ⚠️ **Local Xcode: create the "iPhone 16" simulator
  first.** Verify **RED→GREEN** for the Swift bridge test. Ref: `quickstart.md` §3.

**Checkpoint**: US1 MVP delivered end-to-end (Rust engine + balance chain + Swift bridge). A person's HDFC
savings/current statement text — **either** export layout — → transactions + a RECONCILED verdict, on-device.

---

## Phase 5: User Story 2 — One reader, two layouts, auto-selected by first-match-wins anchors (Priority: P2)

**Goal**: The single HDFC reader handles **both** export layouts behind one `anchor_res()` ordered list; the
caller never selects a layout, and each row is read by exactly one anchor (the 2-digit vs 4-digit year makes them
mutually exclusive). *(Impl landed in T009's `anchor_res() -> vec![&COMPACT_RE, &DETAILED_RE]` on the reused base;
adds no base capability — FR-003/006.)*

**Independent Test**: Parsing the compact and the detailed fixtures through the **same** `HdfcBankReader` yields
the correct rows without a layout hint; a compact row never matches `DETAILED_RE` and vice-versa.

- Delivered by **T009** (two ordered anchors) · Verified by **T005** (both `Case` rows through one
  `parse_hdfc_bank`), **T009** unit tests (compact vs detailed parse), **T003/T004** (mutually-exclusive fixture
  rows), **T013** (both layouts over the bridge).

**Checkpoint**: One reader, two layouts, first-match-wins — no caller-side layout selection, no cross-matching.

---

## Phase 6: User Story 3 — Direction from the running-balance delta in both layouts; amount as an independent check (Priority: P3)

**Goal**: Each row's direction is decided **solely** by the running-balance movement (fall ⇒ debit, rise ⇒
credit) in **both** layouts; the printed amount is an **independent** check (`amount == |delta|`), taken from the
**non-zero** Withdrawals/Deposits column in the detailed layout. *(Impl landed in the reused
`read_ledger_lines` delta logic + `anchor_amount`/`loose_amount`; T009 supplies the two anchors.)*

**Independent Test**: Compact and detailed rows whose balance rises classify credit and whose balance falls
classify debit; the detailed amount is the non-zero column and reconciles against the delta; a flipped balance
movement flips direction regardless of the printed amount/column.

- Delivered by the reused base (delta direction + two-column `anchor_amount`) · Verified by **T009** unit test (b)
  (detailed non-zero-side amount), **T003/T004** (delta-derived directions + `amount_matches_delta true`),
  **T005**/**T013** (both layouts), and the reused `ledger_reader.rs` delta-flip unit test from slice 007.

**Checkpoint**: Direction is provably delta-sourced in both layouts; the amount (single or non-zero column) is a
pure cross-check.

---

## Phase 7: User Story 4 — Opening balance per layout, and an opening-anchored row 1 (Priority: P4)

**Goal**: The detailed opening is read from the inline `Opening Balance :` line; the compact opening is read from
the **end-of-statement summary row** (across `\n`), **not** row-1's balance; row 0's direction is anchored to that
printed opening (`direction_source = OpeningBalance`) in both fixtures. *(Impl landed in T009's `OPENING_RE`
two-alternative pattern + the reused row-1 bootstrap; HDFC sets no `column_split_x`, so no x-position path.)*

**Independent Test**: Detailed opening `100000.00` from the inline line; compact opening `100000.00` from the
summary row's first figure; each fixture's row 0 is `OpeningBalance`, every later row `BalanceDelta`.

- Delivered by **T009** (`OPENING_RE` inline **and** newline-spanning summary alternatives) · Verified by
  **T009** unit test (a) (compact opening-from-summary), **T003/T004** (`direction_source` OpeningBalance/BalanceDelta;
  `printed_opening_balance 100000.00`), **T005**/**T013**.

**Checkpoint**: Opening balance is read correctly per layout; row 1 is opening-anchored (no untrusted bootstrap).

---

## Phase 8: User Story 5 — Faithful narration stitching, including the header/summary lines the web engine stitches in (Priority: P5)

**Goal**: Each row's `description_raw` reproduces the web engine's stitched narration **byte-for-byte** — row 0's
narration includes the column-header line (both layouts) and the **compact row 1's** narration includes the
trailing summary block — with **no** normalization/trim/reorder. *(Impl landed in the reused `stitch_narration`;
the exact strings are pinned by the fixtures.)*

**Independent Test**: Both fixtures' row descriptions match the ground-truth strings exactly, including the
stitched header/summary text.

- Delivered by the reused `stitch_narration` (`ledger_reader.rs:271`) · Verified by **T003/T004** (the exact
  `description_raw` bytes), **T005** (parity asserts them), **T013** (Swift `descriptionRaw`). ⚠️ Do **not** "clean
  up" the stitched text — it would break parity (research **D4/D5**).

**Checkpoint**: Narration parity is byte-exact, quirks included.

---

## Phase 9: User Story 6 — Ledger metadata: the alphanumeric serial, the billing period, and a bank-aware account last-4 (Priority: P6)

**Goal**: Each compact row exposes its **alphanumeric serial** (detailed rows an **empty** serial); both
statements record period `2026-04-01 → 2026-04-30` and account **last-4 `3425`** via the shared
`account_tail_last4` with HDFC's primary regex (optional masked `X*`, 4+ digits) else the longest `\d{9,}` run —
retaining only the trailing four digits. *(Impl landed in T009's anchors/`enrich` + T007's `account_tail_last4`.)*

**Independent Test**: Compact serials `0000600000000001`/`CITIN26653417445`, detailed serials `""`; period and
`card_last4 "3425"` on both; the full account number is never retained beyond last-4.

- Delivered by **T009** (`serial` capture + `PERIOD_RE` + `HDFC_ACCOUNT_RE`) + **T007** (`account_tail_last4`) ·
  Verified by **T009** unit tests, **T007** `account_tail_last4` test (`3425`), **T003/T004** (serials, period,
  last-4), **T005**/**T013**.

**Checkpoint**: The ledger is auditable and attributable — per-row serial + period + the correct bank-account
last-4 (never the full number).

---

## Phase 10: User Story 7 — The document gate tells an HDFC savings statement from an HDFC credit-card statement (Priority: P7)

**Goal**: `hdfc_bank_claims` requires the HDFC bank code + **all** `claim_all` (`["HDFC"]`) + **any** `claim_any`
(`["WithdrawalAmt", "Savings Account Details", "Statementof account"]`) — accepting both HDFC bank layouts and
**rejecting** the HDFC credit-card statement (which the existing `statement/hdfc.rs` reader still claims). *(Impl
landed in T009's `claim_all`/`claim_any` + the reused `claims_ledger`.)*

**Independent Test**: The bank reader claims the compact and detailed statements, rejects an HDFC credit-card
statement and other issuers; the existing HDFC credit-card reader (`hdfc_claims`) still claims the credit-card
statement.

- Delivered by **T009** (`claim_all`/`claim_any`) + reused `claims_ledger` · Verified by **T009** unit test (c),
  **T005** (`hdfc_bank_claims_accepts_bank_rejects_card`), **T013** (Swift claims), and the untouched
  `hdfc_claims_accepts_own_document_and_rejects_others` (`parity.rs:253`) confirming the CC reader still claims.

**Checkpoint**: The savings-vs-credit-card gate is precise — 0 misroutes; each statement reaches the correct
reader.

---

## Phase 11: User Story 8 — A config-on-an-existing-base slice: reuse the base unchanged, with one small shared addition (Priority: P8)

**Goal**: The HDFC parse is delivered by a per-issuer configuration plugged into the **unchanged** base and
balance-chain check; the **only** new *shared* code is `account_tail_last4` (per-bank primary regex, else longest
`\d{9,}` run) in `common.rs`, reused by HDFC and consumed by the refactored ICICI reader (proving it
generalises), and available to later Federal/AU readers. *(Impl landed in T007 + T008 + T009.)* The **[OD-1]**
`DATE_FORMATS` reorder is the one approved second shared touch (guarded by T007's regression test).

**Independent Test**: No base internals (anchor recognition, direction-from-delta, amount-as-check, stitching,
row-1 bootstrap, errored-vs-suspect, the balance chain, the parity harness, the privacy gate) were modified;
`account_tail_last4` is the sole new shared function; the ICICI fixture stays green.

- Delivered by **T007** (`account_tail_last4` + OD-1) + **T008** (ICICI consumes it, stays GREEN) + **T009** (HDFC
  as a config) · Verified by **T011** (all prior cases green, ICICI `card_last4 "3456"` unchanged) + the
  constitution review **T018** (diff is exactly the additive helper + reorder + config + FFI + fixtures + tests).

**Checkpoint**: HDFC is a genuine config-on-base; the base/chain/harness/gate are untouched; one small shared
helper (+ the approved 1-line reorder) is the entire shared footprint.

---

## Phase 12: User Story 9 — Proven byte-for-byte against two golden fixtures, both RECONCILED (Priority: P9) 🛡️ whole-slice guard

**Goal**: The parity harness is the **regression-proof** guarantee pinning **both** HDFC layouts to the web
engine — reusing the 007 schema (optional ledger fields; dedicated chain tests), with the 7 prior vectors
reproducing **unchanged**. *(Fixtures T003/T004; harness/chain/claim tests T005; greened T011.)*

**Independent Test**: The harness over both ported HDFC vectors matches expected output exactly (rows + ledger
metadata + printed opening/closing + period + last-4 + RECONCILED chain), and re-running is stable; all 7 prior
issuers still reproduce their vectors.

- [ ] T014 [US9] Finalize `core/crates/kaname-core/tests/parity.rs` as the **whole-slice guard**: confirm **both**
  HDFC `Case` rows call `parse_hdfc_bank` (empty geometry) and match field-by-field — `value_date`, exact
  `Decimal` amounts (scale preserved; Indian grouping stripped), delta-derived directions, `INR`,
  `description_raw` **byte-for-byte** (incl. the stitched header/summary quirks), per-row
  `balance`/`balance_delta`/`direction_source`/`serial`/`amount_matches_delta`/`is_suspect`, and
  `printed_opening_balance 100000.00`/`printed_closing_balance 145000.00`/`period 2026-04-01→2026-04-30`/`card_last4
  "3425"`/`errored_lines []` (SC-001/002/009); both `hdfc_bank_…_balance_chain_reconciles` tests assert
  **RECONCILED**, 0 suspects, no row-1 fallback, `checked_rows 2` (SC-003); the determinism **re-run** covers both
  bank vectors (SC-014); the fixtures are **100% synthetic** (SC-009/FR-032); and confirm the schema stayed
  **back-compatible** — the 6 CC fixtures + the ICICI bank fixture and their assertions are **byte-identical** (no
  migration; the ICICI `card_last4` is still `"3456"` after T008). Ref: `contracts/golden-fixture.md`
  §Acceptance, research **D5/D6**.

**Checkpoint**: Parity is an enforced guarantee for both HDFC layouts; one harness serves all readers with no
prior-fixture migration.

---

## Phase 13: User Story 10 — Privacy gate & the Swift bridge: zero network, no new dependency, reachable from Swift (Priority: P10) 🛡️ inherited guard

**Goal**: Prove the HDFC bank-account parse **and** chain path is egress-free — **structurally** (no networking
crate can even link) and **behaviorally** (determinism) — via the **inherited** gate with **zero** new config, and
confirm reachability over UniFFI (greened in T013). *(No new script/CI: this slice adds no dependency, so the
audit is byte-identical.)*

**Independent Test**: `make core-privacy-audit` passes only when zero networking crates are in the shipped graph;
the reader is callable over UniFFI from Swift; no new runtime (or networking) dependency was added.

- [ ] T015 [US10] Confirm the inherited privacy-egress gate stays **GREEN with ZERO changes**: run `make
  core-privacy-audit` → passes (no networking crate in `kaname-core` deps) — this slice adds **no dependency**
  (runtime *or* dev), so `cargo tree -p kaname-core -e normal` is byte-identical (`Cargo.toml` unchanged —
  FR-028/029/034, SC-010/012); the determinism/purity assertion over both HDFC vectors lives in `tests/parity.rs`
  (T005/T014, FR-026, SC-014); the whole reader (`read_hdfc_bank_statement`, `hdfc_bank_claims`, reused
  `check_balance_chain`) is reachable from Swift over UniFFI (proved GREEN in T013, SC-013, FR-027); confirm
  **no** telemetry/analytics/crash-reporter enters the parse/chain path and **no** network entitlement/ATS is
  added app-side (FR-029/030). Ref: `quickstart.md` §2, research **D1**, spec US10.

**Checkpoint**: Privacy-egress remains a first-class, structurally- and behaviorally-enforced gate covering the
HDFC bank-account parse **and** the reused balance-chain check; the reader is reachable from Swift.

---

## Phase 14: Polish & Cross-Cutting — full iOS Local Verification Gate green

**Purpose**: Prove the whole slice is merge-ready (SC-015) and review the constitution guarantees.

- [ ] T016 [P] Light docs alignment (no behaviour change): note the **second bank config** (HDFC savings/current,
  two layouts) on the balance-ledger base where the engine/build is described (`README.md` and/or
  `specs/008-hdfc-bank-ledger-reader/quickstart.md`); ensure `fixtures/README.md` reflects the two HDFC bank
  vectors under `fixtures/hdfc/bank_account/`. Refresh the `statement/mod.rs` doc comment only if it enumerates
  readers. No stale wording.
- [ ] T017 **Run the full iOS Local Verification Gate green**, in order: `make core-lint && make core-test && make
  core-privacy-audit && make lint && make ios-gen && make ios-test`. ⚠️ `make core-xcframework` is rebuilt before
  `tuist generate` (via `ios-gen`, `Makefile:32`); local Xcode requires the **"iPhone 16"** simulator; CI runs the
  same (core on ubuntu, iOS on **macos-15**). This is the SC-015 / FR-035 merge gate. Ref: `quickstart.md` §1–§3.
- [ ] T018 [P] Final constitution review (no code change): **NO new dependency** (runtime *or* dev) —
  `Cargo.toml`/`uniffi.toml` unchanged; the diff is exactly `account_tail_last4` + the **[OD-1]** `DATE_FORMATS`
  reorder in `common.rs` + the behaviour-preserving `icici_bank.rs` refactor + `statement/hdfc_bank.rs` +
  `mod.rs` wiring + 2 `ffi.rs` exports + `lib.rs` re-exports + 2 fixtures + 2 `parity.rs` `Case`/chain/claim tests
  + 1 Swift test; **no new record/enum/FFI type** (`check_balance_chain` reused); **money is `Decimal`, never
  `f64`** (no geometry exercised — HDFC sets no `column_split_x`); direction **delta-derived** with an auditable
  `direction_source`, never the amount's sign/column; **exact** `amount == |delta|` in the reader vs the **₹1.00**
  tolerance **only** in `balance_chain`; `card_last4 "3425"` via `account_tail_last4` (never the full number); no
  secrets / network entitlements / copyleft (GPL/AGPL/LGPL) deps (FR-034); all fixture/test data synthetic
  (FR-032, SC-009); the 7 prior fixtures + the harness schema stay back-compatible (no migration). Confirm against
  `git diff` before handoff. Ref: `plan.md` §Constitution Check/§Complexity Tracking.

**Checkpoint**: Whole slice is green end-to-end and constitution-clean — ready to ship.

---

## Phase 15: Ship — two commits, PR #8, CI, merge (requester step 7)

**Purpose**: Land the slice. Executed **only after** Phase 14 is green. (Generation writes nothing here; the
implementer runs these once the gates pass.)

- [ ] T019 Create **two small, pure commits** on `008-hdfc-bank-ledger-reader` (RED→GREEN kept coherent, matching
  the prior slices' shape):
  **Commit 1 — engine + fixtures + parity**: `core/crates/kaname-core/src/statement/common.rs`
  (`account_tail_last4` + OD-1 reorder + guards), `core/crates/kaname-core/src/statement/icici_bank.rs` (refactor),
  `core/crates/kaname-core/src/statement/hdfc_bank.rs` (+ its unit tests), `pub mod hdfc_bank;` in
  `core/crates/kaname-core/src/statement/mod.rs`, `core/crates/kaname-core/src/ffi.rs` (2 exports),
  `core/crates/kaname-core/src/lib.rs` (re-exports), `fixtures/hdfc/bank_account/compact.json`,
  `fixtures/hdfc/bank_account/detailed.json`, `core/crates/kaname-core/tests/parity.rs` (wrapper + 2 `Case` rows +
  2 chain tests + claim split), and any docs from T016.
  **Commit 2 — Swift test**: `ios/Tests/HDFCBankParseTests.swift`.
  Do **not** commit generated artifacts (`ios/Generated/…`, `ios/Frameworks/…` are git-ignored). Ref: requester
  step 7.
- [ ] T020 Push the branch, open **PR #8** (`SSKUltra/kaname`, base default branch), **watch CI** — both the
  **core** job (ubuntu: `core-lint` + `core-test` + `core-privacy-audit`) and the **iOS** job (**macos-15**:
  `core-xcframework` → `tuist generate` → `xcodebuild … iPhone 16` test) go green — then **`gh pr merge --rebase
  --delete-branch`**. Ref: requester step 7, `plan.md` §Constitution Check (CI ordering inherited unchanged).

**Checkpoint**: HDFC savings/current joins the balance-ledger family as the second reference reader — two export
layouts behind one config, byte-for-byte with the web engine, on the unchanged base.

---

## Dependencies & Execution Order

### Phase order

1. **Setup (P1)** → 2. **Test-First Foundation (P2, RED)** → 3. **US1 GREEN engine pipeline (P3)** →
4. **Bridge/Swift green (P4)** → 5–11. **US2/US3/US4/US5/US6/US7/US8 verification (P5–P11)** →
12. **US9 parity guard (P12)** → 13. **US10 privacy guard (P13)** → 14. **Polish + full gate (P14)** →
15. **Ship (P15)**.

- **Test-First (Phase 2) BLOCKS all engine code (Phase 3+)** — T003–T006 must exist and be RED first (Principle V,
  FR-033).
- **The US1 GREEN pipeline (T007→T011) is the critical path** and lands the behaviours US2–US8 verify.

### Task-level dependencies

- T003/T004 (fixtures) precede T005 (parity `Case`/chain/claim) and T011 (green); T005/T006 (RED tests) precede
  **all** implementation (T007+).
- **Engine spine**: **T007** (`common.rs`: `account_tail_last4` + OD-1) → { **T008** (`icici_bank.rs` refactor),
  **T009** (`hdfc_bank.rs` + `mod.rs`) } → **T010** (`ffi.rs` exports + `lib.rs`, needs T009) → **T011**
  (`core-fmt` → Rust green, needs T008+T009+T010).
- T010 → **T012** (xcframework) → **T013** (Swift green). **T012 before any `tuist generate`.**
- Guards: **T014** (parity whole-slice) depends on T011; **T015** (privacy + reachability) depends on T011 (+ T013
  reachability).
- **T017 (full gate) depends on everything** (T011, T013, T014, T015, T016); T018 is review only.
- **Ship**: T019 depends on T017 (all green); T020 depends on T019.

### Parallel opportunities

- **Setup**: T001 [P] + T002 [P].
- **Test-First**: T003 [P] (compact fixture) + T004 [P] (detailed fixture) + T006 [P] (Swift test) are different
  files; T005 edits `parity.rs` (run it alone; it references T003/T004's fixture paths to verify RED).
- **Engine spine**: after T007, **T008 [P] + T009 [P]** are different files depending only on T007 (author in
  parallel); the crate compiles once T010 lands.
- **Polish**: T016 [P] + T018 [P] (docs + review); T017 runs the gate alone.

**[P] set**: T001, T002, T003, T004, T006, T008, T009, T016, T018.

**Critical path**: T003/T004 → T005/T006 (RED) → **T007 → T009 → T010 → T011** → T012 → T013 → T014 → T015 → T017
→ T019 → T020. (T008/`icici_bank.rs` is parallel off T007 but is pulled into the green gate by T011.)

---

## Parallel Example: the Test-First Foundation (Phase 2) and the engine spine (Phase 3)

```bash
# Phase 2 — author the three independent RED artifacts together (different files):
Task T003: "Author fixtures/hdfc/bank_account/compact.json (exact bytes from contracts/golden-fixture.md)"
Task T004: "Author fixtures/hdfc/bank_account/detailed.json (exact bytes from contracts/golden-fixture.md)"
Task T006: "Author ios/Tests/HDFCBankParseTests.swift (RED core ↔ Swift HDFC bank parse + chain, both layouts)"
# Then T005 edits tests/parity.rs (wrapper + 2 Case rows + 2 chain tests + claim split) → verify RED (won't compile).

# Phase 3 — after T007 (common.rs: account_tail_last4 + OD-1 reorder), author the two different-file tasks in parallel:
Task T008: "icici_bank.rs — call common::account_tail_last4(&ACCOUNT_RE); drop local last4/account_tail/DIGIT_RUN_RE; stay GREEN"
Task T009: "statement/hdfc_bank.rs — HdfcBankReader impl LedgerReaderConfig (2 anchors) + enrich + mod.rs wiring + unit tests"
# Converge: T010 (ffi.rs exports + lib.rs re-exports) → T011 (core-fmt → Rust green).
```

---

## Implementation Strategy

### MVP first (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 **RED** anchors (2 fixtures → parity `Case`s/chain/claim → Swift) → 3. Phase 3
engine spine (T007→T011, `make core-fmt` then green) → 4. Phase 4 bridge (T012–T013). **STOP & VALIDATE**: **both**
HDFC statements parse on-device through `read_hdfc_bank_statement`, `check_balance_chain` reports RECONCILED for
each, and the Swift suite is green. This alone is a shippable, useful slice (the second bank config on the base).

### Incremental delivery

Add US2 (two layouts) → US3 (delta direction + two-column) → US4 (opening per layout) → US5 (narration stitching)
→ US6 (serial/period/last-4) → US7 (savings-vs-CC gate) → US8 (config-on-base + the shared helper) — each an
independent test increment over the same engine, already verified by the fixtures/parity/unit/Swift tests authored
in Phases 2–4. Then lock the **guards**: US9 (golden parity — both layouts, no prior-fixture migration) and US10
(inherited privacy-egress + Swift reachability). Finish with the full-gate run (T017) and Ship (T019–T020, two
commits + PR #8).

### Story → task traceability

| Story | Delivered by | Independently verified by |
|---|---|---|
| **US1** on-device parse 🎯 | T007, T008, T009, T010, T011, T012, T013 | **T011** (Rust parity, both layouts), **T013** (Swift), **T005** claim-split |
| **US2** two layouts / first-match-wins | T009 (`anchor_res` → `[COMPACT, DETAILED]`) on the reused base | **T009** unit tests + **T003/T004** (mutual exclusion) + **T005**/**T013** |
| **US3** delta direction / amount-as-check (+ two-column) | reused `read_ledger_lines`/`anchor_amount` + T009 anchors | **T009** unit test (detailed non-zero side) + **T003/T004** + reused delta-flip test |
| **US4** opening per layout / opening-anchored row-1 | T009 (`OPENING_RE` inline + summary alts) + reused row-1 bootstrap | **T009** unit test (compact summary opening) + **T003/T004** + **T005** |
| **US5** narration stitching (quirks) | reused `stitch_narration` | **T003/T004** (byte-exact `description_raw`) + **T005** + **T013** |
| **US6** ledger metadata + account last-4 | T009 (`serial`/`PERIOD_RE`/`HDFC_ACCOUNT_RE`) + T007 (`account_tail_last4`) | **T009** + **T007** (`3425`) unit tests + **T003/T004** + **T005**/**T013** |
| **US7** savings-vs-CC gate | T009 (`claim_all`/`claim_any`) + reused `claims_ledger` | **T009** unit test + **T005** (`hdfc_bank_claims` split) + **T013** |
| **US8** config-on-base + one shared addition | T007 (`account_tail_last4` + OD-1) + T008 (ICICI consumes it) + T009 | **T011** (prior cases green; ICICI `3456`) + **T018** review |
| **US9** golden parity 🛡️ | T003, T004, T005, T011 | **T014** (whole-slice guard; both layouts; no prior migration) |
| **US10** privacy + bridge 🛡️ | *inherited* gate + T005 determinism + T010/T013 UniFFI | **T015** (privacy-egress + no-new-dep + reachability) |

---

## Notes

- **Test-first is mandatory** (Principle V, FR-033): T003–T006 are RED before Phase 3; T011 greens the Rust parity
  + chain + claim-split + unit guards, T013 greens the Swift bridge — each has an explicit RED→GREEN verify step.
  The two `expected` blocks are the **locked characterization ground truth** (`hdfc-bank-ground-truth.json`; no
  live capture needed — `quickstart.md` §0/§6).
- **Design is LOCKED** in `plan.md`/`data-model.md`/`contracts/` — the porting tasks **sequence** it, they do not
  re-derive it. Every value (2 rows/layout, ledger metadata, printed `100000.00`/`145000.00`, period, serials,
  `3425`, RECONCILED chain, the stitched narrations) is pinned in `contracts/golden-fixture.md` and research
  **D4–D6**.
- **Use the REAL landed symbols, not the contracts' drift**: `ParsedTransaction` (`value_date`) via
  `ParsedStatement.lines`; `check_balance_chain(statement: ParsedStatement) -> ChainResult` with
  `result.status == ChainStatus::Reconciled`. (The fixture JSON key is `expected.rows[]` — unchanged.)
- **OD-1 is approved** and is the one shared touch beyond `account_tail_last4`: reorder `DATE_FORMATS` so
  `%d/%m/%y` precedes `%d/%m/%Y` (guarded by T007's `parse_date` regression + the compact `Case`). No base change;
  no input normalization hook.
- **Two-place amount-vs-delta** (research **D6**): the **reader** records **exact** `amount == |delta|`; the
  **₹1.00 tolerance** lives **ONLY** in `balance_chain::check`. Keep them separate.
- **Direction is delta-derived** in both layouts, never the amount's sign/column (FR-007); row 0 opening-anchored
  (`OpeningBalance`), later rows `BalanceDelta`; HDFC exercises no x-position path (no `column_split_x`).
- **`card_last4 "3425"`** via the shared `account_tail_last4(text, primary)` (HDFC's `X*`/4+-digit primary else
  the longest `\d{9,}` run) — **not** `find_last4`/masked-PAN.
- **Additive & back-compatible**: no records/enums/FFI types added; the harness schema is untouched (extended in
  007), so the **7 prior fixtures need NO migration**; the ICICI refactor keeps its fixture green. **No new
  dependency** (runtime *or* dev); money is `Decimal` (no geometry exercised).
- **REUSE, not rebuild**: the ledger base (`ledger_reader.rs`), the balance chain (`balance_chain.rs`),
  `common.rs` (`parse_amount`/`parse_date`, both HDFC date formats present), `base.rs` records, the
  `tests/parity.rs` harness, the `ffi.rs` `Decimal`/`NaiveDate` bridges + the reused `check_balance_chain`, and
  the privacy-egress gate are inherited. The **only** NEW code is `account_tail_last4` + the HDFC config + FFI +
  fixtures + tests (+ the approved OD-1 reorder).
- **iOS gate ordering**: `make core-xcframework` **before** `tuist generate` (`Makefile:32`); **iPhone 16**
  simulator; CI iOS job pinned to **macos-15**.
- **[P]** = different files, no unfinished dependency. `[Story]` labels map each task to its user story.
- **Generation commits nothing**; the two commits + PR #8 + `--rebase --delete-branch` merge are **Phase 15:
  Ship**, executed by the implementer after every gate is green.
