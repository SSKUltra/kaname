# Contract: Transfer Detection Golden Fixture

**Feature**: `015-transfer-detection` | **Date**: 2026-07-20
**Fixture**: `fixtures/transfer/basic.json` (repo-root `fixtures/`, shared by the Rust parity harness)

The byte-for-byte golden vector that pins `transfer::detect_transfers` to the **live web engine**
(`transfer_detector.py`'s `_narration_similarity` + `_score` + the ±1-day / ±₹1.00 envelope + the outflow-anchored
greedy claim from `detect_pairs_for_user` / `_best_counterpart`). One nine-scenario single-user pool captured from a
standalone in-memory harness that reproduces the pure web logic (the DB path cannot run without Postgres). This
contract fixes the schema **and** the exact bytes (constitution Principle V — parity is proven against captured
ground truth, not re-derived). Per-scenario-isolated amounts (≥ ₹1000 apart) guarantee the greedy claim never
crosses scenarios.

---

## Location & loader

- **Path**: `fixtures/transfer/basic.json` (sibling of `fixtures/dedup/cross_source/basic.json`,
  `fixtures/coverage/basic.json`).
- **Consumer**: `core/crates/kaname-core/tests/parity.rs` (`transfer_detection_matches_expected`), resolved via
  `concat!(env!("CARGO_MANIFEST_DIR"), "/../../../fixtures/transfer/basic.json")` — the same `../../../` hop the
  dedup/coverage loaders use.
- **Deserialized with** `serde_json` (dev-dependency, already present) into typed structs (below). No production code
  reads the fixture.

---

## Schema

```jsonc
{
  "_comment": "<provenance: synthetic, no real data; captured from a live run of the web helpers>",
  "rows": [
    {
      "id":             "s1-out",         // stable opaque row id (also the final selection tiebreak)
      "account_id":     "acct-a",         // opaque account id (different-account guard)
      "is_credit_card": false,            // this leg is a credit-card account
      "date":           "2026-06-01",     // ISO-8601 (YYYY-MM-DD)
      "amount":         "5000.00",        // decimal STRING, re-parsed to Decimal — never a float
      "direction":      "Debit",          // "Debit" = outflow (anchor) | "Credit" = inflow (counterpart)
      "description":    "NEFT TO HDFC SALARY ACCOUNT"  // raw narration (un-normalized) for token-Jaccard
    }
    // … one object per pooled transaction …
  ],
  "expected_pairs": [
    {
      "outflow_id":             "s1-out",             // anchor (Debit) leg id
      "inflow_id":              "s1-in",              // counterpart (Credit) leg id
      "is_credit_card_payment": false,                // either leg is a credit-card account
      "score":                  1.0285714285714285    // web _score, JSON number at full f64 precision
    }
    // … one object per detected pair, in anchor (date, id) order …
  ]
}
```

### Field rules

- **`rows[].amount`** is a **string** (`"5000.00"`), re-parsed with `Decimal::from_str` — money is **never** a JSON
  float (constitution). **`rows[].date`** is ISO-8601. **`rows[].direction`** is exactly `"Debit"` / `"Credit"`
  (the `Direction` serde form — no rename; verified against the shipped reader fixtures).
