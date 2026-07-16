# Phase 1 — Data Model: Bank-Account Balance-Ledger Reader (base + balance chain + ICICI reference)

**Feature**: `007-bank-account-ledger-reader` | **Date**: 2026-07-16
**Scope**: The types this slice introduces, extends, reuses, and configures. It adds **1 reader base**, **1
integrity module**, **1 reference reader**, **3 new records** (`LedgerMetadata`, `Word`, `Suspect`), **2 new
enums** (`DirectionSource`, `ChainStatus`), **1 new result record** (`ChainResult`), and **2 additive
fields each** on the existing `ParsedTransaction` and `ParsedStatement` — with **no new dependency**. The
credit-card path is unchanged in behaviour (it carries `ledger: None`).

All money is `rust_decimal::Decimal` (exact, never `f64`); the **only** `f64` values are `Word.x0/x1`,
which are **layout points, not money**. Dates are `chrono::NaiveDate`. Everything crosses the UniFFI bridge
via the existing `Decimal`→`String`(base-10)→`Foundation.Decimal` and `NaiveDate`→`String`(ISO-8601)
bridges (`ffi.rs`).

---

## Extended records (additive) — the parse output

### `ParsedTransaction` (extended) — `uniffi::Record` (`base.rs`)
One successfully-parsed row. **One new field**; the credit-card readers set it to `None` via the single
constructor in `line_reader.rs`.

