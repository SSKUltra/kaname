# Phase 0 Research: DEBUG-Only Test Seeding

**Feature**: `019-debug-test-seeding` | **Date**: 2026-08-17 | **Spec**: [`spec.md`](./spec.md)

Every decision below is grounded in code that exists in this repository today, or in a
measurement that was actually run on this machine while planning. Where a decision rejects an
alternative, the rejection reason is a measured fact or a cited line, not a preference.

**How the measurements were produced.** A Release build of the app was produced with

```bash
cd ios && xcodebuild -workspace Kaname.xcworkspace -scheme Kaname \
    -configuration Release -sdk iphonesimulator \
    -derivedDataPath /tmp/kaname-rel-timed build CODE_SIGNING_ALLOWED=NO
```

and the resulting `Kaname.app/Kaname` was inspected with `nm`, `strings`, `strip` and
`xcodebuild -showBuildSettings`. Nothing in the repository was modified to take these
measurements; the derived-data directory was outside the tree and is gone. Every figure quoted
as `E<n>` below is a line of that output. The permanent version of these probes is the absence
audit itself (R5), so nothing here rests on a measurement that cannot be re-run.

Source anchors used throughout:

- `ios/Project.swift` — the four Tuist targets; the app's `sources: ["Sources/**"]` glob.
- `ios/Kaname.xcodeproj/project.pbxproj` — the generated build configurations (git-ignored).
- `ios/Sources/KanameApp.swift` — the 13-line `@main` entry point.
- `ios/Sources/Persistence/StoreProvider.swift`, `StoreLocator.swift`, `KeyStore.swift` — the
  one `Store` per process, where its file lives, and the Keychain key ceremony.
- `ios/Sources/RootView.swift` — the front door and the only route to the transaction list.
- `ios/Sources/Transactions/TransactionListViewModel.swift` — `pageSize = 50`, `EmptyKind`
  selection, the `.loading` initial state.
- `ios/Sources/Transactions/TransactionListModels.swift:161–205` — `EmptyKind` and `decide`.
- `ios/Sources/Import/ImportService.swift` — **398** of the 400-line SwiftLint limit; its
  `accountSummaries()` call at line 126 is the front door's account source.
- `ios/UITests/ImportFrontDoorUITests.swift` — the launch-argument technique already in use,
  and `testAFreshInstallOffersNoRouteToAnEmptyTransactionList`, the assertion this slice retires.
- `core/crates/kaname-core/src/store.rs` — `SCHEMA_VERSION = 7` (L41), `LIVE` (L185),
  `import_statement` (L713), `list_accounts_in` (L1658), `mint_id` (L1715), the dedup ordering
  (L1874).
- `core/scripts/build-xcframework.sh:41–44` — `cargo build --release`, once, for all configs.
- `scripts/import-path-audit.sh` — the nine mechanical scans.
- `Makefile` — `ios-test`, `a11y-sweep`, `perf-corpus`, `import-audit`, `lint`.
- `.github/workflows/ci.yml` — the two CI jobs.
- `.scratch/018-transaction-list/issues/02`, `03` — the two defects FR-038 names.

---

## R1 — The seed is requested by a launch **environment** variable, not a launch argument

**Decision.** An automated run asks for a scenario by setting one variable on the app process
before launching it:

```swift
let app = XCUIApplication()
app.launchEnvironment["KANAME_SEED_SCENARIO"] = "small"
app.launch()
```

The app reads it with `ProcessInfo.processInfo.environment["KANAME_SEED_SCENARIO"]`, inside
`#if DEBUG`. No other channel exists.

**Rationale.**

- **`XCUIApplication.launchEnvironment` reaches the app directly.** It is set on the process
  XCUITest spawns, so there is no forwarding rule to get wrong. ⚠️ This is *not* the rule the
  `Makefile` documents at `reference-check`: `xcodebuild` refuses to pass the shell environment
  to a process in the simulator and forwards only `TEST_RUNNER_`-prefixed variables to the
  **test runner**, stripping the prefix. That rule governs `make reference-check` and
  `make perf-corpus`, which drive *unit* tests hosted in the app. It does not govern a UI test
  launching the app itself, and confusing the two is how somebody spends an afternoon on a
  variable that was never delivered. Both rules go in the quickstart, side by side.
- **A launch argument would leave a residue.** Arguments beginning with `-` are consumed by
  `NSUserDefaults` as a volatile domain — which is exactly why
  `ImportFrontDoorUITests` already sets `-UIPreferredContentSizeCategoryName` that way. That
  domain is volatile per process, but the technique invites the obvious next step of reading the
  request from `UserDefaults`, and a `UserDefaults` read is a *persistable* surface. FR-021 says
  a seeded run leaves nothing behind that changes a later non-seeded run; an environment
  variable dies with the process and cannot be persisted by accident.
- **The four axes must compose.** The spec's edge case asks for largest text size + Dark Mode +
  Increase Contrast + a seed, all at once. They already occupy three separate channels —
  `launchArguments` (text size), `XCUIDevice.shared.appearance` (Dark Mode), `simctl` via
  `make a11y-sweep` (Increase Contrast). `launchEnvironment` is a fourth, disjoint channel, so
  nothing has to be reconciled.

**Alternatives considered and rejected.**

| Alternative | Why not |
|---|---|
| A custom URL scheme | FR-031 bans it outright, and it would need a `CFBundleURLTypes` entry in `Info.plist` — a **data** surface present in the Release bundle that the artifact audit would then also have to police. A trigger that ships is not absent. |
| A file dropped into the app container by `simctl` | FR-001 forbids "a file being placed anywhere by hand", and the app would need file-discovery code on a launch path. |
| A pasteboard payload | Reachable by a person, in any build. FR-031. |
| `simctl spawn … setenv` | Sets the environment for the *simulator*, not per launch, so it survives between runs — the opposite of FR-021. |
| Passing the whole scenario as JSON in the variable | Rejected in R11: it makes the app a general-purpose row injector whose shape is decided by whatever is on the other end. |

---

## R2 — 🚨 The Rust engine **cannot** carry a DEBUG boundary, so the seeding path is Swift-only

**The finding.** `core/scripts/build-xcframework.sh` builds the engine **once**, in release
profile, for all three Apple targets:

```bash
# build-xcframework.sh:41–44
echo "==> [1/5] Building kaname-core static libs (release) for iOS targets"
for target in "$DEVICE_TARGET" "${SIM_TARGETS[@]}"; do
    cargo build --release --quiet --target "$target"
done
```

