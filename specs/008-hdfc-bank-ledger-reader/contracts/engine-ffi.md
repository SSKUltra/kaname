# Contract: Engine FFI Surface (HDFC Bank Reader) — additive, no new types

**Feature**: `008-hdfc-bank-ledger-reader` | **Phase 1** | **Plan**: [`plan.md`](../plan.md)

Defines the UniFFI functions this slice adds. **Additive only** — every parameter and return type already has a
binding from slice 007, so `uniffi.toml`, the `Decimal ↔ Foundation.Decimal` map, and the generated Swift shape
are otherwise unchanged. Rebuild via `make core-xcframework` **before** `tuist generate`.

## New exported functions (`src/ffi.rs`, re-exported from `src/lib.rs`)

### `read_hdfc_bank_statement`

```rust
#[uniffi::export]
pub fn read_hdfc_bank_statement(
    lines: Vec<String>,
    full_text: String,
    first_row_words: Vec<Word>,
) -> ParsedStatement {
    read_ledger_lines(&HdfcBankReader, &lines, &full_text, &first_row_words)
}
```

- **Purpose**: parse an HDFC savings/current statement (either export layout) into a `ParsedStatement`.
- **Inputs**:
  - `lines` — the statement's text lines (non-empty, stripped) as extracted natively.
  - `full_text` — the whole statement text (used for opening balance, period, account last-4, and cross-line
    narration context).
  - `first_row_words` — layout tokens for the two-column x-split path. **Unused by HDFC** (no
    `column_split_x`); callers may pass an **empty** `Vec<Word>`. Kept for signature parity with
    `read_icici_bank_statement` and the app-side extractor.
- **Output**: `ParsedStatement` (reused): `rows`, `period_start/period_end`, `card_last4`,
  `printed_opening_balance/printed_closing_balance`, `errored_lines`.
- **Guarantees**: pure, deterministic, allocation-only (no I/O, no network, never opens a PDF). Money as
  `Decimal`. Direction delta-derived with an auditable `direction_source`.

### `hdfc_bank_claims`

```rust
#[uniffi::export]
pub fn hdfc_bank_claims(full_text: String) -> bool {
    claims_ledger(&HdfcBankReader, &full_text, "HDFC")
}
```

- **Purpose**: fast issuer/layout gate — does this text look like an **HDFC bank** (savings/current) statement?
- **Semantics**: `true` iff **all** `claim_all` tokens (`["HDFC"]`) **and at least one** `claim_any` token
  (`["WithdrawalAmt", "Savings Account Details", "Statementof account"]`) are present. Must **reject** HDFC
  **credit-card** statements (handled by the separate `statement/hdfc.rs` reader). See research **D9**.
- **Output**: `bool`.

## Reused (already exported in slice 007 — do NOT duplicate)

### `check_balance_chain`

```rust
#[uniffi::export]
pub fn check_balance_chain(rows: Vec<LedgerRow>) -> ChainReport; // reused unchanged
```

- Applied to the `rows` of a parsed HDFC statement; both HDFC fixtures yield `ChainStatus::Reconciled`
  (₹1.00 tolerance, 0 suspects, no row-1 fallback).

## `src/lib.rs` re-exports (additive)

```rust
pub use ffi::{read_hdfc_bank_statement, hdfc_bank_claims}; // check_balance_chain already re-exported
```

## Type inventory (all REUSED — zero new FFI types)

| Type | Origin | Role here |
|---|---|---|
| `ParsedStatement` | slice 007 | reader output |
| `LedgerRow`, `LedgerMetadata`, `DirectionSource` | slice 007 | per-row data + audit trail |
| `Direction` | existing (`model.rs`) | `Debit`/`Credit` |
| `Word` | slice 007 | layout token (passed empty for HDFC) |
| `ChainReport`, `ChainStatus` | slice 007 | balance-chain result |

## Non-goals / invariants

- **No new UniFFI record or enum.** No change to `uniffi.toml` or binding generation shape.
- **No new dependency** (runtime or dev) — Constitution III / FR-034.
- **No I/O / no network / no PDF** in any exported function — Constitution I / FR-025/028.
- **Ordering**: `make core-xcframework` runs before `tuist generate` (Makefile `ios-gen: core-xcframework`);
  iPhone 16 simulator; macos-15 CI.

## Verification (parity harness + Swift)

- `hdfc_bank_claims(compact.full_text) == true`, `hdfc_bank_claims(detailed.full_text) == true`,
  `hdfc_bank_claims(<hdfc-card-style text>) == false`.
- `read_hdfc_bank_statement(fixture.lines, fixture.full_text, vec![])` reproduces each fixture's `expected`
  exactly (rows + ledger fields + period + last-4 + printed balances + `errored_lines == []`).
- `check_balance_chain(rows) == Reconciled` for both fixtures.
- Swift Testing (`import KanameCore`): parse each fixture over the bridge and assert the chain is reconciled.
