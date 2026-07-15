# Feature Specification: Import an HDFC Credit-Card Statement On-Device (Second Real Parser, Two Layouts)

**Feature Branch**: `003-hdfc-cc-parser`  
**Created**: 2026-07-15  
**Status**: Draft  
**Milestone**: P2 (next slice) — the second real statement parser in the shared engine  
**Input**: User description: "P2 (next slice) — Import an HDFC credit-card statement on-device: the second real statement parser, proving the reusable 'one transaction per line' reader seam and the golden-fixture parity harness (built for ICICI) generalize to a new bank with a different — and two-layout — statement format."

> **Note on priority labels**: This feature is milestone **P2** in the product roadmap (`docs/kaname-ios-plan.md` §9). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P2" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

The previous slice (milestone P2, first slice) landed the first real parser — ICICI — and, with it, two things every later parser reuses: the shared **"one transaction per text line"** parsing seam and the **golden-fixture parity** harness that pins the on-device engine to the proven web engine. This slice delivers the **second** bank, HDFC, and proves those foundations generalize: a person imports their HDFC credit-card statement and the app produces the list of transactions — date, exact amount, debit/credit direction, and description — entirely on-device, with no network and no account, exactly as it already does for ICICI. HDFC is the next bank in the fixtures-driven, **incremental-by-bank** ingestion roadmap; landing it green with its golden vectors demonstrates the shared engine scales bank-by-bank.

HDFC is also the first parser that must read **two different statement layouts** behind a single reader — a year-end consolidated layout and a monthly co-brand layout — so it is the slice that proves the reader seam handles a multi-layout bank without the caller ever knowing which layout applied.

The platform boundary is unchanged and fixed by the constitution and locked decisions: **text extraction is native** — on iOS, the platform extracts the statement's text lines and full text and hands them to the shared engine; the shared engine **never** embeds a PDF engine. Its entry point is a pure seam that takes already-extracted text plus the full statement text and returns the parsed result.

### User Story 1 - Turn an HDFC credit-card statement into transactions, on-device (Priority: P1)

A person imports their HDFC credit-card statement. The platform extracts the statement's text natively and hands it to the shared engine; the engine recognizes the document as an HDFC credit-card statement and returns the list of transactions — each with its date, amount, debit/credit direction, and description — computed entirely on the device with no network access.

**Why this priority**: This is the headline value and the smallest slice that turns a real HDFC statement into usable data. It is a viable increment on its own: a person gets their HDFC transactions from their statement, on-device, exactly as they already can for ICICI. Every subsequent story refines this parse.

**Independent Test**: Provide the engine with the extracted text of a synthetic HDFC credit-card statement and confirm it recognizes the issuer and returns one transaction per row, each carrying a date, an exact amount, a direction, and a description — with no network access during the parse.

**Acceptance Scenarios**:

1. **Given** the extracted text of a synthetic HDFC credit-card statement (containing the issuer marker `HDFC Bank Credit Cards`), **When** the engine parses it, **Then** it recognizes the document as an HDFC credit-card statement and returns a transaction for each transaction row.
2. **Given** the synthetic HDFC year-end row `16-Apr-2025 ONLINE TRF - PYMT RECD - THANK YOU 10,610.00 CR 526873XXXXXX9070`, **When** the engine parses it, **Then** it returns a transaction dated 2025-04-16, amount 10610.00, in Indian Rupees, with a description preserving the row's descriptive text.
3. **Given** the synthetic HDFC year-end row `04-Apr-2025 WWW EXAMPLE COM GURGAON 1,071.00 DR 526873XXXXXX9070`, **When** the engine parses it, **Then** it returns a transaction dated 2025-04-04, amount 1071.00, in Indian Rupees.
4. **Given** a statement that belongs to a different issuer (for example, an ICICI statement), **When** the HDFC reader is asked whether it recognizes the document, **Then** it does not claim it, so the document is never misattributed to HDFC.
5. **Given** the device has no network connectivity, **When** the statement is parsed, **Then** the transactions are still produced, proving the parse is fully local.

---

### User Story 2 - One reader, two layouts: year-end and monthly, auto-selected (Priority: P2)

