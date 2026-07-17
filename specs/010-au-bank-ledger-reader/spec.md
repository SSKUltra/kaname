# Feature Specification: Read an AU Small Finance Bank (Savings/Current) Statement On-Device — the Fourth and Final Balance-Ledger Reference Reader (AU Config on the Existing Ledger Base, One Statement Template, Dash-Marked Empty Debit/Credit Columns, Delta-Derived Direction Despite UPI/DR·UPI/CR Counterparty Text)

**Feature Branch**: `010-au-bank-ledger-reader`  
**Created**: 2026-07-17  
**Status**: Draft  
**Milestone**: P2 — Engine port; the **fourth and final** bank-account (balance-ledger) reader, after the **ICICI** reference reader (which landed the reusable base), the **HDFC** drop-in, and the **Federal** drop-in  
**Input**: User description: "AU Small Finance Bank savings/current statement reading for the on-device Kaname core — the FOURTH and FINAL bank-account (balance-ledger) reader, after ICICI, HDFC and Federal. AU bank statements are running-balance ledgers with NO per-row Dr/Cr marker (the 'UPI/DR' / 'UPI/CR' text that appears inside a narration describes the COUNTERPARTY's leg, never this account's), so direction is derived from the running-balance delta. AU uses a SINGLE statement template: a flat-text transaction line starts with TWO 'DD Mon YYYY' dates (transaction date + value date) and ends in three tokens — a Debit column, a Credit column, and the running Balance — where EXACTLY ONE of the debit/credit columns carries a money value and the empty side prints a DASH ('-'). The wrapped UPI/NEFT narration and reference number land on the lines above and below the anchor and are stitched back together. This slice adds the AU configuration of the existing balance-ledger base plus its golden fixture; it reuses the base, the balance-chain check, the shared account_tail_last4 helper, the parity harness and the privacy gate unchanged."

> **Note on priority labels**: This feature is milestone **P2** (Engine port) in the product roadmap (`docs/kaname-ios-plan.md` §9). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P2" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

Three prior bank-account slices landed the **balance-ledger reader family** and its base: a **reusable balance-ledger base** (anchor recognition against an ordered pattern list, delta-derived direction, the printed-amount-as-independent-check, narration stitching, the row-1 bootstrap, and the errored-vs-suspect distinction), the **balance-chain integrity check**, the **golden-fixture parity harness** extended to ledgers, a shared **account-tail helper** (per-bank primary account regex, else the longest standalone ≥9-digit run → trailing four), and three configurations on that base — **ICICI** (the reference), **HDFC** (the first drop-in), and **Federal** (the second drop-in). This slice delivers the **fourth and final** bank on that same base — **AU Small Finance Bank** — and proves once more that a new bank is *just configuration plus fixtures*: a person imports their AU **savings / current** account statement and the app produces the ledger's transactions (date, exact amount, delta-derived debit/credit direction, running balance, and stitched description) entirely on-device, with no network and no account, exactly as it already does for ICICI, HDFC, and Federal.

This is a **config-on-an-existing-base** slice, not new infrastructure — and it is the **leanest** of the family: a **single-template drop-in** (even simpler than the two-template Federal and HDFC slices). The reusable balance-ledger base, the balance-chain check, **and** the shared account-tail helper **already exist and are reused unchanged**; AU is added purely as a **per-issuer configuration** (its own document gate, **one** anchor pattern, its opening/closing-balance and period patterns, and its account-number extractor) plus **one** golden fixture. This slice introduces **zero** new shared engine code, **zero** new shared helpers, and **zero** new dependencies.

