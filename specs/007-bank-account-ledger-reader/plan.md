# Implementation Plan: Read a Bank-Account (Savings/Current) Statement On-Device — the Balance-Ledger Reader Base + Balance-Chain Integrity + ICICI as the First Reference Reader (Second Reader Family)

**Branch**: `007-bank-account-ledger-reader` | **Date**: 2026-07-16 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/007-bank-account-ledger-reader/spec.md`
**Milestone**: P2 (next slice) — the first bank-account (balance-ledger) reader family, after the five credit-card issuers

## Summary

Open the **second reader family** in `kaname-core` (Rust) by porting the web engine's **balance-ledger**
stack. A bank-account (savings/current) statement is a **Withdrawal / Deposit / running-Balance ledger
with NO Dr/Cr marker**, so the landed credit-card line reader (`line_reader.rs` — one signed amount + a
trailing `Dr/Cr`) **structurally cannot read it**. This slice delivers **three things together**, all as a
**pure, deterministic** parse over already-extracted text:

1. **A new reusable balance-ledger reader base** — `statement/ledger_reader.rs`, a `LedgerReaderConfig`
   trait that **mirrors `LineReaderConfig`'s shape** plus `read_ledger_lines(cfg, lines, full_text,
   first_row_words)` and `claims_ledger(cfg, text, bank_code)`. Direction is derived from the
   **running-balance delta** (balance falls ⇒ debit, rises ⇒ credit); the printed amount is an
   **independent integrity check** (`amount == |balance delta|`), **never** a source of direction.
2. **A balance-chain integrity check** — `statement/balance_chain.rs`, `check(&ParsedStatement) ->
   ChainResult` reporting **RECONCILED / NEEDS_REVIEW** with the suspect rows (a chain break is a
   **suspect**, still returned — distinct from an unparseable **errored** line).
3. **ICICI savings/current as the first reference reader** — `statement/icici_bank.rs`, a zero-sized
   `IciciBankReader` config on the new base, proven **byte-for-byte** against a golden fixture exactly as
   each credit-card issuer was.

This is a **determinism / parity** slice (Constitution Principle V): the web engine is the source of
truth — `_ledger_reader.py` (`BalanceLedgerStatementReader`, 422 lines), `balance_chain.py`
(`check`, 113 lines) and `icici_bank.py` (the ICICI reference config) were **read as ground truth** and the
port is **faithful** (values already captured in the persisted ground truth
`icici-bank-ground-truth.json`). It **REUSES the existing seams** and adds **ONE new base + ONE integrity
module + ONE reference reader**, with **ZERO new dependencies** and **ZERO networking**.

It is also the first slice to **finally use the constitution's `read_lines(lines, full_text,
first_row_words)` seam**: the core **never opens a PDF** — the first transaction row's word geometry
(`Word { text, x0, x1 }`) is supplied natively (iOS PDFKit). The reference fixture is
**opening-balance-anchored and geometry-free**, so it reconciles without exercising the x-position path
(which is supported but **not calibrated** this slice; such rows are surfaced NEEDS_REVIEW).

**Technical approach** (details in [`research.md`](./research.md); every value below is confirmed against
the persisted ground truth and the web-engine sources):

- **Port faithfully, 1:1** from
  `finance-tracker-phase/backend/app/services/ingestion/statement_readers/_ledger_reader.py`,
  `.../ingestion/balance_chain.py`, and `.../statement_readers/icici_bank.py` →
  `statement/ledger_reader.rs`, `statement/balance_chain.rs`, `statement/icici_bank.rs`. The module layout
  mirrors the web engine so the diff is mechanical and reviewable.
- **New records (all additive; extend, don't break the CC path)** — `ParsedTransaction` gains
  `pub ledger: Option<LedgerMetadata>` (CC readers set `None`; the one constructor in `line_reader.rs`
  gains `ledger: None`). New `LedgerMetadata`, `DirectionSource` (enum), `Word` (all `uniffi`);
  `ParsedStatement` gains `pub printed_opening_balance`/`printed_closing_balance: Option<Decimal>`
  (`ParsedStatement::new` defaults both to `None`). `Word.x0/x1` are **layout points, not money**, so
  `f64` is constitutionally fine (money stays `Decimal`).
- **The base** (`ledger_reader.rs`) mirrors `LineReaderConfig`: `bank_code`, `claim_all()`, `claim_any()`,
  `anchor_res()` (first-match-wins, multi-template ready), `opening_balance_re()`/`closing_balance_re()`,
  `column_split_x()`, `provisional_direction()` (default `Debit`), `enrich()` (default no-op),
  `account_tail()` (default `None`). Internals ported 1:1: `find_anchors` (named groups `serial/date/desc/
  amount` **or** `withdrawal`+`deposit`/`balance`; unparseable date/amount/balance → `errored_lines[..240]`);
  `anchor_amount` (single `amount` via `parse_amount`, else the non-zero side of a withdrawal/deposit pair
  via a **"loose" integer-or-decimal** parse, since those columns may print bare integers like `0`/`59`/
  `50000`); `stitch_narration` (line above + lines below to the next anchor, skipping other anchors and
  balance lines; inline `desc` prepended); `row1_direction` (opening balance → x-position → provisional,
  returning `(Direction, DirectionSource, prev_balance)`); delta / `amount_matches_delta`
  (**exact** `amount == |delta|` in the reader — the ₹1.00 tolerance lives **only** in `balance_chain`);
  `is_suspect = !amount_matches_delta`; `printed_opening_balance` (printed, else derived from row 1) and
  `printed_closing_balance` (last anchor balance). Pure/total — never panics; bad rows → `errored_lines`.
- **The balance chain** (`balance_chain.rs`) — `check(&ParsedStatement) -> ChainResult` with new
  `ChainStatus { Reconciled, NeedsReview }`, `Suspect { row, serial, amount, reason }`, `ChainResult
  { status, checked_rows, suspect_count, suspects (cap 20), row1_direction_fallback,
  derived_opening_balance, derived_closing_balance, reason }`. Walk from `printed_opening_balance`; per row
  compare printed amount to `|balance − prev|` with a `Decimal("1.00")` tolerance; **skip** the row-1
  amount-vs-delta check when row-1's `direction_source` is `Row1XPosition`/`Row1Provisional` (that delta is
  tautological); **RECONCILED iff** no suspects **and** row-1's source is not a fallback; empty statement →
  `NeedsReview` with `reason "no parsed transactions"`.
- **ICICI reference** (`icici_bank.rs`) — zero-sized `IciciBankReader`: `BANK_CODE "ICICI"`; anchor
  `^(?P<serial>\d{1,4})\s+(?P<date>\d{2}\.\d{2}\.\d{4})(?:\s+\d{2}\.\d{2}\.\d{4})?\s+(?P<desc>.*?)\s*
  (?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$`; opening
  `(?i)(?:Opening Balance|BALANCE\s+B/F|B/F)\s+([\d,]+\.\d{2})`; closing `(?i)Closing Balance\s+
  ([\d,]+\.\d{2})`; `column_split_x 400.0`; `claim_all ("Statement of Transactions", "ICICI")`,
  `claim_any ("Saving", "Current")`; `enrich` = full-month period regex `([A-Za-z]+ \d{1,2}, \d{4})\s+to\s+
  ([A-Za-z]+ \d{1,2}, \d{4})` → `parse_date`; `account_tail` = trailing 4 of the printed account number via
  `(?i)Account\s+(?:Number|No\.?)\s*:?\s*([0-9]{6,})` (fallback: longest ≥9-digit run) — a **bank-account**
  tail, **not** `find_last4`/masked-PAN. ICICI now has **both** a CC reader (`icici.rs`, credit_card) and
  this bank reader (`icici_bank.rs`, bank_account); they coexist behind **different claim gates**.
- **FFI** (`ffi.rs` + `lib.rs` re-exports) — add `read_icici_bank_statement(lines, full_text,
  first_row_words: Vec<Word>) -> ParsedStatement`, `icici_bank_claims(full_text) -> bool`, and
  `check_balance_chain(statement) -> ChainResult`, reusing the existing `Decimal`/`NaiveDate` custom-type
  bridges; the new records/enums derive `uniffi`. Rebuild via `make core-xcframework` (regenerates
  `ios/Generated`, git-ignored) **before** `tuist generate` (iOS gate ordering; iPhone 16 sim; macos-15 CI).
- **Golden parity harness extension** (`tests/parity.rs`) — extend `ExpectedRow` with optional
  (`#[serde(default)]`) ledger fields and `Expected` with optional `printed_opening_balance`/
  `printed_closing_balance` (CC fixtures omit them and **stay unchanged**). Add a `parse_icici_bank`
  wrapper (calls `read_icici_bank_statement` with an **empty `Vec<Word>`**, since the reference fixture is
  opening-balance-anchored) so the existing `Case` table gets **one new row**; assert the ledger fields when
  present. Add a dedicated balance-chain parity test asserting `check_balance_chain(icici_bank fixture) ==
  RECONCILED` (0 suspects, no row-1 fallback). Later HDFC/Federal/AU ledgers each add one fixture + one
  `Case` row.

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency.**
**Storage**: N/A (no persistence this slice; encrypted SQLite/SQLCipher is out of scope)
**Testing**: `cargo test` (unit + `tests/parity.rs` — the ICICI-bank golden vector with per-row ledger fields, a dedicated balance-chain RECONCILED parity test, determinism, and the bank-vs-card claim split); **Swift Testing** (`import KanameCore`) for a "core ↔ Swift ICICI bank parse + balance chain" test over the UniFFI bridge
**Target Platform**: iOS 18+ (device `aarch64-apple-ios`; simulator `aarch64-apple-ios-sim` + `x86_64-apple-ios`); core is platform-agnostic
**Project Type**: Mobile — Rust core + native SwiftUI app (monorepo `core/` + `ios/`)
**Performance Goals**: parse + chain check are sub-millisecond pure functions over a handful of lines; no throughput target this slice
**Constraints**: 100% on-device, ZERO network in the parse/chain path (FR-024/028–030, SC-010); deterministic (FR-025, SC-012); money is `rust_decimal::Decimal`, never `f64` — **only** geometry x-coordinates (`Word.x0/x1`) are `f64` layout points (FR-012/016, SC-009); direction from the balance **delta** (row 1: opening balance → x-position → flagged provisional), **never** the amount's sign/magnitude (FR-008/013/014, SC-003); **exact** `amount == |delta|` in the reader vs a **₹1.00** tolerance **only** in the balance chain (FR-009, FR-018); Apache-2.0, no GPL/AGPL/LGPL, **no new deps** (FR-034)
**Scale/Scope**: **1 new reader base** (`ledger_reader.rs`) + **1 integrity module** (`balance_chain.rs`) + **1 reference reader** (`icici_bank.rs`); **3 new records** (`LedgerMetadata`, `Word`, `Suspect`) + **2 new enums** (`DirectionSource`, `ChainStatus`) + **1 new result record** (`ChainResult`); **2 additive fields** on `ParsedTransaction` (`ledger`) and **2** on `ParsedStatement` (`printed_opening_balance`, `printed_closing_balance`); **3 exported FFI functions**; **1 golden fixture** + a **back-compatible** harness schema extension (optional ledger fields) + **1 balance-chain parity test**; **0 new dependencies**; no new app UI

## Constitution Check

*GATE: evaluated before Phase 0 and re-checked after Phase 1. Constitution v1.0.0.*

| Principle / Gate | Verdict | Evidence & how this plan complies |
|---|---|---|
| **I. Data Privacy & Sovereignty** (NON-NEGOTIABLE) — free/core = 100% on-device, zero network, no telemetry | ✅ PASS | The whole bank-account parse **and** balance-chain path is pure Rust over an in-memory `Vec<String>` + `String` + `Vec<Word>` — no sockets, HTTP, async runtime, or file/PDF I/O (FR-024/028). The core **never opens a PDF**: `first_row_words` geometry is already-extracted native input (FR-016/024). It **inherits the existing privacy-egress gate** (`make core-privacy-audit`) unchanged; **no new dependency at all** (see III), so the shipped `cargo tree -e normal` graph is byte-identical. Determinism/purity parity tests now also cover the ICICI-bank vector and the chain check (FR-025, SC-010/012). No telemetry/analytics/crash reporter added (FR-029). |
| **II. Local-First Shared Engine** — pure, deterministic, platform-agnostic Rust core via UniFFI; money never float; explicit polarity; no PDF engine in core | ✅ PASS | The new base is a **reusable** balance-ledger seam (the analogue of `line_reader.rs`) that later banks reuse (FR-003/005). This slice is the first to **use the constitution's `read_lines(lines, full_text, first_row_words)` seam** — geometry is native input, the core embeds **no PDF engine** (FR-016/024). Determinism is structural (regexes, `parse_amount`/`parse_date` are pure; `chrono`/`regex` are locale-independent; no clock/global state) (FR-025). **Money is `Decimal`, never `f64`** — amounts, balances, deltas, tolerance are all `Decimal` (FR-012); the **only** floats are `Word.x0/x1`, which are **layout points, not money** (FR-016, SC-009). Direction is **delta-derived** (row 1: opening balance → x-position → flagged provisional), recorded via `direction_source`, **never** from the amount's sign (FR-008/013/014, SC-003). |
| **III. Open-Core & Permissive Licensing** — client Apache-2.0; GPL/AGPL/LGPL forbidden; no secrets | ✅ PASS | No secrets/keys/endpoints (FR-034). **NO new runtime OR dev dependency** — the base, the chain check, and the ICICI reader are built entirely from crates already in the graph (`regex`, `rust_decimal`, `chrono`, `serde`, `uniffi`; dev `serde_json`). Nothing copyleft enters the tree; the privacy audit's `cargo tree` surface re-confirms it. |
| **IV. Native Experience & Accessibility** — latest HIG, SwiftUI, Dynamic Type, Dark Mode, VoiceOver | ✅ PASS (N/A UI) | This is an **engine slice with no new user-facing surface** — app-side PDF text/geometry extraction (PDFKit), the file-import UI, and the Share Extension are explicitly out of scope (FR-035 is conditional). The only app-side artifact is a Swift Testing suite. If a demo surface is later added it MUST follow HIG + a11y; none is added here. |
| **V. Test-First & Parity** — failing test precedes behaviour; `cargo test` + Swift Testing; privacy-egress test | ✅ PASS | **Golden-fixture parity**: the web engine's synthetic ICICI-savings characterization vector is **ported** to `fixtures/icici/bank_account/basic.json` (FR-031) and reproduced **exactly** — three rows with dates/amounts/directions/descriptions, per-row balance/delta/direction_source/serial/matches/suspect, printed opening/closing, period, account last-4, **and** a RECONCILED chain (SC-001/002/013). **Test-first**: the failing golden test + balance-chain test + bank-claims split precede the port (FR-033). Core via `cargo test`; the bridge via a "core ↔ Swift" suite. Privacy-egress + determinism guards extended to the bank path. All fixture data is **synthetic/redacted** (FR-032). |
| **iOS Local Verification Gate** — cargo fmt/clippy/test; swiftlint + swift-format; tuist generate; simulator build+test | ✅ PASS | Ordering **unchanged**: `make core-xcframework` runs **before** `tuist generate` (Makefile `ios-gen: core-xcframework`; CI builds the xcframework first). The three new exports + the new records/enums are **additive** to the bindings; the new `Word` input record and `ChainResult`/`ChainStatus`/`Suspect`/`LedgerMetadata`/`DirectionSource` types are generated into Swift, and the additive `ledger`/`printed_*` fields extend the existing records. `macos-15` stays pinned for the iOS job; the **iPhone 16** simulator (`OS=latest`) is the `xcodebuild` destination; the core (ubuntu) job's privacy audit is inherited (FR-027/035). |
| **Security & Privacy Constraints** — no network SDKs in core paths; deps reviewed & justified; synthetic fixtures; no committed secrets | ✅ PASS | No network SDK anywhere; the audit proves it structurally and **no dependency review is needed** (no new dep). All fixture data is **synthetic/redacted** — fabricated payers (`ALICE STORE`, `EMPLOYER PRIVATE LIMITED`), amounts, and a synthetic account number `000401000123456` → last-4 `3456` (FR-032, SC-008). No secrets; `.env*` remain ignored. |

**Initial gate result: PASS** — **zero new dependencies**, zero unjustified violations. The slice's real
complexity is **additive and back-compatible**: (a) new record fields (`ParsedTransaction.ledger`,
`ParsedStatement.printed_*`) that ripple **only** as `ledger: None` / `None` defaults into the CC path, and
(b) the parity-harness schema extension (optional ledger fields via `#[serde(default)]`, so CC fixtures
deserialize unchanged). Both are recorded in **Complexity Tracking** as justified, not principle
violations. No NEEDS CLARIFICATION remain (the approach is locked by the requester and confirmed against the
persisted ground truth and the web-engine sources — see [`research.md`](./research.md)). Cleared to
Phase 0/1.

## Project Structure

### Documentation (this feature)

```text
specs/007-bank-account-ledger-reader/
├── plan.md                  # This file (/speckit.plan)
├── research.md              # Phase 0 — decisions D1–D12 (all unknowns resolved, ground truth read)
├── data-model.md            # Phase 1 — new records/enums, additive fields, reused types, the ICICI config, harness rows
├── contracts/
│   ├── engine-ffi.md        # Phase 1 — additive UniFFI surface (read_icici_bank_statement, icici_bank_claims, check_balance_chain) + Word/ChainResult types
│   ├── ledger-base.md       # Phase 1 — the LedgerReaderConfig trait contract + read_ledger_lines/claims_ledger + balance_chain::check semantics
│   └── golden-fixture.md    # Phase 1 — the ICICI-bank vector + the back-compatible harness schema extension
├── quickstart.md            # Phase 1 — build, verify, run the parity + balance-chain + privacy gates
├── checklists/              # (pre-existing) requirements.md spec-quality checklist
└── tasks.md                 # Phase 2 — created by /speckit.tasks (NOT here)
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── Cargo.toml                        # UNCHANGED — no new dependency (runtime or dev)
├── uniffi.toml                       # UNCHANGED — Decimal → Foundation.Decimal map reused
├── src/
│   ├── lib.rs                        # + re-export read_icici_bank_statement, icici_bank_claims, check_balance_chain (+ new record/enum re-exports as needed)
│   ├── model.rs                      # UNCHANGED — Direction (uniffi::Enum) reused for the delta-derived polarity
│   ├── ffi.rs                        # + #[uniffi::export] read_icici_bank_statement (accepts Vec<Word>), icici_bank_claims, check_balance_chain (custom Decimal/NaiveDate bridges reused)
│   ├── statement/
│   │   ├── mod.rs                    # + pub mod ledger_reader; pub mod balance_chain; pub mod icici_bank; (+ re-exports)
│   │   ├── base.rs                   # CHANGED (additive) — ParsedTransaction gains `ledger: Option<LedgerMetadata>`; ParsedStatement gains `printed_opening_balance`/`printed_closing_balance: Option<Decimal>` (::new defaults None); new `LedgerMetadata`, `DirectionSource`, `Word` records/enum
│   │   ├── common.rs                 # UNCHANGED — parse_amount/parse_date reused; "%d.%m.%Y" and "%B %d, %Y" ICICI-savings formats ALREADY present
│   │   ├── polarity.rs               # UNCHANGED — Direction::Debit/Credit reused (the base derives them from the delta, not classify)
│   │   ├── line_reader.rs            # CHANGED (1 line) — the ParsedTransaction constructor gains `ledger: None` (CC readers carry no ledger metadata)
│   │   ├── icici.rs                  # UNCHANGED — the ICICI *credit-card* reader; coexists with icici_bank.rs behind a different claim gate
│   │   ├── hdfc.rs / sbi.rs / yes.rs / federal.rs  # UNCHANGED — existing CC readers (each still emits `ledger: None` via the shared constructor)
│   │   ├── ledger_reader.rs          # NEW — LedgerReaderConfig trait + read_ledger_lines(cfg, lines, full_text, first_row_words) + claims_ledger; find_anchors / anchor_amount / stitch_narration / row1_direction / direction_from_x_position (ported 1:1 from _ledger_reader.py)
│   │   ├── balance_chain.rs          # NEW — check(&ParsedStatement) -> ChainResult; ChainStatus/Suspect/ChainResult (ported 1:1 from balance_chain.py); ₹1.00 tolerance lives HERE only
│   │   └── icici_bank.rs             # NEW — zero-sized IciciBankReader impl LedgerReaderConfig (ICICI savings/current; account-number tail, NOT masked-PAN)
│   └── bin/uniffi-bindgen.rs         # UNCHANGED
└── tests/
    └── parity.rs                     # CHANGED (additive) — optional (#[serde(default)]) ledger fields on ExpectedRow + printed_* on Expected; + parse_icici_bank wrapper + 1 Case row; + a balance-chain RECONCILED parity test; CC fixtures/rows UNCHANGED

fixtures/
└── icici/bank_account/
    └── basic.json                    # NEW — ported synthetic ICICI-savings vector (3 rows + ledger metadata + printed opening/closing + period + account last-4 + RECONCILED chain)

ios/Tests/
└── IciciBankParseTests.swift         # NEW — "core ↔ Swift ICICI bank parse + balance chain" Swift Testing suite (over the UniFFI bridge)

Makefile                              # UNCHANGED — inherits core-test / core-privacy-audit / ios-test
.github/workflows/ci.yml              # UNCHANGED — inherits the core + iOS gates
```

**Structure Decision**: Keep the **monorepo mobile** layout (`core/` Rust + `ios/` SwiftUI) and the
`statement/` module that mirrors the web engine 1:1 — `_ledger_reader.py → statement/ledger_reader.rs`,
`balance_chain.py → statement/balance_chain.rs`, `icici_bank.py → statement/icici_bank.rs` — so the port is
a mechanical, reviewable diff. The new **base** is the direct analogue of `line_reader.rs` (a
`LedgerReaderConfig` trait + a `read_ledger_lines` free function + a `claims_ledger` gate), so the second
reader family drops in exactly as the first did, and later HDFC/Federal/AU ledgers become tiny per-issuer
configs. New records/enums live in `base.rs` alongside the existing `ParsedStatement`/`ParsedTransaction`
(the additive `ledger`/`printed_*` fields belong there); `balance_chain.rs` owns its own `ChainResult`/
`ChainStatus`/`Suspect`. Exported FFI functions stay in `ffi.rs` (pure reader/chain logic stays FFI-free and
unit-testable). Generated Swift + `KanameCoreFFI.xcframework` remain git-ignored artifacts rebuilt by
`make core-xcframework` (before `tuist generate`).

## Complexity Tracking

> **No constitution violations.** The slice adds **no new dependency**, embeds **no PDF engine**, and keeps
> money in `Decimal`. Its genuine complexity is **additive and back-compatible** — the record-field
> additions ripple into the CC path only as inert defaults, and the harness schema extension leaves every
> credit-card fixture and `Case` row unchanged. These are recorded here per the requester's ask, with the
> simpler alternative and why it is rejected.

| Item | Why (in scope this slice) | Why the alternative is rejected |
|---|---|---|
| **Additive record fields ripple to the CC path** — `ParsedTransaction` gains `ledger: Option<LedgerMetadata>` (CC readers pass `None` via the single `line_reader.rs` constructor); `ParsedStatement` gains `printed_opening_balance`/`printed_closing_balance: Option<Decimal>` (`::new` defaults `None`) | The ledger family needs per-row balance/delta/source/serial metadata and statement-level printed balances (FR-020/021); putting them on the shared records is the faithful port (web `ParsedTransaction.metadata` + `ParsedStatement.printed_*`) and lets the balance chain read them. `Option<…>` keeps them **absent** for cards. | A **separate** `ParsedLedgerStatement`/`ParsedLedgerRow` type hierarchy would duplicate every field the CC path already has, fork the parity harness in two, and block a future unified pipeline — more code and drift for no gain. The 1-line `ledger: None` at the one CC constructor is the minimal, precedented touch. |
| **Parity-harness schema extension** — `ExpectedRow` gains optional (`#[serde(default)]`) ledger fields; `Expected` gains optional `printed_opening_balance`/`printed_closing_balance` | The ICICI-bank vector must assert per-row balance/delta/direction_source/serial/matches/suspect and the printed balances (FR-031, SC-001/008); the harness is the constitution's acceptance mechanism (Principle V). | A **second** harness file for ledger fixtures would duplicate the loader/assert scaffolding. `#[serde(default)]` keeps all five CC fixtures deserializing **unchanged** (they omit the new keys), so one harness serves both families — **no CC fixture migration** (see research D9). |
| **Two-place amount-vs-delta design** — the **reader** records **exact** `amount == \|delta\|`; the **₹1.00 tolerance** lives **only** in `balance_chain` | Faithful to the web engine: `_ledger_reader.py` sets `amount_matches = amount == abs(delta)` (exact), while `balance_chain.py` uses `abs(amount - abs(delta)) > Decimal("1.00")` for the trust decision (FR-009/018). The reader flag is a precise per-row fact; the chain is the tolerant statement-level verdict. | Applying the tolerance in **both** places (or **neither**) would diverge from the ground truth and could flip `is_suspect` vs the chain's `NEEDS_REVIEW` independently. Keeping exact-in-reader / tolerant-in-chain reproduces the reference RECONCILED result and every per-row flag. **(Flagged for the requester's sanity-check — see Phase status.)** |
| **Two-column "loose" integer parse in the base** (`anchor_amount` accepts bare integers `0`/`59`/`50000` on the withdrawal/deposit pair) | The base must support the two-column Withdrawal/Deposit/Balance template that later HDFC/Federal/AU readers require (FR-005); those columns print bare integers, so the pair side needs a comma-stripped integer-or-decimal parse distinct from the currency-aware `parse_amount`. | Restricting the base to ICICI's single-`amount` template would force each later bank to re-implement the two-column anchor + narration + row-1 + chain plumbing — the exact duplication the "reusable base" exists to prevent. ICICI's fixture exercises only the single-amount path, so the loose parse is dormant but ready. **(Flagged for sanity-check.)** |
| **`Word` (`f64` x-coords) crosses the FFI** | Row-1 x-position bootstrap needs the first row's word geometry as native input (FR-013/016); `Word { text: String, x0: f64, x1: f64 }` carries it. x-coords are **layout points, not money**, so `f64` is constitutionally correct. | Encoding geometry as `Decimal` would misrepresent layout points as money and add pointless precision; passing raw PDF bytes would force a PDF engine into the core (forbidden). A tiny `uniffi::Record` of `f64` points is the minimal, honest shape. |

