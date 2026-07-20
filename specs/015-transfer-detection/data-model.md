# Phase 1 — Data Model: On-Device Transfer (Self-Transfer) Detection

**Feature**: `015-transfer-detection` | **Date**: 2026-07-20
**Scope**: The types and functions this slice introduces, reuses, and configures — all inside a **new top-level
`transfer` module** + its bridge. It adds **one pure matcher** (`detect_transfers`) with **two private helpers**
(`narration_similarity`, `score`), **one input record** (`TransferInput`), **one output record** (`TransferPair`),
**one constant** (`DATE_TOLERANCE_DAYS`), **one FFI wrapper**, **one golden fixture**, and **tests** — with **no new
runtime OR dev dependency**, **no `uniffi.toml` change**, and **no reader/`model.rs`/`base.rs` change**. It reuses
the shared `Direction` enum, the `rust_decimal::Decimal` money type, and the `chrono::NaiveDate` date type (both
ISO/base-10 custom types), the parity harness, and the UniFFI bridge. Money and the ±₹1 tolerance stay exact
`Decimal`; the only `f64` is the confidence `score` (it is not money).

---

## New types — `core/crates/kaname-core/src/transfer.rs`

### `TransferInput` (NEW) — `uniffi::Record` — one **input** row (the single pool)

```rust
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct TransferInput {
    pub id: String,
    pub account_id: String,
    pub is_credit_card: bool,
    pub date: NaiveDate,
    pub amount: Decimal,
    pub direction: Direction,
    pub description: String,
}
```

| Field | Rust type | Wire → Swift | Meaning |
|---|---|---|---|
| `id` | `String` | `String` → `id: String` | stable, opaque row identifier (also the final selection tiebreak) |
| `account_id` | `String` | `String` → `accountId: String` | opaque account identifier (the different-account guard) |
| `is_credit_card` | `bool` | `Bool` → `isCreditCard: Bool` | this leg is a credit-card account (faithful reduction of the web `account_type == "credit_card"` — the only use of account_type) |
| `date` | `NaiveDate` | `String` (ISO-8601) → `date: String` | the row's date; drives `date_diff` |
| `amount` | `Decimal` | `String` (base-10) → `amount: Decimal` | exact money magnitude; drives `amount_diff` (never a float) |
| `direction` | `Direction` | `Direction` → `direction` | `Debit` = outflow (anchor) / `Credit` = inflow (counterpart) |
| `description` | `String` | `String` → `description: String` | raw narration for `narration_similarity` (un-normalized) |

Derives `Debug/Clone/PartialEq/uniffi::Record` (mirrors `CrossSourceMatch`/`StatementCoverage`/`TransactionCoverage`).
It does **not** need serde: the parity harness builds it from typed rows, exactly as the dedup loader builds
`Transaction` (D2/D12).

### `TransferPair` (NEW) — `uniffi::Record` — one **output** detected pair

```rust
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct TransferPair {
    pub outflow_id: String,
    pub inflow_id: String,
    pub is_credit_card_payment: bool,
    pub score: f64,
}
```

| Field | Rust type | Wire → Swift | Meaning |
|---|---|---|---|
| `outflow_id` | `String` | `String` → `outflowId: String` | the anchor (Debit) leg id (web `transaction_id_a`) |
| `inflow_id` | `String` | `String` → `inflowId: String` | the counterpart (Credit) leg id (web `transaction_id_b`) |
| `is_credit_card_payment` | `bool` | `Bool` → `isCreditCardPayment: Bool` | true when **either** leg is a credit-card account (Credit Card Bill Payment vs Self Transfer) |
| `score` | `f64` | `Double` → `score: Double` | the web `_score` confidence metric (floored at 0.0, **not** capped at 1.0) — a float because it is **not** money |

Derives `Debug/Clone/PartialEq/uniffi::Record`. Like `CrossSourceMatch`, it does **not** derive serde: the parity
loader deserialises into a separate `ExpectedPair` row and constructs `TransferPair` values for comparison (D12). The
web `transfer_group_id` is **dropped** — a persistence field the platform owns (D3/D14).

### Constant (NEW, public)

```rust
pub const DATE_TOLERANCE_DAYS: i64 = 1; // the ±1-day date window (web fixed window; match_window_days override is out of scope)
```

The ±₹1.00 **amount** tolerance uses **`Decimal::ONE`** (the `rust_decimal` associated const) directly in the
matcher — **not** the `rust_decimal_macros::dec!` macro (`dec!` stays in tests only — D7).

### Reused type — `Direction` (from `model.rs`, unchanged)

