# Feature Specification: The Transaction List (See and Scroll What Import Has Been Writing)

**Feature Branch**: `018-transaction-list`  
**Created**: 2026-08-14  
**Status**: **Ready for `/speckit.plan`** — both clarifications resolved (Session 2026-08-14; see Clarifications).  
**Milestone**: P3 (Core SwiftUI app) — the **third** slice of P3, and the first slice that gives a person somewhere to *go*. Slices 016 and 017 built a pipeline that writes transactions to the device; this slice is the first that lets a person read them.  
**Input**: User description: "The transaction list — the screen that lets a person actually see and scroll the transactions that statement import has been writing to their device."

> **Note on priority labels**: This feature sits in product milestone **P3** (Core SwiftUI app). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P3" and "User Story P3" are unrelated numbering schemes.

## Why this slice exists

Kaname can read a statement. It cannot show one.

Slice `016-statement-import-vertical` delivered the whole import vertical — the front door, native text extraction into the engine, the encrypted store, honest failures, account attribution, the integrity verdict, a cancellable import. Slice `017-column-major-pdf` made that extraction geometry-first, so real multi-column statements yield real rows. Between them, a person's financial history is now on their device, parsed, categorized, de-duplicated, integrity-checked and encrypted at rest.

And then the app shows them a number.

Today, once anything has been imported, the front door is a flat list of accounts. Each row carries the account's name, its masked last-4, and **a transaction count**. The rows do not respond to touch. There is nowhere to go. That count is the *only* evidence a person has that their data is really there — an unverifiable assertion that Kaname read forty-two things. A finance app whose entire user-visible output is a number a person cannot audit is asking for a trust it has not earned.

This slice is what that count should lead to.

**The list is a list of the person's money, not a list of one account's money.** The question a person actually asks is "what did I spend?", not "what did I spend on the Federal card". So the screen this slice delivers is **one combined list across every account**, each row naming the account it came from, and **looking at a single account is a filter on that one list** rather than a second screen. The front door's per-account count still leads somewhere — it leads into the same list with that account's filter already applied — which keeps one screen, one ordering rule and one set of empty states instead of two of each.

That choice is more honest about what a person wants and more expensive to build than the per-account form, and this spec says so rather than discovering it in planning:

**A cross-account read does not exist today.** The engine's store can list the transactions of *one* account. Nothing in it can produce an ordered view across all of them, and nothing in it can hand back a screenful at a time. This slice therefore does add **new engine surface**, and that surface crosses the FFI — which means it lands in a different pull request from the interface work and needs its own tests on the engine side. This spec states the capability required in terms of what the screen needs; it deliberately does not prescribe its shape, which is `/speckit.plan`'s decision. It remains true that this slice adds **no parsing, no categorization, no new stored data and no writes** — every field it renders is already written, already exact, already encrypted.

**Ordering now has to span accounts.** Two accounts' rows interleave by date, and a date that carries rows from more than one account needs a tie-break that is defined, total and stable. Without one, the same data can draw in a different order on the next launch — and a finance app whose history reshuffles by itself has told the person, convincingly, that it is making things up. Within a single account, the printed statement's own order remains the tie-break, because the statement in the person's other hand is the reference document.

**Multi-currency stops being an edge case and becomes load-bearing.** Every stored transaction carries its own currency. One account is usually one currency; the *combination of every account* very often is not. This spec therefore answers what a mixed-currency list does rather than deferring it: every amount always shows its own currency, nothing is ever converted or normalised, and **no figure anywhere in this slice may be derived by combining amounts in different currencies**. Since a cross-currency sum is meaningless rather than merely imprecise, the rule is not "be careful" — it is that such a figure must not exist. This slice has no totals, which makes now the cheap moment to fix that rule in place, before the dashboard slice arrives wanting one.

That makes this slice unusually exposed. A transaction list is the first screen where the app's data is checkable against something the person already has — the printed statement in their other hand. Every row is a claim that can be proved wrong. If a date is off, if an amount is rounded, if a debit reads as a credit, if a row appears twice, if a row is attributed to the wrong account, the person will see it here first, and it will be the last thing they trust the app about.

Three hard-won facts from the slices before this one constrain it directly, and all three are written into the requirements below rather than left to good intentions.

**The store's transaction list is a raw view, not a history.** It returns rows that were deleted, and it returns the superseded losers of a de-duplication. Both are retained deliberately: when a person re-imports a statement they already imported, every row is written again and the repeats are *linked* to what they duplicate rather than dropped (slice 016, FR-025), so provenance survives a re-import. Neither deleted rows nor superseded rows are things the person has. This is not a hypothetical: a bug shipped in 016 because the accounts list counted that raw view directly, and a person's transaction count visibly doubled the moment they re-imported the same statement — on the one screen whose promise was that it would not. It was fixed, and the live-row rule now lives in one place beside the reason for it. **Every screen and every count this slice adds inherits that rule, and this spec makes it a requirement rather than a convention**, because each new surface can get it wrong the same way — and a combined list adds more of them, not fewer.

**The accessibility rules have been paid for in failures.** De-emphasised styling does not carry content text at any size this app uses; a value rendered in that de-emphasised style must be restored to full contrast explicitly; a prominent translucent button refracting scrolled content fails at accessibility text sizes, so bottom bars sit on an opaque surface; and the app carries its own accent because the system default sits in the auditor's borderline band. There is also a **live, unresolved finding on the accounts list**: at the largest accessibility text size the auditor reported a contrast failure on the transaction count, at a position consistent with a two-column row collapsing to a vertical layout and pushing its own content underneath the opaque bottom bar. A transaction list is a two-column row — description on one side, amount on the other — repeated hundreds of times, and in the combined form each row now carries an account name as well. **The known failure mode of the screen this slice replaces is the exact shape of the screen this slice adds, with more content in it.**

**The automated accessibility audit cannot reach this screen, and that is a recorded limitation rather than an oversight.** The system auditor runs against a launched app and can only audit what it can navigate to. Every screen behind an import — the summary, the failure, the password prompt, the account picker, and now the transaction list — sits behind a real file being picked, which no automated run can do. Slice 016 recorded this and parked the decision (`.scratch/HANDOFF.md`, T115/T123): a **DEBUG-only seeding hook** in the app would make every one of these screens auditable, at the cost of a test-only entry point in shipped source. That hook is **its own slice, scheduled before the categorize slice**, and it is explicitly not designed or built here. For *this* slice, the rendered-screen audit is therefore a **manual, release-blocking gate**, in the same category as 016's T123 — and everything that can be proven without a rendered screen is automated instead, so the manual gate stays as small as it honestly can be.

