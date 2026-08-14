# Contract — Platform Seams (`018-transaction-list`)

**Date**: 2026-08-14 | **Layer**: `ios/Sources/Transactions/`, `ios/Sources/Import/`
**Depends on**: [`engine-history.md`](./engine-history.md) — must land first.

Five seams. Each exists so that a rule this slice cares about is enforced by a type rather than
remembered by a reviewer, and so that the automatable half of every success criterion can be
checked in `ios/Tests` with no screen rendered (FR-074, SC-013).

> ⚠️ **`ios/Sources/Import/ImportService.swift` is exactly 400 lines** — the SwiftLint `--strict`
> file limit. Nothing in this slice may be added to it. The one line that changes there is the
> count inside `importedAccounts()`. Everything new lives under `ios/Sources/Transactions/`.

---

## 0. The shared store — a correctness requirement, not tidiness

```swift
/// Both services take the same `Store`. One `Store` per process.
final class StoreProvider {          // ios/Sources/Persistence/
    static func shared() throws -> Store
}
```

`Store` wraps a `std::sync::Mutex<Connection>`. Two `Store` instances over the same file would
be two connections with two independent locks, and a page read could land in the middle of
`import_statement`'s transaction — SQLite would either block or return `SQLITE_BUSY`, and
FR-054's "never a partially-written statement" would depend on timing. One `Store` makes the
existing mutex serialise reads against the atomic import, and FR-054 becomes structural.

`ImportService` and `TransactionHistoryService` are constructed with an injected `Store`, so
tests can hand them a temporary one.

---

## 1. `TransactionHistoryService` — the engine's only caller

```swift
actor TransactionHistoryService {
    init(store: Store)

    /// One page. `cursor == nil` starts at the newest end.
    func page(accountID: String?, cursor: HistoryCursor?, limit: UInt32) async throws
        -> HistoryPage

    /// Every account, in the front door's order, with live counts.
    func accountSummaries() async throws -> [AccountSummary]
}
```

**Contract**

| # | Rule | Requirement |
|---|---|---|
| H1 | An `actor`, so every engine call is off the main thread. No `Store` method is ever called from a view body or a `@MainActor` initialiser. | FR-058, SC-006 |
| H2 | It performs **no** filtering, sorting, grouping, de-duplication or counting of its own. It is a transport. | FR-045 — one place for the rule |
| H3 | It has no cache. The view model owns accumulated pages. | FR-056 — one place for scroll state |
| H4 | A thrown `StoreError` is mapped to a `TransactionListError` carrying **no** description, amount, date or account identifier. | FR-063, SC-016 |
| H5 | It imports nothing from `Import/` and `Import/` imports nothing from it, except through `StoreProvider`. | file-size and layering |

**Test double.** A `TransactionHistoryReading` protocol with the same two methods, so the view
model's tests need no SQLCipher store. The concrete actor is exercised by an integration test
against a real temporary store.

---

## 2. `TransactionListViewModel` — where scroll, filter and grouping live

```swift
@MainActor @Observable
final class TransactionListViewModel {
    enum State: Equatable { case loading, showing, empty(EmptyKind), unavailable }
    enum AccountFilter: Equatable { case all, account(id: String, name: String, last4: String?) }

    private(set) var state: State
    private(set) var groups: [DateGroup]
    private(set) var filter: AccountFilter        // always `.all` at init — FR-041
    private(set) var isLoadingMore: Bool

    init(history: TransactionHistoryReading, clock: () -> Date, pageSize: UInt32 = 50)

    func onAppear() async
    func loadMoreIfNeeded(currentRowID: String) async
    func setFilter(_ filter: AccountFilter) async
    func clearFilter() async
    func refreshAfterImport() async               // FR-053
}
```

**Contract**

| # | Rule | Requirement |
|---|---|---|
| V1 | `filter` is `.all` at `init` and is never written to `UserDefaults`, the store, or a scene-restoration payload. A test asserts `UserDefaults` is untouched across a filter change. | FR-041 |
| V2 | `setFilter`/`clearFilter` discard the cursor and every accumulated row, then load page 1. No row of the previous population can survive. | FR-040 |
| V3 | `refreshAfterImport` preserves `filter` and the captured anchor row id. | FR-056, SC-010 |
| V4 | Date grouping is folded **incrementally** over the flat page sequence: a page boundary that falls inside a date appends to the open group rather than starting a second one with the same heading. A test pages at size 1 across a 5-row date and asserts one group. | FR-033, R13 |
| V5 | `loadMoreIfNeeded` is idempotent per cursor — two calls before the first returns issue one request. | FR-044, SC-007 |
| V6 | The current year comes from the injected `clock`, never `Date()` inside a formatter, so the year-suffix rule is testable at a fixed date. | FR-035 |
| V7 | `groups` has no total, subtotal, balance or average field, and no code path computes one. | FR-025, FR-026 |
| V8 | `EmptyKind` is chosen by a pure function of `[AccountSummary]` and `filter` — the six-row table in `data-model.md` §6. | FR-047–FR-051 |

---

## 3. `TransactionRowLayout` — the accessibility decision, extracted so it can be proved

```swift
/// The layout choice for one row, as data. Pure — no View, no environment, no rendering.
struct TransactionRowLayout: Equatable {
    let axis: Axis                       // .horizontal | .vertical
    let descriptionLineLimit: Int
    let accountNameLineLimit: Int
    let amountYields: Bool               // always false

    init(dynamicTypeSize: DynamicTypeSize)
}
```

**Contract**