| Field | Rust type | Wire → Swift | Notes |
|---|---|---|---|
| `value_date` | `NaiveDate` | `String` (ISO-8601) | ICICI dotted anchor date `16.06.2025 → 2025-06-16` via the **existing** `parse_date` (`%d.%m.%Y` already present, `common.rs:30`). |
| `amount` | `Decimal` | `String` (base-10) → `Foundation.Decimal` | Exact, non-negative, scale preserved (`5000.00`, `50000.00`, `2000.00`); Indian grouping stripped (FR-012). |
| `direction` | `Direction` | `Direction` | **Delta-derived** (`Debit` when balance falls, `Credit` when it rises); row 1 via opening balance/x-position/provisional (FR-008/013). Never the amount's sign. |
| `currency` | `String` | `String` | Constant **`"INR"`**. |
| `description_raw` | `String` | `String` | Stitched narration (D3), ≤240 codepoints (`truncate_chars`). |
| `bank_code` | `String` | `String` | `"ICICI"`. |
| **`ledger`** | **`Option<LedgerMetadata>`** | **`LedgerMetadata?`** | **NEW.** `Some(..)` for ledger rows; **`None`** for every credit-card row (set at `line_reader.rs`'s constructor). |

### `ParsedStatement` (extended) — `uniffi::Record` (`base.rs`)
The full result of reading one statement. **Two new fields**; `ParsedStatement::new` defaults both to
`None`, so the credit-card readers are unchanged.

| Field | Rust type | Wire → Swift | Notes |
|---|---|---|---|
| `bank_code` | `String` | `String` | `"ICICI"`. |
| `lines` | `Vec<ParsedTransaction>` | `[ParsedTransaction]` | Ledger rows in input order; may be empty (no rows → empty, no error). |
| `errored_lines` | `Vec<String>` | `[String]` | Anchor-shaped rows whose date/amount/balance failed to parse; ≤240 cp; never a panic (FR-019). |
| `period_start` | `Option<NaiveDate>` | `String?` | `2025-06-16` from the enrich period regex (FR-021). |
| `period_end` | `Option<NaiveDate>` | `String?` | `2025-07-15` from the enrich period regex (FR-021). |
| `card_last4` | `Option<String>` | `String?` | Account last-4 `"3456"` via the **account-number** tail extractor, **not** masked-PAN (FR-022). |
| `confidence` | `f64` | `Double` | Reused as-is (defaults `1.0`); not a money value. |
| **`printed_opening_balance`** | **`Option<Decimal>`** | **`Decimal?`** | **NEW.** Printed opening (`100000.00`) else derived from row 1 (D7). |
| **`printed_closing_balance`** | **`Option<Decimal>`** | **`Decimal?`** | **NEW.** Last anchor balance (`143000.00`) (D7). |

> **Back-compat:** existing credit-card fixtures/rows are untouched — `ledger`/`printed_*` are simply absent
> (`None`) for cards, and the parity harness compares field-by-field, so **no CC fixture migration** is
> required (research D9).

---

## New records & enums

### `LedgerMetadata` (NEW) — `uniffi::Record` (`base.rs`)
Per-row ledger metadata — the auditable balance/delta/source/serial data the balance chain and review UI
consume (FR-020). Ported from the web `ParsedTransaction.metadata` dict.

| Field | Rust type | Wire → Swift | Notes |
|---|---|---|---|
| `balance` | `Decimal` | `Decimal` | Running balance after this row (`95000.00`, …). |
| `balance_delta` | `Option<Decimal>` | `Decimal?` | `balance − prev_balance` (`−5000.00`, `+50000.00`, `−2000.00`); `None` only if no predecessor could be established. |
| `amount_matches_delta` | `bool` | `Bool` | **Exact** `amount == balance_delta.abs()` (**no** tolerance — the ₹1.00 tolerance is chain-only; research D6). |
| `is_suspect` | `bool` | `Bool` | `!amount_matches_delta`. |
| `direction_source` | `DirectionSource` | `DirectionSource` | How this row's direction was decided (below). |
| `serial` | `String` | `String` | The printed serial (`"1"`, `"2"`, `"3"`). |

### `DirectionSource` (NEW) — `uniffi::Enum` (`base.rs`)
`enum DirectionSource { OpeningBalance, BalanceDelta, Row1XPosition, Row1Provisional }` — exactly the four
`direction_source` values (FR-014). Row 1 is one of `OpeningBalance`/`Row1XPosition`/`Row1Provisional`;
**every** later row is `BalanceDelta`. `Row1XPosition`/`Row1Provisional` are the **fallback** sources that
force the chain to NEEDS_REVIEW (FR-015/018).

### `Word` (NEW) — `uniffi::Record` (`base.rs`)
`struct Word { text: String, x0: f64, x1: f64 }` — one word of the **first transaction row's** geometry,
supplied natively (iOS PDFKit) for the row-1 x-position bootstrap (FR-016). **`x0`/`x1` are layout points,
not money** — `f64` is constitutionally correct here (money stays `Decimal`; SC-009). The reference fixture
is opening-balance-anchored, so the harness passes an **empty `Vec<Word>`**.

### `Direction` (reused, unchanged) — `uniffi::Enum` (`model.rs`)
`enum Direction { Debit, Credit }`. For the ledger family it is **derived from the running-balance delta**,
never from `classify`/Dr-Cr (that path is credit-card only). No field change.

---

## Balance-chain types (NEW) — `balance_chain.rs`

### `ChainStatus` (NEW) — `uniffi::Enum`
`enum ChainStatus { Reconciled, NeedsReview }` (FR-017). `Reconciled` **iff** no suspects **and** row-1
`direction_source` is not a fallback.

### `Suspect` (NEW) — `uniffi::Record`
One flagged chain-break (still returned in `ParsedStatement.lines`, never dropped — FR-010).

| Field | Rust type | Wire → Swift | Notes |
|---|---|---|---|
| `row` | `u32` | `UInt32` | 1-based row index. |
| `serial` | `Option<String>` | `String?` | The row's `ledger.serial` when present. |
| `amount` | `Decimal` | `Decimal` | The printed amount. |
| `reason` | `String` | `String` | `"missing running balance"` or `"amount {amount} != \|balance delta\| {abs}"`. |

### `ChainResult` (NEW) — `uniffi::Record`
The statement-level verdict (FR-017/018). Ported from `balance_chain.ChainResult` + its `detail` dict.

| Field | Rust type | Wire → Swift | Notes |
|---|---|---|---|
| `status` | `ChainStatus` | `ChainStatus` | RECONCILED / NEEDS_REVIEW. |
| `checked_rows` | `u32` | `UInt32` | `lines.len()`. |
| `suspect_count` | `u32` | `UInt32` | Number of suspects found (may exceed the capped list length). |
| `suspects` | `Vec<Suspect>` | `[Suspect]` | Capped at **20** for the payload. |
| `row1_direction_fallback` | `bool` | `Bool` | `lines[0].ledger.direction_source ∈ {Row1XPosition, Row1Provisional}`. |
| `derived_opening_balance` | `Option<Decimal>` | `Decimal?` | `= statement.printed_opening_balance` when set. |
| `derived_closing_balance` | `Option<Decimal>` | `Decimal?` | `= statement.printed_closing_balance` when set. |
| `reason` | `Option<String>` | `String?` | Set **only** for the empty-statement case: `"no parsed transactions"`. |

---

## The reader base — `LedgerReaderConfig` (NEW trait) + free functions (`ledger_reader.rs`)

The ledger analogue of `LineReaderConfig`. A per-issuer config is a zero-sized type; all patterns live in
`LazyLock<Regex>` statics.

```rust
pub trait LedgerReaderConfig {
    fn bank_code(&self) -> &'static str;
    fn claim_all(&self) -> &'static [&'static str];
    fn claim_any(&self) -> &'static [&'static str];
    fn anchor_res(&self) -> &'static [&'static Regex];      // first-match-wins (multi-template ready)
    fn opening_balance_re(&self) -> Option<&'static Regex>;
    fn closing_balance_re(&self) -> Option<&'static Regex>;
    fn column_split_x(&self) -> Option<f64>;
    fn provisional_direction(&self) -> Direction { Direction::Debit }   // default
    fn enrich(&self, _s: &mut ParsedStatement, _full_text: &str) {}      // default no-op
    fn account_tail(&self, _text: &str) -> Option<String> { None }       // default
}

pub fn read_ledger_lines<C: LedgerReaderConfig + ?Sized>(
    cfg: &C, lines: &[String], full_text: &str, first_row_words: &[Word],
) -> ParsedStatement;

pub fn claims_ledger<C: LedgerReaderConfig + ?Sized>(
    cfg: &C, text: &str, bank_code: &str,
) -> bool;   // bank_code match + ALL claim_all + (claim_any empty OR ANY claim_any), case-insensitive
```

**Internal helpers** (private, ported 1:1 from `_ledger_reader.py`): `find_anchors` (D2), `anchor_amount`
(single `amount` via `parse_amount` else the non-zero withdrawal/deposit side via a **loose** integer-or-
decimal parse — D4), `stitch_narration` (D3), `row1_direction` + `direction_from_x_position` (D5),
`is_balance_line`, `extract_balance`, `derived_opening` (D7). All pure/total (never panic; bad rows →
`errored_lines`).

**`read_ledger_lines` flow**: extract `opening` from `full_text` via `opening_balance_re`; `find_anchors`;
push errored lines (≤240); if no anchors → `enrich` + return. Else walk anchors, computing `(direction,
source, prev)` for row 1 (D5) and delta-direction for later rows, `delta`/`amount_matches_delta`/
`is_suspect` (D6), and push a `ParsedTransaction` carrying `Some(LedgerMetadata{..})`. Set
`printed_opening_balance` (printed else derived from row 1) and `printed_closing_balance` (last anchor);
`enrich`; return.

---

## The integrity check — `balance_chain::check` (NEW fn) (`balance_chain.rs`)

```rust
pub fn check(statement: &ParsedStatement) -> ChainResult;
```
Walks `statement.lines` from `statement.printed_opening_balance`, comparing each printed `amount` to its
`|balance − prev|` with a `Decimal("1.00")` tolerance; skips the amount-vs-delta check for a row-1 whose
`direction_source` is a fallback; `Reconciled` iff no suspects and no row-1 fallback; empty → `NeedsReview`
with `reason "no parsed transactions"` (D11). Pure; no clock/network/global state.

---

## The ICICI reference config — `IciciBankReader` (NEW) (`icici_bank.rs`)

`pub struct IciciBankReader;` implementing `LedgerReaderConfig`. `BANK_CODE = "ICICI"`.

Config values (each regex is a `static` `Regex` built once via `LazyLock`):

- **`anchor_res`** → `[ &ANCHOR_RE ]`, where `ANCHOR_RE` is:
  ```text
  ^(?P<serial>\d{1,4})\s+(?P<date>\d{2}\.\d{2}\.\d{4})(?:\s+\d{2}\.\d{2}\.\d{4})?\s+(?P<desc>.*?)\s*(?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$
  ```
- **`opening_balance_re`** → `Some(&OPENING_RE)`:
  ```text
  (?i)(?:Opening Balance|BALANCE\s+B/F|B/F)\s+([\d,]+\.\d{2})
  ```
- **`closing_balance_re`** → `Some(&CLOSING_RE)`:
  ```text
  (?i)Closing Balance\s+([\d,]+\.\d{2})
  ```
- **`column_split_x`** → `Some(400.0)`
- **`claim_all`** → `["Statement of Transactions", "ICICI"]`
- **`claim_any`** → `["Saving", "Current"]`
- **`enrich`** → period regex below → `period_start`/`period_end` via `parse_date`; then `card_last4 = account_tail(full_text)`:
  ```text
  (?i)([A-Za-z]+ \d{1,2}, \d{4})\s+to\s+([A-Za-z]+ \d{1,2}, \d{4})
  ```
- **`account_tail`** → match below → last 4; fallback to the last 4 of the longest `≥9`-digit run:
  ```text
  (?i)Account\s+(?:Number|No\.?)\s*:?\s*([0-9]{6,})
  ```

**Coexistence**: `icici.rs` (credit-card) and `icici_bank.rs` (bank-account) both use `BANK_CODE = "ICICI"`
but gate on document type; the bank gate requires `"Statement of Transactions"` + `"ICICI"` +
`Saving`/`Current`, so it rejects the ICICI **credit-card** statement (which the CC reader still claims) and
other issuers (FR-001/002, SC-007).

---

## Test surface — `tests/parity.rs` (extended, back-compatible)

- `ExpectedRow` gains optional `#[serde(default)]` ledger fields: `balance`, `balance_delta`,
  `direction_source`, `serial`, `amount_matches_delta`, `is_suspect` (all `Option`/defaulted).
- `Expected` gains optional `printed_opening_balance`/`printed_closing_balance`.
- `parse_icici_bank(lines, full_text)` wrapper → `read_icici_bank_statement(lines, full_text, vec![])`
  (empty geometry) so the `Case { parse: fn(Vec<String>, String) -> ParsedStatement }` table gains **one**
  row (`icici/bank_account/basic.json`).
- Row assertion checks ledger fields **only when the fixture supplies them** (CC rows omit them → unchanged).
- **New** balance-chain parity test: `check_balance_chain(parse_icici_bank(fixture)) == RECONCILED` with 0
  suspects and `row1_direction_fallback == false`.
- **New** claim-split test: `icici_bank_claims(bank fixture) == true`; `icici_bank_claims(ICICI credit-card
  text) == false`; and the existing `icici_claims(credit-card text) == true` still holds (SC-007).

---

## Type inventory (this slice)

| Type | Kind | File | Status |
|---|---|---|---|
| `Direction` | `uniffi::Enum` | `model.rs` | reused, unchanged |
| `ParsedTransaction` | `uniffi::Record` | `base.rs` | **+1 field** (`ledger`) |
| `ParsedStatement` | `uniffi::Record` | `base.rs` | **+2 fields** (`printed_*`) |
| `LedgerMetadata` | `uniffi::Record` | `base.rs` | **NEW** |
| `DirectionSource` | `uniffi::Enum` | `base.rs` | **NEW** |
| `Word` | `uniffi::Record` | `base.rs` | **NEW** |
| `LedgerReaderConfig` | trait | `ledger_reader.rs` | **NEW** |
| `IciciBankReader` | zero-sized config | `icici_bank.rs` | **NEW** |
| `ChainStatus` | `uniffi::Enum` | `balance_chain.rs` | **NEW** |
| `Suspect` | `uniffi::Record` | `balance_chain.rs` | **NEW** |
| `ChainResult` | `uniffi::Record` | `balance_chain.rs` | **NEW** |

**No new dependency. Money is `Decimal` everywhere; only `Word.x0/x1` are `f64` (layout points).**
