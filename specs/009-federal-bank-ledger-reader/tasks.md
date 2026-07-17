---
description: "Task list — Federal Bank (Savings/Current) Ledger Reader: the LEANEST config-on-existing-base slice (1 Federal config + 2 golden fixtures + 2 FFI exports reusing check_balance_chain; ZERO shared-code changes, zero new deps, zero new FFI types). Two templates (classic DD-MON-YYYY + Fi DD/MM/YYYY) behind one reader; a trailing Cr/Dr consumed-but-ignored; direction delta-derived. 2 commits + PR #10."
---

# Tasks: Read a Federal Bank (Savings/Current) Statement On-Device — the Third Balance-Ledger Reference Reader (Federal config on the existing ledger base; two statement templates; a consumed-but-ignored Cr/Dr marker)

**Input**: Design documents from `/specs/009-federal-bank-ledger-reader/`
**Prerequisites**: `plan.md`, `spec.md` (US1–US11), `research.md` (D1–D10), `data-model.md`,
`contracts/ffi.md` (C1–C6), `quickstart.md`

**Tests**: REQUIRED and **TEST-FIRST** for this slice (Constitution Principle V, FR-034/036). The **two** golden
fixtures, the failing Rust parity `Case` rows (+ the per-fixture balance-chain RECONCILED test + the
`federal_bank_claims` accept/reject split), and the failing Swift "core ↔ Swift Federal bank parse + balance chain"
test are all authored **RED, before** the engine that greens them. The engine-side focused unit tests (classic
direction-from-delta-despite-Cr + S-serial-out-of-desc + GRAND-TOTAL-not-a-transaction, Fi two-column whole-number
amounts, claims savings-vs-Scapia-CC) land **with** the GREEN engine (in `federal_bank.rs`'s `#[cfg(test)]` module,
mirroring `hdfc_bank.rs::tests`).

**Port source of truth** (faithful, byte-for-byte with the two golden vectors — the design is **LOCKED** in
`plan.md`/`data-model.md`/`contracts/`; do **not** re-derive it, just sequence it): the web engine's
`federal_bank.py` (`BalanceLedgerStatementReader`), whose captured JSON ground truth (`classic_savings`,
`fi_neobank`, both RECONCILED) is the persisted ground truth. Every value (rows, ledger metadata, printed
`100000.00`/closing, period, serials, last-4, the stitched narrations, RECONCILED chain) is pinned in
`data-model.md §3` + `research.md D8`. **No live run needed** (`research.md` §Open questions: "None").

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: `US1`=on-device parse (MVP) · `US2`=two templates / first-match-wins · `US3`=delta direction /
  Cr-Dr consumed-but-ignored / amount-as-check (+ Fi two-column) · `US4`=S-serial captured, kept OUT of the
  description · `US5`=opening balance per template / opening-anchored row-1 · `US6`=narration stitching (incl. the
  folded continuation + `GRAND TOTAL`) / non-transaction lines · `US7`=ledger metadata (period / bank-aware account
  last-4) · `US8`=savings-vs-Scapia-CC claim gate (shared `FEDERAL` code) · `US9`=config-on-base, ZERO new shared
  code · `US10`=golden parity (2 vectors, both RECONCILED) · `US11`=privacy-egress + Swift bridge. Setup/Polish/Ship
  carry no label.
- Exact file paths are included in every task.

> **Note (this slice commits nothing during generation).** `/speckit.tasks` only writes this file. The **two**
> commits + **PR #10** + `--rebase --delete-branch` merge are encoded as the final **Phase 16: Ship** and are
> executed by the implementer **only after** every gate is green (requester step 7).

## ♻️ REUSE — do NOT re-create (this slice adds 1 config + 2 FFI exports + 2 fixtures, and NOTHING shared)

This is the **third bank config** on the balance-ledger base (007) and the **leanest ledger drop-in to date** — even
leaner than HDFC (008), which had to factor out `account_tail_last4`. This slice adds **ZERO new dependency**
(runtime *or* dev), **zero new records/enums**, **zero new FFI types**, **zero new shared helpers**, and **zero base
changes**. Do **not** rebuild, refactor, or touch any of these — the base, the chain check, the shared helper, the
harness, and the privacy gate are **reused UNCHANGED**:

- `statement/ledger_reader.rs` — `trait LedgerReaderConfig` (`:51`: `fn bank_code` `:52`, `fn claim_all` `:56`, `fn
  anchor_res() -> Vec<&'static Regex>` `:60` **first-match-wins ordered list**, `fn claim_any` `:63`, `fn
  opening_balance_re` `:66`/`fn closing_balance_re` `:69` `-> Option<&'static Regex>`, `fn column_split_x() ->
  Option<f64>` `:74`, `fn provisional_direction` `:79`, `fn enrich(&self, &mut ParsedStatement, &str)` `:83`,
  defaulted `fn account_tail -> None` `:86`), `claims_ledger` (`:93`), `read_ledger_lines` (`:126`), the serial
  split + two-column `anchor_amount`/`loose_amount` (`:221`/`:238`/`:262`), `stitch_narration` (`:271`),
  `row1_direction`/`direction_from_x_position` (`:310`/`:342`). **No base change** — Federal is a config that returns
  **2** anchors (HDFC already proved >1).
- `statement/balance_chain.rs` — `pub fn check(statement: &ParsedStatement) -> ChainResult` (`:74`); `enum
  ChainStatus { Reconciled, NeedsReview }` (`:23`); `struct ChainResult { status, checked_rows, suspect_count,
  suspects, row1_direction_fallback, derived_opening_balance, derived_closing_balance, reason }` (`:41`, incl.
  `row1_direction_fallback` `:49`). Reused **unchanged** (the ₹1.00 tolerance lives here only).
