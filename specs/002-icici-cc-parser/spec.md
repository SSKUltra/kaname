# Feature Specification: Import an ICICI Credit-Card Statement On-Device (First Real Parser)

**Feature Branch**: `002-icici-cc-parser`  
**Created**: 2026-07-08  
**Status**: Draft  
**Milestone**: P2 (first slice) — the first real statement parser in the shared engine  
**Input**: User description: "P2 (first slice) — Import an ICICI credit-card statement on-device: port the first real statement parser into the shared engine, proven byte-for-byte against golden fixtures, with a privacy gate."

> **Note on priority labels**: This feature is milestone **P2** in the product roadmap (`docs/kaname-ios-plan.md` §9). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P2" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

Today the app only proves the engine bridge works (milestone P1: it shows the engine's version and round-trips a typed value). It cannot yet turn a real statement into transactions. This slice delivers the first genuinely useful capability: a person imports their ICICI credit-card statement and the app produces the list of transactions — date, amount, debit/credit direction, and description — entirely on-device, with no network and no account. It also establishes two things every later parser will reuse: the shared **"one transaction per text line"** parsing seam and the **golden-fixture parity** harness that pins the on-device engine to the proven web engine. This is the foundation of the whole ingestion feature.

The platform boundary is fixed by the constitution and locked decisions: **text extraction is native** — on iOS, the platform extracts the statement's text lines and full text and hands them to the engine. The shared engine **never** embeds a PDF engine; its entry point is a pure seam that takes already-extracted text plus the full statement text and returns the parsed result.

### User Story 1 - Turn an ICICI credit-card statement into transactions, on-device (Priority: P1)

A person imports their ICICI credit-card statement. The platform extracts the statement's text natively and hands it to the shared engine; the engine recognizes the document as an ICICI credit-card statement and returns the list of transactions — each with its date, amount, debit/credit direction, and description — computed entirely on the device with no network access.

**Why this priority**: This is the headline value and the smallest slice that turns a real statement into usable data. It is a viable MVP on its own: even without the later refinements, a person gets their transactions from their statement, on-device. Every subsequent story builds on this parse.

**Independent Test**: Provide the engine with the extracted text of a synthetic ICICI credit-card statement and confirm it recognizes the issuer and returns one transaction per spend line, each carrying a date, an exact amount, a direction, and a description — with no network access during the parse.

**Acceptance Scenarios**:

1. **Given** the extracted text of a synthetic ICICI credit-card statement, **When** the engine parses it, **Then** it recognizes the document as an ICICI credit-card statement and returns a transaction for each spend line.
2. **Given** the synthetic ICICI spend line `29/04/2026 4262 BBPS Payment received 0 13,628.36 CR`, **When** the engine parses it, **Then** it returns a transaction dated 2026-04-29, amount 13628.36, in Indian Rupees, with a description preserving the line's text.
3. **Given** the synthetic ICICI spend line `26/05/2026 1814 Fee on gaming transaction 0 10.20`, **When** the engine parses it, **Then** it returns a transaction dated 2026-05-26, amount 10.20, in Indian Rupees.
4. **Given** the statement text belongs to a different issuer (for example, an HDFC statement), **When** the ICICI reader is asked whether it recognizes the document, **Then** it does not claim it, so the document is never misattributed to ICICI.
5. **Given** the device has no network connectivity, **When** the statement is parsed, **Then** the transactions are still produced, proving the parse is fully local.

---

### User Story 2 - Debit/credit direction comes from the statement, never from the amount's sign (Priority: P2)

Each transaction's direction (money in vs money out) reflects the statement's own debit/credit indication. A row marked as a credit is a credit; a refund, reversal, cashback, or "payment received" with no explicit marker is treated as a credit; everything else defaults to a spend (debit). The direction is never guessed from whether an amount looks positive, negative, or large.

**Why this priority**: Correct direction is what makes the parsed data trustworthy for later categorization, dedup, and reconciliation. Reading polarity from the statement (never from the amount) is a non-negotiable engine rule; getting it wrong silently corrupts every downstream total.

**Independent Test**: Parse rows that carry an explicit credit marker, rows whose description uses credit-type language without a marker, and ordinary spend rows, and confirm each is classified credit, credit, and debit respectively — regardless of the amount's value.

**Acceptance Scenarios**:

1. **Given** a row ending in the credit marker `CR` (e.g., the `BBPS Payment received … 13,628.36 CR` line), **When** it is parsed, **Then** the transaction's direction is **credit**.
2. **Given** a spend row with no credit marker (e.g., the `Fee on gaming transaction … 10.20` line), **When** it is parsed, **Then** the transaction's direction is **debit**.
3. **Given** a row with no explicit marker whose description uses credit-type language (refund, reversal, cashback, or "payment received"), **When** it is parsed, **Then** the transaction's direction is **credit**.
4. **Given** any row, **When** it is parsed, **Then** the direction is decided solely from the statement's debit/credit indication and never from the sign or magnitude of the amount.

---

### User Story 3 - Statement metadata: billing-period end and card last-4 (Priority: P3)

Beyond the individual transactions, the engine reads two pieces of statement-level context that later features (account attribution, coverage, reconciliation) depend on: the statement's closing date becomes the billing-period end, and the card's last four digits are recovered from its masked number.

**Why this priority**: The transactions are the core deliverable, but attributing them to a card and a billing period is what lets the app place them correctly later. This is small, self-contained, and independently verifiable.

**Independent Test**: Parse a synthetic statement whose text contains a closing date and a masked card number, and confirm the engine records the billing-period end date and the card's last four digits.

**Acceptance Scenarios**:

1. **Given** the statement text contains `Statement Date May 28, 2026`, **When** the engine parses it, **Then** the billing-period end is recorded as 2026-05-28.
2. **Given** the statement text contains the masked card number `4315XXXXXXXX1002`, **When** the engine parses it, **Then** the card's last four digits are recorded as `1002`.
3. **Given** the statement text contains no recognizable closing date or masked card number, **When** the engine parses it, **Then** the corresponding metadata is simply absent (left unset) rather than fabricated, and the transactions are still returned.

---

### User Story 4 - Malformed rows are captured for review, never dropped or fatal (Priority: P4)

If a line looks like a transaction row but one of its fields will not parse, the engine keeps the raw line aside as an "errored line" for later review instead of crashing or silently discarding it — and it still returns every well-formed transaction from the same statement.

**Why this priority**: Real statements are messy. A single odd line must never take down the whole import or cause a person to lose the rest of their transactions. This resilience is what makes the parser safe to ship.

**Independent Test**: Parse a statement that mixes well-formed rows with a row whose fields cannot be parsed, and confirm the good rows are all returned, the bad row is captured for review, and no error is raised.

**Acceptance Scenarios**:

1. **Given** a statement containing one unparseable row among several valid rows, **When** the engine parses it, **Then** all valid rows are returned as transactions and no error is raised.
2. **Given** the same statement, **When** the engine parses it, **Then** the unparseable row is captured as an errored line (its raw text preserved, bounded to a safe maximum length) for review.
3. **Given** lines that are not transaction rows at all (headers, summaries, balances, totals), **When** the engine parses the statement, **Then** those lines are ignored without producing transactions and without being reported as errors.

---

### User Story 5 - Proven byte-for-byte against golden fixtures (Priority: P5)

As a maintainer, the engine's ICICI behaviour is pinned to the proven web engine by porting the web engine's synthetic ICICI characterization vectors into the repository's `fixtures/` directory as golden vectors and asserting the on-device engine reproduces them exactly.

**Why this priority**: Parity is the constitution's acceptance mechanism for the port (Principle V). It turns "we think it matches" into an enforced, regression-proof guarantee, and it establishes the fixture harness that every later bank/card parser will reuse.

**Independent Test**: Run the parity harness over the ported synthetic ICICI vectors and confirm the engine's output matches the expected output exactly, and that re-running produces identical results.

**Acceptance Scenarios**:

1. **Given** the ported synthetic ICICI golden vectors, **When** the parity harness runs, **Then** the engine's parsed output (dates, amounts, directions, descriptions, billing-period end, and card last-4) matches the expected output exactly.
2. **Given** a change that alters ICICI parsing behaviour, **When** the parity harness runs, **Then** it fails, enforcing the parity guarantee.
3. **Given** the golden fixtures, **When** they are inspected, **Then** all input and expected data is synthetic or fully redacted (fabricated merchants, amounts, and masked card numbers) — never real account data.

---

### User Story 6 - Privacy gate: zero network in the parse path (Priority: P6)

As a maintainer, an automated privacy-egress test asserts that the entire import/parse path performs no network I/O, so the constitution's "free features run 100% on-device" guarantee is enforced for this slice and protected against regressions.

**Why this priority**: Privacy is the product's non-negotiable promise and a required constitution gate. Making it an automated, first-class deliverable of this slice means the guarantee is proven, not merely asserted.

**Independent Test**: Run the privacy-egress test against the ICICI parse path and confirm it passes only when zero outbound network connections occur during parsing.

**Acceptance Scenarios**:

1. **Given** the ICICI parse path, **When** the automated privacy-egress test runs, **Then** it confirms zero outbound network connections occur during parsing.
2. **Given** a regression that introduces any network access into the parse path, **When** the privacy-egress test runs, **Then** it fails, blocking the change.
3. **Given** the feature as a whole, **When** the engine and app are reviewed, **Then** no telemetry, analytics, advertising, or crash-reporting component is present in the parse path.

---

### Edge Cases

- **Wrong issuer**: A statement from another issuer (e.g., HDFC) is presented to the ICICI reader → it must not claim the document, so transactions are never misattributed to ICICI.
- **Non-transaction lines**: Header, summary, balance, and total lines → ignored (no transaction, no error).
- **Unparseable row**: A line that resembles a transaction but whose fields will not parse → captured as an errored line; every good row in the same statement is still returned; no error is raised.
- **Indian money formatting**: Amounts with currency symbols (₹/Rs/INR) and thousands separators, including the Indian grouping style (e.g., `1,23,456.78`) → parsed to the exact, non-negative decimal value, with stated precision preserved (e.g., `10.20` keeps two decimal places).
- **Direction sources**: A trailing `CR` marker, a credit-type description with no marker, and an ordinary spend → classified credit, credit, and debit respectively — regardless of the amount.
- **Reward points between description and amount**: An optional reward-points value sitting between the description and the amount → not mistaken for the amount and not folded into the description.
- **Serial digits adjacent to the date**: Serial-number digits immediately following the date with no separating space → still read correctly as date plus serial.
- **No transaction lines**: Empty input, or input with no recognizable rows → an empty transaction list is returned with no error.
- **Repeated / concurrent parses**: The same input parsed repeatedly → identical results every time, with no dependence on wall-clock time, locale, or hidden global state.
- **Missing metadata**: No recognizable closing date or masked card number in the text → billing-period end and card last-4 are left unset rather than fabricated.

## Requirements *(mandatory)*

### Functional Requirements

**Document recognition**

- **FR-001**: The engine MUST recognize a statement as an ICICI credit-card statement via an issuer/document-plausibility check (the statement text contains the ICICI issuer marker) before parsing it as ICICI.
- **FR-002**: The engine MUST NOT claim a statement that belongs to a different issuer, so a document is only parsed by the reader that recognizes it.

**Transaction extraction (the core parse)**

- **FR-003**: For each ICICI spend line — a transaction date, an optional serial number, a description, an optional reward-points value, an amount, and an optional trailing credit marker — the engine MUST produce exactly one transaction.
- **FR-004**: Each produced transaction MUST include the transaction date, the amount, the debit/credit direction, the description text, and the currency (Indian Rupees, INR).
- **FR-005**: Lines that are not transaction rows (headers, summaries, balances, totals) MUST be ignored without producing transactions or errors.

**Amount**

- **FR-006**: The engine MUST parse each amount as an exact, non-negative decimal, stripping currency symbols (₹/Rs/INR) and thousands separators, including the Indian grouping style (e.g., `1,23,456.78`), and preserving the stated precision (e.g., `10.20` retains two decimal places).
- **FR-007**: Monetary amounts MUST NEVER be represented as floating-point numbers; they MUST be exact decimals throughout.

**Direction / polarity**

- **FR-008**: The engine MUST determine each transaction's debit/credit direction from the statement's own debit/credit indication and MUST NEVER infer it from the sign or magnitude of the amount.
- **FR-009**: A trailing credit marker (`CR`) on a row MUST classify that transaction as a credit.
- **FR-010**: When a row carries no explicit marker, the engine MUST classify it as a credit when its description uses credit-type language (e.g., refund, reversal, cashback, "payment received"); otherwise it MUST default to a debit.

**Statement metadata**

- **FR-011**: The engine MUST extract the statement's closing (statement) date and record it as the billing-period end date when present.
- **FR-012**: The engine MUST extract the card's last four digits from a masked card number (e.g., `4315XXXXXXXX1002` → `1002`) when present.
- **FR-013**: When a metadata field cannot be found, the engine MUST leave it unset rather than fabricate a value, and MUST still return the parsed transactions.

**Robustness**

- **FR-014**: A line that resembles a transaction row but whose fields cannot be parsed MUST be captured as an "errored line" (raw text preserved, bounded to a safe maximum length) for later review; the engine MUST NOT raise an error or silently drop it, and MUST still return every successfully parsed row.

**Engine purity & platform boundary**

- **FR-015**: The engine's parse entry point MUST accept already-extracted text lines plus the full statement text and return the parsed result; it MUST NOT read files, extract PDF text, or embed a PDF engine (text extraction is a native platform concern).
- **FR-016**: The engine MUST remain pure and deterministic: identical input MUST yield identical output, with no dependence on network, wall-clock time, locale, or hidden global mutable state.
- **FR-017**: This slice MUST introduce a reusable "one transaction per text line" parsing capability (row recognition + direction/polarity + statement enrichment) that later credit-card readers can reuse.

**Privacy (constitution Principle I — NON-NEGOTIABLE)**

- **FR-018**: The entire import/parse path MUST run 100% on-device with ZERO network I/O.
- **FR-019**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting into the engine or the app.
- **FR-020**: An automated privacy-egress test MUST assert that the parse path performs no network access; it is a required constitution gate and a first-class deliverable of this slice.

**Parity & test-first (constitution Principle V)**

- **FR-021**: The web engine's synthetic ICICI characterization vectors MUST be ported into the repository's `fixtures/` directory as golden vectors, and the engine MUST reproduce them exactly.
- **FR-022**: All fixture and test data MUST be synthetic or fully redacted (fabricated merchants, amounts, and masked card numbers) — never real account data.
- **FR-023**: The parsing behaviour introduced by this slice MUST be developed test-first (a failing golden test precedes the behaviour).

**Licensing, secrets & quality gates**

- **FR-024**: The change MUST NOT add secrets, API keys, or private endpoints, and MUST remain distributable under Apache-2.0 with no copyleft (GPL/AGPL/LGPL) dependencies introduced.
- **FR-025**: The change MUST keep the iOS Local Verification Gate and CI green: core formatting, linting, and tests; app linting; project generation; a simulator build with passing app tests; and the privacy gate.
- **FR-026**: If any user-facing surface is introduced for this slice, it MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility.

### Key Entities *(include if feature involves data)*

- **Extracted statement text (input)**: The already-extracted text lines plus the full statement text handed to the engine by the native platform. Contains no PDF binary; the engine never opens a PDF.
- **Parsed transaction**: One statement row's result — a transaction date, an exact non-negative amount, an explicit debit/credit direction, a currency (INR), and a description.
- **Parsed statement result**: The full output of reading one statement — the issuer/bank identity, the list of parsed transactions, the list of errored (unparseable) lines, the billing-period end date, and the card last-4.
- **Direction (polarity)**: An explicit debit or credit indicator carried on every transaction, sourced from the statement's own indication and never from the amount's sign.
- **Golden characterization vector**: A synthetic ICICI input (text lines + full text) paired with its expected engine output, stored under `fixtures/` as the source of truth for parity.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For the two synthetic ICICI golden lines, the engine produces exactly the expected transactions — line 1 → date 2026-04-29, amount 13628.36, direction credit; line 2 → date 2026-05-26, amount 10.20, direction debit (100% match).
- **SC-002**: The engine recognizes the synthetic ICICI statement as ICICI and does not claim a non-ICICI (e.g., HDFC) statement — 0 misattributions across the recognition cases.
- **SC-003**: From the synthetic statement text, the engine records the billing-period end as 2026-05-28 and the card last-4 as `1002`.
- **SC-004**: Direction is correct across every tested case — a trailing `CR` → credit; credit-type language → credit; an ordinary spend → debit — and is never changed by the amount's sign or magnitude.
- **SC-005**: 100% of parsed amounts are exact decimals with their stated precision preserved and are always non-negative; no monetary value is ever a floating-point number.
- **SC-006**: A malformed row is captured for review while every well-formed row in the same input is still returned, and no error is raised (parse never aborts on a bad row).
- **SC-007**: Zero outbound network connections occur during the entire parse path, verified by the automated privacy-egress test.
- **SC-008**: Given identical input, the engine returns identical output across repeated runs (100% reproducible).
- **SC-009**: The ported synthetic golden vectors reproduce exactly and the parity harness passes; re-running is stable.
- **SC-010**: All automated checks required to merge pass (green), including the parity harness and the privacy-egress test, with the iOS Local Verification Gate and CI green.
- **SC-011**: No secrets, network entitlements, telemetry, or copyleft-licensed dependencies are added by the feature (verified by review of manifests and dependencies).

## Assumptions

- **Parse seam & platform boundary**: The engine parse seam mirrors the web engine's `read_lines(lines, full_text)` — it takes already-extracted text lines plus the full statement text and returns the parsed result. The native platform (iOS PDFKit) performs the text extraction; the exact seam signature and native wiring are finalized in `/speckit.plan`.
- **Binding**: The parser is exposed to Swift via the existing UniFFI bridge established in milestone P1 (which already surfaces the engine version, a typed round-trip, and the `Direction`/`Transaction` domain types); concrete binding mechanics belong in `/speckit.plan`.
- **Fixtures location**: Golden fixtures live under the repository-root `fixtures/` directory and are the source of truth for parity.
- **Reusable reader introduced now**: The shared "one transaction per text line" reader infrastructure (row recognition + direction/polarity + statement enrichment) is introduced in this slice because ICICI needs it and later credit-card readers (HDFC, SBI, Yes, Federal) will reuse it.
- **Registry scope**: The issuer registry keyed by `(bank_code, account_kind)` is introduced only to the extent ICICI needs; broader registry work is deferred.
- **Source of truth**: The web engine is the source of truth for behaviour — `icici.py`, `_line_reader.py`, `base.py`, `_common.py`, and `polarity.py`, plus the credit-card characterization test. The porting approach (module layout, patterns, fixture format) is decided in `/speckit.plan`, not here.
- **No new UI required**: This is an engine slice; no user-facing UI is required to deliver it. App-side PDF text extraction (PDFKit wiring), the file-import UI, and the Share Extension remain a native concern and a next step. If a trivial demo surface is added, it follows HIG and accessibility (FR-026).
- **Data safety**: All fixture and test data is synthetic or fully redacted — no real account data.
- **Money & polarity**: Amounts are exact decimals (never floating-point) and direction is carried explicitly, consistent with the engine's existing domain types.

### Dependencies

- **Kaname Constitution v1.0.0** — privacy (zero-network free/core), determinism, a pure platform-agnostic core (no PDF engine), decimal money with explicit polarity, Apache-2.0 open-core with no copyleft, native HIG/accessibility, and the test-first iOS Local Verification Gate (including the privacy-egress gate).
- **Milestone P1 bridge (already landed)** — the shared engine crate with its `Direction`/`Transaction` domain types and the UniFFI Swift binding proven end-to-end.
- **Web engine golden vectors** — the synthetic ICICI characterization vectors and reader behaviour used as the parity source of truth.

## Out of Scope

Deferred to later P2 slices / milestones:

- **Reconciliation** (printed-total integrity check), **coverage / billing-period timeline**, **cross-source de-duplication and transfer detection**, and **balance-chain integrity**.
- **All other bank/card parsers** — HDFC, SBI, Yes, Federal, and the bank-account ledger readers.
- The `(bank_code, account_kind)` registry **beyond what ICICI needs**.
- **Encrypted SQLite / SQLCipher persistence** and key management.
- **AI-fallback parsing**.
- Any **premium / cloud features**.
- **App-side PDF text extraction** (PDFKit wiring in the app) and the **file-import UI / Share Extension** — native concerns handled in a later slice; this slice focuses on the engine parse seam plus its parity and privacy gates.
