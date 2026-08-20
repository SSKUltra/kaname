# Implementation Plan: Categorize

**Branch**: `020-categorize` | **Date**: 2026-08-18 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/020-categorize/spec.md` — FR-001–FR-078,
SC-001–SC-036, seven user stories, three clarifications answered (Q1→D, Q2→B, Q3→C). Its
§ *Decisions taken without asking*, § *Assumptions* and § *Out of Scope* are settled constraints
and are not re-opened here. `.specify/memory/constitution.md` v2.0.0 wins over this document.

## Summary

The categorization engine has been finished for five slices and nobody can disagree with it.
`Store` has no method that changes one transaction's category — the full public surface is
enumerated in [`research.md`](./research.md) R2 and not one of its twenty-three methods takes a
transaction id and a category. Every category any person has ever seen was written by the engine
during an import, about a merchant it had never been told anything about. This slice adds the
write path, protects it from the thing that would erase it, and gives a person a way to work
through the rows the engine could not place.

**The technical shape, in one paragraph.** Four Rust changes and one new Swift directory. (1) A
**reserved provenance** — `categorised_by` becomes the one place that records *who decided*, with
two values the engine can never produce, `PERSON` and `PERSON_MEMORY`. (2) A **new table**,
`merchant_memory`, keyed by the derived merchant portion, so two contradictory memories of one
shop are unrepresentable rather than merely discouraged. (3) A **guard** on
`load_account_transactions` so the engine never decides about a row a person decided about, and
the same guard on `detect_transfers`'s update. (4) A **new pure module**, `merchant.rs`, holding
the derivation rule — additive to `dedup::normalize_narration`, which is not touched, and
consulted by the *store* rather than by the stack, so `categorize.rs` is not modified by this
slice at all. Schema goes **v7 → v8** and v8 is `CREATE TABLE` + `CREATE INDEX` only: it reads no
existing row and writes none, which makes FR-047 and SC-014 true by construction rather than by
testing hard enough. Because `Store` is a `uniffi::Object` whose methods are exported from
`store.rs`, the FFI surface changes, so **`make core-xcframework` then `make ios-gen`** is
mandatory — `AGENTS.md:88-92`'s trap, where a stale xcframework yields "cannot find `X` in scope",
a Swift error that is not a Swift problem.

**The defect this slice exists to not ship.** `categorize_account_in` (`store.rs:1278-1327`) runs
`UPDATE transactions SET category_id = ?2, categorised_by = ?3 WHERE id = ?1` against every live
non-transfer row of an account, unconditionally, and writes **`NULL, NULL`** when the stack has
no answer. `import_statement` calls it every time (`store.rs:825`). So a correction stored as an
ordinary engine verdict is not merely overwritten by a better answer — it is **erased to nothing**
whenever the stack has no rule for that merchant, which is the common case for exactly the
merchants a person bothers to correct. Silently.

**The trap inside the fix.** The obvious guard, `AND categorised_by NOT IN ('PERSON',
'PERSON_MEMORY')`, is a three-valued-logic bomb: `NULL NOT IN (…)` is `NULL`, not `TRUE`, so it
discards **every row `import_statement` has just inserted** — its bulk insert writes `NULL, NULL`
literally in the SQL text (`store.rs:855-870`). The engine would categorize nothing, every import
would land wholly uncategorized, and nothing would error. Measured, both spellings, in
[`research.md`](./research.md) R10. The predicate is therefore a single macro with the `IS NULL
OR` baked in, spelled once, exactly as `LIVE` is.

**The query-plan question, answered by measurement rather than by assertion** (R13). The
uncategorized narrowing keeps `idx_txn_live_account_date` at v7 with no new index — `SEARCH t
USING INDEX idx_txn_live_account_date`, no `SCAN`, no `TEMP B-TREE` — so 018's `s1`/`s2` criteria
are met by the narrowing for free. `PAGE_SQL`'s own plan is byte-identical before and after the
v8 index exists, because the new index's `WHERE` is not implied by `PAGE_SQL`'s, so `s1`/`s2`
**cannot** regress. The v8 index earns its place on the **count**: at v7 the entry point's count
walks every live row every time the front door appears; at v8 it walks only the unanswered ones,
so it gets cheaper exactly as the person works. ⚠️ And that creates a trap for the gate — the
count's optimal plan **is** a `SCAN` (of a partial index), so a new plan-shape test that copies
`s1`'s blanket "no SCAN" assertion would be red for the right query. It asserts the named index
instead.

## Technical Context

**Language/Version**: Rust 1.90 (`rust-toolchain.toml`) · Swift 6 / SwiftUI, iOS 26.0 deployment
target — **both** touched by this slice, unlike 019
**Primary Dependencies**: **none added**, in either language. Existing only — `rusqlite`/SQLCipher,
`rust_decimal`, `regex`, `uniffi`, `thiserror` on the engine side; XCTest/XCUITest, Swift Testing,
Tuist, SwiftLint, swift-format on the platform side. The stale-set token is a list of ids rather
than a digest specifically so that no hashing crate is needed (research R17)
**Storage**: the existing encrypted SQLCipher store, schema **v7 → v8**. v8 is one `CREATE TABLE`
(`merchant_memory`) and one `CREATE INDEX` (`idx_txn_unanswered_account_date`) — **no `ALTER
TABLE`, no column added to `transactions`, no CHECK constraint added, no existing row read or
written**. Forward-only via `apply_migration` (`store.rs:1521-1544`), one version at a time, each
inside a transaction that carries its own `PRAGMA user_version` bump (`store.rs:1258-1273`), so
FR-048/SC-015 are properties of the existing mechanism
**Testing**: `cargo test` — new `tests/store_correction.rs`, `tests/merchant_memory.rs`,
`tests/merchant_portion.rs` (fixture-driven), plus additions to `tests/store.rs` (migration
v7→v8), `tests/history_paging.rs` (the narrowing), `tests/history_perf.rs` (plan shape) and
`tests/store_transfer.rs` (the R18 guard) · Swift Testing in `ios/Tests` for the picker's grouping,
the strings and the states a seed cannot construct · XCUITest in `ios/UITests` over three new seed
scenarios · `make import-audit` (ten scans, four widened in scope), `make release-audit`,
`make a11y-sweep`
**Target Platform**: iPhone simulator for every gate; iOS 26+ device for what remains manual and
for 018's still-unmeasured `06`
**Project Type**: mobile app over a shared Rust engine — the repo's two-layer split. No new layer,
no new package, no new Tuist target; **one** new directory each side
**Performance Goals**: none expressed as a wall clock, deliberately — `019/04` established that a
wall clock in a UI test measures the machine, and the spec carries no timing success criterion.
The engine's budget is expressed as **plan shape** instead (research R13): the narrowed page keeps
a `SEARCH` on a named index; the count scans only unanswered rows; `PAGE_SQL`'s plan is unchanged
**Constraints**: 100% on-device, zero network I/O; money is `Decimal` end-to-end and never a
float; determinism and parity against `fixtures/`; encrypted at rest with the existing Keychain
key handling; Liquid Glass **unconditional** — no `#available(iOS 26, *)`, no `.ultraThinMaterial`;
`.glassProminent` only in `Theme.swift`; SwiftLint `--strict`, 400-line files, 120 columns, and
⚠️ `ios/Sources/Import/ImportService.swift` is at **398** lines so **nothing in this slice may add
a line to it**; `cargo fmt` + `clippy -D warnings`; no real statement, fragment, merchant or
account identifier in any fixture; ⚠️ `core/tests/history_perf.rs::s5` is wall-clock and flaky
under CPU contention — **never run `make core-test` and `make ios-test` concurrently**
**Scale/Scope**: 7 user stories, 78 functional requirements, 36 success criteria; **1** migration
(v7→v8), **1** new Rust module, **6** new/changed `Store` methods, **2** changed `uniffi::Record`s,
**1** new `StoreError` variant, **0** changes to `categorize.rs`, **0** changes to `dedup.rs`;
1 new Swift directory (~8 files), 3 new seed scenarios, 4 scans widened in scope, 1 new fixture

