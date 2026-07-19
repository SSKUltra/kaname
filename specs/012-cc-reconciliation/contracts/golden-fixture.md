# Contract: Golden-Fixture Schema — reconciliation vectors

**Feature**: `012-cc-reconciliation` | **Date**: 2026-07-19
**Consumers**: `core/crates/kaname-core/tests/parity.rs`. Reuses the schema defined in
`../../002-icici-cc-parser/contracts/golden-fixture.md` and extended by
`../../003-hdfc-cc-parser/contracts/golden-fixture.md` (`period_start`, `#[serde(default)]`) and
`../../007-bank-account-ledger-reader/contracts/golden-fixture.md` (`printed_opening_balance` /
`printed_closing_balance` + `ledger`). This slice adds **two optional `expected` keys**
(`printed_total_debits` / `printed_total_credits`), **extends the Yes vector's `full_text`** (two printed
totals), **adds two `expected` keys to the IOB vector** (no `full_text` change), and **reuses the ICICI
vector unchanged** as the neutral case. **No new fixture file** is added.

---

## Schema extension (two additive optional keys)

`Expected` gains two `#[serde(default)]` `Option<String>` fields — the same pattern the ledger balance
keys use (so every existing fixture that omits them deserializes to `None`, unchanged):

```rust
#[derive(Deserialize)]
struct Expected {
    // … existing fields …
    #[serde(default)]
    printed_total_debits: Option<String>,
    #[serde(default)]
    printed_total_credits: Option<String>,
}
```

**Field rules**
- Both are **JSON strings** (never numbers) → `Decimal::from_str`, so no `f64` touches money and scale is
  exact (`"100.00"`, `"9000.00"`, `"3500.00"`, `"1000.00"`) (FR-017, SC-012).
- Present **only** on the Yes and IOB credit-card vectors this slice. Every other fixture (all bank_account
  vectors + the other credit-card vectors, incl. ICICI) **omits** both keys → `None` (unchanged).
- Asserted in `assert_matches_expected` via the existing `parse_dec` closure:
  ```rust
  assert_eq!(statement.printed_total_debits,
      expected.printed_total_debits.as_deref().map(parse_dec), "{label}: printed_total_debits");
  assert_eq!(statement.printed_total_credits,
      expected.printed_total_credits.as_deref().map(parse_dec), "{label}: printed_total_credits");
  ```

---

## 1) Yes vector — `fixtures/yes/credit_card/basic.json` (EDIT: full_text + two expected keys)

Two printed-total lines are inserted into `full_text` **immediately after the `Statement Period:` line**
(and **before** the two transaction lines). `lines`, `rows`, `period_start`, `period_end`, `card_last4`,
and `errored_lines` are **unchanged** (only `full_text` feeds `enrich`; `lines` is the parse input and
stays as the two transaction rows). Two `expected` keys are added; the `_comment` is updated.

- Inserted `full_text` lines (exact):
  - `Current Purchases / Cash Advance & Other Charges : Rs. 100.00 Dr`
  - `Payment & Credits Received : Rs. 9,000.00 Cr`
- `DEBITS_RE` matches the first line → `printed_total_debits = 100.00`; `CREDITS_RE` matches the second →
  `printed_total_credits = 9000.00` (thousands separator stripped by `parse_amount`). The transaction
  lines' own `… 9,000.00 Cr` / `… 100.00 Dr` are **not** matched by the total regexes (no
  `Purchases`/`Payment & Credits Received` label), and the summary lines precede them anyway (first-match
  wins) (FR-012, verified — plan D10).
- Added `expected` keys: `"printed_total_debits": "100.00"`, `"printed_total_credits": "9000.00"`.

**Exact fixture bytes to write in implementation** (`fixtures/yes/credit_card/basic.json`):

