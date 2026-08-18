# Contract: Platform — Categorize

**Feature**: 020-categorize | **Surface**: `ios/Sources/Categorize/` + four edited files
**Sources**: [`spec.md`](../spec.md), [`data-model.md`](../data-model.md), [`engine-categorize.md`](./engine-categorize.md)

⚠️ **Placement is contractual.** All new platform code lives in **`ios/Sources/Categorize/`**.
`ios/Sources/Import/ImportService.swift` is at **398** lines against a hard 400-line SwiftLint
`--strict` limit (FR-073) — **no line may be added to it by this slice**.
`TransactionListModels.swift` is at 332 and is the next file at risk, which is why
`TransactionScope` and the picker's grouping live in `Categorize/` rather than beside
`AccountFilter`.

⚠️ **`sources: ["Sources/**"]` is resolved at generation time.** A new file without `make ios-gen`
is compiled by nothing, and a suite that never ran reports success. This bit 019 twice.

---

## 1. The service seam

```swift
// Categorize/CategorizeService.swift
actor CategorizeService {
    func correct(_ id: String, to: CategoryRef?, remember: Bool) async throws -> CorrectionOutcome
    func previewMemory(_ portion: String) async throws -> MemoryImpact
    func applyMemory(_ portion: String, expecting ids: [String]) async throws -> UInt32
    func uncategorizedCount() async throws -> UInt32
    func categories() async throws -> [Category]
}
```

**The seam's whole rule**: every method is a thin pass-through to one engine call. It **must not**
filter, count, sum, group, sort by a derived key, or take a second opinion about anything the
engine returned (FR-076, FR-077, FR-078). `uncategorizedCount()` in particular returns the
engine's number verbatim — Q3-C exists because 018 deliberately moved the front door's count out
of Swift into SQL, and this is where it would creep back.

Mechanically watched by `import-path-audit.sh` scans 5 (second opinion), 6 (filter persistence),
7 (aggregates) and 8 (`.tint`), **once their scope is widened from `ios/Sources/Transactions/` to
include `ios/Sources/Categorize/`** (judgement call §6). Widening the scope of a scan is not
weakening it, so FR-056/SC-022 hold.

---

## 2. Navigation

```swift
// Categorize/TransactionScope.swift
struct TransactionScope: Hashable, Codable { var filter: AccountFilter; var uncategorizedOnly: Bool }
```

`RootView.swift:16-33`'s `.navigationDestination(for: AccountFilter.self)` becomes
`for: TransactionScope.self`. The nav **value type** changes; the nav **behaviour** does not — the
same `NavigationStack`, the same push, the same back. 018's `AccountFilter` is reused unchanged
rather than reimplemented.

**Rule.** There is exactly one destination for the transaction list. A second
`.navigationDestination` for a "just uncategorized" list would give the same screen two identities
and two back-stack behaviours.

---

## 3. The row becomes tappable

Transaction rows are **not tappable today** — there is no `Button`, `NavigationLink` or
`.onTapGesture` anywhere in `ios/Sources/Transactions/`, and `TransactionRowView` is one combined
accessibility element (`.accessibilityElement(children: .combine)`, lines 36-38).

**Rules.**

| ID | Rule | FR/SC |
|---|---|---|
| R1 | The row becomes a `NavigationLink` to the detail surface. | FR-003 |
| R2 | The row's combined accessibility element is **preserved** — the sentence VoiceOver reads must not fragment into per-label pieces because the row gained a link. | FR-060, SC-016 |
| R3 | The row's visual layout does not change. Adding a chevron or an inset would silently redo 018's list. | FR-046 |
| R4 | The tap target is the full row, ≥44×44pt. | FR-062 |

---

## 4. The detail surface — `TransactionDetailView.swift`

| ID | Rule | FR/SC |
|---|---|---|
| D1 | Shows the transaction's own facts — description, amount, date, account — and its current category, or the app's one word for having none. | FR-001 |
| D2 | The word for "no category" comes from `TransactionListStrings.uncategorized` and is **never redeclared**. | FR-002, SC-002 |
| D3 | Shows how the app currently understands this transaction **without engine vocabulary** — no `T1`, `T2`, `stage`, `rule`, `heuristic`, `merchant map`, `provenance`, `tier`. | FR-029, SC-007 |
| D4 | Money uses the existing `Decimal` formatting and tabular figures carried from 018. | Constitution II |
| D5 | Liquid Glass unconditionally — no `#available(iOS 26, *)`, no `.ultraThinMaterial`. `.glassProminent` only via `Theme.swift`. | FR-063, SC-021 |
| D6 | One primary action: change the category. It is reachable without scrolling at default Dynamic Type. | FR-004 |

---

## 5. The picker — `CategoryPickerView.swift` + `CategoryCatalog.swift`

