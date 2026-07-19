# Quickstart — Credit-Card Statement Reconciliation (build & verify)

**Feature**: `012-cc-reconciliation` | **Date**: 2026-07-19
Walkthrough to build, test, and verify the slice locally, honoring the iOS Local Verification Gate
ordering (xcframework **before** `tuist generate`). Commands run from the repo root unless noted.
Reconciliation is the **credit-card counterpart of `balance_chain`**: it **reuses** every existing gate,
the `ParsedStatement`/`Direction` types, the parity harness, and the UniFFI bridge, and adds **no new
runtime or dev dependency** and **no new shared helper**.

---

## Prerequisites
- Toolchain per `rust-toolchain.toml` (stable + iOS targets) and `make bootstrap` (tuist, swiftlint,
  swift-format). iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`.
- Local Xcode: an **"iPhone 16"** simulator (the `-destination …,name=iPhone 16,OS=latest` used by
  `make ios-test` must exist).
- `cargo` on PATH (`source "$HOME/.cargo/env"` if needed).

## 0. Ground truth (already captured & verified — no live run needed)
The reconcile behaviour is the locked ground truth from the web engine's `reconciliation.py`, and the
three new regexes + the reconcile arithmetic were **re-confirmed against the real `regex` + `rust_decimal`
crates** (research "Verification harness"):

| Vector | read_debits | read_credits | printed_debits | printed_credits | `reconcile_statement` |
|---|--:|--:|--:|--:|---|
| Yes (extended) | `100.00` | `9000.00` | `100.00` | `9000.00` | `Some(Reconciled)` |
| IOB (existing) | `3500.00` | `1000.00` | `3500.00` | `1000.00` | `Some(Reconciled)` |
| ICICI (no totals) | (row sums) | (row sums) | — | — | `None` (neutral, reason `"no printed totals extracted"`) |
| Mismatch (printed debit `9999`) | `100.00` | `9000.00` | `9999` | … | `Some(NeedsReview)` |

The exact fixture bytes are in `contracts/golden-fixture.md`. (Optional re-confirmation from the web repo,
`finance-tracker-phase/backend`, with its venv:)
```bash
PYTHONPATH="$PWD" .venv/bin/python - <<'PY'
from app.services.ingestion.statement_readers import yes_kiwi, iob
from app.services.ingestion import reconciliation
for reader, lines, text in [
    (yes_kiwi, ["29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr",
                "19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr"],
     "YES BANK KLICK\nStatement Period: 17/04/2026 To 16/05/2026\n"
     "Current Purchases / Cash Advance & Other Charges : Rs. 100.00 Dr\n"
     "Payment & Credits Received : Rs. 9,000.00 Cr\n"
     "29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr\n"
     "19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr"),
]:
    st = reader.reader.read_lines(lines, text)
    print(st.printed_total_debits, st.printed_total_credits)   # 100.00 9000.00
    print(reconciliation.reconcile(st))                        # status 'reconciled', detail read/printed
PY
```
Expected: Yes → `printed_total_debits 100.00`, `printed_total_credits 9000.00`, reconcile
`reconciled`. (The web `detail` uses camel-ish dict keys; the Rust port carries the same figures as
typed `ReconcileResult` fields.)

## 1. Core — format, lint, test (test-first)
```bash
make core-test      # cargo test --all --all-features → reconcile.rs unit tests + tests/parity.rs (Yes/IOB/ICICI reconcile) + determinism
make core-lint      # cargo fmt --check + clippy -D warnings
```
Expected:
- `reconcile.rs` unit tests pass — totals-match→Reconciled; debit-mismatch→NeedsReview (+ read/printed
  detail); 0.50-within-tolerance→Reconciled; exactly-1.00 boundary→Reconciled; only-one-total-present;
  both-present-one-mismatch→NeedsReview; balance-change fallback→Reconciled;
  primary-takes-precedence-over-fallback; only-one-balance→neutral; no-totals→neutral(`None`)+reason;
  empty-rows sums `0.00`.
- Reader unit tests pass — Yes surfaces `printed_total_debits 100.00`/`printed_total_credits 9000.00`;
  IOB surfaces `printed_total_credits 1000.00`/`printed_total_debits 3500.00` from `ACCOUNT SUMMARY`.
- Parity harness reproduces the web-engine output **exactly**: `yes_statement_reconciles` +
  `iob_statement_reconciles` → `Some(Reconciled)` with matching read/printed totals;
  `statement_without_printed_totals_is_neutral` → `status None`, `reason "no printed totals extracted"`.
  Every other fixture asserts `printed_total_* == None` (unchanged).

## 2. Privacy-egress gate (inherited — must stay green)
```bash
make core-privacy-audit   # cargo tree denylist over kaname-core's shipped (default, -e normal) deps
```
Expected: `privacy-egress: OK (no networking crate in kaname-core deps)`. This slice adds **no
dependency**, so the shipped graph is byte-identical to before — the gate must remain green with zero
changes, and it covers the new `reconcile` path (pure, on-device, zero network — FR-020/022).

## 3. Build the engine xcframework (MUST precede tuist generate)
```bash
make core-xcframework     # compiles device+sim slices, runs uniffi-bindgen, lipo, create-xcframework
```
Produces `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift` (git-ignored) —
now also exporting `reconcileStatement`, the `ReconcileStatus` enum, the `ReconcileResult` record, and
the two new `printedTotalDebits`/`printedTotalCredits` fields on `ParsedStatement`.

## 4. iOS — generate, lint, test
```bash
make lint                 # swiftlint --strict + swift-format lint --strict
make ios-test             # ios-gen (depends on core-xcframework) → xcodebuild … -destination 'name=iPhone 16' test
```
Expected: the "core ↔ Swift reconcile" suite (`ios/Tests/ReconcileTests.swift`) passes — read a Yes
statement via `readYesStatement` then `reconcileStatement(statement:)` → `.status == .reconciled` with
`printedDebits`/`printedCredits` surfaced; an IOB statement → `.reconciled`; an ICICI statement (no
totals) → `.status == nil` (neutral). `status` surfaces as `ReconcileStatus?`.

> **swift-format `[Spacing]`**: no trailing inline `//` comment after code — put any comment on its own
> line **above** the statement, or `make lint` fails.

