---
description: "Task list — Yes Bank (Kiwi) Credit-Card Parser (fourth real reader, single layout, zero new engine infra)"
---

# Tasks: Import a Yes Bank (Kiwi) Credit-Card Statement On-Device (Fourth Real Parser, Zero New Engine Infrastructure)

**Input**: Design documents from `/specs/005-yes-cc-parser/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md` (D1–D10), `data-model.md`,
`contracts/engine-ffi.md`, `contracts/golden-fixture.md`, `quickstart.md`

**Tests**: REQUIRED and **TEST-FIRST** for this slice (Constitution Principle V). Authoring the
golden fixture, the failing Rust parity `Case` row (+ the `yes_claims` accept/reject test), and the
failing Swift "core ↔ Swift Yes parse" test are all done **RED, before** the `YesReader` code that
greens them (FR-024).

**Port source of truth** (faithful, byte-for-byte with the golden vector — every porting task cites
exact `yes_kiwi.py` lines/regex/behavior):
`/Users/ssk/Projects/finance-tracker-phase/backend/app/services/ingestion/statement_readers/yes_kiwi.py`
(reusing the already-ported `_common`, `polarity`, `base`, `_line_reader` from the ICICI slice,
extended by HDFC, and reused verbatim by SBI). Yes's `expected` is the **locked characterization
ground truth** from the web engine's Yes vector — **no live run needed** (`quickstart.md` §0); it was
re-confirmed by running the proposed `YesReader` against the real `kaname-core` helpers (research
"Verification harness").

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: `US1`=parse · `US2`=zero-new-infra · `US3`=direction (`Dr`/`Cr`) · `US4`=metadata ·
  `US5`=reconciliation carve-out · `US6`=errored-lines · `US7`=golden parity · `US8`=privacy-egress.
  Setup/Polish carry no story label.
- Exact file paths are included in every task.

## ♻️ REUSE — do NOT re-create (Yes adds only `yes.rs` + fixture + exports + one `Case` row)

Yes plugs into the ICICI/HDFC/SBI foundations **unchanged**. Like SBI (`004`), this is a **clean
single-layout drop-in**: it adds **NO new shared helper and NO composite** (FR-017, SC-010). Do
**not** rebuild any of these:

- `statement/common.rs` — `parse_amount` (`common.rs:50`) / `parse_date` (`common.rs:58`) — the
  day-first `DD/MM/YYYY` format `"%d/%m/%Y"` is **already present** (`common.rs:21`, already commented
  **"(ICICI, Yes)"** — the very format ICICI uses; research **D4**) / `find_last4(text, Some("Card
  Number"))` **anchor** path (`common.rs:141`, already exercised by HDFC/SBI; research **D6/D7**).
- `statement/polarity.rs` — `classify(...)` (`polarity.rs:62`); the two-letter `Dr`/`Cr` markers are
  **already** in the tables (`CR_MARKERS` has `"CR"`, `DR_MARKERS` has `"DR"` — `polarity.rs:11–12`;
  `normalise_marker` upper-cases `"Cr"→"CR"`, `"Dr"→"DR"`; research **D5**).
- `statement/base.rs` — `ParsedStatement` / `ParsedTransaction` records **unchanged**; `period_start`
  is **already a field** (`base.rs:44`, added by HDFC), as are `period_end` (`base.rs:45`) and
  `card_last4` (`base.rs:46`). **There are NO `printed_total_*` fields** — the reconciliation carve-out
  is structural (research **D10**, FR-013).
- `statement/line_reader.rs` — the `read_lines` / `claims` seam + `LineReaderConfig` trait, reused
  **verbatim** (single layout → **`read_lines` directly**, NOT the HDFC composite; research **D2**);
  the errored-line `truncate_chars`/`MAX_RAW` path is reused as-is (US6).
- `ffi.rs` — the `Decimal`/`NaiveDate` custom types + `Direction` enum (**no `uniffi.toml` change, no
  new record, no new Swift type**).
- `tests/parity.rs` — the golden-fixture parity harness (**add one `Case` row + one `claims` test, do
  NOT change the schema** — `period_start` is already present with `#[serde(default)]` and asserted:
  `parity.rs:30–31`).
- The **privacy-egress gate** (`make core-privacy-audit`) and CI — inherited **unchanged** (**no new
  dependency** → byte-identical shipped `cargo tree` graph; research **D1**, plan Constitution Check).

**The only NEW code**: `statement/yes.rs` (one zero-sized `YesReader` config + its `enrich` = period +
last-4 ONLY), **two** `#[uniffi::export]` functions (`read_yes_statement` + `yes_claims`), the
`lib.rs` re-exports, `pub mod yes;` in `statement/mod.rs`, **one** golden fixture, and **one** parity
`Case` row. **No new dependency** (runtime *or* dev); **no new shared helper**; **no harness schema
change**.

## 🚫 Reconciliation carve-out — the one non-mechanical rule (research D10, FR-013, US5, SC-013)

The web `yes_kiwi.py` `_enrich` **also** scrapes printed per-statement totals via `_DEBITS_RE`
(`yes_kiwi.py:26`) → `printed_total_debits` (`yes_kiwi.py:38–40`) and `_CREDITS_RE`
(`yes_kiwi.py:27–29`) → `printed_total_credits` (`yes_kiwi.py:41–43`). **Those two regexes and their
`printed_total_*` assignments MUST NOT be ported.** The Rust `ParsedStatement` has no such fields; the
Yes `enrich` here is **period + last-4 only**. Every porting task below repeats this prohibition.

