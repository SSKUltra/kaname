# Phase 0 — Research: Bank-Account Balance-Ledger Reader Base + Balance-Chain Integrity + ICICI Reference Reader

**Feature**: `007-bank-account-ledger-reader` | **Date**: 2026-07-16
**Method**: The web engine is the source of truth. Its balance-ledger stack —
`finance-tracker-phase/backend/app/services/ingestion/statement_readers/_ledger_reader.py`
(`BalanceLedgerStatementReader`, 422 lines), `.../ingestion/balance_chain.py` (`check`, 113 lines), and
`.../statement_readers/icici_bank.py` (the ICICI reference config) — was **read as ground truth**, together
with the shared `base.py`/`_common.py`/`polarity.py`. The expected output is the **persisted ground truth**
`icici-bank-ground-truth.json`. Every decision below is a faithful port or a justified, verified idiomatic
Rust mapping onto the **landed** `kaname-core` seams (`line_reader.rs`, `base.rs`, `common.rs`,
`polarity.rs`, `ffi.rs`, `tests/parity.rs`).

All NEEDS CLARIFICATION are resolved; the approach was **locked by the requester** and confirmed here
against the sources. **Headline finding: this is the biggest engine slice so far, yet it needs no new
dependency and no PDF engine. The shared date parser already carries the two ICICI-savings formats
(`%d.%m.%Y`, `%B %d, %Y` — `common.rs:29–30`), `parse_amount` already handles the Indian `1,23,456.78`
grouping, and `Direction` already exists. The new surface is exactly: one base (the ledger analogue of
`line_reader.rs`), one integrity module, one ICICI config, additive record fields, three FFI exports, and a
back-compatible harness extension.**

The two behaviours worth a requester sanity-check — (a) **exact** `amount == |delta|` in the reader vs the
**₹1.00** tolerance living **only** in the chain, and (b) the **two-column "loose" integer** parse — are
called out explicitly (D6, D4) and confirmed faithful to the web engine.

---

## D1 — Add a new reusable base `statement/ledger_reader.rs`, structured as the ledger analogue of `line_reader.rs`