```json
{
  "_comment": "Synthetic Yes Bank (Kiwi) credit-card golden vector (no real data). Ported from the web engine's test_cc_reader_characterization.py _YES case; values captured from a live run of the web reader. Layout: DD/MM/YYYY <details ... Ref No> <Merchant Category> <amount> Dr|Cr. Reconciliation printed-totals are now surfaced (012-cc-reconciliation): printed_total_debits 100.00 from 'Current Purchases / Cash Advance & Other Charges : Rs. 100.00 Dr' and printed_total_credits 9000.00 from 'Payment & Credits Received : Rs. 9,000.00 Cr', both added to full_text after the 'Statement Period:' line (lines/rows/period/last4 unchanged). read_debits 100.00 / read_credits 9000.00 match, so reconcile_statement -> RECONCILED.",
  "lines": [
    "29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr",
    "19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr"
  ],
  "full_text": "YES BANK KLICK\nStatement for YES BANK Card Number 3561XXXXXXXX6686\nStatement Period: 17/04/2026 To 16/05/2026\nCurrent Purchases / Cash Advance & Other Charges : Rs. 100.00 Dr\nPayment & Credits Received : Rs. 9,000.00 Cr\n29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr\n19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr",
  "expected": {
    "rows": [
      {
        "date": "2026-04-29",
        "amount": "9000.00",
        "direction": "Credit",
        "currency": "INR",
        "description_raw": "PAYMENT RECEIVED BBPS - Ref No: RT0001"
      },
      {
        "date": "2026-04-19",
        "amount": "100.00",
        "direction": "Debit",
        "currency": "INR",
        "description_raw": "UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores"
      }
    ],
    "period_start": "2026-04-17",
    "period_end": "2026-05-16",
    "card_last4": "6686",
    "printed_total_debits": "100.00",
    "printed_total_credits": "9000.00",
    "errored_lines": []
  }
}
```

> **Reconcile expectation**: `read_debits 100.00 == printed 100.00` and `read_credits 9000.00 == printed
> 9000.00` (both `|Δ| = 0 <= 1.00`) ⇒ `reconcile_statement` → `Some(Reconciled)` (SC-002/014).

---

## 2) IOB vector — `fixtures/iob/credit_card/basic.json` (EDIT: two expected keys only)

**No `full_text` change** — the vector already carries the `ACCOUNT SUMMARY` block and its values row
(`345.50  1,000.00  3,500.00  0  2,845.50`). `SUMMARY_RE` scrapes the **2nd** figure as credits
(`1000.00`) and the **3rd** as debits (`3500.00`) (FR-013, verified — plan D11). Two `expected` keys are
added; the `_comment` is updated. Rows/period_end/card_last4/errored_lines unchanged.

- Added `expected` keys: `"printed_total_debits": "3500.00"`, `"printed_total_credits": "1000.00"`.
- Updated `_comment` tail (replace the "intentionally not modeled" carve-out sentence):
  `"Reconciliation printed-totals are now surfaced (012-cc-reconciliation) from the ACCOUNT SUMMARY
  values row 345.50 1,000.00 3,500.00 0 2,845.50: printed_total_credits 1000.00 (2nd figure) and
  printed_total_debits 3500.00 (3rd figure); full_text is unchanged. read_debits 3500.00 / read_credits
  1000.00 match, so reconcile_statement -> RECONCILED."`

**Resulting `expected` block** (the two keys added just before `errored_lines`; the rest byte-for-byte as
today):

```json
  "expected": {
    "rows": [
      { "date": "2026-03-31", "amount": "1000.00", "direction": "Credit", "currency": "INR", "description_raw": "ExampleRefundMerchant" },
      { "date": "2026-04-04", "amount": "3500.00", "direction": "Debit",  "currency": "INR", "description_raw": "ExampleStorePurchase" }
    ],
    "period_end": "2026-04-20",
    "card_last4": "0042",
    "printed_total_debits": "3500.00",
    "printed_total_credits": "1000.00",
    "errored_lines": []
  }
```

