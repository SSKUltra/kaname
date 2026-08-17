# Feature Specification: DEBUG-Only Test Seeding (Let an Automated Run Reach a Screen That Has Data In It)

**Feature Branch**: `019-debug-test-seeding`  
**Created**: 2026-08-17  
**Status**: **Ready for `/speckit.plan`** — no open clarifications (see § *Decisions taken without asking*).  
**Milestone**: P3 (Core SwiftUI app) — the **fourth** slice of P3, scheduled in `docs/kaname-ios-plan.md` **before the categorize slice**. Slices 016–018 built screens a person can use; this slice is the first that is not for the person at all. It exists so that every screen after it can be checked by a machine before a person ever sees it.  
**Input**: User description: "A DEBUG-only test-seeding capability that lets an **automated** UI test reach a *populated* screen — starting with the transaction list — without going through the system document picker, and which is provably absent from Release builds."

> **Note on priority labels**: This feature sits in product milestone **P3** (Core SwiftUI app). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P3" and "User Story P3" are unrelated numbering schemes.

## Why this slice exists

The app can show a person their transactions. No automated run can see that it does.

The transaction list is behind an account. An account is behind a real imported statement. An import is behind Apple's **system document picker**, which is another process's user interface and which XCUITest cannot drive. Slice 018's FR-077 forbids the obvious escape — a seeding hook in the shipping app — precisely because a test-only path into a person's financial data is the one thing this app must not carry. So `KanameUITests` today does the only honest thing left to it: `testAFreshInstallOffersNoRouteToAnEmptyTransactionList` asserts that the list is **unreachable**. That is a real assertion about a real promise, and it is also the whole of the automated coverage of the screen that took three slices to build.

**This is not a theory about what might go wrong. It has a bill, and the bill is itemised.**

`.scratch/018-transaction-list/issues/01-manual-accessibility-gate-not-run.md` — now resolved — records what it costs to check that screen by hand: about **forty minutes** on a simulator, and **four defects that no automated gate in this repository could have caught** (`issues/02` through `issues/05`). One of them, `issues/02`, took **two** attempts to close: the first fix **passed every unit test in the repo** and was still broken on screen, because unit tests here prove *which fact leads* and **a pure layout decision cannot see a width**. What caught it was a person at the largest accessibility text size and a screenshot — a chip reading `•••• 77…`, with the digits cut, a truncation four characters wide and easy to accept as fine at a glance. `issues/03` could not be *run at all* until a six-row `gate/` corpus was added to `make perf-corpus`, because the gate asks about the **end** of a list and at XXXL the end of a ten-thousand-row list is some hundreds of flicks away.

Forty minutes is the price of one screen, one time. P3 has dashboard, budgets, tags, search and export still to come, and **every one of them shows a person their own data, which means every one of them sits behind an import**. The cost is not forty minutes; it is forty minutes per screen per release, paid by whoever has an afternoon, forever, on the exact class of defect — clipped text, occluded rows, unreadable chrome, contrast — that a machine is *better* at finding than a person is.

There is a second, quieter cost. `EmptyKind.nothingImported` is **unreachable on the transaction list** in the shipped app (018 PR D finding): the front door hides the route to the list until an account exists, and an account requires an import. The branch is defensive, it is correct, and nothing automated has ever executed it or ever can. A screen's empty states are where its wording is most load-bearing and least exercised, and this one has a state that no test and no person will ever see until the day it appears in front of somebody who has just lost their data.

**What this slice is, exactly.** A way for an automated run to launch the app with a **named, declared, synthetic** history already in the encrypted store, so that the run lands on a populated transaction list, drives it, and turns the system accessibility auditor loose on it — with **no file, no picker and no person**. That is the whole capability. It writes no new screen, changes no user-visible string, and adds nothing a person can reach.

**And what it must cost, in full.** A DEBUG-only path in the app's own sources is a real concession, made knowingly. The condition attached to it is that its absence from Release is **proved, not asserted**. This repository already knows how to pin a ban mechanically rather than by convention: `scripts/import-path-audit.sh` carries **nine** scans, each one the residue of a defect that a review had already waved through — networking symbols anywhere under `ios/Sources`, bank literals read out of the Rust registry, availability gates and material fallbacks, the accent tokens, `listTransactions(` and any second opinion about liveness, persistence APIs under `ios/Sources/Transactions/`, `sorted`/`sort(`/`reversed`, aggregates and `.tint(`, and any claim that transfer detection runs. A tenth scan is the natural shape of this slice's proof. **This spec states the requirement and not the implementation**: the absence must be enforced by something that fails a build, must reach the built Release artifact and not only the sources, and must itself be watched failing against a deliberately re-enabled path — because a gate that has only ever been green proves nothing about what it would catch.

**⚠️ This slice is not a corpus builder, and scope drift in that direction is the specific failure mode to guard against.** `make perf-corpus` already solves getting *data* in cheaply: eight synthetic statements, ten thousand rows, verified at generation time by importing all eight into a throwaway store, plus `200-rows/` and the six-row `gate/` corpus added for `018/03`. Statements reach the simulator's *On My iPhone* by `cp` into the app group whose metadata reads `group.com.apple.FileProvider.LocalStorage`; `xcrun simctl ui booted` drives appearance, Increase Contrast and content size; `xcrun simctl io booted screenshot` reads the screen better than an eye does. All three techniques are written down in `specs/018-transaction-list/quickstart.md` and **none of them changes**. What none of them can do — what no amount of corpus can do — is let an **automated** run reach a populated screen. **That gap alone is this slice.** If this feature appears to need a new generator, a bigger corpus, or a second way of making PDFs, that is a signal that scope has drifted, not a requirement discovered.

