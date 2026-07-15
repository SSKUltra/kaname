# Feature Specification: Import an SBI Card Credit-Card Statement On-Device (Third Real Parser, Zero New Engine Infrastructure)

**Feature Branch**: `004-sbi-cc-parser`  
**Created**: 2026-07-15  
**Status**: Draft  
**Milestone**: P2 (next slice) — the third real statement parser in the shared engine  
**Input**: User description: "P2 (next slice) — Import an SBI Card credit-card statement on-device: the third real statement parser. SBI is a clean single-layout reader that drops into the existing 'one transaction per line' seam with ZERO new engine infrastructure, further proving the fixtures-driven, incremental-by-bank ingestion scales."

> **Note on priority labels**: This feature is milestone **P2** in the product roadmap (`docs/kaname-ios-plan.md` §9). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P2" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

The two previous slices (milestone P2) landed the first two real parsers — **ICICI** and **HDFC** — and, with them, everything a new bank now reuses: the shared **"one transaction per text line"** parsing seam and per-issuer reader configuration, the parsed-statement / parsed-transaction output types, the amount / date / last-4 / polarity helpers, the **golden-fixture parity** harness that pins the on-device engine to the proven web engine, the UniFFI bridge, and the privacy-egress gate. This slice delivers the **third** bank, **SBI Card**, and demonstrates that landing a new bank is now a small, repeatable step: a person imports their SBI Card credit-card statement and the app produces the list of transactions — date, exact amount, debit/credit direction, and description — entirely on-device, with no network and no account, exactly as it already does for ICICI and HDFC.

SBI is the slice that proves the ingestion architecture **scales bank-by-bank with essentially no new engine code**. Unlike HDFC (which added a month-end date helper, a leading-`+` credit rule, and an ordered multi-layout "composite" reader), SBI is a **clean single-layout** reader that needs **no new shared helpers at all**: its day-first `DD Mon YY` date format and its single-letter `C`/`D` direction markers are already handled by the shared date parser and the shared polarity classifier. Adding SBI is therefore just a new reader configuration, a golden fixture, two bridge exports, and one parity case — no changes to the shared engine internals.

The platform boundary is unchanged and fixed by the constitution and locked decisions: **text extraction is native** — on iOS, the platform extracts the statement's text lines and full text and hands them to the shared engine; the shared engine **never** embeds a PDF engine. Its entry point is a pure seam that takes already-extracted text plus the full statement text and returns the parsed result.

### User Story 1 - Turn an SBI Card credit-card statement into transactions, on-device (Priority: P1)

A person imports their SBI Card credit-card statement. The platform extracts the statement's text natively and hands it to the shared engine; the engine recognizes the document as an SBI Card statement and returns the list of transactions — each with its date, amount, debit/credit direction, and description — computed entirely on the device with no network access.

**Why this priority**: This is the headline value and the smallest slice that turns a real SBI Card statement into usable data. It is a viable increment on its own: a person gets their SBI transactions from their statement, on-device, exactly as they already can for ICICI and HDFC. Every subsequent story refines this parse.

**Independent Test**: Provide the engine with the extracted text of a synthetic SBI Card credit-card statement and confirm it recognizes the issuer and returns one transaction per matching row, each carrying a date, an exact amount, a direction, and a description — with no network access during the parse.

**Acceptance Scenarios**:

1. **Given** the extracted text of a synthetic SBI Card credit-card statement (containing the issuer marker `SBI Card` / `GSTIN of SBI Card`), **When** the engine parses it, **Then** it recognizes the document as an SBI Card statement and returns a transaction for each transaction row.
2. **Given** the synthetic SBI row `21 Apr 26 CARD CASHBACK CREDIT 643.00 C`, **When** the engine parses it, **Then** it returns a transaction dated 2026-04-21, amount 643.00, in Indian Rupees, with the description `CARD CASHBACK CREDIT`.
3. **Given** the synthetic SBI row `20 May 26 APPLE INDIA STORE MUMBAI IN 82,900.00 D`, **When** the engine parses it, **Then** it returns a transaction dated 2026-05-20, amount 82900.00, in Indian Rupees, with the description `APPLE INDIA STORE MUMBAI IN`.
4. **Given** a statement that belongs to a different issuer (for example, an ICICI or HDFC statement), **When** the SBI reader is asked whether it recognizes the document, **Then** it does not claim it, so the document is never misattributed to SBI.
5. **Given** the device has no network connectivity, **When** the statement is parsed, **Then** the transactions are still produced, proving the parse is fully local.