That single `KanameCoreFFI.xcframework` is linked into **both** the Debug and the Release iOS
configurations. The Xcode configuration is not an input to this script and cannot become one
without the xcframework being built twice and the Tuist manifest choosing between them per
configuration.

**Two consequences, and they are absolute.**

1. `#[cfg(debug_assertions)]` is **off in the DEBUG app**. It tracks the *cargo* profile, which
   is always `--release` here — so a Rust seeding hook guarded that way would compile out of the
   very build that needs it.
2. `#[cfg(feature = "seed")]` would compile **into the Release app**. There is no Xcode-side
   switch that reaches it. FR-025 requires exclusion "by the build itself"; a Rust feature flag
   would be excluded by nothing.

**Decision.** The seeding path is **Swift-only**, written entirely against the existing
`#[uniffi::export] impl Store` surface. `core/` is not touched by this slice at all.

**What this buys, beyond correctness.**

- **No FFI change ⇒ no `make core-xcframework` ⇒ no engine PR.** 018's mandatory "engine work
  lands separately from, and before, interface work" ordering exists because the xcframework is
  rebuilt and Tuist resolves its path at generation time. Neither happens here, so this slice's
  delivery order is free to follow the user stories instead of the bridge.
- **The `AGENTS.md` trap does not apply.** No `ffi.rs` edit means no `make core-xcframework`
  then `make ios-gen` dance, and no "cannot find X in scope" Swift error that is not a Swift
  problem. `make ios-gen` is still run, because `Project.swift` gains one line (R11).
- **`core/tests/history_perf.rs::s5` is not disturbed.** This slice adds no `cargo test`, so the
  wall-clock suite that is flaky under CPU contention is neither changed nor made more likely to
  run alongside the iOS gate.

**Deliberately not done.** No `#[uniffi::export]` is added "just for seeding" — not a
`seed_history`, not a `set_deleted`, not a debug-only `Store` constructor. Every one of them
would ship. This is also why R8's two unreachable fixture clauses are recorded as findings
rather than closed with a new export.

---

## R3 — The boundary is `#if DEBUG` over a new `ios/Sources/DebugSeed/`, plus one line in `KanameApp.swift`

**Decision.** All seeding code lives in a new directory, `ios/Sources/DebugSeed/`, and every
file in it is wrapped, in full, in `#if DEBUG` / `#endif`. The only edit to an existing shipping
source is a three-line `#if DEBUG` block in `KanameApp.swift`:

```swift
@main
struct KanameApp: App {
    init() {
        #if DEBUG
        DebugSeed.applyIfRequested()
        #endif
    }
    …
}
```

**Rationale.**

- **`DEBUG` is defined in the Debug configuration and in no Release configuration.** Verified
  against the generated project: `SWIFT_ACTIVE_COMPILATION_CONDITIONS = ("$(inherited)", DEBUG)`
  appears **four** times in `ios/Kaname.xcodeproj/project.pbxproj`, once per target, and every
  one of them is inside an `XCBuildConfiguration` whose `name = Debug`. No Release configuration
  sets it. This is Tuist's default, so it survives `make ios-gen` and does not depend on a
  setting somebody has to remember to keep.
- **The entry point has to be `App.init()`**, because FR-002 requires the history to be complete
  before any screen can read the store, and `StoreProvider.shared()` memoises the `Store` on
  first use. `init()` runs before the `WindowGroup` body is ever evaluated, so the seeder is
  guaranteed to be the first thing that opens the database.
- **`KanameApp.swift` is 13 lines**, so this is one of the few shipping files with room. It is
  also the honest place: an entry point is where a launch-time decision belongs, and hiding the
  call inside `StoreProvider` would put a test concern inside the type whose whole doc comment
  is about a correctness requirement.
- **A directory, not a file, because `ImportService.swift` is at 398 of 400 lines** and
  `make lint` runs `--strict`. `AGENTS.md` records 393; it is now 398. Two lines of headroom is
  not headroom. This is the same reasoning that created `ios/Sources/Transactions/` in 018, and
  the same answer.
- **Inside `ios/Sources/`, deliberately** — see R7. It puts the new code inside the networking
  scan's root and inside the bank-literal scan's root, both of which this slice wants.

**Alternatives considered and rejected.**

| Alternative | Why not |
|---|---|
| A separate Tuist target linked only in Debug | `ProjectDescription.Target.dependencies` has no per-configuration form. Expressing it takes an `OTHER_LDFLAGS`/`EXCLUDED_SOURCE_FILE_NAMES` trick per configuration — a build-system incantation no scan can read and no reviewer can check by eye. `#if DEBUG` is visible in the source, and the artifact audit checks the result rather than the intent. |
| A local Swift package with a trait | Same problem one layer further away, plus a new package boundary for six files. |
| `EXCLUDED_SOURCE_FILE_NAMES` for the Release configuration | Works, but the exclusion lives in `Project.swift` rather than beside the code, and a file added to the directory later is included by default — failing open. `#if DEBUG` fails closed. |
| Guarding at runtime on `ProcessInfo.isRunningTests` or a build flag read at launch | FR-025 forbids it in as many words: the code would still be in the binary, where a flag, a patched byte or a debugger reaches it. |

---

## R4 — What an audit of the built Release artifact can actually see — measured, including the trap

This is the entry the whole slice rests on. FR-027 requires the check to inspect the **built
Release artifact and not only the sources**. Before designing that check, it has to be
established what a Release artifact of *this* app actually reveals.

**E1 — the build succeeds unsigned, and it is cheap.**

```
** BUILD SUCCEEDED **
real 16.21   user 0.78   sys 0.28
```

with a fresh `-derivedDataPath`. `Kaname.app/Kaname` is **2,651,224 bytes**. The products
directory contains `Kaname.app`, `KanameCore.framework` and `Kaname.swiftmodule` — and **no test
bundles**, which matters for R11.

**E2 — symbols are present, and they carry Swift type names in full.**

```
$ nm -a Kaname.app/Kaname | wc -l
   12249
$ nm Kaname.app/Kaname | grep FilterChromeLayout | head -1
00000001000330dc t _$s6Kaname18FilterChromeLayoutV10scopeLines5title8subtitleSayAA9ScopeLineVGSS_SSSgtF
```

The module name `Kaname` and the type name `FilterChromeLayout` are both in the mangled symbol.
A `DebugSeed` type or a `SeedScenario` type would appear exactly the same way, so a symbol scan
is a real instrument.

