# Feature Specification: Read a Federal Bank (Savings/Current) Statement On-Device — the Third Balance-Ledger Reference Reader (Federal Config on the Existing Ledger Base, Two Statement Templates, a Consumed-but-Ignored Cr/Dr Marker)

**Feature Branch**: `009-federal-bank-ledger-reader`  
**Created**: 2026-07-17  
**Status**: Draft  
**Milestone**: P2 — Engine port; the **third** bank-account (balance-ledger) reader, after the **ICICI** reference reader (which landed the reusable base) and the **HDFC** drop-in  
**Input**: User description: "Federal Bank savings/current statement reading for the on-device Kaname core — the THIRD bank-account (balance-ledger) reader, after the ICICI reference and HDFC. Federal bank statements are running-balance ledgers; the printed Cr/Dr marks the BALANCE's sign, NOT the transaction, so direction is still derived from the running-balance delta. Federal issues two statement templates, both handled by one reader via first-match-wins anchors: (1) a CLASSIC (direct Federal Bank) layout — DD-MON-YYYY dates, a single printed amount then the running balance and a trailing Cr/Dr (consumed but ignored); an optional S-prefixed Tran ID is captured as the serial and kept OUT of the description; and (2) a NEOBANK / Fi (Epifi) layout — DD/MM/YYYY dates with both Withdrawal and Deposit columns printed (the empty side is 0), amounts that may be WHOLE NUMBERS (e.g. 5000, 50000), then the balance and Cr/Dr. This slice adds the Federal configuration of the existing balance-ledger base plus its golden fixtures; it reuses the base, the balance-chain check, the shared account_tail_last4 helper, the parity harness and the privacy gate unchanged."

> **Note on priority labels**: This feature is milestone **P2** (Engine port) in the product roadmap (`docs/kaname-ios-plan.md` §9). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P2" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

Two prior bank-account slices landed the **balance-ledger reader family** and its base: a **reusable balance-ledger base** (anchor recognition against an ordered pattern list, delta-derived direction, the printed-amount-as-independent-check, narration stitching, the row-1 bootstrap, and the errored-vs-suspect distinction), the **balance-chain integrity check**, the **golden-fixture parity harness** extended to ledgers, a shared **account-tail helper** (per-bank primary account regex, else the longest standalone ≥9-digit run → trailing four), and two configurations on that base — **ICICI** (the reference) and **HDFC** (the first drop-in, proving two export layouts are pure configuration). This slice delivers the **third** bank on that same base — **Federal** — and proves again that a new bank is *just configuration plus fixtures*: a person imports their Federal **savings / current** account statement and the app produces the ledger's transactions (date, exact amount, delta-derived debit/credit direction, running balance, and stitched description) entirely on-device, with no network and no account, exactly as it already does for ICICI and HDFC.

This is a **config-on-an-existing-base** slice, not new infrastructure — and it is **even leaner** than the HDFC drop-in: the reusable balance-ledger base, the balance-chain check, **and** the shared account-tail helper **already exist and are reused unchanged**; Federal is added purely as a **per-issuer configuration** (its own document gate, its two anchor patterns, its opening-balance and period patterns, and its account-number extractor) plus **golden fixtures**. This slice introduces **zero** new shared engine code, **zero** new shared helpers, and **zero** new dependencies.

Like HDFC, Federal reads **two different statement templates behind a single reader** — a **classic** (direct Federal Bank) layout and a **neobank / Fi (Epifi)** layout — selected by **first-match-wins anchor patterns**, so the caller never knows or chooses which template applied. This capability is already supported by the base (it recognizes a transaction against an **ordered list** of per-issuer anchor patterns).

Federal's distinctive twist is the **trailing `Cr`/`Dr` marker that must be consumed but ignored**. Unlike ICICI/HDFC (which print no marker at all), a Federal ledger prints a `Cr`/`Dr` at the end of every row — but that marker denotes the **running balance's sign** (the account being in credit/debit), **not** the transaction's direction. Direction is therefore **still** derived from the running-balance delta, exactly as for ICICI and HDFC; the trailing marker is matched by the anchor and discarded. In the reference statements every row prints "Cr", yet the rows are a mix of debits and credits.

This is a **determinism / parity** slice (Constitution Principle V): the behaviours are ported faithfully from the proven web engine (`federal_bank.py`) and the on-device engine must reproduce the two reference ground truths **byte-for-byte** — including the known web-engine narration-stitching quirks (a transaction's own wrapped continuation line, and a trailing `GRAND TOTAL` line, are folded into an adjacent row's narration). The platform boundary is unchanged and fixed by the constitution: **text extraction is native** — on iOS the platform extracts the statement's text lines, its full text, and (for a bank statement) the first transaction row's word geometry, and hands them to the shared engine. **The Rust core never opens a PDF.**

### User Story 1 - Turn a Federal savings/current statement into transactions, on-device (Priority: P1)

