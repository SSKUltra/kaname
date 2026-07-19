# Phase 0 — Research: Cross-Source Transaction De-Duplication (the pure L3+L4 subset; zero new deps)

**Feature**: `013-cross-source-dedup` | **Date**: 2026-07-19
**Method**: The web engine is the source of truth. Its narration normaliser
(`.../ingestion/normaliser.py`, `normalise_narration`), its de-duplicator
(`.../ingestion/deduplicator.py`, the **L3 CANONICAL** and **L4 FUZZY** rungs), `rapidfuzz`'s
Jaro-Winkler similarity, and the parity tests (`test_statement_cross_source_dedup.py`,
`test_bank_statement_cross_source_dedup.py`) were **read as ground truth**. The two non-trivial ports —
the normaliser (built on the existing `regex` crate) and the **hand-rolled** Jaro-Winkler — were
**verified byte-for-byte** on the pinned stable toolchain against the real `regex` crate and against the
captured `rapidfuzz` values (throwaway programs, removed after use — repo left clean). Every decision
below is a faithful port or a justified, verified idiomatic mapping.

All NEEDS CLARIFICATION are resolved; the approach was **locked by the requester** and confirmed here
with evidence. **Headline finding: this slice needs no new dependency and no new shared engine helper
beyond the matcher, the `normalise_narration` port, and the Jaro-Winkler helper — it extends the existing
`dedup` module and is exposed exactly like `reconcile_statement`. The only non-mechanical points are the
ungated Jaro-Winkler (D3), the `f64`-similarity-is-not-money framing (D4), the 4-dp assertion of the two
repeating-decimal reference values (D5), and the index-based match record (D8).**

---

## D1 — Reuse the landed foundations wholesale; **extend** the existing `dedup.rs` module

**Decision**: Add the L3/L4 matcher, its `normalize_narration` port, and the hand-rolled Jaro-Winkler to
the **existing** `core/crates/kaname-core/src/dedup.rs`, leaving its current `normalize_description` +
`dedup_fingerprint` **unchanged**. Reuse, unchanged: `Transaction`/`Direction` (`model.rs`), the
`rust_decimal::Decimal` money type, the parity harness (`tests/parity.rs`), the UniFFI bridge (`ffi.rs` +
`uniffi.toml`), and the privacy-egress gate + CI. The one FFI export lives in `ffi.rs`, as
`reconcile_statement`/`check_balance_chain` do.

