# Feature Specification: Import an Indian Overseas Bank (IOB) Credit-Card Statement On-Device (Sixth & Final Credit-Card Parser, Zero New Engine Infrastructure; Corrects IOB Miscategorization)

**Feature Branch**: `011-iob-cc-reader`  
**Created**: 2026-07-17  
**Status**: Draft  
**Milestone**: P2 (final credit-card slice) — the sixth and last credit-card statement parser, completing the full set of ten statement readers (6 credit-card + 4 bank-account)  
**Input**: User description: "Indian Overseas Bank (IOB) credit-card statement reading for the on-device Kaname core — the sixth and final credit-card reader, completing the full set of statement readers (10 total: 6 credit-card + 4 bank-account). IOB is a single-layout credit-card reader (NOT a bank-account/ledger reader — the project roadmap docs currently miscategorize it, which this slice also fixes). Layout: one transaction per line as 'DD-MON-YYYY <merchant> <amount> Dr|Cr'. Direction is read from the trailing Dr/Cr marker, never from the amount. Anchoring on a leading DD-MON-YYYY date and a trailing Dr/Cr naturally skips the header, ACCOUNT SUMMARY, and Total lines. The statement date ('Stmt Date: 20-APR-2026') gives the cycle end (no explicit period range is printed); the masked card number is printed INLINE with the credit/cash limits on one line, and the trailing four is extracted. This slice adds the IOB configuration of the existing line-reader base plus its golden fixture, and corrects the two roadmap docs that list IOB under bank-account readers."

> **Note on priority labels**: This feature is milestone **P2** in the product roadmap (`docs/kaname-ios-plan.md` §9). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P2" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

The five previous credit-card slices (milestone P2) landed the first five real credit-card parsers — **ICICI**, **HDFC**, **SBI Card**, **Yes Bank (Kiwi)**, and **Federal (Scapia)** — and the four bank-account ledger slices landed the account-ledger readers (**ICICI bank**, **HDFC bank**, **Federal bank**, **AU bank**). Together they built everything a new bank now reuses: the shared **"one transaction per text line"** parsing seam and per-issuer reader configuration, the parsed-statement / parsed-transaction output types, the amount / date / last-4 / polarity helpers, the **golden-fixture parity** harness that pins the on-device engine to the proven web engine, the UniFFI bridge, and the privacy-egress gate. This slice delivers the **sixth and final** credit-card bank, **Indian Overseas Bank (IOB)**, and — like SBI and Yes — is a **clean single-layout drop-in**: a person imports their IOB credit-card statement and the app produces the list of transactions — date, exact amount, debit/credit direction, and description — entirely on-device, with no network and no account, exactly as it already does for the five credit-card banks already landed. Landing IOB completes the full planned set of **ten** statement readers (six credit-card + four bank-account).

IOB reinforces that the ingestion architecture **scales bank-by-bank with essentially no new engine code**. Like SBI and Yes, IOB is a **single-layout** reader that needs **no new shared helpers at all**: its `DD-MON-YYYY` date format with an uppercase month (e.g., `31-MAR-2026`) is already handled by the shared date parser (whose `%d-%b-%Y` format is case-insensitive, so uppercase `MAR` parses), and its two-letter `Dr`/`Cr` direction markers are already handled by the shared polarity classifier (direction read from the explicit marker). Adding IOB is therefore just a new reader configuration, a golden fixture, two bridge exports, and one parity case — no changes to the shared engine internals.

This slice also carries a **documentation correction** that is part of its scope. The project's two roadmap documents (`docs/HANDOFF.md` and `docs/kaname-ios-plan.md`) currently list IOB (`iob.py` / `iob`) under the **bank-account** readers. That is a miscategorization: IOB is a **credit-card** reader — it uses the line-based statement reader, registers under `account_kind="credit_card"`, and has **no** bank-account (ledger) reader. This slice moves IOB from the bank-account list to the credit-card list in both documents so the roadmap reflects reality (six credit-card readers, four bank-account readers).

There is **one deliberate scope carve-out** that distinguishes this port from a naive one: the web engine's IOB reader *also* scrapes the `ACCOUNT SUMMARY` block's printed `Payment / Credits` and `Purchases / Debits` totals (for a future reconciliation feature). Those printed-total fields are intentionally **left out of this slice's output model and must not be ported here** — only the transactions, the billing-cycle end date, and the card last-4 are in scope. This mirrors the same carve-out already applied to the Yes reader.

The platform boundary is unchanged and fixed by the constitution and locked decisions: **text extraction is native** — on iOS, the platform extracts the statement's text lines and full text and hands them to the shared engine; the shared engine **never** embeds a PDF engine. Its entry point is a pure seam that takes already-extracted text plus the full statement text and returns the parsed result.

### User Story 1 - Turn an IOB credit-card statement into transactions, on-device (Priority: P1)

A person imports their Indian Overseas Bank credit-card statement. The platform extracts the statement's text natively and hands it to the shared engine; the engine recognizes the document as an IOB statement and returns the list of transactions — each with its date, amount, debit/credit direction, and description — computed entirely on the device with no network access.

**Why this priority**: This is the headline value and the smallest slice that turns a real IOB statement into usable data. It is a viable increment on its own: a person gets their IOB transactions from their statement, on-device, exactly as they already can for the five credit-card banks already landed. Every subsequent story refines this parse.