A person imports their Federal **savings / current** account statement. The platform extracts the statement's text natively and hands it to the shared engine; the engine recognizes the document as a Federal **bank-account** statement and returns the ledger's transactions — each with its date, exact amount, delta-derived debit/credit direction, running balance, and stitched description — computed entirely on the device with no network access. Direction is derived from the running-balance movement, not from the trailing `Cr`/`Dr` marker (which denotes the balance's sign).

**Why this priority**: This is the headline value and the smallest slice that turns a real Federal bank statement into usable data. It is a viable increment on its own: a person gets their Federal savings/current transactions, on-device, exactly as they already can for ICICI and HDFC — extending the balance-ledger family to a third bank. Every subsequent story refines this parse.

**Independent Test**: Provide the engine with the extracted text of the synthetic Federal **classic** reference statement and, separately, the synthetic Federal **Fi (neobank)** reference statement, and confirm it recognizes each as a Federal bank-account statement and returns one transaction per ledger row — each carrying a date, an exact amount, a delta-derived direction, a running balance, and a stitched description — with no network access during the parse.

**Acceptance Scenarios**:

1. **Given** the extracted text of the synthetic Federal **classic** reference statement, **When** the engine parses it, **Then** it recognizes the document as a Federal bank-account statement and returns exactly **three** transactions.
2. **Given** the extracted text of the synthetic Federal **Fi** reference statement, **When** the engine parses it, **Then** it recognizes the document as a Federal bank-account statement and returns exactly **two** transactions.
3. **Given** the **classic** reference ledger, **When** the engine parses it, **Then** row 1 is dated 2026-04-08, amount 5000.00, direction **debit**, running balance 95000.00; row 2 is dated 2026-04-11, amount 50000.00, direction **credit**, running balance 145000.00; and row 3 is dated 2026-04-13, amount 45000.00, direction **debit**, running balance 100000.00 — all in Indian Rupees.
4. **Given** the **Fi** reference ledger, **When** the engine parses it, **Then** row 1 is dated 2026-04-08, amount 5000, direction **debit**, running balance 95000.00; and row 2 is dated 2026-04-20, amount 50000, direction **credit**, running balance 145000.00 — all in Indian Rupees.
5. **Given** the device has no network connectivity, **When** either statement is parsed, **Then** the transactions are still produced, proving the parse is fully local.

---

### User Story 2 - One reader, two templates: classic and Fi, auto-selected by first-match-wins anchors (Priority: P2)

Federal issues its bank-account statements in two different templates, and a single Federal reader parses whichever one the statement uses. The **classic** (direct Federal Bank) template has `DD-MON-YYYY` dates (e.g. `08-APR-2026`), a single printed amount, then the running balance and a trailing `Cr`/`Dr`. The **Fi (Epifi neobank)** template has `DD/MM/YYYY` dates, explicit **Withdrawal** and **Deposit** columns (the empty side prints `0`), then the balance and a trailing `Cr`/`Dr`. The reader recognizes a transaction against an **ordered list of anchor patterns** (first match wins); a **classic** row never matches the **Fi** pattern and vice-versa, because the classic date is `DD-MON-YYYY` (alphabetic month, hyphen-separated) and the Fi date is `DD/MM/YYYY` (numeric, slash-separated).

**Why this priority**: Reading both Federal templates behind one reader is a core capability of the slice, and it is delivered purely as configuration — the base already tries a per-issuer **ordered** anchor list (proven by HDFC). Proving a single Federal reader auto-selects the correct template (without the caller choosing) keeps Federal a drop-in on the same base.

**Independent Test**: Parse the classic reference statement and the Fi reference statement through the *same* Federal reader and confirm each yields the correct transactions without the caller selecting a template; confirm each transaction row is read by exactly one template's anchor pattern (the other never matches it).

**Acceptance Scenarios**:

1. **Given** a synthetic Federal statement in the **classic** template, **When** the single Federal reader parses it, **Then** it returns the classic transactions correctly, without the caller specifying a template.
2. **Given** a synthetic Federal statement in the **Fi** template, **When** the same Federal reader parses it, **Then** it returns the Fi transactions correctly, without the caller specifying a template.
3. **Given** a **classic** transaction line (`DD-MON-YYYY` date, a single amount), **When** the reader scans it, **Then** it matches the **classic** anchor and **not** the Fi anchor.
4. **Given** a **Fi** transaction line (`DD/MM/YYYY` date, Withdrawal/Deposit columns), **When** the reader scans it, **Then** it matches the **Fi** anchor and **not** the classic anchor.
5. **Given** the reader's ordered anchor patterns, **When** a transaction line is read, **Then** the **first** pattern that matches wins and produces exactly one transaction.

---

### User Story 3 - Direction from the running-balance delta in both templates; the trailing Cr/Dr is consumed but ignored; the printed amount is an independent check (Priority: P3)

Each transaction's direction (money in vs money out) is decided **solely** by how the running balance moved — a **fall** in the balance is a **debit**, a **rise** is a **credit** — in **both** templates. The trailing `Cr`/`Dr` marker denotes the **running balance's sign**, **not** the transaction's direction, so it is matched by the anchor and then **discarded** (consumed but ignored) — it is never used to decide direction. The printed amount is used only as an **independent integrity check** (it should equal the absolute value of the balance delta within the rounding tolerance). In the **classic** template the printed amount is the single amount token; in the **Fi** template the printed amount is the **non-zero** of the Withdrawal/Deposit pair (the empty side prints `0`). Direction is never inferred from the marker, from which column an amount sits in, nor from the amount's sign or magnitude.

**Why this priority**: Deriving polarity from the balance movement — and specifically **not** from the ever-present `Cr`/`Dr` marker — is the defining rule of the balance-ledger family and the non-negotiable engine invariant for Federal. In the reference statements **every** printed marker says "Cr", yet the rows are a mix of debits and credits; getting this right is what keeps every downstream total trustworthy.

**Independent Test**: Parse classic rows and Fi rows whose balance rises and falls, and confirm each is classified credit and debit respectively from the delta — never from the trailing marker; confirm the Fi template's printed amount is taken from the non-zero Withdrawal/Deposit column and reconciles against the delta; confirm flipping the balance movement flips the direction regardless of the printed amount or the marker.

**Acceptance Scenarios**:

1. **Given** a row whose running balance falls from the previous balance (e.g., 100000.00 → 95000.00), **When** it is parsed, **Then** its direction is **debit**, in either template — even though the row prints a trailing "Cr".
2. **Given** a row whose running balance rises from the previous balance (e.g., 95000.00 → 145000.00), **When** it is parsed, **Then** its direction is **credit**, in either template — even though the row prints the same trailing "Cr".
3. **Given** the **classic** reference statement in which **every** row prints "Cr", **When** it is parsed, **Then** rows 1 and 3 are **debits** and row 2 is a **credit** — proving direction follows the delta, not the marker.
4. **Given** a **Fi** row that prints `5000` in Withdrawal and `0` in Deposit, **When** it is parsed, **Then** the printed amount used for the integrity check is 5000 (the non-zero column), and the row reconciles against its balance delta.
5. **Given** any row, **When** the sign of its balance delta is flipped (by changing the surrounding balances) while its printed amount and trailing marker are unchanged, **Then** its direction flips between debit and credit — the direction follows the delta, never the amount, the column, or the marker.

---

### User Story 4 - The S-prefixed Tran ID is captured as the per-row serial and kept OUT of the description (Priority: P4)

Each Federal row may carry an **S-prefixed Tran ID** (e.g. `S10000001`) that sits between the description and the amount(s). This identifier is captured as the row's **serial** (its audit trail) and **must not appear in the row's description** — because it is unique per row, leaving it in the narration would defeat cross-source de-duplication (which relies on stable, non-unique descriptions to match the same transaction across sources). The serial is captured in **both** templates.

**Why this priority**: The S-serial is a genuine, per-row Federal identifier that must be preserved for audit — but keeping it *out of the description* is a correctness prerequisite for the later dedup/transfer-detection work. A description containing a per-row-unique token would never match its counterpart, silently breaking dedup; pinning the serial into its own field (and out of the narration) is what keeps both the audit trail and future dedup sound.

**Independent Test**: Parse both reference statements and confirm each row exposes its S-serial (`S10000001`, `S10000002`, `S10000003` for classic; `S10000001`, `S10000002` for Fi) and that **no** row's stitched description contains its `S…` token.

**Acceptance Scenarios**:

1. **Given** the **classic** statement, **When** it is parsed, **Then** row 1's serial is `S10000001`, row 2's is `S10000002`, and row 3's is `S10000003`.
2. **Given** the **Fi** statement, **When** it is parsed, **Then** row 1's serial is `S10000001` and row 2's is `S10000002`.
3. **Given** either statement, **When** any row's description is inspected, **Then** it does **not** contain that row's `S…` Tran ID.
4. **Given** a row that carries no S-prefixed Tran ID, **When** it is parsed, **Then** its serial is empty and the row is still returned (the serial is optional in the anchor).
5. **Given** the captured serial, **When** the result is produced, **Then** it is preserved exactly as printed (e.g., `S10000002`) for the audit trail.

---

### User Story 5 - Opening balance per template, and an opening-anchored row 1 (Priority: P5)

The first ledger row has no predecessor balance, so its direction is resolved against the statement's printed **opening balance**. Federal prints the opening balance similarly in both templates, and one pattern reads both: the **classic** template prints `Opening Balance 1,00,000.00 Cr`; the **Fi** template prints `Opening Balance OPNBAL 1,00,000.00 CR`, where an `OPNBAL` transaction-id sits between the label and the figure. A single opening pattern tolerates the optional intervening upper-case token, so both resolve to a printed opening balance of 100000.00. Row 1 is **opening-anchored** in both fixtures.

**Why this priority**: Row 1 is the one place the delta rule cannot self-start, so a correct opening balance is what anchors the whole chain. Federal's Fi template inserts an `OPNBAL` tran-id between the label and the figure; tolerating that (while still reading the same figure) is what makes both fixtures reconcile with an auditable `opening_balance` direction source.

**Independent Test**: Parse the classic statement and confirm the opening balance is read from `Opening Balance 1,00,000.00 Cr`; parse the Fi statement and confirm the opening balance is read from `Opening Balance OPNBAL 1,00,000.00 CR` (the intervening `OPNBAL` tolerated); confirm row 1's direction in each fixture is set from that printed opening balance with `direction_source = opening_balance`.

**Acceptance Scenarios**:

1. **Given** the **classic** statement, **When** it is parsed, **Then** the printed opening balance is 100000.00, read from the `Opening Balance 1,00,000.00 Cr` line.
2. **Given** the **Fi** statement, **When** it is parsed, **Then** the printed opening balance is 100000.00, read from the `Opening Balance OPNBAL 1,00,000.00 CR` line (the intervening `OPNBAL` tran-id tolerated).
3. **Given** either statement, **When** row 1 (running balance 95000.00) is bootstrapped, **Then** its delta is computed against the printed opening balance (95000.00 − 100000.00 = −5000.00), so its direction is **debit**, with `direction_source = opening_balance` and no geometry consulted.
4. **Given** either statement, **When** any row after the first is bootstrapped, **Then** its direction is derived from its balance delta with `direction_source = balance_delta`.
5. **Given** the printed opening balance is present, **When** the balance chain runs, **Then** there is no row-1 direction fallback (neither provisional nor x-position).

---

### User Story 6 - Faithful narration stitching, and the non-transaction lines (headers, Opening Balance, GRAND TOTAL) (Priority: P6)

Each row's human-readable **narration** is reassembled deterministically by the reused base — the anchor's inline description plus the wrapped detail lines around it (the line immediately above the anchor plus the lines below it up to the next transaction, skipping other anchors and printed-balance lines). Because this is a **parity** port, the engine must reproduce the **known web-engine stitching behaviour**: a transaction's own wrapped continuation line — which is printed *above the next transaction's anchor* — is folded into that **next** row's narration; and the trailing **`GRAND TOTAL`** line (two money tokens, but **no** leading date and **no** `Cr`/`Dr` suffix) is folded into the **last** row's narration. The `GRAND TOTAL` line, the per-page column headers, and the `Opening Balance` line are **not** transactions. These stitched strings must be reproduced **byte-for-byte** — the port must **not** "clean them up".

**Why this priority**: This is a determinism/parity slice, and the narration strings are part of the golden ground truth. The web engine's stitching folds a transaction's continuation line into its neighbour and the `GRAND TOTAL` line into the last row; faithfully reproducing that (rather than "fixing" it) is exactly what parity requires. Excluding the header/opening/grand-total lines from the transaction list is what keeps the row count correct.

**Independent Test**: Parse both reference statements and confirm each row's stitched description matches the ground-truth string exactly — including classic row 2's inclusion of row 1's continuation (`/EXAMPLEMERCHANT \EXAM/07:17`) and classic row 3's inclusion of the trailing `GRAND TOTAL 50,000.00 50,000.00` — and confirm the `GRAND TOTAL`, column-header, and `Opening Balance` lines produce no transactions.

**Acceptance Scenarios**:

1. **Given** the **classic** statement, **When** row 1 is parsed, **Then** its description is exactly `TO ECM/600000000001 TFR`.
2. **Given** the **classic** statement, **When** row 2 is parsed, **Then** its description is exactly `UPI IN/600000000002 TFR /EXAMPLEMERCHANT \EXAM/07:17` (row 1's continuation line, printed above row 2's anchor, folded in).
3. **Given** the **classic** statement, **When** row 3 is parsed, **Then** its description is exactly `POS/600000000003/EXAMPLESTORE TFR /payer@example/Payment/0000 \EXAM/12:34 GRAND TOTAL 50,000.00 50,000.00` (its own continuation line plus the trailing `GRAND TOTAL` line folded in).
4. **Given** the **Fi** statement, **When** it is parsed, **Then** row 1's description is exactly `TO ECM/600000000001/EXAMPLE TFR` and row 2's is exactly `UPI IN/600000000002/payer TFR MERCHANT \EXAM Payment f/0000` (row 1's continuation line `MERCHANT \EXAM`, printed above row 2's anchor, folded into row 2).
5. **Given** either statement, **When** it is parsed, **Then** the `GRAND TOTAL` line, the per-page column-header line, and the `Opening Balance` line yield **no** transactions, and the total row count is exactly 3 (classic) and 2 (Fi).

---

### User Story 7 - Ledger metadata: the billing period and a bank-aware account last-4 (Priority: P7)

Each parsed row carries its ledger metadata (running balance, balance delta, amount-matches-delta, is-suspect, direction source, and serial), and the statement carries its printed opening/closing balances, billing **period**, and account **last-4**. The billing **period** comes from the statement's `for the period [of] <start> to <end>` text — where the classic template prints **ISO** dates (`2026-04-01 to 2026-04-30`) and the Fi template prints **DD/MM/YYYY** dates (`08/04/2026 to 07/05/2026`); the optional `of` (Fi's "for the period of") is tolerated. The account **last-4** comes from Federal's account-number pattern (`Account Number` then an optional masked `X*` prefix and 4+ digits), else the longest standalone ≥9-digit run; only the trailing four digits are ever kept — the full account number is never logged or persisted. The classic statement prints the account number in full (`99990100001234` → `1234`); the Fi statement masks it (`XXXXX4222` → `4222`).

