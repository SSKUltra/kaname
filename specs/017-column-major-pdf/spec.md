# Feature Specification: Column-Major PDF Extraction Fidelity (Read Every Transaction a Real Statement Prints)

**Feature Branch**: `017-column-major-pdf`  
**Created**: 2026-08-13  
**Status**: Draft — **all clarifications answered; ready for `speckit.plan`**  
**Milestone**: P3 (Core SwiftUI app) — the second slice of P3, and the first slice that closes the gap between "the import vertical works on our fixtures" and "the import vertical works on the statements people actually hold."  
**Input**: User description: "Column-major PDF extraction fidelity. Real statements are multi-column tables; the platform's PDF text layer emits them column-major, so the date+description column arrives on different text lines from the amount+Dr/Cr column. Every shipped reader expects one row on one line, so 10 of 13 real statements import zero transactions and the other 3 under-read. The extractor can currently only add line breaks, never re-join what the PDF text layer split. Fix the extraction so a row printed on one visual line is delivered as one text line — without regressing the opposite failure (rows the text layer merges) that slice 016 PR D fixed, and without breaking issuer detection, which is sensitive to inter-token spacing."

> **Note on priority labels**: This feature sits in product milestone **P3**. Separately, the user stories below use the standard spec priority labels (P1/P2/P3, …) to order the work *within this feature*. "Milestone P3" and "User Story P3" are unrelated numbering schemes.

## Why this slice exists

Slice 016 delivered the import vertical end to end: pick a PDF, identify the issuer, parse it, persist it, see a summary. It is proven against every golden vector in `fixtures/` and against a round-trip through the real platform PDF engine (`ios/Tests/ExtractionFidelityTests.swift`). By the tests, statement import works.

It does not work on real statements.

Running the app's own extractor and the engine's own dispatcher over a reference set of **13 genuine statement PDFs** (the author's own records, held outside this repository and never committed) produced this:

| Outcome | Count | Files |
|---|---|---|
| Issuer not recognised at all | **2** | AU savings, HDFC savings |
| Issuer recognised, **0 transactions imported** | **8** | Federal savings ×2, HDFC savings (2nd), ICICI savings (42 pages), IOB card, Federal card, HDFC card, Yes card |
| Issuer recognised, 1–4 transactions imported (almost certainly under-reading) | **3** | HDFC card (new layout), ICICI card, SBI card |

**Not one of the 13 files is defective.** None is password-locked, none is image-only. Every one yields a text layer between 7,697 and 100,792 characters across 2–42 pages. The text is there; the app cannot read a row out of it.

The cause is structural, not per-issuer. Real statements are **multi-column tables**, and the platform's PDF text layer emits them **column-major**: it walks the date/description column down the page, then the amount column, then the Dr/Cr column. So one printed row arrives as several unrelated text lines. Measured on the reference set: the Yes card statement has **18 text lines that are nothing but an amount** (`999.99 Dr`); the HDFC card statement has **21**; the IOB card statement has **10**. The corresponding date+description lines carry **no amount and no Dr/Cr marker at all**. Two files (IOB card, HDFC card) contain **zero** text lines with a date anywhere on them.

Every shipped reader — the credit-card `line_reader` and the bank `ledger_reader` alike — matches a row only when the date, the description and the amount (and, for cards, the `Dr`/`Cr` marker) appear together on **one** line. Against column-major text, that matches nothing, and the app dutifully reports a statement with no spending.

The extractor cannot fix this today because of a specific limitation: it re-derives line breaks from glyph geometry but **keeps the PDF text layer's own newlines as hard breaks**. That makes it a one-way valve — it can only ever *split* a line further, never *re-join* text the platform split. Slice 016 PR D deliberately built it that way, because it was solving the **opposite** failure: a tight layout where the text layer *merged* two adjacent rows and the reader produced one confidently wrong transaction from row 1's date and row 2's amount. Both failures are real, they are mirror images of each other, and after this slice **both must be impossible at the same time**.

This slice is also two-sided in a second, less obvious way. A prototype that reconstructed rows geometry-first did recover complete rows (`date  description  Ref No: …  category  amount` for the Yes statement; `DD-MMM-YYYY  description  Dr  9999.99` for IOB) — **and then broke issuer detection on 11 of the 13 files**, because the engine's claim markers are matched as literal substrings against the document text and several of them contain spaces (`"Statement of Transactions"`, `"HDFC Bank Credit Card"`, `"Savings Account Details"`, `"Statementof account"`). Changing inter-token spacing anywhere on the page changes whether those literals match. **The extractor and the engine's document-recognition layer must move together, in one slice, or the app gets worse rather than better.**

Everything here stays inside the constitution's boundaries: PDF text extraction remains native to the platform (**no PDF engine goes into the Rust core**), the whole path stays **100% on-device with zero network I/O**, money stays an exact decimal, and **every fixture added by this slice is synthetic** — the reference statements are private financial records and are the reference for *structure and geometry only*.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A real statement imports all of its transactions (Priority: P1)

A person imports a statement from any of the ten supported issuers — the real thing, straight from their bank's website or email, laid out as the multi-column table every Indian bank prints. Kaname reads **every transaction it contains**: the same dates, the same descriptions, the same exact amounts, in the same order as the printed statement. Not zero. Not one. All of them.

**Why this priority**: This is the entire slice. Today ten of thirteen real statements import nothing at all, which means the import vertical — the app's only feature — does not work for the people it was built for. Every other story in this spec protects, qualifies or proves this one.

**Independent Test**: Build synthetic statement documents that reproduce the **column-major geometry** of each supported issuer's real layout (column x-positions, row bands, which column carries the amount and which carries the `Dr`/`Cr` marker, the issuer's date format) with entirely fabricated merchants, amounts, dates and account numbers; import each; confirm the transaction count, dates, exact decimal amounts and directions match the vector's declared expectations exactly.

**Acceptance Scenarios**:

1. **Given** a statement whose rows are printed as a multi-column table and whose text layer emits those columns separately, **When** it is imported, **Then** every printed transaction is imported with its correct date, description, exact amount and direction.
2. **Given** such a statement, **When** it is imported, **Then** the number of transactions imported equals the number of transactions printed — no row is dropped and no row is invented.
3. **Given** a statement whose amount column is emitted as standalone amount-only text lines, **When** it is imported, **Then** each amount is attached to the transaction printed on the same visual row, and to no other.
4. **Given** a statement in which no text line contains a date, **When** it is imported, **Then** it still imports its transactions — the absence of a date on any emitted line is a property of the text layer, not of the statement.
5. **Given** a long statement (tens of pages), **When** it is imported, **Then** transactions are read from **every** page, not only the first.
6. **Given** any imported transaction, **When** its amount is stored and displayed, **Then** it is exact to the last paisa, carried as an exact decimal at every step.

---

### User Story 2 - Reshaping the text does not lose the issuer (Priority: P2)

The person picks the same statements as before and Kaname still knows who issued each one. Recovering complete rows must not cost the app its ability to recognise the document in the first place.

**Why this priority**: This is the failure the prototype actually produced — complete rows, and eleven of thirteen documents suddenly unrecognised. An unrecognised statement imports nothing, which is exactly the outcome this slice exists to eliminate. It is second only to reading the rows because it is the way this work most plausibly makes things worse.

