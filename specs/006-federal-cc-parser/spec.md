# Feature Specification: Import a Federal Bank / Scapia Credit-Card Statement On-Device (Fifth and Final Credit-Card Parser — the Most Distinctive Layout, Zero New Engine Infrastructure)

**Feature Branch**: `006-federal-cc-parser`  
**Created**: 2026-07-16  
**Status**: Draft  
**Milestone**: P2 (next slice) — the fifth and final credit-card statement parser, completing the credit-card set  
**Input**: User description: "P2 (next slice) — Import a Federal Bank / Scapia credit-card statement on-device: the fifth and final credit-card parser, completing the credit-card set (ICICI, HDFC, SBI, Yes already landed). Federal has the most distinctive layout of the five, but still slots into the existing 'one transaction per line' seam with no new shared engine helpers. A person imports their Scapia (by Federal Bank) credit-card statement PDF and the app produces the list of transactions (date, exact amount, debit/credit direction, description) entirely on-device — no network, no account — exactly as it already does for the other four banks."

> **Note on priority labels**: This feature is milestone **P2** in the product roadmap (`docs/kaname-ios-plan.md` §9). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P2" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

The four previous slices (milestone P2) landed the first four real credit-card parsers — **ICICI**, **HDFC**, **SBI Card**, and **Yes Bank (Kiwi)** — and, with them, everything a new bank now reuses: the shared **"one transaction per text line"** parsing seam and per-issuer reader configuration, the parsed-statement / parsed-transaction output types, the amount / date / last-4 / polarity helpers, the **golden-fixture parity** harness that pins the on-device engine to the proven web engine, the UniFFI bridge, and the privacy-egress gate. This slice delivers the **fifth and final** credit-card issuer, **Federal Bank** (marketed as **Scapia**), and with it **completes the credit-card set**: a person imports their Scapia / Federal Bank credit-card statement and the app produces the list of transactions — date, exact amount, debit/credit direction, and description — entirely on-device, with no network and no account, exactly as it already does for ICICI, HDFC, SBI, and Yes. Landing it means **all five credit-card issuers parse on-device with byte-for-byte parity**.

Federal is the payoff case for the "incremental-by-bank" thesis: it has the **most distinctive layout of the five**, yet it still **slots into the existing seam with no new shared engine helpers**. Where the other four each place the amount and a direction marker in familiar positions, Federal's rows join the date to a transaction time with a middle-dot separator, prefix the amount with the rupee symbol, and mark a credit with a leading `+` in front of the amount (Scapia's own notation) rather than a `Dr`/`Cr` column. The billing cycle is printed as a space-stripped date range, and the card number is fully masked with no textual anchor. Even so, both of Federal's date formats are **already** in the shared date parser, and the credit-word fallback reuses the **shared polarity classifier** — so Federal needs only a new reader configuration (with its own row pattern and a Scapia-specific direction rule), a golden fixture, two bridge exports, and one parity case. No shared engine internals change.

The platform boundary is unchanged and fixed by the constitution and locked decisions: **text extraction is native** — on iOS, the platform extracts the statement's text lines and full text and hands them to the shared engine; the shared engine **never** embeds a PDF engine. Its entry point is a pure seam that takes already-extracted text plus the full statement text and returns the parsed result.

### User Story 1 - Turn a Federal Bank / Scapia credit-card statement into transactions, on-device (Priority: P1)

A person imports their Scapia (by Federal Bank) credit-card statement. The platform extracts the statement's text natively and hands it to the shared engine; the engine recognizes the document as a Scapia / Federal Bank statement and returns the list of transactions — each with its date, amount, debit/credit direction, and description — computed entirely on the device with no network access.

**Why this priority**: This is the headline value and the smallest slice that turns a real Scapia / Federal statement into usable data. It is a viable increment on its own: a person gets their Federal transactions from their statement, on-device, exactly as they already can for ICICI, HDFC, SBI, and Yes. Every subsequent story refines this parse.

**Independent Test**: Provide the engine with the extracted text of a synthetic Scapia / Federal credit-card statement and confirm it recognizes the issuer and returns one transaction per matching row, each carrying a date, an exact amount, a direction, and a description — with no network access during the parse.

**Acceptance Scenarios**:

