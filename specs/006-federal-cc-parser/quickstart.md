# Quickstart — Federal Bank / Scapia Credit-Card Parser (build & verify)

**Feature**: `006-federal-cc-parser` | **Date**: 2026-07-16
Walkthrough to build, test, and verify the slice locally, honoring the iOS Local Verification Gate
ordering (xcframework **before** `tuist generate`). Commands run from the repo root unless noted.
Federal **reuses** the ICICI/HDFC/SBI/Yes gates and adds **no new dependency** and **no new shared
helper**.

---

## Prerequisites
- Toolchain per `rust-toolchain.toml` (stable + iOS targets) and `make bootstrap` (tuist, swiftlint,
  swift-format). iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`.
- Local Xcode: create an **"iPhone 16"** simulator (the `-destination …,name=iPhone 16,OS=latest`
  used by `make ios-test` must exist).
- `cargo` on PATH (`source "$HOME/.cargo/env"` if needed).
- **Editor must preserve UTF-8**: the fixture contains the middle dot **U+00B7** (`·`) and rupee sign
  **U+20B9** (`₹`) — do not let an editor rewrite them to ASCII or escapes.

## 0. Ground truth (already captured & verified — no live run needed)
Federal's `expected` is the locked ground truth from the web engine's Federal reader
(`federal_scapia.py`), and was **re-confirmed by running the proposed `FederalReader` against the real
`kaname-core` helpers** (research "Verification harness"). The exact fixture bytes are in
`contracts/golden-fixture.md`. (Optional re-confirmation from the web repo,
`finance-tracker-phase/backend`, with its venv:)
```bash
PYTHONPATH="$PWD" .venv/bin/python - <<'PY'
from app.services.ingestion.statement_readers import federal_scapia
lines = ["29-04-2026\u00b716:18 Billpayment Payment +\u20b9324.45",
         "24-04-2026\u00b706:03 ExampleMerchantTokyo \u20b92,353.13"]
