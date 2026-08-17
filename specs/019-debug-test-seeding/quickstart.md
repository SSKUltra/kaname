# Quickstart: DEBUG-Only Test Seeding

**Feature**: `019-debug-test-seeding` | **Phase**: 1
**Read first**: [`plan.md`](./plan.md) · [`research.md`](./research.md) ·
[`contracts/seeded-launch.md`](./contracts/seeded-launch.md) ·
[`contracts/release-absence-audit.md`](./contracts/release-absence-audit.md)

## The one-sentence problem

Every UI test in this repository launches a fresh install, so every accessibility audit has only
ever run against an empty screen — and both defects 018 found on a populated list were found by
a person, by hand, and parked.

## The one-paragraph fix

A DEBUG build reads `KANAME_SEED_SCENARIO` from its environment during `App.init()`. If it is
set, the seeding path deletes `kaname.db` and its sidecars, then writes a named synthetic
history through `Store.importStatement` — the same call `ImportService` makes, into the same
encrypted store, under the same Keychain key — and returns before the first `View` body runs.
The ordinary app then opens an ordinary store and knows nothing about any of it. All of that
code lives in `ios/Sources/DebugSeed/`, entirely inside `#if DEBUG`, and two gates prove it is
absent from Release: a grep over the sources, and a scan of a Release binary the gate builds
itself. **The Rust engine is not touched, and the schema stays at v7.**

## Build order

⚠️ **`make core-xcframework` is NOT required for this slice** — and that is unusual enough to
say out loud. Nothing here changes `core/src/ffi.rs` or any `#[uniffi::export]`, so the rule
that normally bites ("cannot find X in scope" is not a Swift problem) does not apply. If a task
ever *does* make you edit `ffi.rs`, stop: research R2 explains why an engine-side DEBUG boundary
cannot work, and the answer is to move the code to Swift, not to rebuild.

```bash
# 1. Project.swift gains one line (SeedScenarios.swift in KanameUITests' sources),
#    so the project must be regenerated. NEVER run a bare `tuist generate`.
make ios-gen

# 2. Build and run the seeded suite
make ios-test
```

## Verification gate (run before every PR — Constitution § iOS Local Verification Gate)

```bash
# Engine half — unchanged by this slice, but still required
make core-lint && make core-test

# ⚠️ WAIT for it to finish. core/tests/history_perf.rs::s5 is a wall-clock bound and is
# flaky under CPU contention. Do NOT run the two halves concurrently.

# Platform half
make lint && make ios-test

# The absence proofs
make import-audit      # ten scans now; +0.005 s over the previous nine
make release-audit     # NEW — ~16.2 s, because it builds its own Release binary
```

**Cost, measured.** `make import-audit` stays a sub-second grep. `make release-audit` is
**16.21 s** with a cold `-derivedDataPath` (16.2 s of `xcodebuild`, 0.03 s of `nm`/`strings`).
It is a separate target precisely so the cheap gate stays cheap (FR-028, SC-014).

## Smoke test (the shortest path to seeing it work)

```bash
make ios-gen
xcodebuild -workspace ios/Kaname.xcworkspace -scheme Kaname \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:KanameUITests/SeededTransactionListUITests/testASeededHistoryRendersEveryLiveRow \
  test
```

Or by hand, from a test you are writing:

```swift
let app = XCUIApplication()
app.launchEnvironment["KANAME_SEED_SCENARIO"] = "small"
app.launchArguments += ["-AppleLocale", "en_IN", "-AppleLanguages", "(en)"]
app.launch()
XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
app.buttons["All transactions"].tap()      // the same control a person taps
```

Six rows, one account, in a prior calendar year. If the app does not reach the foreground, the
seed failed — that is the entire failure contract (`contracts/seeded-launch.md` §3).

## How to watch the absence audit fail (do this before trusting it)

Five deliberate breaks, each reverted in the same commit
(`contracts/release-absence-audit.md`). Break 5 is the one that matters most and the one most
likely to be skipped:

```bash
# Break 5 — point the audit at a stripped copy and confirm it says INCONCLUSIVE, not OK.
cp "$BIN" /tmp/stripped && strip -rSTx /tmp/stripped
nm /tmp/stripped | wc -l             # measured: 156, versus 4,511 unstripped
```

A scan over that binary finds nothing — **because there is nothing to find**. If the audit
reports `OK` there, the audit is decorative.

### What the breaks actually did (019 PR A, T011–T016, measured)

Run against the PR A stub. **Six** breaks, not five: the sixth exists because the fifth's
sibling trap was discovered while running the others.