---

### User Story 2 - A third bank added with zero new engine infrastructure (Priority: P2)

As a maintainer, adding SBI must require **no new shared engine infrastructure** — only a new per-issuer reader configuration, a golden fixture, two UniFFI exports, and one parity case row. The day-first `DD Mon YY` date format (e.g., `21 Apr 26`) and the single-letter `C`/`D` direction markers are already handled by the shared date parser and the shared polarity classifier; SBI adds no new shared helper, unlike HDFC's month-end and composite-reader additions.

**Why this priority**: This is the distinctive point of the slice and the reason SBI was chosen as the third bank: it proves the fixtures-driven, **incremental-by-bank** ingestion architecture scales with essentially no new engine code. Landing SBI green as a pure drop-in reader validates that the shared seam, helpers, harness, bridge, and privacy gate built for ICICI and extended by HDFC generalize cleanly to a new single-layout bank.

**Independent Test**: Confirm the SBI parse is delivered by a new single-layout reader configuration that plugs into the existing `read_lines(lines, full_text)` seam, reusing the shared date parser (for `DD Mon YY`) and polarity classifier (for `C`/`D`), and that **no new shared helper** is introduced or modified in the shared reader subsystem to support SBI.

**Acceptance Scenarios**:

1. **Given** the SBI reader, **When** it parses the `21 Apr 26 … 643.00 C` row, **Then** the shared date parser interprets `21 Apr 26` as 2026-04-21 with no SBI-specific date code, proving the existing `DD Mon YY` support is reused unchanged.
2. **Given** the SBI reader, **When** it classifies a row's direction, **Then** the shared polarity classifier maps the single-letter `C`/`D` marker to credit/debit with no SBI-specific direction code.
3. **Given** the change set that adds SBI, **When** it is reviewed, **Then** it consists of a new reader configuration, a golden fixture, two bridge exports, and one parity case row — and adds **no** new shared engine helper (in contrast to the month-end and composite-reader helpers HDFC required).

---

### User Story 3 - Debit/credit direction comes from the statement's C/D marker, never from the amount's sign (Priority: P3)

Each transaction's direction (money in vs money out) reflects the statement's own single-letter marker at the end of the row: `C` means credit and `D` means debit (legend: C = Credit, D = Debit). The direction is never guessed from whether an amount looks positive, negative, or large, and never inferred from words in the description.

**Why this priority**: Correct direction is what makes the parsed data trustworthy for later categorization, dedup, and reconciliation. Reading polarity from the statement's own marker (never from the amount) is a non-negotiable engine rule; SBI expresses direction with an explicit terminal `C`/`D` marker, so honouring that marker is what makes SBI directions correct.

**Independent Test**: Parse rows ending in `C` and rows ending in `D` and confirm each is classified credit or debit from the statement's own marker — regardless of the amount's value and regardless of any credit/debit words appearing in the description.

**Acceptance Scenarios**:

1. **Given** a row whose final field is the marker `C` (e.g., the `CARD CASHBACK CREDIT 643.00 C` line), **When** it is parsed, **Then** the transaction's direction is **credit**.
2. **Given** a row whose final field is the marker `D` (e.g., the `APPLE INDIA STORE MUMBAI IN 82,900.00 D` line), **When** it is parsed, **Then** the transaction's direction is **debit**.
3. **Given** a row whose description contains a direction-like word that conflicts with its marker, **When** it is parsed, **Then** the direction is taken from the terminal `C`/`D` marker and not from the description's wording (e.g., `CARD CASHBACK CREDIT … C` is a credit because of the `C` marker, not because the description says "CREDIT").
4. **Given** any row, **When** it is parsed, **Then** the direction is decided solely from the statement's own `C`/`D` marker and never from the sign or magnitude of the amount.