HDFC issues its credit-card statements in two different formats: a **year-end consolidated** layout (`DD-Mon-YYYY <description> <amount> DR|CR`) and a **monthly co-brand** layout (`DD/MM/YYYY| HH:MM <merchant> [+ ]C <amount>`). A person may import either. The single HDFC reader parses whichever layout the statement uses — trying the year-end layout first and falling back to the monthly layout — so the caller never has to know or choose which format applies.

**Why this priority**: This is the distinctive capability of the slice and the reason HDFC was chosen as the second bank: it proves the shared "one transaction per line" seam generalizes to a bank with **more than one** row format. Landing it establishes the reusable "try multiple layouts in order" capability that later multi-layout banks will depend on.

**Independent Test**: Parse a synthetic statement in the year-end layout and a synthetic statement in the monthly layout through the *same* HDFC reader, and confirm each yields the correct transactions without the caller selecting a layout — the year-end layout is attempted first, the monthly layout is used as the fallback.

**Acceptance Scenarios**:

1. **Given** a synthetic HDFC statement in the **year-end** layout, **When** the single HDFC reader parses it, **Then** it returns the year-end transactions correctly, without the caller specifying a layout.
2. **Given** a synthetic HDFC statement in the **monthly** layout (e.g., a row like `14/05/2026| 13:30 EXAMPLE MERCHANT BANGALORE C 1,639.00`), **When** the same HDFC reader parses it, **Then** it falls back to the monthly layout and returns the monthly transactions correctly — the leading `C` produced from the extracted Rupee glyph is not mistaken for the amount (amount parses as 1639.00) and is not folded into the description.
3. **Given** a monthly-layout row, **When** the engine reads its date `DD/MM/YYYY`, **Then** the date is interpreted day-first (e.g., `14/05/2026` → 2026-05-14).
4. **Given** a statement that matches **neither** HDFC layout, **When** the reader parses it, **Then** it returns an empty transaction list without raising an error (rather than misparsing rows).

---

### User Story 3 - Debit/credit direction comes from the statement, never from the amount's sign (Priority: P3)

Each transaction's direction (money in vs money out) reflects the statement's own indication, in whichever layout the statement uses. In the year-end layout the direction is read from the explicit `DR`/`CR` marker that sits immediately after the amount; in the monthly layout a leading `+` before the amount marks a payment/credit and its absence marks a spend (debit). The direction is never guessed from whether an amount looks positive, negative, or large.

**Why this priority**: Correct direction is what makes the parsed data trustworthy for later categorization, dedup, and reconciliation. Reading polarity from the statement (never from the amount) is a non-negotiable engine rule; because HDFC expresses direction two different ways across its two layouts, getting each right is essential.

**Independent Test**: Parse year-end rows carrying `CR` and `DR` markers and monthly rows with and without a leading `+`, and confirm each is classified credit or debit from the statement's own indication — regardless of the amount's value.

**Acceptance Scenarios**:

1. **Given** a year-end row whose amount is immediately followed by the marker `CR` (e.g., the `ONLINE TRF - PYMT RECD - THANK YOU 10,610.00 CR` line), **When** it is parsed, **Then** the transaction's direction is **credit**.
2. **Given** a year-end row whose amount is immediately followed by the marker `DR` (e.g., the `WWW EXAMPLE COM GURGAON 1,071.00 DR` line), **When** it is parsed, **Then** the transaction's direction is **debit**.
3. **Given** a monthly row whose amount is preceded by a leading `+` (e.g., a `CC PAYMENT RECEIVED + C 6,738.00` line), **When** it is parsed, **Then** the transaction's direction is **credit**.
4. **Given** a monthly row whose amount has no leading `+`, **When** it is parsed, **Then** the transaction's direction is **debit** (a spend).
5. **Given** any row in either layout, **When** it is parsed, **Then** the direction is decided solely from the statement's own indication and never from the sign or magnitude of the amount.

---

### User Story 4 - Statement metadata: billing period and card last-4, for both layouts (Priority: P4)

Beyond the individual transactions, the engine reads two pieces of statement-level context that later features (account attribution, coverage, reconciliation) depend on: the statement's billing period and the card's last four digits — derived correctly from whichever layout the statement uses.

**Why this priority**: The transactions are the core deliverable, but attributing them to a card and a billing period is what lets the app place them correctly later. HDFC expresses the billing period differently in each layout, so this story confirms both derivations are correct and self-contained.

