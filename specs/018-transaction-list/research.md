# Phase 0 Research: The Transaction List

**Feature**: `018-transaction-list` | **Date**: 2026-08-14 | **Spec**: [`spec.md`](./spec.md)

Every decision below is grounded in code that exists in this repository today, or in a
measurement that was actually run on this machine while planning. Where a decision rejects an
alternative, the rejection reason is a measured fact or a cited line, not a preference.

**How the measurements were produced.** Two throwaway integration tests were written into
`core/crates/kaname-core/tests/` (`scratch_probe.rs`, `scratch_probe2.rs`), run with
`cargo test --test scratch_probe -- --nocapture`, and **deleted before this document was
written**. They opened a real SQLCipher-encrypted store through `Store::open`, seeded a
synthetic corpus, and printed `EXPLAIN QUERY PLAN` output, wall-clock timings and `dbstat`
page counts. Every figure quoted as `E<n>` below is a line of that output, reproduced verbatim.
The permanent versions of these probes are specified as tasks in `plan.md` (the engine PR's
plan-shape gates), so nothing here rests on a measurement that cannot be re-run.

Source anchors used throughout:

- `core/crates/kaname-core/src/store.rs` — the encrypted store; schema v6 at line 41.
- `core/crates/kaname-core/src/dedup.rs` — the cross-source duplicate matcher.
- `core/crates/kaname-core/src/transfer.rs` — the transfer detector.
- `core/crates/kaname-core/src/ffi.rs` — the UniFFI surface.
- `ios/Sources/Import/ImportService.swift` — the front door's data source (exactly 400 lines).
- `ios/Sources/Import/ImportModels.swift:79–89` — `StoredTransaction.isLive`, the live-row rule.
- `ios/Sources/Import/ImportedAccountsView.swift` — the screen carrying the parked a11y finding.
- `scripts/import-path-audit.sh:15–16` — the two directories the audits actually scan.
- `.scratch/HANDOFF.md` — 016's T115/T123 limitation and the `3ba7890` doubling fix.

---

## R1 — The cross-account read is a stateless, keyset-paged call; not a handle, not offset/limit

**Decision.** Add one read to the engine:

```rust
pub fn history_page(&self, query: HistoryQuery) -> Result<HistoryPage, StoreError>
```

`HistoryQuery` carries an optional `account_id` filter, an optional `cursor`, and a `limit`.
`HistoryPage` carries the rows and the cursor to resume from (`None` = the end of history).
Each call is a complete, self-contained SQL round trip: it takes the store's mutex, does its
work, releases it, and keeps **no** state between calls. The cursor is an opaque value the
caller carries and hands back.

**Rationale.**

- **A lazily-consumed handle is not implementable over this bridge.** A cursor object that
  yields rows on demand must hold a live `rusqlite::Statement`, which borrows the
  `Connection`. The connection lives behind `Store`'s mutex (`store.rs:966`,
  `fn lock(&self) -> std::sync::MutexGuard<'_, Connection>`), so the handle would have to
  hold a `MutexGuard` across FFI calls. `std::sync::Mutex` is not reentrant, and 016 already
  paid for that lesson — `plan.md`'s post-Phase-1 note records that `categorize_account` and
  `find_duplicates` had to be split into `*_in(tx, …)` helpers "or the happy path deadlocks".
  A handle that holds the lock deadlocks *every other reader*, including the import the list
  is supposed to stay current with (FR-053). Rust's borrow checker would additionally require
  a self-referential struct to express it. This is not a UniFFI limitation — UniFFI would
  happily export a second `#[derive(uniffi::Object)]` beside `Store` (`store.rs:417`) — it is
  a lock-ownership limitation, which is worse, because it fails at runtime rather than at
  compile time.
- **Offset/limit is wrong, not merely slow.** `LIMIT n OFFSET m` makes SQLite walk and discard
  `m` rows on every page, so page cost grows linearly with scroll depth — the exact thing
  FR-044 and FR-059 forbid. It is also *incorrect* under concurrent writes: an import that
  inserts rows above the current offset shifts the window and either duplicates or skips rows
  (FR-054's "never a partially-written statement" would be violated by paging, not by the
  store).
- **Keyset paging is stable under insertion.** The cursor names a position in the *ordering*,
  not a position in a result set. Rows inserted above it do not move it; rows inserted below
  it are picked up. That is precisely FR-056 ("not silently returned to the top") and FR-032
  ("importing must not change the relative order of what is already there").

**Alternatives rejected.**

- *A `TransactionCursor` UniFFI object.* Rejected on the lock argument above.
- *`LIMIT/OFFSET`.* Rejected: linear page cost and unstable under concurrent import.
- *Return everything and page in Swift.* Rejected outright by FR-044 — and measured: reading
  the 10,000-row corpus across the bridge is what the front door does today, and it costs
  43.8 ms of Rust time alone before any bridging (E6, R6 below).

---

## R2 — One page is a *k*-way merge in Rust over *k* per-account keyset queries, not one SQL query

**Decision.** `history_page` runs **one prepared statement, once per account in scope**, each
returning at most `limit` rows already ordered within that account, and merges the *k* streams
in Rust by the comparator in R3. With an account filter, *k* = 1 and it is *the same statement
with the same bindings shape*.

The per-account statement is:

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

**Rationale — three plans were measured, and only this one is index-satisfied.**

The alternative of expressing the whole page as a single SQL statement was tried in two forms.

*Form 1 — join `accounts` and order globally.* Rejected without measurement: the account
tie-break (R3) is `accounts.rowid`, which is not a column of `transactions`, so no index on
`transactions` can satisfy the ORDER BY. SQLite must materialise and sort the join. That is
O(N log N) per page over the whole corpus, and SC-008 dies.

*Form 2 — `UNION ALL` of k bounded sub-selects, ordered by the outer query.* Measured, and it
is **worse than the merge**:

```
E11 UNION ALL plan: MERGE (UNION ALL) | LEFT | CO-ROUTINE (subquery-1)
  | SEARCH t USING INDEX ix_desc (account_id=?) | SCAN (subquery-1)
  | USE TEMP B-TREE FOR ORDER BY | RIGHT | CO-ROUTINE (subquery-3)
  | SEARCH t USING INDEX ix_desc (account_id=?) | SCAN (subquery-3)
  | USE TEMP B-TREE FOR ORDER BY
```

Each branch's `ORDER BY … LIMIT` forces a co-routine and a temp b-tree, and the SQL text has
to be *built* with one branch per account (the account's sort position must be injected as a
literal, because SQLite has no way to know it). Dynamic SQL, a prepared-statement cache miss
per distinct *k*, and two temp b-trees — for a merge of at most `k × limit` rows that Rust
does in a few hundred nanoseconds.

