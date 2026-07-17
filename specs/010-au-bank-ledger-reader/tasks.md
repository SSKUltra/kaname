---
description: "Task list — AU Small Finance Bank (Savings/Current) Ledger Reader: the LEANEST config-on-existing-base slice and the FOURTH & FINAL bank on the balance-ledger base (1 AU config + 1 golden fixture + 2 FFI exports reusing check_balance_chain; ZERO shared-code changes, zero new deps, zero new FFI types). ONE anchor; a dash-marked empty debit/credit column (loose_amount('-')→None picks the non-dash side); NO per-row Dr/Cr marker — direction is delta-derived and the narration's UPI/DR·UPI/CR is counterparty text, ignored; printed closing = last row balance (16570.79), NOT the header 223.34; the ₹ U+20B9 glyph is preserved. 2 commits + PR #11."
---

# Tasks: Read an AU Small Finance Bank (Savings/Current) Statement On-Device — the Fourth and Final Balance-Ledger Reference Reader (AU config on the existing ledger base; ONE template; a dash-marked empty column; no per-row Dr/Cr marker)

**Input**: Design documents from `/specs/010-au-bank-ledger-reader/`
**Prerequisites**: `plan.md`, `spec.md` (US1–US10), `research.md` (D1–D11), `data-model.md`,
`contracts/ffi.md` (C1–C6), `quickstart.md`

**Tests**: REQUIRED and **TEST-FIRST** for this slice (Constitution Principle V, FR-033/035). The **one** golden
fixture, the failing Rust parity `Case` row (+ the balance-chain RECONCILED test + the `au_bank_claims` accept/reject
split), and the failing Swift "core ↔ Swift AU bank parse + balance chain" test are all authored **RED, before** the
engine that greens them. The engine-side focused unit tests (direction-from-delta-despite-`UPI/DR`·`UPI/CR`,
dash-column non-dash-side amount, header/footer-not-a-transaction, claims savings-vs-CC) land **with** the GREEN
engine (in `au_bank.rs`'s `#[cfg(test)]` module, mirroring `icici_bank.rs::tests`).

**Port source of truth** (faithful, byte-for-byte with the one golden vector — the design is **LOCKED** in
`plan.md`/`data-model.md`/`contracts/`; do **not** re-derive it, just sequence it): the web engine's `au_bank.py`,
whose captured JSON ground truth (`savings`, RECONCILED) is the persisted ground truth. Every value (2 rows, ledger
metadata, printed opening `11570.79`/closing `16570.79`, period, empty serials, last-4 `0042`, the stitched
narrations incl. the folded footer, RECONCILED chain) is pinned in `data-model.md §3` + `research.md D8/D9`. **No live
run needed** (`research.md` §Open questions: "None").

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: `US1`=on-device parse (MVP) · `US2`=delta direction / `UPI/DR`·`UPI/CR` narration is NOT a signal /
  amount-as-check · `US3`=one template, dash-marked empty debit/credit columns → non-dash side is the amount ·
  `US4`=opening balance from the parenthesised-currency header / opening-anchored row-1 / the `Closing Balance(₹)`
  line is a non-transaction whose figure is NOT the printed closing · `US5`=narration stitching (above + below, incl.
  the folded footer) / non-transaction lines · `US6`=ledger metadata (period / bank-aware account last-4) ·
  `US7`=savings/current claim gate rejecting a credit-card statement (AU is the SOLE reader under `AU`) ·
  `US8`=config-on-base, ZERO new shared code · `US9`=golden parity (1 vector, RECONCILED) · `US10`=privacy-egress +
  Swift bridge. Setup/Polish/Ship carry no label.
- Exact file paths are included in every task.

> **Note (this slice commits nothing during generation).** `/speckit.tasks` only writes this file. The **two**
> commits + **PR #11** + `--rebase --delete-branch` merge are encoded as the final **Phase 15: Ship** and are executed
> by the implementer **only after** every gate is green (requester step 7).

## ♻️ REUSE — do NOT re-create (this slice adds 1 config + 2 FFI exports + 1 fixture, and NOTHING shared)

This is the **fourth (and final) bank config** on the balance-ledger base (007) and the **leanest ledger drop-in of
the family** — leaner than Federal (009), which shipped two templates + two fixtures. This slice adds **ZERO new
dependency** (runtime *or* dev), **zero new records/enums**, **zero new FFI types**, **zero new shared helpers**, and
**zero base changes**. Do **not** rebuild, refactor, or touch any of these — the base, the chain check, the shared
helper, the harness, and the privacy gate are **reused UNCHANGED**:

- `statement/ledger_reader.rs` — `trait LedgerReaderConfig` (`:51`: `fn bank_code` `:52`, `fn claim_all` `:56`, `fn
  anchor_res() -> Vec<&'static Regex>` `:60` first-match-wins ordered list, `fn claim_any` `:63`, `fn
  opening_balance_re` `:66`/`fn closing_balance_re` `:69` `-> Option<&'static Regex>`, `fn column_split_x() ->
  Option<f64>` `:74`, `fn provisional_direction` `:79`, `fn enrich(&self, &mut ParsedStatement, &str)` `:83`,
  defaulted `fn account_tail -> None` `:86`), `claims_ledger` (`:93`), `read_ledger_lines` (`:126`,
  `printed_closing_balance = last anchor balance` at `:195`), the two-column `anchor_amount`/`loose_amount`
  (`:238`/`:262` — `loose_amount("-") → None`, so `anchor_amount` picks the non-dash side), `stitch_narration`
  (`:271`), and `is_balance_line` (`:395` — uses `opening_balance_re` `:396` **and** `closing_balance_re` `:399` only
  to **skip** those lines during stitching). **No base change** — AU returns **1** anchor and sets **no**
  `column_split_x`.
- `statement/balance_chain.rs` — `pub fn check(statement: &ParsedStatement) -> ChainResult` (`:74`); `enum
  ChainStatus { Reconciled, NeedsReview }` (`:23`); `struct ChainResult { status, checked_rows, suspect_count,
  suspects, row1_direction_fallback, derived_opening_balance, derived_closing_balance, reason }` (`:41`, incl.
  `row1_direction_fallback` `:49`). Reused **unchanged** (the ₹1.00 tolerance lives here only).
- `statement/common.rs` — `account_tail_last4(text, primary)` (**already exists**, `:177`; primary group 1 →
  trailing 4, else the longest `\d{9,}` run → trailing 4), `parse_amount` (`:58`), `parse_date` (`:66`). The AU date
  format **`%d %b %Y`** (`01 Mar 2026`) is **already present** at `common.rs:30`. **No `common.rs` change at all.**
- `statement/base.rs` — records reused **unchanged**: `ParsedTransaction { value_date, amount, direction, currency,
  description_raw, bank_code, ledger: Option<LedgerMetadata> }`; `ParsedStatement { bank_code, lines, errored_lines,
  period_start, period_end, card_last4, printed_opening_balance, printed_closing_balance, confidence }`;
  `LedgerMetadata { balance, balance_delta, amount_matches_delta, is_suspect, direction_source, serial }`;
  `DirectionSource` (`OpeningBalance`/`BalanceDelta`); `Word { text, x0, x1 }`.
- `statement/icici_bank.rs` — **THE TEMPLATE**: `IciciBankReader` likewise overrides **`claim_any` + `closing_balance_re`**
  and calls `account_tail_last4` from an overridden `account_tail`. Copy its **structure** (not its patterns); it is
  **UNCHANGED**. `statement/federal_bank.rs` — SECONDARY template for the `enrich()`/period shape.
- `ffi.rs` — the `Decimal`/`NaiveDate` custom-type bridges reused **unchanged** (**no `uniffi.toml` change**);
  `read_federal_bank_statement` (`:183`), `federal_bank_claims` (`:194`), and **`check_balance_chain(statement:
  ParsedStatement) -> ChainResult`** (`:152`) are the exact templates.
- `tests/parity.rs` — the golden-fixture harness with the `#[serde(default)]` optional-ledger schema
  (`Fixture`/`Expected`/`ExpectedRow`/`ExpectedLedger` `:22`/`:29`/`:46`/`:58`; `Case` `:69`; `CASES` `:75`;
  `parse_federal_bank` wrapper `:148`; `load_fixture` `:152`; `federal_bank_statements_balance_chain_reconciles`
  `:367`; `federal_claims_accepts_own_document_and_rejects_others` `:319`). **NO schema change** — the **11** existing
  fixtures/cases need **NO migration**.
- The **privacy-egress gate** (`make core-privacy-audit`, `Makefile:22` → `core/scripts/privacy-egress-audit.sh`) and
  CI — inherited **unchanged** (**no new dependency** → byte-identical shipped `cargo tree` graph).

**The only NEW code**: `statement/au_bank.rs` (the AU config + its unit tests) + `pub mod au_bank;` in `mod.rs`; **2**
`#[uniffi::export]` fns (`read_au_bank_statement` / `au_bank_claims`) + `lib.rs` re-exports; **1** golden fixture under
`fixtures/au/bank_account/`; **1** parity `Case` row + **1** chain test + **1** claim-split test; **1** Swift test.
**No new dependency; no new FFI type; no shared/base change; `check_balance_chain` reused.**

## ⚠️ Grounding & local gotchas (apply throughout — the design is LOCKED; use the REAL landed symbols)

- **Use the ACTUAL landed symbols** (mirror the Federal 009 / ICICI 007 surface): the per-row type is
  **`ParsedTransaction`** (field **`value_date`**, not `date`), reached via **`ParsedStatement.lines`**; the chain fn
  is **`check_balance_chain(statement: ParsedStatement) -> ChainResult`** (takes the whole statement **by value**) and
  you assert **`result.status == ChainStatus::Reconciled`**. The fixture **JSON** key **is** `expected.rows[]` (the
  harness maps `ExpectedRow` → `statement.lines[i]`).
- **AU is the SOLE reader under bank code `AU`** (research **D6**, spec US7). Unlike ICICI/HDFC/Federal (each of which
  shares its issuer code with a coexisting **credit-card** reader), **AU has no credit-card reader in this client**.
  There is no sibling reader to mis-route to; the rejection of a card statement is simply the gate correctly declining
  a document that lacks a **Savings/Current** account-type marker (`claim_any` unmet). `au_bank_claims` requires the
  `AU` bank code + **all** of `claim_all` = `["aubank.in"]` + **any** of `claim_any` =
  `["Savings Account", "Current Account"]`.
- **NO per-row Dr/Cr marker — the narration's `UPI/DR`·`UPI/CR` is COUNTERPARTY text, NEVER a direction signal**
  (research **D5**, the defining AU invariant, FR-006/007, SC-003). AU prints **no** direction marker at all (unlike
  Federal's consumed-but-ignored trailing `Cr`/`Dr`). Direction comes **only** from the balance delta (fall ⇒ `Debit`,
  rise ⇒ `Credit`); row 1 is anchored on the printed opening balance (`OpeningBalance`). In the fixture the **debit**
  row's narration happens to contain `UPI/DR` and the **credit** row's contains `UPI/CR` — a **coincidence** that must
  **not** drive direction. The `UPI/…` tokens live **inside** `description_raw` and are read by nothing.
- **Dash-marked empty column → the base's `loose_amount("-") → None` picks the non-dash side** (research **D3**,
  FR-005, SC-004). AU prints a **Debit** column and a **Credit** column where the empty side is a literal `-` (NOT the
  Fi/HDFC `0`). The anchor captures each side as `([\d,]+\.\d{2}|-)`; `anchor_amount` runs `loose_amount` on each and
  `loose_amount("-") = None` (because `Decimal::from_str_exact("-")` errors), so the non-dash column becomes the
  amount — **row 1** `5,000.00` from Debit (Credit `-`), **row 2** `10,000.00` from Credit (Debit `-`). **No base
  change** (same mechanism as the `0`-empty layout, `!is_zero()` vs `None`).
