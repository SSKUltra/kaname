---
description: "Task list — SBI Card Credit-Card Parser (third real reader, single layout, zero new engine infra)"
---

# Tasks: Import an SBI Card Credit-Card Statement On-Device (Third Real Parser, Zero New Engine Infrastructure)

**Input**: Design documents from `/specs/004-sbi-cc-parser/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md` (D1–D9), `data-model.md`,
`contracts/engine-ffi.md`, `contracts/golden-fixture.md`, `quickstart.md`

**Tests**: REQUIRED and **TEST-FIRST** for this slice (Constitution Principle V). Authoring the
golden fixture, the failing Rust parity `Case` row (+ the `sbi_claims` accept/reject test), and the
failing Swift "core ↔ Swift SBI parse" test are all done **RED, before** the `SbiReader` code that
greens them.

**Port source of truth** (faithful, byte-for-byte with the golden vector — every porting task cites
exact `sbi_card.py` lines/regex/behavior):
`/Users/ssk/Projects/finance-tracker-phase/backend/app/services/ingestion/statement_readers/sbi_card.py`
(reusing the already-ported `_common`, `polarity`, `base`, `_line_reader` from the ICICI slice and
extended by HDFC). SBI's `expected` is the **locked characterization ground truth** from the web
engine's `test_cc_reader_characterization.py` (`_SBI_LINES`/`_SBI_TEXT`) — **no live run needed**
(`quickstart.md` §0); it was re-confirmed against the real `kaname-core` helpers (research
"Verification harness").

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: `US1`=parse · `US2`=zero-new-infra · `US3`=direction (`C`/`D`) · `US4`=metadata ·
  `US5`=errored-lines · `US6`=golden parity · `US7`=privacy-egress. Setup/Polish carry no story label.
- Exact file paths are included in every task.

## ♻️ REUSE — do NOT re-create (SBI adds only `sbi.rs` + fixture + exports + one `Case` row)

SBI plugs into the ICICI/HDFC foundations **unchanged**. This slice is the **simplest yet**: unlike
HDFC (which added `read_lines_first_match` + `month_year_end` + a monthly `+` rule), **SBI adds NO
new shared helper and NO composite** (FR-017, SC-010). Do **not** rebuild any of these:

- `statement/common.rs` — `parse_amount` (`common.rs:50`) / `parse_date` — the `DD Mon YY` format
  `"%d %b %y"` is **already present** (`common.rs:26`, commented "21 Apr 26 (SBI)"; research **D4**) /
  `find_last4(text, Some("Credit Card Number"))` **anchor** path (`common.rs:141`, already exercised
  by HDFC; research **D6/D7**).
- `statement/polarity.rs` — `classify(...)` (`polarity.rs:62`); the single-letter `C`/`D` markers are
  **already** in the tables (`CR_MARKERS` has `"C"`, `DR_MARKERS` has `"D"` — `polarity.rs:11–12`;
  research **D5**).
- `statement/base.rs` — `ParsedStatement` / `ParsedTransaction` records **unchanged**; `period_start`
  is **already a field** (`base.rs:44`, added by HDFC) + `truncate_chars` / `MAX_RAW` for
  errored-lines.
- `statement/line_reader.rs` — the `read_lines` / `claims` seam + `LineReaderConfig` trait, reused
  **verbatim** (single layout → **`read_lines` directly**, NOT the HDFC composite; research **D2**).
- `ffi.rs` — the `Decimal`/`NaiveDate` custom types + `Direction` enum (**no `uniffi.toml` change, no
  new record, no new Swift type**).
- `tests/parity.rs` — the golden-fixture parity harness (**add one `Case` row + one `claims` test,
  do NOT change the schema** — `period_start` is already present and asserted).
- The **privacy-egress gate** (`make core-privacy-audit`) and CI — inherited **unchanged**
  (**no new dependency** → byte-identical shipped `cargo tree` graph; research **D1**, plan
  Constitution Check).

**The only NEW code**: `statement/sbi.rs` (one zero-sized `SbiReader` config + its `enrich`),
**two** `#[uniffi::export]` functions (`read_sbi_statement` + `sbi_claims`), the `lib.rs` re-exports,
`pub mod sbi;` in `statement/mod.rs`, **one** golden fixture, and **one** parity `Case` row.
**No new dependency** (runtime *or* dev); **no new shared helper**; **no harness schema change**.

## ⚠️ Local gotchas (apply throughout)

