# 06 — The three device timing gates (G9, G11, G12) have never been measured

**Status:** ready-for-human

**Split out of:** `issues/01`, on 2026-08-15, once G1–G8 and G10 were run and that ticket's
accessibility half was closed. 01 was two jobs bolted together — *"nobody has audited this"* and
*"nobody has timed this"*. The first is done; this is the second, on its own, so it can be picked
up cold by whoever next has a phone in their hand.
**Belongs to:** `018-transaction-list` — SC-006, SC-008, SC-008c, and § *How to run G9–G14* in
`specs/018-transaction-list/quickstart.md`.
**Severity:** ⚠️ **SC-012 cannot be signed off until these three carry numbers.** They do not
block development, and on the evidence below they are unlikely to *fail* — their value is the
baseline, not the verdict.
**Needs:** a physical iPhone, a Release build, and about 20 minutes. **No code.**

## The three gates

| Gate | Criterion | The question it alone answers | Bound |
|---|---|---|---|
| **G9** | SC-006 | Tap into the list — is the first screenful **readable** that fast? | < 1 s (< 60 frames) |
| **G11** | SC-008c | Does a 10,000-row corpus feel like a *different app* from a 200-row one? | the two must not differ perceptibly |
| **G12** | SC-008 | Apply an account filter, then clear it | < 300 ms each (< 18 frames) |

## Why the automated gates do not already cover this

They cover the **engine**, and they cover it thoroughly. `research.md` R9 measured the
first-page k-way merge at **254.75 µs** on the 10,000-row / 8-account corpus — 0.018% of G9's
one-second budget — and restated SC-008 into a **query-plan** assertion (`EXPLAIN QUERY PLAN`
contains no `SCAN` and no `USE TEMP B-TREE`, identically on both corpora) precisely because a
wall-clock number can pass by luck and a plan cannot.

None of that touches what happens **between the query returning and a person reading a row**:
the FFI hop, SQLCipher's first decrypt, the actor hops, SwiftUI building rows, glass
compositing, and the frame budget. The engine can be 255 µs and the screen can still take 1.4
seconds, with every automated gate green. **These three are the only measurement taken from the
person's side of the glass.**

G11 carries the most real risk of the three, because it is the only check that the *platform*
layer does not scale with corpus size even though the engine provably does not.

## Why an impression will not close it

*"Felt instant"* was recorded on the 2026-08-15 device run, and it is a real signal — a screen
that took two seconds would not feel instant. But **900 ms also feels instant**, and the reason
the bound was written down was to stop a later regression hiding behind a judgement. A number is
something the next person can compare against; an impression is not. G12's 300 ms is **eighteen
frames** — past what an unaided eye can time at all.

## Runbook

Full detail in `quickstart.md` § *How to run G9–G14*. In short:

1. **Corpus** — `make perf-corpus DIR=~/kaname-corpus`. Eight statements, 1,250 rows each; the
   target verifies itself by importing all eight into a throwaway store and failing unless the
   result is 8 accounts / 10,000 live rows. It also writes `200-rows/` for G11.
2. **Get it on the phone** — AirDrop `10000-rows/*.pdf` (→ *Save to Files*) or iCloud Drive.
   Nothing is seeded; they go through the document picker like any statement (FR-077).
   ⚠️ `04-sbi.pdf` prints no card number, so Kaname will **ask** which account it belongs to —
   name it and carry on. That is FR-024 working, not a defect.
3. **Release build, no debugger.**
   ```
   TUIST_DEVELOPMENT_TEAM=ABCDE12345 make ios-gen
   cd ios && xcodebuild -workspace Kaname.xcworkspace -scheme Kaname \
       -configuration Release -destination 'id=<device udid>' -allowProvisioningUpdates install
   ```
   ⚠️ **Install it, quit Xcode, then tap the icon on the home screen.** A build under the
   debugger pays a frame-budget tax that G9's one-second bound cannot afford.
4. **Measure from a screen recording, not a stopwatch.** Control Centre → record, do the action,
   AirDrop the video to the Mac, step it frame by frame in QuickTime with the arrow keys. At 60
   fps one frame is 17 ms. Count from the frame the finger lands to the frame the content is
   **readable** — not the frame it first appears. Recording costs a few percent of frame budget,
   which biases *against* passing: a number that passes while recording passes.
5. **G11 needs a fresh store.** Delete the app — which deletes the encrypted database with it —
   reinstall, and import `200-rows/01-icici-1002.pdf` **alone**. The two corpora must never share
   a store.
6. **Write the numbers into** `quickstart.md` § *Record here*, with the build and the date. That
   record is what actually satisfies SC-012.

## Traps

- ⚠️ **A free Personal Team build expires after seven days.** The one installed on 2026-08-15 is
  dead after **2026-08-22**; re-install before running.
- ⚠️ **A device must be trusted over a cable once, unlocked, with Developer Mode on**
  (Settings → Privacy & Security → Developer Mode → restart). Until then `xcrun devicectl list
  devices` can report it as `available` while Xcode still calls it unpaired — that disagreement
  is the signature of an untrusted phone, not a broken cable.
- ⚠️ **Do not measure on the simulator.** Different GPU path, different memory, no thermal or
  power management. A number taken there looks like evidence and is not. This is why the
  2026-08-15 simulator session ran G1–G8 and G10 and deliberately left these three alone.

## Definition of done

`quickstart.md` § *Record here* carries three measured numbers with a build and a date, and G9,
G11 and G12 read ✅ or ⛔ rather than ⚠️. If any fails, file the failure as its own ticket — the
fix is not this ticket's job.

---

## Deferred — 2026-08-17, by the holder

**Deferred, not dropped.** Status stays `ready-for-human` because that is still what it needs; the
`Deferred:` note is the repo's existing idiom for "not now", the same one `issues/01` carried
before it was run.

**What deferring costs, precisely:** **SC-012 cannot be signed off.** G9, G11 and G12 are the last
three unmeasured items in 018's gate — every accessibility gate now passes — so 018 is complete on
every axis except *timed on real hardware*. Nothing else is waiting on it, and no further work is
blocked by it.

**Why it is a low-risk deferral.** The engine halves of the same bounds are already asserted in
`cargo test` (`history_perf.rs` — the page plan neither scans nor sorts, first page within budget,
per-account cost flat), and G10 (scrolling the full 10,000-row corpus) passed by hand. What is
unmeasured is the *platform* half: how long a person waits, in frames.

**Pick it up when a phone and a Release build are in the same room** — the ticket's runbook is
unchanged and self-contained. ⚠️ A free Personal Team build expires **seven days** after install,
so budget the measurement inside one week of installing it.
