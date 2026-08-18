# Phase 0 Research: Categorize (`020-categorize`)

Every claim below is checked against the code at `adf9206` on branch `020-categorize`. Where the
spec and the codebase disagree, the codebase wins and the disagreement is written down as an
amendment (`plan.md` § *Spec amendments*). Line numbers are from the files as they stand today.

Four things in the feature prompt that set this work up were **wrong about the repository**, and
one of them would have sent the FFI work to a file that does not exist. They are corrected in R1.

---

## R1 — ⚠️ Four load-bearing coordinates in the brief are wrong, and one file does not exist

| Claimed | Actual | Consequence |
|---|---|---|
| `core/src/ffi.rs` | **`core/crates/kaname-core/src/ffi.rs`** — `core/` is a workspace whose only member is `crates/kaname-core` | Nothing to fix in the plan's shape, but the path appears in `AGENTS.md:88-92` too and is worth not repeating |
| The FFI change goes in `ffi.rs` / `#[uniffi::export]` | **`Store` is a `uniffi::Object`** (`store.rs:559-561`) and every one of its methods is exported by a single `#[uniffi::export] impl Store` block **in `store.rs`** (`store.rs:571`). `ffi.rs` holds only free functions (readers, `categorize`, `default_categories`, the `Decimal`/`NaiveDate` custom-type bridges at `ffi.rs:60-70`). There are **no** free `history_*` functions in `ffi.rs` at all | Every new store method in this slice lands in `store.rs`, not `ffi.rs`. Only the one pure function (R8) goes near `ffi.rs`. `make core-xcframework` → `make ios-gen` is still mandatory and unchanged |
| `apply_migration` at `store.rs:1257-1275` | `apply_migration` is at **`store.rs:1521-1544`**; `store.rs:1258-1273` is **`migrate()`**, the loop that calls it | Both matter and they are different functions — see R4 |
| `categorize_account_in` at `store.rs:1303-1324` | **`store.rs:1278-1327`**; the `UPDATE` is line **1304** | — |

Two more, minor: `import_statement`'s call is one line, `store.rs:825` (not 824-846);
`detect_transfers` is `store.rs:1150-1187` (not 1160-1183); `normalize_narration` is
`dedup.rs:52-70` (not 55-70). The row loader is `load_account_transactions`,
`store.rs:1759-1798`.

**Everything else in the brief checks out**, including the two claims the slice actually rests
on: there is no single-row category write anywhere on `Store` (R2), and `categorize_account_in`
overwrites unconditionally (R3).

---

## R2 — Confirmed: there is no write path, and the full method list proves it

