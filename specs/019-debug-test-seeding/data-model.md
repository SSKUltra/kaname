# Data Model: DEBUG-Only Test Seeding

**Feature**: `019-debug-test-seeding` | **Date**: 2026-08-17 | **Phase**: 1

This slice adds **no persisted data model**. The store's schema stays at **v7**; nothing is
migrated, added, indexed or renamed (research [R18](./research.md#r18)). What this document
models is a **fixture**: a named, declared, synthetic history that exists only in a DEBUG build,
and the rules that make one declaration produce one store, identically, every time.

Everything below lives inside `#if DEBUG` in `ios/Sources/DebugSeed/`.

---

## 1. The store: unchanged, and deliberately so

| Fact | Value | Source |
|---|---|---|
| Schema version | **v7**, unchanged | `store.rs:41` |
| Migration added by this slice | **None** | — |
| Tables/columns/indexes added | **None** | — |
| Rust files changed | **None** | research R2 |
| FFI surface changed | **None** — no `#[uniffi::export]` added or altered | research R2 |

**Why the non-change is recorded.** The seed writes through `Store.importStatement`, which
writes only into columns v1–v7 already define. A migration would have been the tell that seeding
had stopped going through the front door and started going around it — which FR-014 and US3
forbid. The two fixture clauses this design cannot express (§6) are recorded as findings for
exactly that reason: closing them would have required a schema or an FFI change.

---

## 2. `SeedScenario` — the single source of truth

One value type, declared once, compiled into the DEBUG app **and** into the UI-test bundle
(research R11), so the rows written and the rows asserted are the same literal.

```swift
struct SeedScenario {
    /// The name a launch asks for. Lowercase, hyphen-free, stable — it is part of a
    /// contract with the test suite, not a label.
    let name: String
    /// The instant every write in this scenario is stamped with. Declared, never read
    /// from a clock (FR-023).
    let now: String                    // ISO-8601, e.g. "2026-01-15T09:00:00Z"
    /// Applied in order. The order is load-bearing: it fixes account order, the history's
    /// account tie-break, and which row wins a de-duplication (§4).
    let statements: [SeedStatement]
}

struct SeedStatement {
    let accountName: String            // synthetic; may not contain a registry literal (§5)
    let bankCode: String               // synthetic; not in the registry
    let isCreditCard: Bool
    let last4: String?
    let currency: String               // the ACCOUNT's currency; a row may differ
    let periodStart: String?           // ISO-8601 date
    let periodEnd: String              // ISO-8601 date
    /// `true` re-imports into the account created by an earlier statement of the same
    /// name, which is how a superseded row is produced (§4).
    let reimportsPrevious: Bool
    let rows: [SeedRow]                // MAY be empty — that is a declared situation
}

struct SeedRow {
    let date: String                   // ISO-8601 date; declared, never relative to today
    let description: String
    let amount: String                 // base-10 decimal STRING → Decimal. Never a Double (§3)
    let direction: Direction           // .debit / .credit — explicit, never a sign convention
    let currency: String               // the ROW's currency (FR-023 of 018: never the account's)
    let sourceCategory: String?
}
```

### What a scenario deliberately cannot say

| Not expressible | Why | Consequence |
|---|---|---|
| A transaction id, account id or statement id | `mint_id` is `lower(hex(randomblob(16)))` (`store.rs:1716`) — every id is random on every run | Assertions key on (date, description, amount, currency, account name). See §7 |
| `isDeleted` | No write path exists anywhere in `store.rs` (research R8) | Declared as a finding; deletion coverage stays engine-side in `history_live.rs` |
| `isTransfer` | Set only by `detect_transfers`, which `import-path-audit.sh` bans the app from calling — and which is `0` on every row of every real install (research R8) | Declared as a finding; the marking keeps its unit coverage |
| A cursor, a page size, a sort order, a filter state | The seed writes **data**, never interface state (FR-004) | The screen is unaware it is looking at a seeded store |

---

## 3. Money

`SeedRow.amount` is a **base-10 decimal string**, parsed to `Foundation.Decimal` and handed to
`NewImportTransaction.amount` (a `rust_decimal::Decimal` across the bridge). There is no
`Double` on the path — not in the declaration, not in the write, not in the read, not in the
formatting (`TransactionRow.formattedAmount` is `Decimal.formatted(.currency(code:))`).

**The declaration is a string rather than a `Decimal` literal on purpose**: `Decimal(1234.56)`
in Swift goes through a `Double` and is not the value it looks like. `Decimal(string:)` is
exact. This is the FR-012 path stated as a construction rule so it cannot be got wrong by
somebody adding a scenario in a hurry.

⚠️ **Amount range constraint (research R16).** Every declared amount stays **below ₹1,00,000**,
because `.currency(code:)` takes its grouping from the locale — `₹1,23,456.00` under `en_IN`,
`₹123,456.00` under `en_US` — and an assertion on a formatted string above that boundary is an
assertion about the simulator's region. A scenario that genuinely needs a large amount (the
`018/04` shape) must pin the locale *and* say so at the declaration site.

---

## 4. How a declaration becomes a store — the ordering rules that make it deterministic

The seeder applies statements **in declaration order**, one
`Store.importStatement(ImportRequest)` per statement. Three engine facts turn that into
byte-identical results across runs and machines:

| Rule | Where it is fixed | What it determines |
|---|---|---|
| `accounts` are read `ORDER BY rowid` | `list_accounts_in`, `store.rs:1661` | Account order at the front door **and** the history's account tie-break (018 R3) |
| Dedup candidates are read `ORDER BY a.rowid, t.rowid` | `store.rs:1874` (018 PR A's R17 fix) | **Which** of two matching rows is superseded |
| The history's total order is `date DESC`, account position, `transactions.rowid` | 018 R3, `SCHEMA_V7`'s index | The sequence the screen renders |
| `ImportRequest.now` is caller-supplied | `store.rs:406`; the core reads no clock | Every timestamp; FR-023 |

So: **declaration order is the only ordering input, and it is written down.** Reordering the
`statements` array is a semantic change to the fixture, not a formatting one, and the contract
says so.

### Producing a superseded row — two routes, both the engine's own

1. **Re-import.** Declare a statement with `reimportsPrevious: true` carrying rows already
   present in that account. The engine supersedes the held rows in favour of the new ones
   (016's re-import supersession; `ImportOutcome.rows_superseded` counts them).
2. **Cross-source de-duplication.** Declare one **bank ledger** account and one **credit card**
   account sharing an identical row. ⚠️ After 018 PR A's source-kind guard
   (`store.rs:1448`), cross-source dedup **only ever compares a bank against a card** — two
   synthetic cards produce no supersession at all, silently. A scenario that wants this route
   must declare `isCreditCard: false` on one side and `true` on the other.

### ⚠️ The corpus must not de-duplicate itself

018 R20 records this the hard way: a synthetic corpus built from repeated rows collapses under
its own dedup and comes out short. Here the rule is precise —

> Exactly the rows a scenario *intends* to collide may collide. Every other row must differ from
> every row in every other account by description **and** amount, or by date.

`deep`'s generator varies the description index and the amount per row for this reason, and the
scenario's expected live count is the check that the rule was honoured (§7).

---

## 5. Synthetic content — enforced, not promised

| Rule | Enforced by |
|---|---|
| No account name, bank code, description or category may contain a **registry literal** (an issuer `id`, `display_name`, or a reader's `BANK_CODE`) | `scripts/import-path-audit.sh` § bank-literal audit — it scans **all** of `ios/Sources`, which is where `DebugSeed/` lives (research R7). `make import-audit` fails the build |
| No networking symbol on any seeding path | the same script's networking audit, same scan root — FR-033 / SC-011 for free |
| No real statement, fragment, merchant record or account identifier | `AGENTS.md` § *Reading a statement*; SC-012 |
| No wording that claims transfers are detected | the same script's transfer-claim audit, which also covers `ios/Tests` |

**Naming convention** (so the above is obvious at the declaration site, not discovered at the
gate): accounts are `SYNTHETIC BANK ONE` / `SYNTHETIC CARD TWO`; bank codes are `SYNTH_BANK` /
`SYNTH_CARD`; descriptions are `SYNTHETIC MERCHANT NN`. Last-4s are `0001`…`0009`, matching the
convention `make perf-corpus` already uses (`gate/01-icici-0006.pdf` → `···· 0006`).

⚠️ `bank_code` is looked up by `categorize_account_in` against `source_category_map`
(`store.rs:1286`). A synthetic code matches nothing at the T1 stage — which is *how* a scenario
gets uncategorized rows. Categorized rows come from a description that a default T3 rule matches.

---

## 6. The two named scenarios

### `small` — six rows, one account

| Property | Value | Why |
|---|---|---|
| Accounts | 1 (`SYNTHETIC BANK ONE`, `···· 0006`) | Filterable to alone |
| Live rows | **6** | `018/03`: at XXXL the end of a 10,000-row list is hundreds of flicks away. Six rows is two flicks |
| Currencies | 1 (`INR`) | Not what this scenario is asking about |
| Dates | 6 consecutive days in a **prior calendar year** | So a group heading must carry its year (018 FR-035, gate G4) |
| Answers | G1 (truncation), G2 (occlusion, research R10), G5 (filter chrome), G8 (pinned heading) | |

### `deep` — 160 rows, three accounts

| Property | Value | Why |
|---|---|---|
| Statements | 4 (one is a re-import) | The fourth produces the supersession |
| Accounts | 3: a bank ledger, a credit card, and one whose statement declares **zero** rows | FR-008; `EmptyKind.accountStatementEmpty` |
| Live rows | **160** across the two populated accounts | `pageSize` is 50 → four pages, last one partial. FR-009, SC-017 |
| Currencies | **2** (`INR`, `USD`), on rows of the same account | 018 FR-023: the row's currency, never the account's. No figure may combine them |
| Same-date collision | ≥ 1 date carrying rows in **two** accounts | FR-008; exercises the account tie-break |
| Superseded rows | ≥ 2 — one by re-import, one cross-source (bank ↔ card) | FR-008 |
| Categorized / uncategorized | both | FR-008 |
| Deleted rows | **none** — no write path | Finding, §7 |
| Transfer-flagged rows | **none** — would be a store no person can have | Finding, §7 |
| Answers | paging (SC-017), the filter's four states (FR-040), the currency rule, ordering across a page boundary | |

### The empty states these two make reachable

| `EmptyKind` case | Reachable in an automated run after this slice? | How |
|---|---|---|
| `noTransactionsAnywhere` | ✅ | `deep`, filtered off, if every account's statement were empty — declared as a third scenario only if a task needs it; otherwise via the zero-row account with the filter |
| `nothingToShowAnywhere` | ✅ | a store whose only rows are superseded |
| `accountStatementEmpty(name:)` | ✅ | `deep`'s zero-row account, filtered to |
| `accountNothingToShow(name:)` | ✅ | an account whose every row is superseded (deletion is not needed for this) |
| `accountEmptyOthersHaveRows(name:_:)` | ✅ | `deep`, filtered to the zero-row account while others have rows |
| **`nothingImported`** | ⛔ **No** | The front door hides the route to the list precisely when this state would apply. See §7 and research R9 |

---

## 7. Findings this model records rather than resolves

Three, each traced in `research.md` and surfaced for decision in `plan.md` § *Judgement calls*.

1. **`is_deleted` has no write path** (R8). `store.rs` never `UPDATE`s it; only engine tests set
   it with raw SQL. FR-008's "deleted rows" clause is not expressible, and adding an export to
   express it would ship in Release (R2). Deletion coverage stays where it already is:
   `core/tests/history_live.rs` L1/L4/L5.
2. **Transfer-flagged rows must not be seeded** (R8). `detectTransfers` is banned in the app by
   an existing scan, and every row of every real install has `is_transfer = 0`. A seeded
   transfer would be a screen no person can have.
3. **`EmptyKind.nothingImported` stays unreachable by an automated run of the shipping route**
   (R9). The front door's link condition and the list's empty-state condition read the **same**
   `accountSummaries()` call, so the two can never disagree. Recommended remedy: host the real
   view in `KanameTests` with the existing double, which gives the branch its first automated
   execution against a rendered screen — but **not** a `performAccessibilityAudit`, which is an
   `XCUIApplication` API.

None of the three is caused by this slice, and none is worked around in it.

---

## 8. Lifecycle of one seeded launch

```
App.init()
  └─ #if DEBUG DebugSeed.applyIfRequested() #endif
       ├─ read ProcessInfo.environment["KANAME_SEED_SCENARIO"]
       │    └─ absent → return. Nothing is read, deleted, opened or written.   (FR-005, FR-022)
       ├─ resolve the name against the declared set
       │    └─ unknown → fatalError("…")  → the app never reaches the foreground (FR-006, R13)
       ├─ delete kaname.db and its -journal / -wal / -shm sidecars              (FR-020, R12)
       │    └─ the Keychain key is NOT touched                                  (FR-017)
       ├─ StoreProvider.shared()   ← first open of the process; fresh, encrypted, app's own key
       ├─ for each SeedStatement, in order: store.importStatement(request)      (FR-014)
       │    └─ any throw → fatalError("…")                                      (FR-006)
       └─ return — the history is complete before any View body is evaluated    (FR-002)

WindowGroup { RootView() }   ← the ordinary app, unaware, reading the ordinary store
```

**Idempotence and isolation** (US4): the reset is unconditional *within* a seeded launch, so
seeding the same scenario ten times on a container that is never cleaned produces the same store
ten times (SC-010). A non-seeded launch immediately afterwards deletes nothing and finds
whatever the last seeded run left — which is why the *first* thing a non-seeded assertion does
is run after `make ios-test`'s uninstall, and why the suite's non-seeded tests are the ones that
already exist.

---

## 9. What a test derives from the declaration

| Assertion | Derived from | Rule |
|---|---|---|
| Row count on screen | `scenario.expectedLiveRowCount` — declared rows minus declared supersessions | Also equals `AccountSummary.liveTransactionCount`, so the engine's count and the screen's rows are compared (R20) |
| Each row's content | `TransactionRow.accessibilityLabel` built from the same declaration | One combined element per row (`TransactionRowView` uses `.accessibilityElement(children: .combine)`) |
| Order | The declaration's rows sorted by the engine's total order, computed once in the fixture | Never re-sorted in the test — the same rule `import-path-audit.sh` bans under `ios/Sources/Transactions/` |
| Which rows must be **absent** | The declared superseded rows | US1 AS-3's "and nothing else is" |

⚠️ **No assertion may name an id** (§2). ⚠️ **No assertion may compute a total** — a scenario
declares two currencies on purpose, and a test that summed them would be the defect
`import-path-audit.sh`'s aggregate scan exists to prevent, written in the test target where that
scan does not reach.
