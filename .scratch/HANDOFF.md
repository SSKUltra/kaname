# Kaname — task pickup (START HERE)

> **Read order:** this file → `.specify/memory/constitution.md` (wins over everything) →
> **the feature you're picking up (§3 names it)** → `docs/kaname-ios-plan.md` (architecture +
> P0–P6) → `.github/copilot-instructions.md`.
> Durable "why" reference: `docs/HANDOFF.md` (original scaffold) + `docs/adr/`.

Kaname (要, "the key") is the **privacy-first, local-first** open-source iOS client
(Rust core + SwiftUI) for personal finance, by **BeaconBrain**. The free/core engine runs
**100% on-device with zero network I/O**; premium (AI/AA/sync) is server-gated elsewhere.

---

## 1. Where work is tracked — TWO trackers, know which one

**→ §3 always names the live one. Read it before scanning either.**

**A. `specs/NNN-<slug>/` — Spec Kit. This is where current work lives.** Every UI/engine
slice from 016 onward is specified here: `spec.md` → `plan.md` → `research.md` →
`contracts/` → **`tasks.md`** (the executable queue, checkbox per task) → `quickstart.md`.
A feature here is picked up by working `tasks.md` in order, respecting its PR split.
**`specs/020-categorize/` is COMPLETE — all 183 tasks. The next slice has not been specified yet.**

**B. `.scratch/<feature-slug>/` — the older local ticket convention** (see
`docs/agents/issue-tracker.md`): `spec.md` plus `issues/<NN>-<slug>.md`, each with a
`Status:` line (`needs-triage`/`needs-info`/`ready-for-agent`/`ready-for-human`/`wontfix`,
per `docs/agents/triage-labels.md`). Used by `.scratch/categorization/` and
`.scratch/persistence/` — **both fully resolved; nothing open there.** Kept for history.

**Nothing is open on 016.** `issues/07` — the last one — is resolved:
- **`issues/07`** — **resolved.** `transactions_inserted` counted rows *read from the document*,
  not rows the account gained, so re-importing a six-row statement claimed six transactions while
  the account gained none. `ImportOutcome` now carries `rows_read`, `transactions_added` and
  `rows_superseded`, which always sum; `transactions_added` is a `COUNT(*)` over the statement's
  live rows taken after every linking pass, because both available derivations are right in the
  common case and wrong in the interesting one. The screen reads **"Transactions added"** and
  **"Already in Kaname"**. ⚠️ The rename is load-bearing: there is no longer a field whose name
  promises something it does not count.
- **`issues/04`**, **`05`**, **`06`** — **resolved.** `04`'s status line was stale until
  2026-08-16; `05` split the summary into `Imported` / `This account` with the scope captioned;
  `06` moved "Import another" into the content so the title has room to say what happened.

⚠️ **Open on 018, and all of it from the 2026-08-15 gate run** — `SC-012 is still not satisfied`,
but **every accessibility gate now passes**. What is left is three timings that need a phone, one
unreproduced hang, and one new legibility question:

- **`issues/02`** — ⛔ failed, was "fixed", ⛔ **failed again**, now **resolved** and ✅ **G5
  passes**. The first fix kept the bar horizontal and only changed *which* fact truncated: the
  chip shipped reading `•••• 77…`, with the digits cut. At the largest size the mask (~280 pt) and
  the collapsed clear button (~110 pt) plus padding (32 pt) want ~420 pt of a **393 pt** screen —
  **no ordering fits them side by side**. The bar is now a `VStack` at accessibility sizes
  (`FilterChromeLayout.axis`) and the chip reads `•••• 7742` over `ICICI Amazon Pay Credit Card`
  in full. ⚠️ **Every unit test passed against the broken bar**: they prove which fact *leads*,
  and it did — a pure layout decision cannot see a width. That is the boundary of the approach,
  not a flaw in it, and it is why FR-075 puts rendering on a manual gate.
- **`issues/03`** — **resolved**, ✅ **G2 passes**. The last row sits entirely clear of the bar at
  XXXL with a filter applied. `.safeAreaBar` was always correct; what it could not survive was a
  bar with no bound on its height.
- **`issues/04`** — **resolved**, and **confirmed by eye at both the default and accessibility
  sizes**. Rows read `···· 1002 · ICICI Amazon Pay Credit…` and `···· 7742 · …`, so two cards of
  one product are finally distinguishable on screen.
- **`issues/07`** — **resolved by 019 PR B.** The pinned date heading had no background, so at
  XXXL a row was legible *through* it. The fix is the one this ticket's own analysis names — an
  opaque background — and FR-068 permits it, because what FR-068 bans is *material*, not opacity.
  ⚠️ Two things worth carrying: it was **reproduced by a machine at the default text size in
  twelve seconds** by the first audit ever run against a populated list, where a person had needed
  XXXL and forty minutes; and the heading's **colour** was independently wrong, because T116's
  `.foregroundStyle(.primary)` is the *hierarchical* style and resolved to a no-op against the
  grey already in force (`.scratch/019-debug-test-seeding/issues/01`).
- **`issues/05`** (`needs-info`) — a one-off 100% CPU main-thread render hang; sampled, not
  reproduced in three attempts.
- **`issues/06`** (`ready-for-human`) — **G9, G11, G12 have never been measured.** ~20 minutes
  with a device, a Release build and a frame-stepped screen recording; the ticket carries the
  whole runbook. ⚠️ A free-team build expires seven days after install. **This is now the only
  thing between 018 and SC-012.**
- **`issues/01`** — **resolved.** T139's accessibility half (G1–G8) and G10 were run on the
  simulator: 6 pass, 2 fail. It is kept for what the run cost and the two techniques that made
  it cheap.

⚠️ **Three things learned running the gate to closure, all now permanent.** `make perf-corpus`
writes a **`gate/`** corpus — one six-row statement on its own card number — because G2 asks about
the *end* of a list and at XXXL the 10,000-row corpus puts that hundreds of flicks away; statements
reach the simulator's *On My iPhone* by `cp` into the
`group.com.apple.FileProvider.LocalStorage` app group, with no drag-and-drop; and `make ios-test`
now pins `content_size large`, because a text size left at XXXL by a manual run fails two
front-door contrast audits and looks exactly like a code regression. All three are written up in
`specs/018-transaction-list/quickstart.md`.

⚠️ **One lesson from `3151e5b`'s own working session, because it cost a rebuild.** The repo's
"watch it fail" discipline needs a way to revert a deliberate break, and
`git checkout -- ios/Sources` is **not** it while the fix itself is uncommitted — it reverts to
`HEAD` and takes the fix with it. Copy the tree aside, or commit first, then break.

⚠️ **`core/tests/history_perf.rs::s5` is wall-clock and flaky under CPU contention.** It failed
once during this session purely because `make core-test` and `make ios-test` were running at the
same time, and passed alone immediately after. Do not run the two gates concurrently, and do not
chase an `s5` failure before re-running it on a quiet machine.

**Resolved during 018's manual gate**, kept for the reasoning:
- **`issues/01-front-door-contrast-dark-mode-largest-text.md`** — **resolved**, and
  **`make ios-test` is green again** (256 unit tests, 6 UI tests). It was an auditor artifact:
  at the largest text size the explanation is 621 pt tall on an 852 pt screen, so the contrast
  verdict was computed over pixels never drawn. Proved by dropping one text size — same
  colours, only the height changes — and watching both tests pass. The suppression is narrow
  (`.contrast` only, only when the element's frame escapes the window, only on the two
  largest-text tests) and was watched failing against a real in-window contrast break.
- **`issues/02-accent-unreadable-as-text-in-dark-mode.md`** — **resolved**. The accent is now
  two tokens (`kanameAccentText` / `kanameAccentFill`), Dark Mode text goes from **2.35:1 to
  5.02:1** at its worst surface, Increase Contrast is answered, and two guards hold it:
  `ThemeContrastTests` computes the ratios from the tokens, and `import-audit`'s ninth scan
  confines `.glassProminent` to `Theme.swift` so the fill and its style cannot come apart.
  **Confirmed by eye on the device** by the holder who reported it.
- **`issues/03-no-way-to-state-an-unprinted-last-4.md`** — **resolved**. The account picker now
  takes an optional last-4 beside the name, under one rule: **what the document printed wins**
  (`parsed.cardLast4 ?? statedLast4`), so a typo can leave an account without digits but can
  never overwrite digits a statement carried. Four digits or none. ⚠️ **Nothing edits an account
  after the fact** — the "update flows later" this defers belongs to the account-management
  slice.

⚠️ **Don't conclude "no work left" from an empty `.scratch/` queue** — that is the older
tracker. Check §3.

---

## 2. What exists — read the source, don't cache it here

A hand-maintained status table drifts every slice, so this section points at the sources of
truth instead of copying them:

- **The engine + store API that's built** → §7 "Key reusable seams" (names the functions,
  points at the code); the P0–P6 phase map → `docs/kaname-ios-plan.md`.
- **Which slices shipped** → the `Status: resolved` line in each `.scratch/*/issues/NN-*.md`,
  the unchecked boxes in the live `specs/NNN-*/tasks.md`, and the merged PRs
  (`gh pr list --state merged`).
- **Test counts / current `main`** → `make core-test` && `make ios-test`; `git rev-parse main`.
- **Source layout** → §8 repo map, or `ls core/crates/kaname-core/src/`.