Everything here stays inside the constitution. The seeded store is the same **encrypted** store with the same key handling — no plaintext store, no test key in any target. The paths this slice adds perform **zero** network I/O. Money is an exact **decimal** from fixture to pixel and is never a floating-point number. Every seeded byte is **synthetic**: no real statement, and no fragment of one, enters this repository (`AGENTS.md` § *Reading a statement*).

## User Scenarios & Testing *(mandatory)*

<!--
  The "user" of this feature is the automated verification gate, and behind it the person
  whose screen is checked before it reaches them. Each story below is a journey that gate
  can take, and each is independently valuable if it is the only one that ships.
-->

### User Story 1 - An automated run opens a screen with a person's transactions on it (Priority: P1)

An automated run launches the app asking for a named, pre-declared synthetic history. The app comes up with that history already in its encrypted store. The run walks the ordinary route a person walks — front door, one tap — lands on a populated transaction list, and points the system accessibility auditor at it. No file is picked, no picker appears, and nobody was in the room.

**Why this priority**: This is the entire slice. Shipped alone it turns the one screen that took three slices to build from *not covered* into *covered*, and it is the capability every later P3 screen inherits. Every other story below qualifies, protects, or pays for this one.

**Independent Test**: Run the UI suite with no human present and no file on the device; confirm it reaches a transaction list showing exactly the rows the named fixture declares — same count, same dates, same descriptions, same exact amounts, same accounts — and that the system accessibility audit runs against that rendered, populated screen and reports its findings.

**Acceptance Scenarios**:

1. **Given** an automated run that asks for a named seeded history, **When** the app launches, **Then** the history is present before the run can observe any screen, and no document picker is ever shown.
2. **Given** a seeded launch, **When** the run navigates from the front door, **Then** it reaches the transaction list by the same route a person takes, with no test-only screen, deep link, or entry point that does not exist for a person.
3. **Given** the populated list, **When** the run compares it to the fixture, **Then** every declared live row is present with its date, description, exact amount, currency and account, and nothing else is.
4. **Given** the populated list, **When** the system accessibility audit runs against it, **Then** it audits a rendered screen with rows on it — not an empty state and not a placeholder.
5. **Given** a run that asks for no seed, **When** the app launches, **Then** it behaves exactly as it does today: a first-run front door with nothing imported.
6. **Given** any seeded run, **When** the app is inspected for outbound network activity, **Then** **zero** network requests were made.

---

### User Story 2 - The path that makes this possible cannot ship (Priority: P2)

A Release build is produced. Nothing of the seeding capability is in it: not the code, not the fixtures, not the strings, not the instruction that triggers it. A Release build handed that instruction does exactly what it does without it. And none of that is believed on anyone's word — a check that fails the build says so, every time, and has been watched saying so.

**Why this priority**: This is the price of User Story 1, and an unpaid price makes the slice a liability rather than an asset. A test-only route into a person's financial data, shipped, is precisely the thing 018's FR-077 exists to forbid. It sits below US1 only because there is nothing to prove absent until something exists.

**Independent Test**: Build for Release; run the automated absence check over both the sources and the built artifact and confirm it passes; launch that Release build with the seeding instruction and confirm nothing whatsoever is different; then deliberately re-enable the path, rebuild, and confirm the check fails.

**Acceptance Scenarios**:

1. **Given** a Release build, **When** its artifact is inspected, **Then** no seeding code, symbol, fixture, data file or instruction string is present in it.
2. **Given** a Release build, **When** it is launched with the seeding instruction, **Then** it starts as a fresh first-run app with no seeded data, no crash, no diagnostic, and no observable difference of any kind from a launch without the instruction.
3. **Given** the shipping app, **When** a person uses it, **Then** they find no menu item, gesture, settings toggle, URL, shared file or debug screen that reaches this capability — in any build.
4. **Given** the absence check, **When** the seeding path is deliberately re-enabled for Release, **Then** the check fails, and this has been observed rather than assumed.
5. **Given** the repository's verification gate and CI, **When** either runs, **Then** the absence check runs with them, so a regression fails a pull request rather than reaching a build.
6. **Given** the capability is excluded by the build itself, **When** anyone looks for a runtime flag that could switch it back on in a shipped binary, **Then** there is none, because there is no code to switch on.

---

### User Story 3 - What the auditor sees is the shipping screen (Priority: P3)

The seeded run is looking at the real screen: the real encrypted store, the real engine reads, the real ordering, the real live-row rule, the real view. The only thing that differs from a person's install is how the rows got in.

**Why this priority**: A seeding path that injects rows straight into a view, or stands up a stub store, would produce a green audit of a screen that does not exist in the product. That is worse than no coverage, because it is coverage that lies. It ranks below the absence proof only because a lying gate is a slower failure than a shipped hook.

