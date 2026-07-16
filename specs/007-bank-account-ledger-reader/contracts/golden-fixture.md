# Contract: ICICI Bank-Account Golden Fixture (parity vector)

**Feature**: `007-bank-account-ledger-reader` | **Date**: 2026-07-16
**Fixture**: `fixtures/icici/bank_account/basic.json` (created in `/speckit.implement`, not here)
**Harness**: `core/crates/kaname-core/tests/parity.rs`

The golden vector pins the on-device ICICI bank-account reader **byte-for-byte** to the web engine
(Constitution Principle V). It is the ported synthetic ICICI-savings characterization vector; the persisted
ground truth is `icici-bank-ground-truth.json`. All data is **synthetic/redacted** — fabricated payers,
amounts, and a synthetic account number (FR-032). Amounts/balances/deltas are stored as **strings** and
re-parsed via `Decimal::from_str`, so **no `f64` touches money** and comparison is exact.

---

## Harness schema extension (back-compatible)

`tests/parity.rs` gains **optional** fields; every existing credit-card fixture omits them and deserializes
**unchanged** (the pattern already used for `period_start`, `tests/parity.rs:30–33`).

```rust
#[derive(Deserialize)]
struct ExpectedRow {
    date: String,
    amount: String,
    direction: Direction,
    currency: String,
    description_raw: String,
    // NEW — optional ledger fields (present only for balance-ledger fixtures):
    #[serde(default)] balance: Option<String>,
    #[serde(default)] balance_delta: Option<String>,
    #[serde(default)] direction_source: Option<DirectionSource>,
    #[serde(default)] serial: Option<String>,
    #[serde(default)] amount_matches_delta: Option<bool>,
    #[serde(default)] is_suspect: Option<bool>,
}

#[derive(Deserialize)]
struct Expected {
    rows: Vec<ExpectedRow>,
    #[serde(default)] period_start: Option<String>,
    period_end: Option<String>,
    card_last4: Option<String>,
    #[serde(default)] errored_lines: Vec<String>,
    // NEW — optional statement-level balances:
    #[serde(default)] printed_opening_balance: Option<String>,
    #[serde(default)] printed_closing_balance: Option<String>,
}
```

- The row assertion checks each ledger field **only when `Some`** (CC rows leave them `None` → skipped).
  `direction_source` deserializes straight into the `DirectionSource` enum (variant names below), exactly as
  `direction` deserializes into `Direction`.
- A new `Case` row registers the reader via a wrapper that supplies **empty geometry**:
  ```rust
  fn parse_icici_bank(lines: Vec<String>, full_text: String) -> ParsedStatement {
      kaname_core::read_icici_bank_statement(lines, full_text, Vec::new())
  }
  const CASES: &[Case] = &[ /* …5 CC rows unchanged… */
      Case { label: "ICICI bank", parse: parse_icici_bank, rel_path: "icici/bank_account/basic.json" },
  ];
  ```
- The generic `golden_fixtures_match_expected_output` + `parse_is_deterministic` tests then cover the bank
  vector automatically; a **dedicated** test additionally asserts the balance chain (below).

**Enum wire form** (Rust default `#[derive(Deserialize)]` = variant name): `direction` → `"Debit"`/
`"Credit"`; `direction_source` → `"OpeningBalance"`/`"BalanceDelta"`/`"Row1Xposition"`/`"Row1Provisional"`.
(The web engine's snake_case `opening_balance`/`balance_delta` maps to these PascalCase variants in the Rust
fixture, just as the web `DEBIT`/`CREDIT` maps to `Debit`/`Credit`.)

---

## Exact fixture bytes — `fixtures/icici/bank_account/basic.json`

