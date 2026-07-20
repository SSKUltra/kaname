# Phase 0 — Research: On-Device Transfer (Self-Transfer) Detection (the pure `transfer_detector.py` port; zero new deps)

**Feature**: `015-transfer-detection` | **Date**: 2026-07-20
**Method**: The web engine is the source of truth. Its `app/services/ingestion/transfer_detector.py` — the pure
helpers `_narration_similarity` and `_score`, the ±1-day / ±₹1.00 tolerance envelope, and the outflow-anchored
greedy selection (`detect_pairs_for_user` + `_best_counterpart`, minus all SQL) — was **read as ground truth**. The
ported helpers and the greedy matcher were **verified** against a throwaway simulation of the locked algorithm on a
nine-scenario pool (run, then discarded — repo left clean; see **Verification**). Every decision below is a
faithful port or a justified, verified idiomatic mapping.

All NEEDS CLARIFICATION are resolved; the approach was **locked by the requester** and confirmed here with
evidence. **Headline finding: this slice needs no new runtime OR dev dependency and no new shared engine helper
beyond the matcher, its two private helpers, and its two input/output types — it adds a new top-level `transfer.rs`
module and is exposed exactly like `cross_source_duplicates`/`compute_coverage`. The three non-mechanical points are
(D4) the token-Jaccard `narration_similarity` that must NOT be conflated with the de-dup slice's
`normalize_narration` + Jaro-Winkler, (D5) the `_score` that is floored at 0.0 but NOT capped at 1.0 and whose exact
Python op order is preserved so the f64 bits match, and (D9) the `detect_transfers` FFI-wrapper name-clash handled
exactly as `compute_coverage` (014) was.**

---

## D1 — New top-level `transfer.rs` module (sibling to `dedup.rs` / `coverage.rs`)

**Decision**: Add a **new top-level module** `core/crates/kaname-core/src/transfer.rs` (wired with `pub mod
transfer;` in `lib.rs`), holding the `TransferInput` input record, the `TransferPair` output record,
`DATE_TOLERANCE_DAYS = 1`, the pure `detect_transfers` matcher, the private `narration_similarity` + `score`
helpers, and unit tests. Reuse, unchanged: the shared `chrono::NaiveDate` date type, the `rust_decimal::Decimal`
money type, the shared `Direction` enum (`model.rs`), the parity harness (`tests/parity.rs`), the UniFFI bridge
(`ffi.rs` + `uniffi.toml`), and the privacy-egress gate + CI. The one FFI export lives in `ffi.rs`, as
`cross_source_duplicates` / `compute_coverage` / `reconcile_statement` do.

**Rationale**: Transfer pairing is a **distinct ingestion-signal concern** from parsing (`statement/*`),
reconciliation (`statement/reconcile.rs`), the balance-chain (`statement/balance_chain.rs`), cross-source de-dup
(`dedup.rs`), and the coverage map (`coverage.rs`). A dedicated sibling module keeps the diff surgical and
self-contained and mirrors how each prior check got its own home. The requester's locked design specifies "a pure
sibling of `dedup.rs` / `coverage.rs`", which this follows exactly.

**Alternatives**: Folding transfer into `dedup.rs` — rejected: unrelated logic, and dangerously so — transfer's
`narration_similarity` (token-Jaccard) must not be confused with `dedup::normalize_narration` + Jaro-Winkler (D4).
Folding into `statement/` — rejected: it is not a statement reader and does not use the `ParsedStatement`/`Word`
machinery. A submodule under a new `analytics/` tree — rejected: unnecessary nesting for one matcher + two helpers
+ two types.

---

## D2 — `TransferInput` input record (single pool; reuse `Direction`; `is_credit_card` is the faithful `account_type` reduction)

**Decision**: One input record, deriving the codebase-standard set plus `uniffi::Record`:

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

The matcher takes **one** list `&[TransferInput]` — a **single-pool** API, **not** a two-list API (FR-001). It
reuses the shared `Direction` enum (`model.rs`: `Debit` = outflow, `Credit` = inflow) rather than introducing a new
polarity type. **`is_credit_card` is the faithful reduction of the web `account_type == "credit_card"`** — the
**only** use of the web's `account_type`, collapsed to the single boolean the pure logic actually needs (it drives
`is_credit_card_payment`, D6). `id` and `account_id` are opaque platform-supplied stable identifiers (`String`);
`amount` is the shared exact `Decimal` money type; `date` is the shared `NaiveDate`; `description` is the raw
narration (un-normalized — D4).

