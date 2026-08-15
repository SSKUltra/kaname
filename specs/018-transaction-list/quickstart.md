# Quickstart: The Transaction List

**Feature**: `018-transaction-list` | **Plan**: [`plan.md`](./plan.md)

Read order for a fresh session: [`spec.md`](./spec.md) → [`plan.md`](./plan.md) →
[`research.md`](./research.md) (R1–R20, the decisions with measured evidence) →
[`contracts/engine-history.md`](./contracts/engine-history.md) →
[`contracts/platform-seams.md`](./contracts/platform-seams.md) →
[`data-model.md`](./data-model.md) → `tasks.md` (once `/speckit.tasks` has run) → this file.

---

## The one-sentence problem

Import writes a person's financial history to their device, and the app shows them a number.

## The one-paragraph fix

Give the engine two reads — one keyset-paged screenful of every account's live transactions in
one deterministic order, and one live count per account — then give the app a scrollable,
date-grouped list that renders them. The live-row rule and the ordering are expressed **once**,
in SQL, behind one partial index whose `WHERE` clause is byte-identical to the Rust constant
that names it, so a read that forgets the rule loses its index and a test goes red. Everything
the person sees is a projection of those two reads: the front door's count, the filtered list,
the unfiltered list, the empty states.

---

## Build order

Follow the PR split in `plan.md` § *Delivery order*. **A before B is not a preference** — it is
the FFI boundary, and Tuist resolves the xcframework path at *generation* time.

```text
A  Engine   🔒  → core: schema v7 index, LIVE, history_page, account_summaries, ffi exports
B  The list 🎯  → ios: Sources/Transactions/*, StoreProvider, nav, front-door count, audit widen
C  Filter       → ios: account filter + the six empty states + pluralisation
D  Detail       → ios: currency, categories, transfers, the full a11y suite
E  Live & fast  → ios+core: import signal, scroll anchor, perf gates, manual gate, docs
```

**The build-order trap, in full.** After any change to `core/src/ffi.rs` or any
`#[uniffi::export]`:

```bash
make core-xcframework   # rebuilds KanameCoreFFI.xcframework AND regenerates the Swift bindings
make ios-gen            # tuist generate — resolves the xcframework path AT THIS MOMENT
```

`make ios-gen` already depends on `core-xcframework`, so **always use `make ios-gen`, never a
bare `tuist generate`**. Running `tuist generate` before the xcframework is rebuilt produces a
project that links yesterday's bindings and fails with a "cannot find `HistoryPage` in scope"
error that looks like a Swift problem and is not.

---

## Verification gate (run before every PR — Constitution § iOS Local Verification Gate)

```bash
make core-lint          # cargo fmt --check + clippy -D warnings
make core-test          # engine tests incl. O/L/P/F/S suites and the v6→v7 migration
make core-privacy-audit # no networking crate reaches the shipped core
make import-audit       # no networking symbol, no legacy material, no #available(iOS 26)
make lint               # swiftlint --strict + swift-format lint --strict
make ios-test           # core-xcframework → tuist generate → simulator build + tests
```

**Non-negotiable outcomes**

| Check | Requirement |
|---|---|
| `EXPLAIN QUERY PLAN` for the page query contains no `SCAN` and no `USE TEMP B-TREE`, on both corpora | SC-006, SC-008a |
| `sum(account_summaries().live_transaction_count)` equals a full unfiltered read's row count | FR-006, FR-008, SC-004 |
| A re-imported statement changes neither the row count nor the sequence | FR-009, SC-003 |
| Ten consecutive full reads are byte-identical | FR-031, SC-009 |
| `TransactionRowLayout.amountYields == false` for all 12 `DynamicTypeSize` cases | FR-021, SC-013 |
| `make import-audit` green **with the widened networking scan** covering `ios/Sources/Transactions` | Constitution I, FR-062 |
| `swiftlint --strict` green — remember `ImportService.swift` is at exactly 400 lines | Constitution |

