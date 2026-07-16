# Feature Specification: Read a Bank-Account (Savings/Current) Statement On-Device — the Balance-Ledger Reader Base + Balance-Chain Integrity + ICICI as the First Reference Reader (Second Reader Family)

**Feature Branch**: `007-bank-account-ledger-reader`  
**Created**: 2026-07-16  
**Status**: Draft  
**Milestone**: P2 (next slice) — the first bank-account (balance-ledger) reader family, after the five credit-card issuers  
**Input**: User description: "Bank-account (savings/current) statement reading for the on-device Kaname core — the second reader family after the five credit-card issuers. A bank-account statement is a Withdrawal/Deposit/running-Balance ledger with NO Dr/Cr marker, so the existing credit-card line reader structurally cannot read it. This slice delivers THREE things: (1) a new reusable balance-ledger reader base that derives each transaction's direction from the running-balance delta (debit when the balance falls, credit when it rises) and treats the printed amount as an INDEPENDENT integrity check (amount == |balance delta|); (2) a balance-chain integrity check that walks the rows and reports RECONCILED or NEEDS_REVIEW with the suspect rows; and (3) ICICI savings/current as the FIRST reference reader on that base. HDFC, Federal and AU bank-account readers follow in later slices (out of scope here). IOB is a credit-card reader, not a ledger reader (also out of scope)."

> **Note on priority labels**: This feature is milestone **P2** in the product roadmap (`docs/kaname-ios-plan.md` §9). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P2" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

The five previous slices (milestone P2) landed the complete **credit-card** reader set — **ICICI**, **HDFC**, **SBI Card**, **Yes Bank (Kiwi)**, and **Federal / Scapia** — on a shared **"one transaction per text line"** seam whose direction comes from an explicit **Dr/Cr** indication. A **bank-account** (savings/current) statement is a different animal: it is a **Withdrawal / Deposit / running-Balance ledger with NO Dr/Cr marker**, so the credit-card line reader **structurally cannot read it** — there is no marker to read direction from. This slice opens the **second reader family** and delivers **three** things together:

1. **A new reusable balance-ledger reader base.** It derives each transaction's direction from the **running-balance delta** — a **debit** when the balance falls, a **credit** when it rises — and treats the **printed amount as an INDEPENDENT integrity check** (the printed amount should equal the absolute value of the balance delta). Direction is **never** taken from an amount's sign.
2. **A balance-chain integrity check.** It walks the ledger rows and reports the statement as **RECONCILED** or **NEEDS_REVIEW**, naming the **suspect** rows. A row whose printed amount does not match its balance delta is a **suspect** — it is flagged but **still returned** (never silently dropped).
3. **ICICI savings/current as the FIRST reference reader** on that base, proven byte-for-byte against a golden fixture, exactly as each credit-card issuer was.

This is a **determinism / parity** slice (Constitution Principle V): the behaviours are ported faithfully from the proven web engine, and the on-device engine must reproduce the reference ground truth exactly.

The platform boundary is unchanged and fixed by the constitution and locked decisions: **text extraction is native** — on iOS, the platform extracts the statement's text lines, its full text, and (for a bank statement) the **first transaction row's word geometry** (each word with its x-position), and hands them to the shared engine. The shared engine **never** embeds a PDF engine; **the Rust core never opens a PDF.** Its entry point is a pure seam that takes already-extracted text (plus first-row word geometry) and returns the parsed result.

### User Story 1 - Turn an ICICI savings/current statement into transactions, on-device (Priority: P1)

A person imports their ICICI **savings / current** account statement. The platform extracts the statement's text natively and hands it to the shared engine; the engine recognizes the document as an ICICI **bank-account** statement and returns the ledger's transactions — each with its date, amount, debit/credit direction, and description — computed entirely on the device with no network access. Direction is derived from the running-balance movement, not from any Dr/Cr column (there is none).

**Why this priority**: This is the headline value and the smallest slice that turns a real bank-account statement into usable data. It is a viable MVP on its own: a person gets their savings/current transactions from their statement, on-device, opening the entire second reader family. Every subsequent story refines this parse.

**Independent Test**: Provide the engine with the extracted text of the synthetic ICICI savings reference statement and confirm it recognizes the issuer as an ICICI bank-account statement and returns one transaction per ledger row — each carrying a date, an exact amount, a delta-derived direction, and a stitched description — with no network access during the parse.

**Acceptance Scenarios**:

1. **Given** the extracted text of the synthetic ICICI savings reference statement, **When** the engine parses it, **Then** it recognizes the document as an ICICI bank-account statement and returns exactly three transactions.
2. **Given** the reference ledger, **When** the engine parses it, **Then** row 1 is dated 2025-06-16, amount 5000.00, direction **debit**, description `UPI/512345/ALICE STORE/Payment`; row 2 is dated 2025-06-18, amount 50000.00, direction **credit**, description `NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY`; row 3 is dated 2025-06-20, amount 2000.00, direction **debit**, description `ATM CASH WITHDRAWAL` — all in Indian Rupees.
3. **Given** the reference ledger, **When** the engine parses it, **Then** each row also carries its running balance (95000.00, 145000.00, 143000.00) and its balance delta (−5000.00, +50000.00, −2000.00).
4. **Given** the device has no network connectivity, **When** the statement is parsed, **Then** the transactions are still produced, proving the parse is fully local.

---

### User Story 2 - Direction from the running-balance delta; the printed amount is an independent integrity check (Priority: P2)