```rust
pub enum Direction { Debit, Credit } // Debit = outflow (anchor), Credit = inflow (counterpart)
```

Reused as `TransferInput.direction`. No change to `model.rs`.

---

## New functions — `transfer.rs`

### `detect_transfers` (NEW, `pub`) — the pure single-pool matcher

```rust
pub fn detect_transfers(rows: &[TransferInput]) -> Vec<TransferPair>
```

**Input**: one **borrowed** slice `&[TransferInput]` — the single pool of already-parsed, still-unpaired rows for
one user (the platform scopes it). Not mutated.

**Output**: `Vec<TransferPair>` — the detected pairs, **ordered by the anchor's `(date, id)`**.

**Algorithm (exact web order — the pure port of `detect_pairs_for_user` + `_best_counterpart`, minus SQL — D6)**:

1. **Anchor set** — collect the indices of `Direction::Debit` rows, **sorted ascending by `(date, id)`**:
   `anchors.sort_by(|&i, &j| rows[i].date.cmp(&rows[j].date).then_with(|| rows[i].id.cmp(&rows[j].id)))`.
2. **Consumed vector** — `let mut consumed = vec![false; rows.len()];` (indexed by row **position**).
3. For each `a` in `anchors` (sorted): `if consumed[a] { continue; }`. Build the **candidate index set** — every
   `c` with **all** of:
   - `!consumed[c]`
   - `rows[c].account_id != rows[a].account_id`  *(different account)*
   - `rows[c].direction == Direction::Credit`     *(opposite direction / inflow)*
   - `(rows[a].date - rows[c].date).num_days().abs() <= DATE_TOLERANCE_DAYS`   *(±1 day, inclusive)*
   - `(rows[a].amount - rows[c].amount).abs() <= Decimal::ONE`                 *(±₹1.00, inclusive)*

   If the candidate set is **empty**, `continue`.
4. **Best candidate** — `min_by` over the candidates with the explicit comparator implementing the tuple
   **`(date_diff: i64, amount_diff: Decimal, -narration_similarity: f64, id: String)`** (lowest wins):

   ```rust
   let best = candidates.into_iter().min_by(|&i, &j| {
       let di = (rows[a].date - rows[i].date).num_days().abs();
       let dj = (rows[a].date - rows[j].date).num_days().abs();
       let ai = (rows[a].amount - rows[i].amount).abs();
       let aj = (rows[a].amount - rows[j].amount).abs();
       let si = narration_similarity(&rows[a].description, &rows[i].description);
       let sj = narration_similarity(&rows[a].description, &rows[j].description);
       di.cmp(&dj)                                   // smallest date_diff
           .then_with(|| ai.cmp(&aj))                // then smallest amount_diff (Decimal Ord)
           .then_with(|| sj.partial_cmp(&si).unwrap()) // then HIGHER similarity first (safe: finite in [0,1])
           .then_with(|| rows[i].id.cmp(&rows[j].id))  // then lowest id (unique → strict total order)
   }).unwrap(); // candidates non-empty (checked above)
   ```

5. **Claim + emit** — mark `consumed[a] = true; consumed[best] = true;` and push:

   ```rust
   TransferPair {
       outflow_id: rows[a].id.clone(),
       inflow_id: rows[best].id.clone(),
       is_credit_card_payment: rows[a].is_credit_card || rows[best].is_credit_card,
       score: score(date_diff, amount_diff, sim), // date_diff/amount_diff/sim for the chosen best
   }
   ```

6. **Output order** — pairs are pushed in anchor-iteration order → naturally ordered by anchor `(date, id)`.

- Uses only `std` (`Vec`, sort, `cmp`/`partial_cmp`), `chrono` (`NaiveDate` subtraction → `num_days`), and
  `rust_decimal` (`Decimal` arithmetic, `Decimal::ONE`). **No new dependency.**
- **Pure / deterministic / total** — never reads the clock; never panics (the two `unwrap`s are safe: candidates
  non-empty; similarity finite in `[0,1]` — D11). Identical input ⇒ identical output (the stable anchor sort + the
  unique-`id` total-order comparator make it order-independent).

**Invariants**

- **Anchor = outflows only, `(date, id)` order**; each row claimed **at most once** (shared `consumed`) (FR-003/005).
- **Candidate eligibility** = not-consumed ∧ different-account ∧ inflow ∧ ≤1-day ∧ ≤₹1.00 (all inclusive) (FR-004/006).
- **Selection** = min `(date_diff, amount_diff, -narration_similarity, id)`; higher similarity, then lowest id, wins
  ties (FR-007).
