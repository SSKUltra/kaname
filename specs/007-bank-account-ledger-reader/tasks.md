---
description: "Task list — Bank-Account Balance-Ledger Reader (second reader family: 1 new base + 1 integrity module + 1 ICICI reference reader + additive data-model, zero new deps)"
---

# Tasks: Read a Bank-Account (Savings/Current) Statement On-Device — the Balance-Ledger Reader Base + Balance-Chain Integrity + ICICI as the First Reference Reader

**Input**: Design documents from `/specs/007-bank-account-ledger-reader/`
**Prerequisites**: `plan.md`, `spec.md` (US1–US9), `research.md` (D1–D12), `data-model.md`,
`contracts/ledger-base.md`, `contracts/engine-ffi.md`, `contracts/golden-fixture.md`, `quickstart.md`

**Tests**: REQUIRED and **TEST-FIRST** for this slice (Constitution Principle V). The golden fixture, the
failing Rust parity `Case` row (+ the dedicated balance-chain RECONCILED test + the `icici_bank_claims`
accept/reject split), and the failing Swift "core ↔ Swift ICICI bank parse + balance chain" test are all
authored **RED, before** the engine that greens them (FR-033).

**Port source of truth** (faithful, byte-for-byte with the golden vector — the design is **LOCKED** in
`plan.md`/`data-model.md`/`contracts/`; do **not** re-derive it, just sequence it): the web engine's
`.../ingestion/statement_readers/_ledger_reader.py` (`BalanceLedgerStatementReader`),
`.../ingestion/balance_chain.py` (`check`), and `.../statement_readers/icici_bank.py`, whose captured output
is the persisted ground truth `icici-bank-ground-truth.json`. **No live run needed** (`quickstart.md` §0).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: `US1`=on-device parse (MVP) · `US2`=delta direction / amount as integrity check · `US3`=reusable
  ledger base (anchors + narration) · `US4`=balance chain (RECONCILED/NEEDS_REVIEW/suspect) · `US5`=row-1
  bootstrap (opening→x-position→provisional) · `US6`=ledger metadata + account last-4 · `US7`=savings-vs-CC
  claim gate · `US8`=golden parity · `US9`=privacy-egress + Swift bridge. Setup/Polish/Ship carry no label.
- Exact file paths are included in every task.