**Rationale**: The module already exists **for cross-source de-dup** (its doc-comment literally names "the
on-device equivalent of the web engine's `*_cross_source_dedup` behaviour"), so the L3/L4 matcher is its
natural home — no new module, no structural churn. This mirrors how `reconcile.rs` reused the shared
statement types and the bridge to land beside `balance_chain.rs`. FR-013 forbids "any new shared engine
helper beyond the matcher itself, the `normalise_narration` port, and the Jaro-Winkler helper" — extending
`dedup.rs` satisfies that exactly.

**Alternatives**: A brand-new `dedup/cross_source.rs` submodule — rejected: unnecessary indirection for
~150 lines that belong in the module already named `dedup`. Reworking `dedup_fingerprint` into the matcher
— rejected: `dedup_fingerprint` is the **L2 EXACT-hash** analogue (out of scope) and is deliberately not
wired in (spec Out of Scope, FR-012).

---

## D2 — Port `normalise_narration` verbatim; keep it **distinct** from `normalize_description`

**Decision**: Add `pub fn normalize_narration(raw: &str) -> String` to `dedup.rs`, backed by four
`std::sync::LazyLock<Regex>` statics ported 1:1 from `normaliser.py`:

```rust
static LEADING_PREFIX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)^(POS\s|UPI[-/]|NEFT/|IMPS/|ACH/|BIL/|RTGS/|INT\.PD\./|TO TRANSFER-|BY TRANSFER-)")
        .unwrap()
});
static RRN: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)\bRRN\d+\b").unwrap());
static TRAILING_REFNUM: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\b[0-9]{10,16}\b\s*$").unwrap());
static WHITESPACE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\s+").unwrap());
```

Algorithm — **exact order from the web engine**:

1. `trim`.
2. **Loop**: strip **one** leading prefix (`LEADING_PREFIX.replace(&s, "")`) and `trim`; **repeat until
   stable** (handles stacked prefixes like `UPI/POS …`).
3. Replace every `RRN\d+` with `""` (`RRN.replace_all`).
4. Collapse whitespace runs to a single space (`WHITESPACE.replace_all(&s, " ")`).
5. Strip a **trailing 10–16-digit refnum** (`TRAILING_REFNUM.replace(&s, "")`).
6. `to_lowercase()`.
7. `trim`.

The existing `normalize_description` (Unicode uppercase + whitespace-collapse, used by
`dedup_fingerprint`) is a **different, coarser** normaliser and is **left unchanged**; it is **not** the
canonical key. `normalize_narration` is the pinned narration source of truth for both the canonical
60-char prefix and the fuzzy Jaro-Winkler input (FR-006/007, spec Assumptions).

**Rationale**: The canonical key and the fuzzy similarity must be computed on the **web engine's**
normalisation, which strips payment-rail prefixes, RRN tokens, and trailing reference numbers that vary
between a bank ledger and a card statement for the same purchase. `LazyLock<Regex>` is the established
pattern across every reader (`yes.rs`, `iob.rs`, …). Keeping `normalize_description` untouched avoids
disturbing `dedup_fingerprint` (the L2 analogue) and any current callers.

**Verified** (real `regex` crate — see Verification harness): all five captured reference outputs
reproduce exactly, and stacked prefixes collapse (`"UPI/POS Coffee Day"→"coffee day"`).

**Alternatives**: Reusing `normalize_description` as the canonical key — rejected: it neither strips
prefixes/RRN/refnums nor lowercases, so it would **not** reproduce the web L3 key or the `rapidfuzz`
inputs (parity break). A char-by-char hand parser instead of regex — rejected: more code, less faithful
to `normaliser.py`, and `regex` is already a dependency.

---

## D3 — Hand-rolled Jaro-Winkler, **ungated** (no 0.7 boost threshold) — matches `rapidfuzz` exactly

**Decision**: Two private helpers in `dedup.rs`:

```rust
fn jaro(a: &[char], b: &[char]) -> f64          // classic Jaro on char slices (unicode-safe)
fn jaro_winkler(a: &str, b: &str) -> f64         // jaro + prefix * 0.1 * (1 - jaro)
```

- `jaro`: match window `max(a.len(), b.len()) / 2 - 1` (saturating at 0), count matches within the
  window, count transpositions and divide by 2, then `(m/|a| + m/|b| + (m − t)/m) / 3`; returns `1.0` for
  two empty inputs and `0.0` if either side is empty or there are no matches. Operates on `&[char]`
  (collect `chars()` into `Vec<char>` for both sides) so multi-byte characters are handled by scalar, not
  byte.
- `jaro_winkler`: `prefix` = number of common leading characters **capped at 4**; return `jaro + prefix *
  0.1 * (1.0 − jaro)`. **No `jaro > 0.7` gate** (the "boost threshold" some implementations add) — the
  prefix bonus is always applied. This is exactly what `rapidfuzz.distance.JaroWinkler.similarity`
  computes (default `prefix_weight = 0.1`, no threshold).

**Rationale**: FR-010 requires reproducing `rapidfuzz`'s values **byte-for-byte** with **no new
dependency**. `rapidfuzz`'s Jaro-Winkler is ungated, so the port must be ungated too. Crucially, the gate
distinction **can never change a decision** at the 0.92 threshold: with `prefix ≤ 4` and `weight = 0.1`,
the maximum boost is `4·0.1·(1 − jaro) = 0.4·(1 − jaro)`, so the ungated score is at most `jaro + 0.4·(1 −
jaro) = 0.6·jaro + 0.4`. For the boost to matter it would have to lift a `jaro ≤ 0.7` result to `≥ 0.92`,
but `0.6·0.7 + 0.4 = 0.82 < 0.92`. Therefore **any pair reaching the 0.92 threshold already has `jaro >
0.7`**, where gated and ungated agree — the two formulations are decision-equivalent here, and we use the
faithful (ungated) one. (Proven algebraically; consistent with the captured pairs, whose Jaro components
are all well above 0.7.)

**Verified** (hand-rolled, pinned toolchain): `swiggy bangalore`/`swiggy bangaluru` = `0.95`,
`amazon`/`amazon pay` = `0.92`, `acme corp`/`acme corporation` = `0.9125`, `fine dining`/`fine dine` =
`0.9232`, `swiggy order`/`swiggy orders` = `0.9846`, identical = `1.0`; `amazon` pair `>= 0.92` **true**,
`acme` pair `>= 0.92` **false** (Verification harness).

**Alternatives**: Add the `strsim` or `rapidfuzz` crate — rejected: violates the zero-new-dependency gate
(FR-023) and the constitution's "prefer std / small audited deps + justify new runtime deps" posture.
Gate the boost at `jaro > 0.7` — rejected: not what `rapidfuzz` does (parity), and proven irrelevant to
every decision at the 0.92 threshold anyway.

---

## D4 — A Jaro-Winkler similarity is `f64`, **not** money — constitution-compliant

**Decision**: Represent and compare the similarity as `f64`. **All monetary** values remain exact
`Decimal`; amount equality uses `Decimal::normalize` (D7). The `0.92` threshold is a `const f64`.

**Rationale**: The constitution's "money is never a float" rule targets **monetary quantities** (amounts,
balances, totals). A Jaro-Winkler score is a **string-similarity statistic in [0,1]** — the same
legitimate `f64` use the codebase already makes for `Word.x0`/`Word.x1` (glyph x-geometry) and
`ParsedStatement.confidence`. Forcing it into `Decimal` would misrepresent a continuous score and diverge
from `rapidfuzz`'s f64 arithmetic (breaking byte-for-byte parity). FR-011/SC-011 are about money, and
every monetary comparison in the matcher stays `Decimal`.

