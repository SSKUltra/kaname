# Phase 1 — Contracts: Federal Bank Ledger Reader (UniFFI surface + document gate + parity harness)

**Feature**: 009-federal-bank-ledger-reader · **Date**: 2026-07-17

No new UniFFI **types** are introduced — only two new exported **functions** that reuse the landed `ParsedStatement`, `Word`, and `ChainResult` records. This mirrors the ICICI (007) and HDFC (008) bank surfaces exactly.

---

## C1. UniFFI function contract (`core/crates/kaname-core/src/ffi.rs`, re-exported in `lib.rs`)

### `read_federal_bank_statement`
```rust
#[uniffi::export]
pub fn read_federal_bank_statement(
    lines: Vec<String>,
    full_text: String,
    first_row_words: Vec<Word>,
) -> ParsedStatement
```
- **Wraps**: `read_ledger_lines(&FederalBankReader, &lines, &full_text, &first_row_words)`.
- **Inputs**: `lines` = native-extracted, non-empty, stripped text lines; `full_text` = the whole statement text (for `enrich`/opening extraction); `first_row_words` = first anchor row word geometry — **pass empty** for Federal (no `column_split_x`; both fixtures opening-anchored). The core **never opens a PDF** (FR-028).
- **Output**: `ParsedStatement` (see data-model.md). Pure & total — an anchor-shaped row whose fields won't parse lands in `errored_lines`; a row whose amount ≠ delta is flagged `is_suspect` but kept. Never panics, never errors.
- **Determinism**: no clock/locale/network/global state (FR-029).

### `federal_bank_claims`
```rust
#[uniffi::export]
pub fn federal_bank_claims(full_text: String) -> bool
```
- **Wraps**: `claims_ledger(&FederalBankReader, &full_text, "FEDERAL")`.
- **Returns** `true` iff bank code is `FEDERAL` **and** `full_text` contains (case-insensitively) **all** of `claim_all` = `Federal Bank` **and** `Statement of Account`.

### Reused (UNCHANGED)
```rust
#[uniffi::export]
pub fn check_balance_chain(statement: ParsedStatement) -> ChainResult   // already exported
```

### `lib.rs` re-export delta
Add `federal_bank_claims` and `read_federal_bank_statement` to the existing `pub use ffi::{…}` list (alongside `hdfc_bank_claims`, `read_hdfc_bank_statement`). No other change.

---

## C2. Document gate (claims) contract — the savings-vs-Scapia split under the shared `FEDERAL` code

| Input document | `federal_bank_claims` | `federal_claims` (Scapia CC, landed) |
|---|---|---|
| Federal **classic** savings (`Federal Bank` + `Statement of Account`) | **true** | false |
| Federal **Fi** neobank (`Federal Bank` + `Statement of account`, case-insensitive) | **true** | false |
| Scapia/Federal **credit-card** (`Federal Bank`, `Scapia`, **no** `Statement of Account`) | **false** | **true** |
| Different issuer (e.g. `ICICI Bank Statement`) | false | false |

- **Invariant**: exactly one reader claims each document — **0 misroutes** (SC-008). The two coexist (research.md, Decision 5); neither is modified beyond adding the new bank surface.
- **Bank-code guard**: `claims_ledger` returns `false` when the caller passes a non-`FEDERAL` code, independent of markers.

---

## C3. Behavioural contract (from the spec's FRs — enforced by the fixtures)