**Independent Test**: Provide the engine with the extracted text of a synthetic IOB credit-card statement and confirm it recognizes the issuer and returns one transaction per matching row, each carrying a date, an exact amount, a direction, and a description — with no network access during the parse.

**Acceptance Scenarios**:

1. **Given** the extracted text of a synthetic IOB credit-card statement (containing an IOB issuer marker such as `INDIAN OVERSEAS BANK` or `iobnet.co.in`), **When** the engine parses it, **Then** it recognizes the document as an IOB statement and returns a transaction for each transaction row.
2. **Given** the synthetic IOB row `31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr`, **When** the engine parses it, **Then** it returns a transaction dated 2026-03-31, amount 1000.00, in Indian Rupees, direction **credit**, with the description `ExampleRefundMerchant`.
3. **Given** the synthetic IOB row `04-APR-2026 ExampleStorePurchase 3,500.00 Dr`, **When** the engine parses it, **Then** it returns a transaction dated 2026-04-04, amount 3500.00, in Indian Rupees, direction **debit**, with the description `ExampleStorePurchase`.
4. **Given** a statement that belongs to a different issuer (for example, an HDFC statement), **When** the IOB reader is asked whether it recognizes the document, **Then** it does not claim it, so the document is never misattributed to IOB.
5. **Given** the device has no network connectivity, **When** the statement is parsed, **Then** the transactions are still produced, proving the parse is fully local.

---

### User Story 2 - A sixth credit-card bank added with zero new engine infrastructure, completing the set (Priority: P2)

As a maintainer, adding IOB must require **no new shared engine infrastructure** — only a new per-issuer reader configuration, a golden fixture, two UniFFI exports, and one parity case row. The `DD-MON-YYYY` date format with an uppercase month (e.g., `31-MAR-2026`) is already handled by the shared date parser (its `%d-%b-%Y` format parses month abbreviations case-insensitively, so `MAR`/`APR` parse), and the two-letter `Dr`/`Cr` direction markers are already handled by the shared polarity classifier; IOB adds no new shared helper. Landing IOB completes the full planned set of six credit-card readers and, with the four bank-account readers, all ten statement readers.

**Why this priority**: This is the distinctive point of the slice and the reason IOB is a fitting final credit-card bank: it re-confirms the fixtures-driven, **incremental-by-bank** ingestion architecture scales with essentially no new engine code. Landing IOB green as a pure drop-in reader — a third clean single-layout bank after SBI and Yes — validates that the shared seam, helpers, harness, bridge, and privacy gate generalize to the last credit-card bank without touching the engine internals, and closes out the credit-card reader set.

**Independent Test**: Confirm the IOB parse is delivered by a new single-layout reader configuration that plugs into the existing `read_lines(lines, full_text)` seam, reusing the shared date parser (for `DD-MON-YYYY` with an uppercase month) and polarity classifier (for `Dr`/`Cr`), and that **no new shared helper** is introduced or modified in the shared reader subsystem to support IOB.

**Acceptance Scenarios**:

1. **Given** the IOB reader, **When** it parses the `31-MAR-2026 … 1,000.00 Cr` row, **Then** the shared date parser interprets `31-MAR-2026` as 2026-03-31 using the existing case-insensitive `%d-%b-%Y` format (uppercase `MAR` parses), with no IOB-specific date code.
2. **Given** the IOB reader, **When** it classifies a row's direction, **Then** the shared polarity classifier maps the two-letter `Dr`/`Cr` marker to debit/credit with no IOB-specific direction code.
3. **Given** the change set that adds IOB, **When** it is reviewed, **Then** it consists of a new reader configuration, a golden fixture, two bridge exports, one parity case row, and the two roadmap-doc corrections — and adds **no** new shared engine helper.

---

### User Story 3 - Debit/credit direction comes from the statement's Dr/Cr marker, never from the amount's sign (Priority: P3)

Each transaction's direction (money in vs money out) reflects the statement's own two-letter marker at the end of the row: `Cr` means credit and `Dr` means debit. The direction is never guessed from whether an amount looks positive, negative, or large, and never inferred from words in the description.

**Why this priority**: Correct direction is what makes the parsed data trustworthy for later categorization, dedup, and reconciliation. Reading polarity from the statement's own marker (never from the amount) is a non-negotiable engine rule; IOB expresses direction with an explicit terminal `Dr`/`Cr` marker, so honouring that marker is what makes IOB directions correct.

**Independent Test**: Parse rows ending in `Cr` and rows ending in `Dr` and confirm each is classified credit or debit from the statement's own marker — regardless of the amount's value and regardless of any credit/debit words appearing in the description.

**Acceptance Scenarios**:

1. **Given** a row whose final field is the marker `Cr` (e.g., the `31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr` line), **When** it is parsed, **Then** the transaction's direction is **credit**.
2. **Given** a row whose final field is the marker `Dr` (e.g., the `04-APR-2026 ExampleStorePurchase 3,500.00 Dr` line), **When** it is parsed, **Then** the transaction's direction is **debit**.
3. **Given** a row whose description contains a direction-like word that conflicts with its marker, **When** it is parsed, **Then** the direction is taken from the terminal `Dr`/`Cr` marker and not from the description's wording.
4. **Given** any row, **When** it is parsed, **Then** the direction is decided solely from the statement's own `Dr`/`Cr` marker and never from the sign or magnitude of the amount (e.g., the `Cr` refund of 1000.00 is credit while the larger `Dr` purchase of 3500.00 is debit — the magnitudes do not decide direction).

