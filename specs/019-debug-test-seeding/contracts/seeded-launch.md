# Contract: The seeded launch

**Feature**: `019-debug-test-seeding` | **Phase**: 1
**Interface kind**: a launch-time contract between an automated run and a DEBUG build of the app.

This is the only interface this slice exposes, and it exists in **DEBUG builds only**. There is
no API, no URL, no file format and no user-facing affordance. `release-absence-audit.md` is the
contract that proves this one is absent from Release.

---

## 1. The request

```swift
let app = XCUIApplication()
app.launchEnvironment["KANAME_SEED_SCENARIO"] = "small"
app.launch()
XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))   // ← also the failure detector
```

| Property | Value |
|---|---|
| Channel | `XCUIApplication.launchEnvironment` — the app process's environment |
| Key | `KANAME_SEED_SCENARIO` |
| Value | A declared scenario **name**, exactly (`small`, `deep`) |
| Scope | One launch. Nothing persists |
| Read by | `ProcessInfo.processInfo.environment`, inside `#if DEBUG` |

⚠️ **This is not the `TEST_RUNNER_` rule.** `xcodebuild` forwards only `TEST_RUNNER_`-prefixed
variables to the **test runner** process, stripping the prefix — which is what `make
reference-check` and `make perf-corpus` rely on for *unit* tests hosted in the app.
`launchEnvironment` is set on the app process by XCUITest and needs no prefix. Using the wrong
one leaves the variable undelivered and the suite silently unseeded.

### Composing with the other axes

All are disjoint channels and may be set together (spec § *Edge Cases*):

| Axis | Channel |
|---|---|
| Seed | `app.launchEnvironment["KANAME_SEED_SCENARIO"]` |
| Content size | `app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]` |
| Appearance | `XCUIDevice.shared.appearance = .dark` |
| Increase Contrast | `xcrun simctl ui … increase_contrast enabled` — `make a11y-sweep` |
| Locale (research R16) | `app.launchArguments += ["-AppleLocale", "en_IN", "-AppleLanguages", "(en)"]` |

---

## 2. The guarantees

| # | Guarantee | Requirement |
|---|---|---|
| L1 | When the variable is **absent**, nothing is read, deleted, opened or written by the seeding path. The app behaves exactly as it does today | FR-005, FR-022 |
| L2 | When it is **present and recognised**, the declared history is complete in the app's own encrypted store **before** the first `View` body is evaluated | FR-002 |
| L3 | The store is reset to a known state first: `kaname.db` and its `-journal` / `-wal` / `-shm` sidecars are deleted. The Keychain key is **not** touched | FR-020, FR-017 |
| L4 | Every row is written by `Store.importStatement` — the same call `ImportService` makes | FR-014 |
| L5 | When the name is **unrecognised**, or any write throws, the process terminates before reaching the foreground. It never degrades to an empty or partial app | FR-006, SC-016 |
| L6 | Nothing is seeded twice in one launch, and a seed on top of a seeded store is the reset plus a fresh seed — not an accumulation | FR-020, US4 AS-2 |
| L7 | No route to this exists for a person, in any build: no menu, gesture, toggle, URL, shared file or pasteboard | FR-031 |
| L8 | Zero network I/O on this path | FR-033, SC-011 |
| L9 | No transaction field is written to a log or diagnostic by anything on this path | FR-034 |

---

## 3. The failure contract

**A failed seed is a failed launch.** There is no error screen, no fallback and no log channel,
because `App.init()` has no UI and no way to report to a test.

```swift
fatalError("KANAME_SEED_SCENARIO=\(name): no such scenario. Declared: small, deep")
```

The run detects it through the assertion **every existing UI test in this repository already
makes**: `XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))`. Nothing new has to be
written to notice.

Because `import_statement` is one SQLite transaction, a *partial* write cannot commit: a throw
rolls the whole statement back, and the `fatalError` makes the non-event observable.

---

## 4. Assertions — written before any implementation (Constitution V)

Named here so the task list can write them RED first. `L*` = launch behaviour, `S*` = seeded
screen, `D*` = determinism, `E*` = empty states, `A*` = accessibility.

### Launch behaviour

| ID | Assertion | Story |
|---|---|---|
| L1 | A launch with **no** `KANAME_SEED_SCENARIO` reaches the front door's empty state and offers no route to the list — i.e. today's `testAFreshInstallOffersNoRouteToAnEmptyTransactionList` still passes, unchanged | US1 AS-5, FR-005 |
| L2 | A launch with `KANAME_SEED_SCENARIO=small` reaches the foreground and the front door shows the seeded account | US1 AS-1 |
| L3 | No document picker is ever presented on a seeded launch | US1 AS-1 |
| L4 | `KANAME_SEED_SCENARIO=does-not-exist` → the app does **not** reach the foreground | FR-006, SC-016 |
| L5 | A seeded launch reaches the populated list within **5 s**, measured from `app.launch()` to the first row element existing | SC-009 |
| L6 | A non-seeded launch immediately after a seeded one performs no deletion (a store written by the previous run is still there) | FR-022, US4 AS-4 |