- `statement/common.rs` — `account_tail_last4(text, primary)` (**already exists**, `:177`; primary group 1 →
  trailing 4, else the longest `\d{9,}` run `:51`/`:183` → trailing 4), `parse_amount` (`:58`), `parse_date`
  (`:66`). **All three Federal date formats are already present and correctly ordered**: `%d/%m/%y` (`:24`) **before**
  `%d/%m/%Y` (`:25`), `%Y-%m-%d` (`:26`), `%d-%b-%Y` (`:28`, matches uppercase `APR` case-insensitively — research
  **D10**). **No `common.rs` change at all** (unlike 008's `account_tail_last4` addition + the OD-1 reorder).
- `statement/base.rs` — records reused **unchanged**: `ParsedTransaction { value_date, amount, direction, currency,
  description_raw, bank_code, ledger: Option<LedgerMetadata> }`; `ParsedStatement { bank_code, lines, errored_lines,
  period_start, period_end, card_last4, printed_opening_balance, printed_closing_balance, confidence }`;
  `LedgerMetadata { balance, balance_delta, amount_matches_delta, is_suspect, direction_source, serial }`;
  `DirectionSource` (`OpeningBalance`/`BalanceDelta`); `Word { text, x0, x1 }`.
- `statement/federal.rs` — the **landed Scapia CC reader** (`FederalReader: LineReaderConfig`, `BANK_CODE
  "FEDERAL"` `:21`, `CLAIM_MARKERS = ["Scapia", "Federal Bank"]` `:38`). **UNCHANGED** — it coexists with the new
  bank reader under the shared `FEDERAL` code (research **D5**); do **not** modify it.
- `ffi.rs` — the `Decimal`/`NaiveDate` custom-type bridges reused **unchanged** (**no `uniffi.toml` change**);
  `read_hdfc_bank_statement` (`:160`), `hdfc_bank_claims` (`:171`), and **`check_balance_chain(statement:
  ParsedStatement) -> ChainResult`** (`:151`) are the exact templates.
- `tests/parity.rs` — the golden-fixture harness with the `#[serde(default)]` optional-ledger schema
  (`Fixture`/`Expected`/`ExpectedRow`/`ExpectedLedger` `:22`/`:29`/`:46`/`:58`; `Case` `:69`; `CASES` `:75`;
  `parse_hdfc_bank` `:132`; `load_fixture` `:136`; `hdfc_bank_statements_balance_chain_reconciles` `:332`;
  `federal_claims_accepts_own_document_and_rejects_others` `:303`). **NO schema change** — the **9** existing
  fixtures/cases need **NO migration**.
- The **privacy-egress gate** (`make core-privacy-audit`, `Makefile:22`) and CI — inherited **unchanged** (**no new
  dependency** → byte-identical shipped `cargo tree` graph).
- `fixtures/federal/credit_card/basic.json` — the **landed Scapia CC fixture** (`full_text` begins `Scapia by
  Federal Bank\nXXXXXXXXXXXX4836 …`; has `Federal Bank` but **NOT** `Statement of Account`). **DO NOT TOUCH IT** —
  it is the negative case the new bank reader must reject and the CC reader must keep claiming.

**The only NEW code**: `statement/federal_bank.rs` (the Federal config + its unit tests) + `pub mod federal_bank;`
in `mod.rs`; **2** `#[uniffi::export]` fns (`read_federal_bank_statement` / `federal_bank_claims`) + `lib.rs`
re-exports; **2** golden fixtures under `fixtures/federal/bank_account/`; **2** parity `Case` rows + **1** per-fixture
chain test + **1** claim-split test; **1** Swift test. **No new dependency; no new FFI type; no shared/base change;
`check_balance_chain` reused.**

## ⚠️ Grounding & local gotchas (apply throughout — the design is LOCKED; use the REAL landed symbols)

- **Use the ACTUAL landed symbols** (mirror the HDFC 008 surface): the per-row type is **`ParsedTransaction`**
  (field **`value_date`**, not `date`), reached via **`ParsedStatement.lines`**; the chain fn is
  **`check_balance_chain(statement: ParsedStatement) -> ChainResult`** (takes the whole statement **by value**) and
  you assert **`result.status == ChainStatus::Reconciled`**. The fixture **JSON** key **is** `expected.rows[]` (the
  harness maps `ExpectedRow` → `statement.lines[i]`).
- **Shared `FEDERAL` bank code — TWO readers coexist, told apart by their claim gates** (research **D5**, spec US8):
  the landed **Scapia CC** reader (`federal.rs`, `read_federal_statement`/`federal_claims`, requires `Scapia`) and
  the **new bank** reader (`federal_bank.rs`, `read_federal_bank_statement`/`federal_bank_claims`, requires
  `Federal Bank` **and** `Statement of Account`). A Scapia CC statement lacks `Statement of Account` ⇒ the bank
  reader rejects it; the CC reader still claims it. Distinct module/struct/trait/FFI-name — **0 misroutes** (SC-008).
- **Trailing `Cr`/`Dr` is CONSUMED-BUT-IGNORED** (research **D3**, the defining Federal invariant, FR-007/008,
  SC-004): the anchors match `\s+(?:Cr|Dr)\s*$` as a **non-capturing, unnamed** group; `find_anchors` reads only the
  **named** groups (`date`/`desc`/`serial`/`amount`|`withdrawal`+`deposit`/`balance`). Direction comes **only** from
  the balance delta (fall ⇒ `Debit`, rise ⇒ `Credit`); row 1 is anchored on the printed opening balance
  (`OpeningBalance`). In **both** fixtures **every** printed marker is `Cr`, yet the classic rows are Debit/Credit/Debit
  and the Fi rows are Debit/Credit — **never read the marker**.
- **Whole-number Fi amounts reconcile** (research **D4**): Fi withdrawal/deposit tokens are `[\d,]+(?:\.\d{2})?`;
  the base picks the **non-zero** column and `loose_amount` parses via `Decimal::from_str_exact`, preserving scale 0
  for `5000`. rust_decimal compares by value across scales (`5000 == 5000.00`), so both Fi rows reconcile
  (`amount_matches_delta = true`, `is_suspect = false`). Store the Fi amounts **exactly** as `"5000"`/`"50000"` (no
  `.00`) — `to_string()` round-trips the printed form. Classic amounts keep `.00` (`"5000.00"` etc.).
- **`make core-xcframework` MUST run before `tuist generate`** (`ios-gen: core-xcframework`, `Makefile:32`) — the
  generated Swift + `KanameCoreFFI.xcframework` are git-ignored **rebuilt** artifacts (`quickstart.md` §Verify iOS).
- **Local Xcode needs an explicit "iPhone 16" simulator** for `make ios-test`
  (`xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'`, `Makefile:37`); CI pins
  **`macos-15`** for the iOS job.
- **Money is `Decimal`, never `f64`** — amounts, balances, deltas all `Decimal`; Indian grouping (`1,45,000.00`) is
  stripped and scale preserved. The **only** `f64` on this surface is `Word.x0/x1` — **layout points, not money** —
  and Federal sets **NO `column_split_x`**, so no geometry is exercised (empty `Vec<Word>`). Fixture money is stored
  as **JSON strings**, re-parsed via `Decimal::from_str` (never float).
- **`GRAND TOTAL` is NOT a transaction** (research **D8**): `GRAND TOTAL 50,000.00 50,000.00` has two money tokens
  but **no** leading date and **no** trailing `Cr`/`Dr`, so it matches neither anchor. It is folded into classic row
  3's narration (byte-for-byte), never emitted as a row. Column headers and the `Opening Balance` line likewise
  yield no rows.
- **Narration is intentionally "dirty"** — the base `stitch_narration` folds a row's continuation line (printed
  *above the next anchor*) into that **next** row, and the trailing `GRAND TOTAL` into the **last** row. Reproduce
  **byte-for-byte** (research **D8**); do **not** trim/collapse/reorder — it would break parity.
- **`\EXAM` backslash escaping**: `full_text`/`lines`/`description_raw` contain the literal `\EXAM` token; in **JSON**
  it must be `\\EXAM`, and in Rust/Swift string literals likewise escaped. The stitched `description_raw` is
  byte-for-byte (no normalization).
- **`card_last4`** is `"1234"` (classic, full `…99990100001234`) / `"4222"` (Fi, masked `XXXXX4222`) via the shared
  **`account_tail_last4`** with Federal's own primary regex `(?i)Account\s+Number\s*:?\s*X*([0-9]{4,})` → last-4;
  fallback longest `\d{9,}` run → last-4. Only the trailing four is ever surfaced (FR-021, privacy).
- **Two-place amount-vs-delta**: the **reader** records **exact** `amount == |delta|` (`amount_matches_delta`); the
  **₹1.00 tolerance** lives **ONLY** in `balance_chain::check`. Both Federal fixtures reconcile (0 suspects).
- **Encoding**: both fixtures are plain **ASCII/UTF-8** (no rupee/middot glyphs); the only non-alphanumeric quirk is
  the literal `\` in `\EXAM`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the invariants and prerequisites so every later task has a place to land and the gates stay
green. No behaviour yet.

- [ ] T001 [P] Confirm the **no-new-dependency, no-shared-change** invariant: `core/crates/kaname-core/Cargo.toml`
  and `uniffi.toml` stay **UNCHANGED** (runtime `regex`/`rust_decimal`/`chrono`/`serde`/`uniffi` + dev-only
  `serde_json` already present); this slice adds **zero** deps, **zero** new FFI types, and **zero** shared/base
  edits (FR-037, SC-010/012). Create the fixtures home directory `fixtures/federal/bank_account/` **alongside** the
  existing `fixtures/federal/credit_card/` (which must stay untouched). Ref: `plan.md` §Summary/§Project Structure,
  `contracts/ffi.md §C6`.
- [ ] T002 [P] Verify local prerequisites & gotchas (no code): `cargo` on PATH (`source "$HOME/.cargo/env"`); iOS
  targets present (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`); an **"iPhone 16"**
  simulator exists in Xcode; recall `make core-xcframework` precedes `tuist generate` (`Makefile:32`); confirm
  `common.rs` **already** carries all four needed formats correctly ordered — `%d/%m/%y` (`:24`) before `%d/%m/%Y`
  (`:25`), `%Y-%m-%d` (`:26`), `%d-%b-%Y` (`:28`) — so **no `DATE_FORMATS` change is needed** (research **D10**), and
  `account_tail_last4` **already exists** at `common.rs:177` (no shared helper to add). Ref: `quickstart.md`
  §Prerequisites, `plan.md` §Complexity Tracking.

**Checkpoint**: Fixtures home exists, manifest + shared code unchanged, toolchain ready, the reused seams located.

---

## Phase 2: Test-First Foundation (⚠️ Principle V — author RED before ANY engine code)

**Purpose**: Pin the on-device engine to the proven web engine **before** writing it. These are the parity (US10),
chain (US10), claim-split (US8), and bridge (US1/US11) tests that **protect the whole slice**; they MUST be **RED**
at the end of this phase (`read_federal_bank_statement` / `federal_bank_claims` do not exist yet).

**⚠️ CRITICAL**: No engine code (Phase 3+) may be written until T003–T006 exist and are verified failing.

