# Feature Specification: Statement Import — the First End-to-End Vertical (Pick a PDF → Identify the Issuer → Parse → Persist → Import Summary)

**Feature Branch**: `016-statement-import-vertical`  
**Created**: 2026-08-12  
**Status**: Draft  
**Milestone**: P3 (Core SwiftUI app) — the **first** slice of P3, and the first slice in the project that joins every already-shipped layer into one user-visible flow: SwiftUI → native PDF text extraction → the on-device engine's readers → the SQLCipher-encrypted store → back to SwiftUI.  
**Input**: User description: "The import vertical — the first end-to-end user-facing flow. A user picks a bank/card statement PDF from Files, the app extracts its text natively, the Rust core identifies the issuer and parses it, the transactions are persisted to the encrypted on-device store, and the user sees an import summary. This is the first slice of P3 (Core SwiftUI app) and the first slice that proves the entire stack end-to-end."

> **Note on priority labels**: This feature sits in product milestone **P3** (Core SwiftUI app). Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P3" and "User Story P3" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

Everything the engine needs already exists and is proven: **ten statement readers** (six credit-card issuers, four bank ledgers), the **balance-chain** and **reconciliation** integrity checks, **cross-source de-duplication**, **coverage**, **transfer detection**, the **deterministic categorization stack** with 23 builtin categories, and the **encrypted on-device store** (schema v5) with its platform-side key ceremony and file-protection wiring. What does **not** exist is a way for a person to actually *use* any of it: the app's only screen today prints the engine version.

This slice delivers **the import vertical** — the shortest path from "I have a statement PDF on my phone" to "my transactions are in Kaname, categorized, and I can see what happened." A person opens Kaname, taps **Import**, picks a statement PDF from Files (or iCloud Drive, or any Files provider), and the app does the rest: it reads the document's text **natively on device**, hands that text to the engine, which **identifies which bank or card issuer produced it** and parses it into dated transactions, resolves the statement to an existing account or creates one, writes the rows into the **encrypted store**, runs **categorization**, and finally shows an **import summary**: how many transactions landed, which account, which statement period, and any warnings worth a human's attention.

Two properties make this slice more than plumbing:

**The app is bank-agnostic.** Today the engine exposes ten *separate* reader pairs (a "does this document look like mine?" claim plus a parse) and **no dispatcher**. This slice adds the dispatcher **inside the engine**, so the app asks one question ("who issued this?") and issues one instruction ("parse it as that issuer"). The app never names a bank, never enumerates readers, and never branches per-issuer. The direct consequence — and a hard requirement of this slice — is that **adding an eleventh bank later requires zero changes to the app**.

**Nothing leaves the device, and nothing is fabricated.** The whole path — file access, text extraction, issuer detection, parsing, integrity checks, storage, categorization — is **100% on-device with zero network I/O** (Constitution Principle I, non-negotiable). Money is carried as an exact decimal end to end and never as a floating-point number. Every failure the person can hit — a scanned image-only PDF, a password-protected PDF, a corrupt file, an unrecognized issuer, an ambiguous one — is surfaced in **plain, non-technical language**, never as a raw engine error string.

### User Story 1 - Import a statement and see what landed (Priority: P1)

A person taps **Import**, picks a statement PDF for a supported bank or card from Files, and — without any further input — ends up looking at an **import summary**: the account the statement belongs to, the statement period, and how many transactions were added. Behind that summary the transactions are already in the encrypted store and already categorized.

**Why this priority**: This is the entire point of the slice and the first moment Kaname delivers user value. Every other story qualifies, protects, or explains this one. Shipped alone, it is a viable MVP: a person can get their real financial history into the app.

**Independent Test**: With a fresh install and no accounts, import a single synthetic statement PDF for a supported issuer and confirm the summary reports the correct account, period and transaction count, and that the same transactions are readable from the encrypted store after relaunching the app.

**Acceptance Scenarios**:

1. **Given** a fresh install with no accounts and no transactions, **When** the person picks a supported credit-card statement PDF from Files, **Then** the app shows an import summary naming the issuer and the last-4 of the card, the statement period, and the number of transactions imported — and no error is shown.
2. **Given** the import in (1) has completed, **When** the person force-quits and relaunches the app, **Then** the imported account and its transactions are still present (they were persisted to the encrypted store, not held in memory).
3. **Given** a supported **bank-account** (savings/current) statement PDF, **When** it is imported, **Then** the summary reports transactions for a bank account (not a card), with the statement period, and the transactions carry the correct debit/credit direction.
4. **Given** an import that persisted transactions, **When** the summary is shown, **Then** the summary reports how many of the imported transactions were automatically assigned a category and how many were left uncategorized.
5. **Given** any completed import, **When** the app is inspected for outbound network activity across the whole flow (pick → extract → detect → parse → persist → categorize → summary), **Then** **zero** network requests were made.
6. **Given** any imported transaction, **When** its amount is displayed or stored, **Then** the amount is exact to the last paisa — no rounding drift, no floating-point representation.

---

### User Story 2 - The app never needs to know which bank it is (Priority: P2)

The person is never asked "which bank is this?" for a supported issuer. They pick a file; the engine works out who produced it. When the engine **cannot** work it out, or when the document is claimed by **more than one** issuer, the person gets a clear, honest outcome rather than a wrong parse or a crash.

**Why this priority**: Bank-agnosticism is the architectural payoff of this slice — it is what makes every future bank a zero-app-change addition. It also carries the two failure modes most likely to produce *silently wrong data* (an unrecognized document parsed by the wrong reader, or an ambiguous one parsed arbitrarily), which is worse than an honest refusal.

**Independent Test**: Import three documents in turn — one supported issuer, one PDF with extractable text that no reader claims, and one crafted document claimed by more than one reader — and confirm the app identifies, declines, and disambiguates respectively, all without the app itself containing any bank-specific branching.

**Acceptance Scenarios**:

1. **Given** a statement PDF for any one of the ten supported issuers, **When** it is imported, **Then** the engine identifies the issuer and the app parses it correctly **without the app naming, listing, or branching on any bank**.
2. **Given** a hypothetical eleventh issuer added to the engine later, **When** a statement for it is imported, **Then** it is detected and parsed with **no change to the app** (verified by the app containing no per-issuer logic).
3. **Given** a readable PDF with extractable text that **no** reader claims (e.g. a utility bill, or an unsupported bank), **When** it is imported, **Then** the app tells the person in plain language that it does not yet recognize this statement's format, imports **nothing**, and leaves the store unchanged.
4. **Given** a document that **more than one** reader claims, **When** it is imported, **Then** the engine resolves the ambiguity with a deterministic tie-break without asking the person, **never** persists a partially-parsed result from a losing candidate, and the summary shows which issuer won so a wrong pick is visible.
5. **Given** an unrecognized or ambiguous document, **When** the outcome is shown, **Then** the message contains **no** engine internals — no reader names, no error codes, no Rust error text.

---

### User Story 3 - A file that cannot be read fails honestly (Priority: P3)

Not every file a person picks is a parsable statement. A **scanned / image-only** PDF has no text to extract. A **password-protected** PDF cannot be opened without its password. A **corrupt file, or a file that is not a PDF at all**, cannot be opened. In every case the person gets a specific, plain-language explanation and a way forward — and nothing is written to the store.

**Why this priority**: Scanned statements and password-protected statements are both common in Indian retail banking, so these are everyday paths, not exotic ones. An unexplained failure here is the fastest way to lose a person's trust in an app that has just asked for their financial documents.

**Independent Test**: Import each of the four unusable inputs in turn (image-only PDF, password-protected PDF, corrupt PDF, a non-PDF file renamed to `.pdf`) and confirm each produces its own distinct plain-language message and leaves the store byte-identical.

**Acceptance Scenarios**:

1. **Given** a PDF whose pages are scanned images with **no extractable text**, **When** it is imported, **Then** the app explains that this looks like a scanned statement it cannot read, distinguishes this from "unsupported bank", and imports nothing.
2. **Given** a **password-protected** PDF, **When** it is imported, **Then** the app recognizes that the document is locked and prompts for its password rather than reporting a generic failure.
3. **Given** the password prompt in (2), **When** the person enters the correct password, **Then** the import proceeds normally; **When** they enter an incorrect password, **Then** they are told the password did not work and may retry or cancel.
4. **Given** a password supplied in (3), **When** the import finishes or is cancelled, **Then** the password is **not** persisted anywhere — not in the store, not in the Keychain, not in logs.
5. **Given** a corrupt PDF, or a file that is not a PDF despite its name, **When** it is imported, **Then** the app says the file could not be opened as a PDF and imports nothing.
6. **Given** any failure in this story, **When** it occurs, **Then** the encrypted store is **unchanged** — no account is created, no statement record is written, no transaction is written.
7. **Given** a file the person selected from another app's storage (iCloud Drive, a third-party Files provider), **When** the import runs, **Then** the app obtains and releases the temporary permission it needs to read that file, and a permission failure is reported as "could not read the file you picked" rather than surfacing as a crash or a silent no-op.

---

### User Story 4 - Importing the same statement twice does not corrupt history (Priority: P4)

A parsed statement identifies itself by **issuer** and by the **last-4** of the account or card. The app uses that to attach the import to the right existing account — or to create the account the first time. If the person imports **the same statement file again** (a month later, from a different folder, after a reinstall), the app must not silently double every transaction in that period.

**Why this priority**: Double-counted spend is the single most damaging data error a personal-finance app can make, and re-importing is a completely ordinary user mistake. It ranks below the failure paths only because it requires a successful import to exist first.

**Independent Test**: Import the same synthetic statement file twice in a row and confirm the account is not duplicated, the transaction totals are not doubled, and the second import's summary tells the person plainly what happened.

**Acceptance Scenarios**:

1. **Given** no existing accounts, **When** a statement for issuer X ending in 1234 is imported, **Then** exactly one account is created for issuer X / 1234, and the summary names it.
2. **Given** an account already exists for issuer X ending in 1234, **When** a later statement for the same issuer and last-4 is imported, **Then** the transactions attach to the **existing** account and **no** second account is created.
3. **Given** a statement has already been imported in full, **When** the **same statement** is imported again, **Then** the import proceeds, the existing cross-source de-duplication links the repeats so the person's transaction history is **not** doubled, and the summary reports how many duplicates were skipped.
4. **Given** a parsed statement whose issuer is identified but whose **last-4 could not be recovered** from the document, **When** exactly one account already exists for that issuer, **Then** the app attaches the statement to it; **When** there is no such account or more than one, **Then** the app asks the person to pick or name the account rather than guessing silently.
5. **Given** an import that creates a new account, **When** the summary is shown, **Then** the newly created account is identified as new, so the person is never surprised by an account they did not expect.

---

### User Story 5 - The app tells the person whether the numbers add up (Priority: P5)

Every parse is checked for internal consistency: a bank-account statement's running-balance chain is walked, and a credit-card statement's rows are reconciled against its own printed totals. The person sees the **outcome** of those checks in plain language — not the diagnostics.

**Why this priority**: These checks already exist and are proven; this story is about *surfacing* them. It is what lets a person trust an import instead of hoping. It ranks here because an import that persists correct data is still valuable without the reassurance banner, but far less trustworthy.

**Independent Test**: Import a statement whose totals reconcile and one whose totals deliberately do not, and confirm the two summaries differ in a way a non-technical person can act on.

**Acceptance Scenarios**:

