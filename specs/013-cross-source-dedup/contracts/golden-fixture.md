# Contract: Golden-Fixture Schema — cross-source de-dup vectors (NEW shape)

**Feature**: `013-cross-source-dedup` | **Date**: 2026-07-19
**Consumers**: `core/crates/kaname-core/tests/parity.rs` (a new dedup loader + one test; the statement
`CASES` are untouched).

The matcher's input is **two already-parsed transaction lists**, not a statement — so this slice
introduces a **new fixture shape** under `fixtures/dedup/cross_source/`, distinct from the per-statement
`lines`/`full_text`/`expected.rows` schema. It adds **one file** (`basic.json`); no existing fixture
changes. All amounts are **JSON strings** (re-parsed to `Decimal`, never `f64`), all data synthetic.

---

## Schema

```jsonc
{
  "_comment": "string — provenance + scenario notes (synthetic, no real data)",
  "existing": [                       // the stored list (candidates; each consumed at most once)
    { "date": "YYYY-MM-DD", "description": "string", "amount": "string", "direction": "Debit|Credit" }
  ],
  "incoming": [                       // the list tested against `existing`, in order
    { "date": "YYYY-MM-DD", "description": "string", "amount": "string", "direction": "Debit|Credit" }
  ],
  "expected_matches": [               // the duplicates the web L3/L4 logic identifies, in incoming order
    { "incoming_index": <u32>, "existing_index": <u32>, "layer": "Canonical|Fuzzy" }
  ]
}
```

**Field rules**

- `date` → `NaiveDate::parse_from_str(_, "%Y-%m-%d")`; `amount` → `Decimal::from_str` (string only — no
  `f64` touches money, scale preserved so `250.00`/`250.0` compare equal via `normalize`); `direction`
  deserialises to the shared `Direction` enum (`"Debit"`/`"Credit"`).
- Each `existing`/`incoming` object maps to `Transaction::new(date, description, amount, direction)`.
- `expected_matches` mirrors `CrossSourceMatch` (`incoming_index`/`existing_index`/`layer`), in the order
  the matcher emits them (incoming order). Incoming rows that survive are simply **absent**.
- `layer` deserialises to `DedupLayer` (`"Canonical"`/`"Fuzzy"`).

---

## `fixtures/dedup/cross_source/basic.json` — exact bytes to write (in implementation, test-first)

Verified end-to-end against the locked algorithm (research Verification harness): the five scenarios
(canonical, fuzzy ±1-day, below-threshold survivor, direction-guard survivor, multiplicity survivor)
produce exactly `expected_matches = [{0,0,Canonical}, {1,1,Fuzzy}, {4,4,Canonical}]`.

```json
{
  "_comment": "Synthetic cross-source de-dup golden vector (no real data). Two already-parsed transaction lists (an existing bank-ledger list and an incoming card list) plus the duplicate matches the web engine's L3 CANONICAL + L4 FUZZY logic identifies (normalise_narration + rapidfuzz Jaro-Winkler). amount is a string (re-parsed to Decimal - never float); direction Debit|Credit; layer Canonical|Fuzzy. Scenarios: (0) canonical match on same date/amount/direction + same 60-char normalised prefix 'swiggy bangalore'; (1) fuzzy match with a +1-day posting skew and JW('swiggy bangalore','swiggy bangaluru')=0.95>=0.92; (2) below-threshold survivor JW('acme corp','acme corporation')=0.9125<0.92; (3) direction-guard survivor (same date/amount/narration, Debit vs Credit); (4) canonical multiplicity match; (5) surplus identical repeat survives (the single existing 'uber' was already consumed by 4). expected_matches captured from the pinned web logic.",
  "existing": [
    { "date": "2026-07-04", "description": "Swiggy Bangalore", "amount": "250.00", "direction": "Debit" },
    { "date": "2026-07-10", "description": "swiggy bangalore", "amount": "500.00", "direction": "Debit" },
    { "date": "2026-07-15", "description": "acme corp", "amount": "400.00", "direction": "Debit" },
    { "date": "2026-07-20", "description": "netflix", "amount": "600.00", "direction": "Debit" },
    { "date": "2026-07-25", "description": "uber", "amount": "200.00", "direction": "Debit" }
  ],
  "incoming": [
    { "date": "2026-07-04", "description": "swiggy   bangalore", "amount": "250.00", "direction": "Debit" },
    { "date": "2026-07-11", "description": "swiggy bangaluru", "amount": "500.00", "direction": "Debit" },
    { "date": "2026-07-15", "description": "acme corporation", "amount": "400.00", "direction": "Debit" },
    { "date": "2026-07-20", "description": "netflix", "amount": "600.00", "direction": "Credit" },
    { "date": "2026-07-25", "description": "uber", "amount": "200.00", "direction": "Debit" },
    { "date": "2026-07-25", "description": "uber", "amount": "200.00", "direction": "Debit" }
  ],
  "expected_matches": [
    { "incoming_index": 0, "existing_index": 0, "layer": "Canonical" },
    { "incoming_index": 1, "existing_index": 1, "layer": "Fuzzy" },
    { "incoming_index": 4, "existing_index": 4, "layer": "Canonical" }
  ]
}
```

