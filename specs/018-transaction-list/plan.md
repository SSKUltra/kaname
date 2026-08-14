# Implementation Plan: The Transaction List

**Branch**: `018-transaction-list` | **Date**: 2026-08-14 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/018-transaction-list/spec.md` — **FINAL**; both
clarifications (Session 2026-08-14) are settled constraints and are not re-opened here.

## Summary

Kaname can read a statement and cannot show one. Import writes transactions to an encrypted
store; the front door renders a count. This slice turns that count into something a person can
audit: a scrollable, date-grouped, cross-account transaction list, reachable from the front
door, filterable to one account, honest about what it is not showing.

The technical shape, in one paragraph. The engine gains **one migration and two reads**: schema
v7 adds a single partial descending index, `history_page(HistoryQuery) -> HistoryPage` returns
one keyset-paged screenful of the combined history, and `account_summaries()` moves the live
count out of Swift and into SQL. `history_page` runs one index-satisfied statement per account
and merges the k already-sorted streams in Rust; the filtered read is the same statement with
k = 1, so a filtered list is not a second code path. The order — `date DESC`, then the account's
position in `list_accounts()`, then `transactions.rowid` — is total, deterministic and
index-friendly, and it is expressed in exactly two places that a test pins to each other. The
live-row rule is a single Rust constant that is *byte-identical to the index's `WHERE` clause*,
so a read that forgets the rule does not silently return the wrong rows — it loses its index and
the plan-shape gate goes red. On the platform side a new `ios/Sources/Transactions/` directory
holds the list, because `ios/Sources/Import/ImportService.swift` is already at exactly the
400-line SwiftLint limit; the accessibility layout decision is extracted into a pure value type
so the automatable half of SC-013 can be proved without rendering a screen.

Measured while planning, on a real SQLCipher store with 10,000 transactions across 8 accounts:
first page **254.75 µs** with a plan containing no `SCAN` and no temp b-tree; worst page over a
full walk **289 µs**; per-account cost varying **13%** between a 200-row and a 10,000-row
corpus; index cost **+12.4%** on the database file. The front door's current Swift-side count
costs **43.8 ms** of Rust time on the same corpus; the engine count costs **0.99 ms**.

Two findings in shipped code that the spec did not anticipate are flagged below and in
[`research.md`](./research.md) R17 and R18. Neither is caused by this slice; one blocks one
acceptance scenario.

## Technical Context

**Language/Version**: Rust 1.90 (`rust-toolchain.toml`), edition 2021 · Swift 6 / SwiftUI, iOS
26.0 deployment target, built with Xcode 26.6 / iOS SDK 26.5
**Primary Dependencies**: **none added.** Existing only — `rusqlite` with bundled SQLCipher
(SQLite 3.46.1 / SQLCipher 4.6.1 community, verified at runtime), `rust_decimal`, `chrono`,
`uniffi` 0.32, Tuist, SwiftLint
**Storage**: the existing encrypted SQLCipher store, schema v6 → **v7**. The migration is a
single `CREATE INDEX` — no table, column, constraint or row is added or changed
**Testing**: `cargo test` (engine, incl. `EXPLAIN QUERY PLAN` shape assertions and wall-clock
bounds against a real store) · Swift Testing in `ios/Tests` (view model, layout decision,
strings, empty states, parity) · XCUITest in `ios/UITests` (accessibility sweep) · a manual,
release-blocking device gate for what no automated test can see
**Target Platform**: iPhone, iOS 26+, offline
**Project Type**: mobile app over a shared Rust engine — the repo's established two-layer split;
no new layer, target or package
**Performance Goals**: first screenful < 1 s on device with 10,000 transactions over ≥ 8
accounts (SC-006); no page > 100 ms (SC-007); time-to-first-screenful varying ≤ 20% between a
200-row and a 10,000-row corpus (SC-008); filter apply or clear < 300 ms
**Constraints**: zero network I/O on this path — `make import-audit` fails the build on a
networking symbol; money is `Decimal`/`rust_decimal` at every hop and never a float, including
through formatting; Liquid Glass unconditional — no `#available(iOS 26, *)`, no
`.ultraThinMaterial`, no hand-rolled blur; SwiftLint `--strict`, 400-line files, 120 columns;
no real statement, merchant or account identifier in any fixture; `list_transactions` keeps its
current raw semantics because engine tests depend on them
**Scale/Scope**: 8 user stories, 77 functional requirements, 17 success criteria; 2 new engine
reads, 6 new engine types, 1 migration, 1 new Swift directory of 6 files, 1 line changed in
`ImportService.swift`, 1 line widened in `scripts/import-path-audit.sh`

