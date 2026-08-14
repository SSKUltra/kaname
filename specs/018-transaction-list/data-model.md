# Phase 1 Data Model — The Transaction List (`018-transaction-list`)

**Date**: 2026-08-14 | **Source**: [`spec.md`](./spec.md) Key Entities → [`research.md`](./research.md) decisions

This slice adds **no field a person can see** to the store. It adds one index, two engine reads,
and a set of presentation types on the platform side. Nothing crosses a layer except through the
types below.

```text
  Swift (platform)                UniFFI boundary              Rust (kaname-core)
  ────────────────                ───────────────              ──────────────────
  TransactionListViewModel  ──▶   HistoryQuery          ──▶    history_page()
        │                                                            │
        │                   ◀──   HistoryPage           ◀────────────┤  transactions
        │                          { rows, cursor }                  │  (schema v7 index)
        ├─ [DateGroup]                                               │
        ├─ TransactionRow  ◀───    HistoryRow                        │
        └─ AccountFilter   ──▶     HistoryQuery.accountId            │
                                                                     │
  ImportedAccount          ◀───    AccountSummary       ◀────────────┘  account_summaries()
```

Money is `rust_decimal::Decimal` ⇄ base-10 `String` ⇄ `Foundation.Decimal` at every hop —
never a float, including through formatting (research R16). Dates are `NaiveDate` ⇄ ISO-8601
`String`.

---

## 1. Storage — schema v7

### The one migration

```rust
const SCHEMA_V7: &str = "\
CREATE INDEX idx_txn_live_account_date \
    ON transactions(account_id, date DESC) \
    WHERE is_deleted = 0 AND superseded_by IS NULL;";
```

`SCHEMA_VERSION` 6 → 7 (`store.rs:41`), applied by the existing forward-only runner
(`apply_migration`, `store.rs:1201`). Shape and risk, compared with the five migrations already
shipped:

| | v2 | v3 | v4 | v5 | v6 | **v7** |
|---|---|---|---|---|---|---|
| Adds a table | ✓ | | | ✓ | | |
| Adds a column | ✓ | ✓ | ✓ | ✓ | ✓ | |
| Adds an index | | | | ✓ | | ✓ |
| Rebuilds a table | | | | | | |
| Disables foreign keys | | | | | | |
| Writes or reads a row | | | | | | |

v7 is the **least invasive migration in the store's history**: it creates an index and touches
no row, no column and no constraint. It is idempotent under the runner (each version is applied
exactly once, gated on `PRAGMA user_version`) and it is forward-only, like every migration
before it.

**Why `DESC` and why partial** — measured, research R4. `DESC` makes the index entry order
`(account_id ASC, date DESC, rowid ASC)`, which is the ordering key with the account fixed; an
ASC index costs `USE TEMP B-TREE FOR LAST TERM OF ORDER BY`. Partial keeps the index to the live
rows (282,624 bytes for 10,000 rows, +12.4% on the database) and makes the live-row rule
structural.

**Cost on write.** One extra b-tree insert per transaction inserted, inside the existing import
transaction. No change to `import_statement`'s semantics or atomicity.

### No table, column, constraint or stored value changes

`accounts`, `transactions`, `statements`, `categories` are untouched. `is_deleted`,
`superseded_by`, `dedup_layer`, `is_transfer`, `transfer_group_id`, `category_id`, `currency`
and `date` are all read; none is written by this slice.

---

## 2. The ordering key — the one definition the whole slice depends on

A row's position in the combined history is the triple

```text
  ( date , account_position , rowid )
```

compared **date descending, account_position ascending, rowid ascending**.

| Component | Where it comes from | Why it is safe |
|---|---|---|
| `date` | `transactions.date`, ISO-8601 `TEXT` | Lexicographic order over `YYYY-MM-DD` is chronological order. It is the date the transaction *happened*, never the import time. |
| `account_position` | the row's account's index in `Store::list_accounts()` — i.e. `accounts.rowid`, insertion order (`store.rs:496–501`) | It is *the front door's own ordering* (FR-030), so a person sees one account order in the app. It is not a hidden identifier; it is the visible one's representation. |
| `rowid` | `transactions.rowid` | Insertion order = printed order within one imported statement (research R8). Stable: nothing in the repo runs `VACUUM`, and `VACUUM` preserves relative order anyway (measured). Never displayed. |

