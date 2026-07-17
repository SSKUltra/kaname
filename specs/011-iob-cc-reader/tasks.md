---
description: "Task list — Indian Overseas Bank (IOB) Credit-Card Parser (sixth & final CC reader, single layout, zero new engine infra) + roadmap doc fix"
---

# Tasks: Import an Indian Overseas Bank (IOB) Credit-Card Statement On-Device (Sixth & Final Credit-Card Reader, Zero New Engine Infrastructure) + Roadmap Doc Fix

**Input**: Design documents from `/specs/011-iob-cc-reader/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md` (D1–D11), `data-model.md`,
`contracts/engine-ffi.md`, `contracts/golden-fixture.md`, `quickstart.md`

**Tests**: REQUIRED and **TEST-FIRST** for this slice (Constitution Principle V). Authoring the
golden fixture, the failing Rust parity `Case` row (+ the `iob_claims` accept/reject test), and the
failing Swift "core ↔ Swift IOB parse" test are all done **RED, before** the `IobReader` code that
greens them (FR-024, FR-026). The engine's `expected` is the **locked characterization ground truth**
from the web IOB reader — **no live run needed** (`quickstart.md` §0); the two IOB-specific derivations
(uppercase-month `%d-%b-%Y` parsing; inline masked-PAN `find_last4`) were **re-confirmed against the
real `kaname-core` helpers** (research D4/D7 + "Verification harness").

**Port source of truth** (faithful, byte-for-byte with the golden vector — every porting task cites
exact `iob.py` lines/regex/behavior):
`/Users/ssk/Projects/finance-tracker-phase/backend/app/services/ingestion/statement_readers/iob.py`
(reusing the already-ported `_common`, `polarity`, `base`, `_line_reader` from the ICICI slice,
extended by HDFC, and reused verbatim by SBI/Yes/Federal). IOB is the **third clean single-layout
drop-in** (after SBI and Yes) and the **sixth and final credit-card reader**, completing the 10-reader
set (6 CC + 4 bank).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: `US1`=parse · `US2`=zero-new-infra (completes the CC set) · `US3`=direction (`Dr`/`Cr`) ·
  `US4`=metadata (`period_end` only + `"0042"`) · `US5`=reconciliation carve-out · `US6`=roadmap doc fix ·
  `US7`=errored-lines · `US8`=golden parity · `US9`=privacy-egress. Setup/Polish/Delivery carry no story label.
- Exact file paths are included in every task.

## ♻️ REUSE — do NOT re-create (IOB adds only `iob.rs` + fixture + exports + one `Case` row + two doc edits)

IOB plugs into the ICICI/HDFC/SBI/Yes/Federal foundations **unchanged**. Like SBI (`004`) and Yes
(`005`), this is a **clean single-layout drop-in**: it adds **NO new shared helper, NO composite, and
NO new dependency** (FR-017/019, SC-012). Do **not** rebuild any of these:

- `statement/common.rs` — `parse_amount` (`common.rs:58`) / `parse_date` (`common.rs:66`): the
  `%d-%b-%Y` format is **already present** (`common.rs:28`, commented "04-Apr-2025 (HDFC)") and
  **`chrono`'s `%b` month table is case-insensitive**, so the **uppercase** `MAR`/`APR` parse with **no
  IOB date code** (research **D4**, **verified** `31-MAR-2026 → 2026-03-31`) / `find_last4(text,
  Some("Credit Card Number"))` **anchor** path (`common.rs:149`, already exercised by SBI at
  `sbi.rs`'s `enrich`; `STRICT_PAN_RE` at `common.rs:41`; research **D7**).
- `statement/polarity.rs` — `classify(...)` (`polarity.rs:62`); the two-letter `Dr`/`Cr` markers are
  **already** in the tables (`CR_MARKERS` has `"CR"`, `DR_MARKERS` has `"DR"` — `polarity.rs:11–12`;
  `normalise_marker` upper-cases `"Cr"→"CR"`, `"Dr"→"DR"` — `polarity.rs:29`; research **D5**).
- `statement/base.rs` — `ParsedStatement` / `ParsedTransaction` records **unchanged**; `period_start`
  (`base.rs:88`), `period_end` (`base.rs:89`) and `card_last4` (`base.rs:90`) are **already fields**.
  **There are NO `printed_total_*` fields** — the reconciliation carve-out is structural (research
  **D10**, FR-013).
- `statement/line_reader.rs` — the `read_lines` / `claims` seam + `LineReaderConfig` trait, reused
  **verbatim** (single layout → **`read_lines` directly**, NOT the HDFC composite; research **D2**); the
  errored-line `truncate_chars`/`MAX_RAW` path is reused as-is (US7).
- `ffi.rs` — the `Decimal`/`NaiveDate` custom types + `Direction` enum (**no `uniffi.toml` change, no
  new record, no new Swift type**).
- `tests/parity.rs` — the golden-fixture parity harness (**add one `Case` row + one `claims` test, do
  NOT change the schema** — `Expected.period_start` is already `#[serde(default)]` and asserted:
  `parity.rs:31–33/192–199`; a fixture that **omits** `period_start` deserializes to `None`, exactly
  like the ICICI vector).
- The **privacy-egress gate** (`make core-privacy-audit`) and CI — inherited **unchanged** (**no new
  dependency** → byte-identical shipped `cargo tree` graph; research **D1**, plan Constitution Check).

**The only NEW code**: `statement/iob.rs` (one zero-sized `IobReader` config + its free/trait `enrich`
= **`period_end` + last-4 ONLY**), **two** `#[uniffi::export]` functions (`read_iob_statement` +
`iob_claims`), the `lib.rs` re-exports, `pub mod iob;` in `statement/mod.rs`, **one** golden fixture,
and **one** parity `Case` row. **The only NEW docs**: two one-line moves in `docs/HANDOFF.md` +
`docs/kaname-ios-plan.md` (US6). **No new dependency** (runtime *or* dev); **no new shared helper**;
**no harness schema change**.

## 🚫 Reconciliation carve-out — non-mechanical rule #1 (research D10, FR-013, US5, SC-013)

The web `iob.py` `_enrich` **also** scrapes printed per-statement debit/credit totals via `_SUMMARY_RE`
(`ACCOUNT SUMMARY … <credits> <debits> …`) → `printed_total_credits` / `printed_total_debits`. **That
regex and those `printed_total_*` assignments MUST NOT be ported.** The Rust `ParsedStatement` has no
such fields; the IOB `enrich` here is **`period_end` + last-4 only** — the **same carve-out already
applied to Yes** (`005` D10). Every porting task below repeats this prohibition.

## 🚫 No fabricated `period_start` — non-mechanical rule #2 (research D6, FR-010, SC-003)

Unlike SBI/Yes (whose `enrich` sets **both** ends from a `<from> to <to>` range), IOB prints **only** a
lone `Stmt Date : 20-APR-2026` → that is the billing-cycle **end**. **`period_start` is left at its
`None` default and MUST NEVER be fabricated** (e.g. do not copy Yes's `PERIOD_RE`/`Statement Period`
scrape). This is the notable structural difference from `yes.rs`/`sbi.rs`.

## ⚠️ Local gotchas (apply throughout)

- **`make core-xcframework` MUST run before `tuist generate`** (`ios-gen: core-xcframework`) — the
  generated Swift (`ios/Generated/kaname_core.swift`) + `KanameCoreFFI.xcframework` are rebuilt
  artifacts (`quickstart.md` §3/§Troubleshooting). CI builds the xcframework first.
- **The iOS CI job stays pinned to `macos-15`**; the `xcodebuild` destination is the **"iPhone 16"**
  simulator (`OS=latest`) — create it locally in Xcode for `make ios-test` (plan Constitution Check,
  `quickstart.md` §Prerequisites).
- **swift-format `[Spacing]` rejects trailing inline comments** — in the Swift bridge test any comment
  (e.g. a `Cr`/`Dr` marker note) MUST be on its **own line**, never trailing after code. (Rust `//`
  trailing comments are fine — see `yes.rs:88`/`sbi.rs`.)
- Money is **`Decimal`, never `f64`**; Indian grouping is stripped and scale preserved
  (`1,000.00 → 1000.00`, `3,500.00 → 3500.00`). Direction comes from the **terminal `Dr`/`Cr` marker**
  via `classify(desc, dir, None)`, never the amount's magnitude (the `Cr` refund `1000.00` is a credit;
  the larger `Dr` purchase `3500.00` is a debit) and never the description's wording. **No new
  dependency** (runtime *or* dev).
