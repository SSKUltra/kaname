# AGENTS.md

Agent instructions for the Kaname repo. Repo-wide conventions and
Copilot-specific guidance live in
[`.github/copilot-instructions.md`](.github/copilot-instructions.md).

## Start here (task pickup)

New session? Read [`.scratch/HANDOFF.md`](.scratch/HANDOFF.md) first — it's the
current-status + what's-next index (then the constitution, then the feature's
`.scratch/<slug>/` spec + tickets).

## Agent skills

### Issue tracker

Issues and specs live as local markdown under `.scratch/<feature-slug>/`.
See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical roles (`needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human`, `wontfix`), recorded as a `Status:` line in each issue
file. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` + `docs/adr/` at the repo root.
See `docs/agents/domain.md`.

### Reading a statement

Extraction is **geometry-first** and platform-side: a line is one *printed row*, rebuilt from
where the glyphs sit, never the PDF text layer's own newlines. It lives in
`ios/Sources/Import/PrintedRows.swift` (which words form a row) and `WordGeometry.swift` (where
a word is, and the three separate ways PDFKit gets that wrong). Evidence is
`fixtures/geometry/*.json` — synthetic layout signatures rendered to real PDFs at test time,
each of which must fail against the pre-017 extraction to count. No real statement, and no
fragment of one, ever enters this repository.


## Seeding a screen with data (019)

An automated run cannot import a statement — the picker is a system UI nothing can drive — so a
**DEBUG-only** launch writes a named synthetic history through the shipped
`Store.importStatement` before any view is evaluated:

```swift
let app = XCUIApplication()
app.launchEnvironment["KANAME_SEED_SCENARIO"] = "small"   // small · deep · barren · empty
app.launchArguments += ["-AppleLocale", "en_IN", "-AppleLanguages", "(en)"]
app.launch()
```

`ios/Sources/DebugSeed/` holds all of it, entirely inside `#if DEBUG`; `ios/UITests/SeededLaunch
.swift` wraps the launch, the walk and the filter. Two gates prove it cannot ship: the tenth scan
in `make import-audit`, and `make release-audit`, which builds its own Release binary (~16 s) and
refuses to conclude an absence unless it first finds a symbol and a literal it knows are present.

**The traps, each of which fails quietly:**

- ⚠️ The key is **bare** on `launchEnvironment`. The `TEST_RUNNER_` prefix is the rule for
  app-hosted *unit* tests (`make reference-check`, `make perf-corpus`); prefixed here it is never
  delivered and the suite runs unseeded, which looks exactly like a pass.
- ⚠️ **Pin the locale, and keep every amount under ₹1,00,000.** `.currency(code:)` takes its
  grouping from the locale (`₹1,23,456` vs `₹123,456`), and the test runner is a different process
  from the app, so an expectation must pin `en_IN` too.
- ⚠️ **Two credit cards never de-duplicate, silently.** Cross-source dedup compares a bank ledger
  against a card and nothing else (`store.rs`'s source-kind guard). A scenario declaring both sides
  as cards loses its supersession with no error anywhere; the fixture's own row count is the only
  thing that notices.
- ⚠️ **A `List` renders a screenful, not a list**, and a row's sentence is not on its cell — it
  hangs on a `StaticText` inside, and a date heading is a cell too. Use `SeededLaunch.walk`.
- ⚠️ **A seeded store outlives the suite that wrote it.** Reset in `tearDown` with the `empty`
  scenario, or the shipped front-door audits assert a fresh install against an accounts list.
- ⚠️ **Adding a file needs `make ios-gen`.** `sources: ["Sources/**"]` is resolved at generation
  time, so a new test file is compiled by nothing — and a suite that never ran reports success.

## Two traps this repo will spring on you (018)

**1. `ios/Sources/Import/ImportService.swift` sits on the SwiftLint file-length limit.** The
threshold is 400 lines and `make lint`'s `--strict` turns the warning into a failure, so *one*
added line fails the gate. It is at **398** as of 019, with **two lines** of headroom, and the
only reason there is any room at all is that the front-door count moved into the engine. If you
need to add to it, **move something out** — do not reformat to squeeze under. New platform code
for the transaction list belongs in `ios/Sources/Transactions/`.

**2. Never run a bare `tuist generate`.** `tuist` resolves the xcframework path *at generation
time*, so after any change to `core/src/ffi.rs` or any `#[uniffi::export]` you must run
`make core-xcframework` **then** `make ios-gen` (which depends on it). Skipping the rebuild
yields "cannot find `HistoryPage` in scope" — a Swift error that is not a Swift problem, and
which sends you looking in the wrong language.

## The build sequence, in the imperative (020)

Three rules. Each of them has cost this repo a rebuild or a vacuous green run.

1. **Changed an `#[uniffi::export]`, a `uniffi::Record` or an enum crossing the FFI?**
   → `make core-xcframework` **then** `make ios-gen`. Both, in that order, every time — including
   when you *revert* a deliberate break in Rust, or the simulator keeps testing the broken engine.
2. **Added a file anywhere under `ios/Sources/**` or `ios/Tests/**`?** → `make ios-gen`.
   `sources: ["Sources/**"]` is resolved **at generation time**, so a new file is compiled by
   nothing and **a test suite that never ran reports success.** This has bitten twice.
   ⚠️ `KanameUITests` does not glob `Sources/**` at all — it hand-lists `UITests/**` plus
   `Sources/DebugSeed/SeedScenarios.swift` and `SeedExpectations.swift`. Sharing a declaration
   with a UI test is a `Project.swift` edit **and** a `make ios-gen`.
3. **Running `make` from a script, a CI step or an agent shell?** → prefix
   `. "$HOME/.cargo/env" &&`. `.zshrc` sources it and a non-interactive shell does not read
   `.zshrc`, so `build-xcframework.sh` fails with `cargo: command not found` — which reads like a
   missing toolchain and is a missing `PATH`.

⚠️ **And never run `make core-test` and `make ios-test` concurrently.**
`core/crates/kaname-core/tests/history_perf.rs::s5` is wall-clock and flaky under CPU contention.
More generally: **a wall-clock failure is a claim about the machine until you measure the
machine** — check `uptime` and, if in doubt, `git stash` and run the same test against `HEAD`
under the same load. A `Timed out while synthesizing event` UI failure is never worth debugging.