1. **Given** the extracted text of a synthetic Scapia / Federal credit-card statement (containing the issuer marker `Scapia by Federal Bank`), **When** the engine parses it, **Then** it recognizes the document as a Federal Bank statement and returns a transaction for each transaction row.
2. **Given** the synthetic Federal row `29-04-2026·16:18 Billpayment Payment +₹324.45` (where `·` is the middle-dot separator U+00B7 and `₹` is the rupee sign U+20B9), **When** the engine parses it, **Then** it returns a transaction dated 2026-04-29, amount 324.45, in Indian Rupees, with the description `Billpayment Payment` (the `16:18` transaction time is consumed by the layout and is **not** part of the description).
3. **Given** the synthetic Federal row `24-04-2026·06:03 ExampleMerchantTokyo ₹2,353.13`, **When** the engine parses it, **Then** it returns a transaction dated 2026-04-24, amount 2353.13, in Indian Rupees, with the description `ExampleMerchantTokyo`.
4. **Given** a statement that belongs to a different issuer (for example, an ICICI, HDFC, SBI, or Yes statement), **When** the Federal reader is asked whether it recognizes the document, **Then** it does not claim it, so the document is never misattributed to Federal.
5. **Given** the device has no network connectivity, **When** the statement is parsed, **Then** the transactions are still produced, proving the parse is fully local.

---

### User Story 2 - The most distinctive layout, absorbed with zero new engine infrastructure — completing the five-issuer credit-card set (Priority: P2)

As a maintainer, adding Federal — despite it being the **most distinctive** of the five layouts — must require **no new shared engine infrastructure**: only a new per-issuer reader configuration (its own row pattern plus a Scapia-specific direction rule), a golden fixture, two UniFFI exports, and one parity case row. Federal's day-first `DD-MM-YYYY` date format (`%d-%m-%Y`) and its space-stripped `DDMonYYYY` billing-cycle date format (`%d%b%Y`, as in `20Apr2026`) are **already** handled by the shared date parser, and the credit-word fallback reuses the **shared polarity classifier**; Federal adds no new shared helper. With Federal green, all five credit-card issuers parse on-device.

**Why this priority**: This is the distinctive point of the slice and the reason Federal is the right bank to finish the set: it proves the fixtures-driven, **incremental-by-bank** ingestion architecture scales even to the **hardest** layout with essentially no new engine code. Landing Federal green — a middle-dot separator, a rupee-prefixed amount, and a leading-`+` credit notation, all absorbed by a single reader configuration — validates that the shared seam, helpers, harness, bridge, and privacy gate generalize to every credit-card issuer without touching the engine internals.

**Independent Test**: Confirm the Federal parse is delivered by a new single-layout reader configuration that plugs into the existing `read_lines(lines, full_text)` seam, reusing the shared date parser (for both `%d-%m-%Y` and `%d%b%Y`) and the shared polarity classifier (for the credit-word fallback), and that **no new shared helper** is introduced or modified in the shared reader subsystem to support Federal.

**Acceptance Scenarios**:

1. **Given** the Federal reader, **When** it parses the `29-04-2026·…` row, **Then** the shared date parser interprets `29-04-2026` as 2026-04-29 using the existing `%d-%m-%Y` format, with no Federal-specific date code.
2. **Given** the Federal reader, **When** it reads the billing cycle `20Apr2026-19May2026`, **Then** the shared date parser interprets `20Apr2026` and `19May2026` using the existing space-stripped `%d%b%Y` format, with no Federal-specific date code.
3. **Given** the change set that adds Federal, **When** it is reviewed, **Then** it consists of a new reader configuration (row pattern + Scapia-specific direction rule), a golden fixture, two bridge exports, and one parity case row — and adds **no** new shared engine helper.
4. **Given** all five credit-card readers after this slice lands, **When** the parity harness runs, **Then** ICICI, HDFC, SBI, Yes, and Federal each reproduce their golden vectors exactly, confirming the credit-card set is complete.

---

### User Story 3 - Direction comes from Scapia's leading `+` and the statement's language, never from the amount's sign (Priority: P3)