**Independent Test**: For every supported issuer, run document recognition over both the pre-existing golden vector text **and** the reshaped text produced by the new extraction from that issuer's synthetic column-major document, and confirm both identify the same issuer.

**Acceptance Scenarios**:

1. **Given** any document that the engine recognised before this slice, **When** it is imported after this slice, **Then** the engine recognises the same issuer. No supported issuer regresses to "not recognised".
2. **Given** a document whose recognisable phrases are printed with unusual spacing — extra spaces, no space, or a column gap falling inside the phrase — **When** recognition runs, **Then** the document is still recognised. Recognition MUST NOT depend on the exact number or kind of whitespace between words.
3. **Given** a document whose recognisable phrases are split across the reshaping (a header printed as two columns), **When** recognition runs, **Then** the outcome is the same as before reshaping.
4. **Given** any document, **When** it is imported twice, **Then** recognition returns the identical issuer both times — the same document text always yields the same issuer.
5. **Given** a document that no issuer should claim, **When** it is imported, **Then** the whitespace tolerance added here does **not** cause a new false claim: a document not recognised before is not spuriously recognised now.

---

### User Story 3 - The money keeps its meaning after reshaping (Priority: P3)

A reconstructed row must say what the printed row says. The amount must be the amount, the `Dr`/`Cr` marker must sit where the reader expects it relative to the amount, a withdrawal must not become a deposit, and a description must not swallow a figure from the next column.

**Why this priority**: A dropped transaction is visibly missing; a transaction imported with the wrong sign is invisibly wrong, and it silently corrupts every balance, budget and total downstream. The prototype demonstrated this is a live risk — the `Dr`/`Cr` marker drifted to the wrong side of the amount on some reconstructed rows.

**Independent Test**: Import synthetic column-major documents that include both a debit and a credit for every supported issuer — including a bank ledger where direction comes from the running-balance delta and the withdrawal/deposit **column position** — and assert every direction against the vector's declared expectation.

**Acceptance Scenarios**:

1. **Given** a row whose direction is printed as a `Dr`/`Cr` marker, **When** the row is reconstructed, **Then** the marker appears in the reconstructed row in the same position relative to the amount as it is printed on the page, and the transaction's direction matches the printed marker.
2. **Given** a bank-ledger row where direction is derived from the running-balance delta, **When** the row is reconstructed, **Then** the amount and the balance land in the correct columns and the derived direction matches the printed ledger.
3. **Given** a bank ledger whose first row's direction is bootstrapped from the withdrawal-vs-deposit column position, **When** the row is reconstructed, **Then** the word positions reported for that row still describe where the figures were printed on the page, so the bootstrap remains correct.
4. **Given** two adjacent columns whose contents are pushed together by reshaping, **When** the row is read, **Then** the two values remain distinguishable as two values and are never concatenated into one unreadable token.
5. **Given** any reconstructed row, **When** its values are read left to right, **Then** they appear in the same order as they are printed on the page.
6. **Given** any statement, **When** it is imported twice from the same file, **Then** the reconstructed rows and every resulting transaction are byte-for-byte identical.

---

### User Story 4 - The opposite failure stays fixed (Priority: P4)

The extraction must now be able to both **split** a line the text layer merged and **join** lines the text layer split — simultaneously, on the same page, without either capability re-opening the other's bug.

**Why this priority**: Slice 016 PR D fixed a real, damaging bug — a tight layout where two rows merged and the reader produced one confidently wrong transaction. Its parity proof (`ios/Tests/ExtractionFidelityTests.swift`) is the only thing standing between this slice and a regression to that state. It ranks below the money-correctness story only because it is a known, already-pinned hazard rather than a new one.

**Independent Test**: Run the existing extraction-fidelity suite unchanged, then add a document that exhibits **both** hazards at once — tightly-spaced rows that the text layer merges *and* columns it emits separately — and confirm both are resolved correctly in one pass.

**Acceptance Scenarios**:

1. **Given** the tightly-spaced layout that the text layer merges into fewer lines than were printed, **When** it is imported, **Then** the printed rows are recovered exactly as they are today, and the existing parity proof passes unchanged.
2. **Given** a document containing both hazards, **When** it is imported, **Then** the merged rows are split and the split columns are joined, and every transaction is correct.
3. **Given** any single-column document that already extracted correctly, **When** it is imported, **Then** it still produces exactly the transactions it produced before — reshaping never alters a document that was already read correctly.
4. **Given** the reference set of statements, **When** each is imported, **Then** no document produces **more** transactions than it prints — over-joining that fabricates a row is as much a failure as under-joining that loses one.

---

### User Story 5 - A layout it still cannot read says so (Priority: P5)

Some documents will still defeat reconstruction — an exotic layout, an unusable text layer, a genuinely unsupported statement variant. In each case the person is told plainly, and Kaname never presents an unreadable statement as an empty one.

**Why this priority**: The honesty requirement is already established and shipped (slice 016, US2/US5); this story protects it through a change that reshapes the very text those judgements are made from. It ranks here because it is a guarantee to preserve rather than new value to deliver.

**Independent Test**: Import a document whose geometry cannot be trusted, a document no issuer claims, and a supported-issuer document laid out in a variant the readers do not cover, and confirm each produces its own plain-language outcome and imports nothing silently.

**Acceptance Scenarios**:

1. **Given** a document whose page geometry cannot be trusted (positions unavailable or inconsistent with the text), **When** it is imported, **Then** extraction falls back to a defined, safe behaviour and the outcome is either a correct import or an honest failure — never a confidently wrong transaction.
2. **Given** a document that is recognised as a supported issuer but from which **no** transaction can be read, **When** the import finishes, **Then** the person is told that nothing could be recognised — unless the statement's own printed figures independently confirm it really is empty, in which case it is reported as a successful import of zero transactions.
3. **Given** a document that no issuer claims, **When** it is imported, **Then** the person is told the format is not recognised yet and nothing is written to the store.
4. **Given** any of these outcomes, **When** the message is shown, **Then** it contains no engine internals — no reader names, no error codes, no raw error text.
5. **Given** any failure in this story, **When** it occurs, **Then** the encrypted store is left exactly as it was.

---

### User Story 6 - The fix is proven without a single real statement entering the repository (Priority: P6)

The evidence for this slice comes from thirteen real, private financial documents. None of them, and no fragment of them, may be committed. The proof that ships is a set of **synthetic** documents that reproduce the real layouts' *geometry* with wholly fabricated content, plus a way for a person to re-run the check against their own files locally.

**Why this priority**: It is a constitutional constraint (fixtures MUST be synthetic or fully redacted) and the reason this class of bug survived to production in the first place — every existing fixture feeds the readers pre-split, single-column text and therefore cannot exercise line reconstruction at all. It ranks last only because it delivers no user-visible behaviour; it is non-negotiable regardless of rank.

**Independent Test**: Inspect every file added by this slice for real merchant names, real amounts, real dates and real account numbers; confirm the synthetic geometry vectors fail loudly if the extraction regresses; and confirm the local verification path works against an arbitrary directory of PDFs without writing any of their content into the repository, the store or any log.

