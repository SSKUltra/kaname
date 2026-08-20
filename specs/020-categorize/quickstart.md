# Quickstart: Categorize

**Feature**: 020-categorize | **Branch**: `020-categorize`
**Read first**: [`plan.md`](./plan.md) · [`research.md`](./research.md) · [`data-model.md`](./data-model.md) · [`contracts/`](./contracts/)

---

## The problem, in one sentence

`Store` has no method that changes one transaction's category, so nobody can disagree with the
engine — and the moment you add one, `categorize_account_in`'s unconditional
`UPDATE transactions SET category_id = ?2, categorised_by = ?3` will erase their answer to
**`NULL, NULL`** on the next import, silently.

## The fix, in one paragraph

Reserve two `categorised_by` values the engine can never produce (`PERSON`, `PERSON_MEMORY`), add
one predicate macro that keeps the engine out of those rows, and add one new table
(`merchant_memory`) so what a person teaches the app is a different kind of fact from what the
engine guessed. Schema goes **v7 → v8** and v8 is `CREATE TABLE` + `CREATE INDEX` only — it reads
no existing row and writes none. Then give the person a surface to correct a row, a plain-language
offer to remember the merchant, one bounded second action, and a worklist of everything still
unanswered whose count comes from SQL.

---

## Build order

The FFI **changes** in this slice, so — unlike 019 — the engine must be rebuilt before any Swift
compiles.

```bash
make core-xcframework   # 1. rebuild the engine. NOT optional.
make ios-gen            # 2. regenerate the Xcode project against the new xcframework
```

⚠️ **A bare `tuist generate` is a documented trap** (`AGENTS.md:88-92`). Tuist resolves the
xcframework path **at generation time**, so skipping step 1 gives you `cannot find 'X' in scope` —
a Swift error that is not a Swift problem, in a file you did not write, about a symbol you did add.

⚠️ **`sources: ["Sources/**"]` is resolved at generation time too.** A new file added without
`make ios-gen` is compiled by nothing, and a test suite that never ran **reports success**. This
bit 019 twice. Every time you add a file to `ios/Sources/Categorize/`, run `make ios-gen`.

⚠️ **`ios/Sources/Categorize/` is new.** If it does not appear in the generated project, the glob
did not pick it up — check step 2 before you debug anything else.

⚠️ **`KanameUITests` does not glob `Sources/**`.** It hand-lists `UITests/**` plus
`Sources/DebugSeed/SeedScenarios.swift` and `SeedExpectations.swift`. If a UI test needs to share
a declaration with the app, that is a `Project.swift` edit **and** a `make ios-gen`.

---

## The verification gate

```bash
make lint            # cargo fmt --check, clippy -D warnings, swiftlint --strict, swift-format
make core-test       # cargo test
make ios-test        # unit + UI, simulator
make import-audit    # ten scans — four widened in scope by this slice
make release-audit   # scripts/release-absence-audit.sh
make a11y-sweep      # Increase Contrast lives here, NOT in make ios-test
```

⚠️ **Never run `make core-test` and `make ios-test` concurrently.**
`core/crates/kaname-core/tests/history_perf.rs::s5` is wall-clock and flaky under CPU contention.
A red `s5` from a parallel run costs an hour of looking in the wrong place.

⚠️ `make release-audit` runs **`scripts/release-absence-audit.sh`** — there is no
`scripts/release-audit.sh`. Its denylist already includes `SeedScenario`, so the three new
scenarios need no new gate entry.

---

## Smoke test

```bash
# Engine, without a simulator:
cargo test -p kaname-core store_correction   # the correction survives an import
cargo test -p kaname-core merchant_portion   # the derivation matches its fixture
cargo test -p kaname-core history_perf       # plan shape, including s1/s2 still green

# Platform:
make core-xcframework && make ios-gen && make ios-test
```

Then by hand, once: import a statement, tap a row, change its category, decline the memory offer,
**re-import the same statement**, and confirm the category is still yours. That last step is the
whole slice.

---

## How to watch each new gate fail