- **`card_last4` is `"0042"`** here — the inline masked PAN `123456XXXXXX0042` exposes four trailing
  digits, recovered via the whole-text fallback with **no bleed** from the adjacent limits
  `16000 25091.5` (research **D7**, **verified**).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the invariants and prerequisites so every later task has a place to land and the
gates stay green. No behavior yet.

- [ ] T001 [P] Confirm the **no-new-dependency** invariant: `core/crates/kaname-core/Cargo.toml` stays **UNCHANGED** (runtime deps `regex`/`rust_decimal`/`chrono`/`serde`/`uniffi` + dev-only `serde_json` already present from earlier slices) — IOB adds **zero** deps (FR-027, SC-012). Create the fixtures home directory `fixtures/iob/credit_card/`. Ref: plan §Summary/§Project Structure, `contracts/golden-fixture.md` §Location.
- [ ] T002 [P] Verify local prerequisites & gotchas (no code): `cargo` on PATH (`source "$HOME/.cargo/env"`); iOS targets present (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`); an **"iPhone 16" simulator** exists in Xcode; recall `make core-xcframework` precedes `tuist generate` (`ios-gen: core-xcframework`) and that the iOS CI job is pinned to **`macos-15`**; recall **swift-format `[Spacing]` forbids trailing inline comments** in the Swift test. Ref: `quickstart.md` §Prerequisites/§Troubleshooting, plan §Constitution Check (iOS Local Verification Gate).

**Checkpoint**: Fixtures home exists, no manifest change needed, toolchain + simulator + CI ordering understood.

---

## Phase 2: Test-First Foundation (⚠️ Principle V — author RED before ANY IOB code)

**Purpose**: Pin the on-device engine to the proven web engine **before** writing it. These are the
parity (US8) and bridge (US1) tests that **protect the whole slice**; they MUST be **RED** at the end
of this phase (`read_iob_statement` / `iob_claims` do not exist yet).

**⚠️ CRITICAL**: No IOB parser code (Phase 3+) may be written until T003–T005 exist and are verified failing.

- [ ] T003 [P] [US8] Author the **ported** golden vector `fixtures/iob/credit_card/basic.json` — copy the **exact fixture bytes** from `contracts/golden-fixture.md` §"Exact fixture bytes to write" (do **not** hand-derive). `lines` = the 15 non-empty stripped lines (header/metadata/`Credit Card Number`/inline PAN `123456XXXXXX0042 16000 25091.5`/`ACCOUNT SUMMARY` block/summary values row/`Total Purchase`/end marker + the **two** `DD-MON-YYYY … Dr|Cr` rows `31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr` and `04-APR-2026 ExampleStorePurchase 3,500.00 Dr`); `full_text` (`\n`-joined, trailing `\n`) contains `INDIAN OVERSEAS BANK CREDIT CARD DIVISION`, `Stmt Date: 20-APR-2026`, the `iobnet.co.in` e-mail (second claim marker), the inline masked PAN, and the `ACCOUNT SUMMARY` block (present but NOT scraped). `expected.rows` = `{ "2026-03-31", "1000.00", Credit, INR, "ExampleRefundMerchant" }` and `{ "2026-04-04", "3500.00", Debit, INR, "ExampleStorePurchase" }`; `period_end "2026-04-20"` (from `Stmt Date: 20-APR-2026`); **`card_last4 "0042"`** (inline masked PAN, never `6000`/`5091` from the limits — research **D7**); `errored_lines []`; **`period_start` OMITTED** → deserializes to `None` (IOB prints no range — research **D6**; mirrors the ICICI vector). Amounts are **JSON strings** (re-parsed to `Decimal`, never `f64`); `1,000.00`/`3,500.00` normalize to `"1000.00"`/`"3500.00"` (scale preserved, Indian grouping stripped). `description_raw` is **byte-for-byte** — the terminal `Dr`/`Cr` marker and the amount are **not** part of it (US1-AC3, research **D3**). **No `printed_total_*` keys anywhere** (reconciliation carve-out, FR-013, SC-013). 100% synthetic/redacted (FR-025, SC-004). Ref: `contracts/golden-fixture.md` §The IOB `basic.json` vector, `quickstart.md` §0, research **D3/D6/D7/D10**.
- [ ] T004 [US8] Extend the parity harness `core/crates/kaname-core/tests/parity.rs` → **RED** (the **only** harness change; **NO schema/struct/assertion change** — `period_start` is already `#[serde(default)]` and asserted at `parity.rs:31–33/192–199`): extend `use kaname_core::{… , read_iob_statement, iob_claims, …}` (`parity.rs:12–17`); add **one** `Case` row to `CASES` **after the Federal/Scapia case (`parity.rs:101–105`) and before the bank-account cases (`parity.rs:106+`)** — `Case { label: "IOB", parse: read_iob_statement, rel_path: "iob/credit_card/basic.json" }`; add an `iob_claims_accepts_own_document_and_rejects_others` test mirroring `federal_claims_accepts_own_document_and_rejects_others` (`parity.rs:328–339`, cf. `sbi`/`yes` at `:309–326`): `iob_claims(basic.full_text) == true`; `iob_claims("ICICI Bank Statement".to_string()) == false` (FR-002, SC-002, research **D9**). Leave the existing fixtures and `Expected`/`ExpectedRow`/`Case` structs (`parity.rs:21–73`) **untouched**. ⚠️ **Verify RED**: `make core-test` fails to **compile** (`read_iob_statement`/`iob_claims` absent). Ref: `contracts/golden-fixture.md` §Harness behaviour, `data-model.md` §Fixture/harness types, research **D9**.
- [ ] T005 [P] [US1] Author the **RED** Swift bridge test `ios/Tests/IOBParseTests.swift` — "core ↔ Swift IOB parse" (`import Foundation` / `import KanameCore` / `import Testing`, Swift Testing), mirroring `ios/Tests/SBIParseTests.swift`: static `lines` (the two golden rows) + static `fullText` via `[…].joined(separator: "\n")` (header + `Stmt Date: 20-APR-2026` + `iobnet.co.in` line + `Credit Card Number …` + inline `123456XXXXXX0042 16000 25091.5` + the two rows). `readIobStatement(lines:fullText:)` → `statement.lines.count == 2`; `let credit = try #require(statement.lines.first)` = `valueDate "2026-03-31"` / `Decimal(string: "1000.00", locale: Locale(identifier: "en_US_POSIX"))` / `.credit` / `currency "INR"` / `descriptionRaw "ExampleRefundMerchant"`; `lines[1]` = `"2026-04-04"` / `Decimal(string: "3500.00", locale: …en_US_POSIX)` / `.debit` / `"ExampleStorePurchase"`; **`statement.periodStart == nil`**; `statement.periodEnd == "2026-04-20"`; **`statement.cardLast4 == "0042"`**; `erroredLines.isEmpty`. Second `@Test`: `iobClaims(fullText: Self.fullText) == true` and `iobClaims(fullText: "HDFC Bank Credit Cards statement") == false`. Amounts compared as exact `Foundation.Decimal` value-equality (never float). ⚠️ **swift-format `[Spacing]`**: any marker/explanatory comment goes on its **own line**, never trailing after code. ⚠️ **Verify RED**: won't build until the xcframework is regenerated with the exports in Phase 4. Ref: `contracts/engine-ffi.md` §Contract tests (Swift), `ios/Tests/SBIParseTests.swift`.

**Checkpoint**: Fixture in place; Rust parity harness RED (IOB `Case` row + `iob_claims` test won't compile); Swift bridge test RED. Test-first satisfied — IOB parser code may now begin.

---

## Phase 3: User Story 1 — Parse an IOB statement into transactions (Priority: P1) 🎯 MVP

**Goal**: Recognize an IOB credit-card statement and return one transaction per row (date, exact
amount, direction, INR, description) — 100% on-device. Porting the reader here also **lands the
behaviors** that US2/US3/US4/US5 verify independently in Phases 5–8 and that US7/US8/US9 guard.

**Independent Test**: `read_iob_statement(basic.lines, basic.full_text)` returns the two expected rows
and `iob_claims` accepts IOB / rejects ICICI — with no network in the parse path.

> Port order follows the plan's chain: `iob.rs (config + enrich) → FFI exports + lib re-exports →
> green`. IOB needs **no** enabler helper (contrast HDFC's `month_year_end`/`read_lines_first_match`);
> it is structured **identically to `sbi.rs`/`yes.rs`**.

- [ ] T006 [US1] Create `core/crates/kaname-core/src/statement/iob.rs` (and add `pub mod iob;` to `core/crates/kaname-core/src/statement/mod.rs` **between `pub mod icici_bank;` (`mod.rs:18`) and `pub mod ledger_reader;` (`mod.rs:19`)**, keeping alphabetical order) — port `iob.py` wholesale, **structured identically to `yes.rs`** (one zero-sized config + a free `enrich`; single layout):
  - `pub const BANK_CODE: &str = "IOB";`; `const CLAIM_MARKERS: &[&str] = &["INDIAN OVERSEAS BANK", "iobnet.co.in"];` — **two** markers (faithful to `iob.py`, research **D9**).
  - `static ROW_RE: LazyLock<Regex>` ported **byte-for-byte** from `_ROW_RE`: `^(?P<date>\d{2}-[A-Za-z]{3}-\d{4})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>Dr|Cr)$` — `DD-MON-YYYY` (two-digit day, **case-insensitive** three-letter month `[A-Za-z]{3}`, four-digit year) + terminal two-letter `Dr`/`Cr` anchored at `$` (research **D3**).
  - `static STMT_DATE_RE: LazyLock<Regex>` ported from `_STMT_DATE_RE` (case-insensitive, spacing-tolerant): `(?i)Stmt Date\s*:\s*(\d{2}-[A-Za-z]{3}-\d{4})` — the lone statement date = billing-cycle **end** (research **D6**).
  - `pub struct IobReader;` `impl LineReaderConfig for IobReader` (mirror `yes.rs:38–62`): `bank_code()` = `"IOB"`; `claim_markers()` = `CLAIM_MARKERS`; `row_re()` = `&ROW_RE`; `direction(caps, desc)` = **reuse** `classify(description, caps.name("dir").map(|m| m.as_str()), None)` (`Cr→Credit`, `Dr→Debit`; the marker wins **before** any description-keyword check — FR-008/009, research **D5**). Uses the seam's default `date`/`desc`/`amount` group names.
  - `fn enrich(&self, statement, full_text)` (trait method, like `yes.rs:55–61`) — port `_enrich`, **`period_end` + last-4 ONLY**: `if let Some(caps) = STMT_DATE_RE.captures(full_text) { statement.period_end = parse_date(&caps[1]); }` (via the **existing** case-insensitive `%d-%b-%Y`, **verified** `20-APR-2026 → 2026-04-20`); **always** `statement.card_last4 = find_last4(full_text, Some("Credit Card Number"));` (same anchor as `sbi.rs`; whole-text fallback recovers `"0042"` — research **D7**). **🚫 `period_start` is NEVER set** (stays `None`; do NOT port Yes's `PERIOD_RE` — research **D6**).
  - 🚫 **DO NOT PORT the reconciliation scrape**: no `_SUMMARY_RE`, and **no** `printed_total_credits`/`printed_total_debits` assignments. `ParsedStatement` (`base.rs`) has no such fields (research **D10**, FR-013, US5, SC-013). **Document the reconciliation carve-out in a `//!` module comment**, mirroring `yes.rs:8–10`.
  - `LazyLock` both regexes (determinism, compile-once). **Reuse** `parse_date`/`parse_amount`/`find_last4`/`classify`/records unchanged — **no new shared helper** (SC-012). Ref: `data-model.md` §statement/iob.rs, research **D1–D10**, `iob.py`, `yes.rs:1–62`, `sbi.rs`.
  - **Include focused `#[cfg(test)]` unit tests** (mirroring `yes.rs:64–102`/`sbi.rs`'s modules) that green in T008 (these also stand up US2–US5 in Phases 5–8): marker-direction `Cr → Credit` / `Dr → Debit` over the two golden rows; header/summary/total/`Credit Card Number`/end-marker lines are **not** transactions (no row, no errored line); inline `find_last4(full_text, Some("Credit Card Number")) == Some("0042")` (no bleed from `16000`/`25091.5`); `iob_claims`-style marker check via `read_lines`/`claims` for IOB-vs-other.
- [ ] T007 [US1] Add the UniFFI exports in `core/crates/kaname-core/src/ffi.rs` (SBI/Yes-style **inline**, mirroring `ffi.rs:88–110`): add `use crate::statement::iob::IobReader;` with the other reader imports (alphabetical, before the `line_reader` import at `ffi.rs:20`) then, after the Federal block (`ffi.rs:112–124`): `#[uniffi::export] pub fn read_iob_statement(lines: Vec<String>, full_text: String) -> ParsedStatement { read_lines(&IobReader, &lines, &full_text) }` (single layout → `read_lines` **directly**, NOT the HDFC composite — research **D2**; **no `first_row_words` param** — CC reader, not ledger) and `#[uniffi::export] pub fn iob_claims(full_text: String) -> bool { claims(&IobReader, &full_text, "IOB") }` — total functions, never throw/abort (`read_lines`/`claims` imported at `ffi.rs:20`). **Reuse** the existing `Decimal`/`NaiveDate` custom types + `Direction` enum unchanged (**no `uniffi.toml` change, no new record**). Re-export both in `core/crates/kaname-core/src/lib.rs` — extend the existing `pub use ffi::{…}` block (`lib.rs:28–33`) to add `read_iob_statement` and `iob_claims` (keep the alphabetical grouping) — so `tests/parity.rs` and the app path reach them. Depends on T006. Ref: `contracts/engine-ffi.md` §Exported functions, research **D9**.
- [ ] T008 [US1] **Green the engine side**: run `make core-fmt` (format first), then `make core-test` — `tests/parity.rs` (T004) now **PASSES** for the IOB vector (both rows exact incl. `description_raw` byte-for-byte; **`period_start` absent → `None`**; `period_end 2026-04-20`; **`card_last4 "0042"`**; `errored_lines` empty), determinism, `iob_claims` accept/reject, and the `iob.rs` unit tests — while **all prior parity stays green** (fixtures untouched) — then `make core-lint` (clippy `-D warnings` + fmt check). Verify **RED→GREEN** for the Rust parity harness + `iob.rs` tests. Ref: `quickstart.md` §1.

**Checkpoint**: The engine parses the golden IOB statement; the Rust parity + determinism + wrong-issuer + `iob.rs` unit tests are green. US1 is functional on the Rust side (Swift bridge greened in Phase 4).

---

## Phase 4: UniFFI bridge — regenerate the xcframework + green the Swift test (US1)

**Goal**: Surface the two new functions to Swift and green the "core ↔ Swift IOB parse" test.

- [ ] T009 [US1] Run `make core-xcframework` to rebuild `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift` (git-ignored artifacts) now exposing `readIobStatement` + `iobClaims` (records reused ⇒ **no new Swift type**; `ParsedStatement.periodStart` stays `nil` for IOB and `cardLast4 == "0042"`). ⚠️ **MUST run before `tuist generate`** (`quickstart.md` §3). Ref: `contracts/engine-ffi.md` §Stability/compatibility.
- [ ] T010 [US1] Run `make ios-test` (`ios-gen` → `core-xcframework` → `tuist generate` → `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test`) to **green** `ios/Tests/IOBParseTests.swift` (T005) — the two rows with exact `Foundation.Decimal` amounts, `.credit`/`.debit` from the `Cr`/`Dr` markers, **`periodStart == nil`**, `periodEnd == "2026-04-20"`, **`cardLast4 == "0042"`**, and `iobClaims` accept (IOB) / reject (HDFC). ⚠️ **Local: create the "iPhone 16" simulator first.** Verify **RED→GREEN** for the Swift bridge test. Ref: `quickstart.md` §4.

**Checkpoint**: US1 MVP fully delivered end-to-end (Rust engine + Swift bridge). A person's IOB statement text → transactions, on-device.

---

## Phase 5: User Story 2 — A sixth credit-card bank with zero new engine infrastructure, completing the set (Priority: P2)

**Goal**: Prove IOB is delivered as a **single-layout reader configuration only** — reusing the shared
date parser (`%d-%b-%Y`, uppercase-month tolerant) and polarity classifier (`Dr`/`Cr`) with **no new
shared helper** and **no composite** — landing the **sixth and final** CC reader. *(Impl landed in T006
`iob.rs` + T007 direct `read_lines`.)*

**Independent Test**: The IOB parse plugs into the existing `read_lines(lines, full_text)` seam,
reusing `parse_date` and `classify`; a review of the change set shows **no** new/modified shared helper
in the reader subsystem, and the CC reader set now numbers six.

- [ ] T011 [US2] Add reuse/plumbing unit tests in `core/crates/kaname-core/src/statement/iob.rs` (`#[cfg(test)]`, mirroring `yes.rs`/`sbi.rs`'s test modules) proving **zero new infra**: the **uppercase** month `31-MAR-2026` is interpreted as `2026-03-31` **through the shared `parse_date`** with no IOB-specific date code (US2-AC1, SC-012 — the `%d-%b-%Y` format already lives in `common.rs:28` and `chrono`'s `%b` is case-insensitive; research **D4**); a `Dr`/`Cr` marker maps to debit/credit **through the shared `classify`** with no IOB-specific direction code (US2-AC2 — `"Dr"→"DR"`, `"Cr"→"CR"` already in `polarity.rs:11–12`); the reader drives the shared **`read_lines(&IobReader, …)`** seam **directly** (single layout — it does **not** use `read_lines_first_match`, US2 / research **D2**); and a doc with no matching rows → empty `lines`, no error. Then perform the **change-set review** (US2-AC3, SC-012): confirm the IOB diff is exactly `iob.rs` + `mod.rs` (`pub mod iob;`) + two `ffi.rs` exports + `lib.rs` re-exports + one fixture + one `parity.rs` `Case` row (+ the US6 doc edits) — and adds **no** new shared helper (contrast HDFC's `month_year_end`/`read_lines_first_match`) and **no** dependency (`Cargo.toml` unchanged). Ref: research **D1/D2/D4/D5**, spec US2, plan §Complexity Tracking.

**Checkpoint**: IOB is proven a pure single-layout drop-in — shared date/polarity reused, no new engine infrastructure — and the credit-card reader set is complete (six).

---

## Phase 6: User Story 3 — Direction from the terminal `Dr`/`Cr` marker, never the amount's sign (Priority: P3)

**Goal**: Each transaction's direction reflects the statement's own terminal `Dr`/`Cr` marker — `Cr`
credit, `Dr` debit — never the amount's value and never a direction-like word in the description.
*(Impl landed in T006's `direction` = `classify(desc, dir, None)`.)*

**Independent Test**: Rows ending in `Cr` and rows ending in `Dr` classify credit/debit from the
marker, regardless of the amount and regardless of credit/debit wording in the description.

- [ ] T012 [US3] Add direction unit tests in `core/crates/kaname-core/src/statement/iob.rs` (`#[cfg(test)]`): terminal `Cr` → **Credit**, terminal `Dr` → **Debit** (US3-AC1/AC2, FR-009); a **magnitude-independence** check — the `Cr` refund `1,000.00` is a **credit** while the larger `Dr` purchase `3,500.00` is a **debit** (US3-AC4, FR-008, SC-005); a **conflicting-word** case — a fabricated row whose description contains credit/debit keywords but whose terminal marker is `Dr`, e.g. `31-MAR-2026 REFUND CREDIT CASHBACK 500.00 Dr`, classifies **Debit** — the marker beats the wording (US3-AC3, FR-008, research **D5**). Amount value/sign is never consulted. Ref: research **D3/D5**, spec US3.

**Checkpoint**: Direction is sourced solely from the terminal `Dr`/`Cr` marker, never the amount or the description.

---

## Phase 7: User Story 4 — Statement metadata: billing-cycle END + card last-4 (`"0042"`), NO period start (Priority: P4)

**Goal**: Recover `period_end` from the lone `Stmt Date : <DD-MON-YYYY>` and `card_last4` from the
inline masked PAN via the `Credit Card Number` anchor — recovering **`"0042"`** with no bleed from the
adjacent limits, while **leaving `period_start` unset** (IOB prints no range; never fabricated). *(Impl
landed in T006's `enrich` + the reused `find_last4` anchor.)*

**Independent Test**: A `Stmt Date : 20-APR-2026` line yields `period_end 2026-04-20` and leaves
`period_start` `None`; the inline masked `123456XXXXXX0042 16000 25091.5` yields `"0042"` (not
`6000`/`5091`); missing metadata → all `None` while rows are still returned.

- [ ] T013 [US4] Add metadata unit tests in `core/crates/kaname-core/src/statement/iob.rs` (`#[cfg(test)]`, driving `enrich`/`read_lines`): `Stmt No: 2026CC0000001 Stmt Date: 20-APR-2026 E-Mail: creditcard@iobnet.co.in` → **`period_end 2026-04-20`** via the shared case-insensitive `%d-%b-%Y` (the earlier `Stmt No:` is not `Stmt Date`, so it is skipped) **and `period_start == None`** (US4-AC1/AC3, SC-003, FR-010, research **D6**); the inline masked PAN `123456XXXXXX0042 16000 25091.5` → **`card_last4 Some("0042")`** via `find_last4(full_text, Some("Credit Card Number"))` — **never** `6000`/`5091` from the adjacent limits (US4-AC2, FR-011, SC-004, research **D7**); a **missing-metadata** input (no `Stmt Date` line, no masked PAN) → `period_start`/`period_end`/`card_last4` all `None` while rows are still returned (US4-AC4, FR-012). Ref: research **D6/D7**, `iob.py` `_enrich`, spec US4.

**Checkpoint**: Billing-cycle end + card last-4 verified — `period_end 2026-04-20`, `card_last4 "0042"` (no bleed), and `period_start` deliberately unset (never fabricated).

---

## Phase 8: User Story 5 — Reconciliation stays out of scope: printed totals NOT ported (Priority: P5) 🚫 scope guard

**Goal**: Prove the IOB output model + fixture carry **only** transactions + `period_end` + last-4 (+
errored lines) — the web reader's `ACCOUNT SUMMARY` printed debit/credit totals are **absent**. This is
the one place a naïve full port would overreach. *(Impl landed in T006's `enrich` deliberately
**omitting** `_SUMMARY_RE`; structurally guaranteed because `ParsedStatement` has no `printed_total_*`
fields — same carve-out as Yes.)*

**Independent Test**: Parse the IOB `full_text` (which **does** contain the `ACCOUNT SUMMARY` block and
its values row `345.50 1,000.00 3,500.00 0 2,845.50`) and confirm the result contains only rows +
`period_end` + last-4 — no printed-total values anywhere, and the model exposes no printed-total fields;
the summary values row also produces neither a transaction nor an errored line.

- [ ] T014 [US5] Add a reconciliation-carve-out test in `core/crates/kaname-core/src/statement/iob.rs` (`#[cfg(test)]`, driving `read_lines`/`enrich` over the golden `full_text`): `read_iob_statement` returns **only** the two transaction rows + `period_end 2026-04-20` + `card_last4 "0042"` — the `ACCOUNT SUMMARY` figures (`credits 1,000.00`, `debits 3,500.00`) appear **nowhere** in the output, and the summary values row is neither a transaction nor an errored line (US5-AC1, FR-013, SC-013, research **D10**). Then perform the **model/source review** (US5-AC2/AC3): confirm `statement/iob.rs` contains **no** `_SUMMARY_RE` regex and **no** `printed_total_*` reference; confirm `ParsedStatement` (`base.rs`) exposes **no** `printed_total_*` fields; and confirm the golden `expected` (T003) carries **no** printed-total keys — the carve-out is structural. Ref: research **D10**, plan §Complexity Tracking, `iob.py` `_enrich`/`_SUMMARY_RE`, spec US5.

**Checkpoint**: The reconciliation carve-out is enforced — IOB stays identically shaped to the five landed CC readers; no half-built reconciliation surface ships.

---

## Phase 9: User Story 6 — Correct the roadmap docs: IOB is a credit-card reader, not a bank-account reader (Priority: P6) 📝 doc-only

**Goal**: Move IOB from the **bank-account** reader list to the **credit-card** reader list in both
roadmap documents, so they correctly describe IOB as a line-based CC reader (no IOB ledger reader
exists). After the edit both files read **six credit-card + four bank-account** readers (ten total).
Doc-only — **no build/test impact** (research **D11**, FR-014/015, SC-014). *(This story has no engine
code and does not depend on Phases 3–8; it may be done any time after Setup.)*

**Independent Test**: Inspect both files after the change and confirm IOB appears **once**, under
credit-card readers, in each — and no longer under bank-account readers — with the surrounding counts
consistent (six CC, four bank).

- [ ] T015 [P] [US6] Edit the two roadmap docs (doc-only; leave **unstaged** for the Phase 14 commit): in `docs/HANDOFF.md`, add `` `iob.py` `` to the **credit-card** readers list (`HANDOFF.md:56`, currently ending `` … `federal_scapia.py`. ``) and **remove** it from the **bank-account** readers list (`HANDOFF.md:57–59`, so it ends `` … `au_bank.py`. ``); in `docs/kaname-ios-plan.md`, add `` `iob` `` to the **credit-card** bullet (`kaname-ios-plan.md:50`, currently ending `` … `federal_scapia`. ``) and **remove** it from the **bank-account** bullet (`kaname-ios-plan.md:51`, so it ends `` … `au_bank`. ``). Verify with `git --no-pager diff -- docs/HANDOFF.md docs/kaname-ios-plan.md`: exactly two moves, IOB now appears once (CC) per file. Ref: research **D11**, `quickstart.md` §5, spec US6.

**Checkpoint**: Both roadmap docs consistently list IOB as a credit-card reader (6 CC + 4 bank); the miscategorization is corrected.

---

## Phase 10: User Story 7 — Malformed rows captured for review, never dropped or fatal (Priority: P7)

**Goal**: A line that looks like an IOB transaction but whose fields won't parse is captured in
`errored_lines` (raw, ≤240 codepoints), every good row is still returned, and nothing panics.
*(Behavior is **reused unchanged** from the ICICI `read_lines` seam — IOB adds no robustness code.)*

**Independent Test**: Mixed input (a good IOB row + one shape-matching but unparseable row) → the good
row returned, bad row captured, no error; non-transaction lines ignored silently.

- [ ] T016 [P] [US7] Add an IOB errored-line/robustness test in `core/crates/kaname-core/tests/parity.rs` (mirroring `malformed_row_is_captured_not_fatal`, `parity.rs:409–421`): a line matching the IOB shape but with an **unparseable date** (e.g. `99-XXX-9999 SOME MERCHANT 10.00 Dr`) → captured in `errored_lines` (raw, truncated to 240 codepoints via the reused `truncate_chars`), the valid row (`31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr`) still returned, **no panic** (FR-016, SC-008); header/summary/total lines → ignored (no transaction, no error). Note in the test that this exercises the **reused** `read_lines` errored-line path (`line_reader.rs`) — IOB adds no robustness code. [P] (different file from the `iob.rs` test cluster). Ref: spec US7, `line_reader.rs` read loop, `parity.rs:409–421`.

**Checkpoint**: Parser is resilient — one bad row never takes down the import.

---

## Phase 11: User Story 8 — Proven byte-for-byte against a golden fixture (Priority: P8) 🛡️ whole-slice guard

**Goal**: Make the parity harness the **reusable, regression-proof** guarantee that pins IOB (and every
future reader) to the web engine — this time proving the harness accepts the **sixth and final CC bank
as a one-fixture + one-row addition**, and that a fixture **omitting** `period_start` is asserted
`None`. *(Fixture T003; harness `Case` row + `iob_claims` test T004; greened T008.)*

**Independent Test**: The harness over the ported IOB vector matches expected output exactly, and
re-running is stable.

- [ ] T017 [US8] Finalize `core/crates/kaname-core/tests/parity.rs` as the **reusable whole-slice guard**: confirm the IOB `Case` calls `read_iob_statement`; field-by-field parity — dates (`2026-03-31`, `2026-04-04` from the **uppercase** `MAR`/`APR`), exact `Decimal` amounts (scale preserved: `"1000.00"`, `"3500.00"`; Indian grouping stripped), directions (`Credit`/`Debit` from the `Cr`/`Dr` markers), currency `INR`, `description_raw` **byte-for-byte** (`"ExampleRefundMerchant"` / `"ExampleStorePurchase"`), **`period_start` asserted `None`** (via `#[serde(default)]`), `period_end 2026-04-20`, **`card_last4 "0042"`**, `errored_lines []` (SC-001/003/011); the determinism **re-run** covers the IOB vector (SC-010); the fixture is **100% synthetic** (fabricated merchants/amounts, masked PAN `123456XXXXXX0042`; SC-004); confirm `expected` carries **no** printed-total keys (structurally proving the carve-out, SC-013); and confirm the schema stayed **stable** — IOB needed **only one `Case` row** (no struct/assertion change), proving a new line-reader bank is a **one-fixture + one-row** addition (and closing the CC set). Leave the prior fixtures untouched. Ref: `contracts/golden-fixture.md` §Harness behaviour/§Adding a future fixture, research **D9/D10**, plan §Complexity Tracking.

**Checkpoint**: Parity is an enforced guarantee for IOB and the harness stays reusable — the sixth and final CC bank landed as one row.

---

## Phase 12: User Story 9 — Privacy gate: zero network in the parse path (Priority: P9) 🛡️ inherited guard

**Goal**: Prove the IOB parse path is egress-free — **structurally** (no networking crate can even
link) and **behaviorally** (determinism) — using the **inherited** gate with **zero** new config.
*(No new script/CI: IOB adds no dependency, so the audit is byte-identical.)*

**Independent Test**: `make core-privacy-audit` passes only when zero networking crates are in the
shipped graph; the determinism test passes; no telemetry/analytics anywhere in the parse path.

- [ ] T018 [US9] Confirm the inherited privacy-egress gate stays **GREEN with ZERO changes**: run `make core-privacy-audit` → `privacy-egress: OK (no networking crate in kaname-core deps)` — IOB adds **no dependency** (runtime *or* dev), so `cargo tree -p kaname-core -e normal` is byte-identical (`Cargo.toml` unchanged — FR-019/027, SC-012); the determinism/purity assertion over the IOB vector lives in `tests/parity.rs` (T004/T017, FR-018, SC-010); confirm **no** telemetry/analytics/advertising/crash-reporter enters the parse path and **no** network entitlement/ATS is added app-side (`ios/Project.swift` `infoPlist` unchanged) (FR-021/022). Ref: research **D1**, `quickstart.md` §2, spec US9.

**Checkpoint**: Privacy-egress remains a first-class, structurally- and behaviorally-enforced gate covering IOB.

---

## Phase 13: Polish & Cross-Cutting — full iOS Local Verification Gate green

**Purpose**: Prove the whole slice is merge-ready (SC-011) and review the constitution guarantees.

- [ ] T019 [P] Light docs alignment (no behavior change, separate from the US6 roadmap fix): note the **sixth & final CC reader — a third clean single-layout drop-in (after SBI/Yes) with zero new shared helpers** where the engine/build is described (`README.md` and/or this `quickstart.md`); ensure `fixtures/README.md` reflects the IOB vector under `fixtures/iob/credit_card/`; if convenient, refresh the `statement/mod.rs` doc comment that lists issuers (`mod.rs:6–7`) so it reflects IOB landing. No stale wording.
- [ ] T020 **Run the full iOS Local Verification Gate green**, in order: `make core-lint && make core-test && make core-privacy-audit && make lint && make ios-gen && make ios-test`. ⚠️ `make core-xcframework` is rebuilt before `tuist generate` (via `ios-gen`); local requires the **"iPhone 16"** simulator; CI runs the same on **`macos-15`** (iOS job) + ubuntu (core + privacy audit). This is the SC-011 / FR-028 merge gate. Ref: `quickstart.md` §6.
- [ ] T021 [P] Final constitution review (no code change): **NO new dependency** (runtime *or* dev) — `Cargo.toml` unchanged; **NO new shared helper** and **NO composite** (SC-012 — the diff is `iob.rs` + `mod.rs` + two exports + `lib.rs` re-exports + one fixture + one `Case` row + two doc edits); **reconciliation carve-out honored** — no `_SUMMARY_RE`/`printed_total_*` anywhere (FR-013, SC-013); **`period_start` never fabricated** — asserted `None` (FR-010, SC-003); no secrets / network entitlements / copyleft (GPL/AGPL/LGPL) deps (FR-027, SC-012); all fixture/test data synthetic (SC-004); money never `f64` (amounts `Decimal`, Indian grouping stripped, scale preserved); direction from the terminal `Dr`/`Cr` marker; **`card_last4` is `Some("0042")`** (never bleeding from `16000`/`25091.5`); prior fixtures and the harness schema untouched (backward-compatible); both roadmap docs list IOB under credit-card (US6). Confirm against `git diff` before handoff. Ref: spec FR-010/FR-013/FR-014/FR-015/FR-027/SC-012/SC-013, plan §Constitution Check/§Complexity Tracking.

**Checkpoint**: Whole slice is green end-to-end and merge-ready; constitution guarantees reviewed.

---

## Phase 14: Delivery — two commits, PR, CI, merge

**Purpose**: Ship the slice in the **same two-commit shape** as the merged CC slices (`feat(core): …`
then `test(ios): …`), open the PR, watch CI, and merge. *(Generated Swift + `KanameCoreFFI.xcframework`
are git-ignored artifacts — never committed.)*

- [ ] T022 Stage & create **commit 1 — `feat(core): Indian Overseas Bank (IOB) credit-card reader (sixth & final CC reader) — single-layout drop-in; roadmap doc fix`**: `core/crates/kaname-core/src/statement/iob.rs`, `…/statement/mod.rs`, `…/ffi.rs`, `…/lib.rs`, `fixtures/iob/credit_card/basic.json`, `core/crates/kaname-core/tests/parity.rs` (Case row + `iob_claims` test + errored-row test), `docs/HANDOFF.md`, `docs/kaname-ios-plan.md`, and any `README.md`/`fixtures/README.md` alignment from T019. Commit body notes the roadmap doc correction (US6) and the two carve-outs (reconciliation; no `period_start`). Depends on T008/T017/T018 (Rust green) + T015 (docs). **Do NOT** `git add` the git-ignored iOS artifacts.
- [ ] T023 Create **commit 2 — `test(ios): IOB credit-card parse over the UniFFI bridge`**: `ios/Tests/IOBParseTests.swift` only (mirrors the git-log pattern `feat(core): …` → `test(ios): …`). Depends on T010 (Swift green).
- [ ] T024 Push the branch and open the **PR (next number: #12)** titled e.g. `P2: Indian Overseas Bank (IOB) credit-card reader (sixth & final CC reader)`; base `main`, head `011-iob-cc-reader`. Summarize: single-layout CC drop-in, zero new infra/deps, uppercase-month + inline-PAN `"0042"` verified, reconciliation & `period_start` carve-outs, roadmap doc fix, completes the 10-reader set.
- [ ] T025 **Watch CI** to green: the **core** job (ubuntu — `core-lint`, `core-test`, `core-privacy-audit`) and the **iOS** job (**`macos-15`** — `ios-gen` builds the xcframework before `tuist generate`, then `xcodebuild` on the **iPhone 16** simulator). Address any failure and re-push.
- [ ] T026 **Merge**: `gh pr merge --rebase --delete-branch` once CI is green and review approves. Verify the branch is deleted and `main` contains both commits.

**Checkpoint**: IOB is merged into `main` via a rebased, two-commit PR; the branch is deleted; the credit-card reader set (six) is complete.

---

## Dependencies & Execution Order

### Phase order

1. **Setup (P1)** → 2. **Test-First Foundation (P2, RED)** → 3. **US1 pipeline (P3)** →
4. **Bridge/Swift green (P4)** → 5–8. **US2/US3/US4/US5 verification (P5–P8)** →
9. **US6 doc fix (P9, doc-only, order-independent)** → 10. **US7 errored-lines (P10)** →
11. **US8 parity guard (P11)** → 12. **US9 privacy guard (P12)** → 13. **Polish + full gate (P13)** →
14. **Delivery: 2 commits → PR #12 → CI → merge (P14)**.

- **Test-First (Phase 2) BLOCKS all IOB parser code (Phase 3+)** — T003–T005 must exist and be RED first (Principle V, FR-024/026).
- **US1 pipeline is the critical path** and lands the behaviors US2/US3/US4/US5 verify and US7/US8/US9 guard.

### Task-level dependencies

- T003 (fixture) precedes T004 (parity `Case` row) and T008 (green).
- T004/T005 (RED tests) precede **all** implementation (T006+).
- **Chain**: T006 (`iob.rs` + `mod.rs`) → T007 (FFI exports + `lib.rs` re-exports) → T008 (Rust green).
- T007 → T009 (xcframework) → T010 (Swift green). T009 before any `tuist generate`.
- T011/T012/T013/T014 depend on T006 (they extend `iob.rs`'s test module); T016 depends on T004 (harness) + T007 (exports); T017 depends on T008; T018 depends on T008.
- **T015 (docs) depends only on Setup** — order-independent (no engine dependency).
- **T020 (full gate) depends on everything** (T010 + T015–T018); T019/T021 are docs/review only.
- **T022 (commit 1) depends on T008/T015/T017/T018**; **T023 (commit 2) depends on T010**; T024→T025→T026 are strictly sequential.

### Parallel opportunities

- **Setup**: T001 [P] + T002 [P].
- **Test-First**: T003 [P] (fixture) + T005 [P] (Swift test) are different files; T004 edits `parity.rs` (run it alone; it references T003's path).
- **Story verification**: T011/T012/T013/T014 all extend `iob.rs`'s `#[cfg(test)]` module (**same file → sequential**, though each is an independent group); **T015 [P]** (docs) and **T016 [P]** (`parity.rs`) are different files and can run alongside them.
- **Polish**: T019 [P] + T021 [P] (docs + review); T020 runs the gate alone.
- **Delivery**: strictly sequential (T022 → T023 → T024 → T025 → T026).

---

## Parallel Example: the Test-First Foundation (Phase 2)

```bash
# Author the two independent RED artifacts together (different files):
Task T003: "Author fixtures/iob/credit_card/basic.json (exact bytes from contracts/golden-fixture.md)"
Task T005: "Author ios/Tests/IOBParseTests.swift (RED core ↔ Swift IOB parse)"
# Then T004 edits tests/parity.rs (one Case row + iob_claims test) → verify RED (won't compile).
# Converge on the pipeline: T006 (iob.rs + mod.rs) → T007 (ffi.rs exports + lib.rs re-exports) → T008 (Rust green).
# T015 (doc fix) can be done any time after Setup — it has no engine dependency.
```

---

## Implementation Strategy

### MVP first (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 **RED** test-first anchors (fixture → parity `Case` row + `iob_claims`
→ Swift) → 3. Phase 3 pipeline (T006→T008) → 4. Phase 4 bridge (T009–T010).
**STOP & VALIDATE**: the golden IOB statement parses on-device through `read_iob_statement` and the
Swift suite is green. This alone is a shippable, useful slice.

### Incremental delivery

Add US2 (zero-new-infra, completing the CC set) → US3 (direction from `Dr`/`Cr`) → US4 (metadata:
`period_end` only + recovered `"0042"`) → US5 (reconciliation carve-out) — each an independent test
increment over the same reader. Land US6 (roadmap doc fix) any time after Setup. Then lock the
**guards**: US7 (errored/robustness, reused), US8 (golden parity), US9 (inherited privacy-egress).
Finish with the full-gate run (T020), then the two-commit PR (T022–T026).

### Story → task traceability

| Story | Delivered by | Independently verified by |
|---|---|---|
| **US1** parse | T005, T006, T007, T008, T009, T010 | T008 (Rust), T010 (Swift), T004 wrong-issuer |
| **US2** zero-new-infra (CC set complete) | T006 `iob.rs` (config) + T007 direct `read_lines` | **T011** (reuse tests + change-set review) |
| **US3** direction (`Dr`/`Cr`) | T006 `direction = classify(desc, dir, None)` | **T012** |
| **US4** metadata (`period_end` only, `"0042"`) | T006 `enrich` (+ reused `find_last4` anchor) | **T013** |
| **US5** reconciliation carve-out 🚫 | T006 `enrich` **omits** `_SUMMARY_RE`; `base.rs` has no `printed_total_*` | **T014** (behavior + model/source review) |
| **US6** roadmap doc fix 📝 | **T015** (`HANDOFF.md` + `kaname-ios-plan.md`) | T015 diff review (6 CC + 4 bank) |
| **US7** errored-lines | *reused* `read_lines` seam + `truncate_chars` | **T016** |
| **US8** golden parity 🛡️ | T003, T004, T008 | **T017** (reusable one-row guard) |
| **US9** privacy-egress 🛡️ | *inherited* gate + T004 determinism | **T018** |

---

## Notes

- **Test-first is mandatory** (Principle V, FR-024/026): T003–T005 are RED before Phase 3; T008 greens
  the Rust parity, T010 greens the Swift bridge — each has an explicit RED→GREEN verify step. IOB's
  `expected` is the **locked characterization ground truth** (no live capture needed — `quickstart.md`
  §0); the two IOB-specific derivations were **verified** against the real `kaname-core` helpers
  (research D4/D7).
- **Faithful port** (byte-for-byte with the golden vector): every porting task cites its exact `iob.py`
  lines/regex/behavior; `description_raw` is asserted **byte-for-byte** — `"ExampleRefundMerchant"` /
  `"ExampleStorePurchase"` (the terminal `Dr`/`Cr` marker and the amount are **not** part of it);
  `card_last4` is **`"0042"`** because the mask `123456XXXXXX0042` exposes four trailing digits, with no
  bleed from the adjacent limits (research **D3/D6/D7**).
- **🚫 Reconciliation carve-out** (research **D10**, FR-013, US5, SC-013): `statement/iob.rs` MUST NOT
  port `_SUMMARY_RE` or the `printed_total_*` assignments. The IOB `enrich` is **`period_end` + last-4
  only**; `ParsedStatement` has no such fields. Deliberate scope *reduction*, not a violation — mirrors
  `yes.rs`.
- **🚫 No fabricated `period_start`** (research **D6**, FR-010, SC-003): IOB prints only `Stmt Date`
  (the billing-cycle end) — do **not** port Yes's `PERIOD_RE`/`Statement Period` scrape; `period_start`
  stays `None`.
- **REUSE, not rebuild**: IOB adds only `iob.rs`, two exports, `lib.rs` re-exports, `pub mod iob;`, one
  fixture, one `Case` row, and two doc edits — everything else (records, `common`/`polarity` helpers,
  the `read_lines` seam, the UniFFI custom types, the parity harness, the privacy gate) is inherited
  unchanged (FR-017/019). **No new dependency** (runtime *or* dev); **no new shared helper**; **no
  composite** (contrast HDFC). IOB completes the 10-reader set (6 CC + 4 bank).
- **swift-format `[Spacing]`**: comments in `IOBParseTests.swift` go on their **own line** (no trailing
  inline comments); Rust `//` trailing comments remain fine.
- **iOS gate ordering**: `make core-xcframework` before `tuist generate` (`ios-gen: core-xcframework`);
  local + CI use the **iPhone 16** simulator; the iOS CI job is pinned to **`macos-15`**.
- **[P]** = different files, no unfinished dependency. `[Story]` labels map each task to its slice.
- **Guards protect the whole slice**: US5 (reconciliation carve-out), US8 (golden parity), and US9
  (privacy) fail the build/review on any regression to parsing behavior, scope, or egress-freedom.
- **Delivery** ships as **two commits** (`feat(core): engine+fixture+parity+docs` → `test(ios): Swift
  bridge test`), one PR (**#12**), CI watch (ubuntu core + `macos-15` iOS), then `gh pr merge --rebase
  --delete-branch`.
