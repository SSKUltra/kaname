# Feature Specification: Categorize (Let a Person Correct What the Engine Decided, and Have the Correction Stick)

**Feature Branch**: `020-categorize`  
**Created**: 2026-08-18  
**Status**: **Ready for `/speckit.plan`** — Q1, Q2 and Q3 are answered and their answers are written into the requirements (see § *Clarifications*). Nothing in this spec now waits on a decision.  
**Milestone**: P3 (Core SwiftUI app) — the **fifth** slice of P3, scheduled in `docs/kaname-ios-plan.md` immediately after `018-transaction-list` and `019-debug-test-seeding`, both DONE and merged.  
**Input**: User description: "A person reading their own transactions can see what each one was categorized as, correct it when it's wrong, work through the ones the engine could not categorize at all, and have a correction they make once apply to that merchant from then on — all on-device, deterministically, with no network."

> **Note on priority labels**: This feature sits in product milestone **P3** (Core SwiftUI app). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P3" and "User Story P3" are unrelated numbering schemes.

## Why this slice exists

The categorization engine has been finished for five slices. Nobody can disagree with it.

`core/crates/kaname-core/src/categorize.rs` is complete and shipped: a deterministic, first-wins stack — CC narration rules, then **T1** the issuer's own source-category map, then **T2** the user merchant map, then **T3** keyword, regex and amount-range rules — returning a `Decision { category_ref, stage, matched_rule_id }` or `None`. There is deliberately no confidence field, because the stack does not guess; it either matches or it does not (`categorize.rs:472-485`). Twenty-three built-in categories are defined (`categorize.rs:167-211`). The store persists the answer and its provenance in `transactions.category_id` and `transactions.categorised_by` (`store.rs:73-86`). The transaction list has shown the result on every row since slice 018 — `Text(row.categoryLabel)`, where `categoryLabel` is `categoryName ?? "Uncategorized"` (`TransactionRowView.swift:63`, `TransactionListModels.swift:71`, `TransactionListStrings.swift:63`).

So a person can already read the verdict. **What they cannot do is answer it.**

**There is no write path.** `Store` has no `set_category`, no `update_category`, no method of any name that changes one transaction's category. The repository contains exactly **two** statements that ever write `transactions.category_id`, and a person is behind neither of them: `categorize_account_in` (`store.rs:1303-1324`) and `detect_transfers` (`store.rs:1160-1183`). Every category any person will ever see was written by the engine, during an import, about a merchant it had never been told anything about. The T2 merchant map — the tier whose entire purpose is to hold what *this person* has taught the app — can be read (`list_merchant_rules`) and can be written (`insert_merchant_rule`), and in the shipping app nothing has ever put a row in it, because nothing asks a person anything.

That is the gap, and it is a strange one to have carried this long: the app has a memory, and no way to form one.

**The gap has a sharp edge, and the edge is the defect this slice most plausibly ships.** `categorize_account_in` does not ask whether a row already has an answer. It loads every live, non-transfer row of the account (`store.rs:1759-1774`) and executes `UPDATE transactions SET category_id = ?2, categorised_by = ?3 WHERE id = ?1` against each one — unconditionally — and when the stack returns `None` it writes `NULL, NULL` (`store.rs:1303-1324`). `import_statement` calls it on every import (`store.rs:824-846`). So the naive implementation of this slice — write the person's choice into `category_id` and stop — produces an app in which a person carefully corrects thirty rows, imports next month's statement, and finds the corrections gone, including the ones that reverted from a real category to nothing at all. Silently. With no error, no diagnostic, and no way to tell it happened except by remembering. **A correction that does not survive the next import is not a correction; it is a joke told to somebody about their own money.** This spec treats surviving re-categorization as a first-class requirement, not a detail (US2, FR-018 to FR-025).

**This slice is therefore not Swift-only.** Slice 019 touched no Rust at all. This one must add a write path to the engine, which means a **schema migration** — the store is at `SCHEMA_VERSION: i64 = 7` (`store.rs:38-41`), migrations are forward-only and applied one version at a time by `apply_migration` (`store.rs:1257-1275`), and this slice is very likely the thing that makes it 8. It also means the **FFI surface changes**, and therefore `make core-xcframework` followed by `make ios-gen` is **mandatory**. A bare `tuist generate` is a documented trap in `AGENTS.md:88-92`: it regenerates the project against a stale framework and produces a build that fails in a way that looks like a Swift error and is not one.

**There is a second gap, quieter, on the read side.** `HistoryQuery` carries `account_id`, `cursor` and `limit` and nothing else (`store.rs:307-318`). `HistoryRow` carries `category_name` but no category identity and no flag saying "this one has no category" (`store.rs:320-339`). A person who wants to work through the transactions the engine could not place has no way to ask for them: the list can be narrowed to one account and to nothing else. Triage is not a screen this slice invents for fun; it is the only way the value of a correction compounds, because the uncategorized rows are exactly the ones where a single answer teaches the most.

**What this slice is, exactly.** The core loop, and only the core loop: **see** what a transaction was categorized as, **change** it, **find** the ones that were not categorized at all and work through them, and have a change **stick for that merchant** so the next import lands right. Four verbs. Everything adjacent — creating a person's own categories beyond the twenty-three, selecting many rows and changing them together, editing T1 or T3 through the interface, budgets, any rollup of spend by category, anything premium — is a later slice and is listed in § *Out of Scope* so that it is refused rather than discussed. The one thing here that reaches past a single row is the second action of FR-035a: one memory the person just formed, applied only after they are told how many rows and which accounts, with nothing to select and nothing implicit.

**And it must be honest about what it changes.** A correction that quietly rewrites a hundred existing rows is a bulk edit wearing a disguise, and bulk edit is explicitly out of scope for this slice. Whatever "make it stick" turns out to mean, the person MUST be told in plain language which rows it touched and which it did not, at the moment they make the choice — not in a settings screen, not in a release note, and never in the vocabulary of the engine. A person does not have a "T2 merchant map"; they have a shop they go to.

Everything here stays inside the constitution. The engine performs **zero** network I/O and this slice adds no path that could. Money is an exact **decimal** at every step and never a floating-point number. The stack stays **deterministic** and reproducible against `fixtures/`. The store stays **encrypted**, with the same key handling. The interface is **iOS 26 and Liquid Glass, unconditionally** — no `#available` gate, no `.ultraThinMaterial` fallback, both of which `scripts/import-path-audit.sh` already bans mechanically. And accessibility is a **shipping gate**: 018's manual gate found four defects and 019's first automated audit found two more, so the new surfaces here are audited by a machine, at the largest text sizes, in both appearances, with Increase Contrast — and the coverage is **watched failing** before it is believed.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A person fixes a category that is wrong (Priority: P1)

A person is reading their transactions and sees one filed under the wrong thing — a pharmacy counted as Groceries, a train ticket counted as Miscellaneous. They tap the row. It opens, showing what this transaction is and what it was filed under. They pick the right category from the list of categories the app knows. They go back, and the row says the right thing.

**Why this priority**: This is the write path that does not exist, and every other story here is either a consequence of it or a protection around it. Shipped alone — with no merchant teaching and no triage — it already converts the engine from an oracle into a tool, because the person can finally disagree with it and be heard.

**Independent Test**: On a seeded history, open a transaction whose category is known, change it to a different category, return to the list, and confirm the row shows the new category; relaunch the app and confirm it still does.

**Acceptance Scenarios**:

1. **Given** a transaction shown in the list, **When** the person taps it, **Then** a detail surface opens showing that transaction's own facts — its description, its exact amount, its date, its account and its current category — and nothing about any other transaction.
2. **Given** the detail surface, **When** the person chooses to change the category, **Then** they are offered the categories the app knows, each named the way a person names things, with the current one clearly marked as current.
3. **Given** a category is chosen, **When** the person confirms, **Then** the change is saved to the encrypted store before the surface reports success, and the list reflects it without the person having to reload anything.
4. **Given** a saved change, **When** the app is fully relaunched, **Then** the changed category is still there.
5. **Given** a transaction with no category at all, **When** the person opens it, **Then** it says so in plain words rather than showing a blank, and offers the same choice.
6. **Given** a person has changed a category, **When** they change their mind, **Then** they can change it again, and can set it back to having no category at all.
7. **Given** any change, **When** it is saved, **Then** **zero** network requests occur.

---

### User Story 2 - The correction is not quietly undone (Priority: P2)