**Decision**: Introduce `statement/ledger_reader.rs` with a `LedgerReaderConfig` trait **mirroring
`LineReaderConfig`'s shape**, plus free functions `read_ledger_lines<C: LedgerReaderConfig + ?Sized>(cfg,
lines: &[String], full_text: &str, first_row_words: &[Word]) -> ParsedStatement` and `claims_ledger<C:
?Sized>(cfg, text, bank_code) -> bool`. Reuse **unchanged**: `ParsedStatement`/`ParsedTransaction`
(`base.rs`), `parse_amount`/`parse_date` (`common.rs`), `Direction` (`model.rs`), the UniFFI bridge
(`ffi.rs`), the parity harness (`tests/parity.rs`), and the privacy-egress gate + CI.

**Trait surface** (ported from `BalanceLedgerStatementReader.__init__` config): `bank_code() ->
&'static str`; `claim_all() -> &'static [&'static str]`; `claim_any() -> &'static [&'static str]`;
`anchor_res() -> &'static [&'static Regex]` (first-match-wins, so a bank can carry several templates);
`opening_balance_re() -> Option<&'static Regex>`; `closing_balance_re() -> Option<&'static Regex>`;
`column_split_x() -> Option<f64>`; `provisional_direction() -> Direction` (default `Debit`); `enrich(&self,
&mut ParsedStatement, &str)` (default no-op); `account_tail(&self, &str) -> Option<String>` (default
`None`).

**Rationale**: The credit-card family already proved this exact pattern (a per-issuer config trait + a
shared `read_lines` free function + a `claims` gate). The balance-ledger family is a **different row model**
(no Dr/Cr; direction from the balance delta; anchor + narration stitching; row-1 bootstrap), so it gets its
**own** base rather than contorting `LineReaderConfig` — but the **shape** is deliberately identical so the
second family reads like the first. This is what makes "the second reader family" real (FR-003) and lets
HDFC/Federal/AU drop in as tiny configs later (FR-005).

**Alternatives**: (a) Extend `LineReaderConfig` with ledger hooks — rejected: it would bloat the CC seam
with balance/geometry/anchor concepts irrelevant to Dr/Cr readers and blur two genuinely different row
models. (b) A trait-object registry keyed by `(bank_code, account_kind)` (as the web `registry.py` does) —
deferred: the Rust core exposes readers as **explicit FFI functions** (`read_icici_statement`,
`read_hdfc_statement`, …), so this slice adds `read_icici_bank_statement` the same way; a registry is not
needed to ship ICICI and would be speculative infrastructure (YAGNI).

---

## D2 — `find_anchors`: named-group anchors, first-match-wins, unparseable → `errored_lines[..240]`

**Decision**: Port `_find_anchors` 1:1. For each input line, try each regex in `anchor_res()` in order
(first match wins). On a match, read the named groups: `date` (via `parse_date`), the amount (via
`anchor_amount`, D4), and `balance` (via `parse_amount`). If **any** of `date`/`amount`/`balance` fails to
parse, push `truncate_chars(line, MAX_RAW)` (MAX_RAW = 240, already in `base.rs`) to `errored_lines` and
continue — **never** panic, **never** drop a good row. Capture optional `serial` and `desc` groups when the
pattern defines them (guard with the pattern's group names, mirroring Python's `pattern.groupindex`). A line
that matches **no** anchor is silently skipped (header/cheque-number/balance lines — FR-006).

**Rationale**: Faithful to the web engine and identical in spirit to `line_reader.rs`'s
"matched-but-unparseable → `errored_lines`, else skip" contract (`line_reader.rs:58–71`). Keeps the reader
**pure and total** (FR-019/025). The 240-cap and `truncate_chars` are the existing, codepoint-safe helpers.

**Group-presence check**: Rust `regex::Regex` exposes `capture_names()`; the base will precompute (or
check) whether a pattern defines `serial`/`desc`/`withdrawal`/`deposit` so a single-amount pattern and a
two-column pattern both work through one code path (mirrors `groups = pattern.groupindex`).

**Alternatives**: Returning a `Result`/raising on a bad row — rejected: violates FR-019 (bad rows are
captured, not fatal) and breaks the "still return every good row" guarantee.

---

## D3 — `stitch_narration`: line-above + lines-below to the next anchor, skipping anchors and balance lines; inline `desc` prepended

**Decision**: Port `_stitch_narration` exactly. For anchor `k` at line index `idx_k`: candidate lines are
(A) the single line **immediately above** (`idx_k − 1`, the payer/VPA wrap) and (B) the lines **below**
`idx_k` up to `anchors[k+1].index − 1` (exclusive) — i.e. the detail lines that belong to this transaction,
stopping before the next transaction's own above-line. Build the narration by first pushing the anchor's
inline `desc` (when non-empty), then each candidate line that is **not** another anchor index, **not**
empty, and **not** a balance line (`opening_re`/`closing_re` match). Join with single spaces and trim.
Truncate to 240 (`truncate_chars`).

**Verified against the ground truth** (line indices from `icici-bank-ground-truth.json.lines`):

- Row 1 (anchor idx 7, `inline_desc` empty): above = idx 6 `"UPI/512345/ALICE STORE/Payment"`; below range
  `(8, 8)` empty → narration **`UPI/512345/ALICE STORE/Payment`**. ✓
- Row 2 (anchor idx 9, `inline_desc` empty): above = idx 8 `"NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY"`;
  below range `(10, 9)` empty → narration **`NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY`**. ✓
- Row 3 (anchor idx 10, `inline_desc` = `"ATM CASH WITHDRAWAL"`): above = idx 9 (an anchor → skipped);
  below range `(11, 12)` = idx 11 `"Closing Balance 1,43,000.00"` (balance line → skipped) → narration =
  inline **`ATM CASH WITHDRAWAL`**. ✓

**Rationale**: Reproduces all three descriptions in the ground truth exactly (SC-001). The "skip other
anchors and balance lines" rule is what prevents a neighbouring transaction's serial line or the printed
closing-balance line from leaking into a narration (FR-007).

**Alternatives**: Only using the inline `desc` — rejected: rows 1 and 2 have empty inline `desc` and rely on
the above-line wrap; only using the above-line — rejected: row 3's text is inline. The web engine's
above+below+inline union is required.

---

## D4 — `anchor_amount`: single `amount` via `parse_amount`, else the non-zero side of a withdrawal/deposit pair via a **"loose" integer-or-decimal** parse *(sanity-check item)*

**Decision**: Port `_anchor_amount` 1:1. If the matched pattern defines an `amount` group, return
`parse_amount(amount)` (the currency-aware Indian-grouping parser). Otherwise (a two-column template) read
`withdrawal`/`deposit` via a **loose** parser `loose_amount(token)`: strip commas + trim, then
`Decimal::from_str`; accept a **bare integer** (`0`, `59`, `50000`) or a decimal (`1,314.90`). Return the
**non-zero** side (withdrawal first, then deposit); if both are zero/absent, return whichever is present.
Direction is **still** derived from the balance delta, so the printed amount stays an independent integrity
check regardless of which column it came from (FR-008/009).

**Why a separate loose parser**: `parse_amount` (`common.rs`) requires a `\d+\.\d{2}` money shape (its
`AMOUNT_RE` mandates two decimals), so it would reject a bare-integer withdrawal/deposit cell. The anchor
regex has **already** constrained the token to digits/commas, so `loose_amount` just needs comma-strip +
`Decimal::from_str` — mirroring the web `_loose_amount`.

**Scope note (sanity-check)**: ICICI's single-amount template uses the `amount` group only, so **the loose
path is dormant for this slice**. It exists so the base is genuinely reusable for the later two-column banks
(FR-005); the reference fixture does not exercise it. **Flagged for the requester** (per the plan's
Complexity Tracking) because it is code that ships without a fixture exercising it this slice — it is
covered by a small **unit test** in `ledger_reader.rs` (a synthetic two-column line) rather than a golden
fixture, matching how the web engine unit-tests the two-column path.

**Alternatives**: Reuse `parse_amount` for the columns — rejected: it rejects bare integers. Add a second
`\d{2}`-optional branch to `AMOUNT_RE` — rejected: it would loosen the shared money parser used by every CC
reader (risking parity drift) for a bank-only need; a local `loose_amount` is the minimal, isolated choice.

---

## D5 — `row1_direction`: opening balance → x-position → flagged provisional, returning `(Direction, DirectionSource, prev_balance)`

**Decision**: Port `_row1_direction` + `_direction_from_x_position` exactly.

1. **Opening balance present** (`opening: Some`): `direction = if balance < opening { Debit } else {
   Credit }`; source `OpeningBalance`; `prev_balance = opening`.
2. **Else x-position** (`column_split_x` set **and** `first_row_words` non-empty): among the row's words,
   keep those whose text is a money token (`^[\d,]+\.\d{2}$`) parsed via `parse_amount`; the **rightmost**
   (max `x1`, falling back to `x0`) is the running balance; find the word whose value **equals the amount**;
   its horizontal **center** `(x0 + x1) / 2` vs `column_split_x` decides `Debit` (left) / `Credit` (right);
   source `Row1XPosition`; `prev_balance = balance + amount` (debit) or `balance − amount` (credit).
3. **Else provisional**: `direction = provisional_direction()` (default `Debit`); source `Row1Provisional`;
   `prev_balance = balance ± amount` as above.

`DirectionSource` (new `uniffi::Enum`) has exactly `OpeningBalance | BalanceDelta | Row1XPosition |
Row1Provisional` (FR-014). Every row after the first is `BalanceDelta`: `direction = if balance <
prev_balance { Debit } else { Credit }`.

**Verified against ground truth**: row 1 has `opening = 100000.00` (printed), `balance = 95000.00` →
`95000 < 100000` ⇒ **Debit**, source **OpeningBalance**, `prev = 100000` ⇒ `delta = −5000` ⇒
`amount_matches = (5000 == 5000)` ⇒ **not** suspect. Rows 2/3 use the delta: `145000 > 95000` ⇒ Credit;
`143000 < 145000` ⇒ Debit; sources **BalanceDelta**. ✓ (matches `direction_source` `opening_balance`,
`balance_delta`, `balance_delta` in the ground truth).

**Geometry types**: `Word { text: String, x0: f64, x1: f64 }` — x-coords are **layout points, not money**,
so `f64` is correct (FR-016, SC-009). The reference fixture is geometry-free, so `read_icici_bank_statement`
is called with an **empty `Vec<Word>`** in the harness (D10).

**Alternatives**: Deriving row 1 from the amount's sign — rejected outright (the invariant the whole family
exists to avoid, FR-008). Trusting an x-position/provisional row silently — rejected: FR-015/018 require
NEEDS_REVIEW for any un-calibrated first-row decision.

---

## D6 — Amount-vs-delta: **exact** `amount == |delta|` in the reader; the **₹1.00 tolerance** lives **only** in `balance_chain` *(sanity-check item)*

**Decision**: Reproduce the web engine's **two-place** design faithfully.

- **In the reader** (`ledger_reader.rs`): `delta = balance − prev_balance` (when `prev_balance` is set);
  `amount_matches_delta = delta.is_some() && amount == delta.abs()` — **exact** `Decimal` equality, no
  tolerance. `is_suspect = !amount_matches_delta`. These per-row flags are recorded in `LedgerMetadata`.
- **In the chain** (`balance_chain.rs`): the trust decision compares `(amount − |delta|).abs() >
  Decimal("1.00")` — the **₹1.00** rounding tolerance — to decide whether a row is a chain-break suspect.

**Evidence** (web sources): `_ledger_reader.py` → `amount_matches = delta is not None and amount ==
abs(delta)` (exact); `balance_chain.py` → `_TOLERANCE = Decimal("1.00")` and `if abs(line.amount -
abs(delta)) > _TOLERANCE: suspects.append(...)`. The two are intentionally different: the reader's flag is a
precise per-row fact for the review UI; the chain is the tolerant statement-level verdict.

**Why this is safe / flagged**: For the reference fixture every amount equals its delta **exactly**, so both
places agree (per-row `is_suspect = false`, chain `RECONCILED`). The distinction only matters for
off-by-≤₹1 rounding rows, where the reader would mark `is_suspect = true` but the chain would still count the
statement RECONCILED. **This is faithful to the web engine and is the requester's locked decision** — called
out here (and in the plan's Complexity Tracking) purely for an explicit sanity-check, since a reader that
"marks a row suspect" while the chain "says reconciled" can look contradictory until you see the two-place
design. Recommendation: keep as-is (parity), and document the semantic in `LedgerMetadata`'s doc comment.

**Alternatives**: Apply the ₹1.00 tolerance in the reader too (so `is_suspect` and the chain always agree) —
rejected: diverges from the ground truth and would change `amount_matches_delta`'s meaning from "exact" to
"within ₹1", losing a precise signal. Drop the reader flag and compute everything in the chain — rejected:
`is_suspect`/`amount_matches_delta` are required per-row output fields (FR-011/020).

---

## D7 — `printed_opening_balance` / `printed_closing_balance` and the `_derived_opening` fallback

**Decision**: Port the statement-level assignments 1:1. `printed_opening_balance = opening` when the
`opening_balance_re` matched `full_text`, **else** `derived_opening(lines[0])` = `balance ± amount` of row 1
(add when row 1 is `Debit`, subtract when `Credit`) — i.e. reconstruct the pre-row-1 balance from the first
row. `printed_closing_balance = anchors.last().balance`. Both are new `Option<Decimal>` fields on
`ParsedStatement` (`::new` defaults `None`), added additively (D8).

**Verified against ground truth**: `opening = 100000.00` (printed) ⇒ `printed_opening_balance =
100000.00`; last anchor balance `143000.00` ⇒ `printed_closing_balance = 143000.00`. ✓

**Rationale**: The chain walks from `printed_opening_balance` (D11), so this field must be set even when the
statement doesn't print an opening balance — hence the row-1 derivation. Faithful to `_derived_opening`.

**Alternatives**: Leave `printed_opening_balance` unset when not printed — rejected: the chain would then
have no start point for a geometry/provisional statement and couldn't even attempt a walk.

---

## D8 — Additive record model: `ParsedTransaction.ledger` + `ParsedStatement.printed_*` + new `LedgerMetadata`/`DirectionSource`/`Word` in `base.rs`

**Decision**: Extend the existing records **additively** in `base.rs` (they are the natural home — the CC
readers already produce `ParsedTransaction`/`ParsedStatement`):

- `ParsedTransaction` gains `pub ledger: Option<LedgerMetadata>`. The **one** CC constructor in
  `line_reader.rs` (`line_reader.rs:77–84`) gains `ledger: None`; every CC reader inherits this (no
  per-reader change).
- New `LedgerMetadata` (`uniffi::Record`): `balance: Decimal`, `balance_delta: Option<Decimal>`,
  `amount_matches_delta: bool`, `is_suspect: bool`, `direction_source: DirectionSource`, `serial: String`.
- New `DirectionSource` (`uniffi::Enum`): `OpeningBalance | BalanceDelta | Row1XPosition | Row1Provisional`.
- New `Word` (`uniffi::Record`): `text: String`, `x0: f64`, `x1: f64`.
- `ParsedStatement` gains `pub printed_opening_balance: Option<Decimal>` and `pub printed_closing_balance:
  Option<Decimal>`; `ParsedStatement::new` sets both to `None`.

**Rationale**: This is the faithful map of the web `ParsedTransaction.metadata` dict + `ParsedStatement.
printed_*` fields onto typed Rust records. `Option<…>`/`None` keeps the CC path byte-identical in behaviour
(the fields are simply absent). Deriving `Serialize/Deserialize/PartialEq/Clone/Debug` matches the existing
records so determinism/equality tests keep working.

**Alternatives**: A separate `ParsedLedgerStatement`/`ParsedLedgerRow` hierarchy — rejected (see plan
Complexity Tracking): it duplicates every shared field and forks the harness/pipeline for no benefit; the
1-line `ledger: None` touch is minimal and precedented.

---

## D9 — No CC fixture migration: harness schema extended with `#[serde(default)]` optional fields *(answers the requester's migration question)*

**Decision**: Extend the parity harness types, **not** the CC fixtures. In `tests/parity.rs`: add optional
`#[serde(default)]` ledger fields to `ExpectedRow` (`balance`, `balance_delta`, `direction_source`,
`serial`, `amount_matches_delta`, `is_suspect` — all `Option`/defaulted) and optional
`printed_opening_balance`/`printed_closing_balance` to `Expected`. The row assertion checks the ledger
fields **only when present** (i.e. when the fixture supplies them). CC fixtures omit these keys and
therefore deserialize **unchanged** (the same pattern the harness already uses for `period_start`, which is
`#[serde(default)]` today — `tests/parity.rs:30–33`).

**Conclusion for the requester**: **No fixture migration is required for the existing credit-card golden
vectors.** They neither carry nor need `ledger`/`printed_*` keys; `#[serde(default)]` makes their absence a
`None`/empty, and the harness only asserts ledger fields for fixtures that declare them. Likewise, adding
`ParsedTransaction.ledger`/`ParsedStatement.printed_*` to the Rust records does not touch the CC fixtures,
because the harness compares **field-by-field** against the `Expected*` structs (it never deserializes a
fixture directly into `ParsedStatement`). The five CC `Case` rows and their JSON stay byte-identical.

**Rationale**: Keeps one harness for both families (Principle V) with zero churn to landed vectors.

**Alternatives**: A second harness file for ledger fixtures — rejected: duplicates the loader/assert
scaffolding. Backfilling `ledger: null` into CC fixtures — rejected: pointless churn; `#[serde(default)]`
already handles absence.

---

## D10 — ICICI reference config `statement/icici_bank.rs`; coexists with the ICICI **credit-card** reader

**Decision**: Port `icici_bank.py` to a **zero-sized** `IciciBankReader` implementing `LedgerReaderConfig`.
`BANK_CODE = "ICICI"`. Statics via `LazyLock<Regex>` (as every landed reader does):

- **anchor** `^(?P<serial>\d{1,4})\s+(?P<date>\d{2}\.\d{2}\.\d{4})(?:\s+\d{2}\.\d{2}\.\d{4})?\s+
  (?P<desc>.*?)\s*(?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$` — single-amount template
  (`amount` + `balance`); the optional second dotted date (transaction date) is consumed and not stored.
- **opening** `(?i)(?:Opening Balance|BALANCE\s+B/F|B/F)\s+([\d,]+\.\d{2})`; **closing**
  `(?i)Closing Balance\s+([\d,]+\.\d{2})`.
- **column_split_x** `400.0` (only consulted for a geometry-only row 1; NEEDS_REVIEW regardless this slice).
- **claim_all** `("Statement of Transactions", "ICICI")`, **claim_any** `("Saving", "Current")`.
- **enrich**: full-month period `([A-Za-z]+ \d{1,2}, \d{4})\s+to\s+([A-Za-z]+ \d{1,2}, \d{4})` (case-
  insensitive) → `period_start = parse_date(g1)`, `period_end = parse_date(g2)` (both via the **already
  present** `%B %d, %Y`). `card_last4 = account_tail(full_text)` (D11).
- **account_tail** (bank-account-aware): `(?i)Account\s+(?:Number|No\.?)\s*:?\s*([0-9]{6,})` → last 4;
  fallback = the longest standalone `≥9`-digit run's last 4. **Not** `find_last4`/masked-PAN.

**Coexistence**: ICICI now has **both** `icici.rs` (credit-card, `claims` on `"ICICI Bank"`) and
`icici_bank.rs` (bank-account, `claims_ledger` requiring `"Statement of Transactions"` + `"ICICI"` +
`Saving`/`Current`). Both share `BANK_CODE = "ICICI"` but gate on **document type** (FR-001/002). The bank
gate's `claim_all` includes `"ICICI"` specifically so it does **not** claim other issuers' "Statement of
Transactions" documents (the web engine's note about IOB); an ICICI **credit-card** statement lacks
"Statement of Transactions"/`Saving`/`Current` markers and is **rejected** by the bank reader while the CC
reader still claims it (FR-002, SC-007).

**Verified against ground truth**: `Account Number 000401000123456` → `account_tail = "3456"`; period
`June 16, 2025 to July 15, 2025` → `2025-06-16` / `2025-07-15`. ✓

**Alternatives**: Reuse `find_last4` for the account tail — rejected: it targets **masked PANs**
(`4315XXXXXXXX1002`), not a printed all-digits account number, and would miss/mis-extract `3456` (FR-022).

---

## D11 — `balance_chain.rs`: `check(&ParsedStatement) -> ChainResult`, ported 1:1 (₹1.00 tolerance, row-1 fallback skip, cap 20)

**Decision**: Port `balance_chain.check` exactly, into typed Rust records.

- New `ChainStatus` (`uniffi::Enum`): `Reconciled | NeedsReview`.
- New `Suspect` (`uniffi::Record`): `row: u32`, `serial: Option<String>`, `amount: Decimal`, `reason:
  String`.
- New `ChainResult` (`uniffi::Record`): `status: ChainStatus`, `checked_rows: u32`, `suspect_count: u32`,
  `suspects: Vec<Suspect>` (capped at 20), `row1_direction_fallback: bool`, `derived_opening_balance:
  Option<Decimal>`, `derived_closing_balance: Option<Decimal>`, `reason: Option<String>` (set **only** for
  the empty-statement NEEDS_REVIEW case, `"no parsed transactions"`).

**Algorithm** (from `balance_chain.py`): empty `lines` → `NeedsReview` with `checked_rows = 0`, `reason =
"no parsed transactions"`. Else walk with `prev = statement.printed_opening_balance` (1-based `row`); per
row read `balance` from `ledger.balance` and `source` from `ledger.direction_source`. If `balance` missing →
suspect `"missing running balance"`. `derived_row1 = (row == 1 && source ∈ {Row1XPosition,
Row1Provisional})`; when `prev.is_some() && !derived_row1`: `delta = balance − prev`; if `(amount −
|delta|).abs() > Decimal("1.00")` → suspect `"amount {amount} != |balance delta| {|delta|}"`. Set `prev =
balance`. `row1_direction_fallback = lines[0].ledger.direction_source ∈ fallback set`. `status = Reconciled`
**iff** `suspects.is_empty() && !row1_direction_fallback`, else `NeedsReview`. `derived_opening_balance`/
`derived_closing_balance` = the statement's `printed_opening_balance`/`printed_closing_balance` (set when
present). `suspects` truncated to 20.

**Verified against ground truth** (`balance_chain` block): `checkedRows 3`, `suspectCount 0`, `suspects []`,
`row1DirectionFallback false`, `derivedOpeningBalance 100000.00`, `derivedClosingBalance 143000.00`, status
**RECONCILED** (row 1 source `opening_balance` is **not** a fallback; every amount equals its delta within
₹1). ✓

**Rust idiom notes**: `ChainStatus`/`Suspect`/`ChainResult` live in `balance_chain.rs` (the chain owns its
types; `LedgerMetadata`/`Word` live in `base.rs` with the records they extend). `check` reads
`line.ledger.as_ref()` — a row with `ledger: None` (a CC row) yields "missing running balance", which is
correct (the chain is only meaningful for ledger statements; the harness only calls it on the bank fixture).

**Alternatives**: Fold the chain into the reader — rejected: FR-017 wants an independent, separately-callable
check (exposed over FFI as `check_balance_chain`), matching the web engine's separate module.

---

## D12 — FFI: `read_icici_bank_statement` (+ `Vec<Word>`), `icici_bank_claims`, `check_balance_chain`; reuse the Decimal/NaiveDate bridges

**Decision**: Add three `#[uniffi::export]` functions in `ffi.rs`, re-exported from `lib.rs`:

- `read_icici_bank_statement(lines: Vec<String>, full_text: String, first_row_words: Vec<Word>) ->
  ParsedStatement` → `read_ledger_lines(&IciciBankReader, &lines, &full_text, &first_row_words)`.
- `icici_bank_claims(full_text: String) -> bool` → `claims_ledger(&IciciBankReader, &full_text, "ICICI")`.
- `check_balance_chain(statement: ParsedStatement) -> ChainResult` → `balance_chain::check(&statement)`.

The existing `Decimal`/`NaiveDate` custom-type bridges (`ffi.rs:22–33`) are reused unchanged; the new
records/enums (`Word`, `LedgerMetadata`, `DirectionSource`, `ChainResult`, `ChainStatus`, `Suspect`) derive
`uniffi::Record`/`uniffi::Enum` and generate into Swift automatically. Rebuild with `make core-xcframework`
(regenerates the git-ignored `ios/Generated` + `KanameCoreFFI.xcframework`) **before** `tuist generate`
(Makefile `ios-gen: core-xcframework`; research on iOS gate ordering) — iPhone 16 sim, macos-15 CI.

**Rationale**: Mirrors the credit-card FFI surface (a `read_*` + a `*_claims` per reader) and adds the one
new cross-family primitive (`check_balance_chain`). `ParsedStatement` already crosses the FFI, so
round-tripping it into `check_balance_chain` is free (its new `ledger`/`printed_*` fields ride along).

**Alternatives**: Return the chain inside `ParsedStatement` — rejected: keeps the chain a separate, testable
primitive (FR-017) and avoids making every parse recompute a check the caller may not want.

---

## Ground-truth cross-check (summary)

| Output | Ground truth | Reproduced by |
|---|---|---|
| Rows | 3 (`5000.00` Debit, `50000.00` Credit, `2000.00` Debit) | D2 anchors + D5 delta directions |
| Descriptions | `UPI/512345/ALICE STORE/Payment`, `NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY`, `ATM CASH WITHDRAWAL` | D3 narration stitching (verified line-by-line) |
| Per-row balance | `95000.00`, `145000.00`, `143000.00` | anchor `balance` group |
| Per-row delta | `−5000.00`, `+50000.00`, `−2000.00` | D5/D7 (`balance − prev`) |
| direction_source | `opening_balance`, `balance_delta`, `balance_delta` | D5 |
| serial | `1`, `2`, `3` | anchor `serial` group |
| amount_matches / is_suspect | all `true` / `false` | D6 exact equality |
| printed opening / closing | `100000.00` / `143000.00` | D7 |
| period | `2025-06-16` → `2025-07-15` | D10 enrich (`%B %d, %Y`) |
| account last-4 | `3456` | D10 account_tail |
| balance chain | RECONCILED, 0 suspects, no row-1 fallback | D11 |

**All Phase 0 unknowns resolved.** No NEEDS CLARIFICATION remain. The two items flagged for the requester's
sanity-check (D6 exact-vs-tolerance, D4 loose two-column parse) are faithful ports of the web engine and the
requester's locked design; the migration question is answered (D9: **no CC fixture migration**). Cleared to
Phase 1.
