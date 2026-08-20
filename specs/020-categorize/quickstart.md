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

⚠️ **`cargo` is not on a non-interactive shell's `PATH`.** `.zshrc` sources `~/.cargo/env`, and a
`make` invoked from a script or an agent shell does not read `.zshrc` — `make core-xcframework`
then fails with `cargo: command not found` from inside `build-xcframework.sh`, which reads like a
toolchain problem and is a `PATH` problem. Prefix with `. "$HOME/.cargo/env" &&`.

### What each gate signed off, this slice (T161, T164, T165, T182)

- **`make core-lint` + `make core-test` — clean and green: 358 passed, 0 failed, 19 binaries.**
  Unchanged from PR C's count, because PRs D–G touched no Rust.
- **`make lint` — 0 violations, 127 files** (T166). `ios/Sources/Import/ImportService.swift` is
  still **398** lines, and nothing in `ios/Sources/Categorize/` exceeds its budget — the largest
  is `CategorizeStrings.swift` at 268 of 400.
- **`make ios-test` — `TEST SUCCEEDED`: 410 passed, 0 failed, 2 skipped, 57 UI tests, 1,372 s.**
- **`make a11y-sweep` (T161) — PASSED.** `TEST SUCCEEDED`, **57 UI tests, 0 failures, 0 skipped**,
  1,270 s, iPhone 16 / iOS 26.5, **Increase Contrast enabled** and restored afterwards. That
  sweeps every seeded surface the UI bundle reaches — the transaction list, the detail surface,
  the picker, the memory offer, the second action, and the worklist with its door — in the one
  configuration `make ios-test` structurally cannot set (T180).
- **`make release-audit` (T164) — OK.** *"Release binary carries no seeding path; 6,079 symbols
  scanned, 6 terms"*, and the script self-checks for a known-present symbol and literal **first**,
  because `strip` would otherwise make the scan vacuously green. `DebugSeed`, `SeedScenarios
  .swift`, `SeedExpectations.swift` and the three new scenarios are absent.
- **`make import-audit` (T165) — OK, all ten scans**, four of them (5, 6, 7, 8) now covering
  `ios/Sources/Categorize/` as well as `ios/Sources/Transactions/`. 42 files under `ios/Sources`,
  5 seeding files, all `#if DEBUG`.
- **Parity (T167) — untouched.** `core/crates/kaname-core/tests/parity.rs` has an empty diff
  against the merge base, and so does `fixtures/` — the one fixture this slice added
  (`merchant_portion.json`, T041) shipped in #42 and is already on `main`. **No fixture was
  edited to make anything pass.**
- **No floats in money (T171), zero network (T172)** — the slice's diff adds no `Double`, `Float`,
  `f64` or `f32` on any money path (`merchant.rs`, `store.rs`, all of `ios/Sources/Categorize/`),
  and no `URLSession`, no network entitlement and no host in any `Info.plist`.
- **Synthetic data (T169)** — the one added fixture carries `syntheticcafe@examplebank` and digit
  runs that are keyboard sequences (`9876543210123`, `123456`, `778899`); `ios/Sources/DebugSeed/`
  contains **no** `@handle` and **no** digit run of 7 or more, anywhere.
- **Wording (T170)** — no banned engine word appears in `CategorizeStrings` or in any seed
  declaration. Now a standing test rather than a one-off grep:
  `CategorizeStringsTests.noSeedDeclarationCarriesEngineVocabulary` audits every scenario's
  account names, descriptions, declared categories and built row sentences. ⚠️ A banned word
  there could not *ship* — `DebugSeed` is `#if DEBUG` and `make release-audit` proves it — but it
  could **enshrine the engine's vocabulary in what a UI test expects a person to read**, so the
  day a surface leaked that word the suite would agree with it.

### 🚨 No disabled tests (T168) — one finding, and two legitimate skips

