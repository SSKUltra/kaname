# Phase 0 Research: Column-Major PDF Extraction Fidelity

**Feature**: `017-column-major-pdf` | **Date**: 2026-08-13 | **Spec**: [`spec.md`](./spec.md)

Every decision below is grounded in code that exists in this repository today, or in evidence the
spec records from the (private, uncommitted) thirteen-statement reference set. Where a decision
rejects an alternative, the rejection reason is a measured fact, not a preference.

Source anchors used throughout:

- `ios/Sources/Import/StatementTextExtractor.swift` — the extractor being changed.
- `core/crates/kaname-core/src/statement/registry.rs` — the 10-entry registry and `detect_issuer`.
- `core/crates/kaname-core/src/statement/line_reader.rs::claims` — card claim matching.
- `core/crates/kaname-core/src/statement/ledger_reader.rs::claims_ledger` — ledger claim matching.
- `ios/Tests/ExtractionFidelityTests.swift` — the slice-016 parity proof that must stay green.
- `docs/adr/0004-unknown-bank-ingestion.md` §Amendment (2026-08-13) — signatures generate fixtures.

---

## R1 — One algorithm must both split and join; it must therefore ignore the text layer's newlines

**Decision.** Replace the "PDFKit newlines as hard breaks, geometry may only add more breaks"
model with **geometry-first row reconstruction**: build the page's words with their positions,
group words into row bands by vertical overlap, order bands top-to-bottom and words within a band
left-to-right, and emit one line per band. The PDF text layer's own newlines carry **no**
authority; they are used only to bound words, never to bound rows.

**Rationale.**

- `lineRanges(on:)` today walks the page string in text-layer order and can only ever *append* a
  break (`ranges.append(...)` at a band change). That is structurally a one-way valve: FR-002
  cannot be satisfied by adding a rule to it.
- Ignoring text-layer newlines makes the two hazards *the same problem*. A row the text layer
  merged occupies two bands and is split; columns the text layer split occupy one band and are
  joined. FR-030 ("both hazards in one document, resolved in one pass") falls out of the
  algorithm rather than needing a second mechanism.
- It is exactly what the web engine's extractor (pdfplumber) does, which is what the ten readers
  were fixture-locked against.

**Alternatives rejected.**

- *Keep newlines, add a "join amount-only lines to the nearest date line" heuristic.* Rejected:
  it is a per-symptom patch that cannot know which row an amount belongs to (the reference set has
  files with **zero** date-bearing lines — IOB card, HDFC card), and it would fabricate rows,
  violating FR-006/SC-003.
- *Glyph-level grouping.* Rejected by measurement recorded in the spec's Assumptions: PDFKit
  returns stray far-off rects for the trailing glyphs of a drawn run, and glyph granularity was
  verified to produce scrambled output. **Words are atomic** — a constraint, not a choice.

---

## R2 — A word is a maximal non-separator run of the page string, anchored on its glyph extents

**Decision.** A *word* is a maximal run of non-separator UTF-16 units in `page.string`
(`isSeparator` = `unit <= 0x20 || unit == 0x00A0`, as today). Its geometry is the union of the
usable `characterBounds` of its glyphs: `xMin` from the first usable glyph, `xMax` from the last,
`yMin`/`yMax` from the union of all usable glyph extents. A word with **no** usable glyph is
carried in text-layer order (see R6) rather than dropped — FR-007 forbids losing content.

**Rationale.** This preserves the two properties the current code documents as making the geometry
pass safe on real documents: words are never split across rows, and a row band only ever grows by
glyphs already inside it. It also keeps intra-word spacing untouched, which matters for the
whitespace-artefact markers (`WithdrawalAmt`, `Statementof account`) discussed in R7.

**Alternatives rejected.** Using `page.selection(for:)` line rects: PDFKit derives those from the
same inferred line breaks that are the bug.

---

## R3 — Row membership is vertical-overlap clustering with a bounded band, seeded left-to-right

**Decision.** Sort words by `(-yMax, xMin, textIndex)`; sweep, assigning each word to the current
band if `sharesARow(word.yExtent, band)` (the existing overlap-by-a-quarter-of-the-shorter test),
otherwise starting a new band. A band's extent is the union of its members, **capped**: a band may
not grow beyond `2.0 ×` the median word height on the page. A word that would exceed the cap
starts a new band.

**Rationale.**

- The `sharesARow` predicate already ships and is documented against real mixed-glyph-height rows
  (a comma and a capital on one row have very different midpoints — hence overlap, not centres).
