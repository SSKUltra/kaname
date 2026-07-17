# Specification Quality Checklist: Import an Indian Overseas Bank (IOB) Credit-Card Statement On-Device (Sixth & Final Credit-Card Parser, Zero New Engine Infrastructure; Corrects IOB Miscategorization)

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-07-17
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

- **Validation result**: All items pass; the specification is ready for `/speckit.clarify` or `/speckit.plan`. Zero `[NEEDS CLARIFICATION]` markers were needed — the feature description, the captured ground-truth vector, the constitution, the two roadmap docs (`docs/kaname-ios-plan.md`, `docs/HANDOFF.md`), the landed single-layout credit-card slices (`specs/004-sbi-cc-parser/`, `specs/005-yes-cc-parser/`) whose pattern IOB mirrors, and the web-engine source of truth (`iob.py` plus the shared line-reader, `common`, and polarity helpers) made the context complete, so open details were resolved as documented Assumptions (informed defaults) rather than questions.
- **Judgment call — the reconciliation carve-out (mirrors Yes)**: The web engine's IOB reader additionally scrapes the `ACCOUNT SUMMARY` printed `Payment / Credits` and `Purchases / Debits` totals for a future reconciliation feature. User Story 5, FR-013, SC-013, the Assumptions ("Reconciliation carve-out"), and Out of Scope all state that these printed-total fields MUST NOT be ported into this slice's output model. This is a scope/boundary guarantee (a user-facing "we ship only what's finished" outcome), not an implementation detail, and it is verifiable by review of the output model and the golden vector's expected output — consistent with the already-landed credit-card fixtures (none carry printed totals) and specifically with the Yes carve-out precedent.
- **Judgment call — the documentation correction is a first-class deliverable**: User Story 6, FR-014, FR-015, and SC-014 require moving IOB from the bank-account reader list to the credit-card reader list in `docs/HANDOFF.md` and `docs/kaname-ios-plan.md`. This is a verifiable documentation-correctness outcome (the roadmap must reflect that IOB is a credit-card reader with no ledger reader), stated in user-facing, reviewable terms. The file names are the artifacts being corrected (the deliverable itself), not prescriptive engine technology.
- **Judgment call — behavioural characterization data**: The spec quotes the two synthetic IOB rows and their expected outputs (dates, amounts, directions, descriptions) and the metadata values (billing-cycle end 2026-04-20, absent period start, card last-4 `0042`). These are the constitution's golden-fixture parity vector (Principle V) — behavioural acceptance data, not implementation details — and all data is synthetic/redacted (fabricated merchants `ExampleRefundMerchant` / `ExampleStorePurchase`, fabricated amounts, and a masked card number `123456XXXXXX0042`). The values were confirmed against the captured web-engine ground-truth vector.
- **Judgment call — statement-format tokens are data, not implementation**: The layout shape (`DD-MON-YYYY <merchant> <amount> Dr|Cr`), the uppercase-month date (`31-MAR-2026`), the terminal two-letter direction markers (`Cr` = credit, `Dr` = debit), the single statement-date label (`Stmt Date : …`), the inline masked-PAN line printed next to limit figures (`123456XXXXXX0042 16000 25091.5`), the `Credit Card Number` anchor, and the issuer markers (`INDIAN OVERSEAS BANK`, `iobnet.co.in`) describe the *statement's own printed format* that the engine must recognize — behavioural inputs, exactly like the prior slices quoting their own row formats. They prescribe no engine technology (no regex/module/API is specified in the requirements themselves).
- **Judgment call — the inline masked-PAN anchoring outcome**: FR-011, SC-004, User Story 4, and the Edge Cases state the card last-4 (`0042`) is taken from the masked card number via the `Credit Card Number` anchor and NOT from the adjacent limit figures (`16000` / `25091.5`) on the same line. This is a testable correctness outcome specific to IOB's inline layout (the distinctive metadata risk of this slice), stated behaviourally rather than as a regex/algorithm.
- **Judgment call — statement-date-only cycle end**: FR-010, SC-003, and User Story 4 state the billing-cycle end comes from the lone `Stmt Date` and that the period start is left unset because IOB prints no period range. This is an accuracy/"never fabricate" outcome (contrasted with Yes/SBI, which print an explicit period range), stated as a verifiable behaviour.
- **Judgment call — "zero new engine infrastructure" vocabulary**: User Story 2, FR-019, and SC-012 assert that IOB adds no new *shared* engine helper and is delivered as a single-layout reader configuration plus a fixture, two bridge exports, one parity row, and the two doc corrections. This is a scope/architecture-scaling outcome (the thesis of the slice — that incremental-by-bank ingestion scales, now completing the reader set) stated in reviewable, verifiable terms, mirroring the SBI and Yes clean single-layout drop-ins. It prescribes no concrete module layout or code — those are deferred to `/speckit.plan` (Assumptions).
- **Judgment call — "already handled" date/polarity claims**: The spec states the case-insensitive `%d-%b-%Y` date format (so uppercase `MAR`/`APR` parse) and the two-letter `Dr`/`Cr` markers are already handled by the shared date parser and polarity classifier. This is an accuracy/scope claim about reuse, stated as a testable reuse outcome (User Story 2 scenarios) rather than as prescriptive implementation.
- **Judgment call — technology proper nouns**: The only technology names in the document are intentional and confined to non-prescriptive locations: the verbatim **Input** line; the **Assumptions / Dependencies / Out of Scope** sections (where locked decisions such as UniFFI, native PDFKit text extraction, Apache-2.0, and deferred scope like SQLCipher are recorded, each noted as belonging to `/speckit.plan`); the constitution-mandated gate names (privacy-egress test, iOS Local Verification Gate, CI); and the two roadmap file names that are the documentation-correction deliverable. The parse-seam shape `read_lines(lines, full_text)` appears only in Assumptions as a locked contract inherited from the source engine and the prior slices, and the bank code `IOB` (with `account_kind="credit_card"`) is recorded as a locked identity value.
- **Judgment call — accessibility & privacy vocabulary**: References to Human Interface Guidelines, Dynamic Type, Dark Mode, VoiceOver, "zero network I/O", and "no telemetry" are treated as user-facing outcomes mandated by the constitution's Privacy and Native Experience principles, not as framework/API implementation choices.
- Items marked incomplete would require spec updates before `/speckit.clarify` or `/speckit.plan`; none are incomplete.