**Alternatives**: Model similarity as `Decimal` — rejected: not money, breaks f64 parity with `rapidfuzz`,
and buys nothing (the threshold decision is a pure comparison).

---

## D5 — Pin the reference Jaro-Winkler values by **rounding to 4 dp**; the `>= 0.92` decision uses the raw f64

**Decision**: The `dedup.rs` unit tests assert each reference Jaro-Winkler value by **rounding the raw
f64 to 4 decimal places** and comparing to the captured constant, e.g.

```rust
fn round4(v: f64) -> f64 { (v * 10_000.0).round() / 10_000.0 }
assert_eq!(round4(jaro_winkler("fine dining", "fine dine")), 0.9232);
```

The **threshold decision** (`jaro_winkler(a, b) >= JARO_WINKLER_THRESHOLD`) uses the **raw** f64.

**Rationale (verified, important)**: The captured reference values are not all exact f64 literals.
Measured on the pinned toolchain:

| Pair | raw f64 (17 sig figs) | `== <literal>`? | `round4 == <literal>`? |
|---|---|:-:|:-:|
| `swiggy bangalore`/`swiggy bangaluru` (`0.95`) | `0.94999999999999996` | **true** | true |
| `amazon`/`amazon pay` (`0.92`) | `0.92000000000000004` | **true** | true |
| `acme corp`/`acme corporation` (`0.9125`) | `0.91249999999999998` | **true** | true |
| `fine dining`/`fine dine` (`0.9232`) | `0.92323232323232318` | **false** | true |
| `swiggy order`/`swiggy orders` (`0.9846`) | `0.98461538461538467` | **false** | true |

`0.95`/`0.92`/`0.9125` happen to land on their nearest f64, so `==` works; but `0.9232`/`0.9846` are
**4-dp roundings of repeating decimals** (`0.92323232…`, `0.98461538…`) and would **fail** `== 0.9232` /
`== 0.9846`. `rapidfuzz` returns those same full-precision repeating-decimal f64s — so "byte-for-byte vs
rapidfuzz" holds at the f64 level, and the `0.9232`/`0.9846` in the spec are the **displayed 4-dp
captures**. Rounding to 4 dp in the tests pins the reference values unambiguously and avoids brittle
f64-literal equality, while the **decision** stays on the raw f64 (so the inclusive-`0.92` boundary —
`amazon` pair `0.92000000000000004 >= 0.92` → **match**; `acme` pair `0.91249999999999998 >= 0.92` → **no
match**) is exact and robust (there is a comfortable gap between `0.9125` and `0.92`). This is a faithful
encoding of the locked design — the algorithm, values, and decisions are byte-for-byte; only the **test
assertion style** is made correct for repeating decimals.