## ⚠️ Local gotchas (apply throughout)

- **`make core-xcframework` MUST run before `tuist generate`** (`ios-gen: core-xcframework`) — the
  generated Swift (`ios/Generated/kaname_core.swift`) + `KanameCoreFFI.xcframework` are rebuilt
  artifacts (`quickstart.md` §3/§Troubleshooting).
- **Local Xcode 26 needs an explicitly-created "iPhone 16" simulator** for `make ios-test`
  (`xcodebuild -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'`).
- Money is **`Decimal`, never `f64`**; Indian grouping is stripped and scale preserved
  (`9,000.00 → 9000.00`). Direction comes from the **terminal `Dr`/`Cr` marker** via
  `classify(desc, dir, None)`, never the amount's sign and never the description's wording (even though
  row 0's description begins with "PAYMENT RECEIVED"). **No new dependency** (runtime *or* dev).
- **`card_last4` is `"6686"`** here (the parity contrast vs SBI's `null`): the mask
  `3561XXXXXXXX6686` exposes **four** trailing digits, so `find_last4` recovers `"6686"` with no
  Yes-specific code (research **D7**).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the invariants and prerequisites so every later task has a place to land and the
gates stay green. No behavior yet.

- [ ] T001 [P] Confirm the **no-new-dependency** invariant: `core/crates/kaname-core/Cargo.toml` stays **UNCHANGED** (runtime deps `regex`/`rust_decimal`/`chrono`/`serde`/`uniffi` + dev-only `serde_json` already present from the ICICI slice) — Yes adds **zero** deps (FR-025, SC-012). Create the fixtures home directory `fixtures/yes/credit_card/`. Ref: plan §Summary/§Project Structure, `contracts/golden-fixture.md` §Location.
- [ ] T002 [P] Verify local prerequisites & gotchas (no code): `cargo` on PATH (`source "$HOME/.cargo/env"`); iOS targets present (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`); an **"iPhone 16" simulator** exists in Xcode 26; recall `make core-xcframework` precedes `tuist generate` (`ios-gen: core-xcframework`). Ref: `quickstart.md` §Prerequisites/§Troubleshooting.

**Checkpoint**: Fixtures home exists, no manifest change needed, toolchain ready.

---

## Phase 2: Test-First Foundation (⚠️ Principle V — author RED before ANY Yes code)

**Purpose**: Pin the on-device engine to the proven web engine **before** writing it. These are the
parity (US7) and bridge (US1) tests that **protect the whole slice**; they MUST be **RED** at the end
of this phase (`read_yes_statement` / `yes_claims` do not exist yet).

**⚠️ CRITICAL**: No Yes parser code (Phase 3+) may be written until T003–T005 exist and are verified failing.

- [ ] T003 [P] [US7] Author the **ported** golden vector `fixtures/yes/credit_card/basic.json` — copy the **exact fixture bytes** from `contracts/golden-fixture.md` §"Exact fixture bytes to write" (do **not** hand-derive). `lines` = the two synthetic Yes rows `29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr` and `19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr`; `full_text` (`\n`-joined) contains `YES BANK KLICK`, `Statement for YES BANK Card Number 3561XXXXXXXX6686`, `Statement Period: 17/04/2026 To 16/05/2026`, then the two rows; `expected.rows` = `{ "2026-04-29", "9000.00", Credit, INR, "PAYMENT RECEIVED BBPS - Ref No: RT0001" }` and `{ "2026-04-19", "100.00", Debit, INR, "UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores" }`; `period_start "2026-04-17"`; `period_end "2026-05-16"`; **`card_last4 "6686"`** (the mask `3561XXXXXXXX6686` exposes **four** trailing digits — recovered, never fabricated, research **D7**); `errored_lines []`. Amounts are **JSON strings** (re-parsed to `Decimal`, never `f64`); `9,000.00` normalizes to the string `"9000.00"` (scale preserved, Indian grouping stripped). `description_raw` is **byte-for-byte** — the terminal `Dr`/`Cr` marker and the amount are **not** part of it, but the merchant-category text (`Miscellaneous Stores`) **is** (US1-AC3, research **D3**). **No `printed_total_*` keys anywhere** (reconciliation carve-out, FR-013, SC-013). 100% synthetic/redacted (FR-023, SC-012). Ref: `contracts/golden-fixture.md` §The Yes `basic.json` vector, `quickstart.md` §0, research **D3/D6/D7/D10**.
- [ ] T004 [US7] Extend the parity harness `core/crates/kaname-core/tests/parity.rs` → **RED** (the **only** harness change; **NO schema/struct/assertion change** — `period_start` was already added with `#[serde(default)]` and asserted by HDFC, `parity.rs:30–31/107–110`): extend `use kaname_core::{… , read_yes_statement, yes_claims, …}` (`parity.rs:12–14`); add **one** `Case` row to the existing `CASES` table (`parity.rs:54–75`) — `Case { label: "Yes Bank", parse: read_yes_statement, rel_path: "yes/credit_card/basic.json" }`; add a `yes_claims` accept/reject test mirroring `sbi_claims_accepts_own_document_and_rejects_others` (`parity.rs:169–177`): `yes_claims(basic.full_text) == true`; `yes_claims("ICICI Bank Statement".to_string()) == false`; `yes_claims("GSTIN of SBI Card".to_string()) == false` (FR-002, SC-002, research **D9**). Leave the ICICI/HDFC/SBI fixtures and `Expected`/`ExpectedRow`/`Case` structs (`parity.rs:27–53`) **untouched**. ⚠️ **Verify RED**: `make core-test` fails to **compile** (`read_yes_statement`/`yes_claims` absent). Ref: `contracts/golden-fixture.md` §Harness behaviour, `data-model.md` §Fixture/harness types, research **D9**.
- [ ] T005 [P] [US1] Author the **RED** Swift bridge test `ios/Tests/YesParseTests.swift` — "core ↔ Swift Yes parse" (`import KanameCore`, Swift Testing), mirroring `ios/Tests/SBIParseTests.swift`: `readYesStatement(lines:fullText:)` over the two golden lines → 2 `lines`; `lines[0]` = `valueDate "2026-04-29"` / `Decimal(string: "9000.00", locale: en_US_POSIX)` / `.credit` / `currency "INR"` / `descriptionRaw "PAYMENT RECEIVED BBPS - Ref No: RT0001"`; `lines[1]` = `"2026-04-19"` / `Decimal(string: "100.00")` / `.debit` / `"UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores"`; `periodStart == "2026-04-17"`; `periodEnd == "2026-05-16"`; **`cardLast4 == "6686"`**; `erroredLines.isEmpty`. `yesClaims(fullText:) == true` for the Yes text and `false` for an `"ICICI Bank Statement"` string. Amounts compared as exact `Foundation.Decimal` value-equality (never float). ⚠️ **Verify RED**: won't build until the xcframework is regenerated with the exports in Phase 4. Ref: `contracts/engine-ffi.md` §Contract tests (Swift), `ios/Tests/SBIParseTests.swift`.

**Checkpoint**: Fixture in place; Rust parity harness RED (Yes `Case` row + `yes_claims` test won't compile); Swift bridge test RED. Test-first satisfied — Yes parser code may now begin.

---

## Phase 3: User Story 1 — Parse a Yes statement into transactions (Priority: P1) 🎯 MVP

**Goal**: Recognize a Yes Bank (Kiwi) CC statement and return one transaction per row (date, exact
amount, direction, INR, description) — 100% on-device. Porting the reader here also **lands the
behaviors** that US2/US3/US4/US5/US6 verify independently in Phases 5–9.

**Independent Test**: `read_yes_statement(basic.lines, basic.full_text)` returns the two expected rows
and `yes_claims` accepts Yes / rejects ICICI+SBI — with no network in the parse path.

> Port order follows the plan's chain: `yes.rs (config + enrich) → FFI exports + lib re-exports →
> green`. Yes needs **no** enabler helper (contrast HDFC's `month_year_end`/`read_lines_first_match`);
> it is structured **identically to `sbi.rs`**.

- [ ] T006 [US1] Create `core/crates/kaname-core/src/statement/yes.rs` (and add `pub mod yes;` to `core/crates/kaname-core/src/statement/mod.rs`, after `pub mod sbi;` at `mod.rs:15`, keeping alphabetical order) — port `yes_kiwi.py` wholesale, **structured identically to `sbi.rs`** (one zero-sized config + `enrich` as the trait method; single layout):
  - `pub const BANK_CODE: &str = "YES";` (`yes_kiwi.py:18`); `const CLAIM_MARKERS: &[&str] = &["YES BANK"];` — a **single** marker (`yes_kiwi.py:48`).
  - `static ROW_RE: LazyLock<Regex>` ported **byte-for-byte** from `_ROW_RE` (`yes_kiwi.py:20–22`): `^(?P<date>\d{2}/\d{2}/\d{4})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>Dr|Cr)$` — the terminal two-letter `Dr`/`Cr` marker is anchored at `$`; the non-greedy `desc` extends through the merchant-category phrase (`… Ref No: RT0002 Miscellaneous Stores`) because only an *amount* can follow it (US1-AC3, research **D3**).
  - `static PERIOD_RE: LazyLock<Regex>` ported from `_PERIOD_RE` (`yes_kiwi.py:23`, case-insensitive, **NO `Statement Period:` prefix** — just `<date> To <date>`): `(?i)(\d{2}/\d{2}/\d{4})\s+To\s+(\d{2}/\d{2}/\d{4})`.
  - `pub struct YesReader;` `impl LineReaderConfig for YesReader` (mirror `sbi.rs:36–62`): `bank_code()` = `"YES"`; `claim_markers()` = `CLAIM_MARKERS`; `row_re()` = `&ROW_RE`; `direction(caps, desc)` = **reuse** `classify(desc, caps.name("dir").map(|m| m.as_str()), None)` (the exact behavior of the web's `marker_direction()` at `yes_kiwi.py:50`; `Cr→Credit`, `Dr→Debit`; the marker wins **before** any description-keyword check — FR-008/009, research **D5**). Uses the seam's default `date`/`desc`/`amount` group names.
  - `fn enrich(&self, statement, full_text)` (trait method, like `sbi.rs:55–61`) — port `_enrich` (`yes_kiwi.py:32–37`), **period + last-4 ONLY**: if `PERIOD_RE` matches, `statement.period_start = parse_date(&caps[1])` and `statement.period_end = parse_date(&caps[2])` (both via the **existing** `%d/%m/%Y`, `yes_kiwi.py:35–36`); **always** `statement.card_last4 = find_last4(full_text, Some("Card Number"))` (`yes_kiwi.py:37`). Produces `description_raw` `"PAYMENT RECEIVED BBPS - Ref No: RT0001"` / `"UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores"`; `card_last4 = Some("6686")` for the four-digit mask (research **D6/D7**).
  - 🚫 **DO NOT PORT the reconciliation scrape**: no `_DEBITS_RE` (`yes_kiwi.py:26`), no `_CREDITS_RE` (`yes_kiwi.py:27–29`), and **no** `printed_total_debits`/`printed_total_credits` assignments (`yes_kiwi.py:38–43`). `ParsedStatement` (`base.rs`) has no such fields (research **D10**, FR-013, US5, SC-013).
  - `LazyLock` both regexes (determinism, compile-once). **Reuse** `parse_date`/`parse_amount`/`find_last4`/`classify`/records unchanged — **no new shared helper** (SC-010). Ref: `data-model.md` §statement/yes.rs, research **D1–D10**, `yes_kiwi.py:18–51`, `sbi.rs:1–62`.
- [ ] T007 [US1] Add the UniFFI exports in `core/crates/kaname-core/src/ffi.rs` (ICICI/SBI-style **inline**, mirroring `ffi.rs:51–61` and `ffi.rs:80–89`): `use crate::statement::yes::YesReader;` (alongside `ffi.rs:14`) then `#[uniffi::export] pub fn read_yes_statement(lines: Vec<String>, full_text: String) -> ParsedStatement { read_lines(&YesReader, &lines, &full_text) }` (single layout → `read_lines` **directly**, NOT the HDFC composite — research **D2**) and `#[uniffi::export] pub fn yes_claims(full_text: String) -> bool { claims(&YesReader, &full_text, "YES") }` — total functions, never throw/abort (`read_lines`/`claims` imported at `ffi.rs:13`). **Reuse** the existing `Decimal`/`NaiveDate` custom types + `Direction` enum unchanged (**no `uniffi.toml` change, no new record**). Re-export both in `core/crates/kaname-core/src/lib.rs` — extend the existing `pub use ffi::{…}` block (`lib.rs:28–31`) to add `read_yes_statement, yes_claims` — so `tests/parity.rs` and the app path reach them. Depends on T006. Ref: `contracts/engine-ffi.md` §Exported functions, research **D9**, `yes_kiwi.py:46–51`.
- [ ] T008 [US1] **Green the engine side**: run `make core-test` — `tests/parity.rs` (T004) now **PASSES** for the Yes vector (both rows exact incl. `description_raw` byte-for-byte; `period_start 2026-04-17`; `period_end 2026-05-16`; **`card_last4 "6686"`**; `errored_lines` empty), determinism, and `yes_claims` accept/reject — while **ICICI/HDFC/SBI parity stay green** (fixtures untouched) — and `make core-lint` (fmt + clippy `-D warnings`). Verify **RED→GREEN** for the Rust parity harness. Ref: `quickstart.md` §1.

**Checkpoint**: The engine parses the golden Yes statement; the Rust parity + determinism + wrong-issuer tests are green. US1 is functional on the Rust side (Swift bridge greened in Phase 4).

---

## Phase 4: UniFFI bridge — regenerate the xcframework + green the Swift test (US1)

**Goal**: Surface the two new functions to Swift and green the "core ↔ Swift Yes parse" test.

- [ ] T009 [US1] Run `make core-xcframework` to rebuild `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift` (git-ignored artifacts) now exposing `readYesStatement` + `yesClaims` (records reused ⇒ **no new Swift type**; `ParsedStatement.periodStart` is populated for Yes and `cardLast4 == "6686"`). ⚠️ **MUST run before `tuist generate`** (`quickstart.md` §3). Ref: `contracts/engine-ffi.md` §Stability/compatibility.
- [ ] T010 [US1] Run `make ios-test` (`ios-gen` → `core-xcframework` → `tuist generate` → `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test`) to **green** `ios/Tests/YesParseTests.swift` (T005) — the two rows with exact `Foundation.Decimal` amounts, `.credit`/`.debit` from the `Cr`/`Dr` markers, `periodStart == "2026-04-17"`, `periodEnd == "2026-05-16"`, **`cardLast4 == "6686"`**, and `yesClaims` accept/reject. ⚠️ **Local Xcode 26: create the "iPhone 16" simulator first.** Verify **RED→GREEN** for the Swift bridge test. Ref: `quickstart.md` §4.

**Checkpoint**: US1 MVP fully delivered end-to-end (Rust engine + Swift bridge). A person's Yes Bank statement text → transactions, on-device.

---

## Phase 5: User Story 2 — A fourth bank with zero new engine infrastructure (Priority: P2)

**Goal**: Prove Yes is delivered as a **single-layout reader configuration only** — reusing the shared
date parser (`DD/MM/YYYY`) and polarity classifier (`Dr`/`Cr`) with **no new shared helper** and **no
composite**. *(Impl landed in T006 `yes.rs` + T007 direct `read_lines`.)*

**Independent Test**: The Yes parse plugs into the existing `read_lines(lines, full_text)` seam,
reusing `parse_date` and `classify`; a review of the change set shows **no** new/modified shared
helper in the reader subsystem.

- [ ] T011 [US2] Add reuse/plumbing unit tests in `core/crates/kaname-core/src/statement/yes.rs` (`#[cfg(test)]`, mirroring `sbi.rs`'s test module `sbi.rs:64–105`) proving **zero new infra**: `29/04/2026` is interpreted as `2026-04-29` **through the shared `parse_date`** with no Yes-specific date code (US2-AC1, SC-010 — the `%d/%m/%Y` format already lives in `common.rs:21`, commented "ICICI, Yes"); a `Dr`/`Cr` marker maps to debit/credit **through the shared `classify`** with no Yes-specific direction code (US2-AC2 — `"Dr"→"DR"`, `"Cr"→"CR"` already in `polarity.rs:11–12`); the reader drives the shared **`read_lines(&YesReader, …)`** seam **directly** (single layout — it does **not** use `read_lines_first_match`, US2 / research **D2**); and a doc with no matching rows → empty `lines`, no error. Then perform the **change-set review** (US2-AC3, SC-010): confirm the Yes diff is exactly `yes.rs` + `mod.rs` (`pub mod yes;`) + two `ffi.rs` exports + `lib.rs` re-exports + one fixture + one `parity.rs` `Case` row — and adds **no** new shared helper (contrast HDFC's `month_year_end`/`read_lines_first_match`) and **no** dependency (`Cargo.toml` unchanged). Ref: research **D1/D2/D4/D5**, spec US2, plan §Complexity Tracking.

**Checkpoint**: Yes is proven to be a pure single-layout drop-in — shared date/polarity reused, no new engine infrastructure.

---

## Phase 6: User Story 3 — Direction from the terminal `Dr`/`Cr` marker, never the amount's sign (Priority: P3)

**Goal**: Each transaction's direction reflects the statement's own terminal `Dr`/`Cr` marker — `Cr`
credit, `Dr` debit — never the amount's value and never a direction-like word in the description.
*(Impl landed in T006's `direction` = `classify(desc, dir, None)`.)*

**Independent Test**: Rows ending in `Cr` and rows ending in `Dr` classify credit/debit from the
marker, regardless of the amount and regardless of credit/debit wording in the description.

- [ ] T012 [US3] Add direction unit tests in `core/crates/kaname-core/src/statement/yes.rs` (`#[cfg(test)]`): terminal `Cr` → **Credit**, terminal `Dr` → **Debit** (US3-AC1/AC2, FR-009); the **conflicting-word** case — a fabricated row whose description contains **three** credit keywords but whose terminal marker is `Dr`, e.g. `29/04/2026 PAYMENT RECEIVED REFUND CASHBACK 500.00 Dr`, classifies **Debit** — the marker beats the wording `PAYMENT RECEIVED`/`REFUND`/`CASHBACK` (US3-AC3, FR-008, research **D5**); note that golden row 0 (`… 9,000.00 Cr`, desc begins `PAYMENT RECEIVED`) is a credit by **both** marker and keyword, and the marker is the authority; a large/"negative-looking" amount **never** changes the direction (US3-AC4, FR-008, SC-004). Ref: research **D3/D5**, spec US3.

**Checkpoint**: Direction is sourced solely from the terminal `Dr`/`Cr` marker, never the amount or the description.

---

## Phase 7: User Story 4 — Statement metadata: billing period + card last-4 (`"6686"` recovered) (Priority: P4)

**Goal**: Recover `period_start`/`period_end` from the `<date> To <date>` line and `card_last4` from
the `Card Number` anchor — and, crucially, recover **`"6686"`** (four visible digits) while leaving
`card_last4` **absent** (never fabricated) when a mask exposes fewer than four trailing digits. *(Impl
landed in T006's `enrich` + the reused `find_last4` anchor.)*

**Independent Test**: A `Statement Period: … To …` line yields the correct start/end; the masked
`Card Number 3561XXXXXXXX6686` yields `"6686"`; a two-digit mask yields **no** last-4; neither present
→ unset.

- [ ] T013 [US4] Add metadata unit tests in `core/crates/kaname-core/src/statement/yes.rs` (`#[cfg(test)]`, driving `enrich`/`read_lines`): `Statement Period: 17/04/2026 To 16/05/2026` → `period_start 2026-04-17`, `period_end 2026-05-16` (US4-AC1, SC-003, FR-010, both via the shared `parse_date`; note the Yes `_PERIOD_RE` has **no** `Statement Period:` prefix — the `(?i)…To…` pattern matches anywhere, research **D6**); the masked `Statement for YES BANK Card Number 3561XXXXXXXX6686` → **`card_last4 Some("6686")`** because four trailing digits are visible via `find_last4(full_text, Some("Card Number"))` (US4-AC2, FR-011, SC-003, research **D7**); a control mask exposing only two trailing digits (e.g. `Card Number XXXX XXXX XXXX XX61`) → `card_last4 None` — never fabricated (FR-012, research **D7**); a **missing-metadata** input (no `<date> To <date>` line, no masked PAN) → `period_start`/`period_end`/`card_last4` all `None` while rows are still returned (US4-AC3, FR-012). Ref: research **D6/D7**, `yes_kiwi.py:32–37`, spec US4.

**Checkpoint**: Billing-period + card last-4 verified — the four-digit mask yields `"6686"` (the parity contrast vs SBI's `null`), and a short mask yields no fabricated last-4.

---

## Phase 8: User Story 5 — Reconciliation stays out of scope: printed totals NOT ported (Priority: P5) 🚫 scope guard

**Goal**: Prove the Yes output model + fixture carry **only** transactions + period + last-4 (+ errored
lines) — the web reader's printed debit/credit totals are **absent**. This is the one place a naïve
full port would overreach. *(Impl landed in T006's `enrich` deliberately **omitting** `_DEBITS_RE`/
`_CREDITS_RE`; structurally guaranteed because `ParsedStatement` has no `printed_total_*` fields.)*

**Independent Test**: Parse a Yes `full_text` that also contains printed `Purchases … Dr` /
`Payment & Credits Received … Cr` summary lines and confirm the result contains only rows + period +
last-4 — no printed-total values anywhere, and the model exposes no printed-total fields.

- [ ] T014 [US5] Add a reconciliation-carve-out test in `core/crates/kaname-core/src/statement/yes.rs` (`#[cfg(test)]`, driving `read_lines`/`enrich`): with printed-total lines appended to `full_text` (`Purchases Rs. 100.00 Dr` and `Payment & Credits Received Rs. 9,000.00 Cr`), `read_yes_statement` returns **only** the two transaction rows + `period_start 2026-04-17` + `period_end 2026-05-16` + `card_last4 "6686"` — no printed-total value appears in `lines` or anywhere in the output (US5-AC1, FR-013, SC-013, research **D10**). Then perform the **model/source review** (US5-AC2/AC3): confirm `statement/yes.rs` contains **no** `_DEBITS_RE`/`_CREDITS_RE` regex and **no** `printed_total_*` reference (the web `yes_kiwi.py:26/27–29/38–43` lines are deliberately not ported); confirm `ParsedStatement` (`base.rs`) exposes **no** `printed_total_*` fields; and confirm the golden `expected` (T003) carries **no** printed-total keys — the carve-out is structural. Ref: research **D10**, plan §Complexity Tracking, `yes_kiwi.py:26–43`, spec US5.

**Checkpoint**: The reconciliation carve-out is enforced — Yes stays identically shaped to the landed ICICI/HDFC/SBI readers; no half-built reconciliation surface ships.

---

## Phase 9: User Story 6 — Malformed rows captured for review, never dropped or fatal (Priority: P6)

**Goal**: A line that looks like a Yes transaction but whose fields won't parse is captured in
`errored_lines` (raw, ≤240 codepoints), every good row is still returned, and nothing panics.
*(Behavior is **reused unchanged** from the ICICI `read_lines` seam — Yes adds no robustness code.)*

**Independent Test**: Mixed input (a good Yes row + one shape-matching but unparseable row) → the good
row returned, bad row captured, no error; non-transaction lines ignored silently.

- [ ] T015 [P] [US6] Add a Yes errored-line/robustness test in `core/crates/kaname-core/tests/parity.rs` (mirroring `malformed_row_is_captured_not_fatal`, `parity.rs:179–191`): a line matching the Yes shape but with an **unparseable date** (e.g. `99/99/9999 SOME MERCHANT 10.00 Dr`) → captured in `errored_lines` (raw, truncated to 240 codepoints via the reused `truncate_chars`), the valid row (`29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr`) still returned, **no panic** (FR-014, SC-006); header/summary/balance/total lines → ignored (no transaction, no error). Note in the test that this exercises the **reused** `read_lines` errored-line path (`line_reader.rs`) — Yes adds no robustness code. [P] (different file from the `yes.rs` test cluster). Ref: spec US6, `line_reader.rs` read loop, `parity.rs:179–191`.

**Checkpoint**: Parser is resilient — one bad row never takes down the import.

---

## Phase 10: User Story 7 — Proven byte-for-byte against a golden fixture (Priority: P7) 🛡️ whole-slice guard

**Goal**: Make the parity harness the **reusable, regression-proof** guarantee that pins Yes (and every
future reader) to the web engine — this time proving the harness accepts a **fourth bank as a
one-fixture + one-row addition**. *(Fixture T003; harness `Case` row T004; greened T008.)*

**Independent Test**: The harness over the ported Yes vector matches expected output exactly, and
re-running is stable.

- [ ] T016 [US7] Finalize `core/crates/kaname-core/tests/parity.rs` as the **reusable whole-slice guard**: confirm the Yes `Case` calls `read_yes_statement`; field-by-field parity — dates, exact `Decimal` amounts (scale preserved: `"9000.00"`, `"100.00"`; Indian grouping stripped), directions (`Credit`/`Debit` from the `Cr`/`Dr` markers), currency `INR`, `description_raw` **byte-for-byte** (`"PAYMENT RECEIVED BBPS - Ref No: RT0001"` / `"UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores"`), plus `period_start 2026-04-17`, `period_end 2026-05-16`, **`card_last4 "6686"`**, `errored_lines []` (SC-001/003/009); the determinism **re-run** covers the Yes vector (SC-008); the fixture is **100% synthetic** (fabricated merchants/amounts, masked PAN `3561XXXXXXXX6686`; SC-012); confirm `expected` carries **no** printed-total keys (structurally proving the carve-out, SC-013); and confirm the schema stayed **stable through `period_start`** — Yes needed **only one `Case` row** (no struct/assertion change), proving a new line-reader bank is a **one-fixture + one-row** addition. Leave the ICICI/HDFC/SBI fixtures untouched. Ref: `contracts/golden-fixture.md` §Harness behaviour/§Adding a future fixture, research **D9/D10**, plan §Complexity Tracking.

**Checkpoint**: Parity is an enforced guarantee for Yes and the harness stays reusable — a fourth bank landed as one row.

---

## Phase 11: User Story 8 — Privacy gate: zero network in the parse path (Priority: P8) 🛡️ inherited guard

**Goal**: Prove the Yes parse path is egress-free — **structurally** (no networking crate can even
link) and **behaviorally** (determinism) — using the **inherited** gate with **zero** new config.
*(No new script/CI: Yes adds no dependency, so the audit is byte-identical.)*

**Independent Test**: `make core-privacy-audit` passes only when zero networking crates are in the
shipped graph; the determinism test passes; no telemetry/analytics anywhere in the parse path.

- [ ] T017 [US8] Confirm the inherited privacy-egress gate stays **GREEN with ZERO changes**: run `make core-privacy-audit` → `privacy-egress: OK (no networking crate in kaname-core deps)` — Yes adds **no dependency** (runtime *or* dev), so `cargo tree -p kaname-core -e normal` is byte-identical (`Cargo.toml` unchanged — FR-019/025, SC-007/012); the determinism/purity assertion over the Yes vector lives in `tests/parity.rs` (T004/T016, FR-016, SC-008); confirm **no** telemetry/analytics/advertising/crash-reporter enters the parse path and **no** network entitlement/ATS is added app-side (`ios/Project.swift` `infoPlist` unchanged) (FR-020/021). Ref: research **D1**, `quickstart.md` §2, spec US8.

**Checkpoint**: Privacy-egress remains a first-class, structurally- and behaviorally-enforced gate covering Yes.

---

## Phase 12: Polish & Cross-Cutting — full iOS Local Verification Gate green

**Purpose**: Prove the whole slice is merge-ready (SC-011) and review the constitution guarantees.

- [ ] T018 [P] Light docs alignment (no behavior change): note the **fourth real parser** — a **second clean single-layout drop-in (after SBI) with zero new shared helpers** — where the engine/build is described (`README.md` and/or `specs/005-yes-cc-parser/quickstart.md`); ensure `fixtures/README.md` reflects the Yes vector under `fixtures/yes/credit_card/`; if convenient, refresh the `statement/mod.rs` doc comment that lists issuers (`mod.rs:7`) so it reflects Yes landing. No stale wording.
- [ ] T019 **Run the full iOS Local Verification Gate green**, in order: `make core-lint && make core-test && make core-privacy-audit && make lint && make ios-gen && make ios-test`. ⚠️ `make core-xcframework` is rebuilt before `tuist generate` (via `ios-gen`); local Xcode 26 requires the **"iPhone 16"** simulator. This is the SC-011 / FR-026 merge gate. Ref: `quickstart.md` §5.
- [ ] T020 [P] Final constitution review (no code change): **NO new dependency** (runtime *or* dev) — `Cargo.toml` unchanged; **NO new shared helper** and **NO composite** (SC-010 — the diff is `yes.rs` + `mod.rs` + two exports + `lib.rs` re-exports + one fixture + one `Case` row); **reconciliation carve-out honored** — no `_DEBITS_RE`/`_CREDITS_RE`/`printed_total_*` anywhere (FR-013, SC-013); no secrets / network entitlements / copyleft (GPL/AGPL/LGPL) deps (FR-025, SC-012); all fixture/test data synthetic (SC-012); money never `f64` (amounts `Decimal`, Indian grouping stripped, scale preserved); direction from the terminal `Dr`/`Cr` marker, never the amount sign or the description; **`card_last4` is `Some("6686")`** for the four-digit mask (never fabricated); ICICI/HDFC/SBI fixtures and the harness schema untouched (backward-compatible). Confirm against `git diff` before handoff. Ref: spec FR-013/FR-025/SC-010/SC-012/SC-013, plan §Constitution Check/§Complexity Tracking.

---

## Dependencies & Execution Order

### Phase order

1. **Setup (P1)** → 2. **Test-First Foundation (P2, RED)** → 3. **US1 pipeline (P3)** →
4. **Bridge/Swift green (P4)** → 5–9. **US2/US3/US4/US5/US6 verification (P5–P9)** →
10. **US7 parity guard (P10)** → 11. **US8 privacy guard (P11)** → 12. **Polish + full gate (P12)**.

- **Test-First (Phase 2) BLOCKS all Yes parser code (Phase 3+)** — T003–T005 must exist and be RED first (Principle V, FR-024).
- **US1 pipeline is the critical path** and lands the behaviors US2/US3/US4/US5/US6 verify.

### Task-level dependencies

- T003 (fixture) precedes T004 (parity `Case` row) and T008 (green).
- T004/T005 (RED tests) precede **all** implementation (T006+).
- **Chain**: T006 (`yes.rs` + `mod.rs`) → T007 (FFI exports + `lib.rs` re-exports) → T008 (Rust green).
- T007 → T009 (xcframework) → T010 (Swift green). T009 before any `tuist generate`.
- T011/T012/T013/T014 depend on T006; T015 depends on T004 (harness) + T007 (exports); T016 depends on T008; T017 depends on T008.
- **T019 (full gate) depends on everything**; T018/T020 are docs/review only.

### Parallel opportunities

- **Setup**: T001 [P] + T002 [P].
- **Test-First**: T003 [P] (fixture) + T005 [P] (Swift test) are different files; T004 edits `parity.rs` (run it alone; it depends on T003's path existing).
- **Story verification**: T011/T012/T013/T014 all extend `yes.rs`'s `#[cfg(test)]` module (**same file → sequential**, though each is an independent test group); **T015 [P]** lives in `parity.rs` and can run alongside them.
- **Polish**: T018 [P] + T020 [P] (docs + review); T019 runs the gate alone.

---

## Parallel Example: the Test-First Foundation (Phase 2)

```bash
# Author the two independent RED artifacts together (different files):
Task T003: "Author fixtures/yes/credit_card/basic.json (exact bytes from contracts/golden-fixture.md)"
Task T005: "Author ios/Tests/YesParseTests.swift (RED core ↔ Swift Yes parse)"
# Then T004 edits tests/parity.rs (one Case row + yes_claims test) → verify RED (won't compile).
# Converge on the pipeline: T006 (yes.rs + mod.rs) → T007 (ffi.rs exports + lib.rs re-exports) → T008 (Rust green).
```

---

## Implementation Strategy

### MVP first (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 **RED** test-first anchors (fixture → parity `Case` row + `yes_claims`
→ Swift) → 3. Phase 3 pipeline (T006→T008) → 4. Phase 4 bridge (T009–T010).
**STOP & VALIDATE**: the golden Yes statement parses on-device through `read_yes_statement` and the
Swift suite is green. This alone is a shippable, useful slice.

### Incremental delivery

Add US2 (zero-new-infra proof) → US3 (direction from `Dr`/`Cr`) → US4 (metadata incl. recovered
`"6686"`) → US5 (reconciliation carve-out) → US6 (errored/robustness, reused) — each an independent
test increment over the same reader. Then lock the **guards**: US7 (golden parity) and US8 (inherited
privacy-egress). Finish with the full-gate run (T019).

### Story → task traceability

| Story | Delivered by | Independently verified by |
|---|---|---|
| **US1** parse | T005, T006, T007, T008, T009, T010 | T008 (Rust), T010 (Swift), T004 wrong-issuer |
| **US2** zero-new-infra | T006 `yes.rs` (config) + T007 direct `read_lines` | **T011** (reuse tests + change-set review) |
| **US3** direction (`Dr`/`Cr`) | T006 `direction = classify(desc, dir, None)` | **T012** |
| **US4** metadata (`"6686"`) | T006 `enrich` (+ reused `find_last4` anchor) | **T013** |
| **US5** reconciliation carve-out 🚫 | T006 `enrich` **omits** `_DEBITS_RE`/`_CREDITS_RE`; `base.rs` has no `printed_total_*` | **T014** (behavior + model/source review) |
| **US6** errored-lines | *reused* `read_lines` seam + `truncate_chars` | **T015** |
| **US7** golden parity 🛡️ | T003, T004, T008 | **T016** (reusable one-row guard) |
| **US8** privacy-egress 🛡️ | *inherited* gate + T004 determinism | **T017** |

---

## Notes

- **Test-first is mandatory** (Principle V, FR-024): T003–T005 are RED before Phase 3; T008 greens the
  Rust parity, T010 greens the Swift bridge — each has an explicit RED→GREEN verify step. Yes's
  `expected` is the **locked characterization ground truth** (no live capture needed — `quickstart.md`
  §0).
- **Faithful port** (byte-for-byte with the golden vector): every porting task cites its exact
  `yes_kiwi.py` lines/regex/behavior; `description_raw` is asserted **byte-for-byte** —
  `"PAYMENT RECEIVED BBPS - Ref No: RT0001"` / `"UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous
  Stores"` (the merchant-category text is part of the description); `card_last4` is **`"6686"`** because
  the mask `3561XXXXXXXX6686` exposes four trailing digits (research **D3/D6/D7**).
- **🚫 Reconciliation carve-out** (research **D10**, FR-013, US5, SC-013): `statement/yes.rs` MUST NOT
  port `_DEBITS_RE` (`yes_kiwi.py:26`), `_CREDITS_RE` (`yes_kiwi.py:27–29`), or the `printed_total_*`
  assignments (`yes_kiwi.py:38–43`). The Yes `enrich` is **period + last-4 only**; `ParsedStatement`
  has no such fields. This is a deliberate scope *reduction*, not a violation.
- **REUSE, not rebuild**: Yes adds only `yes.rs`, two exports, `lib.rs` re-exports, `pub mod yes;`, one
  fixture, and one `Case` row — everything else (records, `common`/`polarity` helpers, the `read_lines`
  seam, the UniFFI custom types, the parity harness, the privacy gate) is inherited unchanged (FR-017).
  **No new dependency** (runtime *or* dev); **no new shared helper**; **no composite** (contrast HDFC).
- **[P]** = different files, no unfinished dependency. `[Story]` labels map each task to its slice.
- **Guards protect the whole slice**: US5 (reconciliation carve-out), US7 (golden parity), and US8
  (privacy) fail the build/review on any regression to parsing behavior, scope, or egress-freedom.
- **Do not commit** — the author will review and commit.