Each transaction's direction (money in vs money out) is decided by Scapia's own notation: a leading `+` immediately before the amount marks a **credit**; when the `+` is absent, the direction falls back to the transaction's description language via the shared classifier (credit words → credit; otherwise debit). The direction is never guessed from whether an amount looks positive, negative, or large.

**Why this priority**: Correct direction is what makes the parsed data trustworthy for later categorization, dedup, and reconciliation. Reading polarity from the statement's own indication (never from the amount) is a non-negotiable engine rule. Federal is distinctive here: it has **no** `Dr`/`Cr` column — a credit is signalled only by the leading `+`, and everything else defaults through the shared description-language classifier — so honouring that precedence is what makes Federal directions correct.

**Independent Test**: Parse a row with a leading `+` before the amount and a row without one, and confirm the first is classified credit (from the `+`) and the second is classified from the description language (defaulting to debit) — in every case independent of the amount's value.

**Acceptance Scenarios**:

1. **Given** the row `29-04-2026·16:18 Billpayment Payment +₹324.45` (a leading `+` immediately before the amount), **When** it is parsed, **Then** the transaction's direction is **credit** — even though the description `Billpayment Payment` is not itself a recognized credit phrase, the `+` is decisive.
2. **Given** the row `24-04-2026·06:03 ExampleMerchantTokyo ₹2,353.13` (no leading `+`, no credit-type words in the description), **When** it is parsed, **Then** the transaction's direction is **debit** via the shared classifier's default.
3. **Given** a row with no leading `+` whose description contains a credit-type word (e.g., `refund`, `reversal`, `cashback`, `payment received`), **When** it is parsed, **Then** the shared classifier maps it to **credit** from the description language.
4. **Given** any row, **When** it is parsed, **Then** the direction is decided solely from Scapia's leading `+` and, failing that, the description language — and never from the sign or magnitude of the amount.

---

### User Story 4 - Statement metadata: billing cycle (space-stripped range) and fully-masked card last-4 (no anchor) (Priority: P4)

Beyond the individual transactions, the engine reads two pieces of statement-level context that later features (account attribution, coverage) depend on: the statement's billing cycle and the card's last four digits. The billing cycle is read from a space-stripped date range such as `20Apr2026-19May2026`, and the card last-4 is read from a fully-masked card number such as `XXXXXXXXXXXX4836` found in the full text with **no** textual anchor.

**Why this priority**: The transactions are the core deliverable, but attributing them to a card and a billing cycle is what lets the app place them correctly later. This story confirms both derivations are correct for Federal's distinctive statement format — a compact, space-stripped date range and an anchor-less fully-masked card number — and that, when a metadata field is not present, the engine leaves it unset rather than inventing a value.

**Independent Test**: Parse a synthetic Federal statement whose full text carries a space-stripped billing range (`20Apr2026-19May2026`) and a fully-masked card number (`XXXXXXXXXXXX4836`), and confirm the engine records the correct billing-cycle start/end and the correct card last-4.

**Acceptance Scenarios**:

1. **Given** statement text containing the space-stripped range `20Apr2026-19May2026`, **When** the engine parses it, **Then** the billing-cycle start is recorded as 2026-04-20 and the billing-cycle end as 2026-05-19 (both via the shared `%d%b%Y` date format).
2. **Given** statement text containing the fully-masked card number `XXXXXXXXXXXX4836` with no textual anchor, **When** the engine parses it, **Then** the card last-4 is recorded as `4836` (found by scanning the full text, with no anchor).
3. **Given** statement text containing no recognizable billing cycle or masked card number, **When** the engine parses it, **Then** the corresponding metadata is simply absent (left unset) rather than fabricated, and the transactions are still returned.

---

### User Story 5 - Malformed rows are captured for review, never dropped or fatal (Priority: P5)

If a line looks like a transaction row but one of its fields will not parse, the engine keeps the raw line aside as an "errored line" for later review instead of crashing or silently discarding it — and it still returns every well-formed transaction from the same statement.

**Why this priority**: Real statements are messy. A single odd line must never take down the whole import or cause a person to lose the rest of their transactions. This resilience is what makes the parser safe to ship, and it is reused unchanged from the ICICI, HDFC, SBI, and Yes slices.

**Independent Test**: Parse a statement that mixes well-formed rows with a row whose fields cannot be parsed, and confirm the good rows are all returned, the bad row is captured for review, and no error is raised.