A gate that has only ever been green proves nothing (FR-068, SC-017). Each of these is a
deliberate break, watched red, then reverted.

⚠️ **First, the revert discipline.** `git checkout -- ios/Sources` reverts to `HEAD`, so while
your fix is uncommitted it takes the fix with it. Either:

```bash
git add -A && git commit -m "wip: fix in place"   # commit FIRST, then break
# …break…  then:  git checkout -- .
```

or:

```bash
cp -R ios/Sources /tmp/sources-backup             # copy aside, then break
# …break…  then:  rm -rf ios/Sources && cp -R /tmp/sources-backup ios/Sources && make ios-gen
```

Never break first and hope.

| Gate | The deliberate break | What must go red |
|---|---|---|
| Correction survives an import | Remove `AND {ENGINE_MAY_DECIDE}` from `load_account_transactions` | `store_correction::C1` |
| 🚨 The `NULL NOT IN` trap | Replace `ENGINE_MAY_DECIDE` with the naive `categorised_by NOT IN ('PERSON','PERSON_MEMORY')` | `store_correction::C2` — and **C1 stays green**, which is exactly why C2 exists as its own named test |
| Transfer detection can't erase a person | Remove the guard from `detect_transfers`'s `UPDATE` | `store_transfer::T1` |
| Memory outranks the stack | Consult the memory *after* `categorize::categorize` instead of before | `merchant_memory::M2` |
| One memory per merchant | Drop the `PRIMARY KEY` from `merchant_memory` | `merchant_memory::M3` |
| Second action can't be a bulk edit | Change `apply_memory`'s set-equality check to a subset check | `merchant_memory::M7` |
| Stale set refused | Remove the recompute-and-compare inside the transaction | `merchant_memory::M6` |
| Derivation generalizes | Change the max segment count from 2 to 3 | `merchant_portion::P2` — the four `UPDATE-SWIGGY-*` shapes stop collapsing |
| The narrowing is the engine's | Filter the page in `TransactionListViewModel` instead of passing `uncategorizedOnly` | `import-audit` scan 5 or 6 — **only after the scans are widened**, which is the point |
| The count is the engine's | Sum `AccountSummary` counts in Swift | `import-audit` scan 7 |
| The plan didn't regress | Drop `idx_txn_unanswered_account_date` | `history_perf::Q3` — and `s1`/`s2` **stay green**, which proves v8 didn't touch `PAGE_SQL` |
| A new file is actually compiled | Add a failing test to a new file, run without `make ios-gen` | It reports **success**. That is the trap. Then run `make ios-gen` and watch it fail properly. |

---

## Gotchas found during planning

1. 🚨 **`NULL NOT IN (…)` is `NULL`, not `TRUE`.** The obvious guard drops every row
   `import_statement` just inserted (its bulk insert writes `NULL, NULL` literally,
   `store.rs:855-870`), so every import lands wholly uncategorized and nothing errors. Keep the
   `IS NULL OR` (research R10).
2. ⚠️ **Do not copy `s1`'s "no step contains SCAN" for the count.** The count's *optimal* plan is a
   `SCAN` of a partial index containing only the rows being counted. Assert the index **name**
   instead. A copied `s1` is red for the correct query and the tempting fix is to weaken `s1`.
3. ⚠️ **There is no `core/src/ffi.rs`.** `Store` is a `uniffi::Object` and all its methods are
   exported from one `#[uniffi::export] impl Store` block in `store.rs:571`. New store methods go
   in `store.rs`; only the free `merchant_portion` touches `ffi.rs`.
4. ⚠️ **`ImportService.swift` is at 398 of 400 lines.** Nothing in this slice may add a line.
5. ⚠️ **`categorize.rs` and `dedup.rs` must not be modified.** That is what keeps
   `fixtures/categorization/basic.json` and the dedup fixtures unedited. If you find yourself
   editing `normalize_narration` to fix a derivation case, stop — that is exactly what Q2's answer
   **B** refused, and research R15 prices the three limitations that decision leaves in place.