`impl Store`'s complete public surface is `open, insert_account, list_accounts,
insert_statement, list_statements, insert_transaction, import_statement, list_transactions,
history_page, account_summaries, list_categories, insert_category, insert_merchant_rule,
list_merchant_rules, insert_source_category_mapping, list_source_category_mappings, insert_rule,
list_rules, categorize_account, detect_transfers, find_duplicates, coverage, schema_version`.

Not one of them takes *a transaction id and a category*. The only four statements in the
repository that ever put a value in `transactions.category_id` are:

1. `insert_transaction` (`store.rs:684-708`) — a one-off insert, caller-supplied.
2. `import_statement`'s bulk insert (`store.rs:855-870`) — writes **`NULL, NULL`** literally,
   in the SQL text, for every imported row.
3. `detect_transfers` (`store.rs:1160-1163`).
4. `categorize_account_in` (`store.rs:1304`).

A person is behind none of them. **This slice cannot be Swift-only**, and the brief is right that
`make core-xcframework` → `make ios-gen` is mandatory — the sequence `AGENTS.md:88-92` exists to
protect, where a stale xcframework produces "cannot find `X` in scope", a Swift error that is not
a Swift problem.

---

## R3 — 🚨 The defect is exactly as described, and it is worse than "corrections are lost"

`categorize_account_in` (`store.rs:1278-1327`) prepares one statement:

```rust
let mut update = tx.prepare(
    "UPDATE transactions SET category_id = ?2, categorised_by = ?3 WHERE id = ?1",
)?;
```

and runs it against **every** row `load_account_transactions` returns, with no guard of any kind.
When the stack returns `None` it writes nulls:

```rust
None => {
    update.execute(params![txn_id, Option::<String>::None, Option::<String>::None])?;
    summary.uncategorized += 1;
}
```

The loader's filter is `account_id = ?1 AND is_deleted = 0 AND superseded_by IS NULL AND
is_transfer = 0` (`store.rs:1764-1770`) — live, non-transfer rows, which is precisely the set a
person can see and would correct. `import_statement` calls it on every import (`store.rs:825`),
and `Store::categorize_account` (`store.rs:1126-1132`) calls it on demand.

**Worse than losing the correction**: because the write is unconditional and null-writing, a
person's correction is not merely *overwritten by a better answer* — it is **erased to nothing**
whenever the stack has no rule for that merchant, which is the common case for exactly the
merchants a person bothers to correct. The row reverts from a real category to `Uncategorized`.

---

## R4 — The migration mechanism, and why v8 can be purely additive

`migrate()` (`store.rs:1258-1273`) is a `while version < SCHEMA_VERSION` loop; each step opens its
own `rusqlite::Transaction`, calls `apply_migration(&tx, next)`, bumps `PRAGMA user_version`
**inside the same transaction**, and commits. The comment at `store.rs:1267-1268` is explicit that
`user_version` lives in the header page and rolls back with the transaction.

That gives FR-048/SC-015 ("no partially migrated store") **for free, already** — it is a property
of the existing mechanism, not something this slice must build. `apply_migration`
(`store.rs:1521-1544`) is a `match` where every arm is `tx.execute_batch(SCHEMA_Vn)`; v1 also
calls `seed_categories`. Adding v8 is one arm plus one `const SCHEMA_V8` plus `SCHEMA_VERSION: i64
= 8` (`store.rs:41`).

**The design goal that follows**: keep v8's DDL to `CREATE TABLE` and `CREATE INDEX` only. If v8
never reads or writes a single existing row, then FR-047 and SC-014 ("every row identical
afterwards, zero categories re-derived") are true by construction rather than by testing hard
enough. R5 and R7 are chosen so that this holds.

---

## R5 — 🚨 The provenance decision: a reserved `categorised_by` value, and why the other two shapes lose

`transactions.categorised_by` is `TEXT` with **no `NOT NULL` and no `CHECK`** (`store.rs:82`) —
contrast `direction TEXT NOT NULL CHECK (direction IN ('Debit','Credit'))` on line 79 and
`dedup_layer`'s CHECK added in v4 (`store.rs:140-141`). The five values ever written are
`CC_RULE`, `T1_SOURCE_CATEGORY`, `T2_MERCHANT_MAP`, `T3_RULE` (`stage_to_sql`,
`store.rs:2148-2155`) and `TRANSFER_DETECTOR` (`store.rs:47-48`).

Critically: **nothing parses `categorised_by` back**. There is no `stage_from_sql`, no `FromSql`
impl, no reader anywhere. `HistoryRow`'s doc comment (`store.rs:321-324`) says outright that it
deliberately carries no `categorised_by`. So a new value cannot break an existing reader, because
there is no existing reader.

| Shape | Cost | Verdict |
|---|---|---|
| **Reserved provenance value(s) in `categorised_by`** | Overloads a column named for the engine's own stages with "a person decided". Introduces a row shape that has never existed: `category_id IS NULL` **and** `categorised_by IS NOT NULL` (a deliberate blank) | ✅ **CHOSEN** |
| New column `decided_by_person INTEGER` on `transactions` | Two columns that can disagree — `categorised_by = 'T3_RULE'` with `decided_by_person = 1` is representable and meaningless. Requires `ALTER TABLE` on the one table SC-014 is about. Every write site must maintain both | ❌ Rejected: a second opinion about the same fact, which is the class of defect 018's mechanical bans exist to prevent |
| New table `person_decisions(transaction_id, category_id)` | A transaction's category would live in two places, and every read — including `PAGE_SQL`, the live index, the count — would need a `LEFT JOIN` and a `COALESCE`. The live-row rule's byte-identical index/query discipline (R6) could not survive it | ❌ Rejected: it makes the category itself ambiguous, and it is the most expensive of the three |

**Chosen: two reserved values, `PERSON` and `PERSON_MEMORY`.** Both are values the engine can never
produce for itself (FR-025, SC-004), both are protected identically from re-categorization
(FR-018–FR-022), and both mean "a person decided". They differ in exactly one place, and the
reason they must is R11.

**Cost of the choice, stated:** `categorised_by`'s name now understates what it holds. The
mitigation is that v8 adds no CHECK constraint (adding one to an existing `STRICT` table requires
a full table rebuild, which is precisely the row-touching migration R4 rules out), so the
vocabulary is documented in one Rust constant block and pinned by a test, not by the schema.

---

## R6 — The `LIVE` discipline, and the second predicate this slice must write the same way

`store.rs:175-186` is the pattern the whole store's correctness rests on:

```rust
macro_rules! live_predicate {
    () => { "is_deleted = 0 AND superseded_by IS NULL" };
}
const LIVE: &str = live_predicate!();
```

with the doc comment: *"It is also, verbatim, the `WHERE` clause of `idx_txn_live_account_date` —
so a read that forgets it does not merely return the wrong rows, it silently loses its index, and
the plan-shape gate goes red."* The macro is expanded into `SCHEMA_V7` (`store.rs:193-198`),
`PAGE_SQL` (`store.rs:200-215`), `load_account_transactions` (`store.rs:1764-1770`) and
`count_live_statement_rows_in` (`store.rs:1335-1345`) — four places, one literal.

**This slice adds two more predicates and they get the same treatment**, because they have the
same failure mode:

```rust
/// "The engine could not place it and the person has not answered." Byte-identical to the
/// WHERE clause of idx_txn_unanswered_account_date.
macro_rules! unanswered_predicate {
    () => { "category_id IS NULL AND categorised_by IS NULL" };
}