**Acceptance Scenarios**:

1. **Given** the fixtures added by this slice, **When** they are reviewed, **Then** every merchant name, amount, date, account number and card number in them is fabricated, and none can be traced to a real statement.
2. **Given** a synthetic geometry vector, **When** it is imported, **Then** it exercises the real column-major failure — that is, it must **fail** against the pre-slice extraction and **pass** after it. A vector that passes both ways proves nothing and is not acceptable.
3. **Given** the full existing golden-vector suite, **When** it is run after this slice, **Then** every existing vector still passes with identical results.
4. **Given** a person with their own statements on their own machine, **When** they run the local verification path over a directory of PDFs, **Then** they get a per-file report of issuer and transaction count, and **no** statement content is written into the repository, committed, logged or transmitted.
5. **Given** the whole path, **When** the privacy audits are run, **Then** they pass: zero network I/O anywhere on the import path and no networking dependency in the shipped core.

---

### Edge Cases

- **A page-wide horizontal band that contains unrelated blocks** — an address block printed beside a summary box sits at the same height as a transaction row. Joining everything at one height would fuse unrelated content into a fake row. Row grouping must not manufacture a transaction from unrelated neighbours.
- **A genuinely wrapped description** — a narration too long for its column continues on the next visual line. That is two visual rows and must stay two lines, so the bank ledger's existing narration stitching (which reads the line above and the lines below an anchor) keeps working.
- **A continuation row with no date** — many ledgers print the date only on the first row of a day. The row must still be read.
- **Two amounts on one row** (withdrawal *and* deposit columns both printed, one of them blank or zero) — the blank column must not shift the remaining values into the wrong slots.
- **A row whose columns are further apart than the gap between two adjacent rows** — a wide table on tight leading. Horizontal grouping and vertical grouping can disagree; the outcome must be deterministic and must not silently prefer the wrong one.
- **Rotated or landscape pages**, and **statements printed in two side-by-side panels** — must not produce interleaved nonsense rows.
- **A very long statement** (40+ pages, thousands of glyphs per page) — reconstruction must complete in a time a person will wait, on every page, without exhausting memory.
- **A text layer whose reported character positions disagree with its text** (ligatures, unusual encodings) — must fall back safely rather than place a figure in the wrong row.
- **Amounts printed with a currency symbol, in parentheses, or with a trailing minus** — must not be mistaken for a column boundary or split into two tokens.
- **A header or footer that repeats on every page** and shares a band with the first or last row — must not be absorbed into a transaction.
- **A statement that legitimately has zero transactions** — must remain reportable as a successful zero-transaction import (slice 016 FR-020) and must not become "nothing recognised" as a side effect of reshaping.
- **A document claimed by a reader of the wrong statement kind** — a bank-account statement claimed by a credit-card reader (observed on the reference set: an SBI bank statement claimed by the SBI **card** reader). Importing a bank statement as a card mis-attributes every direction and every balance.

## Requirements *(mandatory)*

### Functional Requirements

#### Reconstructing a printed row

- **FR-001**: Text extraction MUST deliver each row **printed on one visual line** of the document as **one** text line, regardless of how many separate pieces the platform's PDF text layer emitted it in.
- **FR-002**: Text extraction MUST be able to **join** text the PDF text layer split as well as **split** text it merged. The text layer's own line breaks MUST NOT be treated as authoritative, unbreakable boundaries.
- **FR-003**: Row membership MUST be determined from where the content is **printed on the page**, not from the order or grouping in which the text layer emitted it.
- **FR-004**: Within a reconstructed row, values MUST appear in the same left-to-right order in which they are printed.
- **FR-005**: A reconstructed row MUST keep values from separate printed columns separable — two adjacent column values MUST NOT be run together into a single token that no reader can split.
- **FR-006**: Text extraction MUST NOT fabricate a row. Content printed on two different visual lines MUST NOT be joined into one, and unrelated blocks that merely share a horizontal band MUST NOT be fused into a transaction.
- **FR-007**: Text extraction MUST NOT lose content. Every non-whitespace character the text layer yields MUST appear in exactly one delivered line.
- **FR-008**: Rows MUST be reconstructed on **every** page of the document, not only the first.
- **FR-009**: Extraction MUST be **deterministic**: the same document MUST always produce the same lines, in the same order, byte for byte.
- **FR-010**: When a page's geometry cannot be trusted, extraction MUST fall back to a defined, documented behaviour that risks reading **too little** rather than placing a figure in the wrong row.
- **FR-011**: The word-position information the engine's bank-ledger bootstrap depends on MUST continue to describe where values were printed on the page, and MUST stay consistent with the reconstructed rows it is reported against.

#### Recognising the document

- **FR-012**: Document recognition MUST NOT depend on the exact whitespace between words. A recognisable phrase MUST still be recognised when its words are separated by a different amount or kind of whitespace, or by none.
- **FR-013**: Every document recognised by the engine before this slice MUST still be recognised, as the same issuer, after it. No supported issuer may regress.
- **FR-014**: The added whitespace tolerance MUST NOT introduce **new** claims: a document not claimed by an issuer before this slice MUST NOT become claimed by it now, except where doing so is an explicitly specified fix in this slice.
- **FR-015**: Recognition MUST remain deterministic and MUST remain a pure, on-device, network-free computation over the document's text.
- **FR-016**: A credit-card reader MUST NOT claim a document that is a bank-account statement, and a bank-account reader MUST NOT claim a credit-card statement. Where the engine has no reader for a document's actual statement kind, the honest outcome is "not recognised yet" — never a claim by a reader of the other kind. *(Retained as a sound invariant, but note it is **unevidenced**: the mis-attribution originally cited here was an error — see **Q1**. Planning MUST NOT let this requirement cause a reader to decline a statement of its own kind.)*

#### Naming the issuer: card products, not just banks