**Independent Test**: Parse a synthetic year-end statement whose text carries a "period from … to …" summary and a masked card number, and a synthetic monthly statement whose text carries a "Billing Period …" line, and confirm the engine records the correct billing-period start/end and the card's last four digits in each case.

**Acceptance Scenarios**:

1. **Given** year-end text containing `Account Summary for the period from APRIL-25 to MARCH-26`, **When** the engine parses it, **Then** the billing-period end is recorded as the **last** day of the closing month (2026-03-31) and the billing-period start as the **first** day of the opening month (2025-04-01).
2. **Given** monthly text containing `Billing Period 15 May, 2026 - 14 Jun, 2026`, **When** the engine parses it, **Then** the billing-period start is recorded as 2026-05-15 and the billing-period end as 2026-06-14.
3. **Given** statement text containing the masked card number anchored as `Card Number XXXX6873XXXXXX9070`, **When** the engine parses it, **Then** the card's last four digits are recorded as `9070`.
4. **Given** statement text containing no recognizable billing period or masked card number, **When** the engine parses it, **Then** the corresponding metadata is simply absent (left unset) rather than fabricated, and the transactions are still returned.

---

### User Story 5 - Malformed rows are captured for review, never dropped or fatal (Priority: P5)

If a line looks like a transaction row but one of its fields will not parse, the engine keeps the raw line aside as an "errored line" for later review instead of crashing or silently discarding it — and it still returns every well-formed transaction from the same statement, in either layout.

**Why this priority**: Real statements are messy. A single odd line must never take down the whole import or cause a person to lose the rest of their transactions. This resilience is what makes the parser safe to ship, and it is reused unchanged from the ICICI slice.

**Independent Test**: Parse a statement that mixes well-formed rows with a row whose fields cannot be parsed, and confirm the good rows are all returned, the bad row is captured for review, and no error is raised.

**Acceptance Scenarios**:

1. **Given** a statement containing one unparseable row among several valid rows, **When** the engine parses it, **Then** all valid rows are returned as transactions and no error is raised.
2. **Given** the same statement, **When** the engine parses it, **Then** the unparseable row is captured as an errored line (its raw text preserved, bounded to a safe maximum length) for review.
3. **Given** lines that are not transaction rows at all (headers, summaries, balances, totals), **When** the engine parses the statement, **Then** those lines are ignored without producing transactions and without being reported as errors.

---

### User Story 6 - Proven byte-for-byte against golden fixtures (both layouts) (Priority: P6)

As a maintainer, the engine's HDFC behaviour is pinned to the proven web engine by porting the web engine's synthetic HDFC **year-end** characterization vector into the repository's `fixtures/` directory as a golden vector, and by adding a synthetic **monthly-layout** golden vector to prove the second layout and the leading-`+` credit rule — with the on-device engine asserted to reproduce both exactly.

**Why this priority**: Parity is the constitution's acceptance mechanism for the port (Principle V). It turns "we think it matches" into an enforced, regression-proof guarantee, and — by adding a second layout to the fixture set — it extends the harness that every later bank/card parser reuses.

**Independent Test**: Run the parity harness over the ported year-end vector and the new monthly vector and confirm the engine's output matches the expected output exactly for each, and that re-running produces identical results.

**Acceptance Scenarios**:

1. **Given** the ported synthetic HDFC **year-end** golden vector, **When** the parity harness runs, **Then** the engine's parsed output (dates, amounts, directions, descriptions, billing-period start/end, and card last-4) matches the expected output exactly.
2. **Given** the synthetic HDFC **monthly** golden vector — whose expected output is captured from a live run of the web engine's HDFC reader (never hand-derived) — **When** the parity harness runs, **Then** the engine reproduces it exactly, proving the monthly layout and the leading-`+` credit rule.
3. **Given** a change that alters HDFC parsing behaviour, **When** the parity harness runs, **Then** it fails, enforcing the parity guarantee.
4. **Given** the golden fixtures, **When** they are inspected, **Then** all input and expected data is synthetic or fully redacted (fabricated merchants, amounts, and masked card numbers) — never real account data.

---