- [ ] T003 [P] [US10] Author the **ported** golden vector `fixtures/federal/bank_account/classic.json` — copy the
  **EXACT fixture bytes** from the captured `classic_savings` ground truth; the transaction/opening/continuation/
  `GRAND TOTAL` lines and every expected field are pinned in `data-model.md §3.1` + `research.md D8`. **13 `lines`**
  (non-empty stripped `splitlines()` of `full_text`; anchors at indices **6/8/10**, opening at index **5**):
  - idx 0–4: the header/meta lines carrying the claim markers `Federal Bank` **and** `Statement of Account`, the ISO
    period text `for the period 2026-04-01 to 2026-04-30`, the account `Account Number : …99990100001234`, and a
    column-header line (exact wording from the ground truth).
  - idx 5 (opening): `Opening Balance 1,00,000.00 Cr`
  - idx 6 (row 1 anchor): `08-APR-2026 08-APR-2026 TO ECM/600000000001 TFR S10000001 5,000.00 95,000.00 Cr`
  - idx 7 (row 1 continuation, folds into row 2): `/EXAMPLEMERCHANT \EXAM/07:17`
  - idx 8 (row 2 anchor): `11-APR-2026 11-APR-2026 UPI IN/600000000002 TFR S10000002 50,000.00 1,45,000.00 Cr`
  - idx 9 (row 3 continuation part A): `/payer@example/Payment/0000`
  - idx 10 (row 3 anchor): `13-APR-2026 13-APR-2026 POS/600000000003/EXAMPLESTORE TFR S10000003 45,000.00 1,00,000.00 Cr`
  - idx 11 (row 3 continuation part B): `\EXAM/12:34`
  - idx 12 (folds into row 3, NOT a transaction): `GRAND TOTAL 50,000.00 50,000.00`

  `full_text` = the `\n`-joined same lines. `expected.rows` = the **3** rows (all money as **JSON strings**; `\EXAM`
  escaped `\\EXAM`; direction from the delta despite every printed `Cr`):
  - row 0 `{"date":"2026-04-08","amount":"5000.00","direction":"Debit","currency":"INR","description_raw":"TO
    ECM/600000000001 TFR","ledger":{"balance":"95000.00","balance_delta":"-5000.00","amount_matches_delta":true,
    "is_suspect":false,"direction_source":"OpeningBalance","serial":"S10000001"}}`
  - row 1 `{"date":"2026-04-11","amount":"50000.00","direction":"Credit","currency":"INR","description_raw":"UPI
    IN/600000000002 TFR /EXAMPLEMERCHANT \\EXAM/07:17","ledger":{"balance":"145000.00","balance_delta":"50000.00",
    "amount_matches_delta":true,"is_suspect":false,"direction_source":"BalanceDelta","serial":"S10000002"}}`
  - row 2 `{"date":"2026-04-13","amount":"45000.00","direction":"Debit","currency":"INR","description_raw":"POS/
    600000000003/EXAMPLESTORE TFR /payer@example/Payment/0000 \\EXAM/12:34 GRAND TOTAL 50,000.00 50,000.00",
    "ledger":{"balance":"100000.00","balance_delta":"-45000.00","amount_matches_delta":true,"is_suspect":false,
    "direction_source":"BalanceDelta","serial":"S10000003"}}`

  Top level: `period_start "2026-04-01"`, `period_end "2026-04-30"`, `card_last4 "1234"`,
  `printed_opening_balance "100000.00"`, `printed_closing_balance "100000.00"` (last row balance; **no**
  `closing_balance_re`), `errored_lines []`. **100% synthetic/redacted** (FR-035). Ref: `data-model.md §3.1`,
  `research.md D8`.
- [ ] T004 [P] [US10] Author the **ported** golden vector `fixtures/federal/bank_account/fi.json` — copy the **EXACT
  fixture bytes** from the captured `fi_neobank` ground truth; fields pinned in `data-model.md §3.2` + `research.md
  D8`. **9 `lines`** (anchors at indices **5/7**, opening at index **4**):
  - idx 0–3: header/meta lines carrying `Federal Bank` **and** `Statement of account` (case-insensitive), the
    period text `for the period of 08/04/2026 to 07/05/2026` (the optional `of` + DD/MM/YYYY tolerated), and the
    masked account `…XXXXX4222`.
  - idx 4 (opening, with an intervening `OPNBAL` tran-id tolerated): `Opening Balance OPNBAL 1,00,000.00 CR`
  - idx 5 (row 1 anchor; withdrawal `5000`, deposit `0`): `08/04/2026 08/04/2026 TO ECM/600000000001/EXAMPLE TFR
    S10000001 5000 0 95,000.00 Cr`
  - idx 6 (row 1 continuation `MERCHANT \EXAM`, folds into row 2): `MERCHANT \EXAM`
  - idx 7 (row 2 anchor; withdrawal `0`, deposit `50000`): `20/04/2026 20/04/2026 UPI IN/600000000002/payer TFR
    S10000002 0 50000 1,45,000.00 Cr`
  - idx 8 (folds into row 2): `Payment f/0000`

  `expected.rows` = the **2** rows — **Fi amounts stored as whole numbers `"5000"`/`"50000"` (no `.00`)**, resolved
  from the **non-zero** withdrawal/deposit column (research **D4/D9**):
  - row 0 `{"date":"2026-04-08","amount":"5000","direction":"Debit","currency":"INR","description_raw":"TO
    ECM/600000000001/EXAMPLE TFR","ledger":{"balance":"95000.00","balance_delta":"-5000.00","amount_matches_delta":
    true,"is_suspect":false,"direction_source":"OpeningBalance","serial":"S10000001"}}`
  - row 1 `{"date":"2026-04-20","amount":"50000","direction":"Credit","currency":"INR","description_raw":"UPI
    IN/600000000002/payer TFR MERCHANT \\EXAM Payment f/0000","ledger":{"balance":"145000.00","balance_delta":
    "50000.00","amount_matches_delta":true,"is_suspect":false,"direction_source":"BalanceDelta","serial":
    "S10000002"}}`

  Top level: `period_start "2026-04-08"`, `period_end "2026-05-07"`, `card_last4 "4222"`,
  `printed_opening_balance "100000.00"`, `printed_closing_balance "145000.00"`, `errored_lines []`. **Synthetic/
  redacted.** Note the **whole-number** amounts still reconcile against the 2-dp delta. Ref: `data-model.md §3.2`,
  `research.md D4/D8/D9`.
- [ ] T005 [US10] Extend the parity harness `core/crates/kaname-core/tests/parity.rs` → **RED** (**NO schema
  change** — the `#[serde(default)]` optional-ledger schema already landed in 007; do **NOT** touch the 9 existing
  fixtures/cases):
  - Extend the `use kaname_core::{…}` block (`parity.rs:12`) to add `federal_bank_claims,
    read_federal_bank_statement`.
  - Add the wrapper (mirrors `parse_hdfc_bank`, `parity.rs:132`; empty geometry — Federal sets no `column_split_x`):
    `fn parse_federal_bank(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_federal_bank_statement(lines, full_text, Vec::new()) }`.
  - Add **two** `Case` rows to `CASES` (`parity.rs:75`, after the `hdfc/bank_account/detailed.json` case):
    `Case { label: "Federal bank classic", parse: parse_federal_bank, rel_path:
    "federal/bank_account/classic.json" }` and `Case { label: "Federal bank Fi", parse: parse_federal_bank,
    rel_path: "federal/bank_account/fi.json" }`. They flow through the existing
    `golden_fixtures_match_expected_output` (`:238`) and `parse_is_deterministic` (`:247`) unchanged.
  - Add **one per-fixture** chain test `federal_bank_statements_balance_chain_reconciles` (mirror
    `hdfc_bank_statements_balance_chain_reconciles`, `parity.rs:332`, but the row counts differ → iterate
    **`(rel_path, checked)` pairs**): `[("federal/bank_account/classic.json", 3u32),
    ("federal/bank_account/fi.json", 2u32)]` → each `load_fixture(…)` →
    `check_balance_chain(read_federal_bank_statement(fx.lines, fx.full_text, Vec::new()))` → assert
    `result.status == ChainStatus::Reconciled`, `result.suspect_count == 0`, `!result.row1_direction_fallback`,
    `result.checked_rows == checked` (SC-003).
  - Add `federal_bank_claims_accepts_own_document_and_rejects_others` (mirror
    `federal_claims_accepts_own_document_and_rejects_others`, `parity.rs:303`): `federal_bank_claims(classic.full_text)
    == true`, `federal_bank_claims(fi.full_text) == true`, `== false` for the **Scapia CC** fixture
    (`load_fixture("federal/credit_card/basic.json").full_text` — has `Federal Bank` but no `Statement of Account`),
    and `== false` for a foreign issuer (`"ICICI Bank Statement"`) (SC-008).
  - ⚠️ **Verify RED**: `make core-test` **fails to compile** (`read_federal_bank_statement`/`federal_bank_claims`
    absent). Ref: `contracts/ffi.md §C4`, `data-model.md §3`.