**Rationale**: This is the minimal, faithful shape of "one already-parsed, still-unpaired transaction" (spec Key
Entities). Reusing `Direction` keeps polarity consistent with every reader and the de-dup/coverage slices. Reducing
`account_type` (a web string enum with many values) to `is_credit_card: bool` is exact for the pure logic: the only
thing the pairing needs from account type is "is this leg a credit card?" (the Credit Card Bill Payment vs Self
Transfer split, D6). Deriving `Debug/Clone/PartialEq/uniffi::Record` matches `CrossSourceMatch` / `StatementCoverage`
(no serde needed on the input — the parity loader builds it from typed rows, D12).

**Alternatives**: Carrying the full `account_type` string — rejected: the pure logic never branches on any value
other than "credit_card"; a bool is the honest reduction and avoids a stringly-typed enum crossing the bridge.
Reusing `Transaction` (`model.rs`) directly — rejected: it lacks `id`, `account_id`, and `is_credit_card`, which
the matcher requires.

---

## D3 — `TransferPair` output record (`outflow_id`/`inflow_id` map the web `transaction_id_a`/`_b`; `transfer_group_id` dropped; `score` is `_score`)

**Decision**: One output record:

```rust
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct TransferPair {
    pub outflow_id: String,
    pub inflow_id: String,
    pub is_credit_card_payment: bool,
    pub score: f64,
}
```

Maps the web `TransferPair.transaction_id_a` → **`outflow_id`** (the anchor/Debit leg) and `transaction_id_b` →
**`inflow_id`** (the counterpart/Credit leg). The web `transfer_group_id` is **dropped** — it is a persistence
concern the platform owns (FR-016, D14). `is_credit_card_payment` is the web "Credit Card Bill Payment" vs "Self
Transfer" split (D6). `score` is the web `_score` **f64** (D5).

**Rationale**: `outflow_id`/`inflow_id` name the two legs by their role (anchor vs counterpart) rather than the
web's positional `_a`/`_b`, which is clearer on-device and matches the spec's "outflow id / inflow id" wording
(FR-002). Dropping `transfer_group_id` keeps the pure output free of persistence identity (the core never persists
— FR-014/016). Derives mirror `CrossSourceMatch` — but see D12: `TransferPair` does **not** need serde (the parity
loader deserialises into a separate `ExpectedPair` row and constructs `TransferPair` values for comparison, exactly
as the dedup loader does for `CrossSourceMatch`).

**Alternatives**: Keeping the positional `transaction_id_a`/`_b` names — rejected: on-device the legs have fixed
roles (outflow anchor, inflow counterpart), so role names are clearer and match the spec. Emitting a
`transfer_group_id` — rejected: it is a DB/persistence field (spec Out of Scope, FR-016).

---

## D4 — `narration_similarity` is token-level Jaccard on the raw lowercased description (THE key porting gotcha; DISTINCT from de-dup)

**Decision**: A **private** `fn narration_similarity(a: &str, b: &str) -> f64` — the exact port of the web
`_narration_similarity`: **token-level Jaccard** on the **raw lowercased, whitespace-split** description. Returns
`0.0` if either string is empty **or** yields no tokens; else `|A ∩ B| / |A ∪ B|` as f64 over the token **sets**:

```rust
fn narration_similarity(a: &str, b: &str) -> f64 {
    if a.is_empty() || b.is_empty() {
        return 0.0;
    }
    let ta: HashSet<&str> = a.to_lowercase(); /* split_whitespace().collect() */
    let tb: HashSet<&str> = b.to_lowercase(); /* split_whitespace().collect() */
    if ta.is_empty() || tb.is_empty() {
        return 0.0;
    }
    let inter = ta.intersection(&tb).count();
    let union = ta.union(&tb).count();
    inter as f64 / union as f64
}
```

*(Sketch — the implementation lowercases into an owned `String` first, then builds `HashSet<&str>` from
`split_whitespace()`; the whitespace-only case is caught by the empty-token-set guard.)*

**This is DELIBERATELY DISTINCT from `dedup::normalize_narration` + Jaro-Winkler** (slice 013). The de-dup measure
strips channel prefixes (POS/UPI/NEFT/…), `RRN…` tokens, and trailing reference numbers, collapses whitespace, and
then computes a **character-level Jaro-Winkler** similarity with a 0.92 threshold. Transfer's measure does **none**
of that pre-processing: it splits the **raw lowercased** string on whitespace and computes **set Jaccard** over the
tokens. The two must **not** be conflated (FR-008, spec Assumptions). In particular, `narration_similarity` must
**not** call `normalize_narration`, and must **not** reuse the `jaro`/`jaro_winkler` helpers in `dedup.rs`.

