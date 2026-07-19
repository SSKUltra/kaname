# Feature Specification: On-Device Statement Coverage Map (Rolling-24-Month GAP / PARTIAL / COVERED Classifier) — the Ingestion Trust Signal for "Which Months Are Fully Imported"

**Feature Branch**: `014-coverage`  
**Created**: 2026-07-19  
**Status**: Draft  
**Milestone**: P2 (engine port) — the coverage-map piece of the web engine's ingestion layer, alongside the already-shipped balance-chain, reconciliation, and cross-source de-duplication.  
**Input**: User description: "on-device statement coverage map (slice 014). Port the web engine's coverage.py — month_window(today, 24) + a GAP/PARTIAL/COVERED + needsReview classification over the rolling 24 months ending at the current month, for one account. Pure/on-device; the core never reads the wall-clock (today is passed in). The classifier takes today + per-statement facts (billing period-end + a needsReview flag) + per-transaction facts (date + whether it came from a full statement) and returns the 24 month entries. DB/persistence/aggregation is out of scope (the platform supplies the pre-aggregated facts). Behaviour is pinned by the web coverage.py."

> **Note on priority labels**: This feature sits in product milestone **P2** (engine port). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P2" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

The engine already imports statements (ten readers), verifies their internal integrity (the bank-ledger **balance-chain** and the credit-card **reconciliation** checks), and recognises the same purchase across sources (**cross-source de-duplication**). What a person still cannot see is the **shape of their imported history**: *which months are fully covered by a statement, which have only piecemeal live-alert data, and which are empty holes to backfill.*

This slice delivers that **coverage map**: for one account, over the **rolling 24 months** ending at the current month, it classifies each month as **GAP**, **PARTIAL**, or **COVERED**, and flags a **needsReview** badge on COVERED months whose statement run was incomplete or failed reconciliation. It ports the web engine's `coverage.py` — the `month_window` helper and the classification — into the pure, on-device core. Its behaviour is **fully pinned** by the proven web engine (Constitution Principle V); this port reproduces it exactly.

Because the on-device engine has **no local store yet** (encrypted persistence arrives later), and because the core must be **pure and deterministic** (no wall-clock, Constitution Principle II), the classifier takes its inputs **explicitly**: the **today** date (supplied by the platform — the core never reads the clock); a list of **statement facts** (one per imported statement: its billing **period-end** date plus a **needsReview** flag for that run); and a list of **transaction facts** (one per transaction: its **date** plus whether it came from a **full statement**). It returns the **24** month entries, oldest first, each with the month label, the state, and the needsReview flag. The platform (which owns aggregation/persistence) supplies the facts; the engine owns the deterministic classification.

Like the checks it joins, the coverage classifier is **pure** and **on-device**: no network, no clock, no locale, no hidden state (Constitution Principles I & II). It reuses the shared money/date types and the UniFFI bridge and adds **no new runtime dependency**.

### User Story 1 - See which of the last 24 months are covered, partial, or empty (Priority: P1)

For one account, the person gets a 24-entry map of the rolling two years ending at the current month, each month classified as **COVERED** (a full statement covers it), **PARTIAL** (only piecemeal transactions, no full statement), or **GAP** (nothing known) — so they can see at a glance which months are fully imported and which have holes to backfill.

**Why this priority**: This is the headline value and the smallest slice that delivers the coverage signal — the counterpart to the integrity checks already shipped. Every other story refines this map.

**Independent Test**: Give the classifier a `today`, one full statement covering month M, and one alert-only transaction in month N; confirm month M is COVERED, month N is PARTIAL, every other month in the 24-month window is GAP, and there are exactly 24 entries oldest-first — with no network access.

**Acceptance Scenarios**:

1. **Given** `today = 2026-06-14`, a statement with period-end `2026-05-16`, and an alert-only transaction on `2026-04-10`, **When** the map is computed, **Then** `2026-05` is **COVERED**, `2026-04` is **PARTIAL**, `2026-03` is **GAP**, and there are exactly **24** entries.
2. **Given** the same inputs, **When** the map is computed, **Then** the entries are ordered **oldest first**, from `2024-07` to `2026-06`.
3. **Given** a month with no transactions and no statement, **When** the map is computed, **Then** that month is **GAP** with needsReview false.

---