- **`make core-xcframework` MUST run before `tuist generate`** (`ios-gen: core-xcframework`) — the
  generated Swift (`ios/Generated/kaname_core.swift`) + `KanameCoreFFI.xcframework` are rebuilt
  artifacts (`quickstart.md` §3/§Troubleshooting).
- **Local Xcode 26 needs an explicitly-created "iPhone 16" simulator** for `make ios-test`
  (`xcodebuild -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'`).
- Money is **`Decimal`, never `f64`**; Indian grouping is stripped and scale preserved
  (`82,900.00 → 82900.00`). Direction comes from the **terminal `C`/`D` marker** via
  `classify(desc, dir, None)`, never the amount's sign and never the description's wording (even
  though row 0's description ends in the word "CREDIT"). **No new dependency** (runtime *or* dev).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the invariants and prerequisites so every later task has a place to land and the
gates stay green. No behavior yet.

- [ ] T001 [P] Confirm the **no-new-dependency** invariant: `core/crates/kaname-core/Cargo.toml` stays **UNCHANGED** (runtime deps `regex`/`rust_decimal`/`chrono`/`serde`/`uniffi` + dev-only `serde_json` already present from the ICICI slice) — SBI adds **zero** deps (FR-025, SC-012). Create the fixtures home directory `fixtures/sbi_card/credit_card/`. Ref: plan §Summary/§Project Structure, `contracts/golden-fixture.md` §Location.
- [ ] T002 [P] Verify local prerequisites & gotchas (no code): `cargo` on PATH (`source "$HOME/.cargo/env"`); iOS targets present (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`); an **"iPhone 16" simulator** exists in Xcode 26; recall `make core-xcframework` precedes `tuist generate` (`ios-gen: core-xcframework`). Ref: `quickstart.md` §Prerequisites/§Troubleshooting.

**Checkpoint**: Fixtures home exists, no manifest change needed, toolchain ready.

---

## Phase 2: Test-First Foundation (⚠️ Principle V — author RED before ANY SBI code)

**Purpose**: Pin the on-device engine to the proven web engine **before** writing it. These are the
parity (US6) and bridge (US1) tests that **protect the whole slice**; they MUST be **RED** at the end
of this phase (`read_sbi_statement` / `sbi_claims` do not exist yet).

**⚠️ CRITICAL**: No SBI parser code (Phase 3+) may be written until T003–T005 exist and are verified failing.

- [ ] T003 [P] [US6] Author the **ported** golden vector `fixtures/sbi_card/credit_card/basic.json` — copy the **exact fixture bytes** from `contracts/golden-fixture.md` §"Exact fixture bytes to write" (do **not** hand-derive). `lines` = the two synthetic SBI rows `21 Apr 26 CARD CASHBACK CREDIT 643.00 C` and `20 May 26 APPLE INDIA STORE MUMBAI IN 82,900.00 D`; `full_text` (`\n`-joined) contains `GSTIN of SBI Card`, `Credit Card Number XXXX XXXX XXXX XX61`, `for Statement Period: 22 Apr 26 to 21 May 26`, then the two rows; `expected.rows` = `{ "2026-04-21", "643.00", Credit, INR, "CARD CASHBACK CREDIT" }` and `{ "2026-05-20", "82900.00", Debit, INR, "APPLE INDIA STORE MUMBAI IN" }`; `period_start "2026-04-22"`; `period_end "2026-05-21"`; **`card_last4 null`** (the mask `XXXX XXXX XXXX XX61` exposes only **two** trailing digits — never fabricated, research **D7**); `errored_lines []`. Amounts are **JSON strings** (re-parsed to `Decimal`, never `f64`); `82,900.00` normalizes to the string `"82900.00"` (scale preserved). `description_raw` is **byte-for-byte** — the terminal `C`/`D` marker and the amount are **not** part of it. 100% synthetic/redacted (FR-023, SC-012). Ref: `contracts/golden-fixture.md` §The SBI `basic.json` vector, `quickstart.md` §0, research **D3/D6/D7**.
- [ ] T004 [US6] Extend the parity harness `core/crates/kaname-core/tests/parity.rs` → **RED** (the **only** harness change; **NO schema/struct/assertion change** — `period_start` was already added and asserted by HDFC): `use kaname_core::{sbi_claims, read_sbi_statement, …}`; add **one** `Case` row to the existing `CASES` table — `Case { label: "SBI", parse: read_sbi_statement, rel_path: "sbi_card/credit_card/basic.json" }`; add an `sbi_claims` accept/reject test mirroring `icici_claims`/`hdfc_claims` (`sbi_claims(basic.full_text) == true`; `sbi_claims("ICICI Bank Statement") == false`; `sbi_claims("HDFC Bank Credit Cards".to_string()) == false` — FR-002, SC-002). Leave the ICICI/HDFC fixtures and `Expected`/`ExpectedRow` structs **untouched**. ⚠️ **Verify RED**: `make core-test` fails to **compile** (`read_sbi_statement`/`sbi_claims` absent). Ref: `contracts/golden-fixture.md` §Harness behavior, `data-model.md` §Fixture/harness types, research **D9**.
- [ ] T005 [P] [US1] Author the **RED** Swift bridge test `ios/Tests/SBIParseTests.swift` — "core ↔ Swift SBI parse" (`import KanameCore`, Swift Testing), mirroring `ios/Tests/ICICIParseTests.swift`/`HDFCParseTests.swift`: `readSbiStatement(lines:fullText:)` over the two golden lines → 2 `lines`; `lines[0]` = `valueDate "2026-04-21"` / `Decimal(string:"643.00", locale: en_US_POSIX)` / `.credit` / `currency "INR"` / `descriptionRaw "CARD CASHBACK CREDIT"`; `lines[1]` = `"2026-05-20"` / `Decimal(string:"82900.00")` / `.debit` / `"APPLE INDIA STORE MUMBAI IN"`; `periodStart == "2026-04-22"`; `periodEnd == "2026-05-21"`; **`cardLast4 == nil`**; `erroredLines.isEmpty`. `sbiClaims(fullText:) == true` for the SBI text and `false` for an `"ICICI Bank Statement"`/`"HDFC Bank Credit Cards"` string. Amounts compared as exact `Foundation.Decimal` value-equality (never float). ⚠️ **Verify RED**: won't build until the xcframework is regenerated with the exports in Phase 4. Ref: `contracts/engine-ffi.md` §Contract tests (Swift).

**Checkpoint**: Fixture in place; Rust parity harness RED (SBI `Case` row + `sbi_claims` test won't compile); Swift bridge test RED. Test-first satisfied — SBI parser code may now begin.

---

## Phase 3: User Story 1 — Parse an SBI statement into transactions (Priority: P1) 🎯 MVP

**Goal**: Recognize an SBI Card CC statement and return one transaction per row (date, exact amount,
direction, INR, description) — 100% on-device. Porting the reader here also **lands the behaviors**
that US2/US3/US4/US5 verify independently in Phases 5–8.

**Independent Test**: `read_sbi_statement(basic.lines, basic.full_text)` returns the two expected rows
and `sbi_claims` accepts SBI / rejects ICICI+HDFC — with no network in the parse path.

> Port order follows the plan's chain: `sbi.rs (config + enrich) → FFI exports + lib re-exports →
> green`. SBI needs **no** enabler helper (contrast HDFC's `month_year_end`/`read_lines_first_match`).

- [ ] T006 [US1] Create `core/crates/kaname-core/src/statement/sbi.rs` (and add `pub mod sbi;` to `core/crates/kaname-core/src/statement/mod.rs`, after `pub mod polarity;`) — port `sbi_card.py` wholesale, **structured identically to `icici.rs`** (one zero-sized config + `enrich` as the trait method; single layout):
  - `pub const BANK_CODE: &str = "SBI_CARD";` (`sbi_card.py:18`); `const CLAIM_MARKERS: &[&str] = &["SBI Card", "GSTIN of SBI Card"];` (`sbi_card.py:40`).
  - `static ROW_RE: LazyLock<Regex>` ported **byte-for-byte** from `_ROW_RE` (`sbi_card.py:20–23`): `^(?P<date>\d{2} [A-Za-z]{3} \d{2})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>[CD])$` — the terminal single-letter `C`/`D` marker is anchored at `$`; the non-greedy `desc` extends through a trailing "CREDIT" word because only an *amount* can follow it (research **D3**).
  - `static PERIOD_RE: LazyLock<Regex>` ported from `_PERIOD_RE` (`sbi_card.py:24–27`, case-insensitive): `(?i)Statement Period:\s*(\d{2} [A-Za-z]{3} \d{2})\s+to\s+(\d{2} [A-Za-z]{3} \d{2})`.
  - `pub struct SbiReader;` `impl LineReaderConfig for SbiReader` (mirror `icici.rs:38–62`): `bank_code()` = `"SBI_CARD"`; `claim_markers()` = `CLAIM_MARKERS`; `row_re()` = `&ROW_RE`; `direction(caps, desc)` = **reuse** `classify(desc, caps.name("dir").map(|m| m.as_str()), None)` (the exact behavior of the web's `marker_direction()` at `sbi_card.py:42`; `C→Credit`, `D→Debit`; the marker wins **before** any description-keyword check — FR-008/009, research **D5**). Uses the seam's default `date`/`desc`/`amount` group names.
  - `fn enrich(&self, statement, full_text)` (trait method, like `icici.rs:55–61`) — port `_enrich` (`sbi_card.py:30–35`): if `PERIOD_RE` matches, `statement.period_start = parse_date(g1)` and `statement.period_end = parse_date(g2)` (both via the **existing** `%d %b %y`); **always** `statement.card_last4 = find_last4(full_text, Some("Credit Card Number"))`. Produces `description_raw` `"CARD CASHBACK CREDIT"` / `"APPLE INDIA STORE MUMBAI IN"`; `card_last4 = None` for the two-digit mask (research **D6/D7**).
  - `LazyLock` both regexes (determinism, compile-once). **Reuse** `parse_date`/`parse_amount`/`find_last4`/`classify`/records unchanged — **no new shared helper** (SC-010). Ref: `data-model.md` §statement/sbi.rs, research **D1–D9**, `sbi_card.py:18–46`.
- [ ] T007 [US1] Add the UniFFI exports in `core/crates/kaname-core/src/ffi.rs` (ICICI-style **inline**, mirroring `ffi.rs:50–60`): `use crate::statement::sbi::SbiReader;` then `#[uniffi::export] pub fn read_sbi_statement(lines: Vec<String>, full_text: String) -> ParsedStatement { read_lines(&SbiReader, &lines, &full_text) }` (single layout → `read_lines` **directly**, NOT the HDFC composite — research **D2**) and `#[uniffi::export] pub fn sbi_claims(full_text: String) -> bool { claims(&SbiReader, &full_text, "SBI_CARD") }` — total functions, never throw/abort. **Reuse** the existing `Decimal`/`NaiveDate` custom types + `Direction` enum unchanged (**no `uniffi.toml` change, no new record**). Re-export both in `core/crates/kaname-core/src/lib.rs` (`pub use ffi::{hdfc_claims, icici_claims, read_hdfc_statement, read_icici_statement, read_sbi_statement, sbi_claims};`, extending the existing line) so `tests/parity.rs` and the app path reach them. Depends on T006. Ref: `contracts/engine-ffi.md` §Exported functions, research **D9**, `sbi_card.py:38–46`.
- [ ] T008 [US1] **Green the engine side**: run `make core-test` — `tests/parity.rs` (T004) now **PASSES** for the SBI vector (both rows exact incl. `description_raw` byte-for-byte; `period_start 2026-04-22`; `period_end 2026-05-21`; **`card_last4 null`**; `errored_lines` empty), determinism, and `sbi_claims` accept/reject — while **ICICI and HDFC parity stay green** (fixtures untouched) — and `make core-lint` (fmt + clippy `-D warnings`). Verify **RED→GREEN** for the Rust parity harness. Ref: `quickstart.md` §1.

**Checkpoint**: The engine parses the golden SBI statement; the Rust parity + determinism + wrong-issuer tests are green. US1 is functional on the Rust side (Swift bridge greened in Phase 4).

---

## Phase 4: UniFFI bridge — regenerate the xcframework + green the Swift test (US1)

**Goal**: Surface the two new functions to Swift and green the "core ↔ Swift SBI parse" test.

- [ ] T009 [US1] Run `make core-xcframework` to rebuild `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift` (git-ignored artifacts) now exposing `readSbiStatement` + `sbiClaims` (records reused ⇒ **no new Swift type**; `ParsedStatement.periodStart` is populated for SBI, `cardLast4` may be `nil`). ⚠️ **MUST run before `tuist generate`** (`quickstart.md` §3). Ref: `contracts/engine-ffi.md` §Stability/compatibility.
- [ ] T010 [US1] Run `make ios-test` (`ios-gen` → `core-xcframework` → `tuist generate` → `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test`) to **green** `ios/Tests/SBIParseTests.swift` (T005) — the two rows with exact `Foundation.Decimal` amounts, `.credit`/`.debit` from the `C`/`D` markers, `periodStart == "2026-04-22"`, `periodEnd == "2026-05-21"`, **`cardLast4 == nil`**, and `sbiClaims` accept/reject. ⚠️ **Local Xcode 26: create the "iPhone 16" simulator first.** Verify **RED→GREEN** for the Swift bridge test. Ref: `quickstart.md` §4.

**Checkpoint**: US1 MVP fully delivered end-to-end (Rust engine + Swift bridge). A person's SBI Card statement text → transactions, on-device.

---

## Phase 5: User Story 2 — A third bank with zero new engine infrastructure (Priority: P2)

**Goal**: Prove SBI is delivered as a **single-layout reader configuration only** — reusing the shared
date parser (`DD Mon YY`) and polarity classifier (`C`/`D`) with **no new shared helper** and **no
composite**. *(Impl landed in T006 `sbi.rs` + T007 direct `read_lines`.)*

**Independent Test**: The SBI parse plugs into the existing `read_lines(lines, full_text)` seam,
reusing `parse_date` and `classify`; a review of the change set shows **no** new/modified shared
helper in the reader subsystem.

- [ ] T011 [US2] Add reuse/plumbing unit tests in `core/crates/kaname-core/src/statement/sbi.rs` (`#[cfg(test)]`, mirroring `icici.rs`'s test module) proving **zero new infra**: `21 Apr 26` is interpreted as `2026-04-21` **through the shared `parse_date`** with no SBI-specific date code (US2-S1, SC-010 — the `%d %b %y` format already lives in `common.rs:26`); a `C`/`D` marker maps to credit/debit **through the shared `classify`** with no SBI-specific direction code (US2-S2); the reader drives the shared **`read_lines(&SbiReader, …)`** seam **directly** (single layout — it does **not** use `read_lines_first_match`, US2 / research **D2**); and a doc with no matching rows → empty `lines`, no error. Then perform the **change-set review** (US2-S3, SC-010): confirm the SBI diff is exactly `sbi.rs` + `mod.rs` (`pub mod sbi;`) + two `ffi.rs` exports + `lib.rs` re-exports + one fixture + one `parity.rs` `Case` row — and adds **no** new shared helper (contrast HDFC's `month_year_end`/`read_lines_first_match`) and **no** dependency (`Cargo.toml` unchanged). Ref: research **D1/D2/D4/D5**, spec US2, plan §Complexity Tracking.

**Checkpoint**: SBI is proven to be a pure single-layout drop-in — shared date/polarity reused, no new engine infrastructure.

---

## Phase 6: User Story 3 — Direction from the terminal `C`/`D` marker, never the amount's sign (Priority: P3)

**Goal**: Each transaction's direction reflects the statement's own terminal `C`/`D` marker — `C`
credit, `D` debit — never the amount's value and never a direction-like word in the description.
*(Impl landed in T006's `direction` = `classify(desc, dir, None)`.)*

**Independent Test**: Rows ending in `C` and rows ending in `D` classify credit/debit from the
marker, regardless of the amount and regardless of credit/debit wording in the description.

- [ ] T012 [US3] Add direction unit tests in `core/crates/kaname-core/src/statement/sbi.rs` (`#[cfg(test)]`): terminal `C` → **Credit**, terminal `D` → **Debit** (US3-S1/S2, FR-009); the **conflicting-word** case — `21 Apr 26 CARD CASHBACK CREDIT 643.00 C` is **Credit** because of the `C` marker even though the description ends in the word "CREDIT" (US3-S3, FR-008), and a fabricated row whose description contains "CREDIT" but whose terminal marker is `D` (e.g. `01 Jun 26 REFUND CREDIT ADJUSTMENT 500.00 D`) classifies **Debit** — the marker beats the wording (research **D5**); a large/"negative-looking" amount **never** changes the direction (US3-S4, FR-008, SC-004). Ref: research **D3/D5**, spec US3.

**Checkpoint**: Direction is sourced solely from the terminal `C`/`D` marker, never the amount or the description.

---

## Phase 7: User Story 4 — Statement metadata: billing period + card last-4 (absent under 4 digits) (Priority: P4)

**Goal**: Recover `period_start`/`period_end` from the `Statement Period:` line and `card_last4` from
the `Credit Card Number` anchor — and, crucially, leave `card_last4` **absent** (never fabricated)
when the mask exposes fewer than four trailing digits. *(Impl landed in T006's `enrich` + the reused
`find_last4` anchor.)*

**Independent Test**: A `Statement Period: … to …` line yields the correct start/end; the masked
`Credit Card Number XXXX XXXX XXXX XX61` yields **no** last-4; four visible digits yield the last-4;
neither present → unset.

- [ ] T013 [US4] Add metadata unit tests in `core/crates/kaname-core/src/statement/sbi.rs` (`#[cfg(test)]`, driving `enrich`/`read_lines`): `for Statement Period: 22 Apr 26 to 21 May 26` → `period_start 2026-04-22`, `period_end 2026-05-21` (US4-S1, SC-003, FR-010, both via the shared `parse_date`); the masked `Credit Card Number XXXX XXXX XXXX XX61` → **`card_last4 None`** because only two trailing digits are visible — never fabricated (US4-S2, FR-012, SC-003, research **D7**); a mask exposing four trailing digits (e.g. `Credit Card Number XXXX XXXX XXXX 1234`) → `card_last4 Some("1234")` via `find_last4(full_text, Some("Credit Card Number"))` (US4-S3, FR-011); a **missing-metadata** input (no `Statement Period` line, no masked PAN) → `period_start`/`period_end`/`card_last4` all `None` while rows are still returned (US4-S4, FR-013). Ref: research **D6/D7**, `sbi_card.py:30–35`, spec US4.

**Checkpoint**: Billing-period + card last-4 (and their principled absence) verified — the two-digit mask yields no fabricated last-4.

---

## Phase 8: User Story 5 — Malformed rows captured for review, never dropped or fatal (Priority: P5)

**Goal**: A line that looks like an SBI transaction but whose fields won't parse is captured in
`errored_lines` (raw, ≤240 codepoints), every good row is still returned, and nothing panics.
*(Behavior is **reused unchanged** from the ICICI `read_lines` seam — SBI adds no robustness code.)*

**Independent Test**: Mixed input (a good SBI row + one shape-matching but unparseable row) → the good
row returned, bad row captured, no error; non-transaction lines ignored silently.

- [ ] T014 [P] [US5] Add an SBI errored-line/robustness test in `core/crates/kaname-core/tests/parity.rs` (mirroring `malformed_row_is_captured_not_fatal`): a line matching the SBI shape but with an **unparseable date** (e.g. `99 Zzz 99 SOME MERCHANT 10.00 C`) → captured in `errored_lines` (raw, truncated to 240 codepoints via the reused `truncate_chars`), the valid row (`21 Apr 26 CARD CASHBACK CREDIT 643.00 C`) still returned, **no panic** (FR-014, SC-006); header/summary/balance/total lines → ignored (no transaction, no error). Note in the test that this exercises the **reused** `read_lines` errored-line path (`line_reader.rs`) — SBI adds no robustness code. [P] (different file from the `sbi.rs` test cluster). Ref: spec US5, `line_reader.rs` read loop.

**Checkpoint**: Parser is resilient — one bad row never takes down the import.

---

## Phase 9: User Story 6 — Proven byte-for-byte against a golden fixture (Priority: P6) 🛡️ whole-slice guard

**Goal**: Make the parity harness the **reusable, regression-proof** guarantee that pins SBI (and
every future reader) to the web engine — this time proving the harness accepts a **third bank as a
one-fixture + one-row addition**. *(Fixture T003; harness `Case` row T004; greened T008.)*

**Independent Test**: The harness over the ported SBI vector matches expected output exactly, and
re-running is stable.

- [ ] T015 [US6] Finalize `core/crates/kaname-core/tests/parity.rs` as the **reusable whole-slice guard**: confirm the SBI `Case` calls `read_sbi_statement`; field-by-field parity — dates, exact `Decimal` amounts (scale preserved: `"643.00"`, `"82900.00"`), directions (`Credit`/`Debit` from the `C`/`D` markers), currency `INR`, `description_raw` **byte-for-byte** (`"CARD CASHBACK CREDIT"` / `"APPLE INDIA STORE MUMBAI IN"`), plus `period_start 2026-04-22`, `period_end 2026-05-21`, **`card_last4 null`**, `errored_lines []` (SC-001/003/009); the determinism **re-run** covers the SBI vector (SC-008); the fixture is **100% synthetic** (fabricated merchants/amounts, masked PAN `…XX61`; SC-012); and confirm the schema stayed **stable through `period_start`** — SBI needed **only one `Case` row** (no struct/assertion change), proving a new line-reader bank is a **one-fixture + one-row** addition. Leave the ICICI/HDFC fixtures untouched. Ref: `contracts/golden-fixture.md` §Harness behavior/§Adding a future fixture, research **D9**, plan §Complexity Tracking.

**Checkpoint**: Parity is an enforced guarantee for SBI and the harness stays reusable — a third bank landed as one row.

---

## Phase 10: User Story 7 — Privacy gate: zero network in the parse path (Priority: P7) 🛡️ inherited guard

**Goal**: Prove the SBI parse path is egress-free — **structurally** (no networking crate can even
link) and **behaviorally** (determinism) — using the **inherited** gate with **zero** new config.
*(No new script/CI: SBI adds no dependency, so the audit is byte-identical.)*

**Independent Test**: `make core-privacy-audit` passes only when zero networking crates are in the
shipped graph; the determinism test passes; no telemetry/analytics anywhere in the parse path.

- [ ] T016 [US7] Confirm the inherited privacy-egress gate stays **GREEN with ZERO changes**: run `make core-privacy-audit` → `privacy-egress: OK (no networking crate in kaname-core deps)` — SBI adds **no dependency** (runtime *or* dev), so `cargo tree -p kaname-core -e normal` is byte-identical (`Cargo.toml` unchanged — FR-019/025, SC-007/012); the determinism/purity assertion over the SBI vector lives in `tests/parity.rs` (T004, FR-016, SC-008); confirm **no** telemetry/analytics/advertising/crash-reporter enters the parse path and **no** network entitlement/ATS is added app-side (`ios/Project.swift` `infoPlist` unchanged) (FR-020/021). Ref: research **D1**, `quickstart.md` §2, spec US7.

**Checkpoint**: Privacy-egress remains a first-class, structurally- and behaviorally-enforced gate covering SBI.

---

## Phase 11: Polish & Cross-Cutting — full iOS Local Verification Gate green

**Purpose**: Prove the whole slice is merge-ready (SC-011) and review the constitution guarantees.

- [ ] T017 [P] Light docs alignment (no behavior change): note the **third real parser** — a **single-layout drop-in with zero new shared helpers** — where the engine/build is described (`README.md` and/or `specs/004-sbi-cc-parser/quickstart.md`); ensure `fixtures/README.md` reflects the SBI vector under `fixtures/sbi_card/credit_card/`; if convenient, refresh the `statement/mod.rs` doc comment that lists issuers so it reflects SBI landing. No stale wording.
- [ ] T018 **Run the full iOS Local Verification Gate green**, in order: `make core-lint && make core-test && make core-privacy-audit && make lint && make ios-gen && make ios-test`. ⚠️ `make core-xcframework` is rebuilt before `tuist generate` (via `ios-gen`); local Xcode 26 requires the **"iPhone 16"** simulator. This is the SC-011 / FR-026 merge gate. Ref: `quickstart.md` §5.
- [ ] T019 [P] Final constitution review (no code change): **NO new dependency** (runtime *or* dev) — `Cargo.toml` unchanged; **NO new shared helper** and **NO composite** (SC-010 — the diff is `sbi.rs` + `mod.rs` + two exports + `lib.rs` re-exports + one fixture + one `Case` row); no secrets / network entitlements / copyleft (GPL/AGPL/LGPL) deps (FR-025, SC-012); all fixture/test data synthetic (SC-012); money never `f64` (amounts `Decimal`, Indian grouping stripped, scale preserved); direction from the terminal `C`/`D` marker, never the amount sign or the description; **`card_last4` is `None`** for the two-digit mask (never fabricated); ICICI/HDFC fixtures and the harness schema untouched (backward-compatible). Confirm against `git diff` before handoff. Ref: spec FR-025/SC-010/SC-012, plan §Constitution Check.

---

## Dependencies & Execution Order

### Phase order

1. **Setup (P1)** → 2. **Test-First Foundation (P2, RED)** → 3. **US1 pipeline (P3)** →
4. **Bridge/Swift green (P4)** → 5–8. **US2/US3/US4/US5 verification (P5–P8)** →
9. **US6 parity guard (P9)** → 10. **US7 privacy guard (P10)** → 11. **Polish + full gate (P11)**.

- **Test-First (Phase 2) BLOCKS all SBI parser code (Phase 3+)** — T003–T005 must exist and be RED first (Principle V).
- **US1 pipeline is the critical path** and lands the behaviors US2/US3/US4/US5 verify.

### Task-level dependencies

- T003 (fixture) precedes T004 (parity `Case` row) and T008 (green).
- T004/T005 (RED tests) precede **all** implementation (T006+).
- **Chain**: T006 (`sbi.rs` + `mod.rs`) → T007 (FFI exports + `lib.rs` re-exports) → T008 (Rust green).
- T007 → T009 (xcframework) → T010 (Swift green). T009 before any `tuist generate`.
- T011/T012/T013 depend on T006; T014 depends on T004 (harness) + T007 (exports); T015 depends on T008; T016 depends on T008.
- **T018 (full gate) depends on everything**; T017/T019 are docs/review only.

### Parallel opportunities

- **Setup**: T001 [P] + T002 [P].
- **Test-First**: T003 [P] (fixture) + T005 [P] (Swift test) are different files; T004 edits `parity.rs` (run it alone; it depends on T003's path existing).
- **Story verification**: T011/T012/T013 all extend `sbi.rs`'s `#[cfg(test)]` module (**same file → sequential**, though each is an independent test group); **T014 [P]** lives in `parity.rs` and can run alongside them.
- **Polish**: T017 [P] + T019 [P] (docs + review); T018 runs the gate alone.

---

## Parallel Example: the Test-First Foundation (Phase 2)

```bash
# Author the two independent RED artifacts together (different files):
Task T003: "Author fixtures/sbi_card/credit_card/basic.json (exact bytes from contracts/golden-fixture.md)"
Task T005: "Author ios/Tests/SBIParseTests.swift (RED core ↔ Swift SBI parse)"
# Then T004 edits tests/parity.rs (one Case row + sbi_claims test) → verify RED (won't compile).
# Converge on the pipeline: T006 (sbi.rs + mod.rs) → T007 (ffi.rs exports + lib.rs re-exports) → T008 (Rust green).
```

---

## Implementation Strategy

### MVP first (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 **RED** test-first anchors (fixture → parity `Case` row + `sbi_claims`
→ Swift) → 3. Phase 3 pipeline (T006→T008) → 4. Phase 4 bridge (T009–T010).
**STOP & VALIDATE**: the golden SBI statement parses on-device through `read_sbi_statement` and the
Swift suite is green. This alone is a shippable, useful slice.

### Incremental delivery

Add US2 (zero-new-infra proof) → US3 (direction from `C`/`D`) → US4 (metadata incl. absent last-4) →
US5 (errored/robustness, reused) — each an independent test increment over the same reader. Then lock
the **guards**: US6 (golden parity) and US7 (inherited privacy-egress). Finish with the full-gate
run (T018).

### Story → task traceability

| Story | Delivered by | Independently verified by |
|---|---|---|
| **US1** parse | T005, T006, T007, T008, T009, T010 | T008 (Rust), T010 (Swift), T004 wrong-issuer |
| **US2** zero-new-infra | T006 `sbi.rs` (config) + T007 direct `read_lines` | **T011** (reuse tests + change-set review) |
| **US3** direction (`C`/`D`) | T006 `direction = classify(desc, dir, None)` | **T012** |
| **US4** metadata | T006 `enrich` (+ reused `find_last4` anchor) | **T013** |
| **US5** errored-lines | *reused* `read_lines` seam + `truncate_chars` | **T014** |
| **US6** golden parity 🛡️ | T003, T004, T008 | **T015** (reusable one-row guard) |
| **US7** privacy-egress 🛡️ | *inherited* gate + T004 determinism | **T016** |

---

## Notes

- **Test-first is mandatory** (Principle V): T003–T005 are RED before Phase 3; T008 greens the Rust
  parity, T010 greens the Swift bridge — each has an explicit RED→GREEN verify step. SBI's `expected`
  is the **locked characterization ground truth** (no live capture needed — `quickstart.md` §0).
- **Faithful port** (byte-for-byte with the golden vector): every porting task cites its exact
  `sbi_card.py` lines/regex/behavior; `description_raw` is asserted **byte-for-byte** —
  `"CARD CASHBACK CREDIT"` / `"APPLE INDIA STORE MUMBAI IN"`; `card_last4` is **`None`** because the
  mask `XXXX XXXX XXXX XX61` exposes only two trailing digits (research **D3/D6/D7**).
- **REUSE, not rebuild**: SBI adds only `sbi.rs`, two exports, `lib.rs` re-exports, `pub mod sbi;`,
  one fixture, and one `Case` row — everything else (records, `common`/`polarity` helpers, the
  `read_lines` seam, the UniFFI custom types, the parity harness, the privacy gate) is inherited
  unchanged (FR-017). **No new dependency** (runtime *or* dev); **no new shared helper**; **no
  composite** (contrast HDFC).
- **[P]** = different files, no unfinished dependency. `[Story]` labels map each task to its slice.
- **Guards protect the whole slice**: US6 (golden parity) and US7 (privacy) fail the build on any
  regression to parsing behavior or egress-freedom.
- **Do not commit** — the author will review and commit.