**Independent Test**: Seed a history, then read the same population through the app's ordinary engine reads and confirm the screen and the engine agree; confirm the seeded rows are subject to the same live-row rule by seeding superseded and deleted rows and observing they never appear; confirm no stub, double or in-memory substitute stands between the screen and the store on a seeded run.

**Acceptance Scenarios**:

1. **Given** a seeded history, **When** the list draws it, **Then** the rows were read from the same encrypted store, through the same engine reads, in the same order as they would be for a person.
2. **Given** a seed containing deleted and superseded rows, **When** the list is shown, **Then** neither appears, and the front-door count still equals the number of rows the list shows when filtered to that account.
3. **Given** a seeded run, **When** the screen's data path is inspected, **Then** no stub store, fake view model, test double or injected row list stands between the store and the view.
4. **Given** a seed, **When** it is written, **Then** it goes in through the engine's own write path, so a seeded store is a store the shipping app could have produced by importing.
5. **Given** a seeded store, **When** its encryption and key handling are inspected, **Then** they are the app's own — no plaintext store, no hard-coded or exported key, in any target.

---

### User Story 4 - The same run, twice, is the same run (Priority: P4)

The suite runs today and runs again tomorrow on a simulator that has been used in between. Same rows, same order, same count, same screenshots. A seeded run does not inherit what an earlier run left behind, and does not leave anything behind for the next one.

**Why this priority**: The simulator's app container persists between runs — `make ios-test` uninstalls first for exactly this reason, and the quickstart records a container from a previous corpus being mistaken for a bug. A seeding capability that accumulates or inherits produces failures nobody can reproduce, and a suite nobody trusts is a suite people start skipping.

**Independent Test**: Run the same seeded scenario ten times consecutively without cleaning between runs and confirm the row count, the row contents and the order are identical each time; run a non-seeded launch immediately after a seeded one and confirm it is a clean first-run app.

**Acceptance Scenarios**:

1. **Given** the same named scenario, **When** it is seeded ten times in a row, **Then** the resulting list is identical in contents, count and order every time.
2. **Given** a device that already holds data from an earlier run, **When** a seeded launch starts, **Then** it starts from a known state rather than adding to what was there.
3. **Given** a seeded run has finished, **When** a launch is made without the seeding instruction, **Then** it finds no seeded data and behaves as a first-run app.
4. **Given** an existing store, **When** no seeding is requested, **Then** nothing is wiped, migrated or replaced — the reset happens only on an explicit seeded launch.
5. **Given** a seeded scenario, **When** its declared contents change, **Then** the tests that assert against it fail loudly rather than passing against stale expectations.

---

### User Story 5 - A run asks for the shape of history it needs (Priority: P5)

One check needs six rows, because it asks whether the **last** row clears the bottom bar and at the largest text size a single row is most of the screen. Another needs enough rows to cross the paging boundary, because paging is the part most likely to be wrong. A run names the scenario that fits the question it is asking, instead of every run paying for the largest one.

**Why this priority**: This is the lesson of `018/03` written into the capability rather than rediscovered: the gate was unrunnable until a six-row corpus existed, because the end of a ten-thousand-row list at XXXL is hundreds of flicks away. A single fixed seed would reproduce that trap on the first day and be expensive to undo later.

**Independent Test**: Confirm at least one scenario small enough that an automated run reaches the last row within a few swipes at the largest accessibility text size, and at least one deep enough that the list's paging is exercised more than once; confirm a run names which it wants and gets it.

**Acceptance Scenarios**:

1. **Given** a small scenario, **When** an automated run scrolls at the largest accessibility text size, **Then** it reaches the last row in a handful of swipes and can assert that nothing occludes it.
2. **Given** a deep scenario, **When** an automated run scrolls it, **Then** the list pages more than once and the run can observe that no row is duplicated, skipped or reordered across a page boundary.
3. **Given** several accounts in one scenario, **When** the run applies and clears the account filter, **Then** each filter state — filtered, cleared, and filtered to an account with nothing live — is reachable without a person.
4. **Given** a scenario declaring more than one currency and at least one same-date collision across accounts, **When** the list is shown, **Then** both situations are on screen where an automated run and the auditor can see them.
5. **Given** a new question arises later, **When** a scenario is added for it, **Then** doing so requires no change to anything that ships in a Release build.

---

### User Story 6 - The manual gate shrinks, and says so in writing (Priority: P6)

018's manual gate is rewritten to record what a machine now checks and what is still a person's job. What remains is only what no machine can set or judge: Reduce Transparency, which has no `simctl` control and no test API; VoiceOver assessed for meaningfulness rather than presence; and the three device timings that need a phone. Nothing in the wording lets a reader believe CI now covers the rest.

**Why this priority**: The value of this slice is only realised when somebody stops doing forty minutes of work by hand, and that only happens if the record says which forty minutes. It ranks last because it is bookkeeping — but bookkeeping that, left undone, means the manual gate is run in full forever alongside the automation that replaced most of it.

**Independent Test**: Read 018's recorded gate and confirm every step is marked either automated-by-this-slice with a named test, or still-manual with the reason it cannot be automated; confirm nothing claims SC-012 is closed.

**Acceptance Scenarios**:

1. **Given** the updated gate record, **When** it is read, **Then** each step is either automated with the check that now covers it named, or manual with the specific reason it cannot be automated.
2. **Given** the updated record, **When** SC-012 is referenced, **Then** it is not claimed to be closed, because `issues/06`'s device timings still need a phone.
3. **Given** the updated record, **When** anyone reads it, **Then** no wording suggests continuous integration enforces a step that a person must still run.
4. **Given** a later P3 screen, **When** its spec is written, **Then** the record tells the author which gates come free and which they must budget a person's time for.

---

### Edge Cases

- **An unrecognised scenario name, or a seed that fails halfway.** The launch must fail in a way the automated run detects as a failure. A silent fall-back to an empty app is the worst possible outcome: the auditor would pass against a blank screen and report success for a screen it never saw.
- **A seed requested twice in one launch**, or requested on top of a store that already holds a seed.
- **A Release build launched with the seeding instruction** — no data, no crash, no log line, nothing that reveals the instruction was ever recognised.
- **A DEBUG build launched by a person with no instruction** — an ordinary empty app; their own imported data, if any, untouched.
- **A run that sets the largest accessibility text size, Dark Mode and Increase Contrast at launch and asks for a seed at the same time** — all four instructions must take effect together.
- **A simulator container left over from an earlier run or an earlier corpus.**
- **A scenario whose declared rows drift from what the tests assert** — the two must not be able to disagree quietly.
- **A seed containing an account whose statement genuinely had zero transactions**, and an account whose every row is superseded or deleted — the two produce *different* empty states, and both must be reachable.
- **A seed containing amounts of more than one currency, on the same date, across accounts** — no figure anywhere may combine them.
- **A very large amount and a very long account name in the same seeded row**, at the largest text size — the shape that produced `018/04`.
- **Seeding on a physical device rather than a simulator** — permitted in a DEBUG build, and subject to every rule here without exception.

## Requirements *(mandatory)*

### Reaching a populated screen without a person

- **FR-001**: An automated run MUST be able to launch the app such that a **named**, pre-declared synthetic history is already present in the app's store, without a document picker, without a file being placed anywhere by hand, and without any human action.
- **FR-002**: The seeded history MUST be complete **before** the run can observe any screen that reads the store, so no run can ever audit, screenshot or assert against a half-populated list.
- **FR-003**: A seeded run MUST reach the populated transaction list by the **same route a person takes** — the front door and its ordinary navigation. This slice MUST NOT add a test-only screen, deep link, alternate root, or any entry point that does not exist for a person.
- **FR-004**: What is seeded is **data**, never interface state. The screen, its navigation, its ordering and its copy are unchanged and unaware they are looking at a seeded store.
- **FR-005**: Seeding MUST be requested **explicitly, per launch**. A launch that does not request it MUST behave exactly as the app behaves today.
- **FR-006**: An unrecognised scenario name, or a seed that cannot be applied in full, MUST cause the launch to fail in a way the automated run detects as a **failure**. It MUST NOT degrade into an empty, partial or default state.
- **FR-007**: A run MUST be able to choose **which** scenario it wants by name, from more than one.

### What a seed may contain

- **FR-008**: A scenario MUST be able to express, at minimum: several accounts; more than one currency; at least one same-date collision across accounts; rows superseded by de-duplication; an account whose statement contained **zero** transactions; and categorized and uncategorized rows.
- **FR-008a**: Two states named in this spec's first draft — **deleted rows** and **rows flagged as transfers** — are **excluded**, because a seed that could build them would be describing a store the shipping app cannot produce. `is_deleted` is never written by `store.rs`'s API at all; the only `UPDATE … SET is_deleted = 1` in the repository is a raw statement in `core/crates/kaname-core/tests/common/mod.rs`, used by engine tests that reach past the API on purpose. `is_transfer` is written only by `detect_transfers`, which `scripts/import-path-audit.sh` **bans the app from calling** — so a seeded transfer would be staging a screen no person can currently have. Seeding MUST NOT acquire a write path that the import pipeline lacks: the value of a seeded screen is that it is the screen a person gets, and a fixture that can build states the product cannot is a fixture that tests fiction. Both exclusions MUST be recorded rather than worked around. The superseded-row half of the live rule (FR-008) is unaffected and remains the way `accountNothingToShow` is reached.
- **FR-009**: There MUST be a scenario small enough that an automated run reaches the **last** row within a few swipes at the largest accessibility text size, and a scenario deep enough that the list **pages more than once**.
- **FR-010**: Every scenario MUST be declared in **one** place, and what the tests expect MUST be derived from or pinned against that same declaration, so the fixture and its assertions cannot drift apart silently.
- **FR-011**: Seeded content MUST be **entirely synthetic**. No real statement, no fragment of one, no real account number, no real merchant record and no real person's data may enter this repository or any build.
- **FR-012**: Every monetary value in a seed MUST be an exact decimal at every step, from declaration to storage to screen. A floating-point number MUST NOT appear on any part of this path.
- **FR-013**: Adding a new scenario later MUST NOT require changing anything that is compiled into a Release build.

### The seeded screen is the shipping screen

- **FR-014**: Seeded transactions MUST be written through the engine's **own write path**, so that a seeded store is a store the shipping app could have produced by importing.
- **FR-015**: A seeded run MUST read through the app's **existing** engine reads. This slice MUST NOT introduce a stub store, a fake view model, a test double, or an injected row list between the store and the screen.
- **FR-016**: This slice MUST NOT introduce a second definition of the population, the ordering, or any count. The live-row rule, the total order and the account counts remain the engine's, exactly as slice 018 fixed them.
- **FR-017**: A seeded store MUST be the app's own **encrypted** store with the app's own key handling. No plaintext store, and no hard-coded, bundled or exported key, may exist in any target.
- **FR-018**: The shipping app's behaviour, screens, copy and data MUST be **unchanged** by this slice.