/// The rows the engine is still allowed to decide about. NOT the negation of `PERSON`:
/// see R10 for why the obvious spelling is a silent catastrophe.
macro_rules! engine_may_decide {
    () => { "(categorised_by IS NULL OR categorised_by NOT IN ('PERSON', 'PERSON_MEMORY'))" };
}
```

`unanswered_predicate!()` is exact, not approximate. The engine writes `(NULL, NULL)` when it
cannot place a row and never writes a non-null provenance with a null category; a person writes
`PERSON` with either. So `category_id IS NULL AND categorised_by IS NULL` **is** "unanswered",
with no third value to worry about — see R12 for why this matters to FR-037.

---

## R7 — 🚨 The merchant memory cannot be the T2 `merchant_map`, for four independent reasons

The spec's narrative frames the memory as the T2 map — *"the tier whose entire purpose is to hold
what this person has taught the app… nothing has ever put a row in it."* The **requirements**,
however, describe something `merchant_map` cannot do. It is at `store.rs:99-105`:

```sql
CREATE TABLE merchant_map (
    id          INTEGER PRIMARY KEY,
    priority    INTEGER NOT NULL,
    match_type  TEXT NOT NULL CHECK (match_type IN ('Literal', 'Regex')),
    pattern     TEXT NOT NULL,
    category_id TEXT NOT NULL REFERENCES categories(id)
) STRICT;
```

1. **Its matching is substring, not equality.** `prepare_merchants` lower-cases the pattern
   (`categorize.rs:398-419`) and `categorize` tests `normalized.contains(pattern.as_str())`
   (`categorize.rs:522`). FR-027b requires *exactly equal*. A memory for `swiggy` stored here
   would silently also claim `swiggy instamart` and anything else containing the substring — the
   over-broad match the spec has no undo surface for.
2. **It is outranked.** T2 runs after the CC narration rules and after T1 (`categorize.rs:487-518`).
   FR-032 forbids a person's instruction being outrankable by a rule they never wrote. See R9.
3. **It has a `priority` and no uniqueness.** Two rows for the same merchant can coexist, and
   which wins depends on a stable sort by `priority` (`categorize.rs:400-403`) — an ordering
   nobody can see. FR-031 forbids exactly that. Adding a `UNIQUE` to an existing `STRICT` table
   means a full table rebuild, which is the migration R4 rules out.
4. **It is already exported.** `list_merchant_rules()` (`store.rs:1057-1062`) is a public,
   uniffi-exported method. Putting a person's memories in it means every existing caller gets a
   mixture of engine facts and personal ones, and FR-035's "no way to view the person's
   remembered merchants as a set" quietly stops being true.

**Decision: a new table, `merchant_memory`, and `merchant_map` is not touched.** This is the same
distinction the spec draws everywhere else — *a person's decision is a different kind of fact from
an engine verdict* — applied one level up: **a person's memory is a different kind of fact from
the engine's merchant map.** The T2 map keeps its exact current behaviour and its exact current
emptiness.

```sql
CREATE TABLE merchant_memory (
    merchant_portion TEXT PRIMARY KEY,
    category_id      TEXT NOT NULL REFERENCES categories(id)
) STRICT;
```

`PRIMARY KEY` on the portion **is** FR-031: an upsert replaces, so two contradictory memories of
one shop are unrepresentable rather than merely discouraged. There is no `priority`, no
`created_at` and no timestamp of any kind — newest-instruction-wins is achieved by replacement,
so no ordering is needed, and the engine therefore still reads no clock (FR-052, Principle II).

---

## R8 — Where the memory is consulted: **beside** the stack, not inside it, so FR-024 holds literally

FR-024 says this slice must not change the stack's stage order or first-wins behaviour. FR-032
says a person's memory must not be outrankable. Adding a stage to `categorize.rs` satisfies the
second by violating the first.

**It does not have to be a stage.** `categorize::categorize` is a pure function over already-
prepared facts; the *store* is what decides which rows to feed it. So the memory is consulted in
`categorize_account_in`, before the call:

```rust
// in categorize_account_in, per row:
match merchant_portion(&txn.description).and_then(|p| memories.get(&p)) {
    Some(category_id) => write(txn_id, Some(category_id), PERSON_MEMORY),
    None => match crate::categorize::categorize(txn, &catalog, &merchants, &rules, &source_map) {
        Some(decision) => write(txn_id, category_ref_to_id(&decision.category_ref), stage_to_sql(decision.stage)),
        None => write(txn_id, None, None),
    },
}
```

**`core/crates/kaname-core/src/categorize.rs` is not modified by this slice at all.** The stage
order is unchanged, first-wins is unchanged, the set of rows fed to it is unchanged (R3's loader
gains only the person-protection clause), and `Decision`/`Stage` gain no variant. FR-023, FR-024
and FR-032 are all satisfied simultaneously, and the parity fixture
(`fixtures/categorization/basic.json`, read by `tests/parity.rs:873`) cannot move, because the
function it pins is untouched.

The derivation itself lives in a **new** module, `core/crates/kaname-core/src/merchant.rs`, whose
only public items are `pub fn merchant_portion(narration: &str) -> Option<String>` (also a free
`#[uniffi::export]`, so the interface can show the person what will be remembered before they
agree — FR-026a) and the constants it is built from. It imports `dedup::normalize_narration` and
calls it; it does not change it (FR-027c).

---

## R9 — 🚨 FINDING: a person's memory outranks the CC rules and T1, and that is a real behaviour change

FR-032 and the spec's own edge case ("a merchant that matches an existing engine rule at an
earlier tier than the person's memory… the app is lying about having listened") force the
memory to win. R8's placement makes it win **over everything**, including stage 0.

That is not free. Concretely, the CC narration rules classify `4262 BBPS Payment received` as a
bill payment and `10% Swiggy Cashback` as a cashback/refund (`categorize.rs:259-341`). If a
person corrects such a row and a memory forms, future rows of that shape stop being classified by
the CC rules. **This is the intended behaviour** — the person is more authoritative than a
keyword list — but it is a change in what the engine does with rows it currently handles
confidently, and it is recorded rather than discovered.

Two things blunt it in practice, and both are checked:

- R14's derivation returns `None` for `4262 BBPS Payment received`, `CC PAYMENT RECEIVED`,
  `ONLINE TRF - PYMT RECD - THANK YOU` and `PAYMENT RECEIVED BBPS - Ref No: RT0001` — every one
  of them is degenerate, so **no memory can form from a bill-payment row at all** (FR-027d). The
  overlap between "rows the CC stage claims" and "rows a memory can be made from" is much smaller
  than it first looks.