Everything here stays inside the constitution's boundaries. Reading a list of transactions is a free, fully on-device capability: **zero network I/O**, no analytics, no telemetry. Money remains an **exact decimal** from the store to the pixel and is never a floating-point number at any point, including in formatting. Every fixture is **synthetic**.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See everything I have, across every account (Priority: P1)

A person who has imported statements opens the app and reaches one list of their transactions — all of their accounts together, most recent first. Each row shows the date it happened, the description as the statement printed it, the exact amount with money out plainly distinguishable from money in, and **which account it belongs to**. They scroll it, they recognise their own spending, and the numbers they were shown on the front door are now something they can count.

**Why this priority**: This is the entire slice, and the first moment the app's stored data becomes checkable by the person who owns it. Shipped alone it is a viable MVP: import stops being an act of faith. Every other story below qualifies, protects or explains this one.

**Independent Test**: Import synthetic statements for two different accounts with a known set of transactions each, open the combined list, and confirm it shows exactly those transactions — same total count, same dates, same descriptions, same exact amounts, same directions, each attributed to the right account — as the fixtures declare.

**Acceptance Scenarios**:

1. **Given** transactions have been imported for one or more accounts, **When** the person opens the app, **Then** they can reach the combined transaction list in no more than one action from the front door.
2. **Given** the combined list is on screen, **When** the person reads any row, **Then** it shows the transaction's date, its description as the statement printed it, its amount, and the account it belongs to.
3. **Given** any row, **When** its amount is shown, **Then** it is exact to the last paisa — identical to the amount on the printed statement, with no rounding drift and no floating-point representation.
4. **Given** a row for money leaving an account and a row for money entering one, **When** both are on screen, **Then** the two are distinguishable **without relying on colour**, and each is announced as a debit or a credit in words.
5. **Given** two accounts holding N and M live transactions, **When** the unfiltered list is shown, **Then** it contains exactly N + M transactions.
6. **Given** two accounts contain a transaction with the same date, description and amount, **When** both appear in the list, **Then** each is attributed to its own account and neither is mistaken for, merged with, or hidden by the other.
7. **Given** the combined list has been used, **When** the app is inspected for outbound network activity across the whole screen, **Then** **zero** network requests were made.
8. **Given** the person is finished, **When** they leave the list, **Then** they can return to the front door by the standard back gesture and the front door is as they left it.

---

### User Story 2 - Re-importing a statement does not double what the person sees (Priority: P2)

A person imports a statement, looks at their transactions, then imports the same statement again a month later — from a different folder, after a reinstall, or simply by mistake. The list is unchanged: the same transactions, the same number of them, in the same order. Nothing doubled, nothing vanished, nothing reshuffled.

**Why this priority**: Double-counted spend is the single most damaging error a personal-finance app can make, and it has already happened once in this app on the screen this slice replaces. The store deliberately keeps the duplicate rows and the deleted ones, so a list that reads the store naively reproduces the bug exactly. It sits directly below the list itself because a doubled list is worse than no list — it is confidently wrong, and it looks authoritative. A combined list makes it worse still: the doubling would now be buried among other accounts' rows rather than isolated on one screen.

**Independent Test**: Import one synthetic statement, record the combined list's rows and their order; import the identical file again; confirm the list's contents, count and order are unchanged, and that every front-door count still agrees with the list filtered to that account.

**Acceptance Scenarios**:

1. **Given** a statement that has been imported once, **When** the identical statement is imported again, **Then** the combined list shows the same transactions, the same number of them, and in the same order as before.
2. **Given** the re-import in (1), **When** the front door is shown, **Then** its transaction count for that account is unchanged and still equals the number of rows the list shows when filtered to that account.
3. **Given** a transaction that was superseded as a duplicate of another, **When** the list is shown, **Then** that transaction does not appear — and its absence leaves no blank row, no gap, and no placeholder.
4. **Given** a transaction that has been deleted, **When** the list is shown, **Then** it does not appear.
5. **Given** every transaction on every account is superseded or deleted, **When** the list is opened, **Then** the person sees a plainly-worded empty state rather than an empty list or a broken screen.
6. **Given** a re-import into one account, **When** the combined list updates, **Then** no other account's rows change, move or disappear.

---

### User Story 3 - Narrow to one account (Priority: P3)

A person with several accounts wants to check one of them against the paper statement in their hand. They tap that account on the front door and land in the same list, filtered to that account. The filter is named and visible, they can clear it in one action to get everything back, and while it is applied the number of rows is exactly the count the front door promised.

**Why this priority**: Without it, the front-door counts stay unverifiable — the very problem this slice exists to fix — and a person cannot reconcile a single statement without reading around every other account's spending. It ranks below the correctness stories because a filtered wrong list is still wrong, but above ordering because reconciling one account is the concrete task people bring to this screen first.

**Independent Test**: Import synthetic statements for three accounts; tap one account on the front door; confirm the list shows exactly that account's live transactions and exactly the count the front door showed; clear the filter in one action and confirm all three accounts' transactions return; re-apply, force-quit, relaunch and confirm the documented behaviour on relaunch.

**Acceptance Scenarios**:

1. **Given** the front door lists accounts, **When** the person taps one, **Then** they arrive at the transaction list already filtered to that account, in a single action.
2. **Given** the filter is applied, **When** the person looks at the screen, **Then** the account being filtered to is named on screen at all times, using the same identity the front door shows.
3. **Given** the filter is applied, **When** the rows are counted, **Then** the number of rows equals the transaction count the front door showed for that account.
4. **Given** the filter is applied, **When** the person clears it, **Then** they do so in a single action and every account's transactions return.
5. **Given** the filter is applied, **When** the person changes it to a different account, **Then** the list shows only that account's transactions, with no rows of the previous account left behind.
6. **Given** the filter is applied and the app is force-quit and relaunched, **When** the person opens the list again, **Then** it is **unfiltered** — every account's transactions are shown — and this is true on every launch, so a person can never be reading a subset of their spending without having chosen it in this session.
7. **Given** the filter is applied to an account with no live transactions, **When** the list is shown, **Then** the empty state names that account and offers to clear the filter, rather than implying the person has no transactions at all.
8. **Given** the filter is applied, **When** VoiceOver is used, **Then** the fact that the list is filtered, and to which account, is announced — never conveyed by visual styling alone.