1. **Given** a statement whose rows agree with its own printed totals (or whose balance chain walks cleanly), **When** the import finishes, **Then** the summary shows a positive, plainly-worded confirmation that the imported figures match the statement.
2. **Given** a statement whose rows do **not** agree with its printed totals or whose balance chain has suspect rows, **When** the import finishes, **Then** the summary shows a **warning** in plain language ("some figures on this statement didn't add up — you may want to check these transactions"), the transactions are still imported, and the statement is marked as needing review.
3. **Given** a statement that prints **no** totals to reconcile against, **When** the import finishes, **Then** the summary neither claims the statement reconciled nor warns that it failed — the absence of a check is never presented as either a pass or a fail.
4. **Given** a parse that produced rows it recognized but could not fully read, **When** the import finishes, **Then** the summary reports how many rows could not be read, so the person knows the import was incomplete rather than believing it was total.
5. **Given** any integrity warning, **When** it is displayed, **Then** it uses everyday language and never surfaces a status code, a reader name, or an internal field name.

---

### User Story 6 - A long import stays responsive and can be abandoned (Priority: P6)

A large statement takes a noticeable moment to extract and parse. Throughout, the app stays responsive, shows that work is happening, and lets the person cancel. Cancelling leaves no half-imported mess.

**Why this priority**: This is a correctness requirement disguised as a polish requirement — an unresponsive app during the single most important flow reads as a broken app, and a cancel that leaves half a statement behind corrupts the data the previous stories worked to protect. It ranks below them because a small statement imports fast enough to mask it.

**Independent Test**: Import a large multi-page statement and confirm the UI remains interactive and shows progress throughout; then cancel mid-parse and confirm no partial data was persisted.

**Acceptance Scenarios**:

1. **Given** a large statement, **When** extraction and parsing run, **Then** the interface remains responsive (scrolling and cancelling both work) — the work never blocks the main thread.
2. **Given** an import in progress, **When** the person looks at the screen, **Then** they see that work is underway and roughly what stage it is at, rather than a frozen or blank screen.
3. **Given** an import in progress, **When** the person cancels, **Then** the import stops and the encrypted store is left exactly as it was before the import began — no account, statement record, or transaction from the cancelled run remains.
4. **Given** an import in progress, **When** the person backgrounds the app and returns, **Then** the app is in a coherent state — either the import completed, or it reports that it did not — and never shows a permanently stuck progress indicator.

---

### User Story 7 - A first-run app explains itself instead of showing nothing (Priority: P7)

Before any import exists, the app's main screen is not blank and not a spinner. It says what Kaname does, states the privacy promise, and offers exactly one obvious action: import a statement.

**Why this priority**: It is the first thing every new person sees, and it is cheap. It ranks last because it delivers no data value on its own — but without it, the P1 flow has no entry point.

**Independent Test**: Launch a fresh install and confirm the empty state is present, legible at the largest Dynamic Type size, fully navigable by VoiceOver, and leads to the document picker in one tap.

**Acceptance Scenarios**:

1. **Given** a fresh install with no imported data, **When** the app opens, **Then** the person sees an empty state explaining what Kaname does and a single primary action to import a statement.
2. **Given** the empty state, **When** the person activates the primary action, **Then** the system document picker opens.
3. **Given** at least one successful import, **When** the app opens, **Then** the empty state is no longer the primary content — the person sees evidence that their data is there (at minimum, the imported accounts and the ability to import again).
4. **Given** any screen in this flow, **When** it is viewed at the largest accessibility text size, in Dark Mode, or with Reduce Transparency enabled, **Then** all text remains legible and meets contrast requirements, and nothing is clipped or unreachable.
5. **Given** any screen in this flow, **When** it is navigated with VoiceOver, **Then** every control and every summary figure is announced meaningfully (including amounts, counts and warnings), with no unlabelled elements.

---

### Edge Cases

