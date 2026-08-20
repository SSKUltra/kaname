# A person's decision is a different kind of fact, and the engine is kept out of it

**Status**: accepted (020-categorize) · **Schema**: v7 → v8 · **Supersedes nothing**

## Context

Before 020, `Store` had no method that changed one transaction's category. Nobody could
disagree with the engine. The moment such a method was added, `categorize_account_in`'s
unconditional `UPDATE transactions SET category_id = ?2, categorised_by = ?3` would erase the
answer on the next import — silently, to `NULL, NULL`.

The obvious fix is to make the categorization stack's T2 merchant map do the remembering. It
cannot: T2 matches by `contains` and is **outranked by the CC rules**, so a person's own
instruction would be one more rule to be beaten. Worse, it is already exported as
`list_merchant_rules()`, so a person's private correction would arrive in a surface built for
engine facts.

## Decision

**A person's decision is a different kind of fact from an engine verdict, and is stored,
guarded and named as one.**

1. **Two reserved provenance values the engine can never produce** — `PERSON` (by hand) and
   `PERSON_MEMORY` (carrying a memory).
2. **One macro states the rule once**:
   ```rust
   engine_may_decide!() = "(categorised_by IS NULL OR categorised_by NOT IN ('PERSON', 'PERSON_MEMORY'))"
   ```
   applied to `load_account_transactions` **and** to `detect_transfers`' `UPDATE`.
3. **A new table, not T2.** `merchant_memory(merchant_portion PRIMARY KEY, category_id)` is
   consulted by the store **beside** the stack and **before** it, so `categorize.rs` and
   `dedup::normalize_narration` are not modified and their fixtures cannot move.
4. **The second action is all-or-nothing.** `apply_memory` recomputes the affected set inside
   its own writing transaction and refuses **any** difference.

---

## 🚨 The two findings, and the tests that hold them

> **Read these before the code.** Both are shapes that look correct, pass the obvious test, and
> fail silently in production.

### (a) `NULL NOT IN (…)` is `NULL`, not `TRUE` — and `NULL` is not `TRUE`

The natural spelling of the guard is:

```sql
categorised_by NOT IN ('PERSON', 'PERSON_MEMORY')     -- ❌ WRONG
```

`Store::import_statement`'s bulk insert writes `NULL, NULL` **literally**, so for every
freshly imported row the expression evaluates to `NULL`, the row is excluded, and **every
import lands wholly uncategorized with no error anywhere**. The `IS NULL OR` arm is
load-bearing and must never be "simplified".

**Regression test: `store_correction::C2`** (`a_fresh_import_still_categorizes_what_the_stack
_can_answer`) — after a fresh import into an empty store, the count of rows with a non-null
`category_id` is **greater than zero**.

⚠️ **C1 passing proves nothing here.** C1 (the correction survives a re-import) stays **green**
against the broken spelling — it was watched doing exactly that (020 T026). C2 exists as a
separate named test for that reason alone, and merging it into C1 would delete the guarantee
while leaving a green suite.

### (b) `detect_transfers` could erase a person's decision, on a path no UI can reach

Its `UPDATE` was guarded on `transfer_group_id IS NULL` **only**, so transfer detection would
overwrite a hand-chosen category with `'TRANSFER_DETECTOR'`.

**Regression test: `store_transfer::T1`** (`detection_does_not_overwrite_a_category_a_person
_chose`). Against the unguarded code it reads `left: Some("CREDIT_CARD_BILL_PAYMENT")`,
`right: Some("SHOPPING")`.

⚠️ **It is Rust-only, and must stay Rust-only.** `detectTransfers` is unreachable from the
shipping app — `scripts/import-path-audit.sh` scan 9 bans it in Swift, and 018's R18 (nothing
calls it) is still open. No UI test can ever reach this path. The guarantee belongs to the
engine, not to the current absence of a caller, which is why it was fixed anyway.

---

## The surface this slice changed (T181)

Everything 020 added to the engine's contract, in one place.

**Schema — `PRAGMA user_version` 7 → 8**, forward-only:

| Change | Statement |
|---|---|
| New table | `CREATE TABLE merchant_memory (merchant_portion TEXT PRIMARY KEY, category_id TEXT NOT NULL REFERENCES categories(id)) STRICT` |
| New index | `CREATE INDEX idx_txn_unanswered_account_date ON transactions(account_id, date DESC) WHERE …` (`LIVE ∧ UNANSWERED`) |

⚠️ **v8 is `CREATE TABLE` + `CREATE INDEX` only.** No `ALTER TABLE`, no column added to
`transactions`, no `CHECK` added, and **no existing row read or written** — which is why "every
existing transaction keeps its category, amount, date, description, account and provenance" is
true by construction rather than by testing hard enough.

⚠️ Both use plain `CREATE`, **not `IF NOT EXISTS`**: a second open that re-ran the migration
must *fail*, not silently succeed, and `reopening_a_v8_store_is_a_no_op` depends on it.

**FFI — six surfaces**, all generated from `#[uniffi::export] impl Store` in `store.rs` except
the free function:

| Surface | Where | Note |
|---|---|---|
| `set_transaction_category` | `store.rs` | writes `PERSON`; forms the memory in the **same** transaction |
| `merchant_portion` | `ffi.rs` | the only one in `ffi.rs`; owned-`String` wrapper over the pure `merchant::merchant_portion` |
| `preview_memory_application` | `store.rs` | states the blast radius before anything is written |
| `apply_memory_application` (`apply_memory`) | `store.rs` | ⚠️ the contract and the shipped name are `apply_memory`; `tasks.md` calls it `apply_memory_application` |
| `uncategorized_count` | `store.rs` | the count is SQL's, never a Swift sum |
| `HistoryQuery.uncategorized_only` | `model.rs` | an **input**, so it carries a default of `false` — every existing caller keeps its behaviour |

🚨 **A `uniffi::Record` that gains a field breaks every Swift memberwise construction of it.**
`HistoryRow.category_id` broke ten call sites across seven files. `#[uniffi(default = None)]`
would have kept the Swift tree untouched and was **rejected**: a test double that can silently
omit a fact the engine always populates is precisely the quiet failure this repository keeps
finding. Expect the same the next time an output record grows a field — and note the asymmetry
with `HistoryQuery` above, which *does* carry a default because it is an input.

## Build consequence

The FFI changed, so — unlike 019 — the engine must be rebuilt before any Swift compiles:

```bash
. "$HOME/.cargo/env"     # a non-interactive shell has no cargo on PATH
make core-xcframework    # 1. NOT optional
make ios-gen             # 2. resolves the xcframework path AT GENERATION TIME
```

Skipping step 1 gives `cannot find 'X' in scope` — a Swift error that is not a Swift problem.
And `sources: ["Sources/**"]` is resolved at generation time too, so **a new file added without
`make ios-gen` is compiled by nothing, and a suite that never ran reports success.**

## Consequences

- A person's correction survives re-imports, transfer detection and every other engine path.
- The categorization fixtures (`fixtures/categorization/basic.json`, the dedup fixtures) are
  **unedited**, because the memory sits beside the stack rather than inside it.
- The engine's own guarantees are now stated in SQL predicates spelled exactly once each
  (`live_predicate!`, `unanswered_predicate!`, `engine_may_decide!`), and the v8 index's `WHERE`
  is built from the same macros — so a read that forgets the rule loses its index and a
  plan-shape test goes red.
- 🚨 The derivation rule behind `merchant_memory` is proven against **synthetic shapes only**.
  See `specs/020-categorize/quickstart.md` § *what cannot be verified on this machine* (T179).
