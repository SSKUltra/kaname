# Contract: Golden Fixtures & Parity Harness (HDFC Bank — two layouts)

**Feature**: `008-hdfc-bank-ledger-reader` | **Phase 1** | **Plan**: [`plan.md`](../plan.md)

Defines the two HDFC golden vectors and the additive parity-harness rows. The harness **schema is reused
unchanged** (extended in slice 007 to carry optional ledger fields + printed balances + a `Case` row per bank).
The exact fixture bytes below are authoritative; the files are authored during `/speckit.tasks` implementation
(test-first, before the reader), mirroring `fixtures/icici/bank_account/basic.json`.

## Fixture files (NEW)

- `fixtures/hdfc/bank_account/compact.json`
- `fixtures/hdfc/bank_account/detailed.json`

**Schema** (reused from 007): top-level `lines` (non-empty stripped `splitlines()` of `full_text`), `full_text`,
and `expected { rows[ { date, amount, direction, currency, description_raw, ledger{ balance, balance_delta,
amount_matches_delta, is_suspect, direction_source, serial } } ], period_start, period_end, card_last4,
printed_opening_balance, printed_closing_balance, errored_lines }`. Monetary fields are **strings** (parsed to
`Decimal`; never `f64`); `direction` is `Debit`/`Credit`; `direction_source` is the PascalCase enum variant.
All data is **synthetic/redacted** (FR-032).

### `fixtures/hdfc/bank_account/compact.json`

```json
{
  "_comment": "Synthetic HDFC savings/current bank-account golden vector — COMPACT layout (DD/MM/YY, single amount, alphanumeric ref as serial, opening balance from the end-of-statement summary row). No real data. Ported from the web engine's hdfc_bank.py (BalanceLedgerStatementReader); direction is derived from the running-balance delta and the printed amount is an independent check (amount == |balance delta|). RECONCILED. Header/summary lines are intentionally stitched into narration to match the web engine byte-for-byte.",
  "lines": [
    "HDFC BANK LIMITED",
    "Statementof account",
    "From : 01/04/2026 To : 30/04/2026",
    "AccountNo : 50100359253425",
    "Date Narration Chq./Ref.No. ValueDt WithdrawalAmt. DepositAmt. ClosingBalance",
    "01/04/26 UPI-EXAMPLEMERCHANT 0000600000000001 01/04/26 5,000.00 95,000.00",
    "16/04/26 NEFTCR-EXAMPLEEMPLOYER CITIN26653417445 16/04/26 50,000.00 1,45,000.00",
    "OpeningBalance DrCount CrCount Debits Credits ClosingBal",
    "1,00,000.00 1 1 5,000.00 50,000.00 1,45,000.00"
  ],
  "full_text": "HDFC BANK LIMITED\nStatementof account\nFrom : 01/04/2026 To : 30/04/2026\nAccountNo : 50100359253425\nDate Narration Chq./Ref.No. ValueDt WithdrawalAmt. DepositAmt. ClosingBalance\n01/04/26 UPI-EXAMPLEMERCHANT 0000600000000001 01/04/26 5,000.00 95,000.00\n16/04/26 NEFTCR-EXAMPLEEMPLOYER CITIN26653417445 16/04/26 50,000.00 1,45,000.00\nOpeningBalance DrCount CrCount Debits Credits ClosingBal\n1,00,000.00 1 1 5,000.00 50,000.00 1,45,000.00\n",
  "expected": {
    "rows": [
      {
        "date": "2026-04-01",
        "amount": "5000.00",
        "direction": "Debit",
        "currency": "INR",
        "description_raw": "UPI-EXAMPLEMERCHANT Date Narration Chq./Ref.No. ValueDt WithdrawalAmt. DepositAmt. ClosingBalance",
        "ledger": {
          "balance": "95000.00",
          "balance_delta": "-5000.00",
          "amount_matches_delta": true,
          "is_suspect": false,
          "direction_source": "OpeningBalance",
          "serial": "0000600000000001"
        }
      },
      {
        "date": "2026-04-16",
        "amount": "50000.00",
        "direction": "Credit",
        "currency": "INR",
        "description_raw": "NEFTCR-EXAMPLEEMPLOYER OpeningBalance DrCount CrCount Debits Credits ClosingBal 1,00,000.00 1 1 5,000.00 50,000.00 1,45,000.00",
        "ledger": {
          "balance": "145000.00",
          "balance_delta": "50000.00",
          "amount_matches_delta": true,
          "is_suspect": false,
          "direction_source": "BalanceDelta",
          "serial": "CITIN26653417445"
        }
      }
    ],
    "period_start": "2026-04-01",
    "period_end": "2026-04-30",
    "card_last4": "3425",
    "printed_opening_balance": "100000.00",
    "printed_closing_balance": "145000.00",
    "errored_lines": []
  }
}
```