- **A statement with zero transactions** (a card with no spend that cycle) — the parse succeeds and finds nothing. The summary must say "0 transactions" as a *successful* import, not report a failure.
- **A statement whose period cannot be recovered** from the document — the summary must omit the period rather than invent or approximate one.
- **A statement spanning a period already partly covered** by an earlier import (overlapping date ranges from two different files) — overlapping rows must not silently double-count.
- **A person picks a file, then the file becomes unavailable** mid-import (an iCloud file evicted, the provider revoking access) — reported as a read failure, store untouched.
- **A very large statement** (hundreds of pages / thousands of rows) — must complete or fail cleanly, never exhaust memory or hang indefinitely.
- **A PDF that opens and has text, but whose text is meaningless** (garbled font encoding producing character soup) — no reader will claim it; this must land in the "not recognized" path, not a crash.
- **Two imports started in quick succession** (the person taps Import twice) — must not run two conflicting writes into the store.
- **The encrypted store cannot be opened** (key ceremony failure, damaged database) — reported as a plain-language "Kaname couldn't open your data" state, never as a raw storage error, and never by silently falling back to unencrypted storage.
- **Storage is full** while writing the imported rows — reported plainly; the partial write must not leave the store in a half-imported state.
- **A password-protected PDF whose password is empty or is the same as an owner password** — must be treated as openable rather than prompting pointlessly.

## Requirements *(mandatory)*

### Functional Requirements

#### Picking a file

- **FR-001**: The app MUST let the person choose a statement PDF from the system document picker, including files provided by iCloud Drive and third-party Files providers.
- **FR-002**: The app MUST obtain the temporary read permission required for a file outside its own container before reading it, and MUST release that permission when reading is done (including on the failure and cancellation paths).
- **FR-003**: The app MUST accept exactly **one** file per import in this slice; selecting multiple files at once is out of scope (see Out of Scope).
- **FR-004**: The app MUST never copy, upload, or transmit the picked file anywhere off the device.

#### Reading the document

- **FR-005**: The app MUST extract the document's text **natively on the device**, producing the text lines, the full document text, and the word positions of the first data row that the engine's reader seam requires. The engine MUST NOT be given the PDF file itself.
- **FR-006**: The app MUST detect a document with **no extractable text** (an image-only/scanned PDF) and report it as such, distinctly from an unrecognized issuer.
- **FR-007**: The app MUST detect a **password-protected** document, prompt for its password, allow retry after an incorrect password, and allow cancellation.
- **FR-008**: The app MUST NOT persist a document password anywhere — not in the stored data, not in the device's secure credential storage, not in logs or diagnostics. It exists only for as long as it takes to open the document.
- **FR-009**: The app MUST report a **corrupt file or a non-PDF file** as an unopenable document, without crashing.

#### Identifying the issuer

- **FR-010**: The engine MUST expose a single **issuer-detection** capability that, given the document's text, reports which supported issuer produced it — or reports that none did.
- **FR-011**: The engine MUST expose a single **parse** capability that, given an identified issuer and the extracted text, returns the parsed statement — so the app selects a reader exactly once, by value, never by name.
- **FR-012**: The app MUST NOT contain any per-issuer **logic**: no list of banks, no per-bank branch, no per-bank string literal. Adding a new issuer to the engine MUST require **zero** changes to the app. The issuer is **data** the engine returns, not a compile-time app concern — the app displays whatever issuer name it is handed (see FR-033) without knowing which issuers exist.
- **FR-013**: When **no** issuer claims the document, the app MUST import nothing and MUST tell the person that this statement format is not recognized yet.
- **FR-014**: When **more than one** issuer claims the document, the **engine** MUST resolve it with a deterministic tie-break (the app never asks the person to choose), and MUST NOT persist a result from a losing candidate. The import summary MUST always show the issuer that won together with the account last-4, so a wrong pick is visible to the person rather than silent.
- **FR-015**: Issuer detection MUST be deterministic: the same document text MUST always yield the same issuer.

#### Parsing and integrity

- **FR-016**: The app MUST run the engine's existing integrity check appropriate to the statement kind — the running-balance chain for bank-account statements, reconciliation against printed totals for credit-card statements — on every successful parse.
- **FR-017**: The app MUST present the integrity outcome in **plain, non-technical language**: a confirmation when the figures agree, a warning when they do not, and **nothing** when the statement offers nothing to check against.
- **FR-018**: The app MUST report the count of rows the engine recognized but could not fully read, so an incomplete import is never presented as a complete one.
- **FR-019**: A statement that fails its integrity check MUST still import its transactions, and MUST be recorded as **needing review**.
- **FR-020**: A parse that yields **zero** transactions MUST be reported as a successful import of zero transactions, not as an error.

