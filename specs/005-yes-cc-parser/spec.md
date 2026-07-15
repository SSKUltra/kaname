# Feature Specification: Import a Yes Bank (Kiwi) Credit-Card Statement On-Device (Fourth Real Parser, Zero New Engine Infrastructure)

**Feature Branch**: `005-yes-cc-parser`  
**Created**: 2026-07-15  
**Status**: Draft  
**Milestone**: P2 (next slice) — the fourth real statement parser in the shared engine  
**Input**: User description: "P2 (next slice) — Import a Yes Bank (Kiwi) credit-card statement on-device: the fourth real statement parser, another clean single-layout drop-in that reuses the existing 'one transaction per line' seam with ZERO new engine infrastructure. A person imports their Yes Bank / Kiwi credit-card statement PDF and the app produces the list of transactions (date, exact amount, debit/credit direction, description) entirely on-device — no network, no account — exactly as it already does for ICICI, HDFC, and SBI."

> **Note on priority labels**: This feature is milestone **P2** in the product roadmap (`docs/kaname-ios-plan.md` §9). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P2" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

The three previous slices (milestone P2) landed the first three real parsers — **ICICI**, **HDFC**, and **SBI Card** — and, with them, everything a new bank now reuses: the shared **"one transaction per text line"** parsing seam and per-issuer reader configuration, the parsed-statement / parsed-transaction output types, the amount / date / last-4 / polarity helpers, the **golden-fixture parity** harness that pins the on-device engine to the proven web engine, the UniFFI bridge, and the privacy-egress gate. This slice delivers the **fourth** bank, **Yes Bank** (marketed as **Kiwi**), and — like SBI — is a **clean single-layout drop-in**: a person imports their Yes Bank / Kiwi credit-card statement and the app produces the list of transactions — date, exact amount, debit/credit direction, and description — entirely on-device, with no network and no account, exactly as it already does for ICICI, HDFC, and SBI.

Yes reinforces that the ingestion architecture **scales bank-by-bank with essentially no new engine code**. Like SBI, Yes is a **single-layout** reader that needs **no new shared helpers at all**: its day-first `DD/MM/YYYY` date format (the very same `%d/%m/%Y` format ICICI already uses) and its two-letter `Dr`/`Cr` direction markers are already handled by the shared date parser and the shared polarity classifier. Adding Yes is therefore just a new reader configuration, a golden fixture, two bridge exports, and one parity case — no changes to the shared engine internals.

There is **one deliberate scope carve-out** that distinguishes this port from a naive one: the web engine's Yes reader *also* extracts printed debit/credit totals (for a future reconciliation feature). Those printed-total fields are intentionally **left out of this slice's output model and must not be ported here** — only the transactions, the billing period, and the card last-4 are in scope.

The platform boundary is unchanged and fixed by the constitution and locked decisions: **text extraction is native** — on iOS, the platform extracts the statement's text lines and full text and hands them to the shared engine; the shared engine **never** embeds a PDF engine. Its entry point is a pure seam that takes already-extracted text plus the full statement text and returns the parsed result.

### User Story 1 - Turn a Yes Bank (Kiwi) credit-card statement into transactions, on-device (Priority: P1)

A person imports their Yes Bank / Kiwi credit-card statement. The platform extracts the statement's text natively and hands it to the shared engine; the engine recognizes the document as a Yes Bank statement and returns the list of transactions — each with its date, amount, debit/credit direction, and description — computed entirely on the device with no network access.

**Why this priority**: This is the headline value and the smallest slice that turns a real Yes Bank / Kiwi statement into usable data. It is a viable increment on its own: a person gets their Yes transactions from their statement, on-device, exactly as they already can for ICICI, HDFC, and SBI. Every subsequent story refines this parse.

**Independent Test**: Provide the engine with the extracted text of a synthetic Yes Bank credit-card statement and confirm it recognizes the issuer and returns one transaction per matching row, each carrying a date, an exact amount, a direction, and a description — with no network access during the parse.

**Acceptance Scenarios**:

