# Contract: The Balance-Ledger Reader Base + Balance-Chain (internal Rust seam)

**Feature**: `007-bank-account-ledger-reader` | **Date**: 2026-07-16
**Module**: `kaname-core::statement::ledger_reader` + `kaname-core::statement::balance_chain`

This is the **reusable in-crate seam** for the whole bank-account (balance-ledger) reader family — the
analogue of the credit-card `line_reader.rs` seam. Its consumers are the per-issuer configs (ICICI now;
HDFC/Federal/AU later) and the FFI layer. It is a **stable contract** in the same sense as
`LineReaderConfig`: a new bank is added as a config that satisfies this trait, with **no** change to the
base's internals. Ported 1:1 from the web engine's `_ledger_reader.py` + `balance_chain.py`.

---

## `LedgerReaderConfig` (trait) — the per-issuer configuration

```rust
pub trait LedgerReaderConfig {
    fn bank_code(&self) -> &'static str;
    fn claim_all(&self) -> &'static [&'static str];
    fn claim_any(&self) -> &'static [&'static str];
    fn anchor_res(&self) -> &'static [&'static Regex];
    fn opening_balance_re(&self) -> Option<&'static Regex>;
    fn closing_balance_re(&self) -> Option<&'static Regex>;
    fn column_split_x(&self) -> Option<f64>;
    fn provisional_direction(&self) -> Direction { Direction::Debit }
    fn enrich(&self, _statement: &mut ParsedStatement, _full_text: &str) {}
    fn account_tail(&self, _text: &str) -> Option<String> { None }
}
```

**Method contracts**

| Method | Contract |
|---|---|
| `bank_code` | The issuer code (e.g. `"ICICI"`). Used by `claims_ledger` and stamped on every row/statement. |
| `claim_all` | Markers that **all** must be present (case-insensitive) for the reader to claim a document. Enough to distinguish this issuer's **savings/current** statement from its **credit-card** statement. |
| `claim_any` | Markers of which **at least one** must be present (case-insensitive) when non-empty. Empty ⇒ this gate is skipped. |
| `anchor_res` | One or more anchor regexes, tried **in order, first match wins** (multi-template banks supply several). Each defines named groups: `date`, `balance`, and **either** `amount` **or** a `withdrawal`+`deposit` pair; optional `serial` and `desc`. |
| `opening_balance_re` | Optional regex whose **group 1** is the printed opening balance; also used to recognise a balance line to skip during narration stitching. |
| `closing_balance_re` | Optional regex used to recognise a printed closing-balance line to skip during stitching. |
| `column_split_x` | Optional x-coordinate (layout points) splitting the withdrawal (left ⇒ debit) and deposit (right ⇒ credit) columns; consulted **only** for a geometry-only row 1. |
| `provisional_direction` | Row-1 fallback direction when neither opening balance nor geometry is available. Default `Debit`. |
| `enrich` | Populate statement-level metadata (`period_*`, `card_last4`, …) from `full_text`. Default no-op. |
| `account_tail` | Bank-account-aware account last-4 extractor (trailing 4 of the printed account number). Default `None`. **Not** the masked-PAN matcher. |

**Purity**: implementations are pure — all state is in `LazyLock<Regex>` statics; the config type is
zero-sized.

---

## `read_ledger_lines` — the parse

```rust
pub fn read_ledger_lines<C: LedgerReaderConfig + ?Sized>(
    cfg: &C, lines: &[String], full_text: &str, first_row_words: &[Word],
) -> ParsedStatement
```

**Guarantees**
1. **Total & pure** — never panics; no I/O, clock, locale, network, or global state. Deterministic.
2. **Anchor detection** — a line is a transaction **iff** it matches one of `anchor_res()`. Non-matching
   lines are skipped silently (headers, cheque numbers, balance lines). An anchor-shaped line whose
   `date`/`amount`/`balance` won't parse is appended to `errored_lines` (`truncate_chars(line, 240)`) and
   skipped — never fatal, and every good row is still returned (FR-006/019).
3. **Amount** — `anchor_amount`: if the matched pattern has an `amount` group, `parse_amount(amount)`; else
   the **non-zero** side of the `withdrawal`/`deposit` pair via a **loose** parser (comma-strip +
   `Decimal::from_str`, accepting bare integers like `0`/`59`/`50000`). Non-negative, scale preserved.
4. **Narration** — `stitch_narration`: inline `desc` (if any) + the line immediately **above** the anchor +
   the lines **below** up to the next anchor, skipping other anchor indices and balance lines; joined by
   single spaces, trimmed, ≤240 cp (FR-007).