- `10% Swiggy Cashback` **does** yield `swiggy cashback`, so the overlap is not empty. That one is
  a genuine, deliberate override.

Raised as Judgement call §2.

---

## R10 — 🚨 The protection guard has a three-valued-logic trap that stops the engine categorizing anything

The obvious way to write R3's missing guard is to add `AND categorised_by NOT IN ('PERSON',
'PERSON_MEMORY')` to `load_account_transactions`. **Measured, on a table built from `store.rs`'s
own DDL:**

```
-- rows: t1 (NULL provenance, a brand-new imported row), t2 ('T3_RULE'), t3 ('PERSON')
WHERE categorised_by NOT IN ('PERSON','PERSON_MEMORY')                          -> t2
WHERE (categorised_by IS NULL OR categorised_by NOT IN ('PERSON','PERSON_MEMORY')) -> t1, t2
```

`NULL NOT IN (...)` is `NULL`, not `TRUE`, so the naive guard **discards every row with no
provenance** — which is every row `import_statement` has just inserted, because its bulk insert
writes `NULL, NULL` literally (`store.rs:855-870`). The engine would categorize nothing, every
import would land wholly uncategorized, and nothing would error. It would look like
"categorization stopped working" and it would be one missing `IS NULL OR`.

This is why `engine_may_decide!()` in R6 is a single macro with the `IS NULL OR` baked in, and why
the contract requires a test that imports a fresh statement and asserts a **non-zero**
`CategorizeSummary.categorized` after the guard lands.

---

## R11 — 🚨 FR-035d and FR-031a contradict each other, and resolving it costs a second provenance value

- **FR-035d**: the second action changes rows "about which the person has **not** themselves
  decided", and such rows "MUST NOT be counted".
- **FR-035e**: every row the second action changes is recorded "with the **same provenance**" as a
  row corrected by hand.
- **FR-031a**: when the memory is later replaced, the newer second action's count "MUST **include**"
  the rows the earlier second action changed.

Rows changed by the first second action are, by FR-035e, indistinguishable from hand-corrected
rows; by FR-035d they must therefore be excluded; by FR-031a they must be included. **The three
cannot all hold with one provenance value.**

The behaviour that is actually right is not in doubt — it is stated plainly in FR-031a's prose and
in the spec's edge case list. A row a person hand-corrected is *their* answer about that row; a
row that merely carries their memory is *their instruction about the shop*, and when the
instruction changes, the rows carrying it are exactly the ones the new offer must account for.

**Resolution: `PERSON` (hand) and `PERSON_MEMORY` (carrying a memory).** FR-035e is amended: the
same *protection*, not the same *string*. Both are person-decided everywhere it matters
(FR-018–FR-022, FR-025, the `engine_may_decide!()` guard, the unanswered predicate, SC-004); they
diverge only in the second action's affected-set rule, which becomes:

> live ∧ portion equals the memory's ∧ `categorised_by IS NOT 'PERSON'` ∧ not already
> (`PERSON_MEMORY` with this exact `category_id`)

The last clause makes a re-run a genuine no-op and makes "nothing to change" an honest answer
rather than a count of rows that would be rewritten to their existing values.

---

## R12 — 🚨 FR-037 and the Key Entity for "the uncategorized set" define different sets

- **FR-037**: "exactly the live transactions with **no category** — every one, and nothing that
  has one."
- **Key Entities → The uncategorized set**: "the live transactions the engine could not place
  **and the person has not answered**."

A person who deliberately sets a row to *no category* (FR-007, FR-020) has no category. Under
FR-037 that row stays in the worklist forever. Then:

- **SC-010** ("answering every transaction in the uncategorized set takes it to **zero**
  remaining") becomes unachievable — the worklist cannot be cleared by using it as intended.
- **FR-039** ("a transaction that is given a category MUST leave the set") has nothing to say
  about the one answer that gives no category, so the person's own deliberate blank reads as
  unfinished work.
- **FR-042b**'s "reads as finished" state is unreachable for any person who ever used FR-007.

The Key Entity's definition is the one that makes the rest of the spec true. **Amendment: the set
is `LIVE ∧ category_id IS NULL ∧ categorised_by IS NULL`** — R6's `unanswered_predicate!()`. It is
one indexable predicate, it needs no exception list, and it is the same bytes in the index, in the
page query and in the count (FR-043a).

---

## R13 — The query-plan question, answered by measurement

Run against SQLite 3.45.3 on a table built from `store.rs`'s own v1–v7 DDL, with
`idx_txn_live_account_date` created exactly as `SCHEMA_V7` creates it. ⚠️ This is the **system**
`sqlite3`, not the SQLCipher build the engine links; the real assertion belongs in
`history_perf.rs` against the real store, and that is what the contract requires. The shapes below
are what it must find.

**1. The narrowed page already keeps the index at v7, with no new index at all:**

```
EXPLAIN QUERY PLAN <PAGE_SQL + " AND category_id IS NULL AND categorised_by IS NULL">
  -> SEARCH t USING INDEX idx_txn_live_account_date (account_id=? AND date<?)
```

No `SCAN`, no `TEMP B-TREE`. The extra terms are a residual filter on rows the index already
ordered, so **`s1` and `s2`'s criteria are met by the narrowing without v8 doing anything**. This
is the answer to "what does an uncategorized narrowing do to that query plan": *nothing bad*.

**2. `PAGE_SQL`'s own plan is byte-identical before and after the v8 index exists:**

```
-- with idx_txn_unanswered_account_date created:
EXPLAIN QUERY PLAN <PAGE_SQL>
  -> SEARCH t USING INDEX idx_txn_live_account_date (account_id=? AND date<?)