- **Printed closing balance is the LAST anchor's running balance, NOT the header figure** (research **D4**,
  FR-012/013, SC-007). `read_ledger_lines` sets `printed_closing_balance = anchors.last().balance` unconditionally
  (`ledger_reader.rs:195`) ⇒ **`16570.79`**. The header line `Closing Balance(₹) : 223.34` is **only** matched by
  `closing_balance_re` inside `is_balance_line` (`:399`) to **skip** it during narration stitching; its `223.34` is
  **never** assigned to `printed_closing_balance`. Store `printed_closing_balance = "16570.79"`, **not** `"223.34"`.
- **The `₹` (U+20B9) glyph is PRESERVED** — the header lines `Opening Balance(₹) : 11,570.79` and
  `Closing Balance(₹) : 223.34` keep the literal U+20B9 verbatim in both `lines` and `full_text`. In **JSON** it may
  be written as the raw character **or** the `\u20b9` escape (both decode identically); `description_raw` is
  byte-for-byte (no normalization). This is the **only** non-ASCII glyph on this surface.
- **`make core-xcframework` MUST run before `tuist generate`** (`ios-gen: core-xcframework`, `Makefile:32`) — the
  generated Swift + `KanameCoreFFI.xcframework` are git-ignored **rebuilt** artifacts (`quickstart.md §Verify — iOS`).
- **Local Xcode needs an explicit "iPhone 16" simulator** for `make ios-test`
  (`xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'`, `Makefile:37`); CI pins
  **`macos-15`** for the iOS job.
- **Money is `Decimal`, never `f64`** — amounts, balances, deltas all `Decimal`; Indian grouping (`1,00,000.00`) is
  stripped and the printed scale preserved (amounts stored `"5000.00"`/`"10000.00"`). The **only** `f64` on this
  surface is `Word.x0/x1` — layout points, not money — and AU sets **NO `column_split_x`**, so **no geometry is
  exercised** (empty `Vec<Word>`; the row-1 x-position path is not reached — the fixture is opening-anchored). Fixture
  money is stored as **JSON strings**, re-parsed via `Decimal::from_str` (never float).
- **The header, column-header, `Opening Balance(₹)`, `Closing Balance(₹)`, and the footer are NOT transactions**
  (research **D8**): none begins with **two** `DD Mon YYYY` dates, so none matches the anchor. The footer
  `1800 1200 1200 www.aubank.in customercare@aubank.in` begins with digit groups but not two dates ⇒ no anchor; it is
  **folded into row 2's narration** byte-for-byte (Part B of the last anchor), never emitted as a row. The statement
  yields exactly **2** transactions.
- **Narration is intentionally "dirty"** — the base `stitch_narration` folds the `UPI/…` reference line printed
  **above** each anchor into **that** row (Part A) and the trailing detail lines below the last anchor — **including
  the footer** — into the **last** row (Part B). Reproduce **byte-for-byte** (research **D8**); do **not**
  trim/collapse/reorder/"clean up" — it would break parity.
- **`card_last4 "0042"`** via the shared **`account_tail_last4`** with AU's own primary regex `(?i)Account\s+Number\s*:?\s*X*([0-9]{6,})`
  (optional masked `X*`; **6+** digits) → group 1 `1234567890120042` → last-4 `0042`; fallback longest `\d{9,}` run →
  last-4. Only the trailing four is ever surfaced (FR-020, privacy).
- **Two-place amount-vs-delta**: the **reader** records **exact** `amount == |delta|` (`amount_matches_delta`); the
  **₹1.00 tolerance** lives **ONLY** in `balance_chain::check`. The AU fixture reconciles (0 suspects, 0 errored).
- **Anchor is NOT `(?i)`** — dates use `[A-Za-z]{3}` and the anchor is case-sensitive, matching the ICICI anchor
  style; the opening/closing/period/account regexes **are** `(?i)`.
- **`serial` is empty** — AU's anchor has **no** `serial` group, so every row's `serial` is `""` (the row is still
  returned).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the invariants and prerequisites so every later task has a place to land and the gates stay
green. No behaviour yet.

- [ ] T001 [P] Confirm the **no-new-dependency, no-shared-change** invariant: `core/crates/kaname-core/Cargo.toml`
  and `uniffi.toml` stay **UNCHANGED** (runtime `regex`/`rust_decimal`/`chrono`/`serde`/`uniffi` + dev-only
  `serde_json` already present); this slice adds **zero** deps, **zero** new FFI types, and **zero** shared/base edits
  (FR-036, SC-008/010). Create the **new** issuer fixtures home directory `fixtures/au/bank_account/` (AU has no
  `credit_card` sibling in this client). Ref: `plan.md` §Summary/§Project Structure, `contracts/ffi.md §C6`.