**Rationale**: This is a 1:1 port of the pinned web helper. Jaccard-over-raw-tokens is what the web `_score`
tiebreak and the confidence formula are calibrated against; any pre-processing would change the numbers and break
parity. The empty/no-token guard reproduces the web's "0.0 when either side is empty" behaviour and keeps the
function total on blank descriptions (spec Edge Cases).

**Verified**: On the golden pool the token-Jaccard values are exactly `1/7`, `3/5`, `1/4`, `1/1`, `1/6` for the
five pairing scenarios (Verification below) — matching a hand computation and the web helper.

**Alternatives**: Reusing the de-dup normaliser/Jaro-Winkler — **rejected** (parity break; the explicit gotcha).
Multiset (token-frequency) Jaccard — rejected: the web uses **set** semantics (`set(a.split())`), so repeated
tokens collapse. Case-sensitive tokens — rejected: the web lowercases first.

---

## D5 — `score` is the web `_score`: floored at 0.0, NOT capped at 1.0; exact Python op order for bit-identical f64

**Decision**: A **private** `fn score(date_diff: i64, amount_diff: Decimal, sim: f64) -> f64` — the exact port of
the web `_score`:

```rust
use rust_decimal::prelude::ToPrimitive;

fn score(date_diff: i64, amount_diff: Decimal, sim: f64) -> f64 {
    let amount_diff_f64 = amount_diff.to_f64().unwrap_or(0.0);
    (((1.0 - (0.2 * date_diff as f64)) - (0.2 * amount_diff_f64)) + (0.2 * sim)).max(0.0)
}
```

- **Floored at 0.0 but NOT capped at 1.0.** The web `_score` is `max(0, 1 − 0.2·date_diff − 0.2·amount_diff +
  0.2·sim)` with **no upper clamp**. Verified against live ground truth: a same-day/same-amount pair with narration
  overlap scores **`1.0285714285714285`** (> 1), and other golden pairs score **`1.05`**, **`1.2`**,
  **`1.0333333333333334`** — all above 1.0 (FR-010, spec US5, Verification below). Capping at 1.0 would break
  parity.
- **Exact Python left-to-right op order** — `((1.0 - (0.2*date_diff)) - (0.2*amount_diff_f64)) + (0.2*sim)` — so
  the IEEE-754 binary64 result is **bit-identical** to the web engine (and reproducible across x86_64/arm64). The
  operations are simple, non-contracted multiplies/adds; associativity matters, so the parenthesisation is pinned.
- **`amount_diff` is a `Decimal`** (exact money) converted with `ToPrimitive::to_f64` (from the already-present
  `rust_decimal`), `unwrap_or(0.0)` — mirroring the web `float(amount_diff)`. `date_diff` is an `i64` widened with
  `as f64`. `sim` is the f64 from D4.

**Rationale**: The score is a **confidence metric, not money** (Constitution II governs money) — a float is
correct, and it must reproduce the web `_score` bits exactly for parity (FR-011). Preserving the Python op order is
the discipline that makes the exact-f64 `==` parity assertion (D12) safe across compilers/architectures.

**Verified (bit-identity + round-trip)**: A throwaway Rust reimplementation of this exact expression produced
values **bit-identical** to the Python `_score`, and each value's shortest decimal (serde_json's `ryu` formatter)
**round-trips** back to the same f64 (`parse(stored) == computed`). So the fixture-stored decimals parse to exactly
the bits `detect_transfers` computes, and the parity `assert_eq!` (exact `f64` `==`) holds (Verification below).

**Alternatives**: Representing the score as `Decimal` — rejected: it is not money, and the web `_score` is an f64;
a `Decimal` would not reproduce the pinned bits. Capping at 1.0 or normalising to [0,1] — rejected: the web does
neither (live pairs exceed 1.0). Reordering the arithmetic "for readability" — rejected: could change the low bits
and break exact-f64 parity.

---

## D6 — `detect_transfers`: anchor-sort, consumed-vector greedy claim, candidate filter, `min_by` selection tuple

**Decision**: `pub fn detect_transfers(rows: &[TransferInput]) -> Vec<TransferPair>` — the faithful pure port of
`detect_pairs_for_user` + `_best_counterpart`, minus all SQL:

1. **Anchor set** = the **indices of `Direction::Debit`** (outflow) rows, **sorted ascending by `(date, id)`**
   (`sort_by` / `sort_by_key` on `(rows[i].date, rows[i].id.clone())`).
2. **Consumed tracking** = `let mut consumed = vec![false; rows.len()];` indexed by row **position**.
3. **For each anchor index** (in sorted order): `if consumed[a] { continue; }`. Build the **candidate set** = every
   row index `c` that is **(a)** not consumed, **(b)** `rows[c].account_id != rows[a].account_id`, **(c)**
   `rows[c].direction == Direction::Credit`, **(d)** `(rows[a].date - rows[c].date).num_days().abs() <=
   DATE_TOLERANCE_DAYS`, **(e)** `(rows[a].amount - rows[c].amount).abs() <= Decimal::ONE`. If **empty**, continue.
