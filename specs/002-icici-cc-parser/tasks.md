---
description: "Task list — ICICI Credit-Card Parser (first real reader)"
---

# Tasks: Import an ICICI Credit-Card Statement On-Device (First Real Parser)

**Input**: Design documents from `/specs/002-icici-cc-parser/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md` (D1–D13), `data-model.md`,
`contracts/engine-ffi.md`, `contracts/golden-fixture.md`, `quickstart.md`

**Tests**: REQUIRED and **TEST-FIRST** for this slice (Constitution Principle V). The golden
fixture + the failing Rust parity harness (`tests/parity.rs`) and the failing Swift
"core ↔ Swift ICICI parse" test are authored **RED, before** the parser code that greens them.

**Port source of truth** (faithful, byte-for-byte with the golden vector — porting tasks cite
exact files/regexes):
`/Users/ssk/Projects/finance-tracker-phase/backend/app/services/ingestion/statement_readers/{_common,polarity,base,_line_reader,icici}.py`

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: `US1`=parse · `US2`=polarity · `US3`=metadata · `US4`=errored-lines ·
  `US5`=golden parity · `US6`=privacy-egress. Setup/Polish carry no story label.
- Exact file paths are included in every task.

## ⚠️ Local gotchas (apply throughout)

- **`make core-xcframework` MUST run before `tuist generate`** (`ios-gen: core-xcframework`) —
  the generated Swift is a rebuilt artifact (research **D11**).
- **Local Xcode 26 needs an explicitly-created "iPhone 16" simulator** for
  `make ios-test` (`xcodebuild -destination 'name=iPhone 16'`).
- Money is **`Decimal`, never `f64`**; direction comes from the **statement**, never the amount
  sign; **no lookaround** in Rust `regex` (port PAN with manual neighbor checks — **D7**).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Wire the new module + dev-dependency + fixtures location so every later task has a
place to land. No behavior yet.

- [ ] T001 [P] Add `serde_json` to `[dev-dependencies]` in `core/crates/kaname-core/Cargo.toml` (fixture harness only — **not** a runtime dep; excluded from the shipped graph by `-e normal`). Ref: plan Complexity Tracking.
- [ ] T002 Create the reader-subsystem module: new `core/crates/kaname-core/src/statement/mod.rs` (module doc + **pre-declare** `pub mod common; pub mod polarity; pub mod base; pub mod line_reader; pub mod icici;` and re-export `base::{ParsedStatement, ParsedTransaction}`), and add `pub mod statement;` + `pub use statement::{ParsedStatement, ParsedTransaction};` to `core/crates/kaname-core/src/lib.rs`. (Pre-declaring lets T007–T011 create files in parallel.) Ref: plan Project Structure, research **D1**.
- [ ] T003 [P] Create `fixtures/icici/credit_card/` and refine `fixtures/README.md` to document the **line-reader single-JSON** schema (`lines`+`full_text`+`expected`) that supersedes the `input/`+`expected/` proposal for CC readers. Ref: `contracts/golden-fixture.md`, research **D13**.

**Checkpoint**: Crate has a `statement` module seam and a fixtures home (crate will not fully compile until Phase 3 fills the modules — expected).

---

## Phase 2: Test-First Foundation (⚠️ Principle V — author RED before ANY parser code)

**Purpose**: Pin the on-device engine to the proven web engine **before** writing it. These are
the parity (US5) and bridge tests that **protect the whole slice**; they MUST be **RED** at the
end of this phase.

**⚠️ CRITICAL**: No parser code (Phase 3+) may be written until T004–T006 exist and are verified
failing.

