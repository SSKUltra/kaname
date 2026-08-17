# Implementation Plan: DEBUG-Only Test Seeding

**Branch**: `019-debug-test-seeding` | **Date**: 2026-08-17 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/019-debug-test-seeding/spec.md` — FR-001–FR-049,
SC-001–SC-017, six user stories. Its § *Decisions taken without asking* and § *Out of Scope* are
settled constraints and are not re-opened here.

## Summary

018 shipped a transaction list that no automated test has ever seen with a transaction in it.
Every UI test in this repository launches a **fresh install**, so every accessibility audit runs
against an empty screen, and the two defects 018 found — a filter chip truncating at
`AccessibilityXXXL`, a row's amount sliced by the floating glass bar — were both found by a
person, by hand, and both parked. This slice gives the tests a populated store: a launch reads
`KANAME_SEED_SCENARIO` from its environment, writes a named synthetic history into the app's own
encrypted store, and hands the ordinary app an ordinary store to open. Nothing else changes.

**The technical shape, in one paragraph.** The seeding path is **Swift-only** and lives in one
new directory, `ios/Sources/DebugSeed/`, every file wrapped in `#if DEBUG`, reached by a
three-line `#if DEBUG` block in `KanameApp.swift`'s `init()`. It reads a scenario name from
`ProcessInfo.processInfo.environment`, deletes `kaname.db` and its sidecars, then writes each
declared statement through `Store.importStatement` — the same call `ImportService` makes, with
the same Keychain key and the same encryption. **The Rust engine is not touched**: research R2
established that `build-xcframework.sh:41-44` runs `cargo build --release` once and links that
single artifact into *both* Xcode configurations, so `#[cfg(debug_assertions)]` is off in the
DEBUG app and a cargo feature would compile straight into Release. That single fact removes the
FFI change, the `make core-xcframework` rebuild, and the engine-first PR ordering that governed
018. Schema stays at **v7**; no migration. The boundary is then *proved* rather than asserted, in
two places: a tenth grep in `scripts/import-path-audit.sh` (**+0.005 s**), and a new
`make release-audit` that **builds its own Release binary and scans it** — measured at
**2,651,224 bytes**, **12,249** symbols, **16.21 s** to build and **0.03 s** to scan.

**The trap that shapes the whole absence proof.** `-showBuildSettings` reports `STRIP_STYLE =
all` and `STRIP_SWIFT_SYMBOLS = YES`, but `DEPLOYMENT_POSTPROCESSING = NO` — stripping runs on
`install`/`archive`, not `build`. Simulating it (`strip -rSTx`) takes the binary from **12,249
symbols to 157**, and a known shipping type vanishes from `strings` entirely. **A symbol scan
over a stripped artifact is vacuously green.** So the audit builds its own artifact, and
**self-checks** that a known Release-present symbol and a known Release-present literal *are*
found before it is willing to conclude an absence. That self-check is the difference between a
proof and a formality, and it is the deliberate break most likely to be skipped.

## Technical Context