4. **Select the best candidate** = **min by the tuple `(date_diff: i64, amount_diff: Decimal, -sim: f64, id:
   String)`** — implemented via `min_by` with an explicit comparator: `date_diff.cmp(&…)` then
   `amount_diff.cmp(&…)` then **higher-similarity-first** (`sj.partial_cmp(&si).unwrap()`, safe — similarities are
   finite in `[0,1]`) then **`id` ascending** (`rows[i].id.cmp(&rows[j].id)`).
5. **Claim + emit**: mark **both** anchor and counterpart `consumed`; push `TransferPair { outflow_id:
   rows[a].id.clone(), inflow_id: rows[cp].id.clone(), is_credit_card_payment: rows[a].is_credit_card ||
   rows[cp].is_credit_card, score: score(date_diff, amount_diff, sim) }`.
6. **Output order**: pairs are pushed in anchor-iteration order, so they are naturally ordered by anchor `(date,
   id)` (FR-002, SC-008).

**Rationale**: A direct transcription of the pinned web loop. Iterating a **stably-sorted anchor set** and marking
a shared `consumed` vector reproduces greedy single-claim (each row paired at most once) and the "earliest anchor
by `(date, id)` wins a contested inflow" rule (FR-003/005, US6). The candidate guards (b)–(e) reproduce the
opposite-direction, different-account, ±1-day, ±₹1 eligibility (FR-004/006). The `min_by` comparator reproduces the
`(date_diff, amount_diff, -narration_similarity, id)` "lowest wins" tuple (FR-007): note that including the unique
`id` as the final key makes the comparator a **strict total order** over candidates, so `min_by`'s "returns the
last equal element" behaviour is irrelevant (there are never two equal candidates) — matching Python `min`'s
first-wins outcome. `is_credit_card_payment` is the logical OR of the two legs' `is_credit_card` (FR-009, D6-flag).

**Verified**: On the golden pool this yields exactly 5 pairs in anchor `(date, id)` order and 4 no-pair guards
(Verification below; SC-001..SC-008).

**Alternatives**: Removing matched rows from a working list instead of a `consumed` vector — rejected: index-based
`consumed` is O(1), preserves original positions for the id tiebreak, and mirrors the web's claim semantics.
Sorting candidates and taking the first — rejected: `min_by` with the explicit comparator is the literal tuple and
avoids allocating/sorting a candidate vector per anchor. Using `partial_cmp(...).unwrap()` on the whole tuple —
rejected: only the similarity term is an f64; keeping `date_diff`/`amount_diff`/`id` on their `Ord` `cmp` and
unwrapping `partial_cmp` **only** for the finite-in-`[0,1]` similarity is the minimal, panic-safe surface.

---

## D7 — Tolerances: `DATE_TOLERANCE_DAYS = 1` and `Decimal::ONE` (not `dec!`); both bounds inclusive

**Decision**: Export/keep `const DATE_TOLERANCE_DAYS: i64 = 1;`. Use **`Decimal::ONE`** (the `rust_decimal`
associated constant) for the ±₹1.00 amount tolerance in the library code — **not** the `rust_decimal_macros::dec!`
macro. `dec!` stays confined to **tests** only. Both bounds are **inclusive**: a counterpart exactly **1 day** away
(`num_days().abs() <= 1`) or exactly **₹1.00** away (`.abs() <= Decimal::ONE`) is **within** tolerance; 2 days or
₹1.01 is outside (spec Edge Cases, SC-002).

**Rationale**: `Decimal::ONE` is a zero-cost associated const already in the crate — using it keeps the library
free of the `rust_decimal_macros` dev-macro in non-test code and expresses "±₹1.00" exactly (no float). Keeping
`dec!` to tests matches the codebase convention (readers/`model.rs` use `dec!` only under `#[cfg(test)]`). The
inclusive `<=` comparisons reproduce the web's `abs(...) <= 1` guards.

**Alternatives**: `dec!(1)` in the library — rejected: pulls a dev-macro into shipped code needlessly; `Decimal::ONE`
is the idiomatic constant. `Decimal::from(1)` / `"1".parse()` — rejected: `Decimal::ONE` is clearer and const.
Exclusive bounds — rejected: the web (and spec SC-002) treat the boundary as **within** tolerance.

---