## Phase status

- **Phase 0 — Research**: ✅ complete → [`research.md`](./research.md) (D1–D12; all unknowns resolved;
  ground truth read from `_ledger_reader.py` / `balance_chain.py` / `icici_bank.py` and the persisted
  `icici-bank-ground-truth.json`; every golden value — the three rows + ledger metadata, printed opening
  `100000.00` / closing `143000.00`, period `2025-06-16 → 2025-07-15`, account last-4 `3456`, and the
  RECONCILED chain — accounted for, including the narration stitching that yields
  `UPI/512345/ALICE STORE/Payment`, `NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY`, `ATM CASH WITHDRAWAL`).
- **Phase 1 — Design & Contracts**: ✅ complete → [`data-model.md`](./data-model.md),
  [`contracts/engine-ffi.md`](./contracts/engine-ffi.md),
  [`contracts/ledger-base.md`](./contracts/ledger-base.md),
  [`contracts/golden-fixture.md`](./contracts/golden-fixture.md),
  [`quickstart.md`](./quickstart.md); agent context refreshed via
  `.specify/scripts/bash/update-agent-context.sh copilot`.
- **Phase 1 re-check (post-design Constitution Check)**: ✅ PASS — the design adds **no new dependency**,
  embeds **no PDF engine**, keeps **money in `Decimal`** (only `Word` x-coords are `f64` layout points), and
  derives **direction from the balance delta** with an auditable `direction_source`. The golden vector + the
  string-based `Decimal` fixture + the determinism/purity + dependency-audit gates actively **reinforce**
  the no-float-money, determinism, and privacy principles. The additive record-field changes and the
  harness schema extension are recorded in Complexity Tracking as back-compatible (no CC fixture migration),
  not shared-subsystem violations.
- **Phase 2 — Tasks**: ⏭️ NOT done here. Run `/speckit.tasks` to generate `tasks.md`, ordered test-first
  per Principle V: write the golden fixture + failing parity `Case` row + balance-chain RECONCILED test +
  bank-vs-card `icici_bank_claims` split → additive records/fields in `base.rs` (+ `ledger: None` in
  `line_reader.rs`) → `statement/ledger_reader.rs` (the base) → `statement/balance_chain.rs` (the check) →
  `statement/icici_bank.rs` (the ICICI config) → FFI exports (`read_icici_bank_statement` +
  `icici_bank_claims` + `check_balance_chain`) + `lib.rs` re-exports + `mod.rs` module wiring → Swift bridge
  test → run the inherited privacy/iOS gates.