```json
{
  "_comment": "Synthetic ICICI savings/current (bank-account) golden vector — no real data. Ported from the web engine's balance-ledger characterization (BalanceLedgerStatementReader + icici_bank + balance_chain); values captured from the persisted ground truth. amount/balance/balance_delta are strings (re-parsed to Decimal — never float). direction_source deserializes into the DirectionSource enum. Geometry is empty: row 1 is anchored by the printed Opening Balance, so the x-position path is not exercised.",
  "lines": [
    "ICICI Bank Limited",
    "Statement of Transactions in Savings Account",
    "Account Number 000401000123456",
    "Statement Period June 16, 2025 to July 15, 2025",
    "Opening Balance 1,00,000.00",
    "S No. Value Date Transaction Date Cheque No. Transaction Remarks Withdrawal Deposit Balance",
    "UPI/512345/ALICE STORE/Payment",
    "1 16.06.2025 16.06.2025 5,000.00 95,000.00",
    "NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY",
    "2 18.06.2025 18.06.2025 50,000.00 1,45,000.00",
    "3 20.06.2025 20.06.2025 ATM CASH WITHDRAWAL 2,000.00 1,43,000.00",
    "Closing Balance 1,43,000.00"
  ],
  "full_text": "ICICI Bank Limited\nStatement of Transactions in Savings Account\nAccount Number 000401000123456\nStatement Period June 16, 2025 to July 15, 2025\nOpening Balance 1,00,000.00\nS No. Value Date Transaction Date Cheque No. Transaction Remarks Withdrawal Deposit Balance\nUPI/512345/ALICE STORE/Payment\n1 16.06.2025 16.06.2025 5,000.00 95,000.00\nNEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY\n2 18.06.2025 18.06.2025 50,000.00 1,45,000.00\n3 20.06.2025 20.06.2025 ATM CASH WITHDRAWAL 2,000.00 1,43,000.00\nClosing Balance 1,43,000.00",
  "expected": {
    "rows": [
      {
        "date": "2025-06-16",
        "amount": "5000.00",
        "direction": "Debit",
        "currency": "INR",
        "description_raw": "UPI/512345/ALICE STORE/Payment",
        "balance": "95000.00",
        "balance_delta": "-5000.00",
        "direction_source": "OpeningBalance",
        "serial": "1",
        "amount_matches_delta": true,
        "is_suspect": false
      },
      {
        "date": "2025-06-18",
        "amount": "50000.00",
        "direction": "Credit",
        "currency": "INR",
        "description_raw": "NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY",
        "balance": "145000.00",
        "balance_delta": "50000.00",
        "direction_source": "BalanceDelta",
        "serial": "2",
        "amount_matches_delta": true,
        "is_suspect": false
      },
      {
        "date": "2025-06-20",
        "amount": "2000.00",
        "direction": "Debit",
        "currency": "INR",
        "description_raw": "ATM CASH WITHDRAWAL",
        "balance": "143000.00",
        "balance_delta": "-2000.00",
        "direction_source": "BalanceDelta",
        "serial": "3",
        "amount_matches_delta": true,
        "is_suspect": false
      }
    ],
    "period_start": "2025-06-16",
    "period_end": "2025-07-15",
    "card_last4": "3456",
    "printed_opening_balance": "100000.00",
    "printed_closing_balance": "143000.00",
    "errored_lines": []
  }
}
```

> The reader is called with `lines` = the non-empty stripped `splitlines` of `full_text` (as above) and an
> **empty** `Vec<Word>` (the fixture is opening-balance-anchored and geometry-free).

---

## Balance-chain expectation (dedicated test)

A dedicated parity test asserts the integrity check over the same fixture:

```
check_balance_chain(parse_icici_bank(fixture.lines, fixture.full_text)) ==
    ChainResult {
        status: Reconciled,
        checked_rows: 3,
        suspect_count: 0,
        suspects: [],
        row1_direction_fallback: false,
        derived_opening_balance: Some(100000.00),
        derived_closing_balance: Some(143000.00),
        reason: None,
    }
```

This proves SC-002 (RECONCILED, zero suspects, no row-1 fallback — row 1's `direction_source` is
`OpeningBalance`, not a fallback).

---

## What each assertion pins (traceability)

| Assertion | Requirement / SC |
|---|---|
| 3 rows, dates, amounts, directions | FR-004/008/012, SC-001 |
| descriptions (stitched narration) | FR-007, SC-001 |
| per-row `balance` / `balance_delta` | FR-020, SC-001 |
| `direction_source` (`OpeningBalance`, then `BalanceDelta×2`) | FR-014, SC-006 |
| `serial` (1/2/3), `amount_matches_delta`/`is_suspect` | FR-011/020 |
| `printed_opening_balance` / `printed_closing_balance` | FR-021, SC-008 |
| `period_start`/`period_end` | FR-021, SC-008 |
| `card_last4` `"3456"` (account-number tail) | FR-022, SC-008 |
| `errored_lines []` | FR-019 |
| balance chain RECONCILED, 0 suspects, no fallback | FR-017/018, SC-002 |
| determinism (re-run identical) | FR-025, SC-012/013 |

**No change to any credit-card fixture or `Case` row.** The five CC vectors and their assertions remain
byte-identical (research D9).