#### Resolving the account

- **FR-021**: The app MUST attach an imported statement to an existing account when one already exists for the same issuer and account/card last-4.
- **FR-022**: The app MUST create an account when no matching one exists, and MUST identify it as newly created in the summary.
- **FR-023**: The app MUST record whether the account is a credit card or a bank account, as reported by the parse.
- **FR-024**: When the parse recovers **no** last-4, the app MUST attach the statement to the **single existing account for that issuer** when exactly one exists. When there is none, or more than one, the app MUST ask the person to pick or name the account — never guessing silently.
- **FR-025**: Re-importing a statement that was already imported MUST NOT double the person's transaction history. The import MUST proceed and the existing cross-source de-duplication MUST link the repeats; the summary MUST report the number of duplicates skipped. The app MUST NOT refuse the import and MUST NOT delete or replace previously imported transactions.

#### Persisting and categorizing

- **FR-026**: The app MUST persist imported transactions to the **encrypted on-device store**, together with a record of the import (its account, issuer, statement period, and whether it needs review).
- **FR-027**: The app MUST supply every timestamp the store requires; the engine MUST NOT read a wall clock.
- **FR-028**: Money MUST be carried and stored as an **exact decimal** at every step — from parse, across the engine boundary, into the store, and back into the summary. No step may represent an amount as a floating-point number.
- **FR-029**: Transaction direction (money in vs. money out) MUST be carried explicitly and MUST NOT be inferred from the sign of an amount.
- **FR-030**: The app MUST run the existing deterministic categorization over the newly imported transactions, and MUST report how many were categorized and how many were left uncategorized.
- **FR-031**: An import that fails part-way, or is cancelled, MUST leave the store exactly as it was before the import began — no orphan account, statement record, or transaction.
- **FR-032**: The app MUST prevent two imports from running at once.

#### The summary

- **FR-033**: On completion the app MUST show an import summary containing: the account (issuer + last-4 where known, and whether it is new), the statement period (omitted when not recoverable), the number of transactions imported, the number of duplicates skipped, the categorized/uncategorized split, and any warnings. The issuer MUST always be shown, so an ambiguous-document tie-break (FR-014) is visible rather than silent.
- **FR-034**: The summary MUST make its warnings actionable in plain language and MUST NOT display any engine internals — no error codes, no internal reader/function identifiers, no raw error text from the core. The **issuer name** is user-facing data, not an internal, and MUST be shown (FR-033).
- **FR-035**: The person MUST be able to dismiss the summary and start another import from it.

#### Progress, responsiveness and cancellation

- **FR-036**: Text extraction, issuer detection, parsing, persistence and categorization MUST run **off the main thread**; the interface MUST remain responsive throughout.
- **FR-037**: The app MUST show that an import is in progress and roughly what stage it has reached.
- **FR-038**: The person MUST be able to **cancel** an in-progress import, and cancellation MUST take effect promptly and leave no partial data (per FR-031).

#### Empty state and first run

- **FR-039**: Before any import exists, the app MUST show an empty state that explains what Kaname does, states that data stays on the device, and offers a single primary action to import a statement.
- **FR-040**: After at least one successful import, the app MUST show the imported account(s) rather than the empty state, and MUST keep the import action reachable.

#### Privacy, accessibility and platform baseline

- **FR-041**: The entire import path MUST perform **zero** network I/O. No analytics, no crash reporting, no telemetry of any kind may be added on this path.
- **FR-042**: No statement content, transaction, account identifier, amount, or password may be written to logs or diagnostics.
- **FR-043**: All test fixtures for this feature MUST be **synthetic**; no real statement or real account data may enter the repository.
- **FR-044**: Every screen in this flow MUST support Dynamic Type (through the largest accessibility sizes), Dark Mode, and full VoiceOver navigation with meaningful labels for controls, amounts, counts and warnings.
- **FR-045**: Amounts displayed anywhere in this flow MUST use tabular (monospaced) digits so figures do not jitter.
- **FR-046**: Contrast MUST hold with **Reduce Transparency** and **Increase Contrast** enabled; no material treatment may be the only thing carrying meaning.
- **FR-047**: Any translucent (Liquid Glass) treatment MUST be applied only to floating controls and summary surfaces — never to dense rows of transactions or numbers — and a debit/credit colour signal MUST never sit on a tinted translucent surface.