1. **Given** the extracted text of a synthetic Yes Bank credit-card statement (containing the issuer marker `YES BANK`), **When** the engine parses it, **Then** it recognizes the document as a Yes Bank statement and returns a transaction for each transaction row.
2. **Given** the synthetic Yes row `29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr`, **When** the engine parses it, **Then** it returns a transaction dated 2026-04-29, amount 9000.00, in Indian Rupees, with the description `PAYMENT RECEIVED BBPS - Ref No: RT0001`.
3. **Given** the synthetic Yes row `19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr`, **When** the engine parses it, **Then** it returns a transaction dated 2026-04-19, amount 100.00, in Indian Rupees, with the description `UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores` (the merchant-category text between the reference number and the amount is part of the description).
4. **Given** a statement that belongs to a different issuer (for example, an ICICI, HDFC, or SBI statement), **When** the Yes reader is asked whether it recognizes the document, **Then** it does not claim it, so the document is never misattributed to Yes.
5. **Given** the device has no network connectivity, **When** the statement is parsed, **Then** the transactions are still produced, proving the parse is fully local.

---

### User Story 2 - A fourth bank added with zero new engine infrastructure (Priority: P2)

As a maintainer, adding Yes must require **no new shared engine infrastructure** — only a new per-issuer reader configuration, a golden fixture, two UniFFI exports, and one parity case row. The day-first `DD/MM/YYYY` date format (e.g., `29/04/2026`) is already handled by the shared date parser (it is the same `%d/%m/%Y` format ICICI already relies on), and the two-letter `Dr`/`Cr` direction markers are already handled by the shared polarity classifier; Yes adds no new shared helper.

**Why this priority**: This is the distinctive point of the slice and the reason Yes was chosen as the fourth bank: it re-confirms the fixtures-driven, **incremental-by-bank** ingestion architecture scales with essentially no new engine code. Landing Yes green as a pure drop-in reader — a second clean single-layout bank after SBI — validates that the shared seam, helpers, harness, bridge, and privacy gate generalize to yet another bank without touching the engine internals.

**Independent Test**: Confirm the Yes parse is delivered by a new single-layout reader configuration that plugs into the existing `read_lines(lines, full_text)` seam, reusing the shared date parser (for `DD/MM/YYYY`) and polarity classifier (for `Dr`/`Cr`), and that **no new shared helper** is introduced or modified in the shared reader subsystem to support Yes.

**Acceptance Scenarios**:

1. **Given** the Yes reader, **When** it parses the `29/04/2026 … 9,000.00 Cr` row, **Then** the shared date parser interprets `29/04/2026` as 2026-04-29 using the existing `%d/%m/%Y` format (the one ICICI already uses), with no Yes-specific date code.
2. **Given** the Yes reader, **When** it classifies a row's direction, **Then** the shared polarity classifier maps the two-letter `Dr`/`Cr` marker to debit/credit with no Yes-specific direction code.
3. **Given** the change set that adds Yes, **When** it is reviewed, **Then** it consists of a new reader configuration, a golden fixture, two bridge exports, and one parity case row — and adds **no** new shared engine helper.

---

### User Story 3 - Debit/credit direction comes from the statement's Dr/Cr marker, never from the amount's sign (Priority: P3)

Each transaction's direction (money in vs money out) reflects the statement's own two-letter marker at the end of the row: `Cr` means credit and `Dr` means debit. The direction is never guessed from whether an amount looks positive, negative, or large, and never inferred from words in the description.

**Why this priority**: Correct direction is what makes the parsed data trustworthy for later categorization, dedup, and reconciliation. Reading polarity from the statement's own marker (never from the amount) is a non-negotiable engine rule; Yes expresses direction with an explicit terminal `Dr`/`Cr` marker, so honouring that marker is what makes Yes directions correct.

**Independent Test**: Parse rows ending in `Cr` and rows ending in `Dr` and confirm each is classified credit or debit from the statement's own marker — regardless of the amount's value and regardless of any credit/debit words appearing in the description.

**Acceptance Scenarios**:

1. **Given** a row whose final field is the marker `Cr` (e.g., the `PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr` line), **When** it is parsed, **Then** the transaction's direction is **credit**.
2. **Given** a row whose final field is the marker `Dr` (e.g., the `UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr` line), **When** it is parsed, **Then** the transaction's direction is **debit**.
3. **Given** a row whose description contains a direction-like word that conflicts with its marker, **When** it is parsed, **Then** the direction is taken from the terminal `Dr`/`Cr` marker and not from the description's wording.
4. **Given** any row, **When** it is parsed, **Then** the direction is decided solely from the statement's own `Dr`/`Cr` marker and never from the sign or magnitude of the amount.

---

### User Story 4 - Statement metadata: billing period and card last-4 (Priority: P4)

Beyond the individual transactions, the engine reads two pieces of statement-level context that later features (account attribution, coverage) depend on: the statement's billing period and the card's last four digits. The billing period is read from a `Statement Period: <from> To <to>` line, and the card last-4 is read from a masked card number anchored by `Card Number`.

**Why this priority**: The transactions are the core deliverable, but attributing them to a card and a billing period is what lets the app place them correctly later. This story confirms both derivations are correct for Yes's statement format and that, when a metadata field is not present, the engine leaves it unset rather than inventing a value.

**Independent Test**: Parse a synthetic Yes statement whose text carries a `Statement Period: … To …` line and a masked card number anchored by `Card Number`, and confirm the engine records the correct billing-period start/end and the correct card last-4.

**Acceptance Scenarios**:

1. **Given** statement text containing `Statement Period: 17/04/2026 To 16/05/2026`, **When** the engine parses it, **Then** the billing-period start is recorded as 2026-04-17 and the billing-period end as 2026-05-16.
2. **Given** statement text containing the masked card number anchored as `Statement for YES BANK Card Number 3561XXXXXXXX6686`, **When** the engine parses it, **Then** the card last-4 is recorded as `6686` (found via the `Card Number` anchor).
3. **Given** statement text containing no recognizable billing period or masked card number, **When** the engine parses it, **Then** the corresponding metadata is simply absent (left unset) rather than fabricated, and the transactions are still returned.

---

### User Story 5 - Reconciliation stays out of scope: printed debit/credit totals are not ported (Priority: P5)

The web engine's Yes reader also scrapes the statement's **printed** per-statement debit and credit totals (the "Purchases … Dr" and "Payment & Credits Received … Cr" summary values) for a future reconciliation feature. This slice deliberately **does not** port those printed-total fields: the Yes output model for this slice carries only the transactions, the billing-period start/end, and the card last-4. The printed totals belong to a later reconciliation slice.

**Why this priority**: This is the one place a faithful-looking full port would overreach. Keeping the printed-total scrape out of this slice's output model keeps the engine's shape identical to the ICICI/HDFC/SBI credit-card readers already landed (none of which expose printed totals), avoids shipping a half-built reconciliation surface, and draws a clean boundary for the future reconciliation work. It is a reviewable, testable scope guarantee.

**Independent Test**: Parse a synthetic Yes statement whose text also contains printed debit/credit total lines and confirm the engine returns only transactions + billing period + card last-4 — no printed-total values appear anywhere in the output, and the output model exposes no printed-total fields.

**Acceptance Scenarios**:

1. **Given** a Yes statement whose text *also* contains printed summary totals (for example, a `Purchases … Rs. … Dr` line and a `Payment & Credits Received … Rs. … Cr` line), **When** the engine parses it, **Then** those printed totals are **not** extracted — the result contains only the per-row transactions, the billing period, and the card last-4.
2. **Given** the Yes parsed-statement output model produced by this slice, **When** it is inspected, **Then** it carries **no** printed debit/credit total fields (they are deferred to a future reconciliation slice).
3. **Given** the ported Yes golden vector's expected output, **When** it is inspected, **Then** it contains **no** printed-total fields — only rows, billing-period start/end, card last-4, and errored lines.

---

### User Story 6 - Malformed rows are captured for review, never dropped or fatal (Priority: P6)