- **FR-041**: For **credit cards**, the registry MUST identify the issuer at **card-product** granularity, not bank granularity. Two different card products from the same bank are two different registry entries, each with its own id and its own display name naming the product.
- **FR-042**: For **bank accounts**, the registry MUST identify the issuer at **bank** granularity. Multiple statement layouts or template versions of the same bank's account statement map to a **single** registry entry; a new layout is a recognition change, never a new issuer.
- **FR-043**: Every existing credit-card registry entry whose display name states only the bank MUST be renamed to state the card product it actually reads. Renaming MUST NOT alter what any reader parses. *(There is **no installed base** — the app is unreleased and has no users — so the registry `id`, the display name and, if planning finds cause, the persisted `bank_code` and store schema may all be changed freely. This requirement is therefore a constraint on **behaviour**, not on compatibility: rename what a thing is called, never what it reads.)*
- **FR-046**: `bank_code` MUST continue to identify the **institution**, not the card product. The product is carried by the registry entry (FR-041). *(Verified: `bank_code` is used by neither the de-duplication nor the transfer-detection engine, and only two fixtures assert it — so folding the product into it is cheap, and is rejected on modelling grounds rather than cost. "Which institution issued this" and "which product is this" are different questions and MUST remain separately answerable; a Federal savings account and a Scapia card deliberately share `FEDERAL`.)*
- **FR-044**: A card product MUST be identified only from the region of the statement that names the account it belongs to — never by matching a product name anywhere in the document. *(Evidenced: one reference card statement's marketing copy names at least six other card products from the same bank.)*
- **FR-045**: Where a card statement's product cannot be established, the honest outcome is the existing bank-level identification — never a guess at a product. *(No registry entry currently relies on this fallback — all six card entries name their product — but it governs every card product not yet known to the registry.)*
- **FR-047**: A card product MUST be identified from the statement's **title/header region** — the area that names the document and the account — and MUST NOT be identified from the transaction rows or from promotional copy. *(Evidenced: the HDFC card statement's first line is `Swiggy HDFC Bank Credit Card Statement`, an unambiguous product title; meanwhile the string `Swiggy` also appears roughly forty times **inside transaction descriptions**, because the cardholder shops there. A whole-document match would identify the card by where its holder spends.)*
- **FR-048**: Where two registry entries claim the same document, the engine MUST resolve to the **more specific** claim — a product-level entry always beats a bank-level entry for the same institution and statement kind. Two *product-level* entries claiming one document is a defect that MUST fail loudly in tests, never be silently tie-broken. *(Today `detect_issuer` breaks ties by statement kind and then by registry id **alphabetically**. With `HDFC_INFINIA_CARD` and `HDFC_SWIGGY_CARD` both present and both matching a generic `HDFC Bank Credit Card` marker, the alphabetically-earlier entry would silently win. Per-product entries make this reachable, so the resolution rule MUST change in the same slice that adds them.)*
- **FR-049**: Where a statement prints the card number's leading digits unmasked, those digits MAY be used as a product discriminator, but MUST NOT be required — issuers differ in how much they mask. *(Evidenced across the reference set: the HDFC statement prints the first six digits and the last four; the SBI statement masks all but the last two.)*
- **FR-050**: Every credit-card registry entry MUST declare whether its claim is **product-proven** (the document itself identifies the card product, per FR-047) or **bank-level** (the claim matches any card from that institution). A bank-level claim is permitted **only while that institution has exactly one card entry**.
- **FR-051**: A test MUST enforce FR-050 mechanically: if two or more credit-card entries share an institution, **every one of them** MUST be product-proven. Adding a second card for an institution whose existing entry is only bank-level MUST fail the build until a real discriminator exists. *(This is what makes the renames safe. All six card readers currently claim at bank granularity — `["ICICI Bank"]`, `["HDFC Bank Credit Card", …]`, `["SBI Card", …]`, `["YES BANK"]`, `["Scapia", "Federal Bank"]`, `["INDIAN OVERSEAS BANK", …]` — so today's identification is correct by **uniqueness**, not by evidence. The rename must not be allowed to disguise that.)*
- **FR-052**: Registry ids MUST follow one convention: **`<INSTITUTION>_BANK`** for bank accounts and **`<INSTITUTION>_<PRODUCT>_CARD`** for credit cards. The institution prefix is what makes FR-051's "two card entries share an institution" check visible at a glance and trivial to enforce.
- **FR-053**: `bank_code` MUST hold the institution and nothing else, for every reader. *(Defect found: `sbi.rs` sets `BANK_CODE = "SBI_CARD"` — a product/kind value in a field that holds `"AU"`, `"FEDERAL"`, `"HDFC"`, `"ICICI"`, `"IOB"`, `"YES"` everywhere else. It MUST become `"SBI"`. This is a direct violation of FR-046 and is free to fix only because there is no installed base.)*

#### Reading the rows

- **FR-017**: For every one of the ten currently supported issuers, a statement in that issuer's real **column-major** layout MUST import **all** of the transactions it prints.
- **FR-018**: Each transaction MUST carry the date, description, exact decimal amount and direction printed on its own row and no other row's.
- **FR-019**: Direction MUST remain explicit and MUST come from the statement — the printed `Dr`/`Cr` marker for card statements, the running-balance delta (and, for a first row, the withdrawal/deposit column position) for bank ledgers. Direction MUST NOT be inferred from the sign of an amount.
- **FR-020**: A `Dr`/`Cr` marker MUST appear in a reconstructed row in the same position relative to its amount as it is printed on the page.
- **FR-021**: Money MUST be carried as an exact decimal at every step. No step may represent an amount as a floating-point number.
- **FR-022**: A row that is recognised as a transaction but cannot be fully read MUST continue to be reported as an unreadable row rather than silently dropped, so an incomplete import is never presented as a complete one.
- **FR-023**: The engine's existing integrity checks (the bank balance chain, the credit-card reconciliation against printed totals) MUST run over the newly readable rows, and their verdicts MUST be reported as they are today.

#### Honest failure

- **FR-024**: A document recognised as a supported issuer from which no transaction can be read MUST be reported as "nothing could be recognised", unless the statement's own printed figures independently confirm it is genuinely empty — the behaviour established in slice 016 MUST be preserved exactly.
- **FR-025**: A document no issuer claims MUST import nothing and MUST be reported as an unrecognised format.
- **FR-026**: No user-visible message on this path may contain engine internals — no reader names, no error codes, no raw error text.
- **FR-027**: Every failure path MUST leave the encrypted store exactly as it was.

#### Not regressing what already works

- **FR-028**: The existing extraction-fidelity parity proof (the tight-layout merge case from slice 016) MUST continue to pass, unmodified in its expectations.
- **FR-029**: Every existing golden vector in `fixtures/` MUST continue to pass with identical results.
- **FR-030**: A single document MUST be able to exhibit both hazards — merged rows and split columns — and have both resolved correctly in one pass.
- **FR-031**: A statement that legitimately contains zero transactions MUST still be reportable as a successful zero-transaction import.

#### Platform boundary, privacy and performance

- **FR-032**: PDF text extraction MUST remain **native to the platform**. No PDF engine, and no PDF parsing, may be added to the shared core. The core's reader seam MUST remain "lines, full text, first-row word positions".
- **FR-033**: The entire path MUST perform **zero** network I/O, and the shipped core MUST retain no networking dependency. The existing privacy audits MUST stay green.
- **FR-034**: No statement content — no merchant, amount, date, account number, or extracted line — may be written to logs or diagnostics.
- **FR-035**: A statement of at least 40 pages MUST extract and parse without the interface becoming unresponsive and without exhausting memory; the existing responsiveness and cancellation guarantees MUST hold.

#### Evidence

- **FR-036**: This slice MUST add synthetic statement vectors that reproduce the **geometry** of real column-major layouts — column x-positions, row bands, which column carries the amount and which carries the `Dr`/`Cr` marker, and the issuer's printed date format — with entirely **fabricated** merchants, amounts, dates, account numbers and card numbers.
- **FR-037**: Each such vector MUST **fail** against the pre-slice extraction and **pass** after it, so it demonstrably pins the bug rather than merely coexisting with it.
- **FR-038**: Coverage MUST extend to all ten supported issuers, including both statement kinds (credit card and bank ledger) and both observed date formats (`DD-MMM-YYYY` and `DD/MM/YYYY`).
- **FR-039**: **No real statement, and no fragment of one**, may enter the repository — not as a fixture, not as a test resource, not as an extracted-text sample, not in a comment, not in a commit message.
- **FR-040**: A local verification path MUST exist that lets a person run the real app extraction and the engine's dispatcher over a directory of their own PDFs and see, per file, the issuer identified and the number of transactions read — writing nothing into the repository, the store, a log, or the network.

### Key Entities

- **Printed Row**: What a person sees as one line of the statement's transaction table: a date, a description, one or more figures, and possibly a direction marker, printed across several columns at roughly the same height on the page. The unit this slice exists to recover.
- **Column**: A vertical region of the page carrying one kind of value (date, description, reference, withdrawal, deposit, balance, amount, `Dr`/`Cr`). Which column carries which meaning is issuer-specific and is part of what a geometry fixture must reproduce.
- **Emitted Text Fragment**: A piece of text as the platform's PDF text layer hands it over, together with where its characters sit on the page. The raw material of reconstruction; its grouping carries no reliable relationship to printed rows.
- **Reconstructed Line**: One delivered text line, assembled from the fragments printed on one row. The engine's only view of a row, and the contract every shipped reader is written against.
- **Row Band**: The vertical extent a printed row occupies, used to decide which fragments belong to it. Must tolerate mixed glyph heights within a row and must not stretch far enough to swallow the row above or below.
- **Claim Marker**: A phrase whose presence in the document text signals a particular issuer and statement kind. Currently matched as a literal substring, which is why it is sensitive to whitespace.
- **Geometry Fixture**: A synthetic statement vector defined by layout — column positions, row bands, per-column content, date format — from which a test document is produced and against which the reconstructed lines and the parsed transactions are asserted. Fabricated content only.
- **Reference Set**: The thirteen private, real statements the failure was measured against. It lives **outside** the repository, is never committed, and informs this work only through layout structure and expected counts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For **all ten** supported issuers, a statement in that issuer's real column-major layout imports **100%** of the transactions it prints — dates, exact decimal amounts and directions matching the declared expectation exactly.
- **SC-002**: Across the thirteen-statement reference set (verified locally, never committed), the number of statements that import **zero** transactions falls from **10 to 0**, and the number whose issuer is not recognised falls from **2** to at most the number covered by the open scope questions below.
- **SC-003**: Across the reference set, **no** statement imports **more** transactions than it prints.
- **SC-004**: **Zero** of the issuers recognised before this slice fail to be recognised after it.
- **SC-005**: **100%** of the existing golden vectors in `fixtures/` pass with identical results, and the slice-016 tight-layout parity proof passes unmodified.
- **SC-006**: **Zero** transactions import with an inverted direction across the geometry fixtures, which include at least one debit and one credit per issuer.
- **SC-007**: Importing the same document twice produces **byte-identical** extracted lines and identical transactions.
- **SC-008**: A 40-page statement completes extraction and parsing with the interface remaining responsive throughout and cancellable within **2 seconds**.
- **SC-009**: **Zero** network requests occur across the whole path, verified automatically by the existing audits.
- **SC-010**: **Zero** real merchants, amounts, dates, account numbers or card numbers appear in any file added by this slice, verified by review of every added file.
- **SC-011**: **Every** geometry fixture added by this slice fails against the pre-slice extraction, demonstrating it pins the reported bug.
- **SC-012**: **Zero** user-visible messages added or changed on this path contain an error code, a reader name, or engine-internal text.

## Clarifications

### Open questions — for the product owner (unanswered; do not self-answer)

> These are scope and process decisions, not technical unknowns. The spec is written so that it is complete and testable under either answer to each; the answers change what *else* ships.

#### Q1: The SBI statement — **ANSWERED, and the premise was wrong**

**Correction from the product owner**: `SBI-bank.pdf` is **misleadingly named**. It is not a
bank-account statement at all — it is a **credit-card** statement for the **SBI Cashback**
card. The filename was mine to misread, and the spec inferred a defect from it.

**Consequences of the correction:**

- **There is no mis-attribution.** `SBI_CARD`, a credit-card reader, claimed a credit-card
  statement. That is correct behaviour, not the bug this question was built around.
- **FR-016 loses its evidence but keeps its logic.** No observed cross-kind claim exists on the
  reference set. The invariant is still sound and cheap, so it is retained — but it is now
  flagged unevidenced, and planning must ensure it never causes a reader to decline a statement
  of its own kind. That failure would be worse than the one it guards against.
- **The reference set has no unsupported *bank*.** All thirteen files belong to issuers already
  in the registry. Every failure in this slice is extraction or recognition — none is a missing
  reader. That materially shrinks the slice.
- **`SBI-bank.pdf` is a card statement that reads 1 transaction of many**, so it is squarely a
  US1 case, not a scope question.

**The requirement this surfaced** (now FR-041–FR-045, and the real answer to Q1):

> **Credit cards are identified per card product; bank accounts are identified per bank.**

Every credit card a bank issues must be supported *as itself*, so the registry must name **which
card** it reads — cards from one bank differ in layout, in the fields they print, and in what
they mean. Bank-account statements are the opposite case: one bank's account statement may exist
in several template versions, and those all map to the **same** registry entry, because they
describe the same product.

Two of the six card entries already follow this rule — `YES_CARD` reads as "Kiwi (YES Bank)
Credit Card" and `FEDERAL_CARD` as "Scapia Credit Card", both named for the card product. The
remaining four state only the bank (`SBI Card`, `HDFC Bank Credit Card`, `ICICI Bank Credit
Card`, `Indian Overseas Bank Credit Card`) and must be renamed for the product they actually
read. `SBI_CARD` becomes the **SBI Cashback** entry.

**Why this is contained**: there is **no installed base** — the app is unreleased — so ids,
display names and even the store schema can change freely; nothing migrates because nothing
exists. `bank_code` is nonetheless kept at institution granularity (FR-046) as a **modelling**
decision, not a compatibility one: it is used by neither the de-duplication nor the
transfer-detection engine and only two fixtures assert it, so changing it would be cheap — it is
kept because "which institution" and "which product" are different questions and both must stay
answerable. The `make import-audit` bank-literal check reads its literals out of the registry, so
renamed entries are picked up with no change to the script.

**⚠️ Hazard, evidenced**: a card product name cannot be found by searching the document. The SBI
statement's **marketing copy names at least six other SBI card products** (SimplyCLICK,
SimplySAVE, Prime, Elite, BPCL, IRCTC) alongside the one it is actually for, and the HDFC card
statement contains the string `Swiggy` **around forty times inside transaction descriptions**,
because its holder shops there. This is the same class of defect as the
bank-name-in-a-merchant-description hazard recorded under Q4: **a whole-document substring match
is not identification.** Hence FR-044/FR-047 — the product is read only from the title/header
region naming the document and the account — and FR-045: where the product cannot be
established, fall back to bank-level identification rather than guess.