**This slice added one `XCTSkip`, and it is now gone.** `SeededAccessibilityUITests
.openMemoryOffer` skipped when `crossing`'s memory subject was absent — a helper reached by
**five** tests, four of them the accessibility audits over the memory offer and the second
action. On that branch SC-016's "zero findings" would have been **vacuously true for two of the
four new surfaces**, and the `nil` condition is the *documented* failure mode of that scenario
(gotcha 6 below). It is now `XCTUnwrap`, which fails rather than skips.
`.scratch/020-categorize/issues/03`.

⚠️ **The two remaining skips are pre-existing and correct**, and the inference that they were the
`XCTSkip` firing was made and then found to be wrong:

| Skipped | Guard | Why it is right |
|---|---|---|
| `KeyStoreTests/databaseFileIsProtected()` | `.enabled(if: …["SIMULATOR_UDID"] == nil)` | the data-protection class is only meaningful on a device |
| `ReferenceSetVerification/readsTheReferenceSet()` | `.enabled(if: directory != nil)` | the reference set is local and opt-in (`make reference-check`) |

Both are **declarative** `.enabled(if:)` on the test, which is the right shape: the condition is
visible at the test rather than buried in a shared helper. There is no `#[ignore]` in Rust and no
`#if` that removes an assertion. The one `XCTExpectFailure` in the tree is 019's, and it is
asserting that an unrecognised scenario **does** fail the launch — a test doing its job.

⚠️ **A skip count is not self-explanatory.** Two runs both reported "2 skipped" for entirely
different reasons; only `xcrun xcresulttool get test-results tests` and the test *names* settle
which. Read the names before drawing a conclusion from the number.

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

## The break ledger (T163)

**Fifteen deliberate breaks, what each was expected to turn red, and what it actually did.** A
break whose *observed* column is empty is a break that was not run, and there are none of those.
Five of the fifteen behaved differently from the queue's prediction, and **every one of those
five differences is the queue being wrong in a way that would have read as success**.

