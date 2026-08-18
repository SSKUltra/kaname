# Contract: Engine — Categorize

**Feature**: 020-categorize | **Surface**: `kaname-core`, exported through uniffi
**Sources**: [`spec.md`](../spec.md), [`research.md`](../research.md), [`data-model.md`](../data-model.md)

⚠️ **Where this surface lives.** `Store` is a `uniffi::Object` (`store.rs:559-561`) and **all** its
methods are exported by the single `#[uniffi::export] impl Store` block at `store.rs:571`. New
store methods go in `store.rs`. `core/crates/kaname-core/src/ffi.rs` holds only free functions and
the `Decimal`/`NaiveDate` custom-type bridges, and takes only the free `merchant_portion` export.
There is no `core/src/ffi.rs` (research R1).

---

## 1. Types

```rust
// merchant.rs — NEW module
#[uniffi::export]
pub fn merchant_portion(narration: &str) -> Option<String>;

// store.rs
#[derive(uniffi::Record)]
pub struct MemoryImpact { pub transaction_ids: Vec<String>, pub accounts: Vec<AccountImpact> }

#[derive(uniffi::Record)]
pub struct AccountImpact { pub account_id: String, pub display_name: String, pub count: u32 }

#[derive(uniffi::Record)]
pub struct CorrectionOutcome { pub merchant_portion: Option<String>, pub memory_formed: bool }

pub struct HistoryQuery { /* … */ pub uncategorized_only: bool }   // + 1 field
pub struct HistoryRow   { /* … */ pub category_id: Option<String> } // + 1 field

pub enum StoreError { /* … */ StaleSet { expected: u32, found: u32 } }  // + 1 variant
```

Field-level rationale is in [`data-model.md`](../data-model.md) §3. Two points are contractual
rather than incidental: `MemoryImpact.transaction_ids` is the **staleness token**, and
`HistoryRow.category_id` is an id and not a name because the picker's "current" mark is an identity
question.

---

## 2. Functions

### 2.1 `merchant_portion(narration) -> Option<String>`

```rust
#[uniffi::export]
pub fn merchant_portion(narration: &str) -> Option<String>
```

**Purity.** No store, no clock, no locale, no allocation of randomness. The same input yields the
same output in any process, on any machine, forever (FR-027e).

**Algorithm.** Exactly the four steps in [`data-model.md`](../data-model.md) §3.1: normalize via
`dedup::normalize_narration`, split on the fixed separator set, drop stop-list / numeric /
single-character segments, keep the first **two** remaining joined by one space.

**Non-modification (FR-027c, contractual).** `dedup::normalize_narration` and its four regexes
(`dedup.rs:41-70`) are **called, not changed**. A diff that touches `dedup.rs` violates this
contract regardless of whether its tests pass — de-duplication depends on that function and Q2's
answer **B** made the derivation additive precisely so the dedup fixtures need no edit.

**Returns `None`** when fewer than one segment survives. Never returns an empty or whitespace-only
string. Never returns a string containing an uppercase character.

**Free function, not a method**, so the interface can show the portion before any memory is written
(FR-026a) without a store round-trip and without a second implementation on the Swift side.

### 2.2 `Store::set_transaction_category`

```rust
pub fn set_transaction_category(
    &self,
    transaction_id: String,
    category: Option<CategoryRef>,
    remember: bool,
) -> Result<CorrectionOutcome, StoreError>
```

**Write.** Sets `category_id` to the chosen category (or `NULL`) and `categorised_by` to the
reserved value `'PERSON'`, always — including when `category` is `None` (FR-007: a deliberate blank
is a decision and is protected exactly as a category is).

**Memory.** Forms a memory **only** when all three hold: `remember` is true, `category` is `Some`,
and `merchant_portion(narration)` is `Some`. Written as
`INSERT … ON CONFLICT (merchant_portion) DO UPDATE SET category_id = excluded.category_id`, which
is FR-033's newest-wins by replacement rather than by ordering — this is why the table carries no
timestamp (research R7).

**No memory from a blank** (spec amendment §3, judgement call §4). `category == None` forms nothing
and returns `memory_formed: false`. `CorrectionOutcome.merchant_portion` is still populated when
derivation succeeded, so the interface can say plainly what it *would* have remembered.

**Atomicity.** The row write and the memory write are one transaction. Either both or neither
(FR-023).

**Errors.** `NotFound` for an unknown or non-live transaction id. `NotFound` for a `CategoryRef`
with no matching row — the FK gives this for free and FR-034 needs no separate check.

**Concurrency.** Single connection behind the existing mutex, as every other `Store` method.

### 2.3 `Store::preview_memory_application`

