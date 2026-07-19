# Feature Specification: Recognise the Same Purchase Across Two Sources On-Device — Cross-Source Transaction De-Duplication (the Pure In-Memory CANONICAL + FUZZY Matcher, Ported From the Web Engine Deduplicator, With No Database and No New Dependency)

**Feature Branch**: `013-cross-source-dedup`  
**Created**: 2026-07-19  
**Status**: Draft  
**Milestone**: P2 (engine port) — the next ingestion check after the shipped balance-chain and reconciliation trust signals; ports the **pure, in-memory subset** of the web engine's cross-source de-duplicator into the on-device Rust core (`kaname-core`)  
**Input**: User description: "on-device cross-source transaction de-duplication (slice 013). The web engine's de-duplicator is a database-backed async ladder (L1 source_ref, L2 exact-hash, L3 canonical, L4 fuzzy, L5 merchant, + amount-drift supersede) that queries a transactions table and depends on merchant resolution and persistence — none of which exist on-device yet. This slice ports only the pure, in-memory subset: a batch cross-source matcher that, given two already-parsed lists of transactions from different sources (e.g. a bank-account ledger and a credit-card statement — the same purchase can appear in both), identifies which transactions are duplicates of each other, using only the two layers that are portable without a database: (1) a CANONICAL layer — same date, same amount, same direction, and same normalised-narration prefix (first 60 chars of the web engine's normalise_narration); and (2) a FUZZY layer — same amount, same direction, dates within ±1 day, and Jaro-Winkler similarity ≥ 0.92 on their normalised narrations. The matcher is multiplicity-aware (each existing transaction is consumed by at most one incoming transaction; surplus genuine repeats survive), tries canonical before fuzzy per incoming transaction, and the first matching unconsumed existing transaction wins. Behaviour is pinned by the web engine's normalise_narration (normaliser.py) and L3/L4 logic (deduplicator.py) plus rapidfuzz Jaro-Winkler; ground truth has been captured (e.g. 'swiggy bangalore' vs 'swiggy bangaluru' = 0.95; 'amazon' vs 'amazon pay' = 0.92; 'acme corp' vs 'acme corporation' = 0.9125 → below; 'fine dining' vs 'fine dine' = 0.9232 → above) and a hand-rolled Jaro-Winkler reproduces those values byte-for-byte, so no new runtime dependency is added. Explicitly out of scope: any database/persistence; the L1 SOURCE_REF and L2 EXACT-hash layers; the L5 MERCHANT layer and all merchant resolution; the amount-drift SUPERSEDE behaviour; mutating/deleting/persisting rows; and any UI."

> **Note on priority labels**: This feature sits in product milestone **P2** (engine port, `docs/kaname-ios-plan.md` §9). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P2" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

The ten statement readers (six credit-card — **ICICI**, **HDFC**, **SBI Card**, **Yes Bank / Kiwi**, **Federal / Scapia**, **IOB** — and four bank-account ledgers — **ICICI bank**, **HDFC bank**, **Federal bank**, **AU bank**) are all landed and proven byte-for-byte against golden fixtures, and both per-statement trust signals — the bank-ledger **balance-chain integrity check** and its credit-card counterpart, **reconciliation** — have shipped. Each of those checks looks at **one** statement in isolation. Nothing yet looks **across** two statements from **different sources**.

This slice delivers that cross-source view: when the **same purchase appears in two different statements** — for example a spend that shows up on both a person's **bank-account ledger** and their **credit-card statement** — the engine **recognises it as one purchase, not two**, so it is not silently **double-counted** in any later total, timeline, or analytic. It ports the **pure, in-memory subset** of the web engine's cross-source de-duplicator (`deduplicator.py`) into the on-device core. Its behaviour is **fully pinned** by the proven web engine and its parity tests (Constitution Principle V, Test-First & Parity); this port reproduces that behaviour exactly.

The web de-duplicator is a **database-backed async ladder** — **L1** SOURCE_REF, **L2** EXACT-hash, **L3** CANONICAL, **L4** FUZZY, **L5** MERCHANT, plus an amount-drift **SUPERSEDE** step — that queries a `transactions` table and depends on **merchant resolution** and **persistence**, none of which exist on-device yet (encrypted SQLite/SQLCipher is a deferred, later phase). So this slice ports **only the two layers that are portable without a database**, as a **pure, in-memory batch matcher** over two already-parsed transaction lists:

1. **Canonical layer** (the pure analogue of web **L3 CANONICAL**) — two transactions are duplicates when they have the **same date**, the **same amount**, the **same direction**, and the **same normalised-narration prefix** (the first **60 characters** of the web engine's `normalise_narration` output).
2. **Fuzzy layer** (the pure analogue of web **L4 FUZZY**) — two transactions are duplicates when they have the **same amount**, the **same direction**, dates **within ±1 day**, and a **Jaro-Winkler similarity ≥ 0.92** on their normalised narrations.

The matcher is **multiplicity-aware**: each existing (stored) transaction can be consumed by **at most one** incoming transaction, so **N** genuine same-day / same-amount / same-merchant **repeats do not all collapse into one** — only the true duplicates are matched, and surplus repeats **survive**. For each incoming transaction the **canonical layer is tried before the fuzzy layer**, and the **first matching (still-unconsumed) existing transaction wins**. The result identifies, for each matched incoming transaction, **which existing transaction it duplicates** and **by which layer** — and it is **read-only**: it never mutates, drops, reorders, merges, or persists any row (that is the caller's, and a later slice's, job).

Like the balance-chain and reconciliation checks it joins, the matcher is **pure** and **on-device**: no network, no clock, no locale, no hidden state, no database (Constitution Principle I & II). It reuses the existing shared transaction type, the exact-decimal money type, the golden-fixture parity harness, and the UniFFI bridge. Its Jaro-Winkler similarity is **hand-rolled** and reproduces the web engine's `rapidfuzz` values **byte-for-byte**, so the slice adds **no new runtime dependency**.

### User Story 1 - Recognise a purchase that appears in both a bank statement and a card statement as one purchase (canonical match) (Priority: P1)

When the same purchase appears in two sources with the **same date, amount, direction, and merchant** (after narration normalisation), the engine identifies the incoming one as a **duplicate** of the existing one — so a person's spend is counted **once, not twice**. This is the direct on-device analogue of the web engine's **L3 CANONICAL** layer.

**Why this priority**: This is the headline value and the smallest slice that delivers a cross-source signal — it is the one layer that catches the common, clean case (both sources agree on date, amount, direction, and merchant). On its own it lets the app avoid double-counting a purchase seen in two statements. Every other story refines, protects, or enables this identification.

**Independent Test**: Give the matcher an existing (bank) list with one debit and an incoming (card) list containing the same debit on the same date, same amount, same direction, with a narration that normalises to the same 60-character prefix; confirm the incoming transaction is identified as a canonical duplicate of the existing one — with no network access during the match.

**Acceptance Scenarios**:

1. **Given** an existing (bank) debit of 250.00 on 2026-07-04 narrated "Swiggy Bangalore" and an incoming (card) debit of 250.00 on 2026-07-04 narrated "swiggy   bangalore" (which normalises to the same prefix), **When** the matcher runs, **Then** the incoming transaction is identified as a **canonical** duplicate of the existing bank transaction.
2. **Given** two transactions that differ only by cosmetic case, whitespace, or punctuation in the narration (same normalised 60-character prefix) with identical date, amount, and direction, **When** the matcher runs, **Then** they are identified as a canonical duplicate pair.
3. **Given** the same date, amount, and direction but narrations whose normalised prefixes **differ**, **When** the matcher runs, **Then** there is **no** canonical match (the pair falls through to the fuzzy layer, and survives if that also fails).
4. **Given** the device has no network connectivity, **When** the matcher runs, **Then** the duplicate is still identified, proving the match is fully local.

---

### User Story 2 - Catch a near-duplicate despite a cosmetically different merchant name or a one-day posting skew (fuzzy match) (Priority: P2)

When the same purchase appears in two sources with the **same amount and direction** and **near-identical** merchant narrations, but with a small spelling variation or a **one-day** posting-date skew (common when a bank posts a card spend a day later), the engine still recognises it as a **duplicate** via a **Jaro-Winkler similarity ≥ 0.92** on the normalised narrations. This is the pure analogue of the web engine's **L4 FUZZY** layer.

**Why this priority**: Real cross-source pairs rarely match exactly — the two sources render the merchant slightly differently and often post a day apart. The fuzzy layer is what makes the signal useful on real data. It is second because the clean canonical case (US1) is the MVP; the fuzzy layer extends coverage to the near-identical cases the canonical layer misses.

**Independent Test**: Give the matcher two transactions with equal amount and direction, dates within ±1 day, and normalised narrations whose Jaro-Winkler similarity is ≥ 0.92 (e.g. "swiggy bangalore" vs "swiggy bangaluru" = 0.95); confirm they are identified as a **fuzzy** duplicate pair — and confirm a pair whose similarity is below 0.92 is **not** matched.

**Acceptance Scenarios**:

1. **Given** an existing transaction narrated "swiggy bangalore" and an incoming one narrated "swiggy bangaluru" (Jaro-Winkler **0.95** ≥ 0.92) with the same amount and direction and dates within ±1 day, **When** the matcher runs, **Then** they are identified as a **fuzzy** duplicate pair.
2. **Given** narrations "amazon" and "amazon pay" (Jaro-Winkler **exactly 0.92**) with the same amount and direction and dates within ±1 day, **When** the matcher runs, **Then** they are identified as a fuzzy duplicate pair (the 0.92 threshold is **inclusive**).
3. **Given** narrations "fine dining" and "fine dine" (Jaro-Winkler **0.9232** ≥ 0.92) with the same amount and direction and dates within ±1 day, **When** the matcher runs, **Then** they are identified as a fuzzy duplicate pair.
4. **Given** two transactions whose normalised narrations are similar (≥ 0.92) but whose **amounts differ**, or whose **directions differ**, or whose dates are **2 or more days apart**, **When** the matcher runs, **Then** there is **no** fuzzy match (all four conditions — amount, direction, ±1-day window, and similarity — must hold).

---

### User Story 3 - Genuinely separate identical purchases both survive (multiplicity) (Priority: P3)

Two (or more) **genuinely separate** purchases that happen to share the same day, amount, direction, and merchant must **both survive** — the matcher must not collapse every same-day / same-amount / same-merchant repeat into a single row. Each existing transaction can be consumed by **at most one** incoming transaction; any surplus incoming repeats are left **unmatched** (they survive).

**Why this priority**: Over-collapsing is the dangerous failure mode — it would silently **delete** a real, distinct purchase and under-count a person's spend. Multiplicity-awareness is the guarantee that only **true** one-to-one duplicates are matched. It is prioritised right after the two matching layers because it constrains **how** those layers consume candidates, and it is a hard, pinned guarantee of the web engine.

**Independent Test**: Give the matcher an existing list with **one** transaction and an incoming list with **two** transactions identical to it (same day, amount, direction, merchant); confirm **exactly one** incoming transaction is identified as a duplicate and the **other survives** (is unmatched).

**Acceptance Scenarios**:

1. **Given** an existing list with **one** debit of 200.00 on 2026-07-04 narrated "Uber", and an incoming list with **two** debits of 200.00 on 2026-07-04 narrated "Uber", **When** the matcher runs, **Then** **exactly one** incoming transaction is identified as a duplicate (it consumes the single existing transaction) and the **other incoming transaction is unmatched** (survives).
2. **Given** an existing list with **two** such identical transactions and an incoming list with **two** identical transactions, **When** the matcher runs, **Then** **both** incoming transactions are matched (each consumes a **distinct** existing transaction).
3. **Given** an existing list with **two** identical transactions and an incoming list with **three** identical transactions, **When** the matcher runs, **Then** **exactly two** incoming transactions are matched and **one survives**.

---

### User Story 4 - Do not merge a same-amount purchase at a clearly different merchant (threshold protection) (Priority: P4)

A same-amount, same-direction purchase at a **clearly different merchant** must **not** be collapsed into another. The fuzzy layer's **≥ 0.92** similarity threshold, together with the amount, direction, and date guards, protects against false merges — so two distinct merchants that merely share an amount are both kept.

**Why this priority**: A false merge is a silent data-loss bug: it would erase a real purchase and mislead the person. This story pins the **protective** boundary of the fuzzy layer (the just-below-threshold case) and the amount/direction/date guards, ensuring the matcher is conservative. It is the counterweight to US2 — the fuzzy layer must be permissive enough to catch near-duplicates yet strict enough to reject different merchants.

**Independent Test**: Give the matcher two transactions with equal amount and direction and dates within ±1 day whose normalised narrations are "acme corp" and "acme corporation" (Jaro-Winkler **0.9125** < 0.92); confirm they are **not** matched and **both survive**.

**Acceptance Scenarios**:

1. **Given** narrations "acme corp" and "acme corporation" (Jaro-Winkler **0.9125**, just **below** 0.92) with the same amount and direction and dates within ±1 day, **When** the matcher runs, **Then** there is **no** match and **both transactions survive**.
2. **Given** two transactions whose normalised narrations are identical but whose **directions differ** (one debit, one credit), **When** the matcher runs, **Then** there is **no** canonical **and no** fuzzy match.
3. **Given** two transactions with the same merchant and direction but **different amounts**, **When** the matcher runs, **Then** there is **no** match (neither layer matches on differing amounts).
4. **Given** two transactions with the same merchant, amount, and direction but dates **2 days apart**, **When** the matcher runs, **Then** there is **no** match (the canonical layer requires the **same** date; the fuzzy layer allows only **±1 day**).

---

### User Story 5 - Explain each duplicate and never mutate, drop, or persist a row (Priority: P5)

For every duplicate it finds, the result identifies **which existing transaction** the matched incoming transaction duplicates and **by which layer** (canonical or fuzzy). Unmatched incoming transactions simply do not appear as duplicates (they survive). The matcher is a **read-only identifier**: it never mutates, drops, reorders, merges, or persists any transaction in either list.

**Why this priority**: A duplicate the app cannot explain is not actionable, and a matcher that silently removed rows would itself cause the double-counting-in-reverse (under-counting) it exists to prevent. Explaining the match (which pair, which layer) and guaranteeing read-only behaviour are what make the signal safe for a later slice to act on. Both are hard, testable guarantees.

**Independent Test**: Run the matcher over two lists that yield a canonical and a fuzzy match; confirm each identified match names the incoming transaction, the existing transaction it duplicates, and the layer that caught it; then confirm both input lists are unchanged afterward (same rows, same order, nothing removed).

**Acceptance Scenarios**:

1. **Given** a canonical duplicate, **When** the result is inspected, **Then** it names the incoming transaction, the existing transaction it duplicates, and records the layer as **canonical**.
2. **Given** a fuzzy duplicate, **When** the result is inspected, **Then** it records the layer as **fuzzy**.
3. **Given** the matcher has run, **When** both input lists are inspected, **Then** **neither** list has been mutated, reordered, or had any transaction removed — the matcher only **identifies** duplicates.
4. **Given** an incoming transaction with **no** match, **When** the result is inspected, **Then** it appears in **no** duplicate pair (it survives).

---

### User Story 6 - Canonical before fuzzy, and the first unconsumed existing wins (deterministic ladder) (Priority: P6)

For each incoming transaction, the **canonical layer is tried before the fuzzy layer**, and within a layer the **first still-unconsumed existing transaction** (in the existing list's order) that satisfies the layer's conditions is the match. The whole matcher is **deterministic**: identical input always yields identical output.

**Why this priority**: The precedence (canonical over fuzzy) and the tie-break (first unconsumed wins) are exactly what the web ladder does, and they must be reproduced for byte-for-byte parity and for stable, reproducible results. It is lower priority than the layers and multiplicity themselves because it governs their **ordering**, but it is a required, pinned behaviour.

**Independent Test**: Construct an incoming transaction that could match one existing transaction **canonically** and a different existing transaction only **fuzzily**; confirm the canonical match is taken. Construct two unconsumed existing transactions that both match an incoming canonically; confirm the **first** in existing-list order is chosen. Re-run any case and confirm identical output.

**Acceptance Scenarios**:

1. **Given** an incoming transaction that matches one existing transaction **canonically** and a different existing transaction only **fuzzily**, **When** the matcher runs, **Then** the **canonical** match is taken (canonical precedence over fuzzy).
2. **Given** two still-unconsumed existing transactions that both match an incoming transaction canonically, **When** the matcher runs, **Then** the **first** in the existing list's order is chosen.
3. **Given** identical input lists, **When** the matcher runs repeatedly, **Then** it returns identical output every time (100% reproducible).

---

### User Story 7 - Proven byte-for-byte against golden fixtures (normalise_narration + rapidfuzz Jaro-Winkler) (Priority: P7)

The matcher's behaviour is proven against golden vectors ported from the web engine that pin (a) the **narration normalisation** (`normalise_narration`), (b) the **Jaro-Winkler similarity** values (`rapidfuzz`), and (c) the **L3/L4 matching** decisions. The hand-rolled Jaro-Winkler reproduces the captured `rapidfuzz` values **byte-for-byte** (0.95, 0.92, 0.9125, 0.9232 for the four reference pairs).

**Why this priority**: Golden-fixture parity is the constitution's source of truth (Principle V): the on-device matcher must reproduce the web engine's decisions exactly. Pinning the normaliser, the similarity values, and the match/no-match/multiplicity outcomes together is the acceptance gate for the whole slice and guards the ±1-day window, the 60-character prefix, the 0.92 threshold, and the canonical-before-fuzzy precedence against regression.

**Independent Test**: Run the parity harness over the reference vectors and confirm each Jaro-Winkler value equals its captured `rapidfuzz` value exactly, each `normalise_narration` output is reproduced exactly, and each canonical / fuzzy / no-match / multiplicity vector reproduces the web engine's identified matches (and their layers) exactly.

**Acceptance Scenarios**:

1. **Given** the four reference pairs, **When** the on-device Jaro-Winkler similarity is computed, **Then** it equals the captured `rapidfuzz` values exactly: "swiggy bangalore"/"swiggy bangaluru" = **0.95**, "amazon"/"amazon pay" = **0.92**, "acme corp"/"acme corporation" = **0.9125**, "fine dining"/"fine dine" = **0.9232**.
2. **Given** the captured `normalise_narration` ground-truth outputs for the representative narrations, **When** the on-device normaliser runs, **Then** it reproduces each output exactly.
3. **Given** the golden canonical, fuzzy, no-match, and multiplicity vectors, **When** they are run through the matcher, **Then** the identified matches — and the layer that caught each — reproduce the web engine exactly.
4. **Given** identical input, **When** the parity vectors are re-run, **Then** the output is identical every time (100% reproducible).

---

### User Story 8 - Reachable across the Rust↔Swift bridge (Priority: P8)

The cross-source matcher is callable from the app across the existing UniFFI bridge: given two parsed transaction lists, Swift receives the identified duplicate matches (each with the incoming transaction, the existing transaction it duplicates, and the layer) — exactly as the app can already call the reader, balance-chain, and reconciliation entry points.

**Why this priority**: The engine's value is realised only when the app can consume it. Proving the matches cross the bridge (with a Swift bridge test) is what makes the de-duplication signal usable by a future UI or a later persistence slice, and it mirrors the bridge-reachability guarantee every prior slice landed.

**Independent Test**: From a Swift test, build two synthetic transaction lists (with a canonical and a fuzzy duplicate), call the de-duplication entry point across the bridge, and confirm the returned matches and their layers match what the engine computes.

**Acceptance Scenarios**:

1. **Given** the app calls the de-duplication entry point over the bridge with two lists containing a clean canonical duplicate, **When** it runs, **Then** Swift receives a match identifying that pair with the **canonical** layer.
2. **Given** the app calls the entry point with two lists containing a near-duplicate (≥ 0.92, ±1 day), **When** it runs, **Then** Swift receives a match identifying that pair with the **fuzzy** layer.
3. **Given** the app calls the entry point with two lists that contain no duplicates, **When** it runs, **Then** Swift receives an empty set of matches (every incoming transaction survives).

---

### User Story 9 - Privacy: zero network in the de-duplication path (Priority: P9)

Matching two transaction lists — normalising narrations, computing similarities, and identifying duplicates — happens entirely on the device with no network access whatsoever, consistent with the constitution's non-negotiable privacy principle.

**Why this priority**: Privacy is the product's defining, non-negotiable promise (Constitution Principle I). De-duplication reads the person's most sensitive data (their exact transactions across two sources), so it must be provably local. The automated privacy-egress gate must cover this path.

**Independent Test**: Run the de-duplication path under the automated privacy-egress test and confirm zero outbound network connections occur.

**Acceptance Scenarios**:

1. **Given** the device has no network connectivity, **When** two lists are de-duplicated, **Then** the matches are still produced (the matcher is fully local).
2. **Given** the automated privacy-egress test, **When** it exercises the de-duplication path, **Then** it asserts zero network access and remains a required constitution gate.

---

### Edge Cases

- **Amount compared as an exact decimal magnitude**: `250.00` and `250.0` are the **same** amount; comparison is exact-decimal, never floating-point. Direction is compared separately and must be equal.
- **Canonical requires the same date; fuzzy allows ±1 day**: a canonical match needs an identical date (0-day difference); the fuzzy layer treats dates **exactly 1 day apart** as within the window and dates **2 or more days apart** as outside it.
- **Jaro-Winkler threshold is inclusive**: a similarity of **exactly 0.92** matches (fuzzy); a similarity **below** 0.92 (e.g. 0.9125) does not.
- **Direction guard**: a debit is never a duplicate of a credit, even with identical date, amount, and narration (neither layer matches across directions).
- **Normalised-narration prefix is capped at 60 characters**: two narrations that differ only **after** the 60th normalised character share the same canonical key; the fuzzy layer compares the full normalised narrations.
- **Multiplicity — each existing consumed at most once**: N incoming repeats matched against M existing repeats produce exactly min(N, M) matches; surplus incoming repeats survive.
- **Canonical-before-fuzzy per incoming**: for a single incoming transaction, a canonical match (if any unconsumed existing qualifies) is always preferred over any fuzzy match.
- **First unconsumed existing wins**: when several unconsumed existing transactions qualify within a layer, the first in the existing list's order is chosen (deterministic tie-break).
- **Empty inputs**: if either list is empty, no matches are produced and the matcher does not crash; every incoming transaction (if any) survives.
- **No candidate left after consumption**: an incoming transaction whose only qualifying existing transactions have all been consumed by earlier incoming transactions is left unmatched (it survives).
- **Read-only on every path**: match, no-match, and multiplicity cases all leave both input lists intact — the matcher never removes, mutates, reorders, merges, or persists a transaction.
- **Cross-source, not intra-source**: matching is between the **two** lists (one existing, one incoming); de-duplicating within a single list is **not** part of this slice.
- **Direction source unchanged**: the matcher reads each transaction's already-decided debit/credit direction; it never re-derives direction from an amount's sign.

## Requirements *(mandatory)*

### Functional Requirements

**The batch cross-source matcher — inputs, scope & outputs**

- **FR-001**: The engine MUST provide a **pure, in-memory** batch cross-source matcher that takes **two already-parsed transaction lists** from different sources — an **existing** (stored) list and an **incoming** list — and returns the set of identified **duplicate matches**, each naming the incoming transaction, the existing transaction it duplicates, and the **layer** (canonical or fuzzy) that caught it. Incoming transactions with no match are **survivors** (they appear in no match).
- **FR-002**: The matcher MUST be **read-only**: it MUST NOT mutate, drop, reorder, merge, or persist any transaction in either list. It only **identifies** duplicates; acting on them (removing, merging, superseding, persisting) is out of scope.
- **FR-003**: The matcher MUST be **multiplicity-aware**: each existing transaction MUST be consumed by **at most one** incoming transaction, so genuine repeats are not all collapsed into one — surplus incoming repeats survive.
- **FR-004**: For each incoming transaction, the matcher MUST try the **canonical** layer **before** the **fuzzy** layer, and within the first satisfying layer MUST match the **first still-unconsumed existing transaction** in the existing list's order; the **first matching layer** (and first unconsumed candidate) wins.
- **FR-005**: The matcher MUST be **pure and deterministic**: identical input MUST yield identical output, with no dependence on network, wall-clock time, locale, or hidden global mutable state, and it MUST NOT read files, query a database, or extract PDF text.

**Canonical layer (pure analogue of web L3 CANONICAL)**

- **FR-006**: The canonical layer MUST identify two transactions as duplicates when **all** of the following are equal: the **date**, the **amount** (exact decimal magnitude), the **direction**, and the **normalised-narration prefix** (the first **60 characters** of the `normalise_narration` output).
- **FR-007**: The narration normalisation MUST reproduce the web engine's `normalise_narration` (in `normaliser.py`) exactly for the captured ground-truth narrations, and the canonical key MUST use the first **60 characters** of that normalised output.

**Fuzzy layer (pure analogue of web L4 FUZZY)**

- **FR-008**: The fuzzy layer MUST identify two transactions as duplicates when **all** of the following hold: the **amount** is equal (exact decimal magnitude), the **direction** is equal, the dates are **within ±1 day**, and the **Jaro-Winkler similarity** of their normalised narrations is **≥ 0.92**.
- **FR-009**: The Jaro-Winkler similarity MUST be computed on the **normalised narrations**, and the **0.92** threshold MUST be **inclusive** (exactly 0.92 matches).
- **FR-010**: The Jaro-Winkler implementation MUST reproduce the web engine's `rapidfuzz` Jaro-Winkler values **byte-for-byte** for the reference pairs (0.95, 0.92, 0.9125, 0.9232) and MUST add **no new runtime dependency** (`rapidfuzz` is a web-only dependency and MUST NOT be added on-device).

**Money & polarity**

- **FR-011**: All monetary comparisons in the matcher MUST use **exact decimals** (amount magnitude, such that `250.00` equals `250.0`); amounts MUST NEVER be represented as floating-point numbers. Direction is **explicit** and MUST be equal for a match; the matcher MUST NEVER re-derive direction from an amount's sign.

**Scope boundaries — the excluded layers**

- **FR-012**: This slice MUST port **only** the L3 CANONICAL and L4 FUZZY layers. It MUST NOT implement any of: a **database or persistence**; the **L1 SOURCE_REF** or **L2 EXACT-hash** layers (they are database-index concerns); the **L5 MERCHANT** layer or any **merchant resolution** (needs a merchant catalog that does not exist on-device); the amount-drift **SUPERSEDE** behaviour (needs merchant resolution + persistence); any **mutation, deletion, merging, or persistence** of rows; any **CSV / source_ref / exact-source-hash** handling; or any **UI**.

**Counterpart to the shipped checks — reuse, purity & platform boundary**

- **FR-013**: The matcher MUST reuse the shared parsed-transaction type, the exact-decimal money type, the golden-fixture parity harness, and the UniFFI bridge — the same foundations the readers, balance-chain, and reconciliation checks use. It MUST add **no new runtime dependency** and **no new shared engine helper** beyond the matcher itself, the `normalise_narration` port, and the Jaro-Winkler helper it needs.
- **FR-014**: The matcher MUST remain pure and MUST NOT read files or extract PDF text (text extraction is a native platform concern); it operates only on the two in-memory transaction lists it is given.

**Bridge exposure**

- **FR-015**: The matcher MUST be reachable over the existing UniFFI bridge with an entry point that accepts the two transaction lists and returns the identified matches (each with the incoming transaction, the existing transaction it duplicates, and the layer), mirroring how the balance-chain and reconciliation checks are exposed to Swift.

**Privacy (Constitution Principle I — NON-NEGOTIABLE)**

- **FR-016**: The entire de-duplication path MUST run 100% on-device with ZERO network I/O.
- **FR-017**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting into the engine or the app.
- **FR-018**: The existing automated privacy-egress test MUST cover the de-duplication path and assert it performs no network access; it remains a required constitution gate.

**Parity & test-first (Constitution Principle V)**

- **FR-019**: The web engine's de-duplication behaviour MUST be the pinned source of truth — `normalise_narration` (`normaliser.py`), the **L3 CANONICAL** and **L4 FUZZY** logic (`deduplicator.py`), and the `rapidfuzz` Jaro-Winkler similarity — and MUST be reproduced exactly, including the 60-character prefix, the ±1-day window, the inclusive 0.92 threshold, the canonical-before-fuzzy precedence, and the multiplicity (at-most-one-consumption) rule.
- **FR-020**: Golden vectors MUST cover a **canonical** match, a **fuzzy** match (including the inclusive 0.92 boundary), a **non-match** (a below-threshold pair, and pairs failing the direction / amount / date guards), and a **multiplicity** case (surplus repeats survive) — each reproduced exactly by the on-device matcher. The captured Jaro-Winkler reference values (0.95, 0.92, 0.9125, 0.9232) and the `normalise_narration` reference outputs MUST be pinned as parity data.
- **FR-021**: All fixture and test data MUST be **synthetic or fully redacted** (fabricated merchants, amounts, and dates) — never real account data.
- **FR-022**: The behaviour introduced by this slice MUST be developed **test-first** (a failing golden/parity test precedes the behaviour).

**Licensing, secrets & quality gates**

- **FR-023**: The change MUST NOT add secrets, API keys, or private endpoints; MUST remain distributable under **Apache-2.0** with no copyleft (GPL/AGPL/LGPL) dependencies; and MUST introduce **NO new runtime dependencies** for this slice.
- **FR-024**: The change MUST keep the **iOS Local Verification Gate** and CI green: core formatting, linting, and tests; app linting; project generation; a simulator build with passing app tests; and the privacy gate.
- **FR-025**: If any user-facing surface is introduced for this slice, it MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility.

### Key Entities *(include if feature involves data)*

- **Existing (stored) transaction list**: One source's already-parsed transactions (e.g. a bank-account ledger). Its transactions are the **candidates** an incoming transaction may duplicate; each may be consumed by at most one incoming transaction. The matcher never mutates it.
- **Incoming transaction list**: The other source's already-parsed transactions (e.g. a credit-card statement). Each is tested, in order, against the still-unconsumed existing transactions; a matched one is a duplicate, an unmatched one is a survivor.
- **Transaction (shared input type)**: A single parsed transaction — its date, narration/description, amount (exact decimal magnitude), and direction (debit or credit). The matcher consumes it read-only; it carries no currency and matching does not depend on one.
- **Normalised narration**: The `normalise_narration` output for a transaction's narration (the pinned web-engine normalisation); its **first 60 characters** form the canonical key's narration component, and its full form is compared by the fuzzy layer.
- **Canonical match key**: The tuple of (date, amount, direction, 60-character normalised-narration prefix) that the canonical layer compares for exact equality.
- **Fuzzy match predicate**: The conjunction of (equal amount, equal direction, dates within ±1 day, Jaro-Winkler similarity ≥ 0.92) that the fuzzy layer evaluates.
- **Jaro-Winkler similarity**: The string-similarity score (in [0, 1]) on two normalised narrations; the on-device value reproduces the web engine's `rapidfuzz` value exactly (0.95 / 0.92 / 0.9125 / 0.9232 for the reference pairs).
- **Match layer**: Which layer caught a duplicate — **canonical** or **fuzzy** — recorded on each identified match.
- **Duplicate match (result element)**: One identified duplicate — the incoming transaction, the existing transaction it duplicates, and the layer. The full result is the set of these; incoming transactions absent from it are survivors.
- **Golden de-duplication vectors**: Synthetic two-list inputs paired with the expected identified matches (and their layers), plus the pinned `normalise_narration` outputs and `rapidfuzz` Jaro-Winkler values, ported from the web engine and reproduced exactly.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The canonical layer is 100% correct on the reference vectors — a pair with the same date, amount, direction, and 60-character normalised-narration prefix is identified as a canonical duplicate, and a pair differing in any one of those is not.
- **SC-002**: The fuzzy layer classifies the four reference pairs exactly — "swiggy bangalore"/"swiggy bangaluru" (0.95) matches, "amazon"/"amazon pay" (0.92) matches at the inclusive boundary, "fine dining"/"fine dine" (0.9232) matches, and "acme corp"/"acme corporation" (0.9125) does **not** match — with 0 misclassifications at the boundary (given equal amount and direction and dates within ±1 day).
- **SC-003**: The on-device Jaro-Winkler similarity equals the captured `rapidfuzz` values byte-for-byte for the four reference pairs (0.95, 0.92, 0.9125, 0.9232).
- **SC-004**: The on-device narration normalisation reproduces the captured `normalise_narration` reference outputs exactly (0 differences).
- **SC-005**: Multiplicity holds — one existing vs two identical incoming yields exactly one match (one survives); two vs two yields two matches; two vs three yields two matches (one survives) — each existing consumed at most once.
- **SC-006**: Canonical takes precedence over fuzzy — whenever a canonical match exists for an incoming transaction, the fuzzy layer is never used for it (0 cases of a fuzzy match when a canonical one applies).
- **SC-007**: The tie-break is deterministic — when several unconsumed existing transactions qualify within a layer, the first in the existing list's order is chosen every time.
- **SC-008**: The guards reject non-duplicates — a differing direction, a differing amount, or dates 2 or more days apart never produce a match (the canonical layer requires the same date; the fuzzy layer allows only ±1 day), with 0 false matches on the guard vectors.
- **SC-009**: The matcher is read-only — after a run, both input lists are unchanged (same transactions, same order, none removed); the matcher drops 0 rows.
- **SC-010**: Every identified match records the incoming transaction, the existing transaction it duplicates, and the layer (canonical or fuzzy).
- **SC-011**: 100% of the matcher's monetary comparisons use exact decimals; no value is ever a floating-point number.
- **SC-012**: Given identical input, the matcher returns identical output across repeated runs (100% reproducible).
- **SC-013**: The golden vectors (canonical, fuzzy incl. boundary, non-match, multiplicity) reproduce exactly and the parity harness passes; re-running is stable.
- **SC-014**: The identified matches (with layers) are reachable over the existing UniFFI bridge to Swift, demonstrated by a Swift bridge test that distinguishes a canonical match, a fuzzy match, and the no-match (survivor) case.
- **SC-015**: Zero outbound network connections occur during the entire de-duplication path, verified by the automated privacy-egress test.
- **SC-016**: The change adds **no** new runtime dependency and is scoped to the matcher, the `normalise_narration` port, and the Jaro-Winkler helper — with **none** of the excluded concerns present (no database/persistence, no L1 SOURCE_REF, no L2 EXACT-hash, no L5 MERCHANT / merchant resolution, no amount-drift SUPERSEDE, no row mutation/deletion/persistence, no UI), verified by review of the change set.
- **SC-017**: All automated checks required to merge pass (green), including the parity harness and the privacy-egress test, with the iOS Local Verification Gate and CI green; and no secrets, network entitlements, telemetry, or copyleft-licensed dependencies are added (verified by review of manifests and dependencies).

## Assumptions

- **Behaviour is fully pinned by the web engine**: This is a behaviour-parity port. The web engine's `normalise_narration` (`normaliser.py`), the **L3 CANONICAL** and **L4 FUZZY** logic in `deduplicator.py`, and the `rapidfuzz` Jaro-Winkler similarity are the source of truth; open details are resolved by matching the web engine rather than by clarification. Ground truth has already been captured (representative `normalise_narration` outputs and the exact `rapidfuzz` Jaro-Winkler values for the four reference pairs). The concrete on-device design (module layout, result types, layer enum, whether matches reference transactions by index or by value, bridge mechanics, fixture format) is decided in `/speckit.plan`, not here.
- **Two-role batch model (existing vs incoming)**: The matcher takes two lists — an existing (stored) list and an incoming list — and, for each incoming transaction, matches the first still-unconsumed existing transaction, trying canonical before fuzzy. This is the faithful **pure subset** of the web de-duplicator's per-incoming L1→L5 ladder, restricted to the two database-free layers (L3 + L4); the higher/lower ladder rungs are excluded (see Out of Scope).
- **`normalise_narration` is the canonical narration source of truth**: The existing on-device `normalize_description` helper (whitespace-collapse + upper-case, used by the exact-hash `dedup_fingerprint`) is a **different, coarser** normaliser and is **not** the canonical key; this slice faithfully reproduces `normalise_narration` (or the subset sufficient to reproduce the captured outputs). The exact relationship between the two helpers on-device is a `/speckit.plan` decision.
- **Constants match the web engine**: the canonical narration key uses the **first 60 characters** of the normalised narration; the fuzzy date window is **±1 day**; the fuzzy Jaro-Winkler threshold is **0.92, inclusive**. These are the byte-for-byte behavioural constants from `deduplicator.py`.
- **Amount & polarity**: amounts are compared as **exact decimal magnitudes** (`250.00` == `250.0`), never floating-point; direction is explicit and must be equal for a match; the matcher never re-derives direction from an amount's sign. The shared `Transaction` type carries no currency, so matching does not depend on one.
- **Hand-rolled Jaro-Winkler, no new dependency**: `rapidfuzz` is a web-only dependency; on-device the Jaro-Winkler similarity is hand-rolled and reproduces the captured `rapidfuzz` values byte-for-byte, so this slice adds **no** new runtime dependency.
- **Cross-source only**: matching is between the two lists (one existing, one incoming); de-duplicating within a single list is not part of this slice.
- **Identification only**: the result **identifies** duplicates; deciding what to do with them (dropping, merging, superseding, persisting, or presenting "one purchase, not two" in a UI) is the caller's job and belongs to later slices. Preventing double-counting is achieved when a later consumer acts on the identified matches.
- **No new UI required**: this is an engine slice; no user-facing UI is required to deliver it. Surfacing de-duplication in the app is a later, native step. If a trivial demo surface is added, it follows HIG and accessibility (FR-025).
- **Counterpart to the shipped checks**: the matcher is exposed and tested the same way as the shipped balance-chain and reconciliation checks — a pure function over the shared types, reachable over the existing UniFFI bridge, with golden/parity cases and a Swift bridge test. Concrete binding mechanics belong in `/speckit.plan`.
- **Reused, not rebuilt**: the shared `Transaction` / parsed-transaction type, the exact-decimal money type, the golden-fixture JSON parity harness, the UniFFI bridge, and the privacy-egress gate were all built in earlier slices; the matcher plugs into each unchanged.
- **Data safety**: all fixture and test data is synthetic or fully redacted — no real account data.

### Dependencies

- **Kaname Constitution v1.0.0** — privacy (zero-network free/core), determinism, a pure platform-agnostic core (no PDF engine, no database in this slice), decimal money with explicit polarity, Apache-2.0 open-core with no copyleft, native HIG/accessibility, and the test-first iOS Local Verification Gate (including the privacy-egress gate).
- **Shipped reader slices (10) plus balance-chain and reconciliation (007–012)** — the parsed transactions the matcher consumes come from the ten landed readers; de-duplication is the next ingestion check after the per-statement balance-chain and reconciliation trust signals, and it is exposed and tested the same way.
- **Shared engine foundations** — the shared `Transaction` / parsed-transaction domain type, the exact-decimal money type, the golden-fixture parity harness, the UniFFI Rust↔Swift bridge, and the privacy-egress gate. The existing `dedup` module (`normalize_description` + the exact-hash `dedup_fingerprint`) is present but is **not** the L3/L4 matcher this slice adds.
- **Web engine de-duplication source of truth** — `normaliser.py` (`normalise_narration`), `deduplicator.py` (the **L3 CANONICAL** and **L4 FUZZY** layers), and the `rapidfuzz` Jaro-Winkler similarity, together with the web parity tests `test_statement_cross_source_dedup.py` and `test_bank_statement_cross_source_dedup.py`, used as the parity source of truth.

## Out of Scope

Deferred to later slices / milestones, or explicitly excluded (as directed by the user):

- **Any database or persistence** — the web de-duplicator queries a `transactions` table; this slice ports only the **pure, in-memory** matcher. Encrypted SQLite / SQLCipher persistence, key management, and any stored de-duplication state are a later phase.
- **The L1 SOURCE_REF layer** — matching on a source-provided reference id is a database-index concern and is excluded.
- **The L2 EXACT-hash layer** — the exact content-hash / `exact-source-hash` match is a database-index concern and is excluded (the existing `dedup_fingerprint` is not wired into this matcher).
- **The L5 MERCHANT layer and all merchant resolution** — matching by resolved merchant needs a merchant catalog that does not exist on-device; both the layer and the resolution are excluded.
- **The amount-drift SUPERSEDE behaviour** — replacing a stored row when an incoming row supersedes it needs merchant resolution and persistence; excluded.
- **Mutating, deleting, merging, or persisting rows** — the matcher only **identifies** duplicates; actually removing or merging them (and preventing double-counting downstream) is a later consumer/persistence slice.
- **CSV import / `source_ref` / exact-source-hash handling** — excluded.
- **Any UI** — surfacing de-duplication (a "seen in both statements" indicator, a merge/keep review) in the app is a later, native step; this slice is engine-only.
- **Intra-source de-duplication, transfer detection, and coverage/timeline** — de-duplicating within a single list, pairing a card-bill payment against its bank debit as a **transfer**, and statement date-range completeness are separate later slices, not this one.
- **Changing how transactions are parsed** — row extraction, direction/polarity, dates, amounts, and narrations are unchanged; this slice only **adds** the cross-source matcher (and the `normalise_narration` + Jaro-Winkler helpers it needs) over the already-parsed transactions.
- **No new runtime dependencies** — `rapidfuzz` (the web engine's similarity library) is **not** added; the Jaro-Winkler similarity is hand-rolled to reproduce its values byte-for-byte.