---

### User Story 4 - Statement metadata: billing-cycle end from the statement date, and card last-4 from the inline masked card number (Priority: P4)

Beyond the individual transactions, the engine reads two pieces of statement-level context that later features (account attribution, coverage) depend on: the billing-cycle end date and the card's last four digits. IOB's statement prints **no explicit period range** — only a single statement date (`Stmt Date : 20-APR-2026`), which the engine uses as the billing-cycle **end**; there is **no** period start to read, so the period start is left unset. The card's last four digits come from a masked card number (`123456XXXXXX0042`) that is printed **inline on the same line as the credit/cash limit figures** (e.g., `123456XXXXXX0042 16000 25091.5`); the engine locates it via the `Credit Card Number` anchor and extracts the trailing four digits (`0042`) — not digits bleeding in from the adjacent limit numbers.

**Why this priority**: The transactions are the core deliverable, but attributing them to a card and a billing cycle is what lets the app place them correctly later. IOB's format is distinctive in two ways — the cycle end comes from a lone statement date (with no printed period start), and the masked card number shares a line with unrelated limit figures — so this story confirms both derivations are correct and that the card last-4 is taken from the masked card number (anchored), not from the neighbouring limit numbers.

**Independent Test**: Parse a synthetic IOB statement whose text carries a `Stmt Date : <DD-MON-YYYY>` line and a masked card number printed inline with limit figures and anchored by `Credit Card Number`, and confirm the engine records the correct billing-cycle end date, leaves the period start unset, and records the correct card last-4 taken from the masked card number.

**Acceptance Scenarios**:

1. **Given** statement text containing `Stmt Date : 20-APR-2026`, **When** the engine parses it, **Then** the billing-cycle end is recorded as 2026-04-20 and the billing-cycle start is left unset (IOB prints no period start).
2. **Given** statement text containing the inline line `123456XXXXXX0042 16000 25091.5` anchored by a preceding `Credit Card Number` heading, **When** the engine parses it, **Then** the card last-4 is recorded as `0042` (the trailing four of the masked card number `123456XXXXXX0042`), and **not** `6000`, `5091`, or any digits taken from the adjacent limit figures `16000` / `25091.5`.
3. **Given** the `Stmt Date` label appears with varying spacing or letter case around the colon, **When** the engine parses it, **Then** the statement date is still recognized and used as the billing-cycle end (the label match is case-insensitive and tolerant of spacing).
4. **Given** statement text containing no recognizable statement date or masked card number, **When** the engine parses it, **Then** the corresponding metadata is simply absent (left unset) rather than fabricated, and the transactions are still returned.

---

### User Story 5 - Reconciliation stays out of scope: printed debit/credit totals are not ported (Priority: P5)

The web engine's IOB reader also scrapes the `ACCOUNT SUMMARY` block's **printed** per-statement `Payment / Credits` and `Purchases / Debits` totals (for a future reconciliation feature). This slice deliberately **does not** port those printed-total fields: the IOB output model for this slice carries only the transactions, the billing-cycle end date, and the card last-4. The printed totals belong to a later reconciliation slice.

**Why this priority**: This is the one place a faithful-looking full port would overreach. Keeping the printed-total scrape out of this slice's output model keeps the engine's shape identical to the credit-card readers already landed (none of which expose printed totals), avoids shipping a half-built reconciliation surface, and draws a clean boundary for the future reconciliation work. It is a reviewable, testable scope guarantee, and it mirrors the same carve-out already applied to the Yes reader.

**Independent Test**: Parse a synthetic IOB statement whose text also contains the `ACCOUNT SUMMARY` printed debit/credit total figures and confirm the engine returns only transactions + billing-cycle end + card last-4 — no printed-total values appear anywhere in the output, and the output model exposes no printed-total fields.

**Acceptance Scenarios**:

1. **Given** an IOB statement whose text contains an `ACCOUNT SUMMARY` block with printed `Payment / Credits` and `Purchases / Debits` totals, **When** the engine parses it, **Then** those printed totals are **not** extracted — the result contains only the per-row transactions, the billing-cycle end, and the card last-4.
2. **Given** the IOB parsed-statement output model produced by this slice, **When** it is inspected, **Then** it carries **no** printed debit/credit total fields (they are deferred to a future reconciliation slice).
3. **Given** the ported IOB golden vector's expected output, **When** it is inspected, **Then** it contains **no** printed-total fields — only rows, the billing-cycle end, the (absent) period start, the card last-4, and errored lines.

---

### User Story 6 - Correct the roadmap docs: IOB is a credit-card reader, not a bank-account reader (Priority: P6)

The project's two roadmap documents currently miscategorize IOB. `docs/HANDOFF.md` and `docs/kaname-ios-plan.md` both list IOB (`iob.py` / `iob`) under the **bank-account** readers, but IOB is a **credit-card** reader: it uses the line-based statement reader, registers under `account_kind="credit_card"`, and has **no** bank-account (ledger) reader. This story moves IOB from the bank-account list to the credit-card list in both documents so the roadmap reflects reality — six credit-card readers and four bank-account readers.