```rust
pub fn preview_memory_application(&self, merchant_portion: String)
    -> Result<MemoryImpact, StoreError>
```

**Read-only.** Writes nothing. Calling it twice with no intervening change returns equal results.

**Population.** Exactly the affected-set predicate in [`data-model.md`](../data-model.md) §3.5:
live ∧ derived portion equals the argument ∧ `categorised_by IS NOT 'PERSON'` ∧ not already
carrying this memory for this category.

**Order.** `transaction_ids` in a deterministic order (date DESC, id ASC — the store's existing
tie-break). `accounts` ordered by `display_name`. Determinism matters because the ids are compared
for set equality later and because a fixture must be able to pin them.

**Blast radius.** `accounts` exists so FR-035c can be stated in a person's terms — "12
transactions across HDFC Savings and ICICI Credit Card" — without the interface counting anything
itself (FR-043, FR-078).

### 2.4 `Store::apply_memory`

```rust
pub fn apply_memory(&self, merchant_portion: String, expected_transaction_ids: Vec<String>)
    -> Result<u32, StoreError>
```

**Staleness (FR-035f, contractual).** Inside the writing transaction, recompute the affected set
and compare it to `expected_transaction_ids` as a **set** (order-insensitive, duplicate-tolerant).
If they are not **equal**, roll back and return `StoreError::StaleSet { expected, found }`.

🚨 **Equality, not a subset check, and this is the enforcement point for FR-035b.** A caller that
passes a trimmed list — "apply to just these three" — is *refused*. There is no arrangement of any
interface, hostile or merely mistaken, that turns the second action into a bulk recategorize,
because the engine will not accept a chosen subset. This is why the boundary the brief asked about
sits in the engine and not in the platform: a UI that happens not to offer a checkbox proves
nothing, and a test against a UI that has no checkbox proves less. Judgement call and Principle II.

**Also refused**: a count-only token. A count cannot detect a same-size change (one row deleted and
one row added between preview and apply), and the whole point of FR-035f is that the person agreed
to a *specific* blast radius.

**Write.** Sets `category_id` to the memory's category and `categorised_by` to `'PERSON_MEMORY'`
for every row in the set. Returns the count written.

**Atomicity.** One transaction, all or nothing (FR-035g).

**Idempotence (FR-035h).** The predicate excludes rows already carrying this memory for this
category, so a second `preview` returns an empty set and a second `apply` writes 0 rows. Not
"harmless", but genuinely a no-op.

**Never touches a hand correction (FR-035d).** `categorised_by IS NOT 'PERSON'`. Rows a person
corrected by hand are neither counted in the preview nor written by the apply.

### 2.5 `Store::uncategorized_count`

```rust
pub fn uncategorized_count(&self) -> Result<u32, StoreError>
```

Store-wide (FR-041b), `LIVE ∧ UNANSWERED`. **Computed in SQL** — the count the entry point shows
comes from the engine and never from a Swift-side filter of a broader read (Q3-C, FR-043,
FR-078). 018 deliberately moved the front door's count out of Swift and into SQL; this does not
reintroduce it.

### 2.6 `Store::history_page` — changed behaviour, unchanged signature

When `query.uncategorized_only` is false, behaviour is **byte-identical** to today, including the
SQL text and the query plan. When true, `UNANSWERED` is appended to the existing `WHERE` and the
cursor, ordering, limit and page semantics are otherwise unchanged (FR-040). It composes with
`account_id` (FR-039).

### 2.7 The two guards

```rust
// load_account_transactions (store.rs:1759-1798) — the rows categorize_account_in will overwrite
"… WHERE account_id = ?1 AND {LIVE} AND transfer_group_id IS NULL AND {ENGINE_MAY_DECIDE}"

// detect_transfers (store.rs:1160-1166) — spec amendment §6, judgement call §3
"UPDATE transactions SET … WHERE id = ?1 AND transfer_group_id IS NULL AND {ENGINE_MAY_DECIDE}"
```

🚨 **`ENGINE_MAY_DECIDE` must keep its `IS NULL OR`.** `NULL NOT IN ('PERSON','PERSON_MEMORY')` is
`NULL`, not `TRUE`. The shorter spelling excludes every row `import_statement` just inserted — its
bulk insert writes `NULL, NULL` literally (`store.rs:855-870`) — so every import would land wholly
uncategorized and nothing would error. Measured with real rows in research R10.

---

## 3. What does **not** change