If a line looks like a transaction row but one of its fields will not parse, the engine keeps the raw line aside as an "errored line" for later review instead of crashing or silently discarding it — and it still returns every well-formed transaction from the same statement.

**Why this priority**: Real statements are messy. A single odd line must never take down the whole import or cause a person to lose the rest of their transactions. This resilience is what makes the parser safe to ship, and it is reused unchanged from the ICICI, HDFC, and SBI slices.

**Independent Test**: Parse a statement that mixes well-formed rows with a row whose fields cannot be parsed, and confirm the good rows are all returned, the bad row is captured for review, and no error is raised.

**Acceptance Scenarios**:

1. **Given** a statement containing one unparseable row among several valid rows, **When** the engine parses it, **Then** all valid rows are returned as transactions and no error is raised.
2. **Given** the same statement, **When** the engine parses it, **Then** the unparseable row is captured as an errored line (its raw text preserved, bounded to a safe maximum length) for review.
3. **Given** lines that are not transaction rows at all (headers, summaries, balances, totals), **When** the engine parses the statement, **Then** those lines are ignored without producing transactions and without being reported as errors.

---

### User Story 7 - Proven byte-for-byte against a golden fixture (Priority: P7)

As a maintainer, the engine's Yes behaviour is pinned to the proven web engine by porting the web engine's synthetic Yes characterization vector into the repository's `fixtures/` directory as a golden vector, with the on-device engine asserted to reproduce it exactly.

**Why this priority**: Parity is the constitution's acceptance mechanism for the port (Principle V). It turns "we think it matches" into an enforced, regression-proof guarantee, and it extends the harness that every later bank/card parser reuses — this time proving the harness accepts a fourth bank as a one-row addition.

**Independent Test**: Run the parity harness over the ported Yes vector and confirm the engine's output matches the expected output exactly, and that re-running produces identical results.

**Acceptance Scenarios**:

1. **Given** the ported synthetic Yes golden vector, **When** the parity harness runs, **Then** the engine's parsed output (dates, amounts, directions, descriptions, billing-period start/end, and card last-4) matches the expected output exactly — including the two rows (2026-04-29 / 9000.00 / credit and 2026-04-19 / 100.00 / debit), the billing period (2026-04-17 to 2026-05-16), and the card last-4 `6686`.
2. **Given** a change that alters Yes parsing behaviour, **When** the parity harness runs, **Then** it fails, enforcing the parity guarantee.
3. **Given** the golden fixture, **When** it is inspected, **Then** all input and expected data is synthetic or fully redacted (fabricated merchants, amounts, and masked card number) — never real account data.

---

### User Story 8 - Privacy gate: zero network in the parse path (Priority: P8)

As a maintainer, the existing automated privacy-egress test covers the Yes import/parse path and asserts it performs no network I/O, so the constitution's "free features run 100% on-device" guarantee holds for this slice and is protected against regressions.

**Why this priority**: Privacy is the product's non-negotiable promise and a required constitution gate. Extending the existing gate to cover Yes means the guarantee is proven for the new parser, not merely assumed.

**Independent Test**: Run the privacy-egress test against the Yes parse path and confirm it passes only when zero outbound network connections occur during parsing.

**Acceptance Scenarios**:

1. **Given** the Yes parse path, **When** the automated privacy-egress test runs, **Then** it confirms zero outbound network connections occur during parsing.
2. **Given** a regression that introduces any network access into the parse path, **When** the privacy-egress test runs, **Then** it fails, blocking the change.
3. **Given** the feature as a whole, **When** the engine and app are reviewed, **Then** no telemetry, analytics, advertising, or crash-reporting component is present in the parse path.

---

### Edge Cases

