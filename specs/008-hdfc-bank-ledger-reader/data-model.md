# Phase 1 Data Model: HDFC Bank (Savings/Current) Ledger Reader

**Feature**: `008-hdfc-bank-ledger-reader` | **Date**: 2026-07-16 | **Plan**: [`plan.md`](./plan.md)

This slice introduces **no new data types**. It adds one **config value** (`HdfcBankReader`), one **shared
function** (`account_tail_last4`), two **FFI functions**, and two **fixtures**. Every record/enum that crosses a
boundary was defined in slice 007 and is **reused unchanged**. This document enumerates what is new, what is
reused, and the exact field-level expectations the two golden vectors assert.

## 1. New / changed code entities

### 1.1 `HdfcBankReader` — a zero-sized config (NEW), `statement/hdfc_bank.rs`

A unit struct implementing the existing `LedgerReaderConfig` trait (from `ledger_reader.rs`). It holds **no
state** — all behaviour is expressed as `&'static Regex` statics + trait methods, mirroring `IciciBankReader`.

| Trait member | HDFC value | Notes |
|---|---|---|
| `BANK_CODE` | `"HDFC"` | used by `claims_ledger` / balance-chain reporting |
| `anchor_res() -> Vec<&'static Regex>` | `vec![&COMPACT_RE, &DETAILED_RE]` | **ordered**, first-match-wins (D2); HDFC is the first config with >1 anchor |
| `opening_balance_re() -> Option<&'static Regex>` | `Some(&OPENING_RE)` | matches inline **and** compact-summary (across `\n`) forms (D3) |
| `closing_balance_re() -> Option<&'static Regex>` | `None` | closing is derived from the final row's balance |
| `column_split_x() -> Option<f64>` | `None` | HDFC needs no geometry; `Vec<Word>` unused |
| `enrich(&self, full_text, out)` | sets period (`PERIOD_RE`) + `card_last4 = account_tail_last4(full_text, &HDFC_ACCOUNT_RE)` | mirrors ICICI's `enrich` (D5) |

**Static regexes (all `LazyLock<Regex>`, module-private):**

```text
COMPACT_RE      ^(?P<date>\d{2}/\d{2}/\d{2})\s+(?P<desc>.*?)\s+(?P<serial>[A-Za-z0-9]{6,})\s+\d{2}/\d{2}/\d{2}\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$
DETAILED_RE     ^(?P<date>\d{2}/\d{2}/\d{4})\s+(?P<desc>.*?)\s+(?P<withdrawal>[\d,]+\.\d{2})\s+(?P<deposit>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$
OPENING_RE      (?i)(?:Opening Balance\s*:\s*|OpeningBalance\b[^\n]*\n\s*)([\d,]+\.\d{2})
PERIOD_RE       (?i)From\s*:\s*(\d{2}/\d{2}/\d{4})\s+To\s*:?\s*(\d{2}/\d{2}/\d{4})
HDFC_ACCOUNT_RE (?i)Account\s*(?:Number|No\.?)\s*:?\s*X*([0-9]{4,})
```

**Named capture-group contract (consumed by the reused base):**
- COMPACT provides `date, desc, serial, amount, balance`; the base's `anchor_amount` uses the single `amount`.
- DETAILED provides `date, desc, withdrawal, deposit, balance`; `anchor_amount` picks the non-zero of
  `withdrawal`/`deposit` (empty side = `0.00`). No `serial` group ⇒ `serial = ""`.
- `OPENING_RE`, `PERIOD_RE`, `HDFC_ACCOUNT_RE` expose their values in **group 1** (period uses groups 1 & 2).

### 1.2 `account_tail_last4` — the only new SHARED function (NEW), `statement/common.rs`

```rust
/// Return the trailing 4 digits of an account/card number.
/// Try `primary` (capture group 1) → last 4 of its digits; else the longest
/// standalone run of ≥9 digits (DIGIT_RUN_RE) → last 4; else None.
pub fn account_tail_last4(text: &str, primary: &Regex) -> Option<String>;
```

