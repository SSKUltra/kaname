# Feature Specification: Read an HDFC Bank (Savings/Current) Statement On-Device — the Second Balance-Ledger Reference Reader (HDFC Config on the Existing Ledger Base, Two Export Layouts)

**Feature Branch**: `008-hdfc-bank-ledger-reader`  
**Created**: 2026-07-16  
**Status**: Draft  
**Milestone**: P2 — the **second** bank-account (balance-ledger) reader, after the ICICI reference reader that landed the reusable base  
**Input**: User description: "HDFC Bank savings/current statement reading for the on-device Kaname core — the SECOND bank-account (balance-ledger) reader, after the ICICI reference reader that landed the reusable base. HDFC bank statements are running-balance ledgers with no Dr/Cr marker (direction from the balance delta), and HDFC issues them in TWO export layouts, both handled by one reader via first-match-wins anchor patterns: (1) a COMPACT layout — DD/MM/YY dates, one row per line ending `<ref> <value-date> <amount> <balance>`, a single printed amount and an alphanumeric reference (captured as the serial), with the opening balance taken from the end-of-statement summary row; and (2) a DETAILED layout — DD/MM/YYYY dates with explicit Withdrawals and Deposits columns (the empty side prints 0.00) then the closing balance, with an inline `Opening Balance :`. This slice adds the HDFC configuration of the existing balance-ledger base plus its golden fixtures; it reuses the base, the balance-chain check, the parity harness and the privacy gate unchanged."

> **Note on priority labels**: This feature is milestone **P2** in the product roadmap (`docs/kaname-ios-plan.md` §9). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P2" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

The previous bank-account slice landed the **balance-ledger reader family** and its first reference reader: a **reusable balance-ledger base** (anchor recognition, delta-derived direction, the printed-amount-as-independent-check, narration stitching, the row-1 bootstrap, and the errored-vs-suspect distinction), the **balance-chain integrity check**, the **golden-fixture parity harness** extended to ledgers, and **ICICI savings/current** as the first configuration on that base. This slice delivers the **second** bank on that same base — **HDFC** — and proves the base generalizes: a person imports their HDFC **savings / current** account statement and the app produces the ledger's transactions (date, exact amount, delta-derived debit/credit direction, running balance, and stitched description) entirely on-device, with no network and no account, exactly as it already does for ICICI.

This is a **config-on-an-existing-base** slice, not new infrastructure. The reusable balance-ledger base and the balance-chain check **already exist and are reused unchanged**; HDFC is added as a **per-issuer configuration** (its own document gate, its two anchor patterns, its opening-balance and period patterns, and its account-number extractor) plus **golden fixtures**. The **only** genuinely new *shared* code this slice introduces is a **tiny bank-account-tail helper** factored into the shared common module (try a per-bank primary account regex, else the longest standalone ≥9-digit run) — because HDFC's account-number pattern differs from ICICI's while the fallback is identical across banks; it will also serve the later Federal/AU readers.

HDFC is also the **first bank-account reader that must read two different export layouts** behind a single reader — a **compact** running-balance layout and a **detailed** two-column (Withdrawals / Deposits) layout — selected by **first-match-wins anchor patterns**, so the caller never knows or chooses which layout applied. This capability is already supported by the base (it recognizes a transaction against an **ordered list** of per-issuer anchor patterns); HDFC is the first configuration to exercise more than one.