**Language/Version**: Swift 6 / SwiftUI, iOS 26.0 deployment target, Xcode 26.6 / iOS SDK 26.5 ·
Rust 1.90 (`rust-toolchain.toml`) — **untouched by this slice**
**Primary Dependencies**: **none added**, in either language. Existing only — XCTest/XCUITest,
Swift Testing, Tuist, SwiftLint, swift-format, and the shipped `kaname_core` xcframework
**Storage**: the existing encrypted SQLCipher store, schema **v7 — unchanged, no migration**.
The seed writes only into columns v1–v7 already define, because it writes through
`import_statement`. A migration here would have been the tell that seeding had stopped going
through the front door (see Post-Phase-1 re-evaluation and research R18)
**Testing**: XCUITest in `ios/UITests` (the seeded suite: accessibility audits at four
size × appearance combinations, filter states, paging, determinism, one geometry assertion) ·
Swift Testing in `ios/Tests` (a host-rendered empty-state case, subject to Judgement calls §1) ·
two shell gates (`make import-audit`'s tenth scan, `make release-audit`) · the manual,
release-blocking gate, **shrunk** by what this slice automates (FR-042–FR-045)
**Target Platform**: iPhone simulator for the gates; iOS 26+ device for what remains manual
**Project Type**: mobile app over a shared Rust engine — the repo's established two-layer split.
This slice adds no layer, no package, and **no Tuist target**
**Performance Goals**: a seeded launch reaches the populated list in < 5 s (SC-009); the
source-level absence scan adds no measurable time to `make import-audit` (SC-014, measured
+0.005 s); the artifact-level audit is a separate invocation at 16.2 s (FR-028)
**Constraints**: Liquid Glass unconditional — no `#available(iOS 26, *)`, no
`.ultraThinMaterial`; SwiftLint `--strict`, 400-line files, 120 columns, and
`ios/Sources/Import/ImportService.swift` is at **398** lines, so **nothing in this slice may add
a line to it**; money is `Decimal` end-to-end, declared as a base-10 **string** so no `Double`
can appear even in a literal; zero network I/O; no real statement, fragment, merchant or account
identifier in any fixture; `make perf-corpus` and the app-group `cp` technique are UNCHANGED
(FR-046–FR-049); ⚠️ `core/tests/history_perf.rs::s5` is wall-clock — never run the core and iOS
gates concurrently
**Scale/Scope**: 6 user stories, 49 functional requirements, 17 success criteria; **0** Rust
files, **0** FFI changes, **0** migrations; 1 new Swift directory, 1 new script, 1 new `make`
target, 1 tenth scan, 3 lines in `KanameApp.swift`, 1 line in `Project.swift`, 2 CI steps

*(No `NEEDS CLARIFICATION` remains — see [`research.md`](./research.md) R1–R20.)*

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v2.0.0.

| Principle | Verdict | Evidence in this design |
|---|---|---|
| **I. Data Privacy & Sovereignty (NON-NEGOTIABLE)** | ✅ PASS | This slice writes **fabricated** data to the device and reads it back. No network call, no analytics, no telemetry, no new crate, no new framework — `make core-privacy-audit`'s denylist is unaffected and `import-path-audit.sh`'s networking scan already covers **all** of `ios/Sources`, which is where `DebugSeed/` lives, so FR-033/SC-011 are enforced the moment the directory exists (research R7). The seeded store is the app's own SQLCipher store under the app's own Keychain key — no test key, no plaintext store, no alternate location (FR-017, SC-013). Nothing on the path logs a transaction field (FR-034). Crucially, the privacy risk this slice *creates* is the opposite of the usual one: a path that fabricates financial history must never reach a person's build, which is why FR-024–FR-032 get two proofs rather than a promise. |
| **II. Local-First Shared Engine** | ✅ PASS | Nothing moves out of the engine, because nothing is added to it. The seed calls the **existing** `Store.importStatement` — the same entry `ImportService` uses — so the behaviour the tests come to trust is the shipped behaviour (FR-014, US3). Determinism is inherited rather than invented: `list_accounts_in` is `ORDER BY rowid`, dedup orders by `a.rowid, t.rowid`, and `ImportRequest.now` is caller-supplied so no clock is read (FR-023). Money stays `Decimal` at every hop. A second platform would seed the same way, through the same call. |
| **III. Open-Core & Permissive Licensing** | ✅ PASS | Zero new dependencies, so no licence surface changes. No secrets, no keys, no endpoints. Fixtures are synthetic by construction and by scan. |
| **IV. Native Experience & Accessibility** | ✅ PASS | This is the slice whose *purpose* is accessibility coverage: it takes `performAccessibilityAudit` from an empty screen to a populated one across default/`AccessibilityXXXL` × Light/Dark plus Increase Contrast (SC-002), and it is what lets 018's two parked defects be watched failing (FR-038). No UI is added and no Liquid Glass decision is made, so there is nothing here to gate on `#available` — and nothing that could tempt a fallback. The route under test is the one a person taps (FR-003); no test-only screen, deep link or alternate root exists. |
| **V. Test-First & Parity** | ✅ PASS | RED → GREEN throughout, in two directions. The seeded assertions are named before implementation ([`contracts/seeded-launch.md`](./contracts/seeded-launch.md) §4 — L1–L6, S1–S7, D1–D4, E1–E4, A1–A8). More unusually, the **gates themselves** are written test-first: five deliberate breaks must each be watched turning the absence audit red before it is trusted ([`contracts/release-absence-audit.md`](./contracts/release-absence-audit.md), FR-030, SC-005), and the accessibility criteria are proved by reinstating 018/02 and 018/03 and watching the new tests fail (FR-038, SC-006). Every fixture is synthetic with a stated corpus contract (`data-model.md` §4–§5). |
| **VI. Free/Paid Boundary** | ✅ PASS | Nothing shipped, nothing gated, nothing metered. The entire slice is compiled out of the build a person installs — which is exactly what SC-015 asserts and what `make release-audit` proves. |
| **Security & Privacy Constraints** | ⚠️ **PASS with a stated concession** | No third-party SDK, no new crate, no new framework, no secret. But a path that writes fabricated financial rows now exists in the app's own source tree, and the *only* thing keeping it out of a shipped build is a compile-time boundary. That is a knowing concession, and it is paid for rather than waved through: two independent scans, one of which builds and inspects the actual Release binary and refuses to conclude anything if it cannot first find a symbol it knows is there. See Post-Phase-1 re-evaluation. |
| **Development Workflow & Quality Gates** | ✅ PASS | Spec Kit flow; the full iOS Local Verification Gate applies to every PR. Because **no** `#[uniffi::export]` or `core/src/ffi.rs` change occurs (research R2), `make core-xcframework` is **not** required — but `make ios-gen` still is, because `Project.swift` gains a source entry. `make lint && make ios-test` plus `make import-audit` and the new `make release-audit`; ⚠️ core and iOS gates are run **sequentially**, never concurrently, because `history_perf.rs::s5` is wall-clock. |

**Result: PASS — no violation requiring justification. Complexity Tracking is empty.**

### Post-Phase-1 re-evaluation

Re-checked after `research.md`, `data-model.md`, `contracts/` and `quickstart.md`:

- ✅ Still **zero** new dependencies, and now also **zero** Rust changes, **zero** FFI changes
  and **zero** migrations. Schema stays v7, recorded as a deliberate non-change per 017's
  precedent (`data-model.md` §1).
- ⚠️ **The concession, stated plainly.** The constitution's Security & Privacy section is
  written against *shipping* risk, and a DEBUG-only fabrication path is a shipping risk if the
  boundary ever fails. The design's answer is that the boundary is **measured, not trusted**:
  research R4 established that a naive artifact scan would have passed for the wrong reason
  (12,249 → 157 symbols after `strip`), so the audit builds its own artifact with the `build`
  action, scans both `nm` **and** `strings`, and fails as *inconclusive* if its self-check
  cannot find a symbol and a literal it knows are present. A gate that can only say "yes" is
  not a gate. This is the plan's reading of what "proved, not asserted" (FR-025) requires; it
  is called out here so the product owner can raise the bar rather than discover the level.
- ✅ The seeding boundary is placed where it can be *checked cheaply*: `ios/Sources/DebugSeed/`
  sits inside the scan root that `import-path-audit.sh`'s networking **and** bank-literal scans
  already cover, so "no networking on the seed path" and "no scenario may name a real issuer"
  are enforced mechanically the moment the directory exists (research R7). Placement was chosen
  for enforceability, not tidiness.
- ✅ The write path is the shipped one. If seeding had needed a narrower entry point, an FFI
  export, or a schema change, that would have been evidence that the tests were about to trust
  a pipeline nobody uses. It needed none of the three.
- ⚠️ **Three findings in shipped or specified behaviour surfaced.** None is introduced by this
  design; none is worked around in it. `EmptyKind.nothingImported` is unreachable by any
  automated run of the shipping route (R9); `is_deleted` has no write path at all (R8); and
  `is_transfer` can only be set by a call the app is *banned* from making (R8). All three are in
  "Judgement calls" below.
- ⚠️ **Two gaps in the existing gates** were found while planning where this slice's checks
  belong (R19): CI runs `core-privacy-audit` but **never** `make import-audit` — nine scans have
  been local-only — and CI's `swift-format lint` covers `Sources Tests` while `make lint` covers
  `Sources Tests UITests`. FR-029 forces the first to be fixed here; the second should be fixed
  in the same PR, since this slice's centre of gravity is `UITests/`.
- ✅ `ios/Sources/Import/ImportService.swift` (398/400 lines) is **not touched**, in any PR.

**Result: PASS. Complexity Tracking remains empty.**

## Project Structure

### Documentation (this feature)

```text
specs/019-debug-test-seeding/
├── plan.md                       # This file
├── spec.md                       # FR-001–FR-049, SC-001–SC-017, US1–US6
├── research.md                   # Phase 0 — R1–R20, with measured evidence E1–E5
├── data-model.md                 # Phase 1 — the fixture model; schema v7 non-change; findings
├── contracts/
│   ├── seeded-launch.md          # Phase 1 — the launch contract + ~30 named assertions
│   └── release-absence-audit.md  # Phase 1 — both scans, the self-check, the 5 breaks
├── quickstart.md                 # Phase 1 — build order, gates, traps, the manual-gate rewrite
├── checklists/
│   └── requirements.md           # Pre-existing spec-quality checklist
└── tasks.md                      # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
core/                             # UNCHANGED — no file, no export, no migration (research R2)
                                  #   schema stays at v7; history_perf.rs::s5 undisturbed

ios/
├── Project.swift                 # CHANGED — ONE line: SeedScenarios.swift joins
│                                 #   KanameUITests' sources, so app and test share the literal
├── Sources/
│   ├── KanameApp.swift           # CHANGED — 3 lines, one #if DEBUG block in init()
│   │                             #   (the file is 13 lines today)
│   ├── DebugSeed/                # NEW — every file entirely wrapped in #if DEBUG
│   │   ├── DebugSeed.swift               # applyIfRequested(): read env → reset → write
│   │   ├── SeedScenarios.swift           # the declarations; ALSO compiled into KanameUITests
│   │   └── SeedScenarioBuilder.swift     # SeedScenario → [ImportRequest]; expected-row maths
│   └── Import/
│       └── ImportService.swift   # UNCHANGED — 398/400 lines; nothing here may touch it
├── Tests/
│   └── EmptyStateRenderingTests.swift    # NEW — host-renders the list's empty states
│                                         #   (subject to Judgement calls §1)
└── UITests/
    ├── SeededTransactionListUITests.swift    # NEW — S*, D*, E*, A1–A8, the geometry assertion
    ├── SeedContractUITests.swift             # NEW — L1–L6: absent/unknown/reset/timing
    └── AccessibilityAuditTests.swift         # CHANGED — the populated list joins the sweep

scripts/
├── import-path-audit.sh          # CHANGED — a TENTH scan: the DEBUG-boundary source check
└── release-absence-audit.sh      # NEW — builds a Release binary, self-checks, scans nm+strings

Makefile                          # CHANGED — new `release-audit` target
.github/workflows/ci.yml          # CHANGED — runs `make import-audit` (it never has) and
                                  #   `make release-audit`; swift-format widened to UITests
docs/ / AGENTS.md                 # CHANGED — how to seed; the shrunk manual gate (FR-042–045)
```

**Structure Decision**: the repo's two-layer split is unchanged, and this slice deliberately
lands **entirely on the platform side**. That is not a preference — research R2 established it
as a constraint: `core/scripts/build-xcframework.sh` runs `cargo build --release` **once** and
links the same artifact into both Xcode configurations, so there is no Rust construct that is
present in the DEBUG app and absent from Release. Any engine-side seeding would either be dead
in DEBUG (`#[cfg(debug_assertions)]`) or alive in Release (a cargo feature). The boundary can
only exist where the compiler distinguishes the two builds, and that is Swift.

Within `ios/`, the new code goes in **one new directory** rather than into existing files, for
three reasons: `ImportService.swift` has two lines of headroom and `make lint` is `--strict`; a
directory boundary is what makes the tenth scan a two-line `find` instead of a heuristic; and
`ios/Sources/` is already the scan root for networking and bank literals, so placing the seed
inside it recruits two existing gates instead of needing two new ones. No new Tuist **target**
is created — Tuist's `dependencies:` cannot vary by configuration, so a "debug-only target"
would have to be excluded by build settings, which fails open for files added later.

## Delivery order (mandatory, not advisory)

018's ordering was forced by the FFI: the engine had to land first because the xcframework is
rebuilt and Tuist resolves its path at generation time. **That constraint does not apply here** —
nothing crosses the bridge, so `make core-xcframework` is never run and no PR is blocked on
another's artifact. The ordering below is chosen for a different reason: **the proof that the
seeding path cannot ship must exist before the seeding path does.**

| PR | Scope | Why this order |
|---|---|---|
| **A — The absence proof, first** 🔒 | The tenth scan in `import-path-audit.sh`; `scripts/release-absence-audit.sh` with its self-check; `make release-audit`; the CI wiring (`make import-audit` — which CI has **never** run — plus `make release-audit`, and the `swift-format` widening); the five deliberate breaks watched red, against a **stub** `ios/Sources/DebugSeed/` file that does nothing | Merges **first**, on purpose. This is the price paid *before* the capability is bought: if the gate cannot be made to work, the slice stops here and nothing that fabricates financial data has been written. Reviewing the proof on its own — against a stub whose only job is to be found — is also the only way to see the self-check fail honestly (break 5). |
| **B — The seeding path** 🎯 | `DebugSeed/` for real (`applyIfRequested`, the reset, the builder), the `#if DEBUG` block in `KanameApp.swift`, the `Project.swift` line, the two scenarios, `SeedContractUITests` (L1–L6) and the first seeded audit (S1–S3, A1) | The first PR where a test sees a transaction. Closes US1 and US4's core. Depends on A only in the sense that A's gate is already watching it — which is the intended feeling. |
| **C — What the coverage was for** | The remaining audits (A2–A6), the filter's four states (E1–E3), paging over 160 rows, the currency and ordering assertions, and — the point of the slice — **A5 and A7 watched failing against reinstated 018/02 and 018/03**, then reverted | US2, US3, US5. Cannot precede B: the defects only reproduce on a populated screen. ⚠️ A5 and A7 use different instruments because the iOS auditor has **no occlusion check** (R10); if A5 does not go red against the reinstated chip, the answer is a second geometry assertion, not a weaker criterion. |
| **D — Honesty and hand-back** | The `nothingImported` host-render (pending Judgement calls §1), the rewrite of 018's manual gate record (FR-042–FR-045: what is now automated, what remains, and why), `AGENTS.md` / `docs/` seeding instructions, `.scratch/HANDOFF.md` | US6. Lands last because the manual gate cannot be honestly shrunk until C has established exactly which of G1–G14 an automated run now covers. |

Within each PR the order is RED first: for A, the deliberate break before the fix; for B and C,
the named assertion before the code.

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified.

**Empty — the Constitution Check passed with no violations, before and after Phase 1.** The one
⚠️ (a fabrication path in the app's own sources) is a concession the spec asked for explicitly
and priced explicitly in FR-024–FR-032; it is not a deviation from the constitution, and the
design does not seek relief from any rule.

## Judgement calls for the product owner

Four decisions were made without asking. The first three are findings in **shipped or
specified** behaviour that this slice discovered rather than caused; the fourth is a gap in the
gates themselves.

### 1. 🚨 `EmptyKind.nothingImported` cannot be reached by seeding — or by anything else

FR-039 asks that every empty state get automated coverage. Five of the six can be produced by a
scenario. The sixth cannot, and the reason is structural, not incidental:

- `EmptyKind.decide` returns `.nothingImported` if and only if `summaries.isEmpty`
  (`TransactionListModels.swift:180`).
- `RootView` renders the **only** route to the list — the toolbar link — only
  `if !model.accounts.isEmpty`.
- `ImportViewModel.accounts` and the list's `summaries` come from the **same**
  `store.accountSummaries()` call (`ImportService.swift:126`).

So the state is defined by a condition the front door guarantees you can never be in. There is
no transient window either: the view model's initial state is `.loading`, not an empty result.
No seed can create the contradiction, because the contradiction is prevented by construction.

**Three options.** (a) **Host-render the real view** in `KanameTests` via `UIHostingController`
with the existing `TransactionListDoubles`, giving the branch its first automated execution
against a rendered screen — ⚠️ but *not* a `performAccessibilityAudit`, which is an
`XCUIApplication`-only API, so the state would be executed and asserted but not audited.
(b) **Delete the branch** and let the type stop claiming a state it cannot have. (c) **Change
the front door** so the list is reachable from an empty install, which makes the state real —
and directly contradicts the shipped UI test
`testAFreshInstallOffersNoRouteToAnEmptyTransactionList`.

**Recommended: (a).** It is the only option that neither removes a defence nor changes shipped
product behaviour inside a testing slice. But it means FR-039 is met *unevenly* — five states
audited, one merely executed — and that unevenness should be a decision, not a footnote.

### 2. 🚨 Two clauses of FR-008 describe stores that cannot exist

FR-008 asks a scenario to be able to include deleted rows and transfer-flagged rows. Neither is
expressible, for different reasons, and both were verified against the source:

- **Deleted rows.** `is_deleted` is `DEFAULT 0` and is **never `UPDATE`d anywhere in
  `store.rs`**. The only writes of `1` are raw SQL inside engine tests (`store.rs:2900`). There
  is no Swift-facing API, and R2 forecloses adding one — an `#[uniffi::export]` added for
  testing would ship in Release, which is precisely what this slice exists to prevent.
- **Transfer-flagged rows.** `is_transfer` is set only by `detect_transfers`, which
  `import-path-audit.sh` **bans the app from calling** (018's R18 finding, still open). Every
  row of every real install therefore has `is_transfer = 0`. A seeded transfer would produce a
  screen **no person can currently have**, which violates US3's whole premise.

The design **records both rather than working around either**. The good news is that neither
clause is load-bearing: `EmptyKind.accountNothingToShow` — the state deletion was wanted for —
is reachable through **superseded** rows alone, and both routes to supersession are the engine's
own (⚠️ with the caveat that after 018's source-kind guard, a cross-source pair must be one bank
ledger and one card; two cards never de-duplicate, silently).

**Recommended: accept the two gaps and record them in the manual gate.** They close when the
categorize slice wires transfer detection, and when — if ever — deletion becomes a thing a
person can do. Alternatively the spec may prefer FR-008's two clauses struck.

### 3. ⚠️ SC-008's arithmetic does not add up, and three gate items are unaccounted for

SC-008 says the manual gate shrinks to five named items — Reduce Transparency, VoiceOver
meaningfulness, and three device timings. 018's gate record has **fourteen** (G1–G14). Working
through them, **G10, G13 and G14 have no home**: G13 and G14 require a live import **through the
document picker** while the list is open, and seeding does exactly the opposite — it bypasses
the picker, at launch, before any view exists. A seeded run cannot put a picker in front of a
running test.

**Recommended: SC-008's list is amended to eight**, adding G10, G13 and G14 as items that remain
manual because they concern the *transition* into a populated state rather than the state
itself. But that changes a success criterion, so it needs the product owner's word before
`/speckit.tasks` turns it into tasks.

### 4. ⚠️ CI has never run `make import-audit`

Found while deciding where this slice's scans belong (R19). `.github/workflows/ci.yml` runs
`core-privacy-audit` but **not** `make import-audit` — so nine existing scans, including the
networking scan that is the platform half of Principle I's guarantee, have only ever run on
somebody's laptop. Separately, CI lints `Sources Tests` with swift-format while `make lint`
lints `Sources Tests UITests`, so UITest formatting is checked locally and not in CI.

FR-029 forces the first gap closed for the *new* scan. **Recommended: close it for all ten in
PR A, and widen the swift-format path in the same commit**, since this slice writes most of its
code in `UITests/`. It is a two-line change to a workflow, and leaving nine scans local-only
while adding a tenth would be an odd thing to have decided on purpose.