```

The new index's `WHERE` is not implied by `PAGE_SQL`'s `WHERE`, so the planner cannot use it for
the unnarrowed read. **`s1`/`s2` cannot regress.** That is asserted, not assumed: the contract
keeps both tests unchanged and adds new ones beside them.

**3. So why add the index at all? The count.** The entry point's count is a store-wide predicate
with no `account_id`:

```
-- v7 (live index only):   SCAN transactions USING INDEX idx_txn_live_account_date
-- v8 (+ unanswered index): SCAN transactions USING INDEX idx_txn_unanswered_account_date
```

Both say `SCAN`, and that is correct — a store-wide count has nothing to seek on. What changes is
*what is scanned*: at v7 it walks **every live row** every time the front door appears; at v8 it
walks **only the unanswered rows**, so the count gets cheaper exactly as the person works through
the list and reaches near-zero cost at the moment it matters least. The narrowed page also
switches to the tighter index (`SEARCH t USING INDEX idx_txn_unanswered_account_date`), which
matters for an account whose rows are mostly filed — at v7 the planner must walk past every filed
row to find a screenful of unfiled ones.

**⚠️ The trap this creates for the gate.** `s1` asserts no plan step contains `"SCAN"`. The count's
optimal plan **is** a `SCAN` (of a partial index). A new plan-shape test that copies `s1`'s
assertion would be red for the right query. The count's test must assert
`SCAN … USING INDEX idx_txn_unanswered_account_date` — that the *named* index is scanned — and
must not inherit `s1`'s blanket rule. Written into `contracts/engine-categorize.md` §4.

**4. The second action's read is a live-row scan** (`SCAN transactions USING INDEX
idx_txn_live_account_date`), because the merchant portion is derived in Rust and is not a column
(R15). O(live rows) per preview and per apply.

---

## R14 — The derived merchant portion: one rule, fixed in full, run against the repository's own strings

FR-027a fixes four ordered steps; this pins the three things it leaves to the plan.

**Step 2 — the separator set** (documented, closed):
`whitespace`, `-` `/` `\` `|` `*` `:` `;` `,` `#` `_` `%` `(` `)` `[` `]` `"` `'`

Two deliberate exclusions:
- **`@` is not a separator.** A VPA (`swiggy@ybl`) is a single token that is *stable across every
  transaction of that merchant*, which is exactly what a memory needs. Splitting it would produce
  a bare PSP handle as a segment, and the handles that would then need suppressing (`paytm`,
  `ybl`, `okaxis`…) include names that are also merchants — putting a merchant name in the
  stop-list, which FR-027a forbids outright.
- **`.` is not a separator**, so `amazon.in` stays whole rather than yielding `in` as a segment.

**Step 3 — the closed stop-list** (69 words; **zero** merchant names):

```
upi pos neft neftcr neftdr imps rtgs ach nach ecs ecm eft ift bil bbps atm
tfr trf transfer transaction txn chq cheque inf mps ib imb onl online www net mobile
ref refno rrn no dr cr cc card credit debit emi fee fees charge charges gst int
payment payments pymt pmt paid recd received recvd autopay bpay purchase withdrawal cash
thank you to by in ind at on for from via and the of
```

Line 1–2 are channel words, line 3 instrument words, line 4 payment scaffolding, line 5 the
narration function words that survive because `normalize_narration` did not strip the prefix they
belong to. ⚠️ **Amendment**: FR-027a calls this "a documented closed stop-list of channel and
instrument words"; line 5 is neither. It is still closed, still documented, still fixture-tested
and still contains zero merchant names, but the plan widens its stated character to "channel,
instrument and narration-scaffold words" and says so rather than pretending `to` is a channel.

**Step 4 — the maximum count is 2.**

The choice is a risk trade, and the direction is set by the spec: *"a memory formed from too
little of the narration will match merchants the person never meant, and there is no undo surface
in this slice to rescue them."* Fewer segments generalize **more**, so fewer segments are more
dangerous. `1` collapses `blue tokai` to `blue` and `example merchant` to `example`. `3` keeps the
city in (`swiggy bangalore koramangala`), splitting one merchant into a memory per outlet. **2**
is the moderate choice and it is the one that survived the run below.

**Measured against every narration literal in the repository** (fixtures, Rust tests, `DebugSeed`):

| Narration (verbatim, from the repo) | Portion |
|---|---|
| `UPI-SWIGGY-123456` (`fixtures/categorization/basic.json`) | `swiggy` |
| `UPI-SWIGGY-1` (`tests/store_categorization.rs:296`) | `swiggy` |
| `UPI-SWIGGY` (`tests/store_categorization.rs:431`) | `swiggy` |
| `UPI-SWIGGY-RRN1234` (`dedup.rs:270`) | `swiggy` |
| `POS SWIGGY BANGALORE RRN1234` (`tests/store_import.rs:139`) | `swiggy bangalore` |
| `SWIGGY BANGALORE 1234567890123` (`tests/store_import.rs:142`) | `swiggy bangalore` |
| `swiggy   bangalore` / `Swiggy Bangalore` (`fixtures/dedup/cross_source/basic.json`) | `swiggy bangalore` |
| `POS BLUE TOKAI` (`tests/store_dedup.rs:195`) | `blue tokai` |
| `POS AMZN RETAIL BANGALORE 9876543210` (`fixtures/categorization/basic.json`) | `amzn retail` |
| `UPI/512345/ALICE STORE/Payment` (`fixtures/icici/bank_account/basic.json`) | `alice store` |
| `UPI_EXAMPLE STORE IND - Ref No: RT0002 …` (`fixtures/yes/credit_card/basic.json`) | `example store` |
| `UPI-GREENWOOD-SCHOOL` (`tests/store_categorization.rs:339`) | `greenwood school` |
| `10% Swiggy Cashback` (`fixtures/categorization/basic.json`) | `swiggy cashback` |
| `ATM CASH WITHDRAWAL` (`fixtures/icici/bank_account/basic.json`) | **`None`** |
| `CC PAYMENT RECEIVED` (`fixtures/hdfc/credit_card/*.json`) | **`None`** |
| `4262 BBPS Payment received` (`fixtures/icici/credit_card/basic.json`) | **`None`** |
| `ONLINE TRF - PYMT RECD - THANK YOU` (`fixtures/hdfc/credit_card/*.json`) | **`None`** |
| `PAYMENT RECEIVED BBPS - Ref No: RT0001` (`fixtures/yes/credit_card/basic.json`) | **`None`** |
| `TO ECM/600000000001 TFR` (`fixtures/federal/bank_account/classic.json`) | **`None`** |
| `` (empty) | **`None`** |

