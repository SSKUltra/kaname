# Phase 1 — Quickstart: AU Bank Ledger Reader

**Feature**: 010-au-bank-ledger-reader · **Date**: 2026-07-17

How to implement, run, and verify this slice. It is a **test-first** port: write the fixture + harness row first (it fails), then add `au_bank.rs` + the FFI wiring until green.

---

## Prerequisites
- Toolchain per `rust-toolchain.toml` (stable + `rustfmt`, `clippy`, iOS targets). `make bootstrap` if needed.
- Work on branch `010-au-bank-ledger-reader`.

## Implementation order (test-first)

1. **Add the golden fixture** (byte-for-byte from the captured ground truth; see data-model.md §3 for the value/serialization translation):
   - `fixtures/au/bank_account/savings.json` (2 rows)
   - Remember the translations: `direction` → `Debit`/`Credit`; `direction_source` → `OpeningBalance`/`BalanceDelta`; every `serial` is `""`; amounts stored `"5000.00"`/`"10000.00"`; keep the literal `₹` (U+20B9) in the `Opening Balance(₹)` / `Closing Balance(₹)` lines; `printed_closing_balance` is `"16570.79"` (the last row balance), **not** the header `"223.34"`.

2. **Extend `tests/parity.rs`** (contracts/ffi.md §C4): import the two new fns, add the `parse_au_bank` wrapper, one `Case` row, and the `au_bank_statement_balance_chain_reconciles` test. Run — expect **failures** (no reader yet).

3. **Add the reader** `core/crates/kaname-core/src/statement/au_bank.rs` mirroring `icici_bank.rs` (which also uses `claim_any` + `closing_balance_re`): the five regex statics + the `AuBankReader` impl (data-model.md §2). Register it: add `pub mod au_bank;` to `statement/mod.rs`.

4. **Wire the FFI** in `ffi.rs`: `read_au_bank_statement` + `au_bank_claims` (contracts/ffi.md §C1); add both names to the `pub use ffi::{…}` re-export in `lib.rs`.

5. **(Optional) Reader unit tests** inside `au_bank.rs` (mirror `icici_bank.rs::tests`): a delta-direction test (Debit despite `UPI/DR`, Credit despite `UPI/CR`), the dash-empty amount resolution, and an `au_bank_claims` accept/reject split.

6. **Swift Testing** (`ios/`): add the "core ↔ Swift AU bank parse + chain" `@Test` (contracts/ffi.md §C5).

## Verify — core

```bash
# Fast inner loop: just this crate's parity + unit tests
cd core && cargo test --all --all-features    # or: make core-test

# Expected new green tests:
#   golden_fixtures_match_expected_output      (now covers AU bank savings)
#   parse_is_deterministic                     (idem)
#   au_bank_statement_balance_chain_reconciles
#   (optional) au_bank_claims_accepts_own_document_and_rejects_others

# Lint + format (blocking gate)
make core-lint            # cargo fmt --check && cargo clippy -D warnings

# Privacy egress gate (Constitution Principle I) — must stay green, no networking crate
make core-privacy-audit
```

## Verify — iOS (gate ordering matters)

```bash
# The xcframework MUST be rebuilt BEFORE tuist generate so the new FFI symbols
# (read_au_bank_statement / au_bank_claims) are visible to the app target.
# `make ios-gen` encodes this dependency (ios-gen: core-xcframework); `make ios-test`
# chains gen -> build -> test on the iPhone 16 simulator.
make core-xcframework      # build KanameCoreFFI.xcframework + regenerate KanameCore.swift
make ios-test              # tuist generate --no-open, then xcodebuild test (iPhone 16 sim)

# Swift lint/format
make lint
```

> **Why the order** (from the constitution's iOS Local Verification Gate): `tuist generate` resolves the xcframework path at generation time, so a stale framework would hide the new AU symbols from Swift. Always `core-xcframework` → `ios-gen`/`ios-test`. CI runs the same on `macos-15`.

## Agent context + typo check

```bash
.specify/scripts/bash/update-agent-context.sh copilot
# Then confirm the appended 010 line did NOT reintroduce the "iOS 18 targe" typo:
grep -nE "iOS 18 targe([^t]|$)" .github/copilot-instructions.md   # expect: no output
# If present, fix "iOS 18 targe" -> "iOS 18 target" and leave it UNSTAGED (author commits).
```

## Done-when (acceptance)
- `make core-test`, `make core-lint`, `make core-privacy-audit` green.
- The AU fixture matches byte-for-byte; balance chain **RECONCILED** (2 rows, 0 suspects, no row-1 fallback, derived opening `11570.79`, derived closing `16570.79`).
- `au_bank_claims` claims the AU savings fixture, rejects a credit-card statement lacking a Savings/Current marker and foreign issuers.
- `printed_closing_balance == 16570.79` (last row), not the header `223.34`; `direction` is Debit then Credit (delta-derived, not the `UPI/DR`/`UPI/CR` narration text).
- `make ios-test` + `make lint` green; the Swift bridge test passes.
- No new dependency in `Cargo.toml`/`Cargo.lock`; no base/shared-helper file changed; money is `Decimal` everywhere.

## Rollback
Pure additive: delete `statement/au_bank.rs`, the one fixture (and the now-empty `fixtures/au/` subtree), and revert the additive lines in `mod.rs`/`ffi.rs`/`lib.rs`/`tests/parity.rs`. Nothing else depends on this slice.