---

### User Story 4 - A long history reads as a history, not a pile (Priority: P4)

A person with a year of statements across several accounts scrolls back through their spending. Transactions arrive most-recent-first. They are grouped by the day they happened, and the day being read stays identifiable while scrolling, so a person deep inside a busy month always knows where they are. Two accounts' rows sit together under the day they share. The order never changes between one launch and the next.

**Why this priority**: An unordered or unstably-ordered wall of rows is technically correct and practically unusable, and — worse — an order that shuffles between launches reads as data changing on its own, which destroys the trust User Story 1 exists to build. Combining accounts makes this sharper, because same-date rows from different accounts have no natural order and will take whatever order the machine happens to produce unless one is specified.

**Independent Test**: Import several synthetic statements for at least three accounts covering multiple months, including one day carrying transactions from more than one account; confirm the list is most-recent-first, grouped and headed by date, that the date context remains visible while scrolling, and that the exact order — including the order of same-date rows from different accounts — is identical across a force-quit and relaunch, and identical again after importing an unrelated account.

**Acceptance Scenarios**:

1. **Given** transactions spanning several months and several accounts, **When** the list is shown, **Then** the most recent transaction is at the top and the oldest at the bottom, regardless of which account each belongs to.
2. **Given** the list contains transactions from more than one date, **When** it is shown, **Then** transactions are grouped by the date they happened and each group is headed by that date.
3. **Given** the person is scrolling through a date with many transactions, **When** the group's heading would otherwise have scrolled away, **Then** the date they are currently reading remains identifiable on screen.
4. **Given** several transactions of the **same account** share a date, **When** the list is shown, **Then** they appear in the order that account's statement printed them, so the screen can be read against the paper side by side.
5. **Given** transactions of **different accounts** share a date, **When** the list is shown, **Then** they appear in a defined, repeatable order that does not depend on when anything was imported or read.
6. **Given** any list, **When** the app is force-quit and relaunched and the same list reopened, **Then** the transactions appear in exactly the same order as before.
7. **Given** a further account is imported, **When** the list is shown again, **Then** the relative order of every transaction that was already there is unchanged.
8. **Given** transactions from a year other than the current one, **When** their date is shown, **Then** the year is included, so no row is ambiguous about when it happened.

---

### User Story 5 - Two currencies never quietly become one (Priority: P5)

A person holds a rupee card and a card billed in another currency. Both appear in the same list. Every amount says what currency it is in, no amount is converted into another, and nowhere on the screen is there a figure that could only have been produced by adding them together.

**Why this priority**: Combining accounts is what makes this reachable at all, and a currency read as the wrong one is a wrong number presented as a right one — the failure mode with the least chance of being noticed and the most damage when it is. It ranks below ordering because it affects fewer people, and above the engine-derived detail below because it is a correctness matter rather than a usefulness one.

**Independent Test**: Import synthetic statements for two accounts in different currencies, including transactions of both currencies on the same date; confirm every row carries its own currency unambiguously, that no conversion or normalisation appears anywhere, and that no figure on the screen aggregates across currencies.

**Acceptance Scenarios**:

1. **Given** a list containing amounts in more than one currency, **When** any row is read, **Then** its amount carries its own currency unambiguously, and cannot be read as an amount in a different one.
2. **Given** a date group containing amounts of more than one currency, **When** it is shown, **Then** the heading carries the date only, and no summed, averaged or otherwise combined amount appears on it.
3. **Given** amounts in more than one currency exist anywhere in the app's data, **When** this feature draws anything, **Then** **no** figure it shows is derived by combining amounts of different currencies.
4. **Given** a currency the person's locale does not usually format, **When** an amount in it is shown, **Then** it is still exact, still unambiguous as to currency, and still not clipped or truncated.
5. **Given** a mixed-currency list, **When** VoiceOver reads a row, **Then** the currency is announced along with the amount.

---

### User Story 6 - What the engine already worked out is visible (Priority: P6)

The engine has already decided things about these transactions: which category each one falls into, and which ones are transfers between the person's own accounts rather than real spending. The list shows both. A transfer is marked as a transfer, so a person moving money between their own accounts does not read it as money spent. A transaction the engine could not categorize says so plainly instead of showing nothing.

**Why this priority**: This information is already computed, already stored, and costs nothing to surface — and omitting it actively misleads. An unmarked transfer reads as spending, which inflates a person's sense of what they spent by exactly the amount they moved — and in a combined list, a transfer between two of the person's own accounts now shows up **twice**, once on each side, making the inflation double and the marking twice as necessary. A blank where a category should be reads as a bug rather than as an honest "not yet known".

**Independent Test**: Import synthetic statements for two accounts containing a transfer pair the engine detects, plus transactions that categorize and transactions that do not; confirm both sides of the transfer are marked and announced as such, the assigned categories are shown, and uncategorized transactions are labelled rather than blank.

**Acceptance Scenarios**:

1. **Given** a transaction the engine has flagged as a transfer, **When** it appears in the list, **Then** it is marked as a transfer, and that mark is conveyed by something other than colour alone.
2. **Given** a transfer between two of the person's own accounts, **When** the unfiltered list is shown, **Then** both sides appear, each on its own account's row, and each is marked as a transfer.
3. **Given** the transfer in (1), **When** VoiceOver reads the row, **Then** it is announced as a transfer.
4. **Given** a transaction the engine assigned a category, **When** it appears in the list, **Then** its category is shown by name.
5. **Given** a transaction the engine left uncategorized, **When** it appears in the list, **Then** the row says so in plain language rather than leaving the category blank.
6. **Given** any row, **When** it is displayed, **Then** it contains **no** engine internals — no identifiers, no de-duplication layer names, no internal codes describing how the category was decided.
7. **Given** a transfer, **When** it is shown, **Then** it is still present in the list — a transfer is a real movement on that account's statement and is never silently hidden.

---

### User Story 7 - Nothing to show says why (Priority: P7)

Not every state has transactions in it. A person may have imported nothing at all. A statement can genuinely contain none — a card unused for a month is a real and unremarkable thing. An account being filtered to may have nothing live in it. The list tells these apart, because telling a person who successfully imported a statement to go and import one is a lie that reads as data loss.

**Why this priority**: It is a small screen guarding a large trust problem. It ranks last among the functional stories because most of its states are ones most people will never see.