---

### User Story 4 - Statement metadata: billing period and card last-4 (absent when fewer than four digits are visible) (Priority: P4)

Beyond the individual transactions, the engine reads two pieces of statement-level context that later features (account attribution, coverage, reconciliation) depend on: the statement's billing period and the card's last four digits. Crucially, when the masked card number exposes **fewer than four** trailing digits, the last-4 is simply **absent** — never fabricated.

**Why this priority**: The transactions are the core deliverable, but attributing them to a card and a billing period is what lets the app place them correctly later. SBI's masked card number can show only two trailing digits, so this story confirms both derivations are correct and — importantly — that the engine leaves the last-4 unset rather than inventing digits.

**Independent Test**: Parse a synthetic SBI statement whose text carries a "Statement Period … to …" line and a masked card number that shows only two trailing digits, and confirm the engine records the correct billing-period start/end and records **no** card last-4 (absent, not fabricated).

**Acceptance Scenarios**:

1. **Given** statement text containing `for Statement Period: 22 Apr 26 to 21 May 26`, **When** the engine parses it, **Then** the billing-period start is recorded as 2026-04-22 and the billing-period end as 2026-05-21.
2. **Given** statement text containing the masked card number anchored as `Credit Card Number XXXX XXXX XXXX XX61` (only two trailing digits visible), **When** the engine parses it, **Then** the card last-4 is **absent** (left unset), because fewer than four trailing digits are present — it is never fabricated.
3. **Given** statement text whose masked card number does expose four trailing digits, **When** the engine parses it, **Then** the card's last four digits are recorded from that number.
4. **Given** statement text containing no recognizable billing period or masked card number, **When** the engine parses it, **Then** the corresponding metadata is simply absent (left unset) rather than fabricated, and the transactions are still returned.

---

### User Story 5 - Malformed rows are captured for review, never dropped or fatal (Priority: P5)

If a line looks like a transaction row but one of its fields will not parse, the engine keeps the raw line aside as an "errored line" for later review instead of crashing or silently discarding it — and it still returns every well-formed transaction from the same statement.

**Why this priority**: Real statements are messy. A single odd line must never take down the whole import or cause a person to lose the rest of their transactions. This resilience is what makes the parser safe to ship, and it is reused unchanged from the ICICI and HDFC slices.

**Independent Test**: Parse a statement that mixes well-formed rows with a row whose fields cannot be parsed, and confirm the good rows are all returned, the bad row is captured for review, and no error is raised.

**Acceptance Scenarios**:

1. **Given** a statement containing one unparseable row among several valid rows, **When** the engine parses it, **Then** all valid rows are returned as transactions and no error is raised.
2. **Given** the same statement, **When** the engine parses it, **Then** the unparseable row is captured as an errored line (its raw text preserved, bounded to a safe maximum length) for review.
3. **Given** lines that are not transaction rows at all (headers, summaries, balances, totals), **When** the engine parses the statement, **Then** those lines are ignored without producing transactions and without being reported as errors.

---

### User Story 6 - Proven byte-for-byte against a golden fixture (Priority: P6)

As a maintainer, the engine's SBI behaviour is pinned to the proven web engine by porting the web engine's synthetic SBI characterization vector into the repository's `fixtures/` directory as a golden vector, with the on-device engine asserted to reproduce it exactly.

**Why this priority**: Parity is the constitution's acceptance mechanism for the port (Principle V). It turns "we think it matches" into an enforced, regression-proof guarantee, and it extends the harness that every later bank/card parser reuses — this time proving the harness accepts a third bank as a one-row addition.

**Independent Test**: Run the parity harness over the ported SBI vector and confirm the engine's output matches the expected output exactly, and that re-running produces identical results.

**Acceptance Scenarios**:

