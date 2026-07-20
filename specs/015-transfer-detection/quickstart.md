# Quickstart — On-Device Self-Transfer Detection (build & verify)

**Feature**: `015-transfer-detection` | **Date**: 2026-07-20
Walkthrough to build, test, and verify the slice locally, honoring the iOS Local Verification Gate ordering
(xcframework **before** `tuist generate`). Commands run from the repo root unless noted. This is the pure port of
the web engine's `transfer_detector.py` pure subset (`_narration_similarity` token-Jaccard + `_score` + the ±1-day /
±₹1.00 tolerance envelope + the outflow-anchored greedy claim from `detect_pairs_for_user` / `_best_counterpart`,
minus all SQL) into a **new `transfer.rs`** module (a pure sibling of `dedup.rs` / `coverage.rs`): it **reuses** the
shared `Direction` enum, the `Decimal` + `NaiveDate` custom types, every existing gate, the parity harness, and the
UniFFI bridge, and adds **no new runtime or dev dependency** (`std` sets + `rust_decimal`'s
`ToPrimitive::to_f64` only). The core **never reads the wall-clock, locale, or a DB** — it takes one already-parsed
row pool and returns the detected pairs.

---

## Prerequisites
- Toolchain per `rust-toolchain.toml` (stable + iOS targets) and `make bootstrap` (tuist, swiftlint,
  swift-format). iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`.
- Local Xcode: an **"iPhone 16"** simulator (the `-destination …,name=iPhone 16,OS=latest` used by
  `make ios-test` must exist).
- `cargo` on PATH (`source "$HOME/.cargo/env"` if needed).

## 0. Ground truth (already captured & verified — no live run needed)
The matcher behaviour is the locked ground truth from the web engine's `transfer_detector.py` pure helpers. The
single nine-scenario pool (`fixtures/transfer/basic.json`) was run through the locked algorithm and the five
`_score` values re-confirmed **bit-identical Python ⇄ Rust** and round-trip-stable through serde_json/ryu (research
"Verification"). Amounts are per-scenario-isolated (≥ ₹1000 apart) so greedy claiming never crosses scenarios:

| Scenario | Rows (out / in) | Outcome | `score` (exact f64) |
|---|---|---|---|
| S1 matched pair (same day/amount, non-card) | `s1-out` / `s1-in`, 5000.00, 06-01 | pair, cc=false, sim 1/7 | **1.0285714285714285** |
| S2 within tolerance (1 day, ₹0.50) | `s2-out` 1000.00 06-03 / `s2-in` 1000.50 06-04 | pair, cc=false, sim 3/5 | **0.8200000000000001** |
| S3 amount drift (₹500) | `s3-out` 2000.00 / `s3-in` 2500.00 | **none** | — |
| S4 date drift (4 days) | `s4-out` 06-07 / `s4-in` 06-11 | **none** | — |
| S5 same direction (two outflows) | `s5-out-a` / `s5-out-b`, both Debit | **none** | — |
| S6 same account | `s6-out` / `s6-in`, both acct-a | **none** | — |
| S7 narration tiebreak | `s7-out` / `s7-in-a` (sim 0.25) vs `s7-in-b` (sim 0) | pair → `s7-in-a`, cc=false | **1.05** |
| S8 id tiebreak | `s8-out` / `s8-in-a`,`s8-in-b` (sim 1.0, identical) | pair → `s8-in-a` (lowest id), cc=false | **1.2** |
| S9 credit-card payment | `s9-out` (savings) / `s9-in` (card, is_credit_card=true) | pair, **cc=true**, sim 1/6 | **1.0333333333333334** |

**5 pairs** (emitted in anchor `(date, id)` order `s1, s2, s7, s8, s9`), **4 guards** produce none. The four
same-day/same-amount pairs exceed 1.0 (score **not** capped); S2's is `< 1` (date + amount drift). The exact
golden-fixture bytes (20 rows + 5 `expected_pairs`) are in `contracts/golden-fixture.md`.

## 1. Core — format, lint, test (test-first)
```bash
make core-test      # cargo test --all --all-features → transfer.rs unit tests + tests/parity.rs (transfer/basic.json) + determinism
make core-lint      # cargo fmt --check + clippy -D warnings
```
Expected:
- `transfer.rs` unit tests pass — the five pairing scenarios (S1/S2/S7/S8/S9), the four guards (S3/S4/S5/S6 → zero
  pairs), the **inclusive boundary** (exactly 1 day / exactly ₹1.00 pair; 2 days / ₹1.01 do not), the narration + id
  tiebreaks, the card flag, the score **floor at 0.0 and no cap at 1.0**, greedy single-claim (earliest anchor by
  `(date, id)` wins a contested inflow), `narration_similarity` (incl. empty/blank → `0.0`), and **empty /
  no-outflow input → 0 pairs** + determinism.
- Parity harness reproduces the web-engine output **exactly**: `transfer_detection_matches_expected` loads
  `transfer/basic.json`, builds the `Vec<TransferInput>` pool (parse ISO dates + `Decimal::from_str` amounts), calls
  `detect_transfers`, and asserts the 5 pairs equal `expected_pairs` — the `score` field compared with **exact
  `f64` `==`**. The statement `CASES`, the dedup/coverage loaders/tests, and all prior parity tests are
  **untouched**.

## 2. Privacy-egress gate (inherited — must stay green)
```bash
make core-privacy-audit   # cargo tree denylist over kaname-core's shipped (default, -e normal) deps
```
Expected: `privacy-egress: OK (no networking crate in kaname-core deps)`. This slice adds **no dependency** (`std`
token sets + `rust_decimal`'s `ToPrimitive::to_f64`), so the shipped graph is byte-identical to before — the gate
must remain green with zero changes, and it covers the new `detect_transfers` path (pure, on-device, zero network,
zero clock, zero DB — FR-012/014/016).

## 3. Build the engine xcframework (MUST precede tuist generate)
```bash
make core-xcframework     # compiles device+sim slices, runs uniffi-bindgen, lipo, create-xcframework
```
Produces `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift` (git-ignored) — now also
exporting `detectTransfers` and the `TransferInput` / `TransferPair` records. `amount` crosses as a base-10 `String`
(exact `Decimal`), `date` as ISO-8601 `String` (`NaiveDate`), `direction` via the existing `Direction` enum, and
`score` as a native `Double`; **no `uniffi.toml` change**.

## 4. iOS — generate, lint, test
```bash
make lint                 # swiftlint --strict + swift-format lint --strict
make ios-test             # ios-gen (depends on core-xcframework) → xcodebuild … -destination 'name=iPhone 16' test
```
Expected: the "core ↔ Swift transfer detection" suite (`ios/Tests/TransferDetectionTests.swift`) passes — build a
small `[TransferInput]` (a self-transfer pair with both `isCreditCard: false`, and a credit-card-payment pair with
one leg `isCreditCard: true`), with `amount` via `Decimal(string:locale:)` (`en_US_POSIX`) and `direction`
`.debit`/`.credit`, call `detectTransfers(rows:)`, and assert the returned `[TransferPair]`: the self-transfer pair
links the two ids with `isCreditCardPayment == false`; the card pair has `isCreditCardPayment == true`; each exposes
a `score` (`Double`). Fields surface as `outflowId` / `inflowId` / `isCreditCardPayment` / `score`; input as
`isCreditCard`.

> **swift-format `[Spacing]`**: no trailing inline `//` comment after code — put any comment on its own line
> **above** the statement, or `make lint` fails.