### User Story 7 - Privacy gate: zero network in the parse path (Priority: P7)

As a maintainer, the existing automated privacy-egress test covers the HDFC import/parse path and asserts it performs no network I/O, so the constitution's "free features run 100% on-device" guarantee holds for this slice and is protected against regressions.

**Why this priority**: Privacy is the product's non-negotiable promise and a required constitution gate. Extending the existing gate to cover HDFC means the guarantee is proven for the new parser, not merely assumed.

**Independent Test**: Run the privacy-egress test against the HDFC parse path and confirm it passes only when zero outbound network connections occur during parsing.

**Acceptance Scenarios**:

1. **Given** the HDFC parse path, **When** the automated privacy-egress test runs, **Then** it confirms zero outbound network connections occur during parsing.
2. **Given** a regression that introduces any network access into the parse path, **When** the privacy-egress test runs, **Then** it fails, blocking the change.
3. **Given** the feature as a whole, **When** the engine and app are reviewed, **Then** no telemetry, analytics, advertising, or crash-reporting component is present in the parse path.

---

### Edge Cases

- **Wrong issuer**: A statement from another issuer (e.g., ICICI) is presented to the HDFC reader → it must not claim the document, so transactions are never misattributed to HDFC.
- **Two layouts, one reader**: A year-end statement and a monthly statement each parse through the *single* HDFC reader; the year-end layout is attempted first and the monthly layout is the fallback. A statement matching neither layout yields an empty transaction list with no error.
- **Monthly Rupee glyph**: The leading `C` produced when the Rupee glyph is extracted in the monthly layout → not mistaken for the amount and not folded into the description.
- **Monthly credit marker**: A leading `+` before a monthly amount → credit; its absence → debit (spend).
- **Year-end mid-line direction**: The `DR`/`CR` marker sits immediately after the amount (not at line end — a trailing masked card number may follow it) → direction is read from that marker and the trailing masked number is ignored.
- **Indian money formatting**: Amounts with thousands separators, including the Indian grouping style (e.g., `1,23,456.78`) → parsed to the exact, non-negative decimal value, with stated precision preserved (e.g., `10,610.00` keeps two decimal places).
- **Month-name period derivation (year-end)**: `period from APRIL-25 to MARCH-26` → billing-period start is the first day of the opening month (2025-04-01) and billing-period end is the last day of the closing month (2026-03-31).
- **Non-transaction lines**: Header, summary, balance, and total lines → ignored (no transaction, no error).
- **Unparseable row**: A line that resembles a transaction but whose fields will not parse → captured as an errored line; every good row in the same statement is still returned; no error is raised.
- **No transaction lines**: Empty input, or input with no recognizable rows → an empty transaction list is returned with no error.
- **Repeated / concurrent parses**: The same input parsed repeatedly → identical results every time, with no dependence on wall-clock time, locale, or hidden global state.
- **Missing metadata**: No recognizable billing period or masked card number in the text → billing-period start/end and card last-4 are left unset rather than fabricated.

## Requirements *(mandatory)*

### Functional Requirements

**Document recognition**

- **FR-001**: The engine MUST recognize a statement as an HDFC credit-card statement via an issuer/document-plausibility check — the statement text contains an HDFC credit-card issuer marker (`HDFC Bank Credit Card` or `HDFC Bank Credit Cards`) — before parsing it as HDFC.
- **FR-002**: The engine MUST NOT claim a statement that belongs to a different issuer (e.g., an ICICI statement), so a document is only parsed by the reader that recognizes it.

**Two-layout composite reader**

- **FR-003**: The engine MUST support HDFC's two credit-card statement layouts behind a single reader: (a) the **year-end consolidated** layout `DD-Mon-YYYY <description> <amount> DR|CR` and (b) the **monthly co-brand** layout `DD/MM/YYYY| HH:MM <merchant> [+ ]C <amount>`.
- **FR-004**: The single HDFC reader MUST try the year-end layout first and fall back to the monthly layout, so a statement in either layout is parsed without the caller needing to know or select which layout applies; if neither layout yields any rows, an empty result is returned without error.

**Transaction extraction (the core parse)**