*(No `NEEDS CLARIFICATION` remains — see [`research.md`](./research.md) R1–R23.)*

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v2.0.0.

| Principle | Verdict | Evidence in this design |
|---|---|---|
| **I. Data Privacy & Sovereignty (NON-NEGOTIABLE)** | ✅ PASS | Every path this slice adds is a read or a write against the encrypted store already on the device. No network call, no analytics, no telemetry, no crash reporting, no new crate and no new framework, so `make core-privacy-audit`'s denylist and `import-path-audit.sh`'s networking scan — which already covers **all** of `ios/Sources`, and therefore covers `ios/Sources/Categorize/` the moment it exists — are both satisfied without new machinery (FR-053, SC-020). Nothing on the path logs a transaction field, a category, a merchant description or a correction (FR-054). The migrated store stays SQLCipher under the same Keychain key; v8 creates one table and one index and never copies, exports or rewrites a row, so no plaintext store can exist at any point (FR-049, SC-015). The merchant memory is the most personal thing this app has ever stored and it never leaves the device. |
| **II. Local-First Shared Engine** | ✅ PASS | Every decision this slice makes is made in `kaname-core`: the write, the protection, the derivation, the count, the narrowing, the blast radius and the stale-set refusal. The platform gets no rule of its own — FR-021's "property of the engine, not of the interface" is met literally, and research R17 shows it is enforced *against a hostile caller*, because `apply` demands set equality with a freshly recomputed set rather than trusting what it was handed. The core stays pure and deterministic: the derivation reads no clock and no locale, `merchant_memory` carries **no** timestamp because newest-wins is achieved by replacement rather than by ordering (research R7), and money is `Decimal` on every hop this slice touches. A second platform would correct a category through the same call. |
| **III. Open-Core & Permissive Licensing** | ✅ PASS | Zero new dependencies in either language, so no licence surface changes — and the stale-set design (research R17) was chosen partly to avoid needing a hashing crate for a token. No secrets, no keys, no endpoints, no entitlement logic. Every fixture added is synthetic by construction (research R16) and by scan. |
| **IV. Native Experience & Accessibility** | ⚠️ **PASS with a stated limit** | Liquid Glass unconditionally, SF Symbols, Dynamic Type, Dark Mode, tabular figures for money carried over from 018, category never conveyed by colour alone (FR-061), and the `make-interfaces-feel-better` / `swiftui-liquid-glass` principles applied to every new surface (FR-063). Accessibility is a gate and 019 made it automatable: every new surface is reached by a seeded automated run and audited at default and XXXL, in Light and Dark. **The limit**: Increase Contrast **cannot be set from XCUITest** — the only mechanism in this repository is `make a11y-sweep`'s `simctl ui … increase_contrast enabled` — and the `.contrast` audit type is excluded from every audit because of `019/01`. FR-065 is therefore satisfied across two targets, not one, and the gate says so rather than implying more. See Spec amendments §5 and research R20. |
| **V. Test-First & Parity** | ✅ PASS | RED first throughout, and the two most important REDs are about defects that exist in shipped code rather than about new behaviour: the correction-survives-an-import test must be written and **watched failing against today's `categorize_account_in`** before the guard lands, and the `NULL NOT IN` trap gets its own test that fails against the naive spelling (research R10). Parity is protected by omission: `categorize.rs` and `dedup.rs` are **not modified**, so `fixtures/categorization/basic.json` and `fixtures/dedup/cross_source/basic.json` cannot move and FR-027c's "zero expectation edits" is structural (research R8). The new derivation gets its own fixture, `fixtures/categorization/merchant_portion.json`. Every assertion is named in [`contracts/engine-categorize.md`](./contracts/engine-categorize.md) §4 and [`contracts/platform-categorize.md`](./contracts/platform-categorize.md) before any code. |
| **VI. Free/Paid Boundary** | ✅ PASS | Correcting a category runs fully on-device, so it is free without exception, and nothing here is gated on, or capable of being unlocked by, an entitlement, an account tier or a server (FR-057). No T4/AI stage is added or referenced. |
| **Security & Privacy Constraints** | ✅ PASS | No third-party SDK, no new crate, no new framework, no secret. Fixtures are synthetic and — research R16 — deliberately so: this repository has correctly never contained a real statement, which is also why the derivation rule's *adequacy* against real narrations cannot be proved here. That limit is a consequence of Principle I and is accepted rather than worked around. |
| **Development Workflow & Quality Gates** | ✅ PASS | Spec Kit flow; the full iOS Local Verification Gate applies to every PR. Because `#[uniffi::export] impl Store` changes, **`make core-xcframework` then `make ios-gen` is mandatory** and a bare `tuist generate` is a trap (FR-050). `make lint`, `make core-test`, `make ios-test`, `make import-audit`, `make release-audit`, `make a11y-sweep`; ⚠️ core and iOS gates run **sequentially**, never concurrently, because `history_perf.rs::s5` is wall-clock. |