*(No `NEEDS CLARIFICATION` remains — see [`research.md`](./research.md) R1–R20.)*

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v2.0.0.

| Principle | Verdict | Evidence in this design |
|---|---|---|
| **I. Data Privacy & Sovereignty (NON-NEGOTIABLE)** | ✅ PASS | This slice is a **read path over data that is already on the device**. It adds no network call, no analytics, no crash reporting, no telemetry, and no new crate — so `make core-privacy-audit`'s denylist is unaffected. Data at rest stays in the SQLCipher store under the Keychain key. No account, entitlement check or server call appears anywhere. `HistoryRow` and `AccountSummary` carry no field that could reach a log, and errors are mapped to a platform error type carrying no description, amount, date or account identifier (FR-063). One gap in the *audit itself* is closed here, not created here: `scripts/import-path-audit.sh:15` scans only `ios/Sources/Import` for networking symbols while the glass and bank-literal scans cover all of `ios/Sources`. The networking scan is widened to `ios/Sources` in the same PR that creates `ios/Sources/Transactions/` (research R19). |
| **II. Local-First Shared Engine** | ✅ PASS | The population rule, the ordering, the paging and the counting all live in `kaname-core` and would be reused verbatim by a second platform. `history_page` is deterministic: no clock, no locale, no network, no global mutable state — the same store and the same query yield a byte-identical sequence (test O5). The *only* clock in this slice is on the platform side, injected, and used solely to decide whether a date heading needs a year (FR-035). Money is `rust_decimal::Decimal` → base-10 `String` → `Foundation.Decimal`, and direction is carried by the explicit `Direction` enum, never inferred from an amount's sign (FR-014). Formatting uses `Decimal.formatted(.currency(code:))` — no `Double` bridge anywhere on the path. |
| **III. Open-Core & Permissive Licensing** | ✅ PASS | Zero new dependencies, so no licence surface changes and no copyleft risk. No secrets, no API keys, no endpoints, no entitlement logic. |
| **IV. Native Experience & Accessibility** | ✅ PASS | SwiftUI on the iOS 26 baseline with unconditional Liquid Glass per `.github/skills/swiftui-liquid-glass/SKILL.md`. Glass is applied to floating chrome — the filter control — and **never** to dense numeric rows, which is exactly this skill's rule and exactly what a transaction list is. Amounts use `.monospacedDigit()` (FR-027). Dynamic Type through the accessibility sizes is a first-class design input, not a retrofit: the row switches axis on `dynamicTypeSize.isAccessibilitySize` and the amount never yields (FR-021). VoiceOver, Dark Mode, Reduce Transparency and Increase Contrast are release gates (FR-065–FR-070, SC-012). Bottom-anchored chrome uses `.safeAreaBar(edge: .bottom)`. |
| **V. Test-First & Parity** | ✅ PASS | RED → GREEN throughout. The engine contract is written as ~30 named assertions before any implementation ([`contracts/engine-history.md`](./contracts/engine-history.md) §4), including the v6 → v7 migration test that follows the shipped migrations' pattern. The performance criteria are split into an automatable engine half (plan shape + wall-clock, with ~100× measured headroom) and a device half on the manual gate — a criterion that cannot be measured in this repo's test setup is not a criterion (research R9). `StoredTransaction.isLive` is retained specifically as the cross-language parity mirror of the engine's `LIVE` constant. Every fixture is synthetic, with a documented corpus contract (research R20, `data-model.md` §7). |
| **VI. Free/Paid Boundary** | ✅ PASS | Reading one's own transactions on one's own device is free, and cannot be otherwise — the whole path is local. Nothing here is gated, metered or server-validated. No AI, no Account Aggregator, no sync, no export: all excluded by the spec's Out of Scope. |
| **Security & Privacy Constraints** | ✅ PASS | No third-party SDK, no new crate, no new system framework. Fixtures synthetic. No secrets committed. The `HistoryCursor` is opaque to the platform and contains no user-meaningful value beyond a date the person can already see. |
| **Development Workflow & Quality Gates** | ✅ PASS | Spec Kit flow; the full iOS Local Verification Gate (`make core-lint && make core-test && make lint && make ios-test`, plus `make import-audit`) applies to every PR. Because the FFI surface changes, `make core-xcframework` **must** precede `tuist generate` — `make ios-gen` already encodes this, and [`quickstart.md`](./quickstart.md) leads with it. |

