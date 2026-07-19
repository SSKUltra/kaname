# Quickstart — Cross-Source De-Duplication (build & verify)

**Feature**: `013-cross-source-dedup` | **Date**: 2026-07-19
Walkthrough to build, test, and verify the slice locally, honoring the iOS Local Verification Gate ordering
(xcframework **before** `tuist generate`). Commands run from the repo root unless noted. This is the
**portable subset (L3 CANONICAL + L4 FUZZY)** of the web engine's de-duplicator ported into the existing
`dedup.rs`: it **reuses** every existing gate, the `Transaction`/`Direction` types, the parity harness, and
the UniFFI bridge, and adds **no new runtime or dev dependency** — the Jaro-Winkler is **hand-rolled**
(verified byte-for-byte vs rapidfuzz).

---

## Prerequisites
- Toolchain per `rust-toolchain.toml` (stable + iOS targets) and `make bootstrap` (tuist, swiftlint,
  swift-format). iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`.
- Local Xcode: an **"iPhone 16"** simulator (the `-destination …,name=iPhone 16,OS=latest` used by
  `make ios-test` must exist).
- `cargo` on PATH (`source "$HOME/.cargo/env"` if needed).

## 0. Ground truth (already captured & verified — no live run needed)
The de-dup behaviour is the locked ground truth from the web engine's `normaliser.py` + the L3/L4
matching in `deduplicator.py` (rapidfuzz `WRatio`/Jaro-Winkler). The **normaliser** and the **hand-rolled
Jaro-Winkler** were re-confirmed against the real `regex` crate and against rapidfuzz's published values
(research "Verification harness"):

| `normalize_narration(raw)` | → result |
|---|---|
| `UPI-SWIGGY-RRN1234` | `swiggy-` |
| `POS SWIGGY BANGALORE 12345678901234` | `swiggy bangalore` |
| `NEFT/ACME CORP/REF999` | `acme corp/ref999` |
| `BY TRANSFER-Salary Credit RRN5678` | `salary credit` |
| `SWIGGY  ORDER   9988776655` | `swiggy order` |

| `jaro_winkler(a, b)` | value | ≥ 0.92 ? |
|---|--:|:--:|
| `swiggy bangalore` / `swiggy bangaluru` | `0.95` | ✅ |
| `amazon` / `amazon pay` | `0.92` | ✅ (inclusive boundary) |
| `acme corp` / `acme corporation` | `0.9125` | ❌ |
| `fine dining` / `fine dine` | `0.9232`* | ✅ |
| `swiggy order` / `swiggy orders` | `0.9846`* | ✅ |
| identical strings | `1.0` | ✅ |

\* `0.9232`/`0.9846` are the **4-dp roundings** of repeating decimals — unit tests assert them by rounding
to 4 dp `((v * 10000.0).round() / 10000.0)`, **not** `== 0.9232`. The `>= 0.92` decision itself uses the
**raw** f64 and is exact (research D5). Algebraically a Jaro ≤ 0.7 can never reach 0.92 after the ×0.1
prefix boost, so the ungated (no-0.7-threshold) formula matches rapidfuzz's decision in every case
(research D3).

The exact golden-fixture bytes (5 scenarios → `expected_matches`) are in `contracts/golden-fixture.md`;
the full end-to-end scenario was verified to yield `[{0,0,Canonical}, {1,1,Fuzzy}, {4,4,Canonical}]` with
three correct survivors.

## 1. Core — format, lint, test (test-first)
```bash
make core-test      # cargo test --all --all-features → dedup.rs unit tests + tests/parity.rs (cross_source basic.json) + determinism
make core-lint      # cargo fmt --check + clippy -D warnings
```
Expected:
- `dedup.rs` unit tests pass — `normalize_narration` on the five reference narrations (incl. the
  stacked-prefix loop and the trailing-refnum strip); `jaro_winkler` on the six reference pairs (4-dp
  assertions); and `cross_source_duplicates` for **canonical**, **fuzzy at the 0.92 boundary**,
  **below-threshold non-match**, **direction / amount / ±1-day date guards**, **canonical-before-fuzzy
  precedence**, **multiplicity** (2 identical incoming vs 1 existing → exactly **1** match), and
  **determinism** (same input → same output).
- The existing `normalize_description` + `dedup_fingerprint` tests still pass (that helper is **unchanged**;
  `normalize_narration` is a **separate** function — do not merge them).
- Parity harness reproduces the web-engine output **exactly**: `cross_source_dedup_matches_expected`
  loads `dedup/cross_source/basic.json`, calls `cross_source_duplicates`, and asserts the returned matches
  equal `expected_matches`. The statement `CASES` and all prior parity tests are **untouched**.

## 2. Privacy-egress gate (inherited — must stay green)
```bash
make core-privacy-audit   # cargo tree denylist over kaname-core's shipped (default, -e normal) deps
```
Expected: `privacy-egress: OK (no networking crate in kaname-core deps)`. This slice adds **no dependency**
(the Jaro-Winkler is hand-rolled), so the shipped graph is byte-identical to before — the gate must remain
green with zero changes, and it covers the new `cross_source_duplicates` path (pure, on-device, zero
network — FR-005/014/016).

## 3. Build the engine xcframework (MUST precede tuist generate)
```bash
make core-xcframework     # compiles device+sim slices, runs uniffi-bindgen, lipo, create-xcframework
```
Produces `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift` (git-ignored) —
now also exporting `crossSourceDuplicates`, the `DedupLayer` enum (`.canonical`/`.fuzzy`), and the
`CrossSourceMatch` record (`incomingIndex`/`existingIndex`/`layer`). `Transaction`/`Direction` are reused
unchanged; **no `uniffi.toml` change**.

## 4. iOS — generate, lint, test
```bash
make lint                 # swiftlint --strict + swift-format lint --strict
make ios-test             # ios-gen (depends on core-xcframework) → xcodebuild … -destination 'name=iPhone 16' test
```
Expected: the "core ↔ Swift cross-source dedup" suite (`ios/Tests/CrossSourceDedupTests.swift`) passes —
build `[Transaction]` existing + incoming, call `crossSourceDuplicates(existing:incoming:)`, and assert a
**canonical** match (`layer == .canonical`), a **fuzzy** match (`layer == .fuzzy`), and a **multiplicity
survivor** (two identical incoming vs one existing → exactly one match, surplus index absent). `DedupLayer`
surfaces as `.canonical`/`.fuzzy`; `CrossSourceMatch` as `incomingIndex`/`existingIndex`/`layer`.

> **swift-format `[Spacing]`**: no trailing inline `//` comment after code — put any comment on its own
> line **above** the statement, or `make lint` fails.