- **`rows[].id`** values are unique (the selection comparator's final, total-ordering tiebreak).
- **`expected_pairs[].score`** is a **JSON number** written at full round-trippable f64 precision (serde_json/ryu
  shortest form, e.g. `1.0285714285714285`, `0.8200000000000001`, `1.05`, `1.2`, `1.0333333333333334`). The parity
  test compares it with **exact `f64` `==`** (the port reproduces the web bits — research D5).
- **`expected_pairs`** is ordered by the anchor's `(date, id)` — the emission order of `detect_transfers`.

---

## Exact bytes — `fixtures/transfer/basic.json`

> Write this file **verbatim** (2-space indent, one object per line — matching the dedup/coverage fixtures). Values
> captured from the live web helpers; scores confirmed bit-identical Python ⇄ Rust and round-trip-stable through
> serde_json/ryu.

```json
{
  "_comment": "Synthetic self-transfer detection golden vector (no real data). One single-user pool of already-parsed, still-unpaired rows exercising all 9 acceptance scenarios; expected_pairs captured from a live in-memory run of the web engine's transfer_detector.py pure helpers (_narration_similarity token-Jaccard on the raw lowercased whitespace-split description + _score, with the +-1-day and +-Rs1.00 tolerances and the outflow-anchored greedy claim from detect_pairs_for_user/_best_counterpart; the SQL path is not ported). amount is a string (re-parsed to Decimal - never float); direction Debit=outflow|Credit=inflow; is_credit_card is the reduction of the web account_type=='credit_card'; score is a JSON number at full f64 precision, compared with exact == in parity (floored at 0.0, NOT capped at 1.0). narration_similarity here is DISTINCT from dedup's normalise_narration + Jaro-Winkler. Amounts are per-scenario-isolated (>= Rs1000 apart) so greedy claiming never crosses scenarios. Scenarios: S1 matched pair (same day/amount, non-card) -> pair; S2 within tolerance (1 day, Rs0.50) -> pair; S3 amount drift (Rs500) -> none; S4 date drift (4 days) -> none; S5 same direction (two outflows) -> none; S6 same account -> none; S7 narration tiebreak (closer narration wins) -> pair; S8 id tiebreak (identical date/amount/narration -> lowest id) -> pair; S9 credit-card payment (either leg a card -> is_credit_card_payment true) -> pair.",
  "rows": [
    { "id": "s1-out", "account_id": "acct-a", "is_credit_card": false, "date": "2026-06-01", "amount": "5000.00", "direction": "Debit", "description": "NEFT TO HDFC SALARY ACCOUNT" },
    { "id": "s1-in", "account_id": "acct-b", "is_credit_card": false, "date": "2026-06-01", "amount": "5000.00", "direction": "Credit", "description": "NEFT FROM ICICI" },
    { "id": "s2-out", "account_id": "acct-a", "is_credit_card": false, "date": "2026-06-03", "amount": "1000.00", "direction": "Debit", "description": "NEFT TO KOTAK BANK" },
    { "id": "s2-in", "account_id": "acct-b", "is_credit_card": false, "date": "2026-06-04", "amount": "1000.50", "direction": "Credit", "description": "NEFT FROM KOTAK BANK" },
    { "id": "s3-out", "account_id": "acct-a", "is_credit_card": false, "date": "2026-06-05", "amount": "2000.00", "direction": "Debit", "description": "IMPS TO SAVINGS" },
    { "id": "s3-in", "account_id": "acct-b", "is_credit_card": false, "date": "2026-06-05", "amount": "2500.00", "direction": "Credit", "description": "IMPS FROM SAVINGS" },
    { "id": "s4-out", "account_id": "acct-a", "is_credit_card": false, "date": "2026-06-07", "amount": "3000.00", "direction": "Debit", "description": "RTGS TO CURRENT" },
    { "id": "s4-in", "account_id": "acct-b", "is_credit_card": false, "date": "2026-06-11", "amount": "3000.00", "direction": "Credit", "description": "RTGS FROM CURRENT" },
    { "id": "s5-out-a", "account_id": "acct-a", "is_credit_card": false, "date": "2026-06-09", "amount": "4000.00", "direction": "Debit", "description": "UPI TO FRIEND" },
    { "id": "s5-out-b", "account_id": "acct-b", "is_credit_card": false, "date": "2026-06-09", "amount": "4000.00", "direction": "Debit", "description": "UPI FROM FRIEND" },
    { "id": "s6-out", "account_id": "acct-a", "is_credit_card": false, "date": "2026-06-11", "amount": "6000.00", "direction": "Debit", "description": "INTERNAL TRANSFER" },
    { "id": "s6-in", "account_id": "acct-a", "is_credit_card": false, "date": "2026-06-11", "amount": "6000.00", "direction": "Credit", "description": "INTERNAL TRANSFER" },
    { "id": "s7-out", "account_id": "acct-a", "is_credit_card": false, "date": "2026-06-13", "amount": "7000.00", "direction": "Debit", "description": "NEFT TO HDFC BANK XX1234" },
    { "id": "s7-in-a", "account_id": "acct-b", "is_credit_card": false, "date": "2026-06-13", "amount": "7000.00", "direction": "Credit", "description": "NEFT FROM ICICI BANK XX5678" },
    { "id": "s7-in-b", "account_id": "acct-b", "is_credit_card": false, "date": "2026-06-13", "amount": "7000.00", "direction": "Credit", "description": "SALARY CREDIT FROM ACME CORP" },
    { "id": "s8-out", "account_id": "acct-a", "is_credit_card": false, "date": "2026-06-15", "amount": "8000.00", "direction": "Debit", "description": "SELF TRANSFER AXIS" },
    { "id": "s8-in-a", "account_id": "acct-b", "is_credit_card": false, "date": "2026-06-15", "amount": "8000.00", "direction": "Credit", "description": "SELF TRANSFER AXIS" },
    { "id": "s8-in-b", "account_id": "acct-b", "is_credit_card": false, "date": "2026-06-15", "amount": "8000.00", "direction": "Credit", "description": "SELF TRANSFER AXIS" },
    { "id": "s9-out", "account_id": "acct-a", "is_credit_card": false, "date": "2026-06-17", "amount": "9000.00", "direction": "Debit", "description": "CC BILL PAYMENT" },
    { "id": "s9-in", "account_id": "acct-c", "is_credit_card": true, "date": "2026-06-17", "amount": "9000.00", "direction": "Credit", "description": "PAYMENT RECEIVED HDFC CARD" }
  ],
  "expected_pairs": [
    { "outflow_id": "s1-out", "inflow_id": "s1-in", "is_credit_card_payment": false, "score": 1.0285714285714285 },
    { "outflow_id": "s2-out", "inflow_id": "s2-in", "is_credit_card_payment": false, "score": 0.8200000000000001 },
    { "outflow_id": "s7-out", "inflow_id": "s7-in-a", "is_credit_card_payment": false, "score": 1.05 },
    { "outflow_id": "s8-out", "inflow_id": "s8-in-a", "is_credit_card_payment": false, "score": 1.2 },
    { "outflow_id": "s9-out", "inflow_id": "s9-in", "is_credit_card_payment": true, "score": 1.0333333333333334 }
  ]
}
```

**20 rows, 5 expected pairs** (in anchor order `s1, s2, s7, s8, s9`).

---

## Scenario coverage (why these bytes)

| # | Scenario | Rows | Outcome | Pins |
|---|---|---|---|---|
| S1 | matched pair — same day, same amount, non-card | `s1-out` (D, acct-a) / `s1-in` (C, acct-b), 5000.00, 06-01 | pair, cc=false, **score 1.0285714285714285** (sim 1/7) | FR-004/010, SC-001, score **> 1.0 uncapped** |
| S2 | within tolerance — 1 day + ₹0.50 | `s2-out` 1000.00 06-03 / `s2-in` 1000.50 06-04 | pair, cc=false, **score 0.8200000000000001** (sim 3/5) | FR-004, SC-002, inclusive boundaries |
| S3 | amount drift — ₹500 (> ₹1) | `s3-out` 2000.00 / `s3-in` 2500.00, 06-05 | **none** | FR-006, SC-003 (amount guard) |
| S4 | date drift — 4 days (> 1) | `s4-out` 06-07 / `s4-in` 06-11, 3000.00 | **none** | FR-006, SC-003 (date guard) |
| S5 | same direction — two outflows | `s5-out-a` / `s5-out-b`, both Debit, 4000.00, 06-09 | **none** | FR-006, SC-003 (direction guard) |
| S6 | same account | `s6-out` / `s6-in`, both acct-a, 6000.00, 06-11 | **none** | FR-006, SC-003 (account guard) |
| S7 | narration tiebreak | `s7-out` / `s7-in-a` (sim 0.25) vs `s7-in-b` (sim 0.0), 7000.00, 06-13 | pair → `s7-in-a`, cc=false, **score 1.05** | FR-007/008, SC-004 (closer narration wins) |
| S8 | id tiebreak | `s8-out` / `s8-in-a`,`s8-in-b` (identical date/amount/narration, sim 1.0), 8000.00, 06-15 | pair → `s8-in-a` (lowest id), cc=false, **score 1.2** | FR-007, SC-004 (id tiebreak) |
| S9 | credit-card payment | `s9-out` (savings acct-a) / `s9-in` (card acct-c, is_credit_card=true), 9000.00, 06-17 | pair, **cc=true**, **score 1.0333333333333334** (sim 1/6) | FR-009, SC-005 (either-leg-card) |

**5 produce pairs** (S1, S2, S7, S8, S9), **4 are guards that produce none** (S3, S4, S5, S6). The four
same-day/same-amount pairs (S1/S7/S8/S9) exceed 1.0 (score uncapped); S2's is `< 1` (date + amount drift). Amounts
are ≥ ₹1000 apart across scenarios, so with a ±₹1.00 window no anchor can ever claim another scenario's inflow —
scenarios stay isolated regardless of iteration/`HashSet` order (SC-009 determinism).

---

## Parity harness (`tests/parity.rs`)

Additive to the existing dedup/coverage loaders (types local to the transfer test region):

```rust
#[derive(serde::Deserialize)]
struct TransferFixture { rows: Vec<TransferInputRow>, expected_pairs: Vec<ExpectedPair> }

#[derive(serde::Deserialize)]
struct TransferInputRow {
    id: String,
    account_id: String,
    is_credit_card: bool,
    date: String,      // ISO-8601 → NaiveDate::parse_from_str(_, "%Y-%m-%d")
    amount: String,    // → Decimal::from_str
    direction: Direction,
    description: String,
}

#[derive(serde::Deserialize)]
struct ExpectedPair {
    outflow_id: String,
    inflow_id: String,
    is_credit_card_payment: bool,
    score: f64,
}

#[test]
fn transfer_detection_matches_expected() {
    let fx: TransferFixture = load_transfer_fixture();          // concat!(env!("CARGO_MANIFEST_DIR"), "/../../../fixtures/transfer/basic.json")
    let rows: Vec<TransferInput> = fx.rows.iter().map(build_transfer_input).collect();

    let got = kaname_core::detect_transfers(rows);             // FFI-exported wrapper (crate root)

    assert_eq!(got.len(), fx.expected_pairs.len());
    for (g, e) in got.iter().zip(&fx.expected_pairs) {
        assert_eq!(g.outflow_id, e.outflow_id);
        assert_eq!(g.inflow_id, e.inflow_id);
        assert_eq!(g.is_credit_card_payment, e.is_credit_card_payment);
        assert_eq!(g.score, e.score);                          // exact f64 equality (bits pinned)
    }
}
```

- Reuses the shared `Direction` `Deserialize` (`"Debit"`/`"Credit"`) — no bespoke parsing.
- Calls `kaname_core::detect_transfers` (the **FFI-exported** wrapper re-exported at the crate root — the pure
  `transfer::detect_transfers` is not re-exported, to avoid the name clash; research D9). Input built as an owned
  `Vec<TransferInput>`.
- `assert_eq!(g.score, e.score)` is **exact** `f64` `==` — justified because the port reproduces the web
  arithmetic bit-for-bit and this fixture pins it (SC-010).

---

## Provenance / regeneration

- **Synthetic, no real data.** `expected_pairs` were captured from a standalone in-memory harness that runs the web
  engine's pure helpers (`_narration_similarity`, `_score`) and reproduces the anchor-sort + greedy-claim (the DB
  path in `detect_pairs_for_user` cannot run without Postgres). Scores were then confirmed bit-identical when the
  same arithmetic runs in Rust, and round-trip-stable through serde_json/ryu.
- **Do not hand-edit** `score` values. If the web helpers or tolerances ever change, re-capture from a fresh live
  run and update both this contract and the fixture together; never re-derive by hand.