**Result: PASS — no violations, no justifications required. Complexity Tracking is empty.**

### Post-Phase-1 re-evaluation

Re-checked after `research.md`, `data-model.md`, `contracts/` and `quickstart.md`:

- ✅ Still **zero** new dependencies, in either language.
- ✅ Schema v7 is the **least invasive migration in the store's history**: one `CREATE INDEX`,
  no table rebuild, no foreign-key disable, no row read or written (`data-model.md` §1).
- ⚠️ **Flagged, not waved through**: the spec says this slice "introduces no new stored data".
  An index stores no *data* — it stores no field a person or a later feature can read — but it
  *is* a schema migration and a `PRAGMA user_version` bump. Without it the ordering costs a
  temp b-tree over every live row of every account and SC-006/SC-008 are unreachable
  (measured: 3.97 ms → 254.75 µs, and `USE TEMP B-TREE FOR ORDER BY` disappears). The
  alternative — sorting in Rust after reading everything — contradicts FR-044 outright. This is
  the plan's reading of a sentence about *data*, applied to an *index*; it is called out here
  so the product owner can overrule it. See "Judgement calls" §3.
- ✅ The engine stays pure and deterministic. `history_page` takes `self.lock()` **once** and
  uses `*_in(&conn, …)` helpers thereafter — 016's non-reentrant-mutex lesson is honoured by
  construction, and the lazily-consumed-handle design was rejected precisely because it would
  hold the guard across FFI calls (research R1).
- ✅ `Store::list_transactions` keeps its exact raw semantics; the live rule lands in a new,
  separate place rather than by changing an existing one that engine tests depend on.
- ✅ Sharing one `Store` between `ImportService` and `TransactionHistoryService` makes FR-054
  ("never a partially-written statement") structural rather than timing-dependent: the existing
  mutex serialises the read against the atomic import.
- ⚠️ Two findings in **shipped** code surfaced (research R17, R18). Neither is introduced by
  this design and neither is a constitutional violation, but one blocks an acceptance scenario
  and one makes a requirement vacuous in a real install. Both are in "Judgement calls" below.

**Result: PASS. Complexity Tracking remains empty.**

## Project Structure

### Documentation (this feature)