- **FR-005**: For each HDFC transaction row in the recognized layout, the engine MUST produce exactly one transaction.
- **FR-006**: Each produced transaction MUST include the transaction date, the amount, the debit/credit direction, the description text, and the currency (Indian Rupees, INR).
- **FR-007**: Lines that are not transaction rows (headers, summaries, balances, totals) MUST be ignored without producing transactions or errors.

**Amount**

- **FR-008**: The engine MUST parse each amount as an exact, non-negative decimal using Indian number formatting (thousands separators, including the Indian grouping style), preserving the stated precision (e.g., `10,610.00` → 10610.00 retains two decimal places). In the monthly layout, the leading `C` produced when the Rupee glyph is extracted MUST NOT be treated as part of the amount.
- **FR-009**: Monetary amounts MUST NEVER be represented as floating-point numbers; they MUST be exact decimals throughout.

**Direction / polarity**

- **FR-010**: The engine MUST determine each transaction's debit/credit direction from the statement's own indication and MUST NEVER infer it from the sign or magnitude of the amount.
- **FR-011**: In the **year-end** layout, the explicit marker immediately following the amount MUST set the direction: `CR` → credit, `DR` → debit.
- **FR-012**: In the **monthly** layout, a leading `+` before the amount MUST classify the transaction as a credit; the absence of a leading `+` MUST classify it as a debit (spend).

**Statement metadata**

- **FR-013**: For the **year-end** layout, the engine MUST derive the billing period from text of the form `Account Summary for the period from <MONTH-YY> to <MONTH-YY>`, setting the billing-period end to the **last** day of the closing month (e.g., `MARCH-26` → 2026-03-31) and the billing-period start to the **first** day of the opening month (e.g., `APRIL-25` → 2025-04-01).
- **FR-014**: For the **monthly** layout, the engine MUST derive the billing period from text of the form `Billing Period <DD Mon, YYYY> - <DD Mon, YYYY>`, setting the billing-period start and end to the two parsed dates.
- **FR-015**: The engine MUST extract the card's last four digits from a masked card number found via the `Card Number` anchor (e.g., `Card Number XXXX6873XXXXXX9070` → `9070`).
- **FR-016**: When a metadata field cannot be found, the engine MUST leave it unset rather than fabricate a value, and MUST still return the parsed transactions.

**Robustness**

- **FR-017**: A line that resembles a transaction row but whose fields cannot be parsed MUST be captured as an "errored line" (raw text preserved, bounded to a safe maximum length) for later review; the engine MUST NOT raise an error or silently drop it, and MUST still return every successfully parsed row.

**Engine purity, platform boundary & reuse**

- **FR-018**: The engine's HDFC parse MUST reuse the existing "one transaction per text line" reader seam — accepting already-extracted text lines plus the full statement text and returning the parsed result; it MUST NOT read files, extract PDF text, or embed a PDF engine (text extraction is a native platform concern).
- **FR-019**: The engine MUST remain pure and deterministic: identical input MUST yield identical output, with no dependence on network, wall-clock time, locale, or hidden global mutable state.
- **FR-020**: HDFC MUST reuse — not rebuild — the existing shared output types (parsed statement / parsed transaction), the amount/date/last-4/polarity helpers, the golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate. The modest new engine-internal helpers HDFC requires — a month-name-and-year → month-end date helper, a monthly leading-`+` credit rule, and ordered multi-layout row matching (the composite reader) — MUST be added to the shared reader subsystem so later multi-layout banks can reuse them.
- **FR-021**: The engine MUST expose HDFC over the existing UniFFI bridge with an HDFC parse entry point and an HDFC issuer-claims function, mirroring the ICICI surface.

**Privacy (constitution Principle I — NON-NEGOTIABLE)**

- **FR-022**: The entire HDFC import/parse path MUST run 100% on-device with ZERO network I/O.
- **FR-023**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting into the engine or the app.
- **FR-024**: The existing automated privacy-egress test MUST cover the HDFC parse path and assert it performs no network access; it remains a required constitution gate.

**Parity & test-first (constitution Principle V)**