*Form 3 — the k-way merge, chosen.* Measured on the 8-account / 10,000-row encrypted corpus:

```
E2c plan WITH partial DESC index: SEARCH t USING INDEX idx_txn_live_account_date (account_id=? AND date<?)
E2d first-page k-way (8 accounts) WITH index: 254.75µs
```

No `SCAN`. No `USE TEMP B-TREE`. One index seek per account.

**Why this satisfies FR-042 and FR-045 structurally rather than by discipline.** FR-042 says
filtering must not become a second code path; FR-045 says the ordering, the live-row rule and
the filter must apply to the same population. In this shape the filter is not a branch — it is
the *length of the account list* the merge is given. `history_page` computes that list once:

```rust
let accounts = match query.account_id {
    Some(id) => accounts_in(&conn)?.into_iter().filter(|a| a.id == id).collect(),
    None     => accounts_in(&conn)?,
};
```

and everything after that line is identical. There is exactly one SQL string, one comparator,
one live predicate, and one paging loop, whether *k* is 1 or 8.

**The within-account and across-account orderings are disjoint, not duplicated.** The SQL
`ORDER BY t.date DESC, t.rowid ASC` decides order *inside* one account; the Rust comparator
only ever decides order *between* accounts, using a key (the account's position on the front
door) that SQL cannot see. Neither can contradict the other. A test pins this: the merged page
sequence must equal a brute-force full sort of every live row by the R3 key.

---

## R3 — The total order is `date DESC`, then the front door's account position, then `rowid ASC`

**Decision.** The ordering key of one row is the triple

```
(date, account_position, rowid)
```

compared as **date descending, account_position ascending, rowid ascending**, where
`account_position` is the row's account's index in `Store::list_accounts()` — that is,
`accounts.rowid`, which is insertion order (`store.rs:496–501`,
`FROM accounts ORDER BY rowid`, documented "All accounts, oldest first (insertion order)").

**Rationale.**

- FR-030 requires the same account ordering the front door presents. The front door is
  `ImportedAccountsView`, fed by `ImportService.importedAccounts()`
  (`ImportService.swift:130`), which maps `store.listAccounts()` in the order it returns them.
  So the front door's ordering *is* `accounts.rowid`. Nothing had to be invented; it had to be
  found and then pinned, because it was previously an incidental property of a `SELECT`.
- FR-031 requires totality. Every row has exactly one account, exactly one date and exactly
  one rowid, and rowid is unique within the table, so the triple is a strict total order with
  no ties. There is no "and then fall back to something" clause, which is what makes it
  provable.
- FR-030 also forbids deriving the order from import time, read time or "any identifier the
  person cannot see". `accounts.rowid` **is** account creation order, which is the order the
  person already sees on the front door — it is not a hidden identifier, it is the visible
  one's representation. `transactions.rowid` is discussed on its own terms in R8.