- **Inputs**: `text: &str` (whole `full_text`), `primary: &Regex` (bank-specific account pattern; group 1 = the
  digits).
- **Output**: `Option<String>` — a 4-character digit string, or `None` if neither the primary match nor a
  `\d{9,}` run exists.
- **Moves into `common.rs`**: the existing `last4(&str) -> String` (trailing 4) and `DIGIT_RUN_RE` (`\d{9,}`) +
  "longest run" selection currently local to `icici_bank.rs`.
- **Consumers**: `IciciBankReader` (via `ICICI_ACCOUNT_RE`, refactor — behaviour-preserving) and
  `HdfcBankReader` (via `HDFC_ACCOUNT_RE`). Future Federal/AU readers (FR-018/022).

### 1.3 `DATE_FORMATS` reorder — **PENDING (OD-1)**, `statement/common.rs`

A **1-line** reordering (`%d/%m/%y` before `%d/%m/%Y`) required for the compact 2-digit-year dates (research
**D8**). Not a new entity; a change to an existing shared `const`. **Gated on user sign-off** (see plan → Open
Decisions). Guarded by the compact golden `Case` + a targeted `parse_date` unit test + re-running existing
readers' parity.

## 2. Reused types (defined in slice 007 — NO change)

These cross the reader/FFI boundary and are **reused verbatim**; listed for field-level clarity of what the
fixtures assert. (Canonical definitions in `statement/base.rs` / `model.rs`.)

### 2.1 `LedgerRow` (per parsed transaction)

| Field | Type | HDFC meaning |
|---|---|---|
| `date` | `NaiveDate` | transaction date (compact `%d/%m/%y`; detailed `%d/%m/%Y`) |
| `amount` | `Decimal` | printed amount (single, or non-zero of withdrawal/deposit) — **independent check** |
| `direction` | `Direction` (`Debit`/`Credit`) | **delta-derived** (row 1: opening), never amount-derived |
| `currency` | `String` | `"INR"` |
| `description_raw` | `String` | **stitched** narration (D4) — reproduced byte-for-byte |
| `ledger` | `LedgerMetadata` | see below |

### 2.2 `LedgerMetadata` (per-row audit trail)

| Field | Type | HDFC meaning |
|---|---|---|
| `balance` | `Decimal` | running balance printed on the row |
| `balance_delta` | `Decimal` | signed change from the previous balance |
| `amount_matches_delta` | `bool` | printed `amount == |delta|` (EXACT in reader) — `true` on all fixture rows |
| `is_suspect` | `bool` | `false` on all fixture rows |
| `direction_source` | `DirectionSource` | `OpeningBalance` (row 0) / `BalanceDelta` (row 1) |
| `serial` | `String` | compact: anchor `serial` group; detailed: `""` |

### 2.3 `DirectionSource` (enum, reused)

`OpeningBalance` | `BalanceDelta` | (`XPosition` | `ProvisionalCredit` — defined, not exercised by HDFC).
Fixture JSON uses the PascalCase variant name.

### 2.4 `Word` (reused) — `{ text: String, x0: f64, x1: f64 }`

Layout token for the two-column x-split path. **Not exercised by HDFC** (no `column_split_x`); the FFI takes it
for signature uniformity and the parity wrapper passes an **empty** `Vec<Word>`. `x0/x1` are the only `f64` in
play and carry **no money** (Principle II).

### 2.5 `ParsedStatement` (reader output, reused)

`rows: Vec<LedgerRow>`, `period_start/period_end: Option<NaiveDate>`, `card_last4: Option<String>`,
`printed_opening_balance/printed_closing_balance: Option<Decimal>`, `errored_lines: Vec<String>`.

### 2.6 `ChainReport` + `ChainStatus` (balance-chain output, reused)

`check_balance_chain(rows) -> ChainReport`; HDFC fixtures each yield `ChainStatus::Reconciled` (₹1.00 tolerance;
0 suspects; no row-1 fallback).

