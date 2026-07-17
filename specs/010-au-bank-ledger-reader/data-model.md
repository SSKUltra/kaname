# Phase 1 — Data Model: AU Small Finance Bank Ledger Reader

**Feature**: 010-au-bank-ledger-reader · **Date**: 2026-07-17

This slice introduces **no new types**. It reuses the landed reader output records and the `LedgerReaderConfig` trait unchanged, and adds **one** zero-sized config struct plus **one** golden fixture. This document pins the reused schema (for reviewer reference) and the concrete AU configuration + expected output.

---

## 1. Reused records (UNCHANGED — no schema change)

### `ParsedStatement` (`statement/base.rs`)
| Field | Type | AU usage |
|---|---|---|
| `bank_code` | `String` | `"AU"` |
| `lines` | `Vec<ParsedTransaction>` | 2 |
| `errored_lines` | `Vec<String>` | `[]` |
| `period_start` / `period_end` | `Option<NaiveDate>` | `2026-03-01` / `2026-05-31` (from `PERIOD_RE`) |
| `card_last4` | `Option<String>` | `"0042"` (trailing 4 only) |
| `printed_opening_balance` | `Option<Decimal>` | `11570.79` (from `OPENING_RE`) |
| `printed_closing_balance` | `Option<Decimal>` | **`16570.79`** — the LAST anchor's running balance (NOT the header's `223.34`; `ledger_reader.rs:195`) |
| `confidence` | `f64` | default `1.0` |

### `ParsedTransaction` (`statement/base.rs`)
`value_date: NaiveDate`, `amount: Decimal`, `direction: Direction`, `currency: String` (`"INR"`), `description_raw: String` (stitched, ≤ `MAX_RAW`=240 codepoints), `bank_code: String`, `ledger: Option<LedgerMetadata>` (always `Some` here).

### `LedgerMetadata` (`statement/base.rs`)
`balance: Decimal`, `balance_delta: Option<Decimal>`, `amount_matches_delta: bool`, `is_suspect: bool`, `direction_source: DirectionSource`, `serial: String` (**empty** for AU — the anchor has no serial group).

### `DirectionSource` (`statement/base.rs`) — enum, Debug spelling used in fixtures
`OpeningBalance` (row 1), `BalanceDelta` (row 2). `Row1XPosition` / `Row1Provisional` exist but are **not** exercised (AU sets no `column_split_x`; the fixture is opening-anchored).

### `Direction` (`model.rs`) — `Debit` | `Credit` (serde spelling `"Debit"`/`"Credit"`).

### `ChainResult` / `ChainStatus` (`statement/balance_chain.rs`) — reused via `check_balance_chain`
`status: Reconciled|NeedsReview`, `checked_rows: u32`, `suspect_count: u32`, `suspects: Vec<Suspect>`, `row1_direction_fallback: bool`, `derived_opening_balance`, `derived_closing_balance`, `reason`. AU ⇒ `Reconciled`, `suspect_count=0`, `row1_direction_fallback=false`, `checked_rows=2`, `derived_opening_balance=11570.79`, `derived_closing_balance=16570.79`.

---

## 2. New entity: `AuBankReader` (`statement/au_bank.rs`)

Zero-sized struct implementing `LedgerReaderConfig`. All state is in module `LazyLock<Regex>` statics + `const` marker slices. Structurally mirrors `IciciBankReader` (which also overrides `claim_any` + `closing_balance_re`), but with **one** anchor and **no** `column_split_x`.

| Trait method | Value |
|---|---|
| `bank_code()` | `"AU"` |
| `claim_all()` | `["aubank.in"]` |
| `claim_any()` | `["Savings Account", "Current Account"]` |
| `anchor_res()` | `vec![&ANCHOR_RE]` (single template) |
| `opening_balance_re()` | `Some(&OPENING_RE)` |
| `closing_balance_re()` | `Some(&CLOSING_RE)` *(narration-skip only; see note)* |
| `column_split_x()` | *(default `None`)* |
| `provisional_direction()` | *(default `Debit`, unused)* |
| `account_tail(text)` | `account_tail_last4(text, &AU_ACCOUNT_RE)` |
| `enrich(st, full_text)` | set `period_start/end` from `PERIOD_RE` (via `parse_date`); set `card_last4 = account_tail(full_text)` |

> **`closing_balance_re` note**: consumed ONLY by `is_balance_line` to skip the `Closing Balance(₹) : 223.34` header during narration stitching. It is **never** used to set `printed_closing_balance` (that is always the last anchor balance, `16570.79`). This is the intended parity behaviour (research.md, Decision 4).