### Key Entities

- **Picked Document**: The file the person chose. Attributes: a file location the app has temporary permission to read, and (transiently) a password when the document is locked. Never copied off-device; never retained after the import.
- **Extracted Text**: The on-device, native output of reading the document — the text lines, the full document text, and the first data row's word positions. The engine's only view of the document; the engine never sees the file.
- **Issuer**: Which bank or card issuer produced the document, as identified by the engine. A closed set owned entirely by the engine; the app treats it as an opaque value with a display name.
- **Parsed Statement**: The engine's structured reading of the document — the transactions, the rows it could not read, the statement period, the account/card last-4, the printed balances and totals, and a confidence figure.
- **Integrity Outcome**: The verdict of the statement's own consistency check — agrees / does not agree / nothing to check — plus the count of suspect rows. Rendered to the person as plain language, never as raw diagnostics.
- **Account**: The stored account an import attaches to. Attributes: issuer, last-4 where known, credit-card vs. bank account, currency, display name. Created on first import for that issuer + last-4.
- **Import Record**: The stored record of one import run, linking the imported transactions to their account and statement period, and carrying the needs-review flag.
- **Imported Transaction**: A dated row with an exact decimal amount, an explicit direction, a raw description, a currency, and an optional assigned category. Linked to its account and its import record.
- **Import Summary**: What the person sees at the end — account (and whether it is new), period, transaction count, categorized/uncategorized split, and warnings.
- **Import Failure**: A terminal, plain-language outcome with no data written: not recognized, ambiguous, no extractable text, locked, unopenable, unreadable, cancelled, or storage unavailable.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A person with a supported statement PDF can go from opening the app to reading an import summary in **under 60 seconds** and **at most 4 taps** (import → pick file → confirm → done), with no typing for an unprotected statement.
- **SC-002**: **100%** of statements for the ten currently supported issuers are correctly attributed to their issuer without the person naming the bank.
- **SC-003**: **100%** of the transactions a supported statement contains are imported with amounts exact to the last paisa, verified against synthetic golden fixtures.
- **SC-004**: **Zero** network requests occur across the entire import path, verified automatically.
- **SC-005**: Importing the **same statement twice** never increases the person's transaction totals for that period — verified by comparing period totals after one import and after two.
- **SC-006**: **Every** failure path (not recognized, ambiguous, no text, locked, corrupt/not a PDF, unreadable, cancelled, storage unavailable) leaves the stored data **byte-identical** to its pre-import state.
- **SC-007**: **Zero** user-visible messages in this flow contain an error code, a reader name, or engine-internal text — verified by review of every message string.
- **SC-008**: A statement of at least 200 transactions imports without the interface becoming unresponsive at any point, and can be cancelled within **2 seconds** of the person asking.
- **SC-009**: Every screen and control in this flow is reachable and correctly announced under VoiceOver, and remains legible with **no clipping** at the largest accessibility text size, in Dark Mode, and with Reduce Transparency enabled.
- **SC-010**: A new issuer can be added to the engine and imported successfully with **zero** lines changed in the app.
- **SC-011**: **Zero** real statements or real account identifiers appear in any fixture or test added by this feature.

## Clarifications

### Session 2026-08-12 (settled with the product owner)