**SC-008 is demonstrable with strings already in this repository.** The four `UPI-SWIGGY-*` shapes
— which differ only by a per-transaction reference — all collapse to `swiggy`. That is precisely
the criterion: *a memory that can only ever match the row it came from has taught nothing.*

The six `None` results are FR-027d working: every one is a bill-payment or cash-withdrawal row
with no shop in it, and the app will say it has nothing to remember rather than remembering
`thank you`.

---

## R15 — ⚠️ Three limitations of the rule, priced rather than hidden

Found by running it, not by reasoning about it. None is fixable inside this slice's scope, and
each is mitigated by FR-026a's "show the portion before the memory forms".

1. **A 1–3 digit reference token survives.** `NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY`
   (`fixtures/icici/bank_account/basic.json`) → `n123 employer`. The ≥4-digit rule is FR-027a's,
   and `n123` has three. The root cause is upstream: `NARRATION_LEADING_PREFIX` matches `NEFT/`
   but not `NEFT-` (`dedup.rs:44`), so the channel prefix is never stripped and the reference sits
   in the merchant position. **Fixing it means editing `normalize_narration`**, which is what Q2
   answered **B** rather than **D** specifically to avoid — de-duplication depends on that
   function and FR-027c requires zero fixture edits there. So it stands, and the person sees
   `n123 employer` before agreeing.
2. **A merchant whose own name carries four or more digits is discarded.** `MTR1924 LALBAGH` →
   `lalbagh`. This is the dangerous direction (over-broad: it would claim every Lalbagh merchant),
   and it is the price of the ≥4-digit rule catching `rt0001` and `abc0000000001ref`. No such
   narration exists in the repository today; it is recorded because Indian merchant names of this
   shape are common.
3. **The same merchant on two channels does not unify.** `UPI-SWIGGY-123456` → `swiggy` but
   `POS SWIGGY BANGALORE` → `swiggy bangalore`, and FR-027b's exact equality keeps them apart. A
   person who uses one shop through both UPI and card will teach the app twice. Deliberate:
   prefix or fuzzy matching would make "what will this match?" undecidable from what the person
   was shown, which FR-027b rejects in as many words. Likewise `acme corp` ≠ `acme corporation` —
   dedup's fuzzy layer unifies those, a person's memory does not, and the two are different tools.

---

## R16 — 🚨 The fixtures cannot exercise the rule at realistic breadth, and the honest answer is new synthetic ones

`grep -rniE "ybl|okaxis|oksbi|okhdfcbank|paytm|@apl|@axl"` across `fixtures/`,
`core/crates/kaname-core/`, and `ios/Sources/DebugSeed/` returns **zero matches**. There is no
real-world VPA shape anywhere in this repository. The only `@` in any narration is the placeholder
`payer@example` (`fixtures/federal/bank_account/classic.json:13`).

`ios/Sources/DebugSeed/` is worse for this purpose: every description is a placeholder
(`SYNTHETIC MERCHANT 01`, `SeedScenarios.swift:168-173`), with no UPI, POS, RRN or reference-number
shape at all. A seed scenario built from those cannot demonstrate SC-008, because every
`SYNTHETIC MERCHANT 01` is already byte-identical to every other one — the memory would appear to
generalize while proving nothing.

**What R14's table does establish** is that the rule collapses a per-transaction reference
correctly, using four narrations that already exist. **What it does not establish** is behaviour
against the messy production diversity of Indian UPI narrations — stacked channel codes, merchant
category codes, VPA handles, mixed-case merchant noise.

**Decision.** A new fixture, `fixtures/categorization/merchant_portion.json`, is authored for this
slice: a flat list of `{narration, expected_portion_or_null}` pairs, synthetic, covering every
branch of the rule (each stop-list line, each discard criterion, the max-count boundary, the three
R15 limitations **pinned as they actually behave**, and the degenerate cases). It is a
narration-shape fixture, not a statement fixture, so it adds no bank, no issuer and no parser
surface. New `DebugSeed` scenarios use UPI-shaped synthetic narrations
(`UPI-SYNTHETICCAFE-<n>`) so that the seeded history can exercise the memory at all.

⚠️ Stated plainly, because SC-029 asks for reproducibility "on every machine": the rule's
determinism is provable and is proved; its *adequacy* against real Indian narrations is **not
provable in this repository**, because this repository has correctly never contained a real
statement. That limit is a consequence of Principle I and is accepted, not solved.

---