The person corrected thirty rows in March. In April they import April's statement. In May they import May's. Their thirty corrections are still exactly as they left them — every one, including the ones where they said "this has no category" and meant it.

**Why this priority**: This is the specific defect this slice is most likely to ship, and it is invisible when it happens. `categorize_account_in` rewrites every live non-transfer row of the account unconditionally and writes `NULL, NULL` when the stack has no answer (`store.rs:1303-1324`); `import_statement` calls it every time (`store.rs:824-846`). A correction stored as an ordinary engine verdict is a correction with a countdown on it. It ranks second only because there must be a correction before there is anything to lose.

**Independent Test**: Correct a category; then run an import into the same account, and separately run a re-categorization of that account; confirm the corrected row is unchanged in both cases, including when the correction was "no category" and the stack would have supplied one.

**Acceptance Scenarios**:

1. **Given** a transaction whose category a person set, **When** a new statement is imported into that account, **Then** the person's category is still in place afterwards.
2. **Given** the same transaction, **When** the account is re-categorized by the engine for any reason, **Then** the person's category is still in place afterwards.
3. **Given** a transaction a person deliberately set to **no category**, **When** the engine later runs over it and would have matched a rule, **Then** the person's "no category" stands, because a person's silence is also an answer.
4. **Given** any transaction, **When** anything reads its category, **Then** it is possible to tell whether a person put it there or the engine did — the two are different kinds of fact and are never conflated.
5. **Given** a stored correction, **When** the store is inspected, **Then** the record of *who decided* is distinguishable from every provenance the engine writes today (`CC_RULE`, `T1_SOURCE_CATEGORY`, `T2_MERCHANT_MAP`, `T3_RULE`, `TRANSFER_DETECTOR`).
6. **Given** an existing install with existing data, **When** it is upgraded to this slice, **Then** no category, no transaction and no account is lost, altered or re-derived by the upgrade itself.

---

### User Story 3 - A correction teaches the app, and the app says what it taught (Priority: P3)

The person corrects a coffee shop they visit weekly. The app remembers that shop for next time — automatically, as part of the correction — and, in the person's own words rather than the engine's, shows them the shop it is about to remember and tells them exactly what that will do: this row changes now, the rows already imported do not, and next month's arrive filed correctly. Then, separately and clearly labelled, it offers to go back and fix the ones already there — naming how many and in which accounts — which the person can take or ignore. Either way, what they were told is what happens.

**Why this priority**: This is the compounding value of the slice. Without it, a person corrects the same coffee shop fifty-two times a year, and the engine learns nothing — which is the current state of the T2 merchant map, a memory that has never held anything. It ranks below durability because a memory that gets wiped every import is worse than no memory at all.

**Independent Test**: Correct a transaction for a merchant that appears in more than one seeded statement; observe the merchant the app says it will remember and exactly what it says will happen; ignore the offer to fix the rows already there and confirm **zero** of them changed; then import a further statement containing that same merchant and confirm the new rows land in the corrected category. Repeat, this time taking the second action, and confirm precisely the rows it counted changed — no more and no less.

**Acceptance Scenarios**:

1. **Given** a person changes a transaction's category, **When** that change could be remembered for the merchant, **Then** the app tells them so in plain language, naming the merchant as it appears to them.
2. **Given** the app offers to remember, **When** it describes what will happen, **Then** it states which rows are affected and which are not, without using the words the engine uses for its own tiers, stages or rules.
3. **Given** the person agrees to remember, **When** a later import contains that merchant, **Then** the imported rows arrive in the remembered category without the person doing anything.
4. **Given** the person declines to remember, **When** a later import contains that merchant, **Then** nothing was remembered and only the single row they changed stays changed.
5. **Given** the person later corrects the **same** merchant to a **different** category, **Then** the most recent instruction is what the app follows, and the app does not accumulate two contradictory memories of the same shop.
6. **Given** anything was remembered, **When** the person looks at the transaction again, **Then** they can tell that a memory exists for this merchant, and the app does not pretend the row is an isolated fact.
7. **Given** two merchants whose descriptions differ only by a per-transaction reference number, **When** one of them is remembered, **Then** the memory is about the merchant and not about that one transaction — a memory that can only ever match the row it was made from has taught nothing.
8. **Given** a memory has just been formed, **When** the app offers to re-apply it to transactions already imported, **Then** that offer is a **separate, clearly labelled second action**, it states how many rows would change and in which accounts before the person agrees, and it changes **nothing** unless they take it.
9. **Given** the person ignores or declines that second action, **When** they return to the list, **Then** every row except the one they opened is exactly as it was, and the memory still applies to the next import.
10. **Given** the person takes the second action, **When** it completes, **Then** exactly the rows it described have changed, each recorded as the person's own decision, and no row in any account was changed that was not counted.
11. **Given** the person later corrects the same merchant to a different category, **When** they do, **Then** the newer instruction replaces the older memory, the rows an earlier second action already changed are left as they are, and the newer second action counts those rows and says so.

---

### User Story 4 - A person works through the ones the engine could not place (Priority: P4)

The person wants to clear the backlog. They tap the entry point that says how many transactions have no category, land on their own transaction list narrowed to exactly those, and go through them one at a time. As each is answered it leaves the set. When the set is empty, the app says so, and says it as an achievement rather than as an error.

**Why this priority**: The uncategorized rows are where a correction is worth the most, because each one is a merchant the engine has never placed and each answer can be remembered. It ranks below teaching because triage without memory is a treadmill.

**Independent Test**: Seed a history containing a known number of transactions with no category; confirm the entry point's count equals that number and equals the number of rows found on opening it; confirm exactly those transactions appear and no others; answer some; confirm they leave the set and the count falls; answer all; confirm the empty state is the one that means "you are done" and not the one that means "there is nothing here".

**Acceptance Scenarios**:

1. **Given** a history with uncategorized transactions, **When** the person asks for them, **Then** they get exactly the transactions with no category — every one, and nothing else.
2. **Given** the uncategorized set, **When** the person categorizes one, **Then** it leaves the set, and any count of what remains agrees with what is on screen.
3. **Given** the uncategorized set is empty because everything has been answered, **When** the person looks at it, **Then** the wording says the work is finished, and is distinguishable from the wording for a person who has imported nothing.
4. **Given** the person has narrowed the list to one account, **When** they ask for the uncategorized set, **Then** the two narrowings agree with each other and the person can tell which are in force.
5. **Given** the uncategorized set, **When** it is read, **Then** it obeys the same live-row rule as the transaction list: superseded and deleted rows are absent, and no second opinion about liveness exists anywhere.
6. **Given** the uncategorized set spans more transactions than fit on a screen, **When** the person scrolls, **Then** it pages in the same order and by the same rule as the transaction list, with nothing duplicated, skipped or reordered across a page boundary.
7. **Given** a history with uncategorized transactions, **When** the person looks for them, **Then** there is a visible entry point that opens the transaction list already narrowed to them, showing a count that came from the engine, and the number they were shown is the number of rows they land on.
8. **Given** everything has been answered, **When** the person looks at that entry point, **Then** its count is zero and it reads as finished rather than as an error, and opening it lands on the "you are done" wording.

---

### User Story 5 - Every transaction says what it was filed under, everywhere it is read (Priority: P5)

Wherever a person reads a transaction — the list, the detail, the uncategorized set — it says what it was filed under, or says that it was not filed at all. Never blank, never a code, never a number.

**Why this priority**: Most of this is already true and this spec says so rather than claiming credit for it: the row has rendered `categoryName ?? "Uncategorized"` since slice 018 (`TransactionRowView.swift:63`). What is new is that the same promise must hold on every surface this slice adds, and that the uncategorized state must read as an invitation rather than as damage.

**Independent Test**: On a seeded history containing both categorized and uncategorized rows, read every surface this slice touches and confirm each transaction states its category or its absence, in the same words, with no internal identifier visible anywhere.

**Acceptance Scenarios**:

1. **Given** any transaction on any surface, **When** it is displayed, **Then** its category is shown by its human name, or its absence is stated in words.
2. **Given** a transaction with no category, **When** it is shown, **Then** the wording is identical on every surface — one phrase, defined once.
3. **Given** any surface, **When** it is inspected, **Then** no category identifier, stage name, rule identifier or provenance value is visible to a person.
4. **Given** a category name that is long, at the largest accessibility text size, **When** it is shown beside an amount, **Then** the amount is never truncated, shrunk or abbreviated to make room.