**What the discriminator actually is, per issuer** (measured on the reference set; the header
region only, digits masked, nothing recorded):

| Issuer | Header evidence | Usable product discriminator? |
|---|---|---|
| HDFC card | First line reads `Swiggy HDFC Bank Credit Card Statement` | **Yes** — the product names itself in the document title. `HDFC_INFINIA_CARD` would claim on its own title text. |
| ICICI card | First line reads only `CREDIT CARD STATEMENT` | **No** — the header names no product. FR-045 applies until a discriminator is found. |
| SBI card | Header names only `SBI Card`; card number masked to its last two digits | **No** from the header, and FR-049's leading-digits route is unavailable here. |
| Yes / Federal | Already product-named (`Kiwi`, `Scapia`) | Yes — the product *is* the brand on the statement. |

So per-product identification is **not uniformly available**, and the slice must not pretend it
is. `ICICI_CARD` and `SBI_CARD` are renamed because the product owner knows which card each
statement is — but their `claims()` cannot yet *prove* it from the document. Planning MUST decide
whether an entry whose product the engine cannot verify is (a) claimed at bank level per FR-045
with the product name carried only as a display label, or (b) confirmed once by the person when
the account is created. **This is the single most consequential open design point in the slice**:
get it wrong and a second card from the same bank is silently misfiled under the first.

