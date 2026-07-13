# Quickstart — ICICI Credit-Card Parser (build & verify)

**Feature**: `002-icici-cc-parser` | **Date**: 2026-07-08
Walkthrough to build, test, and verify the slice locally, honoring the iOS Local Verification
Gate ordering (xcframework **before** `tuist generate`). Commands run from the repo root unless
noted.

---

## Prerequisites
- Toolchain per `rust-toolchain.toml` (stable + iOS targets) and `make bootstrap` (tuist,
  swiftlint, swift-format). iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`.
- Local Xcode 26: create an **“iPhone 16”** simulator (the `-destination name=iPhone 16` used by
  `make ios-test` must exist).

## 1. Core — format, lint, test (test-first)
```bash
make core-test      # cargo test --all --all-features  → unit tests + tests/parity.rs (golden) + determinism
make core-lint      # cargo fmt --check + clippy -D warnings
```
Expected: the golden parity test reproduces the web-engine output **exactly** —
rows `2026-04-29 / 13628.36 / Credit / INR / "4262 BBPS Payment received"` and
`2026-05-26 / 10.20 / Debit / INR / "1814 Fee on gaming transaction"`; `period_end 2026-05-28`;
`card_last4 "1002"`; `errored_lines` empty. Determinism, wrong-issuer, and malformed-row tests pass.

## 2. Privacy-egress gate (new)
```bash
make core-privacy-audit   # cargo tree denylist over kaname-core's shipped (default, -e normal) deps
```
Expected: `privacy-egress: OK (no networking crate in kaname-core shipped deps)`. Fails the
build if any networking crate (reqwest/hyper/tokio/rustls/…) ever enters the shipped graph.
Note `serde_json` is a **dev**-dependency and is correctly excluded by `-e normal`.

## 3. Build the engine xcframework (MUST precede tuist generate)
```bash
make core-xcframework     # compiles device+sim slices, runs uniffi-bindgen, lipo, create-xcframework
```
Produces `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift`
(git-ignored) — now including `readIciciStatement`, `iciciClaims`, `ParsedStatement`,
`ParsedTransaction`.

## 4. iOS — generate, lint, test
```bash
make lint                 # swiftlint --strict + swift-format lint --strict
make ios-test             # ios-gen (depends on core-xcframework) → xcodebuild … -destination 'name=iPhone 16' test
```
Expected: the “core ↔ Swift ICICI parse” suite (`ios/Tests/ICICIParseTests.swift`) passes —
`readIciciStatement(...)` returns the two rows with exact `Foundation.Decimal` amounts, correct
directions, `periodEnd == "2026-05-28"`, `cardLast4 == "1002"`; `iciciClaims` is `true` for the
ICICI text and `false` for an HDFC string.

## 5. Full local gate (what CI runs)
```bash
make core-lint && make core-test && make core-privacy-audit && make lint && make ios-test
```
CI mirrors this: the **core** job (ubuntu) adds `make core-privacy-audit`; the **iOS** job stays
on `macos-15` and builds the xcframework before `tuist generate`.

---

## Try the parse (ad-hoc, optional)
The seam is pure — a tiny Rust snippet exercises it without the app:
```rust
let lines = vec![
    "29/04/2026 4262 BBPS Payment received 0 13,628.36 CR".to_string(),
    "26/05/2026 1814 Fee on gaming transaction 0 10.20".to_string(),
];
let full = "ICICI Bank Statement\nStatement Date May 28, 2026\n4315XXXXXXXX1002".to_string();
let st = kaname_core::read_icici_statement(lines, full);
assert_eq!(st.lines.len(), 2);
assert_eq!(st.card_last4.as_deref(), Some("1002"));
```

## Add another golden fixture (future readers)
1. Capture ground truth from the web engine (run its reader; never hand-derive
   `description_raw`).
2. Write `fixtures/<bank>/<kind>/<name>.json` per `contracts/golden-fixture.md` (amounts as
   **strings**; synthetic data only).
3. Add one row to the harness case table in `tests/parity.rs`. Run `make core-test`.

## Troubleshooting
- **`cargo` not found**: `source "$HOME/.cargo/env"` (or add `~/.cargo/bin` to `PATH`).
- **`xcodebuild` can't find a destination**: create the “iPhone 16” simulator in Xcode.
- **Swift can't see the new functions**: rebuild `make core-xcframework` before `tuist generate`
  (generated Swift is an artifact).
- **Privacy audit false positive**: confirm the offending crate is a **dev/build** dep; the
  audit uses `-e normal` (shipped only). If it's genuinely in the shipped tree, that's the gate
  working — remove the network dependency.