| ID | Rule | FR/SC |
|---|---|---|
| K1 | Lists every category the engine knows, grouped by `Category.classification` (Spend / Income / Investment / Transfer / CcPayment / Refund). The **engine's** taxonomy; the view invents none. | FR-016 |
| K2 | `CategoryCatalog.grouped(_:)` is **pure** — `[Category]` in, grouped array out. No engine call, no state. Unit-tested in `ios/Tests` without a simulator. | FR-076 |
| K3 | The current category is marked, resolved by `HistoryRow.category_id`, never by display-name match. | FR-005 |
| K4 | "No category" is an offered choice, not only an implicit state. | FR-007 |
| K5 | Choosing dismisses the picker and the new category is visible on the detail surface without a manual refresh. | FR-006, SC-003 |
| K6 | Grouping and ordering are deterministic — the same catalog renders in the same order every launch. | FR-017 |
| K7 | Reachable and operable at XXXL, in Light and Dark, by VoiceOver, with ≥44pt targets. | FR-060–FR-062, SC-016 |

---

## 6. The memory offer — `MemoryOfferView.swift`

| ID | Rule | FR/SC |
|---|---|---|
| M1 | After a correction, the app states — in the person's words, showing the derived merchant portion — what it will remember. | FR-026, FR-026a |
| M2 | The offer can be **declined**, and declining leaves the correction fully intact and protected. | FR-028 |
| M3 | When derivation returns nothing, or the correction was to *no category*, the app says plainly there is nothing to remember and offers no memory. It **must not** show an empty or degenerate portion. | FR-027d, spec amendment §3 |
| M4 | The portion shown is `merchant_portion(narration)` from the engine — the Swift side derives nothing. | FR-021, FR-076 |
| M5 | The word "remember" and its neighbours never leak engine vocabulary. | FR-029 |

---

## 7. The second action — `SecondActionView.swift`

🚨 **This is the surface most able to become something the spec forbids.** Q1-D's second action
applies exactly one memory — the one just formed.

| ID | Rule | FR/SC |
|---|---|---|
| S1 | States the blast radius **before** the person agrees: how many transactions, and which accounts, from `MemoryImpact`. | FR-035a, FR-035c, SC-026 |
| S2 | Offers **no choice of which transactions**. No checkboxes, no multi-select, no "select all". | FR-035b, SC-028 |
| S3 | The counts and accounts shown are `MemoryImpact`'s, unmodified. The view does not count, filter or re-derive. | FR-043, FR-078 |
| S4 | On confirm, calls `applyMemory(portion, expecting: impact.transactionIds)` — the ids from the preview it showed, unmodified. | FR-035f |
| S5 | A `StaleSet` error is surfaced as a person-legible "things changed, take another look", and **nothing is written**. It is not retried silently with a fresh set. | FR-035f, SC-027 |
| S6 | Rows the person corrected by hand are neither counted nor changed — enforced in the engine; the view merely displays the truth. | FR-035d, SC-031 |
| S7 | Declining leaves the memory formed and the correction intact. Only the bulk application is declined. | FR-028 |

⚠️ **S2 is a UI rule, but it is not the enforcement.** The enforcement is engine-side set equality
(`engine-categorize.md` §2.4, test M7). A UI without a checkbox proves nothing about a future UI.

---

## 8. The entry point — `UncategorizedEntryPoint.swift`

| ID | Rule | FR/SC |
|---|---|---|
| E1 | A single door to the uncategorized worklist, visible from the app's front door. | FR-041a |
| E2 | Its count is **store-wide** and comes from `uncategorizedCount()` — one engine call, no Swift arithmetic, no summing of `AccountSummary`. | FR-041b, FR-043, SC-029 |
| E3 | When the count is zero the door says so in a person's words rather than showing "0". | FR-042b, SC-011 |
| E4 | Tapping pushes `TransactionScope(filter: .all, uncategorizedOnly: true)`. | FR-038 |
| E5 | The count refreshes after a correction or a memory application, without a manual reload. | SC-030 |

---

## 9. The list, narrowed — edits to `ios/Sources/Transactions/`

| ID | Rule | FR/SC |
|---|---|---|
| L1 | `TransactionListViewModel` carries `uncategorizedOnly` into `HistoryQuery`. It **never** filters a page it received. | FR-038, FR-076, SC-024 |
| L2 | The narrowing composes with the account filter — both axes, one query. | FR-039 |
| L3 | Paging, cursors and the infinite-scroll behaviour are 018's, unchanged. | FR-040, FR-046 |
| L4 | `EmptyKind.decide(summaries:filter:uncategorizedOnly:)` stays a **pure function**, gains `allAnswered` and `accountAnswered`, and every combination in [`data-model.md`](../data-model.md) §6 is either reachable-and-tested or named-with-its-structural-reason. | FR-042a, FR-042b |
| L5 | **No new `AccountSummary` field.** "Live rows exist but the narrowed page is empty" ⇒ all answered; the inference is exact. | FR-078 |
| L6 | With the narrowing off, the list is byte-identical to 018 in behaviour and appearance. | FR-046, SC-023 |

