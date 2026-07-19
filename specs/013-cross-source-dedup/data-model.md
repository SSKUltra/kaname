# Phase 1 — Data Model: Cross-Source Transaction De-Duplication

**Feature**: `013-cross-source-dedup` | **Date**: 2026-07-19
**Scope**: The types and functions this slice introduces, reuses, and configures — all inside the existing
`dedup` module + its bridge. It adds **one pure function** (the L3+L4 matcher), **two small string/`f64`
helpers** (`normalize_narration` + the private `jaro`/`jaro_winkler`), **one enum** (`DedupLayer`), **one
record** (`CrossSourceMatch`), **one FFI wrapper**, **one golden fixture**, and **tests** — with **no new
dependency**, **no `uniffi.toml` change**, and **no reader/`model.rs`/`base.rs` change**. It reuses the
shared `Transaction`/`Direction`, the exact-decimal `Decimal` money type, the parity harness, and the
UniFFI bridge. The existing `normalize_description` + `dedup_fingerprint` are **left unchanged**.

---

## New types (the matcher) — `core/crates/kaname-core/src/dedup.rs`

### `DedupLayer` (NEW) — `uniffi::Enum`

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum DedupLayer {
    Canonical,
    Fuzzy,
}
```

Which layer caught a duplicate → Swift `.canonical` / `.fuzzy`. Fieldless, so `Copy` + `Eq` are safe;
derives mirror `ChainStatus`/`ReconcileStatus` exactly.

### `CrossSourceMatch` (NEW) — `uniffi::Record`

```rust
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CrossSourceMatch {
    pub incoming_index: u32,
    pub existing_index: u32,
    pub layer: DedupLayer,
}
```

One identified duplicate: the incoming row, the existing row it duplicates, and the layer. Derives mirror
`ChainResult`/`ReconcileResult` (`Debug/Clone/PartialEq/uniffi::Record`). Rows are named **by index** into
the caller's input slices (D8) — `Transaction` has no id, and both `Vec<Transaction>` are held by the
caller.

| Field | Rust type | Wire → Swift | Meaning |
|---|---|---|---|
| `incoming_index` | `u32` | `UInt32` | position of the matched **incoming** row |
| `existing_index` | `u32` | `UInt32` | position of the **existing** row it duplicates (consumed once) |
| `layer` | `DedupLayer` | `DedupLayer` | `Canonical` or `Fuzzy` |

### Threshold constant (NEW, private)

```rust
const JARO_WINKLER_THRESHOLD: f64 = 0.92; // inclusive fuzzy cutoff (FR-009)
```

---

## New helpers — `dedup.rs`

### `normalize_narration` (NEW, `pub`) — the pinned narration source of truth

```rust
pub fn normalize_narration(raw: &str) -> String
```

Backed by four `std::sync::LazyLock<Regex>` statics ported 1:1 from `normaliser.py`:

| Static | Pattern | Role |
|---|---|---|
| `LEADING_PREFIX` | `(?i)^(POS\s\|UPI[-/]\|NEFT/\|IMPS/\|ACH/\|BIL/\|RTGS/\|INT\.PD\./\|TO TRANSFER-\|BY TRANSFER-)` | strip one payment-rail prefix (looped until stable) |
| `RRN` | `(?i)\bRRN\d+\b` | remove RRN reference tokens |
| `TRAILING_REFNUM` | `\b[0-9]{10,16}\b\s*$` | strip a trailing 10–16-digit reference number |
| `WHITESPACE` | `\s+` | collapse whitespace runs to a single space |

**Algorithm (exact web order)**: `trim` → **loop**{ strip one `LEADING_PREFIX` + `trim` } until stable →
`RRN.replace_all → ""` → `WHITESPACE.replace_all → " "` → strip `TRAILING_REFNUM` → `to_lowercase()` →
`trim`. Pure; total (never panics); deterministic. **Distinct from** the coarser `normalize_description`
(kept for `dedup_fingerprint`). Verified against the real `regex` crate (research Verification harness).

### `jaro` / `jaro_winkler` (NEW, private) — hand-rolled, ungated, `f64`

```rust
fn jaro(a: &[char], b: &[char]) -> f64
fn jaro_winkler(a: &str, b: &str) -> f64
```

- `jaro`: classic Jaro on `&[char]` (unicode-safe). Match window `max(a.len(), b.len()) / 2 - 1`
  (saturating), transpositions `/ 2`; `1.0` for two empty inputs, `0.0` if either empty or no matches;
  `(m/|a| + m/|b| + (m − t)/m) / 3` otherwise.
- `jaro_winkler`: collect both into `Vec<char>`; `prefix` = common leading chars **capped at 4**; return
  `jaro + prefix as f64 * 0.1 * (1.0 − jaro)`. **Ungated** (no `jaro > 0.7` boost threshold) — matches
  `rapidfuzz` exactly, and the gate is proven decision-irrelevant at 0.92 (research D3).

A Jaro-Winkler similarity is a statistical score in [0,1] → legitimately `f64`, **not money** (research
D4). Verified byte-for-byte vs `rapidfuzz` (research D3/D5 + Verification harness).

---

## New function (the matcher) — `dedup.rs`

```rust
pub fn cross_source_duplicates(
    existing: &[Transaction],
    incoming: &[Transaction],
) -> Vec<CrossSourceMatch>
```

**Algorithm** (research D7):

1. **Precompute** `normalize_narration` for every `existing` and `incoming` row once → two `Vec<String>`.
2. `let mut consumed = vec![false; existing.len()];` (multiplicity — each existing matched at most once).
3. For each `incoming[i]` in order:
   - **Canonical pass** (first): first unconsumed `e` where `existing[e].date == incoming[i].date` **&&**
     `existing[e].amount.normalize() == incoming[i].amount.normalize()` **&&** `existing[e].direction ==
     incoming[i].direction` **&&** the **60-char prefix** of `norm_e` equals that of `norm_i`
     (`s.chars().take(60).collect::<String>()`). Hit → push `{ i, e, Canonical }`, `consumed[e] = true`,
     next `i`.
   - **Fuzzy pass** (only if no canonical hit): first unconsumed `e` where amounts equal
     (`normalize()`) **&&** directions equal **&&** `(existing[e].date −
     incoming[i].date).num_days().abs() <= 1` **&&** `jaro_winkler(&norm_e, &norm_i) >=
     JARO_WINKLER_THRESHOLD`. Hit → push `{ i, e, Fuzzy }`, `consumed[e] = true`, next `i`.
   - No hit → survivor (no match emitted).

| Aspect | Rule | Source |
|---|---|---|
| Amount equality | `a.amount.normalize() == b.amount.normalize()` (`250.00` == `250.0`), exact `Decimal` | FR-006/008/011, edge cases |
| Direction | `Direction` equality; **never** re-derived from sign | FR-011, edge cases |
| Canonical date | `existing[e].date == incoming[i].date` (0-day) | FR-006 |
| Fuzzy date window | `(d_e − d_i).num_days().abs() <= 1` (±1 day inclusive; ≥2 out) | FR-008, edge cases |
| Canonical narration | first-60-char prefix equality of the normalised narrations | FR-006/007 |
| Fuzzy narration | `jaro_winkler(full norm_e, full norm_i) >= 0.92` (inclusive) | FR-008/009 |
| Layer precedence | canonical tried before fuzzy, per incoming | FR-004, US6 |
| Tie-break | first **unconsumed** existing in existing order wins | FR-004, US6, SC-007 |
| Multiplicity | `consumed[e]` set on match → each existing at most once | FR-003, US3, SC-005 |
| Read-only | borrows `&[Transaction]`; never mutates/drops/reorders/merges/persists | FR-002, US5, SC-009 |

**Purity/totality**: no I/O, no network/clock/locale, no global mutable state, no file/DB/PDF; identical
input ⇒ identical output; empty either side ⇒ empty result; never panics (FR-005, SC-012).

### Unit tests (`dedup.rs`)

- **`normalize_narration`** on the captured references: `"UPI-SWIGGY-RRN1234"→"swiggy-"`, `"POS SWIGGY
  BANGALORE 12345678901234"→"swiggy bangalore"`, `"NEFT/ACME CORP/REF999"→"acme corp/ref999"`, `"BY
  TRANSFER-Salary Credit RRN5678"→"salary credit"`, `"SWIGGY  ORDER   9988776655"→"swiggy order"`.