1. **Given** the ported synthetic SBI golden vector, **When** the parity harness runs, **Then** the engine's parsed output (dates, amounts, directions, descriptions, billing-period start/end, and card last-4) matches the expected output exactly — including the two rows (2026-04-21 / 643.00 / credit and 2026-05-20 / 82900.00 / debit), the billing period (2026-04-22 to 2026-05-21), and the **absent** card last-4.
2. **Given** a change that alters SBI parsing behaviour, **When** the parity harness runs, **Then** it fails, enforcing the parity guarantee.
3. **Given** the golden fixture, **When** it is inspected, **Then** all input and expected data is synthetic or fully redacted (fabricated merchants, amounts, and masked card number) — never real account data.

---

### User Story 7 - Privacy gate: zero network in the parse path (Priority: P7)

As a maintainer, the existing automated privacy-egress test covers the SBI import/parse path and asserts it performs no network I/O, so the constitution's "free features run 100% on-device" guarantee holds for this slice and is protected against regressions.

**Why this priority**: Privacy is the product's non-negotiable promise and a required constitution gate. Extending the existing gate to cover SBI means the guarantee is proven for the new parser, not merely assumed.

**Independent Test**: Run the privacy-egress test against the SBI parse path and confirm it passes only when zero outbound network connections occur during parsing.

**Acceptance Scenarios**:

1. **Given** the SBI parse path, **When** the automated privacy-egress test runs, **Then** it confirms zero outbound network connections occur during parsing.
2. **Given** a regression that introduces any network access into the parse path, **When** the privacy-egress test runs, **Then** it fails, blocking the change.
3. **Given** the feature as a whole, **When** the engine and app are reviewed, **Then** no telemetry, analytics, advertising, or crash-reporting component is present in the parse path.

---

### Edge Cases

- **Wrong issuer**: A statement from another issuer (e.g., ICICI or HDFC) is presented to the SBI reader → it must not claim the document, so transactions are never misattributed to SBI.
- **Terminal direction marker**: The single-letter `C`/`D` marker sits at the **end** of the row, after the amount → direction is read from that marker (`C` → credit, `D` → debit) and the marker is not mistaken for part of the description or the amount.
- **Direction vs description wording**: A description containing a credit/debit-like word (e.g., "CARD CASHBACK CREDIT") → direction is still taken from the terminal `C`/`D` marker, not from the description text.
- **Indian money formatting**: Amounts with thousands separators, including the Indian grouping style (e.g., `1,23,456.78`) → parsed to the exact, non-negative decimal value, with stated precision preserved (e.g., `82,900.00` → 82900.00 keeps two decimal places).
- **Masked card with fewer than four trailing digits**: A masked card number such as `XXXX XXXX XXXX XX61` (only two visible trailing digits) → the card last-4 is **absent** (left unset), never fabricated.
- **Non-transaction lines**: Header, summary, balance, and total lines → ignored (no transaction, no error).
- **Unparseable row**: A line that resembles a transaction row but whose fields will not parse → captured as an errored line; every good row in the same statement is still returned; no error is raised.
- **No transaction lines**: Empty input, or input with no recognizable rows → an empty transaction list is returned with no error.
- **Missing metadata**: No recognizable billing period or masked card number in the text → billing-period start/end and card last-4 are left unset rather than fabricated.
- **Repeated / concurrent parses**: The same input parsed repeatedly → identical results every time, with no dependence on wall-clock time, locale, or hidden global state.

## Requirements *(mandatory)*

### Functional Requirements

**Document recognition**

- **FR-001**: The engine MUST recognize a statement as an SBI Card credit-card statement via an issuer/document-plausibility check — the statement text contains an SBI Card issuer marker (`SBI Card` or `GSTIN of SBI Card`) — before parsing it as SBI.
- **FR-002**: The engine MUST NOT claim a statement that belongs to a different issuer (e.g., an ICICI or HDFC statement), so a document is only parsed by the reader that recognizes it.

**Transaction extraction (the core parse)**