| # | Break | Scan A | Scan B | What it taught |
|---|---|---|---|---|
| 1 | `#if DEBUG` removed from `DebugSeed.swift` | ⛔ FAIL (FR-024) | ✅ **OK** | An unguarded but **unreferenced, internal** type is dead-code eliminated: no symbol, no literal. Scan A is what catches this, and B's silence is honest — recorded, not fixed by weakening the denylist |
| 2 | Seeding function copied, unguarded, into `Sources/Transactions/` | ⛔ FAIL (reverse direction) | ✅ OK | Same reason as 1 |
| 3 | Guarded stub **referenced** from `RootView.swift` | ⛔ FAIL | ⛔ FAIL, via **`nm`** — `_$s6Kaname9DebugSeedOMa`, `…OMF`, `…OMf` | The artifact half is not decorative. **Variant 3a** (guard kept, reference added) fails the Release *build* — `cannot find 'DebugSeed' in scope` — so the compiler is a third gate: an unguarded shipping reference to DEBUG-only code cannot ship quietly |
| 4 | `KANAME_SEED_SCENARIO` as a literal on an **unused** `static let` | ⛔ FAIL | ✅ OK | The optimiser drops it. **Variant 4b** — the same literal spliced into `TransactionListStrings.title`, which the screen renders — fails **through `strings` while `nm` stays silent**. That pair is the whole argument for scanning both |
| 5 | Audit pointed at a `strip -rSTx`ed copy | — | ⛔ **FAIL (inconclusive)** | The self-check works, and "inconclusive" is a different sentence from "clean" |
| 6 | A new `DebugSeed/*.swift` added **without** `make ios-gen` | ✅ OK (it is guarded) | ⛔ **FAIL (inconclusive)** | See below — this one was found the hard way |

### ⚠️ Two traps found while building the proof, both now handled by the script

**1. Tuist resolves `sources: ["Sources/**"]` at generation time.** A file added since the last
`make ios-gen` is in no target, is compiled by nothing, and is therefore absent from the Release
binary **for the wrong reason**. Three `release-audit: OK` runs and two "Scan B stayed green"
break verdicts were recorded before this was noticed, and every one of them looked like a pass.
The script now asserts, before concluding anything, that each `DebugSeed/*.swift` appears in
`ios/Kaname.xcodeproj/project.pbxproj`, and fails as **inconclusive** if not. It is the same
class of defect as the strip trap, in a place nobody was watching. **Run `make ios-gen` before
`make release-audit` after adding any file.**

**2. `nm -a` includes the debug map, and the debug map names source files.** A *correctly
guarded* `DebugSeed.swift` produces three `nm -a` hits (`SO …/DebugSeed/`, `OSO …/DebugSeed.o`,
`SO DebugSeed.swift`) in a binary containing none of its code — a false positive on a clean
tree, which is how a gate gets deleted. The scan uses plain **`nm`** (4,511 real symbols rather
than 12,249 stab entries) and still catches break 3. The question `-a` would have answered —
"was the file even compiled?" — is answered directly and truthfully by trap 1's check.

**3. `nm "$BIN" | grep -q X` fails under `pipefail` even when it matches.** `grep -q` exits on
the first hit, `nm` dies of SIGPIPE (141), and the pipeline reports failure — so the audit's
first honest run declared itself inconclusive against a binary carrying both anchors. It is the
cousin of the `|| true` rule the nine existing scans follow (there, a `grep` that finds
*nothing* exits 1). **Match in a variable, never in a pipe.**


## How FR-038's "watched failing" is actually carried out

Two defects, two instruments, because the iOS accessibility auditor has **no occlusion check**
(research R10 — the seven types are Contrast, ElementDetection, HitRegion,
SufficientElementDescription, DynamicType, TextClipped, Trait).

| Reinstate | One-line break | Test that must go RED |
|---|---|---|
| `018/02` — the filter chip truncates at `AccessibilityXXXL` | `FilterChromeLayout.axis` forced to `.horizontal` | **A5** — `performAccessibilityAudit`, `.textClipped` |
| `018/03` — the glass bar slices a row's amount | `FilterChromeLayout.maximumScopeLines` restored to `6` | **A7** — geometry: `lastRow.frame.maxY <= filterBar.frame.minY` |

Procedure: make the break → run the seeded suite → **record the failure message verbatim in the
task** → revert → re-run and confirm green. ⚠️ A5's `.textClipped` firing is **inferred from the
audit's type list, not yet observed** — it could not be run before the capability being planned
exists. If it does not fire, the remedy is a second geometry assertion of A7's shape, **not** a
weakened criterion.

## Gotchas discovered during planning