## 5. Full local gate (what CI runs)
```bash
make core-lint && make core-test && make core-privacy-audit && make lint && make ios-test
```
CI mirrors this unchanged: the **core** job (ubuntu) runs the privacy audit; the **iOS** job stays on
`macos-15` and builds the xcframework before `tuist generate`.

---

## Try the dedup (ad-hoc, optional)
The matcher is pure — a tiny Rust snippet exercises both layers without the app:
```rust
use kaname_core::{cross_source_duplicates, CrossSourceMatch, DedupLayer, Transaction, Direction};
use rust_decimal::Decimal;
use chrono::NaiveDate;

let d = |s: &str| NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap();
let amt = |s: &str| std::str::FromStr::from_str(s).unwrap(); // Decimal::from_str

let existing = vec![
    Transaction::new(d("2026-07-04"), "Swiggy Bangalore".into(), amt("250.00"), Direction::Debit),
    Transaction::new(d("2026-07-10"), "swiggy bangalore".into(), amt("500.00"), Direction::Debit),
    Transaction::new(d("2026-07-25"), "uber".into(),             amt("200.00"), Direction::Debit),
];
let incoming = vec![
    // Canonical: same date/amount/direction, narration differs only by whitespace + case.
    Transaction::new(d("2026-07-04"), "swiggy   bangalore".into(), amt("250.00"), Direction::Debit),
    // Fuzzy: +1-day skew, JW("swiggy bangalore","swiggy bangaluru") = 0.95 >= 0.92.
    Transaction::new(d("2026-07-11"), "swiggy bangaluru".into(),   amt("500.00"), Direction::Debit),
    // Multiplicity: matches the single existing "uber" (index 2).
    Transaction::new(d("2026-07-25"), "uber".into(),               amt("200.00"), Direction::Debit),
    // Surplus repeat: the one existing "uber" is already consumed → survivor (absent from result).
    Transaction::new(d("2026-07-25"), "uber".into(),               amt("200.00"), Direction::Debit),
];

let matches = cross_source_duplicates(existing, incoming);
assert_eq!(matches, vec![
    CrossSourceMatch { incoming_index: 0, existing_index: 0, layer: DedupLayer::Canonical },
    CrossSourceMatch { incoming_index: 1, existing_index: 1, layer: DedupLayer::Fuzzy },
    CrossSourceMatch { incoming_index: 2, existing_index: 2, layer: DedupLayer::Canonical },
]);
// Incoming index 3 is a survivor — no match emitted (multiplicity: each existing consumed once).
```

