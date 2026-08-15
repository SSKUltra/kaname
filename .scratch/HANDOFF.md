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
**The live one is `specs/018-transaction-list/`, resuming at T071 (PR B, US2).**

**B. `.scratch/<feature-slug>/` — the older local ticket convention** (see
`docs/agents/issue-tracker.md`): `spec.md` plus `issues/<NN>-<slug>.md`, each with a
`Status:` line (`needs-triage`/`needs-info`/`ready-for-agent`/`ready-for-human`/`wontfix`,
per `docs/agents/triage-labels.md`). Used by `.scratch/categorization/` and
`.scratch/persistence/` — **both fully resolved; nothing open there.** Kept for history.

⚠️ **One thing *is* open here**: `.scratch/016-statement-import-vertical/issues/01-front-door-contrast-dark-mode-largest-text.md`
(`Status: ready-for-human`) — **`make ios-test` is red on unmodified `main`**, and every slice
after 016 inherits a gate it cannot pass. Read it before running any iOS gate and concluding
you broke something.

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

**`017-column-major-pdf` is DONE and fully merged — all 119 tasks, every gate green, including
the human reference pass (T116).** PR A+B is #36, PR C–E is #37; both are on `main`.
**Nothing in 017 is open**, R15/T119 included.

**What the reference pass measured** (13 real statements, on the holder's machine, counts
only): statements reading **zero** transactions **10 → 0**; **unrecognised 2 → 0**. Re-run it
any time with `make reference-check DIR=…`, and `make reference-shapes DIR=…` to describe a
document that reads nothing — the latter prints each line with every value replaced (digits →
`9`, letters → `A`/`a`), so a layout can be diagnosed, and pasted into a bug report, without a
statement leaving the machine.

**⬅️ NEXT: `018-transaction-list`, PR C — US3 (the filter) and US7 (the empty states), starting at T084.**

018 is specified, planned and broken into **147 tasks** — `specs/018-transaction-list/`. **Do not
re-run `speckit.specify`/`plan`/`tasks`**: the design is locked, and its two clarifications and
two judgement calls are settled (spec § *Clarifications*, plan § *Judgement calls*).

**PR A0 (#38) is merged**, **PR A is done — T001–T044**, and **PR B is done — T045–T083, less
T069.** A person can now open the app, tap once, and read their own transactions across every
account, newest first and grouped by date; importing the same statement a second time changes
nothing they can see. **PR B has not been opened as a pull request yet** — its three commits are
on `main` (`738cbe1`, `ea7ba68`, `1a8054f`, plus US4's).

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

Green: `make lint` (0 violations), `make import-audit` (all five scans), `make core-test`
(**308 tests**), the **unit target — 185 tests in 40 suites**. `ImportService.swift` is **397 lines**, three below the limit it sat
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

**Also still open, and release-blocking: 016's two manual gates.** T129 is ready to re-run and
tick (see below); **T123 has never been run** — Reduce Transparency, VoiceOver, and the five
screens behind an import all need a person.

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

**⬅️ NEXT: the two manual gates, which no agent can run.** Both are on the simulator, both
are release-blocking:

- **T123** — `quickstart.md` §6: largest Dynamic Type, Dark Mode, **Reduce Transparency**,
  **Increase Contrast**, VoiceOver across every screen in the flow. The automated audit
  (`ios/UITests/`) covers only the front door; the summary, failure, password and
  account-picker screens need eyes and ears.

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
- `tests/parity.rs` — the golden harness (readers + reconcile/dedup/coverage/transfer).

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