- **FR-003**: The engine MUST parse SBI's single credit-card statement layout `DD Mon YY <details> <amount> C|D` — a day-first date with a three-letter month and two-digit year, followed by the description, the amount, and a terminal single-letter `C`/`D` direction marker — and MUST produce exactly one transaction per matching row.
- **FR-004**: Each produced transaction MUST include the transaction date, the amount, the debit/credit direction, the description text, and the currency (Indian Rupees, INR).
- **FR-005**: Lines that are not transaction rows (headers, summaries, balances, totals) MUST be ignored without producing transactions or errors.

**Amount**

- **FR-006**: The engine MUST parse each amount as an exact, non-negative decimal using Indian number formatting (thousands separators, including the Indian grouping style), preserving the stated precision (e.g., `82,900.00` → 82900.00 retains two decimal places).
- **FR-007**: Monetary amounts MUST NEVER be represented as floating-point numbers; they MUST be exact decimals throughout.

**Direction / polarity**

- **FR-008**: The engine MUST determine each transaction's debit/credit direction from the statement's own terminal `C`/`D` marker and MUST NEVER infer it from the sign or magnitude of the amount, nor from words in the description.
- **FR-009**: The terminal marker MUST set the direction: `C` → credit, `D` → debit (legend: C = Credit, D = Debit).

**Statement metadata**

- **FR-010**: The engine MUST derive the billing period from text of the form `Statement Period: <DD Mon YY> to <DD Mon YY>` (e.g., `for Statement Period: 22 Apr 26 to 21 May 26`), setting the billing-period start and end to the two parsed dates (start = 2026-04-22, end = 2026-05-21 for that example).
- **FR-011**: The engine MUST extract the card's last four digits from a masked card number found via the `Credit Card Number` anchor when four trailing digits are present.
- **FR-012**: When the masked card number exposes fewer than four trailing digits (e.g., `XXXX XXXX XXXX XX61`), the engine MUST leave the card last-4 absent (unset) and MUST NOT fabricate any digits.
- **FR-013**: When a metadata field cannot be found, the engine MUST leave it unset rather than fabricate a value, and MUST still return the parsed transactions.

**Robustness**

- **FR-014**: A line that resembles a transaction row but whose fields cannot be parsed MUST be captured as an "errored line" (raw text preserved, bounded to a safe maximum length) for later review; the engine MUST NOT raise an error or silently drop it, and MUST still return every successfully parsed row.

**Engine purity, platform boundary & reuse**

- **FR-015**: The engine's SBI parse MUST reuse the existing "one transaction per text line" reader seam — accepting already-extracted text lines plus the full statement text and returning the parsed result; it MUST NOT read files, extract PDF text, or embed a PDF engine (text extraction is a native platform concern).
- **FR-016**: The engine MUST remain pure and deterministic: identical input MUST yield identical output, with no dependence on network, wall-clock time, locale, or hidden global mutable state.
- **FR-017**: SBI MUST reuse — not rebuild — the existing shared output types (parsed statement / parsed transaction), the amount / date / last-4 / polarity helpers (including the `DD Mon YY` date format and the single-letter `C`/`D` marker classification), the golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate. This slice MUST add **no new shared engine helper** (in contrast to the month-end and composite-reader helpers HDFC added); SBI is delivered as a new single-layout reader configuration only.
- **FR-018**: The engine MUST expose SBI over the existing UniFFI bridge with an SBI parse entry point and an SBI issuer-claims function, mirroring the ICICI and HDFC surfaces (two exports).

**Privacy (constitution Principle I — NON-NEGOTIABLE)**

- **FR-019**: The entire SBI import/parse path MUST run 100% on-device with ZERO network I/O.
- **FR-020**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting into the engine or the app.
- **FR-021**: The existing automated privacy-egress test MUST cover the SBI parse path and assert it performs no network access; it remains a required constitution gate.

**Parity & test-first (constitution Principle V)**

- **FR-022**: The web engine's synthetic SBI characterization vector MUST be ported into the repository's `fixtures/` directory (under `fixtures/sbi_card/credit_card/`) as a golden vector, and the engine MUST reproduce it exactly.
- **FR-023**: All fixture and test data MUST be synthetic or fully redacted (fabricated merchants, amounts, and masked card number) — never real account data.
- **FR-024**: The SBI parsing behaviour introduced by this slice MUST be developed test-first (a failing golden test precedes the behaviour).