**Alternatives**: `assert_eq!(jaro_winkler(...), 0.9232)` — rejected: **fails** (proven); the value is a
repeating decimal. An epsilon compare (`(v − 0.9232).abs() < 1e-9`) — acceptable and equivalent, but 4-dp
rounding matches the captured precision and reads more clearly; either is fine, tests use `round4`.

---

## D6 — Result types: `DedupLayer` enum + `CrossSourceMatch` record (mirrors `ReconcileStatus`/`ReconcileResult`)

**Decision**:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum DedupLayer { Canonical, Fuzzy }

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CrossSourceMatch {
    pub incoming_index: u32,
    pub existing_index: u32,
    pub layer: DedupLayer,
}

const JARO_WINKLER_THRESHOLD: f64 = 0.92;
```

`DedupLayer` derives exactly like `ChainStatus`/`ReconcileStatus` (fieldless enum → `Copy` + `Eq` safe →
Swift `.canonical`/`.fuzzy`). `CrossSourceMatch` derives like `ChainResult`/`ReconcileResult`
(`Debug/Clone/PartialEq/uniffi::Record`; **no** `Copy`/`Eq` needed, but the fields are all `Copy`, so
value-equality in tests is trivial → Swift `incomingIndex`/`existingIndex`/`layer`).

**Rationale**: FR-001/FR-015 require each match to name the incoming row, the existing row it duplicates,
and the layer. A `uniffi::Record` with two indices + a layer enum is the minimal faithful shape and
mirrors the established "typed record across the bridge" pattern (`ChainResult`, `ReconcileResult`). The
`JARO_WINKLER_THRESHOLD` constant pins the inclusive 0.92 (FR-009).

**Alternatives**: Return `Vec<(Transaction, Transaction, DedupLayer)>` (by value) — rejected: duplicates
row data across the bridge, loses the caller's identity/positional handle, and complicates multiplicity
reasoning. A single "annotated transaction list" — rejected: the spec's result is the **set of matches**,
and survivors are simply "absent from it" (FR-001).

---

## D7 — `cross_source_duplicates`: canonical-then-fuzzy, multiplicity via a `consumed` vector, first-unconsumed-wins

**Decision**:

```rust
pub fn cross_source_duplicates(
    existing: &[Transaction],
    incoming: &[Transaction],
) -> Vec<CrossSourceMatch>
```

- **Precompute** `normalize_narration` for every existing and incoming row **once** (two `Vec<String>`),
  so the per-pair inner loop never re-normalises.
- `let mut consumed = vec![false; existing.len()];` — the multiplicity guard (each existing row matched
  **at most once**).
- For each `incoming[i]` in order:
  1. **Canonical pass** (tried first): scan `existing` in order for the **first unconsumed** `e` with
     `existing[e].date == incoming[i].date` **and** amounts equal **and** `existing[e].direction ==
     incoming[i].direction` **and** the **60-char prefix** of the two normalised narrations equal
     (`norm.chars().take(60).collect::<String>()`). On hit → push `CrossSourceMatch { incoming_index: i,
     existing_index: e, layer: Canonical }`, set `consumed[e] = true`, **continue** to the next incoming
     row.
  2. **Fuzzy pass** (only if no canonical hit): scan `existing` in order for the **first unconsumed** `e`
     with amounts equal **and** directions equal **and** `(existing[e].date −
     incoming[i].date).num_days().abs() <= 1` **and** `jaro_winkler(&norm_e, &norm_i) >=
     JARO_WINKLER_THRESHOLD`. On hit → push `{ i, e, Fuzzy }`, set `consumed[e] = true`, **continue**.
  3. No hit → `incoming[i]` is a **survivor** (no match emitted).
- **Amount equality**: `a.normalize() == b.normalize()` — `Decimal` **value** equality ignoring scale
  (`250.00` == `250.0`), matching the web SQL `NUMERIC amount = :amount` and mirroring how
  `dedup_fingerprint` already normalises. **Direction** is `Direction` equality — never re-derived from
  sign.
- Pure/total/deterministic; borrows both slices (`&`), never mutates either.

**Rationale**: This is the faithful pure subset of the web per-incoming L1→L5 ladder restricted to L3+L4:
canonical precedence (FR-004/US6), the ±1-day window and inclusive 0.92 for fuzzy (FR-008/009), and the
at-most-one-consumption multiplicity that keeps surplus genuine repeats alive (FR-003/US3). The
`consumed` vector + "first unconsumed in existing order wins" is the deterministic tie-break (US6, SC-007).
Precomputing the normalised narrations keeps it a clean two-pass-per-incoming scan.

**Verified**: `250.00 == 250.0` under `Decimal::normalize`; `(date − date).num_days().abs() <= 1` treats
0- and 1-day gaps as within window and ≥2 as outside; `chars().take(60)` caps the prefix by scalar (not
byte). See Verification harness + D5.

**Alternatives**: Fuzzy-before-canonical or "best score wins" — rejected: the web ladder is canonical
(L3) **then** fuzzy (L4), first-candidate-wins, not best-match (parity). A `HashSet` of consumed indices —
rejected: a `Vec<bool>` is simpler, allocation-light, and order-preserving.

---

## D8 — Match rows **by index** (`u32`), not by value or id

**Decision**: `CrossSourceMatch` carries `incoming_index`/`existing_index` as `u32` (positions in the
caller's input slices).

**Rationale**: `Transaction` has no identity field, and the shared type crosses UniFFI as a `Record`
(value type). Positional indices are the stable, minimal way to name "which incoming duplicates which
existing" without copying row data or inventing an id, and they make multiplicity explicit (two incoming
indices can never point at the same existing index because that existing index is consumed after the
first). `u32` matches UniFFI's natural unsigned integer and is ample for statement-sized lists. The caller
already holds both `Vec<Transaction>`, so indices are directly dereferenceable.

**Alternatives**: `usize` — rejected: UniFFI prefers fixed-width; `u32` is the idiomatic FFI choice and
plenty. Embedding both `Transaction` values — rejected (D6).

---

## D9 — FFI wrapper mirrors `reconcile_statement`; re-export the **FFI** function at the crate root

**Decision**: In `ffi.rs`:

```rust
use crate::dedup::{cross_source_duplicates, CrossSourceMatch};

