# Contract — The Engine's Combined-History Surface (`018-transaction-list`)

**Date**: 2026-08-14 | **Layer**: `core/crates/kaname-core/src/store.rs` + `src/ffi.rs`
**Consumed by**: `ios/Sources/Transactions/TransactionHistoryService.swift`,
`ios/Sources/Import/ImportService.swift`

This is the whole engine change of slice 018: **one migration and two reads**. Nothing else in
`kaname-core` is touched. Every existing signature, including `Store::list_transactions`, keeps
its exact current behaviour.

> ⚠️ **This surface crosses the FFI.** `make core-xcframework` must run before
> `tuist generate` — `make ios-gen` already encodes that order (research D5 of 016). Any PR
> that lands this contract must land it *before* any Swift that calls it.

---

## 1. Types

```rust
/// Where to resume a combined-history read. Opaque to the caller: it is produced by
/// `history_page` and handed back unchanged. It is never displayed (FR-019).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct HistoryCursor {
    /// One resume point per account that still has rows to give. An exhausted account is
    /// absent, so the cursor shrinks as the person scrolls.
    pub marks: Vec<AccountMark>,
}

/// One account's resume point: the ordering-key suffix of the last row emitted from it.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct AccountMark {
    pub account_id: String,
    pub date: NaiveDate,
    /// `transactions.rowid` — the within-account, within-date tie-break. Internal.
    pub sequence: i64,
}

/// What the screen is asking for.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct HistoryQuery {
    /// `None` = every account, in `list_accounts()` order. `Some(id)` = that account only.
    /// This is the ONLY difference between a filtered and an unfiltered read (FR-042).
    pub account_id: Option<String>,
    /// `None` = start at the newest end of the sequence.
    pub cursor: Option<HistoryCursor>,
    /// Rows wanted. Clamped to `1..=200`; an out-of-range value is clamped, never an error.
    pub limit: u32,
}

/// One live transaction, ready to render. Carries no storage internals (FR-019, SC-016).
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct HistoryRow {
    pub id: String,
    pub account_id: String,
    pub account_name: String,
    pub account_last4: Option<String>,
    pub date: NaiveDate,
    pub description_raw: String,
    pub amount: Decimal,
    pub direction: Direction,
    /// The **transaction's** currency, never the account's and never the locale's (FR-023).
    pub currency: String,
    /// The category's display name, or `None` for uncategorized (FR-017).
    pub category_name: Option<String>,
    pub is_transfer: bool,
}

/// One screenful of the combined history.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct HistoryPage {
    pub rows: Vec<HistoryRow>,
    /// `None` ⇔ the sequence is exhausted.
    pub cursor: Option<HistoryCursor>,
}

/// One account, with the only count this slice produces.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct AccountSummary {
    pub id: String,
    pub name: String,
    pub last4: Option<String>,
    pub is_credit_card: bool,
    pub currency: String,
    /// Live rows only — neither deleted nor superseded (FR-006, FR-008, FR-046).
    pub live_transaction_count: u32,
    /// True when the account holds rows and every one of them is excluded. A boolean and not
    /// a count, deliberately: FR-008 forbids this slice introducing a count that does not use
    /// the live rule, and a boolean cannot be rendered as one. Chooses FR-048 vs FR-050.
    pub has_only_excluded_rows: bool,
}
```

`NaiveDate` and `Decimal` use the custom types already registered in `ffi.rs:60` and `ffi.rs:67`
— ISO-8601 `String` and `Foundation.Decimal` respectively. Money never becomes a float.

---

## 2. Functions

```rust
#[uniffi::export]
impl Store {
    /// One screenful of every account's live transactions, in the combined history's order.
    pub fn history_page(&self, query: HistoryQuery) -> Result<HistoryPage, StoreError>;

    /// Every account, in the front door's order, each with its live transaction count.
    pub fn account_summaries(&self) -> Result<Vec<AccountSummary>, StoreError>;
}
```

### `history_page`

**Order.** Rows are returned in the combined history's total order: `date` **descending**, then
the account's position in `list_accounts()` **ascending**, then `transactions.rowid`
**ascending**. See `data-model.md` §2.

**Population.** Only live rows — `is_deleted = 0 AND superseded_by IS NULL` — always, filtered or
not (FR-007, FR-042, FR-045).