## D8 — Types cross UniFFI via the already-registered custom types (`Decimal` ↔ string, `NaiveDate` ↔ ISO string); no `uniffi.toml` change

**Decision**: Reuse the **already-registered** `uniffi::custom_type!(Decimal, String, …)` (base-10 string ↔ Swift
`Decimal`) and `uniffi::custom_type!(NaiveDate, String, …)` (ISO-8601 `%Y-%m-%d` string ↔ Swift `String`) in
`ffi.rs`. `TransferInput.amount` crosses as an exact base-10 **string** (never a float); `TransferInput.date`
crosses as an ISO string; `TransferPair.score` crosses as a native **`f64`/`Double`** (it is a confidence metric,
not money). `id` / `account_id` / `description` are `String`; `is_credit_card` / `is_credit_card_payment` are
`bool`; `direction` reuses the `Direction` `uniffi::Enum`. **No new custom type, no `uniffi.toml` change.**

**Rationale**: Money crossing as an exact string is the constitutional rule already implemented for every reader and
the de-dup slice; reuse it. The score is deliberately the one `f64` on the bridge because it is not money (D5). The
`Direction` enum already crosses (it is the shared polarity type). This keeps the bridge change to "one function +
two records" with zero new machinery.

**Alternatives**: A new custom type for the score — rejected: `f64` crosses natively and is the right type for a
confidence metric. Crossing `amount` as a float — **forbidden** (Constitution II).

---

## D9 — FFI-wrapper name-clash: import transfer **types only**, call the pure fn fully-qualified (the `compute_coverage`/`cross_source_duplicates` precedent)

**Decision**: The exported bridge function is named `detect_transfers`, which **shadows** the pure
`transfer::detect_transfers`. To avoid the clash, `ffi.rs` imports only the transfer **types**
(`use crate::transfer::{TransferInput, TransferPair};`) — **not** the pure function — and calls it fully-qualified:

```rust
#[uniffi::export]
pub fn detect_transfers(rows: Vec<TransferInput>) -> Vec<TransferPair> {
    crate::transfer::detect_transfers(&rows)
}
```

The FFI takes an **owned** `Vec` (UniFFI passes owned collections) and calls the pure function with a borrowed slice
`&rows` — mirroring how `cross_source_duplicates` (ffi) wraps `crate::dedup::cross_source_duplicates(&existing,
&incoming)` and `compute_coverage` (ffi) wraps `crate::coverage::compute_coverage(today, &statements,
&transactions)`. `lib.rs` re-exports **only the FFI wrapper** at the crate root (`pub use ffi::detect_transfers;`)
plus the transfer **types** (`pub use transfer::{TransferInput, TransferPair};`). The pure
`transfer::detect_transfers` is **not** re-exported at the crate root (name clash) — `tests/parity.rs` and Swift use
the FFI-exported one via `kaname_core::detect_transfers`.

**Rationale**: This is exactly the pattern 013/014 established (`pub use ffi::cross_source_duplicates;` /
`pub use ffi::compute_coverage;`, with the pure functions deliberately **not** re-exported and the FFI module
importing only the types). Two crate-root `pub use` items named `detect_transfers` would be a hard `E0252`
name-clash; importing types-only and re-exporting the FFI wrapper is the working, precedent-matching resolution.
The requester's locked design fixes the exported Swift name as `detectTransfers`, which this preserves.

**Alternatives**: Re-exporting the pure `transfer::detect_transfers` at the crate root **too** — rejected:
duplicate-name compile error, and it diverges from the 013/014 precedent. Aliasing one under a different name —
rejected: the locked design fixes the name; aliasing would confuse the Swift surface. Making the pure fn take an
owned `Vec` — rejected: the pure signature is `&[TransferInput]` (borrow; no ownership needed), and the FFI wrapper
adapts the owned `Vec` to a slice exactly as the two precedents do.

---

## D10 — No new dependency (`std` + `rust_decimal`'s `ToPrimitive`); the score is the only `f64` and it is not money

**Decision**: The matcher uses only `std` (`Vec`, `HashSet`, slice sort, `str::to_lowercase` /
`str::split_whitespace`, `cmp`/`partial_cmp`), `chrono` (`NaiveDate` subtraction → `num_days`), `rust_decimal`
(`Decimal` arithmetic, `Decimal::ONE`, and `prelude::ToPrimitive::to_f64` for the score) — **all already in the
graph**. **No new runtime OR dev dependency.** The token-Jaccard and the score are **hand-rolled**. Money and the
±₹1 tolerance stay exact `Decimal`; the only `f64` is the confidence `score` (D5) — which is not money.