- **`jaro_winkler`** on the reference pairs, asserted via 4-dp rounding (research D5):
  `swiggy bangalore/swiggy bangaluru → 0.95`, `amazon/amazon pay → 0.92`, `acme corp/acme corporation →
  0.9125`, `fine dining/fine dine → 0.9232`, identical → `1.0`, `swiggy order/swiggy orders → 0.9846`;
  plus `amazon` pair `>= 0.92` **true**, `acme` pair `>= 0.92` **false**.
- **`cross_source_duplicates`**: canonical match; fuzzy at the inclusive **0.92** boundary
  (`amazon`/`amazon pay`, ±1 day); below-threshold non-match (`acme corp`/`acme corporation` → survives);
  direction guard, amount guard, and 2-day date guard (all survive); multiplicity (2 identical incoming vs
  1 existing → exactly **1** match, the other survives); canonical-before-fuzzy precedence; determinism.

---

## Reused types (UNCHANGED)

### `Transaction` (`model.rs`) — `uniffi::Record`

```rust
pub struct Transaction { pub date: NaiveDate, pub description: String, pub amount: Decimal, pub direction: Direction }
```

The matcher's input rows. Read-only: it reads `date`, `description` (→ `normalize_narration`), `amount`
(exact `Decimal`), and `direction`. **No field change.** Constructed in tests via `Transaction::new`.