Orientation in one line: the deterministic engine (10 readers + balance-chain, reconcile,
dedup, coverage, transfer, categorize), the UniFFI bridge, and the SQLCipher encrypted store
are all in and fully wired together — **P2 is done; P3 (the SwiftUI app) is now the work**.
The import vertical and the front door have landed (016, 017); **the transaction list is
under way (018 — PR A0 merged, PR A's engine done)** and the accounts/dashboard/budgets screens
have not started.

---

## 3. What's next

**`018-transaction-list` is DONE and merged — PR #39, 21 commits, every gate green.** A person
can open the app, tap once, and read their own transactions across every account newest-first and
grouped by date; narrow to one account and clear it in a tap; be told which of six true things is
the case when a screen is empty; and watch a statement they import while reading appear **without
a relaunch**, without losing their filter or their place in the list.

**⬅️ NEXT: `020-categorize` is DONE and merged — [PR #43](https://github.com/SSKUltra/kaname/pull/43),
merge commit `2394061`, both CI jobs green (Rust core 1m10s, iOS 39m49s).** All 183 tasks, all
seven PRs, across two pull requests (#42 = A–D, #43 = E–G). **The next slice has not been
specified yet** — `speckit.specify` is where it starts.

A person can now open a transaction, change its category, and have that answer survive every
re-import, every transfer-detection run and every other engine path; be asked in their own words
whether Kaname should remember the merchant, decline that without touching the correction, and —
if they accept — be told exactly how many transactions in which accounts would change **before**
anything is written; and work a list of everything nobody has answered down to zero, being told
in words when they are finished.

**⚠️ What is open, and it is short:**

- 🚨 **`.scratch/020-categorize/issues/04`** (`ready-for-agent`) — **`SeedContractUITests
  .testAnUnrecognisedScenarioNameNeverReachesTheForeground` is flaky on CI**, and it cost #43
  **37m42s + a 39m49s re-run**. The test deliberately crashes the app and absorbs XCUITest's
  crash report with `issueMatcher = { $0.compactDescription.contains("crashed") }` — but the
  **same event has two spellings**, and on a differently-loaded runner it arrives as
  `Failed to get background assertion for target app with pid N`, which the matcher does not
  absorb. One line to fix; the narrowness must be preserved, and the ticket says exactly why and
  how to watch it fail. **Fix this before the next CI-gated PR.**
- **`.scratch/020-categorize/issues/02`** (`ready-for-agent`) — **`EmptyKind.accountAnswered` is
  rendered by nothing.** One account finished while another still has work: asserted twice as a
  value and a sentence, reached by no automated run of any kind. **Not** FR-070's kind of state —
  it is perfectly seedable (`crossing` has two accounts), so it is a strict hole in SC-018. Found
  by T183's mechanical walk of all 78 FRs and 36 SCs, which is the only thing that could have
  found it: the traceability tables are complete for *assertions* and silent about requirements
  no assertion is named after. Reported and not closed, per T183's own instruction.
- **`018/06`** (`ready-for-human`) — still **the only thing between 018 and SC-012**, and 020 did
  not sign it either. Three device timings, ~20 minutes with a physical phone.
- **`018/05`** (`needs-info`) — the render hang. 020 pushes a detail view over a deeply-scrolled
  list, which is *closer* to the untested combination than 018 was; the four reopen conditions
  are now written out precisely in `specs/020-categorize/quickstart.md`.
- **`019/03`** and **`.scratch/020-categorize/issues/01`** — the same Dynamic Type design question
  at two text sizes, both still open, neither this slice's to settle.

⚠️ **A CI failure here is a claim about the runner until it has been re-run.** #43's iOS job went
red on a test that had never failed, on a change that touched neither it nor anything it uses,
and passed on re-run of the identical commit. Read the *failure text* before the test name: an
`XCTest` assertion is a finding, and `Failed to get background assertion` / `Timed out while
synthesizing event` are claims about the machine.

**020 PR G is DONE** (T160–T183). Nothing new was built; everything built is now *shown* to hold.
`specs/020-categorize/quickstart.md` gained the **audit matrix** (which audit type × which
surface, with every un-audited cell named and reasoned), the **break ledger** (all fifteen
deliberate breaks with their **observed** failure text), **who signed what** (machine vs person,
with nothing in between), and five explicit deferrals. `docs/adr/0006-a-persons-decision-is-a-
different-kind-of-fact.md` is new and records both 🚨 findings, their regression tests and the
whole v8 + FFI surface in one place; `CONTEXT.md` gains **Memory**, **Merchant portion**,
**Deliberate blank** and **Unanswered**; `AGENTS.md` gains the build sequence in the imperative.
Gates: core-lint clean, **core-test 358/0**, **lint 0 violations (127 files)**, import-audit ten
scans OK, release-audit OK, **a11y-sweep TEST SUCCEEDED (57 UI, 0 failures, 0 skipped, 1,270 s,
Increase Contrast on)**. `specs/020-categorize/tasks.md` § *PR G — RECORDED* has the full
account; the six things worth carrying:

- 🚨 **A skip is a green run.** `SeededAccessibilityUITests.openMemoryOffer` threw `XCTSkip`, and
  **five** tests reach it, four of them the audits over the memory offer and the second action.
  On that branch SC-016's "zero findings" would have been vacuously true for two of the four new
  surfaces — and the `nil` branch is the **documented** failure mode of `crossing` (it must dodge
  dedup). Now `XCTUnwrap`. ⚠️ **It was latent, not firing.** PR F's "2 skipped" is two *unit*
  tests that pre-date 020 and are both correct (`databaseFileIsProtected` is device-only;
  `readsTheReferenceSet` is opt-in), each a declarative `.enabled(if:)`. **A skip count is not
  self-explanatory** — only `xcrun xcresulttool get test-results tests` settles which test it is,
  and the obvious inference here was wrong. `.scratch/020-categorize/issues/03`.
- 🚨 **Five of the fifteen breaks did not do what the queue predicted, and every difference would
  have read as success.** T027 turned *nothing* red (the two guards are not independent); T051
  missed P2 entirely — **what protects SC-008 is the reference-token discard, not the segment
  count**; T075 turned **three** tests red, not one; T117 and T154 each hit exactly one of the two
  things named. **Record the observed red, never the intended one.**
- ⚠️ **A first-failure-exits audit can only be observed one scan at a time.** `import-path-audit
  .sh` exits on the first failure, so T096's "scans 5/6/7 red" is unobservable as written — scan 5
  fires and the rest never run. Scan 7 needed its own probe. Any queue predicting a *set* of scans
  is predicting something the tool cannot show.
- ⚠️ **`cargo` is not on a non-interactive shell's `PATH`.** `.zshrc` sources `~/.cargo/env` and
  `make` from a script or an agent shell does not read it, so `make core-xcframework` dies with
  `cargo: command not found` inside `build-xcframework.sh` — a `PATH` problem that reads as a
  toolchain problem. Prefix `. "$HOME/.cargo/env" &&`. Now rule 3 of AGENTS.md's build sequence.
- ⚠️ **T157's break is in Rust, so watching it costs two full engine rebuilds** —
  `core-xcframework` → `ios-gen` on the way in *and* out, ~15 minutes for one line. It is worth
  it: X3 went red twice over, end to end through the app.
- ⚠️ **`make a11y-sweep` is a 21-minute gate** (it runs the whole UI bundle under Increase
  Contrast) and it is **not** part of `make ios-test`. FR-065 is satisfied across two targets and
  that is permanent, not a gap waiting on a fix (T180).

**020 PR F is DONE** (T141–T159). A person can now see, on the app's first screen, how many of
their transactions have no category; open exactly those across every account; narrow them
further to one card; answer them one at a time and watch each leave; deliberately file one under
nothing and watch that count as an answer too; and be told, when the last one goes, that they are
finished — in words, never as a "0". `ios/Sources/Categorize/` gains `UncategorizedEntryPoint
.swift` and `CategoryChangeSignal.swift`; `EmptyKind` grows the two rows `data-model.md` §6
predicted. Every gate green: `make lint` **0 violations (127 files)**, `make ios-test` **TEST
SUCCEEDED — 409 passed, 0 failed, 57 UI tests, 1,194 s at load 4.1**, `make import-audit` ten
scans OK. `ImportService.swift` **unchanged at 398 lines**; `git diff core/` empty.
⚠️ **That run's "2 skipped" is two pre-existing *unit* tests** — `databaseFileIsProtected`
(device-only) and `readsTheReferenceSet` (opt-in) — **not** the `XCTSkip` PR G found.
`specs/020-categorize/tasks.md` § *PR F — RECORDED* has the full account; the five things worth
carrying:

- 🚨 **`.textClipped` fires on the *shipped* 018 row at the DEFAULT text size, and only the
  fixture had ever hidden it** (`.scratch/020-categorize/issues/01`). Seeded with `unfiled`,
  whose descriptions are eight characters longer than `small`'s, the **unnarrowed** list fails
  the type with nothing of PR F on the screen — proved by three probes, one per surface. The
  exclusion is scoped to the list half of A18–A21 and nothing else, because on the **door** the
  same type caught a real defect: drawn as `Label(_:systemImage:)` it was reported clipped at the
  default size, *naming its own element*; drawn as a plain `Text`, like the account rows beside
  it, it passes. 019's `issues/03` asks the same design question one text size up and both are
  still open.
- 🚨 **The queue named the wrong gate for T154.** Filtering the page in Swift turns **scan 5**
  red exactly as written; **scan 6 cannot fire** — it is the filter-*persistence* scan and looks
  for `UserDefaults` — and the audit exits on the first failure, so it never even runs. The
  behavioural half is sharper than promised: three `TransactionNarrowingTests` assertions go red
  naming the field that drifted.
- ⚠️ **L6 needed exactly one edit, and it is the finding T156 asks for.**
  `TransactionListDoubles.swift` changed because the seam gained an axis and a double is a
  conformance. **No expectation moved** — `PageRequest.uncategorizedOnly` defaults to `false`. A
  three-argument spelling of `page` was rejected as PR C's "silently omit a fact" shape.
- ⚠️ **The count needed a signal.** `CategoryChangeSignal` mirrors `ImportCompletionSignal` and
  is deliberately not it, carries `Void`, and is subscribed from **`RootView`** rather than the
  door — a `.task` on a `List` row is a subscription that dies with a row.
- ⚠️ **Four SwiftLint limits at once, all answered by moving something out** — never by
  reformatting. `CategorizeStrings.finishedState(accountName:)`,
  `TransactionWorklistEmptyStateTests`, `AccessibilityAudit.swift` and
  `SeededWorklistAccessibilityUITests` are all that split.

**020 PR E is DONE** (`0468cee`, T122–T140). A person can now correct a transaction, be asked in
their own words whether Kaname should remember the merchant, decline that without touching the
correction, and — if they accept — be told exactly how many transactions in which accounts would
change **before** anything is written. `ios/Sources/Categorize/` gains `MemoryOfferView.swift` and
`SecondActionView.swift`; `ios/Sources/DebugSeed/SeedMemoryScenarios.swift` adds the `repeated`
and `crossing` scenarios; three unit suites and two UI suites are new. Every gate green:
`make lint` **0 violations (119 files)**, `make ios-test` **TEST SUCCEEDED (49 UI tests, 1,024 s
at load 2.8)**, `make import-audit` ten scans OK, `make release-audit` OK.
`ImportService.swift` **unchanged at 398 lines**. `specs/020-categorize/tasks.md` § *PR E —
RECORDED* has the full account; the five things worth carrying:

- 🚨 **A geometry assertion found a real hit-target defect that the accessibility auditor did
  not.** Both new sheets' answers rendered **34.33 pt** tall **at the default text size** — under
  FR-062's 44 pt — while all four `performAccessibilityAudit` runs stayed green. The cause:
  `.buttonStyle` draws its background around what the **label** asks for, so a `.frame(minHeight:)`
  outside a styled button sizes the space around a control that stayed small. `SheetAnswer` puts
  the minimum on the label. **Second time this repo has recorded it** — A12 was the first. On
  these controls, hit targets are measured or they are not checked.
- 🚨 **Every correction now leads to a sheet, and that broke a test that changed by nothing.** X2
  reached for the detail surface underneath the new offer and failed as "not hittable", which
  reads exactly like a layout defect. `SeededLaunch.dismissMemoryOffer` is the shared way through
  it. ⚠️ Anything that changes a category from now on must expect the offer.
- 🚨 **The second action changed rows the list behind it was still holding, and nothing said so.**
  Watched: agree, go back, read three stale categories. Fixed through `refreshAfterCorrection` —
  the seam a single correction already uses — rather than by patching rows. **The queue did not
  ask for this**: K5 is written about one row, and this is the first thing in the app that changes
  rows the current screen is not showing.
- ⚠️ **The picker cannot be found by the name of the thing you are choosing.** The current choice's
  spoken label carries its mark (`No category, Current category`), so `app.buttons["No category"]`
  finds nothing on an *unanswered* transaction — which is every transaction a memory test starts
  from, and it reads as a missing control. `SeededLaunch.chooseCategory` matches the prefix.
- ⚠️ **A declared blast radius has to be adjudicated for completeness, not just correctness.**
  `SeedMemoryExpectationTests` asks the engine in both directions — every named description
  derives to the portion, and **no other row in the scenario does**. Dropping one entry from
  `repeated`'s `alsoMatching` was watched turning both arms red. An `alsoMatching` that is merely
  correct understates the one number the second action exists to state.

**`020-categorize` PRs A–D are MERGED — [PR #42](https://github.com/SSKUltra/kaname/pull/42),
merge commit `f6171b3`, both CI jobs green (Rust core 1m6s, iOS 30m31s).** A person can open a
transaction and change its category on `main` today. Work continues **on the same branch**,
`020-categorize`, which is fast-forwarded to the merge commit and clean — exactly how 019 ran
(#40 then #41). PRs **E, F and G** (T122–T183) become the second pull request.

⚠️ **The engine halves of E and F already shipped in #42, tested and uncalled**:
`preview_memory_application` / `apply_memory` have no Swift caller until PR E, and
`uncategorized_count()` has no entry point until PR F. That is deliberate, and it means a
"nothing calls this" search is not evidence of a mistake.

✅ **PR D's gate is green.** `make ios-test`: **297 unit tests in 59 suites + 39 UI tests, 0
failures, 782 s**. ⚠️ The same commit had previously taken **18,322 s** and failed one test with
`Timed out while synthesizing event`, at load average 20–120; on a quiet host (load 3.7) it is 23×
faster and clean. **A UI-test failure on this machine is a claim about the machine until the load
average has been looked at** — check `uptime` before debugging one.

**020 PR D is DONE** (`b6112a0`, T094–T121). A person can now open a transaction and change its
category: `ios/Sources/Categorize/` (strings, scope, catalog, service, detail surface, picker),
five new unit suites, X1/X2 over a seeded launch, three accessibility audits plus a hit-target
measurement over the two new surfaces, and the `unfiled` scenario. `make lint` clean (111 files),
`make import-audit` ten scans green with the widened scope, `ImportService.swift` **unchanged at
398 lines**. `specs/020-categorize/tasks.md` § *PR D — RECORDED* has the full account; the five
things worth carrying:

- 🚨 **A row that becomes a `NavigationLink` stops being a `StaticText` and becomes a `Button`.**
  This turned **018's `SeededTransactionListUITests` red** and looked exactly like R2 being
  violated — the row losing its combined element. It had not: the whole sentence is intact on the
  cell's **button**, with the description, account, category and amount still underneath it.
  Nothing a person hears changed. `SeededLaunch.visibleLabels` now reads the sentence wherever it
  is; anything else that identifies a row by "the first `StaticText` in the cell" will break the
  same way. ⚠️ Both placements of `.accessibilityElement(children: .combine)` — on the link, and on
  its content — were measured and are identical, so the placement is **not** load-bearing.
- 🚨 **The source-level R2 assertion passed the whole time the behaviour was red.** It checks the
  modifiers are present in `TransactionRowView.swift`, and they were. Only the seeded run could
  tell. Keep it (it catches the `.opacity(0)` hidden-link trick, which passes a screenshot) but
  never mistake it for the gate.
- 🚨 **The system auditor found four real Dynamic Type defects at the DEFAULT text size** — the
  first audit ever run against these surfaces, and precisely the return 019 was bought for. A
  `Section("string")` header, a `Text` carrying a bare `.accessibilityLabel`, a prominent `Button`
  inside a `List` row, and a **titled toolbar button**. The first three have structural fixes (an
  explicit `Text` header; draw a fact the way the other facts are drawn; put the action in a
  `.safeAreaBar`, which also gives D6 at *every* text size). The fourth passes **only** as an SF
  Symbol with a spoken label — `Button("Cancel")`, an explicit `Text` label, and dropping the
  redundant `.buttonStyle(.glass)` all still failed. No other audited screen here has one.
- ⚠️ **The widened scan forbids the picker from sorting the catalog, and it is right.**
  `list_categories()` is already `ORDER BY rowid`, so a Swift-side sort is a second opinion about
  an order the engine settled. The grouping preserves the engine's order and U1 asserts *that*.
- ⚠️ **T117's break turns the K3 unit assertion red and leaves X2 green.** The queue predicted
  both would fail; the mark on the current category is simply not on X2's path. That is why K3
  lives on `CategoryChoice.isCurrent` as a pure rule rather than privately inside the view — and
  it is the same shape as PR C's finding that only Q3 gates the v8 index.

⚠️ **What a loaded machine does to this gate, measured on one unchanged commit.** The first full
run took **18,322 s** (five hours) at load average 20–120 and failed one test with `Failed to
swipe up CollectionView: Timed out while synthesizing event` — the simulator could not deliver a
gesture. Individual re-runs of that suite passed at 24 s, 985 s, 1,075 s, 1,537 s and 3,145 s for
work that normally takes 15–25 s. The **same commit** then ran clean in **782 s** at load 3.7.
Nothing was changed between them. Check `uptime` before chasing a UI-test failure here, and never
chase a `synthesizing event` timeout at all.

**020 PR C is DONE** (`e42bcf4`, T077–T093, **348 → 358 core tests**, every gate green:
core-lint, core-test, lint, `ios-test` **TEST SUCCEEDED** (33 UI tests), `import-audit` ten scans
OK). It shipped `HistoryQuery.uncategorized_only`, `HistoryRow.category_id`,
`Store::uncategorized_count()`, the `page_sql!` macro that spells the page statement once, and
Q1–Q3. `specs/020-categorize/tasks.md` § *PR C — RECORDED* has the full account; the five things
worth carrying:

- 🚨 **PR C could not be engine-only, and the queue says it is.** A new `HistoryRow` field breaks
  **every Swift memberwise construction of it** — ten call sites, seven files — because uniffi
  generates an initializer with no default for a new field. `#[uniffi(default = None)]` would have
  kept the Swift tree untouched and was **rejected**: a double that can silently omit a fact the
  engine always populates is the exact quiet failure this repo keeps finding. Expect the same the
  next time a `uniffi::Record` grows a field. (`HistoryQuery`'s new field *does* carry a default —
  it is an **input**, and FR-046's "every existing caller keeps its behaviour" is the point.)
- ⚠️ **Q2 does not gate the v8 index — only Q3 does.** T091's break turned Q3 red with `s1`, `s2`
  and Q1 green as predicted; **Q2 stayed green too**, because the narrowed page falls back to the
  v7 index and is still a `SEARCH` on a named index with no `TEMP B-TREE`. If Q3 is ever weakened,
  nothing else in the suite notices `idx_txn_unanswered_account_date` going missing.
- ⚠️ **H5 is a drift gate, not a correctness one.** Break the provenance arm of
  `unanswered_predicate!()` and C5 and H2 go red — **H5 stays green**, because the count and the
  list agreed, on the wrong set. Do not read a green H5 in PR F as "the worklist is right".
- **One predicate, one spelling — via the macro, not the constant.** A `const` cannot be
  interpolated into another `const`, so `PAGE_SQL` / `PAGE_SQL_UNANSWERED` are two expansions of
  one `page_sql!` and the count is `UNCATEGORIZED_COUNT_SQL`. `UNANSWERED` keeps its
  `#[allow(dead_code)]`: it is now a *name* for the rule, not a reader of it. **H1 pins
  `PAGE_SQL`'s full text**, which is the only reason the macro was safe to introduce.
- **R13's plans are now measured on the real SQLCipher store** and reproduce exactly: `SEARCH t
  USING INDEX idx_txn_unanswered_account_date` for the narrowed page, `SCAN transactions USING
  INDEX idx_txn_unanswered_account_date` for the count. That settles **three** statements on one
  corpus on one machine — T178's "not a survey" is recorded as such.

⚠️ **A wall-clock failure is a claim about the machine until you measure the machine.** A re-run of
`history_perf` alone failed `s4` (worst page 73.7 ms, budget 25 ms) and `s5` on a host at **load
average 120** with an unrelated `ffmpeg` at 392% CPU. `HEAD` was stashed to and run under the same
load: **`s4` fails there too, worse — 127.2 ms.** Two minutes of `git stash` settled it. Do that
before chasing `s3`–`s7`.

⚠️ **Do NOT re-run `speckit.specify` / `plan` / `tasks` for 020** — all three are committed
(`adf9206`, `8268268`, `2d05d56`), Q1–Q3 are answered (D / B / C), and the design is locked.
019 is **DONE** — T001–T101, all four PRs, every gate green; do not re-run it either.

**020 PR B is DONE** (T041–T076, **324 → 348 core tests**, fmt + lint clean, **no tracked Swift
file touched**). It shipped the derivation (`core/src/merchant.rs` + its 33-case fixture), the
`merchant_memory` upsert inside `set_transaction_category`'s existing transaction, the
consultation of that memory in `categorize_account_in` **before** the stack, and
`preview_memory_application` / `apply_memory` with set-equality staleness.
`specs/020-categorize/tasks.md` § *PR B — RECORDED* has the full account; the five things worth
carrying:

- 🚨 **T051's break turns P1 and P5 red, not P2 — the queue named the wrong test.** Keeping three
  segments instead of two does not stop the four `UPI-SWIGGY-*` shapes collapsing, because each
  has exactly **one** surviving segment. What actually protects SC-008 is the **reference-token
  discard**: remove it and P2 fails with `swiggy 123456` against `swiggy`. Both breaks were run;
  both reverted.
- ⚠️ **M6 cannot be staged by importing another matching row**, which is what T067 says to do. An
  import re-categorizes the account's undecided rows through the same memory, so the rows change
  for a *legitimate* reason and the test cannot tell that apart from a partial apply. M6 removes
  a row instead. The underlying fact matters for PR D: **a preview goes stale because an import
  happened**, and `StaleSet` is what the person meets when it does.
- **`apply_memory` is guarded on `PERSON`, not on `ENGINE_MAY_DECIDE`**, deliberately: the write
  *is* a person deciding, so it must replace an earlier `PERSON_MEMORY` (FR-031a) while never
  touching a hand correction. `ENGINE_MAY_DECIDE` there would make a second offer write 0 rows.
- **C7 passed on its first run and was broken on purpose to prove it can fail** (commit the row,
  then open a second transaction for the memory → C7 red). T059 was satisfied by T055's code, not
  by new code, and that is recorded rather than dressed up.
- **Two doc discrepancies, resolved toward the contract**: the function is **`apply_memory`**
  (not `apply_memory_application`), and research R14's "69-word" stop-list actually lists **76** —
  the list shipped, with a unit test pinning the count, no duplicates and no upper-case entry.

⚠️ **PR B changed the FFI surface twice** (the free `merchant_portion`, then `MemoryImpact` /
`AccountImpact` / `StaleSet` / the two `Store` methods); both `make core-xcframework` **then**
`make ios-gen` runs are done and the Swift bindings are present
(`previewMemoryApplication`, `applyMemory`, `merchantPortion`). PR C changes it again (T086/T087).
⚠️ `cargo` is not on the default PATH: `export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"`.
⚠️ Never run `make core-test` and `make ios-test` concurrently (`history_perf::s5` is wall-clock).

**020 PR A is DONE** (`5ce166b`, T001–T040, **310 → 324 core tests**, lint clean, privacy audit
OK, **no tracked Swift file touched**). It shipped schema **v8** — additive only, a
`merchant_memory` table and one partial index — the three predicates spelled once, the
`set_transaction_category` write path with `'PERSON'` provenance, and guards on both engine
write paths. `specs/020-categorize/tasks.md` § *PR A — RECORDED* has the full account; the four
things worth carrying:

- 🚨 **`NULL NOT IN ('PERSON', 'PERSON_MEMORY')` is `NULL`, not `TRUE`.** Watched: with the naive
  guard, **C2 went red and C1 stayed green** — every row an import had just inserted was
  discarded and *nothing errored*. `ENGINE_MAY_DECIDE` must keep its `IS NULL OR` arm forever.
- **Two live defects were fixed, both watched failing first**: a re-import wrote
  `FOOD_AND_DINING / T1_SOURCE_CATEGORY` over a person's `GROCERIES / PERSON`, and
  `detect_transfers` wrote `CREDIT_CARD_BILL_PAYMENT` over a person's `SHOPPING`.
- ⚠️ **The two guards are not independent, and the queue assumed they were.** Removing the
  *load*-site guard turns nothing red — the write-site guard covers C1 alone. **C8** now pins it:
  without it the stack decides a category, reports it as `categorized`, and writes nothing.
- **PR A deferred C4/C7 to PR B and C5 to PR C**, with reasons. **C4 and C7 are now paid**;
  **C5 is still open and belongs to T085.**
- **One finding for PR D**: `everyStoreFailureMapsToTheSameThing` in
  `ios/Tests/TransactionHistoryServiceTests.swift` is now one case short of the "every" in its
  name (`.NotFound`) — and **`.StaleSet` makes it two short as of PR B**. Harmless today — the
  mapping takes `_: Error` and discards it.

**What 019 bought, in one sentence:** an automated run can now open a screen with a person's own
transactions on it, so the accessibility auditor finally has something to audit — **UI tests went
from 6 to 33**, and six of 018's fourteen manual gate steps are now run by a machine.

**What it cost the shipping app:** three lines in `ios/Sources/KanameApp.swift`, inside
`#if DEBUG`. Nothing else. No Rust file, no FFI change — **schema was v7, and 020 PR A took it
to v8**.

⚠️ **It paid for itself on its first run.** The first `performAccessibilityAudit` ever pointed at
a populated list found two shipped defects: a date heading rendering grey because
`.foregroundStyle(.primary)` is the *hierarchical* style and resolved to a no-op, and a pinned
heading with nothing behind it — `018/issues/07`, which a person had found at XXXL after forty
minutes of manual gate and which a machine reproduced at the **default** text size in twelve
seconds. Both fixed.

⚠️ **Four findings are open and written up in `.scratch/019-debug-test-seeding/issues/`.**
`01` — three `Contrast failed` verdicts on the filter bar that name **no element**, with the
chip's own text measured at 9.48:1 from the audit's own screenshot; a suppression was rejected
because the real heading defect *also* named no element. `02` — three `EmptyKind` cases are
unreachable by any seed (see §7). `03` — at XXXL the list fires `.textClipped` and `.dynamicType`
by design, so those two types are excluded there and the exclusion cost FR-038 the instrument it
had planned to use. `04` — a wall clock in a UI test measures the machine.

⚠️ **What FR-038 taught, and it generalises.** (1) **A fixture that cannot express a defect cannot
watch a gate catch it** — `SYNTHETIC BANK ONE` is three short words, both parked 018 defects are
defects of a *long name at a large text size*, and neither break went red until the fixture's
account name was as long as a real card product's. (2) **The system auditor is the weaker
instrument here**: reinstated faithfully, `018/02` rendered `••••…` over `SYN-T…NE` and
`performAccessibilityAudit` **passed**. (3) **A label cannot show a truncation** — XCUITest reports
a `Text`'s string, not its glyphs. Geometry carries both defects now, and both were watched red.

⚠️ **018's SC-012 is still open**, and nothing in this slice closes it. `018/issues/06`'s three
device timings have never been measured and still need a phone; **T085 could not be run** for the
same reason, so the "under twenty minutes" figure for the shrunk gate is **unmeasured and is
recorded as such** in `specs/018-transaction-list/quickstart.md`.

**Where to read the detail:** `specs/019-debug-test-seeding/tasks.md` §§ *PR B/C — RECORDED*,
`quickstart.md` § *What it turned out to be*, and the rewritten gate record in
`specs/018-transaction-list/quickstart.md` § *The manual, release-blocking gate*.

**The traps this slice found, in one list.** Every one of them fails *quietly* — the shape of
mistake that reports success. They are written out in `AGENTS.md` § *Seeding a screen with data*
and summarised here:

- **A row's sentence is not on its cell**, and a date heading is a cell too — tell them apart
  structurally, never by wording. And a `List` renders a **screenful**, not a list.
- **A seeded store outlives the suite that wrote it**; so does `XCUIDevice.shared.appearance`.
  The `empty` scenario and `SeededLaunch.pin` exist for those two.
- **Two credit cards never de-duplicate, silently** — cross-source dedup compares a ledger against
  a card and nothing else. Only the fixture's own row count notices.
- **A wall clock in a UI test measures the machine** (`issues/04`).
- **Adding a file needs `make ios-gen`** — and a suite that never ran reports success. This one bit
  twice: once in PR A against the Release audit, once in PR D against a new unit-test file.

**Still true from PR A**, and it will bite anyone adding a file:

- ⚠️ **Tuist resolves `sources: ["Sources/**"]` at generation time.** A file added since the last
  `make ios-gen` is compiled by nothing, so its absence from the Release binary proves nothing —
  three `release-audit: OK` runs and two break verdicts were recorded before this was noticed, and
  every one looked like a pass. `make release-audit` now checks `project.pbxproj` membership first
  and fails as **inconclusive**. **Run `make ios-gen` after adding any file.**
- ⚠️ **`nm -a` includes the debug map, which names source files**, so a *correctly guarded*
  `DebugSeed.swift` shows up three times in a binary holding none of its code. The scan uses plain
  `nm` (4,511 symbols, not 12,249 stabs).
- ⚠️ **`nm … | grep -q` fails under `pipefail` even when it matches** (SIGPIPE) — match in a
  variable, never in a pipe.
- Six breaks were watched: an unguarded but *unreferenced* type is dead-code eliminated, so Scan B is
  honestly silent for breaks 1, 2 and 4; a **referenced** one is caught by `nm`, a literal on a live
  path by `strings` alone, and an unguarded shipping reference to DEBUG-only code fails the Release
  **build** — the compiler is a third gate.
- **CI now runs `make import-audit` (ten scans) and `make release-audit` for the first time**, and
  lints `UITests` too. To exercise the widened lint you need a violation only `swift-format` rejects
  (`[NoBlockComments]`) — SwiftLint runs first and shares `[LineLength]`.

The slice is scheduled in
`docs/kaname-ios-plan.md` before the categorize slice, and 018 is the reason it should stay there:
**no automated run can reach a populated transaction list at all.** The list is behind an import,
the import is behind the system document picker, and FR-077 forbids a seeding hook in the shipping
app — so every P3 screen that shows a person's own data is manual-gate-only, half an hour of
somebody's afternoon each, and 018's own SC-012 is still open because of it. Read
`.scratch/018-transaction-list/issues/01-manual-accessibility-gate-not-run.md` first — now
**resolved**, it is the itemised bill for not having this: forty minutes by hand, and four
defects (`issues/02`–`05`) that no automated gate in this repo could have caught, on a screen no
automated run can even reach. **Do not re-run `speckit.specify`/`plan`/`tasks`** — all three are
committed (`2bbc753`, `9aed2f7`, `705f5ae`, `d7bafe5`).

⚠️ **The planning pass discovered the slice cannot be a Rust one, and this is the single most
load-bearing fact in it.** `core/scripts/build-xcframework.sh` runs `cargo build --release` **once**
for all three Apple targets, and that one xcframework links into **both** Xcode configurations. So
`#[cfg(debug_assertions)]` is already OFF in the DEBUG app and a cargo feature compiles straight
into Release: **there is no Rust construct present in DEBUG and absent from Release.** The slice is
Swift-only. No FFI change, no `make core-xcframework`, no `ios-gen` dance, no risk to
`history_perf::s5` — and **schema stays at v7**, recorded as a deliberate non-change, because a
migration would have been the tell that seeding had stopped going through the front door.

⚠️ **The absence proof builds its own binary and refuses to trust itself.** `-showBuildSettings`
reports `STRIP_STYLE = all` but `DEPLOYMENT_POSTPROCESSING = NO`, so research built a real Release
artifact and simulated the strip: **12,249 symbols → 157**, and a known *shipping* type left
`strings` entirely. A naive artifact scan would have **passed for the wrong reason**. `make
release-audit` therefore scans both `nm` and `strings` and will not conclude an absence unless it
first finds a symbol and a literal it knows are present — failing as **inconclusive** otherwise.
Break 5 of the five deliberate breaks is pointing it at a stripped copy.

⚠️ **CI has never run `make import-audit` — not once.** All nine scans, including the networking
scan that is the platform half of Principle I, run only when somebody remembers. CI also lints
`Sources Tests` while `make lint` lints `Sources Tests UITests`. FR-043a closes both in PR A,
because 019 is about to add a tenth scan whose entire value is that it fails a build.

⚠️ **Four spec amendments after planning, all cases of believing the codebase over the draft**
(spec § *Amendments after `/speckit.plan`*). **FR-008a**: seeds cannot express deleted rows or
transfers — `is_deleted` has no write path in `store.rs`'s API (the only `SET is_deleted = 1` is
raw SQL in an engine test helper) and `is_transfer` is written only by `detect_transfers`, which
`import-path-audit.sh` bans the app from calling. **FR-039a**: `EmptyKind.nothingImported` is
unreachable *by construction* — its precondition is empty account summaries, and `RootView` hides
the list's only entry point under that same call, so no seed satisfies both; it gets host-rendering
without an audit, said plainly rather than folded into a "100%" that would not be true.
**SC-008**: six steps automated, eight remaining, under twenty minutes — the draft's five left
G10/G13/G14 homeless, and G13/G14 need a live import *through the picker*, the one interaction
seeding structurally cannot stage. Two more verdicts are deferred into tasks: `nothingToShowAnywhere`
may be a second FR-039a exception (T058/T080), and a third **`barren`** scenario is needed because
neither `small` nor `deep` can produce a store with zero live rows.

⚠️ **The 2026-08-17 session strengthened the case considerably.** Closing `018/02` took **two**
attempts: the first fix passed every unit test in the repo and was still broken on screen, because
the tests prove *which fact leads* and a pure layout decision **cannot see a width**. What caught it
was a person at XXXL and a screenshot. Meanwhile `018/03` could not be run at all until a **six-row
`gate/` corpus** was added to `make perf-corpus`, since G2 asks about the *end* of a list and at
XXXL the 10,000-row corpus puts that hundreds of flicks away. So the slice's value is measured, not
asserted — and FR-038/SC-006 make it a *requirement* that the new coverage be watched failing
against `018/02` and `018/03` reinstated on purpose (T073, T076). ⚠️ One honest caveat: R10's claim
that `performAccessibilityAudit` fires `.textClipped` for 018/02 is **inferred, not observed** — the
seven iOS audit types have no occlusion check — so T074 determines it and T075 falls back to a
second geometry assertion rather than a weakened criterion.

**State at hand-off (2026-08-18, everything committed, `main` clean):** 016 has **nothing open**;
018 has `issues/06` (deferred, needs a phone — **still the only thing between 018 and SC-012**)
and `issues/05` (`wontfix`, with its reopen conditions written down); **`issues/07` is resolved**
by 019. 019 has four findings open, all `ready-for-human` and all written up
(`.scratch/019-debug-test-seeding/issues/01`–`04`). Green on both gates: 310 core tests,
**278 iOS unit tests in 54 suites**, **33 UI tests**, lint 0 violations, ten audit scans, the
Release absence audit, and `make a11y-sweep` over a populated screen.

**What 017's reference pass measured** (13 real statements, on the holder's machine, counts
only): statements reading **zero** transactions **10 → 0**; **unrecognised 2 → 0**. Re-run it
any time with `make reference-check DIR=…`, and `make reference-shapes DIR=…` to describe a
document that reads nothing — the latter prints each line with every value replaced (digits →
`9`, letters → `A`/`a`), so a layout can be diagnosed, and pasted into a bug report, without a
statement leaving the machine.

**017 is also fully merged** (PR #36, #37) and nothing in it is open, R15/T119 included.

018 is specified, planned and broken into **147 tasks** — `specs/018-transaction-list/`. **Do not
re-run `speckit.specify`/`plan`/`tasks`**: the design is locked, and its two clarifications and
two judgement calls are settled (spec § *Clarifications*, plan § *Judgement calls*).

**Everything is merged**: PR A0 is #38, and **A through E plus the follow-ups are #39** — one PR
of 21 commits, because they were built and gated together on `main` rather than as five stacked
branches. T001–T138 and T141–T147 are done; **T139 is partial and deferred** (see the ticket
above), T140 is recorded as it was actually run. A person can now open the app, tap once,
read their own transactions across every account newest-first and grouped by date, narrow to one
account and clear it again in a single tap, be told which of six true things is the case when a
screen is empty — and see a statement they have just imported appear in a list they are already
reading, without losing the filter they set or the row they were on. Importing the same statement
a second time changes nothing they can see, and the filter is forgotten on relaunch, deliberately.
**None of PR B, C, D or E has been opened as a pull request yet.** Their commits are all on `main`
(`738cbe1`, `ea7ba68`, `1a8054f`, `572f0b4`, `94aa894`, PR D's and PR E's).

**What PR E landed**: `ImportCompletionSignal` — the process's one broadcast `AsyncStream<Void>`,
yielded by `ImportService` **after** `import_statement` commits and on no other path — plus
`refreshAfterImport()` (the held pages re-read from page 1 with the same filter and swapped in as
*one* change), scroll-anchor capture and restore through `.scrollPosition(id:)`, and two
subscribers: the list and the front door, so a count and a list can never be read from two
different moments. Two suites — `ImportCompletionSignalTests` (I1–I4 + the cancelled-import
no-transition case) and four new refresh invariants in `TransactionFilterTests` — and **eight
deliberate breaks were watched going red**, including a signal sent one line early (six tests) and
a refresh that resumed from the cursor the old read had reached.

⚠️ **Two defects PR E found in shipped code, both fixed.** `TransactionListViewModel` had **no
generation guard**: a page read still in flight when the filter changed would append the *old*
account's rows to the *new* population — FR-040, silently. And `TransactionHistoryService` was
handed an already-open `Store`, which meant `StoreProvider.shared()` — SQLCipher's first open —
ran on the **main thread**, from a view body; it now takes `init(opening:)` and opens inside the
actor. A third, smaller one: the prefetch check flattened every row read so far on **every**
scroll tick (ten thousand ids allocated to answer a question about ten), and now walks backwards
by index.

⚠️ **`ImportService.swift` is at 393 lines** (limit 400). PR E spent the headroom T067 created by
moving `PendingImport` and `PipelineOutcome` into `ImportModels.swift` — the file's own budget is
now 7 lines, and the next task to touch it must move something out, not reformat.

**What PR D landed**: four suites — `TransactionAmountTests`, `TransactionCategoryTests`,
`TransactionTransferMarkingTests`, `TransactionAccessibilityTests` — plus three more audit scans
(no aggregate, no `.tint(`, no `detectTransfers` call **or detection claim** anywhere in
`ios/Sources` or `ios/Tests`) and one contrast fix: a `Section` header renders de-emphasised by
default, and a date is content, so the heading now carries an explicit `.foregroundStyle(.primary)`.
Five breaks were watched, including a `Double` on the amount path that turned ₹1,234,567.89 into
`−₹1.2M` and 66.660 KWD into `67`.

⚠️ **Two findings worth carrying forward.** **T118 as specified is impossible**: the front door
hides its "All transactions" link until an account exists, an account needs a real imported
statement, and importing needs the document picker — so **no automated run can reach the
transaction list at all**, and FR-077 forbids the DEBUG seeding hook that would fix it. The UI
test now asserts that reachability fact instead, and the populated list has **no automated
appearance coverage** — it is manual-gate only. Second, for the same reason,
`EmptyKind.nothingImported` is **unreachable on the transaction list** in the shipped app; the
branch is defensive and stays.

**What PR C landed**: the **filter chrome** — a `GlassEffectContainer` on an opaque
`.safeAreaBar(edge: .bottom)` holding a scope `Menu` and a clear button, both `.buttonStyle(.glass)`
with `glassEffectID` in one `@Namespace` — plus the view model's scope surface (`scopeTitle`,
`scopeSubtitle`, `scopeAnnouncement`, `isFiltered`, `availableFilters`, `showsFilterChrome`,
`emptyActionIsProminent`) and three test suites: `TransactionFilterTests`,
`TransactionEmptyStateTests`, `TransactionListStringsTests`. **Six deliberate breaks were watched
going red**, including the one T093 demanded. ⚠️ **T098 found and fixed a real defect**:
`.glassProminent` was being applied to *every* empty state with an import action, but design note
D2 permits it only where there is no filter bar — state 3 was shipping two prominent glass
elements. And the audit gained a **sixth scan**: `UserDefaults`, `@AppStorage`, `@SceneStorage`,
`NSUbiquitousKeyValueStore`, `NSUserActivity` and `FileManager` are banned under
`ios/Sources/Transactions/`, because FR-041 is a promise about what the app *cannot* do.

**What US4 landed**: `ios/Tests/TransactionListOrderingTests.swift` (7 tests over a real store:
newest-first across accounts, both same-date tie-breaks, byte-identical rebuild, identical across
a **relaunch** — a second `Store` over the same file — and a further account disturbing nothing),
`ios/Tests/TransactionListHeadingTests.swift`, and the row-edge tests in
`TransactionRowLayoutTests`. T078/T079/T081's *implementation* had already landed in US1, so the
substance was the proving: **five deliberate breaks, each watched going red** (a sorted page, a
shuffled page, `Date()` instead of the clock, a `(date, account)` grouping key, a total appended
to a heading). ⚠️ **The ordering fixture had to be rebuilt mid-phase** because its printed order
coincided with descending amount and let a break slip past — see `tasks.md` § "US4 — RECORDED".
T080 pinned rather than merely confirmed: the audit now also bans `sorted`, `sort(` and
`reversed` under `ios/Sources/Transactions/`.

**What US2 landed**: `ios/Tests/TransactionListLivenessTests.swift` — six tests over the **real**
import pipeline, a real encrypted store, the real bridge and the real view model (only extraction
and the clock are stubbed). Every one of them was **watched failing** against three deliberate
breaks before it was trusted, including the 016 defect put back on purpose; the count went *front
door 8, list 4*, exactly as it did to a person. T073 found nothing to delete, so it pinned:
`scripts/import-path-audit.sh` gained a **fifth scan** banning a `listTransactions(` call anywhere
under `ios/Sources` and any second opinion (`isLive`, `supersededBy`, `isDeleted`,
`rows.filter`/`sorted`) under `ios/Sources/Transactions/`. Read `tasks.md` § "US2 — RECORDED"
for the three deviations; the one that carries forward is that **SC-004's "after a deletion" is
still unreachable from Swift** and stays pinned engine-side (`history_live.rs` L1, L4, L5).

**What US1 landed** (`ea7ba68`): `ios/Sources/Transactions/` — the models, the copy deck, the
`actor TransactionHistoryService`, the paging + incremental-grouping view model, the row and the
screen; `StoreProvider` (one `Store` per process, so a page read can never land inside an
import's transaction); the front door's rows became `NavigationLink`s and stopped being
`LabeledContent`; **the front-door count became one `account_summaries()` call**; and the
networking audit widened from `ios/Sources/Import` to all of `ios/Sources`.

Green: `make lint` (0 violations), `make import-audit` (all **eight** scans), `make core-test`
(**308 tests**), the **unit target — 238 tests in 47 suites**. `ImportService.swift` is **397 lines**, three below the limit it sat
exactly on. Read `tasks.md` § "US1 — RECORDED" for the five deviations before continuing; the
two that change later work are:

- ⚠️ **US7's empty states landed early** (`EmptyKind.decide` = T096, the rendering = T098),
  because "shippable on its own" and "blank screen when you have nothing" cannot both be true.
  **T093 must still be written, and must be observed failing against a deliberately broken
  decision** — a suite that has only ever been green proves nothing about what it would catch.
- **The Swift corpus cannot build a deleted row.** `is_deleted` has no write path in the store's
  API, so `LivenessParityTests` proves the *superseded* half of the live rule end to end and
  names the gap; the `!isDeleted` half stays pinned engine-side (`history_live.rs` L1–L5).

⚠️ **T069 is unchecked, and not because of this slice.** `make ios-test` also runs the UI target,
where the **front door** fails a Dark Mode contrast audit at the largest text size — **verified
identical on a stashed, clean `main`**. Filed as
`.scratch/016-statement-import-vertical/issues/01-front-door-contrast-dark-mode-largest-text.md`
(`Status: ready-for-human`), with the two fixes already tried and reverted so nobody spends that
time twice. **Use `-only-testing:KanameTests` to gate 018's own work** until it is settled.

**What PR A settled, and the two things it found:**

- **The live rule is structural.** `live_predicate!()` is one literal, and `concat!` builds both
  the v7 index's `WHERE` clause and `PAGE_SQL` from it *at compile time*. A read that paraphrases
  the rule loses its index and the plan-shape gates go red; L6 re-reads the predicate out of
  `sqlite_master` and compares it to `LIVE` byte for byte.
- **A filter is `k = 1` over the same statement**, and a first page binds the identity cursor
  `('9999-12-31', 0)` — no separate filtered path, no separate first-page path. F3 proves it by
  running `PAGE_SQL` by hand and reproducing both reads.
- ⚠️ **A parse failure printed the row.** `invalid stored amount "1234.56"` put a person's money
  into an error string, in *every* path rather than just this one. Z2 caught it; both
  `amount_from_sql` and `date_from_sql` now name the column and nothing else.
- ⚠️ **S5 cannot be two-sided through `history_page`.** A page's fixed cost — one lock, one
  account list, one category catalog — divides by 2 accounts on the small corpus and by 8 on the
  large one, so the large corpus measures ~37% *cheaper* per account (research R9 measured 13% in
  the same direction, and called it correct). The gate asserts the claim it means: cost must not
  **grow** with the corpus.
- **Two deliberate deviations from `tasks.md`**: `SCHEMA_V7`/`PAGE_SQL` are `concat!`-built
  consts rather than a runtime `format!` (byte-identity at compile time is the stronger form of
  T018), and the two reads are exported from `store.rs`'s existing `#[uniffi::export] impl Store`
  block, where every other `Store` method lives — `ffi.rs` carries no `Store` code (T036).

Read, in order: `spec.md` → `plan.md` → `research.md` (R1–R20, with measured evidence) →
`contracts/` → **`tasks.md`** (the queue) → `quickstart.md` (build order + 14 traps).

**What 018 has settled — don't re-litigate it:**

- **One combined list across every account**, each row naming its account; a single account is a
  **filter** on that list, not a second screen. This is why a cross-account read is new engine
  surface (FR-043–FR-046) and why ordering must span accounts.
- **Nothing is converted across currencies, ever**, and no figure anywhere may be derived from
  amounts of more than one currency — which is also why a date group heading carries **no
  total** (FR-023–FR-027). Answered, not deferred.
- **`list_transactions` is the store's raw view** — deleted rows and superseded duplicates
  included, deliberately. `StoredTransaction.isLive` is the rule; the front-door count already
  got this wrong once (`3ba7890`). FR-007/FR-008 make it structural.
- **018's accessibility gate is manual**, because `performAccessibilityAudit` runs against a
  launched app and cannot reach any screen behind an import. A **DEBUG-only seeding hook is its
  own planned slice, before categorize** — it is what would make this automated for every
  remaining P3 screen. Not designed in 018.
- **Transfer marking is built; transfer *detection* stays unwired.** `detectTransfers()` is
  called from no Swift file, so `is_transfer` is always 0 in a real install. Wiring it is the
  **categorize** slice's work — it is an O(n²) pass on a path SC-006 already constrains.

**What PR A0 fixed, and what it left open:**

- **Cross-account dedup was non-deterministic.** Groups were ordered `a.created_at, a.id`, and
  two accounts created by one import share a `created_at`, so the tie-break fell to `a.id` —
  `randomblob(16)`. Over ten fresh databases the vanishing row alternated. Now `accounts.rowid`,
  the order `list_accounts()` returns and the person sees.
- **Two credit cards were de-duplicating against each other.** 013 exists for one purchase seen
  in two *different sources* — a ledger and a card. Only opposite kinds are compared now.
  `dedup.rs` is untouched; what changed is which pairs it is asked about.
- ⚠️ **Open finding**: the source guard is blunt. Two accounts of the **same kind** are now never
  compared at all, so two bank ledgers where one itemises the other's spends would double-count.
  A smaller wrong than hiding a purchase, but it belongs to whoever owns dedup next.
- **A determinism proof must re-exec the test binary.** A single-process assertion passes against
  that defect whenever luck holds — it did, on the first run.

**016's two manual gates are now RUN — 2026-08-15, on the simulator, and both pass.** T129
(smoke + failure matrix) and T123 (Reduce Transparency, VoiceOver, the five screens behind an
import) are no longer blockers. 018's **G1–G8 were run in the same session** — 6 pass, 2 fail.
What came out of it is **seven tickets**; read § *The 2026-08-15 gate run* below before picking
anything up.

**What 017 settled — don't re-litigate it:**

- **A line is a printed row, rebuilt from geometry.** See §7's extraction seam entry. The PDF
  text layer's newlines have no authority in either direction.
- **PDFKit gets word positions wrong in three separate ways**, and `WordGeometry.swift` is the
  only place that knows it (`research.md` R17). Its indices are over *glyphs* while `string`
  carries inserted line breaks; individual glyph rects come back nonsense at the end of a run;
  and `PDFSelection.bounds(for:)` is right but no finer than PDFKit's own line. Read that file's
  doc comment before touching extraction — every one of the three was found the hard way.
- **A gap is a gutter only if no printed row crosses it** (R18). The page-wide test alone cuts
  a ledger's continuation page along its own column gaps, because such a page prints rows and
  nothing else.
- **A block printed level with a row cannot be told from a column of that row.** It is joined,
  never invented as a row; the readers' anchored patterns then decline the polluted line, so a
  figure is lost rather than fabricated. Pinned in `PrintedRowsTests`.
- **Readers were widened for recognition in PR A, but their *rows* stayed brittle.** Scapia
  recognised its statement and matched none of its rows, because the pattern allowed exactly
  one character between a row's date and time and the page prints `date · time` spaced. Worth
  suspecting in any reader whose reference statement happens to print the spacing it expects.

**What 017 PR A+B settled — don't re-litigate it:**

- **A statement is identified by what it prints about itself.** `statement::claim` supplies
  the **identity region** (the document minus its transaction rows) and the **header region**
  (its first fifteen identity lines); claims are whitespace-insensitive. Every reader's
  `claims` fn now receives a `Regions` value, **not** the raw text and **not** the single
  `&str` the contract specified — a product claim is scoped to the title block (FR-047) and
  the identity region has already lost its line boundaries to normalization, so one string
  cannot serve both rules. The FFI surface is unchanged.
- **The two halves are one change.** Whitespace-insensitivity widens every bare-institution
  marker at once and `hdfc_bank::CLAIM_ALL` is literally `["HDFC"]`. Never widen matching
  without the region fence in the same commit. Gate **G7** has three cases and all three go
  red if the row exclusion is removed — including an *ICICI* ledger naming HDFC in a row,
  where `HDFC_BANK` sorts first and a false claim actually wins.
- **Cards are named per product, banks per bank**, ids `<INSTITUTION>_<PRODUCT>_CARD` /
  `<INSTITUTION>_BANK`, and every entry declares `ClaimEvidence`. **All six card readers still
  claim at bank granularity** — per-product identification is correct by uniqueness, not
  evidence. `HDFC_SWIGGY_CARD`'s `ProductProven` describes what its *document* can prove; its
  markers still accept a bank-level title. Gate **G1** (verified failing) is what forces a
  real discriminator the moment a second card for one institution is added.
- **G5 is a closed set, not an absolute.** Three shipped fixtures are already claimed across
  kinds (a `Federal Bank` card marker matches that bank's ledger) and `kind_rank` resolves all
  three correctly. They are named in `KNOWN_CROSS_KIND_CLAIMS`; a **fourth** fails the build.
- **Gate G6 is the standing no-regression proof**: `FIXTURE_ISSUER_BASELINE` in
  `tests/dispatcher.rs` maps every statement fixture to its issuer, and a companion test walks
  `fixtures/` so a new vector cannot skip it. Ids may be renamed there; a fixture may never
  change institution or kind.
- **`make ios-test` now wipes the simulator app first.** It was red on a clean checkout
  because a leftover container made the accessibility audit run against the accounts list
  instead of the front door. Remembering was not a gate; now it is.

`016-statement-import-vertical` is code-complete and fully merged — PRs A, B, C, D and E are
all on `main`. What remains there is the two manual gates only a person can run (T123 and
T129); they are release-blocking but they do not block 017.

⚠️ **Two findings now belong to 016's T123.**

1. **Filed, and blocking every iOS gate**:
   `.scratch/016-statement-import-vertical/issues/01-front-door-contrast-dark-mode-largest-text.md`
   — the front door's explanation fails the Dark Mode contrast audit at the largest text size,
   and **`make ios-test` is red on unmodified `main`** because of it. Verified pre-existing from
   018. Two fixes tried and reverted; the ticket records both.
2. **Parked, and still unverified**: the accessibility audit, run by accident against the
   accounts list at the largest text size, reported a contrast failure on a `StaticText '1'` at
   `{32, 724}` — consistent with `LabeledContent` switching to a vertical layout at accessibility
   sizes and dropping the transaction count to the leading edge under the bottom bar. 018 removed
   the suspected cause (`ImportedAccountsView` is no longer a `LabeledContent`), but the finding
   was never reproduced, so it is not closed by that. No automated test covers that screen.

P3 (the Core SwiftUI app) has begun. Its first slice is fully specified, planned and
broken into tasks; **do not re-run `speckit.specify`/`plan`/`tasks` for it** — the design is
locked and its four product decisions are settled (see the spec's `## Clarifications`).

Read, in order:
`specs/016-statement-import-vertical/spec.md` → `plan.md` → `research.md` (R1–R13, the
decisions with source-line evidence) → `contracts/` → **`tasks.md`** (136 tasks, the actual
queue) → `quickstart.md` (build order + smoke test).

**It shipped as five PRs, not one** (rationale + task ranges in `tasks.md` § "Recommended PR
split"):

| PR | Tasks | What | Status |
|----|-------|------|--------|
| **A** | T001, T006–T017, T035–T046 | Store hardening: the ⚠️ deadlock refactor, schema v6, atomic `import_statement` | ✅ **merged** (#31) |
| **B** | T003, T005, T018–T034 | The issuer dispatcher (`detect_issuer` / `read_statement`) | ✅ **merged** (#32) |
| **C** | T002, T004, T047–T069 | 🎯 The MVP vertical — first demoable build | ✅ **merged** (#33) |
| **D** | T070–T097, T137–T139 | Honest failures & account attribution (US2–US4) | ✅ **merged** (#34) |
| **E** | T098–T136 | Trust, responsiveness, front door (US5–US7 + polish) | ✅ **merged** (#35) |

**016's two manual gates are DONE — both run 2026-08-15 on the simulator, both pass.**

- **T123** — `quickstart.md` §6: ✅ **PASS.** Largest Dynamic Type, Dark Mode, Reduce
  Transparency, Increase Contrast and VoiceOver, across the summary, failure, password,
  account-picker and accounts-list screens. One defect against 016 came out of it
  (`issues/06` — the summary's title truncates to `Import comp…` at the **default** size).
- **T129** — `quickstart.md` §5: ✅ **PASS.** The 4-tap path, force-quit/relaunch, the same-file
  re-import and all six failure sentences. Two defects came out of it (`issues/04`, `issues/05`).

### The 2026-08-15 gate run — what it proved and what it cost

Both 016 gates and 018's **G1–G8** were run in one session, from a fresh install, against the
`make perf-corpus` corpus. **Eleven gates pass, two fail**, and **seven tickets** were filed.
Everything below is evidence, not impression.

**What the gates actually caught — none of it reachable by any automated gate in this repo:**

| Ticket | What |
|---|---|
| `016/issues/04` | ⚠️ **Fixed in this session.** `load_account_transactions` omitted `superseded_by IS NULL`, so categorization walked and counted superseded rows — the live-rule violation `3ba7890` fixed on the front door, arriving on the import summary. Now built from `live_predicate!()`; pinned by `categorization_counts_live_rows_only_after_a_reimport`, **watched failing first**. |
| `016/issues/05` | The summary mixes per-import figures (`Transactions`, `Duplicates skipped`) with account-wide ones (`Categorized`, `Left uncategorized`) under one "Imported" heading. Needs a product decision. |
| `016/issues/06` | ✅ **Resolved 2026-08-16.** The summary's nav title truncated to `Import comp…` at the **default** size, because a wide "Import another" sat opposite "Done". The action moved into the content, below the notices, where it can wrap — **not** deleted, which was tried first and would have traded FR-035 ("start another import **from it**") for a cosmetic fix. |
| `018/issues/02` | ✅ **Resolved 2026-08-16, on the second attempt.** G5 failed, was "fixed", and failed again reading `•••• 77…`. At XXXL the mask (~280 pt) and the collapsed clear button (~110 pt) plus padding cannot share a 393 pt screen at any ordering; the bar is now a `VStack` at accessibility sizes. |
| `018/issues/03` | ✅ **Resolved 2026-08-16.** With the bar's height bounded, the last row sits entirely clear of it at XXXL with a filter applied. Needed a new six-row `gate/` corpus to be runnable at all. |
| `018/issues/04` | ✅ **Resolved 2026-08-16.** A row rendered `name, ending NNNN` at `lineLimit(1)`, so truncation ate the **last-4** — the only discriminator. Rows now lead with the mask; confirmed on screen at both default and accessibility sizes. |
| `018/issues/05` | A one-off 100% CPU main-thread render hang. Sampled (`DisplayList.ViewUpdater` rebuilding a huge tree inside one `CATransaction`); **not reproduced in three attempts**. `needs-info`. |

**Two techniques that made this cheap — reuse them for every P3 screen:**

- **`xcrun simctl ui booted` drives three of the five accessibility axes.** `appearance`,
  `increase_contrast` and `content_size` are all settable from a script, so Dark Mode, Increase
  Contrast and every Dynamic Type size stop depending on anyone remembering. **Reduce
  Transparency still cannot be set this way** and needs Settings by hand.
- **Accessibility Inspector beats driving VoiceOver by gesture.** It reads an element's label
  straight off the simulator, reaches every screen behind an import, and yields a string you can
  paste into a ticket.
- **Hash the store around a failure path.** `shasum` on `…/Application Support/Kaname/kaname.db`
  before and after turns T129's "leaves the store byte-identical" from an eyeball into evidence.
  It held across all five failure documents.

⚠️ **Two gaps in the manual test kit itself**, both worth fixing before the next run:
`scripts/make-manual-test-kit.swift` writes a supported statement that prints **no period**, so
§5 step 4's "the period" is unobservable; and `7-long-for-cancel.pdf` parses far too fast on an
M-series simulator to cancel — a 1,250-row `make perf-corpus` statement is what actually works.

**⬅️ What is still genuinely open on 018: G9, G11 and G12 only** — the three timing bounds, now
their own ticket: `.scratch/018-transaction-list/issues/06-device-timing-gates-never-measured.md`.
They need a Release build on a device and a frame-stepped screen recording; a simulator's timings
are not evidence for them. **~20 minutes, no code.** Issue `01` is **resolved** — its subject,
the unrun accessibility gate, is done.

### T123 — what is now automated, and what a person still has to do

Three of §6's axes were moved out of the manual gate, because the system auditor can run them
and a person's memory cannot. All green on the front door:

- **Dark Mode**, and **Dark Mode at the largest accessibility text size** — two new cases in
  `ios/UITests/ImportFrontDoorUITests.swift`, using `XCUIDevice.shared.appearance`. They run in
  `make ios-test`. Dark Mode is its own contrast problem, not a repaint of the light one.
- **Increase Contrast** — **`make a11y-sweep`** (new). No XCUITest API sets it and no launch
  argument reaches it: it is read from the accessibility daemon, so only `simctl` can. The
  target enables it, runs the front-door suite underneath, and restores the simulator however
  the run ends.

**Still human-only, and still release-blocking:**

- **Reduce Transparency** — no `simctl` control and no test API. Eyes.
- **VoiceOver** — the auditor finds *unlabelled* elements; it cannot judge whether what is
  announced is meaningful. Ears.
- **The four screens behind an import** (summary, failure, password, account picker) — and the
  **accounts list**, which is where the parked contrast finding below lives. `performAccessibilityAudit`
  runs against a launched app, and every one of these is behind a real file being picked, so the
  audit reaches none of them. Closing this needs a decision, not more effort: a DEBUG-only seeding
  hook in the app would make every screen auditable — for this slice and for all of P3's screens
  after it — at the cost of a test-only entry point in the shipped source. T115 deferred exactly
  that call. **It is still open.**

- **T129** — `quickstart.md` §5: the 4-tap path, force-quit and relaunch, the same-file
  re-import, then the failure matrix (image-only, password right and wrong, corrupt, `.txt`
  renamed `.pdf`, a utility bill, cancel mid-parse).

### T129 — first run: three findings, one fixed

A first pass over §5 was run on the simulator. The 4-tap path, force-quit/relaunch and the
failure matrix all behaved. **The same-file re-import did not**, and two further questions came
out of it — both now decided, so **only the fix was code**. T129 is ready to be re-run and
ticked.

1. ✅ **FIXED (`3ba7890`) — the accounts list doubled on a re-import.** The engine was right:
   the repeat is inserted, then pointed at the row it duplicates via `superseded_by`, so
   nothing is deleted and provenance survives (FR-025). `Store::list_transactions` is the
   store's **raw** view and returns those superseded losers — plus deleted rows — and the
   front door counted it directly. The summary said "1 duplicate skipped" while the screen
   behind it said 2, which is exactly the doubling FR-025 exists to prevent. The predicate now
   lives on **`StoredTransaction.isLive`** (`ImportModels.swift`) with the reason beside it:
   **every P3 screen that lists or counts transactions must use it**, and each one can get
   this wrong the same way. Pinned by `reimportDoesNotInflateTheAccountsList`.
2. ✅ **DECIDED — a corrupt PDF and a `.txt` renamed `.pdf` say the same thing, on purpose.**
   `StatementTextExtractor.swift:61` maps *any* nil `PDFDocument` to `.notAPDF`, so both read
   *"That file isn't a PDF"*; `.unreadable` stays reserved for bytes that can't be read at all
   (line 57). The distinction is real to a parser and meaningless to a person — both mean "this
   file is not something Kaname can open", and the remedy is the same. §5's failure matrix is
   therefore **six distinct sentences over seven documents**, not seven. Don't add a `%PDF`
   header sniff to split them.
3. ✅ **DECIDED — the summary reports rows *written*, and a re-import reads "1 imported, 1
   duplicate skipped".** `transactionsImported` stays `outcome.transactionsInserted`. The two
   figures describe two different things — what the statement offered, and what was already
   there — and reporting "0 imported" would hide that the statement was read in full. FR-033 is
   satisfied. The screen behind it now counts live rows only (finding 1), which is where the
   person's actual history is stated.

**The seven documents §5 needs are synthetic and regenerated on demand** — `swift
scripts/make-manual-test-kit.swift <dir>`, then drag the folder onto a booted simulator — so no
real statement is ever needed to run this gate: a supported ICICI card statement (detects
`ICICI_AMAZONPAY_CARD`, 3 rows), image-only, password-protected (`kaname`), corrupt,
`.txt`-as-`.pdf`, a utility bill (`detect_issuer` → `None`), and a long one to cancel mid-parse.
The PDFs are build output and are never committed.

**What PR E settled — don't re-litigate it:**

- **The integrity verdict is on screen, in three states.** A reconciling statement confirms
  itself, a mismatched one still imports every row it read and persists `needs_review`, and a
  statement with nothing to check against renders **no verdict row at all**. Pinned by
  `ios/Tests/ImportIntegrityTests.swift` against a real encrypted store.
  `fixtures/yes/credit_card/mismatched_totals.json` is the deliberately non-reconciling
  vector — **Yes, not HDFC**, because the HDFC card reader captures no printed totals or
  balances, so an HDFC card mismatch is unreachable. Only Yes and IOB print totals.
- **`inFlight` records the document, not just the fact of an import.** The same file asked for
  twice joins the running import; a *different* file is refused with
  `ImportFailure.alreadyImporting`. The old code joined unconditionally, so a second statement
  picked mid-import would have been handed the first one's figures.
- **The accessibility audit is real and it bites.** `ios/UITests/ImportFrontDoorUITests.swift`
  runs `performAccessibilityAudit()` on the front door at default and largest text sizes. On
  its first run it found clipped text and four genuine contrast failures. The rules it
  established, which apply to **every future screen**:
  - never `.foregroundStyle(.secondary)` on content text — it does not clear the threshold at
    any size this app uses;
  - `LabeledContent` renders its value in that same secondary style, so every figure sets
    `.primary` explicitly;
  - a `.glassProminent` button refracting scrolled text fails at accessibility sizes — bottom
    action bars sit on `.background`;
  - the app has its own accent (`ios/Sources/Theme.swift`), a deep ink-teal clearing 4.5:1
    against white in both appearances.
- **`make import-audit` gained a Liquid Glass guard**: `#available(iOS 26`, any `*Material`,
  `UIVisualEffectView` or `UIBlurEffect` anywhere under `ios/Sources/` fails the build.
- **The simulator's app container persists between UI-test runs.** `xcrun simctl uninstall
  "iPhone 16" in.beaconbrain.kaname` before auditing, or you will audit the accounts screen
  while believing you audited the empty state.

**What PR D settled — don't re-litigate it either:**

- **The silent empty import is closed, and it was worse than recorded.** PDFKit does merge
  adjacent rows on tight layouts, but the result was not "0 transactions": it parsed into
  **one confidently wrong transaction** (row 1's date, row 2's amount, row 1's Dr/Cr marker).
  `PDFKitStatementTextExtractor.lineRanges(on:)` now re-derives line breaks from glyph
  geometry — **words are atomic** (PDFKit returns a stray far-off rect for the last glyph or
  two of a drawn run) and rows are grouped by **overlapping vertical extents**, with PDFKit's
  own newlines kept as hard breaks. A page whose character indices or bounds can't be trusted
  falls back to plain newline splitting. `ios/Tests/ExtractionFidelityTests.swift` is the
  parity proof and must stay green: it renders fixture lines to a PDF (22pt spacing, and 8pt
  for the merge case), extracts, and demands identical dates, exact `Decimal` amounts and
  directions versus parsing the lines directly.
- **A zero-transaction parse is only reported as an empty statement when the statement's own
  printed figures agree** (`integrity == .agrees`). Everything else gets
  `ImportSummary.nothingRecognized` and its own sentence. A **bank ledger** can never reach
  the trusted state — with no anchor row the reader records no printed balance at all — so a
  genuinely quiet ledger month gets the cautious sentence. That was a deliberate choice over
  extending the engine to expose printed Dr/Cr counts; revisit only if people complain.
- **Re-importing a statement used to double history.** `find_duplicates_in` compares accounts
  against each other and never an account against itself. `link_reimported_rows_in`
  (`store.rs`) now links a new statement's rows against what that account already had —
  **canonical layer only**, never fuzzy, because within one account the fuzzy layer would
  merge two genuine same-day, same-amount purchases. Two identical rows inside one statement
  stay two rows (pinned by `two_identical_rows_in_one_statement_are_both_kept`).
- **`ImportAccountTarget::Existing` now carries `last4`** and the store fills a blank one in,
  so an account created from a statement without an account number learns it later. The FFI
  moved: `make core-xcframework` before `tuist generate`.
- **`ImportService.run` returns `ImportResult`** (`.finished` / `.needsAccount`), and holds
  the parse in `PendingImport` while the person answers — so answering costs no re-read and
  no second password prompt. `resolveAccount(_:)` finishes it.
- **`make import-audit` gained a bank-literal check**, parsed out of the Rust registry, so an
  eleventh issuer is guarded without touching the script. It fails on any registry id, bank
  code or display name anywhere under `ios/Sources/` — including in a `#Preview`.

> ⚠️ **Still live:** never call a bare `tuist generate` — always `make ios-gen` /
> `make ios-test`, and run `make core-xcframework` first whenever the FFI surface moves.
> `make import-audit` is the mechanical SC-004 proof that **zero networking symbols** exist
> under `ios/Sources/Import/` — run it on every PR that touches that directory. The only
> engine-supplied string allowed on screen is `Issuer.display_name` (FR-033/FR-034); the copy
> deck for every failure and integrity state lives in `ios/Sources/Import/ImportModels.swift`.
> The T053/T055 design-gate outcomes (Liquid Glass application points, the four settled
> state-machine edges) are recorded in `tasks.md` § Phase 2.5 — read them before adding UI.

> ⚠️ **Worktree gotcha (learned the hard way):** Tuist cannot resolve its root inside a
> `git worktree` (there `.git` is a *file*, not a directory), so `make ios-gen` fails there.
> Do Swift work in the primary checkout. Adding an `ios/Tuist.swift` "fixes" it but changes
> root resolution for everyone — don't commit one.

**After the two manual gates**, the rest of P3 (transaction list, dashboard, budgets, tags,
search, export — see the spec's Out of Scope) gets specified slice by slice via
`speckit.specify`.

**⚠️ 017 jumps the queue — real statements do not import.** `specs/017-column-major-pdf/`
(branch `017-column-major-pdf`, **the live queue; T001–T045 merged as #36, resume at T046**;
do not re-run `speckit.specify`/`plan`/`tasks`) exists because running
thirteen genuine statement PDFs through the shipped pipeline showed the import vertical does
not work on real documents: **2 recognised no issuer, 8 more were recognised and imported zero
transactions**, and the remaining 3 under-read. Cause: real statements are multi-column tables
whose text layer is emitted **column-major**, and `PDFKitStatementTextExtractor.lineRanges(on:)`
can only *add* line breaks, never re-join what the text layer split — the mirror image of the
merged-row bug 016 PR D fixed. Both must hold at once. The fix is two-sided: a prototype that
recovered complete rows broke issuer detection on 11 of 13 files, because claim markers are
matched as literal substrings and several contain spaces — **that half is now fixed and merged
(PR A+B above).** The remaining, unfixed half is the extraction itself: PR C. **All
clarifications are answered — the spec (53 FRs) is planned and broken into 119 tasks.** Four
findings there are worth knowing before you touch it:

1. **No file needs a *new* reader.** All 13 belong to issuers already in the registry, so the
   slice is smaller than it looks. (`SBI-bank.pdf` is misleadingly named — it is an **SBI Cashback
   credit card** statement, so the "card reader claimed a bank statement" defect the spec was
   first drafted around **does not exist**; FR-016 survives as an unevidenced invariant.)
2. **The registry gains a naming rule** (FR-041–053): **credit cards per card product, bank
   accounts per bank**, with ids shaped `<INSTITUTION>_<PRODUCT>_CARD` / `<INSTITUTION>_BANK`.
   Six card entries are renamed (`SBI_CASHBACK_CARD`, `HDFC_SWIGGY_CARD`, `ICICI_AMAZONPAY_CARD`,
   `IOB_RUPAY_CARD`, `YES_KIWI_CARD`, `FEDERAL_SCAPIA_CARD`); the four bank entries are
   **untouched** — the two HDFC and two Federal savings layouts are template versions of one
   product, not four products. The full future-state table is in the spec under **Q1**.
   ⚠️ Defect fixed in PR B: `sbi.rs` set `BANK_CODE = "SBI_CARD"`, a product value in a
   field that holds a bare institution everywhere else; it is now `"SBI"` (FR-053), and gate
   G4 fails the build if a product or kind token reappears in any `bank_code`.
3. **Matching a literal anywhere in a document is not identification.** One reference statement
   names six of its issuer's *other* card products in marketing copy; the HDFC card statement
   contains `Swiggy` ~40× **inside merchant descriptions**; an AU statement contains `HDFC` inside
   a UPI description while `hdfc_bank.rs`'s mandatory claim marker is exactly `"HDFC"`. Products
   and issuers must be identified from the **title/header region** only (FR-044/FR-047).
   Related: **all six card readers currently claim at bank level**, so today's per-card
   identification is correct by *uniqueness*, not evidence — FR-050/051 make a test fail the build
   if two card entries for one institution are not both product-proven, and FR-048 replaces
   `detect_issuer`'s silent **alphabetical** tie-break with a specificity rule.
4. **The app is unreleased, so ids, names and even the store schema may change freely.**
   `bank_code` is nonetheless kept at institution granularity on *modelling* grounds (FR-046).
   Planning MUST explicitly take or defer one thing rather than let it pass: **an account cannot
   currently say which card product it is** (the store persists `bank_code` + `last4`, not the
   registry id) — a free schema change today, an expensive one after release.

**How to pick 017 up.** Read, in order:
`specs/017-column-major-pdf/spec.md` → `plan.md` → `research.md` (R1–R16) →
`contracts/` (`extraction-seam.md`, `engine-recognition.md`, `geometry-fixture.md`) →
**`tasks.md`** (119 tasks, T001–T119 — the actual queue) → `quickstart.md`.
It ships as **five PRs**:

| PR | Phase | What |
|----|-------|------|
| **A** 🔒 | 3 (T017–T024 + G6/G7) | Recognition: `claim.rs`, identity region, whitespace-insensitive matching |
| **B** | 4 | Registry: `ClaimEvidence`, the six card renames, `sbi::BANK_CODE`, specificity, G1–G5 |
| **C** 🎯 | 5 | Extraction: the `StatementTextExtractor` rewrite — zones → row bands → lines, all-page `lineWords` |
| **D** | 9 | Evidence: 10 generated geometry vectors + cross-bank, non-vacuity, privacy review |
| **E** | 10 | Gates: `make reference-check`, perf/cancellation, audits, docs, sign-off |

Three non-negotiables the plan settled — **don't re-litigate them**:

- 🔒 **PR A merges before PR C.** Recognition (US2, P2) is deliberately sequenced ahead of
  extraction (US1, P1), *against* priority order: R16 measured the reverse breaking 11 of 13
  files. PR A is a strict superset of today's matching, so `main` is never worse at any commit.
  PRs B and C can then run in parallel (different languages, no file overlap).
- 🔒 **Gate G7 ships in the same PR as the widening.** Whitespace-insensitivity widens every
  bare-institution marker at once, and `hdfc_bank::CLAIM_ALL` is literally `["HDFC"]` while
  `AU-statment-savings.pdf` contains `HDFC` in a UPI description. The false-claim gate is not
  a follow-up.
- **Geometry-first replaces the text layer's grouping entirely**, so splitting merged rows and
  re-joining split columns fall out of *one* algorithm rather than two fighting mechanisms.

Two items are **not closable by an agent**:

- **T119 ⛔ blocked** — the AU account-kind header literal (R15) cannot be read from this repo;
  it needs the reference-set holder. Fallback: defer that task **alone**; `AU-statment-savings.pdf`
  keeps reporting "format not recognised yet" (FR-025). Nothing else depends on it.
- **T116 human-gated** — the reference-set pass closing SC-002 (zero-transaction files 10 → 0),
  per the spec's Q3 Option A.

Also deferred on purpose: **persisting `issuer_id` (schema v7)**, priced and recorded as
"must land before first release" — no FR or SC needs it yet.

**Then: the unknown-bank contribution slice — how Kaname reaches every Indian bank.**
Decided but never sliced, so it is easy to miss: `docs/adr/0004-unknown-bank-ingestion.md`,
including **two amendments added 2026-08-13**. In short — a *layout signature* (column
positions, row shape, date format; **no values**) is the contribution unit; it can be rendered
back into a **synthetic statement** that is committable as a golden fixture *and* is the first
fixture that would exercise the native extractor rather than assume it; the fallback ladder's
trigger changes from "no reader claims it" to "the parse is unusable", because 8 of the 13
reference files were recognised correctly and still read nothing; and contribution must be
**inspectable** — the person sees the exact payload before it leaves the device, in plain
language, with a passing test proving no value from their statement survives into it.
017 is a prerequisite: a signature derived from fragmented text records a broken layout.

The older `.scratch/persistence/` and `.scratch/categorization/` queues are **fully
resolved** — the engine→store wiring and the Keychain key ceremony all shipped. Nothing is
open there.

---

## 4. Per-slice workflow (proven on every slice)

Spec Kit, one slice per PR: `speckit.specify` → `speckit.plan` → `speckit.tasks` →
implement directly (faster once the design is locked). For engine slices, **capture ground
truth by RUNNING the live web engine** (`/Users/ssk/Projects/finance-tracker-phase/backend`,
`.venv/bin/python`) — never real data; fixtures stay synthetic. Test-first
(RED → GREEN → `make core-xcframework` → Swift GREEN). Then the full gate → 2 commits
(engine+fixtures+parity; Swift test) → PR → watch CI → `merge --rebase --delete-branch`
→ `git remote prune origin`. Surface sub-agent decisions back to the user; don't self-answer.

---

## 5. Local Verification Gate (MANDATORY before every PR)

```
export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"   # cargo is NOT on the default PATH
make core-lint          # cargo fmt --check + clippy -D warnings
make core-test          # cargo test (unit + parity + store)
make core-privacy-audit # no networking crate / no openssl in the shipped graph
make import-audit       # no networking symbol under ios/Sources/Import (Swift half of the same gate)
make lint               # swiftlint --strict + swift-format lint + core-lint
make ios-gen            # tuist generate (depends on core-xcframework)
make ios-test           # simulator build + Swift Testing (sim named "iPhone 16")
```
CI (`.github/workflows/ci.yml`): Rust on `ubuntu-latest`, iOS on `macos-26`. Docs-only
changes don't need linting/building/testing.

---

## 6. Environment & gotchas (save yourself the pain)

- **Toolchain PATH:** `cargo`/`rustup` live in `~/.cargo/bin`, NOT on the default PATH.
  Prefix every shell: `export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"`.
- **Cargo workspace is under `core/`** — `cargo` needs `cd core` (or use `make`).
- **SQLCipher is built WITHOUT OpenSSL** (Constitution I; CI-enforced). `bundled-sqlcipher`
  auto-selects **CommonCrypto** on Apple (links `Security`/`CoreFoundation` — added in
  `ios/Project.swift`). On **Linux/CI** we force **LibTomCrypt**:
  `LIBSQLITE3_FLAGS=-DSQLCIPHER_CRYPTO_LIBTOMCRYPT` (set by the `Makefile` Linux guard +
  the `ci.yml` core job, which also `apt-get install libtomcrypt-dev`), and
  `core/crates/kaname-core/build.rs` links `tomcrypt` + shadows the `-lcrypto`
  libsqlite3-sys hard-codes with an **empty stub archive** so zero OpenSSL links. Do **not**
  switch to `bundled-sqlcipher-vendored-openssl` (the privacy audit denylists `openssl-sys`).
- **`build-xcframework.sh` pins `IPHONEOS_DEPLOYMENT_TARGET=26.0`** so SQLCipher's
  `sqlite3.o` (which references `___chkstk_darwin`) links on-device — keep it aligned with
  the app's Tuist deployment target.
- **Deployment target is iOS 26.0** (`ios/Project.swift`, all three targets). Chosen so
  **Liquid Glass is unconditional** — never write `#available(iOS 26, *)` or a
  `.ultraThinMaterial` fallback. See the `swiftui-liquid-glass` skill.
- **iOS simulator:** local `make ios-test` targets a sim named **"iPhone 16"** (create once:
  `xcrun simctl create "iPhone 16" "iPhone 16"`). CI selects one **by UDID**
  (`.github/scripts/select-ios-simulator.sh`) — never re-hardcode a device name in CI.
- **CI iOS job runs on `macos-26`** and selects the newest **Xcode 26.x** — the iOS 26 SDK is
  required by the deployment target. Never drop below `macos-15` (Homebrew `tuist` cask breaks
  on `macos-14`).
- **swift-format `[Spacing]` rejects trailing inline comments** after code — put comments on
  their own line above the statement.
- **`DATE_FORMATS` order matters** (`common.rs`): `%d/%m/%y` before `%d/%m/%Y`. chrono's
  `%b` is case-insensitive.
- **Money is never a float:** `rust_decimal::Decimal` in Rust, crosses UniFFI as an exact
  base-10 `String`, surfaces as `Foundation.Decimal` in Swift. Direction from a Dr/Cr marker
  or balance delta — never the amount's sign.
- **PDF text extraction is NATIVE** (iOS PDFKit); the core never opens a PDF.
- **UniFFI 0.32** proc-macro (no UDL). `make core-xcframework` rebuilds the xcframework +
  regenerates `ios/Generated/` (git-ignored) — run it **before** `tuist generate` whenever
  the FFI surface changes.
- **rustfmt reformats your edits:** after an `edit`, run `make core-fmt` then re-view before
  the next `edit` (old_str may no longer match).
- **`update-agent-context.sh` typo:** on `speckit.plan`, it writes "iOS 18 targe" into
  `.github/copilot-instructions.md`. Fix before committing the plan:
  `sed -i '' 's/iOS 18 targe$/iOS 18 target/g; s/iOS 18 targe /iOS 18 target /g' .github/copilot-instructions.md`.

---

## 7. Key reusable seams

- `line_reader.rs` — `LineReaderConfig` + `read_lines` + `claims` (every CC reader is one config).
- `ledger_reader.rs` — `LedgerReaderConfig` + `read_ledger_lines` + `claims_ledger`
  (direction from balance delta; every bank reader is one config).
- `balance_chain.rs` — `check(&ParsedStatement) -> ChainResult`.
- `reconcile.rs` — `reconcile(&ParsedStatement) -> ReconcileResult` (printed totals →
  opening/closing fallback → neutral `None`; ₹1.00 tolerance).
- `dedup.rs` — `cross_source_duplicates`; `normalize_narration` (≠ `normalize_description`).
- `coverage.rs` — `compute_coverage(today, …)` + `month_window` (clock-free; `today` is a param).
- `transfer.rs` — `detect_transfers(&[TransferInput]) -> Vec<TransferPair>`.
- `categorize.rs` — `categorize` / `categorize_batch` (first-wins stack), `default_categories()`
  (23 builtins: code + name + `Classification`), `prepare_merchants`/`prepare_rules`.
- `statement/registry.rs` — the ten-entry issuer registry (private `REGISTRY`, no bank list is
  ever exported — FR-012). `detect_issuer(full_text) -> Option<Issuer>` picks the minimum under
  `(kind_rank, evidence_rank, id)` with **ledger before card** and a product-proven claim ahead
  of a bank-level one (pinned by `tests/dispatcher.rs`). Ids name **cards by product** and
  **banks by bank** — `<INSTITUTION>_<PRODUCT>_CARD` / `<INSTITUTION>_BANK`. Claims are matched
  whitespace-insensitively against the **identity region** (the document minus its transaction
  rows), and a product claim only against the **header region** — so a co-brand's name repeated
  in a person's own spending cannot identify the statement (`statement/claim.rs`).
  `read_statement(issuer, lines, full_text, line_words)` is the single parse front door — cards
  ignore `line_words`; ledgers get only the anchor row's geometry via
  `ledger_reader::first_anchor_index`. The ten legacy `read_<bank>_statement` exports still
  exist and are unchanged.
- **`ios/Sources/Import/PrintedRows.swift` + `WordGeometry.swift` — extraction is geometry-first
  (017).** `ExtractedText.lines` is now **one printed row per element**, not the text layer's
  newlines: PDFKit's breaks have no authority, and reconstruction both *splits* rows it merged
  (tight leading) and *joins* rows it split (a column-major statement, which reported no
  spending at all). `lineWords` is emitted for **every** line of **every** page, not page 1
  only, so a ledger whose first row is on page 2 still bootstraps its direction from the
  amount's printed column. `PDFKitStatementTextExtractor.split(_:)` is **frozen** — it models
  the pre-017 extraction and `GeometryFixtureTests` parses through it to prove every geometry
  vector fails against the old path. ⚠️ Getting a word's position out of PDFKit is not
  one-line: `characterBounds(at:)` is indexed over *glyphs* while `string` carries the line
  breaks PDFKit inserted, individual glyph rects come back nonsense at the end of a run, and
  `PDFSelection.bounds(for:)` is right but no finer than PDFKit's own line. All three are
  handled in `WordGeometry` and nowhere else — read its doc comment before touching it
  (`specs/017-column-major-pdf/research.md` R17/R18).
- `store.rs` — `Store::open(path, key)` (SQLCipher, forward-only `PRAGMA user_version`
  migrations to **schema v6**, `StoreError` typed errors, wrong-key fail-closed);
  `insert_account`/`insert_transaction`/`list_*`; the categorization facts
  (`insert_merchant_rule`/`insert_source_category_mapping`/`insert_rule`/`insert_category`
  + their `list_*`); `categorize_account` (runs the pure stack over stored rows and
  persists `category_id`/`categorised_by`); and `detect_transfers` (cross-account — runs the
  pure matcher over stored rows and tags both legs `is_transfer`/`transfer_group_id`).
  **⚠️ `Store` methods take a non-reentrant `std::sync::Mutex`.** Any *composite* write must
  call the transaction-scoped helpers `categorize_account_in(tx, account_id)` /
  `find_duplicates_in(tx)` — **never** the public `categorize_account` / `find_duplicates`,
  which re-lock and deadlock. `tests/store_import.rs` holds a 10s-timeout guard that fails
  fast and legibly if that rule is broken.
  `Store::import_statement(ImportRequest) -> ImportOutcome` is the atomic composite: one
  transaction doing resolve-or-create account → `statements` row → transactions →
  `categorize_account_in` → `find_duplicates_in` → COMMIT, rolling back entirely on failure.
  No `statements` row is written when there is neither a period nor a transaction (R6).
  **Timestamps are explicit inputs** (the core reads no wall-clock); the platform owns the
  Keychain key + file path + NSFileProtection.
- `common.rs` / `polarity.rs` — `parse_amount`/`parse_date`/`find_last4`/…; `classify`.
- `ios/Sources/Import/` — the platform vertical (016 PR C + D + E). `StatementTextExtractor` is the
  PDFKit seam (a protocol, so the pipeline is provable without a PDF — see
  `ios/Tests/ImportPipelineTests.swift`); `ImportService` is the actor owning the whole
  pipeline and the in-flight `Task` — which now records **which document** is importing, so a
  second call for the same file joins it and a second call for a different file is refused
  with `ImportFailure.alreadyImporting`; `ImportModels.swift` holds **the copy deck** — every
  user-facing sentence for `ImportFailure` and `IntegrityOutcome` lives there, and
  `Issuer.display_name` is the only engine string allowed on screen; `lineRanges(on:)` is the
  glyph-geometry line splitter that keeps PDFKit from merging two statement rows into one
  (proved by `ios/Tests/ExtractionFidelityTests.swift`); `AccountPickerView` is the only place
  an account is ever chosen, and `ImportService.run` returns `ImportResult` so an ambiguous
  attribution asks instead of guessing. `ImportEmptyStateView` is the first-run front door and
  `ImportedAccountsView` what replaces it once anything has been imported;
  `ImportProgressView` is the one floating glass control in the flow.
- `ios/UITests/` — the `KanameUITests` target running the system's own
  `performAccessibilityAudit()` against the front door at default and largest accessibility
  text sizes. **Treat its findings as real** — it caught clipped text and four genuine
  contrast failures on its first run. Two rules it established: never use
  `.foregroundStyle(.secondary)` for content text, and set `.primary` explicitly on every
  `LabeledContent` value, because the system renders it secondary.
- **`ios/Sources/Transactions/` — the transaction list (018).** `TransactionHistoryService` is
  an **actor**, and the *only* thing in the app that reads history: it opens the store inside
  itself (`init(opening:)`), so SQLCipher never opens on the main thread even though the screen
  is reached from a view body. `TransactionListViewModel` owns paging, the filter, incremental
  date grouping and the scroll anchor, and holds a `generation` token so a page read still in
  flight when the population changes underneath it is dropped rather than appended.
  `ImportCompletionSignal` is the process's one **broadcast `AsyncStream<Void>`**: the import
  actor yields it *after* `import_statement` commits and on no other path, and both the list
  and the front door re-read on it — so the count on one screen and the rows on the other can
  never come from two different moments. It carries `Void` deliberately (a payload would be a
  second population, arriving by a second route).
- **The engine's two reads (018).** `Store::history_page(HistoryQuery) -> HistoryPage` —
  keyset-paged, a k-way merge of one index-satisfied query per account, the account filter
  being the same query with k = 1 — and `Store::account_summaries()`, which is where the front
  door's per-account live count now comes from (it was an N+1 in Swift: 43.8 ms of Rust time
  became 1.6 ms measured through the whole seam). Schema is **v7**: one partial descending
  index `idx_txn_live_account_date ON transactions(account_id, date DESC) WHERE is_deleted = 0
  AND superseded_by IS NULL`. ⚠️ The live-row rule is the single Rust constant `LIVE`, and it
  is **byte-identical** to that index's `WHERE` clause — paraphrase either and the read loses
  its index and `history_perf.rs`'s plan-shape test (S1/S2) goes red. `Store::list_transactions`
  keeps its raw semantics (deleted and superseded rows included) on purpose — do not "fix" it.
  `StoreProvider.shared()` is the process's one `Store`, which is a correctness requirement:
  two connections would be two locks, and a page read could land inside an atomic import.
- `tests/parity.rs` — the golden harness (readers + reconcile/dedup/coverage/transfer).

### Seeding a screen with data (019) — the seam every later P3 screen inherits

- **`KANAME_SEED_SCENARIO`** on `XCUIApplication.launchEnvironment` (**bare** — the
  `TEST_RUNNER_` prefix is the app-hosted *unit*-test rule and delivers nothing here). Declared
  scenarios: `small` (6 rows, one account, a long product name, a prior calendar year), `deep`
  (160 live rows, four accounts, five statements, two currencies, five declared supersessions),
  `barren` (two statements, no transactions), `empty` (the reset without the seed).
- **`ios/Sources/DebugSeed/`** — `SeedScenarios.swift` (the declaration) + `SeedExpectations.swift`
  (what a test derives from it) are compiled into **`KanameUITests` as well**, so the rows written
  and the rows asserted are one literal. ⚠️ Both may import **Foundation and nothing else**: that
  bundle links neither the app nor `KanameCore`. `SeedScenarioBuilder.swift` turns a statement into
  an `ImportRequest`; `DebugSeed.swift` resets the database and writes it through the shipped
  `Store.importStatement`. All of it inside `#if DEBUG`.
- **`ios/UITests/SeededLaunch.swift`** — launch with the locale pinned, walk the whole list
  (rows + headings + same-screen duplicates + swipe count in one pass), filter and clear through
  the controls a person uses, read the rendered empty state, pin the appearance.
- **Two gates prove it cannot ship**: `make import-audit`'s **tenth scan** (every file under
  `DebugSeed/` opens with `#if DEBUG`; nothing outside it names the surface except `KanameApp
  .swift`'s three guarded lines) and **`make release-audit`** (~16 s — it builds its own Release
  binary and fails as *inconclusive* unless it first finds a symbol and a literal it knows are
  there; a stripped binary has 156 symbols against 4,534, so a naive scan would pass for the wrong
  reason). **CI now runs `make import-audit` and lints `UITests`**, both for the first time.
- **Adding a scenario costs zero lines compiled into a Release build** (SC-015), and the
  engine was **not touched**: schema stays **v7**, no migration, no `#[uniffi::export]`. Seeding
  cannot be a Rust concern — one `cargo build --release` artifact links into *both* Xcode
  configurations, so no Rust construct is present in DEBUG and absent from Release.

### ⚠️ Open findings carried out of 019 — three states the product cannot produce

- **`is_deleted` has no write path.** Nothing in `store.rs`'s public API sets it; the only
  `SET is_deleted = 1` in the repository is raw SQL in an engine test helper. A seed therefore
  cannot express a deleted row, and deletion coverage stays engine-side
  (`tests/history_live.rs`). **Closes when — if — deleting a transaction becomes something a
  person can do.**
- **`is_transfer` is written only by `detect_transfers`**, which `import-path-audit.sh` bans the
  app from calling, so every row of every real install has `is_transfer = 0`. A seeded transfer
  would be a screen no person can have. **Closes when the categorize slice wires detection.**
- **Three `EmptyKind` cases are unreachable by any seed** — `nothingImported`,
  `nothingToShowAnywhere` and `accountNothingToShow` — because **every supersession the import
  path can produce leaves a live winner** (a re-import keeps the row the account already had;
  cross-source keeps the earlier account's), so a store cannot hold rows and show none of them;
  and `nothingImported`'s precondition is exactly the condition under which `RootView` hides the
  route to the list, both read from the **same** `accountSummaries()` call. They are host-rendered
  in `ios/Tests/EmptyStateRenderingTests.swift` — **executed and asserted, not audited**, because
  `performAccessibilityAudit` is an `XCUIApplication` API. Evidence:
  `.scratch/019-debug-test-seeding/issues/02`.

⚠️ **None of the three was worked around.** A fixture that can build states the product cannot is
a fixture that tests fiction (FR-008a).

### ⚠️ Open findings carried out of 018 — evidence, not opinions

- **R17 — the matcher collapses across accounts, and the same-institution guard is still
  absent.** 018 PR A fixed only the *tie-break*: dedup's account groups are ordered by
  `accounts.rowid`, so which row survives is now deterministic across processes
  (`tests/store_dedup_determinism.rs`). What it did **not** change is which pairs match. Two
  accounts *of the same kind* are now never compared at all — a blunt guard: a person with two
  bank accounts, one of which itemises the other's card spends, would see the spend twice. The
  narrow fix is a **source-kind** guard rather than a same-kind one; the honest fix is a
  matcher that knows *why* two rows are the same purchase. Belongs to the slice that owns
  dedup. Evidence: `specs/018-transaction-list/quickstart.md` § *What US1 AS-6 now asserts*.
- **R18 — `detectTransfers()` is called from no Swift file, and nothing claims otherwise.**
  The engine's cross-account matcher exists and is tested (`tests/store_transfer.rs`); the
  transfer **marking** on the list is built and tested against a store where the flag is set by
  the *test*. Wiring the detection belongs to the categorize slice. `make import-audit` and
  `ios/Tests/TransactionTransferMarkingTests.swift` mechanically fail any task name, test name,
  string or release note that implies the app detects transfers — keep it that way until it
  does.

---

## 8. Repo map

```
core/crates/kaname-core/   Rust engine (kaname-core)
  src/statement/           the 10 readers + shared seams
  src/{model,dedup,coverage,transfer,categorize,store,ffi,lib}.rs
  build.rs                 non-Apple SQLCipher/LibTomCrypt linking (no OpenSSL)
  tests/                   parity golden harness + store behavioural tests (store*.rs)
ios/                       SwiftUI app (Tuist). Tests/*Tests.swift = per-bank + engine + store bridge tests
fixtures/<bank>/<kind>/    synthetic golden vectors (NO real data — Constitution I)
specs/NNN-<slug>/          Spec Kit: spec/plan/research/contracts/tasks  ← CURRENT work (§3)
.scratch/<slug>/           older ticket tracker: spec.md + issues/NN-*.md (all resolved)
.specify/memory/constitution.md   THE rules (privacy non-negotiable; wins over all)
docs/kaname-ios-plan.md    architecture + P0–P6 (durable)
docs/adr/                  architecture decision records (durable)
docs/HANDOFF.md            original scaffold handoff (historical "why")
docs/agents/               issue-tracker / triage-labels / domain conventions
```

---

## 9. The web engine (source of truth for porting — read-only)

`/Users/ssk/Projects/finance-tracker-phase/backend/` (working `.venv/bin/python`).
Ingestion under `app/services/ingestion/`. Always capture ground truth by RUNNING the real
web code, then port to Rust and prove parity. **Fixtures must be synthetic/redacted.**