### User Story 2 - Flag COVERED months whose statement run needs review (Priority: P2)

A COVERED month whose directly-imported statement run was **incomplete (PARTIAL)** or **failed reconciliation (NEEDS_REVIEW)** carries a **needsReview** badge, so the person knows that although the month is covered, its data may not be trustworthy and warrants a second look.

**Why this priority**: Coverage without a trust qualifier would present a month as fully imported even when its statement didn't reconcile. The needsReview badge is what connects the coverage map to the reconciliation/partial-run signals. It rides on top of US1.

**Independent Test**: Give the classifier a statement covering month M with its needsReview flag set; confirm M is COVERED with needsReview true, while an unflagged statement's month is COVERED with needsReview false.

**Acceptance Scenarios**:

1. **Given** `today = 2026-06-14` and a statement with period-end `2026-02-28` whose run needs review, **When** the map is computed, **Then** `2026-02` is **COVERED** with **needsReview true**.
2. **Given** a statement with period-end `2026-05-16` whose run does **not** need review, **When** the map is computed, **Then** `2026-05` is **COVERED** with **needsReview false**.
3. **Given** a PARTIAL or GAP month, **When** the map is computed, **Then** its needsReview is always **false**.

---

### User Story 3 - COVERED via a full-statement transaction, even without a directly-imported statement record (Priority: P3)

A month is **COVERED** not only when a directly-imported statement's period-end falls in it, but also when **any transaction in that month came from a full statement** (e.g. a forwarded/parsed statement's rows). Such a month, covered only via its transactions, carries **needsReview false** (there is no directly-imported statement run to qualify).

**Why this priority**: This is the second COVERED path in the pinned web logic and must be reproduced for parity. It distinguishes "covered because a statement said so" from "covered because full-statement transactions are present", and pins the needsReview default for the latter.

**Independent Test**: Give the classifier a month with a full-statement-sourced transaction but **no** statement record; confirm the month is COVERED with needsReview false; a month with only alert transactions stays PARTIAL.

**Acceptance Scenarios**:

1. **Given** `today = 2026-06-14` and a full-statement transaction on `2026-01-20` with no statement record for that month, **When** the map is computed, **Then** `2026-01` is **COVERED** with **needsReview false**.
2. **Given** a month whose only transactions are alert-sourced (not from a full statement) and no statement record, **When** the map is computed, **Then** that month is **PARTIAL**.

---

### User Story 4 - A deterministic, clock-free rolling 24-month window (Priority: P4)

The month window is the **24** "YYYY-MM" labels ending at **today**'s month, oldest first — computed **deterministically** from a `today` supplied by the platform. The core **never reads the wall-clock**, so the same inputs always produce the same map.

**Why this priority**: Determinism is a constitution gate (Principle II) and a correctness property of the whole feature. Passing `today` in (rather than reading the clock) is what makes the classifier pure and testable.

**Independent Test**: Compute the window for a fixed `today` twice and confirm identical 24-label output, oldest first, ending at `today`'s month; confirm no wall-clock is read.

**Acceptance Scenarios**:

1. **Given** `today = 2026-06-14`, **When** the window is computed, **Then** it is exactly `["2024-07", …, "2026-06"]` — 24 labels, oldest first.
2. **Given** any fixed `today`, **When** the map is computed twice, **Then** the two results are identical (deterministic).
3. **Given** a `today` on the first or last day of a month, **When** the window is computed, **Then** it still ends at `today`'s calendar month.

---

### User Story 5 - Reachable across the Rust↔Swift bridge, with no new engine infrastructure (Priority: P5)

The coverage classifier is delivered as a **pure function** over shared types, exposed over the existing UniFFI bridge exactly as the balance-chain, reconciliation, and de-dup entry points are — reusing the shared date type, the parity harness, the bridge, and the privacy gate, and adding **no new runtime dependency**.

**Why this priority**: This re-confirms the fixtures-driven engine architecture scales to the coverage layer as a clean drop-in (a classifier module + input/output types + a bridge export + a golden fixture + a Swift test), validating that no shared engine internals need rebuilding.

**Independent Test**: Confirm the classifier is a pure function reachable over the bridge, reusing the shared date type and parity harness, adding no new dependency and no new shared helper beyond the classifier and its types.

**Acceptance Scenarios**:

1. **Given** the classifier, **When** it is invoked over the bridge, **Then** it takes `today` + the two fact lists and returns the 24 month entries, mirroring how the other checks are exposed to Swift.
2. **Given** the change set, **When** it is reviewed, **Then** it adds **no** new runtime dependency and no new shared engine helper beyond the coverage classifier and its types.

---

### User Story 6 - Proven byte-for-byte against a golden fixture (Priority: P6)

The coverage behaviour is proven against a golden vector ported from the web engine that covers all three states plus both needsReview values, reproduced exactly by the on-device classifier.

**Why this priority**: Golden-fixture parity is the constitution's proof mechanism (Principle V) and the regression guard for the whole feature.

**Independent Test**: Load the golden fixture (a `today` + statement/transaction facts + the expected 24 month entries) and confirm the classifier reproduces the expected entries exactly.

**Acceptance Scenarios**:

1. **Given** the golden fixture with `today = 2026-06-14`, **When** the classifier runs, **Then** the 24 entries match the expected states and needsReview exactly (2026-01 COVERED/false, 2026-02 COVERED/true, 2026-04 PARTIAL, 2026-05 COVERED/false, the other 20 GAP).
2. **Given** the fixture, **When** the classifier is re-run, **Then** it yields identical output (deterministic).

---

### User Story 7 - Privacy: zero network in the coverage path (Priority: P7)

The entire coverage computation runs 100% on-device with zero network I/O, and the automated privacy-egress gate covers it.

**Why this priority**: Privacy is the non-negotiable first principle; the coverage path must be provably local.

**Independent Test**: Run the privacy-egress gate and confirm no networking crate enters the shipped graph and no network access occurs in the coverage path.

**Acceptance Scenarios**:

1. **Given** the coverage computation, **When** it runs, **Then** zero outbound network connections occur.
2. **Given** the shipped dependency graph, **When** the privacy-egress gate runs, **Then** it reports no networking crate.

---

### Edge Cases

- **Empty inputs**: no statements and no transactions → all 24 months are GAP, needsReview false; still exactly 24 entries.
- **Facts outside the window**: a statement or transaction older than the earliest window month is ignored; a transaction in a future month (beyond `today`) is not represented in any window label.
- **Month boundary attribution**: a statement is attributed to the calendar month of its **period-end**; a transaction to the calendar month of its **date**.
- **Multiple facts in one month**: needsReview for a month is the logical OR over the directly-imported statements attributed to it; a COVERED month is COVERED regardless of how many facts establish it.
- **COVERED precedence**: COVERED wins over PARTIAL when both a full-coverage signal and other transactions exist in the same month; PARTIAL wins over GAP when any transaction exists.
- **needsReview only from statements**: a month COVERED solely via full-statement transactions (no directly-imported statement record) has needsReview false even if it also has partial data.
- **Determinism**: identical inputs always produce identical output; the core reads no wall-clock, locale, or hidden state.

## Requirements *(mandatory)*

### Functional Requirements

**Window & classifier — inputs and outputs**