**Why this priority**: The documentation is the shared map of the ingestion architecture; leaving IOB in the wrong category would misrepresent the final reader set, imply a non-existent IOB ledger reader, and mislead future work. Correcting it is a small, self-contained, independently verifiable deliverable that is explicitly part of this slice. It also keeps the reader inventory consistent with what this slice actually builds (an IOB credit-card reader).

**Independent Test**: Inspect both roadmap documents after the change and confirm IOB appears in the credit-card reader list and no longer appears in the bank-account reader list, in both files, with the surrounding counts consistent (six credit-card readers, four bank-account readers).

**Acceptance Scenarios**:

1. **Given** `docs/HANDOFF.md`, **When** its reader inventory is inspected after the change, **Then** IOB (`iob.py`) is listed among the **credit-card** readers and is **absent** from the **bank-account** readers list.
2. **Given** `docs/kaname-ios-plan.md`, **When** its architecture reader list is inspected after the change, **Then** IOB (`iob`) is listed among the **credit-card** readers and is **absent** from the **bank-account** readers list.
3. **Given** both corrected documents, **When** the reader set is read as a whole, **Then** it consistently describes six credit-card readers and four bank-account readers (ten statement readers total), with no implication of an IOB bank-account/ledger reader.

---

### User Story 7 - Malformed rows are captured for review, never dropped or fatal (Priority: P7)

If a line looks like a transaction row but one of its fields will not parse, the engine keeps the raw line aside as an "errored line" for later review instead of crashing or silently discarding it — and it still returns every well-formed transaction from the same statement.

**Why this priority**: Real statements are messy. A single odd line must never take down the whole import or cause a person to lose the rest of their transactions. This resilience is what makes the parser safe to ship, and it is reused unchanged from the credit-card slices already landed.

**Independent Test**: Parse a statement that mixes well-formed rows with a row whose fields cannot be parsed, and confirm the good rows are all returned, the bad row is captured for review, and no error is raised.

**Acceptance Scenarios**:

1. **Given** a statement containing one unparseable row among several valid rows, **When** the engine parses it, **Then** all valid rows are returned as transactions and no error is raised.
2. **Given** the same statement, **When** the engine parses it, **Then** the unparseable row is captured as an errored line (its raw text preserved, bounded to a safe maximum length) for review.
3. **Given** lines that are not transaction rows at all (the header, the `Credit Card Number` line, the `ACCOUNT SUMMARY` block, the totals row, the `Total Purchase` line, and the end-of-statement marker), **When** the engine parses the statement, **Then** those lines are ignored without producing transactions and without being reported as errors.

---

### User Story 8 - Proven byte-for-byte against a golden fixture (Priority: P8)

As a maintainer, the engine's IOB behaviour is pinned to the proven web engine by porting the web engine's synthetic IOB characterization vector into the repository's `fixtures/` directory as a golden vector, with the on-device engine asserted to reproduce it exactly.

**Why this priority**: Parity is the constitution's acceptance mechanism for the port (Principle V). It turns "we think it matches" into an enforced, regression-proof guarantee, and it extends the harness that every parser reuses — this time proving the harness accepts the sixth and final credit-card bank as a one-row addition.

**Independent Test**: Run the parity harness over the ported IOB vector and confirm the engine's output matches the expected output exactly, and that re-running produces identical results.

**Acceptance Scenarios**:

1. **Given** the ported synthetic IOB golden vector, **When** the parity harness runs, **Then** the engine's parsed output (dates, amounts, directions, descriptions, billing-cycle end, absent period start, and card last-4) matches the expected output exactly — including the two rows (2026-03-31 / 1000.00 / credit / `ExampleRefundMerchant` and 2026-04-04 / 3500.00 / debit / `ExampleStorePurchase`), the billing-cycle end 2026-04-20, the absent period start, the card last-4 `0042`, and an empty errored-lines list.
2. **Given** a change that alters IOB parsing behaviour, **When** the parity harness runs, **Then** it fails, enforcing the parity guarantee.
3. **Given** the golden fixture, **When** it is inspected, **Then** all input and expected data is synthetic or fully redacted (fabricated merchants, amounts, and a masked card number) — never real account data.

---

### User Story 9 - Privacy gate: zero network in the parse path (Priority: P9)

As a maintainer, the existing automated privacy-egress test covers the IOB import/parse path and asserts it performs no network I/O, so the constitution's "free features run 100% on-device" guarantee holds for this slice and is protected against regressions.

**Why this priority**: Privacy is the product's non-negotiable promise and a required constitution gate. Extending the existing gate to cover IOB means the guarantee is proven for the new parser, not merely assumed.

**Independent Test**: Run the privacy-egress test against the IOB parse path and confirm it passes only when zero outbound network connections occur during parsing.

**Acceptance Scenarios**:

1. **Given** the IOB parse path, **When** the automated privacy-egress test runs, **Then** it confirms zero outbound network connections occur during parsing.
2. **Given** a regression that introduces any network access into the parse path, **When** the privacy-egress test runs, **Then** it fails, blocking the change.
3. **Given** the feature as a whole, **When** the engine and app are reviewed, **Then** no telemetry, analytics, advertising, or crash-reporting component is present in the parse path.