- **Wrong issuer**: A statement from another issuer (e.g., ICICI, HDFC, or SBI) is presented to the Yes reader → it must not claim the document, so transactions are never misattributed to Yes.
- **Terminal direction marker**: The two-letter `Dr`/`Cr` marker sits at the **end** of the row, after the amount → direction is read from that marker (`Cr` → credit, `Dr` → debit) and the marker is not mistaken for part of the description or the amount.
- **Merchant category inside the description**: When the row carries a merchant-category phrase between the reference number and the amount (e.g., `… Ref No: RT0002 Miscellaneous Stores 100.00 Dr`), that phrase is part of the transaction's description, not a separate field and not part of the amount.
- **Direction vs description wording**: A description containing a credit/debit-like word (e.g., `PAYMENT RECEIVED …`) → direction is still taken from the terminal `Dr`/`Cr` marker, not from the description text.
- **Indian money formatting**: Amounts with thousands separators, including the Indian grouping style (e.g., `1,23,456.78`) → parsed to the exact, non-negative decimal value, with stated precision preserved (e.g., `9,000.00` → 9000.00 keeps two decimal places).
- **Card last-4 via anchor**: The masked card number is located using the `Card Number` anchor (e.g., `Card Number 3561XXXXXXXX6686`) → the trailing four digits `6686` are recorded as the card last-4.
- **Printed totals present but excluded**: The statement text contains printed debit/credit summary totals → they are deliberately **not** extracted into this slice's output model (reconciliation is a later slice).
- **Non-transaction lines**: Header, summary, balance, and total lines → ignored (no transaction, no error).
- **Unparseable row**: A line that resembles a transaction row but whose fields will not parse → captured as an errored line; every good row in the same statement is still returned; no error is raised.
- **No transaction lines**: Empty input, or input with no recognizable rows → an empty transaction list is returned with no error.
- **Missing metadata**: No recognizable billing period or masked card number in the text → billing-period start/end and card last-4 are left unset rather than fabricated.
- **Repeated / concurrent parses**: The same input parsed repeatedly → identical results every time, with no dependence on wall-clock time, locale, or hidden global state.

## Requirements *(mandatory)*

### Functional Requirements

**Document recognition**

- **FR-001**: The engine MUST recognize a statement as a Yes Bank (Kiwi) credit-card statement via an issuer/document-plausibility check — the statement text contains the Yes Bank issuer marker (`YES BANK`) — before parsing it as Yes.
- **FR-002**: The engine MUST NOT claim a statement that belongs to a different issuer (e.g., an ICICI, HDFC, or SBI statement), so a document is only parsed by the reader that recognizes it.

**Transaction extraction (the core parse)**

- **FR-003**: The engine MUST parse Yes's single credit-card statement layout `DD/MM/YYYY <details … Ref No> <Merchant Category> <amount> Dr|Cr` — a day-first `DD/MM/YYYY` date, followed by the description (details, reference number, and any merchant-category text), the amount, and a terminal two-letter `Dr`/`Cr` direction marker — and MUST produce exactly one transaction per matching row.
- **FR-004**: Each produced transaction MUST include the transaction date, the amount, the debit/credit direction, the description text, and the currency (Indian Rupees, INR).
- **FR-005**: Lines that are not transaction rows (headers, summaries, balances, totals) MUST be ignored without producing transactions or errors.

**Amount**

- **FR-006**: The engine MUST parse each amount as an exact, non-negative decimal using Indian number formatting (thousands separators, including the Indian grouping style), preserving the stated precision (e.g., `9,000.00` → 9000.00 retains two decimal places).
- **FR-007**: Monetary amounts MUST NEVER be represented as floating-point numbers; they MUST be exact decimals throughout.

**Direction / polarity**

- **FR-008**: The engine MUST determine each transaction's debit/credit direction from the statement's own terminal `Dr`/`Cr` marker and MUST NEVER infer it from the sign or magnitude of the amount, nor from words in the description.
- **FR-009**: The terminal marker MUST set the direction: `Cr` → credit, `Dr` → debit.

**Statement metadata**