**Totality.** Every live row has exactly one date, exactly one account and exactly one rowid;
rowid is unique within the table. The order is therefore strict and total, with no fallback
clause — which is what makes FR-031 provable rather than argued.

### Known limit, priced

`rowid` is *insertion* order, which equals *printed* order within one statement. Two
**different** statements of the **same** account that both contribute **live** rows on the
**same** date interleave by import order, not by anything printed. Re-importing the same
statement cannot cause it (`link_reimported_rows_in` supersedes the repeats). The order remains
total, deterministic and stable in that case; it is simply not the paper's order.

**The fix, if a later slice wants it**: `ALTER TABLE transactions ADD COLUMN statement_line_no
INTEGER` written by `import_statement`'s insert loop, plus a persisted statement ordering, and
the key becomes `(date, account_position, statement_position, statement_line_no)`. That is new
stored data, which this slice's spec forbids. Recorded here so the price is known.

---

## 3. New engine types (Rust, `uniffi`-exported)

Full signatures and error behaviour: [`contracts/engine-history.md`](./contracts/engine-history.md).

### `HistoryQuery` — `uniffi::Record`

| Field | Type | Notes |
|---|---|---|
| `account_id` | `String?` | `nil` = every account, in front-door order. Non-`nil` = that account only. **The only difference between a filtered and an unfiltered read** (FR-042). |
| `cursor` | `HistoryCursor?` | `nil` = start at the newest end of the sequence. |
| `limit` | `u32` | Rows per page. Clamped to `1...200` by the engine; an out-of-range value is clamped, never an error. |

**Validation.** An `account_id` that names no account yields an **empty page**, not an error —
the account may have been legitimately absent since the caller last read (there is no delete
path today, but a read must not throw on a race it cannot prevent).

### `HistoryCursor` — `uniffi::Record`

| Field | Type | Notes |
|---|---|---|
| `marks` | `[AccountMark]` | One resume point per account still producing rows. An account that has been exhausted is **absent**, so the cursor shrinks as the person scrolls. |

**Opaque.** Swift stores it and hands it back. No Swift code reads a field of it; a test asserts
no view or accessibility string references `sequence`.

### `AccountMark` — `uniffi::Record`

| Field | Type | Notes |
|---|---|---|
| `account_id` | `String` | which stream this mark resumes. |
| `date` | `NaiveDate` | the date of the last row emitted from that account. |
| `sequence` | `i64` | `transactions.rowid` of that row. Internal; never displayed (FR-019). |

### `HistoryRow` — `uniffi::Record`

| Field | Type | Source | Requirement |
|---|---|---|---|
| `id` | `String` | `transactions.id` | SwiftUI list identity. Never displayed. |
| `account_id` | `String` | `transactions.account_id` | filter identity; never displayed. |
| `account_name` | `String` | `accounts.name` of the attributed account | FR-004, FR-022 |
| `account_last4` | `String?` | `accounts.last4` | FR-003 — the same identity the front door shows |
| `date` | `NaiveDate` | `transactions.date` | FR-012, FR-028 |
| `description_raw` | `String` | `transactions.description_raw` | FR-012 — as the statement printed it |
| `amount` | `Decimal` | `transactions.amount` | FR-016 — exact, never a float |
| `direction` | `Direction` | `transactions.direction` | FR-014 — from the recorded direction, never from a sign |
| `currency` | `String` | `transactions.currency` (**the row's, not the account's**) | FR-023, FR-024 |
| `category_name` | `String?` | resolved from `transactions.category_id` | FR-017 — `nil` ⇒ the app's "Uncategorized" wording |
| `is_transfer` | `bool` | `transactions.is_transfer` | FR-018 — ⚠️ always `false` in a real install today (research R18) |

**Deliberately absent**, so they cannot leak into a view (FR-019, SC-016): `superseded_by`,
`dedup_layer`, `statement_id`, `categorised_by`, `transfer_group_id`, `is_deleted`, `rowid`,
`created_at`, `updated_at`.

`account_name`, `account_last4` and `category_name` are filled in Rust from two small maps
loaded once per page (the account list, and the category catalog), **not** by a SQL join — so
the per-account query stays index-only and the plan-shape gate stays meaningful.

### `HistoryPage` — `uniffi::Record`

| Field | Type | Notes |
|---|---|---|
| `rows` | `[HistoryRow]` | in the ordering above; `count <= limit`. |
| `cursor` | `HistoryCursor?` | `nil` ⇔ the sequence is exhausted. A page with `rows.count < limit` **and** a non-`nil` cursor is impossible and is asserted in a test. |