**Why this priority**: These fields make the ledger auditable and attributable. Federal prints its period in two different date formats (classic ISO, Fi DD/MM/YYYY) and its account number in two forms (full vs masked); tolerating both — and keeping only the trailing four digits — is a correctness and privacy requirement.

**Independent Test**: Parse both reference statements and confirm the classic records period 2026-04-01 → 2026-04-30 and last-4 `1234`, and the Fi records period 2026-04-08 → 2026-05-07 and last-4 `4222`; confirm only the trailing four digits are retained.

**Acceptance Scenarios**:

1. **Given** the **classic** statement, **When** the billing period is extracted, **Then** it is 2026-04-01 → 2026-04-30 — parsed from the ISO `for the period 2026-04-01 to 2026-04-30` text.
2. **Given** the **Fi** statement, **When** the billing period is extracted, **Then** it is 2026-04-08 → 2026-05-07 — parsed from the `for the period of 08/04/2026 to 07/05/2026` text (the optional `of` and the DD/MM/YYYY dates tolerated).
3. **Given** the **classic** statement's full account number (`99990100001234`), **When** the account last-4 is extracted, **Then** it is `1234`.
4. **Given** the **Fi** statement's masked account number (`XXXXX4222`), **When** the account last-4 is extracted, **Then** it is `4222`.
5. **Given** the extracted account number, **When** the result is produced, **Then** only the trailing four digits are retained — the full account number is never logged, columned, or persisted.
6. **Given** a statement in which a metadata field cannot be found, **When** it is parsed, **Then** that field is left unset rather than fabricated, and the transactions are still returned.

---

### User Story 8 - The document gate distinguishes a Federal bank statement from a Federal (Scapia) credit-card statement — the shared issuer code (Priority: P8)

Federal issues **both** a Scapia co-brand **credit-card** statement and this savings/current **bank-account** statement, and — intentionally, following the ICICI precedent — **both share the issuer code `FEDERAL`** (one issuer code, two account kinds). The already-landed Scapia/Federal **credit-card** reader and this bank reader therefore **coexist under the same bank code** and are told apart by their **claim gates**. The bank reader's gate (`claims`) requires the `FEDERAL` bank code plus **all** of the markers `Federal Bank` **and** `Statement of Account`. A Scapia/Federal **credit-card** statement — which carries `Federal Bank` but **not** the savings `Statement of Account` header — must be **REJECTED** by the bank reader; the existing credit-card reader (whose gate requires `Scapia`) continues to claim it.

**Why this priority**: Because the issuer code is deliberately shared, a naive bank-code-only check would misroute a Scapia credit-card statement into the bank reader (or vice-versa). Making each reader's gate specific — the bank reader requiring the `Statement of Account` savings header, the credit-card reader requiring `Scapia` — is what keeps each statement handled by exactly the right reader, exactly as ICICI already does for its shared code.

**Independent Test**: Ask the bank reader whether it claims the classic and Fi Federal reference statements (expect yes for both) and whether it claims a Scapia/Federal credit-card statement (expect no); confirm the existing Scapia/Federal credit-card reader still claims that credit-card statement.

**Acceptance Scenarios**:

1. **Given** the synthetic Federal **classic** reference statement, **When** the bank reader's document gate is asked, **Then** it **claims** the document (`FEDERAL` code present; both `Federal Bank` and `Statement of Account` present).
2. **Given** the synthetic Federal **Fi** reference statement, **When** the bank reader's document gate is asked, **Then** it **claims** the document (`Federal Bank` and `Statement of account` present, matched case-insensitively).
3. **Given** a Scapia/Federal **credit-card** statement, **When** the bank reader's document gate is asked, **Then** it does **not** claim the document — the credit-card statement is rejected by the bank reader (it lacks `Statement of Account`).
4. **Given** a statement from a different issuer, **When** the bank reader's document gate is asked, **Then** it does **not** claim the document.
5. **Given** the same Scapia/Federal credit-card statement, **When** the existing Scapia/Federal credit-card reader's gate is asked, **Then** that reader still claims it — the two readers coexist under the shared `FEDERAL` code, separated by document kind.

---

### User Story 9 - A config-on-an-existing-base slice: reuse the base, the balance chain, and the shared account-tail helper — all unchanged, with zero new shared code (Priority: P9)

As a maintainer, this slice is delivered as a **per-issuer configuration** on the existing balance-ledger base — **not** new infrastructure, and with **no** new shared code at all. The reusable base (anchor recognition against an ordered pattern list, delta-derived direction, the printed-amount-as-independent-check, narration stitching, the row-1 bootstrap, and the errored-vs-suspect distinction), the **balance-chain check**, **and** the shared **account-tail helper** (per-bank primary account regex, else the longest standalone ≥9-digit run → trailing four) — which was factored out in the HDFC slice — are **reused unchanged**, as are the **parity harness** and the **privacy-egress gate**. Federal contributes only its per-issuer configuration (document gate, two anchor patterns, opening/period patterns, and its own account regex fed to the existing helper) plus golden fixtures.

**Why this priority**: The whole point of the slice is to prove the balance-ledger base — and now the shared account-tail helper too — is genuinely reusable, so a third bank is *just configuration plus fixtures*, with an even smaller change than HDFC (which had to add the helper). Keeping the base, the balance chain, the helper, the harness, and the privacy gate untouched is what keeps the change surgical and lets the remaining banks (AU, IOB) drop in the same way.

