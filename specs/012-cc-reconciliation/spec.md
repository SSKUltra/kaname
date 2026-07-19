# Feature Specification: Reconcile a Credit-Card Statement Against Its Own Printed Totals On-Device (the Credit-Card Counterpart to the Shipped Bank-Ledger Balance-Chain; Completes the Ported Reconciliation Layer)

**Feature Branch**: `012-cc-reconciliation`  
**Created**: 2026-07-19  
**Status**: Draft  
**Milestone**: P2 (engine port) — the credit-card counterpart of the already-shipped bank-ledger balance-chain integrity check, and the last remaining piece of the web engine's per-statement reconciliation layer  
**Input**: User description: "credit-card statement reconciliation (slice 012). This ports the last remaining piece of the web engine's per-statement reconciliation into the on-device Rust core (kaname-core), the credit-card counterpart to the bank-account balance-chain check that already shipped. When the app reads a credit-card statement, it should tell the user whether the transactions it extracted actually add up to what the statement itself claims. Primary check: sum of read DEBIT rows and sum of read CREDIT rows vs the statement's printed debit/credit totals within a ₹1.00 tolerance → RECONCILED / NEEDS_REVIEW. Fallback check: if no printed debit/credit totals but a printed opening and closing balance both exist, compare the read balance change (Σdebits − Σcredits) against the printed change (closing − opening) within the same tolerance. Neutral outcome: if the statement prints no totals at all, a neutral 'not reconciled (no balance)' state, explicitly distinct from a true mismatch. All read rows are always retained; the result carries an audit detail. Scope also surfaces the printed debit/credit totals from the two readers that print them — Yes Bank / Kiwi and IOB — which currently defer them. The other four card readers (ICICI, HDFC, SBI, Federal/Scapia) print no such totals and correctly produce the neutral outcome. Behaviour is fully pinned by the web engine (reconciliation.py, test_reconciliation.py, test_statement_reconciliation.py)."

> **Note on priority labels**: This feature sits in product milestone **P2** (engine port, `docs/kaname-ios-plan.md` §9). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P2" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

The ten statement readers (six credit-card — **ICICI**, **HDFC**, **SBI Card**, **Yes Bank / Kiwi**, **Federal / Scapia**, **IOB** — and four bank-account ledgers — **ICICI bank**, **HDFC bank**, **Federal bank**, **AU bank**) are all landed and proven byte-for-byte against golden fixtures. The bank-account side already ships its **trust signal**: a **balance-chain integrity check** that verifies each printed amount against its running-balance delta and reports **Reconciled / NeedsReview** with the suspect rows. The credit-card side has had **no equivalent trust signal** — the credit-card readers deliberately **deferred** the printed per-statement totals needed to build one.

This slice delivers the **credit-card counterpart**: a per-statement **reconciliation check** that tells a person whether the transactions the app extracted from their credit-card statement **actually add up to what the statement itself claims**, so a mis-parse or a dropped row is caught **before the data is trusted**. It ports the web engine's `reconciliation.py` and the two readers' printed-total scrapes into the on-device core, completing the last remaining piece of the web engine's per-statement reconciliation layer. Its behaviour is **fully pinned** by the proven web engine and its tests (Constitution Principle V, Test-First & Parity); this port reproduces that behaviour exactly.

After a credit-card statement is read, the check compares — over **all** the read rows, using **exact decimal** money — the sum of the **DEBIT** rows and the sum of the **CREDIT** rows against the statement's own **printed** figures, in three tiers:

1. **Primary check** — against the statement's **printed debit/credit totals** (e.g., an "ACCOUNT SUMMARY" block, or "Current Purchases … Rs. X Dr" / "Payment & Credits Received … Rs. Y Cr"). Either printed total may be present independently; each present one is checked against its read sum within a small **₹1.00** rounding tolerance. All present totals within tolerance → **RECONCILED**; any out of tolerance → **NEEDS_REVIEW**.
2. **Fallback check** — if **no** printed debit/credit totals were extracted but a printed **opening** and **closing** balance **both** are, compare the read balance change (Σdebits − Σcredits) against the printed change (closing − opening) within the same ₹1.00 tolerance → **RECONCILED / NEEDS_REVIEW**.
3. **Neutral outcome** — if the statement prints **no** totals at all (and not both an opening and a closing balance), the result is a neutral **"not reconciled (no balance)"** state that is **explicitly distinct from a true mismatch**. A statement whose totals simply could not be extracted MUST NOT be flagged as a failure.

In **every** case, **all** read rows are retained regardless of the outcome — reconciliation **never** drops transactions. The result also carries an **audit detail** (the read debit/credit sums, the printed totals compared, or the expected/computed balance change, or the neutral reason) so the person or the UI can explain the verdict.

To make the primary check fire on real statements, this slice also **surfaces the printed debit/credit totals** from the **two** credit-card readers that print them — **Yes Bank / Kiwi** and **IOB** — which the on-device readers currently intentionally defer (their source modules carry an explicit "printed_total_* out of scope for this slice" carve-out). The **other four** card readers (ICICI, HDFC, SBI, Federal/Scapia) print no such totals in the web engine and therefore produce the **neutral** outcome — that is **correct** and in-scope to **verify**, not a gap to fill.

Like the balance-chain check it mirrors, the reconciliation check is **pure** and **on-device**: no network, no clock, no locale, no hidden state (Constitution Principle I & II). It reuses the existing shared statement/transaction types, the exact-decimal money type, the golden-fixture parity harness, and the UniFFI bridge — adding **no new runtime dependency**.

