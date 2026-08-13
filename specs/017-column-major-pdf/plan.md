# Implementation Plan: Column-Major PDF Extraction Fidelity

**Branch**: `017-column-major-pdf` | **Date**: 2026-08-13 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/017-column-major-pdf/spec.md`

## Summary

Ten of thirteen genuine statement PDFs import **zero** transactions today, and the remaining three
under-read. No file is defective: every one yields a text layer of 7,697–100,792 characters. Real
statements are multi-column tables and the platform's text layer emits them **column-major**, so a
printed row arrives as several unrelated text lines — while every shipped reader matches a row only
when date, description and amount appear together on one line.

The fix is **two changes that must ship together**, plus the evidence that pins them:

1. **Geometry-first row reconstruction** (platform, `StatementTextExtractor.swift`). Stop treating
   the text layer's newlines as authoritative. Build the page's words with their positions, group
   them into row bands by vertical overlap, and emit one line per printed row. Because the text
   layer's grouping is discarded entirely, one algorithm both **splits** rows it merged (the
   slice-016 hazard) and **joins** columns it split (this slice's hazard) — FR-030 falls out rather
   than needing a second mechanism.
2. **Recognition that survives reshaping** (engine, `kaname-core`). Claim markers become
   whitespace-insensitive (FR-012) and are matched against an **identity region** — the document
   minus its transaction rows — instead of the whole document. The first half is mandatory: a
   prototype that reshaped rows without it turned **11 of 13** documents into "not recognised". The
   second half is the control on the widening: `AU-statment-savings.pdf` contains the literal
   `HDFC` inside a UPI description, and `hdfc_bank`'s `CLAIM_ALL` is exactly `["HDFC"]`.
3. **Registry at card-product granularity** (FR-041–FR-053). The six card entries are renamed to
   name the product they read, `bank_code` becomes the bare institution everywhere (fixing
   `sbi.rs`'s `"SBI_CARD"`), each entry declares whether its claim is product-proven or bank-level,
   `detect_issuer` resolves by specificity, and a test fails the build if two card entries for one
   institution are not both product-proven. No reader's parsing behaviour changes.
4. **Generated geometry fixtures** (`fixtures/geometry/*.json`). Synthetic statements rendered
   column-major from a layout signature, opened by the real PDF engine, run through the real
   dispatcher and readers — with a standing **non-vacuity** assertion that the pre-slice extraction
   reads strictly fewer transactions. Plus a human-run, local-only pass over the private reference
   set that records counts and nothing else.

**No new runtime or dev dependency. No FFI shape change. No schema change — the store stays at v6.**

## Technical Context

**Language/Version**: Rust (stable, per `rust-toolchain.toml`) + Swift 5.x / SwiftUI
**Primary Dependencies**: existing `regex 1`, `rust_decimal 1`, `chrono 0.4`, `serde 1`,
`thiserror`, `uniffi 0.32`, `rusqlite`/SQLCipher; dev-only `serde_json 1` (already present).
iOS: SwiftUI, Foundation, **PDFKit** and **UIKit/CoreGraphics** (`UIGraphicsPDFRenderer`, already
used by `StatementTextExtractorTests`), Tuist, Swift Testing. **No new runtime OR dev dependency.**
**Storage**: unchanged — encrypted on-device SQLCipher store at **schema v6**. This slice adds no
migration and no persisted field (research R9 records the deliberate deferral of `issuer_id`).
**Testing**: `cargo test` (unit + `tests/parity.rs` + `tests/dispatcher.rs` golden harness) for the
engine; Swift Testing (`import Testing`, `@Test`) for the app, including the existing
`ExtractionFidelityTests` (expectations **unmodified**) and a new `GeometryFixtureTests` that
renders PDFs at test time. TDD, RED → GREEN. All fixtures synthetic.
**Target Platform**: iOS **26.0** deployment target — Liquid Glass unconditional; no `#available`
gates. This slice adds **no UI**, so the design-system surface is untouched.
**Project Type**: Mobile app (native iOS UI + native PDF text extraction) over a shared,
platform-agnostic Rust engine
**Performance Goals**: a 42-page / ~100 k-character statement extracts and parses with the
interface responsive throughout and cancellable within **2 s** (SC-008); per-page geometry cost
stays at the shipped volume (one `characterBounds` call per non-separator unit)
**Constraints**: **zero** network I/O on the entire path (Constitution I, non-negotiable); no PDF
engine may enter the core and the reader seam stays `read_lines(lines, full_text, first_row_words)`
(FR-032); money is exact `Decimal` at every hop; extraction is byte-for-byte deterministic (FR-009);
no statement content may reach a log or diagnostic (FR-034); **no real statement or fragment may
enter the repository** (FR-039); words — not glyphs — are the atomic unit of row grouping (measured
constraint, spec Assumptions)
**Scale/Scope**: 10 issuers (6 card, 4 ledger); 13 reference statements, 2–42 pages each; ~1 Swift
type rewritten, ~6 engine functions added/changed, 6 registry renames, ~12 new fixtures, 0 new
screens

**Unresolved**: one — **R15, the AU account-kind claim marker**. It cannot be read from this
repository (the source file is private) and must be supplied by the reference-set holder. It blocks
exactly one task, not the slice; see *Outstanding inputs* below.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` **v2.0.0**.

| Principle | Verdict | Evidence in this design |
|---|---|---|
| **I. Data Privacy & Sovereignty (NON-NEGOTIABLE)** | ✅ PASS | Nothing on this path touches the network: extraction is PDFKit-local, recognition and parsing are pure core functions, and no dependency is added, so `make core-privacy-audit` and `scripts/import-path-audit.sh` are unaffected and must stay green (FR-033, SC-009). No account, entitlement check or server call appears anywhere. No statement content reaches a log or diagnostic (FR-034) — the extractor deliberately reports *nothing* about why a page fell back. The human-run reference pass (research R13) prints **only** an issuer name and a count, writes no file, and touches no store. Fixtures stay synthetic and generated, never redacted (FR-036, FR-039). |
| **II. Local-First Shared Engine** | ✅ PASS | **The core still never opens a PDF** — all reconstruction is platform-side, and the seam stays `read_lines(lines, full_text, first_row_words)` (FR-032). The engine changes are pure functions over text: whitespace normalization, an identity-region projection, and a registry ordering key. No clock, no locale, no I/O, no interior mutability; identical input ⇒ identical output (FR-015). Money remains `rust_decimal::Decimal` and direction remains explicit (FR-019, FR-021). |
| **III. Open-Core & Permissive Licensing** | ✅ PASS | Zero new dependencies, so no licence surface changes and no copyleft risk. No secrets, keys or endpoints. `UIGraphicsPDFRenderer` is a first-party Apple API already used by the test suite. |
| **IV. Native Experience & Accessibility** | ✅ PASS | No UI is added or changed, so no new accessibility surface. The user-visible outcome improves without a new message: statements that reported "no spending" now import their rows, and the honest-failure messages of slice 016 are preserved verbatim (FR-024–FR-027, SC-012). |
| **V. Test-First & Parity** | ✅ PASS | TDD throughout, RED → GREEN. Every existing golden vector must pass with **identical** results (FR-029, SC-005) and `ExtractionFidelityTests` must pass with **unmodified expectations** (FR-028). The new geometry fixtures carry a standing **non-vacuity** assertion — each must fail against the pre-slice extraction path and pass after it (FR-037, SC-011) — which closes the exact blind spot that let eighteen green fixtures coexist with total failure on real statements. All fixtures synthetic; PDFs are rendered at test time and deleted. |
| **VI. Free/Paid Boundary** | ✅ PASS | Statement import and parsing run fully on-device and are therefore **free**. Nothing here is gated, metered or server-validated; no AI, no Account Aggregator, no sync. |
| **Security & Privacy Constraints** | ✅ PASS | No third-party SDK. Fixtures are synthetic, or generated from a value-free signature (synthetic by construction — ADR-0004 amendment). No secrets committed. No new crate to review. |
| **Development Workflow & Quality Gates** | ✅ PASS | Spec Kit flow; the full iOS Local Verification Gate applies (`make core-lint`, `make core-test`, `make lint`, `make ios-test`, `make import-audit`, `make core-privacy-audit`). The core changes, so `make core-xcframework` must precede `tuist generate` — `make ios-gen` already encodes this. |

**Result: PASS — no violations, no justifications required. Complexity Tracking is empty.**

### Post-Phase-1 re-evaluation

Re-checked after `research.md`, `data-model.md`, `contracts/` and `quickstart.md`:

- ✅ Still **zero** new dependencies, **zero** FFI shape changes, **zero** schema changes. The
  `issuer_id` persistence the spec asked planning to price is **explicitly deferred** (research R9)
  with its rationale and its "must land before first release" condition recorded — the encrypted
  store is untouched by an extraction slice.
- ✅ The engine stays pure. The identity region is a deterministic projection computed per
  `detect_issuer` call; `evidence_rank` is inserted *after* `kind_rank`, so the three shipped
  fixtures that are claimed by two readers resolve exactly as they do today (FR-013).
- ⚠️ **One ordering constraint is mandatory, not advisory** (research R16): recognition must merge
  **before** reshaping. The prototype measured the reverse order producing 11 of 13 documents
  unrecognised. Recognition-first is safe because the new matching is a *superset* of today's for
  every shipped fixture, so no commit on `main` is ever worse than its predecessor. The PR split
  below encodes this.
- ⚠️ **One widening is genuinely dangerous and is fenced**: whitespace-insensitive matching widens
  every bare-institution marker at once (`hdfc_bank::CLAIM_ALL = ["HDFC"]`), and the AU statement is
  measured to contain `HDFC` inside a UPI description. The identity-region projection removes that
  class, and gate **G7** (a synthetic statement for issuer X whose descriptions name issuer Y) ships
  in the **same PR** as the widening — never after it.
- ✅ FR-016 is implemented as a **test invariant only** (research R10), honouring the spec's
  instruction that it must never cause a reader to decline a statement of its own kind.
- ✅ No new user-visible message is added, so SC-012 holds by construction.

**Result: PASS. Complexity Tracking remains empty.**

## Project Structure

### Documentation (this feature)

```text
specs/017-column-major-pdf/
├── plan.md                       # This file
├── spec.md                       # FINAL — Clarifications Q1–Q4 are settled constraints
├── research.md                   # Phase 0 — R1–R16, decisions with source evidence
├── data-model.md                 # Phase 1 — extraction values, registry records, fixture vectors
├── contracts/
│   ├── extraction-seam.md        # Phase 1 — the platform's obligation to the engine
│   ├── engine-recognition.md     # Phase 1 — claim matching, identity region, registry
│   └── geometry-fixture.md       # Phase 1 — the generated-fixture format and its gates
├── quickstart.md                 # Phase 1 — build order, PR split, verification commands
├── checklists/
│   └── requirements.md           # Pre-existing spec-quality checklist
└── tasks.md                      # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
core/crates/kaname-core/
├── src/statement/
│   ├── claim.rs                  # NEW — normalize_for_claim, identity_region, header_region
│   ├── registry.rs               # CHANGED — ClaimEvidence, 6 renames, specificity ordering
│   ├── line_reader.rs            # CHANGED — claims() over the identity region + normalization
│   ├── ledger_reader.rs          # CHANGED — claims_ledger() likewise
│   ├── au_bank.rs                # CHANGED — CLAIM_ANY gains the header phrase (blocked: R15)
│   ├── hdfc.rs                   # CHANGED — hdfc_claims() via the shared path; product-proven
│   ├── sbi.rs                    # CHANGED — BANK_CODE "SBI_CARD" → "SBI" (FR-053)
│   └── mod.rs                    # CHANGED — expose claim.rs
└── tests/
    ├── dispatcher.rs             # CHANGED — renamed ids; gates G1–G7
    └── parity.rs                 # UNCHANGED expectations (FR-029); ids updated where asserted

ios/
├── Sources/Import/
│   └── StatementTextExtractor.swift      # REWRITTEN core: zones → bands → lines + all-page lineWords
└── Tests/
    ├── ExtractionFidelityTests.swift     # EXTENDED — both-hazards document; existing expectations untouched
    ├── StatementTextExtractorTests.swift # EXTENDED — losslessness, determinism, band cap, fallback
    ├── GeometryFixtureTests.swift        # NEW — renders fixtures/geometry/*.json, asserts A1–A7
    ├── GeometryFixtureRenderer.swift     # NEW — column-major PDF renderer (test-only)
    └── ReferenceSetVerification.swift    # NEW — skipped unless KANAME_REFERENCE_DIR is set

fixtures/geometry/                        # NEW — 10 issuer vectors + both-hazards + cross-bank
Makefile                                  # CHANGED — `reference-check` target (local, opt-in)
```

**Structure Decision**: the shipped two-tier layout is unchanged — a platform-agnostic Rust engine
in `core/crates/kaname-core` and a native SwiftUI/PDFKit app in `ios/`, with golden vectors in
`fixtures/`. This slice deliberately puts **all** geometry work on the platform side of the seam and
**all** recognition work on the engine side, because that is exactly where the constitution's
platform boundary already draws the line (FR-032). No new module tier, no new target, no new
package, no new directory outside `fixtures/geometry/`.

## Delivery order (mandatory, not advisory)

| PR | Scope | Why this order |
|---|---|---|
| **A — Recognition** | `claim.rs`, `line_reader::claims`, `ledger_reader::claims_ledger`, identity region, gates G6/G7 | Must land **first** (research R16). It is a superset of today's matching for every shipped fixture, so `main` is never worse. Shipping reshaping first is the measured 11-of-13 regression. |
| **B — Registry** | `ClaimEvidence`, six renames, `sbi::BANK_CODE`, specificity ordering, gates G1–G5 | Independent of extraction; renames plus one ordering key. Lands before the fixtures that reference the new ids. |
| **C — Extraction** | `StatementTextExtractor` rewrite, all-page `lineWords`, per-page fallback, extended fidelity + extractor tests | The behavioural heart. Safe only on top of A. |
| **D — Evidence** | `fixtures/geometry/*`, renderer, `GeometryFixtureTests` (A1–A7 incl. non-vacuity), both-hazards + cross-bank vectors | Needs B's ids and C's behaviour to assert against. |
| **E — Gates** | `make reference-check`, the human-run reference pass, perf/cancellation verification, privacy audits, `AGENTS.md`/HANDOFF updates | Closes SC-002, SC-008, SC-009, SC-010. |

The AU marker (contract C5 / research R15) rides in **B** if its literal is available by then,
otherwise in **E**, otherwise it is deferred to its own follow-up without blocking anything else.

## Outstanding inputs

| Item | Owner | Blocks | Fallback if unavailable |
|---|---|---|---|
| **R15 — the exact account-kind literal `AU-statment-savings.pdf` prints in its header** | The reference-set holder (the only person with the file) | One task: `au_bank::CLAIM_ANY` + its synthetic fixture | Defer that task. The file keeps reporting "format not recognised yet" (FR-025) — honest, not wrong. Every other requirement is unaffected. |
| **R13 — the human-run reference-set pass** | The reference-set holder | Slice sign-off (SC-002) only | None. Spec Q3 chose Option A explicitly: CI alone cannot close this slice. |

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified.

**Empty — the Constitution Check passed with no violations, before and after Phase 1.**