- **Ambiguous document (FR-014):** the **engine** tie-breaks deterministically; the app never asks the person to choose. The import summary always shows the winning issuer + last-4 so a wrong pick is visible and correctable.
- **"Bank-agnostic" means no per-issuer *code*, not a hidden issuer (FR-012).** The issuer is data the engine returns and the app renders it verbatim (e.g. "HDFC Credit Card •••• 4321"). The app must simply never *branch* on it or carry a hardcoded bank list.
- **Duplicate re-import (FR-025):** the import proceeds and the **existing cross-source de-duplication** links the repeats; the summary reports "N duplicates skipped". Refusing the import or replacing prior transactions is rejected — it reuses shipped, parity-locked logic and never loses data.
- **No recoverable last-4 (FR-024):** attach to the **sole existing account for that issuer**; ask the person to pick or name one only when there is none or more than one.
- **Password-protected PDFs:** confirmed **in scope**, at priority P3 — routine in Indian retail banking. The password is never persisted.

## Assumptions

- **The engine gains an issuer dispatcher in this slice.** The ten existing reader pairs stay as they are; a dispatcher is added *inside the engine* so the app asks one question and issues one instruction. Its exact shape (an issuer value plus a single parse entry point) is settled at plan time; what this spec fixes is the *requirement* that the app stays bank-agnostic (FR-010 – FR-012).
- **Everything else already exists and is reused, not rebuilt**: the ten readers, the balance-chain and reconciliation checks, the deterministic categorization stack and its 23 builtin categories, the encrypted store (schema v5) with its typed failures and fail-closed wrong-key behaviour, the Keychain key ceremony, and the encrypted-file location and protection wiring.
- **PDF text extraction is native.** The platform reads the document and supplies the engine's reader seam with lines, full text, and the first row's word positions. The engine never opens a PDF. (Constitution Principle II.)
- **Password-protected statements are worth supporting in this slice**, because password-protected PDFs are routine in Indian retail banking and excluding them would gut the feature's real-world usefulness. The password is used to open the document and then discarded.
- **The person's device holds the only copy of their financial data.** No account sign-in, entitlement check, or server call is involved in this flow; the account requirement of Constitution Principle I is a separate, later milestone (P4) and MUST NOT be introduced here.
- **Currency is INR** for the supported issuers; multi-currency handling is not exercised by this slice.
- **The store's timestamps are supplied by the app**, since the engine reads no wall clock.
- **"Imported" means persisted**: an import is only reported as successful once the transactions are durably written to the encrypted store.
- **The statement period comes from the parse, not from the file** — no inference from a filename or file modification date.
- **Deployment baseline is iOS 26**, so the modern material language is applied unconditionally; no availability gates and no hand-rolled fallbacks exist anywhere in this flow.

## Out of Scope *(deferred to later slices)*

These are explicitly **not** part of this slice. Each is deferred to a later P3 (or later) slice:

- **Transaction list and transaction detail UI** — this slice shows a *summary*, not a browsable ledger.
- **Dashboard, charts, and any analytics visualization.**
- **Budgets** and **tags**.
- **Search and filtering.**
- **Export** (CSV/PDF/share sheet).
- **Manual categorization UI** — categorization runs automatically here; correcting a category by hand is later.
- **Transfer-review UI** — transfer detection exists in the engine but is not surfaced or run as part of this flow.
- **CSV import** — PDF only in this slice.
- **Multi-file / batch import** — one file per import.
- **Share Extension** ("share statement to Kaname") — the in-app document picker only.
- **Onboarding / first-run explainer flow** — the empty state (User Story 7) is the whole of the first-run experience here.
- **Account editing, renaming, or deletion.**
- **The manual column-mapper fallback** for unrecognized statement layouts.
- **Any premium or cloud capability** — AI-assisted parsing, Account Aggregator onboarding, cross-device sync, and the account/entitlement layer are all later milestones and MUST NOT appear on this path.

## Dependencies

- The ten shipped statement readers and their claim checks, exposed over the engine bridge.
- The balance-chain and reconciliation integrity checks.
- The deterministic categorization stack and the builtin categories.
- The encrypted on-device store (schema v5) and its typed failure model.
- The platform-side Keychain key ceremony and the encrypted database location + file-protection wiring.
- Synthetic golden statement fixtures for the supported issuers, plus new synthetic fixtures for the unusable-document cases (image-only, password-protected, corrupt, non-PDF, unrecognized).
