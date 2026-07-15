# Quickstart — HDFC Credit-Card Parser (build & verify)

**Feature**: `003-hdfc-cc-parser` | **Date**: 2026-07-15
Walkthrough to build, test, and verify the slice locally, honoring the iOS Local Verification
Gate ordering (xcframework **before** `tuist generate`). Commands run from the repo root unless
noted. HDFC **reuses** the ICICI gates and adds **no new dependency**.

---

## Prerequisites
- Toolchain per `rust-toolchain.toml` (stable + iOS targets) and `make bootstrap` (tuist,
  swiftlint, swift-format). iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`.
- Local Xcode: create an **"iPhone 16"** simulator (the `-destination name=iPhone 16` used by
  `make ios-test` must exist).
- `cargo` on PATH (`source "$HOME/.cargo/env"` if needed).

## 0. Capture the monthly fixture's ground truth (test-first, do this FIRST)
The monthly vector's `expected` MUST come from a **live web-engine run**, never hand-derived
(FR-026). From the web repo (`finance-tracker-phase/backend`), with its venv:
```bash
PYTHONPATH="$PWD" .venv/bin/python - <<'PY'
from app.services.ingestion.statement_readers import hdfc
lines = ["15/05/2026| 13:30 EXAMPLE MERCHANT BANGALORE C 1,639.00",
         "20/05/2026| 09:05 CC PAYMENT RECEIVED + C 6,738.00"]
text = ("HDFC Bank Credit Card\nBilling Period 15 May, 2026 - 14 Jun, 2026\n"
        "Card Number XXXX1234XXXXXX5678\n" + "\n".join(lines))
st = hdfc.reader.read_lines(lines, text)
print(st.period_start, st.period_end, st.card_last4)
for ln in st.lines: print(ln.value_date, ln.amount, ln.direction, repr(ln.description_raw))
PY
```
Expected (the ground truth to encode in `fixtures/hdfc/credit_card/monthly.json`):
`period_start 2026-05-15`, `period_end 2026-06-14`, `card_last4 5678`; row0 `Debit 1639.00
"EXAMPLE MERCHANT BANGALORE"`, row1 `Credit 6738.00 "CC PAYMENT RECEIVED"`. The **year-end**
vector is ported from the web characterization test (`_HDFC_LINES`/`_HDFC_TEXT`).

## 1. Core — format, lint, test (test-first)
```bash
make core-test      # cargo test --all --all-features → unit tests + tests/parity.rs (BOTH HDFC vectors) + determinism
make core-lint      # cargo fmt --check + clippy -D warnings
```
Expected: the parity harness reproduces the web-engine output **exactly** for both HDFC vectors —
year-end rows `2025-04-16 / 10610.00 / Credit / INR / "ONLINE TRF - PYMT RECD - THANK YOU"` and
`2025-04-04 / 1071.00 / Debit / INR / "WWW EXAMPLE COM GURGAON"` (`period_start 2025-04-01`,
`period_end 2026-03-31`, `card_last4 "9070"`); monthly rows `2026-05-15 / 1639.00 / Debit /
"EXAMPLE MERCHANT BANGALORE"` and `2026-05-20 / 6738.00 / Credit / "CC PAYMENT RECEIVED"`
(`period_start 2026-05-15`, `period_end 2026-06-14`, `card_last4 "5678"`). Both call the **same**
`read_hdfc_statement`. Determinism, wrong-issuer (`hdfc_claims`), and malformed-row tests pass.

## 2. Privacy-egress gate (inherited — must stay green)
```bash
make core-privacy-audit   # cargo tree denylist over kaname-core's shipped (default, -e normal) deps
```
Expected: `privacy-egress: OK (no networking crate in kaname-core deps)`. HDFC adds **no
dependency**, so the shipped graph is byte-identical to before — this gate must remain green with
zero changes.

## 3. Build the engine xcframework (MUST precede tuist generate)
```bash
make core-xcframework     # compiles device+sim slices, runs uniffi-bindgen, lipo, create-xcframework
```
Produces `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift`
(git-ignored) — now also exporting `readHdfcStatement` + `hdfcClaims` (the records are reused,
so no new Swift type; `ParsedStatement.periodStart` is now populated for HDFC).

## 4. iOS — generate, lint, test
```bash
make lint                 # swiftlint --strict + swift-format lint --strict
make ios-test             # ios-gen (depends on core-xcframework) → xcodebuild … -destination 'name=iPhone 16' test
```
Expected: the "core ↔ Swift HDFC parse" suite (`ios/Tests/HDFCParseTests.swift`) passes — both
layouts parse via `readHdfcStatement(...)` with exact `Foundation.Decimal` amounts and correct
directions/periods/last4; `hdfcClaims` is `true` for HDFC text and `false` for an ICICI string.

## 5. Full local gate (what CI runs)
```bash
make core-lint && make core-test && make core-privacy-audit && make lint && make ios-test
```
CI mirrors this unchanged: the **core** job (ubuntu) runs the privacy audit; the **iOS** job stays
on `macos-15` and builds the xcframework before `tuist generate`.

---

## Try the parse (ad-hoc, optional)
The composite is pure — a tiny Rust snippet exercises **both** layouts without the app:
```rust
// year-end
let ye = vec![
    "16-Apr-2025 ONLINE TRF - PYMT RECD - THANK YOU 10,610.00 CR 526873XXXXXX9070".to_string(),
    "04-Apr-2025 WWW EXAMPLE COM GURGAON 1,071.00 DR 526873XXXXXX9070".to_string(),
];
let ye_full = "HDFC Bank Credit Cards\nAccount Summary for the period from APRIL-25 to MARCH-26\nCard Number XXXX6873XXXXXX9070".to_string();
let st = kaname_core::read_hdfc_statement(ye, ye_full);
assert_eq!(st.lines.len(), 2);
assert_eq!(st.card_last4.as_deref(), Some("9070"));

// monthly — SAME function, auto-selected layout
let mo = vec!["20/05/2026| 09:05 CC PAYMENT RECEIVED + C 6,738.00".to_string()];
let mo_full = "HDFC Bank Credit Card\nBilling Period 15 May, 2026 - 14 Jun, 2026\nCard Number XXXX1234XXXXXX5678".to_string();
let st = kaname_core::read_hdfc_statement(mo, mo_full);
assert_eq!(st.lines[0].direction, kaname_core::Direction::Credit); // leading '+' ⇒ credit
```

## Add another golden fixture (future readers)
1. Capture ground truth from the web engine (run its reader; never hand-derive `description_raw`).
2. Write `fixtures/<bank>/<kind>/<name>.json` per `contracts/golden-fixture.md` (amounts as
   **strings**; synthetic data only).
3. Add one `Case` row to the harness case table in `tests/parity.rs`. Run `make core-test`.

## Troubleshooting
- **`cargo` not found**: `source "$HOME/.cargo/env"`.
- **`xcodebuild` can't find a destination**: create the "iPhone 16" simulator in Xcode.
- **Swift can't see `readHdfcStatement`**: rebuild `make core-xcframework` before `tuist generate`
  (generated Swift is an artifact).
- **Monthly parity mismatch on `description_raw`**: re-capture from the web reader (step 0) —
  never hand-edit the expected string; the harness asserts it byte-for-byte.
- **`period_start` assertion fails for ICICI**: ensure the `period_start` field is
  `#[serde(default)]` so the ICICI fixture (which omits it) deserializes to `None`.
- **Privacy audit false positive**: HDFC adds no dep; if a networking crate appears, that's an
  unrelated regression — the gate is working.