### User Story 1 - Tell the user whether a read credit-card statement adds up to its printed totals (Priority: P1)

After the app reads a person's credit-card statement, the engine compares the sum of the read debit rows and the sum of the read credit rows against the statement's own printed debit/credit totals. If each printed total present matches its read sum within a small rounding tolerance, the statement is reported **RECONCILED**; otherwise **NEEDS_REVIEW** — so a mis-parse or a dropped row is caught before the data is trusted.

**Why this priority**: This is the headline value and the smallest slice that delivers a credit-card trust signal — the direct counterpart to the bank-ledger balance-chain that already ships. On its own it lets a person (or the UI) know whether the extracted transactions can be trusted against the statement's own arithmetic. Every other story refines or enables this verdict.

**Independent Test**: Give the check a read statement whose read debit/credit sums equal its printed debit/credit totals and confirm it returns RECONCILED; give it one whose printed total differs by more than the tolerance and confirm it returns NEEDS_REVIEW — with no network access during the check.

**Acceptance Scenarios**:

1. **Given** a read statement with debit rows 100.00 and 250.50 (read debit sum 350.50) and a credit row 900.00, whose printed totals are debit 350.50 and credit 900.00, **When** the check runs, **Then** it returns **RECONCILED**.
2. **Given** a read statement with debit rows 100.00 and 250.50 (read debit sum 350.50) whose printed debit total is 999.99, **When** the check runs, **Then** it returns **NEEDS_REVIEW**, and the audit detail records the read debit sum (350.50) and the printed debit total compared (999.99).
3. **Given** a read statement whose read debit sum is 350.00 and whose printed debit total is 350.50 (a 0.50 difference, within the ₹1.00 tolerance), **When** the check runs, **Then** it returns **RECONCILED**.
4. **Given** the device has no network connectivity, **When** the check runs, **Then** the verdict is still produced, proving the check is fully local.

---

### User Story 2 - Surface the printed debit/credit totals from the two readers that print them (Yes/Kiwi & IOB) (Priority: P2)