### Determinism and isolation

- **FR-019**: The same named scenario MUST produce the same rows, the same count and the same order on every run, on every machine.
- **FR-020**: A seeded launch MUST begin from a **known state** rather than accumulating on top of whatever an earlier run left in the app's container.
- **FR-021**: A seeded run MUST leave nothing behind that changes the behaviour of a later non-seeded run.
- **FR-022**: Nothing may be reset, wiped or replaced **except** on a launch that explicitly requests seeding.
- **FR-023**: Seeding MUST NOT depend on wall-clock time, locale, machine, or the order in which tests run. A date in a scenario is a declared date.

### Absent from Release — and proved, not asserted

- **FR-024**: **No part** of this capability may be present in a Release build: not its code, not its fixture data, not its strings, not the handling of the instruction that triggers it.
- **FR-025**: The capability MUST be excluded from Release **by the build itself**, not by a runtime condition, so that no flag, argument, setting or patched value can re-enable it in a shipped binary.
- **FR-026**: The absence MUST be enforced by an **automated check that fails**, not by review, convention or comment. The repository's existing mechanical bans are the precedent for what "enforced" means here; the shape of the check is `/speckit.plan`'s decision.
- **FR-027**: That check MUST inspect the **built Release artifact** and not only the sources, because a source convention can be honoured while a build setting is wrong.
- **FR-028**: A Release build launched **with** the seeding instruction MUST be indistinguishable from one launched without it — no seeded data, no crash, no log line, no timing difference a person could act on, nothing that reveals the instruction was recognised.
- **FR-029**: The absence check MUST run as part of the repository's existing verification gate and in continuous integration, so a regression fails a pull request.
- **FR-030**: The absence check MUST be **observed failing** against a deliberately re-enabled seeding path before it is trusted, and that observation MUST be recorded.
- **FR-031**: The shipping app MUST gain **no** user-reachable surface from this slice: no menu, no gesture, no settings toggle, no URL scheme, no shared-file or pasteboard trigger, no debug screen — in any build.
- **FR-032**: Slice 018's **FR-077** MUST remain satisfied on its own terms: the shipping app carries no test-only or DEBUG-only entry point. It is satisfied here by **absence from the shipped build**, not by hiding.

### Privacy and data handling

- **FR-033**: Every path this slice adds MUST perform **zero** network I/O. No analytics, no telemetry, no crash reporting, no diagnostic upload of any kind.
- **FR-034**: No transaction field — seeded or real — may be written to logs or diagnostics by anything this slice adds.
- **FR-035**: All fixtures added by this slice MUST be synthetic and MUST remain synthetic; no real statement or fragment of one may enter the repository at any point in its life.
- **FR-036**: This slice MUST NOT weaken, bypass or duplicate the encrypted store's protections in order to make seeding cheaper.

### The coverage this buys

- **FR-037**: The system accessibility audit MUST run against the **populated** transaction list in an automated run, across the axes a machine can set: default and largest accessibility text sizes, Light and Dark Mode, and Increase Contrast through the existing sweep.
- **FR-038**: The new automated coverage MUST be **observed failing** against at least two of slice 018's manual-gate defects deliberately reinstated — the filter chrome unreadable at accessibility sizes (`issues/02`) and a row clipped by the bottom bar (`issues/03`) — and that observation MUST be recorded. A gate that has only ever been green proves nothing about what it would catch.
- **FR-039**: **Every** empty state of the transaction list that a person can reach MUST become reachable by an automated run against a rendered screen.
- **FR-039a**: `EmptyKind.nothingImported` is an exception, and seeding does **not** fix it. It is unreachable **by construction, not by accident**: `EmptyKind.decide` returns it only when the account summaries are empty, while `RootView` shows the list's only entry point only when they are **not** — and both read the *same* `accountSummaries()` call, so the state's precondition is exactly the condition that hides the route to it. No seed can satisfy both. It MUST therefore be covered by **host-rendering the state directly** in the unit target, which proves its wording and layout but yields **no** `performAccessibilityAudit` — so FR-039's coverage is met unevenly, and this spec says so rather than implying parity. The branch MUST NOT be deleted (it is correct and defensive), and the front door MUST NOT be changed to reach it, because that would contradict the shipped UI test asserting a fresh install offers no route to an empty list.
- **FR-040**: Each of the account filter's states — unfiltered, filtered, filtered to an account with nothing live, and cleared — MUST be reachable by an automated run.
- **FR-041**: The capability MUST be usable by a later P3 screen without that screen's slice re-inventing it, and without any change to shipping sources.

### What stays manual, said plainly