| Trap | What actually happens | Do this |
|---|---|---|
| `TEST_RUNNER_` prefix | That rule is for **unit** tests hosted in the app (`make reference-check`, `make perf-corpus`). It does **not** apply to `launchEnvironment` on a UI test's `XCUIApplication` | Set the bare key `KANAME_SEED_SCENARIO`. A prefixed one is never delivered and the suite runs silently unseeded |
| `grep -c` under `set -euo pipefail` | `grep` exits **1** when it finds nothing — which is the **passing** case — and kills the script | End every scan `|| true`, exactly as the nine existing ones do |
| Release symbol scanning | `STRIP_STYLE = all` but `DEPLOYMENT_POSTPROCESSING = NO`: stripping runs on `install`/`archive`, not `build`. 12,249 symbols → 157 after `strip` | The audit builds its own artifact with the `build` action **and** self-checks for a known-present symbol *and* literal before concluding |
| Scanning only `nm` | `strip` removed the symbol but the **string literal survived** | Scan `nm` **and** `strings` |
| Locale grouping | `.currency(code:)` groups by locale: `₹1,23,456.00` (en_IN) vs `₹123,456.00` (en_US). An assertion above ₹1,00,000 is an assertion about the simulator's region | Pin `-AppleLocale en_IN` **and** keep every declared amount below ₹1,00,000 |
| `mint_id` | `lower(hex(randomblob(16)))` — every id is random on every run | No assertion may name an id. Key on (date, description, amount, currency, account) |
| Two cards never de-duplicate | 018's source-kind guard (`store.rs:1448`) only ever compares a bank ledger against a card — a synthetic pair of cards produces no supersession, **silently** | A cross-source supersession needs `isCreditCard: false` on one side, `true` on the other |
| A corpus that eats itself | 018 R20: repeated rows collapse under dedup and the corpus comes out short | Only rows a scenario *intends* to collide may collide. Assert `expectedLiveRowCount` |
| `ImportService.swift` | **398 of 400** SwiftLint lines, and `make lint` is `--strict`. One added line fails the gate | Nothing in this slice touches it. If a task wants to, move code out instead |
| A bare `tuist generate` | Resolves the xcframework path at generation time | Always `make ios-gen` |
| `make ios-test`'s preamble | It uninstalls the app and pins `content_size large` first, both for recorded false-failure reasons | Leave it alone. If you set a text size by hand, **put it back** |
| Concurrent gates | `core/tests/history_perf.rs::s5` is a wall-clock bound | Run core and iOS gates **sequentially** |
| `auditIgnoringContrastOverUnrenderedArea` | It is a **narrow** suppression, proved in four steps for the front door's unrendered text | Do not copy it to the list by reflex. A list scrolls; if a suppression is needed, prove it again and record the proof |

## The manual gate: how FR-042–FR-045's rewrite is carried out

018's `quickstart.md` § *The manual, release-blocking gate* holds G1–G14 and a *Record here*
table whose last run (2026-08-15) shows **6 pass, 2 fail, 3 unmeasured**. FR-042 requires that
record be **rewritten**, not appended to, once this slice lands. The rewrite happens in **PR D**,
after PR C has established which items an automated run actually covers.

Method:

1. For each of G1–G14, record one of three verdicts with evidence: **automated** (name the
   assertion — A1–A8, E1–E3, S2–S5), **still manual** (say what an automated run cannot see),
   or **retired** (say why the question stopped mattering).
2. Carry forward the two open defect tickets and the timing ticket (`018/issues/06`) verbatim.
   This slice does not fix them; it makes two of them catchable.
3. ⚠️ **G10, G13 and G14 have no home** under SC-008's current wording (research R17, plan
   § *Judgement calls* §3). G13/G14 need a live import **through the picker** while the list is
   open — seeding does the opposite, at launch, before any view exists. State them as remaining
   manual, and flag the SC-008 amendment.
4. State the residue in one sentence a person can act on, in the shape 018 used: what is now
   caught by a machine, what still needs a phone, and what nobody has ever measured.

## Definition of done

- [ ] A seeded launch reaches a populated list from the front door's own control (US1, FR-003)
- [ ] The rows on screen equal the declaration, in the declared order, with nothing extra (S2–S5)
- [ ] Ten consecutive seeds of `small` produce an identical screen (SC-010, D1)
- [ ] `performAccessibilityAudit` passes on the populated list at default and `AccessibilityXXXL`,
      in Light and Dark, and under Increase Contrast (SC-002, A1–A6)
- [ ] 018/02 and 018/03 reinstated, **watched red** by A5 and A7 respectively, then reverted
      (FR-038, SC-006)
- [ ] Five of six `EmptyKind` cases automated; `nothingImported` decided per Judgement calls §1
- [ ] The tenth source scan and `make release-audit` both exist, are wired into CI, and have each
      been watched failing against all five deliberate breaks (FR-030, SC-005)
- [ ] `make import-audit` now runs in CI — for all ten scans, not just the new one (R19)
- [ ] A non-seeded launch is byte-for-byte the behaviour it is today (FR-005, FR-022, L1, L6)
- [ ] Schema still v7; `core/` unchanged; `ImportService.swift` still 398 lines
- [ ] 018's manual gate record rewritten, with the three unaccounted items named (FR-042–FR-045)