**Acceptance Scenarios**:

1. **Given** a statement containing one unparseable row among several valid rows, **When** the engine parses it, **Then** all valid rows are returned as transactions and no error is raised.
2. **Given** the same statement, **When** the engine parses it, **Then** the unparseable row is captured as an errored line (its raw text preserved, bounded to a safe maximum length) for review.
3. **Given** lines that are not transaction rows at all (headers, summaries, balances, totals), **When** the engine parses the statement, **Then** those lines are ignored without producing transactions and without being reported as errors.

---

### User Story 6 - Proven byte-for-byte against a golden fixture (Priority: P6)

As a maintainer, the engine's Federal behaviour is pinned to the proven web engine by porting the web engine's synthetic Federal characterization vector into the repository's `fixtures/` directory as a golden vector, with the on-device engine asserted to reproduce it exactly.

**Why this priority**: Parity is the constitution's acceptance mechanism for the port (Principle V). It turns "we think it matches" into an enforced, regression-proof guarantee, and it extends the harness that every reader reuses — this time proving the harness accepts the **fifth and final** credit-card issuer as a one-row addition and closing out the credit-card set.

**Independent Test**: Run the parity harness over the ported Federal vector and confirm the engine's output matches the expected output exactly, and that re-running produces identical results.

**Acceptance Scenarios**:

1. **Given** the ported synthetic Federal golden vector, **When** the parity harness runs, **Then** the engine's parsed output (dates, amounts, directions, descriptions, billing-cycle start/end, and card last-4) matches the expected output exactly — including the two rows (2026-04-29 / 324.45 / credit and 2026-04-24 / 2353.13 / debit), the billing cycle (2026-04-20 to 2026-05-19), and the card last-4 `4836`.
2. **Given** a change that alters Federal parsing behaviour, **When** the parity harness runs, **Then** it fails, enforcing the parity guarantee.
3. **Given** the golden fixture, **When** it is inspected, **Then** all input and expected data is synthetic or fully redacted (fabricated merchants, amounts, and a fully-masked card number) — never real account data.

---

### User Story 7 - Privacy gate: zero network in the parse path (Priority: P7)

As a maintainer, the existing automated privacy-egress test covers the Federal import/parse path and asserts it performs no network I/O, so the constitution's "free features run 100% on-device" guarantee holds for this slice and is protected against regressions.

**Why this priority**: Privacy is the product's non-negotiable promise and a required constitution gate. Extending the existing gate to cover Federal means the guarantee is proven for the new parser — and, with Federal, for the whole credit-card set — not merely assumed.

**Independent Test**: Run the privacy-egress test against the Federal parse path and confirm it passes only when zero outbound network connections occur during parsing.

**Acceptance Scenarios**:

1. **Given** the Federal parse path, **When** the automated privacy-egress test runs, **Then** it confirms zero outbound network connections occur during parsing.
2. **Given** a regression that introduces any network access into the parse path, **When** the privacy-egress test runs, **Then** it fails, blocking the change.
3. **Given** the feature as a whole, **When** the engine and app are reviewed, **Then** no telemetry, analytics, advertising, or crash-reporting component is present in the parse path.

---

### Edge Cases