---

### Edge Cases

- **Wrong issuer**: A statement from another issuer (e.g., an HDFC statement) is presented to the IOB reader → it must not claim the document, so transactions are never misattributed to IOB.
- **Terminal direction marker**: The two-letter `Dr`/`Cr` marker sits at the **end** of the row, after the amount → direction is read from that marker (`Cr` → credit, `Dr` → debit) and the marker is not mistaken for part of the description or the amount.
- **Direction independent of magnitude**: A smaller `Cr` amount and a larger `Dr` amount (e.g., a 1000.00 credit refund and a 3500.00 debit purchase) → direction follows each row's marker, never the relative size of the amounts.
- **Direction vs description wording**: A description containing a credit/debit-like word → direction is still taken from the terminal `Dr`/`Cr` marker, not from the description text.
- **Uppercase month in the date**: The date's month is uppercase (e.g., `MAR`, `APR` in `31-MAR-2026`) → the shared date parser's case-insensitive `%d-%b-%Y` format parses it without any IOB-specific date handling.
- **Indian money formatting**: Amounts with thousands separators (e.g., `1,000.00`, `3,500.00`, and the Indian grouping style such as `1,23,456.78`) → parsed to the exact, non-negative decimal value, with stated precision preserved (e.g., `1,000.00` → 1000.00 keeps two decimal places).
- **Cycle end from the statement date only**: The statement prints a single `Stmt Date : <DD-MON-YYYY>` with no explicit period range → that date is the billing-cycle end and the period start is left unset (never fabricated).
- **Card last-4 from an inline masked card number**: The masked card number `123456XXXXXX0042` is printed on the **same line** as the credit/cash limit figures (`16000 25091.5`) and located via the `Credit Card Number` anchor → the trailing four digits `0042` are recorded as the card last-4, and no digits are taken from the neighbouring limit numbers.
- **Header / summary / totals lines**: The header, the `Credit Card Number` line, the `ACCOUNT SUMMARY` block (including its `Payment / Credits` and `Purchases / Debits` figures), the totals row, the `Total Purchase` line, and the end-of-statement marker do not match the leading-date + trailing-`Dr`/`Cr` anchor → they are ignored (no transaction, no error).
- **Printed totals present but excluded**: The `ACCOUNT SUMMARY` printed debit/credit totals are present in the text → they are deliberately **not** extracted into this slice's output model (reconciliation is a later slice).
- **Unparseable row**: A line that resembles a transaction row but whose fields will not parse → captured as an errored line; every good row in the same statement is still returned; no error is raised.
- **No transaction lines**: Empty input, or input with no recognizable rows → an empty transaction list is returned with no error.
- **Missing metadata**: No recognizable statement date or masked card number in the text → billing-cycle end and card last-4 are left unset rather than fabricated.
- **Repeated / concurrent parses**: The same input parsed repeatedly → identical results every time, with no dependence on wall-clock time, locale, or hidden global state.

## Requirements *(mandatory)*

### Functional Requirements

**Document recognition**

- **FR-001**: The engine MUST recognize a statement as an Indian Overseas Bank (IOB) credit-card statement via an issuer/document-plausibility check — the statement text contains an IOB issuer marker (`INDIAN OVERSEAS BANK` or `iobnet.co.in`) — before parsing it as IOB.
- **FR-002**: The engine MUST NOT claim a statement that belongs to a different issuer (e.g., an HDFC statement), so a document is only parsed by the reader that recognizes it.

**Transaction extraction (the core parse)**

- **FR-003**: The engine MUST parse IOB's single credit-card statement layout `DD-MON-YYYY <merchant> <amount> Dr|Cr` — a `DD-MON-YYYY` date with an uppercase month (e.g., `31-MAR-2026`), followed by the merchant/description text, the amount, and a terminal two-letter `Dr`/`Cr` direction marker — and MUST produce exactly one transaction per matching row.
- **FR-004**: Each produced transaction MUST include the transaction date, the amount, the debit/credit direction, the description text, and the currency (Indian Rupees, INR).
- **FR-005**: Lines that are not transaction rows — including the header, the `Credit Card Number` line, the `ACCOUNT SUMMARY` block, the totals row, the `Total Purchase` line, and the end-of-statement marker — MUST be ignored without producing transactions or errors. Recognition is anchored on a leading `DD-MON-YYYY` date and a trailing `Dr`/`Cr` marker, which those non-transaction lines do not match.

**Amount**

- **FR-006**: The engine MUST parse each amount as an exact, non-negative decimal using Indian number formatting (thousands separators, including the Indian grouping style), preserving the stated precision (e.g., `1,000.00` → 1000.00 retains two decimal places).
- **FR-007**: Monetary amounts MUST NEVER be represented as floating-point numbers; they MUST be exact decimals throughout.

**Direction / polarity**

- **FR-008**: The engine MUST determine each transaction's debit/credit direction from the statement's own terminal `Dr`/`Cr` marker and MUST NEVER infer it from the sign or magnitude of the amount, nor from words in the description.
- **FR-009**: The terminal marker MUST set the direction: `Cr` → credit, `Dr` → debit.

**Statement metadata**