- [ ] T006 [P] [US1] Author the **RED** Swift bridge test `ios/Tests/FederalBankParseTests.swift` — "core ↔ Swift
  Federal bank parse + balance chain" (`import KanameCore`, Swift Testing), mirroring
  `ios/Tests/HDFCBankParseTests.swift`. Build each template's `lines`/`fullText` with `[...].joined(separator:
  "\n")`; exact amounts via `Decimal(string:locale: Locale(identifier: "en_US_POSIX"))`; call
  `readFederalBankStatement(lines:fullText:firstRowWords: [])` (empty geometry). Assert **both** templates:
  - **classic** (3 rows): delta-derived directions **`.debit`/`.credit`/`.debit`** even though **every** printed
    marker is `Cr`; `valueDate` `"2026-04-08"`/`"2026-04-11"`/`"2026-04-13"`; exact `Foundation.Decimal` amounts
    `"5000.00"`/`"50000.00"`/`"45000.00"`; the S-serials `"S10000001"`/`"S10000002"`/`"S10000003"` captured in
    `ledger?.serial` and **NOT** present in `descriptionRaw`; per-row `balance` `"95000.00"`/`"145000.00"`/
    `"100000.00"`, `directionSource` `.openingBalance` then `.balanceDelta`, `amountMatchesDelta`, `!isSuspect`;
    `printedOpeningBalance "100000.00"`, `printedClosingBalance "100000.00"`, `periodStart "2026-04-01"`, `periodEnd
    "2026-04-30"`, `cardLast4 "1234"`, `erroredLines.isEmpty`.
  - **Fi** (2 rows): directions **`.debit`/`.credit`**; `valueDate` `"2026-04-08"`/`"2026-04-20"`; **whole-number**
    amounts `"5000"`/`"50000"` (exact `Foundation.Decimal`); serials `"S10000001"`/`"S10000002"` in `ledger?.serial`,
    not in `descriptionRaw`; `printedOpeningBalance "100000.00"`, `printedClosingBalance "145000.00"`, `periodStart
    "2026-04-08"`, `periodEnd "2026-05-07"`, `cardLast4 "4222"`.
  - `checkBalanceChain(statement:).status == .reconciled` (`suspectCount == 0`, `!row1DirectionFallback`,
    `checkedRows == 3` classic / `2` Fi) for **both** fixtures.
  - `federalBankClaims(fullText:)` accepts **both** Federal savings statements and **rejects** a Scapia/Federal
    **credit-card** text (has `Federal Bank`, `Scapia`, but no `Statement of Account`).
  - Use `firstRowWords: []`; `try #require(statement.lines.first)`; amounts compared as exact `Foundation.Decimal`
    (never `Double`). **Comments on their OWN line — never trailing after code** (swift-format `[Spacing]` rejects
    trailing inline comments). ⚠️ **Verify RED**: won't build until the xcframework is regenerated with the exports
    in Phase 4. Ref: `contracts/ffi.md §C5`, `ios/Tests/HDFCBankParseTests.swift`.