- **Wrong issuer**: A statement from another issuer (e.g., ICICI, HDFC, SBI, or Yes) is presented to the Federal reader → it must not claim the document, so transactions are never misattributed to Federal.
- **Encoding-robust date/time separator**: The date is joined to the `HH:MM` transaction time by a single middle-dot separator (U+00B7). Because native text extraction may render that separator as different bytes/glyphs across encodings, the row must match the separator position as **any single character** — the row is recognized regardless of exactly which character the extractor produced for the dot.
- **Transaction time is not output**: The `HH:MM` time between the separator and the description (e.g., `16:18`) is consumed by the layout and never appears in the transaction's date or description.
- **Rupee-symbol-prefixed amount**: The amount is prefixed by the rupee sign (₹, U+20B9) → the symbol is not part of the numeric value; the amount is parsed to the exact non-negative decimal (e.g., `₹324.45` → 324.45).
- **Leading `+` credit notation**: A `+` immediately before the amount (e.g., `+₹324.45`) marks a **credit** — it is Scapia's own credit notation, not a sign on the number and not part of the amount's value.
- **Direction fallback via description language**: A row with **no** leading `+` takes its direction from the description language via the shared classifier (credit words → credit; otherwise debit) — never from the amount.
- **Indian money formatting**: Amounts with thousands separators, including the Indian grouping style (e.g., `2,353.13` or `1,23,456.78`) → parsed to the exact, non-negative decimal value, with stated precision preserved.
- **Space-stripped billing range**: The billing cycle is printed as a compact range with no spaces (e.g., `20Apr2026-19May2026`) → the two dates are parsed via the shared `%d%b%Y` format to start 2026-04-20 and end 2026-05-19.
- **Fully-masked card, no anchor**: The masked card number is fully masked (e.g., `XXXXXXXXXXXX4836`) and carries no textual anchor → the trailing four digits `4836` are recorded as the card last-4 by scanning the full text.
- **Non-transaction lines**: Header, summary, balance, and total lines → ignored (no transaction, no error).
- **Unparseable row**: A line that resembles a transaction row but whose fields will not parse → captured as an errored line; every good row in the same statement is still returned; no error is raised.
- **No transaction lines**: Empty input, or input with no recognizable rows → an empty transaction list is returned with no error.
- **Missing metadata**: No recognizable billing cycle or masked card number in the text → billing-cycle start/end and card last-4 are left unset rather than fabricated.
- **Repeated / concurrent parses**: The same input parsed repeatedly → identical results every time, with no dependence on wall-clock time, locale, or hidden global state.

## Requirements *(mandatory)*

### Functional Requirements

**Document recognition**

- **FR-001**: The engine MUST recognize a statement as a Federal Bank / Scapia credit-card statement via an issuer/document-plausibility check — the statement text contains a Federal/Scapia issuer marker (`Scapia` / `Federal Bank`) — before parsing it as Federal.
- **FR-002**: The engine MUST NOT claim a statement that belongs to a different issuer (e.g., an ICICI, HDFC, SBI, or Yes statement), so a document is only parsed by the reader that recognizes it.

**Transaction extraction (the core parse)**

- **FR-003**: The engine MUST parse Federal's single credit-card statement layout `DD-MM-YYYY<sep>HH:MM <description> [+]₹<amount>` — a day-first `DD-MM-YYYY` date joined by a single separator character to an `HH:MM` transaction time, followed by the description, an optional leading `+`, the rupee symbol, and the amount — and MUST produce exactly one transaction per matching row.
- **FR-004**: The engine MUST match the date/time separator (a middle dot, U+00B7) **encoding-robustly** — as any single character — so that the row is still recognized regardless of exactly which byte/glyph native text extraction produced for that separator.
- **FR-005**: The engine MUST treat the `HH:MM` transaction time as part of the row's structure only; it MUST NOT appear in the transaction's date or description. Each produced transaction carries the transaction **date** (not a timestamp).
- **FR-006**: Each produced transaction MUST include the transaction date, the amount, the debit/credit direction, the description text, and the currency (Indian Rupees, INR).
- **FR-007**: Lines that are not transaction rows (headers, summaries, balances, totals) MUST be ignored without producing transactions or errors.

**Amount**

- **FR-008**: The engine MUST parse each amount as an exact, non-negative decimal, stripping the leading rupee symbol (₹, U+20B9) and any leading `+`, and honouring Indian number formatting (thousands separators, including the Indian grouping style), preserving the stated precision (e.g., `₹2,353.13` → 2353.13; `+₹324.45` → 324.45).
- **FR-009**: Monetary amounts MUST NEVER be represented as floating-point numbers; they MUST be exact decimals throughout.

**Direction / polarity**

- **FR-010**: The engine MUST determine each transaction's debit/credit direction from Scapia's own notation and MUST NEVER infer it from the sign or magnitude of the amount: a leading `+` immediately before the amount MUST set the direction to **credit**.
- **FR-011**: When no leading `+` is present, the engine MUST fall back to the shared polarity classifier, which classifies the row from its description language (recognized credit-type words → credit) and otherwise defaults to **debit**.

**Statement metadata**