### `fixtures/hdfc/bank_account/detailed.json`

```json
{
  "_comment": "Synthetic HDFC savings/current bank-account golden vector — DETAILED layout (DD/MM/YYYY, explicit Withdrawals/Deposits columns with the empty side 0.00, inline Opening Balance). No real data. Ported from the web engine's hdfc_bank.py; direction derived from the running-balance delta; printed amount is an independent check. RECONCILED. The column-header line is intentionally stitched into row-0 narration to match the web engine.",
  "lines": [
    "HDFC Bank",
    "Savings Account Details",
    "Statement From : 01/04/2026 To 30/04/2026",
    "Account Number : 50100359253425",
    "Opening Balance : 1,00,000.00 Limit : 0.00",
    "Txn Date Narration Withdrawals Deposits Closing Balance",
    "01/04/2026 UPI-EXAMPLEMERCHANT 5,000.00 0.00 95,000.00",
    "20/04/2026 UPI-EXAMPLEEMPLOYER salary 0.00 50,000.00 1,45,000.00"
  ],
  "full_text": "HDFC Bank\nSavings Account Details\nStatement From : 01/04/2026 To 30/04/2026\nAccount Number : 50100359253425\nOpening Balance : 1,00,000.00 Limit : 0.00\nTxn Date Narration Withdrawals Deposits Closing Balance\n01/04/2026 UPI-EXAMPLEMERCHANT 5,000.00 0.00 95,000.00\n20/04/2026 UPI-EXAMPLEEMPLOYER salary 0.00 50,000.00 1,45,000.00\n",
  "expected": {
    "rows": [
      {
        "date": "2026-04-01",
        "amount": "5000.00",
        "direction": "Debit",
        "currency": "INR",
        "description_raw": "UPI-EXAMPLEMERCHANT Txn Date Narration Withdrawals Deposits Closing Balance",
        "ledger": {
          "balance": "95000.00",
          "balance_delta": "-5000.00",
          "amount_matches_delta": true,
          "is_suspect": false,
          "direction_source": "OpeningBalance",
          "serial": ""
        }
      },
      {
        "date": "2026-04-20",
        "amount": "50000.00",
        "direction": "Credit",
        "currency": "INR",
        "description_raw": "UPI-EXAMPLEEMPLOYER salary",
        "ledger": {
          "balance": "145000.00",
          "balance_delta": "50000.00",
          "amount_matches_delta": true,
          "is_suspect": false,
          "direction_source": "BalanceDelta",
          "serial": ""
        }
      }
    ],
    "period_start": "2026-04-01",
    "period_end": "2026-04-30",
    "card_last4": "3425",
    "printed_opening_balance": "100000.00",
    "printed_closing_balance": "145000.00",
    "errored_lines": []
  }
}
```

## Why the expected values are what they are (traceability)

