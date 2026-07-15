# Quickstart — SBI Card Credit-Card Parser (build & verify)

**Feature**: `004-sbi-cc-parser` | **Date**: 2026-07-15
Walkthrough to build, test, and verify the slice locally, honoring the iOS Local Verification Gate
ordering (xcframework **before** `tuist generate`). Commands run from the repo root unless noted.
SBI **reuses** the ICICI/HDFC gates and adds **no new dependency** and **no new shared helper**.

---

## Prerequisites
- Toolchain per `rust-toolchain.toml` (stable + iOS targets) and `make bootstrap` (tuist, swiftlint,
  swift-format). iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`.
- Local Xcode: create an **"iPhone 16"** simulator (the `-destination name=iPhone 16` used by
  `make ios-test` must exist).
- `cargo` on PATH (`source "$HOME/.cargo/env"` if needed).

## 0. Ground truth (already captured — no live run needed)
Unlike the HDFC monthly vector, SBI's `expected` is the **locked characterization ground truth**
from the web engine's `test_cc_reader_characterization.py` (`_SBI_LINES`/`_SBI_TEXT` + the `SBI_CARD`
`_CASES` row) and `sbi_card.py` `_enrich`. The exact fixture bytes are in
`contracts/golden-fixture.md`. (Optional re-confirmation from the web repo, `finance-tracker-phase/backend`, with its venv:)
```bash
PYTHONPATH="$PWD" .venv/bin/python - <<'PY'
from app.services.ingestion.statement_readers import sbi_card
lines = ["21 Apr 26 CARD CASHBACK CREDIT 643.00 C",
         "20 May 26 APPLE INDIA STORE MUMBAI IN 82,900.00 D"]
text = ("GSTIN of SBI Card\nCredit Card Number XXXX XXXX XXXX XX61\n"
        "for Statement Period: 22 Apr 26 to 21 May 26\n" + "\n".join(lines))
st = sbi_card.reader.read_lines(lines, text)
print(st.period_start, st.period_end, st.card_last4)   # 2026-04-22 2026-05-21 None
for ln in st.lines: print(ln.value_date, ln.amount, ln.direction, repr(ln.description_raw))
PY
```
Expected: `period_start 2026-04-22`, `period_end 2026-05-21`, `card_last4 None`; row0 `Credit 643.00
"CARD CASHBACK CREDIT"`, row1 `Debit 82900.00 "APPLE INDIA STORE MUMBAI IN"`.

## 1. Core — format, lint, test (test-first)
```bash
make core-test      # cargo test --all --all-features → unit tests + tests/parity.rs (incl. SBI vector) + determinism
make core-lint      # cargo fmt --check + clippy -D warnings
```
Expected: the parity harness reproduces the web-engine output **exactly** for the SBI vector — rows
`2026-04-21 / 643.00 / Credit / INR / "CARD CASHBACK CREDIT"` and `2026-05-20 / 82900.00 / Debit /
INR / "APPLE INDIA STORE MUMBAI IN"` (`period_start 2026-04-22`, `period_end 2026-05-21`,
`card_last4 null`, `errored_lines []`). Determinism, wrong-issuer (`sbi_claims`), and
direction-from-marker tests pass.

## 2. Privacy-egress gate (inherited — must stay green)
```bash
make core-privacy-audit   # cargo tree denylist over kaname-core's shipped (default, -e normal) deps
```
Expected: `privacy-egress: OK (no networking crate in kaname-core deps)`. SBI adds **no
dependency**, so the shipped graph is byte-identical to before — this gate must remain green with
zero changes.

## 3. Build the engine xcframework (MUST precede tuist generate)
```bash
make core-xcframework     # compiles device+sim slices, runs uniffi-bindgen, lipo, create-xcframework
```
Produces `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift`
(git-ignored) — now also exporting `readSbiStatement` + `sbiClaims` (the records are reused, so no
new Swift type).

## 4. iOS — generate, lint, test
```bash
make lint                 # swiftlint --strict + swift-format lint --strict
make ios-test             # ios-gen (depends on core-xcframework) → xcodebuild … -destination 'name=iPhone 16' test
```
Expected: the "core ↔ Swift SBI parse" suite (`ios/Tests/SBIParseTests.swift`) passes —
`readSbiStatement(...)` returns the two rows with exact `Foundation.Decimal` amounts, correct
directions (`.credit`/`.debit` from the `C`/`D` markers), `periodStart == "2026-04-22"`, `periodEnd
== "2026-05-21"`, and **`cardLast4 == nil`**; `sbiClaims` is `true` for SBI text and `false` for an
ICICI/HDFC string.

## 5. Full local gate (what CI runs)
```bash
make core-lint && make core-test && make core-privacy-audit && make lint && make ios-test
```
CI mirrors this unchanged: the **core** job (ubuntu) runs the privacy audit; the **iOS** job stays
on `macos-15` and builds the xcframework before `tuist generate`.

---

## Try the parse (ad-hoc, optional)
The reader is pure — a tiny Rust snippet exercises the single layout without the app:
```rust
let lines = vec![
    "21 Apr 26 CARD CASHBACK CREDIT 643.00 C".to_string(),
    "20 May 26 APPLE INDIA STORE MUMBAI IN 82,900.00 D".to_string(),
];
let full = "GSTIN of SBI Card\nCredit Card Number XXXX XXXX XXXX XX61\nfor Statement Period: 22 Apr 26 to 21 May 26".to_string();
let st = kaname_core::read_sbi_statement(lines, full);
assert_eq!(st.lines.len(), 2);
assert_eq!(st.lines[0].direction, kaname_core::Direction::Credit); // terminal 'C'
assert_eq!(st.lines[1].direction, kaname_core::Direction::Debit);  // terminal 'D'
assert_eq!(st.card_last4, None);                                    // only 2 masked digits → absent
```

## Add another golden fixture (future readers)
1. Capture ground truth from the web engine (run its reader; never hand-derive `description_raw`).
2. Write `fixtures/<bank>/<kind>/<name>.json` per `contracts/golden-fixture.md` (amounts as
   **strings**; synthetic data only).
3. Add one `Case` row to the harness case table in `tests/parity.rs`. Run `make core-test`.

## Troubleshooting
- **`cargo` not found**: `source "$HOME/.cargo/env"`.
- **`xcodebuild` can't find a destination**: create the "iPhone 16" simulator in Xcode.
- **Swift can't see `readSbiStatement`**: rebuild `make core-xcframework` before `tuist generate`
  (generated Swift is an artifact).
- **`card_last4` came back non-null**: check the mask in `full_text` — `XXXX XXXX XXXX XX61` exposes
  only two trailing digits, so `find_last4` MUST return `None`. A non-null result means the mask was
  edited to expose four digits.
- **Parity mismatch on `description_raw`**: re-capture from the web reader — never hand-edit the
  expected string; the harness asserts it byte-for-byte.
- **Privacy audit false positive**: SBI adds no dep; if a networking crate appears, that's an
  unrelated regression — the gate is working.