#[uniffi::export]
pub fn cross_source_duplicates(
    existing: Vec<Transaction>,
    incoming: Vec<Transaction>,
) -> Vec<CrossSourceMatch> {
    crate::dedup::cross_source_duplicates(&existing, &incoming)
}
```

`Transaction` is already imported in `ffi.rs`. In `lib.rs`:

- `pub use ffi::cross_source_duplicates;` — the **FFI wrapper** (owned `Vec` args, the Swift-facing entry).
- `pub use dedup::{CrossSourceMatch, DedupLayer, normalize_narration};` — the types + the narration helper
  (for tests/consumers).
- **Do NOT** `pub use dedup::cross_source_duplicates` at the crate root — it would **name-clash** with the
  FFI wrapper. `tests/parity.rs` uses the FFI-exported one via `kaname_core::cross_source_duplicates`.

**Rationale**: This is the exact `reconcile_statement`-wraps-`reconcile` precedent (owned args at the FFI
boundary, borrowed slices in the pure core). The same-name-different-module wrapper keeps the Swift API
name identical to the domain function while the crate root exposes exactly one `cross_source_duplicates`
(the FFI one), avoiding an ambiguous glob. The types derive `uniffi`, so bindgen emits their Swift forms;
**no `uniffi.toml` change** (the `Decimal`/`NaiveDate` custom types on `Transaction` are already wired).

**Alternatives**: Re-export the pure function under a different name (`cross_source_duplicates_core`) —
rejected: unnecessary surface; the FFI wrapper is the single public entry, and the pure fn is reachable
in-crate via `crate::dedup::…` for unit tests. Export the pure fn and skip the wrapper — rejected: UniFFI
exports cannot take borrowed slices, and the codebase's convention (`reconcile_statement`) is the owned
wrapper.

---

## D10 — A **new fixture shape** for dedup (two lists + expected matches), not a statement

**Decision**: Add `fixtures/dedup/cross_source/basic.json` with a **new** shape:

```json
{
  "_comment": "…synthetic, no real data; expected matches captured from the web normalise_narration + rapidfuzz L3/L4 logic…",
  "existing": [ { "date": "YYYY-MM-DD", "description": "…", "amount": "…", "direction": "Debit|Credit" }, … ],
  "incoming": [ … ],
  "expected_matches": [ { "incoming_index": <u32>, "existing_index": <u32>, "layer": "Canonical|Fuzzy" }, … ]
}
```

Amounts are **JSON strings** (re-parsed to `Decimal`, never `f64`); `direction` is `"Debit"`/`"Credit"`;
`layer` is `"Canonical"`/`"Fuzzy"`. The scenario covers a **canonical** match, a **fuzzy ±1-day** match, a
**below-threshold** survivor, a **direction-guard** survivor, and a **multiplicity** survivor. Exact bytes
in [`contracts/golden-fixture.md`](./contracts/golden-fixture.md).

**Rationale**: The existing fixtures are per-statement (`lines`/`full_text`/`expected.rows`); the matcher's
input is **two already-parsed transaction lists**, so it needs a distinct schema. Keeping amounts as
strings preserves the "no `f64` touches money" rule (fixtures README) and the exact-decimal comparison.
The new `dedup/cross_source/` path matches the fixtures README's advertised "Cross-source dedup" category.

**Alternatives**: Encode the two lists as statements and re-parse — rejected: the matcher takes parsed
`Transaction`s, not raw statement text; that would drag in reader coupling the slice explicitly avoids.

---

## D11 — Parity harness: a **separate** dedup loader + one test; statement `CASES` untouched

**Decision**: In `tests/parity.rs`, add dedup-only fixture structs and a loader that maps
`existing`/`incoming` JSON rows → `Vec<Transaction>` via `Transaction::new` (parsing the string amount to
`Decimal` and the date to `NaiveDate`, exactly as the statement loader does), plus:

```rust
#[test]
fn cross_source_dedup_matches_expected() {
    // load fixtures/dedup/cross_source/basic.json → existing, incoming, expected_matches
    let got = cross_source_duplicates(existing, incoming);
    // assert got == expected (incoming_index / existing_index / layer)
}
```

Import `cross_source_duplicates`, `CrossSourceMatch`, `DedupLayer`, `Transaction` from `kaname_core`. The
existing statement `Fixture`/`Expected`/`CASES` and every current test are **left byte-for-byte
unchanged**.

**Rationale**: The dedup fixture shape differs from the statement shape, so a small dedicated
loader/struct is cleaner than overloading `Expected`. Reusing the string→`Decimal`/`NaiveDate` re-parse
keeps money exact and parity determinism identical. One focused parity test pins the golden vector against
the web-captured expected matches (FR-020, SC-013).

**Alternatives**: Fold dedup into the statement `CASES` table — rejected: incompatible shapes; would
muddy the reader-parity loop.

---

## D12 — Swift bridge test mirrors `ReconcileTests`; own-line comments only

**Decision**: New `ios/Tests/CrossSourceDedupTests.swift` (Swift Testing, `import KanameCore`) builds
`[Transaction]` `existing` + `incoming` (the existing uniffi `Transaction` Record: `date` ISO string,
`description`, `amount` `Decimal`, `direction`), calls `crossSourceDuplicates(existing:incoming:)`, and
asserts a **canonical** match, a **fuzzy** match, and a **multiplicity survivor** (2 identical incoming vs
1 existing → exactly 1 match). `DedupLayer` surfaces as `.canonical`/`.fuzzy`; `CrossSourceMatch` as
`incomingIndex`/`existingIndex`/`layer`. Requires `make core-xcframework` **before** `tuist generate`.

**Rationale**: This is the `ReconcileTests` precedent — prove the engine's result crosses the bridge with
the right shape (US8, SC-014). Building `Transaction` values directly (no reader) keeps the test focused on
the matcher. `Decimal(string:locale:)` with `en_US_POSIX` matches the reconcile test's money construction.

**swift-format `[Spacing]` constraint**: **no trailing inline `//` comment after code** — put any comment
on its **own line above** the statement, or `make lint` fails (the same rule `ReconcileTests.swift`
follows).