**Rationale**: FR-013/024 / SC-013 require zero new dependencies. `std` + `chrono` + `rust_decimal` suffice; unlike
013 (which hand-rolled Jaro-Winkler to avoid `rapidfuzz`), transfer needs nothing beyond std sets and the
already-present decimal/date crates. `ToPrimitive` is a `rust_decimal` prelude trait — importing it adds no crate.

**Alternatives**: A similarity/regex/date-math crate — rejected: unnecessary; the raw-token Jaccard is a few lines
of std. Pulling `rust_decimal_macros::dec!` into library code — rejected (D7): `Decimal::ONE` avoids it.

---

## D11 — Purity, determinism, totality (never reads the clock; the one `unwrap` is provably safe)

**Decision**: `detect_transfers`, `narration_similarity`, and `score` are **pure, deterministic, and total**: no
network, no wall-clock, no locale, no global mutable state, no file/DB/PDF I/O. Empty input, or input with **no
outflows**, yields an empty `Vec` (no panic). The single `unwrap` on the comparator's similarity term
(`sj.partial_cmp(&si).unwrap()`) is **provably safe**: similarities come from D4 and are always finite in `[0,1]`
(a ratio of non-negative counts, or `0.0`), so `partial_cmp` never returns `None`.

**Rationale**: Determinism is a Constitution gate (Principle II) and a correctness property of the whole feature
(FR-012, spec US3/US6): two runs (or two devices) over the same rows must produce identical pairs. Because the
anchor set is **stably sorted** by `(date, id)` and the selection comparator is a **strict total order** (the unique
`id` breaks every tie), the result is fully determined by `rows` and is byte-identical across runs — independent of
input order and of `HashSet` iteration order (the sets are only used for `intersection`/`union` **counts**, never
iterated into output). Empty/no-outflow input never enters the claim branch.

**Verified**: Re-running the golden pool yields identical output; empty and no-outflow inputs yield 0 pairs
(Verification below; SC-009).

**Alternatives**: Reading `chrono::Local::now()` — **forbidden** (Constitution II; the matcher takes no clock).
Returning a `Result` — rejected: the function is total; a `Vec` is the honest type. `unwrap`-ing a whole-tuple
`partial_cmp` — rejected (D6): only the similarity term needs `partial_cmp`, and it is finite by construction.

---

## D12 — New golden-fixture **shape** under `fixtures/transfer/`; the parity loader is additive; exact-f64 comparison

**Decision**: Introduce a **new fixture shape** `fixtures/transfer/basic.json`:

```jsonc
{
  "_comment": "…provenance + scenario notes (synthetic, no real data)…",
  "rows": [ { "id", "account_id", "is_credit_card": bool, "date": "YYYY-MM-DD",
              "amount": "<string>", "direction": "Debit|Credit", "description" } ],
  "expected_pairs": [ { "outflow_id", "inflow_id", "is_credit_card_payment": bool, "score": <number> } ]
}
```

Add a **new, transfer-only** loader + one test (`transfer_detection_matches_expected`) to `tests/parity.rs`; the
statement `Fixture`/`Expected`/`CASES`, the dedup loader/test, and the coverage loader/test are **untouched**. The
loader deserialises into typed rows (`TransferInputRow { id, account_id, is_credit_card: bool, date: String, amount:
String, direction: Direction, description: String }`, `ExpectedPair { outflow_id, inflow_id, is_credit_card_payment:
bool, score: f64 }`), parses `date` via `NaiveDate::parse_from_str(_, "%Y-%m-%d")` and `amount` via
`Decimal::from_str` (never a float), builds the `Vec<TransferInput>` pool, calls `detect_transfers`, and asserts the
returned `Vec<TransferPair>` **equals** the `expected_pairs`. **Amounts are strings** (re-parsed to `Decimal`);
**`direction` is `Debit`/`Credit`**; **`score` is a JSON number** stored at full round-trippable f64 precision and
compared with **exact `==`** (the arithmetic is simple, non-contracted, and reproducible across x86_64/arm64 — D5;
the fixture pins the bits).

**Rationale**: The matcher's input is a **single row list** (not a statement, not a two-list pair, not a `today` +
fact lists), so it needs a shape distinct from the per-statement `lines`/`full_text`/`expected.rows`, the dedup
`existing`/`incoming`/`expected_matches`, and the coverage `today`/`statements`/`transactions`/`expected_months`
schemas — exactly as each prior slice added its own shape under `fixtures/…`. Storing amounts as strings and
re-parsing keeps money off `f64`; storing the score as a JSON number lets serde_json parse it to the exact f64 bits
`detect_transfers` computes (round-trip verified — D5, Verification). The **single pool** exercises all nine
acceptance scenarios (5 produce pairs, 4 are guards that produce none), with **amounts per-scenario-isolated** so
greedy claiming never crosses scenarios (Verification).