## 5. Full local gate (what CI runs)
```bash
make core-lint && make core-test && make core-privacy-audit && make lint && make ios-test
```
CI mirrors this unchanged: the **core** job (ubuntu) runs the privacy audit; the **iOS** job stays on
`macos-15` and builds the xcframework before `tuist generate`.

---

## Try the reconcile (ad-hoc, optional)
The check is pure — a tiny Rust snippet exercises the three tiers without the app:
```rust
// Primary path — printed totals present and matching → Reconciled.
let lines = vec![
    "29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr".to_string(),
    "19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr".to_string(),
];
let full = "YES BANK KLICK\nStatement Period: 17/04/2026 To 16/05/2026\n\
    Current Purchases / Cash Advance & Other Charges : Rs. 100.00 Dr\n\
    Payment & Credits Received : Rs. 9,000.00 Cr\n\
    29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr\n\
    19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr".to_string();
let st = kaname_core::read_yes_statement(lines, full);
assert_eq!(st.printed_total_debits, Some(rust_decimal::Decimal::new(10000, 2)));  // 100.00
let r = kaname_core::reconcile_statement(st);
assert_eq!(r.status, Some(kaname_core::ReconcileStatus::Reconciled));
assert_eq!(r.read_credits, rust_decimal::Decimal::new(900000, 2));               // 9000.00

// Neutral path — a reader with no printed totals (ICICI) → status None.
let st2 = kaname_core::read_icici_statement(vec![
    "29/04/2026 4262 BBPS Payment received 0 13,628.36 CR".to_string(),
], "ICICI Bank Statement\n4315XXXXXXXX1002".to_string());
let r2 = kaname_core::reconcile_statement(st2);
assert_eq!(r2.status, None);
assert_eq!(r2.reason.as_deref(), Some("no printed totals extracted"));
```

## Add another reconciliation vector (future readers)
1. Give a reader an `enrich` that surfaces `printed_total_debits`/`printed_total_credits` (or the
   opening/closing balances for the fallback path) from its `full_text`.
2. Pin the totals in the fixture `expected` (as **strings**) per `contracts/golden-fixture.md`, and add a
   `*_statement_reconciles` (or neutral) parity test. Run `make core-test`.
3. `reconcile.rs` needs **no change** — it is reader-agnostic (the point of the check).

## Troubleshooting
- **`cargo` not found**: `source "$HOME/.cargo/env"`.
- **`xcodebuild` can't find a destination**: create the "iPhone 16" simulator in Xcode.
- **Swift can't see `reconcileStatement`/`ReconcileStatus`/`ReconcileResult`**: rebuild
  `make core-xcframework` before `tuist generate` (generated Swift is an artifact).
- **`make lint` fails on `ReconcileTests.swift`**: a trailing inline `//` comment after code violates
  swift-format `[Spacing]` — move it to its own line above the statement.
- **A neutral statement came back `Some(NeedsReview)`**: the neutral outcome MUST be `status None` (not
  `NeedsReview`) — a statement lacking printed anchors is not a discrepancy (FR-004). Check the tier
  order: neutral is the `else` after both the printed-totals and the both-balances branches.
- **Primary path didn't win when a total is present**: the fallback MUST be skipped whenever
  `printed_total_debits` **or** `printed_total_credits` is `Some` — verify the leading
  `is_some() || is_some()` guard (FR-005).
- **Yes totals came back `None`**: check the two summary lines are present in `full_text` **after** the
  `Statement Period:` line and spelled exactly (`Current Purchases … Rs. 100.00 Dr`,
  `Payment & Credits Received : Rs. 9,000.00 Cr`); `DEBITS_RE`/`CREDITS_RE` are same-line
  (`[^\n]*?`) and case-insensitive.
- **IOB totals swapped (debits↔credits)**: in the `ACCOUNT SUMMARY` row `credits` is the **2nd** figure
  and `debits` the **3rd** (`345.50  1,000.00  3,500.00  0  2,845.50`) — assign
  `printed_total_credits = summary["credits"]`, `printed_total_debits = summary["debits"]` (FR-013).
- **`exactly 1.00` flagged as NeedsReview**: the tolerance is **inclusive** (`<=`), same as
  `balance_chain`; a `|Δ|` of exactly `1.00` is within tolerance (SC-004).
- **A `printed_total_spend` field appears**: it is intentionally **not** ported (reconciliation never
  reads it) — remove it; `base.rs` carries only `printed_total_debits`/`printed_total_credits` (FR-011).
- **Privacy audit false positive**: this slice adds no dep; if a networking crate appears, that's an
  unrelated regression — the gate is working.