## 5. Full local gate (what CI runs)
```bash
make core-lint && make core-test && make core-privacy-audit && make lint && make ios-test
```
CI mirrors this unchanged: the **core** job (ubuntu) runs the privacy audit; the **iOS** job stays on `macos-15`
and builds the xcframework before `tuist generate`.

---

## Try the matcher (ad-hoc, optional)
The matcher is pure — a tiny Rust snippet exercises a self-transfer + a credit-card payment without the app:
```rust
use kaname_core::{detect_transfers, Direction, TransferInput};
use chrono::NaiveDate;
use rust_decimal::Decimal;
use std::str::FromStr;

let d = |s: &str| NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap();
let m = |s: &str| Decimal::from_str(s).unwrap();

let rows = vec![
    // self-transfer: outflow (anchor) on acct-a …
    TransferInput { id: "a".into(), account_id: "acct-a".into(), is_credit_card: false, date: d("2026-06-01"), amount: m("5000.00"), direction: Direction::Debit, description: "NEFT TO HDFC SALARY ACCOUNT".into() },
    // … and the matching inflow on acct-b (same day, same amount).
    TransferInput { id: "b".into(), account_id: "acct-b".into(), is_credit_card: false, date: d("2026-06-01"), amount: m("5000.00"), direction: Direction::Credit, description: "NEFT FROM ICICI".into() },
    // credit-card payment: outflow from savings …
    TransferInput { id: "c".into(), account_id: "acct-a".into(), is_credit_card: false, date: d("2026-06-17"), amount: m("9000.00"), direction: Direction::Debit, description: "CC BILL PAYMENT".into() },
    // … inflow onto the card account (is_credit_card = true).
    TransferInput { id: "e".into(), account_id: "acct-c".into(), is_credit_card: true, date: d("2026-06-17"), amount: m("9000.00"), direction: Direction::Credit, description: "PAYMENT RECEIVED HDFC CARD".into() },
];

let pairs = detect_transfers(rows);
assert_eq!(pairs.len(), 2);                        // emitted in anchor (date, id) order
assert_eq!(pairs[0].outflow_id, "a");
assert_eq!(pairs[0].inflow_id, "b");
assert_eq!(pairs[0].is_credit_card_payment, false);
assert_eq!(pairs[0].score, 1.0285714285714285);    // exact f64; > 1.0 (uncapped)
assert_eq!(pairs[1].outflow_id, "c");
assert_eq!(pairs[1].inflow_id, "e");
assert_eq!(pairs[1].is_credit_card_payment, true); // either leg a card
```
> Note: this ad-hoc snippet calls the FFI-exported `kaname_core::detect_transfers` with an owned `Vec` (the crate
> root re-exports the FFI wrapper). Over the bridge, Swift passes an owned `[TransferInput]`.