---

### User Story 6 - A machine checks the new screens before a person ever sees them (Priority: P6)

The surfaces this slice adds are populated with a named synthetic history by an automated run, audited at the largest text sizes in both appearances and with Increase Contrast, and the coverage is proved to work by being watched failing against a defect put back on purpose.

**Why this priority**: This is 019's capability being spent for the first time on a screen that did not exist when 019 was written — the reason 019 exists. It also carries this repository's hardest-won lesson: a gate that has only ever been green proves nothing.

**Independent Test**: Run the UI suite with no person present, on named seed scenarios that include uncategorized rows and a merchant repeated across statements; confirm every new surface is reached and audited; then reinstate a known defect and confirm the new coverage goes red.

**Acceptance Scenarios**:

1. **Given** an automated run, **When** it asks for a named scenario, **Then** it reaches every surface this slice adds with real data on it, by the same route a person takes.
2. **Given** each new surface, **When** the system accessibility audit runs, **Then** it audits a rendered, populated screen at the default and largest accessibility text sizes, in Light and Dark Mode, and with Increase Contrast.
3. **Given** the new coverage, **When** a defect of the class 018's manual gate found is deliberately reinstated, **Then** the coverage fails, and this is observed and recorded rather than assumed.
4. **Given** the seeding capability, **When** this slice needs a shape of history it does not yet offer, **Then** the scenario is added to the existing declaration and remains absent from Release, with no new seeding mechanism invented.
5. **Given** any new instrument this slice proposes, **When** it is chosen, **Then** it is not one already shown to be blunt: a label cannot demonstrate a truncation, and a wall clock in a UI test measures the machine.

---

### User Story 7 - The store grows a version without costing anyone their history (Priority: P7)

An existing install, with real imported statements in it, is upgraded. It opens. Everything that was there is there. The new capability works. Nothing was re-derived, re-categorized or thrown away to make it fit.

**Why this priority**: This is the first slice in the app's life to migrate a store that a person might already have data in. It ranks last only because it is a condition on shipping rather than a thing a person asks for — and it is the one item on this list that cannot be fixed in the next release.

**Independent Test**: Build a store at the current schema version holding accounts, statements, transactions with categories and merchant rules; upgrade it; confirm the version advanced, every row survived byte-for-byte, and the new capability works on the upgraded store.

**Acceptance Scenarios**:

1. **Given** a store at the pre-existing schema version, **When** the app opens it after this slice, **Then** it migrates forward, one version at a time, and opens successfully.
2. **Given** the migration, **When** it completes, **Then** every account, statement, transaction, amount, category assignment and rule that existed before is identical afterwards.
3. **Given** the migration, **When** it runs, **Then** it does not re-run categorization, re-derive any category, or change any existing provenance value.
4. **Given** a migration that cannot complete, **When** it fails, **Then** it fails without leaving a partially migrated store behind.
5. **Given** the migrated store, **When** it is inspected, **Then** it is still encrypted with the app's own key handling, and no plaintext copy was created at any point in the process.

---

### Edge Cases

- **A category is changed on a row that is later superseded by de-duplication.** The correction was made about a row that is about to become invisible. What the person sees afterwards must not be a category that vanished without explanation.
- **A category is changed on a row that a later import supersedes with a re-imported copy of itself.** The re-imported row is the one the person will see; it must not arrive uncorrected while the correction sits on a hidden loser.
- **A transfer leg.** `detect_transfers` assigns transfer legs `SELF_TRANSFER` or `CREDIT_CARD_BILL_PAYMENT` with `categorised_by = 'TRANSFER_DETECTOR'` (`store.rs:1160-1183`), and `categorize_account_in` deliberately never touches them (`store.rs:1759-1774`, `AND is_transfer = 0`). Separately, `scripts/import-path-audit.sh` bans the app from calling transfer detection at all, so **no row in the shipping app is a transfer today**. The behaviour must still be specified rather than left to be discovered later.
- **The same merchant corrected to two different categories on two different days.** One shop cannot be two things at once; the app must not hold two contradictory memories, and must not silently pick by an ordering nobody can see.
- **A merchant whose description contains a per-transaction reference number.** A memory formed from the whole description would match exactly one row forever and teach nothing.
- **A merchant that matches an existing engine rule at an earlier tier than the person's memory.** If a person's instruction can be outranked by a rule they never wrote and cannot see, the app is lying about having listened.
- **A transaction with an empty or unreadable description.** It must still be openable and correctable, and the offer to remember the merchant must handle having no merchant to name.
- **A very long category name and a very large amount in the same row**, at the largest accessibility text size — the shape that produced `018/04`.
- **A history where every single transaction is uncategorized**, and one where none of them is.
- **The person changes a category and immediately backgrounds the app**, or an import completes while a detail surface is open.
- **A store already holding merchant rules** written by tests or fixtures before this slice existed.
- **The number of rows the second action would change moves between being shown and being confirmed** — an import lands, another correction is made, a row is superseded. The person agreed to a figure, and applying to a different one silently would make the app a liar about the one thing it promised to be exact about.
- **A second action whose rows are in an account the person was not looking at.** The blast radius crosses an account boundary; the count must say which accounts before the person agrees, not afterwards.
- **A second action over rows the person has already decided about themselves.** Their earlier decisions are not the engine's verdicts and must not be swept up by a later instruction about the same merchant.
- **A derived merchant portion that comes out empty or degenerate** — a narration that is nothing but a channel prefix and a reference number, or one whose every segment is discarded. There is no merchant to name, so there is nothing honest to remember.
- **A derived merchant portion that is broader than the person expects**, matching a shop they did not mean. This is why the portion is shown before the memory is formed and why the second action's count is shown before it runs; there is no memory-management surface in this slice to rescue them afterwards.
- **The same merchant corrected twice to different categories after the first correction's second action has already run.** The newer instruction wins for the future, the rows the earlier run changed stay as the person left them, and the newer offer must count those rows rather than pretending they are not affected.
- **The count behind the entry point is zero.** It must read as finished rather than as an error or an empty shelf, and must be distinguishable from a store with nothing imported at all.
- **An account narrowing and the uncategorized narrowing in force together over an account whose every live row is categorized.** A new empty situation, needing its own words — it is not "this account has nothing", and it is not "you are done" across the whole store.

## Requirements *(mandatory)*

### Seeing what a transaction was filed under

- **FR-001**: Every transaction, on every surface a person can read it, MUST state the category it is filed under by its human name, or state in words that it has none.
- **FR-002**: The wording for "no category" MUST be defined in exactly **one** place and be identical on every surface. The transaction list's existing phrase is that definition; this slice MUST NOT introduce a second one.
- **FR-003**: No surface may display a category identifier, a stage name, a rule identifier, a provenance value, or any other engine or storage internal.
- **FR-004**: A category name MUST never cause a monetary amount to be truncated, shrunk, abbreviated or scaled to fit. The amount does not yield; the slice 018 rule holds unchanged.

### Changing what a transaction is filed under

- **FR-005**: A person MUST be able to open a single transaction from the list and see that transaction's own facts: description, exact amount, date, account, and current category.
- **FR-006**: A person MUST be able to assign or change that transaction's category, choosing from the catalog of categories the app knows.
- **FR-007**: A person MUST be able to set a transaction **back to having no category**, and that MUST be a deliberate, reversible choice rather than a side effect.
- **FR-008**: A transaction MUST have **at most one** category at any time. This slice introduces no notion of multiple categories per transaction.
- **FR-009**: A change MUST be persisted to the encrypted store before the interface reports it as done. No change may exist only in memory or only on screen.
- **FR-010**: After a change, every surface currently showing that transaction MUST show the new category without the person reloading, re-navigating or re-importing anything.
- **FR-011**: A change that fails to save MUST say so plainly and MUST leave the stored category exactly as it was. It MUST NOT report success, and MUST NOT leave the screen disagreeing with the store.
- **FR-012**: Changing a category MUST NOT alter the transaction's amount, date, description, account, currency, direction, liveness or transfer status.
- **FR-013**: This slice MUST NOT add a general way to change many transactions' categories in one action: no multi-select, no selection mode, no "apply to these" affordance anywhere. The **only** action that may change more than one row is the second action of FR-035a–FR-035h, which applies one memory the person has just formed, changes nothing until they explicitly agree, and offers no selection of anything. Bulk recategorization remains out of scope.

### The catalog a person chooses from