---

## Smoke test (the shortest path to seeing it work)

1. Land PR A. `make core-test` — the O/L/P/F/S suites go green, **including** the cross-account
   dedup determinism test: PR A fixes the random-id tie-break (research R17), so no test in this
   slice is skipped. If any test reports as skipped, something has been quietly disabled.
2. `make ios-gen && open ios/Kaname.xcworkspace`.
3. Land PR B. Import a statement, return to the front door, **tap an account row** — the list
   appears, filtered to that account, newest first.
4. Back out and use the toolbar item — the same list, unfiltered, every account interleaved by
   date.
5. Import the **same** statement again. The count on the front door and the number of rows in
   the list both stay the same. If one moves and the other does not, the count and the list are
   being computed in two places again, which is the entire thing this design exists to prevent.

---

## The performance measurement, and how to re-run it

The engine half is automated in `core/crates/kaname-core/tests/history_perf.rs`. **S1–S7 run
under `make core-test` by default** — none is behind `--ignored`, a feature flag or a separate
target, so a regression is caught by the gate everyone already runs. Two things about the corpus
are easy to get wrong and both were measured during planning:

**1. Seed by direct SQL, not through `import_statement`.** Seeding 10,000 rows through the real
import path takes **11.77 s**; direct SQL takes **151 ms** — 78× — because `find_duplicates_in`
runs a full cross-account de-duplication on every import. Use the real path for the correctness
corpus, direct SQL for the performance corpus.

**2. Give every row a globally unique amount and description.** A first attempt at the 10,000-row
corpus silently de-duplicated itself down to **1,250 live rows** (research R20). A performance
test that measures an eighth of the corpus it claims to measure is worse than no test.

Reference numbers, for recognising a regression rather than for pass/fail. The first block is
**this build**, measured through `Store::history_page` / `Store::account_summaries` in a **debug**
build on an M-series Mac with a simulator running — re-run it any time with
`cd core && cargo test --test history_perf -- --nocapture`, which prints every line below:

| Measurement | Value | Printed by |
|---|---|---|
| First page, 10,000 rows / 8 accounts, with the v7 index | 1.494 ms | S3 |
| Worst page over a full 10,000-row walk (182 pages) | 5.020 ms | S4 |
| Median page over that walk | 1.504 ms | S4 |
| Per-account first-page cost, 200/2 vs 10,000/8 | 219 µs vs 186 µs — **−15%** spread (SC-008b budget: +20%) | S5 |
| Filtered first page (one account), 10,000 rows / 8 accounts | 309 µs | S6 |
| `account_summaries()` grouped count, 10,000 rows | 1.614 ms | S7 |
| Database file, that corpus | 2,490,368 B | S7 |

These are **whole-seam** numbers — one lock, one account list, one category catalog, the k-way
merge and the `Decimal` conversions included — where the planning table below timed the SQL
alone. That is why they are ~5× larger and why they are the ones to compare against next time.

Retained from the planning machine, because this build has no way to re-measure them (the
Swift-side N+1 no longer exists, and the index is not optional):

| Measurement | Value |
|---|---|
| First-page SQL **without** the index | 3.974 ms (and `USE TEMP B-TREE FOR ORDER BY`) |
| Today's Swift-side `importedAccounts()` count, same corpus | 43.8 ms of Rust time |
| Index size | 282,624 B on a 2,273,280 B file (+12.4%, ≈28 B/live row) |
| Cold `Store::open` | 180–260 µs, either corpus |

The wall-clock assertions are set at **25 ms** — roughly 100× the measured value — so they catch
an algorithmic regression (an accidental full scan, a lost index, an N+1) without going red on a
loaded CI machine.

---

## Gotchas discovered during planning