**Paging.** `query.cursor == None` starts at the newest end. The returned `cursor` resumes
exactly after the last returned row. Concatenating every page yields the full sequence with no
row repeated and none skipped, **including across a concurrent import** (keyset, not offset).

**Termination.** `cursor == None` ⇔ exhausted. `rows.len() < limit` implies `cursor == None`.

**Filtering.** `account_id: Some(id)` restricts to that account. An id naming no account yields
an empty page and `cursor == None`, not an error.

**Errors.** `StoreError::Sql` for a storage failure; `StoreError::WrongKey`/`OpenFailed` cannot
arise here (the store is already open). It never panics on a corrupt amount, date or direction —
those surface as `StoreError::Sql`, as `map_transaction` already does.

**Concurrency.** Takes the store's mutex once, for the duration of the call, and releases it.
It does **not** re-enter `self.lock()` — the account list and the category catalog are read
through `*_in(&conn, …)` helpers, per the 016 deadlock refactor.

### `account_summaries`

**Order.** Identical to `list_accounts()` — asserted by a test comparing the two id sequences.

**Counts.** `live_transaction_count` uses the same predicate and the same index as
`history_page`. `has_only_excluded_rows` is `true` iff the account has at least one row in
`transactions` and `live_transaction_count == 0`.

**Errors.** `StoreError::Sql` only.

---

## 3. What does not change

| Existing surface | Guarantee |
|---|---|
| `Store::list_transactions(account_id)` | **Unchanged.** Still the raw view — deleted and superseded rows included, `ORDER BY rowid`. Existing engine tests depend on that. |
| `Store::list_accounts()` | **Unchanged.** It is now also the *definition* of the app's account ordering (FR-030), which a test pins. |
| `Store::import_statement` | **Unchanged** in behaviour. It now maintains one additional index as a side effect of inserting. |
| `Store::detect_transfers`, `find_duplicates`, `categorize_account`, `coverage`, `list_statements`, `list_categories` | **Unchanged, and uncalled by this slice.** |
| Every reader export, `detect_issuer`, `read_statement` | **Unchanged.** |

---

## 4. Behavioural contract — the tests that must exist

These are the engine PR's acceptance criteria. Each names the requirement it discharges.

### Ordering

| # | Assertion | Requirement |
|---|---|---|
| O1 | A page's rows are non-increasing by date | FR-028 |
| O2 | Same-date rows of **different** accounts appear in `list_accounts()` order | FR-030 |
| O3 | Same-date rows of the **same** account appear in insertion (printed) order | FR-029 |
| O4 | The concatenation of all pages equals a brute-force sort of every live row by the ordering key | FR-031, FR-045 |
| O5 | Ten consecutive full reads of an unchanged store return byte-identical sequences | FR-031, SC-009 |
| O6 | Importing a further account leaves the relative order of every pre-existing row unchanged | FR-032, SC-009 |
| O7 | `history_page`'s account sequence equals `list_accounts()`'s id sequence | FR-030 |

### The live-row rule

| # | Assertion | Requirement |
|---|---|---|
| L1 | A deleted row never appears in any page, filtered or not | FR-007, SC-005 |
| L2 | A superseded row never appears in any page, filtered or not | FR-007, SC-005 |
| L3 | Importing the same statement twice leaves the full page sequence identical — contents, count and order | FR-009, SC-003 |
| L4 | `sum(account_summaries().live_transaction_count)` equals the number of rows a full unfiltered read returns | FR-006, FR-008, FR-046 |
| L5 | For each account, its `live_transaction_count` equals the row count of a read filtered to it | FR-006, SC-004 |
| L6 | The `LIVE` constant is byte-identical to the v7 index's `WHERE` clause | FR-008 (structural) |

### Paging

| # | Assertion | Requirement |
|---|---|---|
| P1 | Pages of 1, 7, 30 and 200 all concatenate to the same sequence | FR-044 |
| P2 | No row appears in two pages; no row is skipped | FR-044 |
| P3 | `rows.len() < limit` ⇒ `cursor == None` | contract |
| P4 | An import between two page reads neither duplicates nor skips a row already returned | FR-054, FR-056 |
| P5 | An `account_id` naming nothing yields an empty page, not an error | contract |