- **FR-042**: Slice 018's recorded gate MUST be updated so that every step is marked either **automated**, naming the check that now covers it, or **manual**, naming the specific reason it cannot be automated.
- **FR-043**: The remaining manual steps MUST be stated with their reasons: **Reduce Transparency** has neither a `simctl` control nor a test API; **VoiceOver judged for meaningfulness** is an assessment and not an assertion; the **three device timings** (`issues/06`) need a physical phone, not an audit; **G10** is a judgement rather than a check; and **G13/G14** require a live import driven **through the system document picker** while the list is open — the exact interaction seeding structurally cannot stage, since seeding's whole method is to *avoid* the picker.
- **FR-043a**: CI MUST run `make import-audit`. Its nine existing scans — including the networking scan that is the platform half of the constitution's first principle — run today on a laptop and **have never run in CI at all**, so a promise the repository believes is enforced is in fact enforced only when somebody remembers. CI's lint step MUST also cover the same targets as `make lint` (`Sources Tests UITests`, not `Sources Tests`). Both gaps predate this slice and MUST be closed in its first PR, since this slice is about to add a tenth scan whose value depends entirely on the gate actually running.
- **FR-044**: This slice MUST NOT claim to close slice 018's **SC-012**, and no wording anywhere may suggest continuous integration enforces a step a person must still run.
- **FR-045**: Any manual step that remains MUST continue to be recorded with the build and date it was run.

### Scope discipline

- **FR-046**: This slice MUST NOT build, replace, extend or duplicate a statement-corpus generator. `make perf-corpus` and its `10000-rows/`, `200-rows/` and `gate/` outputs stay exactly as they are, and the quickstart's three manual techniques stay exactly as they are.
- **FR-047**: This slice MUST NOT change import, extraction, parsing, categorization, de-duplication, the store schema, or any behaviour of the transaction list. If it appears to need such a change, that is a **finding to record**, not a change to make here.
- **FR-048**: This slice MUST NOT add a user-visible string, screen or affordance to the shipping app.
- **FR-049**: This slice MUST NOT introduce persistence, sorting, filtering or any second opinion about the population under the transaction list's own sources — the mechanical bans slice 018 pinned there continue to hold, unweakened.

### Key Entities *(include if feature involves data)*

- **Seed scenario**: A named, declared, synthetic history — which accounts exist, what rows they hold, and which of them are live, superseded or deleted. The single source of truth for both what gets written and what a test expects. Exists only outside the shipped build.
- **Seeded launch**: One run of the app that was explicitly asked for a named scenario, starts from a known state, and is otherwise an ordinary launch of the ordinary app.
- **Seeded store**: The app's own encrypted store, holding a scenario's rows, written by the engine's own write path. Indistinguishable at read time from the store of a person who imported the same statements.
- **The absence proof**: The automated check that fails when any part of this capability can be found in a Release build — in its sources or in its artifact. It is the condition on which the whole slice is permitted.
- **The gate record**: Slice 018's manual gate, rewritten to say which of its steps a machine now takes and which a person still must, and why.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An automated run with **zero** human actions and **zero** files on the device reaches a populated transaction list and finds **100%** of the named scenario's live rows there — exact dates, exact amounts to the last paisa, descriptions, currencies and account attribution as declared — and **zero** rows that were not declared.
- **SC-002**: The populated transaction list passes the system accessibility audit in an **automated** run at the default and largest accessibility text sizes, in Light and Dark Mode, and with Increase Contrast enabled, with **zero** findings.
- **SC-003**: A Release build contains **zero** seeding code, symbols, fixture data, files or instruction strings — verified by an automated check over the built artifact that fails the gate on any hit.
- **SC-004**: A Release build launched with the seeding instruction is indistinguishable from one launched without it in **100%** of tested states: **zero** seeded rows, **zero** crashes, **zero** diagnostics, **zero** observable differences.
- **SC-005**: The absence check runs in the repository's verification gate and in CI, and has been **observed failing** against a deliberately re-enabled seeding path in **100%** of injected cases.
- **SC-006**: The new automated coverage is **observed failing** against at least **two** of slice 018's manual-gate defects deliberately reinstated (`issues/02`, `issues/03`); **zero** of them pass against a green gate.
- **SC-007**: **100%** of the transaction list's **person-reachable** empty states have automated coverage against a **rendered** screen. `EmptyKind.nothingImported` is covered by host-rendering only, without an accessibility audit, for the structural reason FR-039a records — its count of automated executions today is **zero**, and this slice takes it to at least one.
- **SC-008**: The manual accessibility gate for a screen behind an import falls from **fourteen** steps and about **forty minutes** to **eight**, and takes **under twenty minutes** to run. The eight that remain are the ones no machine can set or judge: Reduce Transparency, VoiceOver assessed for meaningfulness, G10's judgement, the three device timings, and G13/G14's live import through the system picker. ⚠️ Six steps automated, not nine — an earlier draft of this criterion counted only five remaining and had no home for G10, G13 or G14.
- **SC-009**: A seeded launch reaches the populated list within **5 seconds** on the simulator, so that adding this coverage does not measurably slow the suite.
- **SC-010**: The same scenario seeded **10** consecutive times on a container that is never cleaned produces an **identical** list — identical count, contents and order — every time, and a non-seeded launch immediately afterwards finds **zero** seeded rows.
- **SC-011**: **Zero** network requests occur on any path this slice adds, verified automatically.
- **SC-012**: **Zero** real statements, real statement fragments, real merchant records or real account identifiers appear in any fixture, scenario or test added by this slice.
- **SC-013**: **Zero** plaintext stores and **zero** hard-coded, bundled or exported encryption keys exist in any target after this slice.
- **SC-014**: The shipping app is unchanged: **zero** user-visible strings added or altered, **zero** screens added, and the existing suites stay green with **zero** expectation edits.
- **SC-015**: A new scenario can be added with **zero** changes to any file compiled into a Release build.
- **SC-016**: A seed that cannot be applied — an unrecognised name, or a partial write — surfaces as a **test failure** in **100%** of injected cases, with **zero** cases of an audit reporting success against an unpopulated screen.
- **SC-017**: An automated run reaches the **last** row of the small scenario within a handful of swipes at the largest accessibility text size, and the deep scenario pages **more than once** with **zero** rows duplicated, skipped or reordered across a page boundary.

