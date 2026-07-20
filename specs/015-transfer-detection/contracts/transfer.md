# Contract: Transfer Matcher (`transfer::detect_transfers`) — internal Rust seam

**Feature**: `015-transfer-detection` | **Date**: 2026-07-20
**Module**: `kaname-core::transfer`

The pure, in-memory **single-pool self-transfer matcher** — the on-device port of the web engine's
`transfer_detector.py` pure subset (`_narration_similarity` + `_score` + the ±1-day / ±₹1.00 tolerance envelope +
the outflow-anchored greedy selection from `detect_pairs_for_user` + `_best_counterpart`, minus all SQL). This is a
**stable behaviour contract**: given one list of already-parsed, still-unpaired rows, `detect_transfers` returns the
detected transfer pairs (each with `outflow_id`, `inflow_id`, `is_credit_card_payment`, and a float `score`),
ordered by the anchor's `(date, id)`; and it is **pure, deterministic, total**, and **never reads the wall-clock**.
No database, no clock, no locale, no new dependency. Money and the ±₹1 tolerance use exact `Decimal`; only the
confidence `score` is an `f64`.

---

## `transfer::detect_transfers` — the matcher

```rust
pub fn detect_transfers(rows: &[TransferInput]) -> Vec<TransferPair>
```

**Input**: one **borrowed** slice of `TransferInput` rows — the single pool for **one user** (the platform scopes it
and pre-filters to still-unpaired rows). Not mutated.

**Output**: `Vec<TransferPair>` — the detected pairs, **ordered by the anchor's `(date, id)`**; empty when no pair
is found.

### Steps (pinned to the web logic)

1. **Anchors** = indices of `Direction::Debit` (outflow) rows, **sorted ascending by `(date, id)`**.
2. **Consumed** = `vec![false; rows.len()]`, indexed by row position.
3. For each anchor `a` in order: skip if `consumed[a]`. Build the **candidate set** = every index `c` with **all**
   of the guards below. If empty, continue.
4. **Best** = `min_by` the candidates on the tuple `(date_diff, amount_diff, -narration_similarity, id)`.
5. **Claim** both `a` and the best `c` (`consumed`), and **emit** a `TransferPair`.

### Candidate eligibility (the whole guard surface)

| Guard | Rule | Source |
|---|---|---|
| **not consumed** | `!consumed[c]` (each row paired at most once) | FR-005 |
| **different account** | `rows[c].account_id != rows[a].account_id` | FR-004/006 |
| **opposite direction** | `rows[c].direction == Direction::Credit` (inflow for an outflow anchor) | FR-004/006 |
| **date window** | `(rows[a].date - rows[c].date).num_days().abs() <= DATE_TOLERANCE_DAYS` (`= 1`, inclusive) | FR-004/006 |
| **amount window** | `(rows[a].amount - rows[c].amount).abs() <= Decimal::ONE` (±₹1.00, inclusive) | FR-004/006 |

A candidate failing **any** guard is ineligible (never paired with the anchor). If **no** candidate is eligible,
the anchor emits **no pair** and is left unpaired (spec Edge Cases).

### Selection tuple (ambiguity resolution — lowest wins)

`min_by` with an explicit comparator, in order:

1. `date_diff: i64` ascending (`num_days().abs()`) — closest date first.
2. `amount_diff: Decimal` ascending (`(a.amount - c.amount).abs()`, `Decimal` `Ord`) — closest amount next.
3. `narration_similarity: f64` **descending** (`sj.partial_cmp(&si).unwrap()`) — **highest** similarity next
   (the `unwrap` is safe: similarities are finite in `[0,1]`).
4. `id: String` ascending (`rows[i].id.cmp(&rows[j].id)`) — lowest id last.

Because `id` is unique per row, the comparator is a **strict total order** over candidates: there is exactly one
minimum, so `min_by`'s "last equal element" behaviour is irrelevant and the result matches Python `min` (first
wins). (FR-007, SC-004)

### Emitted pair

| Field | Value |
|---|---|
| `outflow_id` | `rows[a].id` (the anchor / Debit leg) |
| `inflow_id` | `rows[best].id` (the counterpart / Credit leg) |
| `is_credit_card_payment` | `rows[a].is_credit_card \|\| rows[best].is_credit_card` (either leg is a card) |
| `score` | `score(date_diff, amount_diff, narration_similarity)` for the chosen pair |

### `narration_similarity` (private) — token-level Jaccard

- **Definition**: Jaccard over the **token sets** of the **raw lowercased, whitespace-split** descriptions:
  `|A ∩ B| / |A ∪ B|` as f64. `0.0` if either description is empty **or** yields no tokens.
- **DISTINCT** from `dedup::normalize_narration` + Jaro-Winkler — no prefix/RRN/refnum stripping, **set**-Jaccard
  not character Jaro-Winkler. Must not call `normalize_narration` or reuse `dedup`'s Jaro helpers (FR-008, the
  porting gotcha).

### `score` (private) — the web `_score`

- **Definition**: `max(0, ((1.0 - 0.2·date_diff) - 0.2·amount_diff_f64) + 0.2·sim)` with
  `amount_diff_f64 = amount_diff.to_f64().unwrap_or(0.0)` (`rust_decimal::prelude::ToPrimitive`).
- **Floored at 0.0, NOT capped at 1.0** (live pairs exceed 1.0). Exact Python left-to-right op order → bit-identical
  f64 across x86_64/arm64 (FR-010).

### Invariants