Each transaction's direction (money in vs money out) is decided **solely** by how the running balance moved: a **fall** in the balance is a **debit**, a **rise** is a **credit**. The printed amount is used only as an **independent integrity check** — it should equal the absolute value of the balance delta (within a small rounding tolerance). The direction is never guessed from whether an amount looks positive, negative, large, or small.

**Why this priority**: Deriving polarity from the balance movement (never from the amount) is the defining rule of the balance-ledger family and the non-negotiable engine invariant for bank statements. Getting it wrong silently corrupts every downstream total. Treating the printed amount as a cross-check (not a source of direction) is what makes the ledger self-verifying.

**Independent Test**: Parse rows whose balance rises and rows whose balance falls and confirm each is classified credit and debit respectively; then flip the balance movement for a row (independent of its printed amount) and confirm the direction flips accordingly — proving the amount never drives the direction.

**Acceptance Scenarios**:

1. **Given** a row whose running balance falls from the previous balance (e.g., 100000.00 → 95000.00), **When** it is parsed, **Then** its direction is **debit**.
2. **Given** a row whose running balance rises from the previous balance (e.g., 95000.00 → 145000.00), **When** it is parsed, **Then** its direction is **credit**.
3. **Given** any row, **When** the sign of its balance delta is flipped (by changing the surrounding balances) while its printed amount is left unchanged, **Then** its direction flips between debit and credit — the direction follows the delta, never the amount.
4. **Given** a row whose printed amount equals the absolute value of its balance delta within the rounding tolerance (₹1.00), **When** it is parsed, **Then** the row is marked as reconciling (amount matches delta) and is **not** a suspect.
5. **Given** a row whose printed amount differs from the absolute value of its balance delta by more than the rounding tolerance, **When** it is parsed, **Then** the row is marked a **suspect** (amount does not match delta) — yet the transaction is **still returned**, never silently dropped.

---

### User Story 3 - A reusable balance-ledger reader base: anchor rows and narration stitching (Priority: P3)

As a maintainer, the slice introduces a **reusable balance-ledger reader base** (the shared engine for this whole second family) so that later bank-account readers (HDFC, Federal, AU) reuse it. The base recognizes a transaction as an **anchor row** ending in money tokens and reassembles the row's human-readable **narration** from the wrapped detail lines around the anchor. ICICI is the first configuration on this base.

**Why this priority**: The base is the point of the slice — it is what makes "the second reader family" real rather than a one-off. Fixing the anchor shape and the narration-stitching rule now, and proving them on ICICI, is what lets every later bank drop in as a small per-issuer configuration (its own anchor pattern and column split) with no new shared engine internals.

**Independent Test**: Confirm the ICICI bank parse is delivered by a per-issuer configuration plugged into the shared balance-ledger base; confirm the base recognizes an anchor row via a per-issuer anchor pattern with named groups (serial, date, amount, balance, optional description), ignores per-page headers and cheque-number lines, and stitches each row's description from the detail line immediately above the anchor plus the detail lines below it up to the next transaction.

**Acceptance Scenarios**:

1. **Given** an ICICI ledger row that ends in two money tokens `… <amount> <balance>` (the single-amount template), **When** the base reads it, **Then** it captures the serial, date, amount, and running balance via the per-issuer anchor pattern's named groups.
2. **Given** a per-page header line or a cheque-number line (a line with no decimal money tokens), **When** the base scans it, **Then** it does **not** match it as an anchor row (no transaction, no error).
3. **Given** an anchor row with a wrapped detail line immediately **above** it (e.g., a payer/VPA line) and detail lines **below** it up to the next transaction, **When** the base stitches the narration, **Then** the row's description is reassembled from the line above plus the lines below, **skipping** any other anchor rows and any printed-balance lines. For the reference statement this yields `UPI/512345/ALICE STORE/Payment`, `NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY`, and `ATM CASH WITHDRAWAL`.
4. **Given** the base's design, **When** a two-column **Withdrawal / Deposit / Balance** template is configured (as later HDFC/Federal/AU readers require), **Then** the base supports that anchor shape too — even though ICICI itself uses the single-amount `<amount> <balance>` template.

---

### User Story 4 - Balance-chain integrity: RECONCILED / NEEDS_REVIEW with the suspect rows (Priority: P4)

Beyond parsing rows, the engine runs a **balance-chain integrity check** that walks the ledger and reports the statement as **RECONCILED** or **NEEDS_REVIEW**, naming the **suspect** rows. A row whose printed amount does not match its balance delta is a **suspect** (a chain break) — it is flagged but **still returned**. This is distinct from an **errored** line: only a genuinely unparseable, anchor-shaped row (bad date/amount/balance) is captured as an errored line; a chain break is a suspect, not an error.

**Why this priority**: The balance chain is the second headline deliverable and the bank-statement analogue of the credit-card reconciliation gate. It is what turns "we parsed some rows" into "we can trust this ledger" — surfacing exactly which rows to review while never discarding data. The errored-vs-suspect distinction keeps genuinely broken rows and merely-inconsistent rows in separate, correctly-labelled buckets.

**Independent Test**: Run the balance-chain check over a clean reference ledger and confirm it reports **RECONCILED** with zero suspects; then introduce a row whose printed amount does not equal its balance delta and confirm the check reports **NEEDS_REVIEW** naming that row as a suspect — while the row is still present in the returned transactions; separately, confirm an unparseable anchor-shaped row is captured as an errored line rather than a suspect.

**Acceptance Scenarios**:

1. **Given** the reference ledger (every printed amount equals its balance delta and row 1 is anchored by a printed opening balance), **When** the balance-chain check runs, **Then** it reports **RECONCILED** with **zero** suspect rows and no row-1 fallback.
2. **Given** a ledger containing one row whose printed amount does **not** equal the absolute value of its balance delta (beyond the ₹1.00 tolerance), **When** the balance-chain check runs, **Then** it reports **NEEDS_REVIEW** and names that row among the suspects.
3. **Given** that same ledger, **When** the statement is returned, **Then** the suspect row is **still included** in the transactions (flagged, never dropped), together with every reconciling row.
4. **Given** a line that matches an anchor's shape but whose date, amount, or balance cannot be parsed, **When** the statement is read, **Then** that line is captured as an **errored line** (raw text preserved, bounded to a safe maximum length) — **not** reported as a suspect — and every well-formed row is still returned.

---

### User Story 5 - Row-1 bootstrap: opening balance, then first-row geometry, then a flagged provisional (Priority: P5)

The first ledger row has **no predecessor balance**, so its direction cannot come from a delta yet. The engine resolves row 1 by a fixed precedence and records **where** the decision came from as a per-row `direction_source`: (a) a printed **"Opening Balance" / "B/F"** line when present (preferred, geometry-free); else (b) the amount word's **x-position** versus a per-issuer **column split** (a word in the withdrawal column ⇒ debit), using the **first-row word geometry supplied by the native platform** (iOS PDFKit) — **the Rust core never opens a PDF**; else (c) a **provisional** direction, flagged so the balance chain marks the run **NEEDS_REVIEW**.

**Why this priority**: Row 1 is the one place the delta rule cannot self-start, so a principled, auditable bootstrap is required to keep the whole chain trustworthy. Recording the `direction_source` makes every first-row decision auditable, and routing the un-anchored cases to NEEDS_REVIEW guarantees an uncalibrated guess is never silently trusted.

**Independent Test**: Parse a statement with a printed opening balance and confirm row 1's direction is set from it with `direction_source = opening_balance` (no geometry used); parse one with no opening balance but with first-row word geometry and confirm the x-position column split is used with `direction_source = row1_xposition`; parse one with neither and confirm a provisional direction is set with `direction_source = row1_provisional` and the balance chain is NEEDS_REVIEW.

**Acceptance Scenarios**:

1. **Given** the reference statement, which prints an opening balance of 100000.00, **When** row 1 (balance 95000.00) is bootstrapped, **Then** its delta is computed against the printed opening balance (95000.00 − 100000.00 = −5000.00) so its direction is **debit**, and `direction_source = opening_balance` — with no geometry consulted.
2. **Given** a statement with **no** printed opening balance but with first-row word geometry, **When** row 1 is bootstrapped, **Then** the amount word's x-position versus the per-issuer column split decides the direction (withdrawal column ⇒ debit) and `direction_source = row1_xposition`.
3. **Given** a statement with **neither** a printed opening balance nor first-row geometry, **When** row 1 is bootstrapped, **Then** a **provisional** direction is set, `direction_source = row1_provisional`, and the balance chain reports the run **NEEDS_REVIEW**.
4. **Given** the geometry path (`row1_xposition`), **When** the statement is reported in this slice, **Then** the row is surfaced as **NEEDS_REVIEW** (the x-position path is supported but not yet calibrated against a real statement) — an uncalibrated first-row decision is never silently trusted.
5. **Given** any row after the first, **When** it is bootstrapped, **Then** its direction is derived from its balance delta and `direction_source = balance_delta`.

---

### User Story 6 - Ledger metadata: per-row fields and statement-level fields, with a bank-aware account last-4 (Priority: P6)

Each parsed row carries **ledger metadata** — its running **balance**, its **balance delta**, whether its printed **amount matches the delta**, whether it **is a suspect**, its **direction source**, and its **serial**. The statement carries **printed opening balance**, **printed closing balance**, the **billing period**, and the account's **last four digits** — recovered from the trailing four digits of the printed **account number** by a **bank-account-aware extractor**, **not** the credit-card masked-PAN matcher.

**Why this priority**: These fields are what make the ledger auditable and attributable: the per-row balance/delta/suspect data drives the balance chain and later review UI, and the statement-level opening/closing/period/account-last-4 place the transactions on the right account and timeline. Using an account-number-tail extractor (rather than the card masked-PAN matcher) is what makes the last-4 correct for a bank account.

**Independent Test**: Parse the reference statement and confirm each row exposes balance, balance delta, amount-matches-delta, is-suspect, direction-source, and serial; and confirm the statement records printed opening 100000.00, printed closing 143000.00, period 2025-06-16 to 2025-07-15, and account last-4 `3456` derived from the printed account number's trailing four digits.

**Acceptance Scenarios**:

1. **Given** the reference statement, **When** it is parsed, **Then** each row exposes its running balance, its balance delta, an amount-matches-delta indicator, an is-suspect indicator, its direction source, and its serial (1, 2, 3).
2. **Given** the reference statement, **When** it is parsed, **Then** the statement records `printed_opening_balance = 100000.00` and `printed_closing_balance = 143000.00`.
3. **Given** the reference statement, **When** it is parsed, **Then** the billing period is recorded as start 2025-06-16 and end 2025-07-15.
4. **Given** the reference statement's printed account number, **When** the account last-4 is extracted, **Then** it is `3456` — taken from the trailing four digits of the printed account number by the bank-account-aware extractor (not the credit-card masked-PAN matcher).
5. **Given** a statement in which a metadata field cannot be found, **When** it is parsed, **Then** that field is left unset rather than fabricated, and the transactions are still returned.

---

### User Story 7 - The document gate tells an ICICI savings statement from an ICICI credit-card statement (Priority: P7)