## Clarifications

No questions were put to the repo owner for this slice. The feature description settled the two that would have been asked — that the capability is DEBUG-only rather than absent from the app entirely, and that its absence from Release must be **proved rather than asserted** — and the remaining open points had defensible defaults, recorded below rather than escalated.

### Decisions taken without asking

- **Seeding is requested per launch, and never by a person.** A DEBUG build launched by a developer with no instruction is an ordinary empty app. The alternative — a developer menu — is a second surface to keep out of Release, gives a person a way into a state the product cannot produce, and buys nothing an automated run needs. FR-005, FR-031.
- **A failed or unrecognised seed fails the launch loudly.** The tempting behaviour is to carry on with an empty app; the consequence is an accessibility audit reporting success against a blank screen, which is the exact failure mode this slice exists to remove. FR-006, SC-016.
- **The seed is written through the engine's own write path, not around it.** Writing rows by a private route would make the seeded store a thing the product cannot produce, and the audit would be checking a screen that does not exist. What is bypassed is the **picker**, and only the picker. FR-014, FR-015.
- **Absence from Release is a property of the build, not a runtime check.** A runtime gate leaves the code in the binary, where a flag, a patched byte or a debugger can reach it — and where a reviewer reading only the sources would conclude, correctly and uselessly, that it was gated. FR-025.
- **The absence proof is watched failing before it is trusted.** This repository has learned twice that a green gate is not evidence: `018/02` passed every unit test while broken on screen, and the 018 tasks record five and six deliberate breaks watched going red per phase for exactly this reason. FR-030, SC-005.
- **The transaction list is the proving ground; the other screens behind an import are not seeded here.** The summary, the failure, the password prompt and the account picker are all reachable once the capability exists, and each is cheap to add afterwards. Doing them all in this slice would multiply the fixture surface before the capability has been proven once. They are named in Out of Scope so nobody reads their absence as an oversight.
- **This slice does not close 018's SC-012.** `issues/06`'s three device timings need a phone, Reduce Transparency has no machine control, and VoiceOver meaningfulness is a judgement. Claiming closure would trade a known-open gate for a false one. FR-044.
- **No new corpus, no new generator, no new PDF-making.** `make perf-corpus` already produces `10000-rows/`, `200-rows/` and `gate/`, verified at generation time by importing all eight statements into a throwaway store. Those exist for the **device** gates and stay there. FR-046.
- **Scenarios are declared once and asserted from that declaration.** Two hand-maintained copies of a fixture's strings drift, and the drift shows up as a test that quietly stopped asserting anything. FR-010.

### Amendments after `/speckit.plan` (2026-08-17)

Four findings from the planning pass changed this spec rather than being routed around. All four are cases where the spec asked for something the codebase cannot give, and in each the codebase was believed over the draft.

- **FR-008 lost two of its states, and gained FR-008a.** The draft asked a scenario to express **deleted rows** and **rows flagged as transfers**. Neither is a state the shipping app can produce: `is_deleted` has no write path in `store.rs`'s API — the only `SET is_deleted = 1` in the repository is raw SQL in an engine test helper — and `is_transfer` is written only by `detect_transfers`, which `import-path-audit.sh` bans the app from calling. Building either would require seeding to hold a power the import pipeline does not, which would make the seeded screen a screen no person can reach. The point of this slice is the opposite of that.
- **FR-039 was overpromising, and now says so.** `EmptyKind.nothingImported` is unreachable **by construction**: its precondition (empty account summaries) is the same condition under which `RootView` hides the only route to the list, read from the same call. Seeding cannot satisfy both, so it is covered by host-rendering without an accessibility audit — real coverage, lesser coverage, and named as such in FR-039a rather than folded into a "100%" that would not be true.
- **SC-008's arithmetic was wrong and is now conservative.** It counted five remaining manual steps against a gate of fourteen, leaving **G10, G13 and G14** with no home. G13/G14 need a live import driven through the system document picker while the list is open — the one interaction seeding structurally cannot stage, because avoiding the picker is its entire method. The criterion now claims **six** steps automated and eight remaining, under twenty minutes rather than ten. A success criterion that overstates the win is a worse outcome than a smaller win.
- **FR-043a is new, and is about a hole this slice would otherwise inherit.** CI has **never** run `make import-audit` — all nine scans, including the networking scan that is the platform half of Principle I, run only when somebody runs them. This slice is about to add a tenth scan whose entire value is that it fails a build, so the gate has to actually run. CI also lints two of the three targets `make lint` covers.

## Assumptions