- **`is_credit_card_payment`** = OR of the two legs' `is_credit_card` (FR-009).
- **`score`** = `max(0, 1 − 0.2·date_diff − 0.2·amount_diff + 0.2·sim)`, floored at 0.0, not capped (FR-010).
- **Output** ordered by anchor `(date, id)` (FR-002, SC-008).

### `narration_similarity` (NEW, **private**) — token-level Jaccard (THE gotcha; distinct from de-dup)

```rust
fn narration_similarity(a: &str, b: &str) -> f64
```

**Definition (exact web `_narration_similarity` — D4)**: token-level **Jaccard** on the **raw lowercased,
whitespace-split** description. `0.0` if either string is empty **or** yields no tokens; else `|A ∩ B| / |A ∪ B|`
as f64 over the token **sets** (repeated tokens collapse). Lowercase into an owned `String`, build
`HashSet<&str>` from `split_whitespace()`, then divide the intersection count by the union count.

- **DISTINCT from `dedup::normalize_narration` + Jaro-Winkler.** It does **no** prefix/RRN/refnum stripping and is
  **set-Jaccard**, not character Jaro-Winkler. Must **not** call `normalize_narration` or reuse `dedup`'s
  `jaro`/`jaro_winkler` (FR-008).
- Total on blank input: whitespace-only description → no tokens → `0.0` (spec Edge Cases).

### `score` (NEW, **private**) — the web `_score` (floored at 0.0, not capped)

```rust
use rust_decimal::prelude::ToPrimitive;

fn score(date_diff: i64, amount_diff: Decimal, sim: f64) -> f64
```

**Definition (exact web `_score` — D5)**:
`(((1.0 - (0.2 * date_diff as f64)) - (0.2 * amount_diff_f64)) + (0.2 * sim)).max(0.0)` where
`amount_diff_f64 = amount_diff.to_f64().unwrap_or(0.0)`.

- **Exact Python left-to-right op order** — the parenthesisation is pinned so the IEEE-754 binary64 result is
  bit-identical to the web engine and reproducible across x86_64/arm64.
- **Floored at 0.0, NOT capped at 1.0** — live golden pairs score `1.0285714285714285` / `1.05` / `1.2` /
  `1.0333333333333334` (all > 1.0).
- `amount_diff` is exact `Decimal` money converted via `rust_decimal`'s `ToPrimitive::to_f64` (the only `f64`
  crossing point for money — the score itself is not money).

---

## FFI wrapper — `ffi.rs` (EXTEND)

```rust
use crate::transfer::{TransferInput, TransferPair}; // TYPES only — not the pure fn (name-clash — D9)

#[uniffi::export]
pub fn detect_transfers(rows: Vec<TransferInput>) -> Vec<TransferPair> {
    crate::transfer::detect_transfers(&rows)
}
```

Takes an **owned** `Vec` (UniFFI convention); calls the pure function with a borrowed slice `&rows`. The wrapper
name `detect_transfers` **shadows** the pure function, so `ffi.rs` imports only the transfer **types** and calls the
pure fn **fully-qualified** (D9). Mirrors `cross_source_duplicates` / `compute_coverage`. The already-registered
`Decimal`/`NaiveDate` custom types carry `amount`/`date` across; no `uniffi.toml` change (D8).

## Crate re-exports — `lib.rs` (EXTEND)

```rust
pub mod transfer;
// …
pub use ffi::{/* …existing… */ detect_transfers};
pub use transfer::{TransferInput, TransferPair};
```

Re-exports the **FFI** `detect_transfers` (the bridge wrapper) + the transfer **types**. The pure
`transfer::detect_transfers` is **not** re-exported at the crate root (name clash — D9); `tests/parity.rs` uses the
FFI-exported one via `kaname_core::detect_transfers`. This matches the `coverage`/`dedup` re-export shape exactly
(types + helpers from the module; the clashing function only from `ffi`).

---

## Parity fixture types — `tests/parity.rs` (EXTEND, additive)

A **new, transfer-only** loader (the statement `Fixture`/`Expected`/`CASES`, the dedup loader, and the coverage
loader are untouched):