**Still needed before planning**: ~~the correct card product for the four entries being renamed~~
**— answered by the product owner:**

| Registry id | Display name today | Becomes |
|---|---|---|
| `SBI_CARD` | SBI Card | **SBI Cashback Credit Card** |
| `HDFC_CARD` | HDFC Bank Credit Card | **HDFC Swiggy Credit Card** |
| `ICICI_CARD` | ICICI Bank Credit Card | **ICICI Amazon Pay Credit Card** |
| `IOB_CARD` | Indian Overseas Bank Credit Card | **IOB RuPay Credit Card** |
| `YES_CARD` | Kiwi (YES Bank) Credit Card | display name already names the product; the **id** becomes product-shaped |
| `FEDERAL_CARD` | Scapia Credit Card | display name already names the product; the **id** becomes product-shaped |

**The registry after this slice — the full future state.** Convention (FR-052):
`<INSTITUTION>_BANK` for accounts, `<INSTITUTION>_<PRODUCT>_CARD` for cards; `bank_code` is
always the bare institution (FR-046/FR-053).

| Registry id | `bank_code` | Display name | Kind |
|---|---|---|---|
| `AU_BANK` | `AU` | AU Small Finance Bank Account | account — unchanged |
| `FEDERAL_BANK` | `FEDERAL` | Federal Bank Account | account — unchanged |
| `HDFC_BANK` | `HDFC` | HDFC Bank Account | account — unchanged |
| `ICICI_BANK` | `ICICI` | ICICI Bank Account | account — unchanged |
| `SBI_CASHBACK_CARD` | `SBI` ⚠️ *was `SBI_CARD`* | SBI Cashback Credit Card | card — renamed |
| `HDFC_SWIGGY_CARD` | `HDFC` | HDFC Swiggy Credit Card | card — renamed |
| `ICICI_AMAZONPAY_CARD` | `ICICI` | ICICI Amazon Pay Credit Card | card — renamed |
| `IOB_RUPAY_CARD` | `IOB` | IOB RuPay Credit Card | card — renamed |
| `YES_KIWI_CARD` | `YES` | Kiwi (YES Bank) Credit Card | card — id only |
| `FEDERAL_SCAPIA_CARD` | `FEDERAL` | Scapia Credit Card | card — id only |

`FEDERAL_BANK` and `FEDERAL_SCAPIA_CARD` deliberately share `bank_code = FEDERAL`: same
institution, different statement kind. That is FR-046 working, not a collision.

Future entries follow the same shape without further decisions — `HDFC_INFINIA_CARD`,
`HDFC_MILLENNIA_CARD`, `SBI_SIMPLYCLICK_CARD`, `AXIS_FLIPKART_CARD` — and the moment any of them
is added beside an existing card for the same institution, FR-051 fails the build until both
entries can prove their product from the document. `IOB_RUPAY_CARD` is the one to watch: RuPay is
a card **network**, so if IOB turns out to issue several RuPay variants, that token is not a
product and FR-051 will force the distinction at the point a second one is added.

**Do the four bank-account entries need the same treatment? No — and renaming them would be a
mistake.** Under FR-042 a bank account is identified per **bank**, so `AU_BANK`, `FEDERAL_BANK`,
`HDFC_BANK` and `ICICI_BANK` are already at the right granularity; the two HDFC savings layouts
and the two Federal savings layouts in the reference set are template versions of one product,
not four products. Only the **six card entries** are renamed.

**But the rename is the easy half, and on its own it would be a lie.** Every one of the six card
readers claims at **bank** granularity today — `["ICICI Bank"]`, `["HDFC Bank Credit Card",
"HDFC Bank Credit Cards"]`, `["SBI Card", "GSTIN of SBI Card"]`, `["YES BANK"]`, `["Scapia",
"Federal Bank"]`, `["INDIAN OVERSEAS BANK", "iobnet.co.in"]`. Note that this includes the two
entries whose display names *already* name a product: `YES_CARD` claims on `YES BANK`, and
`FEDERAL_CARD` will match any Federal card through its `Federal Bank` alternative. So the
existing product-named entries are already writing a cheque their claims cannot cash.

**Today that is harmless, for one reason only: each institution has exactly one card entry.**
Identification is correct by **uniqueness**, not by evidence. The moment a second card from the
same bank is added — an HDFC Infinia beside the HDFC Swiggy — a bank-level claim matches both,
and FR-048 shows `detect_issuer` would resolve it *alphabetically and silently*.

That is why FR-050/FR-051 accompany the rename: each entry declares whether its claim is
product-proven or bank-level, and a test fails the build if two card entries for one institution
are not both product-proven. Bank-level claims stay legal exactly as long as they are unambiguous,
and the second card from any bank becomes impossible to add without a real discriminator.
| `YES_CARD` | Kiwi (YES Bank) Credit Card | unchanged — already names the product |
| `FEDERAL_CARD` | Scapia Credit Card | unchanged — already names the product |

`IOB_CARD` was initially deferred and is now **back in scope**: the product owner confirmed the
card is the **IOB RuPay** credit card. Worth recording *how* that was settled, because it is the
rule this slice is adopting: automated inspection found only the string `RuPay` in the document,
which is a **card network** and not by itself a product name — so under FR-044 that was not
identification, and the entry was left alone until a person who holds the card named it. FR-045
existed to make that deferral honest rather than a gap. All four renames now proceed.

Note that the two HDFC card statements share a `last4`, so they are the **same card in two
statement layouts** — under FR-041 that is one registry entry with two recognisable layouts,
exactly as FR-042 treats bank-account template versions.

Renaming these six is the whole of the registry work: no entry is added, none is removed, the
four bank-account entries are untouched, and no reader's parsing behaviour changes (FR-043).

**A gap this freedom exposes — for planning to price, not for this spec to assume.** With the
registry now identifying cards per product, an **account** still cannot say which product it is:
the store persists `bank_code` (the institution) and `last4`, but not the registry `id`. So two
HDFC cards held by the same person are distinguishable only by their last four digits, and the
app cannot name either of them without re-reading a statement. Persisting the issuer id on
accounts and statements would close that, and with no installed base it is a free schema change
today and an expensive one later. It is **not** pulled into this slice by default — this slice is
an extraction fix — but planning SHOULD state explicitly whether it is taken now or deferred,
rather than letting it pass unnoticed.

