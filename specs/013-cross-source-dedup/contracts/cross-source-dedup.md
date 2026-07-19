# Contract: Cross-Source De-Duplication (`dedup::cross_source_duplicates`) — internal Rust seam

**Feature**: `013-cross-source-dedup` | **Date**: 2026-07-19
**Module**: `kaname-core::dedup`

The pure, in-memory **CANONICAL + FUZZY** cross-source matcher — the on-device analogue of the web
engine's **L3 CANONICAL** and **L4 FUZZY** rungs (`deduplicator.py`), with the narration normalised by a
port of `normalise_narration` (`normaliser.py`) and the similarity by a hand-rolled Jaro-Winkler that
reproduces `rapidfuzz` byte-for-byte. This is a **stable behaviour contract**: given two already-parsed
transaction lists, `cross_source_duplicates` returns the set of identified duplicate matches (each naming
the incoming row, the existing row it duplicates, and the layer), and it is **read-only, multiplicity-
aware, and deterministic**. No database, no new dependency.

---

## `dedup::cross_source_duplicates` — the matcher

```rust
pub fn cross_source_duplicates(
    existing: &[Transaction],
    incoming: &[Transaction],
) -> Vec<CrossSourceMatch>
```

**Inputs**: two borrowed slices of the shared `Transaction` (`date: NaiveDate`, `description: String`,
`amount: Decimal`, `direction: Direction`) — an **existing** (stored) list and an **incoming** list from a
different source. Neither is mutated.

**Output**: `Vec<CrossSourceMatch>` — one element per matched incoming row, in incoming order. An incoming
row with no match is a **survivor** and simply does **not** appear.

### Normalisation (computed once, up front)

- For every existing and incoming row, compute `normalize_narration(&row.description)` once (two
  `Vec<String>`). Both layers read these precomputed values (no re-normalisation per pair).

### Per-incoming ladder (canonical **before** fuzzy; first unconsumed existing wins)

`consumed: Vec<bool>` over `existing` tracks the multiplicity guard (each existing row matched **at most
once**). For each `incoming[i]` **in order**:

1. **Canonical pass** (tried first) — the first **unconsumed** `existing[e]` (in existing order) with
   **all** of:
   - `existing[e].date == incoming[i].date` (identical date — 0-day), **and**
   - `existing[e].amount.normalize() == incoming[i].amount.normalize()` (exact `Decimal` value, scale-
     insensitive — `250.00` == `250.0`), **and**
   - `existing[e].direction == incoming[i].direction` (explicit `Direction` equality), **and**
   - `prefix60(norm_e) == prefix60(norm_i)` where `prefix60(s) = s.chars().take(60).collect::<String>()`
     (first 60 **characters** of the normalised narration).

   On hit → push `CrossSourceMatch { incoming_index: i as u32, existing_index: e as u32, layer:
   Canonical }`, set `consumed[e] = true`, advance to the next incoming row.

2. **Fuzzy pass** (only if the canonical pass found nothing) — the first **unconsumed** `existing[e]` with
   **all** of:
   - `existing[e].amount.normalize() == incoming[i].amount.normalize()`, **and**
   - `existing[e].direction == incoming[i].direction`, **and**
   - `(existing[e].date - incoming[i].date).num_days().abs() <= 1` (within **±1 day**), **and**
   - `jaro_winkler(&norm_e, &norm_i) >= JARO_WINKLER_THRESHOLD` (0.92, **inclusive**).

   On hit → push `CrossSourceMatch { i, e, layer: Fuzzy }`, set `consumed[e] = true`, advance.

3. **No hit** → `incoming[i]` is a survivor (emit nothing).

### Guards (the whole no-match surface)

| Guard | Canonical | Fuzzy |
|---|---|---|
| Amount (`normalize()` value equality) | must be equal | must be equal |
| Direction (`Direction` equality) | must be equal | must be equal |
| Date | must be **identical** | `\|Δdays\| <= 1` |
| Narration | 60-char normalised **prefix** equal | Jaro-Winkler `>= 0.92` on the **full** normalised narrations |

A differing direction, a differing amount (by value), a date ≥ 2 days apart (fuzzy) or ≠ (canonical), or a
narration below the prefix/similarity bar → **no match on that layer**. If neither layer matches, the
incoming row survives.

### Invariants

- **Canonical precedence**: for a single incoming row, if any unconsumed existing row qualifies
  canonically, that match is taken and the fuzzy pass is **never** run for it (FR-004, SC-006).
- **First-unconsumed-wins**: within a layer, the earliest qualifying existing row (in existing order) is
  chosen — deterministic tie-break (FR-004, SC-007).
- **Multiplicity**: each existing row is consumed by at most one incoming row; N incoming vs M existing
  identical rows yield exactly `min(N, M)` matches — surplus incoming rows survive (FR-003, SC-005).
- **Read-only**: `existing`/`incoming` are borrowed `&` and never mutated, dropped, reordered, merged, or
  persisted (FR-002, SC-009).
- **Purity / totality**: no I/O, no network/clock/locale, no global mutable state, no file/DB/PDF;
  identical input ⇒ identical output; either side empty ⇒ empty result; never panics (FR-005, SC-012).
- **Money is exact**; a Jaro-Winkler similarity is `f64` (a [0,1] score), never money (FR-011, SC-011).

---

## `normalize_narration` — pinned narration key (port of web `normalise_narration`)

```rust
pub fn normalize_narration(raw: &str) -> String
```