**Independent Test**: Produce four states — nothing imported at all; an account whose imported statement genuinely parsed zero transactions; an account whose every row is superseded or deleted; and the filter applied to an account with nothing live — and confirm each shows a distinct, plainly-worded state that does not accuse the app of having lost anything.

**Acceptance Scenarios**:

1. **Given** nothing has been imported at all, **When** the list is opened, **Then** it explains that nothing has been imported yet and offers the import action.
2. **Given** an account whose imported statement genuinely contained zero transactions, **When** the list is filtered to it, **Then** it says the imported statement had no transactions — and does **not** claim nothing has been imported, and does **not** present this as an error or a failure.
3. **Given** the filter is applied to an account with no live transactions while other accounts do have some, **When** the empty state is shown, **Then** it makes clear that the filter is why the screen is empty and offers to clear it.
4. **Given** exactly one transaction is shown, **When** any count is worded, **Then** it reads correctly in the singular.
5. **Given** any empty state in this story, **When** it is shown, **Then** it uses everyday language and never suggests the person's data may have been lost.

---

### User Story 8 - The list keeps up with an import, and stays honest during one (Priority: P8)

A person imports another statement while looking at the list. While the import runs, the list stays readable and does not flicker through half-written states. When the import finishes, the new transactions are there — without force-quitting the app. If the import fails or is cancelled, the list is exactly as it was.

**Why this priority**: A list that needs a relaunch to show what was just imported makes the import feel like it failed; a list that redraws mid-write can show a person a statement that is half in. It ranks here because it is only reachable after the earlier stories work, but it is what makes the two features feel like one app.

**Independent Test**: With the list open, import a further synthetic statement; confirm the new transactions appear once the import completes without a relaunch, that no partially-written state was visible during the import, and that a cancelled import leaves the list identical — testing both with no filter applied and with a filter applied to an account the import does not touch.

**Acceptance Scenarios**:

1. **Given** the transaction list is open, **When** an import completes, **Then** the newly imported transactions appear in the list without the person relaunching the app.
2. **Given** an import is running, **When** the person is reading the list, **Then** the list remains readable and responsive and never shows a partially-imported statement — the new rows appear as one complete change, not as a trickle.
3. **Given** an import that fails or is cancelled, **When** it ends, **Then** the list shows exactly what it showed before the import began.
4. **Given** the person has scrolled some way into a long list, **When** an import completes and the list updates, **Then** they are not thrown back to the top without warning.
5. **Given** a re-import that supersedes duplicates, **When** it completes and the list updates, **Then** the list still shows only what the person has, and every front-door count still matches the list filtered to that account.
6. **Given** the list is filtered to one account, **When** an import into a **different** account completes, **Then** the filtered list is unchanged and the person is not moved out of their filter.

---

### Edge Cases

- **A transaction with an empty or unreadable description.** The row must still show its date, account and amount and remain selectable and announceable; it must never collapse to an invisible or unlabelled row.
- **A very long description**, or **a very long account name**, that cannot fit the width — must remain readable enough to identify the transaction, and must not push the amount off screen or truncate the amount.
- **A very large amount** (seven or more digits before the decimal) at the largest accessibility text size — the amount must never be clipped, abbreviated, or truncated. An amount a person cannot fully read is worse than no amount.
- **Amounts in more than one currency in the same list, and on the same date** — each amount carries its own currency; no amount may be rendered as though it were in a currency it is not; no combined figure may appear.
- **Two accounts holding an identical-looking transaction on the same date** — same description, same amount, same direction. Both appear, each attributed to its own account, in a repeatable order.
- **A day carrying an unusually large number of transactions across several accounts**, such that a single date group exceeds a screenful — the date context must remain identifiable throughout.
- **A corpus of several thousand transactions spread over many accounts** — must open and scroll without the person waiting for content that never arrives.
- **Every row on every account superseded or deleted** — the empty state, not an empty list.
- **A filter applied to an account that is then left with nothing live** — the filtered empty state, naming the account and offering to clear the filter.
- **A transaction dated in the future**, or a statement with an implausible date — the list shows it where its date places it; this slice does not correct or hide it.
- **Rotation, and the largest accessibility text size, and Dark Mode together** — the two-column row shape is the exact layout that already produced an occlusion finding on the front door, and each row now carries an account name as well; no row content may end up underneath a bar or control at any combination of these.
- **Backgrounding the app mid-scroll and returning** — the list returns showing the same transactions in the same order, with the same filter state.

## Requirements *(mandatory)*

### Reaching the list