- **FR-014**: The choices offered MUST be the categories held in the store, read through the engine, and MUST NOT be a list re-declared in the interface.
- **FR-015**: The catalog includes the twenty-three built-in categories the engine defines. This slice MUST NOT add, rename, remove or reorder any of them.
- **FR-016**: The catalog MUST be presented so that a person can find a category among roughly two dozen without hunting — the ordering, grouping or means of finding is `/speckit.plan`'s decision, but "an unordered list of twenty-three" is not acceptable.
- **FR-017**: If the store already holds categories beyond the built-ins, they MUST be offered alongside them. This slice MUST NOT provide any way to create, rename or delete a category.

### A correction that lasts

- **FR-018**: A category a person set MUST be recorded as **a person's decision**, distinguishable from every provenance the engine writes for its own verdicts.
- **FR-019**: The engine's re-categorization of an account MUST NOT overwrite, clear or re-derive a category a person set. This applies to re-categorization triggered by an import and to re-categorization triggered by any other means.
- **FR-020**: A transaction a person deliberately set to **no category** MUST likewise be left alone by the engine. The absence of a category chosen by a person is a decision and is protected as one.
- **FR-021**: The protection MUST be a property of the engine, not of the interface. It MUST hold for any caller of the re-categorization path, whether or not that caller is this app.
- **FR-022**: A person's decision MUST survive an unlimited number of subsequent imports and re-categorizations, indefinitely, until that same person changes it.
- **FR-023**: The engine MUST remain free to categorize every transaction a person has **not** decided about, exactly as it does today, with no change to which rows it reaches or in what order.
- **FR-024**: This slice MUST NOT change the stack's stage order, its first-wins behaviour, or the set of rows the engine considers.
- **FR-025**: The provenance recorded for a person's decision MUST be a value the engine can never produce for itself, so that the two can never be confused by any reader now or later.

### Remembering a merchant

- **FR-026**: A correction MUST be remembered for the merchant **automatically**, as the default and without a separate confirmation step, so that future imports of that merchant land in the corrected category without the person acting again.
- **FR-026a**: The merchant that will be remembered MUST be shown, named in plain language, on the same surface where the person confirms the correction — **before** the memory is formed. Remembering MUST NOT cost the person an extra decision, and it MUST NOT happen behind their back.
- **FR-026b**: The person MUST be able to decline remembering, in one deliberate action on that same surface. Declining MUST still save the correction to the row they opened, and MUST leave **zero** memories behind.
- **FR-027**: What is remembered MUST be about the **merchant**, not about the one transaction: it is a **derived merchant portion** of the normalized narration, not the whole narration. A memory that can only ever match the row it was formed from does not satisfy this requirement.
- **FR-027a**: The derivation MUST be a single documented, deterministic rule, specified precisely enough to be implemented one way only, applied in this order and no other:
  1. Take the output of the engine's existing narration normalization exactly as it is. The derivation reads it and never alters it.
  2. Split it, preserving order, on the documented separator set and on runs of whitespace.
  3. Discard every segment that is empty, that is entirely digits, that is a mixed token carrying four or more digits, or that appears in a documented **closed** stop-list of channel and instrument words. The stop-list MUST be fixed in full, MUST be fixture-tested, and MUST contain **zero** merchant names.
  4. The merchant portion is the first surviving segments in order, up to a documented maximum count, joined by single spaces.
- **FR-027b**: A memory matches a transaction when that transaction's merchant portion, derived by the identical rule, is **exactly equal** to the remembered one. This slice introduces no substring, prefix, fuzzy or similarity matching for a person's memory, so that what matches is decidable by looking at what the person was shown.
- **FR-027c**: The derivation MUST be **additive**. It MUST NOT change `dedup::normalize_narration`, the normalization de-duplication depends on, or any other shared engine behaviour. De-duplication's existing results MUST be identical after this slice, with **zero** expectation edits in its fixtures.
- **FR-027d**: If the derivation yields an empty or degenerate merchant portion — nothing survives step 3, or what survives is a fragment the rule cannot name a shop by — the app MUST form **no** memory and MUST offer none. The correction to the row still saves, and the app says plainly that it has nothing to remember rather than remembering something meaningless.
- **FR-027e**: The derivation MUST be deterministic and reproducible against `fixtures/`: the same narration MUST yield the same merchant portion on every run and every machine, with no clock, locale or global state involved.
- **FR-028**: The app MUST tell the person, in plain language and at the moment of choosing, **exactly** what remembering will and will not do: that this row changes now, that rows already imported do **not** change unless they take the second action of FR-035a, and that future imports of this merchant will land in the corrected category.
- **FR-029**: That explanation MUST NOT use the engine's vocabulary. The words "tier", "stage", "T1", "T2", "T3", "rule", "map" and "filter" MUST NOT appear in anything a person reads. `CONTEXT.md` fixes this vocabulary and this slice does not relax it.
- **FR-030**: What the app says will happen MUST be exactly what happens — no row changed that was not described, and no row left unchanged that was described as changing.
- **FR-031**: When a person corrects the same merchant again to a different category, the app MUST follow the **most recent** instruction and MUST NOT retain a contradictory earlier memory of the same merchant. Newest-instruction-wins holds unchanged under FR-026's automatic remembering: the second correction **replaces** the memory rather than adding one beside it.
- **FR-031a**: Replacing a memory MUST NOT retroactively rewrite rows that an earlier second action already changed. Those rows were changed by a decision the person took, are recorded as the person's decision, and MUST stay as they are until the person changes them. The new correction offers its own second action, whose count MUST **include** those rows and MUST say so, so that re-applying the newer instruction is visible rather than assumed.
- **FR-032**: A memory MUST NOT be able to be outranked by an engine rule the person never wrote, in a way that makes their instruction ineffective. If the engine's existing ordering permits that, it is a finding to record and resolve, not a behaviour to ship.
- **FR-033**: Remembering MUST be deterministic: the same correction, on the same history, MUST produce the same memory and the same subsequent categorizations on every run and every machine.
- **FR-034**: A transaction with an empty or unreadable description MUST still be correctable, and the app MUST NOT offer to remember a merchant it cannot name — the case FR-027d governs.
- **FR-035**: This slice MUST NOT provide any way to view, edit, reorder or delete the person's remembered merchants as a set. Managing them is a later slice, and the second action below is not management: it applies one memory the person has just made and offers no view of any other.

### Re-applying one memory to rows already imported

- **FR-035a**: Once a memory is formed, the app MUST offer a **separate, clearly labelled second action** that applies that memory to transactions already in the store. It MUST NOT run automatically, implicitly, as part of saving the correction, or as part of any import.
- **FR-035b**: The second action MUST apply **exactly one** memory — the one just formed from the correction just made. It MUST NOT offer a choice of transactions, a multi-select, a selection of other merchants, or any other bulk edit, and **no multi-select selection UI ships in this slice**.
- **FR-035c**: Before the person agrees, the app MUST state **how many** existing rows would change and **in which accounts**, including accounts they were not looking at. The blast radius is shown beforehand and is never discovered afterwards.
- **FR-035d**: The rows it changes MUST be exactly the live transactions whose derived merchant portion equals the remembered one and about which the person has **not** themselves decided. A category another row carries because a person set it MUST NOT be overwritten, and such rows MUST NOT be counted in FR-035c's figure.
- **FR-035e**: Every row the second action changes MUST be recorded as the person's decision, with the same provenance and the same protection as a row corrected by hand (FR-018, FR-019, FR-025).
- **FR-035f**: If the set of affected rows changes between being shown and being confirmed — an import completes, a correction lands, a row is superseded — the app MUST NOT apply the stale set. It MUST re-state the new count and accounts and ask again, or refuse and say why. Applying to more rows than were described is a violation of FR-030 and is never acceptable.
- **FR-035g**: Ignoring, dismissing or declining the second action MUST leave **every** existing row untouched, and MUST NOT undo the memory or the single-row correction that formed it. The offer MUST NOT re-appear as a nag on rows the person did not open.
- **FR-035h**: The second action MUST be undertaken in full or not at all: a run that cannot complete MUST leave **zero** rows changed rather than a partially applied set, and MUST say so.

### Working through the ones that were not filed