**E3 — string literals survive verbatim.**

```
$ strings -a Kaname.app/Kaname | grep -i "nothing imported\|Show all accounts\|Import a statement"
Import a statement
Import a statement PDF from your bank and Kaname reads the transactions in it, …
Nothing imported yet
Import a statement and the transactions in it will appear here.
Show all accounts
```

So a scenario name, or the string `KANAME_SEED_SCENARIO`, would be findable.

**E4 — ⚠️ and here is the trap.** `xcodebuild -configuration Release -showBuildSettings` reports:

```
COPY_PHASE_STRIP = NO
DEPLOYMENT_POSTPROCESSING = NO
STRIP_INSTALLED_PRODUCT = YES
STRIP_STYLE = all
STRIP_SWIFT_SYMBOLS = YES
```

`STRIP_INSTALLED_PRODUCT` only takes effect when `DEPLOYMENT_POSTPROCESSING` is `YES`, which is
what an `install` or `archive` action sets and a `build` action does not. Simulating the
stripped case:

```
$ strip -rSTx Kaname-copy
$ nm -a Kaname-copy | wc -l
     157                        # was 12,249
$ strings -a Kaname-copy | grep -c FilterChromeLayout
       0                        # was present
$ strings -a Kaname-copy | grep -c "Nothing imported yet"
       1                        # survives
```

**A symbol scan over a stripped artifact is vacuously green.** Twelve thousand symbols become a
hundred and fifty-seven; a type name that was findable disappears; only the string literals
survive. An audit that ran against an archived build and reported "no seeding symbols found"
would be telling the truth and proving nothing.

**Decision, in three parts.**

1. **The audit pins the artifact it inspects.** It performs its own `-configuration Release
   -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO` with a scratch derived-data path, rather
   than auditing whatever binary happens to be lying around. `DEPLOYMENT_POSTPROCESSING` is `NO`
   for that action, so the symbol table is intact by construction.
2. **The audit self-checks before it reports.** It asserts that a known Release-present symbol
   (`FilterChromeLayout`) and a known Release-present literal (`Nothing imported yet`) are both
   found, and **fails** if either is missing. If the binary is stripped, missing, empty or built
   from the wrong configuration, the gate goes red rather than green. This is the discipline the
   repository already applies to its other expensive gates —
   `perf-corpus: the generator did not run - nothing was written`, and
   `reference-check: the suite did not run — nothing was measured` — turned on the audit itself.
3. **The audit scans both `nm` output and `strings` output**, because the two see different
   things and one of them survives stripping.

**E5 — the scan itself is free.** `nm -a` plus `strings -a` over the 2.6 MB binary, piped
through `grep`, measured at **0.03 s** wall clock. The entire cost of the gate is the 16.2 s
build.

⚠️ **`grep -c` returns exit status 1 when it counts zero** — which is the *passing* case for
every pattern this audit looks for. Under `set -euo pipefail` that terminates the script with a
misleading success-shaped failure. `import-path-audit.sh` already handles this with the
`|| true` idiom on every scan; the new script must do the same, and its tasks include watching
it fail correctly.

---

## R5 — The absence proof is **two** checks in two places, and only one of them is a tenth scan

**Decision.**

- A **source scan** joins `scripts/import-path-audit.sh` as its **tenth**, following that file's
  established shape exactly: a comment block saying which defect it is the residue of, a
  denylist array, a `grep -rInE … || true`, a `FAIL` block naming the requirement and the
  remedy, and an `OK` line. It bans the seeding identifiers and `KANAME_SEED_SCENARIO` anywhere
  under `ios/Sources/` **outside** `ios/Sources/DebugSeed/`, and it fails if any file *inside*
  that directory is not wrapped in `#if DEBUG`. This is the scan that catches a mistake in the
  seconds after it is made.
- An **artifact scan** is a new script, `scripts/release-absence-audit.sh`, behind a new
  `make release-audit`. It builds Release and inspects the binary per R4.

**Why two scripts and not one.** `make import-audit` is a 30-millisecond grep. It is cheap
enough that CI runs it without thinking, and cheap enough that a person runs it before every
commit. Putting a 16-second Xcode build inside it would make the cheapest gate in the repository
the most expensive one, and the predictable result is that somebody stops running it. FR-029 is
satisfied by wiring **both** into the documented gate and into CI, not by putting both in one
file.

**Where they attach.**

| Gate | Command | Cost | Runs |
|---|---|---|---|
| Source scan | `make import-audit` (tenth scan) | +~5 ms | already in the local gate; **add to CI** — see R19 |
| Artifact scan | `make release-audit` (new) | 16.2 s + 0.03 s | add to the local gate and to the CI iOS job |

**FR-030 / SC-005 — the audit is watched failing before it is trusted.** Both scans are watched
failing against a deliberately re-enabled path, and the observation is recorded in `tasks.md` in
the table shape 018 used. The injected breaks are named now so the task list does not have to
invent them:

| Break | Which scan must go red |
|---|---|
| Delete the `#if DEBUG` / `#endif` from one `DebugSeed` file | source scan (unguarded file) **and** artifact scan (symbol appears) |
| Move `KANAME_SEED_SCENARIO` into `ios/Sources/Transactions/` | source scan (identifier outside the directory) |
| Change `#if DEBUG` to `#if true` in `KanameApp.swift` | artifact scan (symbol + literal appear in Release) |
| Add a scenario name as a literal in a shipping file | artifact scan (`strings`) |
| Strip the audited binary before the scan runs | the audit's **self-check** — it must report that it can no longer see, not that it found nothing |

That last row is the one that matters most, and it is the row a plan that had not measured E4
would not have known to write.

---

## R6 — Seeded rows go in through `Store.importStatement`, and through nothing else

**Decision.** A scenario is applied as one `Store.importStatement(request:)` call per account,
against the process's own `Store` from `StoreProvider.shared()`.

**Why this is the write path and not a write path.** `import_statement` (`store.rs:713`) is the
call `ImportService` itself makes. It performs, in **one** SQLite transaction: resolve or create
the account, insert the statement row, insert the transactions, link re-imports, run
categorization, run cross-source de-duplication. Every one of those is a behaviour the tests
want to trust. A seeded store is therefore a store the shipping app could have produced by
importing — FR-014 satisfied structurally, and US3's "the only thing that differs is how the
rows got in" true in the strict sense: what is bypassed is the **picker**, and only the picker.

**Determinism comes free, and here is exactly why.**

