---
description: "Task list — HDFC Credit-Card Parser (second real reader, two layouts)"
---

# Tasks: Import an HDFC Credit-Card Statement On-Device (Second Real Parser, Two Layouts)

**Input**: Design documents from `/specs/003-hdfc-cc-parser/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md` (D1–D13), `data-model.md`,
`contracts/engine-ffi.md`, `contracts/golden-fixture.md`, `quickstart.md`

**Tests**: REQUIRED and **TEST-FIRST** for this slice (Constitution Principle V). Capturing the
monthly ground truth, authoring **both** golden fixtures (year-end + monthly), the failing Rust
parity case-table rows (+ the `period_start` assertion), and the failing Swift
"core ↔ Swift HDFC parse" test are all done **RED, before** the HDFC parser code that greens them.

**Port source of truth** (faithful, byte-for-byte with the golden vectors — every porting task
cites exact lines/regexes/behavior):
`/Users/ssk/Projects/finance-tracker-phase/backend/app/services/ingestion/statement_readers/hdfc.py`
(reusing the already-ported `_common`, `polarity`, `base`, `_line_reader` from the ICICI slice).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: `US1`=parse · `US2`=two-layouts · `US3`=direction · `US4`=metadata (both layouts) ·
  `US5`=errored-lines · `US6`=golden parity (both layouts) · `US7`=privacy-egress. Setup/Polish
  carry no story label.
- Exact file paths are included in every task.

## ♻️ REUSE — do NOT re-create (this slice adds config + fixtures + exports, not infrastructure)

HDFC plugs into the ICICI slice's foundations **unchanged**. Do **not** rebuild any of these:

- `statement/common.rs` — `parse_amount` / `parse_date` (all `DATE_FORMATS` already cover HDFC —
  research **D8**) / `find_last4(text, Some("Card Number"))` **anchor** path (HDFC is its first
  consumer — research **D7**).
- `statement/polarity.rs` — `classify(...)` for the **year-end** `DR`/`CR` marker (research **D3**).
- `statement/base.rs` — `ParsedStatement` / `ParsedTransaction` records (unchanged; `period_start`
  **already a field**) + `truncate_chars` / `MAX_RAW`.
- `statement/line_reader.rs` — the `read_lines` / `claims` seam + `LineReaderConfig` trait.
- `ffi.rs` — the `Decimal`/`NaiveDate` custom types + `Direction` enum (**no `uniffi.toml` change,
  no new record**).
