# Phase 1 — Contracts: AU Bank Ledger Reader (UniFFI surface + document gate + parity harness)

**Feature**: 010-au-bank-ledger-reader · **Date**: 2026-07-17

No new UniFFI **types** are introduced — only two new exported **functions** that reuse the landed `ParsedStatement`, `Word`, and `ChainResult` records. This mirrors the ICICI (007), HDFC (008), and Federal (009) bank surfaces exactly.

---

## C1. UniFFI function contract (`core/crates/kaname-core/src/ffi.rs`, re-exported in `lib.rs`)

### `read_au_bank_statement`
```rust
#[uniffi::export]
pub fn read_au_bank_statement(
    lines: Vec<String>,
    full_text: String,
    first_row_words: Vec<Word>,
) -> ParsedStatement
```
- **Wraps**: `read_ledger_lines(&AuBankReader, &lines, &full_text, &first_row_words)`.
- **Inputs**: `lines` = native-extracted, non-empty, stripped text lines; `full_text` = the whole statement text (for `enrich`/opening extraction); `first_row_words` = first anchor row word geometry — **pass empty** for AU (no `column_split_x`; the fixture is opening-anchored). The core **never opens a PDF** (FR-027).
- **Output**: `ParsedStatement` (see data-model.md). Pure & total — an anchor-shaped row whose fields won't parse lands in `errored_lines`; a row whose amount ≠ delta is flagged `is_suspect` but kept. Never panics, never errors.
- **Determinism**: no clock/locale/network/global state (FR-028).

### `au_bank_claims`
```rust
#[uniffi::export]
pub fn au_bank_claims(full_text: String) -> bool
```
- **Wraps**: `claims_ledger(&AuBankReader, &full_text, "AU")`.
- **Returns** `true` iff bank code is `AU` **and** `full_text` contains (case-insensitively) **all** of `claim_all` = `aubank.in` **and** **any** of `claim_any` = `Savings Account` / `Current Account`.

### Reused (UNCHANGED)
```rust
#[uniffi::export]
pub fn check_balance_chain(statement: ParsedStatement) -> ChainResult   // already exported
```

### `lib.rs` re-export delta
Add `au_bank_claims` and `read_au_bank_statement` to the existing `pub use ffi::{…}` list (alongside `federal_bank_claims`, `read_federal_bank_statement`). No other change.

---

## C2. Document gate (claims) contract — AU is the SOLE reader under `AU`

| Input document | `au_bank_claims` |
|---|---|
| AU savings (`aubank.in` + `Savings Account`) | **true** |
| AU current (`aubank.in` + `Current Account`) | **true** |
| A credit-card statement lacking a Savings/Current marker | **false** (`claim_any` unmet) |
| `aubank.in` present but no Savings/Current marker | **false** (`claim_any` unmet) |
| Different issuer (wrong bank code, e.g. `ICICI`) | **false** (bank-code guard) |

- **Invariant**: AU has **no** credit-card reader in this client, so `AuBankReader` is the only reader keyed to `AU` (SC-006). There is no sibling reader to mis-route to.
- **Bank-code guard**: `claims_ledger` returns `false` when the caller passes a non-`AU` code, independent of markers.

---

## C3. Behavioural contract (from the spec's FRs — enforced by the fixture)