## Add another transfer vector (future scenarios)
1. Add a sibling `fixtures/transfer/*.json` (or extend `basic.json`), amounts as **strings**, dates as **ISO
   strings**, direction `"Debit"`/`"Credit"`, per `contracts/golden-fixture.md`.
2. Capture the `expected_pairs` from the pinned web helpers (`_narration_similarity` + `_score` + the tolerances +
   the anchor-sort greedy claim) via a fresh live in-memory run — never hand-derive `score`. Then point the parity
   loader at the new file (or parameterise it) and run `make core-test`.
3. `transfer.rs` needs **no change** — the matcher is pool-agnostic (it takes one `&[TransferInput]`).

## Troubleshooting
- **`cargo` not found**: `source "$HOME/.cargo/env"`.
- **`xcodebuild` can't find a destination**: create the "iPhone 16" simulator in Xcode.
- **Swift can't see `detectTransfers`/`TransferInput`/`TransferPair`**: rebuild `make core-xcframework` before
  `tuist generate` (generated Swift is an artifact).
- **`make lint` fails on `TransferDetectionTests.swift`**: a trailing inline `//` comment after code violates
  swift-format `[Spacing]` — move it to its own line above the statement.
- **Name clash building the crate root** (`detect_transfers` defined twice): only the **FFI** `detect_transfers` is
  re-exported at the crate root (`pub use ffi::detect_transfers;`); the pure `transfer::detect_transfers` is **not**
  re-exported, and `ffi.rs` imports only the transfer **types** (not the pure fn) and calls it fully-qualified
  (research D9). `tests/parity.rs` and Swift both use the FFI-exported one — this mirrors `compute_coverage`
  (014) / `cross_source_duplicates` (013).
- **Similarity looks wrong / too "clean"**: `narration_similarity` is **raw-token Jaccard** on the **lowercased,
  whitespace-split** description — it must **not** call `dedup::normalize_narration` or reuse `dedup`'s Jaro-Winkler
  (that is a *different* character-similarity for a different purpose). Empty or whitespace-only either side → `0.0`
  (research D4, the key porting gotcha).
- **A `score` is capped at 1.0 (or an assertion fails at ~1.03/1.05/1.2)**: `score` is floored at `0.0` but **not**
  capped at 1.0 — a same-day/same-amount pair with narration overlap legitimately exceeds 1.0. Don't add a
  `.min(1.0)` (research D5).
- **`score` bits differ from the fixture**: keep the exact Python left-to-right op order
  `((1.0 - 0.2·date_diff) - 0.2·amount_diff_f64) + 0.2·sim` and `amount_diff.to_f64().unwrap_or(0.0)` — reordering
  the additions changes the last ULP and breaks the exact-`==` parity assertion (research D5/D6).
- **A pair claims the wrong inflow / too many pairs**: pairing is a **greedy single-claim** — anchors are outflows
  processed in `(date, id)` order, and both legs are marked in the shared `consumed` vector on a match, so each row
  is used at most once and the earliest anchor wins a contested inflow (research D3, FR-005).
- **Ambiguous tie resolved unexpectedly**: the selection tuple is `(date_diff ↑, amount_diff ↑, similarity ↓, id ↑)`
  — closest date, then closest amount, then **highest** narration similarity, then **lowest** id. Since `id` is
  unique this is a strict total order (research D7).
- **Determinism worry (`HashSet` order)**: the token sets feed only intersection/union **counts**, and candidate
  selection is a total order over row indices, so iteration order never reaches the result — output is
  byte-identical across runs (research D8, SC-009).
- **The core read the clock / locale / a DB**: it must not — the pool is a parameter and there is no `today`; all
  persistence (`transfer_group_id`/`is_transfer`), categorisation, and audit are platform-side and **out of scope**
  (research D10, Constitution II).
- **Privacy audit false positive**: this slice adds no dep; if a networking crate appears, that's an unrelated
  regression — the gate is working.