- [ ] T002 [P] Verify local prerequisites & gotchas (no code): `cargo` on PATH (`source "$HOME/.cargo/env"`); iOS
  targets present (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`); an **"iPhone 16"**
  simulator exists in Xcode; recall `make core-xcframework` precedes `tuist generate` (`Makefile:32`); confirm
  `common.rs` **already** carries the AU date format `%d %b %Y` (`common.rs:30`), so **no `DATE_FORMATS` change is
  needed** (research **D10**), and `account_tail_last4` **already exists** at `common.rs:177` (no shared helper to
  add). Ref: `quickstart.md §Prerequisites`, `plan.md §Complexity Tracking`.

**Checkpoint**: New `fixtures/au/bank_account/` home exists, manifest + shared code unchanged, toolchain ready, the
reused seams located.

---

## Phase 2: Test-First Foundation (⚠️ Principle V — author RED before ANY engine code)

**Purpose**: Pin the on-device engine to the proven web engine **before** writing it. These are the parity (US9),
chain (US9), claim-split (US7), and bridge (US1/US10) tests that **protect the whole slice**; they MUST be **RED** at
the end of this phase (`read_au_bank_statement` / `au_bank_claims` do not exist yet).

**⚠️ CRITICAL**: No engine code (Phase 3+) may be written until T003–T005 exist and are verified failing.

- [ ] T003 [P] [US9] Author the **ported** golden vector `fixtures/au/bank_account/savings.json` — copy the **EXACT
  fixture bytes** from the captured `savings` ground truth; every transaction/opening/closing/continuation/footer line
  and every expected field are pinned in `data-model.md §3` + `research.md D8/D9`. **15 `lines`** (non-empty stripped
  `splitlines()` of `full_text`; **anchors at indices 9 and 12**; the `Opening Balance(₹)` line at index **3** and the
  `Closing Balance(₹)` line at index **4** — both non-transaction balance lines):
  - idx 0–2, 5–7: the header/meta + column-header lines carrying the claim markers **`aubank.in`** (e.g. in the
    footer `www.aubank.in` and/or a header URL) **and** a **`Savings Account`** account-type marker (e.g.
    `Account Type : AU Lite Savings Account` — research **D10**), the period text
    `Statement Period : 01 Mar 2026 to 31 May 2026`, and the account line
    `Account Number : …1234567890120042` (masked `X*` prefix tolerated) — **exact wording from the ground truth**.
  - idx 3 (opening, a non-transaction balance line, `₹` preserved): `Opening Balance(₹) : 11,570.79`
  - idx 4 (closing header, a non-transaction balance line whose figure is **NOT** the printed closing, `₹`
    preserved): `Closing Balance(₹) : 223.34`
  - idx 8 (row 1 Part A, folds into row 1): `UPI/DR/000000000001/EXAMPLE ABC0000000001ref`
  - idx 9 (row 1 anchor — two `DD Mon YYYY` dates, `desc` `STORE 1111ref2222tail`, Debit `5,000.00`, Credit **`-`**,
    Balance `6,570.79`): `01 Mar 2026 01 Mar 2026 STORE 1111ref2222tail 5,000.00 - 6,570.79`
  - idx 10 (row 1 Part B): `MERCHANT/UTIB/0000/UPI AU`
  - idx 11 (row 2 Part A, folds into row 2): `UPI/CR/000000000002/EXAMPLE XYZ0000000002ref`
  - idx 12 (row 2 anchor — two dates, `desc` `EMPLOYER 3333ref4444tail`, Debit **`-`**, Credit `10,000.00`, Balance
    `16,570.79`): `02 Mar 2026 02 Mar 2026 EMPLOYER 3333ref4444tail - 10,000.00 16,570.79`
  - idx 13 (row 2 Part B): `SALARY/UTIB/0000/UPI AU`
  - idx 14 (footer — digit groups but not two dates ⇒ no anchor; folds into row 2): `1800 1200 1200 www.aubank.in customercare@aubank.in`

  > The exact byte content of the header/meta lines (idx 0–2, 5–7) and the exact two-date prefix on each anchor come
  > from `data-model.md §3` / the captured ground truth — **do not re-derive them**, copy them.

  `full_text` = the `\n`-joined same lines **with a trailing newline**. `expected.rows` = the **2** rows (all money as
  **JSON strings**; direction from the delta **despite** the narration's `UPI/DR`/`UPI/CR`; amounts stored with `.00`
  printed scale):
  - row 0 `{"date":"2026-03-01","amount":"5000.00","direction":"Debit","currency":"INR","description_raw":"STORE
    1111ref2222tail UPI/DR/000000000001/EXAMPLE ABC0000000001ref MERCHANT/UTIB/0000/UPI AU","ledger":{"balance":
    "6570.79","balance_delta":"-5000.00","amount_matches_delta":true,"is_suspect":false,"direction_source":
    "OpeningBalance","serial":""}}`
  - row 1 `{"date":"2026-03-02","amount":"10000.00","direction":"Credit","currency":"INR","description_raw":"EMPLOYER
    3333ref4444tail UPI/CR/000000000002/EXAMPLE XYZ0000000002ref SALARY/UTIB/0000/UPI AU 1800 1200 1200 www.aubank.in
    customercare@aubank.in","ledger":{"balance":"16570.79","balance_delta":"10000.00","amount_matches_delta":true,
    "is_suspect":false,"direction_source":"BalanceDelta","serial":""}}`

  Top level: `period_start "2026-03-01"`, `period_end "2026-05-31"`, `card_last4 "0042"`,
  `printed_opening_balance "11570.79"`, `printed_closing_balance "16570.79"` (the **last row balance**, **NOT** the
  header `223.34`; **no** `closing_balance` block stored — that is asserted by the separate chain test),
  `errored_lines []`. **100% synthetic/redacted** (fabricated payers, amounts, account number — FR-034). Ref:
  `data-model.md §3`, `research.md D8/D9`.
- [ ] T004 [US9] Extend the parity harness `core/crates/kaname-core/tests/parity.rs` → **RED** (**NO schema change** —
  the `#[serde(default)]` optional-ledger schema already landed in 007; do **NOT** touch the 11 existing
  fixtures/cases):
  - Extend the `use kaname_core::{…}` block (`parity.rs:12`) to add `au_bank_claims, read_au_bank_statement` (keep the
    list sorted — `au_bank_claims` before `check_balance_chain`, `read_au_bank_statement` before
    `read_federal_bank_statement`).
  - Add the wrapper (mirrors `parse_federal_bank`, `parity.rs:148`; empty geometry — AU sets no `column_split_x`):
    `fn parse_au_bank(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_au_bank_statement(lines, full_text, Vec::new()) }`.
  - Add **one** `Case` row to `CASES` (`parity.rs:75`, after the `federal/bank_account/fi.json` case):
    `Case { label: "AU bank savings", parse: parse_au_bank, rel_path: "au/bank_account/savings.json" }`. It flows
    through the existing `golden_fixtures_match_expected_output` (`:254`) and `parse_is_deterministic` (`:263`)
    unchanged.
  - Add **one** chain test `au_bank_statement_balance_chain_reconciles` (mirror the single-fixture
    `icici_bank_statement_balance_chain_reconciles`, `parity.rs:331`, **not** the multi-fixture loop):
    `load_fixture("au/bank_account/savings.json")` →
    `check_balance_chain(read_au_bank_statement(fx.lines, fx.full_text, Vec::new()))` → assert
    `result.status == ChainStatus::Reconciled`, `result.suspect_count == 0`, `!result.row1_direction_fallback`,
    `result.checked_rows == 2` (SC-002).
  - Add `au_bank_claims_accepts_own_document_and_rejects_others` (mirror
    `federal_claims_accepts_own_document_and_rejects_others`, `parity.rs:319`):
    `au_bank_claims(load_fixture("au/bank_account/savings.json").full_text) == true`; `== false` for a **credit-card**
    text that carries `aubank.in` but **no** Savings/Current marker (e.g.
    `"AU Small Finance Bank\naubank.in\nCredit Card Statement\nXXXXXXXXXXXX1002"` — `claim_any` unmet); and `== false`
    for a foreign issuer (`"ICICI Bank Statement"` — bank-code/marker guard) (SC-006).
  - ⚠️ **Verify RED**: `make core-test` **fails to compile** (`read_au_bank_statement`/`au_bank_claims` absent). Ref:
    `contracts/ffi.md §C4`, `data-model.md §3`.
- [ ] T005 [P] [US1] Author the **RED** Swift bridge test `ios/Tests/AUBankParseTests.swift` — "core ↔ Swift AU bank
  parse + balance chain" (`import Foundation` + `import KanameCore` + `import Testing`, Swift Testing), mirroring
  `ios/Tests/FederalBankParseTests.swift`. Build `lines`/`fullText` with `[...].joined(separator: "\n")` (the `₹`
  glyph is a literal UTF-8 character in the source); exact amounts via
  `Decimal(string:locale: Locale(identifier: "en_US_POSIX"))`; call
  `readAuBankStatement(lines:fullText:firstRowWords: [])` (**empty** geometry). Assert:
  - **2 rows** with **delta-derived** directions **`[.debit, .credit]`** — Debit then Credit — **despite** the
    `UPI/DR`/`UPI/CR` text in the narrations.
  - The dash-marked empty column is skipped so the **non-dash** side is the amount: row 1 `Decimal("5000.00")` (Debit;
    Credit `-`), row 2 `Decimal("10000.00")` (Credit; Debit `-`), exact `Foundation.Decimal` (never `Double`).
  - `valueDate` `"2026-03-01"` / `"2026-03-02"`; per-row `ledger?.balance` `"6570.79"` / `"16570.79"`,
    `directionSource` `.openingBalance` then `.balanceDelta`, `amountMatchesDelta`, `!isSuspect`, `ledger?.serial ==
    ""`.
  - Printed `printedOpeningBalance == Decimal("11570.79")` and `printedClosingBalance == Decimal("16570.79")` (the
    **last row balance**, NOT the header `223.34`); `cardLast4 == "0042"`; `periodStart "2026-03-01"` / `periodEnd
    "2026-05-31"`; `erroredLines.isEmpty`.
  - `checkBalanceChain(statement:).status == .reconciled` (`suspectCount == 0`, `!row1DirectionFallback`, `checkedRows
    == 2`).
  - `auBankClaims(fullText:)` **accepts** the AU savings statement and **rejects** a credit-card statement lacking a
    Savings/Current marker (e.g. an AU-branded card text with `aubank.in` but no `Savings Account`/`Current Account`).
  - Use `firstRowWords: []`; `try #require(statement.lines.first)`; amounts compared as exact `Foundation.Decimal`.
    **Comments on their OWN line — never trailing after code** (swift-format `[Spacing]` rejects trailing inline
    comments). ⚠️ **Verify RED**: won't build until the xcframework is regenerated with the exports in Phase 4. Ref:
    `contracts/ffi.md §C5`, `ios/Tests/FederalBankParseTests.swift`.