- **FR-012**: The engine MUST derive the billing cycle from a space-stripped date range of the form `DDMonYYYY-DDMonYYYY` (e.g., `20Apr2026-19May2026`), setting the billing-cycle start and end to the two parsed dates (start = 2026-04-20, end = 2026-05-19 for that example), using the shared `%d%b%Y` date format.
- **FR-013**: The engine MUST extract the card's last four digits from a fully-masked card number in the full text (e.g., `XXXXXXXXXXXX4836` → `4836`) with **no** textual anchor.
- **FR-014**: When a metadata field cannot be found, the engine MUST leave it unset rather than fabricate a value, and MUST still return the parsed transactions.

**Robustness**

- **FR-015**: A line that resembles a transaction row but whose fields cannot be parsed MUST be captured as an "errored line" (raw text preserved, bounded to a safe maximum length) for later review; the engine MUST NOT raise an error or silently drop it, and MUST still return every successfully parsed row.

**Engine purity, platform boundary & reuse**

- **FR-016**: The engine's Federal parse MUST reuse the existing "one transaction per text line" reader seam — accepting already-extracted text lines plus the full statement text and returning the parsed result; it MUST NOT read files, extract PDF text, or embed a PDF engine (text extraction is a native platform concern).
- **FR-017**: The engine MUST remain pure and deterministic: identical input MUST yield identical output, with no dependence on network, wall-clock time, locale, or hidden global mutable state.
- **FR-018**: Federal MUST reuse — not rebuild — the existing shared output types (parsed statement / parsed transaction), the amount / date / last-4 / polarity helpers (including the `%d-%m-%Y` and space-stripped `%d%b%Y` date formats already present in the shared date parser, and the shared polarity classifier used for the description-language fallback), the golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate. This slice MUST add **no new shared engine helper**; Federal is delivered as a new single-layout reader configuration only (its own row pattern plus a Scapia-specific direction rule).
- **FR-019**: The engine MUST expose Federal over the existing UniFFI bridge with a Federal parse entry point and a Federal issuer-claims function, mirroring the ICICI, HDFC, SBI, and Yes surfaces (two exports).

**Privacy (constitution Principle I — NON-NEGOTIABLE)**

- **FR-020**: The entire Federal import/parse path MUST run 100% on-device with ZERO network I/O.
- **FR-021**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting into the engine or the app.
- **FR-022**: The existing automated privacy-egress test MUST cover the Federal parse path and assert it performs no network access; it remains a required constitution gate.

**Parity & test-first (constitution Principle V)**

- **FR-023**: The web engine's synthetic Federal characterization vector MUST be ported into the repository's `fixtures/` directory (under `fixtures/federal/credit_card/`) as a golden vector, and the engine MUST reproduce it exactly.
- **FR-024**: All fixture and test data MUST be synthetic or fully redacted (fabricated merchants, amounts, and a fully-masked card number) — never real account data.
- **FR-025**: The Federal parsing behaviour introduced by this slice MUST be developed test-first (a failing golden test precedes the behaviour).

**Licensing, secrets & quality gates**

- **FR-026**: The change MUST NOT add secrets, API keys, or private endpoints; MUST remain distributable under Apache-2.0 with no copyleft (GPL/AGPL/LGPL) dependencies; and MUST introduce NO new runtime dependencies for this slice.
- **FR-027**: The change MUST keep the iOS Local Verification Gate and CI green: core formatting, linting, and tests; app linting; project generation; a simulator build with passing app tests; and the privacy gate.
- **FR-028**: If any user-facing surface is introduced for this slice, it MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility.

### Key Entities *(include if feature involves data)*