### The filter

| # | Assertion | Requirement |
|---|---|---|
| F1 | A filtered read returns exactly that account's live rows | FR-036 |
| F2 | A filtered read's order is the unfiltered order with the other accounts removed | FR-042 |
| F3 | The filtered and unfiltered reads execute the same SQL text | FR-042 (structural) |

### Plan shape and performance (research R9)

| # | Assertion | Requirement |
|---|---|---|
| S1 | `EXPLAIN QUERY PLAN` of the page query contains **no** `SCAN` and **no** `USE TEMP B-TREE`, on both the 200-row and the 10,000-row corpus | SC-006, SC-008a |
| S2 | The plan names `idx_txn_live_account_date` | R5 — the live rule is enforced by the planner |
| S3 | First page < 25 ms on the 10,000-row / 8-account corpus | SC-006 |
| S4 | Max page time over a full walk of the corpus < 25 ms | SC-007 |
| S5 | Per-account first-page cost varies ≤ 20% between the 200/2 and 10,000/8 corpora | SC-008b |
| S6 | A `k = 1` (filtered) page < 25 ms on the 10,000-row corpus | SC-008 filter clause |

Measured on this machine while planning, for context: S1/S2 hold
(`SEARCH t USING INDEX idx_txn_live_account_date (account_id=? AND date<?)`), S3 = 254.75 µs,
S4 = 289 µs, S5 = 13%.

### Migration

| # | Assertion | Requirement |
|---|---|---|
| M1 | `v6 → v7` preserves every existing row, following the pattern of the shipped migration tests | Constitution V |
| M2 | `schema_version() == 7` after `open` | — |
| M3 | Re-opening an already-migrated store is a no-op | — |

### Privacy

| # | Assertion | Requirement |
|---|---|---|
| Z1 | `core-privacy-audit` still passes — no new crate, no new dependency | Constitution I, FR-062 |
| Z2 | No `HistoryRow`, `AccountSummary` or `StoreError` field carries a description, amount, date or account identifier into an error message or a log | FR-063 |

---

## 5. Implementation notes that are part of the contract

**The live predicate is one constant.**

```rust
/// The only definition of "a transaction the person actually has". It is also, verbatim, the
/// WHERE clause of `idx_txn_live_account_date` — so a read that forgets it does not merely
/// return the wrong rows, it silently loses its index, and the plan-shape gate goes red.
const LIVE: &str = "is_deleted = 0 AND superseded_by IS NULL";
```

**The per-account statement, in full.** One prepared statement, used for every account, filtered
or not:

```sql
SELECT t.id, t.account_id, t.date, t.description_raw, t.amount, t.direction,
       t.currency, t.category_id, t.is_transfer, t.rowid
  FROM transactions t
 WHERE t.account_id = ?1
   AND t.is_deleted = 0 AND t.superseded_by IS NULL
   AND (t.date < ?2 OR (t.date = ?2 AND t.rowid > ?3))
 ORDER BY t.date DESC, t.rowid ASC
 LIMIT ?4
```

A first page binds `?2 = '9999-12-31'` and `?3 = 0`, which is the identity cursor — so there is
no separate "first page" code path either.

**The merge.** `history_page` runs that statement once per account in the query's scope (k = the
account count, or 1 when filtered), then merges the k already-sorted buffers in Rust by the
ordering key, emitting `limit` rows. The comparator is the *only* place the order is expressed
outside SQL, and it is a pure function over `(date, account_position, rowid)`, unit-tested on
its own. A `UNION ALL` formulation was measured and is worse — it reintroduces
`USE TEMP B-TREE FOR ORDER BY` (research R2, evidence E11).

**No JOIN.** `account_name`, `account_last4` and `category_name` are resolved in Rust from two
maps read once per call. A join would change the plan and defeat S1/S2.

**No re-entrant lock.** `history_page` and `account_summaries` each take `self.lock()` exactly
once and call `*_in(&conn, …)` helpers thereafter. `std::sync::Mutex` is not reentrant; 016
recorded this as mandatory after the categorize/duplicate paths had to be split.

**Clamping, not erroring.** `limit` is clamped to `1..=200`. A page of 0 would be an infinite
scroll loop in the caller; a page of 100,000 would defeat the point of paging.
