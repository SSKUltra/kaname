# Phase 1 — Data Model: Federal Bank Ledger Reader

**Feature**: 009-federal-bank-ledger-reader · **Date**: 2026-07-17

This slice introduces **no new types**. It reuses the landed reader output records and the `LedgerReaderConfig` trait unchanged, and adds **one** zero-sized config struct plus **two** golden fixtures. This document pins the reused schema (for reviewer reference) and the concrete Federal configuration + expected outputs.

---

## 1. Reused records (UNCHANGED — no schema change)

### `ParsedStatement` (`statement/base.rs`)
| Field | Type | Federal usage |
|---|---|---|
| `bank_code` | `String` | `"FEDERAL"` |
| `lines` | `Vec<ParsedTransaction>` | 3 (classic) / 2 (fi) |
| `errored_lines` | `Vec<String>` | `[]` for both fixtures |
| `period_start` / `period_end` | `Option<NaiveDate>` | from `PERIOD_RE` (ISO or `DD/MM/YYYY`) |
| `card_last4` | `Option<String>` | `"1234"` / `"4222"` (trailing 4 only) |
| `printed_opening_balance` | `Option<Decimal>` | `100000.00` / `100000.00` |
| `printed_closing_balance` | `Option<Decimal>` | last row balance: `100000.00` / `145000.00` |
| `confidence` | `f64` | default `1.0` |

### `ParsedTransaction` (`statement/base.rs`)
`value_date: NaiveDate`, `amount: Decimal`, `direction: Direction`, `currency: String` (`"INR"`), `description_raw: String` (stitched, ≤ `MAX_RAW`=240 codepoints), `bank_code: String`, `ledger: Option<LedgerMetadata>` (always `Some` here).

### `LedgerMetadata` (`statement/base.rs`)
`balance: Decimal`, `balance_delta: Option<Decimal>`, `amount_matches_delta: bool`, `is_suspect: bool`, `direction_source: DirectionSource`, `serial: String`.

### `DirectionSource` (`statement/base.rs`) — enum, Debug spelling used in fixtures
`OpeningBalance` (row 1 both fixtures), `BalanceDelta` (all later rows). `Row1XPosition` / `Row1Provisional` exist but are **not** exercised (Federal sets no `column_split_x`; both fixtures are opening-anchored).

### `Direction` (`model.rs`) — `Debit` | `Credit` (serde spelling `"Debit"`/`"Credit"`).

### `ChainResult` / `ChainStatus` (`statement/balance_chain.rs`) — reused via `check_balance_chain`
`status: Reconciled|NeedsReview`, `checked_rows: u32`, `suspect_count: u32`, `suspects: Vec<Suspect>`, `row1_direction_fallback: bool`, `derived_opening_balance`, `derived_closing_balance`, `reason`. Federal ⇒ `Reconciled`, `suspect_count=0`, `row1_direction_fallback=false`, `checked_rows=3` (classic) / `2` (fi).

---

## 2. New entity: `FederalBankReader` (`statement/federal_bank.rs`)

Zero-sized struct implementing `LedgerReaderConfig`. All state is in module `LazyLock<Regex>` statics + `const` marker slices.

| Trait method | Value |
|---|---|
| `bank_code()` | `"FEDERAL"` |
| `claim_all()` | `["Federal Bank", "Statement of Account"]` |
| `claim_any()` | *(default `&[]` — none)* |
| `anchor_res()` | `vec![&ANCHOR_CLASSIC_RE, &ANCHOR_FI_RE]` (order = first-match-wins) |
| `opening_balance_re()` | `Some(&OPENING_RE)` |
| `closing_balance_re()` | *(default `None`)* |
| `column_split_x()` | *(default `None`)* |
| `provisional_direction()` | *(default `Debit`, unused)* |
| `account_tail(text)` | `account_tail_last4(text, &FEDERAL_ACCOUNT_RE)` |
| `enrich(st, full_text)` | set `period_start/end` from `PERIOD_RE` (via `parse_date`); set `card_last4 = account_tail(full_text)` |