- **FR-036**: A person MUST be able to obtain the set of transactions that have **no category**, as a set, and work through it. That set is a **narrowing on slice 018's existing transaction list** — not a second surface — so that ordering, paging and liveness have exactly one implementation and nothing is duplicated.
- **FR-037**: That set MUST contain exactly the live transactions with no category — every one, and nothing that has one.
- **FR-038**: The set MUST obey the same live-row rule as the transaction list. Superseded and deleted rows MUST NOT appear, and this slice MUST NOT introduce a second opinion about liveness anywhere.
- **FR-039**: A transaction that is given a category MUST leave the set, and any count of what remains MUST agree with what is on screen.
- **FR-040**: The set MUST page in the same order and by the same rule as the transaction list, with **zero** rows duplicated, skipped or reordered across a page boundary.
- **FR-041**: The uncategorized narrowing MUST **compose** with slice 018's existing account narrowing: both may be in force at once, each MUST be legible as in force, and each MUST be clearable independently without disturbing the other. This slice MUST NOT change how the account narrowing itself behaves.
- **FR-041a**: There MUST be a **visible entry point** that opens the transaction list already narrowed to uncategorized, so that a person does not have to assemble the narrowing themselves. It MUST open the same list, by the same route, with no second renderer of transactions anywhere.
- **FR-041b**: The count shown on the entry point MUST equal the number of rows the person finds after opening it, in every case. To keep that true, opening the entry point applies the uncategorized narrowing with **no** account narrowing in force, and the count is the whole store's live uncategorized rows. This is the entry point's own defined behaviour — the one route that sets both narrowings at once — and not an exception to FR-041, which continues to govern the narrowings once the person is on the list.
- **FR-042**: An empty uncategorized set because the work is **finished** MUST read differently from an empty transaction list because nothing was imported. This slice MUST NOT weaken, merge or duplicate slice 018's six existing empty states; any state it adds is additional and is stated as such.
- **FR-042a**: Because this is a narrowing, 018's empty-state matrix grows. **Every** reachable combination of (account narrowing × uncategorized narrowing) MUST have its own honest wording — an account whose rows are all categorized is not the same situation as an account with no live rows at all — and its own coverage. Any combination that is **unreachable** MUST be named as unreachable, with the structural reason stated, rather than folded into a claim of completeness that is not true. This is the precedent 019 set in FR-039a and finding `019/02`, and it applies here in full.
- **FR-042b**: When the count behind the entry point is **zero**, the entry point MUST read as finished rather than as damage or as an error, and opening it MUST land on the "finished" wording of FR-042. When nothing has been imported at all, the entry point MUST be absent for the same structural reason the list's own route is absent — it MUST NOT be offered as a door onto a store with nothing in it.
- **FR-043**: The count of what is uncategorized, wherever it is shown — including on the entry point of FR-041a — MUST be computed by the **engine**, in the same query that defines the set. It MUST NOT be counted in Swift, derived by counting rows the interface happens to hold, or maintained as a second tally. Slice 018 deliberately moved its front door's count out of Swift and into SQL; this slice MUST NOT reintroduce one.
- **FR-043a**: The engine MUST supply that count, and the set it counts MUST be the set FR-037 defines — one definition of "uncategorized", read by both, so that the count and the list can never disagree.
- **FR-043b**: The affected-row figure of FR-035c MUST likewise come from the engine, from the same place that performs the change, so that what is counted and what is changed cannot drift apart.

### The engine, the store and the migration

- **FR-044**: The engine MUST gain a way to set one transaction's category, including setting it to none, recorded as a person's decision.
- **FR-044a**: The engine MUST gain a way to apply **one** remembered merchant to transactions already stored, in two separable steps that read the same definition: **count first** — how many rows would change, and in which accounts — and **apply second**. The interface MUST NOT be able to apply without having been able to count, and the two MUST NOT be able to disagree.
- **FR-045**: The engine MUST gain a way to read the transactions that have no category, and their count, sufficient for the person-facing set and the entry point above, without the interface filtering or counting a broader read itself.
- **FR-046**: Any schema change MUST be a forward-only migration applied one version at a time, consistent with how every prior version of this store has been migrated.
- **FR-047**: The migration MUST preserve **every** existing account, statement, transaction, amount, category assignment, provenance value and rule exactly. It MUST NOT re-run categorization or re-derive anything.
- **FR-048**: A migration that cannot complete MUST leave no partially migrated store behind.
- **FR-049**: The migrated store MUST remain encrypted with the app's own key handling. No plaintext store or copy may be created at any point, including during migration.
- **FR-050**: Because the engine's interface changes, the framework MUST be rebuilt before the project is regenerated. A bare project regeneration is insufficient and is a known trap in this repository.
- **FR-051**: New engine behaviour MUST be proven by a failing test before it is written, and MUST remain reproducible against `fixtures/`.
- **FR-052**: The engine MUST NOT gain a clock, a locale dependence, hidden global state or any nondeterminism through this slice.

### Privacy, money and determinism

- **FR-053**: Every path this slice adds MUST perform **zero** network I/O. No analytics, no telemetry, no crash reporting, no diagnostic upload of any kind.
- **FR-054**: No transaction field, category, merchant description or correction may be written to any log or diagnostic by anything this slice adds.
- **FR-055**: Every monetary value on every path this slice touches MUST be an exact decimal from store to screen. A floating-point number MUST NOT appear anywhere on that path.
- **FR-056**: `make import-audit`'s scans MUST remain green, unweakened, with none disabled, narrowed or excepted for this slice. If a scan blocks something this slice needs, that is a finding, not a scan to edit.
- **FR-057**: Nothing this slice adds may be gated on, or capable of being unlocked by, an entitlement, an account tier or a server. Correcting a category runs fully on-device and is therefore free, without exception.
- **FR-058**: All test data added by this slice MUST be synthetic. No real statement, fragment, merchant record or account identifier may enter the repository.

### How it looks and feels

- **FR-059**: The interface MUST be iOS 26 and Liquid Glass **unconditionally** — no availability gate, no material fallback, no conditional styling path. The existing mechanical ban on both holds.
- **FR-060**: Money MUST use tabular figures wherever it is shown, consistent with the transaction list.
- **FR-061**: Category MUST NOT be conveyed by colour alone. Any colour used is redundant with a word or a symbol.
- **FR-062**: Opening a transaction, changing a category and returning MUST feel like one continuous movement, with no flash of empty state, no reordering of the list under the person's finger, and no loss of scroll position.
- **FR-063**: The design principles of `make-interfaces-feel-better` and `swiftui-liquid-glass` apply to every surface this slice adds.

### Accessibility, proved rather than asserted

- **FR-064**: Every surface this slice adds MUST be reachable by an automated run using the existing DEBUG-only seeding capability, populated with real data, by the same route a person takes.
- **FR-065**: Every such surface MUST be audited by the system accessibility auditor at the **default and largest** accessibility text sizes, in **Light and Dark** Mode, and with **Increase Contrast** enabled.
- **FR-066**: This slice MUST declare the seed scenarios it needs — at minimum one containing transactions with **no category**, one containing the **same merchant across more than one statement**, and one containing the **same merchant in more than one account**, so that the second action's account-crossing blast radius (FR-035c) and the composed narrowings' empty states (FR-042a) are both reachable — and add them to the existing single declaration of scenarios rather than inventing a second seeding mechanism.
- **FR-067**: Every scenario added MUST remain **absent from Release**, and the existing absence proof MUST continue to pass over both sources and the built artifact.
- **FR-068**: The new coverage MUST be **observed failing** against a deliberately reinstated defect before it is trusted, and that observation MUST be recorded. A gate that has only ever been green proves nothing about what it would catch.
- **FR-069**: This slice MUST NOT adopt an instrument this repository has already shown to be blunt. Specifically: a **label cannot demonstrate a truncation**, because XCUITest reports a text element's string and not its glyphs, so a truncation defect must be carried by **geometry**; and a **wall clock in a UI test measures the machine**, not the app, so no timing criterion here is expressed as one.
- **FR-070**: Any state this slice adds that a seed **cannot** construct MUST be covered by rendering it directly in the unit target, and the resulting unevenness in coverage MUST be stated rather than implied — the precedent set for `EmptyKind.nothingImported`.
- **FR-071**: Every new interactive element MUST have a meaningful accessibility label, and a control whose meaning depends on the transaction it belongs to MUST say which transaction that is.
- **FR-072**: Whatever manual accessibility steps remain MUST be recorded with the build and date they were run, and nothing anywhere may suggest continuous integration enforces a step a person must still take.

### Where the code goes, and scope discipline