**Alternatives**: Storing the score as a string and re-parsing — unnecessary: a JSON number round-trips exactly via
`ryu`/`serde_json` (verified); a number is the natural, human-readable form for a confidence metric (contrast money,
which stays a string). Comparing the score with an epsilon tolerance — rejected: the port reproduces the web bits
exactly (D5), so exact `==` is the correct, strictest parity assertion. Splitting the nine scenarios across nine
fixtures — rejected: one isolated pool is enough and matches the "single pool" nature of the matcher.

---

## D13 — Swift bridge test mirrors the `CoverageTests` / `CrossSourceDedupTests` precedent

**Decision**: `ios/Tests/TransferDetectionTests.swift` (Swift Testing, `import KanameCore`) constructs a
`[TransferInput]` (amounts via `Decimal(string:locale:)` with `en_US_POSIX`, dates as ISO strings, `direction`
`.debit`/`.credit`, `isCreditCard` bools), calls `detectTransfers(rows:)`, and asserts the returned `[TransferPair]`
— the camelCased fields `outflowId` / `inflowId` / `isCreditCardPayment` / `score` (input field `isCreditCard`). It
asserts a self-transfer pair (non-card, `isCreditCardPayment == false`) and a credit-card-payment pair (`==
true`), and reads a `score`. Any comment sits on its **own line above** the code (swift-format `[Spacing]` forbids
trailing inline `//`). Requires `make core-xcframework` **before** `tuist generate` (baked into `make ios-gen`).

**Rationale**: Mirrors how `CoverageTests`/`CrossSourceDedupTests`/`ReconcileTests` prove the bridge surface. It is
a **bridge smoke test** (the exhaustive nine-scenario parity is pinned on the Rust side by the golden harness), so a
small hand-built pool that surfaces both `isCreditCardPayment` values and a `score` is sufficient (SC-011). Swift
lower-camel-cases the record fields and the enum cases (`.debit`/`.credit`).

**Alternatives**: Loading the JSON fixture in Swift — rejected: the Rust parity harness already pins the fixture;
the Swift test only needs to prove the bridge round-trips the types and the function is reachable. Asserting exact
score bits in Swift — unnecessary here (the Rust harness owns exact-f64 parity); the Swift test reads the score to
prove it crosses as a `Double`.

---

## D14 — Scope exclusions stay platform-side (mirroring the web engine's DB layer)