6. ⚠️ **`crossing` must dodge dedup.** Cross-source dedup compares a **ledger against a card**, and
   that is precisely the pair `crossing` needs. Make the rows differ in amount or date, or one
   gets eaten and the blast radius is wrong before anyone tests it.
7. ⚠️ **Bare `KANAME_SEED_SCENARIO`.** The `TEST_RUNNER_` prefix is for app-hosted unit tests and
   is silently never delivered to a UI test.
8. ⚠️ **A seeded store outlives the suite that wrote it.** Reset with the `empty` scenario or the
   next suite inherits someone else's rows.
9. ⚠️ **A `List` renders a screenful, not a list.** Never assert a total by counting cells. A row's
   sentence is a `StaticText` **inside** the cell; a date heading is a cell too.
10. ⚠️ **A label cannot demonstrate a truncation** (XCUITest reports the string, not the glyphs)
    and **a wall clock in a UI test measures the machine** (`019/04`). Neither belongs in a gate.
11. ⚠️ **Increase Contrast is `make a11y-sweep`, not `make ios-test`.** It cannot be set from
    XCUITest. Spec amendment §5.
12. ⚠️ **Pin `en_IN`, keep amounts under ₹1,00,000.**

---

## What cannot be verified on this machine

Recorded honestly rather than glossed (research R23):

- **Three device timings** — `.scratch/018-transaction-list/issues/06` is still
  `ready-for-human` and needs a physical phone. It remains the only thing between 018 and SC-012,
  and this slice adds two more tap-reachable surfaces without measuring any of them.
- **`018/05`'s render hang** is `wontfix`/unreproduced with reopen conditions. This slice pushes a
  detail view over a populated, deeply-scrolled list — close to the untested combination. If it
  reproduces, reopen; do not re-diagnose from scratch.
- **The real SQLCipher query plans.** Research R13's plans were measured with system SQLite 3.45.3.
  They are expected to match; `history_perf::Q1`–`Q3` assert against the real store, which is what
  actually settles it.
- 🚨 **Whether the derivation rule is adequate for real Indian bank narrations.** This repository
  has correctly never contained a real statement, and there is not one real VPA or UPI-handle shape
  anywhere in it. The fixture proves the rule is deterministic, fixture-testable and stable across
  the shapes we have. It does **not** prove it is right. That limit is a direct consequence of
  Principle I and is accepted rather than worked around.
- **Increase Contrast inside `make ios-test`.** Not possible; covered by `make a11y-sweep`.

---

## Definition of done

- [ ] Schema v8 applied forward-only; a v7 store with rows in every provenance state migrates with
      every field byte-identical (SC-014, SC-015).
- [ ] A correction survives a re-import, a transfer-detection run, and any other engine path
      (SC-004) — and the **C2** trap test is green with a **non-zero** categorized count.
- [ ] `categorize.rs`, `dedup.rs` and `merchant_map` are untouched; `fixtures/categorization/basic.json`
      and the dedup fixtures have **zero** expectation edits.
- [ ] The four `UPI-SWIGGY-*` shapes collapse to one memory (SC-008).
- [ ] The second action states a count and account names, refuses a trimmed id list and refuses a
      stale set (SC-026, SC-027, SC-028); no multi-select ships.
- [ ] The uncategorized count comes from SQL; `import-audit`'s widened scans watch
      `ios/Sources/Categorize/` and all ten stay green and unweakened (SC-020, SC-022).
- [ ] `s1`/`s2` unedited and green; the count's plan names `idx_txn_unanswered_account_date`.
- [ ] Every new surface audited at default and XXXL, Light and Dark, inside `make ios-test`; and
      under `make a11y-sweep` for Increase Contrast.
- [ ] Every gate in the table above has been **watched failing** at least once.
- [ ] `make lint`, `make core-test`, `make ios-test`, `make import-audit`, `make release-audit`
      green — core and iOS run **sequentially**.
- [ ] `.scratch/HANDOFF.md` and `AGENTS.md` updated; every finding filed with its status.