## R17 — The stale-set problem: a count is not enough, and the ids are the honest token

FR-035f forbids applying a stale set; FR-035h requires all-or-nothing. A count alone cannot
detect a set that changed while staying the same size (one row superseded by an import, another
row of the same merchant arriving in it — a plausible pair, since both happen in one
`import_statement` call).

**Decision: `preview` returns the affected transaction ids; `apply` takes them back and requires
set equality with a freshly recomputed set, inside the same transaction that does the writing.**

- It cannot drift, because the comparison is against the thing that is about to be written, not
  against a remembered number.
- It needs no hash, no digest and therefore no new dependency and no question about whether the
  hash is stable across platforms.
- **It is not a selection UI.** The ids are the engine's own output round-tripped, and because
  `apply` demands *equality* rather than *subset*, a caller that trims the list is refused. This
  is where FR-035b's "no choice of transactions" is **enforced in the engine** rather than
  promised by the interface — which is what FR-021's "property of the engine, not of the
  interface" asks for and what makes SC-028 provable against a hostile caller.
- All-or-nothing is the existing transaction mechanism (R4), not new machinery.

A mismatch returns a new `StoreError::StaleSet { expected: u32, found: u32 }` variant and writes
zero rows. `StoreError` already derives `uniffi::Error` + `thiserror::Error` (`store.rs:220-236`)
and its variants carry only strings/scalars, never row data — the new variant keeps that rule.

---

## R18 — 🚨 `detect_transfers` can still erase a person's decision, and FR-075 says not to touch it

`detect_transfers`'s update is guarded by `transfer_group_id IS NULL` (`store.rs:1160-1166`) —
**not** by provenance. A row a person corrected, which is not yet part of a transfer group, is
eligible. If a later run pairs it, the person's category is overwritten with `SELF_TRANSFER` or
`CREDIT_CARD_BILL_PAYMENT` and their provenance with `TRANSFER_DETECTOR`.

FR-019/FR-021 require the protection to hold "for **any** caller of the re-categorization path".
FR-075 says this slice must not change transfer detection.

**Reading: FR-075 bans changing what transfer detection *decides*; it does not ban stopping it
from overwriting a person.** Adding `AND <engine_may_decide!()>` to that one `UPDATE` changes no
pairing, no threshold, no similarity computation and no summary count — it changes only which rows
the already-computed answer is allowed to land on. Leaving it out would ship a documented hole in
FR-021.

**It is unreachable in the shipping app today** — `import-path-audit.sh`'s ninth scan bans the app
from calling `detectTransfers` at all, and 018's R18 confirmed no Swift file does. So this is a
Rust-only guarantee with a Rust-only test, and it costs the app nothing. Raised as Judgement call
§3.

---

## R19 — What 018's two open findings mean here: one is touched, one is not

- **R17 (cross-account dedup non-determinism)** — fixed in 018 PR A by the `accounts.rowid`
  tie-break and the bank↔card source-kind guard; the **blunt guard** remains an open finding for
  the slice that owns dedup. **This slice does not touch it.** It is load-bearing in one place
  only: a seed scenario that puts the same merchant in two accounts (FR-066) must not
  accidentally trip cross-source dedup, or the blast-radius scenario silently loses a row. The
  scenario therefore varies dates and amounts across accounts, and its declared row count is the
  thing that would notice.
- **R18 (`detectTransfers()` called from no Swift file)** — still true. **This slice does not wire
  it up**, and adds no claim anywhere that transfers are detected (the ninth scan's prose-claim
  regex would catch one). It only closes the hole in R18 above.

Neither finding is resolved here, and neither is made worse. 018's `05` (unreproduced render
hang, `wontfix` with reopen conditions) is relevant only as a watch item: this slice pushes a new
view over a populated, possibly deeply-scrolled list, which is close to the untested combination
that ticket describes. 018's `06` (three device timings, needs a phone) is untouched and remains
the only thing between 018 and its SC-012.

---

## R20 — What 019's four findings cost this slice, including one requirement they contradict

- **`019/01`** — three `Contrast failed` verdicts naming no element, on the bottom filter bar;
  `.contrast` is excluded from every in-test audit. Any bottom-anchored chrome this slice adds
  inherits the same risk. The fix precedents apply directly to a new detail surface:
  `.foregroundStyle(Color.primary)` **not** `.primary` (the hierarchical style resolved to a
  no-op), and an opaque `Color(.systemBackground)` **not** a material (FR-059 bans materials, not
  opacity).
- **`019/02`** — `EmptyKind.nothingToShowAnywhere` and `.accountNothingToShow` are structurally
  unreachable by any seed. ⚠️ That ticket **names a category feature as the thing that could make
  them reachable** — by adding a delete path. **This slice adds none**, so both stay unreachable
  and this slice does not close `019/02`. Recorded so the next reader does not assume it did.
- **`019/03`** — at XXXL the populated list fires `.textClipped` ×5 and `.dynamicType` ×4, all
  unattributable, so both types are excluded at XXXL. A category picker is a screen of long text
  at XXXL; it will meet the same wall. The precedent is to exclude the audit **type** and carry
  the real defect on **geometry**, never to weaken the design.
- **`019/04`** — a wall clock in a UI test measures the machine. The spec already declines timing
  criteria for this reason. No new timing assertion is added.