**Alternatives**: XCUITest/snapshot — rejected: no UI this slice; a unit-level bridge test is the right
scope.

---

## Web-engine mapping (parity target)

| Web (`deduplicator.py` / `normaliser.py` / `rapidfuzz`) | On-device (`dedup.rs`) |
|---|---|
| `normalise_narration(text)` — strip rail prefixes (looped), RRN tokens, trailing refnum; collapse ws; lower | `normalize_narration(raw)` — same four regexes, same order (D2) |
| **L3 CANONICAL** — same date + amount + direction + narration-prefix key | Canonical pass — `date ==`, `amount.normalize() ==`, `direction ==`, 60-char prefix `==` (D7) |
| **L4 FUZZY** — same amount + direction, `|Δdays| ≤ 1`, `rapidfuzz.JaroWinkler ≥ 0.92` | Fuzzy pass — same guards + hand-rolled `jaro_winkler >= 0.92` (D3/D7) |
| DB row consumed once (`UPDATE … WHERE id`) | `consumed: Vec<bool>` — each existing matched at most once (D7) |
| Per-incoming L1→L5, first hit wins | Canonical-then-fuzzy, first unconsumed wins (D7) |
| **L1/L2/L5 + SUPERSEDE** (source_ref, exact-hash, merchant, amount-drift) | **Excluded** — need DB/merchant/persistence (Complexity Tracking, FR-012) |