Order (exact web): `trim` → **loop**{ strip one `LEADING_PREFIX` + `trim` } until stable → remove every
`RRN\d+` → collapse whitespace to a single space → strip a trailing 10–16-digit refnum → `to_lowercase`
→ `trim`. Statics: `LEADING_PREFIX =
(?i)^(POS\s|UPI[-/]|NEFT/|IMPS/|ACH/|BIL/|RTGS/|INT\.PD\./|TO TRANSFER-|BY TRANSFER-)`, `RRN =
(?i)\bRRN\d+\b`, `TRAILING_REFNUM = \b[0-9]{10,16}\b\s*$`, `WHITESPACE = \s+`. **Distinct from** the
coarser `normalize_description` (unchanged). Pinned reference outputs (verified vs the real `regex` crate):

| Input | Output |
|---|---|
| `UPI-SWIGGY-RRN1234` | `swiggy-` |
| `POS SWIGGY BANGALORE 12345678901234` | `swiggy bangalore` |
| `NEFT/ACME CORP/REF999` | `acme corp/ref999` |
| `BY TRANSFER-Salary Credit RRN5678` | `salary credit` |
| `SWIGGY  ORDER   9988776655` | `swiggy order` |

---

## `jaro` / `jaro_winkler` — hand-rolled similarity (private; reproduces `rapidfuzz`)

```rust
fn jaro(a: &[char], b: &[char]) -> f64          // classic Jaro; window max(len)/2-1; transpositions/2
fn jaro_winkler(a: &str, b: &str) -> f64         // jaro + prefix*0.1*(1-jaro); prefix<=4; UNGATED
```

`const JARO_WINKLER_THRESHOLD: f64 = 0.92;`. **Ungated** (no `jaro > 0.7` boost gate) — matches
`rapidfuzz`, and the gate is proven decision-irrelevant at 0.92 (research D3). Pinned reference values
(byte-for-byte vs `rapidfuzz`; **unit tests assert via 4-dp rounding** because the last two are repeating
decimals — research D5):

| Pair | Jaro-Winkler | `>= 0.92`? |
|---|--:|:-:|
| `swiggy bangalore` / `swiggy bangaluru` | `0.95` | match |
| `amazon` / `amazon pay` | `0.92` | **match (inclusive)** |
| `acme corp` / `acme corporation` | `0.9125` | **no match** |
| `fine dining` / `fine dine` | `0.9232` | match |
| `swiggy order` / `swiggy orders` | `0.9846` | match |
| identical strings | `1.0` | match |

---

## Golden behaviour (verified end-to-end — the parity target)

Fixture `fixtures/dedup/cross_source/basic.json` (exact bytes in `golden-fixture.md`), five scenarios in
one pair of lists, run through the locked algorithm (verified — research Verification harness):

| Incoming | vs Existing | Guards | Result |
|---|---|---|---|
| `#0` `swiggy   bangalore` 250.00 D 2026-07-04 | `#0` `Swiggy Bangalore` 250.00 D 2026-07-04 | same date/amt/dir, same 60-char prefix `swiggy bangalore` | **Canonical** (0→0) |
| `#1` `swiggy bangaluru` 500.00 D 2026-07-11 | `#1` `swiggy bangalore` 500.00 D 2026-07-10 | same amt/dir, +1 day, JW 0.95 ≥ 0.92 | **Fuzzy** (1→1) |
| `#2` `acme corporation` 400.00 D 2026-07-15 | `#2` `acme corp` 400.00 D 2026-07-15 | same amt/dir/date, JW 0.9125 < 0.92, prefix differs | **survivor** |
| `#3` `netflix` 600.00 **C** 2026-07-20 | `#3` `netflix` 600.00 **D** 2026-07-20 | same date/amt/narration, **direction differs** | **survivor** |
| `#4` `uber` 200.00 D 2026-07-25 | `#4` `uber` 200.00 D 2026-07-25 | identical | **Canonical** (4→4) |
| `#5` `uber` 200.00 D 2026-07-25 | (E4 already consumed) | multiplicity — no unconsumed candidate | **survivor** |

`expected_matches = [ {0,0,Canonical}, {1,1,Fuzzy}, {4,4,Canonical} ]`.

---

## Unit tests (`dedup.rs`) — mirroring the web logic + the spec edge cases

`normalize_narration` on the five references; `jaro_winkler` on the six reference pairs (4-dp assert) +
the two threshold decisions; `cross_source_duplicates` for: canonical match; fuzzy at the inclusive 0.92
boundary (`amazon`/`amazon pay`, ±1 day); below-threshold non-match (survives); direction / amount / 2-day
guards (survive); multiplicity (2 identical incoming vs 1 existing → exactly 1 match, other survives);
canonical-before-fuzzy precedence; and determinism (identical output on re-run). Money compared via
`Decimal` value-equality; similarity via the raw f64 (threshold) / 4-dp (reference assertion).

---

## Relationship to the shipped checks (the reuse contract)

| | `reconcile::reconcile` | `dedup::cross_source_duplicates` |
|---|---|---|
| Input | `&ParsedStatement` (one statement) | `&[Transaction]` × 2 (two lists) |
| Purity | pure/deterministic/total | pure/deterministic/total |
| Money | exact `Decimal` | exact `Decimal` (similarity is `f64`, not money) |
| Result | `ReconcileResult` (typed record) | `Vec<CrossSourceMatch>` (typed records) |
| FFI wrapper | `reconcile_statement` wraps `reconcile` | `cross_source_duplicates` (ffi) wraps `dedup::cross_source_duplicates` |
| New dependency | none | none (hand-rolled Jaro-Winkler) |

The existing `normalize_description` + `dedup_fingerprint` (the L2 EXACT-hash analogue) are **not** wired
into this matcher and are left unchanged (spec Out of Scope, FR-012).