| Contract | Assertion | Ref |
|---|---|---|
| Row count | classic ⇒ 3, fi ⇒ 2 (headers, `Opening Balance`, `GRAND TOTAL` yield no rows) | FR-017, SC-007 |
| Direction | from balance delta only; trailing `Cr`/`Dr` ignored (all markers `Cr`, mix of Dr/Cr rows) | FR-007/008, SC-004 |
| Amount as check | `amount == |delta|` (±₹1.00) ⇒ `amount_matches_delta`; whole-number Fi amounts reconcile | FR-009, SC-005 |
| Serial | optional `S\d+` captured as `serial`, **never** in `description_raw` | FR-012/013, SC-006 |
| Opening / row 1 | opening read from both templates (OPNBAL tolerated) ⇒ row 1 `direction_source=OpeningBalance` | FR-014/015 |
| Narration | stitched byte-for-byte incl. folded continuation + `GRAND TOTAL` | FR-016, SC-007 |
| Metadata | period (ISO or `DD/MM/YYYY`), `card_last4` (trailing 4 only) | FR-019/020/021, SC-009 |
| Balance chain | RECONCILED, 0 suspects, no row-1 fallback; `checked_rows` 3/2 | FR-027, SC-003 |
| Money type | exact `Decimal`, never `f64` | FR-011, SC-011 |
| Privacy | zero network in the whole parse/chain path | FR-031/033, SC-012 |

---

## C4. Parity harness contract (`core/crates/kaname-core/tests/parity.rs`) — NO schema change

1. **Imports**: add `federal_bank_claims`, `read_federal_bank_statement` to the `kaname_core::{…}` use list.
2. **Wrapper** (fits the `Case.parse: fn(Vec<String>, String) -> ParsedStatement` signature; empty geometry):
   ```rust
   fn parse_federal_bank(lines: Vec<String>, full_text: String) -> ParsedStatement {
       read_federal_bank_statement(lines, full_text, Vec::new())
   }
   ```
3. **Two `Case` rows** appended to `CASES`:
   ```rust
   Case { label: "Federal bank classic", parse: parse_federal_bank, rel_path: "federal/bank_account/classic.json" },
   Case { label: "Federal bank Fi",      parse: parse_federal_bank, rel_path: "federal/bank_account/fi.json" },
   ```
   These flow through the existing `golden_fixtures_match_expected_output` and `parse_is_deterministic` tests unchanged (the harness already supports optional ledger fields, printed balances, per-row `ledger`, and `errored_lines`).
4. **One balance-chain test** (mirrors `hdfc_bank_statements_balance_chain_reconciles`, but per-fixture `checked_rows` differ → iterate `(path, checked_rows)` pairs):
   ```rust
   #[test]
   fn federal_bank_statements_balance_chain_reconciles() {
       for (rel_path, checked) in [
           ("federal/bank_account/classic.json", 3u32),
           ("federal/bank_account/fi.json", 2u32),
       ] {
           let fx = load_fixture(rel_path);
           let result = check_balance_chain(read_federal_bank_statement(fx.lines, fx.full_text, Vec::new()));
           assert_eq!(result.status, ChainStatus::Reconciled, "{rel_path}");
           assert_eq!(result.suspect_count, 0, "{rel_path}: no suspects");
           assert!(!result.row1_direction_fallback, "{rel_path}: opening-anchored");
           assert_eq!(result.checked_rows, checked, "{rel_path}");
       }
   }
   ```
5. *(Optional, mirrors the CC readers)* a `federal_bank_claims_accepts_own_document_and_rejects_others` test asserting it claims both Federal bank fixtures and rejects the Scapia CC fixture (`federal/credit_card/basic.json`) and a foreign issuer.

---

## C5. Swift bridge contract (`ios/`, Swift Testing — mirrors HDFC)

A `@Test` "core ↔ Swift Federal bank parse + chain" over the UniFFI binding: call `readFederalBankStatement(lines:fullText:firstRowWords:)` with the classic fixture, assert 3 rows / directions / `Decimal` amounts, then `checkBalanceChain(...)` ⇒ `.reconciled`. Confirms the new surface is reachable from Swift (FR-030, SC-013). Money surfaces as Foundation `Decimal` (never a float).

---

## C6. What this slice does NOT change (regression guard)

`ledger_reader.rs`, `balance_chain.rs`, `common.rs`, `base.rs`, `federal.rs` (Scapia), the parity-harness **schema**, the privacy-egress gate, `Cargo.toml`/`Cargo.lock` (no dependency), and `fixtures/federal/credit_card/basic.json`. Any diff to these (beyond the additive `mod.rs`/`ffi.rs`/`lib.rs`/`parity.rs` lines) is out of contract.
