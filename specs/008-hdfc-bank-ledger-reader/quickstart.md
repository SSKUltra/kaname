# Quickstart: HDFC Bank (Savings/Current) Ledger Reader

**Feature**: `008-hdfc-bank-ledger-reader` | **Phase 1** | **Plan**: [`plan.md`](./plan.md)

How to build, verify, and exercise the HDFC bank-account reader. **This slice adds no dependency and no network
path**; everything runs offline. Commands assume repo root `/Users/ssk/Projects/kaname`.

> ⚠️ **Blocked pending OD-1.** The **compact** fixture is green only with the 1-line `common.rs::DATE_FORMATS`
> reorder (`%d/%m/%y` before `%d/%m/%Y`) — see plan → Open Decisions / research **D8**. Until you approve it,
> `cargo test` will fail on the compact dates (`0026-…` vs `2026-…`).

## Prerequisites

- Rust stable via `rust-toolchain.toml` (`rustup show` to confirm). If `cargo` isn't on `PATH`:
  `export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$HOME/.cargo/bin:$PATH"; export RUSTUP_TOOLCHAIN=stable`.
- Xcode 16 + `tuist` for the iOS gate; **macos-15** in CI; **iPhone 16** simulator (`OS=latest`).
- No new crates — `cargo build` uses the existing lockfile.

## 1. Core: format, lint, test

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test -p kaname-core
```

Expected after implementation:
- `tests/parity.rs` — the two HDFC `Case` rows (`hdfc/bank_account/compact.json`, `…/detailed.json`) reproduce
  their `expected` exactly, alongside the existing ICICI/other cases.
- Two balance-chain tests → `Reconciled`; the claims test accepts both HDFC bank layouts and rejects an HDFC
  card statement.
- Unit tests in `statement/hdfc_bank.rs` (anchors, opening/period/account regexes) + a `common.rs` unit test
  `parse_date("01/04/26") == 2026-04-01` (OD-1 guard) + `account_tail_last4` (HDFC `3425`, ICICI `3456`).
- The **ICICI** fixture stays **GREEN** after the `account_tail_last4` refactor.

## 2. Privacy egress gate (inherited, unchanged)

```bash
make core-privacy-audit    # scans the dependency/build graph for network/telemetry surfaces
cargo tree -e normal       # must be byte-identical to pre-slice (no new dependency)
```

The HDFC reader and helper are pure functions over in-memory strings — no sockets, HTTP, async runtime, or PDF
I/O. The core never opens a PDF.

## 3. iOS gate (ordering matters)

```bash
make core-xcframework      # rebuild KanameCoreFFI.xcframework + regenerate Swift bindings  ← MUST run first
make ios-gen               # tuist generate (depends on core-xcframework)
# then build + test on the iPhone 16 simulator:
xcodebuild test -scheme Kaname -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

- The two new exports (`read_hdfc_bank_statement`, `hdfc_bank_claims`) reuse existing UniFFI types — **no new
  binding shape**, `uniffi.toml` untouched.
- `ios/Tests/HdfcBankParseTests.swift` (`import KanameCore`): parse each HDFC fixture over the bridge and assert
  `check_balance_chain(rows)` is reconciled.

## 4. Manual smoke (Rust)

```rust
use kaname_core::{read_hdfc_bank_statement, hdfc_bank_claims, check_balance_chain};

let full_text = std::fs::read_to_string("fixtures/hdfc/bank_account/detailed.json").unwrap(); // or use the raw statement text
// In practice pass the natively-extracted `lines` + `full_text`; HDFC needs no geometry:
let parsed = read_hdfc_bank_statement(lines, statement_text, Vec::new());
assert!(hdfc_bank_claims(statement_text.clone()));
assert_eq!(parsed.rows.len(), 2);
assert_eq!(parsed.card_last4.as_deref(), Some("3425"));
assert_eq!(check_balance_chain(parsed.rows).status, ChainStatus::Reconciled);
```

## 5. What to look for (parity intent)

- **Direction is delta-derived** — row 0 from the printed opening balance (`OpeningBalance`), later rows from
  the running balance delta (`BalanceDelta`); never from the amount's column or sign.
- **Printed amount is an independent check** — `amount_matches_delta == true` on every fixture row; a mismatch
  would flag `is_suspect` (none here).
- **Narration is intentionally "dirty"** — header/summary lines are stitched into `description_raw` to match the
  web engine **byte-for-byte** (research D4). Do **not** add cleanup; it would break parity.
- **Two layouts, one reader** — the compact (`DD/MM/YY`) and detailed (`DD/MM/YYYY`) anchors are tried in order
  and are mutually exclusive.
- **Money is `Decimal`** — fixtures store amounts as strings; nothing routes an amount through `f64`.

## 6. Regenerate the ground-truth (optional, web engine)

The fixtures are ported from `finance-tracker-phase/backend/app/services/ingestion/statement_readers/hdfc_bank.py`
(`BalanceLedgerStatementReader`). To re-derive, run that reader + `balance_chain.check` over the two synthetic
statements and confirm `RECONCILED`, then normalize amounts to comma-stripped 2-dp strings (see
`contracts/golden-fixture.md`). Keep all data **synthetic/redacted**.