- **FR-010**: The engine MUST derive the billing-cycle **end** date from text of the form `Stmt Date : <DD-MON-YYYY>` (e.g., `Stmt Date : 20-APR-2026` → 2026-04-20), matching the label case-insensitively and tolerant of spacing around the colon. IOB prints no explicit period range, so the engine MUST leave the billing-cycle **start** unset (it MUST NOT fabricate a start date).
- **FR-011**: The engine MUST extract the card's last four digits from the masked card number located via the `Credit Card Number` anchor (e.g., the inline line `123456XXXXXX0042 16000 25091.5` → `0042`), taking the trailing four digits of the masked card number and NOT any digits from the adjacent credit/cash limit figures printed on the same line.
- **FR-012**: When a metadata field cannot be found, the engine MUST leave it unset rather than fabricate a value, and MUST still return the parsed transactions.

**Scope boundary — reconciliation excluded**

- **FR-013**: This slice MUST NOT port the web engine's IOB printed-total scrape: the `ACCOUNT SUMMARY` printed per-statement `Payment / Credits` and `Purchases / Debits` totals MUST NOT appear in this slice's output model. The IOB parsed result for this slice MUST carry only the transactions, the billing-cycle end date, the (absent) period start, the card last-4, and any errored lines. (Printed totals are deferred to a future reconciliation slice, matching the Yes carve-out.)

**Documentation correction (part of this slice)**

- **FR-014**: The change MUST correct `docs/HANDOFF.md` so IOB (`iob.py`) is listed among the **credit-card** readers and removed from the **bank-account** readers list, reflecting that IOB uses the line-based statement reader, registers under `account_kind="credit_card"`, and has no bank-account (ledger) reader.
- **FR-015**: The change MUST correct `docs/kaname-ios-plan.md` so IOB (`iob`) is listed among the **credit-card** readers and removed from the **bank-account** readers list, and MUST leave the reader inventory consistent (six credit-card readers, four bank-account readers; ten statement readers total).

**Robustness**

- **FR-016**: A line that resembles a transaction row but whose fields cannot be parsed MUST be captured as an "errored line" (raw text preserved, bounded to a safe maximum length) for later review; the engine MUST NOT raise an error or silently drop it, and MUST still return every successfully parsed row.

**Engine purity, platform boundary & reuse**

- **FR-017**: The engine's IOB parse MUST reuse the existing "one transaction per text line" reader seam — accepting already-extracted text lines plus the full statement text and returning the parsed result; it MUST NOT read files, extract PDF text, or embed a PDF engine (text extraction is a native platform concern).
- **FR-018**: The engine MUST remain pure and deterministic: identical input MUST yield identical output, with no dependence on network, wall-clock time, locale, or hidden global mutable state.
- **FR-019**: IOB MUST reuse — not rebuild — the existing shared output types (parsed statement / parsed transaction), the amount / date / last-4 / polarity helpers (including the case-insensitive `%d-%b-%Y` date format that parses uppercase months and the two-letter `Dr`/`Cr` marker classification), the golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate. This slice MUST add **no new shared engine helper**; IOB is delivered as a new single-layout reader configuration only.
- **FR-020**: The engine MUST expose IOB over the existing UniFFI bridge with an IOB parse entry point and an IOB issuer-claims function, mirroring the credit-card readers already landed (two exports).

**Privacy (constitution Principle I — NON-NEGOTIABLE)**

- **FR-021**: The entire IOB import/parse path MUST run 100% on-device with ZERO network I/O.
- **FR-022**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting into the engine or the app.
- **FR-023**: The existing automated privacy-egress test MUST cover the IOB parse path and assert it performs no network access; it remains a required constitution gate.

**Parity & test-first (constitution Principle V)**

- **FR-024**: The web engine's synthetic IOB characterization vector MUST be ported into the repository's `fixtures/` directory (under `fixtures/iob/credit_card/`) as a golden vector, and the engine MUST reproduce it exactly.
- **FR-025**: All fixture and test data MUST be synthetic or fully redacted (fabricated merchants, amounts, and a masked card number) — never real account data.
- **FR-026**: The IOB parsing behaviour introduced by this slice MUST be developed test-first (a failing golden test precedes the behaviour).

**Licensing, secrets & quality gates**

- **FR-027**: The change MUST NOT add secrets, API keys, or private endpoints; MUST remain distributable under Apache-2.0 with no copyleft (GPL/AGPL/LGPL) dependencies; and MUST introduce NO new runtime dependencies for this slice.
- **FR-028**: The change MUST keep the iOS Local Verification Gate and CI green: core formatting, linting, and tests; app linting; project generation; a simulator build with passing app tests; and the privacy gate.
- **FR-029**: If any user-facing surface is introduced for this slice, it MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility.

### Key Entities *(include if feature involves data)*

