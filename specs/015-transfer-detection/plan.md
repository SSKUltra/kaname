# Implementation Plan: On-Device Transfer (Self-Transfer) Detection — the Pure Deterministic Pairing of Opposite-Direction Cross-Account Rows into Self-Transfer / Credit-Card Bill-Payment Pairs, Ported From the Web Engine's `transfer_detector.py` (No Database, No Clock, No New Dependency)

**Branch**: `015-transfer-detection` | **Date**: 2026-07-20 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/015-transfer-detection/spec.md`
**Milestone**: P2 (engine port) — the self-transfer-pairing piece of the ingestion layer, alongside the
already-shipped balance-chain, reconciliation, cross-source de-duplication, and coverage-map slices; the signal
that recognises when a person is **moving their own money between their own accounts**.

## Summary

Port the pure subset of the web engine's `app/services/ingestion/transfer_detector.py` — its `_narration_similarity`
and `_score` helpers, its ±1-day / ±₹1.00 tolerance envelope, and its outflow-anchored greedy selection (`detect_pairs_for_user`
+ `_best_counterpart`, minus all SQL) — into `kaname-core` (Rust) as a **pure single-pool matcher**. Over **one**
list of already-parsed, still-unpaired transactions it **anchors on outflows** (`Direction::Debit`) in ascending
**`(date, id)`** order, and for each still-unpaired anchor **greedily claims** the best opposite-direction
**inflow** (`Direction::Credit`) counterpart on a **different account** within **±1 day** and **±₹1.00** (both
inclusive), resolving ambiguity by the deterministic tuple **`(date_diff, amount_diff, -narration_similarity, id)`**
(lowest wins). Each detected pair reports the **outflow id**, the **inflow id**, an **`is_credit_card_payment`**
flag (true when **either** leg is a credit-card account), and a float confidence **`score`** =
`max(0, 1 − 0.2·date_diff − 0.2·amount_diff + 0.2·narration_similarity)`. Output pairs are ordered by the anchor's
`(date, id)`.

The matcher is **pure and deterministic** (Constitution Principles I & II): no network, no clock, no locale, no
database, no hidden state. It reuses the shared money (`rust_decimal::Decimal`) and date (`chrono::NaiveDate`)
types, the golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate, and adds **no new
runtime OR dev dependency** — token-Jaccard and the score are hand-rolled with `std` + `rust_decimal`'s
`ToPrimitive::to_f64`. Every DB/persistence concern — writing `transfer_group_id`/`is_transfer`, the "Self
Transfer" / "Credit Card Bill Payment" category get-or-create, audit events, the optimistic-concurrency race
handling, cross-user filtering, and the email-parse `match_window_days` override — stays **platform-side**,
mirroring the web engine's DB layer.

The port reproduces the pinned web helpers **exactly** (Constitution Principle V), including three porting details
that this plan calls out up front (full rationale in [`research.md`](./research.md)):

1. **`narration_similarity` is token-level Jaccard on the raw lowercased, whitespace-split description** — the web
   `_narration_similarity`. It is **deliberately DISTINCT** from the de-dup slice's `dedup::normalize_narration` +
   Jaro-Winkler measure; the two must not be conflated (research D4, the key porting gotcha).
2. **`score` is floored at 0.0 but NOT capped at 1.0** — verified against live ground truth (a same-day/same-amount
   pair with narration overlap scores `1.0285714285714285`; other golden pairs score `1.05` / `1.2` /
   `1.0333333333333334`). The exact Python left-to-right op order is preserved so the f64 bits match across
   x86_64/arm64 (research D5).
3. **The FFI wrapper `detect_transfers` shadows the pure `transfer::detect_transfers`** — so `ffi.rs` imports only
   the transfer **types** (not the pure fn) and calls it fully-qualified, and `lib.rs` re-exports the **FFI**
   function at the crate root (the pure one is **not** re-exported). This is the exact `compute_coverage` (014) /
   `cross_source_duplicates` (013) name-clash precedent (research D9).

**Delivered as a small, surgical diff — a new top-level module + its bridge + a golden fixture + tests:**

- **`core/crates/kaname-core/src/transfer.rs`** (NEW top-level module, sibling to `dedup.rs` / `coverage.rs`): the
  `TransferInput` input record, the `TransferPair` output record, `DATE_TOLERANCE_DAYS = 1`, the pure
  `detect_transfers` matcher, the private `narration_similarity` + `score` helpers, and unit tests.
- **`ffi.rs`** — one `#[uniffi::export] pub fn detect_transfers(rows: Vec<TransferInput>) -> Vec<TransferPair>`
  wrapper that calls the pure `crate::transfer::detect_transfers(&rows)` (mirrors how `cross_source_duplicates` /
  `compute_coverage` wrap their pure core).