### `AccountSummary` — `uniffi::Record`

| Field | Type | Notes |
|---|---|---|
| `id`, `name`, `last4`, `is_credit_card`, `currency` | as `StoredAccount` | the front door's existing fields |
| `live_transaction_count` | `u32` | the **only** count this slice produces, from the `LIVE` predicate and the v7 index (FR-006, FR-008, FR-046) |
| `has_only_excluded_rows` | `bool` | `true` when the account holds rows and every one is deleted or superseded |

**Why the second field is a boolean and not a count.** FR-008 requires every count this slice
introduces to use the live rule. A `stored_transaction_count` field would be a number that
violates it the moment someone renders it. A boolean cannot be rendered as a count, and it is
exactly enough to tell FR-048 from FR-050. See the empty-state table in §6.

**Order.** Identical to `Store::list_accounts()` — the front door's order — asserted by a test
comparing the two id sequences.

---

## 4. Platform types (Swift)

### `TransactionRow` — the view's value type

Mirrors `HistoryRow` one-for-one plus the derived presentation facts, all of them pure
functions so they are testable with no view rendered (FR-074, SC-013):

| Member | Type | Notes |
|---|---|---|
| `id` | `String` | list identity |
| `date`, `descriptionRaw`, `amount`, `currency`, `direction`, `accountName`, `accountLast4`, `categoryName`, `isTransfer` | from `HistoryRow` | |
| `formattedAmount` | `String` | `Decimal.formatted(.currency(code:))` — exact, tabular digits applied at the view (FR-016, FR-027) |
| `directionWord` | `String` | "debit" / "credit" — words, never a symbol or a colour (FR-013, FR-015) |
| `categoryLabel` | `String` | `categoryName ?? Strings.uncategorized` — never blank (FR-017) |
| `accessibilityLabel` | `String` | one sentence: date, description, amount + currency, direction in words, account, and transfer when set (FR-015, FR-018) |

### `TransactionRowLayout` — the layout decision, extracted so it can be tested

| Member | Type | Notes |
|---|---|---|
| `axis` | `.horizontal` \| `.vertical` | `.vertical` iff `dynamicTypeSize.isAccessibilitySize` |
| `descriptionLineLimit` | `Int` | 2 horizontal, 3 vertical — the description yields first (FR-021) |
| `accountNameLineLimit` | `Int` | 1 — the account name yields second (FR-021) |
| `amountYields` | `Bool` | **always `false`**, at every `DynamicTypeSize`; pinned by a test over all 12 cases (FR-021, FR-065) |

### `DateGroup`

| Member | Type | Notes |
|---|---|---|
| `date` | `Date` | one group per calendar date **across all accounts** (FR-033) |
| `heading` | `String` | includes the year when it is not the current year (FR-035); the "current year" comes from an injected clock, never `Date()` inside the formatter |
| `rows` | `[TransactionRow]` | in ordering-key order |

**Carries no amount, and has no field that could hold one** (FR-026, FR-025). A later slice
wanting a per-day total must add the field deliberately.

### `AccountFilter`

| State | Meaning |
|---|---|
| `.all` | every account (the launch state, always — FR-041) |
| `.account(id: String, name: String, last4: String?)` | one account, named on screen at all times (FR-003, FR-038) |

Lives in `TransactionListViewModel` as plain state. **Never persisted** — not to `UserDefaults`,
not to the store, not to a scene-restoration payload. FR-041 is satisfied by there being nowhere
for it to be read back from.

### `ImportedAccount` (existing, `ImportModels.swift:70–77`)

`transactionCount` keeps its name and meaning and is now filled from
`AccountSummary.liveTransactionCount` instead of a Swift-side filter. Gains
`hasOnlyExcludedRows` for the empty-state choice.

---

## 5. State transitions — the list screen

```text
                    ┌──────────────┐
      open list ───▶│   loading    │
                    └──────┬───────┘
                    page 1 │ returns
             ┌─────────────┼──────────────┐
             ▼             ▼              ▼
      ┌────────────┐ ┌───────────┐ ┌──────────────┐
      │  showing   │ │   empty   │ │ unavailable  │
      │  (n rows)  │ │ (4 kinds) │ │ (store error)│
      └─────┬──────┘ └───────────┘ └──────────────┘
            │
            ├── scrolled near the end ──▶ loadingMore ──▶ showing (n+limit rows)
            ├── filter changed ─────────▶ loading (cursor discarded, page 1)
            ├── import completed ───────▶ refreshing (pages held re-read, anchor kept)
            └── import failed/cancelled ─▶ showing (unchanged — no event is emitted)
```