**Independent Test**: Confirm the Federal bank parse is delivered by a per-issuer configuration plugged into the unchanged base and balance-chain check; confirm the shared account-tail helper is reused (Federal supplies only its own primary account regex); confirm no base internals (anchor recognition, direction-from-delta, amount-as-check, stitching, row-1 bootstrap, errored-vs-suspect, the balance chain, the account-tail helper, the parity harness, the privacy gate) were modified; confirm this slice adds **no** new shared engine code and **no** new shared helper.

**Acceptance Scenarios**:

1. **Given** the change set, **When** it is reviewed, **Then** the balance-ledger base (anchor recognition, delta-derived direction, amount-as-independent-check, narration stitching, row-1 bootstrap, errored-vs-suspect) is **reused unchanged** — Federal contributes only its per-issuer configuration (document gate, anchor patterns, opening/period patterns, account extractor).
2. **Given** the change set, **When** it is reviewed, **Then** the **balance-chain check** is **reused unchanged**, and reports **RECONCILED** for both Federal fixtures.
3. **Given** the change set, **When** it is reviewed, **Then** the shared **account-tail helper** (per-bank primary regex, else the longest standalone ≥9-digit run) is **reused unchanged**; Federal supplies only its own primary account regex.
4. **Given** the change set, **When** it is reviewed, **Then** the **parity harness** and the **privacy-egress gate** are **reused unchanged** and extended to cover the Federal bank path.
5. **Given** the change set, **When** it is reviewed, **Then** this slice adds **no** new shared engine code and **no** new shared helper — only the Federal per-issuer configuration and its golden fixtures.

---

### User Story 10 - Proven byte-for-byte against two golden fixtures, both RECONCILED (Priority: P10)

As a maintainer, the engine's Federal bank-account behaviour is pinned to the proven web engine by porting **two** synthetic Federal characterization vectors — one **classic**, one **Fi** — into the repository's `fixtures/` directory as golden vectors, and asserting the on-device engine reproduces each exactly: every row's date, amount, direction, stitched description, running balance, delta, amount-matches-delta, is-suspect, direction source, and serial; the statement's printed opening/closing balances; the billing period; the account last-4; the (empty) errored-lines list; and the **RECONCILED** balance-chain result.

**Why this priority**: Parity is the constitution's acceptance mechanism for the port (Principle V). Two fixtures — one per template — turn "we think both templates match" into an enforced, regression-proof guarantee, and they extend the existing ledger parity harness to a third bank without changing it.

**Independent Test**: Run the parity harness over the two ported Federal vectors and confirm the engine's output matches the expected output exactly for each, and that re-running produces identical results.

**Acceptance Scenarios**:

1. **Given** the ported **classic** golden vector, **When** the parity harness runs, **Then** the engine's parsed output matches exactly — row 1 (2026-04-08 / 5000.00 / debit / balance 95000.00 / delta −5000.00 / `direction_source = opening_balance` / serial `S10000001`), row 2 (2026-04-11 / 50000.00 / credit / balance 145000.00 / delta +50000.00 / `direction_source = balance_delta` / serial `S10000002`), and row 3 (2026-04-13 / 45000.00 / debit / balance 100000.00 / delta −45000.00 / `direction_source = balance_delta` / serial `S10000003`), with their stitched descriptions; printed opening 100000.00 and closing 100000.00; period 2026-04-01 → 2026-04-30; account last-4 `1234`; no errored lines; and a **RECONCILED** balance chain (three rows checked, zero suspects, no row-1 fallback).
2. **Given** the ported **Fi** golden vector, **When** the parity harness runs, **Then** the engine's parsed output matches exactly — row 1 (2026-04-08 / 5000 / debit / balance 95000.00 / delta −5000.00 / `direction_source = opening_balance` / serial `S10000001`) and row 2 (2026-04-20 / 50000 / credit / balance 145000.00 / delta +50000.00 / `direction_source = balance_delta` / serial `S10000002`), with their stitched descriptions; printed opening 100000.00 and closing 145000.00; period 2026-04-08 → 2026-05-07; account last-4 `4222`; no errored lines; and a **RECONCILED** balance chain (two rows checked, zero suspects, no row-1 fallback).
3. **Given** a change that alters Federal bank-account parsing behaviour, **When** the parity harness runs, **Then** it fails, enforcing the parity guarantee.
4. **Given** either golden fixture, **When** it is inspected, **Then** all input and expected data is synthetic or fully redacted (fabricated payers, amounts, and account number) — never real account data.

---

### User Story 11 - Privacy gate and the Swift bridge: zero network, no new dependency, reachable from Swift (Priority: P11)

As a maintainer, the existing automated privacy-egress test covers the Federal bank-account import/parse path and asserts it performs no network I/O, and the new reader is reachable over the existing UniFFI bridge to Swift — all with **no new dependency** (and specifically no networking dependency). Money remains an exact decimal (never a float).

**Why this priority**: Privacy is the product's non-negotiable promise and a required constitution gate; being reachable from Swift is what makes the reader usable by the app. Proving both for the third bank — with zero new dependencies — extends the guarantee to another reader on the balance-ledger family without weakening it.

**Independent Test**: Run the privacy-egress test against the Federal bank-account parse path and confirm it passes only when zero outbound network connections occur; confirm the reader is callable over the UniFFI bridge from Swift; confirm no new runtime (and specifically no networking) dependency was added.

**Acceptance Scenarios**:

1. **Given** the Federal bank-account parse path, **When** the automated privacy-egress test runs, **Then** it confirms zero outbound network connections occur during parsing.
2. **Given** a regression that introduces any network access into the parse path, **When** the privacy-egress test runs, **Then** it fails, blocking the change.
3. **Given** the shared engine, **When** the Federal bank-account reader is exposed, **Then** it is reachable over the existing UniFFI bridge to Swift (via a bank-account parse and claims surface distinct from the existing Scapia/Federal credit-card surface), mirroring ICICI and HDFC.
4. **Given** the change set, **When** dependencies are reviewed, **Then** no new runtime dependency — and no networking dependency — is added, and money stays an exact decimal (never a float).

---

### Edge Cases

- **Wrong document type, same issuer code**: A Scapia/Federal **credit-card** statement is presented to the Federal **bank** reader → the bank reader must **not** claim it (it requires the savings `Statement of Account` header, which the card statement lacks), so a card statement is never misread as a ledger; the existing Scapia/Federal credit-card reader still claims it. The two coexist under the shared `FEDERAL` code.
- **Wrong issuer**: A statement from a different issuer is presented to the Federal bank reader → not claimed.
- **Two templates, one reader**: The classic and Fi statements each parse through the *single* Federal reader via first-match-wins anchors; a classic row (`DD-MON-YYYY`) never matches the Fi anchor and a Fi row (`DD/MM/YYYY`) never matches the classic anchor.
- **Trailing Cr/Dr is consumed but ignored**: Every Federal row ends in a `Cr`/`Dr` marker denoting the *balance's* sign; the anchor matches and discards it, and direction is decided by the balance delta. In the reference statements every marker prints "Cr" while the rows are a mix of debits and credits.
- **Fi two-column amount**: A Fi row prints the non-transacting side as `0`; the printed amount for the integrity check is the **non-zero** column (Withdrawal ⇒ the debit figure, Deposit ⇒ the credit figure).
- **Whole-number amounts (Fi)**: Fi amounts may be printed as whole numbers with no decimals (e.g. `5000`, `50000`); these parse to exact decimals and still reconcile against the two-decimal balance delta, and the amount preserves its printed form.
- **Direction independent of amount, column, and marker**: A row's balance falls → **debit**; a row's balance rises → **credit**; flipping the delta's sign flips the direction even when the printed amount/column/marker is unchanged.
- **S-serial kept out of the description**: The `S…` Tran ID (unique per row) is captured as the serial and never appears in the narration, so it cannot defeat later dedup; a row with no S-serial parses with an empty serial.
- **GRAND TOTAL is not a transaction**: The trailing `GRAND TOTAL` line has two money tokens but **no** leading date and **no** `Cr`/`Dr` suffix, so it never matches an anchor; it is folded into the last row's narration (byte-for-byte), not emitted as a transaction.
- **Non-transaction lines**: Per-page column headers and the `Opening Balance` line are not transactions.
- **Opening balance with an intervening tran-id (Fi)**: The Fi opening line prints an `OPNBAL` token between the label and the figure (`Opening Balance OPNBAL 1,00,000.00 CR`); the opening pattern tolerates the optional intervening upper-case token and still reads 100000.00, as does the classic `Opening Balance 1,00,000.00 Cr`.
- **Period in two date formats**: The classic period prints ISO dates (`2026-04-01 to 2026-04-30`); the Fi period prints DD/MM/YYYY dates with an optional `of` (`for the period of 08/04/2026 to 07/05/2026`); both are parsed.
- **Account number full vs masked**: The classic account number is printed in full (`99990100001234` → `1234`); the Fi account number is masked (`XXXXX4222` → `4222`); the last-4 is the trailing four digits, else the longest standalone ≥9-digit run; only the trailing four is retained.
- **Amount ≠ |delta| (chain break)**: A row whose printed amount differs from the absolute balance delta by more than the rounding tolerance → marked a **suspect**; the balance chain reports **NEEDS_REVIEW**; the row is **still returned**, never dropped. (Both Federal fixtures reconcile within tolerance and produce zero suspects.)
- **Unparseable anchor-shaped row**: A line matching an anchor's shape but whose date/amount/balance will not parse → captured as an **errored line** (bounded length); every good row is still returned; it is **not** a suspect. (Both Federal fixtures have zero errored lines.)
- **No column split for Federal**: Federal supplies no column-split x-position, so the row-1 x-position geometry path is **not** exercised by this slice (both fixtures are opening-anchored).
- **Indian money formatting**: Amounts/balances with thousands separators, including the Indian grouping style (e.g., `1,45,000.00`), and Fi's undelimited whole numbers (e.g., `50000`) → parsed to exact, non-negative decimals with stated precision preserved.
- **Missing metadata**: No recognizable opening/closing balance, period, or account number → the corresponding field is left unset rather than fabricated; transactions are still returned.
- **No transaction lines**: Empty input, or input with no recognizable anchor rows → an empty transaction list is returned with no error.
- **Repeated / concurrent parses**: The same input parsed repeatedly → identical results every time, with no dependence on wall-clock time, locale, or hidden global state.