- `tests/parity.rs` — the golden-fixture parity harness (add rows + one field, don't rewrite).
- The **privacy-egress gate** (`core/scripts/privacy-egress-audit.sh` + `make core-privacy-audit`)
  and CI — inherited unchanged (**no new dependency** → byte-identical shipped graph, research **D12**).

**The only NEW engine code** (per FR-020): `month_year_end` (in `common.rs`),
`read_lines_first_match` + a `?Sized` relaxation (in `line_reader.rs`), and `statement/hdfc.rs`
(two configs + one shared `enrich` + the monthly leading-`+` rule + composite), plus two
`#[uniffi::export]` functions and two fixtures.

## ⚠️ Local gotchas (apply throughout)

- **`make core-xcframework` MUST run before `tuist generate`** (`ios-gen: core-xcframework`) — the
  generated Swift is a rebuilt artifact (research **D13**).
- **Local Xcode 26 needs an explicitly-created "iPhone 16" simulator** for `make ios-test`
  (`xcodebuild -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'`).
- Money is **`Decimal`, never `f64`**; the monthly Rupee-glyph `C` is a literal **outside** the
  amount group. Direction comes from the **statement** in both layouts (year-end `DR`/`CR`; monthly
  leading `+`), never the amount sign. **No new dependency** (runtime *or* dev).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the invariants and prerequisites so every later task has a place to land and
the gates stay green. No behavior yet.

- [ ] T001 [P] Confirm the **no-new-dependency** invariant: `core/crates/kaname-core/Cargo.toml` stays **UNCHANGED** (runtime deps `regex`/`rust_decimal`/`chrono`/`serde`/`uniffi` + dev-only `serde_json` already present from the ICICI slice) — HDFC adds **zero** deps (FR-029, SC-012). Create the fixtures home directory `fixtures/hdfc/credit_card/`. Ref: plan Summary/Structure, `contracts/golden-fixture.md` §Location.
- [ ] T002 [P] Verify local prerequisites & gotchas (no code): `cargo` on PATH (`source "$HOME/.cargo/env"`); iOS targets present (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`); an **"iPhone 16" simulator** exists in Xcode 26; recall `make core-xcframework` precedes `tuist generate`. Ref: `quickstart.md` §Prerequisites/§Troubleshooting, research **D13**.

**Checkpoint**: Fixtures home exists, no manifest change needed, toolchain ready.

---

## Phase 2: Test-First Foundation (⚠️ Principle V — author RED before ANY HDFC code)

**Purpose**: Pin the on-device engine to the proven web engine **before** writing it — for **both**
layouts. These are the parity (US6) and bridge (US1) tests that **protect the whole slice**; they
MUST be **RED** at the end of this phase (`read_hdfc_statement` / `hdfc_claims` do not exist yet).

**⚠️ CRITICAL**: No HDFC parser code (Phase 3+) may be written until T003–T007 exist and are verified failing.

- [ ] T003 [US6] **Capture the monthly vector's ground truth from a LIVE web-engine run (do this FIRST — never hand-derive, FR-026).** From `finance-tracker-phase/backend` with its venv, run the `quickstart.md` §0 snippet (`from app.services.ingestion.statement_readers import hdfc; hdfc.reader.read_lines(monthly_lines, monthly_full_text)`) and record the output to encode in `monthly.json`: `period_start 2026-05-15`, `period_end 2026-06-14`, `card_last4 5678`; row0 `Debit 1639.00 "EXAMPLE MERCHANT BANGALORE"`; row1 `Credit 6738.00 "CC PAYMENT RECEIVED"`. Also confirm the **year-end** vector strings from the web characterization test (`_HDFC_LINES`/`_HDFC_TEXT` in `test_cc_reader_characterization.py`): `description_raw` `"ONLINE TRF - PYMT RECD - THANK YOU"` / `"WWW EXAMPLE COM GURGAON"`. Ref: `quickstart.md` §0, `contracts/golden-fixture.md` §monthly, research **D10**.
- [ ] T004 [P] [US6] Author the **ported** golden vector `fixtures/hdfc/credit_card/year_end.json` per `contracts/golden-fixture.md`: `lines` = the two synthetic year-end rows (`16-Apr-2025 ONLINE TRF - PYMT RECD - THANK YOU 10,610.00 CR 526873XXXXXX9070` and `04-Apr-2025 WWW EXAMPLE COM GURGAON 1,071.00 DR 526873XXXXXX9070`); `full_text` contains `HDFC Bank Credit Cards`, `Account Summary for the period from APRIL-25 to MARCH-26`, `Card Number XXXX6873XXXXXX9070`, then the two `\n`-joined rows; `expected.rows` = `{2025-04-16, "10610.00", Credit, INR, "ONLINE TRF - PYMT RECD - THANK YOU"}` and `{2025-04-04, "1071.00", Debit, INR, "WWW EXAMPLE COM GURGAON"}`; `period_start "2025-04-01"`; `period_end "2026-03-31"`; `card_last4 "9070"`; `errored_lines []`. Amounts are **JSON strings**; `description_raw` is **byte-for-byte** (the trailing masked card number is **not** part of it). 100% synthetic (FR-027, SC-012).
- [ ] T005 [P] [US6] Author the **fabricated** golden vector `fixtures/hdfc/credit_card/monthly.json` (expected = the T003 live capture): `lines` = `15/05/2026| 13:30 EXAMPLE MERCHANT BANGALORE C 1,639.00` and `20/05/2026| 09:05 CC PAYMENT RECEIVED + C 6,738.00`; `full_text` contains `HDFC Bank Credit Card`, `Billing Period 15 May, 2026 - 14 Jun, 2026`, `Card Number XXXX1234XXXXXX5678`, then the two rows; `expected.rows` = `{2026-05-15, "1639.00", Debit, INR, "EXAMPLE MERCHANT BANGALORE"}` and `{2026-05-20, "6738.00", Credit, INR, "CC PAYMENT RECEIVED"}` (row1 is a payment: leading `+` ⇒ Credit; the leading `C` is **not** in the amount or the description); `period_start "2026-05-15"`; `period_end "2026-06-14"`; `card_last4 "5678"`; `errored_lines []`. Synthetic only. Depends on T003. Ref: `contracts/golden-fixture.md` §monthly.
- [ ] T006 [US6] Extend the parity harness `core/crates/kaname-core/tests/parity.rs` → **RED** (the **only** harness code change beyond the case rows): add `#[serde(default)] period_start: Option<String>` to `Expected` (between `rows` and `period_end`) and one assertion `assert_eq!(statement.period_start, want_period_start, "{label}: period_start")` (re-parsed via `NaiveDate::parse_from_str`); import `read_hdfc_statement`, `hdfc_claims`; add **two** `Case` rows — `{"HDFC year-end", read_hdfc_statement, "hdfc/credit_card/year_end.json"}` and `{"HDFC monthly", read_hdfc_statement, "hdfc/credit_card/monthly.json"}` (**both call the SAME `read_hdfc_statement`** — proving auto-selection, SC-004); add an `hdfc_claims` accept/reject test (`hdfc_claims(year_end.full_text) == true`; `hdfc_claims("ICICI Bank …") == false`). **Backward-compatible**: the ICICI fixture omits `period_start` ⇒ `serde(default)` = `None`, and ICICI's `period_start` is already `None` — **leave `fixtures/icici/credit_card/basic.json` untouched (stays null)**. ⚠️ **Verify RED**: `make core-test` fails to compile (`read_hdfc_statement`/`hdfc_claims` absent). Ref: `contracts/golden-fixture.md` §Harness behavior, `data-model.md` §Fixture/harness types, research **D10**, plan Complexity Tracking.
- [ ] T007 [P] [US1] Author the **RED** Swift bridge test `ios/Tests/HDFCParseTests.swift` — "core ↔ Swift HDFC parse" (`import KanameCore`, Swift Testing), covering **both layouts + wrong-issuer**: **year-end** — `readHdfcStatement(lines:fullText:)` over the two year-end lines → 2 rows, `lines[0]` = `2025-04-16`/`Decimal(string:"10610.00")`/`.credit`/`"INR"`, `lines[1]` = `2025-04-04`/`Decimal(string:"1071.00")`/`.debit`; `periodStart == "2025-04-01"`; `periodEnd == "2026-03-31"`; `cardLast4 == "9070"`. **monthly** — over the two monthly lines → `lines[0]` `.debit` `1639.00`, `lines[1]` `.credit` `6738.00`; `periodStart == "2026-05-15"`; `periodEnd == "2026-06-14"`; `cardLast4 == "5678"`. `hdfcClaims(fullText:) == true` for an HDFC text and `false` for an ICICI string. Amounts compared as exact `Foundation.Decimal`. ⚠️ **Verify RED**: won't build until the xcframework is regenerated with the exports in Phase 4. Ref: `contracts/engine-ffi.md` §Contract tests (Swift).

**Checkpoint**: Both fixtures in place; Rust parity harness RED (both HDFC rows + `period_start`); Swift bridge test RED. Test-first satisfied — HDFC parser code may now begin.

---

## Phase 3: User Story 1 — Parse an HDFC statement into transactions (Priority: P1) 🎯 MVP

**Goal**: Recognize an HDFC CC statement and return one transaction per row (date, exact amount,
direction, INR, description) — 100% on-device. Porting the pipeline here also **lands the behaviors**
that US2/US3/US4/US5 verify independently in Phases 5–8.

**Independent Test**: `read_hdfc_statement(year_end.lines, year_end.full_text)` returns the two
expected rows and `hdfc_claims` accepts HDFC / rejects ICICI — with no network in the parse path.

> Port order follows the plan's chain: `month_year_end (common) → read_lines_first_match
> (line_reader) → hdfc.rs → FFI + lib re-exports → green`. T008 and T009 touch **different files**
> with no interdependency → parallelizable.

- [ ] T008 [P] [US4] Add `pub fn month_year_end(token: &str) -> Option<NaiveDate>` to `core/crates/kaname-core/src/statement/common.rs` — port `hdfc.py:56-78` (`_MONTHS` table + `_month_year_end`): `name = token[..3]` upper-cased against a `JAN..DEC` table; `year = 2000 + yy` (only when the `yy` after `-` is all digits); day = **last day of that month** (compute via chrono as first-day-of-next-month minus one day, wrapping Dec→Jan). Invalid month/year → `None`. Add `#[cfg(test)]`: `MARCH-26 → 2026-03-31`, `APRIL-25 → 2025-04-30`, leap `FEB-24 → 2024-02-29`, Dec-wrap `DEC-25 → 2025-12-31`, `BOGUS-99 → None` (research **D9**). **Reuse** `parse_date`/`find_last4` unchanged. [P] with T009 (different file). Ref: `data-model.md` §common.rs, research **D9**, `hdfc.py:56-78`.
- [ ] T009 [P] [US2] Add the reusable composite to `core/crates/kaname-core/src/statement/line_reader.rs` and relax the seam — port `hdfc.py:119-143` (`HdfcCreditCardReader.read_lines`): `pub fn read_lines_first_match(cfgs: &[&dyn LineReaderConfig], lines: &[String], full_text: &str) -> ParsedStatement` returns the **first** config whose `statement.lines` are non-empty, else the **last** (enriched) empty statement (total: `last.unwrap_or_else(|| ParsedStatement::new(""))` — unreachable for a non-empty slice). Relax `read_lines`/`claims` to `C: LineReaderConfig + ?Sized` (the trait is already object-safe: no generic methods, no `Self` by value) so `&dyn LineReaderConfig` works — **backward-compatible** (`read_lines(&IciciReader, …)` still compiles). Add `#[cfg(test)]` for the composite (first-non-empty wins; all-empty → last enriched) using lightweight in-test configs. [P] with T008. Ref: `data-model.md` §line_reader.rs, research **D2**, `hdfc.py:119-143`.
- [ ] T010 [US1] Create `core/crates/kaname-core/src/statement/hdfc.rs` (and add `pub mod hdfc;` to `core/crates/kaname-core/src/statement/mod.rs`) — port `hdfc.py` wholesale:
  - `pub const BANK_CODE: &str = "HDFC"`; `const CLAIM_MARKERS: &[&str] = &["HDFC Bank Credit Card", "HDFC Bank Credit Cards"]` (`hdfc.py:30-32`).
  - **`HdfcYearEndReader`** (zero-sized) `impl LineReaderConfig`: `row_re()` = `^(?P<date>\d{2}-[A-Za-z]{3}-\d{4})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>DR|CR)\b` (`hdfc.py:35-38`; **not** end-anchored ⇒ a trailing masked card number is ignored — research **D3**); `direction(caps, desc)` = **reuse** `classify(desc, caps.name("dir").map(|m| m.as_str()), None)` (mirrors `marker_direction()`, `CR→Credit`/`DR→Debit`, FR-011; produces `description_raw` `"ONLINE TRF - PYMT RECD - THANK YOU"` / `"WWW EXAMPLE COM GURGAON"`).
  - **`HdfcMonthlyReader`** (zero-sized) `impl LineReaderConfig`: `row_re()` = `^(?P<date>\d{2}/\d{2}/\d{4})\s*\|?\s*\d{1,2}:\d{2}\s+(?P<desc>.+?)\s+(?P<dir>\+\s*)?C\s*(?P<amount>[\d,]+\.\d{2})\b` (`hdfc.py:43-46`; the literal `C` (Rupee glyph) sits **outside** the `amount` group so it never enters the number or `desc` — research **D4**, FR-008); `direction(caps, _desc)` = **NEW rule, not `classify`** — `Credit` iff `caps.name("dir").map_or("", |m| m.as_str()).trim().starts_with('+')`, else `Debit` (`hdfc.py:96-100` `_monthly_direction`, research **D5**, FR-012; produces `description_raw` `"EXAMPLE MERCHANT BANGALORE"` / `"CC PAYMENT RECEIVED"`).
  - **Shared `enrich(statement, full_text)`** used by both configs (`hdfc.py:81-93`): `_PERIOD_RE = (?i)period from\s+([A-Za-z]+-\d{2})\s+to\s+([A-Za-z]+-\d{2})` → `period_end = month_year_end(g2)`, `period_start = month_year_end(g1).and_then(|d| d.with_day(1))`; **else** `_MONTHLY_PERIOD_RE = (?i)Billing Period\s+(\d{1,2}\s+[A-Za-z]{3,9},?\s+\d{4})\s*-\s*(\d{1,2}\s+[A-Za-z]{3,9},?\s+\d{4})` → `period_start = parse_date(&g1.replace(',', ""))`, `period_end = parse_date(&g2.replace(',', ""))`; **always** `statement.card_last4 = find_last4(full_text, Some("Card Number"))` (**reuse** the existing anchor path). Uses `both configs` default `date`/`desc`/`amount` groups.
  - **Composite accessors**: `pub fn read_hdfc(lines: &[String], full_text: &str) -> ParsedStatement { read_lines_first_match(&[&HdfcYearEndReader, &HdfcMonthlyReader], lines, full_text) }` (year-end first, monthly fallback — FR-004) and `pub fn hdfc_claims_text(full_text: &str) -> bool { claims(&HdfcYearEndReader, full_text, BANK_CODE) }` (both configs share markers — `hdfc.py:127-128`).
  - `LazyLock` all regexes (determinism, compile-once). Depends on T008, T009. Ref: `data-model.md` §hdfc.rs, research **D2–D9**, `hdfc.py:30-143`.
- [ ] T011 [US1] Add the UniFFI exports in `core/crates/kaname-core/src/ffi.rs`: `#[uniffi::export] pub fn read_hdfc_statement(lines: Vec<String>, full_text: String) -> ParsedStatement` (wraps `statement::hdfc::read_hdfc(&lines, &full_text)`) and `#[uniffi::export] pub fn hdfc_claims(full_text: String) -> bool` (wraps `statement::hdfc::hdfc_claims_text(&full_text)`) — total functions, never throw. **Reuse** the existing `Decimal`/`NaiveDate` custom types + `Direction` enum unchanged (**no `uniffi.toml` change, no new record**). Re-export both in `core/crates/kaname-core/src/lib.rs` (`pub use ffi::{hdfc_claims, read_hdfc_statement};`, mirroring the ICICI pair) so `tests/parity.rs` and the app path reach them. Depends on T010. Ref: `contracts/engine-ffi.md`, research **D11**, `hdfc.py:143-145`.
- [ ] T012 [US1] **Green the engine side**: run `make core-test` — `tests/parity.rs` (T006) now **PASSES** for **both** HDFC vectors (rows exact incl. `description_raw` byte-for-byte; `period_start 2025-04-01`/`2026-05-15`; `period_end 2026-03-31`/`2026-06-14`; `card_last4 "9070"`/`"5678"`; `errored_lines` empty), determinism, and `hdfc_claims` accept/reject — while the **ICICI** parity stays green (`period_start` null, fixture untouched) — and `make core-lint` (fmt + clippy `-D warnings`). Verify **RED→GREEN** for the Rust parity harness. Ref: `quickstart.md` §1.

**Checkpoint**: The engine auto-selects the layout and parses both golden HDFC statements; the Rust parity + determinism + wrong-issuer tests are green. US1 is functional on the Rust side (Swift bridge greened in Phase 4).

---

## Phase 4: UniFFI bridge — regenerate the xcframework + green the Swift test (US1)

**Goal**: Surface the two new functions to Swift and green the "core ↔ Swift HDFC parse" test.

- [ ] T013 [US1] Run `make core-xcframework` to rebuild `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift` (git-ignored artifacts) now exposing `readHdfcStatement` + `hdfcClaims` (records reused ⇒ **no new Swift type**; `ParsedStatement.periodStart` is now populated for HDFC). ⚠️ **MUST run before `tuist generate`** (research **D13**). Ref: `quickstart.md` §3.
- [ ] T014 [US1] Run `make ios-test` (`ios-gen` → `core-xcframework` → `tuist generate` → `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test`) to **green** `ios/Tests/HDFCParseTests.swift` (T007) — both layouts + wrong-issuer. ⚠️ **Local Xcode 26: create the "iPhone 16" simulator first.** Verify **RED→GREEN** for the Swift bridge test. Ref: `quickstart.md` §4.

**Checkpoint**: US1 MVP fully delivered end-to-end (Rust engine + Swift bridge). A person's HDFC statement text (either layout) → transactions, on-device.

---

## Phase 5: User Story 2 — One reader, two layouts, auto-selected (Priority: P2)

**Goal**: The single HDFC reader parses whichever layout the statement uses — year-end first,
monthly fallback — without the caller choosing. *(Impl landed in T009 `read_lines_first_match` +
T010 monthly config; the generic composite is unit-tested in T009.)*

**Independent Test**: A year-end statement and a monthly statement each parse through the **same**
`read_hdfc_statement`; a statement matching neither layout returns empty `lines` with no error.

- [ ] T015 [US2] Add HDFC layout-selection unit tests in `core/crates/kaname-core/src/statement/hdfc.rs` (`#[cfg(test)]`, driving `read_hdfc`): a **year-end** doc parses via the composite without the caller specifying a layout (US2-S1); a **monthly** doc → the year-end config yields **zero** rows and the composite **falls back** to monthly, returning the monthly rows (US2-S2); the two row regexes are **mutually exclusive** — a year-end row does not match the monthly regex and vice versa (research **D6**); the day-first monthly date `14/05/2026 → 2026-05-14` (US2-S3); the leading `C` is not folded into the amount (parses `1639.00`) or the description (US2-S2); a doc matching **neither** layout → empty `lines`, no error (US2-S4, FR-004). Ref: research **D2/D4/D6**, spec US2.

**Checkpoint**: Two layouts behind one reader, auto-selected and order-safe, independently verified.

---

## Phase 6: User Story 3 — Direction from the statement, never the amount's sign (Priority: P3)

**Goal**: Each transaction's direction reflects the statement's own indication in **both** layouts —
year-end `DR`/`CR` marker, monthly leading `+` — never the amount value. *(Impl landed in T010.)*

**Independent Test**: Year-end rows carrying `CR`/`DR` and monthly rows with/without a leading `+`
classify credit/debit from the statement's own indication, regardless of the amount.

- [ ] T016 [US3] Add direction unit tests in `core/crates/kaname-core/src/statement/hdfc.rs` (`#[cfg(test)]`): year-end `CR` → **Credit**, `DR` → **Debit** (via `classify` — US3-S1/S2, FR-011); monthly leading `+` → **Credit**, its absence → **Debit** (via the new rule — US3-S3/S4, FR-012); and a large/"negative-looking" amount **never** changes the direction in either layout (US3-S5, FR-010, SC-005). Ref: research **D3/D5**, spec US3.

**Checkpoint**: Direction is correct across both layouts and never sourced from the amount.

---

## Phase 7: User Story 4 — Statement metadata: billing period + card last-4, both layouts (Priority: P4)

**Goal**: Recover `period_start`/`period_end` and `card_last4` correctly from whichever layout the
statement uses, else leave unset — never fabricated. *(Impl landed in T008 `month_year_end` + T010
shared `enrich` + the reused `find_last4` anchor.)*

**Independent Test**: A year-end "period from … to …" summary and a monthly "Billing Period …" line
each yield the correct period; the masked `Card Number` yields the last-4; neither present → unset.

- [ ] T017 [US4] Add metadata unit tests in `core/crates/kaname-core/src/statement/hdfc.rs` (`#[cfg(test)]`, driving `enrich`/`read_hdfc`): year-end `Account Summary for the period from APRIL-25 to MARCH-26` → `period_start 2025-04-01` (first day of the opening month) and `period_end 2026-03-31` (last day of the closing month) (US4-S1, SC-003, FR-013); monthly `Billing Period 15 May, 2026 - 14 Jun, 2026` → `period_start 2026-05-15`, `period_end 2026-06-14` (US4-S2, FR-014); `card_last4` via `find_last4(full_text, Some("Card Number"))` = `"9070"` (year-end) / `"5678"` (monthly) (US4-S3, FR-015); a **missing-metadata** input (no period / no masked PAN) → both period fields and `card_last4` `None` while rows are still returned (US4-S4, FR-016). *(`month_year_end`'s own edge cases are covered in T008.)* Ref: research **D7/D9**, `hdfc.py:81-93`, spec US4.

**Checkpoint**: Billing-period + card last-4 (and their absence) verified for both layouts.

---

## Phase 8: User Story 5 — Malformed rows captured for review, never dropped or fatal (Priority: P5)

**Goal**: A row that looks like an HDFC transaction but whose fields won't parse is captured in
`errored_lines` (raw, ≤240 codepoints), every good row is still returned, and nothing panics.
*(Behavior is **reused unchanged** from the ICICI `read_lines` seam — HDFC adds no robustness code.)*

**Independent Test**: Mixed input (good HDFC rows + one shape-matching but unparseable row) → all
good rows returned, bad row captured, no error; non-transaction lines ignored silently.

- [ ] T018 [P] [US5] Add an HDFC errored-line/robustness test in `core/crates/kaname-core/tests/parity.rs`: a line matching an HDFC shape but with an unparseable date (e.g. year-end `99-Zzz-9999 SOME DESC 10.00 CR`) → captured in `errored_lines` (raw, truncated to 240 codepoints), every valid row still returned, **no panic** (FR-017, SC-007); header/summary/balance/total lines → ignored (no transaction, no error). Note in the test that this exercises the **reused** `read_lines` errored-line path (`line_reader.rs`) + `truncate_chars`. [P] (different file from the hdfc.rs test cluster). Ref: spec US5, `line_reader.rs` read loop.

**Checkpoint**: Parser is resilient in both layouts — one bad row never takes down the import.

---

## Phase 9: User Story 6 — Proven byte-for-byte against golden fixtures, both layouts (Priority: P6) 🛡️ whole-slice guard

**Goal**: Make the parity harness the **reusable, regression-proof** guarantee that pins **both**
HDFC layouts (and every future reader) to the web engine. *(Fixtures T004/T005; harness + rows +
`period_start` T006; greened T012.)*

**Independent Test**: The harness over the ported year-end vector and the live-captured monthly
vector matches expected output exactly for each, and re-running is stable.

- [ ] T019 [US6] Finalize `core/crates/kaname-core/tests/parity.rs` as the **reusable whole-slice guard**: confirm **both** HDFC rows call the **same** `read_hdfc_statement` (auto-selection, SC-004); field-by-field parity **including the new `period_start`** (year-end `2025-04-01`, monthly `2026-05-15`) + `period_end`/`card_last4`/`errored_lines`; the determinism **re-run** covers both HDFC vectors (SC-009); both fixtures are **100% synthetic** (fabricated merchants/amounts, masked PANs `…9070`/`…5678`; SC-012); the schema is now **stable through `period_start`** — a future line-reader bank = **one `Case` row** + a fixture, no further harness change; and the **ICICI fixture stays untouched** with `period_start` null (backward-compat). Ref: `contracts/golden-fixture.md` §Harness behavior/§Adding a future fixture, plan Complexity Tracking, research **D10**.

**Checkpoint**: Parity is an enforced guarantee for both layouts and the harness stays reusable by later banks.

---

## Phase 10: User Story 7 — Privacy gate: zero network in the parse path (Priority: P7) 🛡️ inherited guard

**Goal**: Prove the HDFC parse path is egress-free — **structurally** (no networking crate can even
link) and **behaviorally** (determinism) — using the **inherited** gate with **zero** new config.
*(No new script/CI: HDFC adds no dependency, so the audit is byte-identical.)*

**Independent Test**: `make core-privacy-audit` passes only when zero networking crates are in the
shipped graph; the determinism test passes; no telemetry/analytics anywhere in the parse path.

- [ ] T020 [US7] Confirm the inherited privacy-egress gate stays **GREEN with ZERO changes**: run `make core-privacy-audit` → `privacy-egress: OK (no networking crate in kaname-core deps)` — HDFC adds **no dependency** (runtime *or* dev), so `cargo tree -p kaname-core -e normal` is byte-identical (`Cargo.toml` unchanged — FR-029, SC-012); the determinism/purity assertion over **both** HDFC vectors lives in `tests/parity.rs` (T006, FR-019, SC-008/009); confirm **no** telemetry/analytics/advertising/crash-reporter enters the parse path and **no** network entitlement/ATS is added app-side (`ios/Project.swift` `infoPlist` unchanged) (FR-022/023/024). Ref: research **D12**, `quickstart.md` §2, spec US7.

**Checkpoint**: Privacy-egress remains a first-class, structurally- and behaviorally-enforced gate covering HDFC.

---

## Phase 11: Polish & Cross-Cutting — full iOS Local Verification Gate green

**Purpose**: Prove the whole slice is merge-ready (SC-011) and review the constitution guarantees.

- [ ] T021 [P] Light docs alignment (no behavior change): note the **second real parser** + the **two-layout composite** and the new reuse seams (`read_lines_first_match`, `month_year_end`) where the engine/build is described (`README.md` and/or `specs/003-hdfc-cc-parser/quickstart.md`); ensure `fixtures/README.md` reflects the two HDFC vectors and the `period_start` field. No stale wording.
- [ ] T022 **Run the full iOS Local Verification Gate green**, in order: `make core-lint && make core-test && make core-privacy-audit && make lint && make ios-gen && make ios-test`. ⚠️ `make core-xcframework` is rebuilt before `tuist generate` (via `ios-gen`); local Xcode 26 requires the **"iPhone 16"** simulator. This is the SC-011 / FR-030 merge gate. Ref: `quickstart.md` §5.
- [ ] T023 [P] Final constitution review (no code change): **NO new dependency** (runtime *or* dev) — `Cargo.toml` unchanged; no secrets / network entitlements / copyleft (GPL/AGPL/LGPL) deps (FR-029, SC-012); all fixture/test data synthetic (SC-012); money never `f64` (amounts `Decimal`, monthly `C` excluded); direction from the statement in **both** layouts, never the amount sign; the `period_start` field + the `?Sized` relaxation are backward-compatible (ICICI untouched). Confirm against `git diff` before handoff. Ref: spec FR-029/SC-012, plan Constitution Check.

---

## Dependencies & Execution Order

### Phase order

1. **Setup (P1)** → 2. **Test-First Foundation (P2, RED)** → 3. **US1 pipeline (P3)** →
4. **Bridge/Swift green (P4)** → 5–8. **US2/US3/US4/US5 verification (P5–P8)** →
9. **US6 parity guard (P9)** → 10. **US7 privacy guard (P10)** → 11. **Polish + full gate (P11)**.

- **Test-First (Phase 2) BLOCKS all HDFC parser code (Phase 3+)** — T003–T007 must exist and be RED first (Principle V).
- **US1 pipeline is the critical path** and lands the behaviors US2/US3/US4/US5 verify.

### Task-level dependencies

- T003 (live capture) precedes **T005** (monthly fixture); T004/T005 precede T006/T012.
- T006/T007 (RED tests) precede **all** implementation (T008+).
- **Chain**: (T008 `month_year_end` + T009 `read_lines_first_match`) → **T010** (`hdfc.rs`) → **T011** (FFI + lib re-exports) → **T012** (Rust green).
- T011 → **T013** (xcframework) → **T014** (Swift green). T013 before any `tuist generate`.
- T015/T016/T017 depend on T010; T018 depends on T010–T011; T019 depends on T012; T020 depends on T012.
- **T022 (full gate) depends on everything**; T021/T023 are docs/review only.

### Parallel opportunities

- **Setup**: T001 [P] + T002 [P].
- **Test-First**: T004 [P] + T005 [P] (+ T007 [P]) are different files (the two fixtures + the Swift test); T003 seeds T005; T006 edits `parity.rs` (run it alone).
- **Pipeline enablers**: **T008 [P] + T009 [P]** — two independent files (`common.rs`, `line_reader.rs`) with no interdependency; both feed T010.
- **Story verification**: T015/T016/T017 all extend `hdfc.rs`'s `#[cfg(test)]` module (**same file → sequential**, though each is an independent test group); **T018 [P]** lives in `parity.rs` and can run alongside them.
- **Polish**: T021 [P] + T023 [P] (docs + review); T022 runs the gate alone.

---

## Parallel Example: the pipeline enablers (Phase 3)

```bash
# After Phase 2 RED tests, add the two independent new-helper pieces together:
Task T008: "Add month_year_end to core/crates/kaname-core/src/statement/common.rs (port hdfc.py:56-78)"
Task T009: "Add read_lines_first_match + ?Sized to core/crates/kaname-core/src/statement/line_reader.rs (port hdfc.py:119-143)"
# Then converge: T010 (hdfc.rs: 2 configs + shared enrich + monthly '+' rule + composite)
#              → T011 (ffi.rs exports + lib.rs re-exports) → T012 (Rust green).
```

---

## Implementation Strategy

### MVP first (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 **RED** test-first anchors (capture → both fixtures → parity rows +
`period_start` → Swift) → 3. Phase 3 pipeline (T008→T012) → 4. Phase 4 bridge (T013–T014).
**STOP & VALIDATE**: both golden HDFC statements parse on-device through the **same**
`read_hdfc_statement` and the Swift suite is green. This alone is a shippable, useful slice.

### Incremental delivery

Add US2 (two-layout selection) → US3 (direction, both layouts) → US4 (metadata, both layouts) →
US5 (errored/robustness, reused) — each an independent test increment over the same pipeline. Then
lock the **guards**: US6 (both-layout parity) and US7 (inherited privacy-egress). Finish with the
full-gate run (T022).

### Story → task traceability

| Story | Delivered by | Independently verified by |
|---|---|---|
| **US1** parse | T007, T010, T011, T012, T013, T014 | T012 (Rust), T014 (Swift), T006 wrong-issuer |
| **US2** two layouts | T009 `read_lines_first_match` + T010 monthly config | **T015** (+ T009 composite unit tests) |
| **US3** direction | T010 (year-end `classify` + monthly `+` rule) | **T016** |
| **US4** metadata | T008 `month_year_end` + T010 shared `enrich` (+ reused `find_last4` anchor) | **T017** (+ T008 `month_year_end` cases) |
| **US5** errored-lines | *reused* `read_lines` seam + `truncate_chars` | **T018** |
| **US6** golden parity 🛡️ | T003, T004, T005, T006, T012 | **T019** (reusable both-layout guard) |
| **US7** privacy-egress 🛡️ | *inherited* gate + T006 determinism | **T020** |

---

## Notes

- **Test-first is mandatory** (Principle V): T003–T007 are RED before Phase 3; T012 greens the Rust
  parity (both vectors), T014 greens the Swift bridge — each has an explicit RED→GREEN verify step.
  The monthly `expected` is **captured live** (T003), never hand-derived (FR-026).
- **Faithful port** (byte-for-byte with the golden vectors): every porting task cites its exact
  `hdfc.py` lines/regex/behavior; `description_raw` is asserted **byte-for-byte** — year-end
  `"ONLINE TRF - PYMT RECD - THANK YOU"` / `"WWW EXAMPLE COM GURGAON"`, monthly
  `"EXAMPLE MERCHANT BANGALORE"` / `"CC PAYMENT RECEIVED"` (research **D10**).
- **REUSE, not rebuild**: HDFC adds only `month_year_end`, `read_lines_first_match` (+ `?Sized`),
  `hdfc.rs`, two exports, and two fixtures — everything else (records, `common`/`polarity` helpers,
  the `read_lines` seam, the UniFFI custom types, the parity harness, the privacy gate) is inherited
  unchanged (FR-020). **No new dependency** (runtime *or* dev).
- **[P]** = different files, no unfinished dependency. `[Story]` labels map each task to its slice.
- **Guards protect the whole slice**: US6 (both-layout parity) and US7 (privacy) fail the build on
  any regression to parsing behavior or egress-freedom.
- **Do not commit** — the author will review and commit.