- The cap is what stops FR-006's failure mode: a single tall glyph (a bracket, a rule, a logo
  fragment) otherwise stretches a band until it swallows the row below.
- Sorting by `-yMax` first makes reading order top-down; `xMin` then `textIndex` gives a **total**
  order, which is what FR-009/SC-007 (byte-identical on re-import) requires. No floating-point
  accumulation is involved — only comparisons of values PDFKit returns verbatim.

**Alternatives rejected.**

- *Cluster by row pitch (leading) detection.* Rejected: the spec's edge case "a row whose columns
  are further apart than the gap between two adjacent rows" means pitch and overlap can disagree,
  and pitch estimation is data-dependent, so it would make the outcome vary with content.
- *k-means / DBSCAN over y.* Rejected: non-deterministic seeding, and no simpler than the sweep.

---

## R4 — Unrelated blocks sharing a band: page zoning by full-height gutters, then anchored regexes

**Decision.** Before banding, split the page into **vertical zones** separated by *full-height
gutters* — x-intervals at least `4 ×` the median space width that no word on the page overlaps.
Band words within each zone independently, and emit zones left-to-right, each zone's bands
top-to-bottom. If exactly one zone is found (the overwhelmingly common case), this is a no-op.

Beyond that, rely on the readers' **anchored** row regexes as the second line of defence: every
card row pattern is `^date … amount (Dr|Cr)$` (see `yes.rs`, `iob.rs`), so a band polluted by an
unrelated block fails to match and the row is *lost*, never *invented*.

**Rationale.** FR-006 forbids fabrication; FR-010 says an untrustworthy page must risk reading
too little rather than placing a figure in the wrong row. Zoning handles the spec's "two
side-by-side panels" and "address block beside a summary box" cases where a real gutter exists;
anchoring handles the rest by failing closed. Together they make over-joining a non-event for
money correctness (SC-003).

**Alternatives rejected.**

- *Full recursive XY-cut.* Rejected: unbounded recursion over a 42-page statement is both a
  performance risk (SC-008) and a correctness risk — a transaction table's own column gaps are
  full-height gutters, and cutting there would re-create the column-major bug we are fixing.
  One level, page-wide only, is the safe subset.
- *Region-of-interest detection (find the transaction table, ignore the rest).* Rejected: it needs
  per-issuer knowledge, which contradicts the spec's "the bug is structural, not per-issuer".

---

## R5 — Exactly one U+0020 between words in a reconstructed line

**Decision.** Join a band's words with a single space. Never zero, never proportional padding.
Trailing separators are trimmed (as today).

**Rationale.** FR-005 requires two adjacent column values to stay separable; a single space
guarantees it, and every reader's regex uses `\s+` between fields, so a single space is the
canonical separator they already accept. Column-proportional padding was considered and rejected:
it makes output depend on font metrics, which breaks FR-009 determinism guarantees across PDFKit
versions and makes the golden `lines` unstable. Round-tripping the slice-016 fidelity fixtures
(whose synthetic lines are single-spaced) then reproduces the source lines **exactly**, which is
what keeps FR-028 green with unmodified expectations.

---

## R6 — Untrusted geometry falls back per page, not per document

**Decision.** Keep the existing guards (`page.numberOfCharacters == units.count`, at least one
usable glyph extent) and, on failure, fall back for **that page only** to
`PDFKitStatementTextExtractor.split(page.string)` — the text layer's own newlines, unreshaped.
A page in fallback contributes **no** `lineWords` entries.

**Rationale.** FR-010 demands a defined, documented fallback that risks reading too little. A
per-page fallback loses at most one page of a 42-page statement instead of the whole document,
and it is already the shape of the shipped code. Words with no usable glyph (R2) are appended to
the band of the nearest preceding word in text order, preserving FR-007 without inventing a
position.

---

## R7 — Recognition matches whitespace-insensitively, against an identity region, not the whole document

**Decision.** Two changes to claim matching, both inside `kaname-core`:

1. **Whitespace-insensitive comparison.** Normalize haystack and marker identically before
   `contains`: lowercase, then remove **all** Unicode whitespace. `"Statement of Transactions"`
   → `"statementoftransactions"`; the document's `"Statementof  account"` →
   `"statementofaccount"`, which the marker `"Statementof account"` also normalizes to.
2. **Identity region, not full text.** Claim markers are matched against the document text with
   *row-like* lines removed — a line is row-like if it contains a date in either supported shape
   (`DD/MM/YYYY`, `DD-MMM-YYYY`, `DD/MM/YY`) **and** a `[\d,]+\.\d{2}` amount. The remaining text
   (headers, footers, summary blocks, addresses) is the identity region.