- [ ] T004 [P] [US5] Author the golden vector `fixtures/icici/credit_card/basic.json` per `contracts/golden-fixture.md`: `lines` = the two synthetic ICICI rows; `full_text` contains `ICICI Bank`, `Statement Date May 28, 2026`, `4315XXXXXXXX1002`, then the two `\n`-joined rows; `expected.rows` = `{2026-04-29, "13628.36", Credit, INR, "4262 BBPS Payment received"}` and `{2026-05-26, "10.20", Debit, INR, "1814 Fee on gaming transaction"}`; `period_end "2026-05-28"`; `card_last4 "1002"`; `errored_lines []`. Amounts are **JSON strings**; `description_raw` **keeps the leading serial** (research **D4**). Data is 100% synthetic (FR-022, SC-003).
- [ ] T005 [US5] Author the **RED** parity harness `core/crates/kaname-core/tests/parity.rs`: `serde_json`-deserialized `Fixture`/`Expected`/`ExpectedRow` structs (amounts/dates as **strings**, re-parsed via `Decimal::from_str` / `NaiveDate::parse_from_str`; `direction` → `Direction`); resolve the fixture via `env!("CARGO_MANIFEST_DIR")` + `../../../fixtures/...`; drive it from a **reusable case table** (label, reader, relative path). Assert, calling `kaname_core::read_icici_statement`: per-row `value_date`/`amount`/`direction`/`currency`/`description_raw` equality + statement `period_end`/`card_last4`/`errored_lines` (**US5**); **determinism** — two calls equal (SC-008, **US6**); **wrong-issuer** — `icici_claims("HDFC Bank …") == false`, `icici_claims(full_text) == true` (**US1**); **malformed-row** — a row matching the shape with an unparseable date lands in `errored_lines`, valid rows still returned, no panic (**US4**). ⚠️ **Verify RED**: `make core-test` fails to compile/pass (reader + FFI absent). Ref: `contracts/golden-fixture.md`, `data-model.md` (harness types).
- [ ] T006 [P] [US1] Author the **RED** Swift bridge test `ios/Tests/ICICIParseTests.swift` — "core ↔ Swift ICICI parse" (`import KanameCore`, Swift Testing): call `readIciciStatement(lines:fullText:)` over the two synthetic lines → assert 2 rows, `lines[0]` = `2026-04-29`/`Decimal(string:"13628.36")`/`.credit`/`"INR"`, `lines[1]` = `2026-05-26`/`Decimal(string:"10.20")`/`.debit`; `periodEnd == "2026-05-28"`; `cardLast4 == "1002"`; `iciciClaims(fullText:) == true` and `false` for an HDFC string (amounts compared as exact `Foundation.Decimal`). ⚠️ **Verify RED**: won't build until the xcframework is regenerated in Phase 4. Ref: `contracts/engine-ffi.md` §Contract tests.

**Checkpoint**: Golden fixture in place; Rust parity harness RED; Swift bridge test RED. Test-first satisfied — parser code may now begin.

---

## Phase 3: User Story 1 — Parse an ICICI statement into transactions (Priority: P1) 🎯 MVP

**Goal**: Recognize an ICICI CC statement and return one transaction per spend line (date, exact
amount, direction, INR, description) — 100% on-device. Porting the pipeline here also **lands the
behaviors** that US2/US3/US4 verify independently in Phases 5–7.

**Independent Test**: `read_icici_statement(golden.lines, golden.full_text)` returns the two
expected rows and `icici_claims` accepts ICICI / rejects HDFC — with no network in the parse path.

> Port order follows the plan's chain: `common → polarity → base → line_reader → icici → FFI`.
> T007/T008/T009 touch **different files** with no interdependency → parallelizable.