- **FR-073**: ⚠️ `ios/Sources/Import/ImportService.swift` is at **398** lines against a hard 400-line limit enforced by `swiftlint --strict`. **No** code from this slice may be added to it. New platform code goes in a new, appropriately named directory under `ios/Sources/`.
- **FR-074**: This slice MUST NOT reformat, split or restructure existing files merely to make room for itself.
- **FR-075**: This slice MUST NOT change statement extraction, parsing, de-duplication, reconciliation, transfer detection, or the transaction list's ordering, paging, liveness rule or account narrowing. If it appears to need such a change, that is a **finding to record**, not a change to make here.
- **FR-076**: This slice MUST NOT introduce persistence, sorting, filtering or any second opinion about the population under the transaction list's own sources. The mechanical bans slice 018 pinned there continue to hold, unweakened. The uncategorized narrowing is **not** an exception to this: it is expressed in the engine's own query, alongside the account narrowing, and MUST NOT be implemented as the interface filtering, counting or re-sorting a broader read.
- **FR-077**: This slice MUST NOT add any test-only or DEBUG-only entry point to the shipping app. Slice 018's FR-077 and slice 019's absence proof remain satisfied on their own terms.
- **FR-078**: Nothing in this slice may compute, display or store an aggregate, total, average or rollup of **spend** by category. Analytics is a later slice and its absence here is deliberate. The counts this slice does show — how many transactions remain uncategorized (FR-043), and how many rows a second action would change and in which accounts (FR-035c) — are lengths of worklists and blast radii, counted in transactions. **Zero** of them are figures about money.

### Key Entities *(include if feature involves data)*

- **Category**: A user-facing label for what a transaction was for. Twenty-three are built in. A transaction has at most one, or none. Never called a "tag".
- **A person's decision**: The fact that *this person*, not the engine, determined a transaction's category — including determining that it has none. A different kind of fact from an engine verdict, recorded distinguishably, and never overwritten by one.
- **A remembered merchant**: What the person taught the app about a shop, formed automatically from a correction, applied to that merchant's transactions from the next import onwards. The app's memory — a thing that exists in the engine today and has never held anything.
- **The merchant portion**: The part of a transaction's normalized description that names the shop rather than the visit — derived by one documented, deterministic rule, shown to the person in plain words before the memory is formed, and equal across every transaction of that merchant. It is derived *from* the engine's existing normalization and changes none of it.
- **The second action**: The person's explicit, separately labelled choice to apply the one memory they have just formed to transactions already in the store. Not a bulk edit, not a selection, not a mode: one memory, one count shown first, one decision, taken or ignored.
- **The uncategorized set**: The live transactions the engine could not place and the person has not answered — reached as a narrowing on the transaction list, not as a surface of its own. A worklist that shrinks as it is answered, and whose emptiness is an achievement rather than an absence.
- **The entry point**: The visible door onto that worklist, carrying a count the engine computes, opening the list already narrowed. What it says is how many the person will find.
- **The migration**: The forward step that lets the store hold a person's decision. The first migration in this app's life that may run against a store somebody actually has data in.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A person can change any transaction's category from the list in **at most three** deliberate actions — open it, choose, confirm — and the change is visible on the list immediately afterwards in **100%** of cases.
- **SC-002**: **100%** of category changes survive a full app relaunch, with **zero** reverting to a previous or engine-supplied value.
- **SC-003**: After **ten** consecutive imports into the same account, **100%** of the categories a person set are unchanged — including **100%** of those the person deliberately set to *no category*, with **zero** of them re-filled by the engine.
- **SC-004**: A category set by a person and a category decided by the engine are distinguishable in the store in **100%** of cases, and the value recorded for a person's decision is one the engine produces in **zero** cases.
- **SC-005**: After a merchant is remembered and a further statement containing that merchant is imported, **100%** of the newly imported transactions of that merchant arrive in the remembered category, with **zero** left uncategorized and **zero** placed elsewhere.
- **SC-006**: What the app told the person would happen matches what happened in **100%** of cases: **zero** rows changed that were not described, and **zero** rows left unchanged that were described as changing.
- **SC-007**: Correcting the same merchant to a different category leaves the app following the most recent instruction in **100%** of cases, and leaves **zero** contradictory memories of that merchant behind.
- **SC-008**: A memory formed from a merchant whose description carries a per-transaction reference matches **all** of that merchant's transactions in the seeded history, not merely the one it was formed from — matched by equality of the derived merchant portion, which the person was shown before the memory was formed.
- **SC-009**: The uncategorized set contains **100%** of live transactions with no category and **zero** transactions that have one, measured against a named seed scenario whose count is declared in advance.
- **SC-010**: Answering every transaction in the uncategorized set takes it to **zero** remaining, and the empty state shown is the "finished" wording in **100%** of cases and the "nothing imported" wording in **zero**.
- **SC-011**: Across the uncategorized set at any depth the seed provides, **zero** rows are duplicated, skipped or reordered across a page boundary.
- **SC-012**: **Zero** engine or storage internals — category identifiers, stage names, rule identifiers, provenance values — are visible on any surface a person can reach.
- **SC-013**: **Zero** occurrences of the engine's vocabulary ("tier", "stage", "T1", "T2", "T3", "rule", "map", "filter", "tag") appear in any string a person reads.
- **SC-014**: An existing store at the pre-existing schema version, holding accounts, statements, categorized transactions and merchant rules, migrates with **100%** of its rows and values identical afterwards and **zero** categories re-derived.
- **SC-015**: An interrupted migration leaves **zero** partially migrated stores, and **zero** plaintext stores or copies exist at any point during or after it.
- **SC-016**: Every surface this slice adds passes the system accessibility audit in an **automated** run at the default and largest accessibility text sizes, in Light and Dark Mode, and with Increase Contrast enabled, with **zero** findings.
- **SC-017**: The new automated coverage is **observed failing** against at least **one** deliberately reinstated defect per new surface; **zero** of them pass against a green gate.
- **SC-018**: **100%** of the surfaces this slice adds are reachable by an automated run with **zero** human actions and **zero** files on the device.
- **SC-019**: Every scenario this slice adds is absent from a Release build, verified by the existing absence proof over sources and artifact, with **zero** hits.
- **SC-020**: **Zero** network requests occur on any path this slice adds, verified automatically.
- **SC-021**: **Zero** floating-point numbers appear on any monetary path this slice touches.
- **SC-022**: `make import-audit` passes with **zero** scans disabled, narrowed, excepted or removed.
- **SC-023**: **Zero** lines are added to `ios/Sources/Import/ImportService.swift`, and `swiftlint --strict` and `swift-format lint --strict` pass with **zero** violations.
- **SC-024**: The existing suites from slices 016 through 019 stay green with **zero** expectation edits, and slice 018's transaction list shows **zero** changes in ordering, paging, liveness or account narrowing.
- **SC-025**: **Zero** real statements, statement fragments, merchant records or account identifiers appear in any fixture, scenario or test added by this slice.
- **SC-026**: Taking the second action changes **exactly** the rows it counted: **100%** of the rows described change, **zero** rows outside the accounts it named change, and the figure shown before agreement equals the number changed in **100%** of cases.
- **SC-027**: Without the second action being taken, a correction changes **exactly one** row — the one the person opened — with **zero** other rows in **any** account altered, measured on a seed where the same merchant appears in at least two accounts.
- **SC-028**: **Zero** multi-select or selection affordances exist anywhere in the shipping app after this slice, and the second action offers **zero** choices of which transactions it applies to.
- **SC-029**: The merchant portion derived from a given narration is identical across **10** consecutive runs and on every machine, and `dedup::normalize_narration`'s behaviour is unchanged — de-duplication's fixtures pass with **zero** expectation edits.
- **SC-030**: A narration from which no merchant portion can be derived yields **zero** memories and **zero** offers to remember, while the correction to the row itself succeeds in **100%** of such cases.
- **SC-031**: A second action whose affected set changes between being shown and being confirmed applies to a stale set in **zero** cases; it re-states the figure or refuses, and **zero** rows are changed beyond what was last described.
- **SC-032**: **Zero** categories that a person set on any row are overwritten by a second action about a merchant, and **zero** such rows are included in the figure it shows.
- **SC-033**: Correcting the same merchant to a different category after a second action has run leaves **zero** contradictory memories, **zero** rows silently rewritten, and the newer offer's count includes **100%** of the rows the earlier run changed.
- **SC-034**: The entry point's count equals the number of rows the person finds after opening it in **100%** of seeded scenarios, and is computed in the engine in **100%** of cases — **zero** counts of transactions are performed in Swift.
- **SC-035**: **100%** of the reachable combinations of the account narrowing and the uncategorized narrowing have their own wording and their own coverage; **zero** unreachable combinations are claimed as covered, and each is named with its structural reason.
- **SC-036**: With every transaction answered, the entry point reads as finished in **100%** of cases and as an error or an empty shelf in **zero**, and a store with nothing imported offers the entry point in **zero** cases.