**Rationale.**

- (1) is FR-012, and it is a *correctness* fix, not a convenience: two of HDFC's shipped markers
  (`"WithdrawalAmt"`, `"Statementof account"`) already have their spaces missing because they were
  captured from a *different* extractor's spacing. Matching literals against whatever spacing an
  extractor happens to produce is the wrong contract, and reshaping the text would otherwise turn
  eleven of thirteen reference documents into "not recognised" (the prototype's measured outcome).
- (2) is the answer to the spec's evidenced false-claim hazard: `AU-statment-savings.pdf` contains
  the literal `HDFC` **inside a UPI transaction description**, and `hdfc_bank.rs`'s `CLAIM_ALL` is
  exactly `["HDFC"]` matched anywhere in the document. Whitespace-insensitivity widens every such
  match at once (FR-014), so it must not ship without narrowing the scope. Removing transaction
  rows from the identity text removes the entire class: a bank named inside a merchant description
  can no longer identify the statement.

**Risk and its control.** Narrowing scope could in principle drop a marker that only ever appears
inside a row-like line. Nothing in the registry looks like that (every marker is a bank name, a
URL, or a header phrase), and the eighteen golden vectors in `fixtures/` plus
`core/crates/kaname-core/tests/dispatcher.rs` assert issuer resolution for every one of them —
that suite is the FR-013 gate and must pass unchanged.

**Alternatives rejected.**

- *Normalize runs of whitespace to a single space (instead of removing it).* Rejected: it does not
  match `"WithdrawalAmt"` against a document that prints `Withdrawal Amt.`, which Q2 measured as
  one of the two markers that rescue `HDFC-savings.pdf`.
- *Keep whole-document matching and rely on tests.* Rejected: the AU/HDFC collision is one
  `CLAIM_ANY` coincidence away from importing a person's statement under another bank's identity —
  strictly worse than not recognising it (spec, Q4 risk note).
- *Match only the first N lines.* Rejected: footers legitimately carry markers (`iobnet.co.in`),
  and N is a magic number that varies with layout.

---

## R8 — Card products: rename the six entries, declare each claim's evidence, resolve by specificity

**Decision.** `ReaderEntry` gains one field, `evidence: ClaimEvidence` (`ProductProven` |
`BankLevel`), and the six card entries are renamed per the spec's future-state table. `bank_code`
becomes the bare institution everywhere — including the defect `sbi.rs::BANK_CODE = "SBI_CARD"`
→ `"SBI"` (FR-053). `detect_issuer`'s ordering key becomes
`(kind_rank, evidence_rank, id)` with `ProductProven` ranking before `BankLevel` (FR-048).

Two mechanical tests ship with it:

- **FR-051 gate**: group credit-card entries by `bank_code`; if any group has more than one entry,
  every entry in it must be `ProductProven`. Adding a second HDFC card before a discriminator
  exists fails the build.
- **FR-048 gate**: no fixture may be claimed by two `ProductProven` card entries — a loud failure,
  never a silent tie-break.

**The consequential design point (spec Q1), decided.** An entry whose product the engine cannot
prove from the document — `ICICI_AMAZONPAY_CARD` (header reads only `CREDIT CARD STATEMENT`) and
`SBI_CASHBACK_CARD` (header names only `SBI Card`, card masked to two digits) — is declared
`BankLevel` and carries the product name **only as a display label**. Option (b), asking the
person to confirm the product at account creation, is rejected for this slice: it is UI, it is
absent from every FR and SC here, and FR-051 already makes the unsafe case (a second card from the
same bank) impossible to add without evidence.

**Product-proven claims read the header region only** (FR-044/FR-047). `HDFC_SWIGGY_CARD` may
claim on its own title text (`Swiggy HDFC Bank Credit Card Statement`) but MUST NOT match
`Swiggy` in the ~40 transaction descriptions where its holder shops. The identity region from R7
already excludes row-like lines; product markers additionally match only the identity region's
**first 15 lines** (the title/account block), a bound recorded in the contract and asserted by a
fixture whose transaction rows are stuffed with rival product names.

**Alternatives rejected.** Folding the product into `bank_code` (rejected on modelling grounds by
FR-046 — "which institution" and "which product" are different questions, and `FEDERAL_BANK` /
`FEDERAL_SCAPIA_CARD` deliberately share `FEDERAL`). Adding an enum of products (rejected: the
registry is a static table precisely so an eleventh issuer costs zero app lines).

---

## R9 — Persisting the registry id on accounts/statements: **deferred, explicitly**

**Decision.** Not taken in this slice. No schema change; the store stays at **v6**.

**Rationale.** The spec asks planning to price this rather than let it pass unnoticed. It buys
nothing this slice must deliver: two HDFC cards are already distinct accounts (`bank_code` +
`last4`), no FR or SC here depends on naming a product after import, and the value only appears
alongside UI that displays it. The migration cost does not grow until first release — the app is
unreleased, so the column is exactly as free to add in the UI slice that needs it as it is today.
Against that, an `ALTER TABLE` on the encrypted store is the one change class that can lose a
person's data, and this is an extraction slice.

**Recorded so it is not lost**: the follow-up is "persist `issuer_id` on `accounts` and
`statements` (schema v7) when a screen first names a card product". It MUST be taken before the
first release.

---

## R10 — FR-016 (cross-kind claims) ships as a test invariant, never as a runtime rule

**Decision.** Implement FR-016 as an assertion over the golden fixtures — no card entry claims a
bank-account fixture, no bank entry claims a credit-card fixture — and add **no** runtime guard.

**Rationale.** The spec downgrades FR-016 to "sound but unevidenced" after Q1's correction
(`SBI-bank.pdf` is a *card* statement, correctly claimed by a card reader) and warns that planning
MUST NOT let it cause a reader to decline a statement of its own kind — a failure worse than the
one it guards against. A test has exactly the desired asymmetry: it catches a regression, and it
can never decline a real document.

---

## R11 — `lineWords` for every line, not page 1 only

**Decision.** Emit `LineWords` for **every** reconstructed line on every page, indexed by the
line's position in `lines`. Bands in per-page fallback (R6) contribute no entry, keeping the
sparse-by-design contract.

**Rationale.** FR-011 requires the word positions to describe where values were printed *and* to
stay consistent with the rows they are reported against. Under R1 the positions are a byproduct of
reconstruction, so consistency is structural rather than maintained. The current page-1-only limit
exists because geometry was expensive to derive separately; it also silently degrades the ledger
row-1 bootstrap to `Row1Provisional` whenever the first anchor row is not on page 1 (US3 scenario
3). Cost is bounded — a 42-page statement is ~2,000 lines × ~12 words ≈ 1 MB across the FFI,
crossed once per import, and is verified against SC-008 by the performance task.

---

## R12 — Geometry fixtures are *generated from a layout signature*, and their non-vacuity is asserted forever

**Decision.** Add a committed, synthetic fixture family `fixtures/geometry/<issuer>.json`
(schema in [`contracts/geometry-fixture.md`](./contracts/geometry-fixture.md)): column x-positions,
row pitch, per-column cell content, date format, header/footer lines, and the expected
transactions. A test-side renderer draws it to a real PDF **column-major** (all of column 1's
cells, then column 2's, …), which is what makes the platform text layer emit it column-major, and
the document is then run through the real extractor, the real dispatcher and the real reader.

Each vector asserts **three** things:

1. `detect_issuer` returns the expected issuer id.
2. The new extraction yields exactly the expected transactions (dates, exact decimals, directions,
   order, count).
3. **Non-vacuity (FR-037/SC-011)**: the *pre-slice* extraction of the same document — modelled
   permanently as `PDFKitStatementTextExtractor.split(fullText)`, i.e. the text layer's own
   newlines — yields **strictly fewer** transactions. A vector that passes both ways fails the
   suite.

**Rationale.** This is `docs/adr/0004`'s amended position ("a signature is a fixture *generator*"),
already validated end-to-end against a real Yes/Kiwi layout (35 column positions, 21.3 pt row
spacing, date shape `99/99/9999`) which reproduced this bug exactly: issuer `YES_CARD` recognised,
printed totals recovered, **0 of 4** rows read. Assertion 3 turns that one-time observation into a
standing gate, and it is the specific blind spot that let eighteen green fixtures coexist with
total failure on real statements — every existing fixture supplies pre-split `lines` and therefore
cannot exercise extraction at all.

**Privacy constraint carried into the tasks.** Header and marker literals in a generated fixture
come from the reader's **own published claim markers**, never harvested from a source document, and
every added file is reviewed for tokens lifted from a real statement (FR-039/SC-010).

**Alternatives rejected.** Committing a redacted real statement (rejected by the spec and by
Principle V — redaction is subtractive and can leave residue; generation is additive and synthetic
by construction). Hand-writing column-major `lines` arrays into the existing fixture format
(rejected: it would again test the readers while *assuming* the extraction that failed).

---

## R13 — The reference-set pass is a documented, human-run, local-only gate (spec Q3, Option A)

**Decision.** Add a skipped-by-default Swift Testing suite, `ReferenceSetVerification`, that runs
only when `KANAME_REFERENCE_DIR` is set, plus `make reference-check DIR=…`. For each PDF in the
directory it prints exactly two facts — the issuer display name and the transaction count — and
writes nothing anywhere. It never prints a line of statement text, a merchant, an amount, a date or
an account number, and it never writes to the store, a file, or the network. Its output is recorded
in the PR description as counts only, in the manner of slice 016's T123/T129.

**Rationale.** FR-040 and SC-002 need it; the constitution forbids the files ever entering the
repository; and only the real files can prove the synthetic geometry was reproduced faithfully
*enough*. Option B (synthetic fixtures alone) was rejected in the spec because a geometry fixture
that models the layout slightly wrong would pass while real statements still fail.

---

## R14 — Performance and responsiveness on a 42-page statement

**Decision.** Extraction stays inside the existing `ImportService` actor (off the main thread) with
a `Task.checkCancelled()` between pages. Per page, `characterBounds(at:)` is called at most once
per non-separator UTF-16 unit — the same call volume the shipped code already makes — and all
subsequent work is an in-memory sort. Accept the sort's `O(n log n)`; reject any per-word PDFKit
re-query.

**Rationale.** SC-008 requires a 40-page statement to extract and parse with the interface
responsive and cancellable within 2 s; the largest reference file is 42 pages / 100,792 characters.
The dominant cost is unchanged from the shipped extractor, so the risk is regression, not novelty —
hence a measurement task rather than a redesign.

---

## R15 — OPEN: the AU account-kind claim marker (spec Q4, Option A)

**Status: cannot be resolved from this repository. It blocks one task, not the slice.**

`au_bank.rs` has `CLAIM_ALL = ["aubank.in"]` (matches) and
`CLAIM_ANY = ["Savings Account", "Current Account"]` — and the spec records that **neither**
`CLAIM_ANY` entry appears in `AU-statment-savings.pdf`, exactly or whitespace-insensitively. So
unlike Q2's HDFC file, R7's whitespace tolerance does **not** rescue it; a marker the layout
actually prints must be added, and only a person holding the private file can read it.

**Procedure (recorded so the task is executable the moment the input exists).**

1. The holder of the reference set opens `AU-statment-savings.pdf`, reads its **header region**
   (the block naming the document and the account), and supplies the exact literal that states the
   account kind — e.g. the header phrase AU prints in place of `Savings Account`.
2. The literal is added to `au_bank::CLAIM_ANY`. It MUST be an account-kind or document-title
   phrase from the header, never a bare institution name (that is the R7 hazard) and never a token
   copied from a transaction row.
3. A synthetic AU geometry fixture carrying that header phrase (fabricated everything else) is
   added, and the cross-bank false-claim regression cases (below) must stay green.

**Regression cases this marker change MUST ship with (FR-014).** A synthetic statement for issuer
X whose transaction descriptions name issuer Y — modelled on the measured AU/HDFC case — asserted
to resolve to X, for every pair the registry can confuse. This is the most dangerous marker change
in the slice and does not land without them.

**If the literal is not supplied before implementation reaches it**, the AU marker task alone is
deferred; every other requirement in the slice is unaffected, and the outcome for that one
reference file is an honest "format not recognised yet" (FR-025), not a wrong import.

---

## R16 — Ordering constraint: recognition lands before reshaping

**Decision.** The engine's recognition change (R7, R8) MUST be merged **before** the platform's
extraction change (R1–R6, R11). Never the reverse, and never a `main` in between that has reshaped
text and literal markers.

**Rationale.** The prototype measured exactly that intermediate state: complete rows, and eleven of
thirteen documents suddenly unrecognised. Recognition-first is safe because whitespace-insensitive
matching over an identity region is a **superset** of today's matches for every shipped fixture
(proved by the unchanged `dispatcher.rs` + `parity.rs` suites), so the app is never worse at any
commit.

---

## Open items summary

| Item | Status | Blocks |
|---|---|---|
| R15 — AU account-kind claim marker | **OPEN**, needs the reference-set holder | One task (AU marker + its fixture). Nothing else. |
| R13 — reference-set verification pass | Human-run gate, cannot be closed by CI | Slice sign-off (SC-002), as slice 016's T123/T129 did |
| R9 — persist `issuer_id` (schema v7) | **Deferred by decision**, must land before first release | Nothing in this slice |
