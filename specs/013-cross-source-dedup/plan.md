# Implementation Plan: Recognise the Same Purchase Across Two Sources On-Device — the Pure In-Memory CANONICAL + FUZZY Cross-Source De-Duplicator, Ported From the Web Engine (No Database, No New Dependency)

**Branch**: `013-cross-source-dedup` | **Date**: 2026-07-19 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/013-cross-source-dedup/spec.md`
**Milestone**: P2 (engine port) — the next ingestion check after the shipped per-statement balance-chain
and reconciliation trust signals; the first signal that looks **across two statements from different
sources**.

## Summary

Port the **pure, in-memory subset** of the web engine's cross-source de-duplicator into `kaname-core`
(Rust) as a **pure, deterministic, read-only** batch matcher over two already-parsed transaction lists.
When the **same purchase appears in two sources** — e.g. a person's **bank-account ledger** and their
**credit-card statement** — the matcher recognises it as **one purchase, not two**, so a later consumer
can avoid double-counting it. This is the on-device analogue of the web ladder's **two database-free
rungs** — **L3 CANONICAL** and **L4 FUZZY** — and nothing else.

The web de-duplicator (`deduplicator.py`) is a **database-backed async ladder** (L1 SOURCE_REF, L2
EXACT-hash, L3 CANONICAL, L4 FUZZY, L5 MERCHANT, plus an amount-drift SUPERSEDE) that queries a
`transactions` table and depends on merchant resolution + persistence — **none of which exist on-device
yet**. This slice ports **only** the two portable layers, as one function over two `&[Transaction]`
slices:

1. **Canonical layer** (pure analogue of web **L3**) — a duplicate iff **same date**, **same amount**
   (exact decimal magnitude), **same direction**, and **same normalised-narration prefix** (first **60**
   chars of `normalise_narration`).
2. **Fuzzy layer** (pure analogue of web **L4**) — a duplicate iff **same amount**, **same direction**,
   dates **within ±1 day**, and **Jaro-Winkler similarity ≥ 0.92** on the normalised narrations.

The matcher is **multiplicity-aware** (each existing row consumed by **at most one** incoming row —
surplus repeats survive), tries **canonical before fuzzy** per incoming row, and the **first unconsumed
existing** candidate wins. It is **read-only** (never mutates/drops/reorders/merges/persists a row) and
returns, for each matched incoming row, **which existing row it duplicates** and **by which layer**.

**Zero new dependency.** The web engine's `rapidfuzz` is web-only; on-device the Jaro-Winkler similarity
is **hand-rolled** and reproduces `rapidfuzz`'s f64 values byte-for-byte (verified — see below and
[`research.md`](./research.md)). The narration normaliser (`normalise_narration`) is a small port using
the **existing** `regex` crate. It reuses the shared `Transaction` type, the exact-decimal `Decimal`
money type, the golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate — the same
foundations the ten readers, balance-chain, and reconciliation checks use.

**Delivered as a small, surgical diff, entirely inside the existing `dedup` module + its bridge:**

- **`core/crates/kaname-core/src/dedup.rs`** (the existing de-dup module — **kept, extended**, not
  replaced): a new `normalize_narration` port (distinct from the existing coarser `normalize_description`,
  which is left **unchanged**), a hand-rolled `jaro` + `jaro_winkler` (private helpers), the
  `DedupLayer` enum, the `CrossSourceMatch` record, the `JARO_WINKLER_THRESHOLD = 0.92` constant, and the
  pure `cross_source_duplicates(&[Transaction], &[Transaction]) -> Vec<CrossSourceMatch>`, plus unit tests.
- **`ffi.rs`** — one `#[uniffi::export] pub fn cross_source_duplicates(existing, incoming)` wrapper that
  calls `crate::dedup::cross_source_duplicates(&existing, &incoming)` (mirrors how `reconcile_statement`
  wraps `reconcile`).
- **`lib.rs`** — re-export the **FFI** `cross_source_duplicates` + the `dedup` types/helper
  (`CrossSourceMatch`, `DedupLayer`, `normalize_narration`).
- **New golden fixture** `fixtures/dedup/cross_source/basic.json` (a new fixture **shape** — two lists +
  expected matches, not a statement).
- **Parity harness** (`tests/parity.rs`) — a dedup fixture loader + one `cross_source_dedup_matches_expected`
  test; the existing statement `CASES` are untouched.
