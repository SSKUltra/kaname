# Specification Quality Checklist: Import an SBI Card Credit-Card Statement On-Device (Third Real Parser, Zero New Engine Infrastructure)

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-07-15
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

- **Validation result**: All items pass; the specification is ready for `/speckit.clarify` or `/speckit.plan`. Zero `[NEEDS CLARIFICATION]` markers were needed — the feature description, the constitution, the two planning docs (`docs/kaname-ios-plan.md`, `docs/HANDOFF.md`), the just-landed ICICI and HDFC slices (`specs/002-icici-cc-parser/`, `specs/003-hdfc-cc-parser/`), and the web-engine source of truth (`sbi_card.py` + the CC characterization test) made the context complete, so open details were resolved as documented Assumptions (informed defaults) rather than questions.
- **Judgment call — behavioural characterization data**: The spec quotes the two synthetic SBI rows and their expected outputs (dates, amounts, directions, descriptions) and the metadata values (billing-period start/end, and the deliberately absent card last-4). These are the constitution's golden-fixture parity vector (Principle V) — behavioural acceptance data, not implementation details — and all data is synthetic/redacted (fabricated merchants, amounts, and a masked card number). The values were confirmed against a live run of the web engine's shared helpers.
- **Judgment call — statement-format tokens are data, not implementation**: The layout shape (`DD Mon YY <details> <amount> C|D`), the terminal direction markers (`C`/`D` with the legend C = Credit, D = Debit), and the metadata anchors (`Statement Period: … to …`, `Credit Card Number`, and the issuer markers `SBI Card` / `GSTIN of SBI Card`) describe the *statement's own printed format* that the engine must recognize — behavioural inputs, exactly like ICICI/HDFC quoting their own row formats. They prescribe no engine technology (no regex/module/API is specified in the requirements themselves).
- **Judgment call — "zero new engine infrastructure" vocabulary**: User Story 2, FR-017, and SC-010 assert that SBI adds no new *shared* engine helper and is delivered as a single-layout reader configuration plus a fixture, two bridge exports, and one parity row. This is a scope/architecture-scaling outcome (the thesis of the slice — that incremental-by-bank ingestion scales) stated in reviewable, verifiable terms, deliberately contrasted with the month-end/composite helpers HDFC required. It prescribes no concrete module layout or code — those are deferred to `/speckit.plan` (Assumptions).
- **Judgment call — the absent-last-4 rule**: FR-012, SC-003, and User Story 4 capture that when the masked card number exposes fewer than four trailing digits (`XXXX XXXX XXXX XX61`), the last-4 is left absent and never fabricated. This is a user-facing correctness guarantee (no invented account identifiers), not an implementation detail, and is verified directly by the golden vector.
- **Judgment call — technology proper nouns**: The only technology names in the document are intentional and confined to non-prescriptive locations: the verbatim **Input** line; the **Assumptions / Dependencies / Out of Scope** sections (where locked decisions such as UniFFI, native PDFKit text extraction, Apache-2.0, and deferred scope like SQLCipher are recorded, each noted as belonging to `/speckit.plan`); and the constitution-mandated gate names (privacy-egress test, iOS Local Verification Gate, CI). The parse-seam shape `read_lines(lines, full_text)` appears only in Assumptions as a locked contract inherited from the source engine and the ICICI/HDFC slices, and the bank code `SBI_CARD` is recorded as a locked identity value.
- **Judgment call — accessibility & privacy vocabulary**: References to Human Interface Guidelines, Dynamic Type, Dark Mode, VoiceOver, "zero network I/O", and "no telemetry" are treated as user-facing outcomes mandated by the constitution's Privacy and Native Experience principles, not as framework/API implementation choices.
- Items marked incomplete would require spec updates before `/speckit.clarify` or `/speckit.plan`; none are incomplete.
