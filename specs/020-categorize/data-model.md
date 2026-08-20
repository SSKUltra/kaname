# Data Model: Categorize

**Feature**: 020-categorize | **Date**: 2026-08-18
**Sources**: [`spec.md`](./spec.md), [`research.md`](./research.md), `store.rs`, `categorize.rs`

This document fixes the storage, the predicates, and every type that crosses a boundary. It is the
document a reviewer should be able to hold against a diff.

---

## 1. Storage — schema v8

`SCHEMA_VERSION` goes `7 → 8` (`store.rs:41`). The migration is applied by `apply_migration`
(`store.rs:1521-1544`) through `migrate()` (`store.rs:1258-1273`), which runs one version at a
time inside a transaction that carries its own `PRAGMA user_version` bump.

### 1.1 The one migration

```sql
-- SCHEMA_V8 — additive only. Reads no row. Writes no row. Drops nothing.
CREATE TABLE IF NOT EXISTS merchant_memory (
    merchant_portion TEXT PRIMARY KEY,
    category_id      TEXT NOT NULL REFERENCES categories(id)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_txn_unanswered_account_date
    ON transactions(account_id, date DESC)
    WHERE is_deleted = 0
      AND superseded_by IS NULL
      AND category_id IS NULL
      AND categorised_by IS NULL;
```