- **`lib.rs`** — `pub mod transfer;`, re-export the **FFI** `detect_transfers`, and re-export the transfer **types**
  (`TransferInput`, `TransferPair`). The pure `transfer::detect_transfers` is **not** re-exported at the crate root
  (name clash with the FFI wrapper — research D9).
- **New golden fixture** `fixtures/transfer/basic.json` — a new fixture **shape** (`rows[]` + `expected_pairs[]`),
  captured from a live run of the web engine's pure helpers.
- **Parity harness** (`tests/parity.rs`) — a transfer fixture loader (`TransferFixture` + `TransferInputRow` +
  `ExpectedPair`) + one `transfer_detection_matches_expected` test; the statement `CASES`, the dedup loader/test,
  and the coverage loader/test are untouched.
- **Swift bridge test** `ios/Tests/TransferDetectionTests.swift` (Swift Testing) — construct a `[TransferInput]`,
  call `detectTransfers`, and assert the `[TransferPair]` (camelCased `outflowId` / `inflowId` /
  `isCreditCardPayment` / `score`; input field `isCreditCard`).

**Verified before writing this plan** (a throwaway simulation of the locked algorithm — the web `_narration_similarity`
+ `_score` + the anchor-sort + greedy-claim — run then discarded, repo left clean): the nine-scenario pool produces
**exactly 5 pairs** (`s1→s1` `1.0285714285714285`, `s2→s2` `0.8200000000000001`, `s7→s7-a` `1.05`, `s8→s8-a`
`1.2`, `s9→s9` `1.0333333333333334`) and **4 no-pair guards** (amount-drift, date-drift, same-direction,
same-account). Every score is **bit-identical** between Python and Rust and **round-trips through serde_json/ryu**
(exact f64 `==`) — so the parity test's exact-equality assertion holds. Evidence is captured in
[`research.md`](./research.md) (Verification).

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency** (token-Jaccard + the score are hand-rolled with `std` + `rust_decimal`'s `ToPrimitive::to_f64`)
**Storage**: N/A (no persistence this slice; `transfer_group_id`/`is_transfer` persistence and all DB concerns are explicitly out of scope, platform-side; encrypted SQLite/SQLCipher arrives in a later phase)
**Testing**: `cargo test` (`transfer.rs` unit tests + `tests/parity.rs` golden harness with exact-f64 parity + determinism) and Swift Testing (`ios/Tests/TransferDetectionTests.swift`); the privacy-egress audit stays green
**Target Platform**: iOS 18+ (device + simulator) via the UniFFI bridge; the engine itself is platform-agnostic (Android/desktop later)
**Project Type**: Mobile — shared Rust core (`kaname-core`) + native SwiftUI app (`ios/`)
**Performance Goals**: deterministic, on-device; the matcher is `O(A · N)` (anchors × pool) with a stable sort of the anchor set — not a perf-critical path this slice (correctness + parity are the goals)
**Constraints**: pure & deterministic (no network/clock/locale/global state, no file/DB/PDF I/O); money & the ±₹1 tolerance compared with exact `Decimal` (only the confidence `score` is an `f64`, and it is not money); zero network (privacy-egress gate); no new deps; Apache-2.0, no copyleft
**Scale/Scope**: one in-memory transaction list of statement/transaction scale (~10⁰–10³ rows) → a list of detected pairs; one new module with one pure matcher + two private helpers + two types + one const + one bridge export + one fixture + tests

## Constitution Check

*GATE: evaluated before Phase 0 and re-checked after Phase 1 design. All gates PASS.*

- **I. Data Privacy & Sovereignty (NON-NEGOTIABLE)** — **PASS.** The matcher is pure and on-device: sorting the
  anchors, scanning candidates, computing token-Jaccard and the score, and emitting pairs touch **no network, no
  clock, no locale, no file, no database**. It adds no telemetry/analytics/ad/crash SDK. The existing automated
  **privacy-egress test** (`make core-privacy-audit`) covers the new path — this slice adds **no dependency**, so
  the shipped dependency graph is byte-identical (FR-017/018/019, SC-012).
- **II. Local-First Shared Engine** — **PASS.** The logic lives in `kaname-core` as a pure, deterministic function
  over the shared `NaiveDate` + `Decimal` types, reused across platforms via UniFFI. Identical input ⇒ identical
  output (FR-012, SC-009); the core never reads the wall-clock, locale, or hidden state. **Money and the ±₹1
  tolerance use exact `Decimal`** (compared with `Decimal::ONE`); the only `f64` is the confidence **`score`**,
  which is explicitly a confidence metric, **not money** (Principle II governs money — FR-011). No PDF engine, no
  database (FR-014/016).
- **III. Open-Core & Permissive Licensing** — **PASS.** No secrets, keys, or private endpoints. Apache-2.0 clean:
  **no new runtime OR dev dependency** (token-Jaccard is hand-rolled with `std`; `to_f64` comes from the
  already-present `rust_decimal`), so no copyleft (GPL/AGPL/LGPL) risk is introduced (FR-013/024, SC-013).
- **IV. Native Experience & Accessibility** — **N/A this slice.** No UI is introduced (engine + bridge + tests
  only); the Swift test only exercises the bridge. Any future user-facing surface must follow the latest HIG +
  Dynamic Type/Dark Mode/VoiceOver (FR-026).
- **V. Test-First & Parity** — **PASS.** Behaviour is pinned to the web engine (`transfer_detector.py`'s
  `_narration_similarity` / `_score` / the tolerance envelope / the anchor-sorted greedy selection) and proven
  test-first: a golden fixture (`fixtures/transfer/basic.json`) captured from a live run of the pure helpers, a
  parity-harness test (`transfer_detection_matches_expected`, exact-f64 comparison), `transfer.rs` unit tests
  (the five pairing scenarios + the four guards + empty/no-outflow + determinism + the score floor + the
  narration/id tiebreaks + Jaccard edge cases), and a Swift bridge test. All fixture/test data is synthetic
  (fabricated ids/accounts/dates/amounts/narrations) (FR-020..FR-023, SC-010).

**iOS Local Verification Gate**: unchanged and honored — `make core-lint && make core-test &&
make core-privacy-audit && make lint && make ios-test`, with `make core-xcframework` **before** `tuist generate`
(baked into `make ios-gen`). See [`quickstart.md`](./quickstart.md).

**Result**: **PASS** (no violations). The only nuance recorded in Complexity Tracking is scope — this is
deliberately the **portable pure subset** of the web transfer detector (the pairing logic; the DB writes, category
get-or-create, audit, race handling, cross-user filter, and `match_window_days` override stay on the platform).

## Project Structure

### Documentation (this feature)

```text
specs/015-transfer-detection/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — decisions, alternatives, verification evidence
├── data-model.md        # Phase 1 — TransferInput, TransferPair, detect_transfers, narration_similarity, score
├── quickstart.md        # Phase 1 — build & verify walkthrough (iOS gate ordering)
├── contracts/           # Phase 1 — behaviour + FFI + golden-fixture contracts
│   ├── transfer.md           # the pure detect_transfers behaviour contract
│   ├── engine-ffi.md         # the UniFFI Swift surface (detectTransfers + TransferInput/TransferPair)
│   └── golden-fixture.md     # the NEW transfer fixture schema + exact bytes for basic.json
├── checklists/          # (pre-existing) requirements checklist
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── src/
│   ├── transfer.rs     # NEW top-level module (sibling to dedup.rs / coverage.rs): TransferInput, TransferPair,
│   │                   #   DATE_TOLERANCE_DAYS, detect_transfers, narration_similarity (private), score (private),
│   │                   #   unit tests
│   ├── ffi.rs          # EXTEND: + #[uniffi::export] detect_transfers wrapper (imports transfer TYPES only,
│   │                   #   calls the pure fn fully-qualified to avoid the name clash)
│   ├── lib.rs          # EXTEND: pub mod transfer; re-export ffi::detect_transfers + transfer::{TransferInput,
│   │                   #   TransferPair}
│   ├── model.rs        # REUSED unchanged — Direction (Debit = outflow, Credit = inflow); Transaction untouched
│   └── statement/      # REUSED unchanged — readers, balance_chain, reconcile
└── tests/
    └── parity.rs       # EXTEND: + transfer fixture loader + transfer_detection_matches_expected

fixtures/
└── transfer/
    └── basic.json      # NEW fixture shape: { _comment, rows[], expected_pairs[] }

ios/
└── Tests/
    └── TransferDetectionTests.swift    # NEW Swift Testing bridge test

.github/copilot-instructions.md   # regenerated by update-agent-context.sh (+ `iOS 18 targe` typo fix)
```

**Structure Decision**: Mobile shared-core layout (unchanged). Transfer detection is a **new, independent
ingestion-signal concern** (distinct from parsing/reconcile/dedup/coverage), so it gets its **own top-level module**
`transfer.rs` — a sibling to `dedup.rs` and `coverage.rs` — exactly as the requester specified. The FFI wrapper +
re-exports follow the `cross_source_duplicates` (013) / `compute_coverage` (014) precedent exactly, including the
deliberate non-re-export of the pure function to avoid the name clash. Only the files listed above change; no
reader, `model.rs`, `base.rs`, `uniffi.toml`, `Cargo.toml`, or CI change.

## Complexity Tracking

> No Constitution **violations**. The single nuance below is a deliberate **scope** decision (a faithful subset),
> not a principle violation, and is recorded per Governance for reviewer clarity.

| Nuance | Why (this slice) | Why the rest is correctly excluded |
|---|---|---|
| Ports **only** the pure pairing logic (`_narration_similarity` + `_score` + the tolerance envelope + the anchor-sorted greedy selection), **not** the web `transfer_detector.py`'s DB layer | The pairing is the **only part that is pure and store-free** — it needs just one in-memory row list. The core returns the detected pairs; the platform performs every side effect | Persisting `transfer_group_id`/`is_transfer`, the "Self Transfer" / "Credit Card Bill Payment" **category get-or-create**, **audit events**, the optimistic-concurrency `_claim_pair`/SAVEPOINT **race handling**, **cross-user filtering**, and the email-parse **`match_window_days`** date-tolerance override all need the encrypted store / API surface that is a later phase (spec Assumptions, Out of Scope, FR-016) |
| Transfer gets a **new top-level module** (`transfer.rs`) rather than joining an existing one | Transfer pairing is a distinct concern from parsing/reconcile/dedup/coverage; a sibling module mirrors `dedup.rs`/`coverage.rs` and keeps the diff surgical | Reusing `dedup.rs`/`statement/*` would conflate unrelated logic — in particular, transfer's token-Jaccard `narration_similarity` must **not** be confused with `dedup::normalize_narration` + Jaro-Winkler (research D4) |
| The confidence **`score`** is an `f64` (not `Decimal`) and is **not capped at 1.0** | The score is a **confidence metric, not money** — Constitution Principle II governs money; a float is correct and the web `_score` is uncapped above 1.0 (live ground truth: `1.0285714285714285` / `1.05` / `1.2` / `1.0333333333333334`) | Representing the score as `Decimal` would diverge from the pinned web `_score` bits; capping at 1.0 would break parity (research D5) |

## Phase 0 — Outline & Research

The approach is **locked** by the requester and pinned to the web engine (`transfer_detector.py`'s pure subset);
there are **no NEEDS CLARIFICATION** items. Phase 0 records the decisions, the alternatives rejected, and the
byte-for-byte verification of the ported helpers (`narration_similarity`, `score`) and the greedy matcher against a
throwaway simulation of the locked algorithm on the nine-scenario pool. See [`research.md`](./research.md) for the
decision log and the Verification section (including the exact, bit-identical, round-trip-verified scores).

**Output**: [`research.md`](./research.md) — complete, all unknowns resolved, verification evidence attached.

## Phase 1 — Design & Contracts

- **Data model** — [`data-model.md`](./data-model.md): the `TransferInput` input record, the `TransferPair` output
  record, `DATE_TOLERANCE_DAYS = 1`, the `detect_transfers` matcher (anchor sort; the consumed-vector greedy claim;
  the candidate filter; the `min_by` comparator), the private `narration_similarity` (token-Jaccard) and `score`
  helpers, the reused `Direction`/`NaiveDate`/`Decimal` types, the FFI wrapper + re-exports (name-clash handling),
  and the parity fixture types.
- **Contracts** — [`contracts/`](./contracts):
  - `transfer.md` — the pure matcher's stable behaviour contract (anchor set + ordering; the candidate eligibility
    guards; the selection tuple; greedy single-claim; `is_credit_card_payment`; the `narration_similarity` and
    `score` definitions; determinism/totality).
  - `engine-ffi.md` — the UniFFI Swift surface (`detectTransfers(rows:)`, `TransferInput`, `TransferPair`).
  - `golden-fixture.md` — the **new** transfer fixture schema and the exact `basic.json` bytes (the verified pool +
    5 expected pairs with exact scores).
- **Agent context** — run `.specify/scripts/bash/update-agent-context.sh copilot` to refresh
  `.github/copilot-instructions.md` with this slice's tech line (then apply the known `iOS 18 targe` → `iOS 18
  target` fix; see the report).

**Output**: `data-model.md`, `contracts/*`, `quickstart.md`, and the refreshed agent context file.

## Phase 2 — (Not executed here)

`/speckit.tasks` will turn these artifacts into an ordered `tasks.md`. This command stops after Phase 1.