- [ ] T007 [P] [US1] Create `core/crates/kaname-core/src/statement/common.rs` — port `_common.py`: `parse_amount(&str) -> Option<Decimal>` (regex `-?\(?\s*(?:₹|rs\.?|inr)?\s*([\d,]+\.\d{2})\s*\)?` case-insensitive → group 1 → `replace(',', "")` → `Decimal::from_str`; **scale preserved**, non-negative, `None` on miss/error — `_common.py:32,42-58`, D5); `parse_date(&str) -> Option<NaiveDate>` (try the **full ordered `_DATE_FORMATS` list** — `_common.py:17-30` — via `NaiveDate::parse_from_str(token.trim(), fmt)`, first success; chrono `%b/%B` are locale-independent — D6); `find_last4(text, anchor: Option<&str>) -> Option<String>` (strict core `[0-9]{2,6}[Xx*]{2,}[0-9]{4}` via `find_iter` + **manual neighbor check** that chars adjacent to the match are not `[0-9Xx*]` — **no lookaround**, D7; then the looser `(?:[0-9Xx*][ \-]?){12,}[0-9]{4}` fallback requiring a mask char; anchor tried first then whole text — `_common.py:39,116-149`). Compile regexes once via `std::sync::LazyLock`. Do **NOT** port `extract_*`/`full_text` (native extraction — FR-015). *(find_last4 serves US3.)*
- [ ] T008 [P] [US2] Create `core/crates/kaname-core/src/statement/polarity.rs` — port `polarity.py`: `classify(description: &str, dr_cr_marker: Option<&str>, amount_cell: Option<&str>) -> Direction` with precedence exactly as source (`polarity.py:82-105`): (1) `normalise_marker` — strip `[^A-Za-z-]`, uppercase; `{CR,C,CREDIT,CRDR-CR}`→Credit, `{DR,D,DEBIT,CRDR-DR}`→Debit (`:23-24,57-69`); (2) `is_parenthesised_credit` — trimmed cell starts `(` and ends `)` → Credit (`:72-79`); (3) any `_CREDIT_KEYWORDS` substring (casefold) → Credit — port all 10 (`payment received`, `received, thank you`, `received thank you`, `refund`, `reversal`, `reversed`, `cashback`, `cash back`, `credit adjustment`, `autopay received`) (`:28-39`); (4) default Debit. The amount value/sign is **never** consulted (FR-008). `_DEBIT_KEYWORDS` is non-functional → port as a doc comment or omit (D8).
- [ ] T009 [P] [US1] Create `core/crates/kaname-core/src/statement/base.rs` — port `base.py` records (only this slice's fields; **omit** the five reconciliation `printed_*` fields): `ParsedTransaction { value_date: NaiveDate, amount: Decimal, direction: Direction, currency: String, description_raw: String, bank_code: String }` and `ParsedStatement { bank_code: String, lines: Vec<ParsedTransaction>, errored_lines: Vec<String>, period_start: Option<NaiveDate>, period_end: Option<NaiveDate>, card_last4: Option<String>, confidence: f64 }`, both `#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]`; constructor defaults `lines`/`errored_lines` empty, options `None`, `confidence = 1.0` (`base.py:26-51`). Add `const MAX_RAW: usize = 240` and `truncate_chars(s: &str, max: usize) -> String` (codepoint-safe `chars().take(max)` — **never** byte-slice, D12). *(truncate_chars serves US4; records are the US1 output shape — `data-model.md`.)*
- [ ] T010 [US1] Create `core/crates/kaname-core/src/statement/line_reader.rs` — port `_line_reader.py` (the reusable seam, FR-017): `LineReaderConfig` trait (`bank_code`, `claim_markers`, `row_re`, `direction(&caps, desc) -> Direction`, `enrich(&mut ParsedStatement, &str)` **default no-op**, and `date_group`/`desc_group`/`amount_group` defaulting to `"date"/"desc"/"amount"` — research **D2**); `read_lines<C: LineReaderConfig>(cfg, lines: &[String], full_text: &str) -> ParsedStatement` reproducing `read_lines` (`_line_reader.py:53-85`): for each line `row_re.captures`; no match → **skip** (non-txn lines ignored, FR-005); else `parse_date(date_group)` + `parse_amount(amount_group)`; if **either** `None` → push `truncate_chars(line, 240)` to `errored_lines` and continue (FR-014); else build `ParsedTransaction { value_date, amount, direction: cfg.direction(&caps, desc), currency: "INR".into(), description_raw: truncate_chars(desc.trim(), 240), bank_code }`; after the loop call `cfg.enrich(&mut st, full_text)`; and `claims<C>(cfg, text: &str, bank_code: &str) -> bool` = `bank_code == cfg.bank_code()` AND any marker `casefold` contained in `text.casefold()` (`:44-48`). *(happy path = US1; `errored_lines` branch = US4; `direction`/`enrich` hooks = US2/US3.)* Depends on T007, T009.
- [ ] T011 [US1] Create `core/crates/kaname-core/src/statement/icici.rs` — port `icici.py`: zero-sized `IciciReader` `impl LineReaderConfig` with `bank_code() = "ICICI"`, `claim_markers() = ["ICICI Bank"]`, `row_re()` = `^(?P<date>\d{2}/\d{2}/\d{4})\d*\s+(?P<desc>.+?)(?:\s+\d+)?\s+(?P<amount>[\d,]+\.\d{2})(?:\s+(?P<dir>CR))?$` (`icici.py:24-27`; captures verified byte-for-byte vs Python — D3), `direction(caps, desc)` = `classify(desc, caps.name("dir").map(|m| m.as_str()), None)` (mirrors `marker_direction("dir")`), and `enrich(st, full_text)` = set `period_end` from `_STMT_DATE_RE` `\b([A-Z][a-z]{2,8} \d{1,2}, \d{4})\b` → `parse_date` and `card_last4 = find_last4(full_text, None)` (`icici.py:28,31-36`). `LazyLock` the two regexes. *(row/claims = US1; enrich = US3.)* Depends on T008, T010.
- [ ] T012 [US1] Add the UniFFI exports in `core/crates/kaname-core/src/ffi.rs`: `#[uniffi::export] pub fn read_icici_statement(lines: Vec<String>, full_text: String) -> ParsedStatement` (wraps `read_lines(&IciciReader, &lines, &full_text)`) and `#[uniffi::export] pub fn icici_claims(full_text: String) -> bool` (wraps `claims(&IciciReader, &full_text, "ICICI")`) — total functions, never throw (`contracts/engine-ffi.md`, D10). **Reuse** the existing `Decimal`/`NaiveDate` custom types + `Direction` enum unchanged. Ensure `core/crates/kaname-core/src/lib.rs` re-exports `read_icici_statement`, `icici_claims`, `ParsedStatement`, `ParsedTransaction` so `tests/parity.rs` and the app path can reach them.
- [ ] T013 [US1] **Green the engine side**: run `make core-test` — `tests/parity.rs` (T005) now **PASSES** (rows exact, `period_end 2026-05-28`, `card_last4 "1002"`, `errored_lines` empty, determinism, wrong-issuer, malformed-row) — and `make core-lint` (fmt + clippy `-D warnings`). Verify **RED→GREEN** for the Rust parity harness. Ref: `quickstart.md` §1.

**Checkpoint**: The engine parses the golden ICICI statement and the Rust parity + determinism + wrong-issuer + malformed-row tests are green. US1 is functional on the Rust side (Swift bridge greened in Phase 4).

---

## Phase 4: UniFFI bridge — regenerate the xcframework + green the Swift test (US1)

**Goal**: Surface the new functions to Swift and green the "core ↔ Swift ICICI parse" test.

- [ ] T014 [US1] Run `make core-xcframework` to rebuild `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift` (git-ignored artifacts) now exposing `readIciciStatement`, `iciciClaims`, `ParsedStatement`, `ParsedTransaction`. ⚠️ **MUST run before `tuist generate`** (research **D11**). Ref: `quickstart.md` §3.
- [ ] T015 [US1] Run `make ios-test` (`ios-gen` depends on `core-xcframework` → `tuist generate` → `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test`) to **green** `ios/Tests/ICICIParseTests.swift` (T006). ⚠️ **Local Xcode 26: create the "iPhone 16" simulator first.** Verify **RED→GREEN** for the Swift bridge test. Ref: `quickstart.md` §4.

**Checkpoint**: US1 MVP fully delivered end-to-end (Rust engine + Swift bridge). A person's ICICI statement text → transactions, on-device.

---

## Phase 5: User Story 2 — Direction from the statement, never the amount's sign (Priority: P2)

**Goal**: Every transaction's direction reflects the statement's own Dr/Cr indication (marker →
credit-language → default debit), never the amount value. *(Impl landed in T008/T011.)*

**Independent Test**: Rows with a `CR` marker, credit-type language without a marker, and ordinary
spends classify Credit/Credit/Debit — unchanged by the amount's sign or magnitude.

- [ ] T016 [P] [US2] Add polarity unit tests in `core/crates/kaname-core/src/statement/polarity.rs` (`#[cfg(test)]`): trailing `CR` → Credit (FR-009); no marker + credit keyword (`refund`, `payment received`, `reversal`, `cashback`) → Credit (FR-010); ordinary spend (`Fee on gaming transaction`) → Debit; parenthesised `(1,200.00)` → Credit; and a case proving a large/"negative-looking" amount does **not** change the result (FR-008, SC-004). These cover the keyword/parenthesised paths the golden vector does not exercise.

**Checkpoint**: Polarity rules independently verified across marker/keyword/default/parenthesised paths.

---

## Phase 6: User Story 3 — Statement metadata: billing-period end + card last-4 (Priority: P3)

**Goal**: Recover `period_end` (statement/closing date) and `card_last4` (masked PAN), else leave
unset — never fabricated. *(Impl landed in T007 `find_last4` + T011 `enrich`.)*

**Independent Test**: `Statement Date May 28, 2026` → `period_end 2026-05-28`; `4315XXXXXXXX1002`
→ `card_last4 "1002"`; text with neither → both `None`, transactions still returned.

- [ ] T017 [P] [US3] Add metadata unit tests in `core/crates/kaname-core/src/statement/icici.rs` (`#[cfg(test)]`, driving `enrich`/`read_icici_statement`): `period_end` parsed from the `Statement Date May 28, 2026` header (`_STMT_DATE_RE` + `parse_date %b %d, %Y`) = `2026-05-28` (SC-003, FR-011); `card_last4` from the masked PAN = `"1002"` (FR-012); and a **missing-metadata** input (no closing date / no masked PAN) → both `None` while rows are still returned (FR-013, US3-S3) — the branch the golden vector does not cover.

**Checkpoint**: Metadata extraction (and its absence) independently verified.

---

## Phase 7: User Story 4 — Malformed rows captured for review, never dropped or fatal (Priority: P4)

**Goal**: A row that looks like a transaction but whose fields won't parse is captured in
`errored_lines` (raw, bounded to 240 codepoints), every good row is still returned, and nothing
panics. *(Impl landed in T010 read loop + T009 `truncate_chars`.)*

**Independent Test**: Mixed input (good rows + one unparseable row) → all good rows returned, bad
row captured, no error; non-transaction lines ignored silently.

- [ ] T018 [P] [US4] Add errored-line + robustness unit tests in `core/crates/kaname-core/tests/parity.rs` (or a `#[cfg(test)]` module in `line_reader.rs`): a row matching `row_re` but with an unparseable date (`99/99/9999 …`) or amount → lands in `errored_lines`, valid rows still returned, **no panic** (FR-014, SC-006); the captured raw is **truncated to 240 codepoints** on a multibyte over-length line (D12, proving no byte-slice panic); header/summary/balance/total lines and empty input → **no** transactions and **no** errors (FR-005; empty-list-no-error edge case).

**Checkpoint**: Parser is resilient — one bad row never takes down the import.

---

## Phase 8: User Story 5 — Proven byte-for-byte against golden fixtures (Priority: P5) 🛡️ whole-slice guard

**Goal**: Make the parity harness the **reusable, regression-proof** mechanism that pins ICICI (and
every future reader) to the web engine. *(Fixture + assertions authored T004/T005, greened T013.)*

**Independent Test**: Running the harness over the ported synthetic vector matches expected output
exactly, and re-running is stable.

- [ ] T019 [US5] Finalize `core/crates/kaname-core/tests/parity.rs` as the **reusable whole-slice guard**: confirm it is data-driven via the case table (adding a future reader = **one row**: label + reader + `fixtures/<bank>/<kind>/<name>.json`), asserts field-by-field parity + a determinism **re-run** (SC-008/SC-009), and that `fixtures/icici/credit_card/basic.json` is **100% synthetic** (fabricated merchant/amount, masked PAN `…1002`; SC-003, FR-022). Add the "add a future fixture" note to `specs/002-icici-cc-parser/quickstart.md` §"Add another golden fixture" if not already present. Ref: `contracts/golden-fixture.md` §Adding a future fixture.

**Checkpoint**: Parity is an enforced guarantee and the harness is reusable by later bank/card readers.

---

## Phase 9: User Story 6 — Privacy gate: zero network in the parse path (Priority: P6) 🛡️ whole-slice guard

**Goal**: Prove egress-freedom **structurally** (no networking crate can even link) and
**behaviorally** (determinism), wired into the core gate + CI. *(Determinism assertion authored in
T005.)*

**Independent Test**: `make core-privacy-audit` passes only when zero networking crates are in the
shipped graph; the determinism test passes; no telemetry/analytics anywhere.

- [ ] T020 [US6] Create `core/scripts/privacy-egress-audit.sh` (executable): run `cargo tree -p kaname-core -e normal --prefix none` over the **shipped, default-feature** graph and **fail** if any denylist networking crate appears (`reqwest`, `hyper`, `h2`, `tokio`, `async-std`, `ureq`, `curl`, `isahc`, `surf`, `native-tls`, `openssl`, `rustls`, `quinn`, `tonic`, `socket2`, `mio`, `trust-dns`, …); on success print `privacy-egress: OK (no networking crate in kaname-core shipped deps)`. `-e normal` correctly excludes the `serde_json` **dev**-dep. Ref: research **D9**, `quickstart.md` §2.
- [ ] T021 [US6] Add a `core-privacy-audit` target to `Makefile` (runs `./core/scripts/privacy-egress-audit.sh`) and add it to `.PHONY`. Ref: `quickstart.md` §2/§5.
- [ ] T022 [US6] Wire the gate into CI: add a `make core-privacy-audit` step to the **core** job in `.github/workflows/ci.yml` (ubuntu, after the test step). Ref: plan Project Structure (CI), `quickstart.md` §5.
- [ ] T023 [P] [US6] Confirm the **behavioral** half: the determinism/purity assertion (two `read_icici_statement` calls on the same input are equal) lives in `core/crates/kaname-core/tests/parity.rs` (FR-016, SC-007/008), and that no network entitlement / ATS / analytics / crash-reporter is introduced app-side (`ios/Project.swift` `infoPlist` has no network keys; no telemetry SDK added). FR-018/019/020, SC-011.

**Checkpoint**: Privacy-egress is a first-class, automated, structurally- and behaviorally-enforced gate.

---

## Phase 10: Polish & Cross-Cutting — full iOS Local Verification Gate green

**Purpose**: Prove the whole slice is merge-ready (SC-010) and review the constitution guarantees.

- [ ] T024 [P] Light docs alignment: note the first real parser + the new `core-privacy-audit` gate where the build is described (`README.md` and/or `specs/002-icici-cc-parser/quickstart.md`); ensure no stale "not yet populated" wording remains in `fixtures/README.md`.
- [ ] T025 **Run the full iOS Local Verification Gate green**, in order: `make core-lint && make core-test && make core-privacy-audit && make lint && make ios-gen && make ios-test`. ⚠️ `make core-xcframework` is rebuilt before `tuist generate` (via `ios-gen`); local Xcode 26 requires the **"iPhone 16"** simulator. This is the SC-010 / FR-025 merge gate. Ref: `quickstart.md` §5.
- [ ] T026 [P] Final constitution review (no code change): no secrets / network entitlements / copyleft (GPL/AGPL/LGPL) deps added (FR-024, SC-011); `serde_json` is dev-only and excluded by `-e normal`; all fixture/test data is synthetic (SC-003); money never `f64`, direction never from amount sign. Confirm against `git diff` before handing off for review.

---

## Dependencies & Execution Order

### Phase order

1. **Setup (P1)** → 2. **Test-First Foundation (P2, RED)** → 3. **US1 pipeline (P3)** →
4. **Bridge/Swift green (P4)** → 5–7. **US2/US3/US4 verification (P5–P7)** →
8–9. **US5/US6 guards (P8–P9)** → 10. **Polish + full gate (P10)**.

- **Test-First (Phase 2) BLOCKS all parser code (Phase 3+)** — T004–T006 must exist and be RED first (Principle V).
- **US1 pipeline is the critical path** and lands the behaviors US2/US3/US4 verify.

### Task-level dependencies

- T002 (module skeleton) precedes T007–T012.
- T004 (fixture) precedes T005/T013; T005/T006 (RED tests) precede all implementation.
- **Chain**: T007 + T009 → **T010** → (with T008) **T011** → **T012** → **T013** (Rust green).
- T012 → **T014** (xcframework) → **T015** (Swift green). T014 before any `tuist generate`.
- T016/T017/T018 depend on their impl (T008/T007+T011/T010) being present.
- T020 → T021 → T022 (script → make → CI). T023 depends on T005.
- **T025 (full gate) depends on everything**; T024/T026 are docs/review only.

### Parallel opportunities

- **Setup**: T001 [P] + T003 [P] (T002 edits `lib.rs`, run it alone).
- **Test-First**: T004 [P] + T006 [P] (T005 authored alongside; different files).
- **Pipeline leaves**: **T007, T008, T009 run in parallel** [P] — three independent new files
  (`common.rs`, `polarity.rs`, `base.rs`) with no interdependency (module pre-declared in T002).
- **Story verification**: T016 [P], T017 [P], T018 [P] are independent test-only tasks (distinct
  files/modules) once their impl exists.
- **Privacy/polish**: T023 [P], T024 [P], T026 [P].

---

## Parallel Example: the pipeline leaves (Phase 3)

```bash
# After T002 (module skeleton) + Phase 2 RED tests, port the three independent leaf modules together:
Task T007: "Port _common.py → core/crates/kaname-core/src/statement/common.rs (parse_amount, parse_date, find_last4)"
Task T008: "Port polarity.py → core/crates/kaname-core/src/statement/polarity.rs (classify -> Direction)"
Task T009: "Port base.py   → core/crates/kaname-core/src/statement/base.rs (ParsedStatement/ParsedTransaction + truncate_chars)"
# Then converge: T010 (line_reader) → T011 (icici) → T012 (ffi) → T013 (green).
```

---

## Implementation Strategy

### MVP first (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 **RED** test-first anchors → 3. Phase 3 pipeline (T007→T013) →
4. Phase 4 bridge (T014–T015). **STOP & VALIDATE**: the golden ICICI statement parses on-device
and the Swift suite is green. This alone is a shippable, useful slice.

### Incremental delivery

Add US2 (polarity edge cases) → US3 (metadata + missing case) → US4 (errored/robustness) — each an
independent test-only increment over the same pipeline. Then lock the **guards**: US5 (reusable
parity) and US6 (privacy-egress gate + CI). Finish with the full-gate run (T025).

### Story → task traceability

| Story | Delivered by | Independently verified by |
|---|---|---|
| **US1** parse | T006, T007, T009, T010, T011, T012, T013, T014, T015 | T013 (Rust), T015 (Swift), T005 wrong-issuer |
| **US2** polarity | T008 (+ T011 wiring) | **T016** |
| **US3** metadata | T007 `find_last4` + T011 `enrich` | **T017** |
| **US4** errored-lines | T009 `truncate_chars` + T010 read loop | **T018** (+ T005 malformed-row) |
| **US5** golden parity 🛡️ | T004, T005, T013 | **T019** (reusable guard) |
| **US6** privacy-egress 🛡️ | T005 determinism + T020, T021, T022 | **T023** |

---

## Notes

- **Test-first is mandatory** (Principle V): T004–T006 are RED before Phase 3; T013 greens the Rust
  parity, T015 greens the Swift bridge — each has an explicit RED→GREEN verify step.
- **Faithful port** (byte-for-byte with the golden vector): every porting task cites its exact
  `statement_readers/*.py` source + regex/behavior; `description_raw` **keeps the leading serial**
  (e.g. `"4262 BBPS Payment received"`, research D4).
- **[P]** = different files, no unfinished dependency. `[Story]` labels map each task to its slice.
- **Guards protect the whole slice**: US5 (parity) and US6 (privacy) fail the build on any
  regression to parsing behavior or egress-freedom.
- **Do not commit** — the author will review and commit.