This is a **determinism / parity** slice (Constitution Principle V): the behaviours are ported faithfully from the proven web engine (`hdfc_bank.py`) and the on-device engine must reproduce the two reference ground truths **byte-for-byte** — including the known web-engine narration-stitching quirks (a header/summary line adjacent to a transaction is stitched into that row's narration). The platform boundary is unchanged and fixed by the constitution: **text extraction is native** — on iOS the platform extracts the statement's text lines, its full text, and (for a bank statement) the first transaction row's word geometry, and hands them to the shared engine. **The Rust core never opens a PDF.**

### User Story 1 - Turn an HDFC savings/current statement into transactions, on-device (Priority: P1)

A person imports their HDFC **savings / current** account statement. The platform extracts the statement's text natively and hands it to the shared engine; the engine recognizes the document as an HDFC **bank-account** statement and returns the ledger's transactions — each with its date, exact amount, delta-derived debit/credit direction, running balance, and stitched description — computed entirely on the device with no network access. Direction is derived from the running-balance movement, not from any Dr/Cr column (there is none).

**Why this priority**: This is the headline value and the smallest slice that turns a real HDFC bank statement into usable data. It is a viable increment on its own: a person gets their HDFC savings/current transactions from their statement, on-device, exactly as they already can for ICICI — extending the balance-ledger family to a second bank. Every subsequent story refines this parse.

**Independent Test**: Provide the engine with the extracted text of the synthetic HDFC **compact** reference statement and, separately, the synthetic HDFC **detailed** reference statement, and confirm it recognizes each as an HDFC bank-account statement and returns one transaction per ledger row — each carrying a date, an exact amount, a delta-derived direction, a running balance, and a stitched description — with no network access during the parse.

**Acceptance Scenarios**:

1. **Given** the extracted text of the synthetic HDFC **compact** reference statement, **When** the engine parses it, **Then** it recognizes the document as an HDFC bank-account statement and returns exactly **two** transactions.
2. **Given** the extracted text of the synthetic HDFC **detailed** reference statement, **When** the engine parses it, **Then** it recognizes the document as an HDFC bank-account statement and returns exactly **two** transactions.
3. **Given** the **compact** reference ledger, **When** the engine parses it, **Then** row 1 is dated 2026-04-01, amount 5000.00, direction **debit**, running balance 95000.00; and row 2 is dated 2026-04-16, amount 50000.00, direction **credit**, running balance 145000.00 — all in Indian Rupees.
4. **Given** the **detailed** reference ledger, **When** the engine parses it, **Then** row 1 is dated 2026-04-01, amount 5000.00, direction **debit**, running balance 95000.00; and row 2 is dated 2026-04-20, amount 50000.00, direction **credit**, running balance 145000.00 — all in Indian Rupees.
5. **Given** the device has no network connectivity, **When** either statement is parsed, **Then** the transactions are still produced, proving the parse is fully local.

---

### User Story 2 - One reader, two layouts: compact and detailed, auto-selected by first-match-wins anchors (Priority: P2)

HDFC issues its bank-account statements in two different export layouts, and a single HDFC reader parses whichever one the statement uses. The **compact** layout has `DD/MM/YY` dates and a single printed amount, one transaction per line ending `… <ref> <value-date> <amount> <balance>` with an alphanumeric reference. The **detailed** layout has `DD/MM/YYYY` dates and explicit **Withdrawals** and **Deposits** columns (the empty side prints `0.00`) followed by the closing balance. The reader recognizes a transaction against an **ordered list of anchor patterns** (first match wins); a **compact** row never matches the **detailed** pattern and vice-versa, because the compact date is a **2-digit** year and the detailed date is a **4-digit** year.

**Why this priority**: Reading both HDFC export layouts behind one reader is the distinctive capability of the slice, and it is delivered purely as configuration — the base already tries a per-issuer **ordered** anchor list. Proving a single HDFC reader auto-selects the correct layout (without the caller choosing) establishes that later multi-layout banks are also just configuration on the same base.

**Independent Test**: Parse the compact reference statement and the detailed reference statement through the *same* HDFC reader and confirm each yields the correct transactions without the caller selecting a layout; confirm each transaction row is read by exactly one layout's anchor pattern (the other never matches it).

**Acceptance Scenarios**:

1. **Given** a synthetic HDFC statement in the **compact** layout, **When** the single HDFC reader parses it, **Then** it returns the compact transactions correctly, without the caller specifying a layout.
2. **Given** a synthetic HDFC statement in the **detailed** layout, **When** the same HDFC reader parses it, **Then** it returns the detailed transactions correctly, without the caller specifying a layout.
3. **Given** a **compact** transaction line (`DD/MM/YY` date, single amount), **When** the reader scans it, **Then** it matches the **compact** anchor and **not** the detailed anchor (the 2-digit year cannot satisfy the detailed pattern's 4-digit year).
4. **Given** a **detailed** transaction line (`DD/MM/YYYY` date, two Withdrawals/Deposits columns), **When** the reader scans it, **Then** it matches the **detailed** anchor and **not** the compact anchor.
5. **Given** the reader's ordered anchor patterns, **When** a transaction line is read, **Then** the **first** pattern that matches wins and produces exactly one transaction.

---

### User Story 3 - Direction from the running-balance delta in both layouts; the printed amount is an independent integrity check (Priority: P3)

Each transaction's direction (money in vs money out) is decided **solely** by how the running balance moved — a **fall** in the balance is a **debit**, a **rise** is a **credit** — in **both** layouts. The printed amount is used only as an **independent integrity check** (it should equal the absolute value of the balance delta within the rounding tolerance). In the **compact** layout the printed amount is the single amount token; in the **detailed** layout the printed amount is the **non-zero** of the Withdrawals/Deposits pair (the empty side prints `0.00`). Direction is never inferred from which column an amount sits in, nor from the amount's sign or magnitude.

**Why this priority**: Deriving polarity from the balance movement (never from the amount, and never from which column the figure is printed in) is the defining rule of the balance-ledger family and the non-negotiable engine invariant for bank statements. Getting it right for both HDFC layouts — including resolving the detailed layout's two columns down to the one non-zero printed amount for the integrity check — is what keeps every downstream total trustworthy.

**Independent Test**: Parse compact rows and detailed rows whose balance rises and falls, and confirm each is classified credit and debit respectively from the delta; confirm the detailed layout's printed amount is taken from the non-zero Withdrawals/Deposits column and reconciles against the delta; confirm flipping the balance movement flips the direction regardless of the printed amount.

**Acceptance Scenarios**:

1. **Given** a row whose running balance falls from the previous balance (e.g., 100000.00 → 95000.00), **When** it is parsed, **Then** its direction is **debit**, in either layout.
2. **Given** a row whose running balance rises from the previous balance (e.g., 95000.00 → 145000.00), **When** it is parsed, **Then** its direction is **credit**, in either layout.
3. **Given** a **detailed** row that prints `5,000.00` in Withdrawals and `0.00` in Deposits, **When** it is parsed, **Then** the printed amount used for the integrity check is 5000.00 (the non-zero column), and the row reconciles against its balance delta.
4. **Given** a **detailed** row that prints `0.00` in Withdrawals and `50,000.00` in Deposits, **When** it is parsed, **Then** the printed amount used for the integrity check is 50000.00 (the non-zero column), and the row reconciles against its balance delta.
5. **Given** any row, **When** the sign of its balance delta is flipped (by changing the surrounding balances) while its printed amount is unchanged, **Then** its direction flips between debit and credit — the direction follows the delta, never the amount or the column.

---

### User Story 4 - Opening balance per layout, and an opening-anchored row 1 (Priority: P4)

The first ledger row has no predecessor balance, so its direction is resolved against the statement's printed **opening balance**. HDFC prints the opening balance differently in each layout, so the reader supplies a per-layout opening pattern: the **detailed** layout prints an inline `Opening Balance : <amount>`; the **compact** layout has **no** inline opening line, so its opening balance is taken from the **end-of-statement summary row** — the **first figure** on the line beneath the `OpeningBalance …` summary header (via a multi-line pattern). Critically, the printed opening balance is **not** row 1's running balance — in the compact fixture it is the summary's first figure (100000.00), while row 1's balance is 95000.00. Row 1's direction is therefore **opening-anchored** in both fixtures.

**Why this priority**: Row 1 is the one place the delta rule cannot self-start, so a correct opening balance is what anchors the whole chain. HDFC prints its opening balance in two different places, and the compact layout's opening is a summary figure that must not be confused with row 1's balance; getting this right is what makes both fixtures reconcile with an auditable `opening_balance` direction source.

**Independent Test**: Parse the detailed statement and confirm the opening balance is read from its inline `Opening Balance :` line; parse the compact statement and confirm the opening balance is read from the end-of-statement summary row (its first figure), not from row 1's balance; confirm row 1's direction in each fixture is set from that printed opening balance with `direction_source = opening_balance`.

**Acceptance Scenarios**:

1. **Given** the **detailed** statement, **When** it is parsed, **Then** the printed opening balance is 100000.00, read from the inline `Opening Balance : 1,00,000.00` line.
2. **Given** the **compact** statement, **When** it is parsed, **Then** the printed opening balance is 100000.00, read from the summary row beneath the `OpeningBalance …` header (its first figure `1,00,000.00`) — **not** from row 1's running balance (95000.00).
3. **Given** either statement, **When** row 1 (running balance 95000.00) is bootstrapped, **Then** its delta is computed against the printed opening balance (95000.00 − 100000.00 = −5000.00), so its direction is **debit**, with `direction_source = opening_balance` and no geometry consulted.
4. **Given** either statement, **When** any row after the first is bootstrapped, **Then** its direction is derived from its balance delta with `direction_source = balance_delta`.
5. **Given** the printed opening balance is present, **When** the balance chain runs, **Then** there is no row-1 direction fallback (neither provisional nor x-position).

---

### User Story 5 - Faithful narration stitching, including the header/summary lines the web engine stitches in (Priority: P5)

Each row's human-readable **narration** is reassembled deterministically by the reused base — the anchor's inline description plus the wrapped detail lines around it (the line above and the lines below up to the next transaction, skipping other anchors and printed-balance lines). Because this is a **parity** port, the engine must reproduce the **known web-engine behaviour** where a header or summary line adjacent to a transaction is stitched into that row's narration: in both layouts, **row 0's narration includes the column-header line**; and in the **compact** layout, **row 1's narration includes the trailing end-of-statement summary rows**. These stitched strings must be reproduced **byte-for-byte** — the port must **not** "clean them up".

**Why this priority**: This is a determinism/parity slice, and the narration strings are part of the golden ground truth. The web engine's stitching folds adjacent header/summary lines into a neighbouring row's narration; faithfully reproducing that (rather than "fixing" it) is exactly what parity requires, and it is the behaviour the golden fixtures pin.

**Independent Test**: Parse both reference statements and confirm each row's stitched description matches the ground-truth string exactly, including row 0's column-header text and the compact row 1's trailing summary text — with no normalization, trimming, or reordering applied.

**Acceptance Scenarios**:

1. **Given** the **compact** statement, **When** row 1 is parsed, **Then** its description is exactly `UPI-EXAMPLEMERCHANT Date Narration Chq./Ref.No. ValueDt WithdrawalAmt. DepositAmt. ClosingBalance` (the column-header line stitched in).
2. **Given** the **compact** statement, **When** row 2 is parsed, **Then** its description is exactly `NEFTCR-EXAMPLEEMPLOYER OpeningBalance DrCount CrCount Debits Credits ClosingBal 1,00,000.00 1 1 5,000.00 50,000.00 1,45,000.00` (the trailing summary rows stitched in).
3. **Given** the **detailed** statement, **When** row 1 is parsed, **Then** its description is exactly `UPI-EXAMPLEMERCHANT Txn Date Narration Withdrawals Deposits Closing Balance` (the column-header line stitched in).
4. **Given** the **detailed** statement, **When** row 2 is parsed, **Then** its description is exactly `UPI-EXAMPLEEMPLOYER salary`.
5. **Given** either statement, **When** the narration is stitched, **Then** the output is byte-for-byte identical to the ground truth — the reader does not trim, collapse, reorder, or otherwise "clean up" the stitched header/summary text.

---

### User Story 6 - Ledger metadata: the alphanumeric serial, the billing period, and a bank-aware account last-4 (Priority: P6)

Each parsed row carries its ledger metadata (running balance, balance delta, amount-matches-delta, is-suspect, direction source, and **serial**), and the statement carries its printed opening/closing balances, billing **period**, and account **last-4**. In the **compact** layout the row's **serial** is the alphanumeric reference captured from the anchor (e.g., `0000600000000001`, `CITIN26653417445`); the **detailed** layout has no such reference, so the serial is empty. The billing **period** comes from the statement's `From : <date> To <date>` text (the colon before the end date is optional; matched case-insensitively). The account **last-4** comes from HDFC's account-number pattern (an optional masked `X*` prefix then 4+ digits — which differs from ICICI's pattern), else the longest standalone ≥9-digit run; only the trailing four digits are ever kept — the full account number is never logged or persisted.

**Why this priority**: These fields make the ledger auditable and attributable. HDFC's compact layout carries a genuine alphanumeric reference that must be captured as the serial; HDFC's account-number text differs from ICICI's (a masked `X*` prefix, 4+ digits) so it needs its own primary pattern; and the period text's optional colon must be tolerated. Getting the last-4 right — and keeping only the trailing four digits — is a correctness and privacy requirement.

**Independent Test**: Parse both reference statements and confirm each compact row exposes its alphanumeric serial (and each detailed row an empty serial); confirm both statements record period 2026-04-01 → 2026-04-30 and account last-4 `3425`; confirm only the trailing four digits are retained.

**Acceptance Scenarios**:

1. **Given** the **compact** statement, **When** it is parsed, **Then** row 1's serial is `0000600000000001` and row 2's serial is `CITIN26653417445` (the captured alphanumeric references).
2. **Given** the **detailed** statement, **When** it is parsed, **Then** each row's serial is empty (the layout carries no reference token).
3. **Given** either statement, **When** the billing period is extracted, **Then** it is 2026-04-01 → 2026-04-30 — parsed from `From : 01/04/2026 To : 30/04/2026` (compact) and `Statement From : 01/04/2026 To 30/04/2026` (detailed, no colon before the end date), matched case-insensitively.
4. **Given** either statement's printed account number, **When** the account last-4 is extracted, **Then** it is `3425` — via HDFC's account-number pattern (optional masked `X*` prefix, 4+ digits), else the longest standalone ≥9-digit run.
5. **Given** the extracted account number, **When** the result is produced, **Then** only the trailing four digits (`3425`) are retained — the full account number is never logged, columned, or persisted.
6. **Given** a statement in which a metadata field cannot be found, **When** it is parsed, **Then** that field is left unset rather than fabricated, and the transactions are still returned.

---

### User Story 7 - The document gate tells an HDFC savings statement from an HDFC credit-card statement (Priority: P7)

HDFC issues **both** credit-card and savings/current statements, so — like ICICI — it has both a credit-card reader and this bank reader under distinct kinds. The bank reader's document gate (`claims`) must therefore be specific: it recognizes a document only when it carries the HDFC **bank code**, **all** of the required markers (`HDFC`), and **any** of a set of optional markers (`WithdrawalAmt`, `Savings Account Details`, `Statementof account`). An HDFC **credit-card** statement must be **REJECTED** by the bank reader.

**Why this priority**: Because the issuer is shared, a naive issuer-only check would misroute an HDFC credit-card statement into the bank reader (or vice-versa). Making the gate distinguish the two document types is what keeps each statement handled by exactly the right reader — a correctness prerequisite for the dual-reader (credit-card + bank-account) design that already exists for ICICI.

**Independent Test**: Ask the bank reader whether it claims the compact and detailed HDFC reference statements (expect yes for both) and whether it claims an HDFC credit-card statement (expect no); confirm the existing HDFC credit-card reader still claims that credit-card statement.

**Acceptance Scenarios**:

1. **Given** the synthetic HDFC **compact** reference statement, **When** the bank reader's document gate is asked, **Then** it **claims** the document (HDFC bank code present, all required markers present, at least one optional marker — e.g., `Statementof account` or `WithdrawalAmt` — present).
2. **Given** the synthetic HDFC **detailed** reference statement, **When** the bank reader's document gate is asked, **Then** it **claims** the document (at least one optional marker — e.g., `Savings Account Details` — present).
3. **Given** an HDFC **credit-card** statement, **When** the bank reader's document gate is asked, **Then** it does **not** claim the document — the credit-card statement is rejected by the bank reader.
4. **Given** a statement from a different issuer, **When** the bank reader's document gate is asked, **Then** it does **not** claim the document.
5. **Given** the same HDFC credit-card statement, **When** the existing HDFC credit-card reader's gate is asked, **Then** that reader still claims it — the two readers remain correctly separated by document type.

---

### User Story 8 - A config-on-an-existing-base slice: reuse the base unchanged, with one small shared addition (Priority: P8)

As a maintainer, this slice is delivered as a **per-issuer configuration** on the existing balance-ledger base — **not** new infrastructure. The reusable base (anchor recognition against an ordered pattern list, delta-derived direction, the printed-amount-as-independent-check, narration stitching, the row-1 bootstrap, and the errored-vs-suspect distinction) and the **balance-chain check** are **reused unchanged**, as are the **parity harness** and the **privacy-egress gate**. The **only** genuinely new *shared* code is a **tiny bank-account-tail helper** factored into the shared common module: try a **per-bank primary account regex**, else the **longest standalone ≥9-digit run**. This is factored out because HDFC's account regex differs from ICICI's while the ≥9-digit fallback is identical across banks; the shared helper will also serve the later Federal and AU readers.

**Why this priority**: The whole point of the slice is to prove the balance-ledger base is genuinely reusable — that a second bank is *just configuration plus fixtures*, exactly as the credit-card issuers were drop-ins after the first card reader. Keeping the base, the balance chain, the harness, and the privacy gate untouched (and confining the sole shared addition to a small, clearly-scoped tail helper) is what keeps the change surgical and lets later banks drop in the same way.

**Independent Test**: Confirm the HDFC bank parse is delivered by a per-issuer configuration plugged into the unchanged base and balance-chain check; confirm no base internals (anchor recognition, direction-from-delta, amount-as-check, stitching, row-1 bootstrap, errored-vs-suspect, the balance chain, the parity harness, the privacy gate) were modified; confirm the sole new shared code is the account-tail helper (per-bank primary regex, else longest ≥9-digit run) in the shared common module, reused by HDFC and available to later banks.

**Acceptance Scenarios**:

1. **Given** the change set, **When** it is reviewed, **Then** the balance-ledger base (anchor recognition, delta-derived direction, amount-as-independent-check, narration stitching, row-1 bootstrap, errored-vs-suspect) is **reused unchanged** — HDFC contributes only its per-issuer configuration (document gate, anchor patterns, opening/period patterns, account extractor).
2. **Given** the change set, **When** it is reviewed, **Then** the **balance-chain check** is **reused unchanged**, and reports **RECONCILED** for both HDFC fixtures.
3. **Given** the change set, **When** it is reviewed, **Then** the **parity harness** and the **privacy-egress gate** are **reused unchanged** and extended to cover the HDFC bank path.
4. **Given** the change set, **When** it is reviewed, **Then** the **only** new shared code is the account-tail helper (per-bank primary regex, else the longest standalone ≥9-digit run) placed in the shared common module.
5. **Given** the shared account-tail helper, **When** a later bank reader (e.g., Federal or AU) is added, **Then** it can reuse the helper by supplying its own primary account regex — the ≥9-digit fallback is shared.

---

### User Story 9 - Proven byte-for-byte against two golden fixtures, both RECONCILED (Priority: P9)

As a maintainer, the engine's HDFC bank-account behaviour is pinned to the proven web engine by porting **two** synthetic HDFC characterization vectors — one **compact**, one **detailed** — into the repository's `fixtures/` directory as golden vectors, and asserting the on-device engine reproduces each exactly: every row's date, amount, direction, stitched description, running balance, delta, amount-matches-delta, is-suspect, direction source, and serial; the statement's printed opening/closing balances; the billing period; the account last-4; and the **RECONCILED** balance-chain result.

**Why this priority**: Parity is the constitution's acceptance mechanism for the port (Principle V). Two fixtures — one per layout — turn "we think both layouts match" into an enforced, regression-proof guarantee, and they extend the existing ledger parity harness to a second bank without changing it.

**Independent Test**: Run the parity harness over the two ported HDFC vectors and confirm the engine's output matches the expected output exactly for each, and that re-running produces identical results.

**Acceptance Scenarios**:

1. **Given** the ported **compact** golden vector, **When** the parity harness runs, **Then** the engine's parsed output matches exactly — row 1 (2026-04-01 / 5000.00 / debit / balance 95000.00 / delta −5000.00 / `direction_source = opening_balance` / serial `0000600000000001`) and row 2 (2026-04-16 / 50000.00 / credit / balance 145000.00 / delta +50000.00 / `direction_source = balance_delta` / serial `CITIN26653417445`), with their stitched descriptions; printed opening 100000.00 and closing 145000.00; period 2026-04-01 → 2026-04-30; account last-4 `3425`; and a **RECONCILED** balance chain (zero suspects, no row-1 fallback).
2. **Given** the ported **detailed** golden vector, **When** the parity harness runs, **Then** the engine's parsed output matches exactly — row 1 (2026-04-01 / 5000.00 / debit / balance 95000.00 / delta −5000.00 / `direction_source = opening_balance` / empty serial) and row 2 (2026-04-20 / 50000.00 / credit / balance 145000.00 / delta +50000.00 / `direction_source = balance_delta` / empty serial), with their stitched descriptions; printed opening 100000.00 and closing 145000.00; period 2026-04-01 → 2026-04-30; account last-4 `3425`; and a **RECONCILED** balance chain (zero suspects, no row-1 fallback).
3. **Given** a change that alters HDFC bank-account parsing behaviour, **When** the parity harness runs, **Then** it fails, enforcing the parity guarantee.
4. **Given** either golden fixture, **When** it is inspected, **Then** all input and expected data is synthetic or fully redacted (fabricated payers, amounts, and account number) — never real account data.

---

### User Story 10 - Privacy gate and the Swift bridge: zero network, no new dependency, reachable from Swift (Priority: P10)

As a maintainer, the existing automated privacy-egress test covers the HDFC bank-account import/parse path and asserts it performs no network I/O, and the new reader is reachable over the existing UniFFI bridge to Swift — all with **no new dependency** (and specifically no networking dependency). Money remains an exact decimal (never a float).

**Why this priority**: Privacy is the product's non-negotiable promise and a required constitution gate; being reachable from Swift is what makes the reader usable by the app. Proving both for the second bank — with zero new dependencies — extends the guarantee to another reader on the balance-ledger family without weakening it.

**Independent Test**: Run the privacy-egress test against the HDFC bank-account parse path and confirm it passes only when zero outbound network connections occur; confirm the reader is callable over the UniFFI bridge from Swift; confirm no new runtime (and specifically no networking) dependency was added.

**Acceptance Scenarios**:

1. **Given** the HDFC bank-account parse path, **When** the automated privacy-egress test runs, **Then** it confirms zero outbound network connections occur during parsing.
2. **Given** a regression that introduces any network access into the parse path, **When** the privacy-egress test runs, **Then** it fails, blocking the change.
3. **Given** the shared engine, **When** the HDFC bank-account reader is exposed, **Then** it is reachable over the existing UniFFI bridge to Swift (via the existing bank-account parse and claims surfaces), mirroring ICICI.
4. **Given** the change set, **When** dependencies are reviewed, **Then** no new runtime dependency — and no networking dependency — is added, and money stays an exact decimal (never a float).

---

### Edge Cases

- **Wrong document type, same issuer**: An HDFC **credit-card** statement is presented to the HDFC **bank** reader → the bank reader must **not** claim it (required + optional marker gate), so a card statement is never misread as a ledger; the existing HDFC credit-card reader still claims it.
- **Wrong issuer**: A statement from a different issuer is presented to the HDFC bank reader → not claimed.
- **Two layouts, one reader**: The compact and detailed statements each parse through the *single* HDFC reader via first-match-wins anchors; a compact row (2-digit year) never matches the detailed anchor and a detailed row (4-digit year) never matches the compact anchor.
- **Detailed two-column amount**: A detailed row prints the non-transacting side as `0.00`; the printed amount for the integrity check is the **non-zero** column (Withdrawals ⇒ the debit figure, Deposits ⇒ the credit figure).
- **Direction independent of amount and column**: A row's balance falls → **debit**; a row's balance rises → **credit**; flipping the delta's sign flips the direction even when the printed amount/column is unchanged.
- **Compact opening balance is a summary figure, not row 1's balance**: The compact opening balance is the first figure on the line beneath the `OpeningBalance …` summary header (100000.00), **not** row 1's running balance (95000.00).
- **Detailed opening balance is inline**: The detailed opening balance is read from the inline `Opening Balance : <amount>` line.
- **Period colon optional**: The period is parsed from `From : <date> To <date>` where the colon before the end date is optional (`To :` or `To`), matched case-insensitively.
- **Account number with a masked prefix**: HDFC's account text may carry an optional masked `X*` prefix before 4+ digits; the last-4 is the trailing four digits, else the longest standalone ≥9-digit run; only the trailing four digits are retained.
- **Narration stitching quirk (faithful)**: Row 0's narration includes the adjacent column-header line; the compact row 1's narration includes the trailing end-of-statement summary rows — reproduced byte-for-byte, never "cleaned up".
- **Alphanumeric vs empty serial**: The compact serial is the captured alphanumeric reference; the detailed layout has no reference token, so its serial is empty.
- **Amount ≠ |delta| (chain break)**: A row whose printed amount differs from the absolute balance delta by more than the rounding tolerance → marked a **suspect**; the balance chain reports **NEEDS_REVIEW**; the row is **still returned**, never dropped. (Both HDFC fixtures reconcile within tolerance and produce zero suspects.)
- **Unparseable anchor-shaped row**: A line matching an anchor's shape but whose date/amount/balance will not parse → captured as an **errored line** (bounded length); every good row is still returned; it is **not** a suspect.
- **No column split for HDFC**: HDFC sets no column-split x-position, so the row-1 x-position geometry path is **not** exercised by this slice (both fixtures are opening-anchored).
- **Indian money formatting**: Amounts/balances with thousands separators, including the Indian grouping style (e.g., `1,45,000.00`) → parsed to exact, non-negative decimals with stated precision preserved.
- **Missing metadata**: No recognizable opening/closing balance, period, or account number → the corresponding field is left unset rather than fabricated; transactions are still returned.
- **No transaction lines**: Empty input, or input with no recognizable anchor rows → an empty transaction list is returned with no error.
- **Repeated / concurrent parses**: The same input parsed repeatedly → identical results every time, with no dependence on wall-clock time, locale, or hidden global state.

## Requirements *(mandatory)*

### Functional Requirements

**Document recognition (the savings-vs-credit-card gate)**

- **FR-001**: The engine MUST recognize a statement as an HDFC **bank-account** (savings/current) statement via a document gate that requires the HDFC **bank code**, **all** required markers (`HDFC`), and **any** of a set of optional markers (`WithdrawalAmt`, `Savings Account Details`, `Statementof account`) — specific enough to distinguish an HDFC savings/current statement from an HDFC credit-card statement (which share the issuer).
- **FR-002**: The bank reader MUST NOT claim an HDFC **credit-card** statement, and MUST NOT claim a statement from a different issuer. The existing HDFC credit-card reader MUST continue to claim the HDFC credit-card statement — the two readers remain separated by document kind.

**One reader, two export layouts (configuration on the existing base)**

- **FR-003**: The single HDFC bank reader MUST handle HDFC's **two** export layouts behind one reader, selected by **first-match-wins** anchor patterns supplied to the existing base's ordered anchor mechanism — introducing **no** new base capability (the base already tries a per-issuer ordered list of anchor patterns).
- **FR-004**: The **compact** layout MUST be recognized by an anchor for a `DD/MM/YY` (2-digit year) transaction line ending `… <alphanumeric ref> <value-date DD/MM/YY> <amount> <balance>`, capturing the **date**, an inline **description**, the alphanumeric **serial** (the reference), a single printed **amount**, and the running **balance**.
- **FR-005**: The **detailed** layout MUST be recognized by an anchor for a `DD/MM/YYYY` (4-digit year) transaction line with explicit **Withdrawals** and **Deposits** columns (the empty side printed as `0.00`) followed by the closing **balance**, capturing the **date**, an inline **description**, the **withdrawal** amount, the **deposit** amount, and the running **balance**.
- **FR-006**: A **compact** transaction line MUST NOT match the **detailed** anchor, and a **detailed** transaction line MUST NOT match the **compact** anchor (the 2-digit vs 4-digit year makes the two mutually exclusive); each transaction line is read by exactly one layout, and the first matching anchor wins.

**Direction from the running-balance delta; amount as an independent check**

- **FR-007**: The engine MUST derive each transaction's debit/credit **direction** from the **running-balance delta** in **both** layouts: a **fall** (delta < 0) is a **debit**, a **rise** (delta > 0) is a **credit**. Direction MUST NEVER be inferred from the sign or magnitude of the printed amount, nor from which column (Withdrawals/Deposits) a figure is printed in.
- **FR-008**: The engine MUST treat the printed **amount as an INDEPENDENT integrity check**: a row **reconciles** when the printed amount equals the absolute value of the balance delta within the reused rounding tolerance, otherwise it is a **suspect**. In the **compact** layout the printed amount is the single amount token; in the **detailed** layout the printed amount is the **non-zero** of the Withdrawals/Deposits pair (the empty side prints `0.00`).
- **FR-009**: A **suspect** row (printed amount does not match its balance delta) MUST still be **returned** (flagged), never silently dropped; the engine MUST record per row whether the amount matches the delta (`amount_matches_delta`) and whether the row is a suspect (`is_suspect`). Both HDFC reference fixtures reconcile (zero suspects).

**Amount**

- **FR-010**: The engine MUST parse each amount and each running balance as an exact **decimal**, honouring Indian number formatting (thousands separators, including the Indian grouping style, e.g. `1,45,000.00`) and preserving stated precision. Monetary values MUST NEVER be represented as floating-point numbers.

**Opening balance and row-1 bootstrap**

- **FR-011**: For the **detailed** layout, the engine MUST read the printed opening balance from the inline `Opening Balance : <amount>` text.
- **FR-012**: For the **compact** layout, the engine MUST read the printed opening balance from the **end-of-statement summary row** — the first figure on the line beneath the `OpeningBalance …` summary header (a multi-line pattern) — which is **not** row 1's running balance.
- **FR-013**: For the **first** ledger row, the engine MUST anchor direction against the printed opening balance (`direction_source = opening_balance`) in both fixtures, reusing the base's unchanged row-1 bootstrap precedence; every row after the first MUST be `balance_delta`. HDFC supplies **no** column-split x-position, so the row-1 x-position geometry path is not exercised by this slice.

**Narration stitching (faithful parity)**

- **FR-014**: The engine MUST reassemble each row's **description (narration)** using the reused base's narration stitching (the anchor's inline description plus the wrapped detail line above and the detail lines below up to the next transaction, skipping other anchors and printed-balance lines), and MUST reproduce the known web-engine behaviour where a header/summary line adjacent to a transaction is stitched into that row's narration — **row 0's narration includes the column-header line** (both layouts) and the **compact row 1's narration includes the trailing summary rows**. These stitched strings MUST be reproduced **byte-for-byte**; the port MUST NOT trim, collapse, reorder, or otherwise "clean up" the stitched text.

**Per-row and statement-level ledger metadata**

- **FR-015**: Each parsed row MUST carry: the transaction **date**, the exact **amount**, the delta-derived **direction**, the currency (INR), the stitched **description**, the running **balance**, the **balance delta**, `amount_matches_delta`, `is_suspect`, `direction_source`, and the **serial**. The compact serial is the captured alphanumeric reference; the detailed serial is empty.
- **FR-016**: The statement MUST carry: the **printed opening balance**, the **printed closing balance**, the **billing period** (start and end), and the account **last-4**.
- **FR-017**: The engine MUST derive the billing **period** from `From : <DD/MM/YYYY> To <DD/MM/YYYY>` text where the colon before the end date is **optional** (`To :` or `To`), matched **case-insensitively**.
- **FR-018**: The engine MUST derive the account **last-4** from HDFC's account-number pattern — an optional masked `X*` prefix followed by **4 or more** digits (which differs from ICICI's pattern) — else from the longest standalone **≥9-digit** run; and MUST retain **only** the trailing four digits. The full account number MUST NEVER be logged, columned, or persisted.
- **FR-019**: When a metadata field cannot be found, the engine MUST leave it unset rather than fabricate a value, and MUST still return the parsed transactions.

**Reuse of the existing base, and the one new shared addition**

- **FR-020**: This slice MUST **reuse unchanged** the existing balance-ledger reader base (anchor recognition against an ordered pattern list, delta-derived direction, the printed-amount-as-independent-check, narration stitching, the row-1 bootstrap, and the errored-vs-suspect distinction) and the **balance-chain integrity check** — HDFC is added only as a **per-issuer configuration** (document gate, anchor patterns, opening/period patterns, account extractor).
- **FR-021**: This slice MUST **reuse unchanged** the golden-fixture **parity harness** and the **privacy-egress gate**, extending them to cover the HDFC bank path.
- **FR-022**: The **only** genuinely new *shared* code this slice introduces MUST be a small **bank-account-tail helper** in the shared common module: try a **per-bank primary account regex**, else the **longest standalone ≥9-digit run**, returning the trailing four digits. HDFC supplies its own primary regex; the ≥9-digit fallback is shared and MUST be reusable by the later Federal and AU readers.
- **FR-023**: The engine MUST reuse the existing shared money/date/currency/direction conventions and helpers (Indian-format decimal parsing; the shared date parser, which already carries the HDFC `DD/MM/YY` and `DD/MM/YYYY` formats; the explicit `Direction` type). No other new shared engine internals may be added by this slice.

**Balance-chain integrity (reused)**

- **FR-024**: The engine MUST run the reused **balance-chain integrity check** over the parsed HDFC ledger and report **RECONCILED** for both reference fixtures (every row reconciles within tolerance and there is no un-trusted row-1 bootstrap), with zero suspects and no row-1 direction fallback.

**Engine purity, platform boundary & bridge**

- **FR-025**: The engine's HDFC bank-account parse MUST accept already-extracted text lines, the full statement text, and the first-row word geometry, and return the parsed result; it MUST NOT read files, extract PDF text, or embed a PDF engine (text and geometry extraction are native platform concerns). The Rust core MUST NEVER open a PDF.
- **FR-026**: The engine MUST remain pure and deterministic: identical input MUST yield identical output, with no dependence on network, wall-clock time, locale, or hidden global mutable state.
- **FR-027**: The engine MUST expose the HDFC bank-account reader over the existing **UniFFI** bridge via the existing bank-account parse and claims surfaces, reachable from Swift, mirroring the ICICI bank-account reader.

**Privacy (constitution Principle I — NON-NEGOTIABLE)**

- **FR-028**: The entire HDFC bank-account import/parse path MUST run 100% on-device with ZERO network I/O.
- **FR-029**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting into the engine or the app, and MUST NOT add any **networking** dependency.
- **FR-030**: The existing automated privacy-egress test MUST cover the HDFC bank-account parse path and assert it performs no network access; it remains a required constitution gate.

**Parity & test-first (constitution Principle V)**

- **FR-031**: The web engine's synthetic HDFC **compact** and **detailed** characterization vectors MUST be ported into the repository's `fixtures/` directory (HDFC bank-account subtree) as golden vectors, and the engine MUST reproduce each exactly (rows with dates/amounts/directions/stitched-descriptions/balances/deltas/serials, printed opening/closing balances, billing period, account last-4, and the RECONCILED balance-chain result).
- **FR-032**: All fixture and test data MUST be synthetic or fully redacted (fabricated payers, amounts, and account number) — never real account data.
- **FR-033**: The HDFC bank-account parsing behaviour introduced by this slice MUST be developed test-first (a failing golden test precedes the behaviour).

**Licensing, secrets & quality gates**

- **FR-034**: The change MUST NOT add secrets, API keys, or private endpoints; MUST remain distributable under Apache-2.0 with no copyleft (GPL/AGPL/LGPL) dependencies; and MUST introduce **no new runtime dependency** for this slice.
- **FR-035**: The change MUST keep the iOS Local Verification Gate and CI green: core formatting, linting, and tests; app linting; project generation; a simulator build with passing app tests; and the privacy gate. If any user-facing surface is introduced, it MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility.

### Key Entities *(include if feature involves data)*

- **Extracted statement input**: The already-extracted text lines, the full statement text, and the first transaction row's word geometry handed to the engine by the native platform. Contains no PDF binary; the engine never opens a PDF.
- **HDFC export layout (compact / detailed)**: The two recognized HDFC bank-account row formats. The single HDFC reader selects between them via first-match-wins anchor patterns on the base's ordered anchor list; the caller is unaware of which matched. The compact layout has `DD/MM/YY` dates, a single amount, and an alphanumeric reference; the detailed layout has `DD/MM/YYYY` dates and explicit Withdrawals/Deposits columns.
- **Parsed ledger row**: One ledger transaction — a transaction date, an exact non-negative amount, a delta-derived direction, a currency (INR), a stitched description, the running balance, the balance delta, an amount-matches-delta indicator, an is-suspect indicator, a direction source, and a serial (alphanumeric for compact; empty for detailed).
- **Parsed bank statement result**: The full output of reading one HDFC bank-account statement — the bank identity and account kind, the list of parsed ledger rows, the list of errored (unparseable) lines, the printed opening balance, the printed closing balance, the billing period (start/end), the account last-4, and the balance-chain result.
- **Direction (polarity)**: An explicit debit or credit indicator carried on every transaction, sourced from the running-balance delta (and, for row 1, from the printed opening balance) — never from the amount's sign or the printed column.
- **Balance-chain result**: A statement-level status of RECONCILED or NEEDS_REVIEW, with the list of suspect rows — reused unchanged; RECONCILED for both HDFC fixtures.
- **`direction_source`**: How a row's direction was decided — `opening_balance` for row 1 in both fixtures; `balance_delta` for every later row.
- **Bank-account-tail helper**: The one new shared helper — a per-bank primary account regex, else the longest standalone ≥9-digit run, returning the trailing four digits — factored into the shared common module and reusable by later banks.
- **Golden characterization vectors**: Two synthetic HDFC inputs (compact and detailed: text lines + full text + first-row geometry) paired with their expected engine outputs, stored under `fixtures/`, ported from the web engine and reproduced exactly by the on-device engine.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The synthetic HDFC **compact** reference statement parses byte-for-byte to the ground truth on-device — row 1 (2026-04-01 / 5000.00 / debit / balance 95000.00 / delta −5000.00 / serial `0000600000000001` / `direction_source = opening_balance`) and row 2 (2026-04-16 / 50000.00 / credit / balance 145000.00 / delta +50000.00 / serial `CITIN26653417445` / `direction_source = balance_delta`), with their stitched descriptions (100% match).
- **SC-002**: The synthetic HDFC **detailed** reference statement parses byte-for-byte to the ground truth on-device — row 1 (2026-04-01 / 5000.00 / debit / balance 95000.00 / delta −5000.00 / empty serial / `direction_source = opening_balance`) and row 2 (2026-04-20 / 50000.00 / credit / balance 145000.00 / delta +50000.00 / empty serial / `direction_source = balance_delta`), with their stitched descriptions (100% match).
- **SC-003**: The reused balance-chain check reports **RECONCILED** for **both** HDFC reference statements — zero suspects and no row-1 direction fallback.
- **SC-004**: The **compact** layout captures the alphanumeric **serial** (`0000600000000001`, `CITIN26653417445`) and reads its **opening balance** (100000.00) from the end-of-statement summary row — not from row 1's balance.
- **SC-005**: The **detailed** layout resolves the printed **amount** from the **non-zero** of the Withdrawals/Deposits column pair (5000.00 from Withdrawals for row 1; 50000.00 from Deposits for row 2), and reads its opening balance (100000.00) from the inline `Opening Balance :` line.
- **SC-006**: Direction is **delta-derived** across every tested case and both layouts — the balance falls ⇒ debit, rises ⇒ credit — and a row's direction **flips when its balance delta flips**, independent of the printed amount or column.
- **SC-007**: The narration for every row is stitched **byte-for-byte** to the ground truth, including row 0's column-header text (both layouts) and the compact row 1's trailing summary text — with no normalization applied.
- **SC-008**: The bank reader **claims** both HDFC reference statements (compact and detailed) and **rejects** an HDFC **credit-card** statement — 0 misroutes across the recognition cases; the existing HDFC credit-card reader still claims the credit-card statement.
- **SC-009**: Both statements record `printed_opening_balance = 100000.00`, `printed_closing_balance = 145000.00`, billing **period** 2026-04-01 → 2026-04-30, and account **last-4 `3425`** (via HDFC's account pattern with its optional masked `X*` prefix / 4+ digits, else the longest ≥9-digit run), retaining only the trailing four digits.
- **SC-010**: The base, the balance-chain check, the parity harness, and the privacy-egress gate are reused **unchanged**; the **only** new shared code is the account-tail helper (per-bank primary regex, else longest ≥9-digit run) in the shared common module.
- **SC-011**: 100% of parsed amounts and balances are exact **decimals** with stated precision preserved; **no monetary value is ever a floating-point number**.
- **SC-012**: Zero outbound network connections occur during the entire HDFC bank-account parse path, verified by the automated privacy-egress test, and **no new runtime (or networking) dependency** is added.
- **SC-013**: The whole reader is reachable over the **UniFFI bridge to Swift** (via the existing bank-account parse and claims surfaces), mirroring ICICI.
- **SC-014**: Given identical input, the engine returns identical output across repeated runs (100% reproducible); both ported golden vectors reproduce exactly and the parity harness passes.
- **SC-015**: All automated checks required to merge pass (green), including the parity harness and the privacy-egress test, with the iOS Local Verification Gate and CI green; and no secrets or copyleft-licensed dependencies are added (verified by review of manifests and dependencies).

## Assumptions

- **Config-on-an-existing-base, not new infrastructure**: The balance-ledger reader base (anchor recognition against an ordered pattern list + narration stitching + delta-derived direction + the amount-vs-delta integrity check + row-1 bootstrap + errored-vs-suspect) and the balance-chain integrity check already exist (from the ICICI reference slice) and are reused **unchanged**. HDFC is added as a per-issuer configuration plus golden fixtures.
- **The base already supports multiple layouts**: The base recognizes a transaction against a per-issuer **ordered list** of anchor patterns (first match wins), so HDFC's two export layouts are configuration, not a new base capability. HDFC is simply the first configuration to supply more than one anchor pattern.
- **The one new shared addition**: The sole genuinely new shared code is a small bank-account-tail helper factored into the shared common module — try a per-bank primary account regex, else the longest standalone ≥9-digit run — because HDFC's account regex differs from ICICI's while the fallback is identical across banks. It will also serve the later Federal/AU readers. The exact module placement and function signature are finalized in `/speckit.plan`.
- **Anchor patterns (ported characterization, realized in `/speckit.plan`)**: The compact anchor matches a `DD/MM/YY` line ending `<alphanumeric ref> <value-date DD/MM/YY> <amount> <balance>` (single amount; the reference is the serial); the detailed anchor matches a `DD/MM/YYYY` line with `<withdrawal> <deposit> <balance>` columns (the empty side `0.00`). Ported faithfully from the web engine's `hdfc_bank.py` first-match-wins patterns; the exact regex realization is finalized in `/speckit.plan`.
- **Opening-balance patterns (ported characterization)**: The detailed opening is `Opening Balance : <amount>` (inline); the compact opening is the first figure on the line beneath the `OpeningBalance …` summary header (a multi-line pattern) — deliberately **not** row 1's balance. Realized in `/speckit.plan`.
- **Period & account patterns (ported characterization)**: The period is `From : <DD/MM/YYYY> To <DD/MM/YYYY>` with an optional colon before the end date, matched case-insensitively; the account last-4 is HDFC's account-number pattern (optional masked `X*` prefix, 4+ digits), else the longest ≥9-digit run. These differ from ICICI's patterns; realized in `/speckit.plan`.
- **Narration-stitching quirk is faithful, not a bug to fix**: The web engine stitches a header/summary line adjacent to a transaction into that row's narration (row 0's column header; the compact row 1's trailing summary). The port reproduces these byte-for-byte; the golden fixtures pin them.
- **Rounding tolerance & suspect/errored semantics are reused**: The amount-vs-delta tolerance, the suspect vs errored distinction, and the RECONCILED / NEEDS_REVIEW statuses are inherited unchanged from the base and balance-chain check. Both HDFC fixtures reconcile (zero suspects).
- **No column split for HDFC**: HDFC supplies no column-split x-position, so the row-1 x-position geometry path is supported by the base but **not** exercised by this slice; both fixtures are opening-anchored.
- **Reader identity**: The reader is the HDFC **bank-account** reader, sharing the HDFC issuer with the existing HDFC credit-card reader and distinguished by **account kind** (savings/current). The exact identity string values are finalized in `/speckit.plan`.
- **Parse seam & platform boundary**: The bank-account seam is the existing one — already-extracted text lines, the full text, and the first transaction row's word geometry — returning the parsed result. The native platform (iOS PDFKit) performs the text and geometry extraction; the Rust core never opens a PDF.
- **Binding**: The reader is exposed to Swift via the existing UniFFI bridge through the existing bank-account parse and claims surfaces, mirroring ICICI; concrete binding mechanics belong in `/speckit.plan`.
- **Fixtures location**: The two golden fixtures live under the HDFC bank-account fixtures subtree (e.g. `fixtures/hdfc/bank_account/`) and are the source of truth for parity; the exact paths are finalized in `/speckit.plan`.
- **No new dependencies**: This slice should require **no** new runtime dependencies, and specifically **no** networking dependency.
- **Source of truth**: The web engine is the source of truth for behaviour — the HDFC bank reader `hdfc_bank.py` plus the shared balance-ledger reader, the balance-chain check, and the shared common/polarity helpers, and the bank-account characterization/parity test. The porting approach (module layout, patterns, fixture format, UniFFI exports) is decided in `/speckit.plan`, not here.
- **Synthetic characterization vectors**: The two synthetic statements and their expected outputs — the compact rows (2026-04-01 / 5000.00 / debit and 2026-04-16 / 50000.00 / credit) and detailed rows (2026-04-01 / 5000.00 / debit and 2026-04-20 / 50000.00 / credit), their balances (95000.00, 145000.00) and deltas (−5000.00, +50000.00), serials (`0000600000000001` / `CITIN26653417445` for compact; empty for detailed), stitched descriptions, printed opening/closing balances (100000.00 / 145000.00), billing period (2026-04-01 → 2026-04-30), account last-4 (`3425`), and the RECONCILED balance-chain result — are the constitution's golden-fixture parity vectors (Principle V), confirmed against the web engine, all synthetic/redacted.
- **No new UI required**: This is an engine slice; no user-facing UI is required to deliver it. App-side PDF text/geometry extraction (PDFKit wiring), the file-import UI, and the Share Extension remain a native concern and a later step. If a trivial demo surface is added, it follows HIG and accessibility (FR-035).
- **Data safety**: All fixture and test data is synthetic or fully redacted — no real account data.
- **Money & geometry types**: Amounts and balances are exact decimals (never floating-point) and direction is carried explicitly and derived from the balance delta; geometry x-coordinates are layout points (not money) and may be floating-point.

### Dependencies

- **Kaname Constitution v1.0.0** — privacy (zero-network free/core), determinism, a pure platform-agnostic core (no PDF engine), decimal money with explicit polarity, Apache-2.0 open-core with no copyleft, native HIG/accessibility, and the test-first iOS Local Verification Gate (including the privacy-egress gate).
- **The ICICI bank-account (balance-ledger) reference slice (already landed)** — the reusable balance-ledger reader base (anchor recognition against an ordered pattern list, delta-derived direction, amount-as-independent-check, narration stitching, row-1 bootstrap, errored-vs-suspect), the balance-chain integrity check, the ledger parity harness, the bank-account UniFFI surfaces, and the privacy-egress gate — all reused unchanged by this slice.
- **The five credit-card slices (already landed)** — the shared reader output types (parsed statement / parsed transaction), the Indian-format amount parser, the shared multi-format date parser (which already carries the HDFC `DD/MM/YY` and `DD/MM/YYYY` formats), the shared `Direction` type and polarity module, and the golden-fixture parity harness — reused by this slice.
- **The Rust↔Swift bridge (already landed)** — the shared engine crate and the UniFFI Swift binding proven end-to-end, over which the bank-account parse and claims functions are exposed.
- **Web engine golden vectors** — the two synthetic HDFC bank characterization vectors (compact and detailed) and the `hdfc_bank.py` behaviour used as the parity source of truth.

## Out of Scope

Deferred to later P2 slices / milestones:

- **The other bank-account ledger readers** — the **ICICI** (already landed), **Federal**, and **AU** bank-account readers; Federal and AU follow in later slices on this same base and reuse the new shared account-tail helper.
- **IOB** — a **credit-card** reader (not a ledger reader), out of scope here.
- **Reconciliation of printed debit/credit totals** (the printed Debits/Credits summary figures), **coverage / billing-period timeline**, and **cross-source de-duplication and transfer detection** — separate later concerns; this slice delivers the balance-**chain** integrity check (reused), not printed-total reconciliation.
- **Real-PDF geometry calibration** — HDFC sets no column-split x-position, so the row-1 x-position path is not exercised here; provisional/x-position rows (not present in these fixtures) are surfaced NEEDS_REVIEW, never silently trusted.
- **Persistence** — encrypted SQLite / SQLCipher storage and key management.
- **AI-fallback parsing**.
- Any **premium / cloud features**.
- **App-side PDF text/geometry extraction** (PDFKit wiring in the app) and the **file-import UI / Share Extension** — native concerns handled in a later slice. This slice focuses on the HDFC bank-account configuration on the existing balance-ledger base plus its golden-fixture parity, reusing the existing balance chain, parity harness, and privacy gate, exposed over the existing bridge.