| Contract | Assertion | Ref |
|---|---|---|
| Row count | 2 (header, column-header, `Opening/Closing Balance`, footer yield no rows) | FR-016, SC-005 |
| Direction | from balance delta only; `UPI/DR`/`UPI/CR` in narration ignored (debit despite `UPI/DR`, credit despite `UPI/CR`) | FR-006/007, SC-003 |
| Dash-empty column | amount = non-dash of (Debit, Credit); `loose_amount("-") → None` (base unchanged) | FR-005, SC-004 |
| Amount as check | `amount == \|delta\|` (±₹1.00) ⇒ `amount_matches_delta` (row1 5000.00, row2 10000.00) | FR-008/009, SC-004 |
| Serial | AU anchor has no serial group ⇒ `serial = ""` on every row | FR-017 |
| Opening / row 1 | opening `11570.79` read from `Opening Balance(₹)…` ⇒ row 1 `direction_source=OpeningBalance` | FR-011/014 |
| Printed closing | `printed_closing_balance = 16570.79` (last row balance), **NOT** header `223.34`; `Closing Balance(₹)` line yields no row | FR-012/013, SC-007 |
| Narration | stitched byte-for-byte incl. `UPI/…` line above each anchor + trailing footer folded into last row | FR-015, SC-005 |
| Metadata | period `2026-03-01 → 2026-05-31`, `card_last4="0042"` (trailing 4 only) | FR-018/019/020, SC-007 |
| Balance chain | RECONCILED, 0 suspects, no row-1 fallback; `checked_rows=2` | FR-026, SC-002 |
| Money type | exact `Decimal`, never `f64` | FR-010, SC-009 |
| Privacy | zero network in the whole parse/chain path | FR-030/032, SC-010 |

---

## C4. Parity harness contract (`core/crates/kaname-core/tests/parity.rs`) — NO schema change

1. **Imports**: add `au_bank_claims`, `read_au_bank_statement` to the `kaname_core::{…}` use list.
2. **Wrapper** (fits the `Case.parse: fn(Vec<String>, String) -> ParsedStatement` signature; empty geometry):
   ```rust
   fn parse_au_bank(lines: Vec<String>, full_text: String) -> ParsedStatement {
       read_au_bank_statement(lines, full_text, Vec::new())
   }
   ```
3. **One `Case` row** appended to `CASES`:
   ```rust
   Case { label: "AU bank savings", parse: parse_au_bank, rel_path: "au/bank_account/savings.json" },
   ```
   This flows through the existing `golden_fixtures_match_expected_output` and `parse_is_deterministic` tests unchanged (the harness already supports optional ledger fields, printed balances, per-row `ledger`, and `errored_lines`).
4. **One balance-chain test** (mirrors `federal_bank_statements_balance_chain_reconciles`, single fixture, `checked_rows=2`):
   ```rust
   #[test]
   fn au_bank_statement_balance_chain_reconciles() {
       let fx = load_fixture("au/bank_account/savings.json");
       let result = check_balance_chain(read_au_bank_statement(fx.lines, fx.full_text, Vec::new()));
       assert_eq!(result.status, ChainStatus::Reconciled);
       assert_eq!(result.suspect_count, 0, "no suspect rows");
       assert!(!result.row1_direction_fallback, "row-1 was opening-anchored");
       assert_eq!(result.checked_rows, 2);
   }
   ```
5. *(Optional, mirrors the CC/bank readers)* an `au_bank_claims_accepts_own_document_and_rejects_others` test asserting it claims the AU fixture and rejects a credit-card statement lacking a Savings/Current marker and a foreign issuer (wrong code).

---

## C5. Swift bridge contract (`ios/`, Swift Testing — mirrors Federal/HDFC)

A `@Test` "core ↔ Swift AU bank parse + chain" over the UniFFI binding: call `readAuBankStatement(lines:fullText:firstRowWords:)` with the savings fixture, assert 2 rows / directions (Debit then Credit) / `Decimal` amounts, then `checkBalanceChain(...)` ⇒ `.reconciled`. Confirms the new surface is reachable from Swift (FR-029, SC-011). Money surfaces as Foundation `Decimal` (never a float).

---

## C6. What this slice does NOT change (regression guard)

`ledger_reader.rs`, `balance_chain.rs`, `common.rs`, `base.rs`, the ICICI/HDFC/Federal readers, the parity-harness **schema**, the privacy-egress gate, and `Cargo.toml`/`Cargo.lock` (no dependency). Any diff to these (beyond the additive `mod.rs`/`ffi.rs`/`lib.rs`/`parity.rs` lines and the new `au_bank.rs` + `fixtures/au/bank_account/savings.json`) is out of contract.