- **FR-010**: The engine MUST derive the billing period from text of the form `Statement Period: <DD/MM/YYYY> To <DD/MM/YYYY>` (e.g., `Statement Period: 17/04/2026 To 16/05/2026`), setting the billing-period start and end to the two parsed dates (start = 2026-04-17, end = 2026-05-16 for that example).
- **FR-011**: The engine MUST extract the card's last four digits from a masked card number located via the `Card Number` anchor (e.g., `Card Number 3561XXXXXXXX6686` → `6686`).
- **FR-012**: When a metadata field cannot be found, the engine MUST leave it unset rather than fabricate a value, and MUST still return the parsed transactions.

**Scope boundary — reconciliation excluded**

- **FR-013**: This slice MUST NOT port the web engine's Yes printed-total scrape: the printed per-statement debit/credit totals (the "Purchases … Dr" / "Payment & Credits Received … Cr" summary values) MUST NOT appear in this slice's output model. The Yes parsed result for this slice MUST carry only the transactions, the billing-period start/end, the card last-4, and any errored lines. (Printed totals are deferred to a future reconciliation slice.)

**Robustness**

- **FR-014**: A line that resembles a transaction row but whose fields cannot be parsed MUST be captured as an "errored line" (raw text preserved, bounded to a safe maximum length) for later review; the engine MUST NOT raise an error or silently drop it, and MUST still return every successfully parsed row.

**Engine purity, platform boundary & reuse**

- **FR-015**: The engine's Yes parse MUST reuse the existing "one transaction per text line" reader seam — accepting already-extracted text lines plus the full statement text and returning the parsed result; it MUST NOT read files, extract PDF text, or embed a PDF engine (text extraction is a native platform concern).
- **FR-016**: The engine MUST remain pure and deterministic: identical input MUST yield identical output, with no dependence on network, wall-clock time, locale, or hidden global mutable state.
- **FR-017**: Yes MUST reuse — not rebuild — the existing shared output types (parsed statement / parsed transaction), the amount / date / last-4 / polarity helpers (including the `%d/%m/%Y` date format already used by ICICI and the two-letter `Dr`/`Cr` marker classification), the golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate. This slice MUST add **no new shared engine helper**; Yes is delivered as a new single-layout reader configuration only.
- **FR-018**: The engine MUST expose Yes over the existing UniFFI bridge with a Yes parse entry point and a Yes issuer-claims function, mirroring the ICICI, HDFC, and SBI surfaces (two exports).

**Privacy (constitution Principle I — NON-NEGOTIABLE)**

- **FR-019**: The entire Yes import/parse path MUST run 100% on-device with ZERO network I/O.
- **FR-020**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting into the engine or the app.
- **FR-021**: The existing automated privacy-egress test MUST cover the Yes parse path and assert it performs no network access; it remains a required constitution gate.

**Parity & test-first (constitution Principle V)**

- **FR-022**: The web engine's synthetic Yes characterization vector MUST be ported into the repository's `fixtures/` directory (under `fixtures/yes/credit_card/`) as a golden vector, and the engine MUST reproduce it exactly.
- **FR-023**: All fixture and test data MUST be synthetic or fully redacted (fabricated merchants, amounts, and masked card number) — never real account data.
- **FR-024**: The Yes parsing behaviour introduced by this slice MUST be developed test-first (a failing golden test precedes the behaviour).

**Licensing, secrets & quality gates**

- **FR-025**: The change MUST NOT add secrets, API keys, or private endpoints; MUST remain distributable under Apache-2.0 with no copyleft (GPL/AGPL/LGPL) dependencies; and MUST introduce NO new runtime dependencies for this slice.
- **FR-026**: The change MUST keep the iOS Local Verification Gate and CI green: core formatting, linting, and tests; app linting; project generation; a simulator build with passing app tests; and the privacy gate.
- **FR-027**: If any user-facing surface is introduced for this slice, it MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility.

### Key Entities *(include if feature involves data)*