ICICI issues **both** credit-card and savings/current statements, so they share the issuer. The bank reader's document gate (`claims`) must therefore be specific: it recognizes a document only when it carries the ICICI **bank code**, **all** of a set of **required** markers, and **any** of an **optional** set — enough to tell an ICICI **savings** statement from an ICICI **credit-card** statement. An ICICI **credit-card** statement must be **REJECTED** by the bank reader.

**Why this priority**: Because the issuer is shared, a naive issuer-only check would misroute an ICICI credit-card statement into the bank reader (or vice-versa). Making the gate distinguish the two document types is what keeps each statement handled by exactly the right reader — a correctness prerequisite for the whole dual-reader (credit-card + bank-account) design.

**Independent Test**: Ask the bank reader whether it claims the synthetic ICICI savings reference statement (expect yes) and whether it claims an ICICI credit-card statement (expect no), confirming the required + optional marker gate separates the two document types that share the ICICI issuer.

**Acceptance Scenarios**:

1. **Given** the synthetic ICICI savings reference statement, **When** the bank reader's document gate is asked, **Then** it **claims** the document (ICICI bank code present, all required markers present, at least one optional marker present).
2. **Given** an ICICI **credit-card** statement, **When** the bank reader's document gate is asked, **Then** it does **not** claim the document — the credit-card statement is rejected by the bank reader.
3. **Given** a statement from a different issuer, **When** the bank reader's document gate is asked, **Then** it does **not** claim the document.
4. **Given** the same ICICI credit-card statement, **When** the existing ICICI credit-card reader's gate is asked, **Then** that reader still claims it — the two readers remain correctly separated by document type.

---

### User Story 8 - Proven byte-for-byte against a golden fixture (Priority: P8)

As a maintainer, the engine's ICICI bank-account behaviour is pinned to the proven web engine by porting the web engine's synthetic ICICI savings characterization vector into the repository's `fixtures/` directory as a golden vector and asserting the on-device engine reproduces it exactly — including every row's date, amount, direction, description, running balance, and delta, the statement's printed opening/closing balances, the billing period, the account last-4, and the RECONCILED balance-chain result.

**Why this priority**: Parity is the constitution's acceptance mechanism for the port (Principle V). It turns "we think it matches" into an enforced, regression-proof guarantee, and it extends the fixture harness that every credit-card reader already uses to the balance-ledger family.

**Independent Test**: Run the parity harness over the ported synthetic ICICI savings vector and confirm the engine's output matches the expected output exactly, and that re-running produces identical results.

**Acceptance Scenarios**:

1. **Given** the ported synthetic ICICI savings golden vector, **When** the parity harness runs, **Then** the engine's parsed output matches the expected output exactly — the three rows (2025-06-16 / 5000.00 / debit, 2025-06-18 / 50000.00 / credit, 2025-06-20 / 2000.00 / debit) with their descriptions, balances (95000.00, 145000.00, 143000.00) and deltas (−5000.00, +50000.00, −2000.00); printed opening 100000.00 and closing 143000.00; period 2025-06-16 to 2025-07-15; account last-4 `3456`; and a **RECONCILED** balance chain with zero suspects and no row-1 fallback.
2. **Given** a change that alters ICICI bank-account parsing behaviour, **When** the parity harness runs, **Then** it fails, enforcing the parity guarantee.
3. **Given** the golden fixture, **When** it is inspected, **Then** all input and expected data is synthetic or fully redacted (fabricated payers, amounts, and account number) — never real account data.

---

### User Story 9 - Privacy gate and the Swift bridge: zero network, no new dependency, reachable from Swift (Priority: P9)

As a maintainer, the existing automated privacy-egress test covers the ICICI bank-account import/parse path and asserts it performs no network I/O, and the new reader is reachable over the existing UniFFI bridge to Swift — all with **no new networking dependency** (the slice inherits the privacy-egress gate). Money remains an exact decimal (never a float); geometry x-coordinates are layout points (not money) and may be floating-point.

**Why this priority**: Privacy is the product's non-negotiable promise and a required constitution gate; being reachable from Swift is what makes the parser usable by the app. Proving both for the new reader — with zero new dependencies — extends the guarantee to the whole balance-ledger family without weakening it.

**Independent Test**: Run the privacy-egress test against the ICICI bank-account parse path and confirm it passes only when zero outbound network connections occur; confirm the reader is callable over the UniFFI bridge from Swift; and confirm no new runtime (and specifically no networking) dependency was added.

**Acceptance Scenarios**:

1. **Given** the ICICI bank-account parse path, **When** the automated privacy-egress test runs, **Then** it confirms zero outbound network connections occur during parsing.
2. **Given** a regression that introduces any network access into the parse path, **When** the privacy-egress test runs, **Then** it fails, blocking the change.
3. **Given** the shared engine, **When** the ICICI bank-account reader is exposed, **Then** it is reachable over the existing UniFFI bridge to Swift (a bank-account parse entry point that also accepts the first-row word geometry, plus a bank-account issuer-claims function), mirroring the credit-card surfaces.
4. **Given** the change set, **When** dependencies are reviewed, **Then** no new runtime dependency — and no networking dependency — is added; money stays an exact decimal (never a float), while geometry x-coordinates are layout points that may be floating-point.

---

### Edge Cases