> **Direction note**: in the IOB `ACCOUNT SUMMARY` **credits precede debits** (`Payment / Credits` then
> `Purchases / Debits`), so `SUMMARY_RE`'s `credits` group is the 2nd figure and `debits` the 3rd — the
> opposite column order from Yes. The reconcile still matches (`read_debits 3500.00 == printed 3500.00`,
> `read_credits 1000.00 == printed 1000.00`) ⇒ `Some(Reconciled)` (SC-003/014).

---

## 3) ICICI vector — `fixtures/icici/credit_card/basic.json` (REUSED, unchanged) — the neutral case

**No change.** It has no printed totals and no printed balances, so it deserializes with both new keys
`None`, and `reconcile_statement` returns the **neutral** outcome (`status None`, `reason "no printed
totals extracted"`). This is the golden vector for `statement_without_printed_totals_is_neutral`
(FR-015, SC-006).

---

## Reconcile parity tests (added to `tests/parity.rs`)

Three tests use `reconcile_statement` + `ReconcileStatus` (imported alongside the existing
`check_balance_chain`/`ChainStatus`), mirroring the `*_balance_chain_reconciles` pattern:

```rust
#[test]
fn yes_statement_reconciles() {
    let fx = load_fixture("yes/credit_card/basic.json");
    let statement = read_yes_statement(fx.lines, fx.full_text);
    let result = reconcile_statement(statement);
    assert_eq!(result.status, Some(ReconcileStatus::Reconciled));
    assert_eq!(result.read_debits, Decimal::from_str("100.00").unwrap());
    assert_eq!(result.read_credits, Decimal::from_str("9000.00").unwrap());
    assert_eq!(result.printed_debits, Some(Decimal::from_str("100.00").unwrap()));
    assert_eq!(result.printed_credits, Some(Decimal::from_str("9000.00").unwrap()));
}

#[test]
fn iob_statement_reconciles() {
    let fx = load_fixture("iob/credit_card/basic.json");
    let statement = read_iob_statement(fx.lines, fx.full_text);
    let result = reconcile_statement(statement);
    assert_eq!(result.status, Some(ReconcileStatus::Reconciled));
    assert_eq!(result.read_debits, Decimal::from_str("3500.00").unwrap());
    assert_eq!(result.read_credits, Decimal::from_str("1000.00").unwrap());
    assert_eq!(result.printed_debits, Some(Decimal::from_str("3500.00").unwrap()));
    assert_eq!(result.printed_credits, Some(Decimal::from_str("1000.00").unwrap()));
}

#[test]
fn statement_without_printed_totals_is_neutral() {
    let fx = load_fixture("icici/credit_card/basic.json");
    let statement = read_icici_statement(fx.lines, fx.full_text);
    let result = reconcile_statement(statement);
    assert_eq!(result.status, None);
    assert_eq!(result.reason.as_deref(), Some("no printed totals extracted"));
}
```
(`read_yes_statement`/`read_iob_statement`/`read_icici_statement` are the credit-card readers — **no
`first_row_words` argument**, unlike the bank-account readers.)

---

## Harness behaviour (contract)

1. The parity loop (unchanged) additionally asserts `printed_total_debits`/`printed_total_credits` on
   every fixture via `assert_matches_expected` — Yes/IOB pin them; all others assert `None`.
2. The three reconcile tests above load their fixtures with the existing `load_fixture` helper, parse,
   call `reconcile_statement`, and assert `status` + the tier-specific detail.
3. All comparisons are exact `Decimal`/enum value-equality; re-running yields identical results
   (determinism — SC-013). Any mismatch **fails** (parity guard — FR-023/024).

No fixture data outside Yes/IOB changes; the two new `Expected` keys are additive and default to `None`,
so all prior parity assertions hold unchanged. All fixture data remains synthetic/redacted (FR-026,
SC-018).
