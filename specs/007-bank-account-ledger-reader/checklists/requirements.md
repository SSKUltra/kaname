# Specification Quality Checklist: Read a Bank-Account (Savings/Current) Statement On-Device — the Balance-Ledger Reader Base + Balance-Chain Integrity + ICICI as the First Reference Reader (Second Reader Family)

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

- **Validation result**: All items pass; the specification is ready for `/speckit.clarify` or `/speckit.plan`. Zero `[NEEDS CLARIFICATION]` markers were needed — the feature description (including the full reference ground truth: three rows with dates/amounts/directions/descriptions/balances/deltas/serials, the ₹1.00 tolerance, the four `direction_source` values, printed opening/closing balances, billing period, account last-4, and the RECONCILED balance-chain result), the constitution, the two planning docs (`docs/kaname-ios-plan.md`, `docs/HANDOFF.md`), the five just-landed credit-card slices (`specs/002-icici-cc-parser/` … `specs/006-federal-cc-parser/`), and the web-engine source of truth (`_ledger_reader.py` / `BalanceLedgerStatementReader`, `balance_chain.py`, `icici_bank.py`, plus the shared `base.py` / `_common.py` / `polarity.py`) made the context complete, so open details were resolved as documented Assumptions (informed defaults) rather than questions.
- **Verified against the repo**: The core reason this slice exists — that the credit-card seam cannot read a bank ledger — was confirmed directly: the shared line reader derives direction from a Dr/Cr indication (`core/crates/kaname-core/src/statement/line_reader.rs`, `.../polarity.rs`), which a Withdrawal/Deposit/Balance ledger does not carry. The shared date parser **already** carries the ICICI-savings date formats (`%B %d, %Y` full-month header and `%d.%m.%Y` dotted anchor date) in `core/crates/kaname-core/src/statement/common.rs`, and the roadmap already names the `BalanceLedgerStatementReader`, `balance_chain.check`, and `icici_bank` as the next family (`docs/kaname-ios-plan.md` §3.1, `docs/HANDOFF.md` §3) — so the ground truth aligns with the codebase's intent.
- **Judgment call — the ledger behaviour is data, not implementation**: The direction-from-delta rule (fall ⇒ debit, rise ⇒ credit), the amount-as-independent-check (`amount == |curr_balance − prev_balance|` within ₹1.00), the anchor shape (`… <amount> <balance>` single-amount for ICICI, plus a two-column Withdrawal/Deposit/Balance template the base must support), the narration-stitching rule (line above + lines below, skipping other anchors and printed-balance lines), and the row-1 bootstrap precedence describe the *statement's own printed format and the engine's proven behaviour* the reader must reproduce — behavioural inputs/outcomes, exactly like the credit-card specs quoting their own row formats. They prescribe no engine technology (no regex/module/type is specified in the requirements themselves); those are deferred to `/speckit.plan` (Assumptions).
- **Judgment call — `direction_source`, RECONCILED/NEEDS_REVIEW, and suspect vs errored are domain vocabulary**: The `direction_source` enum (`opening_balance` | `balance_delta` | `row1_xposition` | `row1_provisional`), the balance-chain statuses (RECONCILED / NEEDS_REVIEW), and the suspect-vs-errored distinction are behavioural acceptance labels ported from the web engine's balance-chain, verifiable against the golden vector — not prescribed code. NEEDS\_REVIEW (with an underscore) is a status literal, not a `[NEEDS CLARIFICATION]` marker.
- **Judgment call — row-1 geometry / the `first_row_words` seam**: The spec states that the native platform supplies the first transaction row's word geometry (each word with its x-position) and that the Rust core never opens a PDF (constitution platform boundary). That geometry x-coordinates are layout points which *may* be floating-point — while money is always an exact decimal — is a constitution-mandated data-type outcome (Principle II), stated as a testable outcome, not a framework choice. The seam shape `read_lines(lines, full_text, first_row_words)` appears only in Assumptions as a locked contract inherited from the source engine and the constitution.
- **Judgment call — the savings-vs-credit-card `claims` gate**: ICICI issues both document types under one issuer, so the bank reader's gate requires the ICICI bank code + all required markers + any optional marker, and must reject an ICICI credit-card statement (User Story 7, FR-001/FR-002, SC-007). This is a behavioural routing rule (verifiable by asking the gate about each document), stated in reviewable terms; the concrete marker strings and the `(bank_code, account_kind)` registry key are deferred to `/speckit.plan`.
- **Judgment call — behavioural characterization data**: The spec quotes the three synthetic ICICI savings rows and their expected outputs (2025-06-16 / 5000.00 / debit / `UPI/512345/ALICE STORE/Payment`; 2025-06-18 / 50000.00 / credit / `NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY`; 2025-06-20 / 2000.00 / debit / `ATM CASH WITHDRAWAL`), the balances (95000.00, 145000.00, 143000.00) and deltas (−5000.00, +50000.00, −2000.00), the printed opening/closing balances (100000.00 / 143000.00), the billing period (2025-06-16 → 2025-07-15), the account last-4 (`3456`), and the RECONCILED balance-chain result. These are the constitution's golden-fixture parity vector (Principle V) — behavioural acceptance data, not implementation details — and all data is synthetic/redacted (fabricated payers, amounts, and account number).
- **Judgment call — the account last-4 extractor**: The account last-4 is the trailing four digits of the printed account number via a bank-account-aware extractor, explicitly distinct from the credit-card masked-PAN matcher (FR-022, User Story 6). This is an accuracy/behaviour claim (right derivation for a bank account), stated as a testable outcome rather than prescribed code.
- **Judgment call — technology proper nouns**: The only technology names in the document are intentional and confined to non-prescriptive locations: the verbatim **Input** line; the **Assumptions / Dependencies / Out of Scope** sections (where locked decisions such as UniFFI, native PDFKit text/geometry extraction, Apache-2.0, `rust_decimal`-style decimal money, and deferred scope like SQLCipher are recorded, each noted as belonging to `/speckit.plan`); and the constitution-mandated gate names (privacy-egress test, iOS Local Verification Gate, CI). SC-011's "reachable over the UniFFI bridge to Swift" mirrors the accepted phrasing in the landed ICICI/HDFC/SBI/Yes/Federal success criteria.
- **Judgment call — accessibility & privacy vocabulary**: References to Human Interface Guidelines, Dynamic Type, Dark Mode, VoiceOver, "zero network I/O", "no new networking dependency", and "no telemetry" are treated as user-facing outcomes mandated by the constitution's Privacy and Native Experience principles, not as framework/API implementation choices.
- **Scope-boundary note on IOB (recorded for the reviewer, not a blocker)**: This spec records IOB as **out of scope** and characterizes it as a **credit-card** reader, per the feature description's explicit framing. The repo planning docs (`docs/kaname-ios-plan.md` §3.1 and `docs/HANDOFF.md` §3) currently list `iob.py` **under the bank-account readers**. This is a classification discrepancy between the feature input and the docs, but it does **not** affect this slice's scope (IOB is deferred to a later slice either way), so it is surfaced here rather than raised as a `[NEEDS CLARIFICATION]` marker.
- Items marked incomplete would require spec updates before `/speckit.clarify` or `/speckit.plan`; none are incomplete.