- **FR-025**: The web engine's synthetic HDFC **year-end** characterization vector MUST be ported into the repository's `fixtures/` directory (under `fixtures/hdfc/credit_card/`) as a golden vector, and the engine MUST reproduce it exactly.
- **FR-026**: A synthetic **monthly-layout** HDFC golden fixture MUST additionally be added (fabricated merchants, amounts, and masked card number) to prove the second layout and the leading-`+` credit rule; its expected output MUST be captured from a live run of the web engine's HDFC reader and never hand-derived.
- **FR-027**: All fixture and test data MUST be synthetic or fully redacted (fabricated merchants, amounts, and masked card numbers) — never real account data.
- **FR-028**: The HDFC parsing behaviour introduced by this slice MUST be developed test-first (a failing golden test precedes the behaviour).

**Licensing, secrets & quality gates**

- **FR-029**: The change MUST NOT add secrets, API keys, or private endpoints; MUST remain distributable under Apache-2.0 with no copyleft (GPL/AGPL/LGPL) dependencies; and MUST introduce NO new runtime dependencies for this slice.
- **FR-030**: The change MUST keep the iOS Local Verification Gate and CI green: core formatting, linting, and tests; app linting; project generation; a simulator build with passing app tests; and the privacy gate.
- **FR-031**: If any user-facing surface is introduced for this slice, it MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility.

### Key Entities *(include if feature involves data)*

- **Extracted statement text (input)**: The already-extracted text lines plus the full statement text handed to the engine by the native platform. Contains no PDF binary; the engine never opens a PDF.
- **Statement layout (year-end / monthly)**: The two recognized HDFC row formats. The single HDFC reader selects between them by trying the year-end layout first and falling back to the monthly layout; the caller is unaware of which matched.
- **Parsed transaction**: One statement row's result — a transaction date, an exact non-negative amount, an explicit debit/credit direction, a currency (INR), and a description.
- **Parsed statement result**: The full output of reading one statement — the issuer/bank identity, the list of parsed transactions, the list of errored (unparseable) lines, the billing-period start and end dates, and the card last-4.
- **Direction (polarity)**: An explicit debit or credit indicator carried on every transaction, sourced from the statement's own indication (year-end `DR`/`CR` marker; monthly leading `+`) and never from the amount's sign.
- **Golden characterization vector**: A synthetic HDFC input (text lines + full text) paired with its expected engine output, stored under `fixtures/hdfc/credit_card/` — one for the year-end layout (ported from the web engine) and one for the monthly layout (expected output captured from a live web-engine run).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For the two synthetic HDFC year-end golden rows, the engine produces exactly the expected transactions — row 1 → date 2025-04-16, amount 10610.00, direction credit; row 2 → date 2025-04-04, amount 1071.00, direction debit (100% match).
- **SC-002**: The engine recognizes the synthetic HDFC statement as HDFC and does not claim a non-HDFC (e.g., ICICI) statement — 0 misattributions across the recognition cases.
- **SC-003**: From the synthetic year-end statement text, the engine records the billing-period end as 2026-03-31, the billing-period start as 2025-04-01, and the card last-4 as `9070`.
- **SC-004**: A statement in **either** layout parses correctly through the single HDFC reader without the caller selecting a layout — the year-end layout is tried first and the monthly layout is used as the fallback — verified across the year-end and monthly golden fixtures.
- **SC-005**: Direction is correct across every tested case and layout — year-end `CR` → credit and `DR` → debit; monthly leading `+` → credit and its absence → debit — and is never changed by the amount's sign or magnitude.
- **SC-006**: 100% of parsed amounts are exact decimals with their stated precision preserved and are always non-negative; no monetary value is ever a floating-point number; and the monthly Rupee-glyph `C` is never mistaken for the amount.
- **SC-007**: A malformed row is captured for review while every well-formed row in the same input is still returned, and no error is raised (the parse never aborts on a bad row).
- **SC-008**: Zero outbound network connections occur during the entire HDFC parse path, verified by the automated privacy-egress test.
- **SC-009**: Given identical input, the engine returns identical output across repeated runs (100% reproducible).
- **SC-010**: Both golden vectors — the ported year-end vector and the monthly vector (expected output captured from a live web-engine run) — reproduce exactly and the parity harness passes; re-running is stable.
- **SC-011**: All automated checks required to merge pass (green), including the parity harness and the privacy-egress test, with the iOS Local Verification Gate and CI green.
- **SC-012**: No secrets, network entitlements, telemetry, copyleft-licensed dependencies, or new runtime dependencies are added by the feature (verified by review of manifests and dependencies).