**⚠️ FR-065 cannot be satisfied as written, and this is a spec amendment, not an implementation
detail.** FR-065 requires every new surface audited "with **Increase Contrast** enabled". Increase
Contrast **cannot be set from XCUITest**; the only mechanism in this repository is
`make a11y-sweep`, which toggles it with `xcrun simctl ui "iPhone 16" increase_contrast enabled`
around a `-only-testing:KanameUITests` run (Makefile). And the `.contrast` audit type is excluded
from every audit because of `019/01`. So the honest statement is: the new surfaces are audited at
default and XXXL, in Light and Dark, inside `make ios-test`; and they are audited **again** under
Increase Contrast by `make a11y-sweep`, a separate target that is not part of `make ios-test`,
with `.contrast` still excluded. SC-016's "zero findings" is therefore about the audit types that
actually run. Written into the contract so the gate cannot quietly claim more than it does.

---

## R21 — Seed scenarios: three new ones, and the traps each must dodge

FR-066 names three shapes. `SeedScenario.declared` is `[.empty, .small, .deep, .barren]`
(`SeedScenarios.swift:116`); this slice appends and invents no second mechanism.

| Scenario | Shape | The trap it must dodge |
|---|---|---|
| `unfiled` | One ledger, ~12 rows, a **declared** number of which no rule can place, plus some the engine files confidently | The engine, not the seed, decides what is uncategorized. A row is only unfiled if `categorize` returns `None` for it, so the declared count in `SeedExpectations` must be **asserted against the engine's own answer**, not asserted from the fixture author's belief. `SYNTHETIC MERCHANT 01`-style names are safe here precisely because no rule matches them |
| `repeated` | One merchant, UPI-shaped with a **varying** reference (`UPI-SYNTHETICCAFE-100001`, `-100002`, …), across **two statements** in one account | ⚠️ Same date + same amount + same normalized narration across two statements is a **canonical dedup match** — the second copy would be superseded and the scenario would silently lose the rows SC-008 needs. Vary the amounts |
| `crossing` | The same merchant in **two accounts** — one bank ledger, one credit card — for the blast radius (FR-035c) and SC-027 | ⚠️ Two credit cards never de-duplicate (`AGENTS.md`), which is the opposite of the risk here: a **ledger + card** pair is exactly what cross-source dedup *does* compare (018 R17). Vary dates and amounts so no pair is canonical, or the count the second action shows is wrong before anyone tests it |

All three: ≥1 statement so `EmptyKind.nothingImported` is not reached; amounts under ₹1,00,000;
`en_IN` pinned by `SeededLaunch.localeArguments`; reset in `tearDown` with `empty`. All three land
in `SeedScenarios.swift` inside its existing `#if DEBUG`, and are covered by the existing
denylist (`SeedScenario` is already a denied symbol in `release-absence-audit.sh`) — so FR-067 and
SC-019 need no new gate, only a re-run.

---

## R22 — Where the new code goes, and the four scans that should be widened to follow it

`ios/Sources/Import/ImportService.swift` is at **398** lines; SwiftLint's `file_length` is not
overridden in `ios/.swiftlint.yml`, so the default 400 warning applies and `make lint`'s
`--strict` makes it fatal. `Project.swift`'s own comment already records this. **Zero lines go
there** (FR-073, SC-023).

New platform code goes in **`ios/Sources/Categorize/`**. The app target globs `sources:
["Sources/**"]`, so no manifest edit is needed for the app or for `KanameTests`. ⚠️ **But
`KanameUITests` does not glob `Sources/**`** — it hand-lists `UITests/**` plus two explicit
`DebugSeed` files. If a UI test needs to share a declaration with the app (the way
`SeedExpectations.swift` is shared), `Project.swift` **must** be edited and `make ios-gen` re-run.
This slice's new scenarios go in the already-listed `SeedScenarios.swift`/`SeedExpectations.swift`,
so the edit is expected to be unnecessary — but the trap is real and is the reason a new file
compiled by nothing reports a passing suite.

**Four of `import-path-audit.sh`'s scans are scoped to `ios/Sources/Transactions/`** — the
second-opinion ban (5), filter-persistence (6), aggregates (7) and `.tint` (8). New code in
`ios/Sources/Categorize/` would sit outside all four. FR-076 and FR-078 apply to it just as
strongly: a Swift-side count of uncategorized rows is exactly what FR-043 forbids, and it would be
in a directory no scan watches.

**Recommendation: widen those four scans' directory scope to include `ios/Sources/Categorize/`.**
This *strengthens* the audit and touches no denylist, so FR-056/SC-022 ("zero scans disabled,
narrowed or excepted") is satisfied — widening is the opposite of narrowing. Scans 1, 2, 3, 9 and
10 already cover all of `ios/Sources/` and need nothing.

---

## R23 — What cannot be determined on this machine

Recorded here so the plan does not imply otherwise.

- **Anything needing a physical device.** 018's `06` gates — tap-to-readable under a second,
  10,000-row versus 200-row indistinguishability, filter apply/clear under 300 ms — have never
  been measured on hardware, and this slice adds two more surfaces reachable by a tap without
  closing them. 018's SC-012 stays unsigned; this slice must not claim to have measured anything
  from the person's side of the glass.
- **Whether `018/05`'s render hang recurs** on a detail push over a deep list, on a device, in
  Release. The ticket's own reopen conditions are the test, and they need a phone.
- **The real query plans.** R13 was measured against system SQLite 3.45.3, not the SQLCipher build
  the engine links. The shapes are expected to match and the contract requires them to be asserted
  in `history_perf.rs` against the real store — until that runs, R13 is a prediction with evidence,
  not a measurement of the shipping engine.
- **Whether the derivation rule is adequate for real Indian narrations** (R16). Unprovable here by
  design.
- **Increase Contrast inside `make ios-test`** (R20). Not a machine limit — an XCUITest limit.