**Checkpoint**: The one fixture is in place; Rust parity RED (1 `Case` row + 1 chain test + 1 claim split won't
compile); Swift bridge test RED. Test-first satisfied — engine code may now begin.

---

## Phase 3: User Story 1 — Turn an AU savings/current statement into transactions, on-device (Priority: P1) 🎯 MVP

**Goal**: Recognize an AU **bank-account** statement and return one transaction per ledger row (date, exact amount,
**delta-derived** direction, INR, running balance, stitched description) — 100% on-device. Building the engine here
**also lands the behaviours** US2–US8 verify independently in Phases 5–11.

**Independent Test**: `read_au_bank_statement(savings.lines, savings.full_text, vec![])` returns the expected **2**
rows (row 1 2026-03-01 / 5000.00 / Debit / 6570.79; row 2 2026-03-02 / 10000.00 / Credit / 16570.79), and
`au_bank_claims` accepts the AU savings statement / rejects a credit-card statement — with no network in the parse
path.

> Engine landing order (requester step 4): **au_bank.rs (the AU config) + mod.rs → ffi.rs exports + lib.rs
> re-exports → `make core-fmt` then GREEN core-test/core-lint**. The design is **LOCKED** in
> `data-model.md`/`contracts/` — port it, don't re-derive it. **No `common.rs`/base/`icici_bank.rs`/`federal_bank.rs`
> change.**

- [ ] T006 [US1] **The AU config — `core/crates/kaname-core/src/statement/au_bank.rs` (NEW)** + wire
  `statement/mod.rs`. Port `au_bank.py` to a **zero-sized** `pub struct AuBankReader;` `impl LedgerReaderConfig`,
  mirroring `IciciBankReader` (`icici_bank.rs` — which likewise overrides `claim_any` + `closing_balance_re`).
  `pub const BANK_CODE: &str = "AU";`. Each regex a `static` built once via `LazyLock<Regex>` (exact patterns from
  `data-model.md §2` / `research.md D1`):
  - `ANCHOR_RE` (**no `(?i)`** — dates are `[A-Za-z]{3}`, ICICI-style):
    `^(?P<date>\d{2} [A-Za-z]{3} \d{4})\s+\d{2} [A-Za-z]{3} \d{4}\s+(?P<desc>.*?)\s*(?P<withdrawal>[\d,]+\.\d{2}|-)\s+(?P<deposit>[\d,]+\.\d{2}|-)\s+(?P<balance>[\d,]+\.\d{2})\s*$`
    (two `DD Mon YYYY` dates; non-greedy `desc`; a **Debit** and a **Credit** column each **either** a money token
    **or** a dash `-`; then the running Balance; **no** `serial` group)
  - `OPENING_RE` `(?i)Opening Balance\s*\([^)]*\)\s*:\s*([\d,]+\.\d{2})` (tolerates any parenthesised currency group,
    incl. `(₹)`)
  - `CLOSING_RE` `(?i)Closing Balance\s*\([^)]*\)\s*:\s*([\d,]+\.\d{2})` (**narration-skip only** — see below; NEVER
    sets the printed closing)
  - `PERIOD_RE` `(?i)Statement Period\s*:\s*(\d{2} [A-Za-z]{3} \d{4})\s+to\s+(\d{2} [A-Za-z]{3} \d{4})`
  - `AU_ACCOUNT_RE` `(?i)Account\s+Number\s*:?\s*X*([0-9]{6,})` (optional masked `X*`; **6+** digits)
  - Trait methods: `fn bank_code()` → `BANK_CODE`; `fn claim_all()` → `&["aubank.in"]`; **`fn claim_any()` →
    `&["Savings Account", "Current Account"]`** (override — like ICICI); `fn anchor_res()` → `vec![&ANCHOR_RE]`
    (**one** anchor); `fn opening_balance_re()` → `Some(&OPENING_RE)`; **`fn closing_balance_re()` →
    `Some(&CLOSING_RE)`** (override — consumed **only** by `is_balance_line` to skip the `Closing Balance(₹)` line;
    **not** used to set `printed_closing_balance`); **no** `column_split_x` override (default `None` — no geometry);
    **no** `provisional_direction` override (default `Debit`, unused); `fn account_tail(&self, text)` →
    `account_tail_last4(text, &AU_ACCOUNT_RE)` (override — like ICICI); `fn enrich(&self, statement, full_text)` →
    `PERIOD_RE` groups 1&2 → `period_start`/`period_end` via `parse_date`, then `statement.card_last4 =
    self.account_tail(full_text)`. `use crate::statement::common::{account_tail_last4, parse_date};`,
    `use crate::statement::ledger_reader::LedgerReaderConfig;`, `use crate::statement::base::ParsedStatement;`,
    `use regex::Regex;`, `use std::sync::LazyLock;`.
  - **Wire** `core/crates/kaname-core/src/statement/mod.rs`: add `pub mod au_bank;` (keep alphabetical — **first**,
    before `pub mod balance_chain;`). No new re-export needed (`AuBankReader` is referenced by `ffi.rs` via its path).
  - **Focused unit tests** (`#[cfg(test)]`, driving `read_ledger_lines(&AuBankReader, …)` / `claims_ledger`,
    mirroring `icici_bank.rs::tests`; comments on their own line):
    (a) **direction from the delta despite `UPI/DR`/`UPI/CR`** — row 1 is Debit (balance falls `11570.79→6570.79`)
    though its narration contains `UPI/DR`; row 2 is Credit (rises `6570.79→16570.79`) though its narration contains
    `UPI/CR`; flip the surrounding balances and the direction flips (US2); (b) **dash-column non-dash-side amount** —
    row 1's amount is the Debit `5,000.00` (Credit `-`) and row 2's is the Credit `10,000.00` (Debit `-`), each
    `amount_matches_delta == true` (US3); (c) **header/footer not a transaction** — the `Opening Balance(₹)`,
    `Closing Balance(₹)`, column-header, and the trailing footer `1800 1200 1200 www.aubank.in customercare@aubank.in`
    lines yield **no** transaction (2 rows, not more) while the footer folds into row 2's narration, and
    `printed_closing_balance == 16570.79` (last row) **not** `223.34` (US4/US5); (d)
    `claims_ledger(&AuBankReader, savings_text, "AU") == true` and `== false` for a **credit-card** text carrying
    `aubank.in` but no Savings/Current marker and for a wrong `bank_code` (US7). Ref: `data-model.md §2`,
    `research.md D2–D10`, `core/crates/kaname-core/src/statement/icici_bank.rs`.
- [ ] T007 [US1] **FFI exports + re-exports** — in `core/crates/kaname-core/src/ffi.rs`, mirroring
  `read_federal_bank_statement` (`ffi.rs:183`) / `federal_bank_claims` (`:194`): add
  `use crate::statement::au_bank::AuBankReader;` then
  `#[uniffi::export] pub fn read_au_bank_statement(lines: Vec<String>, full_text: String, first_row_words:
  Vec<Word>) -> ParsedStatement { read_ledger_lines(&AuBankReader, &lines, &full_text, &first_row_words) }` and
  `#[uniffi::export] pub fn au_bank_claims(full_text: String) -> bool { claims_ledger(&AuBankReader, &full_text,
  "AU") }`. **Reuse** the already-exported `check_balance_chain` (`ffi.rs:152`) — do **not** add a second copy.
  Re-export both new fns in `core/crates/kaname-core/src/lib.rs` by extending the `pub use ffi::{…}` block
  (`lib.rs:28`, add `au_bank_claims, read_au_bank_statement` — keep the list sorted). No `uniffi.toml` change; no new
  type crosses the FFI. Depends on T006. Ref: `contracts/ffi.md §C1`, `research.md D2`.
