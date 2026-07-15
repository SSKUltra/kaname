# Quickstart — Yes Bank (Kiwi) Credit-Card Parser (build & verify)

**Feature**: `005-yes-cc-parser` | **Date**: 2026-07-15
Walkthrough to build, test, and verify the slice locally, honoring the iOS Local Verification Gate
ordering (xcframework **before** `tuist generate`). Commands run from the repo root unless noted. Yes
**reuses** the ICICI/HDFC/SBI gates and adds **no new dependency** and **no new shared helper**.

---

## Prerequisites
- Toolchain per `rust-toolchain.toml` (stable + iOS targets) and `make bootstrap` (tuist, swiftlint,
  swift-format). iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`.
- Local Xcode: create an **"iPhone 16"** simulator (the `-destination …,name=iPhone 16,OS=latest`
  used by `make ios-test` must exist).
- `cargo` on PATH (`source "$HOME/.cargo/env"` if needed).

## 0. Ground truth (already captured & verified — no live run needed)
Yes's `expected` is the locked ground truth from the web engine's Yes reader (`yes_kiwi.py`), and was
**re-confirmed by running the proposed `YesReader` against the real `kaname-core` helpers** (research
"Verification harness"). The exact fixture bytes are in `contracts/golden-fixture.md`. (Optional
re-confirmation from the web repo, `finance-tracker-phase/backend`, with its venv:)
```bash
PYTHONPATH="$PWD" .venv/bin/python - <<'PY'
from app.services.ingestion.statement_readers import yes_kiwi
lines = ["29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr",
         "19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr"]
text = ("YES BANK KLICK\nStatement for YES BANK Card Number 3561XXXXXXXX6686\n"
        "Statement Period: 17/04/2026 To 16/05/2026\n" + "\n".join(lines))
st = yes_kiwi.reader.read_lines(lines, text)
print(st.period_start, st.period_end, st.card_last4)   # 2026-04-17 2026-05-16 6686
for ln in st.lines: print(ln.value_date, ln.amount, ln.direction, repr(ln.description_raw))
PY
```
Expected: `period_start 2026-04-17`, `period_end 2026-05-16`, `card_last4 6686`; row0 `Credit 9000.00
"PAYMENT RECEIVED BBPS - Ref No: RT0001"`, row1 `Debit 100.00 "UPI_EXAMPLE STORE IND - Ref No: RT0002
Miscellaneous Stores"`. (The web `st` also has `printed_total_*` — **ignore them**; they are out of
scope and are not ported, FR-013.)

## 1. Core — format, lint, test (test-first)
```bash
make core-test      # cargo test --all --all-features → unit tests + tests/parity.rs (incl. Yes vector) + determinism
make core-lint      # cargo fmt --check + clippy -D warnings
```
Expected: the parity harness reproduces the web-engine output **exactly** for the Yes vector — rows
`2026-04-29 / 9000.00 / Credit / INR / "PAYMENT RECEIVED BBPS - Ref No: RT0001"` and
`2026-04-19 / 100.00 / Debit / INR / "UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores"`
(`period_start 2026-04-17`, `period_end 2026-05-16`, `card_last4 "6686"`, `errored_lines []`).
Determinism, wrong-issuer (`yes_claims`), direction-from-marker, and reconciliation-carve-out tests
pass.

## 2. Privacy-egress gate (inherited — must stay green)
```bash
make core-privacy-audit   # cargo tree denylist over kaname-core's shipped (default, -e normal) deps
```
Expected: `privacy-egress: OK (no networking crate in kaname-core deps)`. Yes adds **no dependency**,
so the shipped graph is byte-identical to before — this gate must remain green with zero changes.

## 3. Build the engine xcframework (MUST precede tuist generate)
```bash
make core-xcframework     # compiles device+sim slices, runs uniffi-bindgen, lipo, create-xcframework
```
Produces `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift` (git-ignored)
— now also exporting `readYesStatement` + `yesClaims` (the records are reused, so no new Swift type).

## 4. iOS — generate, lint, test
```bash
make lint                 # swiftlint --strict + swift-format lint --strict
make ios-test             # ios-gen (depends on core-xcframework) → xcodebuild … -destination 'name=iPhone 16' test
```
Expected: the "core ↔ Swift Yes parse" suite (`ios/Tests/YesParseTests.swift`) passes —
`readYesStatement(...)` returns the two rows with exact `Foundation.Decimal` amounts, correct
directions (`.credit`/`.debit` from the `Cr`/`Dr` markers), `periodStart == "2026-04-17"`, `periodEnd
== "2026-05-16"`, and **`cardLast4 == "6686"`**; `yesClaims` is `true` for Yes text and `false` for an
ICICI/SBI string.

## 5. Full local gate (what CI runs)
```bash
make core-lint && make core-test && make core-privacy-audit && make lint && make ios-test
```
CI mirrors this unchanged: the **core** job (ubuntu) runs the privacy audit; the **iOS** job stays on
`macos-15` and builds the xcframework before `tuist generate`.

---

## Try the parse (ad-hoc, optional)
The reader is pure — a tiny Rust snippet exercises the single layout without the app:
```rust
let lines = vec![
    "29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr".to_string(),
    "19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr".to_string(),
];
let full = "YES BANK KLICK\nStatement for YES BANK Card Number 3561XXXXXXXX6686\nStatement Period: 17/04/2026 To 16/05/2026".to_string();
let st = kaname_core::read_yes_statement(lines, full);
assert_eq!(st.lines.len(), 2);
assert_eq!(st.lines[0].direction, kaname_core::Direction::Credit); // terminal 'Cr'
assert_eq!(st.lines[1].direction, kaname_core::Direction::Debit);  // terminal 'Dr'
assert_eq!(st.card_last4.as_deref(), Some("6686"));                // four masked digits → present
```

## Add another golden fixture (future readers)
1. Capture ground truth from the web engine (run its reader; never hand-derive `description_raw`).
2. Write `fixtures/<bank>/<kind>/<name>.json` per `contracts/golden-fixture.md` (amounts as
   **strings**; synthetic data only).
3. Add one `Case` row to the harness case table in `tests/parity.rs`. Run `make core-test`.

## Troubleshooting
- **`cargo` not found**: `source "$HOME/.cargo/env"`.
- **`xcodebuild` can't find a destination**: create the "iPhone 16" simulator in Xcode.
- **Swift can't see `readYesStatement`**: rebuild `make core-xcframework` before `tuist generate`
  (generated Swift is an artifact).
- **`card_last4` came back `nil`**: check the mask in `full_text` — `3561XXXXXXXX6686` exposes four
  trailing digits, so `find_last4` MUST return `"6686"`. A `nil` result means the mask was edited to
  expose fewer than four digits.
- **A `printed_total_*` field is referenced anywhere**: that's the reconciliation carve-out being
  violated — remove it. `statement/yes.rs` must NOT port `_DEBITS_RE`/`_CREDITS_RE` (FR-013).
- **Parity mismatch on `description_raw`**: re-capture from the web reader — never hand-edit the
  expected string; the harness asserts it byte-for-byte (remember the merchant-category text is part
  of the description).
- **Privacy audit false positive**: Yes adds no dep; if a networking crate appears, that's an
  unrelated regression — the gate is working.