### `Direction` (`model.rs`) — `uniffi::Enum`

`enum Direction { Debit, Credit }`. Compared by equality in both layers; never re-derived from the
amount's sign (FR-011). **No change.**

### `Decimal` (`rust_decimal`)

Exact money. Amount equality is `Decimal::normalize` value-equality (scale-insensitive), the same idiom
`dedup_fingerprint` uses. Never `f64`.

### Left unchanged in `dedup.rs`

`normalize_description` (Unicode uppercase + ws-collapse) and `dedup_fingerprint` (the L2 EXACT-hash
analogue, **not** wired into the L3/L4 matcher) — retained as-is (spec Out of Scope, FR-012).

---

## FFI surface (additive — `ffi.rs` + `lib.rs`)

```rust
// ffi.rs — mirrors reconcile_statement wrapping reconcile.
use crate::dedup::{cross_source_duplicates, CrossSourceMatch};

#[uniffi::export]
pub fn cross_source_duplicates(
    existing: Vec<Transaction>,
    incoming: Vec<Transaction>,
) -> Vec<CrossSourceMatch> {
    crate::dedup::cross_source_duplicates(&existing, &incoming)
}
```

`Transaction` is already imported in `ffi.rs`. `lib.rs` adds:

```rust
pub use ffi::cross_source_duplicates;                              // the FFI wrapper (Swift entry)
pub use dedup::{CrossSourceMatch, DedupLayer, normalize_narration}; // types + narration helper
// NOTE: do NOT `pub use dedup::cross_source_duplicates` — it name-clashes with the ffi wrapper (D9).
```

`DedupLayer`/`CrossSourceMatch` derive `uniffi`, so bindgen emits their Swift types; the `Transaction`
record + its `Decimal`/`NaiveDate` custom types are reused → **no `uniffi.toml` change**. Generated Swift:

```swift
public enum DedupLayer { case canonical; case fuzzy }
public struct CrossSourceMatch { public var incomingIndex: UInt32; public var existingIndex: UInt32; public var layer: DedupLayer }
public func crossSourceDuplicates(existing: [Transaction], incoming: [Transaction]) -> [CrossSourceMatch]
```

---

## Fixture / harness types (test-only)

### Golden fixture — `fixtures/dedup/cross_source/basic.json` (NEW shape)

```json
{
  "_comment": "…synthetic…",
  "existing": [ { "date": "YYYY-MM-DD", "description": "…", "amount": "…", "direction": "Debit|Credit" }, … ],
  "incoming": [ … ],
  "expected_matches": [ { "incoming_index": 0, "existing_index": 0, "layer": "Canonical" }, … ]
}
```

Amounts are **strings** (→ `Decimal`, never `f64`); `direction` `"Debit"`/`"Credit"`; `layer`
`"Canonical"`/`"Fuzzy"`. Exact bytes in [`contracts/golden-fixture.md`](./contracts/golden-fixture.md).

### Parity loader (`tests/parity.rs`, added; statement `CASES` untouched)