- **Wrong document type, same issuer**: An ICICI **credit-card** statement is presented to the ICICI **bank** reader → the bank reader must **not** claim it (required + optional marker gate), so a card statement is never misread as a ledger.
- **Wrong issuer**: A statement from a different issuer is presented to the ICICI bank reader → not claimed.
- **Direction independent of amount**: A row's balance falls → **debit**; a row's balance rises → **credit**; flipping the delta's sign flips the direction even when the printed amount is unchanged — the amount never sets direction.
- **Amount ≠ |delta| (chain break)**: A row whose printed amount differs from the absolute balance delta by more than ₹1.00 → marked a **suspect**; the balance chain reports **NEEDS_REVIEW**; the row is **still returned**, never dropped.
- **Rounding tolerance**: A row whose printed amount differs from the absolute balance delta by **≤ ₹1.00** → treated as reconciling (amount matches delta); not a suspect.
- **Row-1 with a printed opening balance**: Row 1's delta is computed against the printed "Opening Balance" / "B/F" → geometry-free; `direction_source = opening_balance`.
- **Row-1 without an opening balance, with geometry**: Row 1's direction comes from the amount word's x-position versus the per-issuer column split (withdrawal column ⇒ debit); `direction_source = row1_xposition`; surfaced as **NEEDS_REVIEW** in this slice (x-position path supported but not calibrated).
- **Row-1 with neither**: A **provisional** direction is set; `direction_source = row1_provisional`; the balance chain reports **NEEDS_REVIEW**.
- **Anchor shape vs non-transaction lines**: A transaction line ends in money tokens `… <amount> <balance>`; **per-page headers** and **cheque-number lines** (no decimal money tokens) must **not** match as anchor rows (no transaction, no error).
- **Narration stitching**: A row's description is reassembled from the wrapped detail line immediately **above** the anchor (payer/VPA) plus detail lines **below** it up to the next transaction, **skipping** other anchors and printed-balance lines.
- **Unparseable anchor-shaped row**: A line matching an anchor's shape but whose date/amount/balance will not parse → captured as an **errored line** (bounded length); every good row is still returned; no error is raised; it is **not** a suspect.
- **Two-column template**: The base must support a **Withdrawal / Deposit / Balance** two-column anchor for later banks, even though ICICI is single-amount.
- **Indian money formatting**: Amounts/balances with thousands separators, including the Indian grouping style (e.g., `1,23,456.78`) → parsed to exact, non-negative decimals with stated precision preserved.
- **Missing metadata**: No recognizable opening/closing balance, billing period, or account number → the corresponding field is left unset rather than fabricated; transactions are still returned.
- **No transaction lines**: Empty input, or input with no recognizable anchor rows → an empty transaction list is returned with no error.
- **Repeated / concurrent parses**: The same input parsed repeatedly → identical results every time, with no dependence on wall-clock time, locale, or hidden global state.

## Requirements *(mandatory)*

### Functional Requirements

**Document recognition (the savings-vs-credit-card gate)**

- **FR-001**: The engine MUST recognize a statement as an ICICI **bank-account** (savings/current) statement via a document gate that requires the ICICI **bank code**, **all** of a set of **required** markers, and **any** of an **optional** set — specific enough to distinguish an ICICI savings statement from an ICICI credit-card statement (which share the issuer).
- **FR-002**: The bank reader MUST NOT claim an ICICI **credit-card** statement, and MUST NOT claim a statement from a different issuer — a document is only parsed by the reader that recognizes its issuer **and** its account kind.

**The reusable balance-ledger reader base**

- **FR-003**: This slice MUST introduce a reusable **balance-ledger reader base** (the shared engine for the bank-account reader family) that later bank-account readers (HDFC, Federal, AU) can reuse, with ICICI as the first per-issuer configuration on it.
- **FR-004**: The base MUST recognize a transaction as an **anchor row** via a per-issuer anchor pattern with named groups for **serial**, **date**, **amount**, and **balance**, plus an optional **description** group. For ICICI (single-amount template), a transaction line ends in two money tokens `… <amount> <balance>`.
- **FR-005**: The base MUST also support a **two-column** Withdrawal / Deposit / Balance anchor template (required by later HDFC/Federal/AU readers), even though ICICI itself uses the single-amount `<amount> <balance>` template.
- **FR-006**: The base MUST NOT match **per-page header** lines or **cheque-number** lines (lines with no decimal money tokens) as anchor rows; such lines produce neither a transaction nor an error.
- **FR-007**: The base MUST reassemble each row's **description (narration)** from the wrapped detail line immediately **above** the anchor (e.g., payer/VPA) plus the detail lines **below** the anchor up to the next transaction, **skipping** any other anchor rows and any printed-balance lines.

**Direction from the running-balance delta; amount as an independent check**

- **FR-008**: The engine MUST derive each transaction's debit/credit **direction** from the **running-balance delta**: a **fall** in the balance (delta < 0) is a **debit**, a **rise** (delta > 0) is a **credit**. The direction MUST NEVER be inferred from the sign or magnitude of the printed amount.
- **FR-009**: The engine MUST treat the printed **amount as an INDEPENDENT integrity check**: a row **reconciles** when the printed amount equals the absolute value of the balance delta (`amount == |curr_balance − prev_balance|`) within a **₹1.00** rounding tolerance; otherwise the row is a **suspect**.
- **FR-010**: A **suspect** row (printed amount does not match its balance delta) MUST still be **returned** (persisted in the output, flagged), never silently dropped.
- **FR-011**: The engine MUST record per row whether the amount matches the delta (`amount_matches_delta`) and whether the row is a suspect (`is_suspect`).

**Amount**

- **FR-012**: The engine MUST parse each amount and each running balance as an exact **decimal**, honouring Indian number formatting (thousands separators, including the Indian grouping style) and preserving stated precision. Monetary values MUST NEVER be represented as floating-point numbers.