- **Extracted statement text (input)**: The already-extracted text lines plus the full statement text handed to the engine by the native platform. Contains no PDF binary; the engine never opens a PDF.
- **Parsed transaction**: One statement row's result — a transaction date, an exact non-negative amount, an explicit debit/credit direction, a currency (INR), and a description.
- **Parsed statement result**: The full output of reading one statement — the issuer/bank identity (`FEDERAL`), the list of parsed transactions, the list of errored (unparseable) lines, the billing-cycle start and end dates, and the card last-4.
- **Direction (polarity)**: An explicit debit or credit indicator carried on every transaction, sourced from Scapia's leading `+` notation and, when absent, the shared description-language classifier — never from the amount's sign.
- **Golden characterization vector**: A synthetic Federal input (text lines + full text) paired with its expected engine output, stored under `fixtures/federal/credit_card/`, ported from the web engine and reproduced exactly by the on-device engine.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For the two synthetic Federal golden rows, the engine produces exactly the expected transactions — row 1 → date 2026-04-29, amount 324.45, direction credit, description `Billpayment Payment`; row 2 → date 2026-04-24, amount 2353.13, direction debit, description `ExampleMerchantTokyo` (100% match).
- **SC-002**: The engine recognizes the synthetic Federal statement as Federal and does not claim a non-Federal (e.g., ICICI, HDFC, SBI, or Yes) statement — 0 misattributions across the recognition cases.
- **SC-003**: From the synthetic Federal statement text, the engine records the billing-cycle start as 2026-04-20, the billing-cycle end as 2026-05-19, and the card last-4 as `4836`.
- **SC-004**: Direction is correct across every tested case — a leading `+` → credit, and the shared classifier's description-language rule (defaulting to debit) when the `+` is absent — and is never changed by the amount's sign or magnitude.
- **SC-005**: The row is recognized regardless of which single character native text extraction produced for the middle-dot date/time separator (encoding-robust matching), and the `HH:MM` time never leaks into the date or description.
- **SC-006**: 100% of parsed amounts are exact decimals with their stated precision preserved and are always non-negative (rupee symbol and any leading `+` stripped); no monetary value is ever a floating-point number.
- **SC-007**: A malformed row is captured for review while every well-formed row in the same input is still returned, and no error is raised (the parse never aborts on a bad row).
- **SC-008**: Zero outbound network connections occur during the entire Federal parse path, verified by the automated privacy-egress test.
- **SC-009**: Given identical input, the engine returns identical output across repeated runs (100% reproducible).
- **SC-010**: The ported synthetic Federal golden vector reproduces exactly and the parity harness passes; re-running is stable.
- **SC-011**: Federal is added with **zero new shared engine helpers** — the change consists only of a new single-layout reader configuration (row pattern + Scapia-specific direction rule), a golden fixture, two UniFFI exports, and one parity case row; the shared reader/date/polarity/last-4 helper surface is unchanged (verified by review of the change set).
- **SC-012**: With this slice landed, all five credit-card issuers (ICICI, HDFC, SBI, Yes, Federal) reproduce their golden vectors exactly under the parity harness — the credit-card set is complete.
- **SC-013**: All automated checks required to merge pass (green), including the parity harness and the privacy-egress test, with the iOS Local Verification Gate and CI green.
- **SC-014**: No secrets, network entitlements, telemetry, copyleft-licensed dependencies, or new runtime dependencies are added by the feature (verified by review of manifests and dependencies).

## Assumptions