The engine reads the printed per-statement debit and credit totals from the two credit-card readers that print them — **Yes Bank / Kiwi** (from its "Current Purchases … Dr" and "Payment & Credits Received … Cr" figures) and **IOB** (from the "ACCOUNT SUMMARY" block's credit and debit figures) — lifting the deliberate carve-out those two readers currently carry. These printed totals are the numbers the primary check compares the read sums against.

**Why this priority**: The reconciliation verdict (US1) can only fire on real statements once the statement carries the issuer's own printed totals. These two readers are the only two of the six that print such totals; surfacing them is what turns the check from a purely constructed capability into a real, end-to-end credit-card trust signal. It must land with (or before) the verdict to make US1 demonstrable on actual reader output.

**Independent Test**: Read a synthetic Yes statement and a synthetic IOB statement whose text carries their printed totals, and confirm the parsed result now exposes a printed debit total and a printed credit total equal to those figures — while every other parsed field (rows, direction, dates, card last-4, billing period) is unchanged.

**Acceptance Scenarios**:

1. **Given** a synthetic Yes / Kiwi statement whose text prints "Current Purchases / Cash Advance & Other Charges : Rs. 100.00 Dr" and "Payment & Credits Received : Rs. 9,000.00 Cr", **When** it is read, **Then** the parsed result exposes a printed debit total of 100.00 and a printed credit total of 9,000.00.
2. **Given** a synthetic IOB statement whose "ACCOUNT SUMMARY" values row reads "345.50 1,000.00 3,500.00 0 2,845.50" (previous, credits, debits, fees, total), **When** it is read, **Then** the parsed result exposes a printed credit total of 1,000.00 (the 2nd figure) and a printed debit total of 3,500.00 (the 3rd figure).
3. **Given** either reader's statement in which the printed-total label is absent or its value is not on the same extracted line as its label, **When** it is read, **Then** the corresponding printed total is left absent rather than fabricated, and the transactions are still returned.
4. **Given** the change that surfaces these totals, **When** the two readers' output is compared for the rest of their fields, **Then** the rows, directions, dates, card last-4, and billing period are byte-for-byte unchanged from before — only the printed-total fields are added.

---

### User Story 3 - A neutral "no balance" outcome, explicitly distinct from a true mismatch (Priority: P3)

When a statement prints no per-statement totals at all (and does not print both an opening and a closing balance), the check returns a neutral **"not reconciled (no balance)"** outcome that is **distinct** from NEEDS_REVIEW. A statement the engine simply could not extract totals from must never be reported as a reconciliation **failure** — it is an "unknown", not a "mismatch".

**Why this priority**: This distinction is the difference between "we couldn't check" and "we checked and it's wrong". Conflating the two would wrongly alarm a person about every statement that happens not to print totals — including the four credit-card readers (ICICI, HDFC, SBI, Federal/Scapia) that print none. The neutral outcome keeps those statements honest (verifiably not flagged) and is a hard behavioural guarantee pinned by the web engine.

**Independent Test**: Reconcile a read statement that carries no printed totals and no opening/closing balance pair, and confirm the outcome is the neutral "no balance" state and is **not** equal to NEEDS_REVIEW; repeat for each of the four no-total credit-card readers and confirm every one produces the neutral outcome.

**Acceptance Scenarios**:

1. **Given** a read statement with a debit row 100.00 and no printed totals and no opening/closing balance pair, **When** the check runs, **Then** it returns the neutral "not reconciled (no balance)" outcome, which is **not** NEEDS_REVIEW.
2. **Given** the neutral outcome, **When** its audit detail is inspected, **Then** it records the reason that no printed totals were extracted.
3. **Given** a read statement from any of the four no-total credit-card readers (ICICI, HDFC, SBI, Federal/Scapia), **When** the check runs, **Then** it produces the neutral outcome — this is correct behaviour, not a failure to flag.

---

### User Story 4 - Fallback: reconcile against the opening→closing balance change when no printed totals (Priority: P4)

When a statement carries **no** printed debit/credit totals but **does** print both an opening and a closing balance, the check falls back to comparing the read balance change (read debit sum − read credit sum) against the printed change (closing − opening) within the same ₹1.00 tolerance — reconciling when they agree and flagging for review when they do not. Debits raise the balance owed; credits lower it.

**Why this priority**: This is the second tier of the pinned reconciliation ladder and must be reproduced for byte-for-byte parity. It matters when a statement expresses its arithmetic as balances rather than category totals. It is lower priority than the primary check because the shipped credit-card readers express reconciliation via printed totals (US2), but the fallback is part of the proven engine behaviour and must be present and correct.

**Independent Test**: Reconcile a read statement with no printed debit/credit totals but with a printed opening and closing balance whose difference equals the read balance change, and confirm RECONCILED; perturb the closing balance beyond the tolerance and confirm NEEDS_REVIEW.

**Acceptance Scenarios**:

1. **Given** a read statement with a debit row 500.00 and a credit row 200.00 (read balance change +300.00), no printed debit/credit totals, a printed opening balance 1,000.00 and a printed closing balance 1,300.00 (printed change +300.00), **When** the check runs, **Then** it returns **RECONCILED**, and the audit detail records the expected change (+300.00) and the computed change (+300.00).
2. **Given** the same statement but a printed closing balance that makes the printed change differ from the read change by more than ₹1.00, **When** the check runs, **Then** it returns **NEEDS_REVIEW**.
3. **Given** a statement that carries at least one printed debit/credit total, **When** the check runs, **Then** the primary check is used and the opening→closing fallback is **never** consulted (the printed totals take precedence).
4. **Given** a statement with no printed totals and only one of opening/closing present (not both), **When** the check runs, **Then** the fallback is **not** used and the neutral "no balance" outcome is returned.

---

### User Story 5 - Explain the verdict and never drop a transaction (Priority: P5)

Whatever the outcome, the result carries an **audit detail** that explains it — the read debit/credit sums and the printed totals compared, or the expected and computed balance change, or the reason no totals were extracted — and the check **retains every read row** regardless of the verdict. Reconciliation is a read-only trust signal; it never removes, mutates, or reorders transactions.

**Why this priority**: A verdict a person cannot understand is not actionable, and a check that silently dropped rows would defeat its own purpose (it exists to catch dropped rows). Retention and explainability are what make the signal safe to surface. Both are hard, testable guarantees pinned by the web engine, whose integration test asserts the rows are retained even when reconciliation fails.

**Independent Test**: Reconcile a multi-row statement that yields NEEDS_REVIEW and confirm every read row is still present afterward (none dropped); inspect the result for each outcome and confirm the audit detail carries the numbers (or reason) behind the verdict.

**Acceptance Scenarios**:

1. **Given** a three-row statement whose printed totals do not match (yielding NEEDS_REVIEW), **When** the check runs, **Then** all three read rows are still present afterward — reconciliation dropped none of them.
2. **Given** a RECONCILED primary-check result, **When** its audit detail is inspected, **Then** it records the read debit sum, the read credit sum, and each printed total that was compared.
3. **Given** a fallback result, **When** its audit detail is inspected, **Then** it records the expected balance change and the computed balance change.
4. **Given** the neutral outcome, **When** its audit detail is inspected, **Then** it records the reason that no printed totals were extracted.

---

### User Story 6 - The credit-card counterpart to the shipped balance-chain, with no new engine infrastructure (Priority: P6)

Adding reconciliation must mirror the already-shipped bank-ledger balance-chain check and require **no new engine infrastructure** beyond the check itself: the two printed-total fields on the statement model, the two reader enrichments (Yes/Kiwi and IOB), the golden-fixture extensions, one bridge export, the parity cases, and a bridge test. It reuses the shared statement/transaction types, the exact-decimal money type, the parity harness, the UniFFI bridge, and the privacy gate — and adds **no new runtime dependency**.

**Why this priority**: This re-confirms the fixtures-driven, incremental engine architecture scales to the reconciliation layer just as it did to ten readers and the balance-chain — the reconciliation check is the credit-card analogue of `balance_chain` and slots into the same seams. Landing it as a clean drop-in (a check module + two fields + two enrichments + fixtures + a bridge export + parity + a Swift test) validates that no shared engine internals need rebuilding and closes out the ported reconciliation layer.

**Independent Test**: Confirm the reconciliation check is delivered as a pure function over the shared parsed-statement type, exposed over the existing bridge exactly as the balance-chain check is, reusing the shared money/decimal type and parity harness, and that the change adds no new runtime dependency and no new shared engine helper beyond the reconciliation check and the two printed-total fields.

**Acceptance Scenarios**:

1. **Given** the reconciliation check, **When** it is invoked, **Then** it takes the shared parsed-statement type and returns a verdict plus an audit detail, mirroring how the balance-chain check takes a parsed statement and returns its result.
2. **Given** the change set that adds reconciliation, **When** it is reviewed, **Then** it consists of the reconciliation check, two printed-total fields on the statement model, the Yes/Kiwi and IOB reader enrichments, the golden-fixture extensions and reconcile parity cases, one bridge export, and a bridge test — and adds **no** new runtime dependency.
3. **Given** the money involved, **When** any sum, total, or balance change is computed or compared, **Then** it is an exact decimal — never a floating-point number.

---

### User Story 7 - Proven byte-for-byte against golden fixtures for all three verdicts (Priority: P7)

The reconciliation behaviour is proven against golden vectors ported from the web engine that cover all three verdicts: a matching statement → RECONCILED, a mismatching statement → NEEDS_REVIEW, and a no-printed-totals statement → the neutral outcome. The Yes/Kiwi and IOB fixtures are extended so their printed totals are captured and their end-to-end verdict (read → reconcile) is RECONCILED.

**Why this priority**: Golden-fixture parity is the constitution's source of truth (Principle V): the on-device check must reproduce the web engine's verdicts exactly. Covering all three outcomes pins the tolerance, the primary-over-fallback precedence, and the neutral/mismatch distinction against regression. This is the acceptance gate for the whole slice.

**Independent Test**: Run the parity harness over the three verdict vectors and confirm each reproduces its expected outcome exactly; confirm the extended Yes and IOB fixtures capture their printed totals and reconcile to RECONCILED.

**Acceptance Scenarios**:

1. **Given** the extended IOB golden fixture (read debit 3,500.00 / credit 1,000.00 vs printed debit 3,500.00 / credit 1,000.00), **When** it is read and reconciled, **Then** the verdict is **RECONCILED**.
2. **Given** the extended Yes / Kiwi golden fixture (read debit 100.00 / credit 9,000.00 vs printed debit 100.00 / credit 9,000.00), **When** it is read and reconciled, **Then** the verdict is **RECONCILED**.
3. **Given** a mismatch golden vector (a read debit sum that differs from the printed debit total by more than ₹1.00), **When** it is reconciled, **Then** the verdict is **NEEDS_REVIEW**.
4. **Given** a no-printed-totals golden vector (e.g., a statement from one of the four no-total readers), **When** it is reconciled, **Then** the verdict is the neutral "not reconciled (no balance)" outcome.
5. **Given** identical input, **When** the check runs repeatedly, **Then** it returns identical output every time (100% reproducible).

---

### User Story 8 - Reachable across the Rust↔Swift bridge (Priority: P8)

The reconciliation check is callable from the app across the existing UniFFI bridge: given a parsed statement, Swift receives the verdict (RECONCILED / NEEDS_REVIEW / neutral) and the audit detail — exactly as it already can call the balance-chain check.

**Why this priority**: The engine's value is only realized when the app can consume it. Proving the reconcile verdict crosses the bridge (with a Swift bridge test) is what makes the trust signal usable by a future UI, and it mirrors the bridge-reachability guarantee every prior slice landed. It is a required, verifiable deliverable of this slice.

**Independent Test**: From a Swift test, read a synthetic credit-card statement, call the reconcile entry point across the bridge, and confirm the returned verdict and audit detail match what the engine computes.

**Acceptance Scenarios**:

1. **Given** the app calls the reconcile entry point over the bridge with a parsed statement whose read sums match its printed totals, **When** it runs, **Then** Swift receives the **RECONCILED** verdict.
2. **Given** the app calls the reconcile entry point over the bridge with a statement whose printed total is out of tolerance, **When** it runs, **Then** Swift receives the **NEEDS_REVIEW** verdict.
3. **Given** the app calls the reconcile entry point over the bridge with a statement that prints no totals, **When** it runs, **Then** Swift receives the neutral outcome, distinguishable from NEEDS_REVIEW.

---

### User Story 9 - Privacy: zero network in the reconciliation path (Priority: P9)

Reconciling a statement — summing rows, comparing against printed totals or balances, and producing the verdict — happens entirely on the device with no network access whatsoever, consistent with the constitution's non-negotiable privacy principle.

**Why this priority**: Privacy is the product's defining, non-negotiable promise (Constitution Principle I). Reconciliation touches the person's most sensitive data (their exact transactions and balances), so it must be provably local. The automated privacy-egress gate must cover this path.

**Independent Test**: Run the reconciliation path under the automated privacy-egress test and confirm zero outbound network connections occur.

**Acceptance Scenarios**:

1. **Given** the device has no network connectivity, **When** a statement is reconciled, **Then** the verdict is still produced (the check is fully local).
2. **Given** the automated privacy-egress test, **When** it exercises the reconciliation path, **Then** it asserts zero network access and remains a required constitution gate.

---

### Edge Cases

- **Difference exactly at the tolerance**: a read-vs-printed difference of exactly ₹1.00 is **within** tolerance (reconciles); a difference greater than ₹1.00 does not.
- **Only one printed total present**: only the present total is checked against its read sum; the absent one is not required and does not affect the verdict, but the read sums for both directions are still recorded in the audit detail.
- **Both printed totals present, one matches and one does not**: the verdict is **NEEDS_REVIEW** (every present total must be within tolerance to reconcile).
- **Zero read rows with printed totals present**: the read sums are 0.00; the verdict is RECONCILED only if each present printed total is itself within ₹1.00 of 0.00, otherwise NEEDS_REVIEW (the check never crashes on an empty row set).
- **Primary-over-fallback precedence**: if any printed debit/credit total is present, the opening→closing fallback is never consulted, even when opening/closing balances are also present.
- **Fallback requires both balances**: the opening→closing fallback is used only when both a printed opening and a printed closing balance are present; with only one (or neither), the neutral outcome is returned.
- **Neutral vs mismatch**: a statement with no printed totals yields the neutral "no balance" outcome, which must never be represented as, or compared equal to, NEEDS_REVIEW.
- **Rows retained on every outcome**: RECONCILED, NEEDS_REVIEW, and neutral all leave the full read-row set intact; no outcome ever drops a transaction.
- **Sign of the balance change**: in the fallback, debits raise the balance owed and credits lower it, so the read change is (Σdebits − Σcredits) and the printed change is (closing − opening); a negative change is compared just as a positive one.
- **Absent printed-total label or value**: when a reader cannot find its printed-total label, or the value is not on the same extracted line as the label, that printed total is left absent (never fabricated) and the statement reconciles via whatever tier applies (often neutral).
- **Direction source unchanged**: reconciliation reads each row's already-decided debit/credit direction (from the statement's own Dr/Cr marker for credit cards); it never re-derives direction from an amount's sign.