| Thing | Why it must not move |
|---|---|
| `categorize.rs` — **not one line** | The memory is consulted by the store *beside* the stack, not inside it (research R8). This is the only shape that satisfies FR-024 (no change to stage order or first-wins) and FR-032 (a memory is not outrankable) at the same time, and it makes `fixtures/categorization/basic.json` parity structurally immovable. |
| `dedup.rs::normalize_narration` and its regexes | FR-027c. De-duplication depends on it; the dedup fixtures must stay unedited. |
| `merchant_map` — schema, semantics, `list_merchant_rules()`, emptiness | Judgement call §1. Personal memories in an already-exported table would breach FR-035 quietly. |
| `PAGE_SQL`'s text and plan when `uncategorized_only` is false | 018's `s1`/`s2`. Measured byte-identical after v8 (research R13). |
| `LIVE` / `live_predicate!()` | Byte-identical to `idx_txn_live_account_date`'s `WHERE`. Untouched. |
| `categorised_by`'s column type and its absence of a `CHECK` | Adding one requires rebuilding the table the migration exists to not touch. Nothing parses the column back (`stage_from_sql` does not exist), so a new value cannot break a reader. |
| Transfer detection's pairing, thresholds, similarity and summary counts | FR-075. Only *which rows an already-computed answer may land on* changes. |

---

## 4. Behavioural contract — the tests that must exist

**RED first.** Each assertion is written and watched failing before the code that satisfies it. The
two marked 🔴 fail against **shipped** behaviour and are the reason this slice exists.

### 4.1 Protection — `tests/store_correction.rs`

| # | Assertion |
|---|---|
| 🔴 C1 | Correct a row, re-run `import_statement` for that account. The correction stands: `category_id` and `categorised_by = 'PERSON'` unchanged. **Fails today** — `categorize_account_in`'s unconditional `UPDATE` (`store.rs:1304`) writes `NULL, NULL`. |
| 🔴 C2 | After a fresh import into an empty store, the count of rows with a non-null `category_id` is **greater than zero**. **Fails against the naive `NOT IN` guard**, which drops every `NULL`-provenance row. This is research R10's trap and it must have its own named test, because C1 passes with the broken guard. |
| C3 | Correct to `None`. `category_id IS NULL`, `categorised_by = 'PERSON'`, and a re-import leaves it alone — a deliberate blank is protected as strongly as a category. |
| C4 | Correct to `None` with `remember: true`. `memory_formed == false`, `merchant_memory` unchanged. |
| C5 | A corrected row is **not** in the uncategorized set, whether it carries a category or a deliberate blank (spec amendment §1). |
| C6 | `set_transaction_category` on an unknown id returns `NotFound` and writes nothing. |
| C7 | A category and a memory are written in one transaction: force a failure on the second write, assert the first is rolled back. |

### 4.2 Transfer detection — `tests/store_transfer.rs`

| # | Assertion |
|---|---|
| 🔴 T1 | Correct a row, then run `detect_transfers` over a store where that row is a valid transfer leg. The correction stands. **Fails today** (`store.rs:1160-1166` guards only on `transfer_group_id IS NULL`). |
| T2 | Transfer detection's own outcomes are unchanged: the same pairs are found, the same groups formed, the same summary counts returned, for a store with no `PERSON` rows. FR-075's actual content. |

### 4.3 The memory — `tests/merchant_memory.rs`

| # | Assertion |
|---|---|
| M1 | Form a memory, import a new statement containing that merchant. New rows land in the remembered category with `categorised_by = 'PERSON_MEMORY'` (FR-030). |
| M2 | A memory beats a CC narration rule and a T1 builtin for the same row (FR-032). Judgement call §2 is what this test encodes. |
| M3 | Correct the same merchant twice to different categories. `merchant_memory` has exactly **one** row; it names the second category (FR-031, FR-033). |
| M4 | `preview_memory_application` never includes a `'PERSON'` row (FR-035d). |
| M5 | `preview` → `apply` writes exactly the previewed rows, `'PERSON_MEMORY'`, returns the previewed count. |
| M6 | `preview` → delete/insert a matching row → `apply` returns `StaleSet` and **writes nothing** (FR-035f). |
| M7 | 🚨 `preview` → `apply` with a **trimmed** id list returns `StaleSet`. This is the test that proves FR-035b is enforced in the engine and that no interface can turn the second action into a bulk edit. |
| M8 | `apply` twice: the second writes 0 and changes nothing (FR-035h). |
| M9 | `apply` where one row's write would fail: nothing is written (FR-035g). |
| M10 | A memory's category is deleted → the memory cannot exist (FK) → nothing is applied (FR-034). |
| M11 | `list_merchant_rules()` returns the same thing before and after memories exist (FR-035 / judgement call §1). |

### 4.4 Derivation — `tests/merchant_portion.rs`