Dedup-only `#[derive(Deserialize)]` structs + a loader that maps each `{date, description, amount,
direction}` → `Transaction::new(NaiveDate::parse_from_str(date), description, Decimal::from_str(amount),
direction)`, and `expected_matches` → `Vec<CrossSourceMatch>`; then
`cross_source_dedup_matches_expected` asserts `cross_source_duplicates(existing, incoming) ==
expected_matches`. Imports `cross_source_duplicates`, `CrossSourceMatch`, `DedupLayer`, `Transaction` from
`kaname_core`. Money re-parsed via `Decimal::from_str` (never `f64`); dates via
`NaiveDate::parse_from_str`.

### Swift bridge test (`ios/Tests/CrossSourceDedupTests.swift`, NEW)

Builds `[Transaction]` (uniffi Record: `date` ISO `String`, `description`, `amount` `Decimal`,
`direction`), calls `crossSourceDuplicates(existing:incoming:)`, asserts a canonical match, a fuzzy match,
and a multiplicity survivor. `DedupLayer` → `.canonical`/`.fuzzy`; `CrossSourceMatch` →
`incomingIndex`/`existingIndex`/`layer`. Comments on their **own line above** the code (swift-format
`[Spacing]`). Requires `make core-xcframework` before `tuist generate`.

---

## State & lifecycle

Stateless and pure. `cross_source_duplicates(&existing, &incoming)` precomputes two `Vec<String>`
(normalised narrations), then per incoming row does at most two ordered scans of `existing` against a
`Vec<bool> consumed` — `O(|existing| · |incoming|)`, no persistence, no shared-state mutation. Row order
in the inputs is the only ordering input and both slices are borrowed `&` (never mutated). Repeated calls
on identical input yield identical results (SC-012). `normalize_narration` and `jaro`/`jaro_winkler` are
likewise pure single-pass/allocating helpers with no global state.

---

## Validation rules (traceability)

| Rule | Source |
|---|---|
| Pure in-memory matcher over two lists → set of `{incoming, existing, layer}`; survivors absent | FR-001, SC-001/010 |
| Read-only — never mutate/drop/reorder/merge/persist a row (borrows `&`) | FR-002, US5, SC-009 |
| Multiplicity — each existing consumed at most once; surplus repeats survive | FR-003, US3, SC-005 |
| Canonical before fuzzy; first unconsumed existing wins | FR-004, US6, SC-006/007 |
| Pure & deterministic; no network/clock/locale/global state; no file/DB/PDF | FR-005, SC-012 |
| Canonical = same date + amount + direction + 60-char normalised-narration prefix | FR-006, SC-001 |
| `normalize_narration` reproduces the web `normalise_narration`; 60-char prefix key | FR-007, SC-004 |
| Fuzzy = equal amount + direction, ±1-day window, Jaro-Winkler ≥ 0.92 | FR-008, SC-002/008 |
| 0.92 threshold inclusive; computed on the normalised narrations | FR-009, SC-002 |
| Hand-rolled Jaro-Winkler reproduces `rapidfuzz` byte-for-byte; **no new dep** | FR-010/023, SC-003/016 |
| Amount equality exact `Decimal` (`250.00`==`250.0`); direction explicit; never float; sim is `f64` not money | FR-011, SC-011 |
| Only L3+L4 ported; no DB/L1/L2/L5/SUPERSEDE/mutation/CSV/UI | FR-012, SC-016 |
| Reuse `Transaction`/`Decimal`/harness/bridge; no new dep or shared helper beyond matcher + 2 helpers | FR-013, SC-016 |
| Pure; no file/PDF read (operates on the two in-memory lists) | FR-014 |
| Reachable over UniFFI via `cross_source_duplicates`, mirroring `reconcile_statement` | FR-015, SC-014 |
| Zero network in the dedup path; privacy-egress gate covers it | FR-016/018, SC-015 |
| No telemetry/analytics/crash reporter added | FR-017 |
| Web engine pinned as source of truth (normaliser + L3/L4 + rapidfuzz) reproduced exactly | FR-019, SC-013 |
| Golden vectors: canonical, fuzzy (incl. 0.92 boundary), non-match, guards, multiplicity | FR-020, SC-013 |
| Synthetic/redacted fixture data only | FR-021 |
| Test-first (failing golden/parity precedes behaviour) | FR-022 |
| No secrets; Apache-2.0; no copyleft; no new runtime/dev dependency | FR-023, SC-016/017 |
| iOS Local Verification Gate + CI green | FR-024, SC-017 |
| No UI this slice (N/A); if added → HIG + a11y | FR-025 |