## Requirements *(mandatory)*

### Functional Requirements

**Reconciliation verdict — inputs, scope & outcomes**

- **FR-001**: The engine MUST provide a pure per-statement reconciliation check that, given a read statement (all its parsed rows plus any printed totals/balances), returns exactly one of three outcomes — **RECONCILED**, **NEEDS_REVIEW**, or a neutral **"not reconciled (no balance)"** — together with an audit detail.
- **FR-002**: The check MUST compute its sums over **all** read rows of the statement (every parsed transaction, not any later deduped/persisted subset): the total of DEBIT-direction amounts and the total of CREDIT-direction amounts, as exact decimals, with an empty row set summing to 0.00 for each direction.
- **FR-003**: The check MUST be read-only: it MUST NOT drop, mutate, or reorder any read row. All read rows MUST be retained regardless of the outcome (reconciliation never removes transactions).
- **FR-004**: The neutral "not reconciled (no balance)" outcome MUST be represented as **explicitly distinct** from NEEDS_REVIEW, such that a statement whose totals could not be extracted is never reported as (or compared equal to) a reconciliation failure.

**Primary check — printed debit/credit totals**

- **FR-005**: When the statement carries at least one printed per-statement total (a printed debit total and/or a printed credit total), the check MUST use the primary path and MUST NOT consult the opening→closing balance-change fallback.
- **FR-006**: For each printed total that is present, the check MUST compare it against the corresponding read sum (printed debit total vs read debit sum; printed credit total vs read credit sum) and treat that side as reconciled when the absolute difference is within the **₹1.00** rounding tolerance (a difference of exactly ₹1.00 is within tolerance).
- **FR-007**: A printed total that is absent MUST NOT be required. The verdict MUST be **RECONCILED** when every **present** printed total is within tolerance, and **NEEDS_REVIEW** when any present printed total is out of tolerance.