| # | Break | Expected red | **Observed** |
|---|---|---|---|
| **T026** 🚨 | `ENGINE_MAY_DECIDE` → the naive `categorised_by NOT IN ('PERSON','PERSON_MEMORY')` | C2 red, C1 green | ✅ **exactly**. C2 red, **C1 green**. `NULL NOT IN (…)` is `NULL`, so every row the import had just inserted was discarded and **nothing errored**. |
| **T027** ⚠️ | Remove `ENGINE_MAY_DECIDE` from `load_account_transactions` | C1 red | ❌ **turned nothing red** — the *write*-site guard blocks the overwrite alone. The two guards are not independent. **C8** was added rather than deleting the load guard: under the break it reads `left: (1, 1)`, `right: (0, 1)` — a summary describing work it did not do. |
| **T035** | Remove the provenance arm from `detect_transfers`'s `UPDATE` | T1 red, T2 green | ✅ **exactly**. `detection_does_not_overwrite_a_category_a_person_chose` — `left: Some("CREDIT_CARD_BILL_PAYMENT")`, `right: Some("SHOPPING")`; `detection_finds_the_same_pairs_when_no_row_is_a_persons ... ok`. The structural assertion goes red too: `these statements write a category without saying whose decision it is: ["UPDATE transactions \\"]`. |
| **T051** 🚨 | Max segment count 2 → 3 | P2 red | ❌ **P1 and P5 red, P2 GREEN.** The four `UPI-SWIGGY-*` shapes have one surviving segment each, so they still collapse. Watching only P2 would have read as "the break didn't take". The break that *does* reach P2 was run instead — **stop discarding reference tokens** — and P2 failed with `swiggy 123456` against `swiggy`. **What protects SC-008 is the reference-token discard, not the segment count.** |
| **T056** | Drop `merchant_memory`'s `PRIMARY KEY` | M3 red ("two rows for one merchant") | ✅ **harder than predicted, and better.** SQLite refuses the write outright: `ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint`. The constraint is *required* by the upsert, not merely relied on — it cannot decay silently. |
| **T063** | Consult the memory *after* the stack | M2 red | ✅ **exactly, and only M2.** `a_memory_beats_a_card_rule_and_the_issuers_own_label` — `left: (Some("CASHBACKS_AND_REFUNDS"), Some("CC_RULE"))`, `right: (Some("GROCERIES"), Some("PERSON_MEMORY"))`. 13 passed, 1 failed. Ordering is behaviour, not style. |
| **T074** | Set equality → `expected.is_subset(&found)` | M7 red; M5/M6/M8 green | ✅ **exactly.** `apply_refuses_a_trimmed_set_rather_than_obeying_it` — `a chosen subset must be refused: 3`. 13 passed, 1 failed. A subset check looks careful and silently obeys a trimmed list. |
| **T075** ⚠️ | Remove the recompute-and-compare; apply `expecting` verbatim | M6 red | ❌ **three red, not one.** M6 (`the agreed set no longer exists: 2`), M7 (`a chosen subset must be refused: 2`) **and** M11 `a_memory_cannot_outlive_its_category` (`got Sql { message: "FOREIGN KEY constraint failed" }`). The compare is also what stops an absent memory's empty `category_id` reaching the `UPDATE` — it guards more than staleness. |
| **T091** ⚠️ | Drop `idx_txn_unanswered_account_date` | Q3 red; `s1`/`s2` green | ✅ Q3 red, `s1`/`s2`/Q1 green — **and Q2 also stayed green**, unpredicted: the narrowed page falls back to `idx_txn_live_account_date`, still a `SEARCH` on a named index with no `TEMP B-TREE`. **Only Q3 gates the v8 index.** |
| **T096** ⚠️ | A throwaway `__scope_probe.swift` under `ios/Sources/Categorize/` doing `.filter` on a page **and** `.reduce` over `AccountSummary` | scans 5/6/7 red | ✅ scan 5 red, **naming the file and line**: `FAIL — a screen re-derives its own population: …/__scope_probe.swift:6: let rows = raw.rows.filter { $0.categoryId == nil }`. ⚠️ **`import-path-audit.sh` exits on the first failure**, so 6 and 7 never ran. Scan 7 was then isolated in a second probe: `FAIL — a screen computes a figure of its own: … summaries.reduce(0) { $0 + Int($1.transactionCount) }`. **One run can observe one scan.** |
| **T117** ⚠️ | Mark the current category by display name instead of by id | K3 **and** X2 red | ❌ **K3 red, X2 GREEN.** X2 changes a category; the *mark* on the current one is not on its path. Only `CategoryPickerTests` catches it — which is the whole reason K3 was extracted onto `CategoryChoice.isCurrent` as a pure rule. |
| **T138** | `SecondActionView` passes `Array(request.impact.transactionIds.dropLast())` | `StaleSet`, S5 fires, nothing written | ✅ **exactly, end to end.** `testAgreeingChangesTheRowsItNamed` red, the screen reading **"These transactions changed while this was open, so nothing here was changed. Take another look."**, the corrected row still `Category: Groceries`, nothing written. The refusal came from the **engine**, not the view. |
| **T154** 🚨 | Filter the received page inside `TransactionListViewModel` | scans 5 **and 6** red | ❌ **scan 5 red; scan 6 cannot fire and never could.** Scan 6 is the *filter-persistence* scan and looks for `UserDefaults`/`@AppStorage`, which a page filter does not use — and the audit exits on the first failure, so scan 6 never even ran. The behavioural half is sharper than promised: **three** `TransactionNarrowingTests` assertions go red naming the field (`PageRequest(… uncategorizedOnly: false)`). |
| **T155** | Sum `AccountSummary` in Swift in `UncategorizedEntryPoint.swift` | scan 7 red, E2 red | ✅ scan 7 red with the text quoted under T096 above — re-observed in PR G from an equivalent probe in the same directory, because the original break was reverted before its output was written down. |
| **T157** | Let the worklist include `'PERSON'` deliberate blanks (drop the provenance arm from `unanswered_predicate!()`) | X3 red + the platform reflection of H2 | ✅ **exactly, and end to end through the app.** `testChoosingNoCategoryTakesTheRowOffTheWorklist` red twice over: `XCTAssertFalse failed - a transaction a person deliberately left blank is still on the worklist`, then `XCTAssertEqual failed: ("3") is not equal to ("2")`. ⚠️ The break is **in Rust**, so watching it costs `make core-xcframework` → `make ios-gen` on the way in *and* on the way out. |