- **Extracted statement text (input)**: The already-extracted text lines plus the full statement text handed to the engine by the native platform. Contains no PDF binary; the engine never opens a PDF.
- **Parsed transaction**: One statement row's result — a transaction date, an exact non-negative amount, an explicit debit/credit direction, a currency (INR), and a description.
- **Parsed statement result**: The full output of reading one statement — the issuer/bank identity (`IOB`), the list of parsed transactions, the list of errored (unparseable) lines, the billing-cycle end date, the (absent) billing-cycle start, and the card last-4. For this slice the result deliberately excludes the printed debit/credit totals used for reconciliation.
- **Direction (polarity)**: An explicit debit or credit indicator carried on every transaction, sourced from the statement's own terminal `Dr`/`Cr` marker and never from the amount's sign.
- **Golden characterization vector**: A synthetic IOB input (text lines + full text) paired with its expected engine output, stored under `fixtures/iob/credit_card/`, ported from the web engine and reproduced exactly by the on-device engine.
- **Roadmap reader inventory**: The reader lists in `docs/HANDOFF.md` and `docs/kaname-ios-plan.md` that classify each reader as credit-card or bank-account; this slice moves IOB from the bank-account list to the credit-card list in both.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For the two synthetic IOB golden rows, the engine produces exactly the expected transactions — row 1 → date 2026-03-31, amount 1000.00, direction credit, description `ExampleRefundMerchant`; row 2 → date 2026-04-04, amount 3500.00, direction debit, description `ExampleStorePurchase` (100% match).
- **SC-002**: The engine recognizes the synthetic IOB statement as IOB and does not claim a non-IOB (e.g., HDFC) statement — 0 misattributions across the recognition cases.
- **SC-003**: From the synthetic IOB statement text, the engine records the billing-cycle end as 2026-04-20, leaves the billing-cycle start unset, and records the card last-4 as `0042`.
- **SC-004**: The card last-4 is taken from the masked card number `123456XXXXXX0042` (yielding `0042`) and is never taken from the adjacent limit figures `16000` / `25091.5` printed on the same line — 0 cases of digits bleeding from the limits.
- **SC-005**: Direction is correct across every tested case — a terminal `Cr` → credit and a terminal `Dr` → debit — and is never changed by the amount's sign or magnitude (the 1000.00 `Cr` refund is credit and the larger 3500.00 `Dr` purchase is debit), nor by direction-like words in the description.
- **SC-006**: 100% of parsed amounts are exact decimals with their stated precision preserved and are always non-negative; no monetary value is ever a floating-point number.
- **SC-007**: The header, the `Credit Card Number` line, the `ACCOUNT SUMMARY` block, the totals row, the `Total Purchase` line, and the end-of-statement marker produce **no** transactions — the synthetic reference statement yields exactly its two transaction rows and nothing from the non-transaction lines.
- **SC-008**: A malformed row is captured for review while every well-formed row in the same input is still returned, and no error is raised (the parse never aborts on a bad row).
- **SC-009**: Zero outbound network connections occur during the entire IOB parse path, verified by the automated privacy-egress test.
- **SC-010**: Given identical input, the engine returns identical output across repeated runs (100% reproducible).
- **SC-011**: The ported synthetic IOB golden vector reproduces exactly and the parity harness passes; re-running is stable.
- **SC-012**: IOB is added with **zero new shared engine helpers** — the change consists only of a new single-layout reader configuration, a golden fixture, two UniFFI exports, one parity case row, and the two roadmap-doc corrections; the shared reader/date/polarity/last-4 helper surface is unchanged (verified by review of the change set).
- **SC-013**: The IOB output model and its golden vector carry only transactions, the billing-cycle end, the (absent) period start, and the card last-4 (plus errored lines) — the `ACCOUNT SUMMARY` printed debit/credit totals the web reader extracts for reconciliation are **absent** (verified by review of the output model and the fixture's expected output).
- **SC-014**: Both roadmap documents (`docs/HANDOFF.md` and `docs/kaname-ios-plan.md`) list IOB under the **credit-card** readers and no longer under the **bank-account** readers, and the reader inventory reads consistently as six credit-card readers and four bank-account readers (ten total).
- **SC-015**: The IOB parse is reachable over the existing UniFFI bridge to Swift (an IOB parse entry point and an IOB claims function), mirroring the credit-card readers already landed.
- **SC-016**: All automated checks required to merge pass (green), including the parity harness and the privacy-egress test, with the iOS Local Verification Gate and CI green; and no secrets, network entitlements, telemetry, copyleft-licensed dependencies, or new runtime dependencies are added by the feature (verified by review of manifests and dependencies).

## Assumptions

- **Single-layout reader & seam**: IOB is added as a **single-layout** reader configuration reusing the existing `read_lines(lines, full_text)` seam; there is exactly one row layout (`DD-MON-YYYY <merchant> <amount> Dr|Cr`). The exact module layout and row pattern are finalized in `/speckit.plan`.
- **No new shared helpers**: IOB needs **no** new shared engine helpers. Its `DD-MON-YYYY` date with an uppercase month is parsed by the shared date parser's existing case-insensitive `%d-%b-%Y` format, and its two-letter `Dr`/`Cr` direction markers are handled by the shared polarity classifier (direction read from the explicit marker, with no running-balance delta). Card last-4 uses the shared anchored last-4 helper (anchored on `Credit Card Number`). This makes IOB a clean single-layout drop-in, like SBI and Yes.
- **Statement-date cycle end, no period start**: IOB prints a single `Stmt Date : <DD-MON-YYYY>` and no explicit period range; the engine uses that date as the billing-cycle end and leaves the period start unset. Exact label matching (case-insensitive, spacing-tolerant) is finalized in `/speckit.plan`.
- **Inline masked card number**: The masked card number is printed on the same line as the credit/cash limit figures and is located via the `Credit Card Number` anchor; the last-4 is the trailing four digits of the masked card number, never digits from the adjacent limits.
- **Reconciliation carve-out**: The web engine's IOB reader also scrapes the `ACCOUNT SUMMARY` printed `Payment / Credits` and `Purchases / Debits` totals for reconciliation. Those fields are **out of scope** for this slice and are deliberately **not** ported into the output model; they belong to a future reconciliation slice. This matches the already-landed credit-card readers, none of which expose printed totals, and specifically mirrors the Yes carve-out.
- **Documentation correction is in scope**: Correcting the IOB miscategorization in `docs/HANDOFF.md` and `docs/kaname-ios-plan.md` (moving IOB from the bank-account reader list to the credit-card reader list) is an explicit deliverable of this slice.
- **Binding**: IOB is exposed to Swift via the existing UniFFI bridge with an IOB parse entry point and an IOB issuer-claims function, mirroring the credit-card readers already landed (two exports); concrete binding mechanics belong in `/speckit.plan`.
- **Fixtures location**: The golden fixture lives under `fixtures/iob/credit_card/` and is the source of truth for parity.
- **Bank code**: The issuer/bank identity for this reader is `IOB`, registered under `account_kind="credit_card"`. There is no IOB bank-account (ledger) reader.
- **Reused, not rebuilt**: The `read_lines`/`claims`/reader-configuration seam, the parsed-statement / parsed-transaction output types, the amount / date / last-4 / polarity helpers, the golden-fixture JSON parity harness, the UniFFI bridge, and the privacy-egress gate were all built in the earlier slices; IOB plugs into every one of them unchanged.
- **No new dependencies**: This slice should require **no** new runtime dependencies.
- **Source of truth**: The web engine is the source of truth for behaviour — `iob.py` plus the shared line-reader, common helpers, and polarity module, and the credit-card characterization test (whose IOB case values are reproduced in this spec and captured in the ground-truth vector). The porting approach (module layout, patterns, regexes, fixture format, UniFFI exports) is decided in `/speckit.plan`, not here.
- **No new UI required**: This is an engine slice; no user-facing UI is required to deliver it. App-side PDF text extraction (PDFKit wiring), the file-import UI, and the Share Extension remain a native concern and a later step. If a trivial demo surface is added, it follows HIG and accessibility (FR-029).
- **Data safety**: All fixture and test data is synthetic or fully redacted — no real account data.
- **Money & polarity**: Amounts are exact decimals (never floating-point) and direction is carried explicitly and sourced from the statement's terminal `Dr`/`Cr` marker, consistent with the engine's existing domain types.

### Dependencies

- **Kaname Constitution v1.0.0** — privacy (zero-network free/core), determinism, a pure platform-agnostic core (no PDF engine), decimal money with explicit polarity, Apache-2.0 open-core with no copyleft, native HIG/accessibility, and the test-first iOS Local Verification Gate (including the privacy-egress gate).
- **Milestone P1 bridge (already landed)** — the shared engine crate and the UniFFI Swift binding proven end-to-end, over which the IOB parse and claims functions are exposed.
- **Credit-card slices already landed (ICICI, HDFC, SBI, Yes, Federal)** — the shared "one transaction per text line" reader seam and per-issuer reader configuration, the parsed-statement / parsed-transaction domain types, the amount / date / last-4 / polarity helpers (including the case-insensitive `%d-%b-%Y` date format and the `Dr`/`Cr` marker classification IOB reuses), the golden-fixture parity harness, and the privacy-egress gate. SBI and Yes are the clean single-layout drop-ins whose pattern IOB follows exactly (a new reader configuration, a golden fixture, two bridge exports, and one parity case row, with no new shared helpers); the Yes reconciliation carve-out is the precedent for IOB's printed-total exclusion.
- **Bank-account ledger slices already landed (ICICI bank, HDFC bank, Federal bank, AU bank)** — the four bank-account readers that, together with the six credit-card readers, complete the planned set of ten statement readers.
- **Web engine golden vector** — the synthetic IOB characterization vector and the IOB reader behaviour (`iob.py`) used as the parity source of truth.
- **Roadmap documents** — `docs/HANDOFF.md` and `docs/kaname-ios-plan.md`, whose IOB categorization this slice corrects.

## Out of Scope

Deferred to later slices / milestones, or explicitly excluded:

- **Reconciliation** (the printed-total integrity check) — **including the `ACCOUNT SUMMARY` printed per-statement `Payment / Credits` and `Purchases / Debits` totals the web IOB reader extracts**; these are explicitly not ported in this slice — plus **coverage / billing-period timeline**, **cross-source de-duplication and transfer detection**, and **balance-chain integrity**.
- **An IOB bank-account (ledger) reader** — none exists and none is planned; IOB is a credit-card-only reader (the documentation correction reflects this).
- The `(bank_code, account_kind)` registry **beyond what the IOB credit-card reader needs**.
- **Encrypted SQLite / SQLCipher persistence** and key management.
- **AI-fallback parsing**.
- Any **premium / cloud features**.
- **App-side PDF text extraction** (PDFKit wiring in the app) and the **file-import UI / Share Extension** — native concerns handled in a later slice. This slice focuses on the IOB engine parse plus its golden-fixture parity and the roadmap-doc correction, reusing the existing privacy gate and exposed over the existing bridge.