- **FR-001**: The engine MUST provide a pure coverage classifier that, given a `today` date and the pre-aggregated per-account facts, returns exactly **24** month entries (the rolling 24 months ending at `today`'s month), **oldest first**, each entry carrying the month label ("YYYY-MM"), the state (GAP / PARTIAL / COVERED), and a needsReview flag.
- **FR-002**: The engine MUST provide the month-window computation as the pure port of the web `month_window(today, count)`: `count` labels of the form "YYYY-MM", ending at `today`'s calendar month, oldest first (`month_window(2026-06-14, 24)` = `["2024-07", …, "2026-06"]`).
- **FR-003**: The classifier MUST take `today` as an explicit parameter and MUST NEVER read the wall-clock, locale, or any hidden global state — identical inputs MUST yield identical output (deterministic, pure).
- **FR-004**: The classifier's **statement facts** input MUST be a list where each entry carries a billing **period-end** date and a **needsReview** flag. Its **transaction facts** input MUST be a list where each entry carries a **date** and a **from-full-statement** flag.

**Classification rules (pinned)**

- **FR-005**: A month MUST be classified **COVERED** when it is covered by a full statement — either (a) a statement fact whose **period-end** falls in that month, OR (b) a transaction fact in that month whose **from-full-statement** flag is true.
- **FR-006**: A month that is not COVERED MUST be classified **PARTIAL** when it has at least one transaction fact; otherwise it MUST be classified **GAP**.
- **FR-007**: **needsReview** MUST be true **only** for a COVERED month that has at least one statement fact attributed to it whose needsReview flag is true (the logical OR over that month's statement facts). A month COVERED only via transaction facts (no statement fact) MUST have needsReview false. PARTIAL and GAP months MUST always have needsReview false.
- **FR-008**: A transaction fact MUST be attributed to the calendar month of its **date**, and a statement fact to the calendar month of its **period-end**.
- **FR-009**: Facts dated before the earliest month of the window (the first day of `window[0]`'s month) MUST be ignored; the map MUST still contain exactly the 24 window months.

**Counterpart to the shipped checks — reuse, purity & platform boundary**

- **FR-010**: The coverage classifier MUST be the ingestion counterpart of the already-shipped balance-chain / reconciliation / de-dup checks, reusing the shared date type, the golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate. It MUST add **no** new runtime dependency and **no** new shared engine helper beyond the classifier, the window helper, and their types.
- **FR-011**: The classifier MUST remain pure and MUST NOT read files, query a database, aggregate from a store, or extract PDF text — it operates only on the `today` date and the two in-memory fact lists it is given.

**Bridge exposure**

- **FR-012**: The coverage classifier MUST be reachable over the existing UniFFI bridge with an entry point that accepts `today` + the two fact lists and returns the 24 month entries, mirroring how the balance-chain, reconciliation, and de-dup checks are exposed to Swift.

**Scope exclusions**

- **FR-013**: This slice MUST NOT implement any of: a **database, persistence, or SQL**; the **aggregation** of transactions/statements from a store (the platform supplies the pre-aggregated facts); reading the **wall-clock**; the HTTP endpoint; account attribution beyond the single account the caller scopes its facts to; or any **UI**.

**Privacy (Constitution Principle I — NON-NEGOTIABLE)**

- **FR-014**: The entire coverage path MUST run 100% on-device with ZERO network I/O.
- **FR-015**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting into the engine or the app.
- **FR-016**: The existing automated privacy-egress test MUST cover the coverage path and assert it performs no network access.

**Parity & test-first (Constitution Principle V)**

- **FR-017**: The web engine's `coverage.py` (its `month_window` and its GAP/PARTIAL/COVERED + needsReview classification) MUST be the pinned source of truth and MUST be reproduced exactly, including the 24-month window, oldest-first ordering, the two COVERED paths, the needsReview rule, and the period-end / date month attribution.
- **FR-018**: A golden vector MUST cover all three states plus both needsReview values — reproduced exactly by the on-device classifier — and the `month_window` reference output MUST be pinned.
- **FR-019**: All fixture and test data MUST be synthetic or fully redacted (fabricated dates, states) — never real account data.
- **FR-020**: The behaviour introduced by this slice MUST be developed test-first (a failing golden/parity test precedes the behaviour).

**Licensing, secrets & quality gates**

- **FR-021**: The change MUST NOT add secrets, API keys, or private endpoints; MUST remain distributable under Apache-2.0 with no copyleft (GPL/AGPL/LGPL) dependencies; and MUST introduce NO new runtime dependencies.
- **FR-022**: The change MUST keep the iOS Local Verification Gate and CI green: core formatting, linting, and tests; app linting; project generation; a simulator build with passing app tests; and the privacy gate.
- **FR-023**: If any user-facing surface is introduced for this slice, it MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility.

### Key Entities *(include if feature involves data)*

- **Today (input)**: The reference date supplied by the platform; the window ends at its calendar month. The core never reads the clock.
- **Statement fact (input)**: One per imported statement — a billing **period-end** date and a **needsReview** flag (its run was incomplete or failed reconciliation).
- **Transaction fact (input)**: One per transaction — a **date** and a **from-full-statement** flag (whether it came from a full statement vs a piecemeal live alert).
- **Month coverage (output)**: One per window month — the month label ("YYYY-MM"), the **state** (GAP / PARTIAL / COVERED), and the **needsReview** flag.
- **Coverage map (output)**: The ordered list of 24 month-coverage entries, oldest first.
- **Golden coverage vector**: A synthetic `today` + statement/transaction facts paired with the expected 24 month entries, ported from the web engine and reproduced exactly.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The classifier returns exactly **24** month entries for any input, oldest first, ending at `today`'s month.
- **SC-002**: `month_window(2026-06-14, 24)` reproduces `["2024-07", …, "2026-06"]` exactly (24 labels, oldest first).
- **SC-003**: For the reference scenario (`today = 2026-06-14`; statement period-ends `2026-05-16` needsReview-false and `2026-02-28` needsReview-true; transactions `2026-04-10` alert, `2026-05-05` full-statement, `2026-01-20` full-statement), the classifier yields `2026-05` COVERED/false, `2026-02` COVERED/true, `2026-04` PARTIAL, `2026-01` COVERED/false, and the other 20 months GAP — 0 misclassifications.
- **SC-004**: A month covered only via a full-statement transaction (no statement fact) is COVERED with needsReview false; a month with only alert transactions is PARTIAL — verified.
- **SC-005**: needsReview is true only on COVERED months backed by a needs-review statement fact; PARTIAL and GAP months are always needsReview false — 0 violations.
- **SC-006**: Given identical inputs, the classifier returns identical output across repeated runs (100% reproducible); the core reads no wall-clock.
- **SC-007**: Empty inputs yield 24 GAP months (needsReview false) with no crash.
- **SC-008**: The golden vector reproduces exactly and the parity harness passes; re-running is stable.
- **SC-009**: The coverage map is reachable over the UniFFI bridge to Swift, demonstrated by a Swift bridge test that distinguishes GAP / PARTIAL / COVERED and both needsReview values.
- **SC-010**: Zero outbound network connections occur during the coverage path, verified by the automated privacy-egress test.
- **SC-011**: The change is scoped to the coverage classifier, the window helper, the input/output types, one bridge export, a golden fixture, a parity case, and a Swift bridge test — adding no new runtime dependency (verified by review).
- **SC-012**: All automated checks required to merge pass (green), including the parity harness and the privacy-egress test, with the iOS Local Verification Gate and CI green; no secrets, network entitlements, telemetry, copyleft dependencies, or new runtime dependencies are added.

## Assumptions

- **Behaviour is fully pinned by the web engine**: `coverage.py` (`month_window` + the classification loop) is the source of truth; open details are resolved by matching the web engine. Ground truth (the `month_window` labels and the reference-scenario classification) was captured from a live web-engine run. The concrete on-device design (module layout, types, bridge mechanics, fixture format) is decided in `/speckit.plan`.
- **Pre-aggregated facts supplied by the platform**: Because the on-device engine has no local store yet, the platform (which owns aggregation/persistence) supplies the per-account statement and transaction facts. The engine owns only the deterministic classification. When a store lands, the aggregation can move into the core without changing the classifier's behaviour.
- **`today` is a required parameter**: The core is pure and never reads the wall-clock (Constitution Principle II); the platform passes the current date.
- **Single-account scope**: The caller scopes the facts to one account; the classifier does not do cross-account attribution.
- **Rolling window fixed at 24 months**: Matching the web `COVERAGE_MONTHS = 24`. The window helper accepts a count for testability, but the coverage map uses 24.
- **needsReview semantics preserved**: needsReview comes only from directly-imported statement facts (its run was PARTIAL or failed reconciliation), never from transaction-only coverage — matching the web `stmt_by_month.get(label, False)` default.
- **No money involved**: Coverage classifies dates/states; no monetary values are computed, so the "money is never a float" rule has no comparison here (dates use the shared date type).

## Dependencies

- The already-shipped shared types (the transaction/date types), the golden-fixture parity harness, the UniFFI bridge, and the privacy-egress gate — all reused unchanged.
- No new runtime or dev dependency.

## Out of Scope

- Any **database, persistence, or SQL**, and the **aggregation** of transactions/statements from a store (the platform supplies pre-aggregated facts; on-device persistence arrives in a later phase).
- Reading the **wall-clock** (today is a parameter).
- The **HTTP endpoint** / API surface (web concern).
- **Cross-account** attribution beyond the single account the caller scopes.
- Any **UI** (the coverage map's visual surface is a later P3 app slice).
- New runtime or dev dependencies.