## Assumptions

- **Composite reader & seam**: HDFC is added as a **composite reader** (a year-end configuration plus a monthly configuration) reusing the existing `read_lines(lines, full_text)` seam; the year-end layout is tried first and the monthly layout is the fallback. The exact module layout, row patterns, and composite-reader mechanics are finalized in `/speckit.plan`.
- **Binding**: HDFC is exposed to Swift via the existing UniFFI bridge with an HDFC parse entry point and an HDFC issuer-claims function, mirroring ICICI; concrete binding mechanics belong in `/speckit.plan`.
- **Fixtures location**: Golden fixtures live under `fixtures/hdfc/credit_card/` and are the source of truth for parity.
- **Reused, not rebuilt**: The `read_lines` seam and per-issuer reader configuration, the parsed-statement / parsed-transaction output types, the amount/date/last-4/polarity helpers, the golden-fixture JSON parity harness, the UniFFI bridge, and the privacy-egress gate were all built in the ICICI slice; HDFC plugs into every one of them unchanged.
- **New shared helpers**: The modest engine-internal helpers HDFC needs — a month-name-and-year → month-end date helper, a monthly leading-`+` credit direction rule, and ordered "try multiple row layouts" support (the composite reader) — are added to the shared reader subsystem so later multi-layout banks can reuse them.
- **No new dependencies**: This slice should require **no** new runtime dependencies.
- **Monthly-fixture provenance**: The monthly-layout golden fixture is fabricated (synthetic merchants, amounts, and masked card number) and its expected output is captured from a live run of the web engine's HDFC reader — never hand-derived.
- **Source of truth**: The web engine is the source of truth for behaviour — `hdfc.py` plus the shared line-reader, common helpers, and polarity module, and the credit-card characterization test. The porting approach (module layout, patterns, regexes, fixture format, UniFFI exports) is decided in `/speckit.plan`, not here.
- **No new UI required**: This is an engine slice; no user-facing UI is required to deliver it. App-side PDF text extraction (PDFKit wiring), the file-import UI, and the Share Extension remain a native concern and a later step. If a trivial demo surface is added, it follows HIG and accessibility (FR-031).
- **Data safety**: All fixture and test data is synthetic or fully redacted — no real account data.
- **Money & polarity**: Amounts are exact decimals (never floating-point) and direction is carried explicitly and sourced from the statement, consistent with the engine's existing domain types.

### Dependencies

- **Kaname Constitution v1.0.0** — privacy (zero-network free/core), determinism, a pure platform-agnostic core (no PDF engine), decimal money with explicit polarity, Apache-2.0 open-core with no copyleft, native HIG/accessibility, and the test-first iOS Local Verification Gate (including the privacy-egress gate).
- **Milestone P2 — ICICI slice (already landed)** — the shared "one transaction per text line" reader seam, the parsed-statement / parsed-transaction domain types, the amount/date/last-4/polarity helpers, the golden-fixture parity harness, and the privacy-egress gate that HDFC reuses.
- **Milestone P1 bridge (already landed)** — the shared engine crate and the UniFFI Swift binding proven end-to-end, over which the HDFC parse and claims functions are exposed.
- **Web engine golden vectors** — the synthetic HDFC year-end characterization vector and the HDFC reader behaviour used as the parity source of truth (including for capturing the monthly fixture's expected output from a live run).

## Out of Scope

Deferred to later P2 slices / milestones:

- **Reconciliation** (printed-total integrity check), **coverage / billing-period timeline**, **cross-source de-duplication and transfer detection**, and **balance-chain integrity**.
- **All other bank/card parsers** — SBI, Yes, Federal, and the bank-account ledger readers.
- The `(bank_code, account_kind)` registry **beyond what HDFC needs**.
- **Encrypted SQLite / SQLCipher persistence** and key management.
- **AI-fallback parsing**.
- Any **premium / cloud features**.
- **App-side PDF text extraction** (PDFKit wiring in the app) and the **file-import UI / Share Extension** — native concerns handled in a later slice. This slice focuses on the HDFC engine parse (both layouts) plus its golden-fixture parity, reusing the existing privacy gate and exposed over the existing bridge.