### Scenario coverage (why each row exists)

| Incoming index | Narration (raw → normalised) | vs existing | Guards exercised | Outcome |
|:-:|---|:-:|---|---|
| 0 | `swiggy   bangalore` → `swiggy bangalore` | E0 `Swiggy Bangalore` → `swiggy bangalore` | canonical: same date/amount/dir, whitespace+case cosmetic, same 60-char prefix | **Canonical** 0→0 |
| 1 | `swiggy bangaluru` | E1 `swiggy bangalore` | fuzzy: +1-day skew, JW 0.95 ≥ 0.92 | **Fuzzy** 1→1 |
| 2 | `acme corporation` | E2 `acme corp` | below-threshold: JW 0.9125 < 0.92 (and prefix differs → no canonical) | **survivor** |
| 3 | `netflix` (**Credit**) | E3 `netflix` (**Debit**) | direction guard (else identical) | **survivor** |
| 4 | `uber` | E4 `uber` (single) | canonical multiplicity match | **Canonical** 4→4 |
| 5 | `uber` | E4 already consumed | multiplicity: no unconsumed candidate | **survivor** |

This single vector pins a canonical match, a fuzzy ±1-day match (incl. exercising the ≥0.92 threshold), a
below-threshold non-match, a direction-guard non-match, and multiplicity (surplus repeat survives) —
covering FR-020 / SC-013 in one file. (Amount- and 2-day-date guards, and the inclusive-0.92 boundary via
`amazon`/`amazon pay`, are pinned by the `dedup.rs` unit tests.)

---

## Parity harness behaviour (contract)

A **new, dedup-only** loader + test is added to `tests/parity.rs`; the existing statement `Fixture` /
`Expected` / `CASES` and every current test are **unchanged**.

```rust
#[derive(Deserialize)]
struct DedupFixture { existing: Vec<DedupRow>, incoming: Vec<DedupRow>, expected_matches: Vec<ExpectedMatch> }

#[derive(Deserialize)]
struct DedupRow { date: String, description: String, amount: String, direction: Direction }

#[derive(Deserialize)]
struct ExpectedMatch { incoming_index: u32, existing_index: u32, layer: DedupLayer }

fn to_txns(rows: &[DedupRow]) -> Vec<Transaction> {
    rows.iter()
        .map(|r| Transaction::new(
            NaiveDate::parse_from_str(&r.date, "%Y-%m-%d").unwrap(),
            r.description.clone(),
            Decimal::from_str(&r.amount).unwrap(),
            r.direction,
        ))
        .collect()
}

#[test]
fn cross_source_dedup_matches_expected() {
    let raw = std::fs::read_to_string(format!(
        "{}/../../../fixtures/dedup/cross_source/basic.json", env!("CARGO_MANIFEST_DIR")
    )).unwrap();
    let fx: DedupFixture = serde_json::from_str(&raw).unwrap();
    let got = cross_source_duplicates(to_txns(&fx.existing), to_txns(&fx.incoming));
    let want: Vec<CrossSourceMatch> = fx.expected_matches.iter()
        .map(|m| CrossSourceMatch { incoming_index: m.incoming_index, existing_index: m.existing_index, layer: m.layer })
        .collect();
    assert_eq!(got, want, "cross-source dedup matches must equal the golden expected_matches");
}
```

- Imports `cross_source_duplicates`, `CrossSourceMatch`, `DedupLayer`, `Transaction` from `kaname_core`
  (alongside the existing statement imports). `DedupLayer`/`Direction` deserialise directly (they derive
  `serde::Deserialize` via `uniffi` + `model.rs`; `DedupLayer` derives `Deserialize` for the fixture — or
  the loader maps the string, if a derive is not added, per implementation choice).
- Money is re-parsed from strings via `Decimal::from_str` (never `f64`); comparison is exact `Decimal` /
  enum value-equality; re-running yields identical results (determinism, SC-012). Any mismatch **fails**
  (parity guard — FR-020/024).
- No existing fixture or statement-parity assertion changes; the new file is additive and lives under a
  new `fixtures/dedup/` subtree. All data synthetic/redacted (FR-021).

> **Note**: `DedupLayer` must be deserialisable from the fixture string. Simplest per the codebase: add
> `serde::{Serialize, Deserialize}` to `DedupLayer`'s derives (mirrors `Direction` in `model.rs`, which
> derives both `serde` and `uniffi`), so `"Canonical"`/`"Fuzzy"` map directly. This is a test-serialisation
> convenience on a fieldless enum; it does not affect the FFI surface.