| # | Assertion |
|---|---|
| P1 | Every case in `fixtures/categorization/merchant_portion.json` (FR-027e). |
| P2 | 🚨 The four `UPI-SWIGGY-*` shapes yield one identical portion — SC-008's "a memory that can only ever match the row it came from" is the failure this test exists to catch. |
| P3 | Every FR-027d case returns `None`. |
| P4 | The empty string and a whitespace-only string return `None` without panicking. |
| P5 | Research R15's three priced limitations are asserted **as they actually behave**, with a comment naming R15. A fixture that encodes known weaknesses is what tells the next person when they change. |
| P6 | `fixtures/dedup/cross_source/basic.json` still passes unedited — `normalize_narration` did not move. |

### 4.5 Migration — `tests/store.rs`

| # | Assertion |
|---|---|
| G1 | Open a v7 store with rows in every provenance state; migrate; every row's category, amount, date, description, account and provenance is byte-identical (FR-047, SC-014). |
| G2 | After migration `user_version` is 8, `merchant_memory` exists and is empty, and the new index exists. |
| G3 | A migration failure leaves `user_version` at 7 and no partial object behind (FR-048, SC-015). |
| G4 | A v8 store opens and behaves identically to a fresh v8 store. |

### 4.6 Read side — `tests/history_paging.rs`

| # | Assertion |
|---|---|
| H1 | `uncategorized_only: false` returns byte-identical pages to today (FR-046). |
| H2 | `uncategorized_only: true` returns exactly `LIVE ∧ UNANSWERED` (spec amendment §1 — a `'PERSON'` blank is excluded). |
| H3 | It composes with `account_id` (FR-039). |
| H4 | Paging across a narrowed set is stable and complete: no row seen twice, none skipped (FR-040). |
| H5 | `uncategorized_count()` equals the number of rows a full narrowed walk returns. The two definitions cannot drift because they share `UNANSWERED` — this test proves it. |
| H6 | `HistoryRow.category_id` is populated and matches `category_name`'s category. |

### 4.7 Plan shape — `tests/history_perf.rs`

| # | Assertion |
|---|---|
| Q1 | `s1` and `s2` **unchanged and still green** after v8 — `PAGE_SQL`'s plan is byte-identical (measured, research R13). Neither is edited, weakened or excepted. |
| Q2 | The narrowed page's plan contains a `SEARCH` on a named index and no `TEMP B-TREE`. |
| Q3 | ⚠️ `uncategorized_count()`'s plan **names `idx_txn_unanswered_account_date`**. **This test must NOT inherit `s1`'s blanket "no step contains SCAN" rule** — the count's optimal plan *is* a `SCAN`, of a partial index containing only the rows being counted, which is exactly what makes it get cheaper as the person works. A copy-paste of `s1` here is red for the correct query, and the tempting fix is to weaken `s1`. Do neither. |

⚠️ Research R13's plans were measured with system SQLite 3.45.3, not the SQLCipher build. They are
expected to match, but Q1–Q3 assert against the **real store**, which is what settles it.

⚠️ `history_perf.rs::s5` is wall-clock and flaky under CPU contention. **Never run `make core-test`
and `make ios-test` concurrently.**

---

## 5. Implementation notes that are part of the contract

1. **`ENGINE_MAY_DECIDE` and `UNANSWERED` are macros, spelled once.** The v8 index's `WHERE` is the
   byte-identical concatenation of `LIVE` and `UNANSWERED`, in that order — the same discipline
   `LIVE` and `idx_txn_live_account_date` already keep. If either is inlined at a call site, the
   index/query relationship becomes a coincidence and the plan-shape tests become theatre.
2. **`IS` / `IS NOT`, never `=` / `!=`, against `categorised_by`.** It is nullable. Every comparison
   in the affected-set predicate is three-valued and every one of them has been checked.
3. **`PERSON` and `PERSON_MEMORY` are constants**, not string literals at call sites, and they are
   documented as reserved — no `Stage` may ever serialize to either. `stage_to_sql`
   (`store.rs:2148-2155`) is the only producer of the column's other values and must be checked
   against these two when a stage is added.
4. **The memory is looked up in `categorize_account_in`, before delegating to
   `categorize::categorize`.** Not as a new stage, not by passing the memory into the stack.
   Research R8.
5. **`merchant.rs` is pure and takes no `&self`.** It must be unit-testable without a store, and
   `merchant_portion` must be callable from Swift without one.
6. `cargo fmt`, `clippy -D warnings`, small pure functions. The derivation is four functions, not
   one; the stop-list is a `const` array with its five groups on five commented lines.