**Result: PASS — no violation requiring justification. Complexity Tracking is empty.**

### Post-Phase-1 re-evaluation

Re-checked after `research.md`, `data-model.md`, `contracts/` and `quickstart.md`:

- ✅ Still **zero** new dependencies. The migration is still additive-only: after Phase 1, v8 is
  exactly one `CREATE TABLE` and one `CREATE INDEX`, and the decision that got it there — a
  reserved provenance value rather than a new column or a new table for the decision itself
  (research R5) — is what keeps `transactions` untouched. A design that had added a column would
  have made SC-014 a thing to test rather than a thing that cannot fail.
- ✅ **`categorize.rs` is not modified.** The memory is consulted by the store *beside* the stack
  rather than *inside* it (research R8), which is the only shape found that satisfies FR-024
  ("no change to stage order or first-wins") and FR-032 ("a memory must not be outrankable") at
  the same time. It also means the parity fixture cannot move.
- ⚠️ **The design deliberately makes a person outrank the CC narration rules and T1.** That is
  what FR-032 asks for and it is a real change in what the engine does with rows it currently
  handles confidently. Research R9 measures the blast radius and finds it small — the derivation
  returns nothing for `CC PAYMENT RECEIVED`, `4262 BBPS Payment received`, `ONLINE TRF - PYMT
  RECD - THANK YOU` and `PAYMENT RECEIVED BBPS - Ref No: RT0001`, so no memory can form from a
  bill-payment row at all — but it is not empty: `10% Swiggy Cashback` yields `swiggy cashback`.
  Judgement call §2.