- **Swift bridge test** `ios/Tests/CrossSourceDedupTests.swift` (Swift Testing) — canonical, fuzzy, and a
  multiplicity survivor over the bridge.

**Two design points worth stating up front** (details in [`research.md`](./research.md)):

1. **The Jaro-Winkler gate is ungated (no 0.7 boost threshold).** `jaro_winkler = jaro + prefix·0.1·(1 −
   jaro)` with `prefix` capped at 4 and **no** `jaro > 0.7` gate — this is exactly what `rapidfuzz`
   computes, and it is **proven** that a `jaro ≤ 0.7` can never reach the 0.92 decision threshold, so the
   gate distinction never changes any match decision (D3, verified). A Jaro-Winkler *similarity* is
   legitimately `f64` (a geometric/statistical score in [0,1], like `Word.x0/x1`) — **not money** — so it
   does **not** violate the "money is never a float" rule (D4).
2. **The two reference values `0.9232`/`0.9846` are 4-dp roundings of repeating decimals** (raw
   `0.92323232…`, `0.98461538…`), whereas `0.95`/`0.92`/`0.9125` land exactly on their f64 literals. So
   the Jaro-Winkler **unit tests pin the reference values by rounding to 4 decimal places** (which also
   matches how `rapidfuzz`'s full-precision f64 was captured for the spec) — **not** by `== 0.9232`. The
   `>= 0.92` **decision** uses the raw f64 and is robust at the boundary (D5, verified).

**Verified before writing this plan** (throwaway programs on the pinned stable toolchain against the
**real** `regex` crate and hand-rolled Jaro-Winkler, then deleted — repo left clean): all five
`normalize_narration` reference outputs reproduce exactly (`"UPI-SWIGGY-RRN1234"→"swiggy-"`, `"POS SWIGGY
BANGALORE 12345678901234"→"swiggy bangalore"`, `"NEFT/ACME CORP/REF999"→"acme corp/ref999"`, `"BY
TRANSFER-Salary Credit RRN5678"→"salary credit"`, `"SWIGGY  ORDER   9988776655"→"swiggy order"`), the
stacked-prefix loop collapses `"UPI/POS Coffee Day"→"coffee day"`, and the hand-rolled Jaro-Winkler
returns `0.95 / 0.92 / 0.9125 / 0.9232 / 0.9846 / 1.0` for the reference pairs, with `amazon/amazon pay`
`>= 0.92` **true** and `acme corp/acme corporation` `>= 0.92` **false**. Evidence is captured in
[`research.md`](./research.md) (Verification harness).

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI, iOS 18 target
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`, `uniffi 0.32`; dev-only `serde_json 1` (already present, fixture harness). **No new runtime OR dev dependency** (Jaro-Winkler is hand-rolled)
**Storage**: N/A (no persistence this slice; encrypted SQLite/SQLCipher and any stored de-dup state are explicitly out of scope)
**Testing**: `cargo test` (`dedup.rs` unit tests + `tests/parity.rs` golden harness + determinism) and Swift Testing (`ios/Tests/CrossSourceDedupTests.swift`); the privacy-egress audit stays green
**Target Platform**: iOS 18+ (device + simulator) via the UniFFI bridge; the engine itself is platform-agnostic (Android/desktop later)
**Project Type**: Mobile — shared Rust core (`kaname-core`) + native SwiftUI app (`ios/`)
**Performance Goals**: deterministic, on-device; the batch matcher is `O(|existing| · |incoming|)` over statement-sized lists — not a perf-critical path this slice (correctness + parity are the goals)
**Constraints**: pure & deterministic (no network/clock/locale/global state, no file/DB/PDF I/O); money is exact `Decimal` (a Jaro-Winkler similarity is `f64`, not money); zero network (privacy-egress gate); no new deps; Apache-2.0, no copyleft
**Scale/Scope**: two in-memory `Vec<Transaction>` lists of statement scale (~10²–10³ rows each); one new pure function + two small string helpers + two result types + one bridge export + one fixture + tests

## Constitution Check

*GATE: evaluated before Phase 0 and re-checked after Phase 1 design. All gates PASS.*

- **I. Data Privacy & Sovereignty (NON-NEGOTIABLE)** — **PASS.** The matcher is pure and on-device:
  normalising narrations, computing Jaro-Winkler, and identifying duplicates touch **no network, no
  clock, no locale, no file, no database**. It adds no telemetry/analytics/ad/crash SDK. The existing
  automated **privacy-egress test** (`make core-privacy-audit`) covers the new path — this slice adds **no
  dependency**, so the shipped dependency graph is byte-identical (FR-016/017/018, SC-015).
- **II. Local-First Shared Engine** — **PASS.** The logic lives in `kaname-core` as a pure, deterministic
  function over the shared `Transaction` type, reused across platforms via UniFFI. Money is
  `rust_decimal::Decimal` and amount equality is exact (`Decimal::normalize`); direction is the explicit
  `Direction`, never re-derived from sign. The **Jaro-Winkler similarity is `f64`** — a
  geometric/statistical score in [0,1], the same legitimate use of `f64` as `Word.x0/x1` and
  `ParsedStatement.confidence` — and is **not** money (FR-011, D4). No PDF engine, no database (FR-005/014).
- **III. Open-Core & Permissive Licensing** — **PASS.** No secrets, keys, or private endpoints. Apache-2.0
  clean: **no new runtime OR dev dependency** (the Jaro-Winkler is hand-rolled specifically to avoid
  adding `rapidfuzz`), so no copyleft (GPL/AGPL/LGPL) risk is introduced (FR-010/023, SC-016/017).
- **IV. Native Experience & Accessibility** — **N/A this slice.** No UI is introduced (engine + bridge +
  tests only). If a demo surface is ever added it must follow HIG + Dynamic Type/Dark Mode/VoiceOver
  (FR-025) — deferred to a later native step (Out of Scope).
- **V. Test-First & Parity** — **PASS.** Behaviour is pinned to the web engine (`normalise_narration`,
  `deduplicator.py` L3/L4, `rapidfuzz` Jaro-Winkler) and proven test-first: a golden fixture
  (`fixtures/dedup/cross_source/basic.json`), a parity-harness test, `dedup.rs` unit tests (normaliser +
  Jaro-Winkler reference values + canonical/fuzzy/boundary/guard/multiplicity), and a Swift bridge test.
  All fixture/test data is synthetic (FR-019..FR-022, SC-013/014).

**iOS Local Verification Gate**: unchanged and honored — `make core-lint && make core-test &&
make core-privacy-audit && make lint && make ios-test`, with `make core-xcframework` **before**
`tuist generate` (baked into `make ios-gen`). See [`quickstart.md`](./quickstart.md).

**Result**: **PASS** (no violations). The only nuance recorded in Complexity Tracking is scope — this is
deliberately the **portable subset** (L3 + L4) of the web ladder.

## Project Structure

### Documentation (this feature)

```text
specs/013-cross-source-dedup/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — decisions, alternatives, verification evidence
├── data-model.md        # Phase 1 — DedupLayer, CrossSourceMatch, cross_source_duplicates, helpers
├── quickstart.md        # Phase 1 — build & verify walkthrough (iOS gate ordering)
├── contracts/           # Phase 1 — behaviour + FFI + golden-fixture contracts
│   ├── cross-source-dedup.md   # the pure matcher's behaviour contract (canonical/fuzzy ladder)
│   ├── engine-ffi.md           # the UniFFI Swift surface (cross_source_duplicates + types)
│   └── golden-fixture.md       # the NEW dedup fixture schema + exact bytes for basic.json
├── checklists/          # (pre-existing) requirements checklist
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── src/
│   ├── dedup.rs          # EXTEND: + normalize_narration, jaro, jaro_winkler, DedupLayer,
│   │                     #         CrossSourceMatch, JARO_WINKLER_THRESHOLD, cross_source_duplicates,
│   │                     #         unit tests. (existing normalize_description + dedup_fingerprint kept.)
│   ├── ffi.rs            # EXTEND: + #[uniffi::export] cross_source_duplicates wrapper
│   ├── lib.rs            # EXTEND: re-export ffi::cross_source_duplicates and
│   │                     #         dedup::{CrossSourceMatch, DedupLayer, normalize_narration}
│   ├── model.rs          # REUSED unchanged — Transaction, Direction
│   └── statement/        # REUSED unchanged — readers, balance_chain, reconcile
└── tests/
    └── parity.rs         # EXTEND: + dedup fixture loader + cross_source_dedup_matches_expected

fixtures/
└── dedup/cross_source/
    └── basic.json        # NEW fixture shape: { existing[], incoming[], expected_matches[] }

ios/
└── Tests/
    └── CrossSourceDedupTests.swift   # NEW Swift Testing bridge test

.github/copilot-instructions.md       # regenerated by update-agent-context.sh (+ typo fix)
```

**Structure Decision**: Mobile shared-core layout (unchanged). This slice **extends the existing `dedup`
module** rather than adding a new one — the module already exists for cross-source de-dup (it currently
holds the coarser `normalize_description` + `dedup_fingerprint`), so the L3/L4 matcher and its helpers
are its natural home, mirroring how `reconcile.rs` sat beside `balance_chain.rs`. The FFI wrapper +
re-exports follow the `reconcile_statement` precedent exactly. Only the files listed above change; no
reader, `model.rs`, `base.rs`, `uniffi.toml`, `Cargo.toml`, or CI change.

## Complexity Tracking

> No Constitution **violations**. The single nuance below is a deliberate **scope** decision (a faithful
> subset), not a principle violation, and is recorded per Governance for reviewer clarity.

| Nuance | Why (this slice) | Why the rest is correctly excluded |
|---|---|---|
| Ports **only** L3 CANONICAL + L4 FUZZY (the "portable subset" of the web L1→L5 + SUPERSEDE ladder) | These are the **only two layers that are pure and database-free** — they need just the two in-memory lists, exact-decimal amounts, explicit direction, `normalise_narration`, and Jaro-Winkler | **L1 SOURCE_REF** / **L2 EXACT-hash** are database-index concerns; **L5 MERCHANT** + all merchant resolution need a merchant catalog absent on-device; **amount-drift SUPERSEDE** needs merchant resolution **and** persistence; all require the encrypted SQLite/SQLCipher store that is a later phase (spec Out of Scope, FR-012) |
| Jaro-Winkler is **hand-rolled** (not a crate) | Reproduces `rapidfuzz`'s f64 **byte-for-byte** (verified) while honoring **no new dependency** (FR-010/023) | Adding `rapidfuzz` (or any similarity crate) would violate the zero-new-dependency gate and the Apache-2.0/no-copyleft posture; the ~40-line hand-roll is fully covered by unit tests |
| A Jaro-Winkler similarity is stored/compared as `f64` | It is a statistical score in [0,1], not a monetary quantity — the same legitimate `f64` use as `Word.x0/x1` geometry and `ParsedStatement.confidence` | **All monetary** values stay exact `Decimal` (amount equality via `Decimal::normalize`); no money is ever `f64` (FR-011, SC-011) |

## Phase 0 — Outline & Research

The approach is **locked** by the requester and pinned to the web engine; there are **no NEEDS
CLARIFICATION** items. Phase 0 records the decisions, the alternatives rejected, and the byte-for-byte
verification of the two non-trivial ports (the normaliser and the Jaro-Winkler). See
[`research.md`](./research.md) for D1–D12 and the Verification harness.

**Output**: [`research.md`](./research.md) — complete, all unknowns resolved, verification evidence
attached.

## Phase 1 — Design & Contracts

- **Data model** — [`data-model.md`](./data-model.md): the `DedupLayer` enum, the `CrossSourceMatch`
  record, the `cross_source_duplicates` function (canonical-then-fuzzy ladder, multiplicity via a
  `consumed` vector, precomputed normalised narrations, exact-`Decimal` amount equality), the
  `normalize_narration` port, and the private `jaro`/`jaro_winkler` helpers, plus the reused
  `Transaction`/`Direction` types and the parity fixture types.
- **Contracts** — [`contracts/`](./contracts):
  - `cross-source-dedup.md` — the pure matcher's stable behaviour contract (the two-layer ladder, the
    guards, multiplicity, determinism, read-only).
  - `engine-ffi.md` — the UniFFI Swift surface (`crossSourceDuplicates(existing:incoming:)`,
    `DedupLayer`, `CrossSourceMatch`).
  - `golden-fixture.md` — the **new** dedup fixture schema and the exact `basic.json` bytes (verified
    against the web logic).
- **Agent context** — run `.specify/scripts/bash/update-agent-context.sh copilot` to refresh
  `.github/copilot-instructions.md` with this slice's tech line (then apply the known `iOS 18 targe`→`iOS
  18 target` fix; see the report).

**Output**: `data-model.md`, `contracts/*`, `quickstart.md`, and the refreshed agent context file.

## Phase 2 — (Not executed here)

`/speckit.tasks` will turn these artifacts into an ordered `tasks.md`. This command stops after Phase 1.