- **FR-001**: The app MUST offer **one** transaction list covering **all** accounts together, and the person MUST be able to reach it from the front door in **no more than one** action.
- **FR-002**: Each account shown on the front door MUST be actionable and MUST lead to that same list with a filter applied to that account, in **no more than one** action.
- **FR-003**: The list MUST make its current scope unmistakable at all times: either that it is showing every account, or which single account it is filtered to, named with the same identity the front door shows (the account's name and, when known, its masked last-4).
- **FR-004**: Every row MUST identify the account it belongs to, so that no transaction can be attributed to the wrong account by a person reading the screen.
- **FR-005**: The person MUST be able to return from the transaction list to the front door using the platform's standard back affordance, and MUST find the front door in the state they left it.
- **FR-006**: The transaction count shown for an account on the front door MUST equal the number of rows the list shows when filtered to that account. The two MUST NOT be able to disagree.

### Only what the person actually has *(the live-row rule)*

- **FR-007**: The list MUST show only **live** transactions — those that are neither deleted nor superseded by another transaction. It MUST NOT show deleted rows, and it MUST NOT show the superseded losers of a de-duplication. This holds identically whether the list is filtered or not.
- **FR-008**: **Every** count, total or number-of-transactions statement introduced by this slice MUST be derived using the same live-row rule as the list itself. No screen, and no filter state, may count one population and list another.
- **FR-009**: Re-importing a statement that has already been imported MUST NOT change what the transaction list shows: not its contents, not its count, and not its order.
- **FR-010**: An excluded row (deleted or superseded) MUST leave no visible trace in the list — no gap, no blank row, no placeholder, and no effect on grouping.
- **FR-011**: An import affecting one account MUST NOT change the rows, order or attribution of any other account's transactions in the list.

### What a row shows

- **FR-012**: Every row MUST show the transaction's **date**, its **description as the statement printed it**, its **amount**, and the **account** it belongs to.
- **FR-013**: Money leaving an account MUST be distinguishable from money entering it **at a glance and without relying on colour**. Colour MUST NOT be the only carrier of direction.
- **FR-014**: Direction MUST be taken from the direction the engine recorded and MUST NOT be inferred from the sign of an amount.
- **FR-015**: VoiceOver MUST announce each row as a single meaningful statement including its date, description, amount, currency, direction and account, with direction spoken **in words** (such as "debit" or "credit"), never as a symbol or a colour.
- **FR-016**: Amounts MUST be exact decimals at every step from the store to the screen, and MUST be rendered with tabular (monospaced) digits so figures do not jitter while scrolling.
- **FR-017**: A row MUST show the category the engine assigned, by name; a transaction with no category MUST be labelled as uncategorized in plain language rather than left blank.
- **FR-018**: A transaction the engine has flagged as a **transfer** MUST be marked as such, marked by something other than colour alone, announced as such by VoiceOver, and MUST still appear in the list — on both sides of the transfer when both accounts have been imported. ⚠️ **The app does not currently run transfer detection**, so this flag is never set in a real install (see `research.md` R18): this slice builds and tests the marking against a store where the flag is set directly, and **MUST NOT** claim on screen, in release notes, or in any test name that transfers are being detected. Wiring detection is the **categorize** slice's work.
- **FR-019**: No row may display engine or storage internals — no identifiers, no de-duplication layer names, no internal codes for how a category was decided, no raw error text.
- **FR-020**: A transaction whose description is empty or unreadable MUST still render a complete, selectable, announceable row carrying its date, account and amount.
- **FR-021**: An amount MUST NEVER be clipped, abbreviated or truncated, at any text size, for any magnitude, in any orientation. Where space is contested, the description yields first and the account name second; the amount never yields.
- **FR-022**: The account shown on a row MUST be the account the engine attributed the transaction to, and MUST NOT be inferred from anything else on the screen.

### Currency

- **FR-023**: Every amount MUST carry the currency of the transaction it belongs to, always and unconditionally — never only when the list happens to contain more than one currency.
- **FR-024**: No amount may be rendered in, converted into, or normalised to any currency other than its own. This feature MUST NOT introduce a "primary" or "home" currency.
- **FR-025**: **No figure this feature displays may be derived by combining amounts of different currencies.** A cross-currency total, average or comparison MUST NOT be produced, shown, or computed for display, in any state of the screen.
- **FR-026**: Grouping MUST carry no monetary aggregate. A date group heading MUST show the date (and, where useful, a count of transactions — which is not money), never a summed amount, precisely so that grouping can never force a cross-currency sum.
- **FR-027**: An amount MUST remain exact and unambiguous as to its currency even when that currency is not one the person's locale ordinarily formats.

### Order and grouping

- **FR-028**: Transactions MUST be ordered most-recent-first by the date they happened, across all accounts alike.
- **FR-029**: Transactions of the **same account** sharing the same date MUST appear in the order that account's statement printed them, so the screen can be read against the printed statement line by line.
- **FR-030**: Transactions of **different accounts** sharing the same date MUST appear in a defined order that is derived from a fixed account ordering — the same ordering the front door presents — and never from import time, read time, refresh order, or any identifier the person cannot see.
- **FR-031**: The resulting order MUST be **total, deterministic and stable**: any two transactions have a defined relative order; the same transactions MUST appear in the same order on every launch; and the order MUST NOT change unless the underlying data changes.
- **FR-032**: Importing a new account or new statement MUST NOT change the relative order of transactions already in the list.
- **FR-033**: Transactions MUST be grouped by the date they happened — one group per date across all accounts, not one group per account per date — and each group MUST be headed by that date.
- **FR-034**: While the person scrolls within a date group, the date they are currently reading MUST remain identifiable on screen.
- **FR-035**: A date MUST include its year whenever that year is not the current year.

### The account filter

- **FR-036**: The list MUST support restricting itself to a single account. This restriction is a **filter on the one list**, and MUST NOT be a separate screen with its own ordering, empty states or row treatment.
- **FR-037**: Tapping an account on the front door MUST enter the list with that account's filter already applied, without any further input.
- **FR-038**: While a filter is applied, the filtered account MUST be named on screen at all times, and the filtered state MUST be announced by VoiceOver rather than conveyed by visual styling alone.
- **FR-039**: The person MUST be able to clear the filter in a **single** action, returning to every account's transactions.
- **FR-040**: The person MUST be able to change the filter from one account to another without leaving the list, and no row of the previous account may remain when they do.
- **FR-041**: The filter MUST NOT persist across app launches: a relaunch MUST show the unfiltered list. This behaviour MUST be the same on every launch, so a person is never surprised about which population they are reading.
- **FR-042**: Filtering MUST NOT change ordering, grouping, row content, currency handling or the live-row rule — a filtered list is the same list with fewer rows in it.

### Reading across every account

- **FR-043**: The app MUST be able to present transactions **across every account** in one ordered sequence. This capability does not exist today — the store can read one account at a time — so this slice introduces it. *(Its shape is `/speckit.plan`'s decision; this requirement fixes only what the screen needs of it.)*
- **FR-044**: That capability MUST be able to yield the first screenful of the ordered sequence, and successive portions of it, **without every account's full history being read or held in memory**.
- **FR-045**: The ordering, the live-row rule and the account filter MUST be applied consistently to whatever population is read — a screenful must never be assembled from rows selected under one rule and ordered under another.
- **FR-046**: The number of live transactions reported for an account anywhere in the app MUST come from the same rule as the list itself, so that a count and a list can never be produced by two different definitions.

### Empty and boundary states

- **FR-047**: When nothing has been imported at all, the list MUST show an empty state that says so and offers the import action.
- **FR-048**: An account whose imported statement genuinely contained **zero** transactions MUST, when filtered to, show a **distinct** empty state saying the statement had no transactions. It MUST NOT be presented as an error, as a failure, or as "nothing imported yet".
- **FR-049**: A filter applied to an account with no live transactions, while other accounts do have some, MUST show an empty state that makes the filter the reason and offers to clear it.
- **FR-050**: An account whose every transaction is deleted or superseded MUST show an empty state, not an empty list.
- **FR-051**: No empty state may suggest, in wording or tone, that the person's data may have been lost.
- **FR-052**: Any worded count MUST be grammatically correct in the singular as well as the plural.

### Staying current with import

- **FR-053**: When an import completes, an open transaction list MUST reflect the newly imported transactions **without requiring an app relaunch**.
- **FR-054**: While an import is running, the list MUST remain readable and responsive, and MUST NOT display a partially-written statement. Newly imported transactions MUST appear as one complete change.
- **FR-055**: An import that fails or is cancelled MUST leave the list showing exactly what it showed before the import began.
- **FR-056**: When the list updates after an import, the person MUST NOT be silently returned to the top of a list they had scrolled, and MUST NOT be moved out of an applied filter.

### Responsiveness

- **FR-057**: Reading transactions from the encrypted store MUST happen **off the main thread**; the interface MUST remain responsive while transactions are being read.
- **FR-058**: The list MUST scroll smoothly at the device's full frame rate regardless of how many transactions exist in total across all accounts.
- **FR-059**: The time from opening the list to seeing its first screenful MUST NOT grow in proportion to the total number of transactions held across all accounts, nor in proportion to the number of accounts.
- **FR-060**: Applying or clearing the filter MUST NOT require re-reading the whole history to draw the first screenful, and MUST NOT block the interface.
- **FR-061**: Memory use MUST NOT grow without bound as the person scrolls a long history.

### Privacy and data handling

- **FR-062**: The transaction list MUST perform **zero** network I/O. No analytics, no crash reporting, no telemetry of any kind may be added on this path, including on the new cross-account read.
- **FR-063**: No transaction description, amount, date, category, currency or account identifier may be written to logs or diagnostics.
- **FR-064**: All fixtures added by this feature MUST be **synthetic**; no real statement, real merchant record or real account identifier may enter the repository.

### Accessibility and presentation

- **FR-065**: Every element of this screen MUST support Dynamic Type through the largest accessibility sizes, with **no clipping and no truncation of any amount, date, currency, account name or category**.
- **FR-066**: Content text MUST NOT be rendered in a de-emphasised or secondary style. Any value that a container renders de-emphasised by default MUST be explicitly restored to full contrast. This applies to the account name on a row, which is content and not decoration.
- **FR-067**: **No row content may be occluded** by a bottom bar, floating control or any other overlay, at any text size, in any orientation — including the case where a multi-column row collapses to a vertical layout at accessibility text sizes and grows taller than its usual height.
- **FR-068**: Dense rows of transactions and the figures in them MUST be read against an **opaque** surface. Translucent material MUST NOT be placed under scrolling rows of transactions or numbers.
- **FR-069**: No prominent translucent action may refract scrolling transaction content; any persistent action on this screen, including the filter control, sits on an opaque surface.
- **FR-070**: Contrast and legibility MUST hold in **Dark Mode**, with **Increase Contrast** enabled, and with **Reduce Transparency** enabled. No material or translucency treatment may be the only thing carrying meaning.
- **FR-071**: Colour MUST NEVER be the sole carrier of any meaning on this screen — not for direction, not for transfers, not for uncategorized transactions, not for the filtered state.
- **FR-072**: Every row MUST be reachable and announced as one meaningful element under VoiceOver, and every date group heading MUST be announced.
- **FR-073**: Any tint used on this screen MUST be the app's own accent rather than the system default.

### How accessibility is verified *(the automated / manual split)*

- **FR-074**: Everything about this screen that is provable **without a rendered screen** MUST be covered by automated tests in the existing unit test target, in the manner already established for the import screens. That set MUST include, at minimum: the exact wording of every user-visible string and empty state; the presence and wording of every accessibility label and announcement, including direction in words, currency, account, transfer marking, category and uncategorized labelling, and the filtered state; the live-row filtering; the ordering and its same-date tie-break; the account filter's effect on the population; and the singular/plural wording of every count.
- **FR-075**: The remainder — the system accessibility audit against the rendered screen at default and largest accessibility text sizes, in Light and Dark Mode, with Increase Contrast and with Reduce Transparency, plus VoiceOver judged for meaningfulness — MUST be run **manually by a person** and is **release-blocking** for this slice, in the same category as slice 016's manual gate. It MUST be recorded in this slice's quickstart with the steps, the build and the date it was run.
- **FR-076**: This manual gate MUST be documented as manual **because the automated auditor runs against a launched app and cannot reach any screen behind an import**, which is every screen this slice adds — a limitation already recorded in slice 016. It MUST NOT be worded in any way that could be read as something continuous integration enforces.
- **FR-077**: This slice MUST NOT add a test-only or DEBUG-only entry point to the shipped app in order to close that gap. That hook is a separate, later slice (see Out of Scope).

### Key Entities *(include if feature involves data)*

- **Account**: What the person recognises as one card or one bank account — a name (as the engine reported the issuer), an optional masked last-4, and whether it is a card or a bank account. Already exists; this slice makes it both a label on every row and the thing the filter selects.
- **Transaction**: One dated movement of money on an account — its date, the description as printed on the statement, an exact amount, a direction (money in or money out), a currency, an optional category, and flags recording whether it is a transfer, whether it has been deleted, and whether it has been superseded by another transaction as a duplicate. Already exists; this slice reads it and never writes it.
- **Live transaction**: The subset of transactions that the person actually has — neither deleted nor superseded. This is the *only* population this slice ever shows or counts, filtered or not.
- **Combined history**: Every account's live transactions in one ordered sequence, most recent first. New to this slice; it is what the screen reads and what the filter narrows.
- **Account filter**: An optional restriction of the combined history to a single account. Not a separate screen and not a separate ordering — the same list, with fewer rows.
- **Category**: A name the engine assigned to a transaction, drawn from the built-in set or from a category the person created. Already exists; this slice displays it and never changes it.
- **Date group**: A calendar date together with the live transactions from every account that happened on it — the unit by which the list is organised and headed, and one that never carries a monetary total.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A person who has imported statements can go from opening the app to reading their transactions across every account in **one tap**, and can identify a specific transaction they made — and the account it was on — from its row alone.
- **SC-002**: **100%** of the live transactions imported statements contain appear in the combined list, with dates, descriptions, exact amounts, currencies, directions and account attribution matching the statements — verified against synthetic golden fixtures, with **zero** rounding drift at the last paisa and **zero** rows attributed to the wrong account.
- **SC-003**: Importing the **same statement twice** produces a transaction list that is identical in contents, count and order to the list after one import — verified automatically.
- **SC-004**: Every account's front-door transaction count and the number of rows the list shows when filtered to that account agree in **100%** of tested states, including after a re-import, after a deletion, and after an import that supersedes duplicates. Applying a filter and clearing it each take **one** action, restore exactly the population they promise, and a relaunch shows the unfiltered list in **100%** of tested cases.
- **SC-005**: **Zero** deleted or superseded transactions are visible anywhere in this feature, in any filter state, verified automatically against a store seeded with both.
- **SC-006**: A corpus of **10,000** transactions spread across at least **8** accounts opens and scrolls end to end without failing, and shows its first screenful within **1 second** of the person opening the list.
- **SC-007**: Scrolling the whole combined history end to end never leaves the person waiting on a blank or placeholder row for more than **100 ms**, and never drops below the device's full frame rate.
- **SC-008**: Time to first screenful varies by no more than **20%** between a corpus of **200** transactions on 2 accounts and a corpus of **10,000** transactions on 8 accounts, on the same device — and applying or clearing the account filter shows its first screenful within **300 ms** on the 10,000-transaction corpus.
- **SC-009**: The list's order — including the order of same-date transactions belonging to different accounts — is **identical** across at least 10 consecutive launches with unchanged data, and importing a further account leaves the relative order of every pre-existing transaction unchanged in **100%** of tested cases.
- **SC-010**: Newly imported transactions are visible in an already-open list within **1 second** of the import completing, with **zero** relaunches required, and **zero** cases of the person being moved out of an applied filter or thrown to the top of a scrolled list.
- **SC-011**: In a corpus containing at least two currencies, **100%** of rows state their own currency, **zero** amounts are converted or normalised, and **zero** figures anywhere in the feature are derived from amounts of more than one currency — verified automatically.
- **SC-012**: The manual accessibility gate for this slice is run by a person before release and reports **zero** findings: the system accessibility audit against the rendered list in Light Mode, Dark Mode, at the largest accessibility text size, with Increase Contrast and with Reduce Transparency, in both orientations, plus VoiceOver judged for meaningfulness. **This gate is manual and release-blocking. It is not enforced by continuous integration and cannot be**, because the automated auditor runs against a launched app and cannot reach any screen behind an import. The run MUST be recorded with its build and date.
- **SC-013**: **100%** of the behaviours listed in FR-074 have automated coverage in the unit test target — every user-visible string, every accessibility announcement, the live-row filtering, the ordering and its tie-break, the filter's population, and singular/plural wording — so that **zero** of them depend on the manual gate of SC-012.
- **SC-014**: **100%** of rows are announced by VoiceOver as a single statement carrying date, description, amount, currency, direction in words and account; and direction, transfer status, category state and the filtered state are each identifiable with colour perception removed entirely.
- **SC-015**: **Zero** network requests occur while the transaction list is in use, verified automatically, including across the new cross-account read.
- **SC-016**: **Zero** user-visible strings in this feature contain an identifier, an internal code, a layer name or engine-internal text — verified by review of every string.
- **SC-017**: **Zero** real statements, real merchant records or real account identifiers appear in any fixture or test added by this feature.

## Clarifications

### Session 2026-08-14

Two decisions materially changed this slice's scope and its release gate. Both were put to the repo owner and both are now answered; the answers are folded into the requirements above.

- **Q1 — Is the list per-account only, or is there also a combined list across all accounts?**
  **Answered: the combined list is primary.** Every account's transactions appear in one list, each row naming the account it belongs to, and looking at a single account is a **filter** on that list rather than a second screen. The reasoning recorded with the answer: it answers the question people actually ask — "what did I spend this month?" — and the front door's per-account count leading into a filtered view of one list is a smaller conceptual surface than two separate screens with two orderings and two sets of empty states.
  Consequences accepted rather than papered over, each now a requirement: a **cross-account read is new engine surface** that does not exist today and crosses the FFI (FR-043–FR-046); **ordering must span accounts** with a defined, total, stable same-date tie-break (FR-028–FR-032); **multi-currency becomes load-bearing** and is answered outright rather than deferred (FR-023–FR-027); the **filter has defined behaviour** including what happens on relaunch (FR-036–FR-042); and the **performance criteria are now stated over the whole corpus**, not one account (SC-006, SC-008). This is a larger slice than the per-account form, and the spec says so.

- **Q2 — Must this screen be covered by the automated accessibility audit, given the audit cannot currently reach any screen behind an import?**
  **Answered: manual for this slice.** SC-012 is an explicit **manual, release-blocking** gate, in the same category as slice 016's T123, worded so it cannot be mistaken for something continuous integration enforces. The reason is stated plainly in the spec rather than implied: the system auditor runs against a launched app and cannot reach any screen behind an import, which is every screen this slice adds — a limitation already recorded in `.scratch/HANDOFF.md` under 016's T115/T123, not an oversight of this slice.
  Everything that *is* provable without a rendered screen is automated instead (FR-074, SC-013) — the copy, the labels, the announcements, the ordering, the live-row filtering, the filter's population — in the unit target, the way the import screens are already covered. That keeps the manual gate as small as it honestly can be.
  A **DEBUG-only test-seeding hook** is recorded as a planned **future slice, scheduled before the categorize slice** (see Out of Scope). It is what would make SC-012 automated for this screen and for every P3 screen after it. It is not designed here.

### Decisions taken without asking

- **Same-date rows of different accounts are ordered by account, then by printed statement order within each account.** A date has no time of day attached, so nothing in the data can interleave two accounts' rows meaningfully. Grouping a date's rows by account gives a total, repeatable order, keeps each account's rows contiguous and in the order its paper prints them — which is what makes the screen reconcilable — and never depends on when anything was imported. The account ordering is the front door's own, so a person sees one account ordering in the app rather than two.
- **The filter does not survive relaunch; a launch always shows every account.** Persisting it would mean a person can open the app, see a subset of their spending, and not notice that the number is small because they filtered it three days ago. The failure mode of not persisting is one extra tap; the failure mode of persisting is a wrong impression of one's own finances. FR-041.
- **Every amount always carries its currency, even in a single-currency corpus.** Showing the currency only when more than one is present makes the presence of a currency marker itself carry meaning, and makes the row's shape change under the person as data arrives. It is also the class of conditional rule that is quietly wrong for months.
- **Date group headings carry no amount.** Any per-day figure would be a sum, and a day can hold more than one currency, so a heading total would be either meaningless or conditional. Removing the possibility is cheaper than getting the condition right. FR-026.
- **Duplicates are reported in the import summary, not in the list.** The import summary already tells the person how many duplicates were skipped (slice 016, FR-033). Repeating that in the transaction list would require rendering, or at least counting, the superseded rows the live-row rule exists to exclude — re-opening the exact defect that shipped in 016 in a new place, on the screen least able to survive it. The list answers "what do I have"; the summary answers "what happened when I imported". Provenance is preserved in the store either way.
- **Transfers are marked, not hidden and not filtered — and detection is not wired here.** A transfer is a real movement on the account's statement, and a list that silently omits it will not reconcile against the paper. In the combined list both sides of a transfer appear, which is correct: each is a real line on its own statement. This slice carries no totals, so marking is sufficient; excluding transfers from *spending* is the dashboard slice's decision to make. **Separately**, the app never calls the engine's transfer detection (`research.md` R18), so the flag is always unset in a real install. Answered by the repo owner: **build the marking here, defer the wiring to the categorize slice** — detection is an O(n²) pass over the whole corpus and this slice's read path is already constrained by SC-006. FR-018 records the limitation so the marking is never mistaken for a working feature.
- **Categories are shown, never changed.** Displaying an already-assigned category is free and makes the next slice's work visible; assigning or correcting one is the categorize slice.
- **The list shows the full history, not one statement period.** A person scrolls to the past; they do not pick a period first. Filtering by period is search's job, in a later slice. The account filter is not a general filtering feature and does not open that door.
- **Within an account, ordering ties break on printed statement order rather than on when the row was written.** The person's reference document is the statement, and matching its order is what makes the screen auditable against the paper in their hand.

## Assumptions

- The front door's account rows remain the primary way into a single account's transactions; the combined list is what they lead into, filtered.
- Descriptions are shown exactly as the statement printed them. They are often cryptic, and cleaning them up is a separate product problem, not a display bug to be papered over here.
- Every field this slice renders is already written and already correct. This slice reads; it never writes, never corrects and never re-derives.
- The engine's existing transfer detection and categorization results are taken as given. This slice does not re-run, re-check or second-guess them.
- Grouping is by calendar date rather than by month, on the assumption that a date heading is the unit a person matches against a printed statement.
- The date a transaction carries has no time of day, so within one account the printed order is the only meaningful tiebreak within a day, and across accounts a fixed account ordering is required to complete it.
- Amounts are formatted for the person's locale, but the underlying value is an exact decimal at every step, including through formatting, and the currency shown is always the transaction's own.
- The cross-account read is **new engine surface**. It is assumed to land as engine work with its own tests, separate from the interface work, because it crosses the FFI. Its shape is `/speckit.plan`'s decision.
- Most people will hold a single currency; the mixed-currency rules exist so that the minority who do not are never shown a wrong number, not because mixed currencies are expected to be common.
- Test fixtures are synthetic statements built for this slice, including several accounts, at least one pair of accounts in different currencies, at least one same-date collision across accounts, and a corpus large enough to exercise the responsiveness criteria.

## Out of Scope *(deferred to later slices)*

Per the P3 order — onboarding → import → **transaction list** → DEBUG-only test-seeding hook → categorize → dashboard → budgets → tags → search → export — everything below is a later slice and MUST NOT be built here:

- **A DEBUG-only test-seeding hook in the app.** This is a **planned future slice, scheduled before the categorize slice**. It is what would let the automated accessibility auditor reach screens that today sit behind a real file being picked, and it is what would turn SC-012 from a manual gate into an automated one — for this screen and for every P3 screen after it. It is deliberately **not designed here**: this slice neither adds it nor assumes its shape.
- **Categorizing or re-categorizing a transaction.** The list *displays* the category the engine assigned; changing it, correcting it, bulk-assigning it, or creating categories is the **categorize** slice.
- **Editing a transaction in any way** — its description, amount, date, direction or account. This slice is read-only.
- **Deleting, hiding, restoring or splitting a transaction.** The store supports deletion; no interface for it exists here.
- **Any total, sum, average, balance or chart** — spend for the month, category breakdowns, running balances. That is the **dashboard** slice, and it is where transfers must be excluded from spending, and where the cross-currency rule in FR-025 will have to be honoured rather than discovered.
- **Budgets** and any budget-relative treatment of a transaction.
- **Tags** and tagging.
- **Search, date-range selection, sorting by anything other than date, and filtering by anything other than a single account.** That is the **search** slice. The account filter delivered here is exactly one filter and does not generalise.
- **Filtering by more than one account at a time**, or by account type.
- **Export** in any format.
- **A transaction detail screen.** This slice delivers the list; whether a row opens onto anything is a question the categorize slice answers, because a detail view without an action is a dead end.
- **Statement-level browsing** — viewing which statements an account has, or the transactions of one statement in isolation.
- **Surfacing superseded or deleted rows** as provenance, duplicate history, or an audit trail.
- **Multi-currency conversion, normalisation, or a home currency.** Each amount is shown in its own currency; nothing is converted, and no cross-currency figure exists.
- **Any change to import, parsing, extraction or categorization.** The one engine change this slice does carry is the cross-account read (FR-043–FR-046) and nothing else. If this slice appears to need another, that is a finding to record, not a change to make here.

## Dependencies

- **Slice 016 (`016-statement-import-vertical`)** — the front door, the account list this slice makes actionable, the import that produces the transactions, the live-row rule this slice inherits and must apply, and the recorded limitation that the automated accessibility audit cannot reach screens behind an import (T115/T123).
- **Slice 017 (`017-column-major-pdf`)** — geometry-first extraction, without which real statements yield too few transactions to be worth listing.
- **A new cross-account read in the engine**, which does not exist today: the store reads one account at a time. This slice requires an ordered view across every account that can be consumed a portion at a time (FR-043–FR-046). It is **new engine surface that crosses the FFI**, and therefore lands separately from the interface work and carries its own engine-side tests. Its shape is `/speckit.plan`'s decision.
- **The existing encrypted on-device store**, which already holds every field this slice renders — the transactions, their currencies, their statements, and the category set. No new stored data and no writes are required.
- **The engine's existing transfer detection and categorization**, whose results this slice displays without re-running.
- **The app's existing accent colour and accessibility rules**, which this screen inherits rather than re-litigates.
- **The existing automated accessibility audit**, which covers the front door only and cannot reach this screen. This slice therefore adds a manual, release-blocking gate (FR-075, SC-012) and automates everything provable without a rendered screen (FR-074, SC-013).
- **The planned DEBUG-only test-seeding hook slice** (before categorize), which is what would later make SC-012 automated. This slice does not depend on it and must not wait for it.