## 3. FFI functions (additive — NO new type)

| Function (`ffi.rs`, `#[uniffi::export]`, re-exported from `lib.rs`) | Signature | Body |
|---|---|---|
| `read_hdfc_bank_statement` | `(lines: Vec<String>, full_text: String, first_row_words: Vec<Word>) -> ParsedStatement` | `read_ledger_lines(&HdfcBankReader, &lines, &full_text, &first_row_words)` |
| `hdfc_bank_claims` | `(full_text: String) -> bool` | `claims_ledger(&HdfcBankReader, &full_text, "HDFC")` |
| `check_balance_chain` | *(reused, already exported)* | unchanged |

All parameter/return types (`Vec<String>`, `String`, `Vec<Word>`, `ParsedStatement`, `bool`, `ChainReport`)
already have UniFFI bindings from slice 007 ⇒ `uniffi.toml` and the `Decimal ↔ Foundation.Decimal` / `NaiveDate`
bridges are untouched.

## 4. Golden-fixture schema (reused from 007 — NO harness change)

Each of `fixtures/hdfc/bank_account/{compact,detailed}.json`:

```jsonc
{
  "lines": ["…"],                 // non-empty stripped splitlines of full_text
  "full_text": "…",               // exact source text
  "expected": {
    "rows": [
      {
        "date": "YYYY-MM-DD",
        "amount": "…",            // string → Decimal (never f64)
        "direction": "Debit" | "Credit",
        "currency": "INR",
        "description_raw": "…",   // byte-for-byte stitched narration
        "ledger": {
          "balance": "…", "balance_delta": "…",
          "amount_matches_delta": true, "is_suspect": false,
          "direction_source": "OpeningBalance" | "BalanceDelta",
          "serial": "…"           // compact: ref; detailed: ""
        }
      }
    ],
    "period_start": "2026-04-01", "period_end": "2026-04-30",
    "card_last4": "3425",
    "printed_opening_balance": "100000.00",
    "printed_closing_balance": "145000.00",
    "errored_lines": []
  }
}
```

**Concrete row values** (both fixtures) are tabulated in research **D6**; monetary fields are **strings** so no
amount is deserialized through `f64`.

## 5. Parity-harness rows (additive — NO schema change)

`tests/parity.rs` (schema already extended in 007) gains:
- a `parse_hdfc_bank(lines, full_text) -> ParsedStatement` wrapper = `read_hdfc_bank_statement(lines, full_text,
  vec![])`;
- two `Case` rows: `("hdfc/bank_account/compact.json", parse_hdfc_bank)` and
  `("hdfc/bank_account/detailed.json", parse_hdfc_bank)`;
- two balance-chain assertions: `check_balance_chain(rows_of(fixture)) == Reconciled` for each HDFC fixture;
- one claims assertion: `hdfc_bank_claims(bank_text) == true` **and** `hdfc_bank_claims(card_text) == false`.

## 6. Validation & state rules (reused base semantics — recorded, not re-implemented)

- **Row-1 bootstrap**: with a printed opening balance present, row 0's direction is anchored to it
  (`direction_source = OpeningBalance`); subsequent rows use the running delta (`BalanceDelta`).
- **Direction polarity**: from the **signed balance delta** only; the printed amount's magnitude/column never
  sets direction (FR-007/013, SC-006).
- **Independent amount check**: `amount_matches_delta = (amount == |delta|)` exactly; a mismatch would set
  `is_suspect` (none occur here).
- **Errored vs suspect**: an unparseable anchor line → `errored_lines` (none here); a parseable-but-inconsistent
  row → `is_suspect` (none here). Both fixtures: `errored_lines = []`, all rows `is_suspect = false`.
- **Chain reconciliation**: `check_balance_chain` walks rows applying each signed amount to the running balance
  within ₹1.00; both fixtures reconcile start→end ⇒ `Reconciled`.