**Licensing, secrets & quality gates**

- **FR-025**: The change MUST NOT add secrets, API keys, or private endpoints; MUST remain distributable under Apache-2.0 with no copyleft (GPL/AGPL/LGPL) dependencies; and MUST introduce NO new runtime dependencies for this slice.
- **FR-026**: The change MUST keep the iOS Local Verification Gate and CI green: core formatting, linting, and tests; app linting; project generation; a simulator build with passing app tests; and the privacy gate.
- **FR-027**: If any user-facing surface is introduced for this slice, it MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility.

### Key Entities *(include if feature involves data)*

- **Extracted statement text (input)**: The already-extracted text lines plus the full statement text handed to the engine by the native platform. Contains no PDF binary; the engine never opens a PDF.
- **Parsed transaction**: One statement row's result — a transaction date, an exact non-negative amount, an explicit debit/credit direction, a currency (INR), and a description.
- **Parsed statement result**: The full output of reading one statement — the issuer/bank identity (`SBI_CARD`), the list of parsed transactions, the list of errored (unparseable) lines, the billing-period start and end dates, and the card last-4 (which may be absent).
- **Direction (polarity)**: An explicit debit or credit indicator carried on every transaction, sourced from the statement's own terminal `C`/`D` marker and never from the amount's sign.
- **Golden characterization vector**: A synthetic SBI input (text lines + full text) paired with its expected engine output, stored under `fixtures/sbi_card/credit_card/`, ported from the web engine and reproduced exactly by the on-device engine.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For the two synthetic SBI golden rows, the engine produces exactly the expected transactions — row 1 → date 2026-04-21, amount 643.00, direction credit, description `CARD CASHBACK CREDIT`; row 2 → date 2026-05-20, amount 82900.00, direction debit, description `APPLE INDIA STORE MUMBAI IN` (100% match).
- **SC-002**: The engine recognizes the synthetic SBI statement as SBI and does not claim a non-SBI (e.g., ICICI or HDFC) statement — 0 misattributions across the recognition cases.
- **SC-003**: From the synthetic SBI statement text, the engine records the billing-period start as 2026-04-22, the billing-period end as 2026-05-21, and records **no** card last-4 (absent, because only two trailing digits are visible in `XXXX XXXX XXXX XX61`) — the last-4 is never fabricated.
- **SC-004**: Direction is correct across every tested case — a terminal `C` → credit and a terminal `D` → debit — and is never changed by the amount's sign or magnitude, nor by direction-like words in the description.
- **SC-005**: 100% of parsed amounts are exact decimals with their stated precision preserved and are always non-negative; no monetary value is ever a floating-point number.
- **SC-006**: A malformed row is captured for review while every well-formed row in the same input is still returned, and no error is raised (the parse never aborts on a bad row).
- **SC-007**: Zero outbound network connections occur during the entire SBI parse path, verified by the automated privacy-egress test.
- **SC-008**: Given identical input, the engine returns identical output across repeated runs (100% reproducible).
- **SC-009**: The ported synthetic SBI golden vector reproduces exactly and the parity harness passes; re-running is stable.
- **SC-010**: SBI is added with **zero new shared engine helpers** — the change consists only of a new single-layout reader configuration, a golden fixture, two UniFFI exports, and one parity case row; the shared reader/date/polarity/last-4 helper surface is unchanged (verified by review of the change set).
- **SC-011**: All automated checks required to merge pass (green), including the parity harness and the privacy-egress test, with the iOS Local Verification Gate and CI green.
- **SC-012**: No secrets, network entitlements, telemetry, copyleft-licensed dependencies, or new runtime dependencies are added by the feature (verified by review of manifests and dependencies).

## Assumptions