## Requirements *(mandatory)*

### Functional Requirements

**Document recognition (the savings-vs-credit-card gate, under the shared issuer code)**

- **FR-001**: The engine MUST recognize a statement as a Federal **bank-account** (savings/current) statement via a document gate that requires the `FEDERAL` **bank code** and **all** required markers — `Federal Bank` **and** `Statement of Account` — matched case-insensitively; specific enough to distinguish a Federal savings/current statement from a Scapia/Federal credit-card statement (which share the `FEDERAL` issuer code).
- **FR-002**: The Federal bank reader MUST NOT claim a Scapia/Federal **credit-card** statement (which carries `Federal Bank` but not the savings `Statement of Account` header), and MUST NOT claim a statement from a different issuer. The existing Scapia/Federal credit-card reader MUST continue to claim the credit-card statement — the two readers coexist under the shared `FEDERAL` bank code and are separated by document kind (account kind).

**One reader, two statement templates (configuration on the existing base)**

- **FR-003**: The single Federal bank reader MUST handle Federal's **two** statement templates behind one reader, selected by **first-match-wins** anchor patterns supplied to the existing base's ordered anchor mechanism — introducing **no** new base capability.
- **FR-004**: The **classic** template MUST be recognized by an anchor for a `DD-MON-YYYY` transaction line (a posting date and a value date, both `DD-MON-YYYY`) followed by an inline description, an **optional** `S`-prefixed Tran ID, a **single** printed **amount**, the running **balance**, and a trailing `Cr`/`Dr` marker — capturing the **date**, the inline **description**, the optional **serial**, the **amount**, and the **balance**, and **consuming but ignoring** the trailing marker. Matching is case-insensitive.
- **FR-005**: The **Fi (neobank)** template MUST be recognized by an anchor for a `DD/MM/YYYY` transaction line (a posting date and a value date, both `DD/MM/YYYY`) followed by an inline description, an **optional** `S`-prefixed Tran ID, a **Withdrawal** column, a **Deposit** column (the empty side printed as `0`, amounts permitted as **whole numbers** or with two decimals), the running **balance**, and a trailing `Cr`/`Dr` marker — capturing the **date**, the inline **description**, the optional **serial**, the **withdrawal** amount, the **deposit** amount, and the **balance**, and **consuming but ignoring** the trailing marker. Matching is case-insensitive.
- **FR-006**: A **classic** transaction line MUST NOT match the **Fi** anchor, and a **Fi** transaction line MUST NOT match the **classic** anchor (the `DD-MON-YYYY` vs `DD/MM/YYYY` date shapes make the two mutually exclusive); each transaction line is read by exactly one template, and the first matching anchor wins.

**Direction from the running-balance delta; the trailing marker is ignored; amount as an independent check**

- **FR-007**: The engine MUST derive each transaction's debit/credit **direction** from the **running-balance delta** in **both** templates: a **fall** (delta < 0) is a **debit**, a **rise** (delta > 0) is a **credit**. Direction MUST NEVER be inferred from the trailing `Cr`/`Dr` marker (which denotes the balance's sign), nor from the sign or magnitude of the printed amount, nor from which column (Withdrawal/Deposit) a figure is printed in.
- **FR-008**: The engine MUST **consume but ignore** the trailing `Cr`/`Dr` marker on every row — it is matched by the anchor and discarded, and plays no part in deciding direction. In the classic reference statement every row prints "Cr" while rows 1 and 3 are debits and row 2 is a credit.
- **FR-009**: The engine MUST treat the printed **amount as an INDEPENDENT integrity check**: a row **reconciles** when the printed amount equals the absolute value of the balance delta within the reused rounding tolerance, otherwise it is a **suspect**. In the **classic** template the printed amount is the single amount token; in the **Fi** template the printed amount is the **non-zero** of the Withdrawal/Deposit pair (the empty side prints `0`). Whole-number Fi amounts (e.g. `5000`, `50000`) MUST parse to exact decimals and reconcile against the two-decimal balance delta.
- **FR-010**: A **suspect** row (printed amount does not match its balance delta) MUST still be **returned** (flagged), never silently dropped; the engine MUST record per row whether the amount matches the delta (`amount_matches_delta`) and whether the row is a suspect (`is_suspect`). Both Federal reference fixtures reconcile (zero suspects).

**Amount**

- **FR-011**: The engine MUST parse each amount and each running balance as an exact **decimal**, honouring Indian number formatting (thousands separators, including the Indian grouping style, e.g. `1,45,000.00`) and the Fi whole-number form (e.g. `50000`), preserving stated precision. Monetary values MUST NEVER be represented as floating-point numbers.

**The S-prefixed Tran ID (serial) and dedup safety**

- **FR-012**: The engine MUST capture the **optional** `S`-prefixed Tran ID (e.g. `S10000001`) as the row's **serial** in both templates, preserved exactly as printed. When a row carries no S-serial, the serial MUST be empty and the row MUST still be returned.
- **FR-013**: The captured `S`-serial MUST NOT appear in the row's **description** — because it is unique per row, leaving it in the narration would defeat later cross-source de-duplication. No row's stitched description may contain that row's `S…` Tran ID.

**Opening balance and row-1 bootstrap**

- **FR-014**: The engine MUST read the printed opening balance from an `Opening Balance` line in both templates, tolerating an **optional** intervening upper-case tran-id token: classic `Opening Balance 1,00,000.00 Cr` and Fi `Opening Balance OPNBAL 1,00,000.00 CR` both resolve to 100000.00.
- **FR-015**: For the **first** ledger row, the engine MUST anchor direction against the printed opening balance (`direction_source = opening_balance`) in both fixtures, reusing the base's unchanged row-1 bootstrap precedence; every row after the first MUST be `balance_delta`. Federal supplies **no** column-split x-position, so the row-1 x-position geometry path is not exercised by this slice.

**Narration stitching (faithful parity) and the non-transaction lines**