---

#### Q2: The unrecognised HDFC savings variant — cover it, or defer it?

**Context**: On the reference set, `HDFC-savings.pdf` is claimed by **no reader at all**, while a second HDFC savings file (`HDFC-savings-2.pdf`) *is* claimed by `HDFC_BANK` (and then reads zero transactions — which this slice's extraction work should fix). The unclaimed file therefore looks like an **HDFC bank-statement template variant** the existing claim markers do not cover, not a new bank.

| Option | Answer | Implications |
|--------|--------|--------------|
| A | In scope. Extend the existing HDFC bank reader's recognition (and, if needed, its row patterns) to cover the variant, with a synthetic fixture for it. | The reference set reaches full coverage on HDFC. Broadening claim markers raises the risk of a false claim, so FR-014 has to be tested hard. Contained — it is an existing reader, not a new one. |
| B | Out of scope. This slice fixes extraction; the variant becomes its own slice. | Keeps the slice focused on the structural bug. One reference file keeps importing nothing, and the person sees "format not recognised yet". |
| Custom | Something else — e.g. cover it only if the extraction fix alone happens to make it claimable. | Tell me the shape you want. |

**Your choice**: **Custom — and the outcome is now measured, so this costs no extra scope.**

The file was tested directly against `hdfc_bank.rs`'s own claim markers. `CLAIM_ALL = ["HDFC"]`
matches exactly. Of `CLAIM_ANY = ["WithdrawalAmt", "Savings Account Details", "Statementof
account"]`, **two match whitespace-insensitively and neither matches exactly**: the document
contains `WithdrawalAmt` and `Statementof account` once inter-token whitespace is disregarded.
(For contrast, `HDFC-savings-2.pdf` — which *is* claimed today — matches `Savings Account
Details` exactly.)

So this is **not** a template variant needing new markers. It is the same failure as everything
else in this slice: the text layer separates tokens the existing markers expect adjacent.
**FR-012 already requires whitespace-insensitive recognition and is not optional**, so the file
becomes claimable as a direct consequence of work already in scope. No marker is broadened, so
the FR-014 false-claim risk this question worried about does not arise.

Note the shape of those two markers — `WithdrawalAmt`, `Statementof account` — with the spaces
already missing. They are themselves artefacts of a *different* extractor's spacing, carried
over from the web engine. That is the strongest available evidence that matching literal
substrings against whatever spacing an extractor happens to produce is the wrong contract, and
that FR-012 is a correctness fix rather than a convenience.

---

#### Q4: The AU savings statement — the other unrecognised file (raised after the spec was drafted)

**Context**: `AU-statment-savings.pdf` is the second of the two files claimed by no reader, and
it was originally folded into Q2's framing. Direct testing shows it is a **different problem**
and needs its own answer. Against `au_bank.rs`: `CLAIM_ALL = ["aubank.in"]` matches exactly, but
**neither** entry of `CLAIM_ANY = ["Savings Account", "Current Account"]` appears in the
document — not exactly, and not whitespace-insensitively either. Unlike Q2, whitespace tolerance
does **not** rescue this file. The reader correctly identifies the institution and then rejects
the document for want of an account-kind marker it does not print.

| Option | Answer | Implications |
|--------|--------|--------------|
| A | In scope. Add the account-kind marker this layout actually prints to AU's `CLAIM_ANY`, with a synthetic fixture covering it. | Small and contained — one marker on an existing reader, no new issuer. Closes the last unrecognised file. Must be tested against the FR-014 hazard below. |
| B | Out of scope; its own slice. | Keeps the slice to the structural bug. One reference file keeps importing nothing. |

**Your choice**: **Option A — in scope.** Confirmed by the product owner: `AU-statment-savings.pdf`
is a **savings-account** statement, so it is correctly a bank-account document for an issuer
already in the registry (`AU_BANK`). It is not a missing reader and not a mis-kinded claim — the
reader simply requires an account-kind marker this layout does not print. Per FR-042, a second AU
account-statement layout maps to the **same** registry entry; recognition widens, the registry
does not. The FR-014 hazard below makes this the most dangerous marker change in the slice, so it
must ship with the cross-bank false-claim regression cases.

---

#### Risk surfaced while answering Q2 and Q4: a bank's name inside a *merchant description*

Testing turned up a concrete false-claim hazard that FR-014 must be tested against, not merely
asserted. **`AU-statment-savings.pdf` contains the literal string `HDFC`** — not in its header,
but inside a UPI transaction description (`UPI/DR/…/NETFLIX COM/HDFC/…`), where a counterparty
bank is named. `hdfc_bank.rs`'s `CLAIM_ALL` is exactly `["HDFC"]`, matched as a substring
**anywhere in the document**. So the AU statement already satisfies HDFC's mandatory claim
condition; it is held back only by failing every one of HDFC's `CLAIM_ANY` markers.

This is not a hypothetical. Indian bank statements name other banks constantly — UPI handles,
NEFT/IMPS/RTGS strings, beneficiary banks, card networks. Any claim marker that is a bare
institution name matched anywhere in the document is one coincidence away from a false claim,
and **FR-012's whitespace tolerance widens every one of these matches at once**. A statement
claimed by the wrong bank's reader is worse than an unrecognised one: it imports rows under
another institution's identity.

**Constraint carried into planning**: `AU-statment-savings.pdf` (real, local, not committable)
and a synthetic equivalent — a statement for issuer X whose transaction descriptions name issuer
Y — MUST both be regression cases for FR-014. Planning SHOULD also consider whether claim
markers ought to be matched only outside the transaction-row region, rather than against the
whole document.

---

#### Q3: What counts as proof, given the evidence can never be committed?

**Context**: The bug was found by running thirteen real statements through the pipeline. Those files can never enter the repository (Constitution: fixtures MUST be synthetic). Synthetic geometry fixtures can reproduce the *layout* faithfully, but only the real files prove the layouts were reproduced faithfully **enough**. Slice 016 has precedent for human-run release gates (T123, T129).

| Option | Answer | Implications |
|--------|--------|--------------|
| A | Synthetic fixtures are the automated gate; a **documented, human-run, local-only pass over the reference set** is an additional release gate, recorded as counts only (issuer + transaction count per file), like T123/T129. | Strongest evidence, and it keeps the repository clean. Requires a person with the files to sign off before the slice is called done, so the slice cannot be closed purely by CI. |
| B | Synthetic fixtures alone gate the release; the reference-set run is an informal developer aid with no recorded outcome. | Fully automatable, closable by CI alone. Weakens the guarantee: a geometry fixture that models the layout slightly wrong would pass while real statements still fail. |
| Custom | Something else — e.g. a redaction pipeline that mechanically rewrites a real statement into a synthetic one with the geometry preserved, so the *output* is committable. | Tell me the shape you want. This is more work up front but would make the evidence reproducible forever. |

**Your choice**: **Option A**, and the "Custom" option is **rejected as posed** — see below.

**Rationale.** The product owner's goal is broader than this slice: users should be able to
*contribute* the layouts of banks we don't yet support, without exposing their data, so
coverage can expand to every Indian bank and card. That capability is **already decided** by
[`docs/adr/0004-unknown-bank-ingestion.md`](../../docs/adr/0004-unknown-bank-ingestion.md) §4–§6:
the contribution unit is a **layout signature** — date format, column positions, row shape,
header and marker tokens, currency, card-vs-ledger kind, and **no values** — which is PII-free
by construction, so a raw statement never leaves the device. Phase 1 is an out-of-band export
(share sheet → prefilled issue), keeping the client at zero network calls.

That does **not** change what counts as proof here, because ADR-0004 is explicit on the point
that the "Custom" option assumed away: *"a contributed signature guides authoring but is never
committed as test data"*, and golden fixtures MUST stay synthetic (Constitution Principle V).
A contribution tells a maker **what layout to build for**; the maker still authors a synthetic
fixture. So there is no committable-real-geometry artefact to gate on, and Option A stands.

**Dependency, in the other direction.** This slice is a **prerequisite** for ADR-0004's
signature work, not a competitor to it. A layout signature records column positions and row
shape — exactly the geometry this slice proves the app cannot currently recover. Deriving a
signature from column-major text that the extractor has fragmented would learn a broken layout
and teach it to every future contributor. Signatures become meaningful only once rows are
reconstructed correctly.

**Gap this slice's evidence exposes in ADR-0004** — tracked separately, out of scope here.
ADR-0004's fallback ladder is triggered by a statement that **no reader claims**
(*unrecognized*). The reference set shows the dominant real-world failure is not that: **8 of
13 files were recognised correctly and still read zero transactions.** A claimed-but-unreadable
statement never enters the ladder, so it gets no mapper, learns no signature, and produces no
contribution — the app simply reports a statement with no spending. Whatever this slice does to
the extractor, that trigger is too narrow, and closing it is what would let contribution
actually expand issuer coverage. **Both this gap and the change below are now recorded as an
amendment to `docs/adr/0004-unknown-bank-ingestion.md` (2026-08-13).**

#### Q3 addendum — generated fixtures (supersedes the "Custom" option above)

The product owner proposed a sharper version of the rejected "Custom" option, and it holds:
rather than *redacting* a real statement down to a committable one, **render a synthetic
statement up from a structure-only signature**. Because a signature carries no values
(ADR-0004 §5), a document generated from it — fabricated merchants, amounts, dates and account
numbers placed at the signature's real column positions and row spacing — is **synthetic by
construction** while its geometry stays faithful. Nothing is stripped, so nothing can survive
stripping.

This was validated before being adopted. A signature derived from a real Yes/Kiwi card
statement (35 column positions, 21.3pt row spacing, date shape `99/99/9999`) was rendered into
a synthetic statement carrying four fabricated transactions and run through the shipped
pipeline. It reproduced this slice's bug exactly: `detect_issuer` returned `YES_CARD`, printed
totals were recovered (3050.00 Dr / 5000.00 Cr), and the reader returned **0 of the 4 printed
transactions** — the amount column arrived on its own text lines, as lines 13–15 of the
extracted text.

Why this changes the shape of this slice's evidence, without changing the Q3 answer:

- **It is the natural way to satisfy FR-037/SC-011.** A generated fixture demonstrably fails
  against the pre-slice extractor, so it cannot be vacuous.
- **It closes the blind spot that caused this slice.** Every existing fixture supplies
  pre-split `lines`, testing the readers while *assuming* the extraction that actually failed.
  A generated document is opened by the real PDF engine, putting the extractor under test.
- **Option A still stands.** Generated fixtures are faithful to a signature, and a signature is
  derived by code this slice is also changing. The human-run pass over the reference set
  remains the only evidence that the signatures themselves are right.

**Constraint carried into planning**: a generated fixture's header and marker literals MUST come
from the reader's own published claim markers, never harvested from a contributor's document,
and each generated fixture MUST be reviewed to confirm it carries no token lifted from its
source.

## Assumptions

- **The reference set is evidence, never data.** The thirteen real statements live outside the repository and are used only to establish layout structure and expected counts. Nothing from them is committed.
- **The bug is structural, not per-issuer.** It affects every issuer whose statement is a multi-column table, which is all of them; the fix therefore belongs in extraction and recognition, not in ten separate readers. Individual readers are changed only where a real layout demonstrates they must be.
- **The shipped readers' contract is preserved.** They continue to be fed `lines`, `full_text` and first-row word positions and continue to expect one transaction per line; this slice makes that contract *satisfiable* against real documents rather than replacing it. The reader seam does not change shape.
- **Every existing fixture stays valid.** They exercise the readers with pre-split single-column text and remain correct; they are simply insufficient, which is why geometry fixtures are added alongside them rather than in place of them.
- **The two-sided nature of the fix is real and is one slice.** Reshaping the text without making recognition whitespace-tolerant makes the app strictly worse (the prototype turned 11 of 13 documents into "not recognised"). Both sides ship together or neither does.
- **Word-level, not glyph-level, is the unit.** The platform's text layer returns stray, far-off positions for the trailing glyphs of a drawn run; grouping at glyph granularity was verified experimentally to produce scrambled output. Words are treated as atomic and anchored on their first glyph's position. This is a stated constraint on the solution, not an implementation choice to be revisited at plan time.
- **The person's device does all of it.** No server, no account, no entitlement check is involved anywhere on this path; the account requirement of Constitution Principle I remains a later milestone.
- **Deployment baseline is iOS 26**, so the modern material language applies unconditionally — no availability gates anywhere in this flow.
- **Currency is INR** for the supported issuers.
- **Under-reading is still failing.** The three reference files that import 1–4 transactions are treated as failures, not partial successes, until the geometry fixtures for their layouts prove a complete read.

## Out of Scope *(deferred to later slices)*

- **A manual column-mapper UI** for statements Kaname still cannot read. Named in slice 016's Out of Scope and still deferred; this slice's job is to make it needed far less often, not to build it.
- **AI-assisted parsing** or any other premium/networked capability. Constitutionally Pro-only and irrelevant here.
- **OCR of scanned, image-only statements.** Unchanged from slice 016: no text layer means an honest "this looks scanned" failure.
- **New issuers beyond the ten currently supported**, except as decided by open questions **Q1** and **Q2**.
- **CSV import, batch/multi-file import, and the Share Extension.**
- **Transaction list, dashboard, budgets, tags, search, export, manual categorisation** — the rest of P3, sliced separately.
- **Re-architecting the reader seam.** The core stays free of any PDF engine and keeps its `lines`/`full_text`/`first_row_words` contract.
- **Android or desktop extraction.** Extraction is platform-native; other platforms implement the same contract when they exist.

## Dependencies

- The shipped import vertical (slice 016) end to end: document picking, native text extraction, the issuer dispatcher, the readers, the integrity checks, the encrypted store, categorisation and the import summary.
- The ten shipped statement readers, their claim checks, and the registry that dispatches to them.
- The existing extraction-fidelity parity proof (`ios/Tests/ExtractionFidelityTests.swift`), which this slice must keep green.
- The existing golden vectors in `fixtures/`, which this slice must keep passing.
- The existing privacy audits (`make import-audit`, `make core-privacy-audit`) and the core/iOS verification gate.
- A person with the private reference statements, to run the local verification pass — subject to open question **Q3**.