- ⚠️ **Three requirements could not be implemented as written** and are amended below, with the
  codebase believed over the spec in each case (§ *Spec amendments*). 019 did this four times and
  it was the right call.
- ✅ **The blast-radius boundary is enforced in the engine.** The prompt asked where. `apply`
  demands *set equality* with a freshly recomputed set, so a caller that trims or extends the list
  is refused; there is no arrangement of the interface that can turn the second action into a
  bulk edit, and SC-028 is provable against a hostile caller rather than against a UI that happens
  not to offer a checkbox.
- ✅ **No scan is disabled, narrowed or excepted.** Four scans are *widened* in scope to cover
  `ios/Sources/Categorize/` (research R22). Widening is the opposite of narrowing and FR-056/
  SC-022 hold.
- ⚠️ **`019/02` is not closed by this slice.** That ticket names a category feature as the thing
  that could make two unreachable `EmptyKind` cases reachable — by adding a delete path. This
  slice adds none, so both stay unreachable. Recorded so the next reader does not assume otherwise.

## Project Structure

### Documentation (this feature)

```text
specs/020-categorize/
├── plan.md                          # This file
├── research.md                      # Phase 0 — R1–R23
├── data-model.md                    # Phase 1 — schema v8, the predicates, every type
├── quickstart.md                    # Phase 1 — build order, gates, how to watch each one fail
├── contracts/
│   ├── engine-categorize.md         # Phase 1 — the Rust/uniffi surface and its assertions
│   └── platform-categorize.md       # Phase 1 — the Swift seams and their assertions
├── checklists/
└── tasks.md                         # NOT created by /speckit.plan
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── src/
│   ├── merchant.rs                  # NEW — the derivation rule, pure, uniffi-exported
│   ├── store.rs                     # SCHEMA_V8, the two predicate macros, the guard,
│   │                                #   set_transaction_category, preview/apply,
│   │                                #   uncategorized_count, HistoryQuery/HistoryRow,
│   │                                #   detect_transfers' guard, StoreError::StaleSet
│   ├── lib.rs                       # `mod merchant;` + re-export
│   ├── categorize.rs                # UNCHANGED — deliberately (research R8)
│   ├── dedup.rs                     # UNCHANGED — deliberately (FR-027c)
│   └── ffi.rs                       # the free `merchant_portion` export only
└── tests/
    ├── store_correction.rs          # NEW — the write path and its survival
    ├── merchant_memory.rs           # NEW — formation, replacement, preview/apply, stale set
    ├── merchant_portion.rs          # NEW — fixture-driven derivation
    ├── store.rs                     # + the v7→v8 migration test
    ├── history_paging.rs            # + the narrowing's paging and composition
    ├── history_perf.rs              # + plan shape for the narrowed page and the count
    └── store_transfer.rs            # + the detect_transfers person-protection guard

fixtures/categorization/
└── merchant_portion.json            # NEW — narration → expected portion (or null)

ios/Sources/Categorize/              # NEW DIRECTORY — all new platform code
├── CategorizeStrings.swift          # every string; re-uses TransactionListStrings.uncategorized
├── TransactionDetailView.swift      # US1's detail surface
├── CategoryPickerView.swift         # the catalog, grouped by classification
├── CategoryCatalog.swift            # grouping + ordering, pure, unit-testable
├── CorrectionViewModel.swift        # the correction, the memory offer, the decline
├── MemoryOfferView.swift            # FR-026a/FR-028's plain-language explanation
├── SecondActionView.swift           # FR-035a–FR-035h's blast radius and confirmation
├── UncategorizedEntryPoint.swift    # FR-041a/FR-041b's door, with the engine's count
└── CategorizeService.swift          # the actor; the engine's only caller for this slice

ios/Sources/                         # EDITED, minimally
├── RootView.swift                   # 137 → places the entry point, adds the destination
└── Transactions/
    ├── TransactionListModels.swift  # 332 → TransactionScope, EmptyKind's new cases
    ├── TransactionListView.swift    # 288 → the row becomes a NavigationLink
    ├── TransactionListViewModel.swift # 329 → carries the narrowing to the engine
    ├── TransactionHistoryService.swift # 66 → the new query field, the count
    └── TransactionListStrings.swift # 157 → nothing moves out; `uncategorized` stays the one definition

ios/Sources/DebugSeed/               # EDITED — declaration only, no new mechanism
├── SeedScenarios.swift              # 318 → + unfiled, repeated, crossing
└── SeedExpectations.swift           # 238 → their declared counts

ios/Tests/                           # + picker grouping, strings, the seed-unreachable states
ios/UITests/                         # + the new surfaces' audits and the worklist walk
scripts/import-path-audit.sh         # 4 scans WIDENED to cover ios/Sources/Categorize/
```

