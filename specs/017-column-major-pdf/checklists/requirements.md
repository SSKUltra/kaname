# Specification Quality Checklist: Column-Major PDF Extraction Fidelity

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-13
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- **Three open questions are recorded under `## Clarifications` and are deliberately unanswered** (Q1: the SBI bank-account statement; Q2: the unrecognised HDFC savings variant; Q3: what counts as proof when the evidence can never be committed). They are scope/process decisions for the product owner, not underspecification: the spec is complete and testable under either answer to each, and each question states its implications. `/speckit.plan` SHOULD NOT run until they are answered, because Q1 and Q2 change what ships and Q3 changes the release gate.
- Iteration 1 findings, all fixed before this checklist was marked complete:
  - US4 acceptance scenario 3 was stated as a negative that read as its own opposite ("its extracted lines are unchanged in a way that alters any transaction"). Rewritten as a positive, testable assertion.
- Deliberate, reviewed exceptions to "no implementation details":
  - The spec names `fixtures/` and `ios/Tests/ExtractionFidelityTests.swift` in Dependencies and FR-028/FR-029. These are named as **existing contracts this slice must not break**, not as design. Naming them is what makes the non-regression requirement verifiable.
  - The spec states that words, not glyphs, are the unit of row grouping (Assumptions). This is recorded as an empirically established **constraint on any solution** — glyph-level grouping was measured to produce scrambled output — rather than a design choice, so plan time does not rediscover it at cost.
  - `Dr`/`Cr`, `DD-MMM-YYYY` and `DD/MM/YYYY` appear as they are **printed on the statements themselves**; they are user-visible document content, not internals.
- Constitution alignment verified: Principle I (zero network, on-device — FR-033, SC-009), Principle II (no PDF engine in the core, reader seam unchanged — FR-032; exact decimal money — FR-021), Principle V (test-first, golden-fixture parity, synthetic fixtures — FR-029, FR-036 – FR-039, SC-005, SC-010, SC-011).