```text
specs/018-transaction-list/
├── plan.md                       # This file
├── spec.md                       # FINAL — both clarifications are settled constraints
├── research.md                   # Phase 0 — R1–R20, each with measured evidence
├── data-model.md                 # Phase 1 — schema v7, the ordering key, empty states, corpus
├── contracts/
│   ├── engine-history.md         # Phase 1 — history_page, account_summaries, ~30 assertions
│   └── platform-seams.md         # Phase 1 — the six Swift seams and their rules
├── quickstart.md                 # Phase 1 — build order, traps, gates, manual gate record
├── checklists/
│   └── requirements.md           # Pre-existing spec-quality checklist
└── tasks.md                      # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── src/
│   ├── store.rs                  # CHANGED — SCHEMA_VERSION 6→7, SCHEMA_V7 index, LIVE const,
│   │                             #   history_page, account_summaries, *_in helpers
│   └── ffi.rs                    # CHANGED — export the 6 new records (Decimal/NaiveDate
│                                 #   custom types already registered)
└── tests/
    ├── history_order.rs          # NEW — O1–O7: totality, determinism, stability
    ├── history_paging.rs         # NEW — P1–P5, F1–F3: page-size invariance, filter parity
    ├── history_live.rs           # NEW — L1–L6: deleted/superseded, re-import, count parity
    ├── history_perf.rs           # NEW — S1–S6: EXPLAIN QUERY PLAN shape + wall-clock bounds
    ├── store.rs                  # CHANGED — v6→v7 migration test (M1–M3); rest untouched
    └── …                         # UNCHANGED — list_transactions' raw semantics preserved

ios/
├── Sources/
│   ├── RootView.swift            # CHANGED — new NavigationStack destination;
│   │                             #   .safeAreaInset → .safeAreaBar
│   ├── Transactions/             # NEW — all of this slice's platform code
│   │   ├── TransactionListView.swift       # List + Section, glass filter chrome, empty states
│   │   ├── TransactionRowView.swift        # driven by TransactionRowLayout; NOT LabeledContent
│   │   ├── TransactionListViewModel.swift  # paging, filter, incremental date grouping, anchor
│   │   ├── TransactionHistoryService.swift # actor; the engine's only caller
│   │   ├── TransactionListModels.swift     # TransactionRow, DateGroup, EmptyKind, filter
│   │   └── TransactionListStrings.swift    # every user-visible string, one file
│   ├── Import/
│   │   ├── ImportService.swift             # CHANGED — ONE line: the count comes from
│   │   │                                   #   account_summaries(); file is AT the 400 limit
│   │   ├── ImportModels.swift              # CHANGED — isLive's ⚠️ comment; hasOnlyExcludedRows
│   │   └── ImportedAccountsView.swift      # CHANGED — rows become NavigationLinks
│   └── Persistence/
│       └── StoreProvider.swift             # NEW — one Store per process, shared by both services
├── Tests/
│   ├── TransactionListViewModelTests.swift # NEW — V1–V8: filter reset, grouping, no totals
│   ├── TransactionRowLayoutTests.swift     # NEW — A1–A6 over all 12 DynamicTypeSize cases
│   ├── TransactionListStringsTests.swift   # NEW — pluralisation, no ids, no blame words
│   ├── TransactionHistoryServiceTests.swift# NEW — integration over the bridge, real store
│   └── LivenessParityTests.swift           # NEW — Swift isLive ≡ engine LIVE
└── UITests/
    └── AccessibilityAuditTests.swift       # EXTENDED — the list screen joins the sweep

scripts/import-path-audit.sh      # CHANGED — networking scan widened to all of ios/Sources
```

**Structure Decision**: the repo's established two-layer split is unchanged — a
platform-agnostic Rust engine in `core/crates/kaname-core` exposed via UniFFI, and a native
SwiftUI app in `ios/`. Two placements are deliberate rather than incidental. First, **all**
population, ordering and counting logic goes engine-side, because that is what makes FR-008's
"no screen may count one population and list another" structural instead of remembered. Second,
**all** new platform code goes in one new directory, `ios/Sources/Transactions/`, because
`ios/Sources/Import/ImportService.swift` is at **exactly** 400 lines — the SwiftLint `--strict`
file limit — so the seam has to go somewhere, and the honest place is a directory boundary
rather than a file split made under duress.