**Invariants, each pinned by a test:**

1. `showing → refreshing → showing` never changes `AccountFilter` (FR-056).
2. `refreshing` restores the captured top-visible row id (FR-056).
3. `loadingMore` never re-requests a cursor it has already consumed (no duplicate rows).
4. No state ever holds a row whose `id` is not in the current filter's population (FR-040 —
   "no rows of the previous account left behind").
5. A failed or cancelled import produces **no** transition, because no event is emitted
   (FR-055).

---

## 6. Empty states — the decision table

Every branch is a pure function of `[AccountSummary]` and the current filter, so it is fully
testable in the unit target (FR-074).

| # | Condition | State | Requirement |
|---|---|---|---|
| 1 | `summaries.isEmpty` | "Nothing imported yet" + the import action | FR-047 |
| 2 | filter `.all`, all summaries have `liveTransactionCount == 0` and none has `hasOnlyExcludedRows` | "The statements you imported had no transactions" | FR-048 |
| 3 | filter `.all`, all summaries have `liveTransactionCount == 0` and some has `hasOnlyExcludedRows` | "Nothing to show" — no accusation of loss | FR-050, FR-051 |
| 4 | filter `.account`, that summary's `liveTransactionCount == 0`, `hasOnlyExcludedRows == false` | "This statement had no transactions" — **not** an error, **not** "nothing imported" | FR-048 |
| 5 | filter `.account`, that summary's `liveTransactionCount == 0`, `hasOnlyExcludedRows == true` | "Nothing to show for this account" + clear-the-filter action | FR-049, FR-050 |
| 6 | filter `.account`, count 0, **and other accounts have rows** | the filter is named as the reason + clear-the-filter action | FR-049 |

Row 6 refines rows 4–5 rather than replacing them: the filtered empty state always offers to
clear the filter when clearing would show something.

**Wording rules that are tested rather than reviewed** (FR-052, SC-013): every worded count is
generated by one pluralisation helper; a test asserts the singular form for `1` and the plural
for `0` and `2` in every string that carries a count; a test asserts no empty-state string
contains "lost", "missing", "gone", "error" or "failed" (FR-051); a test asserts no
user-visible string contains an id, an internal code or a layer name (FR-019, SC-016).

---

## 7. Test corpus — the fixture contract

Derived from research R20, where a first attempt at this corpus silently de-duplicated 8,750 of
its 10,000 rows.

**Every fixture, without exception:** synthetic; no real merchant, no real account identifier,
no real statement (FR-064, SC-017).

**Correctness corpus** (written through the real `Store::import_statement`):

| Property | Why |
|---|---|
| Every row a **globally unique amount** and a **globally unique description** | otherwise `find_duplicates_in` supersedes rows across accounts and the fixture measures a smaller corpus than it claims (R20), or silently exercises R17 |
| ≥ 3 accounts | FR-030's account tie-break needs more than two to be more than a coin flip |
| ≥ 2 currencies, including one the `en_IN` locale does not localise | FR-023, FR-027, SC-011 |
| ≥ 1 date carrying rows from more than one account, with **different** amounts | FR-030, US4 AS-5 — different amounts so R17 does not fire |
| ≥ 1 account with zero live rows because its statement had none | empty state 4 |
| ≥ 1 account whose every row is superseded, and ≥ 1 deleted row | FR-007, FR-010, SC-005, empty state 5 |
| ≥ 1 date group larger than one page | R13's cross-page grouping, and the spec's "unusually large date" edge |
| ≥ 1 empty description, ≥ 1 very long description, ≥ 1 amount with 7+ integer digits | FR-020, FR-021, the spec's edge cases |
| ≥ 1 transfer pair, marked by calling `store.detectTransfers()` in the test | FR-018 — the only way to get `is_transfer = 1` (R18) |

**Performance corpus** (written by direct SQL — 151 ms versus 11.8 s through the import path,
measured in R20): 10,000 rows over 8 accounts, all-unique amounts and descriptions, plus a
200-row / 2-account twin for the SC-008b ratio.