**Row-1 bootstrap and `direction_source`**

- **FR-013**: For the **first** ledger row (no predecessor balance), the engine MUST resolve direction by this precedence: (a) a printed **"Opening Balance" / "B/F"** line when present (preferred, geometry-free) — the row's delta is computed against that printed opening balance; else (b) the amount word's **x-position** versus a per-issuer **column split** (withdrawal column ⇒ debit), using the **first-row word geometry** supplied by the native platform; else (c) a **provisional** direction.
- **FR-014**: The engine MUST record a per-row **`direction_source`** with one of exactly these values: `opening_balance`, `balance_delta`, `row1_xposition`, or `row1_provisional`. Every row after the first is `balance_delta`.
- **FR-015**: When row 1 resolves via a **provisional** direction (`row1_provisional`), the engine MUST flag the run so the balance chain reports **NEEDS_REVIEW**. In this slice, a row resolved via first-row geometry (`row1_xposition`) MUST also be surfaced as **NEEDS_REVIEW** (the x-position path is supported but not yet calibrated against a real statement) — an uncalibrated first-row decision is never silently trusted.
- **FR-016**: The engine MUST accept the first-row word geometry **as already-extracted input** (each word with its x-position); **the Rust core MUST NEVER open a PDF**. Geometry x-coordinates are **layout points** (not money) and MAY be floating-point.

**Balance-chain integrity**

- **FR-017**: The engine MUST provide a **balance-chain integrity check** that walks the ledger rows and reports a statement-level status of **RECONCILED** or **NEEDS_REVIEW**, together with the list of **suspect** rows.
- **FR-018**: The balance chain MUST report **RECONCILED** only when **every** row reconciles (amount matches delta within tolerance) **and** there is no un-trusted row-1 bootstrap (no `row1_provisional`, and — in this slice — no `row1_xposition`); otherwise it MUST report **NEEDS_REVIEW** and name the suspect rows.

**Errored vs suspect**

- **FR-019**: Only a genuinely **unparseable** anchor-shaped row (bad date, amount, or balance) MUST be captured as an **errored line** (raw text preserved, bounded to a safe maximum length). A **chain break** (amount ≠ delta) MUST be a **suspect**, not an errored line. The engine MUST NOT raise an error or drop a row, and MUST still return every successfully parsed row.

**Per-row and statement-level ledger metadata**

- **FR-020**: Each parsed row MUST carry: the transaction **date**, the exact **amount**, the delta-derived **direction**, the currency (INR), the stitched **description**, the running **balance**, the **balance delta**, `amount_matches_delta`, `is_suspect`, `direction_source`, and the **serial**.
- **FR-021**: The statement MUST carry: the **printed opening balance**, the **printed closing balance**, the **billing period** (start and end), and the account **last-4**.
- **FR-022**: The account **last-4** MUST be derived from the trailing four digits of the printed **account number** by a **bank-account-aware** extractor — **not** the credit-card masked-PAN matcher.
- **FR-023**: When a metadata field cannot be found, the engine MUST leave it unset rather than fabricate a value, and MUST still return the parsed transactions.

**Engine purity, platform boundary & reuse**

- **FR-024**: The engine's bank-account parse MUST accept already-extracted text lines, the full statement text, and the first-row word geometry, and return the parsed result; it MUST NOT read files, extract PDF text, or embed a PDF engine (text and geometry extraction are native platform concerns).
- **FR-025**: The engine MUST remain pure and deterministic: identical input MUST yield identical output, with no dependence on network, wall-clock time, locale, or hidden global mutable state.
- **FR-026**: The bank-account reader MUST reuse the existing shared money/date/currency/direction conventions and helpers where applicable (Indian-format decimal parsing, the shared date parser, the explicit `Direction` type), adding only what the balance-ledger family genuinely needs (the ledger base, the balance-chain check, the account-number last-4 extractor, and the ICICI configuration).
- **FR-027**: The engine MUST expose the ICICI bank-account reader over the existing **UniFFI** bridge with a bank-account parse entry point (accepting the first-row word geometry) and a bank-account issuer-claims function, mirroring the credit-card surfaces, reachable from Swift.

**Privacy (constitution Principle I — NON-NEGOTIABLE)**

- **FR-028**: The entire bank-account import/parse path MUST run 100% on-device with ZERO network I/O.
- **FR-029**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting into the engine or the app, and MUST NOT add any **networking** dependency (it inherits the privacy-egress gate).
- **FR-030**: The existing automated privacy-egress test MUST cover the bank-account parse path and assert it performs no network access; it remains a required constitution gate.

**Parity & test-first (constitution Principle V)**

- **FR-031**: The web engine's synthetic ICICI savings characterization vector MUST be ported into the repository's `fixtures/` directory as a golden vector, and the engine MUST reproduce it exactly (rows with dates/amounts/directions/descriptions/balances/deltas, printed opening/closing balances, billing period, account last-4, and the RECONCILED balance-chain result).
- **FR-032**: All fixture and test data MUST be synthetic or fully redacted (fabricated payers, amounts, and account number) — never real account data.
- **FR-033**: The bank-account parsing behaviour introduced by this slice MUST be developed test-first (a failing golden test precedes the behaviour).

**Licensing, secrets & quality gates**

- **FR-034**: The change MUST NOT add secrets, API keys, or private endpoints; MUST remain distributable under Apache-2.0 with no copyleft (GPL/AGPL/LGPL) dependencies; and MUST introduce **no new runtime dependency** for this slice.
- **FR-035**: The change MUST keep the iOS Local Verification Gate and CI green: core formatting, linting, and tests; app linting; project generation; a simulator build with passing app tests; and the privacy gate. If any user-facing surface is introduced, it MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility.