## Delivery order (mandatory, not advisory)

Engine work crosses the FFI and **must land separately from, and before, interface work**: the
xcframework is rebuilt and Tuist resolves its path at generation time, so a PR mixing both
cannot be reviewed or bisected cleanly.

| PR | Scope | Why this order |
|---|---|---|
| **A — Engine** 🔒 | Schema v7 index, `LIVE` constant, `history_page`, `account_summaries`, the six records, `ffi.rs` exports, the four new test files (O/L/P/F/S) + the migration test, **and the R17 dedup tie-break fix** | Must merge **first**. Everything but the tie-break is purely additive. Crossing the FFI on its own makes the xcframework rebuild a single reviewable event. |
| **B — The list** 🎯 | `ios/Sources/Transactions/` (all six files), `StoreProvider`, the row with its accessibility layout **from the start**, incremental date grouping, `NavigationStack` destination; `ImportedAccountsView` rows become links; the front-door count switches to `account_summaries()`; the widened `import-path-audit.sh` networking scan | The first demoable PR — a person can finally see and scroll their transactions. Closes US1, US2, US4. The a11y layout ships in the same PR as the row because retrofitting it is how the parked occlusion finding happened. |
| **C — Filter and honesty** | The account filter (glass chrome, always-visible name), the six empty states, the pluralisation helper, the "no blame words" test | US3, US7. Depends on B's list existing; independent of D and E. |
| **D — What the engine already knows** | Per-row currency formatting, category names, transfer marking, the full VoiceOver/Dynamic Type/contrast suite | US5, US6. Ships the R18 finding's honest state: the marking is built and tested, and `detectTransfers()` stays uncalled — wiring it is the categorize slice's work (Judgement calls §2). |
| **E — Live and fast** | `AsyncStream<Void>` import-completion signal, anchor capture/restore, the perf gates wired into `make core-test`, the manual gate record, `AGENTS.md` / `.scratch/HANDOFF.md` updates | US8. Closes SC-006, SC-007, SC-008, SC-010, SC-012. Lands last because the anchor logic is only meaningful once C's filter and B's paging both exist. |

The R17 finding is **fixed in PR A** (see below), so `US1 AS-6` is a live, enabled test from the
first PR — written RED against the shipped behaviour, then turned green by the tie-break change.

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified.

**Empty — the Constitution Check passed with no violations, before and after Phase 1.**

## Judgement calls for the product owner

Four decisions were made without asking. The first two are findings in **shipped** code that the
spec did not anticipate; the second two are readings of the spec that are cheap to reverse.

### 1. 🚨 Cross-account de-duplication is non-deterministic, and it blocks US1 AS-6

**The finding.** Two *different* accounts each containing an identical row —
`2025-03-04 / COFFEE SHOP / 250.00 / Debit` — produce a supersession: one of the two rows gets
`superseded_by` set with `dedup_layer = Canonical`, so the person sees **one** coffee, not two.
Worse, running the same scenario twice on two fresh databases produced **different losers**
(account A's row the first time, account B's the second). The cause is
`load_dedup_candidates`'s `ORDER BY a.created_at, a.id, t.rowid` (`store.rs:1393`): two accounts
imported in the same second share a `created_at`, so the tie-break falls to `a.id`, which is
`lower(hex(randomblob(16)))` — random.

**Why it matters here.** US1 AS-6 asks that a transaction appearing in two accounts' statements
appears twice, attributed to both. It cannot pass. And FR-031's "the same store yields the same
sequence" holds for *reads* — the same store always reads back identically — but the *store
itself* is not reproducible from the same statements. A person could import the same two files
twice and lose a different coffee each time.

**What this plan does — ✅ RESOLVED: fix it in PR A.** Put to the repo owner, who overruled the
original recommendation: *"a finance app that reorders rows between launches is the trust problem
018 exists to avoid."*