**Why this is the whole migration.** Because provenance is carried by a **reserved value** in the
existing `categorised_by` column rather than by a new column or a new table (research R5), the
`transactions` table is not altered at all. No `ALTER TABLE`, no table rebuild, no backfill, no
row read. FR-047 ("every existing transaction keeps its category, amount, date, description,
account and provenance exactly") and SC-014 are therefore true **by construction**: there is no
statement in v8 that could make them false. FR-048/SC-015 (a failed migration leaves v7 intact)
are properties of `migrate()`'s existing per-version transaction and need no new machinery.

### 1.2 `merchant_memory` — field by field

| Column | Type | Constraint | Why |
|---|---|---|---|
| `merchant_portion` | `TEXT` | `PRIMARY KEY` | The derived portion (§3.1), lowercase, already normalized. **Primary key, not indexed-unique**: FR-031 ("at most one memory per merchant portion at any time") becomes *unrepresentable otherwise* rather than *enforced by care*. The lookup FR-030 needs is the PK lookup. |
| `category_id` | `TEXT` | `NOT NULL REFERENCES categories(id)` | `NOT NULL` because a memory of *no category* is not formed (plan §4, spec amendment §3), so nullability would only ever encode a bug. The FK is the same shape `merchant_map` uses (`store.rs:99-105`) and gives FR-034 (a memory naming a category that no longer exists cannot exist) for free. |

**No `priority`.** One memory per portion; nothing to order.

**No `created_at`/`updated_at`.** FR-033's newest-wins is achieved by `INSERT … ON CONFLICT
(merchant_portion) DO UPDATE SET category_id = excluded.category_id` — the old memory is *replaced*,
not out-ranked. This is deliberate: the engine reads no clock (Principle II), and a timestamp is a
non-deterministic input that a fixture cannot pin. Research R7.

**No `account_id`.** FR-030 is store-wide by design; a memory is about a shop, not about a card.

### 1.3 The index, and what it is for

`idx_txn_unanswered_account_date` mirrors v7's `idx_txn_live_account_date`
(`store.rs:193-198`) with the two unanswered clauses appended. Its `WHERE` is the byte-identical
concatenation of `LIVE` and `unanswered_predicate!()` (§2), in that order.

Measured plans (research R13, SQLite 3.45.3):

| Query | v7 plan | v8 plan |
|---|---|---|
| `PAGE_SQL` (018's page, unchanged) | `SEARCH t USING INDEX idx_txn_live_account_date (account_id=? AND date<?)` | **identical** |
| Narrowed page (uncategorized, one account) | `SEARCH t USING INDEX idx_txn_live_account_date (account_id=? AND date<?)` | `SEARCH t USING INDEX idx_txn_unanswered_account_date (account_id=? AND date<?)` |
| Store-wide unanswered count | `SCAN transactions USING INDEX idx_txn_live_account_date` | `SCAN transactions USING INDEX idx_txn_unanswered_account_date` |

Two consequences that the contract turns into assertions:

- **`s1`/`s2` cannot regress.** The new index's `WHERE` is not implied by `PAGE_SQL`'s `WHERE`, so
  SQLite cannot choose it for `PAGE_SQL`. The plan is byte-identical, measured.
- ⚠️ **The count's correct plan is a `SCAN`.** Of a partial index containing only the rows being
  counted — which is what makes it get cheaper as the person works. A plan-shape test copied from
  `s1` (which asserts no step contains `"SCAN"`) would be **red for the right query**. The count's
  test asserts the index *name* instead. See [`contracts/engine-categorize.md`](./contracts/engine-categorize.md) §4.

### 1.4 What does **not** change

- No column is added to, removed from, or retyped in `transactions` (`store.rs:73-87`).
- **No `CHECK` is added to `categorised_by`.** It is `TEXT`, nullable, unconstrained today, and
  nothing in the repository parses it back into a `Stage` — `stage_to_sql` exists
  (`store.rs:2148-2155`), `stage_from_sql` does not. A new value therefore cannot break a reader,
  and adding a `CHECK` would require rebuilding the table this migration's whole design avoids
  touching. Research R5.
- `merchant_map` (`store.rs:99-105`) keeps its schema, its semantics, its `list_merchant_rules()`
  export, and its emptiness. Judgement call §1.
- `categories`, `accounts`, `statements`, `transfer_groups`: untouched.

---

## 2. The three predicates

The repository's existing discipline (`store.rs:175-186`) is that a rule appearing in more than one
query is a macro, spelled once, byte-identical to any index that must serve it. This slice adds two
more to that discipline; it does not invent a second mechanism.

```rust
// UNCHANGED — store.rs:175-186. Byte-identical to idx_txn_live_account_date's WHERE.
macro_rules! live_predicate { () => { "is_deleted = 0 AND superseded_by IS NULL" }; }
const LIVE: &str = live_predicate!();

// NEW — the rows the worklist is about. Spec amendment §1: the person's deliberate
// blank (category_id NULL, categorised_by 'PERSON') is NOT unanswered.
macro_rules! unanswered_predicate {
    () => { "category_id IS NULL AND categorised_by IS NULL" };
}
const UNANSWERED: &str = unanswered_predicate!();

// NEW — the rows the engine is still allowed to decide about.
macro_rules! engine_may_decide {
    () => { "(categorised_by IS NULL OR categorised_by NOT IN ('PERSON', 'PERSON_MEMORY'))" };
}
const ENGINE_MAY_DECIDE: &str = engine_may_decide!();
```

🚨 **The `IS NULL OR` is load-bearing and must never be "simplified".** `NULL NOT IN ('PERSON',
'PERSON_MEMORY')` evaluates to `NULL`, not `TRUE`, so the shorter spelling excludes every row
`import_statement` has just inserted — its bulk insert writes `NULL, NULL` literally
(`store.rs:855-870`). Every import would land wholly uncategorized and nothing would error.
Measured with real rows in research R10. A regression test asserting a **non-zero** categorized
count after a fresh import is part of the contract, and it is the test that fails against the
naive spelling.

**Where each is used.**

| Predicate | Used by |
|---|---|
| `LIVE` | `PAGE_SQL`, `account_summaries`, `grouped_counts`, `load_account_transactions`, and — concatenated — both new queries |
| `UNANSWERED` | the narrowed page, `uncategorized_count()`, and the v8 index's `WHERE` |
| `ENGINE_MAY_DECIDE` | `load_account_transactions`'s filter (so `categorize_account_in` never loads a person's row) and `detect_transfers`'s `UPDATE` (spec amendment §6, judgement call §3) |

---

## 3. Engine types

### 3.1 Derivation — `core/crates/kaname-core/src/merchant.rs` (new)

```rust
/// The stable merchant portion of a narration, or None when there is nothing
/// specific enough to remember. Pure: no clock, no locale, no store.
#[uniffi::export]
pub fn merchant_portion(narration: &str) -> Option<String>;
```

Exported as a **free function** so the interface can show the portion *before* the memory forms
(FR-026a) without a store round-trip and without a second implementation.

The rule, fixed (FR-027a, research R14). Four ordered steps:

1. **Normalize** — call `dedup::normalize_narration` unchanged (FR-027c). It lowercases, strips a
   leading `UPI/`/`UPI-`/`NEFT/`/`IMPS/`/`POS-`-style prefix when its regex matches, drops runs of
   ≥4 digits, and collapses whitespace.
2. **Split** on the separator set: whitespace and `- / \ | * : ; , # _ % ( ) [ ] " '`.
   ⚠️ **`@` and `.` are deliberately *not* separators.** A VPA is one stable token — splitting
   `name@paytm` would force PSP handles into the stop-list, and `paytm` is also a merchant name,
   which FR-027a forbids the stop-list from containing. `.` stays so `amazon.in` survives whole.
3. **Drop** every segment in the closed stop-list: 69 words in five documented groups — channel,
   channel-modifier, instrument, payment scaffolding, narration function words. **Zero merchant
   names.** Also drop pure-numeric and single-character segments.
4. **Keep** the first **2** remaining segments, joined by a single space. Fewer than 1 → `None`.

**Why 2.** Fewer segments generalize *more* and are therefore more dangerous — the spec is explicit
that over-broad is the direction that cannot be rescued. 1 collapses `blue tokai` to `blue`;
3 keeps the city and splits a chain per outlet. Measured against every literal narration in the
repository in research R14.

**Validated behaviour** (research R14, real repository strings):

| Narration | Portion |
|---|---|
| `UPI-SWIGGY-123456`, `UPI-SWIGGY-1`, `UPI-SWIGGY`, `UPI-SWIGGY-RRN1234` | `swiggy` — all four, which is SC-008 demonstrated with strings already in the repo |
| `POS/BLUE TOKAI COFFEE/MUMBAI` | `blue tokai` |
| `ATM CASH WITHDRAWAL`, `CC PAYMENT RECEIVED`, `4262 BBPS Payment received`, `ONLINE TRF - PYMT RECD - THANK YOU`, `PAYMENT RECEIVED BBPS - Ref No: RT0001`, `TO ECM/600000000001 TFR`, `""` | `None` — FR-027d |

⚠️ **Three priced limitations**, carried openly (research R15): `NEFT-N123-EMPLOYER…` → `n123
employer`, because `normalize_narration`'s prefix regex matches `NEFT/` but not `NEFT-` and a
3-digit ref survives the ≥4-digit rule; `MTR1924 LALBAGH` → `lalbagh`, because a merchant whose own
name carries ≥4 digits loses it, leaving an over-broad location; and `swiggy` (UPI) ≠ `swiggy
bangalore` (POS) under FR-027b's exact equality. All three could be fixed by editing
`normalize_narration` — which is exactly what Q2's answer **B** refused, because de-duplication
depends on it and the dedup fixtures must stay unedited.

### 3.2 Records crossing the FFI

```rust
#[derive(uniffi::Record)]
pub struct MemoryImpact {
    /// Every live row the second action would change, ids only.
    /// Round-tripped back into apply_memory as the stale-set token.
    pub transaction_ids: Vec<String>,
    /// FR-035c — which accounts, so the blast radius is stated in a person's terms.
    pub accounts: Vec<AccountImpact>,
}

#[derive(uniffi::Record)]
pub struct AccountImpact { pub account_id: String, pub display_name: String, pub count: u32 }

#[derive(uniffi::Record)]
pub struct CorrectionOutcome {
    /// None when the correction was to "no category", or when derivation found
    /// nothing specific enough. The interface says so plainly; no memory forms.
    pub merchant_portion: Option<String>,
    /// True when a memory was written or replaced.
    pub memory_formed: bool,
}
```

**Ids, not a digest, as the staleness token** (research R17): no hashing crate is needed, the
count and the accounts come out of the same call, and — crucially — **set equality** is what
enforces FR-035b in the engine. A caller that trims the list to "just these three" is *refused*,
not obeyed. That is why this is equality and not a subset check.

### 3.3 Changed records

```rust
pub struct HistoryQuery {
    pub account_id: Option<String>,
    pub cursor: Option<HistoryCursor>,
    pub limit: u32,
    pub uncategorized_only: bool,   // NEW — FR-038; composes with account_id (FR-039)
}

pub struct HistoryRow {
    /* … existing fields unchanged … */
    pub category_id: Option<String>,  // NEW — the picker must mark the current choice
}
```

`category_id`, not the name: matching by display name would be fragile and would put an identity
decision in the view. `category_name` already exists for display.

### 3.4 New and changed `Store` methods

All on the single `#[uniffi::export] impl Store` block (`store.rs:571`). ⚠️ There is no
`core/src/ffi.rs`; `Store`'s methods are exported from `store.rs` (research R1).

| Method | Purpose |
|---|---|
| `set_transaction_category(transaction_id, category: Option<CategoryRef>, remember: bool) -> CorrectionOutcome` | FR-004–FR-007, FR-026. Writes `category_id` and `categorised_by = 'PERSON'`; forms or replaces the memory when `remember` and a portion exists and the category is `Some`. One transaction. |
| `preview_memory_application(merchant_portion) -> MemoryImpact` | FR-035a–FR-035d. Read-only. |
| `apply_memory(merchant_portion, expected_transaction_ids) -> u32` | FR-035e–FR-035h. Recomputes the set inside the writing transaction; **`StaleSet` unless the sets are equal**; writes `categorised_by = 'PERSON_MEMORY'`; all-or-nothing. |
| `uncategorized_count() -> u32` | FR-041b, FR-043. Store-wide, engine-side. |
| `history_page(query)` | unchanged signature; honours `uncategorized_only`. |
| `load_account_transactions` (private) | gains `AND <ENGINE_MAY_DECIDE>`. |
| `detect_transfers` (existing) | its `UPDATE` gains `AND <ENGINE_MAY_DECIDE>`. |

```rust
pub enum StoreError {
    /* … existing variants … */
    #[error("the set of affected transactions changed ({expected} expected, {found} found)")]
    StaleSet { expected: u32, found: u32 },   // NEW — FR-035f
}
```

### 3.5 The affected-set predicate (used identically by preview and apply)

```text
LIVE
  AND merchant_portion(narration) == :portion      -- derived in Rust, exact equality
  AND categorised_by IS NOT 'PERSON'               -- FR-035d: never a hand correction
  AND NOT (categorised_by IS 'PERSON_MEMORY'
           AND category_id IS :category_id)        -- already carrying THIS memory
```

The last clause makes a re-run a true no-op (FR-035h) and, with amendment §2's two provenance
values, satisfies FR-031a (a *later* offer includes rows the previous one changed) and FR-035d
(a hand correction is never touched or counted) simultaneously. Note `IS`/`IS NOT`, not `=`/`!=` —
the same three-valued-logic hazard as §2.

---

## 4. Platform types (Swift)

All in `ios/Sources/Categorize/` unless stated. ⚠️ Nothing goes in
`ios/Sources/Import/ImportService.swift` (398/400 lines).

```swift
// Categorize/TransactionScope.swift — the two-axis route.
struct TransactionScope: Hashable, Codable {
    var filter: AccountFilter          // reuses 018's type unchanged
    var uncategorizedOnly: Bool
}
```

018's `.navigationDestination(for: AccountFilter.self)` (`RootView.swift:16-33`) becomes
`for: TransactionScope.self`. The nav *value type* changes; the nav *behaviour* does not.

```swift
// Categorize/CategoryCatalog.swift — pure, unit-testable, no engine call.
struct CategoryCatalog {
    static func grouped(_ categories: [Category]) -> [(Classification?, [Category])]
}
```

FR-016's grouping comes from the engine's own `Category.classification: Option<Classification>`
(`categorize.rs:68-72`) — Spend / Income / Investment / Transfer / CcPayment / Refund. The view
invents no taxonomy of its own.

```swift
// Categorize/CategorizeService.swift — the actor; this slice's only engine caller.
actor CategorizeService {
    func correct(_ id: String, to: CategoryRef?, remember: Bool) async throws -> CorrectionOutcome
    func previewMemory(_ portion: String) async throws -> MemoryImpact
    func applyMemory(_ portion: String, expecting ids: [String]) async throws -> UInt32
    func uncategorizedCount() async throws -> UInt32
}
```

No method returns a filtered, counted or aggregated derivative of a broader read — FR-076/FR-078,
mechanically watched once the four scans are widened (judgement call §6).

**Strings.** `CategorizeStrings.swift` holds every new string. It **references**
`TransactionListStrings.uncategorized` (`TransactionListStrings.swift:65`) and never redeclares it
— FR-002 requires one definition for that word. Every string is in a person's vocabulary; none
contains `T1`, `T2`, `stage`, `rule`, `heuristic` or `merchant map` (FR-029, SC-007).

---

## 5. State transitions

A transaction's category has four reachable provenance states. The columns are `category_id` and
`categorised_by`.

| State | `category_id` | `categorised_by` | Reachable from |
|---|---|---|---|
| **Unanswered** | `NULL` | `NULL` | fresh import where the stack had no answer; this is the worklist |
| **Engine-decided** | set | `T0_CC_RULE` / `T1_…` / `T2_…` / `T3_…` / `TRANSFER_DETECTOR` | the stack, or transfer detection |
| **Person-decided** | set **or** `NULL` | `PERSON` | FR-004 (a category) or FR-007 (deliberately blank) |
| **Person-decided via memory** | set | `PERSON_MEMORY` | the second action, or a later import matching a memory |

```text
Unanswered ──── import runs the stack ───▶ Engine-decided
Unanswered ──── person corrects ─────────▶ Person-decided
Engine-decided ─ person corrects ────────▶ Person-decided
Engine-decided ─ second action / import ─▶ Person-decided via memory
Person-decided via memory ─ person corrects ▶ Person-decided
Person-decided ─────────── ANY engine path ▶ (refused: ENGINE_MAY_DECIDE)
Person-decided via memory ─ ANY engine path ▶ (refused: ENGINE_MAY_DECIDE)
```

Two arrows that must **not** exist, and the tests that prove they do not:

- `Person-decided → Unanswered`. Today this is the shipped defect:
  `categorize_account_in`'s unconditional `UPDATE … SET category_id = NULL, categorised_by = NULL`
  (`store.rs:1304`) via `import_statement` (`store.rs:825`). Test: correct a row, re-import, assert
  the correction stands. **Must be watched failing before the guard lands.**
- `Person-decided → Engine-decided` via `detect_transfers`. Its `UPDATE` is guarded on
  `transfer_group_id IS NULL` only (`store.rs:1160-1166`). Judgement call §3.

The engine never transitions **out of** `PERSON` or `PERSON_MEMORY`. Only a person does.

---

## 6. Empty states — the grown decision table

018's `EmptyKind.decide(summaries:filter:)` (`TransactionListModels.swift:161-197`) is a **pure
function** of `[AccountSummary]` and the filter. It grows one parameter:
`decide(summaries:filter:uncategorizedOnly:)`.

**No new `AccountSummary` field is needed**, and that is worth stating because it looks like it
should be. "This account has live rows but the narrowed page came back empty" ⇒ *every row in it
is answered*. That inference is exact, so the "you have finished this account" state (FR-042b) is
derivable from data the engine already returns.

| Filter | Narrowed | Live rows exist | State | Reachable by a seed? |
|---|---|---|---|---|
| All | no | no | `noStatements` (018) | yes — `empty` |
| All | no | yes | list | yes — any |
| One account | no | none in it | `accountEmpty` (018) | yes |
| **All** | **yes** | **none unanswered, none at all** | `noStatements` — nothing imported beats "all done" | yes — `empty` |
| **All** | **yes** | **rows exist, none unanswered** | **`allAnswered`** — FR-042b, and the reward SC-011 is about | yes — `basic` |
| **All** | **yes** | **some unanswered** | list | yes — `unfiled` |
| **One account** | **yes** | **rows exist, none unanswered in it** | **`accountAnswered`** | yes — `unfiled` + filter |
| **One account** | **yes** | **some unanswered in it** | list | yes — `unfiled` |
| One account | either | account has no live rows at all | `accountEmpty` (018) | yes |

**Unreachable combinations, named with their structural reason** (FR-042a — the requirement is to
say *why*, not to invent a state):

- *Narrowed, but the account was deleted mid-session* — there is no delete path in this slice, in
  018, or in 019. `019/02` names a category feature **with a delete path** as what would make its
  two unreachable cases reachable; this slice adds none, so **`019/02` stays open**.
- *Narrowed, count > 0, page empty* — both come from the same predicate in the same engine
  (`UNANSWERED`), so they cannot disagree. This is the strongest argument for Q3-C's
  "count from the engine": the Swift-side alternative would make this state reachable by drift.

---

## 7. Test corpus — the fixture contract

| Fixture | Status | Contents |
|---|---|---|
| `fixtures/categorization/basic.json` | **UNCHANGED — zero expectation edits** | `categorize.rs` is not modified (research R8), so parity cannot move. FR-027c is structural, not a promise. |
| `fixtures/dedup/cross_source/basic.json` | **UNCHANGED** | `normalize_narration` is not modified. |
| `fixtures/categorization/merchant_portion.json` | **NEW** | `{ narration, expected_portion \| null }`. Must include: the four `UPI-SWIGGY-*` shapes collapsing to one portion (SC-008); every FR-027d `None` case; the two-segment cases; the empty string; **and the three priced limitations of research R15, asserted as they actually behave** — a fixture that encodes the rule's known weaknesses is a fixture that will tell the next person when they change. |

🚨 **What the fixtures cannot do** (research R16). This repository has correctly never contained a
real bank statement, so no fixture here can prove the derivation is adequate against the real
diversity of Indian narrations — there is not one real VPA or UPI-handle shape anywhere in the
repo. The fixture proves the rule is **deterministic, fixture-testable and stable across the shapes
we have**. It does not prove it is *right* for a real person's statement. That limit is a
consequence of Principle I, is accepted rather than worked around, and is restated in
[`quickstart.md`](./quickstart.md) so it is not quietly forgotten.

### Seed scenarios (DEBUG only, `ios/Sources/DebugSeed/SeedScenarios.swift:116`)

| Scenario | For | ⚠️ The trap it must dodge |
|---|---|---|
| `unfiled` | FR-066 — rows the engine could not place | Its narrations must derive to portions with **no** built-in rule, or the seeded rows arrive categorized and the worklist is empty. |
| `repeated` | FR-066 — one merchant across statements | The repeats must span **two statements of the same account**, so they are not dedup candidates. |
| `crossing` | FR-035c — a memory whose blast radius spans accounts | 🚨 Cross-source dedup compares **a ledger against a card and nothing else** (018 R17's blunt guard). A ledger+card pair on the same date and amount is exactly what it does compare — so the crossing rows must differ in amount or date, or the blast radius shown would be wrong before anyone tested it. |

⚠️ Launch environment is the **bare** key `KANAME_SEED_SCENARIO`; the `TEST_RUNNER_` prefix is for
app-hosted unit tests and is silently never delivered to a UI test. A seeded store outlives the
suite that wrote it — reset with the `empty` scenario. Pin `en_IN`; keep amounts under ₹1,00,000.
A `List` renders a screenful, not a list. A row's sentence hangs on a `StaticText` inside the cell,
and a date heading is a cell too. A label **cannot** demonstrate a truncation — XCUITest reports a
`Text`'s string, not its glyphs, so geometry must carry it. All from `AGENTS.md` § *Seeding a
screen with data*.
