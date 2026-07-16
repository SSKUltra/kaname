# Specification Quality Checklist: Import a Federal Bank / Scapia Credit-Card Statement On-Device (Fifth and Final Credit-Card Parser — the Most Distinctive Layout, Zero New Engine Infrastructure)

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-07-16
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

- **Validation result**: All items pass; the specification is ready for `/speckit.clarify` or `/speckit.plan`. Zero `[NEEDS CLARIFICATION]` markers were needed — the feature description, the constitution, the two planning docs (`docs/kaname-ios-plan.md`, `docs/HANDOFF.md`), the four just-landed ICICI/HDFC/SBI/Yes slices (`specs/002-icici-cc-parser/` … `specs/005-yes-cc-parser/`), and the web-engine source of truth (`federal_scapia.py` + the shared helpers + the CC characterization test) made the context complete, so open details were resolved as documented Assumptions (informed defaults) rather than questions. The two authoritative "already handled" claims were verified directly in the repo: the shared date parser already carries both `%d-%m-%Y` ("Scapia/Federal") and the space-stripped `%d%b%Y` ("Scapia billing cycle") formats, and the shared polarity classifier already defaults to debit with a credit-keyword fallback (`core/crates/kaname-core/src/statement/common.rs`, `.../polarity.rs`).
- **Judgment call — the distinctive-layout tokens are data, not implementation**: The layout shape (`DD-MM-YYYY<sep>HH:MM <description> [+]₹<amount>`), the middle-dot date/time separator (U+00B7) matched **encoding-robustly** as any single character, the rupee-symbol prefix (₹, U+20B9), and Scapia's leading-`+` credit notation describe the *statement's own printed format* that the engine must recognize — behavioural inputs, exactly like ICICI/HDFC/SBI/Yes quoting their own row formats. They prescribe no engine technology (no regex/module/API is specified in the requirements themselves). The "encoding-robust single-character separator" requirement (FR-004) is a user-facing robustness outcome (the row is recognized regardless of which glyph native extraction produced for the dot), verifiable by test, not a prescribed implementation.
- **Judgment call — the Scapia-specific direction rule**: Federal has **no** `Dr`/`Cr` column; direction is set by a leading `+` (credit) and otherwise falls back to the shared description-language classifier (default debit). User Story 3, FR-010/FR-011, SC-004, and the Assumptions state this as a behavioural precedence rule (statement notation first, description language second, amount sign never), verifiable against the golden vector — not as prescribed code. The golden row `Billpayment Payment +₹324.45` is a credit **only** because of the `+` (its description is not a recognized credit phrase), which is exactly the behaviour the rule pins.
- **Judgment call — "zero new engine infrastructure" / "most distinctive layout" vocabulary**: User Story 2, FR-018, SC-011, and SC-012 assert that Federal — despite being the hardest of the five layouts — adds no new *shared* engine helper and is delivered as a single-layout reader configuration (row pattern + direction rule) plus a fixture, two bridge exports, and one parity row, completing the five-issuer credit-card set. This is a scope/architecture-scaling outcome (the thesis of the slice — that incremental-by-bank ingestion scales even to the hardest layout) stated in reviewable, verifiable terms. It prescribes no concrete module layout or code — those are deferred to `/speckit.plan` (Assumptions).
- **Judgment call — behavioural characterization data**: The spec quotes the two synthetic Federal rows and their expected outputs (dates 2026-04-29 / 2026-04-24, amounts 324.45 / 2353.13, directions credit/debit, descriptions `Billpayment Payment` / `ExampleMerchantTokyo`) and the metadata values (billing cycle 2026-04-20 → 2026-05-19 from the space-stripped range `20Apr2026-19May2026`, and card last-4 `4836` from the fully-masked `XXXXXXXXXXXX4836`). These are the constitution's golden-fixture parity vector (Principle V) — behavioural acceptance data, not implementation details — and all data is synthetic/redacted (fabricated merchants, amounts, and a fully-masked card number). The date/time separator is the middle dot U+00B7 and the currency symbol is the rupee sign U+20B9.
- **Judgment call — statement metadata rules are format facts**: The space-stripped billing range (`DDMonYYYY-DDMonYYYY`) and the anchor-less fully-masked card number (`XXXXXXXXXXXX4836`) describe the printed statement's own metadata format (FR-012/FR-013, User Story 4), behavioural inputs like the other banks' metadata anchors. That both parse via the shared `%d%b%Y`/last-4 helpers is a reuse/accuracy claim, stated as a testable outcome rather than prescribed implementation.
- **Judgment call — technology proper nouns**: The only technology names in the document are intentional and confined to non-prescriptive locations: the verbatim **Input** line; the **Assumptions / Dependencies / Out of Scope** sections (where locked decisions such as UniFFI, native PDFKit text extraction, Apache-2.0, and deferred scope like SQLCipher are recorded, each noted as belonging to `/speckit.plan`); and the constitution-mandated gate names (privacy-egress test, iOS Local Verification Gate, CI). The parse-seam shape `read_lines(lines, full_text)` appears only in Assumptions as a locked contract inherited from the source engine and the prior slices, and the bank code `FEDERAL` is recorded as a locked identity value. SC-011's "two UniFFI exports" mirrors the accepted phrasing in the landed ICICI/HDFC/SBI/Yes success criteria.
- **Judgment call — accessibility & privacy vocabulary**: References to Human Interface Guidelines, Dynamic Type, Dark Mode, VoiceOver, "zero network I/O", and "no telemetry" are treated as user-facing outcomes mandated by the constitution's Privacy and Native Experience principles, not as framework/API implementation choices.
- Items marked incomplete would require spec updates before `/speckit.clarify` or `/speckit.plan`; none are incomplete.