## Add another dedup vector (future scenarios)
1. Append rows to `existing`/`incoming` in `fixtures/dedup/cross_source/basic.json` (or add a sibling
   `*.json`), amounts as **strings**, per `contracts/golden-fixture.md`.
2. Capture the `expected_matches` from the pinned web logic (`normalise_narration` + rapidfuzz), then add
   the pair to the parity loader / assert against the new file. Run `make core-test`.
3. `dedup.rs` needs **no change** — the matcher is source-agnostic (it takes two `Transaction` lists).

## Troubleshooting
- **`cargo` not found**: `source "$HOME/.cargo/env"`.
- **`xcodebuild` can't find a destination**: create the "iPhone 16" simulator in Xcode.
- **Swift can't see `crossSourceDuplicates`/`DedupLayer`/`CrossSourceMatch`**: rebuild
  `make core-xcframework` before `tuist generate` (generated Swift is an artifact).
- **`make lint` fails on `CrossSourceDedupTests.swift`**: a trailing inline `//` comment after code
  violates swift-format `[Spacing]` — move it to its own line above the statement.
- **A `jaro_winkler` unit test fails on `== 0.9232` / `== 0.9846`**: those two references are 4-dp
  roundings of repeating decimals — assert by rounding to 4 dp, not exact equality (research D5). The
  `>= 0.92` decision uses the raw f64 and is unaffected.
- **`normalize_narration` left a stacked prefix (e.g. `pos …` after `UPI/POS …`)**: the prefix strip is a
  **loop-until-stable**, not a single pass — re-check the `while` that re-tries `LEADING_PREFIX` after each
  trim (research D2).
- **`normalize_narration` kept a trailing ref number**: the `TRAILING_REFNUM` strip (`\b[0-9]{10,16}\b\s*$`)
  runs **after** whitespace collapse and **before** lowercasing; a 9-digit or 17-digit tail is intentionally
  **not** stripped (matches the web).
- **Canonical matched when it shouldn't (or fuzzy fired first)**: canonical is tried **before** fuzzy and
  compares the **first-60-char** normalised prefix (`norm.chars().take(60).collect::<String>()`), exact
  date, exact `Decimal` amount, and `Direction`. Fuzzy only runs when canonical misses (research D7).
- **`250.00` didn't match `250.0`**: amount equality is `a.amount.normalize() == b.amount.normalize()`
  (Decimal **value** equality, scale-insensitive) — never `f64`, never string compare (research D4).
- **Direction inferred from sign**: it must be **`Direction` equality**, never re-derived from the amount's
  sign (a Debit and a Credit of the same magnitude are **not** a match — the direction-guard survivor in
  the fixture pins this).
- **An existing row matched twice**: each existing index is consumed at most once (`consumed: Vec<bool>`);
  the surplus incoming repeat must **survive** (the multiplicity survivor in the fixture pins this —
  SC-005).
- **Name clash building the crate root**: only the **FFI** `cross_source_duplicates` is re-exported at the
  crate root (`pub use ffi::cross_source_duplicates;`); the pure `dedup::cross_source_duplicates` is **not**
  re-exported (research D9). `tests/parity.rs` and Swift both use the FFI-exported one.
- **Privacy audit false positive**: this slice adds no dep; if a networking crate appears, that's an
  unrelated regression — the gate is working.