### Regex statics (LOCKED — see research.md)
```text
ANCHOR_RE   = ^(?P<date>\d{2} [A-Za-z]{3} \d{4})\s+\d{2} [A-Za-z]{3} \d{4}\s+
              (?P<desc>.*?)\s*(?P<withdrawal>[\d,]+\.\d{2}|-)\s+
              (?P<deposit>[\d,]+\.\d{2}|-)\s+(?P<balance>[\d,]+\.\d{2})\s*$
OPENING_RE  = (?i)Opening Balance\s*\([^)]*\)\s*:\s*([\d,]+\.\d{2})
CLOSING_RE  = (?i)Closing Balance\s*\([^)]*\)\s*:\s*([\d,]+\.\d{2})
PERIOD_RE   = (?i)Statement Period\s*:\s*(\d{2} [A-Za-z]{3} \d{4})\s+to\s+(\d{2} [A-Za-z]{3} \d{4})
AU_ACCOUNT_RE = (?i)Account\s+Number\s*:?\s*X*([0-9]{6,})
```
Named groups consumed by the base: `date`, `desc`, `withdrawal`, `deposit`, `balance`. There is **no** `serial` group and **no** `amount` group (the two-column path resolves the non-dash side). The anchor is **not** `(?i)` (dates use `[A-Za-z]{3}`), matching the ICICI anchor style.

---

## 3. Expected output (the golden fixture)

### `fixtures/au/bank_account/savings.json` — 2 rows, RECONCILED

Top level: `period_start=2026-03-01`, `period_end=2026-05-31`, `card_last4="0042"`, `printed_opening_balance="11570.79"`, `printed_closing_balance="16570.79"`, `errored_lines=[]`.

| # | date | amount | direction | balance | balance_delta | matches | suspect | direction_source | serial | description_raw |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-03-01 | `5000.00` | Debit | `6570.79` | `-5000.00` | true | false | OpeningBalance | *(empty)* | `STORE 1111ref2222tail UPI/DR/000000000001/EXAMPLE ABC0000000001ref MERCHANT/UTIB/0000/UPI AU` |
| 2 | 2026-03-02 | `10000.00` | Credit | `16570.79` | `10000.00` | true | false | BalanceDelta | *(empty)* | `EMPLOYER 3333ref4444tail UPI/CR/000000000002/EXAMPLE XYZ0000000002ref SALARY/UTIB/0000/UPI AU 1800 1200 1200 www.aubank.in customercare@aubank.in` |

> **Dash-empty column**: row 1's amount is the **Debit** column `5,000.00` (Credit prints `-`); row 2's amount is the **Credit** column `10,000.00` (Debit prints `-`). The base's `loose_amount("-") → None` picks the non-dash side (research.md, Decision 3). Amounts stored with `.00` (printed scale).
> **`UPI/DR`/`UPI/CR`**: appear inside `description_raw` (counterparty leg) — never a direction signal. Row 1 is Debit (balance falls) despite `UPI/DR`; row 2 is Credit (balance rises) despite `UPI/CR`.
> **`₹` glyph**: `full_text`/`lines` preserve the literal U+20B9 in `Opening Balance(₹)` / `Closing Balance(₹)`; in JSON it may appear as the raw character or the `\u20b9` escape (both decode identically). `description_raw` is byte-for-byte (no normalization).

### Fixture `lines`/`full_text`
Taken verbatim from the captured ground truth. `lines` = the non-empty, stripped `splitlines()` of `full_text` (**15** lines). Anchor line indices **9** and **12** drive the stitch trace in research.md, Decision 8. `full_text` retains its trailing newline.

---

## 4. State & validation notes

- **Row-1 bootstrap**: `printed_opening_balance` present (`11570.79`) ⇒ `direction_source = OpeningBalance`; delta `6570.79 − 11570.79 = −5000.00 < 0 ⇒ Debit`. No geometry consulted (no `column_split_x`; `first_row_words` empty).
- **Suspect vs errored**: amount-vs-delta within ₹1.00 tolerance for both rows ⇒ 0 suspects; both anchor-shaped rows parse ⇒ 0 errored lines. Both inherited unchanged from the base/chain.
- **Row count**: the header, column-header, `Opening Balance(₹)`, `Closing Balance(₹)`, and footer lines are not anchors ⇒ exactly **2** rows.
- **Determinism**: pure functions; identical input ⇒ identical output (asserted by the harness `parse_is_deterministic`).