The change is two parts. The **tie-break**: order dedup's account groups by **`accounts.rowid`**
instead of `created_at, id` — the same single account ordering R3 establishes for the whole app.
And the **source-kind guard**: cross-account de-duplication only ever compares a bank ledger
against a credit card, because `find_duplicates_in` currently folds every account against every
earlier one regardless of kind, so **two credit cards de-duplicate against each other** — which
013 never intended ("a bank-account ledger and a credit-card statement",
`specs/013-cross-source-dedup/spec.md:15`) and which hides a purchase the person actually made.

Without the guard, the tie-break alone leaves one of two identical coffees hidden —
deterministically, but still hidden — and US1 AS-6 says "neither is mistaken for, merged with, or
hidden by the other". With both, AS-6 holds as written. `US1 AS-6` is written RED first and
enabled from PR A onward; determinism is proven **across processes**, since a single-run
assertion would have passed against the defect; and the bank↔card collapse is fenced by its own
test before the guard lands, so the narrowing cannot silently delete 013's reason for existing.

**Deliberately still not answered here:** whether a matcher should understand *why* two rows are
the same purchase. The guard shipped here is blunt — two accounts **of the same kind** are now
never compared at all, so a person with two bank ledgers, one of which itemises the other's card
spends, would double-count. That is a smaller wrong than hiding a purchase a person definitely
made, and it is recorded as an open finding for the slice that owns dedup. The matcher itself,
its layers and its thresholds are untouched.

### 2. 🚨 `detectTransfers()` is never called, so FR-018 is vacuous in a real install

**The finding.** `Store::detect_transfers` exists, is tested, and is called from **no** Swift
source file — only from engine tests. Every transaction in a real install therefore has
`is_transfer = 0`, and a "Transfer" marking would never render for anyone who has not run the
test suite. The likely reason is cost: the detector is O(debits × rows) with a Jaro-Winkler
comparison in the inner loop.

**What this plan does — ✅ RESOLVED: build the marking, defer the wiring.** Put to the repo
owner, who chose to defer: transfer detection is an O(n²) pass over the whole corpus, on a path
SC-006 and SC-007 already constrain. The marking is built and fully tested against a store where
the flag is set directly; `detectTransfers()` stays uncalled.

FR-018 now carries the limitation explicitly, so the marking can never be mistaken for a working
feature: this slice **MUST NOT** claim on screen, in release notes, or in any test name that
transfers are being detected. **Wiring detection is the categorize slice's work**, and that slice
owns the question of whether it belongs in import (with a bound on its cost), in a background
pass, or behind an explicit action.

### 3. Schema v7 is an index, and the spec says "no new stored data"

Read as: an index stores no field a person or a feature can read, so it is not "stored data",
but it *is* a migration and a version bump, and the spec's sentence deserves to be tested rather
than interpreted silently. The measured cost of not having it: `USE TEMP B-TREE FOR ORDER BY`
over every live row of every account, 3.97 ms of pure engine time on the 10k corpus before any
decryption of the rows themselves, growing linearly — which makes SC-008's "≤ 20% variance
between a 200-row and a 10,000-row corpus" unreachable by arithmetic. If the product owner reads
the sentence more strictly, the feature needs a different success criterion, not a different
index.

### 4. SC-008's "≤ 20%" is restated into three testable parts

As written, "time-to-first-screenful varies by no more than 20% between a 200-row and a
10,000-row corpus" is not measurable as one number in this repo: a cold device launch is
dominated by process start and store open, both of which swamp the query. It is split into
**SC-008a** (structural — the query plan is identical and index-satisfied on both corpora,
asserted in `cargo test`), **SC-008b** (per-account first-page cost varies ≤ 20% between the two
corpora — measured today at 13%), and **SC-008c** (the device observation, on the manual gate,
recorded with build and date). The spirit — "a big history must not feel slower than a small
one" — is preserved and, for the first time, actually checkable. See research R9.