**Fallback check — opening→closing balance change**

- **FR-008**: When **no** printed debit/credit totals are present but **both** a printed opening balance and a printed closing balance are present, the check MUST compare the read balance change (read debit sum − read credit sum) against the printed change (closing − opening), reconciling within the same ₹1.00 tolerance → **RECONCILED**, otherwise **NEEDS_REVIEW**. (Debits raise the balance owed; credits lower it.)
- **FR-009**: When no printed debit/credit totals are present and **not** both an opening and a closing balance are present, the check MUST return the neutral outcome (the fallback MUST NOT be used with only one of the two balances).

**Audit detail**

- **FR-010**: The result MUST carry an audit detail sufficient to explain the verdict: for the primary path, the read debit sum, the read credit sum, and each printed total compared; for the fallback path, the expected balance change and the computed balance change; for the neutral outcome, the reason that no printed totals were extracted.

**Surfacing printed totals (Yes / Kiwi & IOB)**

- **FR-011**: The parsed-statement output model MUST gain printed per-statement **debit-total** and **credit-total** fields, each absent (unset) when a reader does not print it. (The opening/closing balance fields the fallback needs already exist on the model from the bank-ledger work and are reused.)
- **FR-012**: The **Yes Bank / Kiwi** reader MUST surface its printed **debit** total (from a "Current Purchases … Rs. X Dr" figure) and its printed **credit** total (from a "Payment & Credits Received … Rs. Y Cr" figure), removing that reader's current deferred carve-out. A total MUST be surfaced only when its label and value are present together on the same extracted line; otherwise it is left absent.
- **FR-013**: The **IOB** reader MUST surface its printed **credit** total and printed **debit** total from the "ACCOUNT SUMMARY" block's values row (the 2nd figure = credits, the 3rd = debits), removing that reader's current deferred carve-out.
- **FR-014**: Surfacing these printed totals MUST leave every other parsed field of the two readers (rows, direction, amounts, dates, card last-4, billing period, errored lines) **byte-for-byte unchanged** — only the printed-total fields are added.