- **Anchor = outflows only**, processed in `(date, id)` order; **greedy single-claim** (each row in ≤ 1 pair) via
  the shared `consumed` vector; the **earliest** anchor wins a contested inflow (FR-003/005, US6).
- **Output ordered by anchor `(date, id)`** — the push order (FR-002, SC-008).
- **Determinism**: identical `rows` ⇒ identical output; independent of input order and of `HashSet` iteration order
  (the sets feed only intersection/union **counts**) (FR-012, SC-009).
- **Purity / totality**: no I/O, no network/**clock**/locale, no global state, no file/DB/PDF; never panics (the
  `unwrap`s are safe — non-empty candidates; finite similarity); empty / no-outflow input ⇒ empty `Vec` (SC-009).
- **Money exact**: amounts and the ±₹1 tolerance are `Decimal` (`Decimal::ONE`); only `score` is `f64` (FR-011).

---

## Golden behaviour (verified end-to-end — the parity target)

Fixture `fixtures/transfer/basic.json` (exact bytes in [`golden-fixture.md`](./golden-fixture.md)) — one
nine-scenario pool with per-scenario-isolated amounts (so greedy claiming never crosses scenarios), run through the
locked algorithm (verified — research Verification):

| Scenario | Outcome | `score` (exact f64) |
|---|---|---|
| S1 matched pair (same day/amount, non-card) | `s1-out → s1-in`, cc=false | `1.0285714285714285` |
| S2 within-tolerance (1 day, ₹0.50) | `s2-out → s2-in`, cc=false | `0.8200000000000001` |
| S3 amount-drift (₹500) | **no pair** | — |
| S4 date-drift (4 days) | **no pair** | — |
| S5 same-direction (two outflows) | **no pair** | — |
| S6 same-account | **no pair** | — |
| S7 narration tiebreak | `s7-out → s7-in-a` (closer narration, Jaccard `0.25`), cc=false | `1.05` |
| S8 id tiebreak | `s8-out → s8-in-a` (lowest id, Jaccard `1.0`), cc=false | `1.2` |
| S9 credit-card payment | `s9-out → s9-in`, **cc=true** (Jaccard `1/6`) | `1.0333333333333334` |

**5 pairs** (in anchor `(date, id)` order `s1, s2, s7, s8, s9`), **4 guards** produce none. The four
same-day/same-amount pairs exceed 1.0 (score not capped); S2's is < 1 (date + amount drift). (SC-001..SC-008,
SC-010)

---

## Unit tests (`transfer.rs`) — mirroring the web logic + the spec edge cases

- **Matched pair** (S1) and **within-tolerance** (S2, 1 day + ₹0.50, both boundaries inclusive) → exactly one pair
  each; **boundary** rows at exactly 1 day / exactly ₹1.00 pair, 2 days / ₹1.01 do not (FR-004, SC-002).
- **Guards** (S3–S6): amount drift > ₹1, date drift > 1 day, same-direction, same-account → **zero** pairs each
  (FR-006, SC-003).
- **Narration tiebreak** (S7): the closer-narration inflow (higher Jaccard) is chosen; **id tiebreak** (S8):
  identical date/amount/narration → the lowest id (FR-007, SC-004).
- **Card flag** (S9): either-leg-card → `is_credit_card_payment == true`; both non-card → `false` (FR-009, SC-005).
- **Score**: same-day/same-amount pair equals `1 + 0.2·sim` (uncapped, > 1 when sim > 0); a large-drift pair floors
  at `0.0` (FR-010, SC-006).
- **Greedy single-claim** (US6): two outflows both eligible for one inflow → the earlier anchor by `(date, id)`
  claims it; the later is unpaired; the inflow is in exactly one pair (FR-005, SC-007).
- **`narration_similarity`**: `"neft to hdfc" / "neft from icici"` → known Jaccard; empty / whitespace-only → `0.0`
  (FR-008, spec Edge Cases).
- **Empty / no-outflow input** → 0 pairs, no panic; **determinism** — re-run yields identical output (SC-009).

Comparison is by `TransferPair` value-equality; the `score` field is compared with **exact `f64` `==`** (the port
reproduces the web bits — research D5).

---

## Relationship to the shipped checks (the reuse contract)

| | `dedup::cross_source_duplicates` / `coverage::compute_coverage` | `transfer::detect_transfers` |
|---|---|---|
| Input | two `&[Transaction]` / `today` + fact slices | **one** `&[TransferInput]` (single pool) |
| Purity | pure/deterministic/total | pure/deterministic/total (**never reads the clock**) |
| Similarity | `normalize_narration` + Jaro-Winkler / none | **raw-token Jaccard** (`narration_similarity`, distinct) |
| Money | exact `Decimal` / none | exact `Decimal` + `Decimal::ONE` tolerance (score is `f64`, not money) |
| Result | `Vec<CrossSourceMatch>` / `Vec<MonthCoverage>` | `Vec<TransferPair>` (anchor-ordered) |
| FFI wrapper | `cross_source_duplicates` / `compute_coverage` (types-only import) | `detect_transfers` (types-only import — name clash) |
| New dependency | none | none |

The web `transfer_detector.py`'s **DB layer** (persisting `transfer_group_id`/`is_transfer`, category
get-or-create, audit events, `_claim_pair` race handling, cross-user filter, `match_window_days` override) is **not**
ported — the platform supplies one user's rows and owns every side effect (spec Assumptions, Out of Scope,
FR-014/016). The core only returns the detected pairs.
