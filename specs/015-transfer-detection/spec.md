# Feature Specification: On-Device Transfer (Self-Transfer) Detection — the Pure Deterministic Pairing of Opposite-Direction Cross-Account Rows into Self-Transfer / Credit Card Bill Payment Pairs

**Feature Branch**: `015-transfer-detection`  
**Created**: 2026-07-20  
**Status**: Draft  
**Milestone**: P2 (engine port) — the self-transfer-pairing piece of the web engine's ingestion layer, alongside the already-shipped balance-chain, reconciliation, cross-source de-duplication, and coverage-map slices.  
**Input**: User description: "On-device transfer (self-transfer) detection — the pure, offline subset of the web engine's `app/services/ingestion/transfer_detector.py`. Port the *deterministic pairing logic* into the Rust core as a pure single-pool matcher: anchor on outflows (Debits) in ascending (date, id) order, greedily claim the best opposite-direction (Credit/inflow) counterpart on a different account within ±1 day and ±₹1.00 (inclusive), resolve ambiguity by the deterministic tuple `(date_diff, amount_diff, -narration_similarity, id)`, and report each pair with an `is_credit_card_payment` flag and a float confidence `score`. All DB/persistence concerns stay platform-side. Pinned byte-for-byte to the web engine's pure helpers."

> **Note on priority labels**: This feature sits in product milestone **P2** (engine port). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P2" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

The engine already imports statements (ten readers), verifies their internal integrity (the bank-ledger **balance-chain** and the credit-card **reconciliation** checks), recognises the same purchase across sources (**cross-source de-duplication**), and shows the **shape of imported history** (the **coverage map**). What it still cannot do is recognise when a person is **moving their own money between their own accounts**. When someone pays a credit-card bill (a Debit in the bank ledger paired with a "payment received" Credit on the card statement) or does a NEFT from one bank account to another, **two rows** appear — one **Debit (outflow)** and one **Credit (inflow)** — on **two different accounts**, close in **date** and **amount**. Left alone, the engine double-counts these as spend *and* income.

This slice delivers **transfer (self-transfer) detection**: a **pure single-pool matcher** that pairs those opposite-direction cross-account rows so the platform can tag them as an **internal transfer** instead of double-counting them. It ports the *deterministic pairing logic* of the web engine's `transfer_detector.py` — its pure helpers `_narration_similarity` and `_score`, its ±1-day / ±₹1 tolerance envelope, and its outflow-anchored greedy selection — into the on-device core. Its behaviour is **fully pinned** by the proven web engine (Constitution Principle V); this port reproduces it exactly.