- **Dates** — compact rows use `DD/MM/YY` (`01/04/26`, `16/04/26`) → `2026-04-01`, `2026-04-16` **iff** OD-1's
  `DATE_FORMATS` reorder is applied (else Rust `chrono`'s greedy `%Y` yields `0026-…`; research **D8**).
  Detailed rows and the period are `DD/MM/YYYY` → parse under `%d/%m/%Y` regardless.
- **Amounts / balances / deltas** — normalized `Decimal` strings (comma-stripped, 2-dp). Debit deltas are
  negative. `amount_matches_delta = (amount == |delta|)` holds on every row (no suspects).
- **Direction** — row 0 from the **opening balance** (`100000 → 95000` ⇒ Debit; `OpeningBalance`); row 1 from
  the running **delta** (`95000 → 145000` ⇒ Credit; `BalanceDelta`). Never from the amount/column.
- **`serial`** — compact rows carry the anchor's `(?P<serial>…)`
  (`0000600000000001`, `CITIN26653417445`); detailed rows have no reference column ⇒ `""`.
- **`description_raw` (stitched, byte-for-byte)** — base `stitch_narration` = `inline_desc` + line-above +
  lines-below-to-next-anchor (joined by a space), skipping anchor lines and `is_balance_line` lines:
  - compact row 0 = `UPI-EXAMPLEMERCHANT` + the column-header line (index 4).
  - compact row 1 = `NEFTCR-EXAMPLEEMPLOYER` + the two trailing summary lines (indexes 7–8), which are **not**
    balance lines when tested in isolation (the newline-spanning `opening_balance_re` alt can't match a single
    line) — see research **D4**.
  - detailed row 0 = `UPI-EXAMPLEMERCHANT` + the column-header line (index 5).
  - detailed row 1 = `UPI-EXAMPLEEMPLOYER salary` (no trailing summary block).
- **Opening / closing** — opening `100000.00` from `opening_balance_re` (compact: summary line across `\n`;
  detailed: inline). Closing `145000.00` = final row balance (no closing regex).
- **Period / last-4** — `2026-04-01 → 2026-04-30`; `card_last4 = 3425` via `account_tail_last4` (both layouts).
- **`errored_lines`** — empty; every non-anchor line is preamble/header/summary/continuation, and every anchor
  parses cleanly.

## Parity harness rows (`tests/parity.rs`, ADDITIVE — no schema change)

```rust
// wrapper: HDFC needs no geometry, so first_row_words is empty
fn parse_hdfc_bank(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_hdfc_bank_statement(lines, full_text, Vec::new())
}

// add to the CASES table (alongside the icici_bank Case):
Case { fixture: "hdfc/bank_account/compact.json",  parse: parse_hdfc_bank },
Case { fixture: "hdfc/bank_account/detailed.json", parse: parse_hdfc_bank },
```

Plus (mirroring the icici_bank balance-chain test):

```rust
#[test]
fn hdfc_bank_compact_chain_reconciled() {
    let p = load("hdfc/bank_account/compact.json");
    assert_eq!(check_balance_chain(p.rows).status, ChainStatus::Reconciled);
}

#[test]
fn hdfc_bank_detailed_chain_reconciled() {
    let p = load("hdfc/bank_account/detailed.json");
    assert_eq!(check_balance_chain(p.rows).status, ChainStatus::Reconciled);
}

#[test]
fn hdfc_bank_claims_accepts_bank_rejects_card() {
    assert!(hdfc_bank_claims(compact_full_text));
    assert!(hdfc_bank_claims(detailed_full_text));
    assert!(!hdfc_bank_claims(hdfc_card_style_text)); // has "HDFC" but no bank claim_any token
}
```

## Acceptance

- Both `Case` rows reproduce `expected` **exactly** (every row + ledger field + printed balances + period +
  last-4 + `errored_lines == []`).
- Both balance-chain tests return `Reconciled`.
- The claims test accepts both bank layouts and rejects an HDFC card statement.
- Determinism: re-running the harness yields identical results (SC-014).
- Verified end-to-end in an out-of-repo Rust replica (63/63 assertions green with OD-1 applied).