- **No wall clock.** `ImportRequest.now` is a caller-supplied `String`; the core reads no clock
  for logic. A scenario declares its own `now`, and FR-023 holds without anything being pinned.
- **Account order is insertion order.** `list_accounts_in` is
  `SELECT … FROM accounts ORDER BY rowid` (`store.rs:1661`), and the history's account tie-break
  is that same position (018 R3). A scenario's account order is the order it declares.
- **The dedup winner is insertion order.** After 018 PR A's R17 fix, `load_dedup_candidates`
  orders by `a.rowid, t.rowid` (`store.rs:1874`) rather than the random `accounts.id`. Two runs
  of the same scenario therefore supersede the *same* row. Before that fix this slice would have
  been unable to declare a superseded fixture at all, because which row lost was a coin toss.
- **The order the list shows is total** — `date DESC`, account position, `transactions.rowid`
  (018 R3) — so the same declaration produces the same sequence on every machine.

**⚠️ But every id is random.** `mint_id` is
`SELECT lower(hex(randomblob(16)))` (`store.rs:1716`), used for accounts, statements and
transactions alike. Two runs of the same scenario produce the same rows in the same order with
**different ids** every time.

**Consequence, and it is a rule for the task list**: a seeded assertion may never name an id.
Expectations are keyed on the tuple a person can see — date, description, amount, currency,
account name — which is also the tuple `TransactionRow.accessibilityLabel` renders, so the
XCUITest assertion and the fixture declaration describe the same thing (R14, `contracts/`).

---

## R7 — Putting `DebugSeed/` under `ios/Sources/` makes two existing scans do this slice's work

`scripts/import-path-audit.sh` scans **all** of `ios/Sources/` for two things that bear directly
on a fixture:

- **Networking symbols** (`URLSession`, `NWConnection`, `getaddrinfo`, `import Network`, …). The
  new directory is covered the moment it exists, so FR-033 / SC-011 need no new machinery. This
  is precisely the hole 018 R19 closed by widening the scan from `ios/Sources/Import` to
  `ios/Sources`; this slice is the first new directory to benefit from it.
- **Bank literals**, read out of `core/.../statement/registry.rs` (`id`, `display_name`) and out
  of every reader's `BANK_CODE`, word-boundary matched, case-sensitive. **A scenario therefore
  cannot name a real issuer.** `make import-audit` fails the build on
  `ICICI Amazon Pay Credit Card` in a fixture. FR-011's "entirely synthetic" is enforced
  mechanically, for free, and by a scan that already exists.

**Decision.** Scenario account names are synthetic and issuer-free — `SYNTHETIC BANK ONE`,
`SYNTHETIC CARD TWO` — and `bank_code` is a synthetic code (`SYNTH_BANK`, `SYNTH_CARD`) that is
in no registry row.

**⚠️ Checked, because it would have been a quiet trap.** `categorize_account_in`
(`store.rs:1286`) reads `bank_code` to look up `source_category_map`. An unrecognised code
simply matches nothing at the T1 stage, so seeded rows fall through to the merchant and rule
stages or stay uncategorized. That is not a defect for this slice — it is FR-008's requirement
for **both** categorized and uncategorized rows, obtained without a bank code. A scenario's
categorized rows come from a synthetic description matching a default T3 rule, and its
uncategorized rows from one that matches nothing.

**A third scan constrains the wording.** The transfer-claim scan fails on
`transfers? (are|is|were) (auto|detect)` and friends anywhere under `ios/Sources` **or**
`ios/Tests`, unless the line carries a negation. Any new test name or comment about the transfer
marking has to be written with that in mind — which is also R8's conclusion arrived at from the
other direction.

---

## R8 — Which of FR-008's clauses are reachable through that write path, and the two that are not

FR-008 lists eight situations a scenario must be able to express. Six are reachable through
`import_statement` alone. Two are not, and both were anticipated by the spec's own Assumptions
section, which asked for them to be named here rather than worked around.

| FR-008 clause | Reachable? | How |
|---|---|---|
| Several accounts | ✅ | One `importStatement` call per account |
| More than one currency | ✅ | `NewImportTransaction.currency` is per **row**, not per account |
| Same-date collision across accounts | ✅ | Two accounts, one declared date |
| Rows superseded by de-duplication | ✅ | Two engine-native routes — see below |
| Deleted rows | ⛔ | **No write path exists** — see below |
| An account whose statement had zero transactions | ✅ | `transactions: []` |
| Categorized and uncategorized rows | ✅ | R7 — a description that matches a default rule, and one that does not |
| Rows flagged as transfers | ⛔ | **Banned by an existing scan, and it would be a lie** — see below |

**Superseded rows, two ways, both the engine's own.** Re-importing the same statement makes the
new rows supersede the held ones (016's re-import supersession, visible in `ImportOutcome`'s
`rows_superseded`). Cross-source de-duplication supersedes a row held in one account when a
matching row arrives in another. ⚠️ After 018 PR A's source-kind guard, cross-source dedup
**only ever compares a bank ledger against a credit card** (`store.rs:1448`, `incoming_is_card`)
— so a scenario that wants a cross-source supersession must declare exactly that pairing, and a
scenario built from two synthetic *cards* would silently produce no supersession at all. This is
the kind of thing a fixture gets wrong once and then nobody understands the fixture.

**⛔ Deleted rows have no write path.** `is_deleted` is declared
`INTEGER NOT NULL DEFAULT 0` (`store.rs:83`) and is **never `UPDATE`d anywhere in
`store.rs`**. The only rows in the repository with `is_deleted = 1` are written by raw SQL
inside engine tests (`store.rs:2900`). There is no Swift-facing API that sets it, and R2
forecloses adding one. **Recorded as a limitation, per the spec's Assumptions**: a scenario
declares no deleted rows, and the half of the live rule that covers deletion stays pinned
engine-side by `core/tests/history_live.rs` L1/L4/L5, exactly as it is today. Nothing is lost
that matters: `EmptyKind.accountNothingToShow` — "every row excluded" — is reachable from
**superseded** rows alone, so every empty state R9 says is reachable stays reachable.