text = ("Scapia by Federal Bank\nXXXXXXXXXXXX4836 20Apr2026-19May2026\n" + "\n".join(lines))
st = federal_scapia.reader.read_lines(lines, text)
print(st.period_start, st.period_end, st.card_last4)   # 2026-04-20 2026-05-19 4836
for ln in st.lines: print(ln.value_date, ln.amount, ln.direction, repr(ln.description_raw))
PY
```
Expected: `period_start 2026-04-20`, `period_end 2026-05-19`, `card_last4 4836`; row0 `Credit 324.45
"Billpayment Payment"`, row1 `Debit 2353.13 "ExampleMerchantTokyo"`.

## 1. Core — format, lint, test (test-first)
```bash
make core-test      # cargo test --all --all-features → unit tests + tests/parity.rs (incl. Federal vector) + determinism
make core-lint      # cargo fmt --check + clippy -D warnings
```
Expected: the parity harness reproduces the web-engine output **exactly** for the Federal vector — rows
`2026-04-29 / 324.45 / Credit / INR / "Billpayment Payment"` and
`2026-04-24 / 2353.13 / Debit / INR / "ExampleMerchantTokyo"`
(`period_start 2026-04-20`, `period_end 2026-05-19`, `card_last4 "4836"`, `errored_lines []`).
Determinism, wrong-issuer (`federal_claims`), leading-`+`/fallback direction, and encoding-robust
separator tests pass.

## 2. Privacy-egress gate (inherited — must stay green)
```bash
make core-privacy-audit   # cargo tree denylist over kaname-core's shipped (default, -e normal) deps
```
Expected: `privacy-egress: OK (no networking crate in kaname-core deps)`. Federal adds **no
dependency**, so the shipped graph is byte-identical to before — this gate must remain green with zero
changes.

## 3. Build the engine xcframework (MUST precede tuist generate)
```bash
make core-xcframework     # compiles device+sim slices, runs uniffi-bindgen, lipo, create-xcframework
```
Produces `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift` (git-ignored)
— now also exporting `readFederalStatement` + `federalClaims` (the records are reused, so no new Swift
type).

## 4. iOS — generate, lint, test
```bash
make lint                 # swiftlint --strict + swift-format lint --strict
make ios-test             # ios-gen (depends on core-xcframework) → xcodebuild … -destination 'name=iPhone 16' test
```
Expected: the "core ↔ Swift Federal parse" suite (`ios/Tests/FederalParseTests.swift`) passes —
`readFederalStatement(...)` returns the two rows with exact `Foundation.Decimal` amounts, correct
directions (`.credit` from the leading `+`; `.debit` from the classifier default), `periodStart ==
"2026-04-20"`, `periodEnd == "2026-05-19"`, and **`cardLast4 == "4836"`**; `federalClaims` is `true`
for Federal text and `false` for an ICICI/HDFC/SBI/Yes string.

## 5. Full local gate (what CI runs)
```bash
make core-lint && make core-test && make core-privacy-audit && make lint && make ios-test
```
CI mirrors this unchanged: the **core** job (ubuntu) runs the privacy audit; the **iOS** job stays on
`macos-15` and builds the xcframework before `tuist generate`.

---

## Try the parse (ad-hoc, optional)
The reader is pure — a tiny Rust snippet exercises the single layout without the app (note the `·` is
U+00B7 and `₹` is U+20B9):
```rust
let lines = vec![
    "29-04-2026·16:18 Billpayment Payment +₹324.45".to_string(),
    "24-04-2026·06:03 ExampleMerchantTokyo ₹2,353.13".to_string(),
];
let full = "Scapia by Federal Bank\nXXXXXXXXXXXX4836 20Apr2026-19May2026".to_string();
let st = kaname_core::read_federal_statement(lines, full);
assert_eq!(st.lines.len(), 2);
assert_eq!(st.lines[0].direction, kaname_core::Direction::Credit); // leading '+'
assert_eq!(st.lines[1].direction, kaname_core::Direction::Debit);  // no '+', no credit words
assert_eq!(st.card_last4.as_deref(), Some("4836"));                // un-anchored find_last4
```

## Add another golden fixture (future readers)
1. Capture ground truth from the web engine (run its reader; never hand-derive `description_raw`).
2. Write `fixtures/<bank>/<kind>/<name>.json` per `contracts/golden-fixture.md` (amounts as
   **strings**; synthetic data only).
3. Add one `Case` row to the harness case table in `tests/parity.rs`. Run `make core-test`.

## Troubleshooting
- **`cargo` not found**: `source "$HOME/.cargo/env"`.
- **`xcodebuild` can't find a destination**: create the "iPhone 16" simulator in Xcode.
- **Swift can't see `readFederalStatement`**: rebuild `make core-xcframework` before `tuist generate`
  (generated Swift is an artifact).
- **A row doesn't match / `desc` is wrong**: check the separator between the date and `HH:MM`. The row
  regex matches it as **any single character** (the unescaped `.`), so `·`, a space, or `.` all work —
  but if the extractor dropped it entirely (date and time run together), the row won't match. Also
  confirm the `₹` (U+20B9) is present immediately before the amount.
- **`card_last4` came back `nil`**: check the mask in `full_text` — `XXXXXXXXXXXX4836` exposes four
  trailing digits, so the **un-anchored** `find_last4` MUST return `"4836"`. A `nil` result means the
  mask was edited to expose fewer than four digits (or removed). Federal passes **no anchor** on
  purpose (the masked PAN has no `Card Number` label).
- **Direction wrong on the credit row**: the leading `+` is decisive — if it was stripped from the
  fixture line, `Billpayment Payment` (not a credit phrase) would fall back to **Debit**. Keep the `+`.
- **Parity mismatch on `description_raw`**: re-capture from the web reader — never hand-edit the
  expected string; the harness asserts it byte-for-byte (the `HH:MM` time, the `+`, and the `₹` are
  **not** part of it).
- **Privacy audit false positive**: Federal adds no dep; if a networking crate appears, that's an
  unrelated regression — the gate is working.
