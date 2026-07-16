---
description: "Task list — Federal Bank (Scapia) Credit-Card Parser (fifth & final reader, single layout, zero new engine infra)"
---

# Tasks: Import a Federal Bank / Scapia Credit-Card Statement On-Device (Fifth & Final Parser — the Most Distinctive Layout, Zero New Engine Infrastructure)

**Input**: Design documents from `/specs/006-federal-cc-parser/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md` (D1–D10), `data-model.md`,
`contracts/engine-ffi.md`, `contracts/golden-fixture.md`, `quickstart.md`

**Tests**: REQUIRED and **TEST-FIRST** for this slice (Constitution Principle V). Authoring the golden
fixture, the failing Rust parity `Case` row (+ the `federal_claims` accept/reject test), and the failing
Swift "core ↔ Swift Federal parse" test are all done **RED, before** the `FederalReader` code that
greens them (FR-025).

**Port source of truth** (faithful, byte-for-byte with the golden vector — every porting task cites
exact `federal_scapia.py` regex/behavior):
`/Users/ssk/Projects/finance-tracker-phase/backend/app/services/ingestion/statement_readers/federal_scapia.py`
(reusing the already-ported `common`, `polarity`, `base`, `line_reader` from the ICICI slice, extended
by HDFC, and reused verbatim by SBI/Yes). Federal's `expected` is the **locked characterization ground
truth** from the web engine's Federal vector — **no live run needed** (`quickstart.md` §0); it was
re-confirmed by running the proposed `FederalReader` against the real `kaname-core` helpers (research
"Verification harness").

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: `US1`=parse · `US2`=zero-new-infra · `US3`=direction (leading `+`) · `US4`=metadata
  (cycle + un-anchored last-4) · `US5`=errored-lines · `US6`=golden parity · `US7`=privacy-egress.
  Setup/Polish/Ship carry no story label.
- Exact file paths are included in every task.