**The five lessons the ledger is actually for**, none of which is visible from a green suite:

1. **Two guards that both look necessary may not be independent** (T027). Ask what goes red, not
   what looks important.
2. **A break can miss the test it was aimed at and still be reverted as "done"** (T051, T117,
   T154). Name the *observed* red, never the intended one.
3. **A break can be broader than predicted, and the excess is information** (T075): the
   recompute-and-compare turned out to guard three things.
4. **A first-failure-exits audit can only be observed one scan at a time** (T096, T154). A queue
   that predicts "scans 5/6/7 red" is predicting something the tool cannot show.
5. **A constraint may be load-bearing in a stronger way than assumed** (T056): the upsert does
   not merely benefit from the `PRIMARY KEY`, it cannot be written without it.

---

## The audit matrix (T160)

**SC-016's "zero findings" is a claim about the audit types that actually run, over the surfaces
they actually reach.** This table is where that scope is written down instead of implied. Every
empty cell is a cell nobody checked, and each one says why.

`A` = audited by `performAccessibilityAudit` inside `make ios-test`, Light **and** Dark, at the
default text size **and** `AccessibilityXXXL`. `M` = measured rather than audited (a geometry
assertion, because the auditor's own hit-target check has never once fired here — 020 PR E, A17).
`S` = swept under Increase Contrast by `make a11y-sweep` (T161). `—` = not audited, with the
reason below.

| Surface | Default | XXXL | Dark | Hit target | Increase Contrast |
|---|---|---|---|---|---|
| Transaction detail (`TransactionDetailView`) | A | A | A | — ¹ | S |
| Category picker (`CategoryPickerView`) | A | A | A | — ¹ | S |
| Memory offer (`MemoryOfferView`) | A | A | A | **M** | S |
| Second action (`SecondActionView`) | A | A | A | **M** | S |
| Worklist door (`UncategorizedEntryPoint`) | A | A | A | **M** | S |
| Narrowed worklist (the list itself) | A ² | A ² | A ² | n/a | S |
| `allAnswered` — "Nothing left to file" | — ³ | — ³ | — ³ | n/a | — ³ |
| `accountAnswered` — one account finished | — ⁴ | — ⁴ | — ⁴ | n/a | — ⁴ |

¹ **Not measured, and not an oversight.** Both are `List` rows and a `Section` header drawn by
SwiftUI at the system's own metrics; the 34.33 pt defect A17 found was on a **`.buttonStyle`d**
control in a sheet, which is the shape that goes wrong. A measurement here would pin UIKit's
row height, not a decision this app made.

² **`.textClipped` is excluded from the list half of A18–A21, and only that half.** It fires on
the **shipped 018 row** at the **default** text size the moment the list is seeded with
`unfiled` — proved by three probes, one per surface, and written up as
`.scratch/020-categorize/issues/01`. The door keeps the type, and it is the type that caught the
door's own real defect.

³ **Rendered on a real screen but never inside an audit.** `CategorizeWorklistUITests
.testTheDoorShowsTheEnginesCountAndThenSaysTheWorkIsFinished` walks a scenario to zero and reads
the finished sentence, so the state is reachable and its wording is asserted — but the four
audits (A18–A21) run over `unfiled`, which by construction still has rows. Auditing the finished
state would mean answering every row through the UI inside an audit test, which is a fifteen-tap
prologue to a one-line assertion.

⁴ **Unit-level only.** `TransactionEmptyStateTests` and `TransactionWorklistEmptyStateTests`
assert the `EmptyKind` and the sentence; nothing renders it and nothing audits it. It is
reachable — filter to a finished account — and no test takes that path.

⚠️ **What no cell in this table covers**: VoiceOver's spoken announcements, Reduce Transparency
(no `simctl` control exists), and Reduce Motion. Those stay with the manual gate, exactly as
018 left them.

---

## What is executed and asserted but **not** audited (T162)

A host-rendered SwiftUI view publishes **no accessibility label**, so `performAccessibilityAudit`
— an `XCUIApplication` API — cannot be pointed at one. Every unit-level rendering test in this
repository is therefore weaker than a seeded UI test, and the difference is recorded rather than
smoothed over:

- **`EmptyStateRenderingTests`** (018's three unreachable states) — the branch runs and the view
  builds, and nothing about contrast, clipping, hit regions or Dynamic Type is checked. The
  file's own header says so at length; this is the second place it is written down.
- **`accountAnswered`** — asserted as a value and as a sentence, never rendered (row ⁴ above).
- **Every sentence in `CategorizeStrings.everyBuiltSentence`** — assembled at runtime, so the
  audit would never see most of them; `CategorizeStringsTests` is what reads them instead.

⚠️ **Two traps, both paid for once already.** `RunLoop.main.run(until:)` inside an async
`@MainActor` test **deadlocks** — use `Task.sleep`. And a detached `UIWindow` has no display
link, so nothing ever draws: attach to the host app's scene.
`ios/Tests/EmptyStateRenderingTests.swift` is the precedent for both.

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

> These are **findings, not footnotes**. Each is closed by writing down what is not known, in the
> manner of 019's T085 — never by an assertion, and never by quietly dropping it because it could
> not be made green.

**T176 — the three device timings. DEFERRED; 018's SC-012 stays unsigned, and this slice did not
sign it.** `.scratch/018-transaction-list/issues/06` is still `ready-for-human`: G9, G11 and G12
have **never been measured**, on any machine, by anybody. A simulator measures the host, so no run
here can close them; the ticket carries the whole runbook (~20 minutes with a physical phone, a
Release build and a frame-stepped screen recording). ⚠️ **A free-team build expires seven days
after install.** This slice adds two more tap-reachable surfaces — the detail view and the
worklist — and **measured the timing of neither**. SC-012 is exactly as unsigned as 018 left it.

**T177 — `018/05`'s render hang. DEFERRED; nothing hung here, and that is not evidence.** The
reopen conditions, stated precisely enough for somebody with the hardware to try them:

1. Seed or import a **deep** history (the `deep` scenario, or ≥10,000 rows), on a physical device.
2. Scroll the transaction list **far past the first page** — several keyset pages in, not one flick.
3. Push a detail view from a row, go back, and repeat **without relaunching**, ~10 times.
4. Watch for 100% main-thread CPU with the list still on screen. Sample with Instruments' Time
   Profiler; the original was sampled and the sample is on the ticket.

020 adds a push over exactly that list, which is what makes it *closer* to the untested
combination than 018 was. It was **not** reproduced here in any run of this slice — and it was
not *attempted* under those four conditions either, because reproducing it needs the phone step 1
calls for. If it reproduces, **reopen `018/05`; do not re-diagnose from scratch.**

**T178 — the query plans. Q1–Q3 settle three statements, and are not a survey.** Research R13's
plan survey was taken on **system SQLite 3.45.3**, not the SQLCipher build the engine links.
Q1–Q3 assert against the **real store** and reproduce R13's predicted shapes exactly:

```text
Q2 narrowed page: ["SEARCH t USING INDEX idx_txn_unanswered_account_date (account_id=? AND date<?)"]
Q3 count:         ["SCAN transactions USING INDEX idx_txn_unanswered_account_date"]
```

That settles **three** queries — `PAGE_SQL`, `PAGE_SQL_UNANSWERED`, `UNCATEGORIZED_COUNT_SQL` — on
**one** corpus shape (8 accounts, 10,000 rows), at **one** SQLCipher version, on **one** machine.
It does not settle the rest of R13's survey, any other statement in the store, the behaviour at
other corpus shapes, or how any of them plan **on a device**. Three green tests are not a survey
and are not recorded as one. ⚠️ And `Q2` does not gate the index at all — only Q3 does (T091).

**T179 🚨 — whether the derivation rule is adequate for real Indian narrations. UNPROVABLE HERE,
BY DESIGN.** This repository has correctly never contained a real statement, and there is not one
real VPA or UPI-handle shape anywhere in it. What the 33-case fixture proves is that the rule is
**deterministic, fixture-testable and stable across the shapes we have**. It does **not** prove
the rule is right about anybody's actual bank. That limit is a direct consequence of Principle I
and is **accepted, not worked around** — the alternative is a real narration in a public repo,
which is not a trade this project makes.

What *is* known are research R15's three priced limitations, asserted in **P5** so they cannot
drift into being surprises. What would settle it: **a person's own store, examined by that
person, on their own device, never exported** — the derivation run over their real narrations
with the output read by them and nothing reported anywhere. Until somebody does that, the honest
claim is "proven against synthetic shapes", and that is the claim this slice makes.

**T180 — Increase Contrast. A permanent split, not a temporary gap.** It cannot be set from
within XCUITest: `performAccessibilityAudit` runs against whatever the accessibility daemon is
configured for, and neither a launch argument nor a test API reaches it. Only `simctl` does. So
**FR-065 is satisfied across two targets** — `make ios-test` for appearance and text size,
`make a11y-sweep` for Increase Contrast (plan § *Spec amendments* §5). This is not a gap waiting
on a fix; it is the shape of the tooling, and a future reader should not "fold the sweep into
`ios-test`" believing it was an oversight. ⚠️ **Reduce Transparency has no `simctl` control at
all** and stays with the manual gate, along with VoiceOver's announcements.

---

## Who signed what (T173)

**Signed by a machine**, every run, no human in the loop:

| Signed by | What |
|---|---|
| `make core-test` | SC-001–SC-010, SC-014, SC-015, SC-024–SC-028 — the correction surviving every engine path, the `NULL NOT IN` trap, the transfer guard, the derivation, the memory's rank, the preview/apply contract, the migration's byte-identity |
| `make core-test` (`history_perf`) | SC-021, SC-029 — the narrowed page's plan and the count's named index |
| `make ios-test` (unit) | SC-007, SC-011, SC-023, SC-024 — the wording, no figure on the screen, the file budgets' subject matter, `EmptyKind`'s eight rows |
| `make ios-test` (UI, seeded) | SC-012's *behavioural* half, SC-013, SC-016 (for the types that run), SC-019, SC-020, SC-022 |
| `make import-audit` | SC-020, SC-022 — the engine is the only population and the only count |
| `make release-audit` | 019's absence guarantee, re-run here because this slice added three scenarios |
| `make a11y-sweep` | FR-065's Increase Contrast half |
| `make lint` | SC-023 |

**Signed by a person, or not signed at all:**

| Status | What |
|---|---|
| ⛔ **Unsigned** | **SC-012's three device timings** (G9, G11, G12) — never measured, by anyone (T176) |
| 👤 Person | VoiceOver's spoken announcements over the four new surfaces |
| 👤 Person | Reduce Transparency and Reduce Motion (no `simctl` control exists) |
| 👤 Person | The end-to-end smoke test above: import → correct → decline → **re-import** → still yours |
| 🚫 **Unprovable here** | Whether the derivation is right about real narrations (T179) |
| 🚫 **Unreproduced** | `018/05`'s render hang (T177) |

There is nothing in between these two tables. A criterion is either run by a machine on every
gate, run by a person and named here, or explicitly not signed.

---

## The hand-back walk (T183)

**Every FR-001–FR-078 and SC-001–SC-036 was walked.** The verdict, in three lines:

- **72 of 78 FRs and 32 of 36 SCs** are discharged by a task that cites them by number — the
  traceability tables in `tasks.md` § *Traceability* map every named engine assertion (C, T, H, M,
  P, Q, G) and every platform rule (R, D, K, M, S, E, L, T, U, X) to its task id.
- **Six were satisfied but never cited by number**, and are cited here so the walk is repeatable:
  **FR-058** and **SC-025** (all test data synthetic) → **T169**; **FR-070** (a state a seed
  cannot construct is rendered in the unit target, and the unevenness is *stated*) → **T162** and
  the matrix above — ⚠️ note that 020 added **no** seed-unreachable state, so FR-070's rendering
  clause is vacuous for this slice and only its stating clause bites; **SC-018** (every surface
  reachable by an automated run, zero human actions, zero files on the device) → the seeded UI
  suites, one per surface; **SC-034** (the count equals what is found, and is the engine's) →
  **T147**, **T155** and `CategorizeWorklistUITests`; **SC-035** (every reachable combination of
  the two narrowings has its own wording and its own coverage) → `TransactionWorklistEmptyStateTests`.
- **Five are explicitly deferred with a reason** — T176 (device timings), T177 (the render hang),
  T178 (the wider plan survey), T179 (real narrations), T180 (Increase Contrast). See § *what
  cannot be verified on this machine*.

### 🚩 One gap, reported rather than closed

**`EmptyKind.accountAnswered` — one account finished while another still has work — is reached by
no automated run of any kind.** It is asserted twice as a value and a sentence
(`TransactionEmptyStateTests`, `TransactionWorklistEmptyStateTests`) and rendered by nothing.

It is **not** covered by FR-070, which is about states a seed *cannot* construct: this one is
perfectly constructible — answer every row of one account in a two-account scenario. So it is a
genuine hole in **SC-018**'s "100% of the surfaces this slice adds are reachable by an automated
run", read strictly, and a soft spot in **SC-035**'s "their own coverage".

Filed as `.scratch/020-categorize/issues/02`. It is reported and not closed because T183 says to
report gaps, and because closing it means a ~15-tap prologue whose cost belongs to whoever
decides the state is worth that.

---

## Definition of done

- [x] Schema v8 applied forward-only; a v7 store with rows in every provenance state migrates with
      every field byte-identical (SC-014, SC-015).
- [x] A correction survives a re-import, a transfer-detection run, and any other engine path
      (SC-004) — and the **C2** trap test is green with a **non-zero** categorized count.
- [x] `categorize.rs`, `dedup.rs` and `merchant_map` are untouched; `fixtures/categorization/basic.json`
      and the dedup fixtures have **zero** expectation edits.
- [x] The four `UPI-SWIGGY-*` shapes collapse to one memory (SC-008).
- [x] The second action states a count and account names, refuses a trimmed id list and refuses a
      stale set (SC-026, SC-027, SC-028); no multi-select ships.
- [x] The uncategorized count comes from SQL; `import-audit`'s widened scans watch
      `ios/Sources/Categorize/` and all ten stay green and unweakened (SC-020, SC-022).
- [x] `s1`/`s2` unedited and green; the count's plan names `idx_txn_unanswered_account_date`.
- [x] Every new surface audited at default and XXXL, Light and Dark, inside `make ios-test`; and
      under `make a11y-sweep` for Increase Contrast — **with the scope written down** (T160's
      matrix), because "every surface" is only true of the audit types that run.
- [x] Every gate in the table above has been **watched failing** at least once — all fifteen,
      with the observed failure text, in § *the break ledger*.
- [x] `make lint`, `make core-test`, `make ios-test`, `make import-audit`, `make release-audit`,
      `make a11y-sweep` green — core and iOS run **sequentially**.
- [x] `.scratch/HANDOFF.md` and `AGENTS.md` updated; every finding filed with its status.