- **Single-layout reader & seam**: SBI is added as a **single-layout** reader configuration reusing the existing `read_lines(lines, full_text)` seam; there is exactly one row layout (`DD Mon YY <details> <amount> C|D`). The exact module layout and row pattern are finalized in `/speckit.plan`.
- **No new shared helpers**: SBI needs **no** new shared engine helpers. Its `DD Mon YY` date format and its single-letter `C`/`D` direction markers are already handled by the shared date parser and the shared polarity classifier (both landed with ICICI and extended by HDFC). This is the deliberate contrast with HDFC, which required a month-end date helper, a leading-`+` credit rule, and a composite multi-layout reader.
- **Binding**: SBI is exposed to Swift via the existing UniFFI bridge with an SBI parse entry point and an SBI issuer-claims function, mirroring ICICI and HDFC (two exports); concrete binding mechanics belong in `/speckit.plan`.
- **Fixtures location**: The golden fixture lives under `fixtures/sbi_card/credit_card/` and is the source of truth for parity.
- **Bank code**: The issuer/bank identity for this reader is `SBI_CARD`.
- **Reused, not rebuilt**: The `read_lines` seam and per-issuer reader configuration, the parsed-statement / parsed-transaction output types, the amount / date / last-4 / polarity helpers, the golden-fixture JSON parity harness, the UniFFI bridge, and the privacy-egress gate were all built in the ICICI slice (and extended in the HDFC slice); SBI plugs into every one of them unchanged.
- **No new dependencies**: This slice should require **no** new runtime dependencies.
- **Source of truth**: The web engine is the source of truth for behaviour — `sbi_card.py` plus the shared line-reader, common helpers, and polarity module, and the credit-card characterization test (`test_cc_reader_characterization.py`, whose SBI case values are reproduced in this spec). The porting approach (module layout, patterns, regexes, fixture format, UniFFI exports) is decided in `/speckit.plan`, not here.
- **No new UI required**: This is an engine slice; no user-facing UI is required to deliver it. App-side PDF text extraction (PDFKit wiring), the file-import UI, and the Share Extension remain a native concern and a later step. If a trivial demo surface is added, it follows HIG and accessibility (FR-027).
- **Data safety**: All fixture and test data is synthetic or fully redacted — no real account data.
- **Money & polarity**: Amounts are exact decimals (never floating-point) and direction is carried explicitly and sourced from the statement's terminal `C`/`D` marker, consistent with the engine's existing domain types.

### Dependencies

- **Kaname Constitution v1.0.0** — privacy (zero-network free/core), determinism, a pure platform-agnostic core (no PDF engine), decimal money with explicit polarity, Apache-2.0 open-core with no copyleft, native HIG/accessibility, and the test-first iOS Local Verification Gate (including the privacy-egress gate).
- **Milestone P2 — ICICI slice (already landed)** — the shared "one transaction per text line" reader seam, the parsed-statement / parsed-transaction domain types, the amount / date / last-4 / polarity helpers (including the `DD Mon YY` date format and single-letter `C`/`D` marker classification), the golden-fixture parity harness, and the privacy-egress gate that SBI reuses.
- **Milestone P2 — HDFC slice (already landed)** — the second parser, which proved the seam generalizes to a multi-layout bank; SBI reuses the same seam and helpers with no further shared additions.
- **Milestone P1 bridge (already landed)** — the shared engine crate and the UniFFI Swift binding proven end-to-end, over which the SBI parse and claims functions are exposed.
- **Web engine golden vector** — the synthetic SBI characterization vector and the SBI reader behaviour used as the parity source of truth.

## Out of Scope

Deferred to later P2 slices / milestones:

- **Reconciliation** (printed-total integrity check), **coverage / billing-period timeline**, **cross-source de-duplication and transfer detection**, and **balance-chain integrity**.
- **All other remaining bank/card parsers** — Yes and Federal credit cards, and the bank-account ledger readers.
- The `(bank_code, account_kind)` registry **beyond what SBI needs**.
- **Encrypted SQLite / SQLCipher persistence** and key management.
- **AI-fallback parsing**.
- Any **premium / cloud features**.
- **App-side PDF text extraction** (PDFKit wiring in the app) and the **file-import UI / Share Extension** — native concerns handled in a later slice. This slice focuses on the SBI engine parse plus its golden-fixture parity, reusing the existing privacy gate and exposed over the existing bridge.