- [ ] T008 [US1] **Green the engine side**: run `make core-fmt` (rustfmt), then `make core-test` — the AU parity
  `Case` row (T004) now **PASSES** for the savings vector (2 rows incl. ledger fields; `printed_opening 11570.79` /
  `printed_closing 16570.79`; `period 2026-03-01→2026-05-31`; `card_last4 "0042"`; `errored_lines []`), the
  `au_bank_statement_balance_chain_reconciles` test (RECONCILED, 0 suspects, no fallback, `checked_rows == 2`), the
  `au_bank_claims` split, and the `au_bank.rs` unit tests — while **all 11 prior parity cases (6 credit-card + ICICI
  bank + 2 HDFC bank + 2 Federal bank) stay green** (fixtures untouched) — then `make core-lint` (fmt `--check` +
  clippy `-D warnings`). Verify **RED→GREEN** for the Rust harness. Depends on T007. Ref: `quickstart.md §Verify —
  core`.

**Checkpoint**: The engine parses the golden AU statement, the balance chain reconciles, and the Rust parity + chain
+ claim-split + determinism + unit tests are green (Swift bridge greened in Phase 4). US1 is functional on the Rust
side; no base/shared/other-reader file changed.

---

## Phase 4: UniFFI bridge — regenerate the xcframework + green the Swift test (US1 / US10)

**Goal**: Surface the two new functions to Swift (reusing the existing types) and green the "core ↔ Swift AU bank
parse + balance chain" test.

- [ ] T009 [US1] Run `make core-xcframework` to rebuild `ios/Frameworks/KanameCoreFFI.xcframework` +
  `ios/Generated/kaname_core.swift` (git-ignored artifacts) now exposing `readAuBankStatement` / `auBankClaims`
  (reusing the existing `Word`, `LedgerMetadata`, `DirectionSource`, `ChainResult`, `ChainStatus`, `ParsedStatement`
  Swift types — **no new binding shape**, `uniffi.toml` untouched). ⚠️ **MUST run before `tuist generate`**
  (`Makefile:32`, `quickstart.md §Verify — iOS`). Depends on T007. Ref: `contracts/ffi.md §C1`.
- [ ] T010 [US1] Run `make ios-test` (`ios-gen` → `core-xcframework` → `tuist generate` → `xcodebuild …
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test`) to **green**
  `ios/Tests/AUBankParseTests.swift` (T005) — 2 rows with exact `Foundation.Decimal` amounts (`5000.00`/`10000.00`
  from the non-dash column), delta-derived `.debit`/`.credit` **despite** the `UPI/DR`/`UPI/CR` narration, per-row
  `ledger` (balance / `directionSource` / empty `serial`), printed opening `11570.79` / closing `16570.79`, period,
  `cardLast4 "0042"`, `checkBalanceChain(...).status == .reconciled` (suspectCount 0, no row-1 fallback, checkedRows
  2), and `auBankClaims` accept-savings / reject-credit-card. ⚠️ **Local Xcode: create the "iPhone 16" simulator
  first.** Verify **RED→GREEN** for the Swift bridge test. Depends on T009. Ref: `quickstart.md §Verify — iOS`.

**Checkpoint**: US1 MVP delivered end-to-end (Rust engine + balance chain + Swift bridge). A person's AU
savings/current statement text → transactions + a RECONCILED verdict, on-device. The balance-ledger family now spans
all four target banks.

---

## Phase 5: User Story 2 — Direction from the running-balance delta, NEVER from the narration's UPI/DR·UPI/CR; the amount is an independent check (Priority: P2)

