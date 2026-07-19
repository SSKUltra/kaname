# Specification Quality Checklist: Reconcile a Credit-Card Statement Against Its Own Printed Totals On-Device (the Credit-Card Counterpart to the Shipped Bank-Ledger Balance-Chain; Completes the Ported Reconciliation Layer)

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-07-19
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

- **Validation result**: All items pass; the specification is ready for `/speckit.clarify` or `/speckit.plan`. Zero `[NEEDS CLARIFICATION]` markers were needed. The behaviour is **fully pinned** by the proven web engine (Constitution Principle V): `reconciliation.py`, the reconciliation unit tests (`test_reconciliation.py`), the statement-reconciliation integration tests (`test_statement_reconciliation.py`), and the two readers' printed-total scrapes (`yes_kiwi.py`, `iob.py`). Open details were resolved as documented Assumptions (informed defaults consistent with the web engine and the already-shipped bank-ledger balance-chain) rather than questions.
- **Judgment call — three-way outcome is a behavioural requirement, exact typing deferred**: The spec makes "three distinct, non-conflatable outcomes, with the neutral 'no balance' state explicitly ≠ NEEDS_REVIEW" a hard requirement (FR-001, FR-004, US3), while explicitly deferring the concrete on-device representation (optional two-variant status vs three-variant enum) to `/speckit.plan` (Assumptions). This is a user-facing behavioural distinction ("we couldn't check" vs "we checked and it's wrong"), not an implementation detail, and it is verifiable by review of the three verdict vectors — pinned directly by the web engine's `RECONCILED` / `NEEDS_REVIEW` / `None` contract.
- **Judgment call — the ₹1.00 tolerance and tier precedence are pinned data**: The ₹1.00 rounding tolerance (inclusive), the primary-over-fallback precedence, the "fallback needs both opening and closing" rule, and the "either printed total may be present independently" rule are stated as testable behaviours (FR-005–FR-009, SC-004/005/007/008, Edge Cases). These are the byte-for-byte behavioural constants from `reconciliation.py`, not prescriptive engine technology.
- **Judgment call — behavioural characterization data**: The spec quotes concrete synthetic values (read debit sums 350.50 / 350.00, printed totals 350.50 / 999.99 / 900.00; the fallback's 500.00 / 200.00 / opening 1,000.00 / closing 1,300.00 → +300.00; the IOB `ACCOUNT SUMMARY` row "345.50 1,000.00 3,500.00 0 2,845.50" → credits 1,000.00 / debits 3,500.00; the Yes "Rs. 100.00 Dr" / "Rs. 9,000.00 Cr"). These are the constitution's golden-fixture parity vectors (Principle V) — behavioural acceptance data drawn from the pinned web unit/integration tests and the existing Kaname Yes/IOB fixtures — not implementation details, and all data is synthetic/redacted (fabricated merchants, amounts, and masked card numbers).
- **Judgment call — statement-format tokens are data, not implementation**: The printed-total label shapes ("Current Purchases … Rs. X Dr", "Payment & Credits Received … Rs. Y Cr", the `ACCOUNT SUMMARY` values row and its 2nd=credits / 3rd=debits positions) describe the *statement's own printed format* the engine must recognize — behavioural inputs identical in kind to the prior reader slices quoting their own row formats. They prescribe no regex/module/API in the requirements themselves.
- **Judgment call — lifting the two readers' carve-out is in scope and is a data-surfacing outcome**: US2, FR-011–FR-014, and SC-011 require the Yes/Kiwi and IOB readers to surface their printed debit/credit totals (removing the deferred carve-out those modules currently carry), while guaranteeing every other parsed field is byte-for-byte unchanged. This is a verifiable output-model outcome (two new fields populated by exactly two readers), stated behaviourally, and bounded so it cannot regress the existing reader fixtures.
- **Judgment call — the four no-total readers producing neutral is a verification target, not a gap**: FR-015, US3, and SC-006 assert that ICICI, HDFC, SBI, and Federal/Scapia print no totals and therefore reconcile to the neutral outcome, and that this is correct behaviour to verify (the slice must not invent totals). This is a scope/correctness boundary stated in user-facing terms, matching the web engine where only two of six CC readers print totals.
- **Judgment call — reconciliation as the counterpart to the shipped balance-chain, no new infra**: US6, FR-016, and SC-017 frame the check as the credit-card analogue of the landed bank-ledger balance-chain, delivered as a check + two fields + two reader enrichments + fixture extensions + one bridge export + parity + a Swift test, with no new runtime dependency. This is a scope/architecture-scaling outcome (the thesis that the ported reconciliation layer completes cleanly) stated in reviewable terms; concrete module layout is deferred to `/speckit.plan` (Assumptions).
- **Judgment call — rows-retained and audit-detail are first-class guarantees**: US5, FR-003, FR-010, SC-009, and SC-010 require that reconciliation never drops/mutates/reorders rows and that every verdict carries an explaining audit detail. These mirror the web integration test's assertion that rows are retained even on NEEDS_REVIEW, and are stated as verifiable, user-facing outcomes (no data loss; an explainable verdict) rather than implementation details.
- **Judgment call — persistence is explicitly out of scope**: The web integration test persists a `reconciliation_status` onto a statement row; the spec deliberately ports only the **pure check** plus parity and bridge reachability, and lists persistence (and any `uploaded_statements`-style schema) under Out of Scope. This keeps the slice bounded to the engine, consistent with the per-slice convention that persistence/DB is a later milestone. The `reconciliation_status` column name appears only in Out of Scope, describing the deferred web-side artifact, not prescribing on-device technology.
- **Judgment call — technology proper nouns are confined to non-prescriptive locations**: The only technology names in the document are intentional and confined to the verbatim **Input** line, the **Assumptions / Dependencies / Out of Scope** sections (where locked decisions such as UniFFI, exact-decimal money, native PDFKit text extraction, Apache-2.0, and deferred scope like SQLCipher are recorded, each noted as belonging to `/speckit.plan`), the constitution-mandated gate names (privacy-egress test, iOS Local Verification Gate, CI), and the web-engine source-of-truth file names used as the parity reference. No engine module/type/regex is prescribed in the requirements themselves.
- **Judgment call — the Rust↔Swift bridge reachability outcome (US8 / FR-019 / SC-015)**: The bridge (the Rust core reached from the native app via UniFFI) is **locked architecture** from Constitution Principle II and the shipped P1 bridge slice, not a choice made here. The user explicitly named "reachability across the Rust↔Swift bridge" as an in-scope deliverable of this slice, so US8, FR-019, and SC-015 state it as the measurable outcome that the app can call the reconcile check and receive the verdict — mirroring how the already-shipped balance-chain check is exposed. This matches the established repo convention (e.g., slice 011's SC-015 "reachable over the existing UniFFI bridge to Swift"), where bridge reachability is treated as a constitution-mandated, verifiable outcome rather than an implementation choice.
- **Judgment call — accessibility & privacy vocabulary**: References to Human Interface Guidelines, Dynamic Type, Dark Mode, VoiceOver, "zero network I/O", and "no telemetry" are treated as user-facing outcomes mandated by the constitution's Privacy and Native Experience principles, not as framework/API implementation choices.
- Items marked incomplete would require spec updates before `/speckit.clarify` or `/speckit.plan`; none are incomplete.