AU's distinctive twist is the **absence of any per-row Dr/Cr marker for this account's direction**. Unlike Federal (which prints a trailing `Cr`/`Dr` denoting the running balance's sign), an AU ledger prints **no** direction marker at all. The strings `UPI/DR` and `UPI/CR` *do* appear — but **inside the narration**, where they describe the **counterparty's** leg of the UPI transfer, never this account's direction. Direction is therefore derived **solely** from the running-balance delta, exactly as for ICICI and HDFC. In the reference statement the debit row's narration happens to contain `UPI/DR` and the credit row's narration happens to contain `UPI/CR` — a **coincidence** that must **not** drive direction.

AU's second twist is the **dash-marked empty column**. AU prints **two** amount columns — a Debit column and a Credit column — where **exactly one** carries a money value and the empty side prints a literal **dash** (`-`). This differs from the Fi/HDFC two-column layout (where the empty side prints `0`). The reused base already resolves the non-empty side automatically: its loose two-column amount parser returns *no value* for a non-numeric token like a dash, so the non-dash column becomes the transaction amount — no new base capability is required.

This is a **determinism / parity** slice (Constitution Principle V): the behaviours are ported faithfully from the proven web engine (`au_bank.py`) and the on-device engine must reproduce the reference ground truth **byte-for-byte** — including the known web-engine narration-stitching behaviour (the wrapped detail lines above and below the anchor, including a trailing footer line, are folded into the adjacent row's narration). The platform boundary is unchanged and fixed by the constitution: **text extraction is native** — on iOS the platform extracts the statement's text lines, its full text, and (for a bank statement) the first transaction row's word geometry, and hands them to the shared engine. **The Rust core never opens a PDF.**

### User Story 1 - Turn an AU savings/current statement into transactions, on-device (Priority: P1)

A person imports their AU Small Finance Bank **savings / current** account statement. The platform extracts the statement's text natively and hands it to the shared engine; the engine recognizes the document as an AU **bank-account** statement and returns the ledger's transactions — each with its date, exact amount, delta-derived debit/credit direction, running balance, and stitched description — computed entirely on the device with no network access. Direction is derived from the running-balance movement, not from the `UPI/DR`/`UPI/CR` text that appears inside the narration.

**Why this priority**: This is the headline value and the smallest slice that turns a real AU bank statement into usable data. It is a viable increment on its own: a person gets their AU savings/current transactions, on-device, exactly as they already can for ICICI, HDFC, and Federal — completing the balance-ledger family across all four target banks. Every subsequent story refines this parse.

**Independent Test**: Provide the engine with the extracted text of the synthetic AU reference statement and confirm it recognizes the document as an AU bank-account statement and returns one transaction per ledger row — each carrying a date, an exact amount, a delta-derived direction, a running balance, and a stitched description — with no network access during the parse.

**Acceptance Scenarios**:

1. **Given** the extracted text of the synthetic AU reference statement, **When** the engine parses it, **Then** it recognizes the document as an AU bank-account statement and returns exactly **two** transactions.
2. **Given** the reference ledger, **When** the engine parses it, **Then** row 1 is dated 2026-03-01, amount 5000.00, direction **debit**, running balance 6570.79; and row 2 is dated 2026-03-02, amount 10000.00, direction **credit**, running balance 16570.79 — all in Indian Rupees.
3. **Given** row 1, **When** it is parsed, **Then** its stitched description is exactly `STORE 1111ref2222tail UPI/DR/000000000001/EXAMPLE ABC0000000001ref MERCHANT/UTIB/0000/UPI AU`.
4. **Given** row 2, **When** it is parsed, **Then** its stitched description is exactly `EMPLOYER 3333ref4444tail UPI/CR/000000000002/EXAMPLE XYZ0000000002ref SALARY/UTIB/0000/UPI AU 1800 1200 1200 www.aubank.in customercare@aubank.in`.
5. **Given** the device has no network connectivity, **When** the statement is parsed, **Then** the transactions are still produced, proving the parse is fully local.

---

### User Story 2 - Direction from the running-balance delta, NEVER from the UPI/DR·UPI/CR text in the narration; the printed amount is an independent check (Priority: P2)

Each transaction's direction (money in vs money out) is decided **solely** by how the running balance moved — a **fall** in the balance is a **debit**, a **rise** is a **credit**. AU prints **no** per-row Dr/Cr direction marker at all. The tokens `UPI/DR` and `UPI/CR` appear **inside the narration**, where they describe the **counterparty's** leg of the UPI transfer — they are ordinary narration text, never a direction signal, and are never consulted to decide direction. The printed amount (the non-dash column) is used only as an **independent integrity check** (it should equal the absolute value of the balance delta within the rounding tolerance). Direction is never inferred from the narration's `UPI/DR`/`UPI/CR` text, from which column (Debit/Credit) an amount sits in, nor from the amount's sign or magnitude.

**Why this priority**: Deriving polarity from the balance movement — and specifically **not** from the `UPI/DR`/`UPI/CR` text embedded in the narration — is the defining rule of the balance-ledger family and the non-negotiable engine invariant for AU. In the reference statement the debit row's narration contains `UPI/DR` and the credit row's narration contains `UPI/CR`, a coincidence that would flip both directions if the narration text were (wrongly) trusted; getting this right is what keeps every downstream total trustworthy.

**Independent Test**: Parse the reference rows whose balance falls and rises, and confirm each is classified debit and credit respectively from the delta — never from the narration text; confirm the printed amount (the non-dash column) reconciles against the delta; confirm flipping the balance movement flips the direction regardless of the printed amount or the narration's `UPI/DR`/`UPI/CR` token.

**Acceptance Scenarios**:

1. **Given** row 1, whose running balance falls from the opening balance (11570.79 → 6570.79), **When** it is parsed, **Then** its direction is **debit** — even though its narration contains `UPI/DR`.
2. **Given** row 2, whose running balance rises (6570.79 → 16570.79), **When** it is parsed, **Then** its direction is **credit** — even though its narration contains `UPI/CR`.
3. **Given** the reference statement, **When** it is parsed, **Then** the ordered directions are **debit** then **credit**, following the balance deltas (−5000.00 then +10000.00) and **not** the narration's `UPI/DR`/`UPI/CR` tokens (which, coincidentally, would suggest the same-then-same reading).
4. **Given** any row, **When** the sign of its balance delta is flipped (by changing the surrounding balances) while its printed amount and its narration's `UPI/DR`/`UPI/CR` text are unchanged, **Then** its direction flips between debit and credit — the direction follows the delta, never the amount, the column, or the narration text.
5. **Given** each row, **When** the printed amount is compared with the balance delta, **Then** it equals the absolute value of the delta within the reused tolerance (row 1: 5000.00 = |−5000.00|; row 2: 10000.00 = |+10000.00|), so the row reconciles and is not a suspect.

---

### User Story 3 - One template with dash-marked empty debit/credit columns: the non-dash side is the amount (Priority: P3)

AU issues its bank-account statement in a **single** template, and one anchor pattern reads it. A transaction line starts with **two** `DD Mon YYYY` dates (a transaction date then a value date), an inline description, then **three** trailing tokens: a **Debit** column, a **Credit** column, and the running **Balance**. **Exactly one** of the Debit/Credit columns carries a money value; the **empty** side prints a literal **dash** (`-`). The transaction amount is the **non-dash** column. The reused base resolves this automatically — its loose two-column amount parser returns *no value* for a non-numeric token like a dash, so the non-dash side becomes the amount — so the dash layout is pure configuration, not a new base capability.

**Why this priority**: Reading AU's single template — and correctly skipping the dash-marked empty column so the non-dash side is the amount — is the core mechanic of the slice. It is delivered purely as configuration on the base's existing two-column amount handling (proven by the Fi/HDFC `0`-empty layout), with the only difference being that AU's empty side is a dash rather than a zero. Proving this keeps AU a drop-in on the same base.

**Independent Test**: Parse the reference statement and confirm each row's amount is taken from the non-dash column (row 1 from the Debit column, row 2 from the Credit column) and that the dash-marked empty column contributes no value; confirm the amount reconciles against the balance delta.

**Acceptance Scenarios**:

1. **Given** a transaction line whose Debit column prints `5,000.00` and whose Credit column prints `-`, **When** it is parsed, **Then** the amount is 5000.00 (the non-dash Debit column), and the dash contributes no value.
2. **Given** a transaction line whose Debit column prints `-` and whose Credit column prints `10,000.00`, **When** it is parsed, **Then** the amount is 10000.00 (the non-dash Credit column), and the dash contributes no value.
3. **Given** the single AU anchor, **When** a transaction line is read, **Then** it matches on **two** leading `DD Mon YYYY` dates followed by a description, a Debit column, a Credit column (each of which is **either** a money token **or** a dash `-`), and the running Balance.
4. **Given** the dash-marked empty column, **When** the amount is resolved, **Then** the printed amount used for the integrity check is the value of the **non-dash** column, and it reconciles against the balance delta.
5. **Given** a per-page column-header line or a header line (neither of which begins with two `DD Mon YYYY` dates), **When** the reader scans it, **Then** it does **not** match the anchor and yields no transaction.

---

### User Story 4 - Opening balance from the parenthesised-currency header, an opening-anchored row 1; the closing-balance header line is a non-transaction whose figure is NOT the printed closing balance (Priority: P4)

The first ledger row has no predecessor balance, so its direction is resolved against the statement's printed **opening balance**, read from the header line `Opening Balance(₹) : 11,570.79`. Because the bracketed currency glyph (`₹`) may extract variably, the opening pattern matches **any** parenthesised group before the figure. Row 1 is **opening-anchored**. The statement also prints a `Closing Balance(₹) : …` header line; this line is recognized as a **non-transaction (balance) line** so it is skipped during narration stitching — but its figure is **not** used as the statement's printed closing balance. The **printed closing balance is the last transaction row's running balance** (16570.79), which differs from the header's printed Closing Balance figure (223.34); the header figure is only used to identify and skip that line during stitching.

**Why this priority**: Row 1 is the one place the delta rule cannot self-start, so a correct opening balance is what anchors the whole chain. AU brackets the currency glyph in its opening/closing labels (which may extract variably), so tolerating any parenthesised group is what makes the fixture reconcile with an auditable `opening_balance` direction source; and pinning the printed closing balance to the last row's running balance (not the header figure) is a correctness requirement the ground truth makes explicit.

**Independent Test**: Parse the reference statement and confirm the opening balance is read as 11570.79 from `Opening Balance(₹) : 11,570.79`; confirm row 1's direction is set from that printed opening balance with `direction_source = opening_balance`; confirm the printed closing balance is 16570.79 (the last row's running balance), not the header's 223.34; and confirm the `Closing Balance(₹) : …` line yields no transaction.

**Acceptance Scenarios**:

1. **Given** the reference statement, **When** it is parsed, **Then** the printed opening balance is 11570.79, read from the `Opening Balance(₹) : 11,570.79` line (any parenthesised currency group tolerated).
2. **Given** the reference statement, **When** row 1 (running balance 6570.79) is bootstrapped, **Then** its delta is computed against the printed opening balance (6570.79 − 11570.79 = −5000.00), so its direction is **debit**, with `direction_source = opening_balance` and no geometry consulted.
3. **Given** the reference statement, **When** any row after the first is bootstrapped, **Then** its direction is derived from its balance delta with `direction_source = balance_delta`.
4. **Given** the reference statement, **When** the printed closing balance is produced, **Then** it is 16570.79 — the **last** transaction row's running balance — **not** the header's printed `Closing Balance(₹) : 223.34` figure.
5. **Given** the `Closing Balance(₹) : …` header line, **When** the statement is parsed, **Then** that line yields **no** transaction and is skipped during narration stitching.
6. **Given** the printed opening balance is present, **When** the balance chain runs, **Then** there is no row-1 direction fallback (neither provisional nor x-position).

---

### User Story 5 - Faithful narration stitching (above + below, including the folded footer), and the non-transaction lines (Priority: P5)

Each row's human-readable **narration** is reassembled deterministically by the reused base — the anchor's inline description plus the wrapped detail lines around it (the line immediately above the anchor plus the lines below it up to the next transaction, skipping other anchors and printed-balance lines). Because this is a **parity** port, the engine must reproduce the **known web-engine stitching behaviour**: the wrapped `UPI/…` reference line printed **above** an anchor is folded into **that** row's narration, and the trailing wrapped detail lines below the last anchor — **including a footer line** (`1800 1200 1200 www.aubank.in customercare@aubank.in`) — are folded into the **last** row's narration. The per-page column headers, the `Opening Balance(₹)` line, and the `Closing Balance(₹)` line are **not** transactions. These stitched strings must be reproduced **byte-for-byte** — the port must **not** "clean them up".

**Why this priority**: This is a determinism/parity slice, and the narration strings are part of the golden ground truth. The web engine stitches the `UPI/…` line above each anchor into that row and folds the trailing footer line into the last row; faithfully reproducing that (rather than "fixing" it) is exactly what parity requires. Excluding the header/opening/closing lines from the transaction list is what keeps the row count correct.

**Independent Test**: Parse the reference statement and confirm each row's stitched description matches the ground-truth string exactly — including row 1's inclusion of the `UPI/DR/…` line printed above its anchor and its `MERCHANT/UTIB/0000/UPI AU` continuation, and row 2's inclusion of the `UPI/CR/…` line above its anchor, its `SALARY/UTIB/0000/UPI AU` continuation, and the trailing footer line `1800 1200 1200 www.aubank.in customercare@aubank.in` — and confirm the column-header, `Opening Balance(₹)`, and `Closing Balance(₹)` lines produce no transactions.

**Acceptance Scenarios**:

1. **Given** the reference statement, **When** row 1 is parsed, **Then** its description is exactly `STORE 1111ref2222tail UPI/DR/000000000001/EXAMPLE ABC0000000001ref MERCHANT/UTIB/0000/UPI AU` — the anchor's inline `STORE 1111ref2222tail`, plus the `UPI/DR/…` line above the anchor, plus the `MERCHANT/UTIB/0000/UPI AU` line below it.
2. **Given** the reference statement, **When** row 2 is parsed, **Then** its description is exactly `EMPLOYER 3333ref4444tail UPI/CR/000000000002/EXAMPLE XYZ0000000002ref SALARY/UTIB/0000/UPI AU 1800 1200 1200 www.aubank.in customercare@aubank.in` — the anchor's inline `EMPLOYER 3333ref4444tail`, plus the `UPI/CR/…` line above the anchor, plus the `SALARY/UTIB/0000/UPI AU` and the trailing footer line below it.
3. **Given** the reference statement, **When** it is parsed, **Then** the column-header lines, the `Opening Balance(₹)` line, and the `Closing Balance(₹)` line yield **no** transactions, and the total row count is exactly **2**.
4. **Given** the trailing footer line `1800 1200 1200 www.aubank.in customercare@aubank.in` (which begins with digit groups but not two `DD Mon YYYY` dates), **When** the reader scans it, **Then** it matches no anchor and is folded into the last row's narration byte-for-byte, not emitted as a transaction.
5. **Given** either row, **When** its stitched description is produced, **Then** it is reproduced byte-for-byte with no trimming, collapsing, reordering, or other normalization.

---

### User Story 6 - Ledger metadata: the billing period and a bank-aware account last-4 (Priority: P6)

Each parsed row carries its ledger metadata (running balance, balance delta, amount-matches-delta, is-suspect, direction source, and serial), and the statement carries its printed opening/closing balances, billing **period**, and account **last-4**. The billing **period** comes from the `Statement Period : 01 Mar 2026 to 31 May 2026` text, whose dates are `DD Mon YYYY`. The account **last-4** comes from AU's account-number pattern (`Account Number` then an optional masked `X*` prefix and 6+ digits), else the longest standalone ≥9-digit run; only the trailing four digits are ever kept — the full account number is never logged or persisted. AU's anchor carries no serial field, so every row's serial is empty.

**Why this priority**: These fields make the ledger auditable and attributable. AU prints its period in the `DD Mon YYYY` format (already known to the shared date parser) and its account number as a long digit run; extracting the period and keeping only the trailing four digits of the account number is a correctness and privacy requirement.

**Independent Test**: Parse the reference statement and confirm it records period 2026-03-01 → 2026-05-31 and account last-4 `0042`; confirm only the trailing four digits are retained; confirm every row's serial is empty.

**Acceptance Scenarios**:

1. **Given** the reference statement, **When** the billing period is extracted, **Then** it is 2026-03-01 → 2026-05-31 — parsed from the `Statement Period : 01 Mar 2026 to 31 May 2026` text (`DD Mon YYYY` dates).
2. **Given** the reference statement's account number (`1234567890120042`), **When** the account last-4 is extracted, **Then** it is `0042`.
3. **Given** the extracted account number, **When** the result is produced, **Then** only the trailing four digits are retained — the full account number is never logged, columned, or persisted.
4. **Given** the AU anchor has no serial field, **When** any row is parsed, **Then** its serial is empty and the row is still returned.
5. **Given** a statement in which a metadata field cannot be found, **When** it is parsed, **Then** that field is left unset rather than fabricated, and the transactions are still returned.

---

### User Story 7 - The document gate claims an AU savings/current statement and rejects a credit-card statement (Priority: P7)

The engine recognizes an AU **bank-account** (savings/current) statement via a document gate that requires the `AU` **bank code** plus the marker **`aubank.in`** and **any** of the account-type markers **`Savings Account`** or **`Current Account`**. A **credit-card** statement — which lacks a savings/current account-type marker — must be **REJECTED** by the AU bank reader. Unlike ICICI, HDFC, and Federal (each of which shares its issuer code with a coexisting credit-card reader), **AU has no credit-card reader in this client**, so the AU bank reader is the sole reader under the `AU` bank code; the rejection is simply the gate correctly declining a document that is not an AU savings/current statement.

**Why this priority**: A correct gate is what keeps the AU bank reader from mis-claiming a non-bank-account document. Requiring both the `aubank.in` marker and a Savings/Current account-type marker is what keeps a credit-card (or other) statement from being misread as a ledger, and confirms the reader claims exactly the AU savings/current statements it should.

**Independent Test**: Ask the bank reader whether it claims the AU reference statement (expect yes) and whether it claims a credit-card statement lacking a Savings/Current marker (expect no); confirm a statement from a different issuer is not claimed.

**Acceptance Scenarios**:

1. **Given** the synthetic AU reference statement, **When** the bank reader's document gate is asked, **Then** it **claims** the document (`AU` code present; `aubank.in` present; a Savings/Current account-type marker present), matched case-insensitively.
2. **Given** a credit-card statement that lacks a Savings/Current account-type marker, **When** the bank reader's document gate is asked, **Then** it does **not** claim the document — the credit-card statement is rejected by the AU bank reader.
3. **Given** a statement from a different issuer (wrong bank code), **When** the bank reader's document gate is asked, **Then** it does **not** claim the document.
4. **Given** a document carrying `aubank.in` but no Savings/Current account-type marker, **When** the bank reader's document gate is asked, **Then** it does **not** claim it (the any-of account-type requirement is unmet).
5. **Given** the AU bank code, **When** the reader registry is inspected, **Then** the AU bank reader is the sole reader under that code (AU has no coexisting credit-card reader in this client).

---

### User Story 8 - A config-on-an-existing-base slice: reuse the base, the balance chain, and the shared account-tail helper — all unchanged, with zero new shared code (Priority: P8)

As a maintainer, this slice is delivered as a **per-issuer configuration** on the existing balance-ledger base — **not** new infrastructure, and with **no** new shared code at all. The reusable base (anchor recognition against an ordered pattern list, delta-derived direction, the printed-amount-as-independent-check including the loose two-column amount resolution that skips a non-numeric dash, narration stitching, the row-1 bootstrap, and the errored-vs-suspect distinction), the **balance-chain check**, **and** the shared **account-tail helper** (per-bank primary account regex, else the longest standalone ≥9-digit run → trailing four) are **reused unchanged**, as are the **parity harness** and the **privacy-egress gate**. AU contributes only its per-issuer configuration (document gate, one anchor pattern, opening/closing/period patterns, and its own account regex fed to the existing helper) plus one golden fixture.

**Why this priority**: The whole point of the slice is to prove the balance-ledger base is genuinely reusable, so the fourth (and final) bank is *just configuration plus fixtures* — the leanest change of the family (a single template, and the dash-empty column handled by the base's existing loose amount parser). Keeping the base, the balance chain, the helper, the harness, and the privacy gate untouched is what keeps the change surgical and completes the family.

**Independent Test**: Confirm the AU bank parse is delivered by a per-issuer configuration plugged into the unchanged base and balance-chain check; confirm the shared account-tail helper is reused (AU supplies only its own primary account regex); confirm the base's existing loose two-column amount parser (which returns no value for a dash) resolves the AU amount with no change; confirm no base internals were modified; confirm this slice adds **no** new shared engine code and **no** new shared helper.

**Acceptance Scenarios**:

1. **Given** the change set, **When** it is reviewed, **Then** the balance-ledger base (anchor recognition, delta-derived direction, amount-as-independent-check including the dash-skipping loose two-column amount resolution, narration stitching, row-1 bootstrap, errored-vs-suspect) is **reused unchanged** — AU contributes only its per-issuer configuration (document gate, one anchor pattern, opening/closing/period patterns, account extractor).
2. **Given** the change set, **When** it is reviewed, **Then** the **balance-chain check** is **reused unchanged**, and reports **RECONCILED** for the AU fixture.
3. **Given** the change set, **When** it is reviewed, **Then** the shared **account-tail helper** (per-bank primary regex, else the longest standalone ≥9-digit run) is **reused unchanged**; AU supplies only its own primary account regex.
4. **Given** the change set, **When** it is reviewed, **Then** the **parity harness** and the **privacy-egress gate** are **reused unchanged** and extended to cover the AU bank path.
5. **Given** the change set, **When** it is reviewed, **Then** this slice adds **no** new shared engine code and **no** new shared helper — only the AU per-issuer configuration and its one golden fixture.

---

### User Story 9 - Proven byte-for-byte against one golden fixture, RECONCILED (Priority: P9)

As a maintainer, the engine's AU bank-account behaviour is pinned to the proven web engine by porting **one** synthetic AU characterization vector into the repository's `fixtures/` directory as a golden vector, and asserting the on-device engine reproduces it exactly: every row's date, amount, direction, stitched description, running balance, delta, amount-matches-delta, is-suspect, direction source, and (empty) serial; the statement's printed opening/closing balances; the billing period; the account last-4; the (empty) errored-lines list; and the **RECONCILED** balance-chain result.

**Why this priority**: Parity is the constitution's acceptance mechanism for the port (Principle V). One fixture turns "we think the AU template matches" into an enforced, regression-proof guarantee, and it extends the existing ledger parity harness to the fourth bank without changing it.

**Independent Test**: Run the parity harness over the ported AU vector and confirm the engine's output matches the expected output exactly, and that re-running produces identical results.

**Acceptance Scenarios**:

1. **Given** the ported AU golden vector, **When** the parity harness runs, **Then** the engine's parsed output matches exactly — row 1 (2026-03-01 / 5000.00 / debit / balance 6570.79 / delta −5000.00 / `direction_source = opening_balance` / empty serial) and row 2 (2026-03-02 / 10000.00 / credit / balance 16570.79 / delta +10000.00 / `direction_source = balance_delta` / empty serial), with their stitched descriptions; printed opening 11570.79 and printed closing 16570.79; period 2026-03-01 → 2026-05-31; account last-4 `0042`; no errored lines; and a **RECONCILED** balance chain (two rows checked, zero suspects, no row-1 fallback, derived opening 11570.79 and derived closing 16570.79).
2. **Given** a change that alters AU bank-account parsing behaviour, **When** the parity harness runs, **Then** it fails, enforcing the parity guarantee.
3. **Given** the golden fixture, **When** it is inspected, **Then** all input and expected data is synthetic or fully redacted (fabricated payers, amounts, and account number) — never real account data.

---

### User Story 10 - Privacy gate and the Swift bridge: zero network, no new dependency, reachable from Swift (Priority: P10)

As a maintainer, the existing automated privacy-egress test covers the AU bank-account import/parse path and asserts it performs no network I/O, and the new reader is reachable over the existing UniFFI bridge to Swift — all with **no new dependency** (and specifically no networking dependency). Money remains an exact decimal (never a float).

**Why this priority**: Privacy is the product's non-negotiable promise and a required constitution gate; being reachable from Swift is what makes the reader usable by the app. Proving both for the fourth bank — with zero new dependencies — completes the balance-ledger family without weakening the guarantee.

**Independent Test**: Run the privacy-egress test against the AU bank-account parse path and confirm it passes only when zero outbound network connections occur; confirm the reader is callable over the UniFFI bridge from Swift; confirm no new runtime (and specifically no networking) dependency was added.

**Acceptance Scenarios**:

1. **Given** the AU bank-account parse path, **When** the automated privacy-egress test runs, **Then** it confirms zero outbound network connections occur during parsing.
2. **Given** a regression that introduces any network access into the parse path, **When** the privacy-egress test runs, **Then** it fails, blocking the change.
3. **Given** the shared engine, **When** the AU bank-account reader is exposed, **Then** it is reachable over the existing UniFFI bridge to Swift (via the existing bank-account parse and claims surface), mirroring ICICI, HDFC, and Federal.
4. **Given** the change set, **When** dependencies are reviewed, **Then** no new runtime dependency — and no networking dependency — is added, and money stays an exact decimal (never a float).

---

### Edge Cases

- **Wrong document type**: A credit-card statement (lacking a Savings/Current account-type marker) is presented to the AU **bank** reader → the bank reader must **not** claim it, so a card statement is never misread as a ledger. AU has no credit-card reader in this client, so the AU bank reader is the sole reader under the `AU` code.
- **Wrong issuer**: A statement from a different issuer (wrong bank code) is presented to the AU bank reader → not claimed.
- **No per-row Dr/Cr marker**: AU prints **no** direction marker on a row. The `UPI/DR`/`UPI/CR` tokens appear only **inside the narration** (the counterparty's leg) and are ordinary narration text; direction is decided by the balance delta. In the reference statement the debit row's narration contains `UPI/DR` and the credit row's contains `UPI/CR` — a coincidence that must not drive direction.
- **Dash-marked empty column**: Each row prints a Debit column and a Credit column where exactly one carries a money value and the empty side prints a dash (`-`); the printed amount for the integrity check is the **non-dash** column (Debit ⇒ the debit figure, Credit ⇒ the credit figure). The reused loose two-column amount parser returns no value for the dash, so the non-dash side becomes the amount.
- **Direction independent of amount, column, and narration text**: A row's balance falls → **debit**; a row's balance rises → **credit**; flipping the delta's sign flips the direction even when the printed amount, the column, and the narration's `UPI/DR`/`UPI/CR` text are unchanged.
- **Printed closing balance is the last row's running balance**: The statement's printed closing balance is the **last transaction row's running balance** (16570.79), **not** the header's printed `Closing Balance(₹)` figure (223.34); the header figure is only used to identify and skip that line during narration stitching.
- **Parenthesised currency glyph**: The `Opening Balance(₹) : …` and `Closing Balance(₹) : …` labels bracket a currency glyph that may extract variably; the opening/closing patterns match **any** parenthesised group before the figure.
- **Footer folded into the last row**: The trailing footer line (`1800 1200 1200 www.aubank.in customercare@aubank.in`) begins with digit groups but not two `DD Mon YYYY` dates, so it matches no anchor; it is folded into the last row's narration byte-for-byte, not emitted as a transaction.
- **Non-transaction lines**: Per-page column headers, the `Opening Balance(₹)` line, and the `Closing Balance(₹)` line are not transactions.
- **Empty serial**: AU's anchor carries no serial field, so every row's serial is empty; the rows are still returned.
- **Indian money formatting**: Amounts/balances with thousands separators, including the Indian grouping style → parsed to exact, non-negative decimals with stated precision preserved.
- **Amount ≠ |delta| (chain break)**: A row whose printed amount differs from the absolute balance delta by more than the rounding tolerance → marked a **suspect**; the balance chain reports **NEEDS_REVIEW**; the row is **still returned**, never dropped. (The AU fixture reconciles within tolerance and produces zero suspects.)
- **Unparseable anchor-shaped row**: A line matching the anchor's shape but whose date/amount/balance will not parse → captured as an **errored line** (bounded length); every good row is still returned; it is **not** a suspect. (The AU fixture has zero errored lines.)
- **No column split for AU**: AU supplies no column-split x-position, so the row-1 x-position geometry path is **not** exercised by this slice (the fixture is opening-anchored).
- **Missing metadata**: No recognizable opening/closing balance, period, or account number → the corresponding field is left unset rather than fabricated; transactions are still returned.
- **No transaction lines**: Empty input, or input with no recognizable anchor rows → an empty transaction list is returned with no error.
- **Repeated / concurrent parses**: The same input parsed repeatedly → identical results every time, with no dependence on wall-clock time, locale, or hidden global state.

## Requirements *(mandatory)*

### Functional Requirements

**Document recognition (the savings/current gate)**

- **FR-001**: The engine MUST recognize a statement as an AU **bank-account** (savings/current) statement via a document gate that requires the `AU` **bank code**, the marker **`aubank.in`**, and **any** of the account-type markers **`Savings Account`** or **`Current Account`** — matched case-insensitively.
- **FR-002**: The AU bank reader MUST NOT claim a **credit-card** statement (which lacks a Savings/Current account-type marker), and MUST NOT claim a statement from a different issuer (wrong bank code). AU has **no** credit-card reader in this client, so the AU bank reader is the sole reader under the `AU` bank code.

**One statement template with dash-marked empty columns (configuration on the existing base)**

- **FR-003**: The single AU bank reader MUST recognize a transaction via **one** anchor pattern supplied to the existing base's ordered anchor mechanism — introducing **no** new base capability.
- **FR-004**: The anchor MUST match a transaction line beginning with **two** `DD Mon YYYY` dates (a transaction date and a value date), followed by an inline **description**, then a **Debit** column, a **Credit** column, and the running **Balance** — where each of the Debit/Credit columns is **either** a money token **or** a literal dash (`-`), and the running Balance is always a money token — capturing the **date**, the inline **description**, the **debit** column, the **credit** column, and the **balance**.
- **FR-005**: The engine MUST resolve the transaction **amount** as the **non-dash** of the Debit/Credit column pair, reusing the base's loose two-column amount resolution (which returns no value for a non-numeric token like a dash, so the non-dash column becomes the amount). AU introduces **no** new amount-parsing capability.

**Direction from the running-balance delta; the narration text is not a direction signal; amount as an independent check**

- **FR-006**: The engine MUST derive each transaction's debit/credit **direction** from the **running-balance delta**: a **fall** (delta < 0) is a **debit**, a **rise** (delta > 0) is a **credit**. Direction MUST NEVER be inferred from the `UPI/DR`/`UPI/CR` text that appears inside the narration (which denotes the **counterparty's** leg), nor from the sign or magnitude of the printed amount, nor from which column (Debit/Credit) a figure is printed in.
- **FR-007**: The engine MUST treat the `UPI/DR`/`UPI/CR` tokens as **ordinary narration text** with **no** bearing on direction. In the reference statement the debit row's narration contains `UPI/DR` and the credit row's contains `UPI/CR`; the ordered directions (debit then credit) MUST follow the balance deltas, not those tokens.
- **FR-008**: The engine MUST treat the printed **amount as an INDEPENDENT integrity check**: a row **reconciles** when the printed amount (the non-dash column) equals the absolute value of the balance delta within the reused rounding tolerance, otherwise it is a **suspect**.
- **FR-009**: A **suspect** row (printed amount does not match its balance delta) MUST still be **returned** (flagged), never silently dropped; the engine MUST record per row whether the amount matches the delta (`amount_matches_delta`) and whether the row is a suspect (`is_suspect`). The AU reference fixture reconciles (zero suspects).

**Amount**

- **FR-010**: The engine MUST parse each amount and each running balance as an exact **decimal**, honouring Indian number formatting (thousands separators, including the Indian grouping style), preserving stated precision. Monetary values MUST NEVER be represented as floating-point numbers.

**Opening/closing balance and row-1 bootstrap**

- **FR-011**: The engine MUST read the printed **opening balance** from the `Opening Balance(₹) : 11,570.79` header line, tolerating the bracketed currency glyph by matching **any** parenthesised group before the figure — resolving to 11570.79.
- **FR-012**: The engine MUST recognize the `Closing Balance(₹) : …` header line as a **non-transaction (balance) line** (so it is skipped during narration stitching), tolerating **any** parenthesised group before the figure. This line's figure MUST NOT be emitted as a transaction.
- **FR-013**: The statement's **printed closing balance** MUST be the **last** transaction row's running balance (16570.79), **not** the header's printed `Closing Balance(₹)` figure (223.34). The header closing figure is used only to identify and skip that line during narration stitching.
- **FR-014**: For the **first** ledger row, the engine MUST anchor direction against the printed opening balance (`direction_source = opening_balance`), reusing the base's unchanged row-1 bootstrap precedence; every row after the first MUST be `balance_delta`. AU supplies **no** column-split x-position, so the row-1 x-position geometry path is not exercised by this slice.

**Narration stitching (faithful parity) and the non-transaction lines**

- **FR-015**: The engine MUST reassemble each row's **description (narration)** using the reused base's narration stitching (the anchor's inline description plus the wrapped detail line immediately above the anchor and the detail lines below it up to the next transaction, skipping other anchors and printed-balance lines), and MUST reproduce the known web-engine behaviour where the wrapped `UPI/…` reference line printed above an anchor is folded into that row's narration and where the trailing wrapped detail lines below the last anchor — **including the footer line** `1800 1200 1200 www.aubank.in customercare@aubank.in` — are folded into the **last** row's narration. These stitched strings MUST be reproduced **byte-for-byte**; the port MUST NOT trim, collapse, reorder, or otherwise "clean up" the stitched text.
- **FR-016**: The engine MUST NOT emit a transaction for a non-transaction line: the per-page **column-header** lines, the **`Opening Balance(₹)`** line, and the **`Closing Balance(₹)`** line are not transactions. The AU statement yields exactly **2** transactions.

**Per-row and statement-level ledger metadata**

- **FR-017**: Each parsed row MUST carry: the transaction **date**, the exact **amount**, the delta-derived **direction**, the currency (INR), the stitched **description**, the running **balance**, the **balance delta**, `amount_matches_delta`, `is_suspect`, `direction_source`, and the **serial** (empty for AU, whose anchor carries no serial field).
- **FR-018**: The statement MUST carry: the **printed opening balance**, the **printed closing balance**, the **billing period** (start and end), and the account **last-4**.
- **FR-019**: The engine MUST derive the billing **period** from the `Statement Period : <start> to <end>` text, whose dates are `DD Mon YYYY` (e.g. `01 Mar 2026 to 31 May 2026`), resolving to 2026-03-01 → 2026-05-31.
- **FR-020**: The engine MUST derive the account **last-4** from AU's account-number pattern — `Account Number` followed by an optional masked `X*` prefix and 6 or more digits (matching `1234567890120042`) — else from the longest standalone **≥9-digit** run; and MUST retain **only** the trailing four digits (`0042`). The full account number MUST NEVER be logged, columned, or persisted.
- **FR-021**: When a metadata field cannot be found, the engine MUST leave it unset rather than fabricate a value, and MUST still return the parsed transactions.

**Reuse of the existing base and shared helpers — with zero new shared code**

- **FR-022**: This slice MUST **reuse unchanged** the existing balance-ledger reader base (anchor recognition against an ordered pattern list, delta-derived direction, the printed-amount-as-independent-check including the loose two-column amount resolution that skips a non-numeric dash, narration stitching, the row-1 bootstrap, and the errored-vs-suspect distinction) and the **balance-chain integrity check** — AU is added only as a **per-issuer configuration** (document gate, one anchor pattern, opening/closing/period patterns, account extractor).
- **FR-023**: This slice MUST **reuse unchanged** the shared **account-tail helper** (a per-bank primary account regex, else the longest standalone ≥9-digit run, returning the trailing four digits) — AU supplies only its own primary account regex. This slice MUST NOT add any new shared helper.
- **FR-024**: This slice MUST **reuse unchanged** the golden-fixture **parity harness** and the **privacy-egress gate**, extending them to cover the AU bank path.
- **FR-025**: This slice MUST reuse the existing shared money/date/currency/direction conventions and helpers (Indian-format decimal parsing; the shared date parser, which already carries the `DD Mon YYYY` (`%d %b %Y`) format; the explicit `Direction` type). This slice MUST add **no** new shared engine internals and **no** new date format.

**Balance-chain integrity (reused)**

- **FR-026**: The engine MUST run the reused **balance-chain integrity check** over the parsed AU ledger and report **RECONCILED** for the reference fixture (every row reconciles within tolerance and there is no un-trusted row-1 bootstrap), with two rows checked, zero suspects, no row-1 direction fallback, a derived opening balance of 11570.79, and a derived closing balance of 16570.79.

**Engine purity, platform boundary & bridge**

- **FR-027**: The engine's AU bank-account parse MUST accept already-extracted text lines, the full statement text, and the first-row word geometry, and return the parsed result; it MUST NOT read files, extract PDF text, or embed a PDF engine (text and geometry extraction are native platform concerns). The Rust core MUST NEVER open a PDF.
- **FR-028**: The engine MUST remain pure and deterministic: identical input MUST yield identical output, with no dependence on network, wall-clock time, locale, or hidden global mutable state.
- **FR-029**: The engine MUST expose the AU bank-account reader over the existing **UniFFI** bridge via the existing bank-account parse and claims surface, reachable from Swift, mirroring the ICICI, HDFC, and Federal bank-account readers.

**Privacy (constitution Principle I — NON-NEGOTIABLE)**

- **FR-030**: The entire AU bank-account import/parse path MUST run 100% on-device with ZERO network I/O.
- **FR-031**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting into the engine or the app, and MUST NOT add any **networking** dependency.
- **FR-032**: The existing automated privacy-egress test MUST cover the AU bank-account parse path and assert it performs no network access; it remains a required constitution gate.

**Parity & test-first (constitution Principle V)**

- **FR-033**: The web engine's synthetic AU characterization vector MUST be ported into the repository's `fixtures/` directory (AU bank-account subtree) as a golden vector, and the engine MUST reproduce it exactly (rows with dates/amounts/directions/stitched-descriptions/balances/deltas/empty-serials, printed opening/closing balances, billing period, account last-4, the empty errored-lines list, and the RECONCILED balance-chain result).
- **FR-034**: All fixture and test data MUST be synthetic or fully redacted (fabricated payers, amounts, and account number) — never real account data.
- **FR-035**: The AU bank-account parsing behaviour introduced by this slice MUST be developed test-first (a failing golden test precedes the behaviour).

**Licensing, secrets & quality gates**

- **FR-036**: The change MUST NOT add secrets, API keys, or private endpoints; MUST remain distributable under Apache-2.0 with no copyleft (GPL/AGPL/LGPL) dependencies; and MUST introduce **no new runtime dependency** for this slice.
- **FR-037**: The change MUST keep the iOS Local Verification Gate and CI green: core formatting, linting, and tests; app linting; project generation; a simulator build with passing app tests; and the privacy gate. If any user-facing surface is introduced, it MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility.

### Key Entities *(include if feature involves data)*

- **Extracted statement input**: The already-extracted text lines, the full statement text, and the first transaction row's word geometry handed to the engine by the native platform. Contains no PDF binary; the engine never opens a PDF.
- **AU statement template (single)**: The one recognized AU bank-account row format — two leading `DD Mon YYYY` dates, an inline description, a Debit column, a Credit column (exactly one of which carries a money value; the empty side prints a dash `-`), and the running Balance. AU prints **no** per-row Dr/Cr direction marker.
- **Parsed ledger row**: One ledger transaction — a transaction date, an exact non-negative amount (the non-dash column), a delta-derived direction, a currency (INR), a stitched description, the running balance, the balance delta, an amount-matches-delta indicator, an is-suspect indicator, a direction source, and a serial (empty for AU).
- **Parsed bank statement result**: The full output of reading one AU bank-account statement — the bank identity and account kind, the list of parsed ledger rows, the list of errored (unparseable) lines, the printed opening balance, the printed closing balance (the last row's running balance), the billing period (start/end), the account last-4, and the balance-chain result.
- **Dash-marked empty column**: The literal `-` printed in whichever of the Debit/Credit columns does not carry the transaction amount; the reused loose amount parser returns no value for it, so the non-dash column becomes the amount.
- **UPI/DR·UPI/CR counterparty text**: The `UPI/DR`/`UPI/CR` tokens printed **inside** the narration, describing the counterparty's leg of the transfer — ordinary narration text that never decides this account's direction.
- **Direction (polarity)**: An explicit debit or credit indicator carried on every transaction, sourced from the running-balance delta (and, for row 1, from the printed opening balance) — never from the narration text, the amount's sign, or the printed column.
- **Balance-chain result**: A statement-level status of RECONCILED or NEEDS_REVIEW, with the list of suspect rows — reused unchanged; RECONCILED for the AU fixture.
- **`direction_source`**: How a row's direction was decided — `opening_balance` for row 1; `balance_delta` for every later row.
- **Account-tail helper (reused, unchanged)**: The shared helper — a per-bank primary account regex, else the longest standalone ≥9-digit run, returning the trailing four digits — reused by AU with its own primary regex; no new shared helper is added.
- **Golden characterization vector**: One synthetic AU input (text lines + full text) paired with its expected engine output, stored under `fixtures/`, ported from the web engine and reproduced exactly by the on-device engine.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The synthetic AU reference statement parses byte-for-byte to the ground truth on-device — row 1 (2026-03-01 / 5000.00 / debit / balance 6570.79 / delta −5000.00 / empty serial / `direction_source = opening_balance`) and row 2 (2026-03-02 / 10000.00 / credit / balance 16570.79 / delta +10000.00 / empty serial / `direction_source = balance_delta`), with their stitched descriptions (100% match).
- **SC-002**: The reused balance-chain check reports **RECONCILED** for the AU reference statement — two rows checked, zero suspects, no row-1 direction fallback, derived opening 11570.79 and derived closing 16570.79.
- **SC-003**: Direction is **delta-derived** across every tested case, and **never** taken from the `UPI/DR`/`UPI/CR` text in the narration: the debit row's narration contains `UPI/DR` and the credit row's contains `UPI/CR`, yet the directions follow the deltas (debit then credit); and a row's direction **flips when its balance delta flips**, independent of the printed amount, column, or narration text.
- **SC-004**: The dash-marked empty column is correctly skipped so the printed **amount** is the **non-dash** column (5000.00 from the Debit column for row 1; 10000.00 from the Credit column for row 2), and each amount reconciles against the two-decimal balance delta.
- **SC-005**: The narration for every row is stitched **byte-for-byte** to the ground truth — including row 1's folded `UPI/DR/…` reference line and `MERCHANT/UTIB/0000/UPI AU` continuation, and row 2's folded `UPI/CR/…` reference line, `SALARY/UTIB/0000/UPI AU` continuation, and trailing footer line `1800 1200 1200 www.aubank.in customercare@aubank.in` — with no normalization applied; the column-header, `Opening Balance(₹)`, and `Closing Balance(₹)` lines produce no transactions, so the statement yields exactly 2 rows.
- **SC-006**: The bank reader **claims** the AU reference statement and **rejects** a credit-card statement lacking a Savings/Current account-type marker — 0 misroutes across the recognition cases; the AU bank reader is the sole reader under the `AU` bank code.
- **SC-007**: The statement records `printed_opening_balance = 11570.79`, `printed_closing_balance = 16570.79` (the last row's running balance, **not** the header's `Closing Balance(₹) : 223.34`), billing **period** 2026-03-01 → 2026-05-31, and account **last-4 `0042`** — retaining only the trailing four digits.
- **SC-008**: The base, the balance-chain check, the shared account-tail helper, the parity harness, and the privacy-egress gate are reused **unchanged**; this slice adds **no** new shared engine code, **no** new shared helper, and **no** new dependency — only the AU per-issuer configuration and its one golden fixture.
- **SC-009**: 100% of parsed amounts and balances are exact **decimals** with stated precision preserved; **no monetary value is ever a floating-point number**.
- **SC-010**: Zero outbound network connections occur during the entire AU bank-account parse path, verified by the automated privacy-egress test, and **no new runtime (or networking) dependency** is added.
- **SC-011**: The whole reader is reachable over the **UniFFI bridge to Swift** (via the existing bank-account parse and claims surface), mirroring ICICI, HDFC, and Federal.
- **SC-012**: Given identical input, the engine returns identical output across repeated runs (100% reproducible); the ported golden vector reproduces exactly and the parity harness passes.
- **SC-013**: All automated checks required to merge pass (green), including the parity harness and the privacy-egress test, with the iOS Local Verification Gate and CI green; and no secrets or copyleft-licensed dependencies are added (verified by review of manifests and dependencies).

## Assumptions

- **Config-on-an-existing-base, not new infrastructure**: The balance-ledger reader base (anchor recognition against an ordered pattern list + narration stitching + delta-derived direction + the amount-vs-delta integrity check including the loose two-column amount resolution + row-1 bootstrap + errored-vs-suspect), the balance-chain integrity check, **and** the shared account-tail helper already exist (from the ICICI reference and the HDFC/Federal drop-in slices) and are reused **unchanged**. AU is added as a per-issuer configuration plus one golden fixture.
- **The base already supports the dash-marked empty column**: The base resolves a two-column debit/credit amount pair by taking the non-empty side, and its loose amount parser returns *no value* for a non-numeric token like a dash — so AU's dash-empty column is configuration, not a new base capability (proven analogously by the Fi/HDFC `0`-empty layout). AU's amount is the non-dash column.
- **Zero new shared code**: This slice adds **no** new shared engine code and **no** new shared helper — the account-tail helper it needs already exists in the shared common module. The AU reader supplies only its own primary account regex. The exact module placement of the AU configuration and the UniFFI surface names are finalized in `/speckit.plan`.
- **Anchor pattern (ported characterization, realized in `/speckit.plan`)**: The single anchor matches a `DD Mon YYYY` line with a transaction date and a value date, an inline description, a Debit column and a Credit column (each **either** a money token **or** a dash `-`), and the running Balance. Ported faithfully from the web engine's `au_bank.py` pattern; the exact regex realization is finalized in `/speckit.plan`. Illustratively (finalized in the plan): `^(?P<date>\d{2} [A-Za-z]{3} \d{4})\s+\d{2} [A-Za-z]{3} \d{4}\s+(?P<desc>.*?)\s*(?P<withdrawal>[\d,]+\.\d{2}|-)\s+(?P<deposit>[\d,]+\.\d{2}|-)\s+(?P<balance>[\d,]+\.\d{2})\s*$` — where the base's named `withdrawal`/`deposit` groups carry AU's Debit/Credit columns.
- **Opening/closing-balance patterns (ported characterization)**: The opening pattern reads `Opening Balance(₹) : 11,570.79`, tolerating the bracketed currency glyph by matching any parenthesised group before the figure — illustratively `Opening Balance\s*\([^)]*\)\s*:?\s*([\d,]+\.\d{2})` — resolving to 11570.79. A closing pattern of the same shape (`Closing Balance\s*\([^)]*\)\s*:?\s*([\d,]+\.\d{2})`) is supplied **only** so the `Closing Balance(₹)` line is recognized as a non-transaction (balance) line and skipped during stitching; it is **not** used to set the printed closing balance. Realized in `/speckit.plan`.
- **Printed closing balance is the last row's running balance**: By the reused base's rule, the statement's printed closing balance is the last transaction row's running balance (16570.79), independent of any `Closing Balance` header figure (223.34). The AU closing pattern exists purely for narration-skip purposes.
- **Period & account patterns (ported characterization)**: The period is `Statement Period\s*:?\s*(\d{2} [A-Za-z]{3} \d{4})\s+to\s+(\d{2} [A-Za-z]{3} \d{4})` (`DD Mon YYYY` dates); the account last-4 is AU's account-number pattern (illustratively `Account\s+Number\s*:?\s*X*([0-9]{6,})`), else the longest ≥9-digit run, keeping only the trailing four. Realized in `/speckit.plan`.
- **No per-row Dr/Cr marker; the narration's UPI/DR·UPI/CR is the counterparty's leg**: An AU ledger prints **no** direction marker on a row (unlike Federal's trailing `Cr`/`Dr`). The `UPI/DR`/`UPI/CR` tokens appear only inside the narration and describe the counterparty's leg of the UPI transfer; they are ordinary narration text and never decide this account's direction, which is always taken from the balance delta. This is the defining AU twist versus Federal (which prints a consumed-but-ignored balance-sign marker) and versus a credit-card `Dr`/`Cr` line (which does decide direction).
- **Empty serial**: AU's anchor carries no serial field, so every row's serial is empty; the rows are still returned. (Unlike Federal's optional `S`-prefixed Tran ID.)
- **Narration-stitching quirk is faithful, not a bug to fix**: The web engine stitches the `UPI/…` reference line printed above an anchor into that row's narration and folds the trailing wrapped detail lines — including the footer line `1800 1200 1200 www.aubank.in customercare@aubank.in` — into the last row's narration. The port reproduces these byte-for-byte; the golden fixture pins them.
- **The column-header, Opening Balance, and Closing Balance lines are not transactions**: None begins with two `DD Mon YYYY` dates, so none matches the anchor. The statement yields exactly 2 transactions.
- **Rounding tolerance & suspect/errored semantics are reused**: The amount-vs-delta tolerance, the suspect-vs-errored distinction, and the RECONCILED / NEEDS_REVIEW statuses are inherited unchanged from the base and balance-chain check. The AU fixture reconciles (zero suspects, zero errored lines).
- **No column split for AU**: AU supplies no column-split x-position, so the row-1 x-position geometry path is supported by the base but **not** exercised by this slice; the fixture is opening-anchored.
- **Reader identity and the bank code**: The reader is the AU **bank-account** reader under a **new** `AU` bank code. Unlike ICICI/HDFC/Federal (which share their issuer code with a coexisting credit-card reader), AU has no credit-card reader in this client, so the AU bank reader is the sole reader under the `AU` code; the registry is keyed by `(bank_code, account_kind)`. The exact identity/surface strings are finalized in `/speckit.plan`.
- **Date parser needs no change**: The shared date parser already carries the `DD Mon YYYY` (`%d %b %Y`) format, so no new date format is added.
- **Parse seam & platform boundary**: The bank-account seam is the existing one — already-extracted text lines, the full text, and the first transaction row's word geometry — returning the parsed result. The native platform (iOS PDFKit) performs the text and geometry extraction; the Rust core never opens a PDF.
- **Binding**: The reader is exposed to Swift via the existing UniFFI bridge through the existing bank-account parse and claims surface, mirroring ICICI, HDFC, and Federal; concrete binding mechanics belong in `/speckit.plan`.
- **Fixtures location**: The one golden fixture lives under the AU bank-account fixtures subtree (e.g. `fixtures/au/bank_account/`) and is the source of truth for parity; the exact path and file name are finalized in `/speckit.plan`.
- **No new dependencies**: This slice requires **no** new runtime dependencies, and specifically **no** networking dependency.
- **Source of truth**: The web engine is the source of truth for behaviour — the AU bank reader `au_bank.py` plus the shared balance-ledger reader, the balance-chain check, and the shared common/polarity helpers, and the bank-account characterization/parity test. A captured JSON ground-truth artifact (one reference fixture, reconciled) accompanies this slice. The porting approach (module layout, pattern, fixture format, UniFFI exports) is decided in `/speckit.plan`, not here.
- **Synthetic characterization vector**: The one synthetic statement and its expected output — the rows (2026-03-01 / 5000.00 / debit; 2026-03-02 / 10000.00 / credit) with empty serials, their balances (6570.79, 16570.79) and deltas (−5000.00, +10000.00), stitched descriptions, printed opening/closing balances (11570.79 / 16570.79), billing period (2026-03-01 → 2026-05-31), account last-4 (`0042`), the empty errored-lines list, and the RECONCILED balance-chain result — is the constitution's golden-fixture parity vector (Principle V), confirmed against the web engine, all synthetic/redacted.
- **No new UI required**: This is an engine slice; no user-facing UI is required to deliver it. App-side PDF text/geometry extraction (PDFKit wiring), the file-import UI, and the Share Extension remain a native concern and a later step. If a trivial demo surface is added, it follows HIG and accessibility (FR-037).
- **Data safety**: All fixture and test data is synthetic or fully redacted — no real account data.
- **Money & geometry types**: Amounts and balances are exact decimals (never floating-point) and direction is carried explicitly and derived from the balance delta; geometry x-coordinates are layout points (not money) and may be floating-point.

### Dependencies

- **Kaname Constitution v1.0.0** — privacy (zero-network free/core), determinism, a pure platform-agnostic core (no PDF engine), decimal money with explicit polarity, Apache-2.0 open-core with no copyleft, native HIG/accessibility, and the test-first iOS Local Verification Gate (including the privacy-egress gate).
- **The ICICI bank-account (balance-ledger) reference slice (already landed)** — the reusable balance-ledger reader base (anchor recognition against an ordered pattern list, delta-derived direction, amount-as-independent-check including the loose two-column amount resolution, narration stitching, row-1 bootstrap, errored-vs-suspect), the balance-chain integrity check, the ledger parity harness, the bank-account UniFFI surfaces, and the privacy-egress gate — all reused unchanged by this slice.
- **The HDFC bank-account drop-in slice (already landed)** — the shared **account-tail helper** (per-bank primary account regex, else the longest standalone ≥9-digit run → trailing four) in the shared common module, and the proof that two-column withdrawal/deposit amounts (empty side skipped) are pure configuration — both reused unchanged by this slice.
- **The Federal bank-account drop-in slice (already landed)** — the second proof that a new bank is just configuration plus fixtures on this base; not modified by this slice.
- **The credit-card and prior bank slices (already landed)** — the shared reader output types (parsed statement / parsed transaction), the Indian-format amount parser, the shared multi-format date parser (which already carries the `DD Mon YYYY` (`%d %b %Y`) format), the shared `Direction` type and polarity module, and the golden-fixture parity harness — reused by this slice.
- **The Rust↔Swift bridge (already landed)** — the shared engine crate and the UniFFI Swift binding proven end-to-end, over which the bank-account parse and claims functions are exposed.
- **Web engine golden vector** — the one synthetic AU bank characterization vector and the `au_bank.py` behaviour used as the parity source of truth, plus the captured JSON ground-truth artifact.

## Out of Scope

Deferred to later P2 slices / milestones:

- **The other bank-account ledger readers** — the **ICICI**, **HDFC**, and **Federal** readers (already landed); AU is the fourth and **final** bank on this base, so no further bank-account readers are planned in this family after this slice.
- **Reconciliation of printed debit/credit totals** (e.g. any printed total figures), **coverage / billing-period timeline**, and **cross-source de-duplication and transfer detection** — separate later concerns; this slice delivers the balance-**chain** integrity check (reused), not printed-total reconciliation.
- **Real-PDF geometry calibration** — AU sets no column-split x-position, so the row-1 x-position path is not exercised here; provisional/x-position rows (not present in this fixture) are surfaced NEEDS_REVIEW, never silently trusted.
- **Persistence** — encrypted SQLite / SQLCipher storage and key management.
- **AI-fallback parsing**.
- Any **premium / cloud features**.
- **App-side PDF text/geometry extraction** (PDFKit wiring in the app) and the **file-import UI / Share Extension** — native concerns handled in a later slice. This slice focuses on the AU bank-account configuration on the existing balance-ledger base plus its golden-fixture parity, reusing the existing balance chain, the shared account-tail helper, the parity harness, and the privacy gate, exposed over the existing bridge.