> **Note (this slice commits nothing during generation).** `/speckit.tasks` only writes this file.
> The two commits + PR #6 + merge are encoded as the final **Phase 12: Ship** and are executed by the
> implementer **after** every gate is green (per the requester's step 7).

## ♻️ REUSE — do NOT re-create (Federal adds only `federal.rs` + fixture + exports + one `Case` row)

Federal plugs into the ICICI/HDFC/SBI/Yes foundations **unchanged**. Like SBI (`004`) and Yes (`005`),
this is a **clean single-layout drop-in**: it adds **NO new shared helper and NO composite** (FR-018,
SC-011). It is the **third such drop-in** and **completes the credit-card set** (ICICI, HDFC, SBI, Yes,
Federal). Do **not** rebuild any of these:

- `statement/common.rs` — `parse_amount` (`common.rs:50`) / `parse_date` (`common.rs:58`). **Both**
  Federal date formats are **already present** and **already annotated for this reader**: the row format
  `"%d-%m-%Y",  // 24-04-2026 (Scapia/Federal)` (`common.rs:24`, research **D4**) and the space-stripped
  billing-cycle format `"%d%b%Y",    // 20Apr2026 (Scapia billing cycle, space-stripped)`
  (`common.rs:31`, research **D5**). `find_last4(text, None)` — the **un-anchored** whole-text path
  (`common.rs:141`/`:155`, already exercised by ICICI; research **D7**).
- `statement/polarity.rs` — `classify(...)` (`polarity.rs:62`), used **only for the fallback** as
  `classify(desc, None, None)`; the `CREDIT_KEYWORDS` table (`polarity.rs:15–26`) already contains
  `refund`/`reversal`/`cashback`/`payment received` (research **D6**). Federal does **NOT** use the
  `Dr`/`Cr` marker path (there is **no** such column) — the leading-`+` test is Federal-local.
- `statement/base.rs` — `ParsedStatement` / `ParsedTransaction` records **unchanged**; `period_start`
  (`base.rs:44`), `period_end` (`base.rs:45`), and `card_last4` (`base.rs:46`) are **already** fields;
  `MAX_RAW` (`base.rs:15`) + `truncate_chars` (`base.rs:18`) back the errored-line path. **No
  `printed_total_*` fields** (there is **no** reconciliation carve-out — research **D10**).
- `statement/line_reader.rs` — the `read_lines` / `claims` seam + `LineReaderConfig` trait
  (`line_reader.rs:14–32`), reused **verbatim** (single layout → **`read_lines` directly**, NOT the HDFC
  `read_lines_first_match` composite at `line_reader.rs:95`; research **D2**). `direction` receives the
  **full `Captures`** (`line_reader.rs:19`), so the extra `sign` group needs **no seam change**; the
  default `date`/`desc`/`amount` group names (`line_reader.rs:23–31`) match the row regex; the
  errored-line `truncate_chars`/`MAX_RAW` path is reused as-is (US5).
- `ffi.rs` — the `Decimal`/`NaiveDate` custom types (`ffi.rs:21–32`) + `Direction` enum (**no
  `uniffi.toml` change, no new record, no new Swift type**).
- `tests/parity.rs` — the golden-fixture parity harness (**add one `Case` row + one `claims` test, do
  NOT change the schema** — `period_start` is already present with `#[serde(default)]` and asserted:
  `parity.rs:30–31` / `:112–116`).
- The **privacy-egress gate** (`make core-privacy-audit`) and CI — inherited **unchanged** (**no new
  dependency** → byte-identical shipped `cargo tree` graph; research **D1**, plan Constitution Check).

**The only NEW code**: `statement/federal.rs` (one zero-sized `FederalReader` config + its `enrich` =
cycle + **un-anchored** last-4), **two** `#[uniffi::export]` functions (`read_federal_statement` +
`federal_claims`), the `lib.rs` re-exports, `pub mod federal;` in `statement/mod.rs`, **one** golden
fixture, and **one** parity `Case` row. **No new dependency** (runtime *or* dev); **no new shared
helper**; **no harness schema change**.

## ✅ No reconciliation carve-out (unlike Yes) — research D10, FR-018

Unlike the Yes port (which had to **drop** the web reader's printed-total scrape), Federal's web
`_enrich` is **already** cycle + last-4 only — there are **no** `printed_total_*` regexes/assignments in
`federal_scapia.py`. The port is therefore a **1:1 mechanical match with nothing to omit and nothing to
add**; the Rust `ParsedStatement` already carries exactly `period_start`/`period_end`/`card_last4`. (A
reviewer expecting a Yes-style carve-out should see there isn't one — Federal is even simpler.)

## ⚠️ Local gotchas (apply throughout)

- **`make core-xcframework` MUST run before `tuist generate`** (`ios-gen: core-xcframework`,
  `Makefile:32`) — the generated Swift (`ios/Generated/kaname_core.swift`) + `KanameCoreFFI.xcframework`
  are rebuilt artifacts (`quickstart.md` §3/§Troubleshooting).
- **Local Xcode needs an explicitly-created "iPhone 16" simulator** for `make ios-test`
  (`xcodebuild -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'`).
- **Editor must preserve UTF-8**: the fixture, the Swift test, and the `federal.rs` row regex all embed
  the **middle dot U+00B7** (`·`) and the **rupee sign U+20B9** (`₹`) — do **not** let an editor rewrite
  them to ASCII or `\u`-escapes. The file is UTF-8 (research **D3**, `contracts/golden-fixture.md`
  §Character encoding).
- Money is **`Decimal`, never `f64`**; the rupee glyph, any leading `+`, and Indian grouping are
  stripped and scale is preserved (`+₹324.45 → 324.45`, `₹2,353.13 → 2353.13`). **No new dependency**
  (runtime *or* dev).
- **Direction** comes from Scapia's **leading `+`** (`+` → Credit) and, when absent,
  `classify(desc, None, None)` — **never** the amount's sign/magnitude, and Federal has **no** `Dr`/`Cr`
  column (research **D6**).
- **`card_last4` is `"4836"`** here: the fully-masked, **anchor-less** PAN `XXXXXXXXXXXX4836` exposes
  four trailing digits, so the **un-anchored** `find_last4(full_text, None)` recovers `"4836"` with no
  Federal-specific code (research **D7**; the parity contrast vs SBI's `null`, matching Yes's four-digit
  recovery).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the invariants and prerequisites so every later task has a place to land and the
gates stay green. No behavior yet.

- [ ] T001 [P] Confirm the **no-new-dependency** invariant: `core/crates/kaname-core/Cargo.toml` stays **UNCHANGED** (runtime deps `regex`/`rust_decimal`/`chrono`/`serde`/`uniffi` + dev-only `serde_json` already present from the ICICI slice) — Federal adds **zero** deps (FR-026, SC-014). Create the fixtures home directory `fixtures/federal/credit_card/`. Ref: plan §Summary/§Project Structure, `contracts/golden-fixture.md` §Location.
- [ ] T002 [P] Verify local prerequisites & gotchas (no code): `cargo` on PATH (`source "$HOME/.cargo/env"`); iOS targets present (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`); an **"iPhone 16" simulator** exists in Xcode; recall `make core-xcframework` precedes `tuist generate` (`ios-gen: core-xcframework`, `Makefile:32`); confirm the editor preserves the **U+00B7** (`·`) and **U+20B9** (`₹`) bytes. Ref: `quickstart.md` §Prerequisites/§Troubleshooting.

**Checkpoint**: Fixtures home exists, no manifest change needed, toolchain ready.

---

## Phase 2: Test-First Foundation (⚠️ Principle V — author RED before ANY Federal code)

**Purpose**: Pin the on-device engine to the proven web engine **before** writing it. These are the
parity (US6) and bridge (US1) tests that **protect the whole slice**; they MUST be **RED** at the end of
this phase (`read_federal_statement` / `federal_claims` do not exist yet).

**⚠️ CRITICAL**: No Federal parser code (Phase 3+) may be written until T003–T005 exist and are verified failing.

- [ ] T003 [P] [US6] Author the **ported** golden vector `fixtures/federal/credit_card/basic.json` — copy the **exact fixture bytes** from `contracts/golden-fixture.md` §"Exact fixture bytes to write" (do **not** hand-derive). Use the **actual** middle dot **U+00B7** (`·`) and rupee sign **U+20B9** (`₹`) characters — never ASCII or `\u` escapes. `lines` = the two synthetic Federal rows `29-04-2026·16:18 Billpayment Payment +₹324.45` and `24-04-2026·06:03 ExampleMerchantTokyo ₹2,353.13`; `full_text` (`\n`-joined) = `Scapia by Federal Bank\nXXXXXXXXXXXX4836 20Apr2026-19May2026\n` + the two rows; `expected.rows` = `{ "2026-04-29", "324.45", Credit, INR, "Billpayment Payment" }` and `{ "2026-04-24", "2353.13", Debit, INR, "ExampleMerchantTokyo" }`; `period_start "2026-04-20"`; `period_end "2026-05-19"`; **`card_last4 "4836"`** (the fully-masked PAN `XXXXXXXXXXXX4836` recovered by the **un-anchored** `find_last4`, research **D7**); `errored_lines []`. Amounts are **JSON strings** (re-parsed to `Decimal`, never `f64`); `+₹324.45`/`₹2,353.13` normalize to `"324.45"`/`"2353.13"` (₹, leading `+`, and the Indian comma stripped; scale preserved). `description_raw` is **byte-for-byte** — the `HH:MM` time, the `+`, and the `₹` are **not** part of it (US1-AC2/AC3, research **D3**). 100% synthetic/redacted (FR-024, SC-002). Ref: `contracts/golden-fixture.md` §The Federal `basic.json` vector, `quickstart.md` §0, research **D3/D7/D8/D10**.
- [ ] T004 [US6] Extend the parity harness `core/crates/kaname-core/tests/parity.rs` → **RED** (the **only** harness change; **NO schema/struct/assertion change** — `period_start` was already added with `#[serde(default)]` and asserted, `parity.rs:30–31`/`:112–116`): extend `use kaname_core::{…}` (`parity.rs:12–15`) to add `federal_claims, read_federal_statement`; add **one** `Case` row to the existing `CASES` table (`parity.rs:54–80`, after the Yes case at `:75–79`) — `Case { label: "Federal", parse: read_federal_statement, rel_path: "federal/credit_card/basic.json" }`; add a `federal_claims_accepts_own_document_and_rejects_others` test mirroring `yes_claims_accepts_own_document_and_rejects_others` (`parity.rs:184–192`): `federal_claims(basic.full_text) == true`; and `== false` for `"ICICI Bank Statement"`, `"HDFC Bank Credit Cards"`, `"GSTIN of SBI Card"`, `"YES BANK KLICK"` (FR-002, SC-002, research **D9**, `contracts/engine-ffi.md` §Contract tests). Leave the ICICI/HDFC/SBI/Yes fixtures and the `Expected`/`ExpectedRow`/`Case` structs (`parity.rs:19–52`) **untouched**. ⚠️ **Verify RED**: `make core-test` fails to **compile** (`read_federal_statement`/`federal_claims` absent). Ref: `contracts/golden-fixture.md` §Harness behaviour, `data-model.md` §Fixture/harness types, research **D9**.
- [ ] T005 [P] [US1] Author the **RED** Swift bridge test `ios/Tests/FederalParseTests.swift` — "core ↔ Swift Federal parse" (`import KanameCore`, Swift Testing), mirroring `ios/Tests/YesParseTests.swift`: build `lines`/`fullText` with `[...].joined(separator: "\n")` (using the real `·` U+00B7 and `₹` U+20B9); `readFederalStatement(lines:fullText:)` over the two golden lines → 2 `lines`; `lines[0]` = `valueDate "2026-04-29"` / `Decimal(string: "324.45", locale: Locale(identifier: "en_US_POSIX"))` / `.credit` / `currency "INR"` / `descriptionRaw "Billpayment Payment"`; `lines[1]` = `"2026-04-24"` / `Decimal(string: "2353.13", …)` / `.debit` / `"ExampleMerchantTokyo"`; `periodStart == "2026-04-20"`; `periodEnd == "2026-05-19"`; **`cardLast4 == "4836"`**; `erroredLines.isEmpty`. Use `try #require(statement.lines.first)` for the first row (mirroring `YesParseTests`). `federalClaims(fullText:) == true` for the Federal text and `false` for an `"ICICI Bank Statement"` string. Amounts compared as exact `Foundation.Decimal` value-equality (never float). ⚠️ **Verify RED**: won't build until the xcframework is regenerated with the exports in Phase 4. Ref: `contracts/engine-ffi.md` §Contract tests (Swift), `ios/Tests/YesParseTests.swift`.

**Checkpoint**: Fixture in place; Rust parity harness RED (Federal `Case` row + `federal_claims` test won't compile); Swift bridge test RED. Test-first satisfied — Federal parser code may now begin.

---

## Phase 3: User Story 1 — Parse a Federal statement into transactions (Priority: P1) 🎯 MVP

**Goal**: Recognize a Scapia / Federal Bank CC statement and return one transaction per row (date, exact
amount, direction, INR, description) — 100% on-device. Porting the reader here also **lands the
behaviors** that US2/US3/US4/US5 verify independently in Phases 5–8.

**Independent Test**: `read_federal_statement(basic.lines, basic.full_text)` returns the two expected
rows and `federal_claims` accepts Federal / rejects ICICI+HDFC+SBI+Yes — with no network in the parse path.

> Port order follows the plan's chain: `federal.rs (config + enrich) → FFI exports + lib re-exports →
> green`. Federal needs **no** enabler helper (contrast HDFC's `month_year_end`/`read_lines_first_match`);
> it is structured **identically to `sbi.rs`/`yes.rs`**.

- [ ] T006 [US1] Create `core/crates/kaname-core/src/statement/federal.rs` (and add `pub mod federal;` to `core/crates/kaname-core/src/statement/mod.rs` **between** `pub mod common;` (`mod.rs:10`) and `pub mod hdfc;` (`mod.rs:11`), keeping alphabetical order) — port `federal_scapia.py` wholesale, **structured identically to `sbi.rs`/`yes.rs`** (one zero-sized config + `enrich` as the trait method; single layout):
  - `pub const BANK_CODE: &str = "FEDERAL";` (research **D9**); `const CLAIM_MARKERS: &[&str] = &["Scapia", "Federal Bank"];` — **two** markers (a faithful port, research **D9**).
  - `static ROW_RE: LazyLock<Regex>` ported **byte-for-byte** from `_ROW_RE` (a **raw UTF-8** literal `r"…₹…"` so the `₹` is a literal char): `^(?P<date>\d{2}-\d{2}-\d{4}).\d{2}:\d{2}\s+(?P<desc>.+?)\s+(?P<sign>\+)?₹(?P<amount>[\d,]+\.\d{2})$` — the **unescaped `.`** after the date matches the middot separator **encoding-robustly** (Rust `regex`'s default `.` = any single non-newline scalar, incl. U+00B7, FR-004/SC-005); the `HH:MM` time is consumed by `\d{2}:\d{2}` and never enters `desc` (FR-005); the literal `₹` (U+20B9) precedes and is **excluded** from `amount`; the optional leading `+` is captured as `sign` (research **D3**).
  - `static CYCLE_RE: LazyLock<Regex>` ported from `_CYCLE_RE`: `(\d{1,2}[A-Za-z]{3}\d{4})\s*-\s*(\d{1,2}[A-Za-z]{3}\d{4})` — matches the space-stripped range `20Apr2026-19May2026` (research **D5**).
  - `pub struct FederalReader;` `impl LineReaderConfig for FederalReader` (mirror `sbi.rs:38–62`): `bank_code()` = `"FEDERAL"`; `claim_markers()` = `CLAIM_MARKERS`; `row_re()` = `&ROW_RE`. Uses the seam's default `date`/`desc`/`amount` group names (`line_reader.rs:23–31`).
  - `fn direction(&self, caps: &Captures<'_>, description: &str) -> Direction` — **Federal-local** (ported from the web `_direction`, research **D6**): `if caps.name("sign").map(|m| m.as_str()) == Some("+") { Direction::Credit } else { classify(description, None, None) }`. This is the **same in-reader pattern `hdfc.rs`'s `HdfcMonthly::direction` uses** (`hdfc.rs:109–118`, which inspects a leading-`+` capture) — **not** the shared `Dr`/`Cr` marker path (Scapia has no such column). The amount's value/sign is **never** consulted (FR-010/011, SC-004).
  - `fn enrich(&self, statement: &mut ParsedStatement, full_text: &str)` (trait method, like `sbi.rs:55–61`) — port `_enrich` (research **D10**), **cycle + last-4 ONLY**: if `CYCLE_RE` matches, `statement.period_start = parse_date(&caps[1])` and `statement.period_end = parse_date(&caps[2])` (both via the **existing** `%d%b%Y`, `common.rs:31`); **always** `statement.card_last4 = find_last4(full_text, None)` — **un-anchored** (`common.rs:141`; the masked PAN has no textual label, research **D7**). Produces `card_last4 = Some("4836")` for `XXXXXXXXXXXX4836`.
  - `use` imports mirror `sbi.rs:8–16`: `std::sync::LazyLock`; `regex::{Captures, Regex}`; `crate::model::Direction`; `crate::statement::base::ParsedStatement`; `crate::statement::common::{find_last4, parse_date}`; `crate::statement::line_reader::LineReaderConfig`; `crate::statement::polarity::classify`.
  - `LazyLock` both regexes (determinism, compile-once). **Reuse** `parse_date`/`parse_amount`/`find_last4`/`classify`/records unchanged — **no new shared helper** (SC-011). Ref: `data-model.md` §statement/federal.rs, research **D1–D10**, `sbi.rs:1–62`, `yes.rs:1–62`, `hdfc.rs:109–118`.
- [ ] T007 [US1] Add the UniFFI exports in `core/crates/kaname-core/src/ffi.rs` (ICICI/SBI/Yes-style **inline**, mirroring `ffi.rs:52–62` and `ffi.rs:92–103`): `use crate::statement::federal::FederalReader;` (alongside `ffi.rs:12`/`:15`) then `#[uniffi::export] pub fn read_federal_statement(lines: Vec<String>, full_text: String) -> ParsedStatement { read_lines(&FederalReader, &lines, &full_text) }` (single layout → `read_lines` **directly**, NOT the HDFC composite — research **D2**) and `#[uniffi::export] pub fn federal_claims(full_text: String) -> bool { claims(&FederalReader, &full_text, "FEDERAL") }` — total functions, never throw/abort (`read_lines`/`claims` imported at `ffi.rs:13`). **Reuse** the existing `Decimal`/`NaiveDate` custom types + `Direction` enum unchanged (**no `uniffi.toml` change, no new record**). Re-export both in `core/crates/kaname-core/src/lib.rs` — extend the existing `pub use ffi::{…}` block (`lib.rs:28–31`) to add `federal_claims, read_federal_statement` (rustfmt orders them) — so `tests/parity.rs` and the app path reach them. Depends on T006. Ref: `contracts/engine-ffi.md` §Exported functions, research **D9**.
- [ ] T008 [US1] **Green the engine side**: run `make core-fmt` (rustfmt), then `make core-test` — `tests/parity.rs` (T004) now **PASSES** for the Federal vector (both rows exact incl. `description_raw` byte-for-byte; `period_start 2026-04-20`; `period_end 2026-05-19`; **`card_last4 "4836"`**; `errored_lines` empty), determinism, and `federal_claims` accept/reject — while **ICICI/HDFC/SBI/Yes parity stay green** (fixtures untouched) — and `make core-lint` (fmt `--check` + clippy `-D warnings`). Verify **RED→GREEN** for the Rust parity harness. Ref: `quickstart.md` §1.

**Checkpoint**: The engine parses the golden Federal statement; the Rust parity + determinism + wrong-issuer tests are green. US1 is functional on the Rust side (Swift bridge greened in Phase 4).

---

## Phase 4: UniFFI bridge — regenerate the xcframework + green the Swift test (US1)

**Goal**: Surface the two new functions to Swift and green the "core ↔ Swift Federal parse" test.

- [ ] T009 [US1] Run `make core-xcframework` to rebuild `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift` (git-ignored artifacts) now exposing `readFederalStatement` + `federalClaims` (records reused ⇒ **no new Swift type**; `ParsedStatement.periodStart` is populated for Federal and `cardLast4 == "4836"`). ⚠️ **MUST run before `tuist generate`** (`quickstart.md` §3, `Makefile:32`). Ref: `contracts/engine-ffi.md` §Stability/compatibility.
- [ ] T010 [US1] Run `make ios-test` (`ios-gen` → `core-xcframework` → `tuist generate` → `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test`) to **green** `ios/Tests/FederalParseTests.swift` (T005) — the two rows with exact `Foundation.Decimal` amounts, `.credit` from the leading `+` / `.debit` from the classifier default, `periodStart == "2026-04-20"`, `periodEnd == "2026-05-19"`, **`cardLast4 == "4836"`**, and `federalClaims` accept/reject. ⚠️ **Local Xcode: create the "iPhone 16" simulator first.** Verify **RED→GREEN** for the Swift bridge test. Ref: `quickstart.md` §4.

**Checkpoint**: US1 MVP fully delivered end-to-end (Rust engine + Swift bridge). A person's Scapia / Federal Bank statement text → transactions, on-device.

---

## Phase 5: User Story 2 — The most distinctive layout with zero new engine infrastructure (Priority: P2)

**Goal**: Prove Federal — despite being the **most distinctive** of the five layouts — is delivered as a
**single-layout reader configuration only** — reusing the shared date parser (`%d-%m-%Y` **and**
`%d%b%Y`) and the shared polarity classifier with **no new shared helper** and **no composite**. *(Impl
landed in T006 `federal.rs` + T007 direct `read_lines`.)*

**Independent Test**: The Federal parse plugs into the existing `read_lines(lines, full_text)` seam,
reusing `parse_date` and `classify`; a review of the change set shows **no** new/modified shared helper
in the reader subsystem.

- [ ] T011 [US2] Add reuse/plumbing unit tests in `core/crates/kaname-core/src/statement/federal.rs` (`#[cfg(test)]`, mirroring `sbi.rs`'s test module `sbi.rs:64–105` and `yes.rs:64–102`, driving `read_lines(&FederalReader, …)`) proving **zero new infra**: `29-04-2026` is interpreted as `2026-04-29` **through the shared `parse_date`** with no Federal-specific date code (US2-AC1, SC-011 — `%d-%m-%Y` already lives in `common.rs:24`, commented "Scapia/Federal"); `20Apr2026`/`19May2026` are interpreted **through the shared `parse_date`** via `%d%b%Y` with no Federal-specific date code (US2-AC2 — already in `common.rs:31`); the reader drives the shared **`read_lines(&FederalReader, …)`** seam **directly** (single layout — it does **not** use `read_lines_first_match`, US2 / research **D2**); and a doc with no matching rows → empty `lines`, no error (edge case, FR-007). Then perform the **change-set review** (US2-AC3, SC-011): confirm the Federal diff is exactly `federal.rs` + `mod.rs` (`pub mod federal;`) + two `ffi.rs` exports + `lib.rs` re-exports + one fixture + one `parity.rs` `Case` row (+ one `federal_claims` test) — and adds **no** new shared helper (contrast HDFC's `month_year_end`/`read_lines_first_match`) and **no** dependency (`Cargo.toml` unchanged). Ref: research **D1/D2/D4/D5**, spec US2, plan §Complexity Tracking.

**Checkpoint**: Federal is proven to be a pure single-layout drop-in — the hardest of the five layouts absorbed with shared date/polarity reused and no new engine infrastructure.

---

## Phase 6: User Story 3 — Direction from Scapia's leading `+`, never the amount's sign (Priority: P3)

**Goal**: Each transaction's direction is decided by Scapia's own notation — a leading `+` immediately
before the amount → **credit**; otherwise the shared description-language classifier decides (credit
words → credit; else debit) — never the amount's value. *(Impl landed in T006's Federal-local
`direction`.)*

**Independent Test**: A row with a leading `+` classifies credit (from the `+`, even without credit
words), and a row without one classifies from the description language (defaulting to debit) —
regardless of the amount.

- [ ] T012 [US3] Add direction unit tests in `core/crates/kaname-core/src/statement/federal.rs` (`#[cfg(test)]`): the golden `+₹324.45` row → **Credit** even though `Billpayment Payment` is **not** a recognized credit phrase — the leading `+` is decisive (US3-AC1, FR-010, research **D6**); the golden no-`+` `ExampleMerchantTokyo ₹2,353.13` row (no credit words) → **Debit** via the shared classifier's default (US3-AC2, FR-011); a fabricated **no-`+`** row whose description contains a credit keyword (e.g. `29-04-2026·10:00 Refund reversal received ₹500.00`) → **Credit** via the shared `classify(desc, None, None)` (`refund`/`reversal`/`payment received` are in `CREDIT_KEYWORDS`, `polarity.rs:15–26`) (US3-AC3, research **D6**); and a large/"negative-looking" amount **never** changes the direction — direction is decided solely from the `+`/description, never the amount's sign or magnitude (US3-AC4, FR-010, SC-004). Ref: research **D6**, spec US3.

**Checkpoint**: Direction is sourced solely from Scapia's leading `+` and, failing that, the description language — never the amount.

---

## Phase 7: User Story 4 — Statement metadata: billing cycle + fully-masked card last-4 (`"4836"`) (Priority: P4)

**Goal**: Recover `period_start`/`period_end` from the space-stripped `DDMonYYYY-DDMonYYYY` cycle and
`card_last4` from the fully-masked, **anchor-less** PAN — recovering **`"4836"`** — while leaving a
field **absent** (never fabricated) when it is not present. *(Impl landed in T006's `enrich` + the reused
un-anchored `find_last4`.)*

**Independent Test**: The space-stripped range `20Apr2026-19May2026` yields the correct start/end; the
fully-masked `XXXXXXXXXXXX4836` yields `"4836"`; neither present → unset (transactions still returned).

- [ ] T013 [US4] Add metadata unit tests in `core/crates/kaname-core/src/statement/federal.rs` (`#[cfg(test)]`, driving `enrich`/`read_lines`): the space-stripped range `XXXXXXXXXXXX4836 20Apr2026-19May2026` → `period_start 2026-04-20`, `period_end 2026-05-19` (US4-AC1, SC-003, FR-012, both via the shared `parse_date` `%d%b%Y`); the fully-masked `XXXXXXXXXXXX4836` with **no** textual anchor → **`card_last4 Some("4836")`** via `find_last4(full_text, None)` (US4-AC2, FR-013, SC-003, research **D7**); and a **missing-metadata** input (no `DDMonYYYY-DDMonYYYY` range, no masked PAN — just the two transaction lines) → `period_start`/`period_end`/`card_last4` all `None` while rows are still returned, and the un-anchored scan is **not** tripped by the lowercase `x` in `ExampleMerchantTokyo` or by the `HH:MM` times (US4-AC3, FR-014, research **D7**). Ref: research **D5/D7**, `data-model.md` §enrich, spec US4.

**Checkpoint**: Billing-cycle + card last-4 verified — the anchor-less four-digit mask yields `"4836"` (the parity contrast vs SBI's `null`), and missing metadata is left unset, never fabricated.

---

## Phase 8: User Story 5 — Malformed rows captured for review, never dropped or fatal (Priority: P5)

**Goal**: A line that looks like a Federal transaction but whose fields won't parse is captured in
`errored_lines` (raw, ≤240 codepoints), every good row is still returned, and nothing panics.
*(Behavior is **reused unchanged** from the ICICI `read_lines` seam — Federal adds no robustness code.)*

**Independent Test**: Mixed input (a good Federal row + one shape-matching but unparseable row) → the
good row returned, bad row captured, no error; non-transaction lines ignored silently.

- [ ] T014 [P] [US5] Add a Federal errored-line/robustness test in `core/crates/kaname-core/tests/parity.rs` (mirroring `malformed_row_is_captured_not_fatal`, `parity.rs:194–206`): a line matching the Federal shape but with an **unparseable date** (e.g. `99-99-9999·16:18 Some Merchant ₹10.00` — matches `\d{2}-\d{2}-\d{4}` but `parse_date` returns `None`) → captured in `errored_lines` (raw, truncated to 240 codepoints via the reused `truncate_chars`, `base.rs:18`), the valid row (`29-04-2026·16:18 Billpayment Payment +₹324.45`) still returned, **no panic** (FR-015, SC-007); header/summary/balance/total lines → ignored (no transaction, no error). Note in the test that this exercises the **reused** `read_lines` errored-line path (`line_reader.rs`) — Federal adds no robustness code. [P] (different file from the `federal.rs` test cluster). Ref: spec US5, `line_reader.rs` read loop, `parity.rs:194–206`.

**Checkpoint**: Parser is resilient — one bad row never takes down the import.

---

## Phase 9: User Story 6 — Proven byte-for-byte against a golden fixture (Priority: P6) 🛡️ whole-slice guard

**Goal**: Make the parity harness the **reusable, regression-proof** guarantee that pins Federal (and
every future reader) to the web engine — this time proving the harness accepts a **fifth and final bank
as a one-fixture + one-row addition** and **completes the credit-card set**. *(Fixture T003; harness
`Case` row T004; greened T008.)*

**Independent Test**: The harness over the ported Federal vector matches expected output exactly, and
re-running is stable; all five credit-card issuers reproduce their vectors.

- [ ] T015 [US6] Finalize `core/crates/kaname-core/tests/parity.rs` as the **reusable whole-slice guard**: confirm the Federal `Case` calls `read_federal_statement`; field-by-field parity — dates, exact `Decimal` amounts (scale preserved: `"324.45"`, `"2353.13"`; ₹/`+`/Indian grouping stripped), directions (`Credit` from the leading `+`; `Debit` from the classifier default), currency `INR`, `description_raw` **byte-for-byte** (`"Billpayment Payment"` / `"ExampleMerchantTokyo"`), plus `period_start 2026-04-20`, `period_end 2026-05-19`, **`card_last4 "4836"`**, `errored_lines []` (SC-001/003/010); the determinism **re-run** covers the Federal vector (SC-009); the fixture is **100% synthetic** (fabricated merchants/amounts, masked PAN `XXXXXXXXXXXX4836`; SC-002); and confirm the schema stayed **stable through `period_start`** — Federal needed **only one `Case` row** (no struct/assertion change), proving a new line-reader bank is a **one-fixture + one-row** addition. With Federal green, **all five** credit-card issuers (ICICI, HDFC, SBI, Yes, Federal) reproduce their golden vectors — the set is complete (SC-012). Leave the ICICI/HDFC/SBI/Yes fixtures untouched. Ref: `contracts/golden-fixture.md` §Harness behaviour/§Adding a future fixture, research **D9/D10**, plan §Complexity Tracking.

**Checkpoint**: Parity is an enforced guarantee for Federal, the harness stays reusable (a fifth bank landed as one row), and the credit-card set is complete.

---

## Phase 10: User Story 7 — Privacy gate: zero network in the parse path (Priority: P7) 🛡️ inherited guard

**Goal**: Prove the Federal parse path is egress-free — **structurally** (no networking crate can even
link) and **behaviorally** (determinism) — using the **inherited** gate with **zero** new config. *(No
new script/CI: Federal adds no dependency, so the audit is byte-identical.)*

**Independent Test**: `make core-privacy-audit` passes only when zero networking crates are in the
shipped graph; the determinism test passes; no telemetry/analytics anywhere in the parse path.

- [ ] T016 [US7] Confirm the inherited privacy-egress gate stays **GREEN with ZERO changes**: run `make core-privacy-audit` → `privacy-egress: OK (no networking crate in kaname-core deps)` — Federal adds **no dependency** (runtime *or* dev), so `cargo tree -p kaname-core -e normal` is byte-identical (`Cargo.toml` unchanged — FR-020/026, SC-008/014); the determinism/purity assertion over the Federal vector lives in `tests/parity.rs` (T004/T015, FR-017, SC-009); confirm **no** telemetry/analytics/advertising/crash-reporter enters the parse path and **no** network entitlement/ATS is added app-side (`ios/Project.swift` `infoPlist` unchanged) (FR-020/021). Ref: research **D1**, `quickstart.md` §2, spec US7.

**Checkpoint**: Privacy-egress remains a first-class, structurally- and behaviorally-enforced gate covering Federal.

---

## Phase 11: Polish & Cross-Cutting — full iOS Local Verification Gate green

**Purpose**: Prove the whole slice is merge-ready (SC-013) and review the constitution guarantees.

- [ ] T017 [P] Light docs alignment (no behavior change): note the **fifth and final credit-card parser** — a **third clean single-layout drop-in (after SBI and Yes) with zero new shared helpers**, **completing the credit-card set** — where the engine/build is described (`README.md` and/or `specs/006-federal-cc-parser/quickstart.md`); ensure `fixtures/README.md` reflects the Federal vector under `fixtures/federal/credit_card/`; if convenient, refresh the `statement/mod.rs` doc comment that lists issuers (`mod.rs:7`) so it reflects Federal landing. No stale wording.
- [ ] T018 **Run the full iOS Local Verification Gate green**, in order: `make core-lint && make core-test && make core-privacy-audit && make lint && make ios-gen && make ios-test`. ⚠️ `make core-xcframework` is rebuilt before `tuist generate` (via `ios-gen`); local Xcode requires the **"iPhone 16"** simulator. This is the SC-013 / FR-027 merge gate. Ref: `quickstart.md` §5.
- [ ] T019 [P] Final constitution review (no code change): **NO new dependency** (runtime *or* dev) — `Cargo.toml` unchanged; **NO new shared helper** and **NO composite** (SC-011 — the diff is `federal.rs` + `mod.rs` + two exports + `lib.rs` re-exports + one fixture + one `Case` row + one `claims` test); **no reconciliation carve-out** to honor — the web `_enrich` is already cycle + last-4 only (research **D10**); no secrets / network entitlements / copyleft (GPL/AGPL/LGPL) deps (FR-026, SC-014); all fixture/test data synthetic (SC-002); money never `f64` (amounts `Decimal`, ₹/`+`/Indian grouping stripped, scale preserved); direction from the leading `+` else the shared classifier, never the amount's sign; **`card_last4` is `Some("4836")`** via the un-anchored `find_last4` (never fabricated); ICICI/HDFC/SBI/Yes fixtures and the harness schema untouched (backward-compatible); all five credit-card issuers green (SC-012). Confirm against `git diff` before handoff. Ref: spec FR-018/FR-026/SC-011/SC-012/SC-014, plan §Constitution Check/§Complexity Tracking.

**Checkpoint**: Whole slice is green end-to-end and constitution-clean — ready to ship.

---

## Phase 12: Ship — two commits, PR #6, CI, merge (requester step 7)

**Purpose**: Land the slice. Executed **only after** Phase 11 is green. (Generation writes nothing here;
the implementer runs these once the gates pass.)

- [ ] T020 Create **two small, pure commits** on `006-federal-cc-parser` (RED→GREEN kept coherent):
  **Commit 1 — engine**: `fixtures/federal/credit_card/basic.json`, `core/crates/kaname-core/src/statement/federal.rs`, `core/crates/kaname-core/src/statement/mod.rs` (`pub mod federal;`), `core/crates/kaname-core/src/ffi.rs` (two exports), `core/crates/kaname-core/src/lib.rs` (re-exports), `core/crates/kaname-core/tests/parity.rs` (one `Case` row + `federal_claims` test), and any docs from T017.
  **Commit 2 — Swift test**: `ios/Tests/FederalParseTests.swift`.
  Do **not** commit generated artifacts (`ios/Generated/…`, `ios/Frameworks/…` are git-ignored). Ref: requester step 7.
- [ ] T021 Push the branch, open **PR #6** (`SSKUltra/kaname`, base default branch), **watch CI** — both the **core** job (ubuntu: `core-lint` + `core-test` + `core-privacy-audit`) and the **iOS** job (`macos-15`: xcframework → `tuist generate` → `xcodebuild … iPhone 16` test) go green — then **`gh pr merge --rebase --delete-branch`**. Ref: requester step 7, plan §Constitution Check (CI ordering inherited unchanged).

**Checkpoint**: Federal is merged; the credit-card set (ICICI, HDFC, SBI, Yes, Federal) is complete on-device with byte-for-byte parity.

---

## Dependencies & Execution Order

### Phase order

1. **Setup (P1)** → 2. **Test-First Foundation (P2, RED)** → 3. **US1 pipeline (P3)** →
4. **Bridge/Swift green (P4)** → 5–8. **US2/US3/US4/US5 verification (P5–P8)** →
9. **US6 parity guard (P9)** → 10. **US7 privacy guard (P10)** → 11. **Polish + full gate (P11)** →
12. **Ship (P12)**.

- **Test-First (Phase 2) BLOCKS all Federal parser code (Phase 3+)** — T003–T005 must exist and be RED first (Principle V, FR-025).
- **US1 pipeline is the critical path** and lands the behaviors US2/US3/US4/US5 verify.

### Task-level dependencies

- T003 (fixture) precedes T004 (parity `Case` row) and T008 (green).
- T004/T005 (RED tests) precede **all** implementation (T006+).
- **Chain**: T006 (`federal.rs` + `mod.rs`) → T007 (FFI exports + `lib.rs` re-exports) → T008 (Rust green).
- T007 → T009 (xcframework) → T010 (Swift green). T009 before any `tuist generate`.
- T011/T012/T013 depend on T006; T014 depends on T004 (harness) + T007 (exports); T015 depends on T008; T016 depends on T008.
- **T018 (full gate) depends on everything** (T008, T010, T015, T016, T017); T019 is review only.
- **Ship**: T020 depends on T018 (all green); T021 depends on T020.

### Parallel opportunities

- **Setup**: T001 [P] + T002 [P].
- **Test-First**: T003 [P] (fixture) + T005 [P] (Swift test) are different files; T004 edits `parity.rs` (run it alone; it depends on T003's path existing).
- **Story verification**: T011/T012/T013 all extend `federal.rs`'s `#[cfg(test)]` module (**same file → sequential**, though each is an independent test group); **T014 [P]** lives in `parity.rs` and can run alongside them.
- **Polish**: T017 [P] + T019 [P] (docs + review); T018 runs the gate alone.

---

## Parallel Example: the Test-First Foundation (Phase 2)

```bash
# Author the two independent RED artifacts together (different files):
Task T003: "Author fixtures/federal/credit_card/basic.json (exact bytes, real U+00B7 + U+20B9)"
Task T005: "Author ios/Tests/FederalParseTests.swift (RED core ↔ Swift Federal parse)"
# Then T004 edits tests/parity.rs (one Case row + federal_claims test) → verify RED (won't compile).
# Converge on the pipeline: T006 (federal.rs + mod.rs) → T007 (ffi.rs exports + lib.rs re-exports) → T008 (core-fmt → Rust green).
```

---

## Implementation Strategy

### MVP first (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 **RED** test-first anchors (fixture → parity `Case` row + `federal_claims`
→ Swift) → 3. Phase 3 pipeline (T006→T008, `make core-fmt` then green) → 4. Phase 4 bridge (T009–T010).
**STOP & VALIDATE**: the golden Federal statement parses on-device through `read_federal_statement` and
the Swift suite is green. This alone is a shippable, useful slice.

### Incremental delivery

Add US2 (zero-new-infra proof, the hardest layout) → US3 (direction from the leading `+`) → US4
(metadata incl. the anchor-less `"4836"`) → US5 (errored/robustness, reused) — each an independent test
increment over the same reader. Then lock the **guards**: US6 (golden parity — completes the five-issuer
set) and US7 (inherited privacy-egress). Finish with the full-gate run (T018) and Ship (T020–T021).

### Story → task traceability

| Story | Delivered by | Independently verified by |
|---|---|---|
| **US1** parse | T005, T006, T007, T008, T009, T010 | T008 (Rust), T010 (Swift), T004 wrong-issuer |
| **US2** zero-new-infra | T006 `federal.rs` (config) + T007 direct `read_lines` | **T011** (reuse tests + change-set review) |
| **US3** direction (leading `+`) | T006 Federal-local `direction` (`+`→Credit, else `classify(desc, None, None)`) | **T012** |
| **US4** metadata (`"4836"`) | T006 `enrich` (cycle + un-anchored `find_last4`) | **T013** |
| **US5** errored-lines | *reused* `read_lines` seam + `truncate_chars` | **T014** |
| **US6** golden parity 🛡️ | T003, T004, T008 | **T015** (reusable one-row guard; set complete) |
| **US7** privacy-egress 🛡️ | *inherited* gate + T004 determinism | **T016** |

---

## Notes

- **Test-first is mandatory** (Principle V, FR-025): T003–T005 are RED before Phase 3; T008 greens the
  Rust parity, T010 greens the Swift bridge — each has an explicit RED→GREEN verify step. Federal's
  `expected` is the **locked characterization ground truth** (no live capture needed — `quickstart.md`
  §0).
- **Faithful port** (byte-for-byte with the golden vector): every porting task cites its exact
  `federal_scapia.py` regex/behavior; `description_raw` is asserted **byte-for-byte** —
  `"Billpayment Payment"` / `"ExampleMerchantTokyo"` (the `HH:MM` time, the `+`, and the `₹` are **not**
  part of it); `card_last4` is **`"4836"`** via the **un-anchored** `find_last4` (research **D3/D7**).
- **✅ No reconciliation carve-out** (research **D10**): unlike Yes, the web `federal_scapia.py`
  `_enrich` is **already** cycle + last-4 only — nothing to drop, nothing to add; the Rust port is 1:1.
- **REUSE, not rebuild**: Federal adds only `federal.rs`, two exports, `lib.rs` re-exports,
  `pub mod federal;`, one fixture, and one `Case` row — everything else (records, `common`/`polarity`
  helpers, the `read_lines` seam, the UniFFI custom types, the parity harness, the privacy gate) is
  inherited unchanged (FR-018). **No new dependency** (runtime *or* dev); **no new shared helper**; **no
  composite** (contrast HDFC). The **one bespoke rule** — the leading-`+` direction — lives entirely in
  `federal.rs`, mirroring the landed `hdfc.rs` monthly pattern (`hdfc.rs:109–118`).
- **Encoding-robust & UTF-8**: the row regex's unescaped `.` matches the middot (any single char), so
  the row is recognized regardless of which glyph extraction produced (FR-004/SC-005); keep the actual
  **U+00B7** (`·`) and **U+20B9** (`₹`) bytes in the fixture, the Swift test, and the `federal.rs` regex.
- **[P]** = different files, no unfinished dependency. `[Story]` labels map each task to its slice.
- **Guards protect the whole slice**: US6 (golden parity — proves all five issuers) and US7 (privacy)
  fail the build/review on any regression to parsing behavior or egress-freedom.
- **Generation commits nothing**; the two commits + PR #6 + `--rebase --delete-branch` merge are
  **Phase 12: Ship**, executed by the implementer after every gate is green.