- The beneficiary of this slice is the person, indirectly: the value is defects caught by a machine before a release rather than by somebody at XXXL with a screenshot, or by the person themselves.
- The transaction list as slice 018 shipped it is correct and stays untouched. This slice changes how a test *arrives* at that screen, and nothing about the screen.
- The engine's existing write path can produce every situation a scenario needs to express. Where it cannot — slice 018 recorded that `is_deleted` has **no write path** in the store's Swift-facing API — that limitation is a finding to name in the plan, not a reason to add a private write route. The half of the live rule that cannot be reached from the platform stays pinned engine-side, exactly as `history_live.rs` L1/L4/L5 pin it today.
- `xcrun simctl ui booted` remains the way appearance, Increase Contrast and content size are set, and `make a11y-sweep` remains the wrapper that runs the UI suite underneath them. This slice supplies the missing ingredient — a screen with rows on it — not a replacement for either.
- `ios/Sources/Import/ImportService.swift` is at **393** of the 400-line SwiftLint limit and `make lint` is `--strict`, so any work that touches it must move code out rather than reformat. New platform code belongs in its own place, as `ios/Sources/Transactions/` was created for slice 018.
- After any change to the FFI surface, the xcframework is rebuilt before the project is generated (`make core-xcframework` then `make ios-gen`); a bare `tuist generate` yields a Swift error that is not a Swift problem.
- The deployment target is iOS 26 and Liquid Glass is unconditional; no `#available(iOS 26, *)` gate, material fallback or hand-rolled blur may be introduced, and the existing mechanical scan that bans them continues to apply.
- The unit test target already builds stores directly and needs nothing from this slice; the automated **UI** run is the consumer.
- A physical device running a DEBUG build may be seeded under exactly the same rules. Nothing here assumes a simulator except the convenience of `simctl`.
- The manual gate's remaining steps will still be run by a person before release. This slice makes that list short and honest; it does not remove it.

## Out of Scope *(deferred to later slices)*

Per the P3 order — onboarding → import → transaction list → **DEBUG-only test seeding** → categorize → dashboard → budgets → tags → search → export — everything below is out of this slice and MUST NOT be built here:

- **Seeding the other screens behind an import** — the import summary, the failure states, the password prompt and the account picker. The capability this slice delivers is what makes them reachable; extending scenarios to cover them is follow-on work, cheap once this exists.
- **Any new statement corpus, corpus generator, or PDF-building capability.** `make perf-corpus` is unchanged.
- **Automating the device timing gates** (`issues/06` — G9, G11, G12). They need a phone; a simulator's frame timings are not evidence for them, and no seeding hook changes that.
- **Automating Reduce Transparency or VoiceOver meaningfulness.** Neither has a machine control; both stay with the manual gate.
- **Closing slice 018's SC-012.**
- **Fixing any defect the new automated coverage finds.** Finding them is this slice; each fix is its own ticket, judged on its own.
- **Any change to import, extraction, parsing, categorization, de-duplication or the store schema.**
- **Any change to the transaction list's behaviour, layout, copy or performance.**
- **A developer menu, debug screen, feature-flag surface or diagnostics panel** of any kind, in any build.
- **Snapshot testing as a discipline**, or any new testing framework. This slice uses the gates the repository already has and gives them a screen to look at.
- **Seeding a person's real data, or importing anything real anywhere**, under any circumstance.
- **Performance measurement of the seeded path beyond keeping the suite fast** (SC-009). This is a test fixture, not a product path.

## Dependencies

- **Slice 018 (`018-transaction-list`)** — the screen this slice proves the capability on, its six empty states, its account filter, its paging, and **FR-077**, which forbids a seeding hook in the shipping app and which this slice satisfies by absence from Release rather than by concealment. Also **SC-012**, the manual gate this slice shrinks but does not close, and **FR-041**/**FR-068**, whose promises the mechanical bans under the transaction list's sources continue to enforce.
- **Slice 016 (`016-statement-import-vertical`)** — the front door, the import pipeline whose write path a seed goes through, and the originally recorded limitation (T115/T123) that the automated auditor cannot reach any screen behind an import.
- **`.scratch/018-transaction-list/issues/01`** — the itemised cost of not having this: forty minutes by hand, four defects no automated gate here could have caught, and the record of which techniques made the manual run cheap.
- **`.scratch/018-transaction-list/issues/02` and `issues/03`** — the two defects this slice's new coverage must be watched failing against (FR-038, SC-006), and the proof that a rendered screen sees what a unit test structurally cannot.
- **`.scratch/018-transaction-list/issues/06`** — the three device timings, which stay manual and which are why SC-012 stays open.
- **`scripts/import-path-audit.sh` and `make import-audit`** — nine mechanical scans, the repository's established precedent for pinning a ban so it fails a build rather than a discussion. The absence proof joins them in spirit; its shape is `/speckit.plan`'s decision.
- **`make a11y-sweep`** — the existing wrapper that sets Increase Contrast with `simctl` and runs the UI suite underneath it. It gains a populated screen to audit and needs no redesign.
- **`make perf-corpus` and `specs/018-transaction-list/quickstart.md`** — unchanged, and the boundary this slice must not cross.
- **The existing encrypted on-device store and its key handling**, which a seeded run uses exactly as a person's install does.
- **The engine's existing write path**, which is how seeded rows get in — and whose one known platform-side gap (no write path for `is_deleted`) is a limitation to name, not to work around.