- **Extracted statement text (input)**: The already-extracted text lines plus the full statement text handed to the engine by the native platform. Contains no PDF binary; the engine never opens a PDF.
- **Parsed transaction**: One statement row's result — a transaction date, an exact non-negative amount, an explicit debit/credit direction, a currency (INR), and a description.
- **Parsed statement result**: The full output of reading one statement — the issuer/bank identity (`YES`), the list of parsed transactions, the list of errored (unparseable) lines, the billing-period start and end dates, and the card last-4. For this slice the result deliberately excludes the printed debit/credit totals used for reconciliation.
- **Direction (polarity)**: An explicit debit or credit indicator carried on every transaction, sourced from the statement's own terminal `Dr`/`Cr` marker and never from the amount's sign.
- **Golden characterization vector**: A synthetic Yes input (text lines + full text) paired with its expected engine output, stored under `fixtures/yes/credit_card/`, ported from the web engine and reproduced exactly by the on-device engine.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For the two synthetic Yes golden rows, the engine produces exactly the expected transactions — row 1 → date 2026-04-29, amount 9000.00, direction credit, description `PAYMENT RECEIVED BBPS - Ref No: RT0001`; row 2 → date 2026-04-19, amount 100.00, direction debit, description `UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores` (100% match).
- **SC-002**: The engine recognizes the synthetic Yes statement as Yes and does not claim a non-Yes (e.g., ICICI, HDFC, or SBI) statement — 0 misattributions across the recognition cases.
- **SC-003**: From the synthetic Yes statement text, the engine records the billing-period start as 2026-04-17, the billing-period end as 2026-05-16, and the card last-4 as `6686`.
- **SC-004**: Direction is correct across every tested case — a terminal `Cr` → credit and a terminal `Dr` → debit — and is never changed by the amount's sign or magnitude, nor by direction-like words in the description.
- **SC-005**: 100% of parsed amounts are exact decimals with their stated precision preserved and are always non-negative; no monetary value is ever a floating-point number.
- **SC-006**: A malformed row is captured for review while every well-formed row in the same input is still returned, and no error is raised (the parse never aborts on a bad row).
- **SC-007**: Zero outbound network connections occur during the entire Yes parse path, verified by the automated privacy-egress test.
- **SC-008**: Given identical input, the engine returns identical output across repeated runs (100% reproducible).
- **SC-009**: The ported synthetic Yes golden vector reproduces exactly and the parity harness passes; re-running is stable.
- **SC-010**: Yes is added with **zero new shared engine helpers** — the change consists only of a new single-layout reader configuration, a golden fixture, two UniFFI exports, and one parity case row; the shared reader/date/polarity/last-4 helper surface is unchanged (verified by review of the change set).
- **SC-011**: All automated checks required to merge pass (green), including the parity harness and the privacy-egress test, with the iOS Local Verification Gate and CI green.
- **SC-012**: No secrets, network entitlements, telemetry, copyleft-licensed dependencies, or new runtime dependencies are added by the feature (verified by review of manifests and dependencies).
- **SC-013**: The Yes output model and its golden vector carry only transactions, billing-period start/end, and card last-4 (plus errored lines) — the printed debit/credit totals the web reader extracts for reconciliation are **absent** (verified by review of the output model and the fixture's expected output).

## Assumptions

- **Single-layout reader & seam**: Yes is added as a **single-layout** reader configuration reusing the existing `read_lines(lines, full_text)` seam; there is exactly one row layout (`DD/MM/YYYY <details … Ref No> <Merchant Category> <amount> Dr|Cr`). The exact module layout and row pattern are finalized in `/speckit.plan`.
- **No new shared helpers**: Yes needs **no** new shared engine helpers. Its `DD/MM/YYYY` date format is the same `%d/%m/%Y` the shared date parser already applies for ICICI, and its two-letter `Dr`/`Cr` direction markers are already handled by the shared polarity classifier. This makes Yes a clean single-layout drop-in, like SBI.
- **Reconciliation carve-out**: The web engine's Yes reader also extracts printed debit/credit totals (`printed_total_debits` / `printed_total_credits`) for reconciliation. Those fields are **out of scope** for this slice and are deliberately **not** ported into the output model; they belong to a future reconciliation slice. This matches the already-landed ICICI/HDFC/SBI credit-card readers, none of which expose printed totals.
- **Binding**: Yes is exposed to Swift via the existing UniFFI bridge with a Yes parse entry point and a Yes issuer-claims function, mirroring ICICI, HDFC, and SBI (two exports); concrete binding mechanics belong in `/speckit.plan`.
- **Fixtures location**: The golden fixture lives under `fixtures/yes/credit_card/` and is the source of truth for parity.
- **Bank code**: The issuer/bank identity for this reader is `YES`.
- **Reused, not rebuilt**: The `read_lines` seam and per-issuer reader configuration, the parsed-statement / parsed-transaction output types, the amount / date / last-4 / polarity helpers, the golden-fixture JSON parity harness, the UniFFI bridge, and the privacy-egress gate were all built in the ICICI slice (and extended in the HDFC and SBI slices); Yes plugs into every one of them unchanged.
- **No new dependencies**: This slice should require **no** new runtime dependencies.
- **Source of truth**: The web engine is the source of truth for behaviour — `yes_kiwi.py` plus the shared line-reader, common helpers, and polarity module, and the credit-card characterization test (`test_cc_reader_characterization.py`, whose Yes case values are reproduced in this spec). The porting approach (module layout, patterns, regexes, fixture format, UniFFI exports) is decided in `/speckit.plan`, not here.
- **No new UI required**: This is an engine slice; no user-facing UI is required to deliver it. App-side PDF text extraction (PDFKit wiring), the file-import UI, and the Share Extension remain a native concern and a later step. If a trivial demo surface is added, it follows HIG and accessibility (FR-027).
- **Data safety**: All fixture and test data is synthetic or fully redacted — no real account data.
- **Money & polarity**: Amounts are exact decimals (never floating-point) and direction is carried explicitly and sourced from the statement's terminal `Dr`/`Cr` marker, consistent with the engine's existing domain types.

### Dependencies

- **Kaname Constitution v1.0.0** — privacy (zero-network free/core), determinism, a pure platform-agnostic core (no PDF engine), decimal money with explicit polarity, Apache-2.0 open-core with no copyleft, native HIG/accessibility, and the test-first iOS Local Verification Gate (including the privacy-egress gate).
- **Milestone P2 — ICICI slice (already landed)** — the shared "one transaction per text line" reader seam, the parsed-statement / parsed-transaction domain types, the amount / date / last-4 / polarity helpers (including the `%d/%m/%Y` date format and Dr/Cr marker classification Yes reuses), the golden-fixture parity harness, and the privacy-egress gate.
- **Milestone P2 — HDFC slice (already landed)** — the second parser, which proved the seam generalizes to a multi-layout bank.
- **Milestone P2 — SBI slice (already landed)** — the third parser and the first clean single-layout drop-in, whose pattern Yes follows exactly (a new reader configuration, a golden fixture, two bridge exports, and one parity case row, with no new shared helpers).
- **Milestone P1 bridge (already landed)** — the shared engine crate and the UniFFI Swift binding proven end-to-end, over which the Yes parse and claims functions are exposed.
- **Web engine golden vector** — the synthetic Yes characterization vector and the Yes reader behaviour used as the parity source of truth.

## Out of Scope

Deferred to later P2 slices / milestones:

- **Reconciliation** (the printed-total integrity check) — **including the printed per-statement debit/credit totals the web Yes reader extracts** (`printed_total_debits` / `printed_total_credits`); these are explicitly not ported in this slice — plus **coverage / billing-period timeline**, **cross-source de-duplication and transfer detection**, and **balance-chain integrity**.
- **The remaining bank/card parsers** — the Federal credit card, and the bank-account ledger readers.
- The `(bank_code, account_kind)` registry **beyond what Yes needs**.
- **Encrypted SQLite / SQLCipher persistence** and key management.
- **AI-fallback parsing**.
- Any **premium / cloud features**.
- **App-side PDF text extraction** (PDFKit wiring in the app) and the **file-import UI / Share Extension** — native concerns handled in a later slice. This slice focuses on the Yes engine parse plus its golden-fixture parity, reusing the existing privacy gate and exposed over the existing bridge.