**⛔ Transfer-flagged rows must not be seeded, and this is not only a mechanical objection.**
`is_transfer` is set only by `Store::detect_transfers`, and `import-path-audit.sh`'s
transfer-detection scan **fails the build if any Swift source under `ios/Sources` calls
`detectTransfers`** — a ban that 018 R18 put there deliberately, with the instruction that
removing it is a whole slice's decision made by somebody who has read why it is there.
`ios/Sources/DebugSeed/` is under `ios/Sources`. But the mechanical objection is the smaller
one. **Every row of every real install has `is_transfer = 0`**, because nothing calls the
detector. A seeded store with a transfer marking on it would be a store **no person can have**,
and US3's whole point is that what the auditor sees is the shipping screen. Seeding a transfer
would be building the lying gate US3 ranks above everything but the absence proof.

**Recorded**: FR-008's transfer clause is **deferred to the slice that wires detection**, which
is the same slice that owns removing the scan. The marking keeps the unit coverage it has
(`ios/Tests/TransactionTransferMarkingTests.swift`). This is flagged for the product owner in
`plan.md` § *Judgement calls*.

---

## R9 — 🚨 FINDING: `EmptyKind.nothingImported` stays unreachable, and seeding does not change that

**The finding, traced end to end.**

- `EmptyKind.decide` returns `.nothingImported` **iff** `summaries.isEmpty`
  (`TransactionListModels.swift:180`) — and *only* then; the filtered branch is below the guard.
- `TransactionListViewModel.reload()` builds `summaries` from `history.accountSummaries()`, and
  sets `.empty(…)` only after that read returns.
- `RootView` offers the only route to the list — a toolbar `NavigationLink(value: AccountFilter.all)`
  — and shows it **only `if !model.accounts.isEmpty`**.
- `model.accounts` comes from `ImportViewModel` → `ImportService`, which reads
  `store.accountSummaries()` (`ImportService.swift:126`). **The same call.**

So the state in which the list would say "nothing imported" is exactly the state in which the
front door offers no way to reach the list. And there is not even a transient window: the view
model's initial state is `.loading`, not `.empty`, so a run cannot catch the branch during a
load.

**Seeding cannot produce the contradiction.** A seed either creates accounts — in which case
`summaries` is non-empty and the branch is not taken — or creates none, in which case there is
no route. There is no third option that does not add an entry point, and FR-003 and FR-031
forbid an entry point in as many words.

**What this slice can honestly deliver against FR-039 / SC-007.** The only way to *render* this
branch automatically, without an entry point, is to host the real view in the **unit-test**
target:

```swift
let model = TransactionListViewModel(history: TransactionHistoryDouble(summaries: [], pages: []))
let host = UIHostingController(rootView: TransactionListView(filter: .all, model: model) {})
```

`ios/Tests/TransactionListDoubles.swift` already supplies the double, and `KanameTests` is
hosted in the app so `UIHostingController` is available. Forcing a layout pass executes the
branch and renders it; the assertion is on the accessibility tree of the hosted view. ⚠️ It
**cannot** run `performAccessibilityAudit`, which is an `XCUIApplication` method with no
in-process equivalent. So SC-002's audit does not extend to this state, and no wording anywhere
may suggest it does.

**This needs the product owner's decision.** Three options, in the plan's *Judgement calls* §1:

1. **Host-render it in `KanameTests`** (recommended). First automated execution ever, no
   shipping change, honest about what it does not cover.
2. **Delete the branch** as dead code. Blocked here by FR-018 and FR-047 — this slice may not
   change the transaction list — and it would need `EmptyKind` to have a total, non-optional
   answer for the empty-summaries case anyway.
3. **Change the front door** so the link is always offered. A product change, out of scope, and
   arguably wrong: a link to a list of nothing, on a screen that already says nothing was
   imported, is the contradiction design note D3 exists to prevent.

Whatever is chosen, the *existing* unit coverage of the decision
(`TransactionEmptyStateTests.nothingImported`) is not affected. What has never happened, and
what option 1 makes happen, is the **view** being drawn for it.

---

## R10 — The auditor catches `018/02`; it cannot catch `018/03`. That needs a second instrument

> 🚨 **OBSERVED, 2026-08-18 (019 PR C, T073/T074): the first half of this heading is wrong.**
> The auditor does **not** catch `018/02`. Reinstated faithfully — the chip rendering `••••…`
> over `SYN-T…NE`, the ticket's own screenshot reproduced — `performAccessibilityAudit` passed.
> `.textClipped` could not have discriminated it in any case: at `AccessibilityXXXL` this screen
> fires that type **by design** (the row caps its account line at one line so the masked digits
> survive — `.scratch/019-debug-test-seeding/issues/03`), so the audit is red before the break.
> Two further facts came out of running it, both of which invalidate the obvious workarounds: a
> `Text`'s **label is the untruncated string**, so no assertion on labels can see an ellipsis;
> and neither one-line break reproduces its defect, because both 018 fixes were plural. What
> carries FR-038 is **geometry** in both cases — see `quickstart.md` § *What it turned out to
> be*. The reasoning below is kept as it was written, because it is the reasoning that sent
> T074 looking, and being wrong in a recorded way is what made the answer cheap to find.

FR-038 requires the new coverage to be watched failing against two reinstated defects. They are
not the same kind of defect, and one instrument does not see both.

**The auditor's complete repertoire on iOS**, read from
`XCUIAutomation.framework/Headers/XCUIAccessibilityAuditTypes.h`:

```
Contrast · ElementDetection · HitRegion · SufficientElementDescription
DynamicType · TextClipped · Trait
```

Seven types. There is **no occlusion audit** — nothing that asks whether one element is drawn
over another.

**`018/02` — the filter chip reading `•••• 77…` with the digits cut.** That is text truncated
inside its own element: `.textClipped`, and the auditor is exactly the right instrument. The
deliberate break to watch it fail against is the one the ticket itself records:
`FilterChromeLayout.axis` forced back to `.horizontal`, which is what produced the truncation
after the *first* fix was found insufficient. Reinstating it puts ~420 pt of demand on a 393 pt
screen and the auditor should see the result.

**`018/03` — a row's amount sliced horizontally by the bottom bar.** That is **occlusion by a
sibling**: the row's own text is laid out correctly and the glass bar is drawn over the top of
it. Nothing in the seven types asks about it. An auditor-only gate would pass this defect, which
is precisely the "coverage that lies" US3 ranks second only to a shipped hook.

**Decision.** `018/03`'s coverage is an **explicit XCUITest geometry assertion**, beside the
audit and not inside it: with the `small` scenario seeded and a filter applied, at
`AccessibilityXXXL`, scroll to the end and assert that the last row's frame clears the filter
bar's frame —

```swift
XCTAssertLessThanOrEqual(lastRow.frame.maxY, filterBar.frame.minY)
```

