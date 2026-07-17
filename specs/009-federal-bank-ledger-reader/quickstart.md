# Phase 1 — Quickstart: Federal Bank Ledger Reader

**Feature**: 009-federal-bank-ledger-reader · **Date**: 2026-07-17

How to implement, run, and verify this slice. It is a **test-first** port: write the two fixtures + harness rows first (they fail), then add `federal_bank.rs` + the FFI wiring until green.

---

## Prerequisites
- Toolchain per `rust-toolchain.toml` (stable + `rustfmt`, `clippy`, iOS targets). `make bootstrap` if needed.
- Work on branch `009-federal-bank-ledger-reader`.

## Implementation order (test-first)

1. **Add the two golden fixtures** (byte-for-byte from the captured ground truth; see data-model.md §3 for the value/serialization translation):
   - `fixtures/federal/bank_account/classic.json` (3 rows)
   - `fixtures/federal/bank_account/fi.json` (2 rows)
   - Remember the translations: `direction` → `Debit`/`Credit`; `direction_source` → `OpeningBalance`/`BalanceDelta`; Fi amounts stored as `"5000"`/`"50000"`; `\EXAM` escaped as `\\EXAM` in JSON. Do **not** touch `fixtures/federal/credit_card/basic.json`.

2. **Extend `tests/parity.rs`** (contracts/ffi.md §C4): import the two new fns, add `parse_federal_bank` wrapper, two `Case` rows, and the `federal_bank_statements_balance_chain_reconciles` test. Run — expect **failures** (no reader yet).

3. **Add the reader** `core/crates/kaname-core/src/statement/federal_bank.rs` mirroring `hdfc_bank.rs`: the five regex statics + `FederalBankReader` impl (data-model.md §2). Register it: add `pub mod federal_bank;` to `statement/mod.rs`.

4. **Wire the FFI** in `ffi.rs`: `read_federal_bank_statement` + `federal_bank_claims` (contracts/ffi.md §C1); add both names to the `pub use ffi::{…}` re-export in `lib.rs`.

5. **(Optional) Reader unit tests** inside `federal_bank.rs` (mirror `hdfc_bank.rs::tests`) and a claims split test.

6. **Swift Testing** (`ios/`): add the "core ↔ Swift Federal bank parse + chain" `@Test` (contracts/ffi.md §C5).

## Verify — core

```bash
# Fast inner loop: just this crate's parity + unit tests
cd core && cargo test --all --all-features    # or: make core-test

# Expected new green tests:
#   golden_fixtures_match_expected_output      (now covers Federal classic + Fi)
#   parse_is_deterministic                     (idem)
#   federal_bank_statements_balance_chain_reconciles
#   (optional) federal_bank_claims_accepts_own_document_and_rejects_others

# Lint + format (blocking gate)
make core-lint            # cargo fmt --check && cargo clippy -D warnings

# Privacy egress gate (Constitution Principle I) — must stay green, no networking crate
make core-privacy-audit
```

## Verify — iOS (gate ordering matters)

```bash
# The xcframework MUST be rebuilt BEFORE tuist generate so the new FFI symbols
# (read_federal_bank_statement / federal_bank_claims) are visible to the app target.
# `make ios-gen` encodes this dependency (ios-gen: core-xcframework); `make ios-test`
# chains gen → build → test on the iPhone 16 simulator.
make core-xcframework      # build KanameCoreFFI.xcframework + regenerate KanameCore.swift
make ios-test              # tuist generate --no-open, then xcodebuild test (iPhone 16 sim)

# Swift lint/format
make lint
```

> **Why the order** (from the constitution's iOS Local Verification Gate): `tuist generate` resolves the xcframework path at generation time, so a stale framework would hide the new Federal symbols from Swift. Always `core-xcframework` → `ios-gen`/`ios-test`. CI runs the same on `macos-15`.

## Agent context + typo check

```bash
.specify/scripts/bash/update-agent-context.sh copilot
# Then confirm the appended 009 line did NOT reintroduce the "iOS 18 targe" typo:
grep -n "iOS 18 targe\b" .github/copilot-instructions.md   # expect: no output
# If present, fix "iOS 18 targe" -> "iOS 18 target" and leave it UNSTAGED (author commits).
```

## Done-when (acceptance)
- `make core-test`, `make core-lint`, `make core-privacy-audit` green.
- Both Federal fixtures match byte-for-byte; balance chain **RECONCILED** (classic 3 rows, Fi 2 rows; 0 suspects; no row-1 fallback).
- `federal_bank_claims` claims both Federal bank fixtures, rejects the Scapia CC fixture + foreign issuers; the landed `federal_claims` still claims the Scapia CC fixture.
- `make ios-test` + `make lint` green; the Swift bridge test passes.
- No new dependency in `Cargo.toml`/`Cargo.lock`; no base/shared-helper file changed; money is `Decimal` everywhere.

## Rollback
Pure additive: delete `statement/federal_bank.rs`, the two fixtures, and revert the additive lines in `mod.rs`/`ffi.rs`/`lib.rs`/`tests/parity.rs`. Nothing else depends on this slice.
