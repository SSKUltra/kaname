# Quickstart — Bank-Account Balance-Ledger Reader (build & verify)

**Feature**: `007-bank-account-ledger-reader` | **Date**: 2026-07-16
Walkthrough to build, test, and verify the slice locally, honoring the iOS Local Verification Gate ordering
(**xcframework before `tuist generate`**). Commands run from the repo root unless noted. This slice
**reuses** the credit-card gates and adds **no new dependency**; it introduces the balance-ledger base, the
balance-chain check, and the ICICI bank reference reader.

---

## Prerequisites
- Toolchain per `rust-toolchain.toml` (stable + iOS targets) and `make bootstrap` (tuist, swiftlint,
  swift-format). iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`.
- Local Xcode: create an **"iPhone 16"** simulator (the `-destination …,name=iPhone 16,OS=latest` used by
  `make ios-test` must exist).
- `cargo` on PATH (`source "$HOME/.cargo/env"` if needed).
- No special encoding needs: the fixture is plain ASCII/UTF-8 (no middot/rupee glyphs this slice).

## 0. Ground truth (already captured & verified — no live run needed)
The `expected` block is the locked ground truth from the web engine's balance-ledger stack
(`_ledger_reader.py` `BalanceLedgerStatementReader`, `balance_chain.py` `check`, `icici_bank.py`), persisted
as `icici-bank-ground-truth.json`. Exact fixture bytes are in
[`contracts/golden-fixture.md`](./contracts/golden-fixture.md). (Optional re-confirmation from the web repo,
`finance-tracker-phase/backend`, with its venv:)
```bash
PYTHONPATH="$PWD" .venv/bin/python - <<'PY'
from app.services.ingestion.statement_readers import icici_bank
from app.services.ingestion import balance_chain
full = ("ICICI Bank Limited\nStatement of Transactions in Savings Account\n"
        "Account Number 000401000123456\nStatement Period June 16, 2025 to July 15, 2025\n"
        "Opening Balance 1,00,000.00\n"
        "S No. Value Date Transaction Date Cheque No. Transaction Remarks Withdrawal Deposit Balance\n"
        "UPI/512345/ALICE STORE/Payment\n1 16.06.2025 16.06.2025 5,000.00 95,000.00\n"
        "NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY\n2 18.06.2025 18.06.2025 50,000.00 1,45,000.00\n"
        "3 20.06.2025 20.06.2025 ATM CASH WITHDRAWAL 2,000.00 1,43,000.00\nClosing Balance 1,43,000.00")
lines = [l for l in full.split("\n") if l.strip()]
st = icici_bank.reader.read_lines(lines, full, first_row_words=None)
print(st.printed_opening_balance, st.printed_closing_balance, st.period_start, st.period_end, st.card_last4)
for ln in st.lines:
    print(ln.value_date, ln.amount, ln.direction, repr(ln.description_raw), ln.metadata)
print(balance_chain.check(st).status)   # RECONCILED
PY
```
Expected: `printed_opening 100000.00`, `printed_closing 143000.00`, period `2025-06-16 → 2025-07-15`,
`card_last4 3456`; three rows (Debit 5000.00 / Credit 50000.00 / Debit 2000.00) with balances
`95000/145000/143000`, deltas `-5000/50000/-2000`, sources `opening_balance/balance_delta/balance_delta`,
serials `1/2/3`, all `amount_matches_delta=True`; chain `RECONCILED`.

## 1. Core — format, lint, test (test-first)
Write the failing tests **first** (Principle V), then implement until green.
```bash
# RED: add fixtures/icici/bank_account/basic.json (contracts/golden-fixture.md), the parity Case row,
#      the balance-chain RECONCILED test, and the icici_bank_claims accept/reject test — all failing.
make core-test        # expect failures until the reader/base/chain land

# GREEN: implement additively, in this order —
#   base.rs      : + ParsedTransaction.ledger; + ParsedStatement.printed_opening/closing_balance (::new None);
#                  + LedgerMetadata, DirectionSource, Word (uniffi)
#   line_reader.rs: the one ParsedTransaction constructor gains `ledger: None` (CC path unchanged)
#   ledger_reader.rs: LedgerReaderConfig trait + read_ledger_lines(cfg, lines, full_text, first_row_words)
#                     + claims_ledger + find_anchors/anchor_amount/stitch_narration/row1_direction/…
#   balance_chain.rs: check(&ParsedStatement) -> ChainResult (+ ChainStatus/Suspect/ChainResult); ₹1.00 here only
#   icici_bank.rs : IciciBankReader impl LedgerReaderConfig (anchor/opening/closing/column_split_x/
#                   claim_all/claim_any/enrich/account_tail)
#   ffi.rs + lib.rs + statement/mod.rs: export read_icici_bank_statement / icici_bank_claims /
#                   check_balance_chain; re-export new types; `pub mod ledger_reader/balance_chain/icici_bank;`