**The four no-total readers**

- **FR-015**: The ICICI, HDFC, SBI, and Federal / Scapia credit-card readers MUST continue to print **no** per-statement debit/credit totals (they print none in the web engine) and therefore MUST reconcile to the **neutral** outcome. This is correct behaviour to verify, not a gap to fill; this slice MUST NOT invent totals for them.

**Counterpart to balance-chain — reuse, purity & platform boundary**

- **FR-016**: The reconciliation check MUST be the credit-card counterpart of the already-shipped bank-ledger balance-chain check, reusing the shared parsed-statement / parsed-transaction output types, the exact-decimal money type, the golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate. It MUST add **no** new runtime dependency and **no** new shared engine helper beyond the reconciliation check itself and the two printed-total fields.
- **FR-017**: All monetary values in the check (row sums, printed totals, balances, balance changes, and the tolerance) MUST be exact decimals; they MUST NEVER be represented as floating-point numbers.
- **FR-018**: The check MUST remain pure and deterministic: identical input MUST yield identical output, with no dependence on network, wall-clock time, locale, or hidden global mutable state, and it MUST NOT read files or extract PDF text (text extraction is a native platform concern).

**Bridge exposure**

- **FR-019**: The reconciliation check MUST be reachable over the existing UniFFI bridge with a reconcile entry point that accepts a parsed statement and returns the verdict plus the audit detail, mirroring how the balance-chain check is exposed to Swift.

**Privacy (Constitution Principle I — NON-NEGOTIABLE)**

- **FR-020**: The entire reconciliation path MUST run 100% on-device with ZERO network I/O.
- **FR-021**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting into the engine or the app.
- **FR-022**: The existing automated privacy-egress test MUST cover the reconciliation path and assert it performs no network access; it remains a required constitution gate.

**Parity & test-first (Constitution Principle V)**

- **FR-023**: The web engine's reconciliation behaviour MUST be the pinned source of truth (`reconciliation.py` plus its unit tests `test_reconciliation.py` and the integration tests `test_statement_reconciliation.py`) and MUST be reproduced exactly — including the ₹1.00 tolerance, the primary-over-fallback precedence, the balance-change fallback, and the neutral outcome distinct from a mismatch.
- **FR-024**: Golden vectors MUST cover all three verdicts — a matching statement → RECONCILED, a mismatching statement → NEEDS_REVIEW, and a no-printed-totals statement → neutral — each reproduced exactly by the on-device check.
- **FR-025**: The Yes / Kiwi and IOB golden fixtures MUST be extended so their printed totals are captured and their end-to-end reconcile verdict is RECONCILED (Yes: read debit 100.00 / credit 9,000.00 vs printed 100.00 Dr / 9,000.00 Cr; IOB: read debit 3,500.00 / credit 1,000.00 vs printed 3,500.00 / 1,000.00).
- **FR-026**: All fixture and test data MUST be synthetic or fully redacted (fabricated merchants, amounts, totals, and masked card numbers) — never real account data.
- **FR-027**: The reconciliation behaviour introduced by this slice MUST be developed test-first (a failing golden/parity test precedes the behaviour).

**Licensing, secrets & quality gates**

- **FR-028**: The change MUST NOT add secrets, API keys, or private endpoints; MUST remain distributable under Apache-2.0 with no copyleft (GPL/AGPL/LGPL) dependencies; and MUST introduce NO new runtime dependencies for this slice.
- **FR-029**: The change MUST keep the iOS Local Verification Gate and CI green: core formatting, linting, and tests; app linting; project generation; a simulator build with passing app tests; and the privacy gate.
- **FR-030**: If any user-facing surface is introduced for this slice, it MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility.

### Key Entities *(include if feature involves data)*