The matcher operates over **one list** of already-parsed, still-unpaired transactions — it is **not** a two-list API. Each input row carries a **stable id**, an **account id**, a **direction** (inflow/outflow), a **date**, an **amount** (the shared Decimal money type), a raw **description**, and an **is_credit_card** flag. The matcher **anchors on outflows only**, processed in ascending **(date, id)** order. For each still-unpaired anchor it selects the best opposite-direction **inflow** counterpart on a **different account** that falls within **±1 day** *and* **±₹1.00** (both bounds inclusive), **greedily claims** both rows (each row is paired at most once), and moves on. When more than one counterpart is eligible, ambiguity is resolved by the deterministic selection tuple **`(date_diff, amount_diff, -narration_similarity, id)`** — lowest wins — where `narration_similarity` is **token-level Jaccard on the raw lowercased description (whitespace-split)**, i.e. the web `_narration_similarity`. (This is **deliberately DISTINCT** from the de-dup slice's `normalize_narration` + Jaro-Winkler; the two must not be conflated.)

Each detected pair reports the **outflow id**, the **inflow id**, an **`is_credit_card_payment`** flag (true when **either** leg is a credit-card account — the web's "Credit Card Bill Payment" vs "Self Transfer" split), and a **float confidence `score`** = `max(0, 1 − 0.2·date_diff − 0.2·amount_diff + 0.2·narration_similarity)` (the web `_score`). The score is a **confidence metric, not money**, so a float is constitutionally fine here. Output pairs are ordered by the anchor's **(date, id)**.

Like the checks it joins, the matcher is **pure** and **on-device**: no network, no clock, no locale, no database, no hidden state (Constitution Principles I & II). It reuses the shared money/date types, the golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate, and adds **no new runtime dependency**. Every DB/persistence concern — writing `transfer_group_id`/`is_transfer`, the "Self Transfer" / "Credit Card Bill Payment" category get-or-create, audit events, the optimistic-concurrency race handling, cross-user filtering, and the email-parse `match_window_days` override — stays **platform-side**, exactly mirroring the web engine's DB layer.

### User Story 1 - Pair a self-transfer across two accounts (Priority: P1)

For one person's still-unpaired rows, the matcher pairs an **outflow** on one account with the matching **inflow** on a **different** account when they are close in **date** (within ±1 day) and **amount** (within ±₹1.00) — so a credit-card bill payment or a bank-to-bank NEFT is recognised as a single internal transfer rather than counted as both spend and income.

**Why this priority**: This is the headline value and the smallest slice that delivers the transfer signal — the recognition that money moved between the user's own accounts. Every other story refines, qualifies, or proves this pairing.

**Independent Test**: Give the matcher two rows — an outflow of ₹5,000.00 on account A dated 2026-06-01 and an inflow of ₹5,000.00 on account B dated 2026-06-01 — and confirm exactly one pair is returned linking the two ids, with no network access.

**Acceptance Scenarios**:

1. **Given** an outflow of ₹5,000.00 on account A dated `2026-06-01` (narration "NEFT TO HDFC SALARY ACCOUNT") and an inflow of ₹5,000.00 on account B dated `2026-06-01` (narration "NEFT FROM ICICI"), **When** detection runs, **Then** exactly **one** pair is returned linking the outflow and inflow ids.
2. **Given** an outflow of ₹1,000.00 on account A dated `2026-06-01` and an inflow of ₹1,000.50 on account B dated `2026-06-02` (one day later, ₹0.50 apart — both within tolerance), **When** detection runs, **Then** exactly **one** pair is returned linking the two ids.

---

### User Story 2 - Never pair non-transfers (no false positives) (Priority: P2)

Rows that are **not** two legs of the same movement are **left unpaired**: an amount difference greater than ₹1.00, a date difference greater than 1 day, two rows in the **same direction**, or two rows on the **same account** never form a pair — so unrelated spend and income are never silently merged.

**Why this priority**: A transfer detector that over-pairs is worse than none — it hides real spend or income. The tolerance envelope, the opposite-direction requirement, and the different-account requirement are exactly what keep the signal trustworthy. This rides directly on US1.

**Independent Test**: Feed the matcher each near-miss in isolation (amount drift > ₹1, date drift > 1 day, same-direction, same-account) and confirm zero pairs are returned in every case.

**Acceptance Scenarios**:

1. **Given** an outflow of ₹1,000.00 and an inflow of ₹1,500.00 on different accounts on the same date (₹500 apart), **When** detection runs, **Then** **no** pair is returned (amount drift exceeds ±₹1.00).
2. **Given** an outflow on `2026-06-01` and an inflow of the same amount on a different account on `2026-06-05` (4 days later), **When** detection runs, **Then** **no** pair is returned (date drift exceeds ±1 day).
3. **Given** two rows of the same amount on different accounts on the same date but **both outflows**, **When** detection runs, **Then** **no** pair is returned (same direction).
4. **Given** an outflow and an inflow of the same amount on the same date but on the **same account**, **When** detection runs, **Then** **no** pair is returned (same account).

---

### User Story 3 - Resolve ambiguous candidates deterministically (Priority: P3)

When an anchor has **more than one** eligible counterpart, the matcher picks the best one **deterministically** by the selection tuple `(date_diff, amount_diff, -narration_similarity, id)` — preferring the closest date, then the closest amount, then the **most similar narration**, and finally the **lowest id** — so the same inputs always yield the same pairing regardless of candidate ordering.

**Why this priority**: Determinism is a constitution gate (Principle II) and a correctness property: two runs (or two devices) over the same rows must produce identical pairs. The narration-similarity tiebreak and the final id tiebreak are what make the choice reproducible when date and amount alone don't decide it.

**Independent Test**: Give an anchor two counterparts identical in date and amount — one with a closer narration, one unrelated — and confirm the closer-narration one is chosen; then give it two counterparts identical in date, amount, and narration and confirm the lower id is chosen.

**Acceptance Scenarios**:

1. **Given** an outflow (narration "NEFT TO HDFC BANK XX1234") and **two** inflows on a different account, same date and same amount — one narrated "NEFT FROM ICICI BANK XX5678" and one narrated "SALARY CREDIT FROM ACME CORP" — **When** detection runs, **Then** the anchor is paired with the **closer-narration** inflow ("NEFT FROM ICICI BANK XX5678").
2. **Given** an outflow and **two** inflows on a different account, identical in date, amount, **and** narration, **When** detection runs, **Then** the anchor is paired with the inflow having the **lowest id** (final tiebreak).

---

### User Story 4 - Distinguish a credit-card bill payment from a plain self-transfer (Priority: P4)

Each detected pair is flagged **`is_credit_card_payment = true`** when **either** leg is a credit-card account (a bank outflow paired with a card "payment received" inflow), and **false** when both legs are non-card accounts — mirroring the web engine's "Credit Card Bill Payment" vs "Self Transfer" category split, so the platform can categorise the pair correctly.

**Why this priority**: The card-payment flag is the one qualitative distinction the pure matcher carries beyond "these two rows pair". It lets the platform choose the right category downstream without re-deriving account types.

**Independent Test**: Pair a bank outflow with a credit-card inflow and confirm the pair's `is_credit_card_payment` is true; pair two bank rows and confirm it is false.

**Acceptance Scenarios**:

1. **Given** an outflow on a savings account paired with an inflow on a **credit-card** account within tolerance, **When** detection runs, **Then** the returned pair has **`is_credit_card_payment = true`**.
2. **Given** an outflow and an inflow on two **non-card** accounts within tolerance, **When** detection runs, **Then** the returned pair has **`is_credit_card_payment = false`**.

---

### User Story 5 - Report a confidence score for each pair (Priority: P5)

Every detected pair carries a **float confidence `score`** = `max(0, 1 − 0.2·date_diff − 0.2·amount_diff + 0.2·narration_similarity)` (the web `_score`), so the platform can rank or threshold pairs — higher for a same-day, same-amount, similarly-narrated match; lower as date/amount drift grows.

**Why this priority**: The score is an output field of every pair and part of the pinned web behaviour; it must be reproduced exactly for parity even though the platform (not the core) decides how to use it. It is explicitly a confidence metric, **not money**, so a float is correct.

**Independent Test**: For a same-day, same-amount pair with a partly-overlapping narration, confirm the reported score equals `max(0, 1 − 0.2·0 − 0.2·0 + 0.2·similarity)` for the computed token-Jaccard similarity, reproduced to the fixture's precision.

**Acceptance Scenarios**:

1. **Given** a detected pair with `date_diff = 0`, `amount_diff = 0`, and narration similarity `s`, **When** the score is computed, **Then** it equals `max(0, 1 + 0.2·s)` capped by the formula (i.e. `1 + 0.2·s` before the floor), reproduced exactly from the pinned formula.
2. **Given** a detected pair whose date/amount drift is large enough that the formula would go negative, **When** the score is computed, **Then** it is floored at **0** (never negative).

---

### User Story 6 - Greedy single-claim and deterministic pair ordering (Priority: P6)

Each row is claimed **at most once**: an inflow already paired with an earlier anchor is not available to a later one, and anchors are processed in ascending **(date, id)** order so the **earliest** competing outflow wins a contested inflow. The returned pairs are ordered by the anchor's **(date, id)**.

**Why this priority**: Greedy single-claiming is what keeps a row from appearing in two pairs, and the stable anchor order is what makes the *set* of pairs (not just each pair) deterministic. This pins the whole-list behaviour, not just the single-pair behaviour.

**Independent Test**: Give **two** outflows that are both eligible for the **same single** inflow; confirm the earlier anchor (by date, id) claims the inflow and the later outflow is left unpaired; confirm the output pair list is ordered by anchor (date, id).

**Acceptance Scenarios**:

1. **Given** two eligible outflows and a single eligible inflow they both match, **When** detection runs, **Then** the **earlier** anchor (by `(date, id)`) is paired with the inflow and the later outflow is **unpaired** — the inflow appears in **exactly one** pair.
2. **Given** several detected pairs, **When** the result is returned, **Then** the pairs are ordered by the anchor's **(date, id)**.

---

### User Story 7 - Reachable across the Rust↔Swift bridge, with no new engine infrastructure (Priority: P7)

The matcher is delivered as a **pure function** over shared types, exposed over the existing UniFFI bridge exactly as the balance-chain, reconciliation, de-dup, and coverage entry points are — reusing the shared money/date types, the parity harness, the bridge, and the privacy gate, and adding **no new runtime dependency**.

**Why this priority**: This re-confirms the fixtures-driven engine architecture scales to the transfer layer as a clean drop-in (a matcher module + input/output types + a bridge export + a golden fixture + a Swift test), validating that no shared engine internals need rebuilding.

**Independent Test**: Confirm the matcher is a pure function reachable over the bridge, taking the single transaction list and returning the pairs, reusing the shared money/date types and parity harness, adding no new dependency and no new shared helper beyond the matcher and its types.

**Acceptance Scenarios**:

1. **Given** the matcher, **When** it is invoked over the bridge, **Then** it takes the single list of transactions and returns the detected pairs (each with outflow id, inflow id, `is_credit_card_payment`, and `score`), mirroring how the other checks are exposed to Swift.
2. **Given** the change set, **When** it is reviewed, **Then** it adds **no** new runtime dependency and no new shared engine helper beyond the transfer matcher and its types.

---

### User Story 8 - Proven byte-for-byte against a golden fixture (Priority: P8)

The transfer behaviour is proven against a **golden vector** captured from a **live run of the real web engine's pure helpers** (`_narration_similarity`, `_score`, the ±1-day / ±₹1 tolerances) — never the DB-backed integration tests — covering all nine acceptance scenarios and reproduced exactly by the on-device matcher.

**Why this priority**: Golden-fixture parity is the constitution's proof mechanism (Principle V) and the regression guard for the whole feature. Capturing from the pure helpers (not the DB path) keeps the fixture free of persistence concerns that are out of scope here.

**Independent Test**: Load the golden fixture (an input transaction list + the expected pairs, each with its ids, `is_credit_card_payment`, and `score`) and confirm the matcher reproduces the expected pairs exactly, in order.

**Acceptance Scenarios**:

1. **Given** the golden fixture under `fixtures/transfer/`, **When** the matcher runs, **Then** the returned pairs match the expected outflow/inflow ids, `is_credit_card_payment` flags, and `score` values exactly, in the expected order.
2. **Given** the fixture, **When** the matcher is re-run, **Then** it yields identical output (deterministic).

---

### User Story 9 - Privacy: zero network in the transfer path (Priority: P9)

The entire transfer-detection computation runs 100% on-device with zero network I/O, and the automated privacy-egress gate covers it.

**Why this priority**: Privacy is the non-negotiable first principle; the transfer path must be provably local.

**Independent Test**: Run the privacy-egress gate and confirm no networking crate enters the shipped graph and no network access occurs in the transfer path.

**Acceptance Scenarios**:

1. **Given** the transfer-detection computation, **When** it runs, **Then** zero outbound network connections occur.
2. **Given** the shipped dependency graph, **When** the privacy-egress gate runs, **Then** it reports no networking crate.

---

### Edge Cases

- **No outflows / empty input**: an empty list, or a list with no outflows, yields **zero** pairs (no crash).
- **Anchor with no eligible counterpart**: an outflow with no opposite-direction, different-account, in-tolerance, still-unpaired inflow is left **unpaired** and emits no pair.
- **Inclusive tolerance boundaries**: a counterpart exactly **1 day** away or exactly **₹1.00** away is **within** tolerance (paired); **2 days** away or **₹1.01** away is **outside** (not paired). Both bounds are inclusive.
- **Contested inflow**: when two eligible outflows match one inflow, the **earlier** anchor by `(date, id)` claims it; the later outflow finds it already claimed and is left unpaired.
- **Id-only tiebreak**: two candidates identical in date, amount, and narration are separated by the **lowest id** (the final component of the selection tuple).
- **Empty / blank descriptions**: a missing or whitespace-only description yields a narration similarity of **0.0** (no crash); such rows can still pair on date + amount alone.
- **Card leg on either side**: `is_credit_card_payment` is true when the **outflow leg** OR the **inflow leg** (or both) is a credit-card account.
- **Score floor**: the confidence score is floored at **0** — it is never negative, however large the date/amount drift.
- **Money vs score types**: amounts and the ±₹1 tolerance are compared using the **exact Decimal money type**; only the confidence **score** is a float (it is not money).
- **Determinism**: identical inputs always produce identical output; the core reads no wall-clock, locale, or hidden state.

## Requirements *(mandatory)*

### Functional Requirements

**Matcher shape — inputs and outputs**

- **FR-001**: The engine MUST provide a **pure single-pool matcher** over **one** list of already-parsed, still-unpaired transactions — **not** a two-list API. Each input transaction MUST carry: a **stable id**, an **account id**, a **direction** (inflow / outflow), a **date**, an **amount** (the shared Decimal money type), a raw **description**, and an **is_credit_card** flag.
- **FR-002**: The matcher MUST return a list of detected **pairs**; each pair MUST carry the **outflow id**, the **inflow id**, an **`is_credit_card_payment`** flag, and a float confidence **`score`**. The returned pairs MUST be **ordered by the anchor's `(date, id)`**.

**Matching rules (pinned to the web `transfer_detector.py` pure subset)**

- **FR-003**: The matcher MUST **anchor on outflows only**, processing anchors in ascending **`(date, id)`** order.
- **FR-004**: For each still-unpaired anchor, the matcher MUST select the best **opposite-direction** counterpart (an **inflow** for an outflow anchor) on a **different account** whose date is within **±1 day** of the anchor AND whose amount is within **±₹1.00** of the anchor — **both bounds inclusive**.
- **FR-005**: The matcher MUST be **greedy and single-claim**: on selecting a counterpart it MUST claim **both** rows, and each row MUST be paired **at most once**; an anchor or counterpart already claimed MUST NOT be reused.
- **FR-006**: A candidate MUST be treated as **ineligible** (never paired with the anchor) when any of these holds: it is in the **same direction** as the anchor; it is on the **same account** as the anchor; its date is **more than 1 day** from the anchor; its amount is **more than ₹1.00** from the anchor; or it has **already been claimed**.
- **FR-007**: When more than one candidate is eligible, the matcher MUST resolve the choice by the deterministic **selection tuple `(date_diff, amount_diff, -narration_similarity, id)`**, where **lowest wins** — preferring smallest date difference, then smallest amount difference, then **highest** narration similarity, then **lowest id** as the final tiebreak.
- **FR-008**: **`narration_similarity`** MUST be **token-level Jaccard similarity on the raw lowercased description**, split on whitespace (the web `_narration_similarity`): the size of the token intersection divided by the size of the token union, and **0.0** when either description is empty or has no tokens. This MUST remain **distinct** from the de-dup slice's `normalize_narration` + Jaro-Winkler measure; the two MUST NOT be conflated.
- **FR-009**: A pair's **`is_credit_card_payment`** flag MUST be **true** when **either** leg's `is_credit_card` flag is true (the web "Credit Card Bill Payment" case), and **false** otherwise (the "Self Transfer" case).
- **FR-010**: A pair's **`score`** MUST equal **`max(0, 1 − 0.2·date_diff − 0.2·amount_diff + 0.2·narration_similarity)`** (the web `_score`), where `date_diff` is the absolute whole-day difference and `amount_diff` is the absolute amount difference between the two legs. The score MUST be floored at **0** and MUST NOT be negative.

**Money, purity & determinism**

- **FR-011**: Amounts and the **±₹1.00** tolerance MUST be represented and compared with the shared **Decimal** money type (Constitution Principle II — money is never a float). Only the confidence **`score`** is a float, because it is a confidence metric and not money.
- **FR-012**: The matcher MUST be **pure and deterministic**: given the same input list it MUST produce the same pairs; it MUST NOT read the wall-clock, locale, files, a database, the network, or any hidden global state.

**Counterpart to the shipped checks — reuse & platform boundary**

- **FR-013**: The transfer matcher MUST be the ingestion counterpart of the already-shipped balance-chain / reconciliation / de-dup / coverage checks, reusing the shared money/date types, the golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate. It MUST add **no** new runtime dependency and **no** new shared engine helper beyond the matcher, its input/output types, and (if needed) the narration-similarity/score helpers it defines internally.
- **FR-014**: The matcher MUST remain pure and MUST NOT read files, query a database, aggregate from a store, extract PDF text, or filter by user — it operates only on the **single in-memory transaction list** it is given (already scoped to one user by the platform).

**Bridge exposure**

- **FR-015**: The matcher MUST be reachable over the existing UniFFI bridge with an entry point that accepts the **single transaction list** and returns the detected pairs (each with outflow id, inflow id, `is_credit_card_payment`, and `score`), mirroring how the balance-chain, reconciliation, de-dup, and coverage checks are exposed to Swift.

**Scope exclusions (stay platform-side, mirroring the web engine's DB layer)**

- **FR-016**: This slice MUST NOT implement any of: persistence of **`transfer_group_id`** / **`is_transfer`**; the **category get-or-create** for "Self Transfer" / "Credit Card Bill Payment"; **audit events**; the optimistic-concurrency **`_claim_pair`** / SAVEPOINT **race handling**; **cross-user filtering** (the core is handed exactly one user's rows); the **`match_window_days`** email-parse date-tolerance override (the core uses the fixed ±1-day window — a later slice may parameterize it); any **database, SQL, persistence, or aggregation**; the **HTTP endpoint** / API surface; or any **UI**.

**Privacy (Constitution Principle I — NON-NEGOTIABLE)**

- **FR-017**: The entire transfer-detection path MUST run 100% on-device with **ZERO network I/O**.
- **FR-018**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting into the engine or the app.
- **FR-019**: The existing automated **privacy-egress test** MUST cover the transfer path and assert it performs no network access.

**Parity & test-first (Constitution Principle V)**

- **FR-020**: The web engine's `transfer_detector.py` **pure subset** — `_narration_similarity`, `_score`, the ±1-day / ±₹1.00 tolerance envelope, the outflow-anchored greedy selection, and the `(date_diff, amount_diff, -narration_similarity, id)` selection tuple — MUST be the **pinned source of truth** and MUST be reproduced **exactly**.
- **FR-021**: A **golden vector** captured from a **live run of the real web engine's pure helpers** (never the DB-backed integration tests) MUST cover the nine acceptance scenarios (matched pair; within-tolerance pair; amount-drift reject; date-drift reject; same-direction reject; same-account reject; narration-tiebreak resolution; id-tiebreak resolution; credit-card-payment flag), and MUST be reproduced exactly by the on-device matcher. Deliverables MUST include the golden fixture under **`fixtures/transfer/`**, a parity Case/loader plus a `#[test]` in **`core/crates/kaname-core/tests/parity.rs`**, and a Swift bridge test in **`ios/Tests/`**.
- **FR-022**: All fixture and test data MUST be **synthetic or fully redacted** (fabricated ids, accounts, dates, amounts, narrations) — never real account data.
- **FR-023**: The behaviour introduced by this slice MUST be developed **test-first** (a failing golden/parity test precedes the behaviour).

**Licensing, secrets & quality gates**

- **FR-024**: The change MUST NOT add secrets, API keys, or private endpoints; MUST remain distributable under **Apache-2.0** with no copyleft (GPL/AGPL/LGPL) dependencies; and MUST introduce **NO** new runtime dependencies.
- **FR-025**: The change MUST keep the **iOS Local Verification Gate** and CI green: core formatting, linting, and tests; app linting; project generation; a simulator build with passing app tests; and the privacy gate.
- **FR-026**: If any user-facing surface is introduced for this slice, it MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility. (This slice introduces no UI.)

### Key Entities *(include if feature involves data)*

- **Transaction (input row)**: One already-parsed, still-unpaired transaction — a **stable id**, an **account id**, a **direction** (inflow / outflow), a **date**, an **amount** (Decimal money type), a raw **description**, and an **is_credit_card** flag.
- **Transaction pool (input)**: The single list of transactions for one user, over which the matcher runs (the platform scopes it to one user and to still-unpaired rows).
- **Transfer pair (output)**: One detected internal transfer — the **outflow id**, the **inflow id**, an **`is_credit_card_payment`** flag (either leg is a card), and a float confidence **`score`**.
- **Selection tuple**: The deterministic ordering key `(date_diff, amount_diff, -narration_similarity, id)` used to choose among eligible counterparts (lowest wins).
- **Narration similarity**: Token-level Jaccard on the raw lowercased, whitespace-split description (the web `_narration_similarity`); 0.0 when either side is empty.
- **Golden transfer vector**: A synthetic input transaction list paired with the expected output pairs (ids, `is_credit_card_payment`, `score`), captured from a live run of the web engine's pure helpers and reproduced exactly.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A same-day, same-amount, opposite-direction, different-account pair is detected as **exactly one** pair linking the two ids.
- **SC-002**: A counterpart at the **inclusive boundary** (exactly 1 day away or exactly ₹1.00 away) is paired; a counterpart just beyond (2 days or ₹1.01) is not — 0 boundary misclassifications.
- **SC-003**: Each near-miss yields **zero** pairs: amount drift > ₹1.00; date drift > 1 day; same-direction rows; same-account rows — no false positives.
- **SC-004**: With two eligible counterparts equal in date and amount, the one with **higher narration overlap** is chosen; with all three equal, the **lowest id** is chosen — deterministic, 0 ambiguity.
- **SC-005**: A pair where **either** leg is a credit-card account is flagged `is_credit_card_payment = true`; a pair of two non-card accounts is flagged false — 0 misclassifications.
- **SC-006**: Every pair's `score` equals `max(0, 1 − 0.2·date_diff − 0.2·amount_diff + 0.2·narration_similarity)`, reproduced to the fixture's precision, and is never negative.
- **SC-007**: Each row appears in **at most one** pair; when two outflows compete for one inflow, the earlier anchor (by `(date, id)`) claims it and the other outflow is left unpaired.
- **SC-008**: The returned pairs are ordered by the anchor's `(date, id)`.
- **SC-009**: Given identical input, the matcher returns identical output across repeated runs (100% reproducible); empty input and no-outflow input each yield 0 pairs with no crash; the core reads no wall-clock.
- **SC-010**: The golden vector (covering all nine acceptance scenarios) reproduces **exactly** — matching ids, `is_credit_card_payment`, `score`, and order — and the parity harness passes and is stable on re-run.
- **SC-011**: The matcher is reachable over the UniFFI bridge to Swift, demonstrated by a Swift bridge test that detects a transfer pair and reads its `is_credit_card_payment` flag and `score`.
- **SC-012**: **Zero** outbound network connections occur during the transfer path, verified by the automated privacy-egress test.
- **SC-013**: The change is scoped to the transfer matcher, its input/output types, one bridge export, a golden fixture under `fixtures/transfer/`, a parity case in `core/crates/kaname-core/tests/parity.rs`, and a Swift bridge test in `ios/Tests/` — adding **no** new runtime dependency (verified by review).
- **SC-014**: All automated checks required to merge pass (green), including the parity harness and the privacy-egress test, with the iOS Local Verification Gate and CI green; no secrets, network entitlements, telemetry, copyleft dependencies, or new runtime dependencies are added.

## Assumptions

- **Behaviour is fully pinned by the web engine**: the pure subset of `transfer_detector.py` (`_narration_similarity`, `_score`, the ±1-day / ±₹1.00 tolerances, the outflow-anchored greedy selection, and the `(date_diff, amount_diff, -narration_similarity, id)` tuple) is the source of truth; open details are resolved by matching the web engine. Ground truth is captured from a **live run of the real web engine's pure helpers** — never the DB-backed integration tests. The concrete on-device design (module layout, types, bridge mechanics, fixture format) is decided in `/speckit.plan`.
- **Single pool, single user**: the core is handed **one** list of one user's already-parsed, still-unpaired rows. Cross-user filtering (the web's Constitution III concern) stays **platform-side**; the core never filters by user.
- **Rows are pre-parsed and pre-tagged**: the platform supplies each row's id, account id, direction, date, amount, description, and `is_credit_card` flag. Parsing, de-duplication, and reconciliation happened in earlier slices; this matcher consumes their output.
- **Fixed ±1-day window**: the core uses the **fixed** ±1-day date tolerance. The web's `match_window_days` email-parse override (e.g. a tighter same-day window for `(EMAIL_ALERT, EMAIL_ALERT)` pairs) is **out of scope**; a later slice may parameterize the window.
- **Money is Decimal; the score is a float**: amounts and the ±₹1 tolerance use the shared Decimal type and are compared exactly. The confidence `score` is deliberately a **float** because it is a confidence metric, not money — which is constitutionally fine (Constitution Principle II governs *money*, not confidence scores).
- **Narration similarity is transfer's own measure**: token-level Jaccard on the raw lowercased, whitespace-split description — deliberately **DISTINCT** from the de-dup slice's `normalize_narration` + Jaro-Winkler. The two similarity measures must not be conflated.
- **The platform owns all side effects**: persisting `transfer_group_id` / `is_transfer`, the "Self Transfer" / "Credit Card Bill Payment" category get-or-create, audit events, and optimistic-concurrency race handling are the platform's responsibility. The core only **returns the detected pairs**; it never mutates or persists anything.
- **No money is computed**: the matcher pairs existing rows and reports a confidence score; it does not add, net, or transform monetary amounts.
- **No new dependencies**: the slice reuses existing shared infrastructure and adds no new runtime or dev dependency.

## Dependencies

- The already-shipped shared types (the transaction/money/date types), the golden-fixture parity harness (`core/crates/kaname-core/tests/parity.rs`), the UniFFI bridge, and the privacy-egress gate — all reused unchanged.
- The web engine's `transfer_detector.py` and its pure helpers as the pinned source of truth, plus a golden fixture captured from a live run of those helpers.
- No new runtime or dev dependency.

## Out of Scope

- Persistence of **`transfer_group_id`** / **`is_transfer`**, and any **database, SQL, persistence, or aggregation** (on-device persistence arrives in a later phase; the platform owns writes for now).
- The **category get-or-create** for "Self Transfer" / "Credit Card Bill Payment".
- **Audit events** for paired rows.
- The optimistic-concurrency **`_claim_pair`** / SAVEPOINT **race handling**.
- **Cross-user filtering** (the core is handed exactly one user's rows).
- The **`match_window_days`** email-parse date-tolerance override (the core uses the fixed ±1-day window; a later slice may parameterize it).
- The **HTTP endpoint** / API surface (web concern).
- Any **UI** (a transfer-review surface is a later app slice).
- New runtime or dev dependencies.