**Structure Decision**: the repo's established two-layer split, unchanged. One new Rust module and
one new Swift directory, both named for what they hold. `ios/Sources/Categorize/` exists because
FR-073 forbids adding a line to `ImportService.swift` and because a new directory is the only
placement that does not force existing files past their budgets — `TransactionListModels.swift` is
at 332 of 400 and is the file most at risk, so `TransactionScope` and the picker's grouping live
in `Categorize/`, not beside `AccountFilter`.

## Delivery order (mandatory, not advisory)

Unlike 019, the FFI **does** change, so 018's constraint is back in force: `tuist` resolves the
xcframework path at generation time, and every Swift PR here depends on an artifact the engine PR
produces. **PR A merges first and is not optional.** Within that, the ordering is chosen so that
the protection exists before the thing it protects: a correction that can be written but not
defended is the defect this slice exists to avoid, and shipping it even for one PR would put it in
the repository's history as a state a person could have been in.

| PR | Scope | Why this order |
|---|---|---|
| **A — The engine's answer to the defect** 🔒 | Schema **v8** (`merchant_memory`, `idx_txn_unanswered_account_date`); the `unanswered_predicate!()` and `engine_may_decide!()` macros; `PERSON`/`PERSON_MEMORY`; the guard on `load_account_transactions` **and** on `detect_transfers`; `set_transaction_category`; the v7→v8 migration test; the `NULL NOT IN` regression test | Merges **first**. The write path and its protection land together, in one PR, because either alone is a worse state than neither. The two REDs that matter are here and both are against **shipped** behaviour: the correction-survives-an-import test fails against today's unconditional `UPDATE`, and the naive-guard test fails against `NULL NOT IN`. ⚠️ Requires `make core-xcframework` **then** `make ios-gen` before any Swift PR can compile. |
| **B — The memory** 🔒 | `merchant.rs` and the derivation; `fixtures/categorization/merchant_portion.json`; the memory upsert; consultation in `categorize_account_in` **beside** the stack; `preview_memory_application` / `apply_memory` with the set-equality refusal; `StoreError::StaleSet` | Second, and still engine-only. Separable from A because a correction is useful without a memory (US1 ships alone, by the spec's own priority ordering) and because the derivation is the piece most likely to need a second look — R15's three limitations are found by running it, and finding them against a stable A is cheaper than against a moving one. |
| **C — The read side** 🔒 | `HistoryQuery.uncategorized_only`; `HistoryRow.category_id`; `uncategorized_count()`; the narrowed page SQL; the plan-shape tests, including the one that must **not** inherit `s1`'s no-`SCAN` rule; paging and composition tests | Third and last of the engine PRs. Deliberately after B so that "unanswered" has exactly one definition before two readers exist for it. Cheap to review because research R13 has already measured every plan it asserts. |
| **D — Correcting one transaction** 🎯 | `ios/Sources/Categorize/` — the detail surface, the picker, the catalog grouping, the strings, the service actor; the row becomes a `NavigationLink`; the four widened scans; the `unfiled` seed scenario and the first audits of both new surfaces | The first demoable PR: a person can finally disagree with the engine. Closes **US1** and **US5**. First PR to need the rebuilt xcframework, so it is also where the `AGENTS.md:88-92` trap is most likely to be met — the symptom is a Swift error and the cause is not. |
| **E — The memory, and the second action** | `MemoryOfferView`, `SecondActionView`, the decline path, the blast-radius statement; the `repeated` and `crossing` scenarios; SC-008, SC-026, SC-027, SC-031, SC-032, SC-033 | Closes **US3**. Cannot precede D — there is no correction to remember. ⚠️ The `crossing` scenario must dodge cross-source dedup (research R21): a ledger + card pair on the same date and amount is exactly what 018's R17 guard *does* compare, so the count the second action shows would be wrong before anyone tested it. |
| **F — The worklist** | The uncategorized narrowing on 018's list, `TransactionScope`, the entry point and its engine count, `EmptyKind`'s new cases and the reachability statement for every combination | Closes **US4**. After D because a worklist you cannot answer is a treadmill, and after C because the narrowing is the engine's, not the view's. |
| **G — Proved, not asserted** | Every new surface audited at default and XXXL × Light and Dark inside `make ios-test`, and again under `make a11y-sweep` for Increase Contrast; the **deliberate breaks watched red**, one per new surface; the host-rendered states no seed can construct; `.scratch/HANDOFF.md`, `AGENTS.md`, the manual-gate record with the build and date it was run | Closes **US6** and **US7**'s hand-back. Lands last because the coverage cannot be honestly described until D–F have established what there is to cover. ⚠️ A gate that has only ever been green proves nothing (FR-068, SC-017). |

Within each PR the order is **RED first**: the named assertion, watched failing, before the code
that satisfies it. For A and B that means watching a test fail against *shipped* behaviour; for
D–G it means watching the new coverage fail against a deliberately reinstated defect.

⚠️ **How to watch a gate fail without losing the fix.** `git checkout -- ios/Sources` reverts to
`HEAD`, so while the fix is uncommitted it takes the fix with it. Either commit the fix first and
then break the tree, or copy the tree aside before breaking it. This is written out step by step
in [`quickstart.md`](./quickstart.md).

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified.

**Empty.** The Constitution Check is a full pass; the one ⚠️ under Principle IV is a limit of
XCUITest, recorded as Spec amendment §5, not a violation requiring justification.

## Spec amendments

Where the codebase contradicted the spec, the codebase was believed. Each of these is a change to
what the spec *says*, made here rather than discovered during implementation.

1. **FR-037 — the uncategorized set excludes a person's deliberate blank.** FR-037 says "exactly
   the live transactions with **no category**"; the Key Entity for the same set says "the engine
   could not place **and the person has not answered**". They are different sets, and FR-037's
   makes SC-010 unachievable — a person who uses FR-007 to set a row to *no category* would leave
   it in the worklist forever, so the worklist could never reach zero by being used as intended,
   and FR-042b's "finished" state would be unreachable for them. **Amended to the Key Entity's
   definition**: `LIVE ∧ category_id IS NULL ∧ categorised_by IS NULL`. Research R12.

2. **FR-035e — the same *protection*, not the same *string*.** FR-035d excludes rows the person
   decided about; FR-035e records second-action rows with "the same provenance" as a hand
   correction; FR-031a requires the *next* offer to **include** the rows the previous one changed.
   All three cannot hold with one provenance value. **Amended**: two values, `PERSON` and
   `PERSON_MEMORY`, identical everywhere protection is concerned (FR-018–FR-022, FR-025, SC-004)
   and distinguished only by the second action's counting rule. Research R11.

3. **FR-026 — a correction to *no category* forms no memory.** FR-026 requires remembering "so
   that future imports of that merchant land in the corrected category"; there is no category to
   land in. Remembering blankness would keep re-filling the worklist with rows the person has
   already declared blank. **Amended** by extending FR-027d's existing precedent — the app forms
   no memory and says plainly that it has nothing to remember. Judgement call §4.

4. **FR-027a — the stop-list's stated character.** FR-027a calls it "a documented closed stop-list
   of channel and instrument words". It must also contain narration function words (`to`, `by`,
   `in`, `no`, `and`, `the`), because `normalize_narration` leaves whole channel phrases standing
   when its prefix regex does not match — `TO ECM/600000000001 TFR` keeps its `to`. **Amended** to
   "channel, instrument and narration-scaffold words". Still closed, still documented, still
   fixture-tested, still **zero** merchant names. Research R14.

