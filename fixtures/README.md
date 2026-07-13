# Golden fixtures

This directory holds **golden test vectors** that pin the on-device engine's behaviour
to the proven web engine. They are ported from the FinTrack/Kaname web repo
(`backend/tests/`) and are the source of truth for parity.

## What gets ported (P2)
Each fixture is a redacted/synthetic statement plus its expected engine output:

- **Statement parity** — parsed transactions per bank/card reader
  (`test_statement_export_parity`, `test_bank_statement_export_parity`).
- **Reconciliation** — CC reconciliation + bank balance-chain integrity
  (`test_statement_reconciliation`, balance-chain checks).
- **Coverage** — statement date-range coverage (`test_statement_coverage`).
- **Cross-source dedup** — the same txn seen across sources collapses to one
  (`test_statement_cross_source_dedup`, `test_bank_statement_cross_source_dedup`).
- **Privacy egress** — asserts **zero network** in free/core paths
  (`test_statement_privacy_egress`) → enforced as a constitution gate.

## Format
Line-based readers (credit-card statements) use a single self-contained JSON per
vector — extracted `lines` + `full_text` in, `expected` engine output out:
```
fixtures/
  <bank_code>/<account_kind>/
    <name>.json   # { lines[], full_text, expected: { rows[], period_end, card_last4, errored_lines[] } }
```
Amounts and dates are stored as **strings** (re-parsed to `Decimal`/`NaiveDate`), so
no floating-point value ever touches money. Word x-positions arrive with the future
bank-ledger reader; line readers do not need them.

Fixtures MUST be synthetic or fully redacted — **no real account data**.

> First populated in P2: `icici/credit_card/basic.json` (see `specs/002-icici-cc-parser/`).