- **Single-layout reader & seam**: Federal is added as a **single-layout** reader configuration reusing the existing `read_lines(lines, full_text)` seam; there is exactly one row layout (`DD-MM-YYYY<sep>HH:MM <description> [+]₹<amount>`). The exact module layout and row pattern (including the encoding-robust single-character separator match and the rupee-prefix handling) are finalized in `/speckit.plan`.
- **No new shared helpers**: Federal needs **no** new shared engine helpers. Both of its date formats — `%d-%m-%Y` (row dates) and the space-stripped `%d%b%Y` (billing cycle) — are **already** present in the shared date parser, and the description-language direction fallback reuses the **shared polarity classifier**. The only Federal-specific logic is the reader's own row pattern and its direction rule (leading `+` → credit, else the shared classifier).
- **Scapia-specific direction rule**: A leading `+` immediately before the amount denotes a credit (Scapia's own notation); when absent, the shared classifier decides from the description language and defaults to debit. Direction is never taken from the amount's sign. This is Federal's one bespoke behaviour and lives entirely in the reader configuration.
- **Binding**: Federal is exposed to Swift via the existing UniFFI bridge with a Federal parse entry point and a Federal issuer-claims function, mirroring ICICI, HDFC, SBI, and Yes (two exports); concrete binding mechanics belong in `/speckit.plan`.
- **Fixtures location**: The golden fixture lives under `fixtures/federal/credit_card/` and is the source of truth for parity.
- **Bank code**: The issuer/bank identity for this reader is `FEDERAL`.
- **Reused, not rebuilt**: The `read_lines` seam and per-issuer reader configuration, the parsed-statement / parsed-transaction output types, the amount / date / last-4 / polarity helpers, the golden-fixture JSON parity harness, the UniFFI bridge, and the privacy-egress gate were all built in the ICICI slice (and extended in the HDFC, SBI, and Yes slices); Federal plugs into every one of them unchanged.
- **No new dependencies**: This slice should require **no** new runtime dependencies.
- **Source of truth**: The web engine is the source of truth for behaviour — `federal_scapia.py` plus the shared line-reader, common helpers, and polarity module, and the credit-card characterization test (whose Federal case values are reproduced in this spec). The porting approach (module layout, patterns, regexes, fixture format, UniFFI exports) is decided in `/speckit.plan`, not here.
- **Synthetic characterization vector**: The two synthetic Federal rows and their expected outputs, the billing cycle (2026-04-20 to 2026-05-19), and the card last-4 (`4836`) are the constitution's golden-fixture parity vector (Principle V) — behavioural acceptance data confirmed against the web engine. The date/time separator is the middle dot U+00B7 and the currency symbol is the rupee sign U+20B9.
- **No new UI required**: This is an engine slice; no user-facing UI is required to deliver it. App-side PDF text extraction (PDFKit wiring), the file-import UI, and the Share Extension remain a native concern and a later step. If a trivial demo surface is added, it follows HIG and accessibility (FR-028).
- **Data safety**: All fixture and test data is synthetic or fully redacted — no real account data.
- **Money & polarity**: Amounts are exact decimals (never floating-point) and direction is carried explicitly and sourced from Scapia's leading `+` (else the shared classifier), consistent with the engine's existing domain types.

### Dependencies

- **Kaname Constitution v1.0.0** — privacy (zero-network free/core), determinism, a pure platform-agnostic core (no PDF engine), decimal money with explicit polarity, Apache-2.0 open-core with no copyleft, native HIG/accessibility, and the test-first iOS Local Verification Gate (including the privacy-egress gate).
- **Milestone P2 — ICICI slice (already landed)** — the shared "one transaction per text line" reader seam, the parsed-statement / parsed-transaction domain types, the amount / date / last-4 / polarity helpers (including the `%d-%m-%Y` and space-stripped `%d%b%Y` date formats and the polarity classifier Federal reuses), the golden-fixture parity harness, and the privacy-egress gate.
- **Milestone P2 — HDFC slice (already landed)** — the second parser, which proved the seam generalizes to a multi-layout bank.
- **Milestone P2 — SBI slice (already landed)** — the third parser and the first clean single-layout drop-in.
- **Milestone P2 — Yes slice (already landed)** — the fourth parser, a second clean single-layout drop-in, whose pattern Federal follows (a new reader configuration, a golden fixture, two bridge exports, and one parity case row, with no new shared helpers).
- **Milestone P1 bridge (already landed)** — the shared engine crate and the UniFFI Swift binding proven end-to-end, over which the Federal parse and claims functions are exposed.
- **Web engine golden vector** — the synthetic Federal characterization vector and the Federal (`federal_scapia.py`) reader behaviour used as the parity source of truth.

## Out of Scope

Deferred to later P2 slices / milestones:

- **Reconciliation** (the printed-total integrity check), **coverage / billing-cycle timeline**, **cross-source de-duplication and transfer detection**, and **balance-chain integrity**.
- **The bank-account ledger readers** — a separate future base. This slice **completes the credit-card readers** (ICICI, HDFC, SBI, Yes, Federal); the bank-account ledger readers are not part of it.
- The `(bank_code, account_kind)` registry **beyond what Federal needs**.
- **Encrypted SQLite / SQLCipher persistence** and key management.
- **AI-fallback parsing**.
- Any **premium / cloud features**.
- **App-side PDF text extraction** (PDFKit wiring in the app) and the **file-import UI / Share Extension** — native concerns handled in a later slice. This slice focuses on the Federal engine parse plus its golden-fixture parity, reusing the existing privacy gate and exposed over the existing bridge.