---

## Verification harness (run before writing this plan; removed after — repo clean)

Two throwaway programs on the pinned stable toolchain (`stable-aarch64-apple-darwin`):

1. **`normalize_narration`** against the real `regex 1` crate (a `/tmp` cargo project) — all five captured
   reference outputs matched **exactly**, and stacked prefixes collapsed:

   | Input | Output |
   |---|---|
   | `UPI-SWIGGY-RRN1234` | `swiggy-` |
   | `POS SWIGGY BANGALORE 12345678901234` | `swiggy bangalore` |
   | `NEFT/ACME CORP/REF999` | `acme corp/ref999` |
   | `BY TRANSFER-Salary Credit RRN5678` | `salary credit` |
   | `SWIGGY  ORDER   9988776655` | `swiggy order` |
   | `UPI/POS Coffee Day` (stacked-prefix probe) | `coffee day` |
   | `Swiggy Bangalore` / `swiggy   bangalore` (US1 peers) | `swiggy bangalore` (shared 60-char prefix) |

2. **Hand-rolled `jaro`/`jaro_winkler`** (pure `rustc -O`) — reproduced every captured `rapidfuzz` value
   and the threshold decisions (raw f64 shown; see D5 for the 4-dp assertion nuance):

   | Pair | raw f64 | 4-dp | `>= 0.92` |
   |---|---|---|:-:|
   | `swiggy bangalore` / `swiggy bangaluru` | `0.94999999999999996` | `0.9500` | match |
   | `amazon` / `amazon pay` | `0.92000000000000004` | `0.9200` | **match (inclusive)** |
   | `acme corp` / `acme corporation` | `0.91249999999999998` | `0.9125` | **no match** |
   | `fine dining` / `fine dine` | `0.92323232323232318` | `0.9232` | match |
   | `swiggy order` / `swiggy orders` | `0.98461538461538467` | `0.9846` | match |
   | `swiggy` / `swiggy` | `1.00000000000000000` | `1.0000` | match |

These reproduce the web engine's decisions exactly and confirm **no genuine design conflict** — only the
4-dp assertion nuance (D5), which is encoded faithfully in the unit tests. The current core suite is green
prior to this slice; the new tests are added test-first (FR-022).

---

## Open items

**None.** All behaviour is pinned to the web engine and verified. No new dependency, no `uniffi.toml`
change, no reader/model change. Phase 1 encodes the types, the algorithm, the contracts, and the golden
fixture bytes.