> **Note (this slice commits nothing during generation).** `/speckit.tasks` only writes this file. The
> **three** commits + PR #7 + merge are encoded as the final **Phase 14: Ship** and are executed by the
> implementer **only after** every gate is green (per the requester's step 7).

## ♻️ REUSE — do NOT re-create (this slice adds 1 base + 1 chain module + 1 reader + additive records)

This is the **second reader family**, but it plugs into the credit-card foundations and adds **ZERO new
dependency** (runtime *or* dev). Do **not** rebuild any of these:

- `statement/common.rs` — `parse_amount` (`common.rs:50`) / `parse_date` (`common.rs:58`). **Both** ICICI
  savings formats are **already present**: the dotted anchor date `"%d.%m.%Y",  // 16.06.2025` (`common.rs:30`)
  and the full-month header `"%B %d, %Y", // June 16, 2025` (`common.rs:29`) — used for the `period_*` enrich
  (research **D5/D8**). The two-column `anchor_amount` needs a **local** `loose_amount` (comma-strip +
  `Decimal::from_str`, accepts bare integers) because `parse_amount` mandates `\d+\.\d{2}` (research **D4**).
- `statement/model.rs` — `Direction` (`uniffi::Enum`, `model.rs:13`) reused **unchanged**. The ledger family
  derives it from the **running-balance delta**, so `statement/polarity.rs` `classify`/`Dr`/`Cr` is **NOT**
  used here (that path is credit-card only; data-model.md §Direction).
- `statement/base.rs` — `ParsedStatement`/`ParsedTransaction` records (`base.rs:25–48`), `ParsedStatement::new`
  (`base.rs:50–62`), `MAX_RAW` (`base.rs:15`) + `truncate_chars` (`base.rs:18`). This slice **extends** them
  **additively** (below); it does not fork them.
- `ffi.rs` — the `Decimal`/`NaiveDate` custom-type bridges (`ffi.rs:22–33`) reused **unchanged** (**no
  `uniffi.toml` change**); the new records/enums derive `uniffi` and reuse those bridges.
- `tests/parity.rs` — the golden-fixture harness (`parity.rs`), extended **back-compatibly** with
  `#[serde(default)]` optional ledger fields — the exact pattern already used for `period_start`
  (`parity.rs:30–33`). **The five existing credit-card fixtures need NO migration** (they omit the new keys →
  deserialize unchanged — research **D9**).
- The **privacy-egress gate** (`make core-privacy-audit`, `Makefile:22`) and CI — inherited **unchanged**
  (**no new dependency** → byte-identical shipped `cargo tree` graph; research **D1**).

**The only NEW code**: additive fields/records in `base.rs`; a **1-line** `ledger: None` ripple in
`line_reader.rs`; **3 new modules** `statement/{ledger_reader,balance_chain,icici_bank}.rs`; **3**
`#[uniffi::export]` functions (`read_icici_bank_statement` / `icici_bank_claims` / `check_balance_chain`) +
`lib.rs` re-exports + `statement/mod.rs` wiring; **1** golden fixture; **1** parity `Case` row + a dedicated
chain test + a claim-split test; **1** Swift test. **No new dependency; no new custom-type bridge.**

## ⚠️ Local gotchas (apply throughout)

- **`make core-xcframework` MUST run before `tuist generate`** (`ios-gen: core-xcframework`, `Makefile:32`) —
  the generated Swift + `KanameCoreFFI.xcframework` are git-ignored **rebuilt** artifacts (`quickstart.md` §3).
- **Local Xcode needs an explicitly-created "iPhone 16" simulator** for `make ios-test`
  (`xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'`, `Makefile:36–37`); CI pins
  **`macos-15`** for the iOS job.
- **Money is `Decimal`, never `f64`** — amounts, balances, deltas, and the ₹1.00 tolerance are all `Decimal`;
  Indian grouping (`1,00,000.00`) is stripped and scale preserved (`100000.00`). The **only** `f64` on this
  surface is `Word.x0/x1` — **layout points, not money** (SC-009). Fixture money is stored as **JSON strings**,
  re-parsed via `Decimal::from_str` (never float).
- **Direction is DELTA-DERIVED** — `Debit` when the running balance falls, `Credit` when it rises; **never**
  the amount's sign/magnitude. Row 1 resolves by precedence **opening balance → x-position → provisional**,
  recorded per row as `direction_source` (FR-008/013/014).
- **Two-place amount-vs-delta design** (research **D6**, `plan.md` §Complexity Tracking): the **reader**
  records **exact** `amount == |delta|` (`amount_matches_delta`); the **₹1.00 tolerance** lives **ONLY** in
  `balance_chain::check`. Keep them in their two places — do not unify.
- **`card_last4` is `"3456"`** here, via the **account-number** tail extractor
  (`(?i)Account\s+(?:Number|No\.?)\s*:?\s*([0-9]{6,})` → last 4; fallback: longest ≥9-digit run) — **NOT** the
  credit-card `find_last4`/masked-PAN matcher (research **D10**, FR-022).
- **Encoding**: the reference fixture is plain **ASCII/UTF-8** (no middot/rupee glyphs this slice).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the invariants and prerequisites so every later task has a place to land and the gates
stay green. No behavior yet.

- [ ] T001 [P] Confirm the **no-new-dependency** invariant: `core/crates/kaname-core/Cargo.toml` stays **UNCHANGED** (runtime `regex`/`rust_decimal`/`chrono`/`serde`/`uniffi` + dev-only `serde_json` already present) — this slice adds **zero** deps (FR-034, SC-010/014). Create the fixtures home directory `fixtures/icici/bank_account/` (alongside the existing `fixtures/icici/credit_card/`). Ref: `plan.md` §Summary/§Project Structure, `contracts/golden-fixture.md` §Fixture.
- [ ] T002 [P] Verify local prerequisites & gotchas (no code): `cargo` on PATH (`source "$HOME/.cargo/env"`); iOS targets present (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`); an **"iPhone 16" simulator** exists in Xcode; recall `make core-xcframework` precedes `tuist generate` (`Makefile:32`); confirm `common.rs` **already** carries `%d.%m.%Y` (`common.rs:30`) and `%B %d, %Y` (`common.rs:29`) so **no** date-format change is needed. Ref: `quickstart.md` §Prerequisites.

**Checkpoint**: Fixtures home exists, no manifest change needed, toolchain ready.

---

## Phase 2: Test-First Foundation (⚠️ Principle V — author RED before ANY engine code)

**Purpose**: Pin the on-device engine to the proven web engine **before** writing it. These are the parity
(US8), chain (US4), claim-split (US7), and bridge (US1/US9) tests that **protect the whole slice**; they MUST
be **RED** at the end of this phase (`read_icici_bank_statement` / `icici_bank_claims` / `check_balance_chain`
do not exist yet).

**⚠️ CRITICAL**: No engine code (Phase 3+) may be written until T003–T005 exist and are verified failing.

- [ ] T003 [P] [US8] Author the **ported** golden vector `fixtures/icici/bank_account/basic.json` — copy the **EXACT fixture bytes** pinned in `contracts/golden-fixture.md` §"Exact fixture bytes" (do **not** hand-derive). `lines` = the 12 synthetic ICICI-savings lines (header, `Account Number 000401000123456`, `Statement Period June 16, 2025 to July 15, 2025`, `Opening Balance 1,00,000.00`, the column header, the three narration+anchor pairs, `Closing Balance 1,43,000.00`); `full_text` = the `\n`-joined same. `expected.rows` = the **3** rows: `{2025-06-16, "5000.00", Debit, INR, "UPI/512345/ALICE STORE/Payment", balance "95000.00", balance_delta "-5000.00", direction_source "OpeningBalance", serial "1", amount_matches_delta true, is_suspect false}`, `{2025-06-18, "50000.00", Credit, INR, "NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY", "145000.00", "50000.00", "BalanceDelta", "2", true, false}`, `{2025-06-20, "2000.00", Debit, INR, "ATM CASH WITHDRAWAL", "143000.00", "-2000.00", "BalanceDelta", "3", true, false}`; `period_start "2025-06-16"`, `period_end "2025-07-15"`, `card_last4 "3456"`, `printed_opening_balance "100000.00"`, `printed_closing_balance "143000.00"`, `errored_lines []`. All money is **JSON strings** (re-parsed to `Decimal`, never `f64`); Indian grouping stripped, scale preserved. **100% synthetic/redacted** (FR-032, SC-008). Ref: `contracts/golden-fixture.md` §Exact fixture bytes, `quickstart.md` §0.
- [ ] T004 [US8] Extend the parity harness `core/crates/kaname-core/tests/parity.rs` → **RED** (back-compatible schema extension — mirror the existing `#[serde(default)] period_start` pattern at `parity.rs:30–33`; **do NOT touch the 5 CC fixtures/rows**):
  - Extend `use kaname_core::{…}` (`parity.rs:12–16`) to add `read_icici_bank_statement, icici_bank_claims, check_balance_chain` and the enums `DirectionSource, ChainStatus` (for the new fields/assertions).
  - Add optional `#[serde(default)]` ledger fields to `struct ExpectedRow` (`parity.rs:39–46`): `balance: Option<String>`, `balance_delta: Option<String>`, `direction_source: Option<DirectionSource>`, `serial: Option<String>`, `amount_matches_delta: Option<bool>`, `is_suspect: Option<bool>` (each `Option`/defaulted → CC rows omit them, deserialize unchanged). Add optional `#[serde(default)] printed_opening_balance: Option<String>` / `printed_closing_balance: Option<String>` to `struct Expected` (`parity.rs:27–37`).
  - Add the wrapper `fn parse_icici_bank(lines: Vec<String>, full_text: String) -> ParsedStatement { kaname_core::read_icici_bank_statement(lines, full_text, Vec::new()) }` (empty geometry — the fixture is opening-balance-anchored) and **one** `Case` row to `CASES` (`parity.rs:55–86`, after the Federal case): `Case { label: "ICICI bank", parse: parse_icici_bank, rel_path: "icici/bank_account/basic.json" }`.
  - In `assert_matches_expected` (`parity.rs:98–133`) assert each ledger field **only when `Some`** (so `direction_source` deserializes into `DirectionSource` exactly as `direction` → `Direction`); assert `statement.printed_opening_balance`/`printed_closing_balance` when the fixture supplies them.
  - Add a **dedicated** chain parity test `icici_bank_chain_reconciles`: `check_balance_chain(parse_icici_bank(fx.lines, fx.full_text))` == `ChainResult { status: Reconciled, checked_rows: 3, suspect_count: 0, suspects: [], row1_direction_fallback: false, derived_opening_balance: Some(100000.00), derived_closing_balance: Some(143000.00), reason: None }` (SC-002).
  - Add `icici_bank_claims_accepts_savings_and_rejects_credit_card` (mirror `parity.rs:154–165`): `icici_bank_claims(bank fx.full_text) == true`; `== false` for an ICICI **credit-card** text (e.g. the `icici/credit_card/basic.json` full_text); and confirm `icici_claims(credit-card text) == true` **still holds** (SC-007).
  - ⚠️ **Verify RED**: `make core-test` **fails to compile** (`read_icici_bank_statement`/`icici_bank_claims`/`check_balance_chain`/`DirectionSource`/`ChainStatus` absent). Ref: `contracts/golden-fixture.md` §Harness schema extension, `data-model.md` §Test surface, research **D9**.
- [ ] T005 [P] [US1] Author the **RED** Swift bridge test `ios/Tests/ICICIBankParseTests.swift` — "core ↔ Swift ICICI bank parse + balance chain" (`import KanameCore`, Swift Testing), mirroring `ios/Tests/ICICIParseTests.swift`: build `lines`/`fullText` with `[...].joined(separator: "\n")`; call `readIciciBankStatement(lines:fullText:firstRowWords: [])` (empty geometry). Assert **3** rows — `valueDate`, exact `Decimal(string:locale: Locale(identifier: "en_US_POSIX"))` amounts (`"5000.00"`/`"50000.00"`/`"2000.00"`), `.debit`/`.credit`/`.debit` (**delta-derived**), `descriptionRaw`; each row's `ledger` — `balance` (`95000.00`/`145000.00`/`143000.00`), `balanceDelta`, `directionSource` (`.openingBalance`, `.balanceDelta`, `.balanceDelta`), `serial` (`"1"`/`"2"`/`"3"`), `amountMatchesDelta`/`isSuspect`; plus `printedOpeningBalance 100000.00`, `printedClosingBalance 143000.00`, `periodStart "2025-06-16"`, `periodEnd "2025-07-15"`, `cardLast4 "3456"`. Use `try #require(statement.lines.first)`. Assert `checkBalanceChain(statement) == .reconciled` (via `status`), `suspectCount == 0`, `row1DirectionFallback == false`. Assert `iciciBankClaims(fullText) == true` and `iciciBankClaims(<ICICI credit-card text>) == false` (rejects the CC statement). Amounts compared as exact `Foundation.Decimal` (never `Double`). ⚠️ **Verify RED**: won't build until the xcframework is regenerated with the exports in Phase 4. Ref: `contracts/engine-ffi.md` §Swift bridge test, `ios/Tests/ICICIParseTests.swift`.

**Checkpoint**: Fixture in place; Rust parity harness RED (new `Case` row + chain test + claim-split won't compile); Swift bridge test RED. Test-first satisfied — engine code may now begin.

---

## Phase 3: User Story 1 — Turn an ICICI savings/current statement into transactions, on-device (Priority: P1) 🎯 MVP

**Goal**: Recognize an ICICI **bank-account** statement and return one transaction per ledger row (date, exact
amount, **delta-derived** direction, INR, stitched description) — 100% on-device. Building the engine here
**also lands the behaviors** US2–US7 verify independently in Phases 5–10.

**Independent Test**: `read_icici_bank_statement(basic.lines, basic.full_text, vec![])` returns the 3 expected
rows and `icici_bank_claims` accepts the savings statement / rejects the ICICI credit-card statement — with no
network in the parse path.

> Engine landing order follows the plan's dependency chain (step 4a→4e): **base.rs data-model → line_reader.rs
> ripple → ledger_reader.rs (base) → balance_chain.rs (check) → icici_bank.rs (config) → ffi.rs + lib.rs +
> mod.rs wiring → green**. The design is **LOCKED** in `data-model.md`/`contracts/` — port it, don't re-derive.

- [ ] T006 [US1] **(step 4a) Additive data-model in `core/crates/kaname-core/src/statement/base.rs`** (research **D8**, `data-model.md` §Extended records / §New records): add `pub ledger: Option<LedgerMetadata>` to `ParsedTransaction` (`base.rs:25–33`); add `pub printed_opening_balance: Option<Decimal>` and `pub printed_closing_balance: Option<Decimal>` to `ParsedStatement` (`base.rs:36–48`) and default **both** to `None` in `ParsedStatement::new` (`base.rs:50–62`). Add three new items (all deriving the same `Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record`/`uniffi::Enum` set as the existing records): `struct LedgerMetadata { balance: Decimal, balance_delta: Option<Decimal>, amount_matches_delta: bool, is_suspect: bool, direction_source: DirectionSource, serial: String }`; `enum DirectionSource { OpeningBalance, BalanceDelta, Row1XPosition, Row1Provisional }`; `struct Word { text: String, x0: f64, x1: f64 }` (x-coords are **layout points, not money**). Keep money as `Decimal` throughout; only `Word.x0/x1` are `f64`. Ref: `data-model.md` §`LedgerMetadata`/§`DirectionSource`/§`Word`, `contracts/engine-ffi.md` §New types.
- [ ] T007 [P] [US1] **(step 4a cont.) CC-path ripple** — in `core/crates/kaname-core/src/statement/line_reader.rs`, the single `ParsedTransaction { … }` constructor (`line_reader.rs:77–84`) gains **`ledger: None,`** (credit-card rows carry no ledger metadata). This is the **only** touch to the CC path; the 5 CC fixtures need **no migration** (the field is `Option`, absent for cards — research **D9**). Depends on T006. [P] vs T008/T009 (different file). Ref: `plan.md` §Complexity Tracking, `data-model.md` §`ParsedTransaction`.
- [ ] T008 [P] [US1] **(step 4b) The reusable base — `core/crates/kaname-core/src/statement/ledger_reader.rs` (NEW)** — port `_ledger_reader.py` 1:1 (contract `contracts/ledger-base.md`). Define `pub trait LedgerReaderConfig` with `bank_code`, `claim_all`, `claim_any`, `anchor_res() -> &'static [&'static Regex]` (first-match-wins), `opening_balance_re`/`closing_balance_re -> Option<&'static Regex>`, `column_split_x() -> Option<f64>`, and defaulted `provisional_direction() -> Direction { Direction::Debit }`, `enrich(&self, _s: &mut ParsedStatement, _full_text: &str) {}`, `account_tail(&self, _text: &str) -> Option<String> { None }`. Free fns `pub fn read_ledger_lines<C: LedgerReaderConfig + ?Sized>(cfg, lines: &[String], full_text: &str, first_row_words: &[Word]) -> ParsedStatement` and `pub fn claims_ledger<C>(cfg, text, bank_code) -> bool` (bank_code match **and** ALL `claim_all` **and** (`claim_any` empty OR ANY `claim_any`), case-insensitive). Private internals ported 1:1: `find_anchors` (named groups `serial/date/desc/amount`|`withdrawal`+`deposit`/`balance`; unparseable date/amount/balance → `errored_lines` via `truncate_chars(line, MAX_RAW)` — **D2**), `anchor_amount` (single `amount` via `parse_amount` else the **non-zero** withdrawal/deposit side via a **local `loose_amount`** = comma-strip + `Decimal::from_str`, accepting bare integers — **D4**), `stitch_narration` (line-above + lines-below to next anchor, skipping anchors + balance lines, inline `desc` prepended, ≤240 cp — **D3**), `row1_direction` + `direction_from_x_position` (opening→x-position→provisional, returns `(Direction, DirectionSource, prev_balance)` — **D5**), `is_balance_line`, `extract_balance`, `derived_opening` (**D7**). `read_ledger_lines` flow: extract `opening` via `opening_balance_re`; `find_anchors`; push errored lines; if no anchors → `enrich` + return; else walk anchors computing row-1 `(direction, source, prev)` then delta-direction for later rows, `balance_delta`/`amount_matches_delta` (**exact** `amount == delta.abs()` — **no** tolerance here) / `is_suspect = !amount_matches_delta`, pushing `ParsedTransaction` with `Some(LedgerMetadata{..})`; set `printed_opening_balance` (printed else `derived_opening(row1)`) and `printed_closing_balance` (last anchor); `enrich`. **Pure/total — never panics.** `use` `std::sync::LazyLock`? (no statics here — the configs own the regexes); `regex::Regex`; `crate::model::Direction`; `crate::statement::base::{ParsedStatement, ParsedTransaction, LedgerMetadata, DirectionSource, Word, truncate_chars, MAX_RAW}`; `crate::statement::common::{parse_amount, parse_date}`. Depends on T006. [P] vs T007/T009. Ref: `contracts/ledger-base.md` §`LedgerReaderConfig`/§`read_ledger_lines`/§`claims_ledger`, research **D1–D5/D7**.
- [ ] T009 [P] [US1] **(step 4c) The integrity check — `core/crates/kaname-core/src/statement/balance_chain.rs` (NEW)** — port `balance_chain.check` 1:1 (contract `contracts/ledger-base.md` §`balance_chain::check`, research **D11**). Define `pub enum ChainStatus { Reconciled, NeedsReview }`; `pub struct Suspect { row: u32, serial: Option<String>, amount: Decimal, reason: String }`; `pub struct ChainResult { status, checked_rows: u32, suspect_count: u32, suspects: Vec<Suspect>, row1_direction_fallback: bool, derived_opening_balance: Option<Decimal>, derived_closing_balance: Option<Decimal>, reason: Option<String> }` (all `uniffi`). `pub fn check(statement: &ParsedStatement) -> ChainResult`: empty `lines` → `NeedsReview`, `checked_rows: 0`, `reason: Some("no parsed transactions")`; else walk 1-based from `prev = statement.printed_opening_balance`, reading `balance`/`source` from `row.ledger`; a row missing its ledger/balance ⇒ suspect `"missing running balance"`; `derived_row1 = (row == 1 && source ∈ {Row1XPosition, Row1Provisional})`; when `prev.is_some() && !derived_row1`: `delta = balance − prev`; if `(amount − delta.abs()).abs() > Decimal::from_str("1.00")` ⇒ suspect `"amount {amount} != |balance delta| {abs}"`; `prev = balance`. `row1_direction_fallback = lines[0].ledger.direction_source ∈ {Row1XPosition, Row1Provisional}`; `status = Reconciled` **iff** `suspects.is_empty() && !row1_direction_fallback`; `suspects` truncated to **20** with `suspect_count` = true count; echo `derived_opening_balance`/`derived_closing_balance` from the statement's `printed_*`. **⚠️ The ₹1.00 tolerance lives ONLY here** (research **D6**). Pure & deterministic. Depends on T006 (reads `ParsedStatement`/`ledger`). [P] vs T007/T008 (different file). Ref: `contracts/ledger-base.md` §`balance_chain::check`, `data-model.md` §Balance-chain types, research **D6/D11**.
- [ ] T010 [US1] **(step 4d) The ICICI reference config — `core/crates/kaname-core/src/statement/icici_bank.rs` (NEW)** + wire `statement/mod.rs`. Port `icici_bank.py` to a **zero-sized** `pub struct IciciBankReader;` `impl LedgerReaderConfig` with `BANK_CODE = "ICICI"`. Each regex is a `static` built once via `LazyLock<Regex>`: `ANCHOR_RE` = `^(?P<serial>\d{1,4})\s+(?P<date>\d{2}\.\d{2}\.\d{4})(?:\s+\d{2}\.\d{2}\.\d{4})?\s+(?P<desc>.*?)\s*(?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$`; `OPENING_RE` = `(?i)(?:Opening Balance|BALANCE\s+B/F|B/F)\s+([\d,]+\.\d{2})`; `CLOSING_RE` = `(?i)Closing Balance\s+([\d,]+\.\d{2})`; `PERIOD_RE` = `(?i)([A-Za-z]+ \d{1,2}, \d{4})\s+to\s+([A-Za-z]+ \d{1,2}, \d{4})`; `ACCOUNT_RE` = `(?i)Account\s+(?:Number|No\.?)\s*:?\s*([0-9]{6,})`. Trait methods: `anchor_res()` → `&[&ANCHOR_RE]`; `opening_balance_re()`/`closing_balance_re()` → `Some(&OPENING_RE)`/`Some(&CLOSING_RE)`; `column_split_x()` → `Some(400.0)`; `claim_all()` → `["Statement of Transactions", "ICICI"]`; `claim_any()` → `["Saving", "Current"]`; `enrich()` → `PERIOD_RE` → `period_start`/`period_end` via `parse_date` (`%B %d, %Y`), then `statement.card_last4 = self.account_tail(full_text)`; `account_tail()` → `ACCOUNT_RE` group-1 last-4, **fallback** longest ≥9-digit run's last-4 (research **D10** — a **bank-account** tail, NOT `find_last4`/masked-PAN → yields `"3456"`). Add `pub mod ledger_reader; pub mod balance_chain; pub mod icici_bank;` to `core/crates/kaname-core/src/statement/mod.rs` (keep alphabetical; `mod.rs:9–17`) and re-export new public types alongside `mod.rs:19` (`pub use base::{…, LedgerMetadata, DirectionSource, Word}; pub use balance_chain::{ChainResult, ChainStatus, Suspect};` as needed). Depends on T008. Ref: `data-model.md` §`IciciBankReader`, `contracts/ledger-base.md` §Adding a later bank, research **D8/D10**.
- [ ] T011 [US1] **(step 4e) FFI exports + re-exports** — in `core/crates/kaname-core/src/ffi.rs` (ICICI-style inline, mirroring `ffi.rs:53–63`): `use crate::statement::icici_bank::IciciBankReader;`, `use crate::statement::ledger_reader::{claims_ledger, read_ledger_lines};`, `use crate::statement::balance_chain;`, `use crate::statement::base::{Word, ...};` then `#[uniffi::export] pub fn read_icici_bank_statement(lines: Vec<String>, full_text: String, first_row_words: Vec<Word>) -> ParsedStatement { read_ledger_lines(&IciciBankReader, &lines, &full_text, &first_row_words) }`; `#[uniffi::export] pub fn icici_bank_claims(full_text: String) -> bool { claims_ledger(&IciciBankReader, &full_text, "ICICI") }`; `#[uniffi::export] pub fn check_balance_chain(statement: ParsedStatement) -> ChainResult { balance_chain::check(&statement) }`. Reuse the existing `Decimal`/`NaiveDate` custom types unchanged (`ffi.rs:22–33`) — **no `uniffi.toml` change**. Re-export all three fns + the new record/enum types in `core/crates/kaname-core/src/lib.rs` (extend the `pub use ffi::{…}` block `lib.rs:28–31` and the `pub use statement::{…}` line `lib.rs:33` so `LedgerMetadata`/`DirectionSource`/`Word`/`ChainResult`/`ChainStatus`/`Suspect` are reachable from `tests/parity.rs` and the app path). Depends on T009 + T010. Ref: `contracts/engine-ffi.md` §Exported functions, research **D12**.
- [ ] T012 [US1] **Green the engine side**: run `make core-fmt` (rustfmt), then `make core-test` — the parity `Case` row (T004) now **PASSES** for the ICICI-bank vector (3 rows exact incl. ledger fields; `printed_opening 100000.00`/`printed_closing 143000.00`; `period 2025-06-16→2025-07-15`; `card_last4 "3456"`; `errored_lines []`), the dedicated `icici_bank_chain_reconciles` test (RECONCILED, 0 suspects, no fallback), the claim-split test, and determinism — while **all 5 credit-card parity cases stay green** (fixtures untouched) — then `make core-lint` (fmt `--check` + clippy `-D warnings`). Verify **RED→GREEN** for the Rust harness. Ref: `quickstart.md` §1.

**Checkpoint**: The engine parses the golden ICICI-bank statement, the balance chain reconciles it, and the Rust parity + chain + claim-split + determinism tests are green (Swift bridge greened in Phase 4). US1 is functional on the Rust side.

---

## Phase 4: UniFFI bridge — regenerate the xcframework + green the Swift test (US1 / US9)

**Goal**: Surface the three new functions + the new records/enums to Swift and green the "core ↔ Swift ICICI
bank parse + balance chain" test.

- [ ] T013 [US1] Run `make core-xcframework` to rebuild `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift` (git-ignored artifacts) now exposing `readIciciBankStatement` / `iciciBankClaims` / `checkBalanceChain` and generating the new Swift types `Word`, `LedgerMetadata`, `DirectionSource`, `ChainResult`, `ChainStatus`, `Suspect` (plus the additive `ledger`/`printedOpeningBalance`/`printedClosingBalance` on the existing records). ⚠️ **MUST run before `tuist generate`** (`Makefile:32`, `quickstart.md` §3). Ref: `contracts/engine-ffi.md` §Types crossing the boundary.
- [ ] T014 [US1] Run `make ios-test` (`ios-gen` → `core-xcframework` → `tuist generate` → `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test`) to **green** `ios/Tests/ICICIBankParseTests.swift` (T005) — the 3 rows with exact `Foundation.Decimal` amounts, delta-derived `.debit`/`.credit`, per-row `ledger` (balance / `directionSource` / serial), `printedOpeningBalance 100000.00`, `printedClosingBalance 143000.00`, `periodStart`/`End`, `cardLast4 "3456"`, `checkBalanceChain(...) == .reconciled` (suspectCount 0, no row-1 fallback), and `iciciBankClaims` accept-savings / reject-credit-card. ⚠️ **Local Xcode: create the "iPhone 16" simulator first.** Verify **RED→GREEN** for the Swift bridge test. Ref: `quickstart.md` §4.

**Checkpoint**: US1 MVP delivered end-to-end (Rust engine + balance chain + Swift bridge). A person's ICICI savings/current statement text → transactions + a RECONCILED verdict, on-device.

---

## Phase 5: User Story 2 — Direction from the running-balance delta; amount as an independent integrity check (Priority: P2)

**Goal**: Each transaction's direction is decided **solely** by the running-balance movement (fall ⇒ debit,
rise ⇒ credit); the printed amount is an **independent** check (`amount == |delta|`). The amount's
sign/magnitude **never** drives direction. *(Impl landed in T008's `read_ledger_lines`/delta logic.)*

**Independent Test**: Rows whose balance rises classify credit and rows whose balance falls classify debit;
flipping a row's balance movement (independent of its printed amount) flips its direction.

- [ ] T015 [US2] Add the **delta-flip** direction unit test(s) in `core/crates/kaname-core/src/statement/ledger_reader.rs` (`#[cfg(test)]`, driving `read_ledger_lines` with a small synthetic single-amount config): a row whose balance **falls** (`100000 → 95000`) → **Debit** (US2-AC1); a row whose balance **rises** (`95000 → 145000`) → **Credit** (US2-AC2); **flip** the surrounding balances for a fixed printed amount and confirm the direction **flips** debit↔credit while the amount is unchanged — proving the amount never drives direction (US2-AC3, SC-003, FR-008); a row whose `amount == |delta|` within the reader's **exact** check → `amount_matches_delta == true`, `is_suspect == false` (US2-AC4); and confirm `direction_source == BalanceDelta` for every non-first row (FR-014). Ref: research **D5/D6**, spec US2.

**Checkpoint**: Direction is provably sourced from the balance delta, and the amount is a pure cross-check.

---

## Phase 6: User Story 3 — A reusable balance-ledger reader base: anchor rows + narration stitching (Priority: P3)

**Goal**: The parse is delivered by a per-issuer config plugged into the shared `LedgerReaderConfig` base; the
base recognizes anchor rows via named groups, ignores header/cheque lines, stitches narration, **and** supports
a two-column Withdrawal/Deposit/Balance template for later banks. *(Impl landed in T008/T010.)*

**Independent Test**: ICICI is a config on the base; an anchor row is captured via named groups; header/cheque
lines (no decimal money tokens) are not anchors; narration = line-above + lines-below to the next anchor,
skipping anchors + balance lines; the two-column template also parses.

- [ ] T016 [US3] Add anchor/narration unit tests in `core/crates/kaname-core/src/statement/ledger_reader.rs` (`#[cfg(test)]`; **same file as T015 → sequential**): a single-amount ICICI-shaped row `… <amount> <balance>` captures `serial/date/amount/balance` via the named groups (US3-AC1); a per-page **header** line and a **cheque-number** line (no decimal money tokens) are **not** anchors → no transaction, no error (US3-AC2, FR-006); narration stitches the payer/VPA line **above** + detail lines **below** to the next anchor, **skipping** other anchors and balance lines → `UPI/512345/ALICE STORE/Payment`, `NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY`, `ATM CASH WITHDRAWAL` (US3-AC3, FR-007, ≤240 cp); an empty/anchor-less input → empty `lines`, no error (edge case). Ref: research **D2/D3**, spec US3, `contracts/ledger-base.md` §`read_ledger_lines`.
- [ ] T017 [US3] Add the **two-column loose-integer** `anchor_amount` unit test in `core/crates/kaname-core/src/statement/ledger_reader.rs` (`#[cfg(test)]`; sequential) — since ICICI's fixture exercises only the single-`amount` path, drive a **synthetic two-column config** whose anchor regex has `withdrawal`+`deposit` named groups (or call `anchor_amount` directly on a targeted `Captures`): a withdrawal cell of a **bare integer** (`0`/`59`/`50000`) and a decimal (`1,314.90`) parse via the local `loose_amount` (comma-strip + `Decimal::from_str`), returning the **non-zero** side (withdrawal first, then deposit); confirm direction is **still** delta-derived regardless of which column supplied the amount (US3-AC4, FR-005, research **D4**). Note in the test that this path is **dormant for ICICI** but proves the base is genuinely reusable for later HDFC/Federal/AU two-column readers. Ref: research **D4**, `plan.md` §Complexity Tracking, spec US3-AC4.

**Checkpoint**: The base is a proven reusable seam — single-amount **and** two-column anchor shapes, with narration stitching — so later banks drop in as small configs.

---

## Phase 7: User Story 4 — Balance-chain integrity: RECONCILED / NEEDS_REVIEW with the suspect rows (Priority: P4)

**Goal**: `check_balance_chain` walks the ledger and reports **RECONCILED**/**NEEDS_REVIEW** with the suspect
rows; a chain break is a **suspect** (still returned), distinct from an unparseable **errored** line. *(Impl
landed in T009; the RECONCILED case is pinned by the T004 parity chain test.)*

**Independent Test**: A clean ledger → RECONCILED, 0 suspects; a row whose amount ≠ |delta| (beyond ₹1.00) →
NEEDS_REVIEW naming it, while the row is still returned; an unparseable anchor-shaped row → an errored line,
not a suspect.

- [ ] T018 [P] [US4] Add chain unit tests in `core/crates/kaname-core/src/statement/balance_chain.rs` (`#[cfg(test)]`): the reference statement → **RECONCILED**, `suspect_count 0`, `row1_direction_fallback false` (US4-AC1, SC-002); a statement with one row whose printed `amount` differs from `|delta|` by **> ₹1.00** → **NEEDS_REVIEW** with that row named in `suspects` (`reason "amount … != |balance delta| …"`), **yet the suspect row is still present** in `statement.lines` (US4-AC2/AC3, FR-010, SC-004); a row whose `amount` differs by **≤ ₹1.00** stays reconciling (tolerance boundary lives **only** here — research **D6**); an **empty** statement → `NeedsReview`, `checked_rows 0`, `reason Some("no parsed transactions")`; `suspects` capped at 20 while `suspect_count` is the true count. Ref: research **D6/D11**, `contracts/ledger-base.md` §`balance_chain::check`, spec US4.
- [ ] T019 [P] [US4] Add an **errored-vs-suspect** test for the bank path in `core/crates/kaname-core/tests/parity.rs` (mirror `malformed_row_is_captured_not_fatal`, `parity.rs:213–225`, driving `read_icici_bank_statement`): a line matching the ICICI anchor shape but with a **bad balance** (e.g. an unparseable/garbled balance token) → captured in `errored_lines` (raw, truncated to 240 cp via `truncate_chars`), every well-formed row **still returned**, **no panic** (US4-AC4, FR-019, SC-005) — and confirm this is an **errored line, NOT a suspect** (the chain-break/suspect path is T018). [P] (different file from the `balance_chain.rs`/`ledger_reader.rs` clusters). Ref: spec US4-AC4, `line_reader.rs`/`ledger_reader.rs` errored path, `parity.rs:213–225`.

**Checkpoint**: The balance chain turns "we parsed some rows" into "we can trust this ledger" — suspects flagged-but-kept, errored lines cleanly separated.

---

## Phase 8: User Story 5 — Row-1 bootstrap: opening balance → first-row geometry → flagged provisional (Priority: P5)

**Goal**: Row 1 (no predecessor) resolves by fixed precedence and records `direction_source`; opening-balance
is preferred; geometry (`row1_xposition`) and `row1_provisional` are **fallbacks** that force NEEDS_REVIEW in
this slice. *(Impl landed in T008 `row1_direction`/`direction_from_x_position` + T009's fallback skip.)*

**Independent Test**: Printed opening balance → `direction_source = opening_balance`; no opening but geometry →
`row1_xposition`; neither → `row1_provisional` and the chain is NEEDS_REVIEW.

- [ ] T020 [US5] Add row-1 bootstrap unit tests spanning `core/crates/kaname-core/src/statement/ledger_reader.rs` (source resolution) and `core/crates/kaname-core/src/statement/balance_chain.rs` (verdict) (`#[cfg(test)]`; the `ledger_reader.rs` additions are **sequential** after T015–T017): with a printed opening balance, row 1's delta is computed against it (`95000 − 100000 = −5000` ⇒ **Debit**), `direction_source = OpeningBalance`, no geometry consulted (US5-AC1, SC-006); with **no** opening but a non-empty `Vec<Word>` and `column_split_x = 400`, the amount word's x-center vs the split decides direction, `direction_source = Row1XPosition` (US5-AC2); with **neither**, `provisional_direction()` (default `Debit`) is used, `direction_source = Row1Provisional` (US5-AC3); every later row is `BalanceDelta` (US5-AC5); and `check` reports **NEEDS_REVIEW** with `row1_direction_fallback == true` for **both** `Row1XPosition` and `Row1Provisional` row-1 sources — an uncalibrated first-row decision is never silently trusted (US5-AC4, FR-015/018, SC-006). Ref: research **D5/D11**, spec US5, `contracts/ledger-base.md` §Direction.

**Checkpoint**: Row 1 bootstraps by a principled, auditable precedence; un-anchored first rows route to NEEDS_REVIEW.

---

## Phase 9: User Story 6 — Ledger metadata: per-row + statement-level fields, bank-aware account last-4 (Priority: P6)

**Goal**: Each row exposes `balance`/`balance_delta`/`amount_matches_delta`/`is_suspect`/`direction_source`/
`serial`; the statement records `printed_opening_balance`/`printed_closing_balance`/`period`/`card_last4`,
with `card_last4` from the **account-number** tail (`"3456"`), and missing fields left unset. *(Impl landed in
T006's records + T008's population + T010's `enrich`/`account_tail`.)*

**Independent Test**: Each row exposes the six metadata fields; the statement records opening `100000.00`,
closing `143000.00`, period `2025-06-16→2025-07-15`, and account last-4 `3456`; a missing field is left unset.

- [ ] T021 [US6] Add metadata unit tests in `core/crates/kaname-core/src/statement/icici_bank.rs` (`#[cfg(test)]`, driving `read_ledger_lines(&IciciBankReader, …)`/`enrich`): each row exposes `balance`/`balance_delta`/`amount_matches_delta`/`is_suspect`/`direction_source`/`serial` (1/2/3) (US6-AC1, FR-020); `printed_opening_balance == 100000.00` and `printed_closing_balance == 143000.00` (US6-AC2, SC-008); `period_start 2025-06-16` / `period_end 2025-07-15` via `PERIOD_RE` + `parse_date` `%B %d, %Y` (US6-AC3); `card_last4 == Some("3456")` from `Account Number 000401000123456` via the **account-number** `account_tail` — **not** `find_last4`/masked-PAN (US6-AC4, FR-022, research **D10**); and a fabricated statement missing the period/account markers → those fields `None` while rows are still returned, never fabricated (US6-AC5, FR-023). Ref: research **D7/D8/D10**, `data-model.md` §`IciciBankReader`, spec US6.

**Checkpoint**: The ledger is auditable and attributable — per-row balance/delta/suspect data + the correct bank-account last-4.

---

## Phase 10: User Story 7 — The document gate tells an ICICI savings statement from an ICICI credit-card statement (Priority: P7)

**Goal**: `icici_bank_claims` requires the ICICI bank code + **all** required markers (`Statement of
Transactions`, `ICICI`) + **any** optional (`Saving`/`Current`) — accepting the savings statement and
**rejecting** the ICICI credit-card statement (which the CC reader still claims). *(Impl landed in T010's
`claim_all`/`claim_any` + T008's `claims_ledger`; the split is pinned by the T004 parity test.)*

**Independent Test**: The bank reader claims the savings statement, rejects an ICICI credit-card statement and
other issuers; the existing ICICI credit-card reader still claims the credit-card statement.

- [ ] T022 [US7] Add claim-split unit tests in `core/crates/kaname-core/src/statement/icici_bank.rs` (`#[cfg(test)]`; **same file as T021 → sequential**): `claims_ledger(&IciciBankReader, savings_text, "ICICI") == true` (all required + one optional present) (US7-AC1); `== false` for an **ICICI credit-card** text (lacks `Statement of Transactions` + `Saving`/`Current`) (US7-AC2, FR-002, SC-007); `== false` for a different-issuer text (US7-AC3); and confirm the case-insensitive `bank_code`/`claim_all`/`claim_any` semantics. Cross-check that `icici_claims(credit_card_text)` (the CC reader, `ffi.rs:61`) still returns `true` (US7-AC4) — the two readers share the issuer but split on document type. (This complements the T004 parity `icici_bank_claims_accepts_savings_and_rejects_credit_card` test.) Ref: `contracts/ledger-base.md` §`claims_ledger`, research **D10**, spec US7.

**Checkpoint**: The savings-vs-credit-card gate is precise — 0 misroutes; each statement reaches the correct reader.

---

## Phase 11: User Story 8 — Proven byte-for-byte against a golden fixture (Priority: P8) 🛡️ whole-slice guard

**Goal**: The parity harness is the **regression-proof** guarantee pinning ICICI-bank to the web engine —
extended **back-compatibly** to the balance-ledger family (optional ledger fields; a dedicated chain test),
with the 5 credit-card vectors reproducing **unchanged**. *(Fixture T003; harness/chain/claim tests T004;
greened T012.)*

**Independent Test**: The harness over the ported ICICI-bank vector matches expected output exactly (rows +
ledger metadata + printed opening/closing + period + account last-4 + RECONCILED chain), and re-running is
stable; all 5 credit-card issuers still reproduce their vectors.

- [ ] T023 [US8] Finalize `core/crates/kaname-core/tests/parity.rs` as the **whole-slice guard**: confirm the `"ICICI bank"` `Case` calls `parse_icici_bank` (empty geometry); field-by-field parity — dates, exact `Decimal` amounts (scale preserved; Indian grouping stripped), delta-derived directions, `INR`, `description_raw` byte-for-byte, **plus** per-row `balance`/`balance_delta`/`direction_source`/`serial`/`amount_matches_delta`/`is_suspect` (asserted because the fixture supplies them), and `printed_opening_balance 100000.00`/`printed_closing_balance 143000.00`/`period_start 2025-06-16`/`period_end 2025-07-15`/`card_last4 "3456"`/`errored_lines []` (SC-001/008); the dedicated `icici_bank_chain_reconciles` test asserts **RECONCILED**, 0 suspects, no row-1 fallback, `derived_opening/closing 100000.00`/`143000.00` (SC-002); the determinism **re-run** covers the bank vector (SC-012/013); the fixture is **100% synthetic** (SC-008); and confirm the schema stayed **back-compatible** — the 5 CC fixtures/rows and their assertions are **byte-identical** (no migration — research **D9**). Ref: `contracts/golden-fixture.md` §Harness schema extension/§What each assertion pins, research **D9**.

**Checkpoint**: Parity is an enforced guarantee for the bank family; one harness serves both reader families with no CC fixture migration.

---

## Phase 12: User Story 9 — Privacy gate & the Swift bridge: zero network, no new dependency, reachable from Swift (Priority: P9) 🛡️ inherited guard

**Goal**: Prove the ICICI bank-account parse **and** chain path is egress-free — **structurally** (no
networking crate can even link) and **behaviorally** (determinism) — via the **inherited** gate with **zero**
new config, and confirm reachability over UniFFI (greened in T014). *(No new script/CI: this slice adds no
dependency, so the audit is byte-identical.)*

**Independent Test**: `make core-privacy-audit` passes only when zero networking crates are in the shipped
graph; the reader is callable over UniFFI from Swift; no new runtime (or networking) dependency was added.

- [ ] T024 [US9] Confirm the inherited privacy-egress gate stays **GREEN with ZERO changes**: run `make core-privacy-audit` → passes (no networking crate in `kaname-core` deps) — this slice adds **no dependency** (runtime *or* dev), so `cargo tree -p kaname-core -e normal` is byte-identical (`Cargo.toml` unchanged — FR-028/029/034, SC-010/014); the determinism/purity assertion over the bank vector lives in `tests/parity.rs` (T004/T023, FR-025, SC-012); the whole reader (`read_icici_bank_statement` with geometry, `icici_bank_claims`, `check_balance_chain`) is reachable from Swift over UniFFI (proved GREEN in T014, SC-011, FR-027); confirm **no** telemetry/analytics/crash-reporter enters the parse/chain path and **no** network entitlement/ATS is added app-side (FR-029/030). Ref: research **D1**, `quickstart.md` §2, spec US9.

**Checkpoint**: Privacy-egress remains a first-class, structurally- and behaviorally-enforced gate covering the bank-account parse **and** the balance-chain check; the reader is reachable from Swift.

---

## Phase 13: Polish & Cross-Cutting — full iOS Local Verification Gate green

**Purpose**: Prove the whole slice is merge-ready (SC-014) and review the constitution guarantees.

- [ ] T025 [P] Light docs alignment (no behavior change): note the **second reader family** (balance-ledger) — the ledger base + balance chain + ICICI reference — where the engine/build is described (`README.md` and/or `specs/007-bank-account-ledger-reader/quickstart.md`); refresh the `statement/mod.rs` doc comment (`mod.rs:1–7`) so it reflects the new ledger seam alongside the `read_lines` seam; ensure `fixtures/README.md` reflects the ICICI bank vector under `fixtures/icici/bank_account/`. No stale wording.
- [ ] T026 **Run the full iOS Local Verification Gate green**, in order: `make core-lint && make core-test && make core-privacy-audit && make lint && make ios-gen && make ios-test`. ⚠️ `make core-xcframework` is rebuilt before `tuist generate` (via `ios-gen`, `Makefile:32`); local Xcode requires the **"iPhone 16"** simulator; CI runs the same (core on ubuntu, iOS on **macos-15**). This is the SC-014 / FR-035 merge gate. Ref: `quickstart.md` §5.
- [ ] T027 [P] Final constitution review (no code change): **NO new dependency** (runtime *or* dev) — `Cargo.toml`/`uniffi.toml` unchanged; the diff is exactly additive `base.rs` fields/records + the 1-line `line_reader.rs` ripple + `ledger_reader.rs` + `balance_chain.rs` + `icici_bank.rs` + `mod.rs` wiring + 3 `ffi.rs` exports + `lib.rs` re-exports + 1 fixture + 1 `parity.rs` `Case`/chain/claim tests + 1 Swift test; **money is `Decimal`, never `f64`** (only `Word.x0/x1` are layout points); direction is **delta-derived** with an auditable `direction_source`, never the amount's sign; **exact** `amount == |delta|` in the reader vs the **₹1.00** tolerance **only** in `balance_chain`; `card_last4 "3456"` via the account-number tail (never fabricated); no secrets / network entitlements / copyleft (GPL/AGPL/LGPL) deps (FR-034); all fixture/test data synthetic (SC-008); the 5 CC fixtures + the harness schema stay back-compatible (no migration — research **D9**). Confirm against `git diff` before handoff. Ref: `plan.md` §Constitution Check/§Complexity Tracking, spec FR-034/SC-009/SC-014.

**Checkpoint**: Whole slice is green end-to-end and constitution-clean — ready to ship.

---

## Phase 14: Ship — three commits, PR #7, CI, merge (requester step 7)

**Purpose**: Land the slice. Executed **only after** Phase 13 is green. (Generation writes nothing here; the
implementer runs these once the gates pass.)

- [ ] T028 Create **three small, pure commits** on `007-bank-account-ledger-reader` (RED→GREEN kept coherent):
  **Commit 1 — data-model + base + chain engine**: `core/crates/kaname-core/src/statement/base.rs` (additive records/fields), `core/crates/kaname-core/src/statement/line_reader.rs` (`ledger: None` ripple), `core/crates/kaname-core/src/statement/ledger_reader.rs`, `core/crates/kaname-core/src/statement/balance_chain.rs`, and the `pub mod ledger_reader; pub mod balance_chain;` lines in `core/crates/kaname-core/src/statement/mod.rs` (+ the ledger/chain `#[cfg(test)]` unit tests T015–T020).
  **Commit 2 — ICICI reader + FFI + fixture + parity**: `core/crates/kaname-core/src/statement/icici_bank.rs` (+ its unit tests T021–T022), `pub mod icici_bank;` in `mod.rs`, `core/crates/kaname-core/src/ffi.rs` (3 exports), `core/crates/kaname-core/src/lib.rs` (re-exports), `fixtures/icici/bank_account/basic.json`, `core/crates/kaname-core/tests/parity.rs` (schema extension + `Case` row + chain test + claim-split + errored test), and any docs from T025.
  **Commit 3 — Swift test**: `ios/Tests/ICICIBankParseTests.swift`.
  Do **not** commit generated artifacts (`ios/Generated/…`, `ios/Frameworks/…` are git-ignored). Ref: requester step 7.
- [ ] T029 Push the branch, open **PR #7** (`SSKUltra/kaname`, base default branch), **watch CI** — both the **core** job (ubuntu: `core-lint` + `core-test` + `core-privacy-audit`) and the **iOS** job (**macos-15**: `core-xcframework` → `tuist generate` → `xcodebuild … iPhone 16` test) go green — then **`gh pr merge --rebase --delete-branch`**. Ref: requester step 7, `plan.md` §Constitution Check (CI ordering inherited unchanged).

**Checkpoint**: The bank-account balance-ledger reader family is merged — the ledger base, the balance chain, and ICICI as the first reference reader, byte-for-byte with the web engine.

---

## Dependencies & Execution Order

### Phase order

1. **Setup (P1)** → 2. **Test-First Foundation (P2, RED)** → 3. **US1 GREEN engine pipeline (P3)** →
4. **Bridge/Swift green (P4)** → 5–10. **US2/US3/US4/US5/US6/US7 verification (P5–P10)** →
11. **US8 parity guard (P11)** → 12. **US9 privacy guard (P12)** → 13. **Polish + full gate (P13)** →
14. **Ship (P14)**.

- **Test-First (Phase 2) BLOCKS all engine code (Phase 3+)** — T003–T005 must exist and be RED first (Principle V, FR-033).
- **The US1 GREEN pipeline (T006→T012) is the critical path** and lands the behaviors US2–US7 verify.

### Task-level dependencies

- T003 (fixture) precedes T004 (parity `Case`/chain/claim) and T012 (green).
- T004/T005 (RED tests) precede **all** implementation (T006+).
- **Engine spine**: **T006** (`base.rs` records) → { **T007** (`line_reader.rs` ripple), **T008** (`ledger_reader.rs`), **T009** (`balance_chain.rs`) } → **T010** (`icici_bank.rs` + `mod.rs`, needs T008) → **T011** (`ffi.rs` exports + `lib.rs`, needs T009+T010) → **T012** (`core-fmt` → Rust green).
- T011 → **T013** (xcframework) → **T014** (Swift green). **T013 before any `tuist generate`.**
- Verification depends on the pipeline: T015/T016/T017/T020 → T008; T018/T020(verdict) → T009; T019 → T011; T021/T022 → T010; T023 → T012; T024 → T012 (+ T014 reachability).
- **T026 (full gate) depends on everything** (T012, T014, T023, T024, T025); T027 is review only.
- **Ship**: T028 depends on T026 (all green); T029 depends on T028.

### Parallel opportunities

- **Setup**: T001 [P] + T002 [P].
- **Test-First**: T003 [P] (fixture) + T005 [P] (Swift test) are different files; T004 edits `parity.rs` (run it alone; it references T003's fixture path).
- **Engine spine**: after T006, **T007 [P] + T008 [P] + T009 [P]** are different files depending only on T006 (author in parallel); the crate compiles once T010/T011 land.
- **Story verification**: T015/T016/T017/T020(reader part) all extend `ledger_reader.rs`'s `#[cfg(test)]` (**same file → sequential**); T021/T022 share `icici_bank.rs` (**sequential**); **T018 [P]** (`balance_chain.rs`) and **T019 [P]** (`parity.rs`) run alongside the `ledger_reader.rs` cluster.
- **Polish**: T025 [P] + T027 [P] (docs + review); T026 runs the gate alone.

**[P] set**: T001, T002, T003, T005, T007, T008, T009, T018, T019, T025, T027.

**Critical path**: T003 → T004/T005 (RED) → **T006 → T008 → T010 → T011 → T012** → T013 → T014 → T023 → T024 → T026 → T028 → T029. (T009/`balance_chain.rs` is parallel off T006 but is pulled in by T011.)

---

## Parallel Example: the Test-First Foundation (Phase 2) and the engine spine (Phase 3)

```bash
# Phase 2 — author the two independent RED artifacts together (different files):
Task T003: "Author fixtures/icici/bank_account/basic.json (exact bytes from contracts/golden-fixture.md)"
Task T005: "Author ios/Tests/ICICIBankParseTests.swift (RED core ↔ Swift ICICI bank parse + chain)"
# Then T004 edits tests/parity.rs (schema extension + Case row + chain test + claim split) → verify RED (won't compile).

# Phase 3 — after T006 (base.rs records), author the three different-file tasks in parallel:
Task T007: "line_reader.rs constructor gains `ledger: None`"
Task T008: "statement/ledger_reader.rs — LedgerReaderConfig trait + read_ledger_lines + claims_ledger + internals"
Task T009: "statement/balance_chain.rs — check + ChainResult/ChainStatus/Suspect (₹1.00 tolerance here only)"
# Converge: T010 (icici_bank.rs + mod.rs) → T011 (ffi.rs exports + lib.rs re-exports) → T012 (core-fmt → Rust green).
```

---

## Implementation Strategy

### MVP first (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 **RED** anchors (fixture → parity `Case`/chain/claim → Swift) → 3. Phase 3
engine spine (T006→T012, `make core-fmt` then green) → 4. Phase 4 bridge (T013–T014). **STOP & VALIDATE**: the
golden ICICI-bank statement parses on-device through `read_icici_bank_statement`, `check_balance_chain` reports
RECONCILED, and the Swift suite is green. This alone is a shippable, useful slice (the whole second reader
family opens on it).

### Incremental delivery

Add US2 (delta direction) → US3 (reusable base + two-column) → US4 (balance chain suspect/errored) → US5
(row-1 bootstrap) → US6 (ledger metadata + account last-4) → US7 (savings-vs-CC gate) — each an independent
test increment over the same engine. Then lock the **guards**: US8 (golden parity — one harness, both
families, no CC migration) and US9 (inherited privacy-egress + Swift reachability). Finish with the full-gate
run (T026) and Ship (T028–T029, three commits + PR #7).

### Story → task traceability

| Story | Delivered by | Independently verified by |
|---|---|---|
| **US1** on-device parse 🎯 | T006, T007, T008, T009, T010, T011, T012, T013, T014 | T012 (Rust parity), T014 (Swift), T004 claim-split |
| **US2** delta direction | T008 `read_ledger_lines` delta logic | **T015** (delta-flip; amount never drives direction) |
| **US3** reusable base + narration | T008 (base + `find_anchors`/`stitch_narration`) + T010 (config) | **T016** (anchors/narration) + **T017** (two-column loose-integer) |
| **US4** balance chain | T009 `balance_chain::check` | **T018** (suspect-but-returned / NEEDS_REVIEW / empty) + **T019** (errored-vs-suspect, bad balance) |
| **US5** row-1 bootstrap | T008 `row1_direction`/`direction_from_x_position` + T009 fallback skip | **T020** (opening/x-position/provisional + NEEDS_REVIEW) |
| **US6** ledger metadata + last-4 | T006 records + T008 population + T010 `enrich`/`account_tail` | **T021** (per-row + printed_*/period/last-4) |
| **US7** savings-vs-CC gate | T010 `claim_all`/`claim_any` + T008 `claims_ledger` | **T022** (+ T004 parity claim-split) |
| **US8** golden parity 🛡️ | T003, T004, T012 | **T023** (whole-slice guard; no CC migration) |
| **US9** privacy + bridge 🛡️ | *inherited* gate + T004 determinism + T011/T014 UniFFI | **T024** (privacy-egress + no-new-dep + reachability) |

---

## Notes

- **Test-first is mandatory** (Principle V, FR-033): T003–T005 are RED before Phase 3; T012 greens the Rust
  parity + chain + claim-split, T014 greens the Swift bridge — each has an explicit RED→GREEN verify step. The
  `expected` block is the **locked characterization ground truth** (`icici-bank-ground-truth.json`; no live
  capture needed — `quickstart.md` §0).
- **Design is LOCKED** in `plan.md`/`data-model.md`/`contracts/` — the porting tasks **sequence** it, they do
  not re-derive it. Every value (3 rows, ledger metadata, printed `100000.00`/`143000.00`, period, last-4
  `3456`, RECONCILED chain) is pinned in `contracts/golden-fixture.md`.
- **Two-place amount-vs-delta** (research **D6**): the **reader** records **exact** `amount == |delta|`; the
  **₹1.00 tolerance** lives **ONLY** in `balance_chain::check`. Keep them separate.
- **Direction is delta-derived**, never the amount's sign (FR-008); row 1 via opening→x-position→provisional
  with an auditable `direction_source`; `Row1XPosition`/`Row1Provisional` force NEEDS_REVIEW (FR-015/018).
- **`card_last4 "3456"`** via the **account-number** tail extractor — **not** `find_last4`/masked-PAN
  (research **D10**, FR-022).
- **Additive & back-compatible**: the record-field additions ripple to the CC path only as `ledger: None` /
  `None` defaults; the harness schema extension uses `#[serde(default)]`, so the **5 credit-card fixtures need
  NO migration** (research **D9**). **No new dependency** (runtime *or* dev); money is `Decimal` (only
  `Word.x0/x1` are `f64` layout points).
- **REUSE, not rebuild**: `common.rs` (`parse_amount`/`parse_date`, ICICI-savings `%d.%m.%Y`/`%B %d, %Y`
  already present), `model.rs` `Direction`, `base.rs` records, `tests/parity.rs` harness, the `ffi.rs`
  `Decimal`/`NaiveDate` bridges, and the privacy-egress gate are inherited. The **only** NEW code is the base +
  chain + ICICI reader + additive records + FFI + fixture + tests.
- **iOS gate ordering**: `make core-xcframework` **before** `tuist generate` (`Makefile:32`); **iPhone 16**
  simulator; CI iOS job pinned to **macos-15**.
- **[P]** = different files, no unfinished dependency. `[Story]` labels map each task to its slice.
- **Generation commits nothing**; the three commits + PR #7 + `--rebase --delete-branch` merge are **Phase 14:
  Ship**, executed by the implementer after every gate is green.