## Clarifications

Three questions need the repository owner's answer before `/speckit.plan`. Each has more than one defensible answer, and each answer changes the shape of the work rather than a detail of it. Everything else the feature description left open has been decided and recorded under § *Decisions taken without asking*.

---

### Q1: When a person corrects a category, what should "make it stick" actually change?

**Context**: The feature description says a correction should "apply to that merchant from then on". "From then on" is unambiguous about the future and silent about the past. The store already holds every previously imported transaction of that merchant, and a correction that silently rewrote all of them would be a bulk recategorize — which this slice's scope explicitly excludes — reached through a door marked "correct one row". Conversely, remembering only for the future leaves a person looking at the same wrong merchant thirty times in rows they can already see, having just been told the app learned something.

**What we need to know**: Does a remembered correction change transactions already in the store, and is remembering automatic or the person's choice each time?

**Suggested Answers**:

| Option | Answer | Implications |
|--------|--------|--------------|
| A | Remember automatically; future imports only. Existing rows are untouched except the one row the person opened. | Simplest and safest. Nothing a person did not look at ever changes. But the person sees twenty-nine identical wrong rows immediately after being told the app learned, which reads as a broken promise. |
| B | Remember automatically; also re-apply to all existing matching rows, and say so. | Most satisfying — the backlog for that merchant clears at once. But it is a bulk edit performed without per-row consent, it can touch rows outside the account the person was looking at, and it puts a scope this slice excluded back in through the side door. |
| C | Ask each time: change this one only, or this one and every other of this merchant — with the count of affected rows shown before the person agrees. | Honest and explicit; the person is never surprised, and the count makes the blast radius visible. Costs an extra decision on every correction and needs a considered piece of writing on the confirmation. |
| D | Remember automatically for the future; offer re-applying to existing rows as a separate, clearly labelled second action the person can take or ignore. | Separates learning from bulk editing cleanly and keeps the fast path fast. The largest surface of the four, and the second action edges towards the bulk-recategorize slice that comes later. |
| Custom | Provide your own answer | Describe what changes now, what changes later, and who decides. |

**Your choice**: **Option D.** The correction is remembered automatically for future imports, and re-applying it to rows already in the store is a **separate, clearly labelled second action** the person can take or ignore — never automatic, never implicit. Learning is thereby separated from bulk editing: the fast path stays fast and changes only the row the person opened, and before they agree to the second action they are told how many existing rows would change and in which accounts, so the blast radius is visible rather than discovered afterwards. The second action applies **one** memory — the one just formed from the correction just made — and offers no selection of transactions, so bulk and multi-select recategorization stay out of scope and no multi-select affordance ships here. FR-013, FR-026, FR-035a–FR-035g.

---

### Q2: What counts as "the same merchant"?

**Context**: The engine's merchant memory matches against the **normalized** narration — `normalize_narration` strips channel prefixes such as `POS `, `UPI-` and `NEFT/`, removes `RRN` tokens, collapses whitespace, removes a trailing 10–16 digit reference number, and lowercases the result (`dedup.rs:55-70`). It does **not** remove every per-transaction artefact. A memory formed from the whole normalized narration of a UPI payment may therefore match exactly one transaction forever — teaching nothing, while telling the person it learned something (FR-027, SC-008). But a memory formed from too *little* of the narration will match merchants the person never meant, and there is no undo surface in this slice to rescue them.

**What we need to know**: How much of a transaction's description defines the merchant a person is teaching the app about?

**Suggested Answers**:

| Option | Answer | Implications |
|--------|--------|--------------|
| A | The whole normalized narration, exactly. | Zero false matches and trivially deterministic. Will silently fail to generalize for any merchant whose description carries a per-transaction artefact the normalizer does not strip — likely a large share of UPI rows, which is most of them. |
| B | A derived merchant portion of the normalized narration, chosen by a documented deterministic rule, shown to the person before they agree. | Generalizes properly and stays deterministic and reproducible against `fixtures/`. Needs the derivation rule specified and fixture-tested, and needs the person shown what will be remembered. |
| C | The whole normalized narration, but let the person edit what is remembered before agreeing. | Maximum control and no guessing by the app. Asks a person to reason about text matching, which is asking them to do the engine's job. |
| D | Extend the normalizer so the normalized narration *is* the merchant, and remember that. | Fixes the problem at the root for de-duplication too. Changes shared engine behaviour that de-duplication already depends on — a determinism and parity risk well outside this slice's scope. |
| Custom | Provide your own answer | Describe how much of the description defines a merchant and who decides. |

**Your choice**: **Option B.** A **derived merchant portion** of the normalized narration, produced by one documented, deterministic rule and shown to the person in plain words before the memory is formed. The derivation is **additive** — it reads `normalize_narration`'s output and never changes it, because de-duplication already depends on that shared behaviour, which is the reason option D was refused. It exists to stop the app making a false promise: a memory that can only ever match the row it was formed from has taught nothing (FR-027, SC-008). FR-027, FR-027a–FR-027c, SC-008, SC-029.

---

### Q3: Where does the uncategorized worklist live?

**Context**: Slice 018 shipped a transaction list with an account narrowing and **six** honest empty states, each distinguishing a different real situation (`EmptyKind`, `TransactionListModels.swift:161-177`). Two of them are already known to be unreachable by any seed (`019/02`). Triage can be a second narrowing on that list, or a screen of its own. The first composes with the account narrowing and inherits 018's paging, ordering and empty states — and multiplies its empty states, since "no uncategorized rows in this account" is a new situation for each existing one. The second keeps 018 untouched but duplicates its paging and ordering, and duplication is exactly what 018's mechanical bans exist to prevent.

**What we need to know**: Is the uncategorized worklist a narrowing on the existing transaction list, or a separate surface?

**Suggested Answers**:

| Option | Answer | Implications |
|--------|--------|--------------|
| A | A second narrowing on the existing transaction list, composing with the account narrowing. | Nothing is duplicated; ordering, paging and liveness stay in one place. Grows 018's empty-state matrix, and every new combination needs its own honest wording and its own coverage. |
| B | A separate worklist surface, reading through the same engine paging. | 018 stays exactly as it is; the worklist can be shaped as a worklist rather than a list. Two surfaces now render transactions, and the second must be held to 018's bans without inheriting them. |
| C | A narrowing, plus a visible entry point that opens the list already narrowed. | The fast path a person wants, with a single implementation underneath. Slightly more surface than A; the entry point needs somewhere to live and a count that must come from the engine. |
| Custom | Provide your own answer | Describe where a person goes to find their uncategorized transactions. |

**Your choice**: **Option C.** A narrowing on slice 018's existing transaction list, composing with the account narrowing, **plus a visible entry point that opens the list already narrowed**. One implementation underneath: 018's ordering, paging and liveness stay in exactly one place and nothing is duplicated. The entry point's count comes from the **engine**, not from a count in Swift — 018 deliberately moved the front door's count out of Swift and into SQL, and this slice does not reintroduce one. Because this is a narrowing, 018's empty-state matrix grows: every reachable combination of the two narrowings gets its own honest wording and its own coverage, and every unreachable one is said to be unreachable plainly rather than folded into a false claim of completeness — the precedent of 019's FR-039a and finding `019/02`. FR-036, FR-041–FR-043b.

---

### Session 2026-08-18

- Q: When a person corrects a category, what should "make it stick" actually change? → A: **Option D** — remember automatically for future imports; re-applying to existing rows is a separate, clearly labelled, explicitly consented second action that applies only the one memory just formed, with its affected row count and accounts shown first, and no multi-select affordance.
- Q: What counts as "the same merchant"? → A: **Option B** — a derived merchant portion of the normalized narration, by one documented deterministic rule, shown to the person before the memory is formed, additive to and never altering `dedup::normalize_narration`.
- Q: Where does the uncategorized worklist live? → A: **Option C** — a narrowing on 018's transaction list composing with the account narrowing, plus a visible entry point that opens it already narrowed, whose count comes from the engine.