### The route and the screen

| ID | Assertion | Story |
|---|---|---|
| S1 | The list is reached from the front door's toolbar link — the same control a person taps. No test-only screen, deep link or alternate root exists | US1 AS-2, FR-003 |
| S2 | The number of row elements equals `scenario.expectedLiveRowCount`, **and** equals the sum of `AccountSummary.liveTransactionCount` | US1 AS-3, SC-001, R20 |
| S3 | Every declared live row is present, matched on its full accessibility label — date with year, description, amount with currency, direction in words, account identity, category | US1 AS-3, SC-001 |
| S4 | Every declared **superseded** row is absent | US3 AS-2, US1 AS-3 |
| S5 | The rendered order equals the declaration sorted by the engine's total order (`date DESC`, account position, insertion order) | FR-016, FR-019 |
| S6 | The front-door count for an account equals the row count when the list is filtered to it | US3 AS-2 |
| S7 | ⚠️ **No assertion names an id**, and no assertion sums two amounts | R6, data-model §9 |

### Determinism and isolation

| ID | Assertion | Story |
|---|---|---|
| D1 | `small` seeded **10** consecutive times, without cleaning the container, produces an identical count, contents and order every time | SC-010, US4 AS-1 |
| D2 | A seeded launch after a *different* seeded launch shows only the second scenario's rows | US4 AS-2 |
| D3 | Every declared date renders as declared, on a machine in any region and at any time of day | FR-023, R16 |
| D4 | Changing a scenario's declaration makes the assertions that depend on it fail, loudly | FR-010, US4 AS-5 |

### Empty states and the filter

| ID | Assertion | Story |
|---|---|---|
| E1 | Filtering to `deep`'s zero-transaction account, with other accounts populated, renders `accountEmptyOthersHaveRows(statementWasEmpty: true)` | FR-039, FR-040 |
| E2 | An account whose every row is superseded renders `accountNothingToShow` | FR-039 |
| E3 | The filter's four states — unfiltered, filtered, filtered-to-an-account-with-nothing-live, cleared — are each reached and asserted | FR-040, US5 AS-3 |
| E4 | ⛔ `nothingImported` — **not** assertable from XCUITest. See `plan.md` § *Judgement calls* §1 | FR-039, R9 |

### Accessibility — the coverage this buys

| ID | Assertion | Story |
|---|---|---|
| A1 | `performAccessibilityAudit` over the **populated** list: default size, Light | SC-002 |
| A2 | …at `AccessibilityXXXL`, Light | SC-002 |
| A3 | …at default size, Dark | SC-002 |
| A4 | …at `AccessibilityXXXL`, Dark | SC-002 |
| A5 | …with a filter applied, at `AccessibilityXXXL` — the state `018/02` failed in | FR-038 |
| A6 | …under `make a11y-sweep`'s Increase Contrast | SC-002, FR-037 |
| A7 | **Geometry, not audit**: with `small` seeded and filtered, at `AccessibilityXXXL`, scrolled to the end — `lastRow.frame.maxY <= filterBar.frame.minY` | FR-038, R10 |
| A8 | The group heading announced on entry carries the year for a prior-year date | gate G4 |

⚠️ **A5 and A7 are the two FR-038 requires be watched failing** against reinstated defects, and
they need **different instruments** because the auditor has no occlusion check (R10):

| Reinstated defect | Deliberate break | Must go red |
|---|---|---|
| `018/02` — filter chip truncates | `FilterChromeLayout.axis` forced to `.horizontal` | **A5** (auditor, `.textClipped`) |
| `018/03` — row clipped by the bar | `FilterChromeLayout.maximumScopeLines` restored to `6` | **A7** (geometry assertion) |

If A5 does **not** go red against the reinstated chip, the remedy is a second geometry assertion
of A7's shape — not a weakened criterion.

### The suppression that does not travel

`ImportFrontDoorUITests.auditIgnoringContrastOverUnrenderedArea` narrowly ignores `.contrast`
issues raised against elements extending beyond the window, and its doc comment records the four
steps by which that was **proved rather than assumed**. It applies to the front door's
explanation text. **It must not be copied to the list's audits by reflex.** A list scrolls, so
its rows are inside the window; if a seeded audit needs a suppression, it needs its own
four-step proof, recorded the same way.