watched failing against `FilterChromeLayout.maximumScopeLines` restored to **6**, which is the
break `018/03`'s own resolution records as the one that produced an unbounded bar.

**This is why FR-038 names two defects rather than one**, and it is the concrete reason the
`small` scenario has to exist: `018/03` records that at XXXL the end of a 10,000-row list is
"some hundreds of flicks away" and the gate was not runnable at all until a six-row corpus
existed. A question about the *end* of a list needs a short list.

⚠️ **Honesty about this entry.** The auditor's behaviour on `018/02` is inferred from the audit
type list and the ticket's description of the failure; it was not run, because running it
requires the capability this slice is planning. The tasks therefore **watch both go red before
either is trusted** (FR-030's discipline applied to FR-038), and if the auditor turns out not to
fire on the reinstated chip, the remedy is a second geometry assertion of the same shape — not a
weakened criterion.

---

## R11 — One declaration, compiled into the DEBUG app **and** into the UI-test bundle

**Decision.** `ios/Sources/DebugSeed/SeedScenarios.swift` holds every scenario as Swift values.
`Project.swift` adds that one path to the `KanameUITests` target's `sources` alongside
`UITests/**`, so the test bundle links the **same literal** the app writes:

```swift
.target(
    name: "KanameUITests",
    …
    sources: ["UITests/**", "Sources/DebugSeed/SeedScenarios.swift"],
```

The app writes `SeedScenario.small.rows`; the test asserts against `SeedScenario.small.rows`.
FR-010's "declared in one place, and what the tests expect derived from that same declaration"
becomes structural rather than remembered, and FR-046's drift failure — "a test that quietly
stopped asserting anything" — has nowhere to happen.

**Why this satisfies SC-015.** "A new scenario can be added with **zero** changes to any file
compiled into a Release build." `SeedScenarios.swift` is wrapped in `#if DEBUG`, so it compiles
to nothing in Release; adding a scenario touches it and nothing else. `KanameApp.swift` *is*
compiled into Release, and it is touched **once**, by this slice, and never again by a scenario.

**⚠️ Two things checked, because both would have bitten.**

- **The Release build does not compile the test targets.** E1's products directory contains
  `Kaname.app`, `KanameCore.framework` and `Kaname.swiftmodule` and no `.xctest` bundle. So
  `make release-audit`'s Release build is not affected by UI-test code that references
  `SeedScenario`, which would not compile in a Release configuration (the UI-test target has no
  `DEBUG` outside its Debug configuration). If the scheme's build action is ever changed to
  include test targets, the audit's build breaks loudly rather than silently — an acceptable
  failure mode, and the quickstart records the remedy (`-target Kaname`).
- **SwiftLint and `swift-format` cover the new path both ways.** `swiftlint --strict` runs over
  `ios/` with `Sources` not excluded, and `make lint` format-lints `Sources Tests UITests`. A
  file listed in two targets is linted once. See R19 for what CI does *not* cover.

**Alternatives considered and rejected.**

| Alternative | Why not |
|---|---|
| Pass the whole scenario as JSON in `launchEnvironment` | FR-007 wants a **name**, and FR-006 wants an unrecognised name to fail — neither means anything if the payload *is* the scenario. Worse, it makes the DEBUG surface a general-purpose row injector whose shape is decided by whatever is on the other end. A named scenario is a closed set; a JSON payload is not. |
| A bundled resource (JSON/plist) | A **file in the app bundle**, which FR-024 bans from Release. Resources are excluded per-configuration by build settings rather than by source, so the exclusion lives away from the data — and the artifact audit would then have to police the bundle's file list as well as its binary. |
| Duplicate the expectations in the test file | The drift FR-010 exists to prevent, written down on purpose. |
| Have the app report what it seeded back to the test | A channel from the app to a test harness is a surface, and it would have to be absent from Release too. Two problems for one. |

---

## R12 — A seeded launch resets by deleting the database file, and only then

**Decision.** When — and only when — `KANAME_SEED_SCENARIO` is set, the seeder deletes the
database file and its sidecars before `StoreProvider.shared()` is ever called, then seeds:

```
Application Support/Kaname/kaname.db          ← StoreLocator.databaseURL
Application Support/Kaname/kaname.db-journal
Application Support/Kaname/kaname.db-wal
Application Support/Kaname/kaname.db-shm
```

**Rationale.**

- **The Keychain key is left alone**, so `StoreLocator.open()` mints a fresh database and
  encrypts it with the app's **own** key, fetched the app's own way. FR-017 holds with no test
  key existing in any target, and SC-013's "zero hard-coded, bundled or exported keys" is true
  because nothing was added.
- **Which sidecars.** `Store::open` sets only `key` and `foreign_keys` pragmas
  (`store.rs:587,606`) — no `journal_mode` — so SQLite's default rollback journal applies and
  the live sidecar is `-journal`. `-wal` and `-shm` are deleted too, defensively: if a later
  slice enables WAL, a stale `-wal` beside a deleted `.db` is a corruption report nobody will
  connect to this file.
- **FR-022 is structural.** The deletion is inside the same `guard let scenario` as the seed. No
  request, no deletion — a developer's own DEBUG build with their own imported data is
  untouched, which is the edge case the spec calls out.
- **SC-010's ten consecutive runs** need the reset to be *inside* the app, not outside it.
  `make ios-test` already uninstalls once before the whole suite (and the `Makefile` explains
  why at length), but nothing runs between two tests in one suite. Putting the reset in the
  launch path is what makes "the same run twice is the same run" a property of the code.

**Alternatives considered and rejected.** Wiping tables through SQL (leaves the schema version
and any future non-table state, and needs a delete path the store does not have); a per-run
database filename (the seeded store would then not be the app's own store, breaking FR-017 and
US3); `simctl uninstall` between tests (moves the suite's cleanliness outside the suite, and
cannot be expressed from inside an XCUITest).

---

## R13 — A seed that cannot be applied **crashes the launch**, deliberately

**Decision.** An unrecognised scenario name, or an `importStatement` that throws, calls
`fatalError` with a message naming the scenario. Nothing is caught, nothing is degraded.

**Rationale.**

- FR-006 and SC-016 forbid the tempting behaviour outright. The consequence of falling back to
  an empty app is an accessibility audit reporting success against a blank screen — the exact
  failure mode this whole slice exists to remove.
- `App.init()` has **no UI to show and no channel to report on**. The only signal an XCUITest
  reliably observes is the app failing to reach the foreground, and every existing UI test
  already asserts exactly that: `XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))`.
  So a crash is not a blunt instrument here — it is the *only* instrument that the assertion
  already in the suite will notice.
- **A partial write cannot commit.** `import_statement` is one SQLite transaction; a failure
  rolls the whole statement back. So "a seed that fails halfway" is, at the store level, a seed
  that did not happen — and the crash makes it a seed that is *reported* as not having happened.
- ⚠️ `fatalError` in a shipping source would deserve an argument. This one is inside `#if DEBUG`
  in a directory that R4's artifact audit proves is absent from Release.

---

## R14 — Two scenarios, named for the questions they answer

**Decision.** Two scenarios ship with this slice.

| Scenario | Shape | The question it exists for |
|---|---|---|
| `small` | **6 rows**, 1 account, 1 currency | The *end* of a list. `018/03`'s G2 and `018/02`'s G5, at `AccessibilityXXXL`, where a single row is most of the screen |
| `deep` | **160 rows**, 3 accounts (one of them a bank ledger, one a card, one with a zero-transaction statement), 2 currencies, one same-date cross-account collision, one cross-source supersession | Paging, ordering across a page boundary, the filter's four states, the currency rule |

**Why `small` is six rows.** `018/03`'s resolution records that G2 was **not runnable by a
person at all** on the 10,000-row corpus, because at XXXL the end of the list is "some hundreds
of flicks away", and that the gate only became runnable when `gate/01-icici-0006.pdf` — one
statement, six rows, its own account — was added. `small` is that corpus expressed as a seed:
the end of the list is two flicks away, so the run can reach it and assert about it.

**Why `deep` is 160 rows.** `TransactionListViewModel.pageSize` defaults to **50**
(`init(history:clock:pageSize:)`). "Pages more than once" therefore needs more than 100 rows;
160 gives four pages with the last one partial, which also exercises the exhausted-cursor case.
It is 1.6% of the corpus `make perf-corpus` already builds and verifies by importing, so it is
comfortably inside SC-009's budget (R15).

**Why two and not one, and not one per test.** One scenario reproduces `018/03`'s trap on the
first day and is expensive to undo later — this is the lesson of that ticket written into the
capability rather than rediscovered (FR-009, US5's *Why this priority*). One scenario per test
grows the fixture surface with the suite and forces FR-019's determinism to be re-proved for
each. Two, named for questions rather than sizes, means a later screen adds
`budgets-two-months` rather than growing `deep` until nobody knows what it is for.

**What `deep` must be built to avoid.** 018 R20 records that a synthetic corpus must be
constructed so that it does not de-duplicate *itself*: identical rows across accounts collapse.
Here that is a feature — one such pair is declared deliberately to produce the supersession — but
every *other* row must be distinct enough not to. The declaration therefore varies the
description and amount per row, and the contract states the rule so a later scenario author does
not have to rediscover it by watching a count come out short.

---

## R15 — SC-009's five seconds: what the seed costs, and where the number comes from

**Decision.** SC-009 is asserted from the UI test's own wall clock — launch to the first row
existing — because that is the number the criterion is actually about, and because it is the
number that degrades if a later scenario grows.

**What is known.** 018 measured the *read* side on a real SQLCipher store with 10,000
transactions across 8 accounts: first page **254.75 µs**, worst page over a full walk **289 µs**.
The *write* side is the expensive one — `import_statement` runs categorization and cross-source
de-duplication per import — and 018 did not measure it. `make perf-corpus` writes and verifies
10,000 rows across 8 accounts by importing all eight into a throwaway store as part of an
ordinary `xcodebuild test` invocation, which puts a loose upper bound on the write path at
something a test target already absorbs. `deep` is **1.6%** of that.

**What is not known, and is said rather than assumed.** This plan has **no measured number** for
seeding 160 rows in `App.init()`. The task list carries the measurement, taken the way 018 took
its own, and the bound is asserted rather than estimated. If it turns out that a synchronous
seed in `init()` is slow enough to be felt, the remedy named in advance is to shrink `deep`,
**not** to move the seed off the launch path — FR-002 requires the history to be complete before
any screen can observe it, and an asynchronous seed is a race with the first screenshot.

---

## R16 — ⚠️ Locale is a hidden input to every assertion about a seeded amount

**The finding.** `TransactionRow.formattedAmount` is
`"\(directionSign)\(amount.formatted(.currency(code: currency)))"`, and
`accessibilityLabel` embeds the same formatted string. `.currency(code:)` takes the **symbol**
from the code but the **grouping** from the locale: the same `Decimal` in `INR` renders
`₹1,23,456.00` under `en_IN` (lakh grouping) and `₹123,456.00` under `en_US`. A UI test that
asserts a row's label is therefore asserting about the region the simulator happens to be set
to — and FR-019 requires the same result "on every machine".

**Decision, belt and braces.**

1. The seeded UI tests pin the locale on the launch:
   `app.launchArguments += ["-AppleLocale", "en_IN", "-AppleLanguages", "(en)"]`.
2. Every seeded amount stays **below the first grouping boundary where the two disagree**
   (₹1,00,000 / ₹100,000), so the assertion is true under either — including on a simulator
   somebody has set to a third region.

**Why both.** Pinning alone is a setting somebody can forget when they add a scenario; small
amounts alone leave a trap for the first scenario that needs a large one. The contract records
the rule so the second author does not have to rediscover it — and `018/04` is the ticket
proving that "a very large amount and a very long account name in the same row" is a shape this
repository actually cares about, so a later scenario *will* want one.

⚠️ This is the same class of trap `make ios-test` already pins `content_size large` for, and for
the same reason: a machine-wide setting silently changing what a test means.

---

## R17 — What the manual gate actually shrinks to, and one gap in SC-008's own arithmetic

018's gate is fourteen steps, G1–G14 (`specs/018-transaction-list/quickstart.md`
§ *The manual, release-blocking gate*). Working through them against what this slice delivers:

| Gate | After this slice | Why |
|---|---|---|
| G1 amounts never truncate at XXXL | **Automated** | Auditor `.textClipped` over the seeded, populated list at XXXL |
| G2 no row clipped by the bottom bar | **Automated** | R10's geometry assertion on the `small` scenario, filtered |
| G3 VoiceOver reads a row as one sentence | **Split** — presence automated, **meaningfulness manual** | Auditor `.sufficientElementDescription` proves a label exists and is not "Button"; whether the sentence *means* something is a judgement |
| G4 heading announced, year when not current | **Automated** | The seeded scenario declares a prior-year date; the group header's label is asserted |
| G5 filter announced, clearing reachable | **Automated** | Auditor + the existing `scopeAnnouncement`; the visual half is `018/02`'s reinstated break |
| G6 Reduce Transparency | **Manual** | No `simctl` control, no test API. FR-043 |
| G7 Increase Contrast + Dark Mode | **Automated** | `make a11y-sweep` already sets it with `simctl`; it gains a populated screen |
| G8 the date in view stays identifiable | **Automated** | Scroll and assert the pinned header changes with the rows |
| G9 / G11 / G12 device timings | **Manual** | `issues/06`. A phone, and a screen recording. FR-043 |
| G10 scroll: no persistent blank rows | **Manual** ⚠️ | A device rendering judgement over the full corpus. Not in SC-008's list |
| G13 / G14 import while the list is open | **Manual** ⚠️ | Needs a **live import through the picker**, which is exactly what no automated run can drive. Not in SC-008's list |

**⚠️ FINDING — SC-008 enumerates five remaining items; there are eight.** SC-008 says the gate
"falls to only those no machine can set or judge — Reduce Transparency, VoiceOver assessed for
meaningfulness, and the three device timings — and takes under ten minutes". That accounts for
G6, G3's judgement half, and G9/G11/G12. It does **not** account for **G10, G13 and G14**.

G13 and G14 are the load-bearing ones: 018's own record calls them "the only evidence anywhere
that US8 works on a device", and they require an import to happen *while the list is open*.
Seeding bypasses the picker at launch; it does not put a picker into a running test. So G13 and
G14 stay manual, and this slice does not shorten them.

**Recommendation** (`plan.md` § *Judgement calls* §3): the rewritten gate record keeps G10, G13
and G14 as manual with their reasons stated, and SC-008's enumeration is treated as incomplete
rather than as a target to hit by reclassifying a gate. Under-ten-minutes remains plausible —
G13/G14 are two runs of one setup — but the *list* needs the product owner's word before a
success criterion is reported as met.

**FR-044 is a wording constraint on the whole record**: nothing may claim SC-012 is closed, and
nothing may suggest CI enforces a step a person still runs. The gate record's existing "What
this record does and does not close" section is the right place for that sentence and already
has the right tone.

---

## R18 — Nothing about the store changes, and that is a decision worth recording

Following 017's precedent of recording a deliberate non-change:

**The schema stays at v7.** No migration, no `PRAGMA user_version` bump, no new column, no new
index, no new table. `core/crates/kaname-core` is not touched by this slice at all.

**Why that is the tell that the design is right.** The seed writes rows through
`import_statement`, which writes only into the tables v1–v7 already define, using the same
columns an imported statement uses. If this slice had needed a migration — a `seeded` flag, a
test-fixtures table, a way to write `is_deleted` — that would have been the signal that seeding
had stopped going through the front door and started going around it, which is exactly what
FR-014 and US3 forbid. R8's two unreachable clauses are recorded as findings **precisely
because** closing them would have required this paragraph to say something else.

---

## R19 — Where the gates attach, and one CI discrepancy found while looking

**What this slice adds to the gate.**

```
make core-lint && make core-test        # unchanged; this slice adds no Rust
make lint && make ios-test              # unchanged commands, new tests inside
make import-audit                       # NINE scans → TEN
make release-audit                      # NEW — 16.2 s
make a11y-sweep                         # unchanged; now audits a populated screen
```

⚠️ **The `a11y-sweep` / `ios-test` interaction is already load-bearing and gets no weaker.**
`make ios-test` uninstalls the app and pins `content_size large` before running, for reasons the
`Makefile` explains at length — a container from an earlier run, and a text size left over from
a manual gate, each cost a false result once. A seeded suite that sets its own text size must
put it back, and R12's in-app reset means the container trap is now handled twice, which is
correct rather than redundant.

⚠️ **Do not run the core and iOS gates concurrently.** `core/tests/history_perf.rs::s5` is
wall-clock and flaky under CPU contention. This slice adds no core test, but it does add a
16-second Xcode build to the gate, and a person who parallelises to win it back will pay for it
in a flaky `s5`. Stated in the quickstart.

**⚠️ FINDING, not caused by this slice.** `.github/workflows/ci.yml` runs

```yaml
- name: swift-format lint
  run: swift-format lint --recursive --strict Sources Tests
```

while `make lint` runs `… Sources Tests UITests`. **Every line in `ios/UITests/` is
format-linted locally and not in CI.** Today that is one file; this slice is the first to put
real volume there. Recommendation: widen the CI step to `Sources Tests UITests` in the same PR —
a one-word change, and the same class of narrowing that 018 R19 found in the networking scan.

Also noted: CI's `import-audit` is currently run by neither job — `core-privacy-audit` is, and
`import-audit` is not. FR-029 requires the absence check to run in CI, so the iOS job gains
`make import-audit` and `make release-audit` steps. Wiring `import-audit` into CI closes a gap
the other nine scans have had all along.

---

## R20 — What the seeded UI test asserts against, and why it is the accessibility label

**Decision.** The seeded assertions match on `TransactionRowView`'s accessibility label, because
that is the only per-row string XCUITest can see.

`TransactionRowView` applies `.accessibilityElement(children: .combine)` and
`.accessibilityLabel(row.accessibilityLabel)`, so the whole row is **one** element to the
automation, and its label is:

```
28 December 2025, SYNTHETIC MERCHANT 04, ₹450.00 Debit, SYNTHETIC BANK ONE ···· 0006, Groceries
```

— date with year, description, amount **with currency**, direction **in words**, account
identity, category, and `Transfer` if marked. That single string carries every field SC-001
demands be checked ("exact dates, exact amounts to the last paisa, descriptions, currencies and
account attribution as declared"), which means the assertion is one comparison against one
string the fixture can produce.

**Consequences the contract records.**

- The expected label is **derived from the declaration**, by the same function the app uses
  where possible, so FR-010's no-drift rule extends to the assertions themselves.
- The label is locale-sensitive (R16) and id-free (R6), which is why both rules are stated as
  fixture constraints rather than test hygiene.
- "**and nothing else is**" (US1 AS-3) is checkable as a count: the run asserts the number of
  row elements equals the declared live-row count, which is also the number
  `AccountSummary.liveTransactionCount` reports — the engine's count and the screen's rows,
  compared, which is the property 018 built `account_summaries()` to make true.