- **FR-016**: The engine MUST reassemble each row's **description (narration)** using the reused base's narration stitching (the anchor's inline description plus the wrapped detail line immediately above the anchor and the detail lines below it up to the next transaction, skipping other anchors and printed-balance lines), and MUST reproduce the known web-engine behaviour where a transaction's own wrapped continuation line — printed above the **next** transaction's anchor — is folded into that **next** row's narration, and where the trailing **`GRAND TOTAL`** line is folded into the **last** row's narration. These stitched strings MUST be reproduced **byte-for-byte**; the port MUST NOT trim, collapse, reorder, or otherwise "clean up" the stitched text.
- **FR-017**: The engine MUST NOT emit a transaction for a non-transaction line: the trailing **`GRAND TOTAL`** line (two money tokens but no leading date and no `Cr`/`Dr` suffix), the per-page **column-header** lines, and the **`Opening Balance`** line are not transactions. The classic statement yields exactly **3** transactions and the Fi statement exactly **2**.

**Per-row and statement-level ledger metadata**

- **FR-018**: Each parsed row MUST carry: the transaction **date**, the exact **amount**, the delta-derived **direction**, the currency (INR), the stitched **description**, the running **balance**, the **balance delta**, `amount_matches_delta`, `is_suspect`, `direction_source`, and the **serial** (the captured `S…` Tran ID, or empty).
- **FR-019**: The statement MUST carry: the **printed opening balance**, the **printed closing balance**, the **billing period** (start and end), and the account **last-4**.
- **FR-020**: The engine MUST derive the billing **period** from the `for the period [of] <start> to <end>` text, tolerating the **optional** `of` and accepting **both** an ISO start/end (classic, e.g. `2026-04-01 to 2026-04-30`) and a DD/MM/YYYY start/end (Fi, e.g. `08/04/2026 to 07/05/2026`).
- **FR-021**: The engine MUST derive the account **last-4** from Federal's account-number pattern — `Account Number` followed by an optional masked `X*` prefix and 4 or more digits (matching the classic full number `99990100001234` and the Fi masked `XXXXX4222`) — else from the longest standalone **≥9-digit** run; and MUST retain **only** the trailing four digits (`1234` classic, `4222` Fi). The full account number MUST NEVER be logged, columned, or persisted.
- **FR-022**: When a metadata field cannot be found, the engine MUST leave it unset rather than fabricate a value, and MUST still return the parsed transactions.

**Reuse of the existing base and shared helpers — with zero new shared code**

- **FR-023**: This slice MUST **reuse unchanged** the existing balance-ledger reader base (anchor recognition against an ordered pattern list, delta-derived direction, the printed-amount-as-independent-check, narration stitching, the row-1 bootstrap, and the errored-vs-suspect distinction) and the **balance-chain integrity check** — Federal is added only as a **per-issuer configuration** (document gate, anchor patterns, opening/period patterns, account extractor).
- **FR-024**: This slice MUST **reuse unchanged** the shared **account-tail helper** (a per-bank primary account regex, else the longest standalone ≥9-digit run, returning the trailing four digits) that was factored into the shared common module by the HDFC slice — Federal supplies only its own primary account regex. This slice MUST NOT add any new shared helper.
- **FR-025**: This slice MUST **reuse unchanged** the golden-fixture **parity harness** and the **privacy-egress gate**, extending them to cover the Federal bank path.
- **FR-026**: This slice MUST reuse the existing shared money/date/currency/direction conventions and helpers (Indian-format decimal parsing; the shared date parser, which already carries the classic `DD-MON-YYYY`, the Fi `DD/MM/YYYY`, and the ISO `YYYY-MM-DD` period formats; the explicit `Direction` type). This slice MUST add **no** new shared engine internals and **no** new date format.

**Balance-chain integrity (reused)**

- **FR-027**: The engine MUST run the reused **balance-chain integrity check** over the parsed Federal ledger and report **RECONCILED** for both reference fixtures (every row reconciles within tolerance and there is no un-trusted row-1 bootstrap), with zero suspects and no row-1 direction fallback — three rows checked for the classic fixture and two for the Fi fixture.

**Engine purity, platform boundary & bridge**

- **FR-028**: The engine's Federal bank-account parse MUST accept already-extracted text lines, the full statement text, and the first-row word geometry, and return the parsed result; it MUST NOT read files, extract PDF text, or embed a PDF engine (text and geometry extraction are native platform concerns). The Rust core MUST NEVER open a PDF.
- **FR-029**: The engine MUST remain pure and deterministic: identical input MUST yield identical output, with no dependence on network, wall-clock time, locale, or hidden global mutable state.
- **FR-030**: The engine MUST expose the Federal bank-account reader over the existing **UniFFI** bridge via a bank-account parse and claims surface that is **distinct** from the existing Scapia/Federal credit-card surface, reachable from Swift, mirroring the ICICI and HDFC bank-account readers.

**Privacy (constitution Principle I — NON-NEGOTIABLE)**

- **FR-031**: The entire Federal bank-account import/parse path MUST run 100% on-device with ZERO network I/O.
- **FR-032**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting into the engine or the app, and MUST NOT add any **networking** dependency.
- **FR-033**: The existing automated privacy-egress test MUST cover the Federal bank-account parse path and assert it performs no network access; it remains a required constitution gate.

**Parity & test-first (constitution Principle V)**

- **FR-034**: The web engine's synthetic Federal **classic** and **Fi** characterization vectors MUST be ported into the repository's `fixtures/` directory (Federal bank-account subtree) as golden vectors, and the engine MUST reproduce each exactly (rows with dates/amounts/directions/stitched-descriptions/balances/deltas/serials, printed opening/closing balances, billing period, account last-4, the empty errored-lines list, and the RECONCILED balance-chain result).
- **FR-035**: All fixture and test data MUST be synthetic or fully redacted (fabricated payers, amounts, and account number) — never real account data.
- **FR-036**: The Federal bank-account parsing behaviour introduced by this slice MUST be developed test-first (a failing golden test precedes the behaviour).

**Licensing, secrets & quality gates**

- **FR-037**: The change MUST NOT add secrets, API keys, or private endpoints; MUST remain distributable under Apache-2.0 with no copyleft (GPL/AGPL/LGPL) dependencies; and MUST introduce **no new runtime dependency** for this slice.
- **FR-038**: The change MUST keep the iOS Local Verification Gate and CI green: core formatting, linting, and tests; app linting; project generation; a simulator build with passing app tests; and the privacy gate. If any user-facing surface is introduced, it MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility.

### Key Entities *(include if feature involves data)*

- **Extracted statement input**: The already-extracted text lines, the full statement text, and the first transaction row's word geometry handed to the engine by the native platform. Contains no PDF binary; the engine never opens a PDF.
- **Federal statement template (classic / Fi)**: The two recognized Federal bank-account row formats. The single Federal reader selects between them via first-match-wins anchor patterns on the base's ordered anchor list; the caller is unaware of which matched. The classic template has `DD-MON-YYYY` dates and a single amount; the Fi (Epifi neobank) template has `DD/MM/YYYY` dates and explicit Withdrawal/Deposit columns whose amounts may be whole numbers. Both print a trailing `Cr`/`Dr` marker that is consumed but ignored.
- **Parsed ledger row**: One ledger transaction — a transaction date, an exact non-negative amount, a delta-derived direction, a currency (INR), a stitched description (never containing the row's `S…` serial), the running balance, the balance delta, an amount-matches-delta indicator, an is-suspect indicator, a direction source, and a serial (the captured `S…` Tran ID, or empty).
- **Parsed bank statement result**: The full output of reading one Federal bank-account statement — the bank identity and account kind, the list of parsed ledger rows, the list of errored (unparseable) lines, the printed opening balance, the printed closing balance, the billing period (start/end), the account last-4, and the balance-chain result.
- **Trailing Cr/Dr marker**: The per-row `Cr`/`Dr` printed at the end of every Federal ledger line, denoting the running balance's sign — matched by the anchor and discarded; it never decides direction.
- **S-prefixed Tran ID (serial)**: A per-row-unique `S…` identifier captured as the row's serial (audit trail) and deliberately kept out of the description so it cannot defeat later de-duplication.
- **Direction (polarity)**: An explicit debit or credit indicator carried on every transaction, sourced from the running-balance delta (and, for row 1, from the printed opening balance) — never from the trailing marker, the amount's sign, or the printed column.
- **Balance-chain result**: A statement-level status of RECONCILED or NEEDS_REVIEW, with the list of suspect rows — reused unchanged; RECONCILED for both Federal fixtures.
- **`direction_source`**: How a row's direction was decided — `opening_balance` for row 1 in both fixtures; `balance_delta` for every later row.
- **Account-tail helper (reused, unchanged)**: The shared helper from the HDFC slice — a per-bank primary account regex, else the longest standalone ≥9-digit run, returning the trailing four digits — reused by Federal with its own primary regex; no new shared helper is added.
- **Golden characterization vectors**: Two synthetic Federal inputs (classic and Fi: text lines + full text) paired with their expected engine outputs, stored under `fixtures/`, ported from the web engine and reproduced exactly by the on-device engine.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The synthetic Federal **classic** reference statement parses byte-for-byte to the ground truth on-device — row 1 (2026-04-08 / 5000.00 / debit / balance 95000.00 / delta −5000.00 / serial `S10000001` / `direction_source = opening_balance`), row 2 (2026-04-11 / 50000.00 / credit / balance 145000.00 / delta +50000.00 / serial `S10000002` / `direction_source = balance_delta`), and row 3 (2026-04-13 / 45000.00 / debit / balance 100000.00 / delta −45000.00 / serial `S10000003` / `direction_source = balance_delta`), with their stitched descriptions (100% match).
- **SC-002**: The synthetic Federal **Fi** reference statement parses byte-for-byte to the ground truth on-device — row 1 (2026-04-08 / 5000 / debit / balance 95000.00 / delta −5000.00 / serial `S10000001` / `direction_source = opening_balance`) and row 2 (2026-04-20 / 50000 / credit / balance 145000.00 / delta +50000.00 / serial `S10000002` / `direction_source = balance_delta`), with their stitched descriptions (100% match).
- **SC-003**: The reused balance-chain check reports **RECONCILED** for **both** Federal reference statements — three rows checked (classic) and two (Fi), zero suspects, and no row-1 direction fallback.
- **SC-004**: Direction is **delta-derived** across every tested case and both templates, and **never** taken from the trailing `Cr`/`Dr` marker: in the classic statement every printed marker is "Cr" yet rows 1 and 3 are debits and row 2 is a credit; and a row's direction **flips when its balance delta flips**, independent of the printed amount, column, or marker.
- **SC-005**: The **Fi** template resolves the printed **amount** from the **non-zero** of the Withdrawal/Deposit column pair (5000 from Withdrawal for row 1; 50000 from Deposit for row 2), and whole-number amounts (`5000`, `50000`) reconcile against the two-decimal balance delta.
- **SC-006**: The **S-serial** is captured for every row that carries one (`S10000001`/`S10000002`/`S10000003` classic; `S10000001`/`S10000002` Fi) and **no** row's description contains its `S…` Tran ID.
- **SC-007**: The narration for every row is stitched **byte-for-byte** to the ground truth — including classic row 2's folded continuation `/EXAMPLEMERCHANT \EXAM/07:17` and classic row 3's folded trailing `GRAND TOTAL 50,000.00 50,000.00` — with no normalization applied; the `GRAND TOTAL`, column-header, and `Opening Balance` lines produce no transactions, so the classic statement yields exactly 3 rows and the Fi statement exactly 2.
- **SC-008**: The bank reader **claims** both Federal reference statements (classic and Fi) and **rejects** a Scapia/Federal **credit-card** statement — 0 misroutes across the recognition cases; the existing Scapia/Federal credit-card reader still claims the credit-card statement, and the two coexist under the shared `FEDERAL` code.
- **SC-009**: The classic statement records `printed_opening_balance = 100000.00`, `printed_closing_balance = 100000.00`, billing **period** 2026-04-01 → 2026-04-30, and account **last-4 `1234`**; the Fi statement records `printed_opening_balance = 100000.00`, `printed_closing_balance = 145000.00`, billing **period** 2026-04-08 → 2026-05-07, and account **last-4 `4222`** — retaining only the trailing four digits.
- **SC-010**: The base, the balance-chain check, the shared account-tail helper, the parity harness, and the privacy-egress gate are reused **unchanged**; this slice adds **no** new shared engine code, **no** new shared helper, and **no** new dependency — only the Federal per-issuer configuration and its two golden fixtures.
- **SC-011**: 100% of parsed amounts and balances are exact **decimals** with stated precision preserved; **no monetary value is ever a floating-point number**.
- **SC-012**: Zero outbound network connections occur during the entire Federal bank-account parse path, verified by the automated privacy-egress test, and **no new runtime (or networking) dependency** is added.
- **SC-013**: The whole reader is reachable over the **UniFFI bridge to Swift** (via a bank-account parse and claims surface distinct from the existing Scapia/Federal credit-card surface), mirroring ICICI and HDFC.
- **SC-014**: Given identical input, the engine returns identical output across repeated runs (100% reproducible); both ported golden vectors reproduce exactly and the parity harness passes.
- **SC-015**: All automated checks required to merge pass (green), including the parity harness and the privacy-egress test, with the iOS Local Verification Gate and CI green; and no secrets or copyleft-licensed dependencies are added (verified by review of manifests and dependencies).

## Assumptions

- **Config-on-an-existing-base, not new infrastructure**: The balance-ledger reader base (anchor recognition against an ordered pattern list + narration stitching + delta-derived direction + the amount-vs-delta integrity check + row-1 bootstrap + errored-vs-suspect), the balance-chain integrity check, **and** the shared account-tail helper already exist (from the ICICI reference and HDFC drop-in slices) and are reused **unchanged**. Federal is added as a per-issuer configuration plus golden fixtures.
- **The base already supports multiple templates and the consumed-but-ignored marker**: The base recognizes a transaction against a per-issuer **ordered list** of anchor patterns (first match wins, proven by HDFC), and an anchor may match-and-discard trailing tokens (like the `Cr`/`Dr` marker) that it does not capture — so both are configuration, not new base capability.
- **Zero new shared code**: Unlike the HDFC slice (which factored out the account-tail helper), this slice adds **no** new shared engine code and **no** new shared helper — the account-tail helper it needs already exists in the shared common module. The Federal reader supplies only its own primary account regex. The exact module placement of the Federal configuration and the UniFFI surface names are finalized in `/speckit.plan`.
- **Anchor patterns (ported characterization, realized in `/speckit.plan`)**: The classic anchor matches a `DD-MON-YYYY` line with a posting date and value date, an inline description, an optional `S`-serial, a single amount, a balance, and a trailing `Cr`/`Dr` (consumed but ignored); the Fi anchor matches a `DD/MM/YYYY` line with a posting date and value date, an inline description, an optional `S`-serial, a Withdrawal column and a Deposit column (the empty side `0`, whole numbers permitted), a balance, and a trailing `Cr`/`Dr` (consumed but ignored). Both are matched case-insensitively. Ported faithfully from the web engine's `federal_bank.py` first-match-wins patterns; the exact regex realization is finalized in `/speckit.plan`. Illustratively (finalized in the plan): classic `^(?P<date>\d{2}-[A-Za-z]{3}-\d{4})\s+\d{2}-[A-Za-z]{3}-\d{4}\s+(?P<desc>.*?)(?:\s+(?P<serial>S\d+))?\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s+(?:Cr|Dr)\s*$`; Fi `^(?P<date>\d{2}/\d{2}/\d{4})\s+\d{2}/\d{2}/\d{4}\s+(?P<desc>.*?)(?:\s+(?P<serial>S\d+))?\s+(?P<withdrawal>[\d,]+(?:\.\d{2})?)\s+(?P<deposit>[\d,]+(?:\.\d{2})?)\s+(?P<balance>[\d,]+\.\d{2})\s+(?:Cr|Dr)\s*$`.
- **Opening-balance pattern (ported characterization)**: One pattern reads both templates, tolerating an optional intervening upper-case tran-id token — illustratively `Opening Balance\s+(?:[A-Z]+\s+)?([\d,]+\.\d{2})` — so classic `Opening Balance 1,00,000.00 Cr` and Fi `Opening Balance OPNBAL 1,00,000.00 CR` both read 100000.00. Realized in `/speckit.plan`.
- **Period & account patterns (ported characterization)**: The period is `for the period(?:\s+of)?\s+(<ISO or DD/MM/YYYY>)\s+to\s+(<…>)` — accepting the classic ISO dates and the Fi DD/MM/YYYY dates, with the optional `of` tolerated; the account last-4 is Federal's account-number pattern (illustratively `Account\s+Number\s*:?\s*X*([0-9]{4,})`), else the longest ≥9-digit run, keeping only the trailing four. These differ from ICICI's and HDFC's patterns; realized in `/speckit.plan`.
- **The trailing Cr/Dr denotes the balance's sign, not the transaction**: A Federal ledger prints a `Cr`/`Dr` at the end of every row indicating whether the running balance is in credit or debit; it is matched by the anchor and discarded, and direction is always taken from the balance delta. This is the defining Federal twist versus ICICI/HDFC (which print no marker at all) and versus a credit-card `Dr`/`Cr` line (which does decide direction).
- **The S-serial is captured out of the description**: The optional `S`-prefixed Tran ID is captured as the row's serial (audit trail) and kept out of the narration because it is unique per row and would otherwise defeat later dedup. Rows without an S-serial parse with an empty serial.
- **Narration-stitching quirk is faithful, not a bug to fix**: The web engine folds a transaction's own wrapped continuation line (printed above the next anchor) into the next row's narration, and folds the trailing `GRAND TOTAL` line into the last row's narration. The port reproduces these byte-for-byte; the golden fixtures pin them.
- **The GRAND TOTAL, header, and Opening Balance lines are not transactions**: The `GRAND TOTAL` line has two money tokens but no leading date and no `Cr`/`Dr` suffix, so it never matches an anchor; per-page column headers and the `Opening Balance` line are likewise not transactions. The classic statement yields 3 transactions and the Fi statement 2.
- **Whole-number Fi amounts**: Fi Withdrawal/Deposit amounts may be printed without decimals (`5000`, `50000`); the base's loose two-column amount handling parses these to exact decimals, and they reconcile against the two-decimal balance delta while the amount preserves its printed form.
- **Rounding tolerance & suspect/errored semantics are reused**: The amount-vs-delta tolerance, the suspect-vs-errored distinction, and the RECONCILED / NEEDS_REVIEW statuses are inherited unchanged from the base and balance-chain check. Both Federal fixtures reconcile (zero suspects, zero errored lines).
- **No column split for Federal**: Federal supplies no column-split x-position, so the row-1 x-position geometry path is supported by the base but **not** exercised by this slice; both fixtures are opening-anchored.
- **Reader identity and the shared issuer code**: The reader is the Federal **bank-account** reader. It **shares the `FEDERAL` bank code** with the already-landed Scapia/Federal **credit-card** reader (one issuer code, two account kinds — the ICICI precedent); the registry is keyed by `(bank_code, account_kind)`, and the two are told apart by their `claims` gates. The exact identity/surface strings are finalized in `/speckit.plan`.
- **Date parser needs no change**: The shared date parser already carries the classic `DD-MON-YYYY` (`%d-%b-%Y`), the Fi `DD/MM/YYYY` (`%d/%m/%Y`), and the ISO period `YYYY-MM-DD` (`%Y-%m-%d`) formats, so no new date format is added.
- **Parse seam & platform boundary**: The bank-account seam is the existing one — already-extracted text lines, the full text, and the first transaction row's word geometry — returning the parsed result. The native platform (iOS PDFKit) performs the text and geometry extraction; the Rust core never opens a PDF.
- **Binding**: The reader is exposed to Swift via the existing UniFFI bridge through a bank-account parse and claims surface distinct from the existing Scapia/Federal credit-card surface, mirroring ICICI and HDFC; concrete binding mechanics belong in `/speckit.plan`.
- **Fixtures location**: The two golden fixtures live under the Federal bank-account fixtures subtree (e.g. `fixtures/federal/bank_account/`) and are the source of truth for parity; the exact paths and file names are finalized in `/speckit.plan`.
- **No new dependencies**: This slice requires **no** new runtime dependencies, and specifically **no** networking dependency.
- **Source of truth**: The web engine is the source of truth for behaviour — the Federal bank reader `federal_bank.py` plus the shared balance-ledger reader, the balance-chain check, and the shared common/polarity helpers, and the bank-account characterization/parity test. A captured JSON ground-truth artifact (both reference fixtures, reconciled) accompanies this slice. The porting approach (module layout, patterns, fixture format, UniFFI exports) is decided in `/speckit.plan`, not here.
- **Synthetic characterization vectors**: The two synthetic statements and their expected outputs — the classic rows (2026-04-08 / 5000.00 / debit; 2026-04-11 / 50000.00 / credit; 2026-04-13 / 45000.00 / debit) with serials `S10000001`/`S10000002`/`S10000003`, and the Fi rows (2026-04-08 / 5000 / debit; 2026-04-20 / 50000 / credit) with serials `S10000001`/`S10000002`, their balances (95000.00, 145000.00, 100000.00) and deltas (−5000.00, +50000.00, −45000.00), stitched descriptions, printed opening/closing balances (classic 100000.00 / 100000.00; Fi 100000.00 / 145000.00), billing periods (2026-04-01 → 2026-04-30; 2026-04-08 → 2026-05-07), account last-4 (`1234`; `4222`), empty errored-lines lists, and the RECONCILED balance-chain result — are the constitution's golden-fixture parity vectors (Principle V), confirmed against the web engine, all synthetic/redacted.
- **No new UI required**: This is an engine slice; no user-facing UI is required to deliver it. App-side PDF text/geometry extraction (PDFKit wiring), the file-import UI, and the Share Extension remain a native concern and a later step. If a trivial demo surface is added, it follows HIG and accessibility (FR-038).
- **Data safety**: All fixture and test data is synthetic or fully redacted — no real account data.
- **Money & geometry types**: Amounts and balances are exact decimals (never floating-point) and direction is carried explicitly and derived from the balance delta; geometry x-coordinates are layout points (not money) and may be floating-point.

### Dependencies

- **Kaname Constitution v1.0.0** — privacy (zero-network free/core), determinism, a pure platform-agnostic core (no PDF engine), decimal money with explicit polarity, Apache-2.0 open-core with no copyleft, native HIG/accessibility, and the test-first iOS Local Verification Gate (including the privacy-egress gate).
- **The ICICI bank-account (balance-ledger) reference slice (already landed)** — the reusable balance-ledger reader base (anchor recognition against an ordered pattern list, delta-derived direction, amount-as-independent-check, narration stitching, row-1 bootstrap, errored-vs-suspect), the balance-chain integrity check, the ledger parity harness, the bank-account UniFFI surfaces, and the privacy-egress gate — all reused unchanged by this slice.
- **The HDFC bank-account drop-in slice (already landed)** — the shared **account-tail helper** (per-bank primary account regex, else the longest standalone ≥9-digit run → trailing four) in the shared common module, and the proof that two statement templates behind one reader are pure configuration on the ordered anchor list — both reused unchanged by this slice.
- **The Scapia/Federal credit-card slice (already landed)** — the existing Federal credit-card reader under the shared `FEDERAL` bank code, alongside which this bank-account reader coexists (separated by claim gates and account kind). Its `claims` gate (requiring `Scapia`) continues to claim the credit-card statement while the bank reader rejects it.
- **The five credit-card slices (already landed)** — the shared reader output types (parsed statement / parsed transaction), the Indian-format amount parser, the shared multi-format date parser (which already carries the classic `DD-MON-YYYY`, the Fi `DD/MM/YYYY`, and the ISO `YYYY-MM-DD` formats), the shared `Direction` type and polarity module, and the golden-fixture parity harness — reused by this slice.
- **The Rust↔Swift bridge (already landed)** — the shared engine crate and the UniFFI Swift binding proven end-to-end, over which the bank-account parse and claims functions are exposed.
- **Web engine golden vectors** — the two synthetic Federal bank characterization vectors (classic and Fi) and the `federal_bank.py` behaviour used as the parity source of truth, plus the captured JSON ground-truth artifact.

## Out of Scope

Deferred to later P2 slices / milestones:

- **The other bank-account ledger readers** — the **ICICI** and **HDFC** (already landed), and the **AU** and **IOB** bank-account readers; AU follows in a later slice on this same base and reuses the shared account-tail helper.
- **The Scapia/Federal credit-card reader** — already landed; this slice does not modify it (beyond coexisting under the shared `FEDERAL` code), and it continues to claim Scapia credit-card statements.
- **Reconciliation of printed debit/credit totals** (e.g. the `GRAND TOTAL` figures), **coverage / billing-period timeline**, and **cross-source de-duplication and transfer detection** — separate later concerns; this slice delivers the balance-**chain** integrity check (reused), not printed-total reconciliation. (Capturing the `S`-serial out of the description is groundwork for that later dedup work, but the dedup itself is out of scope here.)
- **Real-PDF geometry calibration** — Federal sets no column-split x-position, so the row-1 x-position path is not exercised here; provisional/x-position rows (not present in these fixtures) are surfaced NEEDS_REVIEW, never silently trusted.
- **Persistence** — encrypted SQLite / SQLCipher storage and key management.
- **AI-fallback parsing**.
- Any **premium / cloud features**.
- **App-side PDF text/geometry extraction** (PDFKit wiring in the app) and the **file-import UI / Share Extension** — native concerns handled in a later slice. This slice focuses on the Federal bank-account configuration on the existing balance-ledger base plus its golden-fixture parity, reusing the existing balance chain, the shared account-tail helper, the parity harness, and the privacy gate, exposed over the existing bridge.