5. **FR-065 — Increase Contrast is audited by a different target.** Increase Contrast cannot be
   set from XCUITest; the only mechanism here is `make a11y-sweep`'s `simctl ui …
   increase_contrast enabled`, which is not part of `make ios-test`. And `.contrast` is excluded
   from every audit because of `019/01`'s three unattributable verdicts. **Amended**: FR-065 is
   satisfied across two targets and SC-016's "zero findings" is scoped to the audit types that
   actually run. Research R20.

6. **FR-075 — the guard on `detect_transfers` is not a change to transfer detection.** FR-075 bans
   changing transfer detection; FR-019/FR-021 require a person's decision protected against "any
   caller". `detect_transfers`'s update is guarded by `transfer_group_id IS NULL` and not by
   provenance, so it can overwrite a correction. **Amended**: FR-075 bans changing what transfer
   detection *decides*; adding the person-protection clause changes no pairing, no threshold and
   no summary — only which rows an already-computed answer may land on. Judgement call §3.

Minor, recorded for accuracy rather than as amendments: the brief's file coordinates for
`ffi.rs`, `apply_migration`, `categorize_account_in`, `detect_transfers` and `normalize_narration`
are all slightly wrong, and `core/src/ffi.rs` does not exist. Corrected in research R1.

## Judgement calls for the product owner

### 1. 🚨 The merchant memory is a new table, not the T2 map the spec's narrative points at

**The finding.** The spec's opening describes the memory as the T2 `merchant_map` — *"the tier
whose entire purpose is to hold what this person has taught the app… nothing has ever put a row in
it"* — and reads as an invitation to finally put a row in it. The **requirements** describe
something that table cannot do, for four independent reasons (research R7): its `Literal` matching
is `normalized.contains(pattern)` and FR-027b demands *exact equality*; it is consulted at T2,
after the CC rules and T1, and FR-032 forbids a person's instruction being outrankable; it has a
`priority` and no uniqueness, so two contradictory memories of one shop are representable and
FR-031 forbids that; and it is already exposed by `list_merchant_rules()`, so putting personal
memories in it quietly breaks FR-035.

**Why it matters here.** Any one of the four would force a change to `merchant_map`'s semantics or
its schema. Adding a `UNIQUE` to an existing `STRICT` table means a full table rebuild — exactly
the row-touching migration that would turn SC-014 from a structural guarantee into a thing to test
hard enough.

**What this plan does — ✅ RESOLVED: a new table.** `merchant_memory`, keyed by the derived
merchant portion, with no priority and no timestamp. `merchant_map` keeps its exact current
behaviour and its exact current emptiness. This is the same distinction the spec draws everywhere
else — *a person's decision is a different kind of fact from an engine verdict* — applied one level
up.

**Deliberately still not answered here:** whether the T2 map should eventually be retired, merged,
or exposed. Managing remembered merchants is explicitly a later slice, and that slice inherits two
tables where the spec's narrative implies one. That is a real cost of this decision and it is
recorded rather than absorbed.

### 2. 🚨 A person now outranks the credit-card narration rules, and that is a behaviour change

**The finding.** FR-032 and the spec's own edge case ("if a person's instruction can be outranked
by a rule they never wrote and cannot see, the app is lying about having listened") require the
memory to win. Research R8's placement — consulted by the store, beside the stack — makes it win
over **everything**, including stage 0, the India-specific CC narration rules. So a memory can
change how rows the engine currently classifies confidently are filed from then on.

**Why it matters here.** FR-024 says this slice must not change the stack's stage order or
first-wins behaviour, and it does not: `categorize.rs` is not modified, its stage order is
untouched, and the set of rows fed to it is unchanged. But the *observable* precedence of the
whole system changes, and calling that "no change" because no file in `categorize.rs` moved would
be a technicality.

**What this plan does — ✅ RESOLVED, with the blast radius measured.** Research R9 ran the
derivation over every CC-rule-matching narration in the repository. `CC PAYMENT RECEIVED`,
`4262 BBPS Payment received`, `ONLINE TRF - PYMT RECD - THANK YOU` and `PAYMENT RECEIVED BBPS -
Ref No: RT0001` all derive to **nothing**, so no memory can form from a bill-payment row at all —
the overlap is far smaller than it first looks. It is not empty: `10% Swiggy Cashback` yields
`swiggy cashback`, and that one is a genuine override.

**Deliberately still not answered here:** whether a person should be *told* that their instruction
is overriding a built-in rule. This plan says nothing, on the grounds that FR-029 bans the engine's
vocabulary and there is no way to explain "this outranks the credit-card narration rules" without
it. If the owner wants that visible, it needs a piece of writing this slice has not budgeted.

### 3. 🚨 `detect_transfers` can erase a person's decision, and fixing it means touching a function FR-075 fences off

**The finding.** `detect_transfers`'s update is guarded by `WHERE id = ?1 AND transfer_group_id IS
NULL` (`store.rs:1160-1166`) — by group membership, not by provenance. A row a person corrected,
not yet in a transfer group, is eligible: a later run overwrites their category with
`SELF_TRANSFER` or `CREDIT_CARD_BILL_PAYMENT` and their provenance with `TRANSFER_DETECTOR`.
FR-019/FR-021 require the protection to hold "for **any** caller". FR-075 says do not change
transfer detection.

**Why it matters here.** It is unreachable in the shipping app — `import-path-audit.sh`'s ninth
scan bans the app from calling `detectTransfers` at all, and 018's R18 confirmed no Swift file
does. So this costs the app nothing today and is invisible to any test that goes through the UI.
It is precisely the kind of hole that gets discovered later, under pressure, by the slice that
finally wires transfer detection up.

**What this plan does — ✅ RESOLVED: add the guard, in PR A, with a Rust-only test.** One added
`AND <engine_may_decide!()>` clause. It changes no pairing, no threshold, no similarity
computation and no summary count — only which rows an already-computed answer may land on. Recorded
as Spec amendment §6.

**Deliberately still not answered here:** whether `detect_transfers` should ever run in the app.
018's R18 is still open and this slice does not touch it.

### 4. ⚠️ "No category" is an answer, but it is not something to remember

**The finding.** FR-007 makes "set it back to having no category" a first-class, protected
decision. FR-026 makes remembering automatic. The two together imply a memory whose category is
*nothing* — an instruction that every future transaction of this shop should arrive unfiled.

**Why it matters here.** Such a memory would keep re-filling the uncategorized worklist with rows
the person has already declared blank, which is the exact opposite of what the worklist is for. It
also needs a nullable `category_id` on `merchant_memory`, weakening the one table whose whole
value is that it cannot hold a contradiction.

**What this plan does — ✅ RESOLVED: no memory is formed from a blank.** The row's correction saves
and is protected exactly as any other; the app says plainly that there is nothing to remember,
using FR-027d's existing wording path rather than inventing a second one. "I don't know what this
is" is not knowledge about a shop. Recorded as Spec amendment §3.

**Deliberately still not answered here:** whether a person should be able to teach the app "always
leave this merchant alone". That is a real want and it is a memory-management feature, which is
out of scope by name.

### 5. ⚠️ The uncategorized count is cheap only because v8 buys it an index, and the gate for it must break `s1`'s rule

**The finding.** FR-043 requires the entry point's count to come from the engine, and FR-041b makes
it store-wide. Measured (research R13): at v7 that count is `SCAN transactions USING INDEX
idx_txn_live_account_date` — it walks **every live row**, every time the front door appears, and it
stays that expensive forever, including for the person who has diligently filed everything. At v8
it is `SCAN transactions USING INDEX idx_txn_unanswered_account_date` and walks only the rows that
remain.

**Why it matters here.** ⚠️ `history_perf.rs::s1` asserts that no plan step contains `"SCAN"`. The
count's *optimal* plan is a `SCAN` — of a partial index that contains only the rows being counted.
A new plan-shape test written by copying `s1` would be red for the correct query, and the tempting
fix would be to weaken `s1`.

**What this plan does — ✅ RESOLVED: two different assertions, and `s1` is not touched.** `s1` and
`s2` stay exactly as they are and are re-run to prove `PAGE_SQL`'s plan is byte-identical after
v8 (measured: it is). The count gets its own assertion — that the step names
`idx_txn_unanswered_account_date` — and the contract says in as many words that it must not
inherit `s1`'s blanket rule.

**Deliberately still not answered here:** the second action's read is `SCAN transactions USING
INDEX idx_txn_live_account_date`, O(live rows), because the merchant portion is derived in Rust
and is not a column. That is fine at the scales this repository tests and it is the honest cost of
not storing a derived column that the migration would then have to backfill. If a store ever gets
large enough for it to matter, the answer is a stored portion column and a slice that owns it.

### 6. ⚠️ Four of the ten scans do not watch the directory this slice's code goes in

**The finding.** `import-path-audit.sh`'s second-opinion (5), filter-persistence (6), aggregate (7)
and `.tint` (8) scans are scoped to `ios/Sources/Transactions/`. New code in
`ios/Sources/Categorize/` sits outside all four. FR-076's ban on the interface filtering or
counting a broader read, and FR-078's ban on aggregates, apply to it just as strongly — and a
Swift-side count of uncategorized rows is exactly what FR-043 forbids, in a directory no scan
watches.

**What this plan does — ✅ RESOLVED: widen the four scans' scope.** No denylist changes, no pattern
is relaxed, nothing is excepted. Widening is the opposite of narrowing, so FR-056 and SC-022 hold
— and the mechanical ban follows the code rather than the code escaping the ban.

**Deliberately still not answered here:** whether the scans should be scoped to `ios/Sources/`
wholesale. That is a bigger change with its own false-positive surface, and it belongs to whoever
next needs it rather than to this slice.