5. **Direction** — delta-derived (`Debit` if `balance < prev`, else `Credit`) for every row after the first;
   **row 1** via `row1_direction`: `opening_balance` (printed) → `row1_xposition` (geometry vs
   `column_split_x`) → `provisional`. Recorded as `ledger.direction_source`. **Never** from the amount's
   sign (FR-008/013/014).
6. **Ledger metadata** — each row carries `Some(LedgerMetadata{ balance, balance_delta,
   amount_matches_delta, is_suspect, direction_source, serial })`. `amount_matches_delta` is **exact**
   `amount == balance_delta.abs()` (**no** tolerance — the ₹1.00 tolerance is chain-only). `is_suspect =
   !amount_matches_delta` (FR-009/011).
7. **Statement balances** — `printed_opening_balance` = the printed opening (via `opening_balance_re`) else
   `derived_opening(row1)` (`balance ± amount` by row-1 direction); `printed_closing_balance` = the last
   anchor's balance (FR-021).
8. **Enrichment** — `cfg.enrich(&mut statement, full_text)` runs last (even when there are no anchors), so
   `period_*`/`card_last4` are populated on empty statements too.

**Edge behaviour**: empty `lines` or no anchors ⇒ empty `lines`, `enrich` still runs, no error.
`first_row_words` empty ⇒ the geometry path is skipped (row 1 falls through to provisional if no opening
balance).

---

## `claims_ledger` — the document gate

```rust
pub fn claims_ledger<C: LedgerReaderConfig + ?Sized>(cfg: &C, text: &str, bank_code: &str) -> bool
```
`true` **iff** `bank_code == cfg.bank_code()` **and** every `claim_all()` marker is in `text`
(case-insensitive) **and** (`claim_any()` is empty **or** any `claim_any()` marker is in `text`). Mirrors
the web `BalanceLedgerStatementReader.claims`. This is what lets a savings statement and a credit-card
statement that share an issuer be routed to the correct reader (FR-001/002).

---

## `balance_chain::check` — the integrity check

```rust
pub fn check(statement: &ParsedStatement) -> ChainResult
```

**Semantics** (ported 1:1 from `balance_chain.check`)
- Empty `statement.lines` ⇒ `ChainResult { status: NeedsReview, checked_rows: 0, reason:
  Some("no parsed transactions"), .. }`.
- Otherwise walk rows 1-based from `prev = statement.printed_opening_balance`:
  - read `balance = row.ledger.balance`, `source = row.ledger.direction_source`;
  - a row missing its ledger/balance ⇒ suspect `"missing running balance"`;
  - `derived_row1 = (row == 1 && source ∈ {Row1XPosition, Row1Provisional})`;
  - when `prev.is_some() && !derived_row1`: `delta = balance − prev`; if `(amount − delta.abs()).abs() >
    Decimal("1.00")` ⇒ suspect `"amount {amount} != |balance delta| {delta.abs()}"`;
  - `prev = balance`.
- `row1_direction_fallback = lines[0].ledger.direction_source ∈ {Row1XPosition, Row1Provisional}`.
- `status = Reconciled` **iff** `suspects.is_empty() && !row1_direction_fallback`, else `NeedsReview`.
- `suspects` truncated to **20**; `suspect_count` = true count; `checked_rows = lines.len()`;
  `derived_opening_balance`/`derived_closing_balance` = the statement's printed balances when present.

**Invariants**
- The **₹1.00** tolerance lives **only** here (the reader's `amount_matches_delta` is exact — research D6).
- A chain break is a **suspect**, never an `errored_line` (FR-019); suspects remain in `statement.lines`.
- Pure & deterministic; no clock/network/global state.

---

## Adding a later bank (HDFC / Federal / AU) — the reuse contract

1. Add `statement/<bank>_bank.rs`: a zero-sized `struct` implementing `LedgerReaderConfig` — supply
   `bank_code`, `claim_all`/`claim_any`, one or more `anchor_res` (single-amount **or** two-column
   `withdrawal`/`deposit`), optional `opening`/`closing`/`column_split_x`, `enrich`, `account_tail`.
2. Add FFI `read_<bank>_bank_statement` + `<bank>_bank_claims` (wrap `read_ledger_lines`/`claims_ledger`).
3. Add one golden fixture `fixtures/<bank>/bank_account/*.json` + one `Case` row + (optionally) a
   balance-chain assertion.

**No change** to `ledger_reader.rs` or `balance_chain.rs` is expected — that is the point of the base.