| # | Rule | Requirement |
|---|---|---|
| A1 | `amountYields == false` for **all twelve** `DynamicTypeSize` cases. A test iterates `DynamicTypeSize.allCases`. | FR-021, FR-065 |
| A2 | `axis == .vertical` iff `dynamicTypeSize.isAccessibilitySize`. Verified present in the iOS 26.5 SDK's `SwiftUICore.swiftinterface`. | FR-021, FR-066 |
| A3 | `descriptionLineLimit` shrinks before `accountNameLineLimit` — the description yields first, the account name second. | FR-021 |
| A4 | The row view is **not** `LabeledContent`. `LabeledContent` chooses its own axis; that self-collapsing two-column shape is what the parked `StaticText '1'` at `{32, 724}` occlusion finding is consistent with. | R12, the parked finding |
| A5 | The amount uses `.fixedSize(horizontal: true, vertical: false)` + `.layoutPriority(1)`. **Never** `minimumScaleFactor` — shrinking an amount to fit is truncation with extra steps. | FR-021 |
| A6 | The amount uses `.monospacedDigit()`. | FR-027 |

Why this seam exists: SC-013 requires the automatable half of the accessibility criteria to be
covered in the unit target, and no unit test can measure a rendered frame. Extracting the
*decision* makes the decision testable; the *rendering* stays on the manual gate.

---

## 4. The row and screen views

```
ios/Sources/Transactions/
  TransactionListView.swift        // NavigationStack destination, List + Section
  TransactionRowView.swift         // one row, driven by TransactionRowLayout
  TransactionListViewModel.swift
  TransactionHistoryService.swift
  TransactionListStrings.swift     // every user-visible string, one file
  TransactionListModels.swift      // TransactionRow, DateGroup, EmptyKind, AccountFilter
```

**Contract**

| # | Rule | Requirement |
|---|---|---|
| W1 | Glass only through `.glassEffect(...)` / `GlassEffectContainer` / `.buttonStyle(.glass)`. No `.ultraThinMaterial`, no `.background(.regularMaterial)`, no hand-rolled blur. `make import-audit` fails the build on all three. | Constitution IV |
| W2 | No `#available(iOS 26, *)`. Deployment target is 26.0; the check is dead code that `import-audit` rejects. | Constitution IV |
| W3 | A bottom-anchored control uses `.safeAreaBar(edge: .bottom)`, not `.safeAreaInset`. Verified present in the iOS 26.5 SDK. `RootView.swift:15` still uses `.safeAreaInset` and moves in the same PR. | R12, the parked occlusion finding |
| W4 | Every user-visible string comes from `TransactionListStrings`. A test asserts no string literal in a view body. | FR-052, FR-019 |
| W5 | Direction is conveyed by a word, and colour is never the only carrier. A test asserts the accessibility label contains "debit" or "credit". | FR-013, FR-015 |
| W6 | No network symbol. `import-audit`'s networking scan is widened from `ios/Sources/Import` to `ios/Sources` in the same PR that creates this directory (research R19). | Constitution I, FR-062 |

---

## 5. The import-completion signal

```swift
extension ImportService {
    /// Emits exactly once per statement that was actually committed. Nothing is emitted for a
    /// failed, cancelled or duplicate-rejected import.
    var importsCompleted: AsyncStream<Void> { get }
}
```

**Contract**

| # | Rule | Requirement |
|---|---|---|
| I1 | Emitted **after** `import_statement` returns successfully — i.e. after the transaction committed — so a subscriber can never observe a partial statement. | FR-054, SC-010 |
| I2 | A failed or cancelled import emits nothing, so a filtered, scrolled list does not twitch. | FR-055 |
| I3 | It carries `Void`. No row, count or account crosses it; the subscriber re-reads through the engine, so there is still exactly one source of the population. | FR-045 |
| I4 | The subscription is owned by the view's `.task`, so it is cancelled with the screen. | — |
| I5 | The front door's `importedAccounts()` re-reads on the same signal, so the count and the list can never be refreshed from different moments. | FR-006, FR-057 |

**Where the count comes from now.** `ImportService.importedAccounts()` (lines 126–141) currently
does one `list_transactions(account_id)` per account and then `.filter(\.isLive).count` in Swift
— an N+1 that materialises every row of every account across the FFI to produce a number. It
becomes one `account_summaries()` call. Measured on the 10,000-row corpus: **43.8 ms of Rust
time versus 0.99 ms**, before any bridging cost — a 45× reduction, and it deletes the only place
where the count and the list could be computed by different code.

`StoredTransaction.isLive` (`ImportModels.swift:79–89`) **stays**, with its ⚠️ comment updated:
it is no longer the production count, it is the cross-language mirror of the engine's `LIVE`
constant, and a test asserts the two agree on a corpus containing deleted and superseded rows.

---

## 6. Navigation

| # | Rule | Requirement |
|---|---|---|
| N1 | The list is a `NavigationStack` destination pushed from `RootView`'s existing stack — not a sheet, not a tab. A sheet would make FR-056's scroll preservation a dismissal problem. | FR-001 |
| N2 | Each `ImportedAccountsView` row becomes a `NavigationLink` that pushes the list pre-filtered to that account. The pre-filter is the same `AccountFilter` value the in-screen filter sets — one code path. | FR-036, FR-042 |
| N3 | A toolbar item pushes the unfiltered list, so the combined history is reachable without picking an account first. | FR-001, FR-043 |
| N4 | Back from the list returns to the front door with its counts re-read, so a count changed by an import in flight is not stale. | FR-057 |