---

### Decisions taken without asking

- **A person's decision is a distinct kind of provenance, and the engine protects it.** The engine's `Stage` values describe how *the engine* decided; a person deciding is a different fact. Recording a correction as if it were an engine verdict makes it indistinguishable from one and therefore erasable by one. The protection lives in the engine rather than in the app so that it cannot be bypassed by any caller. FR-018, FR-021, FR-025.
- **"No category, deliberately" is a decision and is protected too.** The tempting shortcut is to treat an absent category as "not yet decided" and let the engine fill it. Since `categorize_account_in` writes `NULL, NULL` for rows it cannot place (`store.rs:1316-1323`), a person's deliberate blank is otherwise indistinguishable from the engine's shrug — and would be quietly overwritten the first time a new rule happened to match. FR-020, SC-003.
- **A person can set a transaction back to having no category.** Every correction here is reversible, including reversing into emptiness. The alternative — a one-way door where assigning a category can never be undone — is a worse defect than any it prevents. FR-007.
- **The most recent instruction about a merchant wins, and contradictory memories are not accumulated.** Two memories of the same shop at the same precedence would make the outcome depend on an ordering nobody can see, which breaks determinism in the one tier that exists to hold what a person said. FR-031, SC-007.
- **A correction on a transfer leg behaves like any other correction and outranks the detector.** `detect_transfers` writes `TRANSFER_DETECTOR` and `categorize_account_in` never touches transfer rows (`store.rs:1759-1774`), so no conflict arises in the engine. In the shipping app the question is currently unreachable in any case, because `scripts/import-path-audit.sh` bans the app from calling transfer detection at all. The rule is stated now so it is not invented later under pressure.
- **A correction stays attached to the row it was made on when that row is superseded.** A superseded row is invisible, so the correction has no visible effect — which is the correct outcome for a row the person can no longer see. The merchant memory, where one was formed, is what carries the intent onto the surviving row. Named as an edge case so `/speckit.plan` must confirm the surviving row actually ends up right.
- **No aggregate of any kind.** Not a total, not a count of spend, not a share by category — nothing beyond a count of *how many transactions remain uncategorized*, which is a worklist length and not a figure about money. Analytics is a later slice and this slice must not pre-empt its decisions. FR-078.
- **The seeding capability is spent, not extended.** This slice adds scenarios to 019's existing single declaration. If it appears to need a new seeding mechanism, a new generator or a second way of making fixtures, that is scope drift and a signal to stop. FR-066.
- **The schema migration is assumed necessary and is specified as a requirement, not a design.** Whether the person's decision is carried by a new column, a new table or a reserved provenance value is `/speckit.plan`'s decision; that it must not lose or re-derive a single existing row is not. FR-046 to FR-049, US7.

#### Reconciled after Q1–Q3 were answered

All nine decisions above stand. Three of them needed their edges redrawn, and one requirement elsewhere in this spec contradicted an answer outright and was rewritten rather than left to be discovered in planning.

- **"The most recent instruction about a merchant wins" survives Q1's answer unchanged, and gained a clause.** Automatic remembering forms at most one memory per merchant, so the second correction **replaces** the first rather than accumulating beside it, and FR-031 holds exactly as written. What it did not cover is rows an earlier second action had already changed: those are the person's own decisions and are not rewritten retroactively, so the newer offer counts them and says so. FR-031a is new for that reason.
- **"No aggregate of any kind" needed its boundary restated, not moved.** It already allowed a count of how many transactions remain uncategorized. Q1's answer requires a second count — how many rows a second action would change, and in which accounts — and Q3's requires that first count on an entry point. Both are counts of transactions, not figures about money, and FR-078 now says so explicitly. **Zero** aggregates of spend are introduced.
- **"A correction stays attached to the row it was made on when that row is superseded" now has a companion.** A second action counts and changes live rows only (FR-035d), so a superseded row is neither counted nor touched, and the surviving row is reached by the memory like any other.
- **FR-013 contradicted Q1's answer and was rewritten.** As drafted it banned *any* way to change more than one transaction's category in a single action, which would have forbidden the second action the answer requires. It now bans the general capability — multi-select, selection mode, "apply to these" — and carves out exactly one narrow exception, named and bounded by FR-035a–FR-035h. Out of Scope is unchanged: bulk recategorization is still refused.
- **FR-076 needed the same treatment for Q3's answer.** Its ban on "filtering" under the transaction list's sources is a ban on the **interface** filtering a broader read, not on the engine gaining a second narrowing in its own query. FR-076 now says which of the two it means, so that the uncategorized narrowing cannot be read as either permitted sloppiness or a forbidden feature.

## Assumptions

- The store is at schema version 7 and this slice advances it, most likely to 8. The exact mechanism is `/speckit.plan`'s decision; the preservation guarantees are not.
- The transaction list already displays a category or the word for its absence on every row, so this slice extends that promise to new surfaces rather than establishing it.
- The twenty-three built-in categories are sufficient for this slice. A person who needs a category the app does not have will be served by a later slice, and this spec does not soften that.
- Transactions in the shipping app are never transfers today, because the app is banned from calling transfer detection. Requirements about transfer legs are written so the behaviour is defined when that changes, not because it is reachable now.
- No store in the wild yet holds a person's corrections, because nothing has ever written one, so the migration must preserve existing data but need not migrate any prior form of this feature.
- The derived merchant portion is a **new** engine concept living beside the existing narration normalization, not a change to it. Its separator set, its stop-list and its maximum segment count are fixed in full by `/speckit.plan` and pinned by fixtures; that they exist, are closed, are documented and are shown to the person before a memory forms is not `/speckit.plan`'s to reopen.
- A merchant portion that is broader than the person meant is possible, and this slice's answer to it is visibility rather than an undo surface: the portion is shown before the memory forms, and the second action's count and accounts are shown before any existing row changes. Managing or deleting a memory afterwards remains a later slice.
- `make core-xcframework` then `make ios-gen` is the required sequence whenever the engine's interface changes, and this slice changes it.
- New platform code will live in its own directory under `ios/Sources/`, which the project manifest picks up automatically through its existing source globs; sharing any of it with the test targets is the only case that needs a manifest change.
- Timing is deliberately absent from the success criteria. `019/04` established that a wall clock in a UI test measures the machine, and this slice declines to re-learn it. Performance concerns, if any, are stated as findings and measured on a physical device in Release, per `018/06`.

## Out of Scope

Each of the following is a later slice. Naming them here is how they get refused rather than debated.

- **Creating, renaming, reordering or deleting a person's own categories** beyond the twenty-three built-ins.
- **Bulk or multi-select recategorization** — choosing many transactions and changing them together. Q1 was answered **D**, and the second action it introduces (FR-035a–FR-035h) is **not** this: it applies the one memory the person has just formed, after showing how many rows and which accounts, and offers no selection of anything. **No multi-select affordance ships here**, and this exclusion stands unchanged.
- **Managing remembered merchants as a set** — viewing, editing, reordering or deleting them.
- **Managing the engine's own rules through the interface** — the issuer source-category map (T1) or the keyword, regex and amount-range rules (T3).
- **Category budgets**, targets, limits or alerts.
- **Any analytics, chart, total, average or spend-by-category rollup.**
- **Anything premium, cloud, server-backed or AI-assisted**, including the Pro T4 tier of the categorization stack.
- **Changing the categorization stack's stage order, first-wins behaviour or matching semantics**, beyond adding the protection a person's decision requires.
- **Changing the transaction list's ordering, paging, liveness rule or account narrowing.**
- **Search, tags, notes, attachments or splitting a transaction.**

## Dependencies

- **`016-statement-import-vertical`** — the import path this slice's corrections must survive.
- **`018-transaction-list`** — the list, its rows, its paging, its account narrowing and its six empty states, all of which this slice extends and none of which it may change.
- **`019-debug-test-seeding`** — the DEBUG-only seeding capability, its named scenarios and its absence proof, which this slice spends and extends by declaration only.
- **`core/crates/kaname-core/src/categorize.rs`** — the shipped stack, its twenty-three categories and its merchant memory.
- **`core/crates/kaname-core/src/store.rs`** — schema version 7, its forward-only migrations, and the two statements that today are the only writers of a transaction's category.
- **`scripts/import-path-audit.sh`** — the mechanical bans that must stay green, unweakened.
- **`.specify/memory/constitution.md`** — which wins over everything in this document.