- **Parsed statement (input)**: The full result of reading one statement — the issuer/bank identity, the list of parsed transactions, any errored lines, the billing period, the card last-4, and the printed balances/totals. For this slice it gains a printed **debit-total** and printed **credit-total** field (absent when the reader prints none). The check consumes this; it never opens a PDF.
- **Read debit sum / read credit sum**: The exact-decimal totals of the DEBIT-direction and CREDIT-direction amounts across **all** read rows.
- **Printed totals**: The statement's own per-statement debit total and credit total, as printed by the issuer (surfaced only by the Yes/Kiwi and IOB readers).
- **Printed opening / closing balance**: The statement's printed opening and closing balances, used only by the fallback when no printed debit/credit totals are present.
- **Rounding tolerance**: The ₹1.00 threshold within which a read-vs-printed comparison is treated as reconciled.
- **Reconciliation result**: The outcome of the check — one of RECONCILED, NEEDS_REVIEW, or the neutral "not reconciled (no balance)" — plus an audit detail (read sums and printed totals compared, or expected/computed balance change, or the neutral reason).
- **Golden reconciliation vectors**: Synthetic statements paired with their expected reconcile verdicts (match → RECONCILED, mismatch → NEEDS_REVIEW, no-totals → neutral), ported from the web engine and reproduced exactly; the Yes/Kiwi and IOB fixtures are extended with their printed totals.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Across the three reference verdicts, the check is 100% correct — a matching statement returns RECONCILED, a statement whose printed total is off by more than ₹1.00 returns NEEDS_REVIEW, and a no-printed-totals statement returns the neutral outcome.
- **SC-002**: The IOB reference statement reconciles: read debit sum 3,500.00 equals printed debit total 3,500.00 and read credit sum 1,000.00 equals printed credit total 1,000.00 → RECONCILED.
- **SC-003**: The Yes / Kiwi reference statement reconciles: read debit sum 100.00 equals printed debit total 100.00 (Dr) and read credit sum 9,000.00 equals printed credit total 9,000.00 (Cr) → RECONCILED.
- **SC-004**: The tolerance boundary is exact — a read-vs-printed difference of 0.50 (and of exactly 1.00) reconciles, while a difference greater than 1.00 does not — 0 misclassifications at the boundary.
- **SC-005**: When only one printed total is present, only that side determines the verdict and the other side is not required — verified for a debit-only and a credit-only printed total.
- **SC-006**: The neutral "no balance" outcome is never equal to NEEDS_REVIEW — 0 conflations — and every one of the four no-total readers (ICICI, HDFC, SBI, Federal/Scapia) produces the neutral outcome.
- **SC-007**: The fallback reconciles when the read balance change equals the printed change within ₹1.00 — e.g., read debit 500.00 and credit 200.00 (change +300.00) with opening 1,000.00 and closing 1,300.00 (change +300.00) → RECONCILED — and flags NEEDS_REVIEW when they differ beyond the tolerance.
- **SC-008**: Primary takes precedence over fallback — whenever any printed debit/credit total is present, the opening→closing fallback is never used (0 cases of the fallback firing when a printed total exists).
- **SC-009**: All read rows are retained after reconciliation regardless of the verdict — a three-row statement that yields NEEDS_REVIEW still reports three rows (0 rows dropped) — and no outcome ever removes a transaction.
- **SC-010**: Every outcome carries an audit detail with the numbers (or reason) behind it — the read sums and printed totals compared (primary), the expected and computed change (fallback), or the no-totals reason (neutral).
- **SC-011**: The two printed-total-bearing readers (Yes/Kiwi and IOB) surface their printed debit and credit totals equal to the statement's printed figures, while their rows, directions, dates, card last-4, and billing period stay byte-for-byte unchanged (verified against their existing golden fixtures).
- **SC-012**: 100% of the check's monetary values (sums, totals, balances, changes, tolerance) are exact decimals; no value is ever a floating-point number.
- **SC-013**: Given identical input, the check returns identical output across repeated runs (100% reproducible).
- **SC-014**: The golden vectors for all three verdicts reproduce exactly and the parity harness passes; re-running is stable.
- **SC-015**: The reconcile verdict and audit detail are reachable over the existing UniFFI bridge to Swift (a reconcile entry point taking a parsed statement), demonstrated by a Swift bridge test that distinguishes RECONCILED, NEEDS_REVIEW, and neutral.
- **SC-016**: Zero outbound network connections occur during the entire reconciliation path, verified by the automated privacy-egress test.
- **SC-017**: The change is scoped to the reconciliation check, two printed-total fields on the statement model, the Yes/Kiwi and IOB reader enrichments, the golden-fixture extensions and reconcile parity cases, one bridge export, and a Swift bridge test — adding **no** new runtime dependency and no new shared engine helper beyond these (verified by review of the change set).
- **SC-018**: All automated checks required to merge pass (green), including the parity harness and the privacy-egress test, with the iOS Local Verification Gate and CI green; and no secrets, network entitlements, telemetry, copyleft-licensed dependencies, or new runtime dependencies are added by the feature (verified by review of manifests and dependencies).

## Assumptions