make core-lint        # cargo fmt --check + clippy -D warnings
make core-test        # unit + parity (ICICI-bank vector + chain RECONCILED + claim split + determinism) — all green
```
Watch-points (from research): **exact** `amount == |delta|` in the reader vs the **₹1.00** tolerance in
`balance_chain` (D6); the two-column `anchor_amount` **loose** integer parse is unit-tested with a synthetic
two-column line (ICICI's fixture only exercises the single-amount path, D4); the account last-4 uses the
**account-number** tail, **not** `find_last4` (D10). Confirm the five **credit-card** parity cases still pass
**unchanged** (no fixture migration — D9).

## 2. Privacy-egress gate (Constitution I) — inherited, no new dep
```bash
make core-privacy-audit    # cargo tree -e normal has NO networking crate; unchanged (no dep added)
```

## 3. Bridge — regenerate the xcframework BEFORE tuist (gate ordering)
The new records/enums (`Word`, `LedgerMetadata`, `DirectionSource`, `ChainResult`, `ChainStatus`, `Suspect`)
and the three new exports must be regenerated into Swift.
```bash
make core-xcframework      # builds libs (device + 2 sim arches), regenerates ios/Generated + KanameCoreFFI.xcframework (git-ignored)
```
Then the Swift bridge test proves the reader + chain over UniFFI:
```bash
# ios/Tests/IciciBankParseTests.swift (import KanameCore, Swift Testing):
#   readIciciBankStatement(lines, fullText, firstRowWords: []) → 3 rows + ledger + printed_* + period + cardLast4
#   checkBalanceChain(statement) → .reconciled, suspectCount 0, row1DirectionFallback false
#   iciciBankClaims(savingsText) == true; iciciBankClaims(iciciCardText) == false; iciciClaims(iciciCardText) == true
#   amounts assert as Decimal (never Double)
```

## 4. iOS gate — generate + simulator build/test
```bash
make ios-gen               # depends on core-xcframework; runs `tuist generate --no-open`
make ios-test              # xcodebuild test on 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

## 5. Full local gate (what CI enforces)
```bash
make lint                  # core-lint + swiftlint --strict + swift-format lint --strict
make core-test
make ios-test              # (implies core-xcframework → tuist generate → simulator build+test)
```
CI (`.github/workflows/ci.yml`) runs the same on push/PR: the **core** job (ubuntu) does fmt/clippy/test +
the privacy-egress audit; the **iOS** job (macos-15) builds the xcframework, generates the Tuist project,
and runs the simulator build+tests on **iPhone 16**. All green ⇒ ready.

---

## Definition of done (this slice)
- [ ] `fixtures/icici/bank_account/basic.json` reproduces byte-for-byte (rows + ledger metadata + printed
      opening/closing + period + account last-4) via the parity harness (SC-001/008/013).
- [ ] `check_balance_chain` reports **RECONCILED** (0 suspects, no row-1 fallback) for the fixture
      (SC-002).
- [ ] Direction is **delta-derived** and `direction_source` is recorded per row (SC-003/006); the amount
      never sets direction.
- [ ] Suspect vs errored distinction holds; suspects are still returned (SC-004/005).
- [ ] `icici_bank_claims` accepts the savings statement and **rejects** the ICICI credit-card statement;
      `icici_claims` still accepts the card statement (SC-007).
- [ ] Money is exact `Decimal` everywhere; only `Word.x0/x1` are `f64` layout points (SC-009).
- [ ] Privacy-egress passes; **no new runtime/dev dependency** added (SC-010/014).
- [ ] Reachable from Swift over UniFFI (`read_icici_bank_statement` with geometry, `icici_bank_claims`,
      `check_balance_chain`) (SC-011).
- [ ] The five **credit-card** parity cases pass **unchanged** (no fixture migration — D9).
- [ ] `make lint && make core-test && make ios-test` green; CI green.