| Gotcha | Where it bites |
|---|---|
| **`cargo` is not on `PATH`** in a fresh shell. | `export PATH="$HOME/.cargo/bin:$PATH"` before any `cargo` command, or use the `make` targets, which do it for you. |
| **`ImportService.swift` is at exactly 400 lines** — the SwiftLint `--strict` limit. | Adding *one* line to it fails `make lint`. The one change it takes in PR B must be net-neutral or shorter; everything else goes in `ios/Sources/Transactions/`. |
| **`std::sync::Mutex` is not reentrant.** | `history_page` and `account_summaries` take `self.lock()` **once** and use `*_in(&conn, …)` helpers thereafter. Re-entering deadlocks the happy path — 016 learned this the hard way, and it is why the "lazy cursor handle across the FFI" design was rejected outright (research R1). |
| **`list_transactions` is the raw view on purpose.** | It returns deleted and superseded rows and engine tests depend on that. Do not "fix" it. The live rule lands in the new reads. |
| **`rowid` is *import* order, not *printed* order, across two statements of one account on one date.** | The order stays total, deterministic and stable; it is simply not the paper's. Priced in `data-model.md` §2 — do not re-derive it. |
| **A partial index is only used when the query's `WHERE` clause matches its own.** | This is a feature: the `LIVE` constant and `SCHEMA_V7`'s `WHERE` must stay byte-identical, and test L6 asserts it. If someone paraphrases one of them, the plan-shape test goes red before anyone sees wrong rows. |
| **An ASC index does not satisfy this `ORDER BY`.** | `(account_id, date DESC)` is fully satisfied; `(account_id, date)` costs `USE TEMP B-TREE FOR LAST TERM OF ORDER BY`. Measured. |
| **A `UNION ALL` across accounts is worse than merging in Rust.** | Measured: it reintroduces `USE TEMP B-TREE FOR ORDER BY` twice (research R2, evidence E11). |
| **`detectTransfers()` is called from no Swift file.** | `is_transfer` is always `0` in a real install, and this slice deliberately does not wire it (research R18; wiring is the categorize slice's work). A test that expects a transfer marking must set the flag itself — via `store.detectTransfers()` or by seeding it directly. Never let a test name imply the app detects transfers. |
| **Two accounts holding an identical row de-duplicate each other, non-deterministically.** | Fixture rows need globally unique amounts and descriptions or a test will exercise research R17 by accident and fail intermittently. |
| **`import-path-audit.sh` scans only `ios/Sources/Import` for networking symbols.** | Widen line 15 to `ios/Sources` in PR B, or `ios/Sources/Transactions/` ships with no networking audit at all (research R19). |
| **The simulator's app container persists between runs.** | `make ios-test` uninstalls first. If you run a suite from Xcode and see a store from a previous corpus, `xcrun simctl uninstall <device> <bundle-id>`. |
| **A git worktree's `.git` is a file, not a directory**, and Tuist chokes on it. | Plan and build in the main checkout, as 016 and 017 recorded. |
| **Environment variables reach the test bundle only with the `TEST_RUNNER_` prefix.** | Relevant if a perf or fixture toggle is added on the Swift side. |

---

## The manual, release-blocking gate

Automated tests cover the *decisions*; they cannot see a *screen*. Everything below is run by a
person on a device and recorded in the PR that closes PR E. **This slice cannot be signed off
without it** (SC-012, FR-075, research R9 and R12).

### Accessibility (SC-012, FR-065–FR-070)

| # | Check | Requirement |
|---|---|---|
| G1 | At the largest accessibility text size, in the unfiltered list, **no amount is truncated or ellipsised** — scroll at least three screenfuls | FR-021, SC-012 |
| G2 | At the same size, no row's content is clipped by the bottom bar or the home indicator — the finding this replaces is `StaticText '1'` at `{32, 724}` on the accounts list | FR-021, the parked finding |
| G3 | VoiceOver reads each row as one coherent sentence: date, description, amount **with currency**, direction **in words**, account — and "transfer" where marked | FR-015, FR-018, FR-066 |
| G4 | The date group heading is announced when the group is entered, and includes the year when it is not the current year | FR-033, FR-035 |
| G5 | The current account filter is announced, and clearing it is reachable and announced | FR-038, FR-039 |
| G6 | Reduce Transparency: the list stays legible, glass chrome degrades gracefully, no text on text | FR-067 |
| G7 | Increase Contrast + Dark Mode: amounts and direction words remain distinguishable **without relying on colour** | FR-013, FR-068 |
| G8 | While scrolling, the date currently in view stays identifiable | FR-034 |

### Performance on device (SC-006, SC-007, SC-008c)

Run on a real iPhone, release build, with the 10,000-row / 8-account corpus installed.

| # | Check | Requirement |
|---|---|---|
| G9 | Time from tapping into the list to the first screenful being readable — **< 1 s** | SC-006 |
| G10 | Scroll the full corpus: **no blank row persists for more than a moment**; no stutter that reads as a stall | SC-007 |
| G11 | The same measurement as G9 on a 200-row corpus — the two should not feel like different apps (the engine half is asserted as ≤ 20% in `cargo test`) | SC-008c |
| G12 | Apply a filter, then clear it — each **< 300 ms**, and the list does not jump to the top of an unrelated position | SC-008, FR-040 |
| G13 | Start an import while the list is open, scrolled and filtered. The list updates when the import commits; the filter is preserved; the scroll position is preserved; **no partially-written statement is ever visible** | FR-053, FR-054, FR-056, SC-010 |
| G14 | Cancel an import mid-way with the list open. **Nothing changes** on the list | FR-055 |

### How to run G9–G14 — the corpus, the build, and how the numbers are taken

**1. Build the corpus** (on the Mac, ~3 minutes):

```
make perf-corpus DIR=~/kaname-corpus
```

Eight synthetic statements — six card products, two of them appearing twice under a different
card number — 1,250 rows each. Every row has a globally unique amount and description, so
de-duplication cannot quietly shrink the corpus (R20). The target does not just write them: it
reads every document back through the **shipping** extractor and readers, imports all eight into
a throwaway store, and fails unless the result is **8 accounts holding 10,000 live rows**. On the
planning machine it reported 1.0–1.9 s per import and a 1.4 ms first page.

It also writes `200-rows/` for G11.

**2. Get it onto the phone.** AirDrop `~/kaname-corpus/10000-rows/*.pdf` (Files → *Save to Files*),
or drop the folder in iCloud Drive. Nothing is seeded: the app imports them through the document
picker like any other statement (FR-077).

**3. Install a release build**, then import all eight. Signing is read from the environment, so
it survives regeneration:

```
TUIST_DEVELOPMENT_TEAM=ABCDE12345 make ios-gen     # your team id
cd ios && xcodebuild -workspace Kaname.xcworkspace -scheme Kaname \
    -configuration Release -destination 'id=<device udid>' \
    -allowProvisioningUpdates install
```

Set the team by hand in Xcode instead and the next `make ios-gen` will wipe it.

Finding the two values:

- **Team id** — Xcode → Settings → Accounts → **+** → Apple ID; a free Apple ID gives a
  "Personal Team", which is enough for this gate. Then read it back with
  `defaults read com.apple.dt.Xcode | grep -A3 IDEProvisioningTeamByIdentifier` (⚠️ Xcode 26
  keeps it under `IDEProvisioningTeamByIdentifier`; the older `IDEProvisioningTeams` key does
  not exist and `defaults read` will say so), or developer.apple.com/account → Membership.
- **Device** — connect by cable and trust the Mac, then `xcrun devicectl list devices` for the
  name and UDID, or `xcodebuild -showdestinations -workspace Kaname.xcworkspace -scheme Kaname`
  for destination strings that can be pasted verbatim. Prefer `id=` over `name=`: a device name
  with a space or an emoji in it breaks the `name=` form.

⚠️ **Two things a free Personal Team costs you.** The installed build **stops working after
seven days**, so a gate run spread over two weekends needs re-installing. And a personal team
cannot mint a provisioning profile until the device is **connected and registered** — without
`-allowProvisioningUpdates`, and without the phone attached, the build fails with *"No profiles
for 'in.beaconbrain.kaname' were found"*, which is provisioning talking and not a code problem.
The very first signed build is easiest from Xcode's own UI (select the device, ⌘R), because it
handles two-factor sign-in and device registration interactively; `xcodebuild` works headlessly
from then on. ⚠️ `04-sbi.pdf` prints no readable card
number, so Kaname will **ask which account it belongs to** — name it and carry on. That is the
designed behaviour (FR-024), not a defect. Check the front door reads **8 accounts** before
starting, and that the counts add to 10,000.

⚠️ **Pairing, before any of this works.** A device has to be trusted over a **cable** once, with
the phone **unlocked**, and iOS 16+ needs **Developer Mode** (Settings → Privacy & Security →
Developer Mode → on → restart). Until then `xcrun devicectl list devices` can report the phone
as `available` — it is discoverable over the network — while Xcode still calls it unpaired and
`xcrun xctrace list devices` files it under *Devices Offline*. That disagreement is the
signature of a phone that has never been trusted, not of a broken cable.

⚠️ **Launch the app from the phone, not from Xcode.** A build run under the debugger is not the
build a person uses: the debug server, the memory graph instrumentation and the console pipe all
cost frame budget, and G9's bound is one second. Install it, stop the Xcode session, then tap the
icon on the home screen and start recording.

**4. Take the measurements from a screen recording, not a stopwatch.** Start iOS Screen Recording
(Control Centre), perform the action, stop, AirDrop the video to the Mac and step it frame by
frame in QuickTime with the arrow keys. At 60 fps one frame is 17 ms, so:

| Gate | Bound | Frames |
|---|---|---|
| G9 / G11 | < 1 s | < 60 |
| G12 | < 300 ms | < 18 |

Count from the frame the finger lands to the frame the content is **readable** — not the frame it
first appears. Recording costs a few percent of frame budget, which biases against passing: a
number that passes while recording passes.

**5. G11 needs a fresh store.** Delete the app (which deletes the encrypted database with it),
reinstall, and import `200-rows/01-icici-1002.pdf` only. The two corpora must never share a store.

**6. G13/G14 are the ones no automated test can reach.** Scroll deep into the list, apply an
account filter, then import a ninth statement — copy any of the eight into a new file name, so
it is a *re-import* and the row count must not change — and watch: the list updates, the filter
survives, the scroll position survives, and no half-written statement is ever on screen. Then
repeat, cancelling the import mid-way: **nothing** may change.

### Record here

| Field | Value |
|---|---|
| Device / iOS build | iPhone 17 Pro Max (iPhone18,2), iOS 26.6 |
| App build (commit) | `4a10c07` — Release configuration, free Personal Team, launched from the home screen with no debugger attached |
| Date run | 2026-08-15 |
| Corpus | `make perf-corpus` — 8 accounts, 10,000 live rows, **verified at generation time** by importing all eight into a throwaway store. Not re-confirmed on the device. |
| G1–G8 result | ⛔ **Not run.** See issue 02 below before running G7. |
| G9 / G11 | ⚠️ **Observed, not measured** — "felt instant", by eye, with no screen recording. SC-006's < 1 s bound is **not evidenced**. |
| G10 (scroll) | ✅ No stalls or persistent blank rows reported over the full corpus |
| G12 | ⚠️ **Observed, not measured** — SC-008's < 300 ms bound is **not evidenced**. |
| G13 / G14 | ✅ **PASS.** Importing a ninth statement with the list open, scrolled and filtered: the new rows appeared **without a relaunch**, the filter was kept, the scroll position was kept, and no partially-written statement was seen. A **cancelled** import changed nothing at all. |
| Notes | Two defects found while running it, both against 016 and neither in 018: `issues/02` (the accent measures 2.35:1 as text in Dark Mode — will fail G7) and `issues/03` (no way to give an account a last-4 the statement did not print). |

**What this record does and does not close.**

**G13 and G14 are the load-bearing result**, and they pass. They are the only evidence anywhere
that US8 works on a device: T118 established that no automated run can reach a populated
transaction list at all, so "an import lands in a list you are already reading, without taking
away your filter or your place in it" was, until this run, untested outside unit doubles.

**SC-012 is not yet satisfied.** G9, G11 and G12 were judged by eye. "Felt instant" is a real
signal — a screen that took two seconds would not feel instant — but it is not 60 frames, and
the whole point of writing the bound down was to stop a later regression hiding behind a
judgement. Closing it needs one screen recording and about ten minutes: tap in, filter, clear,
then step the video frame by frame (§ *How to run G9–G14*, step 4). G11 additionally needs the
app deleted and reinstalled with the 200-row corpus alone.

**G1–G8 have not been run at all**, and issue 02 says what one of them will find.

---

## Definition of done

- [x] The front door's account rows are tappable and lead to the list (US1)
- [x] The unfiltered list interleaves every account by date, newest first (US1, FR-028)
- [x] The order is total, deterministic and stable — proved by O1–O7 (FR-031, SC-009)
- [x] Re-importing a statement changes neither the count nor the list (US2, SC-003)
- [x] The front-door count comes from the engine, from the same rule as the list (FR-008, SC-004)
- [x] Deleted and superseded rows never appear anywhere (FR-007, SC-005)
- [x] The filter shows exactly one account, names itself, and is always clearable (US3, FR-038)
- [x] The filter is `.all` on every launch (FR-041)
- [x] Dates group across accounts, with the year shown when it is not the current year (US4)
- [x] No total, subtotal, balance or average exists anywhere in the code (FR-025, FR-026)
- [x] Each amount shows its own transaction's currency (US5, SC-011)
- [x] Categories and transfer markings render what the engine recorded (US6)
- [x] All six empty states are correct, and none of them blames the person (US7, FR-051)
- [x] The list keeps up with an import without losing filter or scroll position (US8, SC-010)
- [x] Engine perf gates green: no `SCAN`, no temp b-tree, every bound met (SC-006–SC-008a/b)
- [x] Every fixture synthetic; no real merchant, amount pattern or account identifier (SC-017)
- [x] `make core-lint && make core-test && make lint && make ios-test && make import-audit` green
      — with the two UI-test failures 016 already owns (see below)
- [ ] **Manual gate recorded above** with device, build and date (SC-012, SC-008c)
- [x] `.scratch/HANDOFF.md` and `AGENTS.md` updated; R17 and R18 carried forward as open items

### What US1 AS-6 now asserts, exactly

AS-6 — *two accounts holding a transaction with the same date, description and amount each keep
their own row* — **holds as written**, and is pinned by
`core/crates/kaname-core/tests/store_dedup_determinism.rs`:

| Test | What it fences |
|---|---|
| `two_credit_cards_each_keep_their_own_identical_row` (T008) | AS-6 itself, for two cards |
| `two_bank_accounts_each_keep_their_own_identical_row` (T008c) | AS-6, for two bank ledgers |
| `a_bank_ledger_and_a_card_still_collapse_the_same_purchase` (T008b) | 013's whole purpose — one purchase, seen twice, stays one row |

⚠️ **Carried forward as an open finding, for the slice that owns dedup.** Two accounts *of the
same kind* are now never compared at all. That is a blunt guard: a person with two bank
accounts, one of which itemises the other's card spends, would see the same spend twice. The
narrow fix is a **source-kind** guard rather than a same-kind one; the honest fix is a matcher
that knows *why* two rows are the same purchase, which is a larger question than a tie-break —
and larger than this slice, which changed only which of two matched rows wins.