**Decision**: This slice ports **only** the pure pairing logic. It does **not** implement — and `transfer.rs` must
**not** contain — any of: persistence of `transfer_group_id` / `is_transfer`; the "Self Transfer" / "Credit Card
Bill Payment" **category get-or-create**; **audit events**; the optimistic-concurrency `_claim_pair` / SAVEPOINT
**race handling**; **cross-user filtering** (the core is handed exactly one user's rows); the email-parse
**`match_window_days`** date-tolerance override (the core uses the fixed ±1-day window); any **database / SQL /
persistence / aggregation**; the **HTTP endpoint** / API surface; or any **UI** (FR-014/016, spec Out of Scope).

**Rationale**: These are all **side effects / persistence / multi-tenant** concerns the platform owns; the pure
matcher only **returns** the detected pairs. Keeping them out preserves purity/determinism (Principle II) and the
zero-network guarantee (Principle I), and keeps the diff surgical. A later slice may parameterise the date window
(the web `match_window_days`) once a store lands — without changing the pairing behaviour.

**Alternatives**: Threading a `match_window_days` parameter now — rejected: out of scope (the fixed ±1-day window
is pinned this slice); a later slice can add it. Emitting a `transfer_group_id` — rejected (D3): persistence
identity is platform-side.

---

## Verification (throwaway simulation of the locked algorithm — repo left clean)

To pin the fixture bytes and the unit-test expectations, the locked `_narration_similarity` + `_score` + the
anchor-sorted greedy matcher were transcribed into a throwaway harness (Python, matching the web engine, for the
canonical f64 bits) and a throwaway Rust snippet (to confirm bit-identity + the serde_json/`ryu` round-trip), run
on a **nine-scenario single pool** with **per-scenario-isolated amounts**, then discarded (no file committed; `git
status` clean):

**The nine scenarios** (amounts isolated so greedy claiming never crosses scenarios):

| # | Scenario | Rows (amount / date / direction / account / card) | Outcome |
|---|---|---|---|
| S1 | matched pair | `5000.00` `2026-06-01` Debit A · `5000.00` `2026-06-01` Credit B | **pair**, cc=false |
| S2 | within-tolerance (1 day, ₹0.50) | `1000.00` `2026-06-03` Debit A · `1000.50` `2026-06-04` Credit B | **pair**, cc=false |
| S3 | amount-drift reject (₹500) | `2000.00` `2026-06-05` Debit A · `2500.00` `2026-06-05` Credit B | no pair |
| S4 | date-drift reject (4 days) | `3000.00` `2026-06-07` Debit A · `3000.00` `2026-06-11` Credit B | no pair |
| S5 | same-direction reject | `4000.00` `2026-06-09` Debit A · `4000.00` `2026-06-09` Debit B | no pair |
| S6 | same-account reject | `6000.00` `2026-06-11` Debit A · `6000.00` `2026-06-11` Credit A | no pair |
| S7 | narration tiebreak | `7000.00` `2026-06-13` Debit A · two `7000.00` Credit B (closer + unrelated narration) | **pair** with closer, cc=false |
| S8 | id tiebreak | `8000.00` `2026-06-15` Debit A · two identical `8000.00` Credit B | **pair** with lowest id, cc=false |
| S9 | credit-card payment flag | `9000.00` `2026-06-17` Debit A (savings) · `9000.00` `2026-06-17` Credit C (card) | **pair**, **cc=true** |

**Result** — anchors process in `(date, id)` order → **5 pairs** emitted in that order, **4 guards** produce none:

| Pair | `date_diff` | `amount_diff` | `narration_similarity` | `score` (exact f64) |
|---|:-:|:-:|:-:|---|
| `s1-out → s1-in` (cc=false) | 0 | `0.00` | `1/7` = `0.14285714285714285` | **`1.0285714285714285`** |
| `s2-out → s2-in` (cc=false) | 1 | `0.50` | `3/5` = `0.6` | **`0.8200000000000001`** |
| `s7-out → s7-in-a` (cc=false) | 0 | `0.00` | `1/4` = `0.25` | **`1.05`** |
| `s8-out → s8-in-a` (cc=false) | 0 | `0.00` | `1/1` = `1.0` | **`1.2`** |
| `s9-out → s9-in` (**cc=true**) | 0 | `0.00` | `1/6` = `0.16666666666666666` | **`1.0333333333333334`** |

- **Guards** S3 (amount ₹500 apart), S4 (4 days apart), S5 (both Debit — no Credit candidate), S6 (same account —
  filtered by the different-account guard) each emit **no pair**. ✅ (FR-006, SC-003)
- **Narration tiebreak** (S7): candidate "NEFT FROM ICICI BANK XX5678" (Jaccard `2/8 = 0.25` with the anchor "NEFT
  TO HDFC BANK XX1234") beats "SALARY CREDIT FROM ACME CORP" (Jaccard `0`) → closer narration wins. ✅ (FR-007,
  SC-004)
- **Id tiebreak** (S8): two Credit rows identical in date, amount, and narration (Jaccard `1.0`) → the **lowest
  id** (`s8-in-a` < `s8-in-b`) is chosen. ✅ (FR-007, SC-004)
- **Card flag** (S9): the inflow is a credit-card account → `is_credit_card_payment == true`; every other pair has
  both legs non-card → `false`. ✅ (FR-009, SC-005)
- **Score floor / no cap**: all five scores match the web `_score` exactly; four exceed 1.0 (no upper cap), and the
  formula floors at 0.0 for large drift (unit test). ✅ (FR-010, SC-006)
- **Ordering**: pairs are emitted in anchor `(date, id)` order (`s1, s2, s7, s8, s9`). ✅ (FR-002, SC-008)
- **Greedy single-claim**: each row appears in at most one pair; the extra Credit rows in S7/S8 are left unpaired.
  ✅ (FR-005, SC-007)
- **Bit-identity + round-trip**: the throwaway Rust reimplementation of `score` produced values **bit-identical**
  to the Python `_score`, and each stored decimal (serde_json `ryu` shortest form) **parses back to the same f64**
  (`parse(stored) == computed` for all five) — so the parity harness's exact-f64 `==` assertion holds across
  x86_64/arm64. ✅ (D5, SC-010)
- **Empty / no-outflow input** → **0 pairs**, no panic (unit test). ✅ (SC-009)
- **Determinism** — re-running the pool yields byte-identical output. ✅ (SC-009)

The exact `rows` + 5-entry `expected_pairs` this pool produces are written verbatim into `fixtures/transfer/basic.json`
(bytes in [`contracts/golden-fixture.md`](./contracts/golden-fixture.md)).

**Output**: all unknowns resolved; the ported helpers and the greedy matcher are verified; the fixture and
unit-test expectations are pinned (with exact, bit-identical, round-trip-verified scores). Proceed to Phase 1.