```rust
#[derive(Deserialize)]
struct TransferFixture {
    rows: Vec<TransferInputRow>,
    expected_pairs: Vec<ExpectedPair>,
}

#[derive(Deserialize)]
struct TransferInputRow {
    id: String,
    account_id: String,
    is_credit_card: bool,
    date: String,
    amount: String,
    direction: Direction,
    description: String,
}

#[derive(Deserialize)]
struct ExpectedPair {
    outflow_id: String,
    inflow_id: String,
    is_credit_card_payment: bool,
    score: f64,
}

#[test]
fn transfer_detection_matches_expected() {
    let path = format!(
        "{}/../../../fixtures/transfer/basic.json",
        env!("CARGO_MANIFEST_DIR")
    );
    let raw = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
    let fx: TransferFixture =
        serde_json::from_str(&raw).unwrap_or_else(|e| panic!("parse {path}: {e}"));
    let rows: Vec<TransferInput> = fx
        .rows
        .iter()
        .map(|r| TransferInput {
            id: r.id.clone(),
            account_id: r.account_id.clone(),
            is_credit_card: r.is_credit_card,
            date: NaiveDate::parse_from_str(&r.date, "%Y-%m-%d").unwrap(),
            amount: Decimal::from_str(&r.amount).unwrap(),
            direction: r.direction,
            description: r.description.clone(),
        })
        .collect();
    let got = detect_transfers(rows);
    let want: Vec<TransferPair> = fx
        .expected_pairs
        .iter()
        .map(|p| TransferPair {
            outflow_id: p.outflow_id.clone(),
            inflow_id: p.inflow_id.clone(),
            is_credit_card_payment: p.is_credit_card_payment,
            score: p.score,
        })
        .collect();
    assert_eq!(got, want, "transfer detection must equal the golden expected_pairs");
}
```

- `date` is re-parsed via `NaiveDate::parse_from_str`; `amount` via `Decimal::from_str` (**never** a float);
  `direction` deserialises into `Direction` (`"Debit"`/`"Credit"`) via its serde derives; `score` deserialises as an
  `f64` and is compared with **exact `==`** (the port reproduces the web bits — D5/D12).
- Imports `detect_transfers`, `TransferInput`, `TransferPair`, `Direction` from `kaname_core` (alongside the
  existing statement + dedup + coverage imports). `detect_transfers` resolves to the **FFI-exported** wrapper
  (owned `Vec`) — D9.

---

## Swift surface (generated by UniFFI) — `ios/Tests/TransferDetectionTests.swift` consumes

| Rust | Swift (generated) |
|---|---|
| `struct TransferInput { id, account_id, is_credit_card, date: NaiveDate, amount: Decimal, direction: Direction, description }` | `TransferInput(id: String, accountId: String, isCreditCard: Bool, date: String, amount: Decimal, direction: Direction, description: String)` |
| `struct TransferPair { outflow_id, inflow_id, is_credit_card_payment, score: f64 }` | `TransferPair(outflowId: String, inflowId: String, isCreditCardPayment: Bool, score: Double)` |
| `fn detect_transfers(rows: Vec<TransferInput>) -> Vec<TransferPair>` | `detectTransfers(rows: [TransferInput]) -> [TransferPair]` |
| `enum Direction { Debit, Credit }` | `.debit` / `.credit` |

`amount` crosses as a base-10 `String` → Swift `Decimal` (never a float); `date` as an ISO-8601 `String`; `score`
as a native `Double`. Field/case names are lower-camel-cased by UniFFI.

---

## Relationship to the shipped checks (the reuse contract)

| | `dedup::cross_source_duplicates` | `coverage::compute_coverage` | `transfer::detect_transfers` |
|---|---|---|---|
| Input | `&[Transaction]` × 2 | `today` + two fact slices | **one** `&[TransferInput]` (single pool) |
| Purity | pure/deterministic/total | pure/deterministic/total | pure/deterministic/total |
| Money | exact `Decimal` (similarity is `f64`) | none (dates/states) | exact `Decimal` + `Decimal::ONE` tolerance (score is `f64`, not money) |
| Similarity | `normalize_narration` + **Jaro-Winkler** | none | **raw-token Jaccard** (`narration_similarity`, distinct — D4) |
| Result | `Vec<CrossSourceMatch>` | `Vec<MonthCoverage>` (always 24) | `Vec<TransferPair>` (0..N, anchor-ordered) |
| FFI wrapper | `cross_source_duplicates` (name-clash → types-only import) | `compute_coverage` (name-clash → types-only import) | `detect_transfers` (name-clash → types-only import — D9) |
| New dependency | none (hand-rolled Jaro-Winkler) | none (`std::HashMap` + `chrono::Datelike`) | none (`std` sets + `chrono` + `rust_decimal` `ToPrimitive`) |
| Module | extends `dedup.rs` | **new** `coverage.rs` | **new** `transfer.rs` (sibling) |

The web `transfer_detector.py`'s **DB layer** (persisting `transfer_group_id`/`is_transfer`, category
get-or-create, audit events, `_claim_pair` race handling, cross-user filter, `match_window_days` override) is **not**
ported — the platform owns every side effect (spec Assumptions, Out of Scope, FR-014/016, D14). The core only
**returns** the detected pairs.