**Checkpoint**: Both fixtures in place; Rust parity RED (2 `Case` rows + 1 per-fixture chain test + claim split
won't compile); Swift bridge test RED. Test-first satisfied — engine code may now begin.

---

## Phase 3: User Story 1 — Turn a Federal savings/current statement into transactions, on-device (Priority: P1) 🎯 MVP

**Goal**: Recognize a Federal **bank-account** statement (**either** template) and return one transaction per ledger
row (date, exact amount, **delta-derived** direction, INR, running balance, stitched description) — 100% on-device.
Building the engine here **also lands the behaviours** US2–US9 verify independently in Phases 5–12.

**Independent Test**: `read_federal_bank_statement(classic.lines, classic.full_text, vec![])` **and**
`…(fi.lines, fi.full_text, vec![])` each return the expected rows (3 / 2), and `federal_bank_claims` accepts both
Federal bank templates / rejects the Scapia CC statement — with no network in the parse path.

> Engine landing order (requester step 4): **federal_bank.rs (the Federal config) + mod.rs → ffi.rs exports + lib.rs
> re-exports → `make core-fmt` then GREEN core-test/core-lint**. The design is **LOCKED** in
> `data-model.md`/`contracts/` — port it, don't re-derive it. **No `common.rs`/base/`icici_bank.rs`/`federal.rs`
> change** (unlike 008).

- [ ] T007 [US1] **The Federal config — `core/crates/kaname-core/src/statement/federal_bank.rs` (NEW)** + wire
  `statement/mod.rs`. Port `federal_bank.py` to a **zero-sized** `pub struct FederalBankReader;` `impl
  LedgerReaderConfig`, mirroring `HdfcBankReader` (`hdfc_bank.rs`). `pub const BANK_CODE: &str = "FEDERAL";`. Each
  regex a `static` built once via `LazyLock<Regex>` (exact patterns from `data-model.md §2` / `research.md D1`):
  - `ANCHOR_CLASSIC_RE`
    `(?i)^(?P<date>\d{2}-[A-Za-z]{3}-\d{4})\s+\d{2}-[A-Za-z]{3}-\d{4}\s+(?P<desc>.*?)(?:\s+(?P<serial>S\d+))?\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s+(?:Cr|Dr)\s*$`
    (two `DD-MON-YYYY` dates; optional `S…` serial out of `desc`; single amount; trailing `(?:Cr|Dr)` matched
    **unnamed** ⇒ ignored)
  - `ANCHOR_FI_RE`
    `(?i)^(?P<date>\d{2}/\d{2}/\d{4})\s+\d{2}/\d{2}/\d{4}\s+(?P<desc>.*?)(?:\s+(?P<serial>S\d+))?\s+(?P<withdrawal>[\d,]+(?:\.\d{2})?)\s+(?P<deposit>[\d,]+(?:\.\d{2})?)\s+(?P<balance>[\d,]+\.\d{2})\s+(?:Cr|Dr)\s*$`
    (two `DD/MM/YYYY` dates; optional serial; **two-column** loose-integer withdrawal/deposit; trailing marker
    ignored)
  - `OPENING_RE` `(?i)Opening Balance\s+(?:[A-Z]+\s+)?([\d,]+\.\d{2})` (tolerates the intervening `OPNBAL`; group 1
    in both forms — `Opening Balance 1,00,000.00 Cr` and `Opening Balance OPNBAL 1,00,000.00 CR`)
  - `PERIOD_RE`
    `(?i)for the period(?:\s+of)?\s+(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})\s+to\s+(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})`
    (classic ISO **or** Fi `DD/MM/YYYY`; optional `of`)
  - `FEDERAL_ACCOUNT_RE` `(?i)Account\s+Number\s*:?\s*X*([0-9]{4,})` (optional masked `X*`; **4+** digits)
  - Trait methods: `fn bank_code()` → `BANK_CODE`; `fn claim_all()` → `&["Federal Bank", "Statement of Account"]`;
    **no** `claim_any` override (default `&[]`); **`fn anchor_res()` → `vec![&ANCHOR_CLASSIC_RE, &ANCHOR_FI_RE]`**
    (ordered, first-match-wins — classic `DD-MON-YYYY` and Fi `DD/MM/YYYY` are mutually exclusive, US2); `fn
    opening_balance_re()` → `Some(&OPENING_RE)`; **no** `closing_balance_re` override (default `None` — closing
    derived from the final row's balance); **no** `column_split_x` override (default `None` — no geometry); **no**
    `provisional_direction` override (default `Debit`, unused); `fn enrich(&self, statement, full_text)` → `PERIOD_RE`
    groups 1&2 → `period_start`/`period_end` via `parse_date`, then `statement.card_last4 =
    account_tail_last4(full_text, &FEDERAL_ACCOUNT_RE)` (call the shared helper directly; do **not** override the
    trait `account_tail`). `use crate::statement::common::{account_tail_last4, parse_date};`,
    `use crate::statement::ledger_reader::LedgerReaderConfig;`, `use crate::statement::base::ParsedStatement;`,
    `use regex::Regex;`, `use std::sync::LazyLock;`.
  - **Wire** `core/crates/kaname-core/src/statement/mod.rs`: add `pub mod federal_bank;` (keep alphabetical — after
    `pub mod federal;`, before `pub mod hdfc;`). No new re-export needed (`FederalBankReader` is referenced by
    `ffi.rs` via its path).
  - **Focused unit tests** (`#[cfg(test)]`, driving `read_ledger_lines(&FederalBankReader, …)` / `claims_ledger`,
    mirroring `hdfc_bank.rs::tests`; comments on their own line):
    (a) **classic** — direction is **delta-derived despite every printed `Cr`** (rows Debit/Credit/Debit for
    `100000→95000→145000→100000`), the `S…` serials are captured **out of** `description_raw`, and the trailing
    `GRAND TOTAL 50,000.00 50,000.00` line yields **no** transaction (3 rows, not 4) while folding into row 3's
    narration (US3/US4/US6); (b) **Fi** — the **non-zero** withdrawal/deposit column resolves as the amount and the
    **whole-number** `5000`/`50000` reconcile against the 2-dp delta (`amount_matches_delta == true`), opening read
    from the `OPNBAL`-interrupted line (US3/US4/US5); (c) `claims_ledger(&FederalBankReader, bank_text, "FEDERAL") ==
    true` for both templates and `== false` for a **Scapia CC** text (`Scapia by Federal Bank …`, no `Statement of
    Account`) and a wrong `bank_code` (US8). Ref: `data-model.md §2`, `research.md D2–D6/D8–D10`,
    `core/crates/kaname-core/src/statement/hdfc_bank.rs`.
- [ ] T008 [US1] **FFI exports + re-exports** — in `core/crates/kaname-core/src/ffi.rs`, mirroring
  `read_hdfc_bank_statement` (`ffi.rs:160`) / `hdfc_bank_claims` (`:171`): add
  `use crate::statement::federal_bank::FederalBankReader;` then
  `#[uniffi::export] pub fn read_federal_bank_statement(lines: Vec<String>, full_text: String, first_row_words:
  Vec<Word>) -> ParsedStatement { read_ledger_lines(&FederalBankReader, &lines, &full_text, &first_row_words) }` and
  `#[uniffi::export] pub fn federal_bank_claims(full_text: String) -> bool { claims_ledger(&FederalBankReader,
  &full_text, "FEDERAL") }`. **Reuse** the already-exported `check_balance_chain` (`ffi.rs:151`) — do **not** add a
  second copy. Re-export both new fns in `core/crates/kaname-core/src/lib.rs` by extending the `pub use ffi::{…}`
  block (`lib.rs:28`, add `federal_bank_claims, read_federal_bank_statement` — keep the list sorted). No
  `uniffi.toml` change; no new type crosses the FFI. Depends on T007. Ref: `contracts/ffi.md §C1`, `research.md D2`.
- [ ] T009 [US1] **Green the engine side**: run `make core-fmt` (rustfmt), then `make core-test` — the **two**
  Federal parity `Case` rows (T005) now **PASS** for the classic + Fi vectors (3 / 2 rows incl. ledger fields;
  classic `printed_opening 100000.00`/`closing 100000.00`, Fi `100000.00`/`145000.00`; classic `period
  2026-04-01→2026-04-30`, Fi `2026-04-08→2026-05-07`; `card_last4 "1234"`/`"4222"`; `errored_lines []`), the
  `federal_bank_statements_balance_chain_reconciles` test (RECONCILED, 0 suspects, no fallback, `checked_rows` 3/2),
  the `federal_bank_claims` split, and the `federal_bank.rs` unit tests — while **all 9 prior parity cases (6
  credit-card incl. Scapia + ICICI bank + 2 HDFC bank) stay green** (fixtures untouched) — then `make core-lint`
  (fmt `--check` + clippy `-D warnings`). Verify **RED→GREEN** for the Rust harness. Depends on T008. Ref:
  `quickstart.md §Verify — core`.

**Checkpoint**: The engine parses **both** golden Federal statements, the balance chain reconciles each, and the
Rust parity + chain + claim-split + determinism + unit tests are green (Swift bridge greened in Phase 4). US1 is
functional on the Rust side; no base/shared/CC-reader file changed.

---

## Phase 4: UniFFI bridge — regenerate the xcframework + green the Swift test (US1 / US11)

**Goal**: Surface the two new functions to Swift (reusing the existing types) and green the "core ↔ Swift Federal
bank parse + balance chain" test for **both** templates.

- [ ] T010 [US1] Run `make core-xcframework` to rebuild `ios/Frameworks/KanameCoreFFI.xcframework` +
  `ios/Generated/kaname_core.swift` (git-ignored artifacts) now exposing `readFederalBankStatement` /
  `federalBankClaims` (reusing the existing `Word`, `LedgerMetadata`, `DirectionSource`, `ChainResult`,
  `ChainStatus`, `ParsedStatement` Swift types — **no new binding shape**, `uniffi.toml` untouched). ⚠️ **MUST run
  before `tuist generate`** (`Makefile:32`, `quickstart.md §Verify — iOS`). Depends on T008. Ref: `contracts/ffi.md
  §C1`.
- [ ] T011 [US1] Run `make ios-test` (`ios-gen` → `core-xcframework` → `tuist generate` → `xcodebuild …
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test`) to **green**
  `ios/Tests/FederalBankParseTests.swift` (T006) — both templates with exact `Foundation.Decimal` amounts (classic
  `.00`, Fi whole-number), delta-derived `.debit`/`.credit` despite the printed `Cr`, per-row `ledger` (balance /
  `directionSource` / S-serial not in `descriptionRaw`), printed opening/closing, period, `cardLast4 "1234"`/`"4222"`,
  `checkBalanceChain(...).status == .reconciled` (suspectCount 0, no row-1 fallback, checkedRows 3/2), and
  `federalBankClaims` accept-both-templates / reject-Scapia-CC. ⚠️ **Local Xcode: create the "iPhone 16" simulator
  first.** Verify **RED→GREEN** for the Swift bridge test. Depends on T010. Ref: `quickstart.md §Verify — iOS`.

**Checkpoint**: US1 MVP delivered end-to-end (Rust engine + balance chain + Swift bridge). A person's Federal
savings/current statement text — **either** template — → transactions + a RECONCILED verdict, on-device.

---

## Phase 5: User Story 2 — One reader, two templates, auto-selected by first-match-wins anchors (Priority: P2)

**Goal**: The single Federal reader handles **both** templates behind one `anchor_res()` ordered list; the caller
never selects a template, and each row is read by exactly one anchor (classic `DD-MON-YYYY` vs Fi `DD/MM/YYYY` are
mutually exclusive). *(Impl landed in T007's `anchor_res() -> vec![&ANCHOR_CLASSIC_RE, &ANCHOR_FI_RE]` on the reused
base; adds no base capability — FR-003/004/006.)*

**Independent Test**: Parsing the classic and the Fi fixtures through the **same** `FederalBankReader` yields the
correct rows without a template hint; a classic row never matches `ANCHOR_FI_RE` and vice-versa.

- Delivered by **T007** (two ordered anchors) · Verified by **T005** (both `Case` rows through one
  `parse_federal_bank`), **T007** unit tests (classic vs Fi parse), **T003/T004** (mutually-exclusive fixture rows),
  **T011** (both templates over the bridge).

**Checkpoint**: One reader, two templates, first-match-wins — no caller-side template selection, no cross-matching.

---

## Phase 6: User Story 3 — Direction from the running-balance delta; the trailing Cr/Dr is consumed but ignored; the amount is an independent check (Priority: P3)

**Goal**: Each row's direction is decided **solely** by the running-balance movement (fall ⇒ debit, rise ⇒ credit)
in **both** templates; the trailing `Cr`/`Dr` is **matched and discarded** (never read); the printed amount is an
**independent** check (`amount == |delta|`), taken from the **non-zero** Withdrawal/Deposit column in Fi. *(Impl
landed in the reused `read_ledger_lines` delta logic + `anchor_amount`/`loose_amount`; T007's anchors match the
marker as an unnamed group.)*

**Independent Test**: Classic rows classify Debit/Credit/Debit and Fi rows Debit/Credit from the delta though every
printed marker is `Cr`; the Fi amount is the non-zero column and the whole-number amounts reconcile; flipping the
balance movement flips direction regardless of the printed amount/column/marker.

- Delivered by the reused base (delta direction + two-column `anchor_amount` + the unnamed `(?:Cr|Dr)`) · Verified by
  **T007** unit tests (a: classic Debit/Credit/Debit despite `Cr`; b: Fi non-zero column + whole-number reconcile),
  **T003/T004** (delta-derived directions + `amount_matches_delta true`), **T005**/**T011** (both templates), and the
  reused `ledger_reader.rs` delta-flip unit test from slice 007.

**Checkpoint**: Direction is provably delta-sourced in both templates; the marker is consumed-but-ignored; the
amount (single or non-zero column) is a pure cross-check.

---

## Phase 7: User Story 4 — The S-prefixed Tran ID is captured as the per-row serial and kept OUT of the description (Priority: P4)

**Goal**: Each row's optional `S…` Tran ID is captured as the `serial` (audit trail) and **never** appears in
`description_raw` (so it cannot defeat later dedup); captured in **both** templates. *(Impl landed in T007's
`(?:\s+(?P<serial>S\d+))?` group + the reused base's separate `serial` capture; the non-greedy `desc` yields the
shortest match that keeps the serial out of the narration — research **D9**.)*

**Independent Test**: Classic serials `S10000001`/`S10000002`/`S10000003`, Fi serials `S10000001`/`S10000002`; no
row's stitched description contains its `S…` token.

- Delivered by **T007** (`serial` anchor group) + reused base serial handling · Verified by **T007** unit test (a)
  (serial captured out of `desc`), **T003/T004** (`serial` fields set; `description_raw` free of `S…`),
  **T005**/**T011** (serials in `ledger.serial`, not `descriptionRaw`).

**Checkpoint**: The per-row serial is preserved for audit and kept out of the narration — dedup-safe.

---

## Phase 8: User Story 5 — Opening balance per template, and an opening-anchored row 1 (Priority: P5)

**Goal**: One `OPENING_RE` reads `Opening Balance 1,00,000.00 Cr` (classic) **and** `Opening Balance OPNBAL
1,00,000.00 CR` (Fi, intervening `OPNBAL` tolerated) → `100000.00`; row 1 is opening-anchored (`direction_source =
OpeningBalance`, delta `95000 − 100000 = −5000 ⇒ Debit`, no geometry) in both fixtures; later rows `BalanceDelta`.
*(Impl landed in T007's `OPENING_RE` + the reused row-1 bootstrap; Federal sets no `column_split_x`, so no
x-position path.)*

**Independent Test**: Both fixtures read opening `100000.00`; each fixture's row 1 is `OpeningBalance`, every later
row `BalanceDelta`; no row-1 direction fallback in the chain.

- Delivered by **T007** (`OPENING_RE` with the optional `(?:[A-Z]+\s+)?`) + reused row-1 bootstrap · Verified by
  **T007** unit test (b) (Fi opening from the `OPNBAL` line), **T003/T004** (`direction_source`
  OpeningBalance/BalanceDelta; `printed_opening_balance 100000.00`), **T005** (chain `!row1_direction_fallback`),
  **T011**.

**Checkpoint**: Opening balance is read per template; row 1 is opening-anchored (no untrusted bootstrap).

---

## Phase 9: User Story 6 — Faithful narration stitching, and the non-transaction lines (headers, Opening Balance, GRAND TOTAL) (Priority: P6)

**Goal**: Each row's `description_raw` reproduces the web engine's stitched narration **byte-for-byte** — classic
row 2 folds row 1's continuation (`/EXAMPLEMERCHANT \EXAM/07:17`), classic row 3 folds its own continuation **plus**
the trailing `GRAND TOTAL 50,000.00 50,000.00`, and Fi row 2 folds `MERCHANT \EXAM` + `Payment f/0000` — with **no**
normalization/trim/reorder. The `GRAND TOTAL`, column-header, and `Opening Balance` lines yield **no** transactions
(classic 3 rows, Fi 2). *(Impl landed in the reused `stitch_narration`; the exact strings are pinned by the
fixtures.)*

**Independent Test**: Both fixtures' row descriptions match the ground-truth strings exactly (incl. the folded
continuations + `GRAND TOTAL`); the non-transaction lines produce no rows.

- Delivered by the reused `stitch_narration` (`ledger_reader.rs:271`) · Verified by **T003/T004** (the exact
  `description_raw` bytes incl. `\\EXAM` + `GRAND TOTAL`), **T007** unit test (a) (`GRAND TOTAL` not a transaction),
  **T005** (parity asserts them), **T011** (Swift `descriptionRaw`). ⚠️ Do **not** "clean up" the stitched text — it
  would break parity (research **D8**).

**Checkpoint**: Narration parity is byte-exact, quirks (folded continuation + `GRAND TOTAL`) included; row counts
correct.

---

## Phase 10: User Story 7 — Ledger metadata: the billing period and a bank-aware account last-4 (Priority: P7)

**Goal**: Both statements record their period (classic ISO `2026-04-01 → 2026-04-30`; Fi `DD/MM/YYYY` `2026-04-08 →
2026-05-07`, the optional `of` tolerated) and account **last-4** (`1234` from the full `…99990100001234`; `4222`
from the masked `XXXXX4222`) via the shared `account_tail_last4` with Federal's primary regex else the longest
`\d{9,}` run — retaining only the trailing four. *(Impl landed in T007's `PERIOD_RE`/`FEDERAL_ACCOUNT_RE`/`enrich` +
the reused `account_tail_last4`.)*

**Independent Test**: classic period + `card_last4 "1234"`; Fi period + `card_last4 "4222"`; only the trailing four
retained; a missing field is left unset, transactions still returned.

- Delivered by **T007** (`PERIOD_RE` two date shapes + `FEDERAL_ACCOUNT_RE`) + reused `account_tail_last4` · Verified
  by **T003/T004** (period + last-4), **T005**/**T011**, and the reused `account_tail_last4` behaviour (from 008).

**Checkpoint**: The ledger is auditable and attributable — period (two date formats) + the correct bank-account
last-4 (never the full number).

---

## Phase 11: User Story 8 — The document gate distinguishes a Federal bank statement from a Federal (Scapia) credit-card statement — the shared issuer code (Priority: P8)

**Goal**: `federal_bank_claims` requires the `FEDERAL` bank code + **all** `claim_all` (`["Federal Bank", "Statement
of Account"]`) — accepting both Federal bank templates and **rejecting** the Scapia/Federal credit-card statement
(which the landed `statement/federal.rs` reader still claims via its `Scapia` marker). *(Impl landed in T007's
`claim_all` + the reused `claims_ledger`; the two readers coexist under `FEDERAL` — research **D5**.)*

**Independent Test**: The bank reader claims classic + Fi, rejects the Scapia CC statement and other issuers; the
existing `federal_claims` still claims the Scapia CC statement — 0 misroutes.

- Delivered by **T007** (`claim_all`) + reused `claims_ledger` · Verified by **T007** unit test (c), **T005**
  (`federal_bank_claims_accepts_own_document_and_rejects_others`), **T011** (Swift claims), and the untouched
  `federal_claims_accepts_own_document_and_rejects_others` (`parity.rs:303`) confirming the Scapia CC reader still
  claims its statement.

**Checkpoint**: The savings-vs-Scapia-CC gate is precise under the shared `FEDERAL` code — 0 misroutes; each
statement reaches the correct reader.

---

## Phase 12: User Story 9 — A config-on-an-existing-base slice: reuse the base, the balance chain, and the shared account-tail helper — all unchanged, with ZERO new shared code (Priority: P9)

**Goal**: The Federal parse is delivered **purely** by a per-issuer configuration plugged into the **unchanged**
base, balance-chain check, **and** the shared `account_tail_last4` helper — this slice adds **NO** new shared code
at all (leaner than HDFC, which added the helper). *(Impl landed entirely in T007 + T008; `common.rs`,
`ledger_reader.rs`, `balance_chain.rs`, `base.rs`, `federal.rs`, and the harness schema are byte-unchanged.)*

**Independent Test**: No base internals (anchor recognition, direction-from-delta, amount-as-check, stitching, row-1
bootstrap, errored-vs-suspect, the balance chain, `account_tail_last4`, the parity harness, the privacy gate) were
modified; Federal supplies only its config + fixtures; **no** new shared function.

- Delivered by **T007** (the config) + **T008** (2 FFI exports reusing `check_balance_chain`) · Verified by **T009**
  (all 9 prior cases green — no fixture migration) + the constitution review **T016** (the diff is exactly
  `federal_bank.rs` + `mod.rs` line + 2 `ffi.rs` exports + `lib.rs` re-exports + 2 fixtures + harness rows + 1 Swift
  test — **nothing** shared/base/CC).

**Checkpoint**: Federal is a genuine config-on-base; the base/chain/helper/harness/gate are untouched; the shared
footprint is **zero**.

---

## Phase 13: User Story 10 — Proven byte-for-byte against two golden fixtures, both RECONCILED (Priority: P10) 🛡️ whole-slice guard

**Goal**: The parity harness is the **regression-proof** guarantee pinning **both** Federal templates to the web
engine — reusing the 007 schema (optional ledger fields; dedicated chain tests), with the 9 prior vectors
reproducing **unchanged**. *(Fixtures T003/T004; harness/chain/claim tests T005; greened T009.)*

**Independent Test**: The harness over both ported Federal vectors matches expected output exactly (rows + ledger
metadata + printed opening/closing + period + last-4 + RECONCILED chain), re-running is stable; all 9 prior issuers
still reproduce their vectors.

- [ ] T012 [US10] Finalize `core/crates/kaname-core/tests/parity.rs` as the **whole-slice guard**: confirm **both**
  Federal `Case` rows call `parse_federal_bank` (empty geometry) and match field-by-field — `value_date`, exact
  `Decimal` amounts (classic scale-2, **Fi whole-number `5000`/`50000`** — Indian grouping stripped, printed scale
  preserved), **delta-derived directions despite the printed `Cr`**, `INR`, `description_raw` **byte-for-byte**
  (incl. the folded continuations + `GRAND TOTAL`, `\\EXAM` intact), per-row
  `balance`/`balance_delta`/`direction_source`/`serial`/`amount_matches_delta`/`is_suspect`, and classic
  `printed_opening 100000.00`/`closing 100000.00`/`period 2026-04-01→2026-04-30`/`card_last4 "1234"` + Fi
  `100000.00`/`145000.00`/`2026-04-08→2026-05-07`/`"4222"` + `errored_lines []` (SC-001/002/009); the
  `federal_bank_statements_balance_chain_reconciles` test asserts **RECONCILED**, 0 suspects, no row-1 fallback,
  `checked_rows` 3 (classic) / 2 (Fi) (SC-003); the determinism **re-run** (`parse_is_deterministic`) covers both
  Federal vectors (SC-014); the fixtures are **100% synthetic** (FR-035); and confirm the schema stayed
  **back-compatible** — the 9 prior fixtures + their assertions are **byte-identical** (no migration; the Scapia CC
  fixture untouched). Ref: `contracts/ffi.md §C3/§C4`, `research.md D8`.

**Checkpoint**: Parity is an enforced guarantee for both Federal templates; one harness serves all readers with no
prior-fixture migration.

---

## Phase 14: User Story 11 — Privacy gate & the Swift bridge: zero network, no new dependency, reachable from Swift (Priority: P11) 🛡️ inherited guard

**Goal**: Prove the Federal bank-account parse **and** chain path is egress-free — **structurally** (no networking
crate can even link) and **behaviorally** (determinism) — via the **inherited** gate with **zero** new config, and
confirm reachability over UniFFI (greened in T011). *(No new script/CI: this slice adds no dependency, so the audit
is byte-identical.)*

**Independent Test**: `make core-privacy-audit` passes only when zero networking crates are in the shipped graph;
the reader is callable over UniFFI from Swift; no new runtime (or networking) dependency was added; money stays an
exact `Decimal`.

- [ ] T013 [US11] Confirm the inherited privacy-egress gate stays **GREEN with ZERO changes**: run `make
  core-privacy-audit` → passes (no networking crate in `kaname-core` deps) — this slice adds **no dependency**
  (runtime *or* dev), so `cargo tree -p kaname-core -e normal` is byte-identical (`Cargo.toml`/`uniffi.toml`
  unchanged — FR-031/032/033, SC-010/012); the determinism/purity assertion over both Federal vectors lives in
  `tests/parity.rs` (T005/T012, FR-029, SC-014); the whole reader (`read_federal_bank_statement`,
  `federal_bank_claims`, reused `check_balance_chain`) is reachable from Swift over UniFFI (proved GREEN in T011,
  SC-013, FR-030); confirm **no** telemetry/analytics/crash-reporter enters the parse/chain path and **no** network
  entitlement/ATS is added app-side, and money is `Decimal` (never `f64`) (FR-011, SC-011). Ref: `quickstart.md
  §Verify — core`, `research.md D1`, spec US11.

**Checkpoint**: Privacy-egress remains a first-class, structurally- and behaviorally-enforced gate covering the
Federal bank-account parse **and** the reused balance-chain check; the reader is reachable from Swift.

---

## Phase 15: Polish & Cross-Cutting — full iOS Local Verification Gate green

**Purpose**: Prove the whole slice is merge-ready (SC-015) and review the constitution guarantees.

- [ ] T014 [P] Light docs alignment (no behaviour change): note the **third bank config** (Federal savings/current,
  two templates classic + Fi) on the balance-ledger base where the engine/build is described (`README.md` and/or
  `specs/009-federal-bank-ledger-reader/quickstart.md`); ensure `fixtures/README.md` reflects the two Federal bank
  vectors under `fixtures/federal/bank_account/`. Refresh the `statement/mod.rs` doc comment only if it enumerates
  readers. Optionally run `.specify/scripts/bash/update-agent-context.sh copilot` and, if it reintroduces the "iOS 18
  targe" typo in `.github/copilot-instructions.md`, fix to "iOS 18 target" and leave it **unstaged** (author commits)
  — see `quickstart.md §Agent context + typo check`. No stale wording.
- [ ] T015 **Run the full iOS Local Verification Gate green**, in order: `make core-lint && make core-test && make
  core-privacy-audit && make lint && make ios-gen && make ios-test`. ⚠️ `make core-xcframework` is rebuilt before
  `tuist generate` (via `ios-gen`, `Makefile:32`); local Xcode requires the **"iPhone 16"** simulator; CI runs the
  same (core on ubuntu, iOS on **macos-15**). This is the SC-015 merge gate. Depends on T009/T011/T012/T013/T014.
  Ref: `quickstart.md §Verify — core/§Verify — iOS`.
- [ ] T016 [P] Final constitution review (no code change): **NO new dependency** (runtime *or* dev) —
  `Cargo.toml`/`uniffi.toml` unchanged; the diff is exactly `statement/federal_bank.rs` (+ its unit tests) +
  `pub mod federal_bank;` in `mod.rs` + 2 `ffi.rs` exports + `lib.rs` re-exports + 2 fixtures under
  `fixtures/federal/bank_account/` + 2 `parity.rs` `Case` rows + 1 chain test + 1 claim-split test + 1 Swift test;
  **no new record/enum/FFI type** (`check_balance_chain` reused); **no shared/base change** (`common.rs`,
  `ledger_reader.rs`, `balance_chain.rs`, `base.rs`, `federal.rs`, `icici_bank.rs`, `hdfc_bank.rs`, the harness
  schema, and `fixtures/federal/credit_card/basic.json` **all byte-unchanged**); **money is `Decimal`, never `f64`**
  (no geometry — Federal sets no `column_split_x`); direction **delta-derived** with an auditable `direction_source`,
  the trailing `Cr`/`Dr` **consumed-but-ignored**; **exact** `amount == |delta|` in the reader vs the **₹1.00**
  tolerance **only** in `balance_chain`; `card_last4 "1234"`/`"4222"` via `account_tail_last4` (never the full
  number); no secrets / network entitlements / copyleft (GPL/AGPL/LGPL) deps (FR-037); all fixture/test data
  synthetic (FR-035); the 9 prior fixtures + the harness schema stay back-compatible (no migration). Confirm
  against `git diff` before handoff. Ref: `plan.md §Constitution Check/§Complexity Tracking`.

**Checkpoint**: Whole slice is green end-to-end and constitution-clean — ready to ship.

---

## Phase 16: Ship — two commits, PR #10, CI, merge (requester step 7)

**Purpose**: Land the slice. Executed **only after** Phase 15 is green. (Generation writes nothing here; the
implementer runs these once the gates pass.)

- [ ] T017 Create **two small, pure commits** on `009-federal-bank-ledger-reader` (RED→GREEN kept coherent, matching
  the prior bank slices' shape):
  **Commit 1 — engine + fixtures + parity**: `core/crates/kaname-core/src/statement/federal_bank.rs` (+ its unit
  tests), `pub mod federal_bank;` in `core/crates/kaname-core/src/statement/mod.rs`,
  `core/crates/kaname-core/src/ffi.rs` (2 exports), `core/crates/kaname-core/src/lib.rs` (re-exports),
  `fixtures/federal/bank_account/classic.json`, `fixtures/federal/bank_account/fi.json`,
  `core/crates/kaname-core/tests/parity.rs` (wrapper + 2 `Case` rows + 1 chain test + claim split), and any docs from
  T014.
  **Commit 2 — Swift test**: `ios/Tests/FederalBankParseTests.swift`.
  Do **not** commit generated artifacts (`ios/Generated/…`, `ios/Frameworks/…` are git-ignored) or the Scapia CC
  fixture. Ref: requester step 7.
- [ ] T018 Push the branch, open **PR #10** (`SSKUltra/kaname`, base default branch — **#10** is the next number;
  slice-number ≠ PR-number because the intervening `chore/harden-ios-ci-simulator` took **#9**; confirm with
  `gh pr list` before opening), **watch CI** — both the **core** job (ubuntu: `core-lint` + `core-test` +
  `core-privacy-audit`) and the **iOS** job (**macos-15**: `core-xcframework` → `tuist generate` → `xcodebuild …
  iPhone 16` test) go green — then **`gh pr merge --rebase --delete-branch`**. Ref: requester step 7.

**Checkpoint**: Federal savings/current joins the balance-ledger family as the third reference reader — two
templates behind one config, byte-for-byte with the web engine, on the unchanged base, with a zero shared footprint.

---

## Dependencies & Execution Order

### Phase order

1. **Setup (P1)** → 2. **Test-First Foundation (P2, RED)** → 3. **US1 GREEN engine pipeline (P3)** →
4. **Bridge/Swift green (P4)** → 5–12. **US2/US3/US4/US5/US6/US7/US8/US9 verification (P5–P12)** →
13. **US10 parity guard (P13)** → 14. **US11 privacy guard (P14)** → 15. **Polish + full gate (P15)** →
16. **Ship (P16)**.

- **Test-First (Phase 2) BLOCKS all engine code (Phase 3+)** — T003–T006 must exist and be RED first (Principle V,
  FR-034/036).
- **The US1 GREEN pipeline (T007→T009) is the critical path** and lands the behaviours US2–US9 verify.

### Task-level dependencies

- T003/T004 (fixtures) precede T005 (parity `Case`/chain/claim) and T009 (green); T005/T006 (RED tests) precede
  **all** implementation (T007+).
- **Engine spine (linear — no shared/refactor task, unlike 008)**: **T007** (`federal_bank.rs` + `mod.rs` + unit
  tests) → **T008** (`ffi.rs` exports + `lib.rs`, needs T007) → **T009** (`core-fmt` → Rust green, needs T008).
- T008 → **T010** (xcframework) → **T011** (Swift green). **T010 before any `tuist generate`.**
- Guards: **T012** (parity whole-slice) depends on T009; **T013** (privacy + reachability) depends on T009 (+ T011
  reachability).
- **T015 (full gate) depends on everything** (T009, T011, T012, T013, T014); T016 is review only.
- **Ship**: T017 depends on T015 (all green); T018 depends on T017.

### Parallel opportunities

- **Setup**: T001 [P] + T002 [P].
- **Test-First**: T003 [P] (classic fixture) + T004 [P] (fi fixture) + T006 [P] (Swift test) are different files;
  T005 edits `parity.rs` (run it alone; it references T003/T004's fixture paths to verify RED).
- **Engine spine**: **linear** (T007 → T008 → T009) — Federal adds no shared/refactor task, so there is **no**
  parallel engine task (contrast 008's `icici_bank.rs` refactor running parallel to `hdfc_bank.rs`).
- **Polish**: T014 [P] + T016 [P] (docs + review); T015 runs the gate alone.

**[P] set**: T001, T002, T003, T004, T006, T014, T016.

**Critical path**: T003/T004 → T005/T006 (RED) → **T007 → T008 → T009** → T010 → T011 → T012 → T013 → T015 → T017 →
T018.

---

## Parallel Example: the Test-First Foundation (Phase 2)

```bash
# Phase 2 — author the three independent RED artifacts together (different files):
Task T003: "Author fixtures/federal/bank_account/classic.json (exact bytes; 3 rows; data-model.md §3.1 + research.md D8)"
Task T004: "Author fixtures/federal/bank_account/fi.json (exact bytes; 2 rows; whole-number amounts; data-model.md §3.2)"
Task T006: "Author ios/Tests/FederalBankParseTests.swift (RED core ↔ Swift Federal bank parse + chain, both templates)"
# Then T005 edits tests/parity.rs (wrapper + 2 Case rows + 1 per-fixture chain test + claim split) → verify RED (won't compile).

# Phase 3 — the engine spine is LINEAR (no parallel task — zero shared/refactor work):
# T007 (statement/federal_bank.rs — FederalBankReader impl LedgerReaderConfig, 2 anchors, enrich, mod.rs, unit tests)
#   → T008 (ffi.rs exports + lib.rs re-exports) → T009 (core-fmt → core-test → core-lint GREEN).
```

---

## Implementation Strategy

### MVP first (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 **RED** (2 fixtures → parity `Case`s/chain/claim → Swift) → 3. Phase 3 engine spine
(T007→T009, `make core-fmt` then green) → 4. Phase 4 bridge (T010–T011). **STOP & VALIDATE**: **both** Federal
statements parse on-device through `read_federal_bank_statement`, `check_balance_chain` reports RECONCILED for each,
and the Swift suite is green. This alone is a shippable, useful slice (the third bank config on the base — the
leanest yet).

### Incremental delivery

Add US2 (two templates) → US3 (delta direction + Cr/Dr-ignored + two-column) → US4 (S-serial out of description) →
US5 (opening per template) → US6 (narration stitching + `GRAND TOTAL`) → US7 (period/last-4) → US8
(savings-vs-Scapia-CC gate) → US9 (config-on-base, zero shared code) — each an independent test increment over the
**same** engine, already verified by the fixtures/parity/unit/Swift tests authored in Phases 2–4. Then lock the
**guards**: US10 (golden parity — both templates, no prior-fixture migration) and US11 (inherited privacy-egress +
Swift reachability). Finish with the full-gate run (T015) and Ship (T017–T018, two commits + PR #10).

### Story → task traceability

| Story | Delivered by | Independently verified by |
|---|---|---|
| **US1** on-device parse 🎯 | T007, T008, T009, T010, T011 | **T009** (Rust parity, both templates), **T011** (Swift), **T005** claim-split |
| **US2** two templates / first-match-wins | T007 (`anchor_res` → `[CLASSIC, FI]`) on the reused base | **T007** unit tests + **T003/T004** (mutual exclusion) + **T005**/**T011** |
| **US3** delta direction / Cr-Dr consumed-but-ignored / amount-as-check | reused `read_ledger_lines`/`anchor_amount` + T007's unnamed `(?:Cr\|Dr)` | **T007** unit tests (a classic Debit/Credit/Debit despite `Cr`; b Fi non-zero column) + **T003/T004** + reused delta-flip test |
| **US4** S-serial captured, kept OUT of description | T007 (`(?:\s+(?P<serial>S\d+))?`) + reused serial handling | **T007** unit test (a) + **T003/T004** (serial set, not in `description_raw`) + **T005**/**T011** |
| **US5** opening per template / opening-anchored row-1 | T007 (`OPENING_RE` with optional `OPNBAL`) + reused row-1 bootstrap | **T007** unit test (b) + **T003/T004** (`direction_source`) + **T005** (no fallback) |
| **US6** narration stitching (folded continuation + `GRAND TOTAL`) | reused `stitch_narration` | **T003/T004** (byte-exact `description_raw`) + **T007** (`GRAND TOTAL` not a row) + **T005** + **T011** |
| **US7** ledger metadata (period / account last-4) | T007 (`PERIOD_RE`/`FEDERAL_ACCOUNT_RE`/`enrich`) + reused `account_tail_last4` | **T003/T004** (period + `1234`/`4222`) + **T005**/**T011** |
| **US8** savings-vs-Scapia-CC gate (shared `FEDERAL`) | T007 (`claim_all`) + reused `claims_ledger` | **T007** unit test (c) + **T005** (`federal_bank_claims` split) + **T011** + untouched `federal_claims` test |
| **US9** config-on-base, ZERO new shared code | T007 (config) + T008 (2 FFI exports reusing `check_balance_chain`) | **T009** (9 prior cases green; no migration) + **T016** review |
| **US10** golden parity 🛡️ | T003, T004, T005, T009 | **T012** (whole-slice guard; both templates; no prior migration) |
| **US11** privacy + bridge 🛡️ | *inherited* gate + T005 determinism + T008/T011 UniFFI | **T013** (privacy-egress + no-new-dep + reachability) |

---

## Notes

- **Test-first is mandatory** (Principle V, FR-034/036): T003–T006 are RED before Phase 3; T009 greens the Rust
  parity + chain + claim-split + unit guards, T011 greens the Swift bridge — each has an explicit RED→GREEN verify
  step. The two `expected` blocks are the **locked characterization ground truth** (captured `classic_savings` /
  `fi_neobank` JSON; no live capture needed — `research.md` §Open questions: "None").
- **Design is LOCKED** in `plan.md`/`data-model.md`/`contracts/` — the porting tasks **sequence** it, they do not
  re-derive it. Every value (3/2 rows, ledger metadata, printed `100000.00`/closing, periods, S-serials,
  `1234`/`4222`, RECONCILED chain, the stitched narrations incl. `GRAND TOTAL`) is pinned in `data-model.md §3` +
  `research.md D8`.
- **Use the REAL landed symbols** (mirror 008): `ParsedTransaction` (`value_date`) via `ParsedStatement.lines`;
  `check_balance_chain(statement: ParsedStatement) -> ChainResult` with `result.status == ChainStatus::Reconciled`.
  (The fixture JSON key is `expected.rows[]`.)
- **The trailing `Cr`/`Dr` is CONSUMED-BUT-IGNORED** (research **D3**) — the anchors match `\s+(?:Cr|Dr)\s*$` as an
  **unnamed** group; direction is delta-derived (row 1 `OpeningBalance`, later `BalanceDelta`), never the marker, the
  amount's sign/column, or the printed column. Every fixture marker is `Cr`; the rows are a debit/credit mix.
- **Whole-number Fi amounts** (research **D4**) are stored **exactly** as `"5000"`/`"50000"` and still reconcile
  against the 2-dp delta (rust_decimal compares by value across scales). Classic amounts keep `.00`.
- **`GRAND TOTAL` is not a transaction** (research **D8**) — no leading date, no trailing `Cr`/`Dr` ⇒ matches no
  anchor; folded into classic row 3's narration byte-for-byte. Column headers + `Opening Balance` likewise yield no
  rows. Do **not** "clean up" stitched text.
- **Two-place amount-vs-delta**: the **reader** records **exact** `amount == |delta|`; the **₹1.00 tolerance** lives
  **ONLY** in `balance_chain::check`. Keep them separate. Both fixtures reconcile (0 suspects).
- **`card_last4 "1234"`/`"4222"`** via the shared `account_tail_last4(text, &FEDERAL_ACCOUNT_RE)` (`X*`/4+-digit
  primary else the longest `\d{9,}` run) — **already exists** in `common.rs` (no new helper).
- **Shared `FEDERAL` code, two readers**: `federal.rs` (Scapia CC, `Scapia` marker) is **UNCHANGED** and coexists
  with `federal_bank.rs` (`Federal Bank` + `Statement of Account`), separated by claim gates (research **D5**).
  **Do not touch `federal.rs` or `fixtures/federal/credit_card/basic.json`.**
- **Additive & back-compatible & LEANEST**: no records/enums/FFI types added; **no shared/base/`common.rs` change at
  all** (`account_tail_last4` + all four date formats already present); the harness schema is untouched (extended in
  007), so the **9 prior fixtures need NO migration**. **No new dependency** (runtime *or* dev); money is `Decimal`
  (no geometry exercised).
- **REUSE, not rebuild**: the ledger base (`ledger_reader.rs`), the balance chain (`balance_chain.rs`), `common.rs`
  (`parse_amount`/`parse_date`/`account_tail_last4`, all Federal date formats present), `base.rs` records, the
  `tests/parity.rs` harness, the `ffi.rs` `Decimal`/`NaiveDate` bridges + the reused `check_balance_chain`, and the
  privacy-egress gate are inherited. The **only** NEW code is the Federal config + FFI + fixtures + tests.
- **iOS gate ordering**: `make core-xcframework` **before** `tuist generate` (`Makefile:32`); **iPhone 16**
  simulator; CI iOS job pinned to **macos-15**.
- **[P]** = different files, no unfinished dependency. `[Story]` labels map each task to its user story.
- **Generation commits nothing**; the two commits + **PR #10** (`gh pr list` confirms #10 is next — #9 was a chore
  PR) + `--rebase --delete-branch` merge are **Phase 16: Ship**, executed by the implementer after every gate is
  green.