---

## 10. Strings — `CategorizeStrings.swift`

| ID | Rule | FR/SC |
|---|---|---|
| T1 | Every new string is declared here. No string literal in a view body. | FR-064 |
| T2 | `uncategorized` is **referenced** from `TransactionListStrings.uncategorized` (`TransactionListStrings.swift:65`), never redeclared. Two spellings of that word is exactly the defect FR-002 exists to prevent. | FR-002, SC-002 |
| T3 | No string contains engine vocabulary. A unit test asserts the whole table against a banned-word list. | FR-029, SC-007 |
| T4 | Every string reads as something a person would say about their own money. | FR-064 |

---

## 11. Test contract

### 11.1 Unit — `ios/Tests` (no simulator, no seeding)

| # | Assertion |
|---|---|
| U1 | `CategoryCatalog.grouped` groups by classification, deterministically, for an empty catalog, a single-classification catalog and the full one. |
| U2 | `EmptyKind.decide` returns the right case for **every row** of [`data-model.md`](../data-model.md) §6 — including the states a seed cannot construct. This is where those states get covered. |
| U3 | `CategorizeStrings` contains no banned engine vocabulary (T3). |
| U4 | `TransactionScope` round-trips through `Hashable`/`Codable` — two scopes differing only in `uncategorizedOnly` are not equal and do not collide in the nav stack. |

### 11.2 UI — `ios/UITests`, over the seeded scenarios

⚠️ **`app.launchEnvironment["KANAME_SEED_SCENARIO"]` — the bare key.** The `TEST_RUNNER_` prefix is
for app-hosted unit tests and is silently never delivered to a UI test. Launch is wrapped by
`ios/UITests/SeededLaunch.swift`. Scenarios are declared in
`ios/Sources/DebugSeed/SeedScenarios.swift:116`.

| # | Assertion | Scenario |
|---|---|---|
| X1 | Tap a row → the detail surface appears with that row's facts. | `basic` |
| X2 | Change a category → the detail surface and the list both show the new one without a manual refresh. | `basic` |
| X3 | Set a category to "no category" → the row leaves the worklist. | `unfiled` |
| X4 | The memory offer names the merchant portion and can be declined; the correction survives the decline. | `repeated` |
| X5 | The second action states a count **and** account names before confirmation; there is **no** multi-select control on the screen. | `crossing` |
| X6 | The entry point shows a count, and after correcting every row it says the worklist is finished rather than "0". | `unfiled` |
| X7 | The narrowed list shows only unanswered rows and composes with an account filter. | `unfiled` |
| X8 | Accessibility audit — every new surface, at default and XXXL, Light and Dark, zero findings for the audit types that run. | all |

⚠️ **Traps these tests must not walk into**, all from `AGENTS.md` § *Seeding a screen with data*:
a `List` renders a **screenful**, not a list — never assert a total by counting cells; a row's
sentence hangs on a `StaticText` **inside** the cell, and a date heading is a cell too; a seeded
store **outlives** the suite that wrote it — reset with the `empty` scenario; pin the locale to
`en_IN` and keep amounts under ₹1,00,000; two credit cards **never** de-duplicate (the source-kind
guard compares a ledger against a card and nothing else), which is why `crossing` needs a
ledger+card pair — and therefore also why its rows must differ in amount or date, or dedup will
eat one and the blast radius will be wrong before anyone tested it.

⚠️ **A label cannot demonstrate a truncation** — XCUITest reports a `Text`'s string, not its
glyphs. If a long category name must be shown not to clip, geometry has to carry it. ⚠️ **A wall
clock in a UI test measures the machine** (`019/04`), which is why the spec carries no timing
success criterion and why none of X1–X8 asserts a duration.

### 11.3 Accessibility outside `make ios-test`

⚠️ **Increase Contrast cannot be set from XCUITest.** The only mechanism here is `make a11y-sweep`
(`xcrun simctl ui "iPhone 16" increase_contrast enabled`), which is **not** part of
`make ios-test`. And `.contrast` is excluded from every audit because of `019/01`. FR-065 is
therefore satisfied across **two** targets and SC-016's "zero findings" is scoped to the audit
types that actually run. Spec amendment §5.

---

## 12. What does **not** change

- `ImportService.swift` — **zero lines**. FR-073.
- 018's list behaviour, appearance, paging and cursors with the narrowing off. FR-046.
- `TransactionListStrings.uncategorized` — referenced, not moved, not copied.
- `AccountFilter` — reused, not replaced.
- `AccountSummary` — no new field.
- `Theme.swift` — `.glassProminent` stays confined to it; nothing in `Categorize/` uses it directly.
- The app still calls `detectTransfers` from **nowhere** — this slice does not wire it up (018 R18
  stays open); it only closes the engine-side hole where it could erase a person's decision.