### Regex statics (LOCKED — see research.md)
```text
ANCHOR_CLASSIC_RE = (?i)^(?P<date>\d{2}-[A-Za-z]{3}-\d{4})\s+\d{2}-[A-Za-z]{3}-\d{4}\s+
                    (?P<desc>.*?)(?:\s+(?P<serial>S\d+))?\s+
                    (?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s+(?:Cr|Dr)\s*$
ANCHOR_FI_RE      = (?i)^(?P<date>\d{2}/\d{2}/\d{4})\s+\d{2}/\d{2}/\d{4}\s+
                    (?P<desc>.*?)(?:\s+(?P<serial>S\d+))?\s+
                    (?P<withdrawal>[\d,]+(?:\.\d{2})?)\s+(?P<deposit>[\d,]+(?:\.\d{2})?)\s+
                    (?P<balance>[\d,]+\.\d{2})\s+(?:Cr|Dr)\s*$
OPENING_RE        = (?i)Opening Balance\s+(?:[A-Z]+\s+)?([\d,]+\.\d{2})
PERIOD_RE         = (?i)for the period(?:\s+of)?\s+
                    (\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})\s+to\s+(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})
FEDERAL_ACCOUNT_RE = (?i)Account\s+Number\s*:?\s*X*([0-9]{4,})
```
Named groups consumed by the base: `date`, `desc`, `serial`, `amount` (classic) or `withdrawal`+`deposit` (fi), `balance`. The trailing `(?:Cr|Dr)` is matched but **unnamed** ⇒ ignored.

---

## 3. Expected outputs (the two golden fixtures)

### 3.1 `fixtures/federal/bank_account/classic.json` — 3 rows, RECONCILED

`period_start=2026-04-01`, `period_end=2026-04-30`, `card_last4="1234"`, `printed_opening_balance="100000.00"`, `printed_closing_balance="100000.00"`, `errored_lines=[]`.

| # | date | amount | direction | balance | balance_delta | matches | suspect | direction_source | serial | description_raw |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-04-08 | `5000.00` | Debit | `95000.00` | `-5000.00` | true | false | OpeningBalance | `S10000001` | `TO ECM/600000000001 TFR` |
| 2 | 2026-04-11 | `50000.00` | Credit | `145000.00` | `50000.00` | true | false | BalanceDelta | `S10000002` | `UPI IN/600000000002 TFR /EXAMPLEMERCHANT \EXAM/07:17` |
| 3 | 2026-04-13 | `45000.00` | Debit | `100000.00` | `-45000.00` | true | false | BalanceDelta | `S10000003` | `POS/600000000003/EXAMPLESTORE TFR /payer@example/Payment/0000 \EXAM/12:34 GRAND TOTAL 50,000.00 50,000.00` |

### 3.2 `fixtures/federal/bank_account/fi.json` — 2 rows, RECONCILED

`period_start=2026-04-08`, `period_end=2026-05-07`, `card_last4="4222"`, `printed_opening_balance="100000.00"`, `printed_closing_balance="145000.00"`, `errored_lines=[]`.

| # | date | amount | direction | balance | balance_delta | matches | suspect | direction_source | serial | description_raw |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-04-08 | `5000` | Debit | `95000.00` | `-5000.00` | true | false | OpeningBalance | `S10000001` | `TO ECM/600000000001/EXAMPLE TFR` |
| 2 | 2026-04-20 | `50000` | Credit | `145000.00` | `50000.00` | true | false | BalanceDelta | `S10000002` | `UPI IN/600000000002/payer TFR MERCHANT \EXAM Payment f/0000` |

> **Amount form**: Fi amounts are stored **exactly** as printed — `"5000"`/`"50000"` (no `.00`) — because `Decimal::from_str_exact` preserves scale 0 and `to_string()` round-trips it. rust_decimal still evaluates `5000 == 5000.00` for the delta check (research.md, Decision 4).

> **Backslashes**: `full_text`/`lines`/`description_raw` contain the literal `\EXAM` token; in JSON it must be escaped as `\\EXAM`. The stitched `description_raw` is byte-for-byte (no normalization).

### Fixture `lines`/`full_text`
Taken verbatim from the captured ground truth. `lines` = the non-empty, stripped `splitlines()` of `full_text`. (Classic: 13 lines; Fi: 9 lines. Anchor line indices — classic 6/8/10, Fi 5/7 — drive the stitch trace in research.md, Decision 8.)

---

## 4. State & validation notes

- **Row-1 bootstrap**: `printed_opening_balance` present (`100000.00`) ⇒ `direction_source = OpeningBalance`, delta `95000.00 − 100000.00 = −5000.00 < 0 ⇒ Debit`. No geometry consulted.
- **Suspect vs errored**: amount-vs-delta within ₹1.00 tolerance for every row ⇒ 0 suspects; every anchor-shaped row parses ⇒ 0 errored lines. Both inherited unchanged from the base/chain.
- **Determinism**: pure functions; identical input ⇒ identical output (asserted by the harness `parse_is_deterministic`).