**⚠️ There are already two account orderings in the store, and they disagree.**
`load_dedup_candidates` orders accounts by `ORDER BY a.created_at, a.id, t.rowid`
(`store.rs:1393`) — `created_at` first, then the *minted random id*. `list_accounts` orders by
`rowid`. These are different orderings, and the second one is not even stable across installs
(see R17, where this turns out to matter far more than it looks). This slice does **not**
reconcile them: `history_page` uses `list_accounts`'s ordering, because FR-030 names the front
door, and a test asserts the two agree by construction (`history_page`'s account sequence ==
`list_accounts()`'s id sequence).

**Alternatives rejected.**

- *Order same-date rows by `transactions.rowid` globally (ignore the account).* Rejected: it
  makes the tie-break depend on import order across accounts, which FR-030 explicitly forbids,
  and it scatters one account's same-date rows through another's, which destroys the
  reconcile-against-paper property FR-029 exists for.
- *Order accounts by name.* Rejected: it is a different ordering from the front door's
  (FR-030), and it changes when an account is renamed — a rename would reshuffle history,
  which is exactly the "data changing on its own" failure US4 is about.
- *Order accounts by `created_at`.* Rejected: `created_at` is a caller-supplied timestamp
  (`ImportRequest.now`), and two accounts created by the same import run carry the **identical**
  string — so it is not even a total order on its own. That is why `load_dedup_candidates` has
  to fall back to `a.id`, and why that fallback is a defect (R17).

---

## R4 — Schema v7 is one partial, `DESC` index — and it is not optional

**Decision.** Add exactly one migration:

```sql
CREATE INDEX idx_txn_live_account_date
    ON transactions(account_id, date DESC)
    WHERE is_deleted = 0 AND superseded_by IS NULL;
```

`SCHEMA_VERSION` goes 6 → 7 (`store.rs:41`), applied by the existing forward-only runner
(`apply_migration`, `store.rs:1201`). No table rebuild, no `ADD COLUMN`, no foreign-key
disable, no new stored data.

**Rationale — measured, three ways.**

*Without the index*, the query in R2 is served by the only index there is
(`idx_transactions_account ON transactions(account_id)`, `store.rs:88`):

```
E2  plan WITHOUT new index: SEARCH t USING INDEX idx_transactions_account (account_id=?)
                          | USE TEMP B-TREE FOR ORDER BY
E2b first-page k-way (8 accounts) WITHOUT index: 3.974167ms
```

`USE TEMP B-TREE FOR ORDER BY` means SQLite sorts **the account's entire history** to produce
each 30-row page. Cost is O(account history) *per page*, and every one of those rows is a
SQLCipher decrypt. SC-006, SC-008 and FR-059 are all unreachable in that shape — not slowly,
but structurally.

*With the index*: `E2c`/`E2d` above — no temp b-tree, 254.75 µs, a 15.6× improvement that is
really a change of complexity class.

*Why `DESC` in the index definition is load-bearing.* SQLite appends the rowid to every index
entry in ascending order, so an index on `(account_id, date)` scanned in reverse yields
`date DESC, rowid DESC` — the wrong tie-break. Measured directly:

```
E9 plan with ASC index:  SEARCH t USING INDEX ix_asc (account_id=? AND date<?)
                       | USE TEMP B-TREE FOR LAST TERM OF ORDER BY
E9 plan with DESC index: SEARCH t USING INDEX ix_desc (account_id=? AND date<?)
```

The ASC index costs a temp b-tree "for last term of ORDER BY" — SQLite gets the dates from the
index and then sorts each date's rows by rowid. Declaring the column `DESC` makes the index
entry order `(account_id ASC, date DESC, rowid ASC)`, which is the R3 key with the account
fixed. The ORDER BY is then free.

*Why partial.* Measured, the partial index is **not** required for the plan — a non-partial
`(account_id, date DESC)` produces the same plan (`E9b`). It is chosen for two other reasons:

1. **Size.** `dbstat` on the 10,000-row corpus:
   `E13 dbstat idx_txn_live_account_date = 282624 bytes` against
   `E13 dbstat transactions = 1519616 bytes` and a 2,273,280-byte file — about 28 bytes per
   live row, +12.4% on the database. A non-partial index also indexes superseded and deleted
   rows, which after a re-import is a meaningful fraction of the table and is pure waste,
   because no query this slice adds ever wants them.
2. **It makes the live-row rule structural.** See R5.

**Cost accepted.** Every insert now maintains one more index. `import_statement` writes rows in
one transaction (`store.rs:589`), so the cost is one b-tree insert per row. Against the
already-measured cost of the same import path (016's `find_duplicates_in` runs a full
cross-account dedup on every import), this is noise.

**⚠️ This contradicts a sentence in the spec, deliberately and in the open.** The spec says
this slice adds "no new stored data and no writes". An index stores no *data* — it stores no
field a person can see, adds no row, and changes no value — but it is a **schema change** and
therefore a v7 migration. The spec's sentence is about the person's data, and it remains true.
The plan records the migration explicitly so nobody discovers it in a diff.

---

## R5 — The live-row rule lives in the index's `WHERE` clause and in one Rust constant; `list_transactions` does not change

**Decision.**

1. `Store::list_transactions` keeps its exact current semantics — raw, deleted and superseded
   rows included, `ORDER BY rowid` (`store.rs:715–726`). Its callers in
   `core/crates/kaname-core/tests/` depend on that and it is documented as the raw view.
2. The live predicate is written **once**, as a private constant used by every new read:
   ```rust
   /// The only definition of "a transaction the person actually has".
   /// It is also, verbatim, the WHERE clause of `idx_txn_live_account_date` — so a read that
   /// forgets it does not merely return the wrong rows, it silently loses its index.
   const LIVE: &str = "is_deleted = 0 AND superseded_by IS NULL";
   ```
3. The partial index's `WHERE` clause is byte-identical to `LIVE`. A unit test asserts that,
   and a second test asserts every new read's `EXPLAIN QUERY PLAN` names the index.

**Rationale — this is what makes FR-008 structural rather than remembered.** FR-008 says no
screen may count one population and list another. The 016 defect (`3ba7890`, recorded in
`.scratch/HANDOFF.md`) happened because the rule was a *convention* — the front door counted
`list_transactions` directly and a person's history visibly doubled on re-import. Moving the
rule into a comment on `StoredTransaction.isLive` made it a better-documented convention, not
a guarded one.

A partial index converts it into a **mechanical consequence**. SQLite will only use a partial
index when the query's `WHERE` provably implies the index's `WHERE`; this was verified rather
than assumed — the plan line `E2c` shows `idx_txn_live_account_date` chosen for a query whose
`WHERE` contains those exact terms. So a future read that drops `AND is_deleted = 0 AND
superseded_by IS NULL` loses the index, and the plan-shape test that asserts the index is used
fails the build. The rule is no longer something a reviewer has to remember; it is something
the query planner enforces.

**Alternatives rejected.**

- *A SQL `VIEW` (`CREATE VIEW live_transactions AS SELECT … WHERE …`).* Tempting, and it would
  put the rule in one place. Rejected: a view is a schema object that must be kept in step with
  the columns of `transactions` across every future migration, and SQLite's use of a partial
  index through a view is a planner detail this slice would have to re-verify on every SQLite
  bump. The constant plus the index gives the same locality with none of the coupling.
- *Change `list_transactions` to filter.* Rejected — it would silently change what five shipped
  engine test files assert, and 016 deliberately made it the raw view.
- *Keep filtering in Swift.* Rejected by R6.

---

## R6 — The count moves into the engine; the front door's N+1 read goes away

**Decision.** Add a second read:

```rust
pub fn account_summaries(&self) -> Result<Vec<AccountSummary>, StoreError>
```

returning every account in `list_accounts()` order, each with a `live_transaction_count`
derived from the same `LIVE` predicate and the same index. `ImportService.importedAccounts()`
calls it and stops counting in Swift.

**Rationale.**

- **FR-046 asks for a structural guarantee**, and Swift-side filtering cannot give one: the
  count and the list would be produced by two implementations of the same rule in two
  languages. With `account_summaries`, the count and the page are the same predicate, the same
  index and the same file.
- **The current shape is also a performance defect the spec did not anticipate.**
  `ImportService.swift:130–137` does `store.listAccounts()` and then, *per account*,
  `store.listTransactions(accountId:).filter(\.isLive).count`. On the 10,000-row corpus that
  is every row of the whole database decrypted, materialised into `StoredTransaction` values
  and bridged into Swift, to produce eight integers. Measured:

  ```
  E6  importedAccounts()-equivalent over 10k rows: 10000 live in 43.795458ms
  E2g grouped live count 8 in 988.084µs
  ```

  43.8 ms of Rust time — before UniFFI bridging of 10,000 records, each of which allocates a
  Swift `String`, a `Decimal` and several optionals — versus 0.99 ms for the grouped count.
  ~45× on the engine side, and the bridging cost, which is the larger half, disappears
  entirely. The grouped count's plan is `SCAN transactions USING INDEX
  idx_txn_live_account_date` (`E2f`) — a scan of the *partial* index, i.e. of exactly the live
  entries, never of the table.
- **Every account's row on the front door becomes a link into the list (FR-002)**, so the front
  door is going to be re-read on every return from the list. Making that read 45× cheaper is
  not an optimisation, it is the difference between a screen that feels instant and one that
  stutters on the way back.

**`AccountSummary` carries a boolean, not a second count.** FR-047–FR-050 need four distinct
empty states, and two of them are only distinguishable by whether the account holds rows that
are all excluded:

| State | `live_transaction_count` | `has_only_excluded_rows` | Copy |
|---|---|---|---|
| Nothing imported at all | *(no accounts exist)* | — | FR-047 |
| Statement genuinely had zero rows | 0 | `false` | FR-048 |
| Every row deleted or superseded | 0 | `true` | FR-050 |
| Filter on an empty account, others have rows | 0 | either | FR-049 |

The obvious field would have been `stored_transaction_count`. **It is deliberately a boolean**,
because FR-008 says *every* count this slice introduces must use the live rule, and a raw count
in a record is a number that will eventually be rendered. A boolean cannot be.

**On `StoredTransaction.isLive`.** It stays. It is no longer on any production path, and its
doc comment is amended to say so; it becomes the Swift-side mirror of the engine rule, pinned
by a test asserting that for a store seeded with deleted and superseded rows,
`listTransactions(accountId:).filter(\.isLive).count == accountSummaries()[i].liveTransactionCount`.
Deleting it would remove the only cross-language check that the two definitions agree.

---

## R7 — The filter is `k = 1`, and it lives in the view model, not in the store

**Decision.** The account filter is `HistoryQuery.account_id: Option<String>`. Applying,
changing or clearing it discards the cursor and requests page 1 — nothing else changes.
Filter state lives in the SwiftUI view model as plain `@State`/`@Observable` property, is
**not** persisted, and is **not** written to `UserDefaults` or anywhere else.

**Rationale.**

- FR-041 requires a relaunch to show the unfiltered list, and the spec's "Decisions taken
  without asking" gives the reason. The cheapest possible implementation of "does not persist"
  is to never write it down. Anything stored — even in memory on a singleton — is something
  that can later be restored by accident.
- FR-060 requires applying or clearing the filter to draw a first screenful without re-reading
  the whole history. Measured for the two extremes on the 10,000-row corpus: `k = 8`
  → 254.75 µs (`E2d`); the small corpus with `k = 2` → 73.25 µs (`E4`). A `k = 1` page is one
  index seek. SC-008's 300 ms budget is three orders of magnitude away on the engine side.
- FR-042 says a filtered list is "the same list with fewer rows in it". R2's shape makes that
  literally true — the same statement, the same comparator, a shorter account list.

**Alternatives rejected.**

- *A separate `list_account_history` FFI function.* Rejected: two functions is two orderings
  and two live predicates waiting to drift, which is FR-042's whole concern.
- *Filtering the merged page in Swift.* Rejected: it reads every account's rows to throw most
  of them away, so a filtered page costs more than an unfiltered one and the page size becomes
  unpredictable.

---

## R8 — `transactions.rowid` is the within-account tie-break; here is exactly what it does and does not guarantee

**Decision.** Use `transactions.rowid` as the third component of the ordering key, and carry it
in the cursor as an opaque `sequence: i64`. It is never displayed and never bridged into
anything a person sees.

**What was verified.**

1. **`rowid` is the printed order within one imported statement.** `import_statement` inserts
   `request.transactions` in a plain `for txn in &request.transactions` loop against one
   prepared statement (`store.rs:673–694`), so rowids ascend in the order the reader emitted
   the rows, which since 017 is the order the page prints them (geometry-first row bands,
   top-to-bottom). Verified:

   ```
   E8 rowid=1 2025-03-04 MARCH ROW 1 stmt=92456cdd
   E8 rowid=2 2025-03-04 MARCH ROW 2 stmt=92456cdd
   E8 rowid=3 2025-03-04 MARCH ROW 3 stmt=92456cdd
   ```

2. **`rowid` survives the atomic import.** All rows of one statement are written inside one
   `conn.transaction()` and committed once (`store.rs:589`, `tx.commit()` at the end), so a
   statement's block of rowids is contiguous and no other writer can interleave into it.

3. **`rowid` is stable under `VACUUM`, and nothing in this repository runs one.**
   `transactions.id` is `TEXT PRIMARY KEY`, not an `INTEGER PRIMARY KEY` alias, so SQLite is
   permitted to renumber its rowids on `VACUUM`. Two things were checked. First,
   `grep -rIn 'VACUUM' --include=*.rs --include=*.swift --include=Makefile .` returns
   **nothing** — no code path in the app or the engine vacuums. Second, a `VACUUM` was run
   against the 10,000-row encrypted corpus anyway:

   ```
   E3 rowids before VACUUM: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
   E3 rowids after  VACUUM: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
   E3 relative id order preserved = true
   ```

   `VACUUM` rebuilds the table by copying rows in existing rowid order, so even when it does
   renumber, the *relative* order — which is all the ordering key uses — is preserved. FR-031's
   stability is therefore safe, and it is safe for a reason rather than by luck.

**What is honestly not guaranteed, and what is done about it.** `rowid` is *insertion* order,
which equals *printed* order only within one statement. Across two statements of the same
account, rowid is import order. It matters only when two statements of the **same account**
contribute **live** rows on the **same date** — because date and account already dominate the
key. Verified that this is reachable:

```
E8 rowid=4 2025-03-04 OTHER STATEMENT ROW stmt=20169c33
```

A March statement imported first and a second statement covering the same day imported later
interleave by import order, not by anything printed. The overwhelmingly common form of this —
re-importing the same statement — cannot produce it, because `link_reimported_rows_in`
supersedes the repeats (`store.rs:1061`) and the live rule then excludes them. The residual
case is genuinely overlapping *different* statements for one account. The decision is to
**accept it and state it**, because:

- the alternative is a persisted `statement_line_no` column plus a persisted statement
  ordering — new stored data, which the spec forbids and which is a much larger change than
  this slice carries;
- the resulting order is still **total, deterministic and stable** (FR-031) — it is simply not
  *printed* order in that one case, which is FR-029, and FR-029 is scoped to "that account's
  statement", singular;
- it is recorded in `data-model.md` as a known limit with the schema change that would fix it,
  priced, so a later slice can take it deliberately.

**Alternatives rejected.**

- *Order by `created_at`.* Rejected: it is a caller-supplied ISO-8601 string and every row of
  one import carries the identical value (`ImportRequest.now`), so it is not a tie-break at all.
- *Order by `transactions.id`.* Rejected, emphatically: `mint_id` is
  `SELECT lower(hex(randomblob(16)))` (`store.rs:1257`). Ordering by it is ordering by a random
  number, which FR-031 forbids and which R17 shows has already caused real damage elsewhere.

---

## R9 — How SC-006, SC-007 and SC-008 are actually measured — and where one of them had to be restated

**Decision.** Each performance criterion is split into an **engine half** that is proven in
`cargo test` and a **device half** that is recorded in the manual gate. Nothing is asserted
that this repository cannot measure.

| Criterion | Engine half (automated, `cargo test`) | Device half (manual gate, quickstart §5) |
|---|---|---|
| SC-006 — 10,000 rows / ≥8 accounts, first screenful < 1 s | The page query's `EXPLAIN QUERY PLAN` contains no `SCAN` and no `USE TEMP B-TREE`, on both corpora; the first page returns in < 25 ms wall clock (a ~100× headroom bound, chosen so CI noise cannot make it flap) | Stopwatch from tap to first row on the seeded 10,000-row build |
| SC-007 — no >100 ms wait on a blank row; full frame rate | Walking the entire corpus one page at a time, **max** page time < 25 ms | Scroll the full history; watch for hitches |
| SC-008 — first-screenful time varies ≤20% between 200/2 and 10,000/8 | **Restated** — see below | Stopwatch both builds |
| SC-008 — filter apply/clear < 300 ms | A `k = 1` page returns in < 25 ms | Stopwatch |

**SC-008's first clause could not be measured as literally worded, and saying so is the point.**
Measured, on the same machine, same run:

```
E4  first-page k-way (2 accounts, 200 rows)  WITH index: 73.25µs
E2d first-page k-way (8 accounts, 10000 rows) WITH index: 254.75µs
```

That is a 3.5× ratio, which fails a literal reading of "varies by no more than 20%". But the
difference is **not** corpus size — it is *k*. Per account: 73.25/2 = 36.6 µs and
254.75/8 = 31.8 µs, a 13% spread in the *right* direction (the larger corpus is marginally
cheaper per account, because its index pages are warmer). The absolute difference is 181 µs
against a 1-second budget: 0.018%.

So the criterion is restated into two things that are true, measurable here, and mean what
SC-008 intended:

- **SC-008a (structural, automated).** The query plan for a page is identical on both corpora
  and contains no `SCAN` and no `USE TEMP B-TREE` — i.e. page cost is provably independent of
  how many rows the corpus holds. This is the stronger claim; a wall-clock ratio can pass by
  accident, a plan cannot.
- **SC-008b (empirical, automated).** Per-account first-page cost varies by ≤20% between the
  200/2 and 10,000/8 corpora. Measured today at 13%.
- **SC-008c (device, manual).** Tap-to-first-row on both seeded builds, recorded with the build
  and date, in the same manual gate as SC-012.

**Why wall-clock assertions are kept generous.** `cargo test` runs on developer machines and on
CI runners of unknown load. A test that asserts 254.75 µs would be red for reasons that have
nothing to do with this feature. 25 ms is ~100× the measured figure and still an order of
magnitude below anything a person can perceive; a regression that breaks it is a regression of
*shape* — a lost index, a re-introduced sort — which is precisely what SC-008a catches first
and more clearly.

**The full-walk figure, for context.** Paging the entire 10,000-row corpus in 30-row pages
through the merge:

```
E13 walked 10000 rows in 13.462708ms; pages=335 first=267us median=10us max=289us
```

335 pages, 13.5 ms total, worst page 289 µs. SC-007's 100 ms budget is 345× the worst page the
engine will ever produce. Whatever makes a row appear blank for 100 ms on a device, it is not
this read.

---

## R10 — The cursor crosses the FFI as a record of per-account marks

**Decision.**

```rust
#[derive(uniffi::Record)]
pub struct HistoryCursor { pub marks: Vec<AccountMark> }

#[derive(uniffi::Record)]
pub struct AccountMark {
    pub account_id: String,
    pub date: NaiveDate,   // crosses as an ISO-8601 String (ffi.rs:67)
    pub sequence: i64,     // transactions.rowid — opaque, never displayed
}
```

**Rationale.**

- The merge needs one resume point *per account*, because each account's stream advances by a
  different amount within one page. A single global `(date, position)` mark cannot express
  "account A is at 2025-03-04 row 7 and account B is at 2025-02-19 row 2".
- UniFFI 0.32 records nest freely; `ParsedStatement` already carries a `Vec` of record values
  across this bridge, so there is nothing novel here. `NaiveDate` already has a
  `uniffi::custom_type!` mapping to `String` (`ffi.rs:67`), and `Decimal` to
  `Foundation.Decimal` via `String` (`ffi.rs:60`) — money never becomes a float on the way
  across, which R16 depends on.
- The cursor is **opaque to Swift**: the app stores it and hands it back, and no Swift code
  reads `sequence`. FR-019 forbids *displaying* internals; carrying an opaque token is not
  displaying one. A test asserts no view or accessibility string references `sequence`.
- Its size is bounded by the account count, which is bounded by how many accounts a person
  has — tens, not thousands.

**Alternatives rejected.**

- *An opaque `String` (e.g. base64 of a serialized struct).* Rejected: it would need a
  serializer in the engine, and it makes the cursor untestable without decoding it. A typed
  record is self-describing and diffable in a test failure.
- *An integer page number.* That is offset paging with extra steps — rejected in R1.

---

## R11 — The Swift seam goes in a new `ios/Sources/Transactions/`, because `ImportService.swift` is full

**Decision.** No line is added to `ios/Sources/Import/ImportService.swift`. The new code lives
in a new directory:

```
ios/Sources/Transactions/
├── TransactionHistoryService.swift   # actor: paging, filter, off-main-thread reads
├── TransactionListViewModel.swift    # @MainActor @Observable presentation state
├── TransactionRow.swift              # the row's value type + layout decision + a11y label
├── TransactionListView.swift         # the List, sections, filter chrome
├── TransactionListStrings.swift      # every user-visible string, in one place
└── TransactionEmptyStateView.swift   # the four empty states
```

The one change inside `Import/` is `ImportService.importedAccounts()` swapping
`listTransactions(...).filter(\.isLive).count` for `store.accountSummaries()` — which
**removes** a line rather than adding one.

**Rationale.**

- `wc -l ios/Sources/Import/ImportService.swift` = **400**. SwiftLint runs `--strict` with a
  400-line file limit (`make lint`), so the file is at the boundary: the next line fails the
  build. This is not a style preference to work around; it is a gate.
- The seam is the right one independently of the line count. `ImportService` is the *write*
  path — it owns the pipeline, the in-flight task and the account resolution. The list is a
  *read* path with a different lifetime (it outlives any one import), a different concurrency
  shape (paged, cancellable per scroll) and different failure modes. Putting a paging reader
  inside an import actor would serialise reads behind imports, which FR-054's "remains readable
  and responsive during an import" forbids.
- `make import-audit` scans `ios/Sources/Import/` for networking symbols and all of
  `ios/Sources/` for the glass and bank-literal rules (`scripts/import-path-audit.sh:15–16`).
  The new directory is covered by two of the three audits and **not** by the networking one.
  R19 fixes that.

**The store handle.** Both services need the same `Store`. `ImportViewModel.liveService()`
opens it today via `StoreLocator(keyStore: KeychainKeyStore()).open()`. Opening it twice would
be two SQLCipher connections to one file — measured cheap
(`E5 cold open (10k) 179.208µs`) but wrong: two connections means two mutexes and no
serialization between a reader and the importer, which is how a reader observes a half-written
statement. **Decision: one `Store` per process**, created by `StoreLocator` and handed to both
services. The engine's own `Mutex<Connection>` then serialises every read against the atomic
import — which is what makes FR-054 free (R14).

---

## R12 — The row layout that survives accessibility sizes, and how it is proven without a rendered screen

**Decision.** The row is **not** a `LabeledContent`. It is an explicit layout that switches axis
on `\.dynamicTypeSize.isAccessibilitySize` (verified present in the SDK: `DynamicTypeSize` and
`isAccessibilitySize` at `SwiftUICore.swiftinterface:11690` / `:11703`, iOS 26.5 simulator SDK):

- **Standard sizes** — `HStack`: a leading `VStack` (description, then account name, then
  category/transfer marks) and a trailing amount. The amount gets `.fixedSize()` and
  `.layoutPriority(1)`; the description gets `.lineLimit(2)` and truncates; the account name
  gets `.lineLimit(1)` and truncates second (FR-021's yield order, encoded as layout priority
  rather than as a comment).
- **Accessibility sizes** — a single `VStack`, amount **last** and full width, everything
  `.fixedSize(horizontal: false, vertical: true)` so the row grows in height rather than
  clipping. Nothing truncates the amount at any size, ever: no `minimumScaleFactor`, no
  `.truncationMode`, no abbreviation.
- **The bottom bar becomes `.safeAreaBar(edge: .bottom)`** (verified present:
  `SwiftUI.swiftinterface:16455`), replacing `RootView`'s `.safeAreaInset(edge: .bottom)`
  (`RootView.swift:15`) on the list screen. `safeAreaBar` is the iOS 26 API whose contract is
  that the bar owns its own safe-area inset and the scrollable content is inset by it — which
  is exactly the mechanism the parked occlusion finding suggests was not holding.
- **No glass under rows.** The skill is explicit — "The transaction list, statement rows, and
  any table of numbers stay on opaque backgrounds" (`.github/skills/swiftui-liquid-glass/SKILL.md`).
  Glass appears on exactly one element on this screen: the filter control, in a
  `GlassEffectContainer`, on an opaque bar.

**The finding this is answering, stated at its real strength.** `.scratch/HANDOFF.md` records
an audit run *by accident* against the accounts list at the largest text size, reporting a
contrast failure on `StaticText '1'` at `{32, 724}` — "consistent with `LabeledContent`
switching to a vertical layout at accessibility sizes and dropping the transaction count to the
leading edge under the bottom bar". It is **unverified**. The accounts list is
`ImportedAccountsView.swift:10`, and it *is* a `LabeledContent`. A transaction row is the same
two-column shape with more content in it. The decision is therefore not "fix the finding" — it
is "do not build the shape the finding is about", and to make the accounts row match once the
list ships (a small, in-scope change, since `importedAccounts()` is being touched anyway).

**How it is proven without a rendered screen (FR-074, SC-013).** The layout decision is
extracted into a pure value type so it can be unit-tested:

```swift
struct TransactionRowLayout: Equatable {
    enum Axis { case horizontal, vertical }
    let axis: Axis
    let descriptionLineLimit: Int
    let amountYields: Bool          // always false — pinned by a test
    init(dynamicTypeSize: DynamicTypeSize)
}
```

Swift Testing then asserts, with no view rendered: every `DynamicTypeSize` case maps to the
right axis; `amountYields` is `false` for all 12 cases; the description's line limit is finite
and the amount's is absent; and the accessibility label for each row is the exact expected
sentence. What genuinely cannot be proven this way — that the rendered result clears the
contrast threshold and is not occluded — goes to the manual gate, which is what FR-075 and
SC-012 already say. This split is the smallest honest one: the *decision* is tested, the
*rendering* is inspected.

**Alternatives rejected.**

- *`ViewThatFits`.* It exists (`SwiftUI.swiftinterface:10808`) and would pick the fitting
  layout automatically — but the choice happens at render time and is therefore untestable in
  the unit target, which is exactly what SC-013 is trying to avoid.
- *`minimumScaleFactor` on the amount.* Rejected: shrinking text to fit is a form of
  abbreviation, and FR-021 says the amount never yields. It also lowers effective contrast.
- *Keep `LabeledContent` and add padding.* Rejected: it treats the symptom of an unverified
  finding, and `LabeledContent` additionally renders its value `.secondary`, which 016 already
  had to override at every site (`ImportedAccountsView.swift:11–13`) — FR-066 makes that
  override a requirement, and a component that fights the requirement at every use is the wrong
  component.

---

## R13 — Date grouping is `List` + `Section`, and the group is computed on the page, not queried

**Decision.** Rows arrive from `history_page` already in order. The view model folds the flat
sequence into `[DateGroup]` (`date` + `rows`) as pages arrive, appending to the last group when
a page's first row shares its date. The view is a `List` of `Section`s with
`.listStyle(.plain)`, whose headers pin while scrolling — FR-034. Headings carry the date and
optionally a transaction count; **never an amount** (FR-026).

**Rationale.**

- Grouping is a pure function of an ordered sequence, so it needs no engine support, no
  `GROUP BY`, and no second query. The engine stays a sequence producer; the app decides how
  the sequence is presented. That keeps FR-045 true (one population, one ordering) with no
  extra place for it to go wrong.
- A group can **span pages**, so grouping must be incremental — the folder takes the previous
  group's date as its seed. A test pins that folding pages of 30 into groups yields exactly the
  same groups as folding the whole sequence at once, for a corpus with a date group larger than
  a page (the spec's edge case "a day carrying an unusually large number of transactions").
- FR-035 (include the year when it is not the current year) is a formatting decision that needs
  "now". The core reads no wall clock (Constitution II), so the current year is supplied by the
  app, from an injectable clock — the same pattern `ImportService`'s `now:` parameter already
  uses (`ImportService.swift:20`). This makes the year rule deterministically testable, which
  it would not be with `Date()`.

**Alternatives rejected.**

- *Group in the engine and return `Vec<DateGroup>`.* Rejected: a group split across a page
  boundary would have to be either re-sent or partially sent, and both make the cursor mean two
  things. A flat sequence has one meaning.
- *A custom sticky header over a `ScrollView`.* Rejected: `List` + `Section` is the system
  behaviour, gets Liquid Glass and Dynamic Type for free, and the skill's rule is not to
  re-skin system chrome.

---

## R14 — Staying current with an import is already structural; only the refresh and the anchor are new

**Decision.**

- **FR-054 ("never a partially-written statement") needs no new mechanism.**
  `import_statement` writes the account, the statement row, every transaction, the re-import
  links, the categorization and the dedup links inside a single `conn.transaction()` and
  commits once (`store.rs:589–710`). Every reader takes the same `Mutex<Connection>`
  (`store.rs:966`), and R11 makes it the *same* `Store` instance. A page therefore observes
  either the whole statement or none of it. This is a property of 016's atomic import, not
  something this slice adds — and it is why R11's "one `Store` per process" is a correctness
  decision and not a tidiness one.
- **FR-053 (appear without a relaunch)**: `ImportService` gains one `AsyncStream<Void>`
  continuation yielded after a successful `persist`. `TransactionListViewModel` consumes it and
  re-reads the pages it currently holds, from page 1, with the same filter.
- **FR-056 (not thrown to the top, not thrown out of the filter)**: before the re-read the view
  model captures the row id at the top of the viewport via
  `.scrollPosition(id:)` (verified present: `SwiftUI.swiftinterface:21438`, and `ScrollPosition`
  at `SwiftUICore.swiftinterface:690`), and restores it after. The filter is view-model state
  and is simply not touched by the refresh — the strongest possible guarantee that a refresh
  cannot move a person out of it.
- **FR-055 (a failed or cancelled import leaves the list identical)**: the stream is yielded
  only on the success path, so a cancelled import produces no refresh at all. 016 already
  guarantees the store is byte-identical after a failure.

**Alternatives rejected.**

- *Poll the store on a timer.* Rejected: it burns decrypts on an idle screen and still cannot
  meet SC-010's 1-second bound reliably.
- *A "N new transactions — tap to load" banner.* Rejected: FR-053 says the transactions must
  appear, and SC-010 allows 1 second. A banner is a second thing to get right and it makes the
  person do work to see their own data.
- *`NotificationCenter`.* Rejected: an untyped global bus between two actors, when a typed
  stream between two objects that already know about each other costs less.

---

## R15 — Reaching the list: one tap, from either the front door's list or the front door itself

**Decision.** `RootView`'s `NavigationStack` gains one destination. `ImportedAccountsView`'s
rows become `NavigationLink`s carrying the account id (FR-002 / FR-037 — arrive filtered), and
a toolbar item — "All transactions" — pushes the same destination with no filter (FR-001 —
one action, unfiltered). Back is the standard navigation-stack back (FR-005), which restores
the front door because the front door's state lives above the pushed view.

**Rationale.** FR-001 and FR-002 are both "no more than one action", from a screen that today
has non-actionable rows and one bottom-bar button. A `NavigationStack` destination gives both,
gives the standard back affordance for free, and preserves the front door by construction. The
empty-state front door (no accounts) has nothing to link to and correctly shows FR-047's empty
state on the list if reached.

**Alternative rejected.** *A sheet.* Rejected: a sheet's dismissal is not the platform's
standard back affordance (FR-005), and a sheet over a list of a year of transactions is the
wrong container for a screen a person scrolls for minutes.

---

## R16 — Money stays `Decimal` through formatting; currency is always shown; no figure combines currencies

**Decision.** `amount` crosses as `rust_decimal::Decimal` → base-10 `String` →
`Foundation.Decimal` (the existing `uniffi::custom_type!` at `ffi.rs:60`) and is formatted with
`Decimal.formatted(.currency(code:))` — `Decimal`'s own `FormatStyle`, which never routes
through `Double`. `.monospacedDigit()` on every amount (FR-016). The currency code comes from
the **transaction's** `currency` column, never the account's and never the locale's.

**Rationale.**

- Constitution II: "Money is never a floating-point number." `NumberFormatter` on a
  `Decimal` goes through `NSDecimalNumber` and stays exact; `String(format:)` and any
  `Double`-taking API do not. A test asserts a 7-digit-plus-2 amount round-trips through
  formatting without drift, and `make lint` plus review keep `Double` off this path.
- FR-023 (always carry the currency, even in a single-currency corpus) and FR-025 (**no** figure
  derived from more than one currency) are both satisfied by having **no aggregate at all** in
  this slice. There is no total to get wrong. The only numbers on the screen are per-row amounts
  and per-group transaction *counts*, which are not money. FR-026 is therefore enforced by the
  absence of a code path rather than by a rule, which is why the group header type carries no
  amount field at all — a later slice would have to add one deliberately.
- FR-027 (a currency the locale does not usually format) — `.currency(code:)` falls back to the
  ISO code as the symbol, which is unambiguous and never wrong. A test covers a code the
  `en_IN` locale does not localise.

---

## R17 — 🚨 FINDING: a cross-account duplicate makes one of a person's rows disappear, and *which* one is decided by a random id

**This is a defect in shipped code, not in this slice. It is recorded, not fixed here.**

**What was found.** `import_statement` calls `find_duplicates_in` on every import
(`store.rs:706`). That function loads candidates grouped by account, ordered
`ORDER BY a.created_at, a.id, t.rowid` (`store.rs:1393`), and links duplicates **across
accounts** via `dedup::cross_source_duplicates`, whose L3 CANONICAL layer matches on same date
+ same amount + same direction + same 60-char normalized narration prefix
(`dedup.rs:186–200`). The loser gets `superseded_by` set — and this slice's live-row rule
(FR-007) then hides it.

**Measured.** Two accounts, each with an identical row (`2025-03-04`, `COFFEE SHOP`, `250.00`,
Debit) plus one row unique to it, imported through the real `Store::import_statement`:

```
E7 A COFFEE SHOP  250.00 superseded_by=None                              layer=None
E7 A A ONLY        11.00 superseded_by=None                              layer=None
E7 B COFFEE SHOP  250.00 superseded_by=Some("63dc18c03dfe3860930f346391e28692") layer=Some(Canonical)
E7 B B ONLY        12.00 superseded_by=None                              layer=None
```

**The same test, run a second time on a fresh database, produced the opposite result** — account
A's row was the one superseded. Nothing changed but the minted ids. Both accounts are created by
the same import run in the same second, so `a.created_at` is the identical string and the
tie-break falls through to `a.id`, which is `SELECT lower(hex(randomblob(16)))`
(`store.rs:1257`). Which of a person's two cards keeps the transaction is decided by 128 random
bits.

**Why it matters to this slice specifically.**

1. **It contradicts a written acceptance scenario.** US1 acceptance scenario 6: "Given two
   accounts contain a transaction with the same date, description and amount, When both appear
   in the list, Then each is attributed to its own account and neither is mistaken for, merged
   with, or hidden by the other." As shipped, one of them *is* hidden — by FR-007, correctly
   applying a rule to data that was written wrongly. **This slice cannot make US1 AS-6 pass.**
2. **This slice is what makes it visible.** Today the effect is one integer being smaller than
   expected on the front door. After this slice, a person looking at two cards can see a
   coffee they definitely bought, on one card and not the other.
3. **The behaviour is not wrong in general** — cross-source dedup exists so that a bill payment
   appearing on both a bank ledger and a card statement is one row, not two. The *tie-break* is
   what is wrong, and possibly the absence of a same-institution guard.

**Decision for this slice — ✅ FIX IT HERE.** Put to the repo owner, who overruled the original
"record, don't fix" recommendation: *"a finance app that reorders rows between launches is the
trust problem 018 exists to avoid."* It breaks a written acceptance scenario of **this** slice,
and this slice is what makes it visible, so it is fixed in **PR A** alongside the read path.

The fix is the minimal one this research already identified: order dedup's account groups by
**`accounts.rowid`** rather than `a.created_at, a.id` — the same single account ordering R3
establishes for the whole app. That makes the outcome deterministic, makes it match the order
the person actually sees, and changes nothing about *what* dedup matches. The random-id
tie-break disappears because `rowid` is total and monotonic.

Scope discipline still applies: this is a **tie-break** change, not a change to the matcher. Do
**not** add a same-institution guard, do **not** touch `dedup.rs`'s layers, and do **not**
change which pairs are considered duplicates — those remain findings to record, not work to do
here.

Consequences:

- US1 AS-6 is a **live, enabled test** in PR A, not `@Test(.disabled(…))`. It must be written
  RED first — the existing behaviour genuinely fails it — and the fix turns it green.
- Determinism needs proving across processes, not within one: the same import repeated on a
  fresh database must supersede the **same** row every time. A single-run assertion would have
  passed against the shipped defect.
- The synthetic corpus for this slice is still built so it does not trip the matcher
  accidentally (R20) — that is about measuring the right thing, and is unaffected.

---

## R18 — 🚨 FINDING: `is_transfer` is never set in a real install, so FR-018 can be built but not exercised

**What was found.** FR-018 requires a transfer to be marked, and `transactions.is_transfer`
(schema v3) is the flag. It is written by exactly one thing: `Store::detect_transfers`
(`store.rs:870`).

```
$ grep -rn "detectTransfers" ios/Sources ios/Tests
ios/Tests/StoreTransferTests.swift:55:    func detectTransfersTagsBothLegsOverTheBridge() throws {
ios/Tests/StoreTransferTests.swift:69:        let summary = try store.detectTransfers()
ios/Tests/TransferDetectionTests.swift:51:        let pairs = detectTransfers(rows: Self.rows)
```

**Nothing under `ios/Sources/` calls it.** `import_statement` calls `link_reimported_rows_in`,
`categorize_account_in` and `find_duplicates_in` — not transfer detection. So on a real device
today, `is_transfer` is `0` on every row, and US6's transfer marking would render for nobody.

**Why it was not simply wired up.** `transfer::detect_transfers` anchors on every debit and, for
each, scans every row for a counterpart, computing a Jaro-Winkler narration similarity in the
comparator (`transfer.rs:88–130`). That is O(debits × rows) with a string-similarity inner
term — on a 10,000-row corpus, roughly 7.5 × 10⁷ similarity computations, on the import path,
on a phone. Calling it after every import is not a one-line change; it is a performance
decision that needs its own measurement, and it is squarely inside the "no change to import"
line the spec drew.

**Decision for this slice.**

- Build the rendering. FR-018's marking, its non-colour carrier, its VoiceOver announcement and
  its "still appears in the list" rule are all implemented and **tested**, by seeding a real
  store, calling `store.detectTransfers()` in the test (exactly as `StoreTransferTests.swift:69`
  already does) and reading the list back. The requirement is fully covered.
- Do **not** call `detectTransfers()` from the app. Record in `plan.md` that no row will be
  marked in a real install until a later slice decides where detection runs and what it costs,
  and raise it to the product owner as the second judgement call.

---

## R19 — The networking audit does not cover the new directory; widen it in the same PR

**Decision.** Change `scripts/import-path-audit.sh` so the networking denylist scans
`ios/Sources` rather than `ios/Sources/Import`, and rename the emitted message accordingly.

**Rationale.** `IMPORT_DIR="$REPO_ROOT/ios/Sources/Import"` and
`SOURCES_DIR="$REPO_ROOT/ios/Sources"` (`scripts/import-path-audit.sh:15–16`); the networking
grep uses `IMPORT_DIR`, while the bank-literal and Liquid Glass greps use `SOURCES_DIR`. A file
added at `ios/Sources/Transactions/TransactionHistoryService.swift` is therefore checked for
glass and bank names and **not** for `URLSession`. FR-062 and SC-015 demand zero network I/O
"including on the new cross-account read", and SC-015 says "verified automatically" — which it
would not be. Widening is strictly safer: nothing under `ios/Sources/` may network, on any
path, per Constitution Principle I; there is no free-path exception to hold back for.

The audit must be widened **in the same PR that adds the directory**, for the same reason 017
put gate G7 in the same PR as the widening it guards: a gate that lands later is a gate that
was absent when it mattered.

---

## R20 — The synthetic corpus must be built so it does not de-duplicate itself

**Decision.** The 10,000-row / 8-account performance corpus, and every multi-account fixture,
gives **every row a globally unique amount and a globally unique description**. It is written
through `Store::import_statement` for the correctness fixtures (so it exercises the real write
path) and through direct SQL for the performance corpus (so seeding does not dominate the run).

**Rationale — this is a measurement, and it cost an hour to find.** The first version of the
performance probe cycled amounts and dates across accounts. It reported:

```
E1c total=10000 live=1250
```

Eight thousand seven hundred and fifty of ten thousand rows had been superseded — the corpus
had de-duplicated itself down to a single account's worth, via the fuzzy layer (same amount,
same direction, dates within ±1 day, similar narration) across accounts. A page query against
it would have measured a corpus 8× smaller than the one it claimed to measure, and the
performance criteria would have "passed" against nothing.

The same run also showed what seeding through the real import path costs at this scale:
`E1b seeded 8x1250 in 11.770755125s` through `import_statement` (400 imports, each running a
full cross-account `find_duplicates_in` over a growing pool) versus
`E1b seeded 8x1250 in 151.425084ms` through direct SQL — a 78× difference. Correctness fixtures
stay on the real path because that is what they are proving; the performance corpus does not,
because it is proving something else and an 11-second fixture makes the gate unrunnable.

**Consequences written into the fixture contract** (`data-model.md` § Test corpus): unique
amount per row; unique description per row; at least two currencies; at least one date carrying
rows from more than one account (with *different* amounts, so R17 does not fire); at least one
account with zero live rows; at least one deleted and one superseded row; and a date group
larger than one page. All synthetic, no real merchant, no real account identifier (FR-064,
SC-017).