- **Behaviour is fully pinned by the web engine**: This is a behaviour-parity port. `reconciliation.py` (the `reconcile` function), its unit tests (`test_reconciliation.py`), the integration tests (`test_statement_reconciliation.py`), and the two readers' printed-total scrapes (`yes_kiwi.py`, `iob.py`) are the source of truth; open details are resolved by matching the web engine rather than by clarification. The concrete on-device design (module layout, types, bridge mechanics, fixture format) is decided in `/speckit.plan`, not here.
- **Three-way outcome representation**: The hard requirement is three distinct, non-conflatable outcomes with the neutral "no balance" state explicitly **not** equal to NEEDS_REVIEW (the web engine returns `RECONCILED` / `NEEDS_REVIEW` / a neutral `None`). The exact on-device typing (e.g., an optional two-variant status, or a three-variant enum) is a `/speckit.plan` decision.
- **Tolerance**: The rupee-rounding tolerance is ₹1.00 and the comparison is inclusive (a difference of exactly ₹1.00 is within tolerance), matching the web engine.
- **Precedence & tiers**: If any printed debit/credit total is present, the primary check is used and the opening→closing fallback is never consulted. The fallback is used only when no printed debit/credit totals are present **and** both an opening and a closing balance are present. Otherwise the neutral outcome is returned.
- **Printed-total fields added; balance fields reused**: The parsed-statement model gains a printed **debit-total** and **credit-total** field. The printed **opening** and **closing** balance fields the fallback needs already exist on the model (added by the bank-ledger balance-chain work) and are reused unchanged.
- **Only two readers print totals**: In the web engine, exactly two of the six credit-card readers print per-statement debit/credit totals — Yes/Kiwi and IOB — and this slice surfaces those. The other four (ICICI, HDFC, SBI, Federal/Scapia) print none and correctly produce the neutral outcome. The web engine's `printed_total_spend` field is not used by reconciliation and is **not** added by this slice.
- **Fallback exercised via a constructed statement**: No shipped credit-card reader currently populates opening/closing balances, so the opening→closing fallback path is exercised via a constructed statement (as the web unit test does). It is ported for byte-for-byte parity and for any future reader that prints balances rather than category totals.
- **Reconciliation runs over all read rows and never drops any**: The check sums over the full parsed-row set (before any dedup/persistence subset) and is read-only; it never removes, mutates, or reorders rows. The web integration test's guarantee that rows are retained even on NEEDS_REVIEW is preserved at the check level (persistence itself is out of scope — see below).
- **Audit detail content preserved**: The audit detail conveys the same information as the web engine's detail payload (read debit/credit sums and the printed totals compared; or expected and computed balance change; or the no-totals reason). The exact field layout and naming are a `/speckit.plan` decision.
- **Counterpart to balance-chain**: Reconciliation is exposed and tested the same way as the shipped balance-chain check — a pure function over the shared parsed-statement type, reachable over the existing UniFFI bridge, with per-verdict golden/parity cases and a Swift bridge test. Concrete binding mechanics belong in `/speckit.plan`.
- **Fixtures location**: The Yes/Kiwi and IOB golden fixtures under `fixtures/yes/credit_card/` and `fixtures/iob/credit_card/` are extended with their printed totals (the IOB fixture already carries the `ACCOUNT SUMMARY` block; the Yes fixture's full text is extended with its printed-total lines). Additional mismatch and no-totals reconcile vectors are added; the fixtures are the source of truth for parity.
- **Reused, not rebuilt**: The parsed-statement / parsed-transaction output types, the exact-decimal money type, the golden-fixture JSON parity harness, the UniFFI bridge, and the privacy-egress gate were all built in earlier slices; reconciliation plugs into each unchanged.
- **No new dependencies**: This slice should require **no** new runtime dependencies.
- **No new UI required**: This is an engine slice; no user-facing UI is required to deliver it. Surfacing the verdict in the app (a "needs review" indicator, an audit-detail view) is a later, native step. If a trivial demo surface is added, it follows HIG and accessibility (FR-030).
- **Data safety**: All fixture and test data is synthetic or fully redacted — no real account data.
- **Money & polarity**: Amounts, totals, balances, and the tolerance are exact decimals (never floating-point); each row's debit/credit direction is read as already decided (from the statement's own Dr/Cr marker for credit cards) and reconciliation never re-derives it from an amount's sign.

### Dependencies

- **Kaname Constitution v1.0.0** — privacy (zero-network free/core), determinism, a pure platform-agnostic core (no PDF engine), decimal money with explicit polarity, Apache-2.0 open-core with no copyleft, native HIG/accessibility, and the test-first iOS Local Verification Gate (including the privacy-egress gate).
- **Bank-ledger balance-chain slices already landed (007–010)** — the shipped bank-account trust signal (`Reconciled` / `NeedsReview` + suspects) that reconciliation is the credit-card counterpart to, and whose result-plus-audit-detail shape and bridge exposure this mirrors.
- **Credit-card reader slices already landed (ICICI, HDFC, SBI, Yes / Kiwi, Federal / Scapia, IOB)** — the six readers whose parsed output reconciliation consumes; specifically the Yes / Kiwi (005) and IOB (011) readers, whose deferred printed-total carve-out this slice lifts, and the four no-total readers whose neutral outcome this slice verifies.
- **Shared engine foundations** — the parsed-statement / parsed-transaction domain types, the exact-decimal money type, the golden-fixture parity harness, the UniFFI Rust↔Swift bridge, and the privacy-egress gate.
- **Web engine reconciliation source of truth** — `reconciliation.py`, `test_reconciliation.py`, `test_statement_reconciliation.py`, and the Yes/Kiwi and IOB readers' printed-total scrapes, used as the parity source of truth.

## Out of Scope

Deferred to later slices / milestones, or explicitly excluded:

- **Persistence / storage of the verdict** — the web integration test writes a `reconciliation_status` (and detail) onto a persisted statement row; this slice ports only the **pure reconciliation check** plus its golden-fixture parity and bridge reachability. Storing the verdict in the encrypted local store (and any `uploaded_statements`-style schema) is a later persistence slice.
- **Any UI screens** — surfacing the verdict, a "needs review" indicator, or an audit-detail view in the app is a later, native step; this slice is engine-only.
- **Changing how rows are parsed** — row extraction, direction/polarity decisions, dates, amounts, card last-4, and billing period are unchanged; this slice only **adds** the two printed-total fields (Yes/Kiwi and IOB) and the reconciliation check that consumes them.
- **Porting the bank-ledger balance-chain** — already shipped (007–010); this slice is its credit-card counterpart, not a re-port.
- **The web engine's `printed_total_spend` field** — not used by reconciliation and not added.
- **Coverage / billing-period timeline**, **cross-source de-duplication and transfer detection**, and any further ingestion checks — separate later slices.
- **Encrypted SQLite / SQLCipher persistence** and key management.
- **AI-fallback parsing**, any **premium / cloud features**, and **app-side PDF text extraction** (PDFKit wiring) / the **file-import UI / Share Extension** — native or later-milestone concerns. This slice focuses on the on-device reconciliation check, the two readers' printed-total surfacing, golden-fixture parity across the three verdicts, and bridge reachability, reusing the existing privacy gate and exposed over the existing bridge.
- **No new runtime dependencies** are introduced by this slice.