### Key Entities *(include if feature involves data)*

- **Extracted statement input**: The already-extracted text lines, the full statement text, and the **first transaction row's word geometry** (each word with its x-position as layout points) handed to the engine by the native platform. Contains no PDF binary; the engine never opens a PDF.
- **Parsed ledger row**: One ledger transaction — a transaction date, an exact non-negative amount, a **delta-derived** direction, a currency (INR), a stitched description, the running **balance**, the **balance delta**, an **amount-matches-delta** indicator, an **is-suspect** indicator, a **direction source**, and a **serial**.
- **Parsed bank statement result**: The full output of reading one bank-account statement — the issuer/bank identity and account kind, the list of parsed ledger rows, the list of **errored** (unparseable) lines, the **printed opening balance**, the **printed closing balance**, the **billing period** (start/end), the account **last-4**, and the **balance-chain result**.
- **Direction (polarity)**: An explicit debit or credit indicator carried on every transaction, sourced from the **running-balance delta** (and, for row 1 only, from the opening balance, first-row geometry, or a flagged provisional) — never from the amount's sign.
- **Balance-chain result**: A statement-level status of **RECONCILED** or **NEEDS_REVIEW**, with the list of **suspect** rows (chain breaks) — distinct from errored lines.
- **`direction_source`**: How a row's direction was decided — one of `opening_balance`, `balance_delta`, `row1_xposition`, or `row1_provisional`.
- **Golden characterization vector**: A synthetic ICICI savings input (text lines + full text + first-row geometry) paired with its expected engine output, stored under `fixtures/`, ported from the web engine and reproduced exactly by the on-device engine.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The synthetic ICICI savings reference statement parses byte-for-byte to the ground truth on-device — the three rows (2025-06-16 / 5000.00 / debit / `UPI/512345/ALICE STORE/Payment`, 2025-06-18 / 50000.00 / credit / `NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY`, 2025-06-20 / 2000.00 / debit / `ATM CASH WITHDRAWAL`) with balances 95000.00, 145000.00, 143000.00 and deltas −5000.00, +50000.00, −2000.00, serials 1/2/3 (100% match).
- **SC-002**: The balance-chain check reports **RECONCILED** for the reference statement — **zero** suspects and no row-1 fallback (row 1 anchored by the printed opening balance).
- **SC-003**: Direction is **delta-derived** across every tested case — the balance falls ⇒ debit, rises ⇒ credit — and a row's direction **flips when its balance delta flips**, independent of the printed amount.
- **SC-004**: A row whose printed amount matches the absolute balance delta within **₹1.00** is treated as reconciling; a row whose amount does **not** match is flagged a **suspect** yet is **still returned** (never dropped), and the balance chain reports **NEEDS_REVIEW** naming it.
- **SC-005**: Only genuinely unparseable anchor-shaped rows (bad date/amount/balance) go to **errored lines**; a chain break is a **suspect**, not an error — the two are never conflated.
- **SC-006**: Row-1 bootstrap resolves in the correct precedence and records `direction_source` accordingly — `opening_balance` for the reference; `row1_xposition` when only geometry is available (surfaced NEEDS_REVIEW in this slice); `row1_provisional` when neither is available (NEEDS_REVIEW) — and every later row is `balance_delta`.
- **SC-007**: The bank reader **claims** the ICICI savings reference statement and **rejects** an ICICI **credit-card** statement — 0 misroutes across the recognition cases; the existing ICICI credit-card reader still claims the credit-card statement.
- **SC-008**: The statement records `printed_opening_balance = 100000.00`, `printed_closing_balance = 143000.00`, billing period 2025-06-16 → 2025-07-15, and account **last-4 `3456`** (from the printed account number's trailing four digits via the bank-account-aware extractor).
- **SC-009**: 100% of parsed amounts and balances are exact **decimals** with stated precision preserved; **no monetary value is ever a floating-point number**, while geometry x-coordinates are layout points that may be floating-point.
- **SC-010**: Zero outbound network connections occur during the entire bank-account parse path, verified by the automated privacy-egress test, and **no new runtime (or networking) dependency** is added.
- **SC-011**: The whole reader is reachable over the **UniFFI bridge to Swift** (a bank-account parse entry point that accepts the first-row word geometry, plus a bank-account issuer-claims function).
- **SC-012**: Given identical input, the engine returns identical output across repeated runs (100% reproducible).
- **SC-013**: The ported synthetic ICICI savings golden vector reproduces exactly and the parity harness passes; re-running is stable.
- **SC-014**: All automated checks required to merge pass (green), including the parity harness and the privacy-egress test, with the iOS Local Verification Gate and CI green; and no secrets or copyleft-licensed dependencies are added (verified by review of manifests and dependencies).

## Assumptions

- **New reusable base introduced now**: The balance-ledger reader base (anchor recognition + narration stitching + delta-derived direction + the amount-vs-delta integrity check) and the balance-chain integrity check are introduced in this slice because ICICI savings/current needs them and the later bank-account readers (HDFC, Federal, AU) will reuse them. The exact module layout, anchor patterns, and column-split mechanics are finalized in `/speckit.plan`.
- **Single-amount for ICICI; two-column supported for later banks**: ICICI's anchor is the single-amount template `… <amount> <balance>`; the base additionally supports a two-column Withdrawal/Deposit/Balance template that later banks require. Only the single-amount path is exercised by the reference fixture.
- **Parse seam & platform boundary**: The bank-account seam mirrors the web engine's `read_lines(lines, full_text, first_row_words)` — already-extracted text lines, the full text, and the first transaction row's word geometry — and returns the parsed result. The native platform (iOS PDFKit) performs the text **and** geometry extraction; the Rust core never opens a PDF. The exact seam signature and native wiring are finalized in `/speckit.plan`.
- **Rounding tolerance**: The amount-vs-delta integrity check uses a **₹1.00** rounding tolerance; a row within tolerance reconciles, beyond it is a suspect.
- **Row-1 geometry is supported but not calibrated here**: The x-position column-split path (`row1_xposition`) is implemented and reachable, but is **not** calibrated against a real statement in this slice; such rows (and any `row1_provisional`) are surfaced **NEEDS_REVIEW**, never silently trusted. The reference fixture is geometry-free (opening-balance-anchored), so it reconciles without exercising the geometry path.
- **Reader identity**: The reader is the ICICI **bank-account** reader, sharing the ICICI issuer with the existing ICICI credit-card reader and distinguished by **account kind** (savings/current) — i.e., the registry key `(bank_code, account_kind)` with account kind `bank_account`. The exact identity string values are finalized in `/speckit.plan`.
- **Account last-4 extractor**: The account last-4 is the trailing four digits of the printed account number, recovered by a **bank-account-aware** extractor — distinct from the credit-card masked-PAN matcher used by the card readers.
- **Binding**: The reader is exposed to Swift via the existing UniFFI bridge with a bank-account parse entry point (accepting first-row geometry) and a bank-account claims function, mirroring the credit-card surfaces; concrete binding mechanics belong in `/speckit.plan`.
- **Fixtures location**: The golden fixture lives under `fixtures/icici/` (bank-account subtree, e.g. `fixtures/icici/bank_account/`) and is the source of truth for parity; the exact path is finalized in `/speckit.plan`.
- **No new dependencies**: This slice should require **no** new runtime dependencies, and specifically **no** networking dependency.
- **Source of truth**: The web engine is the source of truth for behaviour — the shared balance-ledger reader (`_ledger_reader.py`, `BalanceLedgerStatementReader`), the balance-chain check (`balance_chain.py` / `balance_chain.check`), the ICICI bank reader (`icici_bank.py`), plus the shared `base.py` / `_common.py` / `polarity.py` and the bank-account characterization/parity test. The porting approach (module layout, patterns, fixture format, UniFFI exports) is decided in `/speckit.plan`, not here.
- **Synthetic characterization vector**: The three synthetic rows and their expected outputs, the printed opening/closing balances (100000.00 / 143000.00), the billing period (2025-06-16 → 2025-07-15), the account last-4 (`3456`), and the RECONCILED balance-chain result are the constitution's golden-fixture parity vector (Principle V) — behavioural acceptance data confirmed against the web engine, all synthetic/redacted.
- **No new UI required**: This is an engine slice; no user-facing UI is required to deliver it. App-side PDF text/geometry extraction (PDFKit wiring), the file-import UI, and the Share Extension remain a native concern and a later step. If a trivial demo surface is added, it follows HIG and accessibility (FR-035).
- **Data safety**: All fixture and test data is synthetic or fully redacted — no real account data.
- **Money & geometry types**: Amounts and balances are exact decimals (never floating-point) and direction is carried explicitly and derived from the balance delta; geometry x-coordinates are layout points (not money) and may be floating-point.

### Dependencies

- **Kaname Constitution v1.0.0** — privacy (zero-network free/core), determinism, a pure platform-agnostic core (no PDF engine), decimal money with explicit polarity, Apache-2.0 open-core with no copyleft, native HIG/accessibility, and the test-first iOS Local Verification Gate (including the privacy-egress gate).
- **Milestone P2 — the five credit-card slices (already landed)** — the shared reader output types (parsed statement / parsed transaction), the Indian-format amount parser, the shared multi-format date parser (which already carries the ICICI-savings date formats), the shared `Direction` type and polarity module, the golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate — all reused by this slice.
- **Milestone P1 bridge (already landed)** — the shared engine crate and the UniFFI Swift binding proven end-to-end, over which the bank-account parse and claims functions are exposed.
- **Web engine golden vector** — the synthetic ICICI savings characterization vector and the balance-ledger reader / balance-chain / `icici_bank` behaviour used as the parity source of truth.

## Out of Scope

Deferred to later P2 slices / milestones:

- **The other bank-account ledger readers** — **HDFC**, **Federal**, and **AU** bank-account readers follow in later slices on this same base; they are not part of this slice.
- **IOB** — a **credit-card** reader (not a ledger reader), out of scope here.
- **Reconciliation of printed debit/credit totals** (the printed-total integrity check), **coverage / billing-period timeline**, and **cross-source de-duplication and transfer detection** — separate later concerns; this slice delivers the balance-**chain** integrity check, not printed-total reconciliation.
- **Real-PDF geometry calibration** — the row-1 x-position path is supported but **not** calibrated against a real statement in this slice; provisional/x-position rows are surfaced **NEEDS_REVIEW**, never silently trusted.
- **Persistence** — encrypted SQLite / SQLCipher storage and key management.
- **AI-fallback parsing**.
- Any **premium / cloud features**.
- **App-side PDF text/geometry extraction** (PDFKit wiring in the app) and the **file-import UI / Share Extension** — native concerns handled in a later slice. This slice focuses on the balance-ledger engine (base + balance chain + ICICI reference reader) plus its golden-fixture parity, reusing the existing privacy gate and exposed over the existing bridge.