**Goal**: Each row's direction is decided **solely** by the running-balance movement (fall ⇒ debit, rise ⇒ credit);
AU prints **no** per-row marker and the `UPI/DR`/`UPI/CR` tokens are ordinary narration text (the counterparty's leg)
read by nothing; the printed amount (the non-dash column) is an **independent** check (`amount == |delta|`). *(Impl
landed in the reused `read_ledger_lines` delta logic; T006's anchor carries no direction marker.)*

**Independent Test**: The debit row's narration contains `UPI/DR` and the credit row's contains `UPI/CR`, yet the
ordered directions are Debit then Credit from the deltas (−5000.00 then +10000.00); flipping the balance movement
flips the direction regardless of the printed amount, column, or narration text; each amount reconciles against the
delta.

- Delivered by the reused base (delta direction) + T006's marker-free anchor · Verified by **T006** unit test (a)
  (Debit despite `UPI/DR`, Credit despite `UPI/CR`; delta-flip flips direction), **T003** (delta-derived directions +
  `amount_matches_delta true`), **T004**/**T010** (both directions over the harness + bridge), and the reused
  `ledger_reader.rs` delta-flip unit test from slice 007.

**Checkpoint**: Direction is provably delta-sourced; the `UPI/DR`·`UPI/CR` narration is inert; the amount is a pure
cross-check.

---

## Phase 6: User Story 3 — One template with dash-marked empty debit/credit columns: the non-dash side is the amount (Priority: P3)

**Goal**: One anchor reads AU's single template; each row prints a **Debit** and a **Credit** column where the empty
side is a literal **`-`**, and the transaction amount is the **non-dash** column — resolved by the base's unchanged
`loose_amount("-") → None`. *(Impl landed in T006's single `anchor_res()` + the reused two-column
`anchor_amount`/`loose_amount`; adds no base capability — FR-003/004/005.)*

**Independent Test**: Row 1's amount is the Debit `5,000.00` (Credit `-`), row 2's is the Credit `10,000.00` (Debit
`-`); the dash contributes no value; a column-header/header line (no two leading dates) matches no anchor; each amount
reconciles against the delta.

- Delivered by the reused `anchor_amount`/`loose_amount` (`ledger_reader.rs:238`/`:262`) + T006's one dash-tolerant
  anchor · Verified by **T006** unit test (b) (non-dash side is the amount, both rows reconcile), **T003** (amounts
  `5000.00`/`10000.00` from the non-dash column), **T004**/**T010**.

**Checkpoint**: The single template + dash-empty column are pure configuration on the base's existing two-column
amount handling; the non-dash side wins.

---

## Phase 7: User Story 4 — Opening balance from the parenthesised-currency header; opening-anchored row 1; the Closing Balance(₹) line is a non-transaction whose figure is NOT the printed closing (Priority: P4)

**Goal**: `OPENING_RE` reads `Opening Balance(₹) : 11,570.79` (any parenthesised group tolerated) → `11570.79`; row 1
is opening-anchored (`direction_source = OpeningBalance`, delta `6570.79 − 11570.79 = −5000.00 ⇒ Debit`, no geometry);
`CLOSING_RE` recognizes the `Closing Balance(₹) : 223.34` line as a **non-transaction** (skipped during stitching) but
its figure is **never** the printed closing — the printed closing is the **last row's running balance** `16570.79`
(`ledger_reader.rs:195`). *(Impl landed in T006's `OPENING_RE`/`CLOSING_RE` + the reused row-1 bootstrap +
`is_balance_line`.)*

**Independent Test**: Opening reads `11570.79`; row 1 `direction_source = OpeningBalance`, later rows `BalanceDelta`;
`printed_closing_balance == 16570.79` (NOT the header `223.34`); the `Closing Balance(₹)` line yields no transaction;
no row-1 direction fallback in the chain.

- Delivered by **T006** (`OPENING_RE` + `CLOSING_RE` for narration-skip) + the reused row-1 bootstrap +
  `printed_closing_balance = last anchor balance` (`:195`) · Verified by **T006** unit test (c)
  (`printed_closing_balance == 16570.79` not `223.34`; closing line not a row), **T003**
  (`direction_source`; `printed_opening 11570.79`; `printed_closing 16570.79`), **T004** (chain
  `!row1_direction_fallback`), **T010**.

**Checkpoint**: Opening is read from the `(₹)` header; row 1 is opening-anchored; the closing header figure is
discarded — the printed closing is the last row balance.

---

## Phase 8: User Story 5 — Faithful narration stitching (above + below, incl. the folded footer), and the non-transaction lines (Priority: P5)

**Goal**: Each row's `description_raw` reproduces the web engine's stitched narration **byte-for-byte** — the `UPI/…`
line printed **above** each anchor folds into **that** row (Part A), and the trailing detail lines below the last
anchor — **including the footer** `1800 1200 1200 www.aubank.in customercare@aubank.in` — fold into **row 2** (Part
B) — with **no** normalization/trim/reorder. The header, column-header, `Opening Balance(₹)`, `Closing Balance(₹)`,
and footer lines yield **no** transactions (exactly 2 rows). *(Impl landed in the reused `stitch_narration`; the exact
strings are pinned by the fixture.)*

**Independent Test**: Row 1 `= "STORE 1111ref2222tail UPI/DR/000000000001/EXAMPLE ABC0000000001ref
MERCHANT/UTIB/0000/UPI AU"` and row 2 `= "EMPLOYER 3333ref4444tail UPI/CR/000000000002/EXAMPLE XYZ0000000002ref
SALARY/UTIB/0000/UPI AU 1800 1200 1200 www.aubank.in customercare@aubank.in"` exactly; the non-transaction lines
produce no rows.

- Delivered by the reused `stitch_narration` (`ledger_reader.rs:271`) · Verified by **T003** (the exact
  `description_raw` bytes incl. the folded footer), **T006** unit test (c) (footer not a transaction; 2 rows),
  **T004** (parity asserts them), **T010** (Swift `descriptionRaw`). ⚠️ Do **not** "clean up" the stitched text — it
  would break parity (research **D8**).

**Checkpoint**: Narration parity is byte-exact, the folded footer included; the row count is exactly 2.

---

## Phase 9: User Story 6 — Ledger metadata: the billing period and a bank-aware account last-4 (Priority: P6)

**Goal**: The statement records its period (`Statement Period : 01 Mar 2026 to 31 May 2026`, `%d %b %Y` →
`2026-03-01 → 2026-05-31`) and account **last-4** (`0042` from `…1234567890120042`) via the shared
`account_tail_last4` with AU's primary regex else the longest `\d{9,}` run — retaining only the trailing four; AU's
anchor has no serial group ⇒ every row's `serial` is empty. *(Impl landed in T006's `PERIOD_RE`/`AU_ACCOUNT_RE`/`enrich`
+ the reused `account_tail_last4`.)*

**Independent Test**: Period `2026-03-01 → 2026-05-31`; `card_last4 "0042"`; only the trailing four retained; every
row's serial empty; a missing field is left unset, transactions still returned.

- Delivered by **T006** (`PERIOD_RE` + `AU_ACCOUNT_RE` + `enrich`) + the reused `account_tail_last4` (`common.rs:177`)
  · Verified by **T003** (period + `0042` + empty serials), **T004**/**T010**, and the reused `account_tail_last4`
  behaviour (from 008).

**Checkpoint**: The ledger is auditable and attributable — period (`%d %b %Y`) + the correct bank-account last-4
(never the full number); serials empty.

---

## Phase 10: User Story 7 — The document gate claims an AU savings/current statement and rejects a credit-card statement — AU is the SOLE reader under `AU` (Priority: P7)

**Goal**: `au_bank_claims` requires the `AU` bank code + **all** `claim_all` (`["aubank.in"]`) + **any** `claim_any`
(`["Savings Account", "Current Account"]`) — accepting the AU savings/current statement and **rejecting** a
credit-card statement (which lacks a Savings/Current marker) and a foreign issuer. AU has **no** credit-card reader in
this client, so `AuBankReader` is the **sole** reader keyed to `AU`; there is no sibling to mis-route to. *(Impl
landed in T006's `claim_all`/`claim_any` + the reused `claims_ledger`; research **D6**.)*

**Independent Test**: The reader claims the AU savings fixture, rejects a credit-card statement lacking a
Savings/Current marker and a wrong-code document; inspecting the registry shows the AU reader is the sole reader under
`AU` — 0 misroutes.

- Delivered by **T006** (`claim_all` + `claim_any`) + the reused `claims_ledger` · Verified by **T006** unit test (d),
  **T004** (`au_bank_claims_accepts_own_document_and_rejects_others`), **T010** (Swift claims accept/reject).

**Checkpoint**: The savings/current-vs-CC gate is precise and AU is the sole `AU` reader — 0 misroutes.

---

## Phase 11: User Story 8 — A config-on-an-existing-base slice: reuse the base, the balance chain, and the shared account-tail helper — all unchanged, with ZERO new shared code (Priority: P8)

**Goal**: The AU parse is delivered **purely** by a per-issuer configuration plugged into the **unchanged** base,
balance-chain check, **and** the shared `account_tail_last4` helper — this slice adds **NO** new shared code at all
(the leanest of the family; even the dash-empty column is handled by the base's existing `loose_amount`). *(Impl
landed entirely in T006 + T007; `common.rs`, `ledger_reader.rs`, `balance_chain.rs`, `base.rs`, `icici_bank.rs`,
`federal_bank.rs`, and the harness schema are byte-unchanged.)*

**Independent Test**: No base internals (anchor recognition, direction-from-delta, amount-as-check incl. the
dash-skipping two-column resolution, stitching, row-1 bootstrap, errored-vs-suspect, the balance chain,
`account_tail_last4`, the parity harness, the privacy gate) were modified; AU supplies only its config + one fixture;
**no** new shared function.

- Delivered by **T006** (the config) + **T007** (2 FFI exports reusing `check_balance_chain`) · Verified by **T008**
  (all 11 prior cases green — no fixture migration) + the constitution review **T015** (the diff is exactly
  `au_bank.rs` + `mod.rs` line + 2 `ffi.rs` exports + `lib.rs` re-exports + 1 fixture + harness rows + 1 Swift test —
  **nothing** shared/base).

**Checkpoint**: AU is a genuine config-on-base; the base/chain/helper/harness/gate are untouched; the shared footprint
is **zero**.

---

## Phase 12: User Story 9 — Proven byte-for-byte against one golden fixture, RECONCILED (Priority: P9) 🛡️ whole-slice guard

**Goal**: The parity harness is the **regression-proof** guarantee pinning the AU template to the web engine — reusing
the 007 schema (optional ledger fields; a dedicated chain test), with the 11 prior vectors reproducing **unchanged**.
*(Fixture T003; harness/chain/claim tests T004; greened T008.)*

**Independent Test**: The harness over the ported AU vector matches expected output exactly (rows + ledger metadata +
printed opening/closing + period + last-4 + RECONCILED chain), re-running is stable; all 11 prior issuers still
reproduce their vectors.

- [ ] T011 [US9] Finalize `core/crates/kaname-core/tests/parity.rs` as the **whole-slice guard**: confirm the AU
  `Case` row calls `parse_au_bank` (empty geometry) and matches field-by-field — `value_date`, exact `Decimal`
  amounts (`5000.00`/`10000.00`, Indian grouping stripped, printed scale preserved), **delta-derived directions
  despite the `UPI/DR`/`UPI/CR` narration**, `INR`, `description_raw` **byte-for-byte** (incl. the folded footer;
  the `₹` glyph in `full_text`/`lines` intact), per-row
  `balance`/`balance_delta`/`direction_source`/`serial (== "")`/`amount_matches_delta`/`is_suspect`, and
  `printed_opening 11570.79`/`printed_closing 16570.79` (last row, NOT `223.34`)/`period 2026-03-01→2026-05-31`/`card_last4
  "0042"`/`errored_lines []` (SC-001/007/009); the `au_bank_statement_balance_chain_reconciles` test asserts
  **RECONCILED**, 0 suspects, no row-1 fallback, `checked_rows == 2` (SC-002); the determinism **re-run**
  (`parse_is_deterministic`) covers the AU vector (SC-012); the fixture is **100% synthetic** (FR-034); and confirm
  the schema stayed **back-compatible** — the 11 prior fixtures + their assertions are **byte-identical** (no
  migration). Ref: `contracts/ffi.md §C3/§C4`, `research.md D8`.

**Checkpoint**: Parity is an enforced guarantee for the AU template; one harness serves all readers with no
prior-fixture migration.

---

## Phase 13: User Story 10 — Privacy gate & the Swift bridge: zero network, no new dependency, reachable from Swift (Priority: P10) 🛡️ inherited guard

**Goal**: Prove the AU bank-account parse **and** chain path is egress-free — **structurally** (no networking crate
can even link) and **behaviorally** (determinism) — via the **inherited** gate with **zero** new config, and confirm
reachability over UniFFI (greened in T010). *(No new script/CI: this slice adds no dependency, so the audit is
byte-identical.)*

**Independent Test**: `make core-privacy-audit` passes only when zero networking crates are in the shipped graph; the
reader is callable over UniFFI from Swift; no new runtime (or networking) dependency was added; money stays an exact
`Decimal`.

- [ ] T012 [US10] Confirm the inherited privacy-egress gate stays **GREEN with ZERO changes**: run `make
  core-privacy-audit` → passes (no networking crate in `kaname-core` deps) — this slice adds **no dependency**
  (runtime *or* dev), so `cargo tree -p kaname-core -e normal` is byte-identical (`Cargo.toml`/`uniffi.toml`
  unchanged — FR-030/031/032, SC-010); the determinism/purity assertion over the AU vector lives in
  `tests/parity.rs` (T004/T011, FR-028, SC-012); the whole reader (`read_au_bank_statement`, `au_bank_claims`, reused
  `check_balance_chain`) is reachable from Swift over UniFFI (proved GREEN in T010, SC-011, FR-029); confirm **no**
  telemetry/analytics/crash-reporter enters the parse/chain path and **no** network entitlement/ATS is added app-side,
  and money is `Decimal` (never `f64`) (FR-010, SC-009). Ref: `quickstart.md §Verify — core`, `research.md D1`, spec
  US10.

**Checkpoint**: Privacy-egress remains a first-class, structurally- and behaviorally-enforced gate covering the AU
bank-account parse **and** the reused balance-chain check; the reader is reachable from Swift.

---

## Phase 14: Polish & Cross-Cutting — full iOS Local Verification Gate green

**Purpose**: Prove the whole slice is merge-ready (SC-013) and review the constitution guarantees.

- [ ] T013 [P] Light docs alignment (no behaviour change): note the **fourth (and final) bank config** (AU
  savings/current, one template, dash-empty column) on the balance-ledger base where the engine/build is described
  (`README.md` and/or `specs/010-au-bank-ledger-reader/quickstart.md`); ensure `fixtures/README.md` reflects the new
  AU bank vector under `fixtures/au/bank_account/`. Refresh the `statement/mod.rs` doc comment only if it enumerates
  readers. Optionally run `.specify/scripts/bash/update-agent-context.sh copilot` and, if it reintroduces the "iOS 18
  targe" typo in `.github/copilot-instructions.md`, fix to "iOS 18 target" and leave it **unstaged** (author commits)
  — see `quickstart.md §Agent context + typo check`. No stale wording.
- [ ] T014 **Run the full iOS Local Verification Gate green**, in order: `make core-lint && make core-test && make
  core-privacy-audit && make lint && make ios-gen && make ios-test`. ⚠️ `make core-xcframework` is rebuilt before
  `tuist generate` (via `ios-gen`, `Makefile:32`); local Xcode requires the **"iPhone 16"** simulator; CI runs the
  same (core on ubuntu, iOS on **macos-15**). This is the SC-013 merge gate. Depends on T008/T010/T011/T012/T013. Ref:
  `quickstart.md §Verify — core/§Verify — iOS`.
- [ ] T015 [P] Final constitution review (no code change): **NO new dependency** (runtime *or* dev) —
  `Cargo.toml`/`uniffi.toml` unchanged; the diff is exactly `statement/au_bank.rs` (+ its unit tests) +
  `pub mod au_bank;` in `mod.rs` + 2 `ffi.rs` exports + `lib.rs` re-exports + 1 fixture under
  `fixtures/au/bank_account/` + 1 `parity.rs` `Case` row + 1 chain test + 1 claim-split test + 1 Swift test; **no new
  record/enum/FFI type** (`check_balance_chain` reused); **no shared/base change** (`common.rs`, `ledger_reader.rs`,
  `balance_chain.rs`, `base.rs`, `icici_bank.rs`, `federal_bank.rs`, `hdfc_bank.rs`, and the harness schema **all
  byte-unchanged**); **money is `Decimal`, never `f64`** (no geometry — AU sets no `column_split_x`); direction
  **delta-derived** with an auditable `direction_source`, the narration's `UPI/DR`·`UPI/CR` **inert**;
  `printed_closing_balance == 16570.79` (last row) **not** the header `223.34`; **exact** `amount == |delta|` in the
  reader vs the **₹1.00** tolerance **only** in `balance_chain`; `card_last4 "0042"` via `account_tail_last4` (never
  the full number); the `₹` (U+20B9) glyph preserved; no secrets / network entitlements / copyleft (GPL/AGPL/LGPL)
  deps (FR-036); all fixture/test data synthetic (FR-034); the 11 prior fixtures + the harness schema stay
  back-compatible (no migration). Confirm against `git diff` before handoff. Ref: `plan.md §Constitution
  Check/§Complexity Tracking`.

**Checkpoint**: Whole slice is green end-to-end and constitution-clean — ready to ship.

---

## Phase 15: Ship — two commits, PR #11, CI, merge (requester step 7)

**Purpose**: Land the slice. Executed **only after** Phase 14 is green. (Generation writes nothing here; the
implementer runs these once the gates pass.)

- [ ] T016 Create **two small, pure commits** on `010-au-bank-ledger-reader` (RED→GREEN kept coherent, matching the
  prior bank slices' shape):
  **Commit 1 — engine + fixture + parity**: `core/crates/kaname-core/src/statement/au_bank.rs` (+ its unit tests),
  `pub mod au_bank;` in `core/crates/kaname-core/src/statement/mod.rs`, `core/crates/kaname-core/src/ffi.rs` (2
  exports), `core/crates/kaname-core/src/lib.rs` (re-exports), `fixtures/au/bank_account/savings.json`,
  `core/crates/kaname-core/tests/parity.rs` (wrapper + 1 `Case` row + 1 chain test + claim split), and any docs from
  T013.
  **Commit 2 — Swift test**: `ios/Tests/AUBankParseTests.swift`.
  Do **not** commit generated artifacts (`ios/Generated/…`, `ios/Frameworks/…` are git-ignored). Ref: requester step
  7.
- [ ] T017 Push the branch, open **PR #11** (`SSKUltra/kaname`, base default branch — **#11** is the next number
  after the merged **#10** (Federal / slice 009); slice-number ≠ PR-number because the intervening
  `chore/harden-ios-ci-simulator` took **#9**; confirm with `gh pr list` before opening), **watch CI** — both the
  **core** job (ubuntu: `core-lint` + `core-test` + `core-privacy-audit`) and the **iOS** job (**macos-15**:
  `core-xcframework` → `tuist generate` → `xcodebuild … iPhone 16` test) go green — then
  **`gh pr merge --rebase --delete-branch`**. Ref: requester step 7.

**Checkpoint**: AU savings/current joins the balance-ledger family as the **fourth and final** reference reader — one
config on the unchanged base, byte-for-byte with the web engine, with a zero shared footprint. The four-bank
balance-ledger family is complete.

---

## Dependencies & Execution Order

### Phase order

1. **Setup (P1)** → 2. **Test-First Foundation (P2, RED)** → 3. **US1 GREEN engine pipeline (P3)** →
4. **Bridge/Swift green (P4)** → 5–11. **US2/US3/US4/US5/US6/US7/US8 verification (P5–P11)** →
12. **US9 parity guard (P12)** → 13. **US10 privacy guard (P13)** → 14. **Polish + full gate (P14)** →
15. **Ship (P15)**.

- **Test-First (Phase 2) BLOCKS all engine code (Phase 3+)** — T003–T005 must exist and be RED first (Principle V,
  FR-033/035).
- **The US1 GREEN pipeline (T006→T008) is the critical path** and lands the behaviours US2–US8 verify.

### Task-level dependencies

- T003 (fixture) precedes T004 (parity `Case`/chain/claim) and T008 (green); T004/T005 (RED tests) precede **all**
  implementation (T006+).
- **Engine spine (linear — no shared/refactor task)**: **T006** (`au_bank.rs` + `mod.rs` + unit tests) → **T007**
  (`ffi.rs` exports + `lib.rs`, needs T006) → **T008** (`core-fmt` → Rust green, needs T007).
- T007 → **T009** (xcframework) → **T010** (Swift green). **T009 before any `tuist generate`.**
- Guards: **T011** (parity whole-slice) depends on T008; **T012** (privacy + reachability) depends on T008 (+ T010
  reachability).
- **T014 (full gate) depends on everything** (T008, T010, T011, T012, T013); T015 is review only.
- **Ship**: T016 depends on T014 (all green); T017 depends on T016.

### Parallel opportunities

- **Setup**: T001 [P] + T002 [P].
- **Test-First**: T003 [P] (fixture) + T005 [P] (Swift test) are different files; T004 edits `parity.rs` (run it
  alone; it references T003's fixture path to verify RED).
- **Engine spine**: **linear** (T006 → T007 → T008) — AU adds no shared/refactor task, so there is **no** parallel
  engine task.
- **Polish**: T013 [P] + T015 [P] (docs + review); T014 runs the gate alone.

**[P] set**: T001, T002, T003, T005, T013, T015.

**Critical path**: T003 → T004/T005 (RED) → **T006 → T007 → T008** → T009 → T010 → T011 → T012 → T014 → T016 → T017.

---

## Parallel Example: the Test-First Foundation (Phase 2)

```bash
# Phase 2 — author the two independent RED artifacts together (different files):
Task T003: "Author fixtures/au/bank_account/savings.json (exact bytes; 2 rows; dash-empty column; ₹ preserved; data-model.md §3 + research.md D8/D9)"
Task T005: "Author ios/Tests/AUBankParseTests.swift (RED core ↔ Swift AU bank parse + chain; delta directions despite UPI/DR·UPI/CR)"
# Then T004 edits tests/parity.rs (wrapper + 1 Case row + 1 chain test + claim split) → verify RED (won't compile).

# Phase 3 — the engine spine is LINEAR (no parallel task — zero shared/refactor work):
# T006 (statement/au_bank.rs — AuBankReader impl LedgerReaderConfig, 1 anchor, claim_any + closing_balance_re, enrich, mod.rs, unit tests)
#   → T007 (ffi.rs exports + lib.rs re-exports) → T008 (core-fmt → core-test → core-lint GREEN).
```

---

## Implementation Strategy

### MVP first (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 **RED** (fixture → parity `Case`/chain/claim → Swift) → 3. Phase 3 engine spine
(T006→T008, `make core-fmt` then green) → 4. Phase 4 bridge (T009–T010). **STOP & VALIDATE**: the AU savings statement
parses on-device through `read_au_bank_statement`, `check_balance_chain` reports RECONCILED, and the Swift suite is
green. This alone is a shippable, useful slice (the fourth bank config on the base — the leanest yet, completing the
family).

### Incremental delivery

Add US2 (delta direction + `UPI/DR`·`UPI/CR` inert + amount-as-check) → US3 (one template + dash-empty column) → US4
(opening from the `(₹)` header + closing-header-not-printed-closing) → US5 (narration stitching + folded footer) → US6
(period/last-4/empty serials) → US7 (savings/current-vs-CC gate, sole `AU` reader) → US8 (config-on-base, zero shared
code) — each an independent test increment over the **same** engine, already verified by the fixture/parity/unit/Swift
tests authored in Phases 2–4. Then lock the **guards**: US9 (golden parity — one vector, no prior-fixture migration)
and US10 (inherited privacy-egress + Swift reachability). Finish with the full-gate run (T014) and Ship (T016–T017,
two commits + PR #11).

### Story → task traceability

| Story | Delivered by | Independently verified by |
|---|---|---|
| **US1** on-device parse 🎯 | T006, T007, T008, T009, T010 | **T008** (Rust parity), **T010** (Swift), **T004** claim-split |
| **US2** delta direction / `UPI/DR`·`UPI/CR` inert / amount-as-check | reused `read_ledger_lines` delta logic + T006's marker-free anchor | **T006** unit test (a) (Debit despite `UPI/DR`, Credit despite `UPI/CR`; delta-flip) + **T003** + **T004**/**T010** + reused delta-flip test |
| **US3** one template / dash-empty column → non-dash amount | reused `anchor_amount`/`loose_amount("-")→None` + T006's one anchor | **T006** unit test (b) (non-dash side is the amount) + **T003** (amounts from the non-dash column) + **T004**/**T010** |
| **US4** opening from `(₹)` header / opening-anchored row-1 / closing-header-not-printed-closing | T006 (`OPENING_RE`/`CLOSING_RE`) + reused row-1 bootstrap + `printed_closing = last anchor` (`:195`) | **T006** unit test (c) (`printed_closing 16570.79` not `223.34`; closing line not a row) + **T003** (`direction_source`; printed opening/closing) + **T004** (no fallback) |
| **US5** narration stitching (folded footer) / non-transaction lines | reused `stitch_narration` | **T003** (byte-exact `description_raw` incl. footer) + **T006** (footer not a row; 2 rows) + **T004** + **T010** |
| **US6** ledger metadata (period / account last-4 / empty serials) | T006 (`PERIOD_RE`/`AU_ACCOUNT_RE`/`enrich`) + reused `account_tail_last4` | **T003** (period + `0042` + empty serials) + **T004**/**T010** |
| **US7** savings/current-vs-CC gate (sole `AU` reader) | T006 (`claim_all` + `claim_any`) + reused `claims_ledger` | **T006** unit test (d) + **T004** (`au_bank_claims` split) + **T010** (Swift claims) |
| **US8** config-on-base, ZERO new shared code | T006 (config) + T007 (2 FFI exports reusing `check_balance_chain`) | **T008** (11 prior cases green; no migration) + **T015** review |
| **US9** golden parity 🛡️ | T003, T004, T008 | **T011** (whole-slice guard; no prior migration) |
| **US10** privacy + bridge 🛡️ | *inherited* gate + T004 determinism + T007/T010 UniFFI | **T012** (privacy-egress + no-new-dep + reachability) |

---

## Notes

- **Test-first is mandatory** (Principle V, FR-033/035): T003–T005 are RED before Phase 3; T008 greens the Rust
  parity + chain + claim-split + unit guards, T010 greens the Swift bridge — each has an explicit RED→GREEN verify
  step. The `expected` block is the **locked characterization ground truth** (captured `savings` JSON; no live capture
  needed — `research.md` §Open questions: "None").
- **Design is LOCKED** in `plan.md`/`data-model.md`/`contracts/` — the porting tasks **sequence** it, they do not
  re-derive it. Every value (2 rows, ledger metadata, printed `11570.79`/`16570.79`, period, empty serials, `0042`,
  RECONCILED chain, the stitched narrations incl. the folded footer) is pinned in `data-model.md §3` + `research.md
  D8/D9`.
- **Use the REAL landed symbols** (mirror 009/007): `ParsedTransaction` (`value_date`) via `ParsedStatement.lines`;
  `check_balance_chain(statement: ParsedStatement) -> ChainResult` with `result.status == ChainStatus::Reconciled`.
  (The fixture JSON key is `expected.rows[]`.)
- **NO per-row Dr/Cr marker; the narration's `UPI/DR`·`UPI/CR` is COUNTERPARTY text** (research **D5**) — direction is
  delta-derived (row 1 `OpeningBalance`, later `BalanceDelta`), never the narration text, the amount's sign/magnitude,
  or the printed column. The debit row's narration contains `UPI/DR` and the credit row's contains `UPI/CR` — a
  coincidence; ignore it.
- **Dash-marked empty column** (research **D3**) — the anchor captures each of Debit/Credit as `([\d,]+\.\d{2}|-)`;
  the base's `loose_amount("-") → None` (`ledger_reader.rs:262`) makes `anchor_amount` pick the non-dash side (row 1
  Debit `5000.00`, row 2 Credit `10000.00`). Store amounts with `.00` (`"5000.00"`/`"10000.00"`).
- **Printed closing = last row balance** (research **D4**) — `printed_closing_balance = 16570.79`
  (`ledger_reader.rs:195`), **not** the header `Closing Balance(₹) : 223.34`; `closing_balance_re` exists **only** so
  `is_balance_line` (`:399`) skips that line during stitching.
- **`₹` (U+20B9) preserved** — the `Opening Balance(₹)` / `Closing Balance(₹)` lines keep the literal glyph verbatim
  in `full_text`/`lines`; in JSON it may be the raw char or `\u20b9` (both decode identically). `description_raw` is
  byte-for-byte; do **not** "clean up" stitched text.
- **The header/column-header/opening/closing/footer lines are not transactions** (research **D8**) — none begins with
  two `DD Mon YYYY` dates ⇒ no anchor; the footer folds into row 2's narration byte-for-byte. Exactly 2 rows.
- **Two-place amount-vs-delta**: the **reader** records **exact** `amount == |delta|`; the **₹1.00 tolerance** lives
  **ONLY** in `balance_chain::check`. The AU fixture reconciles (0 suspects, 0 errored).
- **`card_last4 "0042"`** via the shared `account_tail_last4(text, &AU_ACCOUNT_RE)` (`X*`/6+-digit primary else the
  longest `\d{9,}` run) — **already exists** in `common.rs:177` (no new helper).
- **AU is the SOLE reader under `AU`** (research **D6**) — no coexisting credit-card reader; the CC rejection is the
  gate declining a non-Savings/Current document (`claim_any` unmet). Mirrors `icici_bank.rs` (which also overrides
  `claim_any` + `closing_balance_re`) — structurally, not its patterns.
- **Additive & back-compatible & LEANEST**: no records/enums/FFI types added; **no shared/base/`common.rs` change at
  all** (`account_tail_last4` + `%d %b %Y` already present); the harness schema is untouched (extended in 007), so the
  **11 prior fixtures need NO migration**. **No new dependency** (runtime *or* dev); money is `Decimal` (no geometry
  exercised — AU sets no `column_split_x`).
- **REUSE, not rebuild**: the ledger base (`ledger_reader.rs`), the balance chain (`balance_chain.rs`), `common.rs`
  (`parse_amount`/`parse_date`/`account_tail_last4`, `%d %b %Y` present), `base.rs` records, the `tests/parity.rs`
  harness, the `ffi.rs` `Decimal`/`NaiveDate` bridges + the reused `check_balance_chain`, and the privacy-egress gate
  are inherited. The **only** NEW code is the AU config + FFI + fixture + tests.
- **iOS gate ordering**: `make core-xcframework` **before** `tuist generate` (`Makefile:32`); **iPhone 16** simulator;
  CI iOS job pinned to **macos-15**.
- **Swift specifics**: `[...].joined(separator: "\n")`; `Decimal(string:locale: Locale(identifier: "en_US_POSIX"))`;
  `firstRowWords: []`; `try #require(statement.lines.first)`; **comments on their OWN line** (swift-format `[Spacing]`
  rejects trailing inline comments).
- **[P]** = different files, no unfinished dependency. `[Story]` labels map each task to its user story.
- **Generation commits nothing**; the two commits + **PR #11** (`gh pr list` confirms #11 is next — #10 was Federal
  / slice 009, #9 was a chore PR) + `--rebase --delete-branch` merge are **Phase 15: Ship**, executed by the
  implementer after every gate is green.
