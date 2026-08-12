# Phase 0 Research — Statement Import Vertical (`016-statement-import-vertical`)

**Date**: 2026-08-12 | **Branch**: `016-statement-import-vertical`
**Input**: [`spec.md`](./spec.md) (FINAL — its `## Clarifications` are settled constraints, not open questions)

All `NEEDS CLARIFICATION` markers raised in the Technical Context are resolved below. Every
decision cites evidence from the shipped source rather than assumption.

---

## R1 — The `Issuer` type crossing UniFFI: **record, not enum**

### Decision

```rust
/// The two statement shapes the engine reads. A CLOSED set (there is no third kind), so an
/// exhaustive Swift switch on it is safe and is NOT per-issuer branching.
#[derive(uniffi::Enum)] pub enum StatementKind { CreditCard, BankAccount }

/// Which reader produced / will produce a statement. An OPEN set — the app treats `id` as
/// opaque and renders `display_name` verbatim (FR-012, FR-033).
#[derive(uniffi::Record)] pub struct Issuer {
    pub id: String,           // stable reader identity, e.g. "ICICI_BANK"
    pub display_name: String, // user-facing, engine-owned, e.g. "ICICI Bank Account"
    pub bank_code: String,    // the code already persisted in accounts.bank_code, e.g. "ICICI"
    pub kind: StatementKind,
}
```

### Rationale

**A `uniffi::Enum` is the wrong shape, for three independent reasons.**

1. **It hands the app the branch the spec forbids.** UniFFI lowers a Rust enum to a Swift
   `enum`, which Swift lets you `switch` over exhaustively. FR-012 says the app must contain
   "no list of banks, no per-bank branch, no per-bank string literal". A Swift enum makes the
   forbidden thing the *most natural* thing to write. A record with an opaque `id` makes it
   awkward — the shape of the type should enforce the rule.
2. **It cannot carry a display name.** FR-033/FR-034 make the issuer name *user-facing data
   the engine supplies*; the app has no string table. A bare enum would need a companion
   `issuer_display_name(Issuer) -> String` lookup — two calls and two things to keep in sync.
   A record carries the name with the value.
3. **It breaks SC-010 (add an issuer, change zero app lines).** Adding an enum case is a
   source-breaking change for any exhaustive Swift `switch` — including in *tests*. A record
   grows without breaking anything.

**Reader identity ≠ bank identity — `bank_code` is not unique.** This is the finding that
forces `id` to exist as a separate field. From the shipped readers:

| `BANK_CODE` | Card reader | Ledger reader |
|---|---|---|
| `ICICI` | `icici.rs:17` | `icici_bank.rs:20` |
| `HDFC` | `hdfc.rs:24` | `hdfc_bank.rs:27` |
| `FEDERAL` | `federal.rs:21` (Scapia) | `federal_bank.rs:29` |
| `SBI_CARD`, `YES`, `IOB` | card only | — |
| `AU` | — | `au_bank.rs:24` |

Three bank codes are shared by two readers each. A dispatcher keyed on `bank_code` alone
could not choose a reader. So the engine's identity is `(bank_code, kind)`, surfaced as a
stable `id`. `bank_code` is retained as a separate field because the store already persists
it (`accounts.bank_code`, `statements.bank_code`) and `source_category_map` joins on it.

### The registry (10 entries)

| `id` | `bank_code` | `kind` | proposed `display_name` |
|---|---|---|---|
| `AU_BANK` | `AU` | BankAccount | AU Small Finance Bank Account |
| `FEDERAL_BANK` | `FEDERAL` | BankAccount | Federal Bank Account |
| `HDFC_BANK` | `HDFC` | BankAccount | HDFC Bank Account |
| `ICICI_BANK` | `ICICI` | BankAccount | ICICI Bank Account |
| `FEDERAL_CARD` | `FEDERAL` | CreditCard | Scapia Credit Card |
| `HDFC_CARD` | `HDFC` | CreditCard | HDFC Bank Credit Card |
| `ICICI_CARD` | `ICICI` | CreditCard | ICICI Bank Credit Card |
| `IOB_CARD` | `IOB` | CreditCard | Indian Overseas Bank Credit Card |
| `SBI_CARD` | `SBI_CARD` | CreditCard | SBI Card |
| `YES_CARD` | `YES` | CreditCard | Kiwi (YES Bank) Credit Card |

> **✅ Confirmed by the product owner (2026-08-12)** — the ten `display_name` strings are
> user-facing brand copy and were reviewed and approved. The two co-brands were corrected from
> the initial proposal: `FEDERAL_CARD` is **"Scapia Credit Card"** (not "Scapia Federal Credit
> Card") and `YES_CARD` is **"Kiwi (YES Bank) Credit Card"** (not "YES Bank Credit Card"),
> matching how cardholders actually refer to them. Implement this table verbatim.

### Alternatives considered

- **`uniffi::Enum` + `issuer_display_name()` lookup** — rejected: invites the forbidden
  branch, splits the value from its name, and breaks SC-010.
- **Opaque `String` id only** — rejected: the app then needs a name from *somewhere*, and the
  only somewhere left is an app-side string table (a direct FR-012 violation).
- **`uniffi::Object` (an interface)** — rejected: needlessly stateful for four immutable
  fields, and objects cannot be cheaply value-compared in Swift tests.

---

## R2 — Dispatcher entry points

### Decision — two exported functions, exactly as FR-010/FR-011 require

```rust
/// FR-010. `None` = no reader claims this document (the "not recognized yet" path, FR-013).
#[uniffi::export]
pub fn detect_issuer(full_text: String) -> Option<Issuer>;

/// FR-011. The single parse entry point. `line_words` is optional geometry (see R5);
/// pass an empty vec when unavailable.
#[uniffi::export]
pub fn read_statement(
    issuer: Issuer,
    lines: Vec<String>,
    full_text: String,
    line_words: Vec<LineWords>,
) -> Result<ParsedStatement, ReaderError>;

#[derive(uniffi::Error)] pub enum ReaderError {
    /// The `Issuer.id` does not match any reader in the registry.
    UnknownIssuer { id: String },
}
```

Both are backed by one private, static registry in a new
`core/crates/kaname-core/src/statement/registry.rs`:

```rust
struct ReaderEntry {
    id: &'static str,
    display_name: &'static str,
    bank_code: &'static str,
    kind: StatementKind,
    claims: fn(&str) -> bool,
    read: fn(&[String], &str, &[LineWords]) -> ParsedStatement,
}
static REGISTRY: &[ReaderEntry] = &[ /* the 10 entries of R1 */ ];
```

### Rationale

- **Two calls, not one.** FR-010 and FR-011 each specify a distinct capability ("a single
  issuer-detection capability", "a single parse capability"). A single fused
  `detect_and_read()` would be fewer moving parts but would collapse two spec'd requirements
  and would make the "detected but the person cancelled before parsing" cancellation
  checkpoint (FR-038) impossible to express.
- **`Result`, not `Option`, on the parse.** `Option<ParsedStatement>` would overload `None`
  with "unknown issuer", while `Some(empty statement)` is a *legitimate successful* outcome
  (FR-020: zero transactions is a success). A typed error keeps those unambiguous, matches
  the precedent already set by `StoreError` (`store.rs:173`), and surfaces in Swift as a
  throwing call. `ReaderError::UnknownIssuer` is a programmer error, never rendered to a
  person (FR-034).
- **The ten existing `read_*_statement` / `*_claims` exports stay.** They are parity-locked
  and exercised by ten Swift test suites (`ios/Tests/*ParseTests.swift`). The dispatcher is
  *additive*; it calls the same `read_lines` / `read_ledger_lines` seams. Nothing is rebuilt.
- **No `supported_issuers()` export.** The app must never enumerate banks (FR-012), so
  handing it a list would be handing it the rope. Exhaustiveness is tested in Rust, where the
  registry lives.

---

## R3 — The deterministic tie-break (FR-014) — **`(kind_rank, id)` ascending, ledger first**

### Decision

`detect_issuer` collects **every** registry entry whose `claims` returns `true`, then returns
the minimum under the total order:

```text
key(entry) = (kind_rank(entry.kind), entry.id)
kind_rank(BankAccount) = 0
kind_rank(CreditCard)  = 1
```

i.e. **a bank-ledger reader always beats a credit-card reader; within a kind, the
lexicographically smallest `id` wins.** No document content, no marker counts, no registry
position participates in the decision.

### Rationale — this is not hypothetical; it fires on 3 of the 13 shipped fixtures today

Replaying the exact `claims` / `claims_ledger` predicates (case-insensitive substring;
`line_reader.rs:36`, `ledger_reader.rs:93`) over every committed golden fixture:

```text
AMBIG fixtures/federal/bank_account/classic.json : [FEDERAL_CARD, FEDERAL_BANK]
AMBIG fixtures/federal/bank_account/fi.json      : [FEDERAL_CARD, FEDERAL_BANK]
AMBIG fixtures/icici/bank_account/basic.json     : [ICICI_CARD,   ICICI_BANK]

13 statement fixtures, 3 not-exactly-one-claimant, 0 claimed by none
```

The cause is structural, not accidental:

- `icici.rs:33` — the card reader claims on the single marker `"ICICI Bank"`, which appears
  in the letterhead of an ICICI *bank-account* statement too.
- `federal.rs:38` — the card reader claims on `"Scapia"` **or** `"Federal Bank"`; the second
  matches every Federal Bank ledger statement.
- Card claims are **disjunctive** (`claim_markers` — *any* marker,
  `line_reader.rs:41-43`). Ledger claims are **conjunctive** (`claim_all` — *all* markers,
  plus an optional `claim_any`, `ledger_reader.rs:96-110`).

In all three collisions the **ledger** reader is the correct answer, and in all three the two
candidates share a `bank_code`. "Ledger before card" therefore picks correctly in 3/3 observed
cases, and its justification is principled rather than fitted: **a conjunctive claim is
strictly stronger evidence than a disjunctive one**, so when both fire the conjunctive one is
the better-supported reading.

### Why the order is *stable*

1. **Total** — `id` is unique across the registry, so no two entries ever tie. The function is
   total and single-valued.
2. **Content-independent** — the key is derived only from the reader's own identity. The same
   candidate set always yields the same winner regardless of the document, satisfying FR-015
   directly.
3. **Monotone under registry growth** — adding an 11th reader cannot reorder any existing
   pair, because the key of an existing entry does not depend on the set. A new reader can
   only win over an incumbent on documents *it also claims*, and a cross-issuer double claim
   is a reader-authoring bug, which the guard test below catches at `cargo test` time.
4. **Guarded** — a new parity test asserts that every golden fixture's `full_text` resolves
   through `detect_issuer` to its expected issuer `id`. That is precisely the test that would
   have caught today's three collisions, and it is the SC-002 (100% attribution) gate.

### Alternatives considered

- **Score by number of matched claim markers, highest wins.** Rejected: marker counts are
  authoring artifacts, not evidence strength — a sloppy reader with five loose markers would
  beat a precise one with a single tight marker, and the winner would silently change when a
  marker is added for an unrelated reason. It also happens to give the right answer on today's
  three cases, which makes it *seductive and fragile*.
- **First match wins over an explicitly ordered registry array.** Rejected: correctness then
  lives in the source ordering of a list — an invisible global that a well-meaning
  alphabetical re-sort silently breaks, with no compile error and no obvious test failure.
- **Parse with every candidate and pick the highest `confidence`.** Rejected on three counts:
  it costs N parses, `confidence` is a `f64` that can tie (reintroducing the problem), and it
  materialises the losing candidates' parses, which FR-014 explicitly wants never to happen.
- **Ask the person.** Rejected by the spec's Clarifications: the engine tie-breaks; the app
  never asks (FR-014).

---

## R4 — Surfacing the statement **kind**

### Decision

`StatementKind` rides on `Issuer` (R1) and drives exactly two things in the app:

| `Issuer.kind` | Integrity check (FR-016) | `accounts.is_credit_card` (FR-023) |
|---|---|---|
| `BankAccount` | `check_balance_chain(parsed) -> ChainResult` | `false` |
| `CreditCard` | `reconcile_statement(parsed) -> ReconcileResult` | `true` |

Both check functions are already exported (`ffi.rs`) and parity-locked. Nothing new is built.

### Rationale

- The kind must be known **before** the parse, because it selects which of two differently
  typed results the app asks for. Deriving it *after* the parse (e.g. "does row 0 have
  `ledger` metadata?") would be inference from a nullable field and would misfire on an empty
  statement (FR-020).
- Putting it on `Issuer` means the one value the app already holds answers it, with no second
  call and no second source of truth.
- **A two-variant closed enum is safe to switch on.** FR-012 forbids per-*issuer* branching,
  not all branching. There will only ever be "card" and "ledger"; the app must treat them
  differently because the two integrity checks return different types. A new *bank* still
  requires zero app changes (SC-010) — only a hypothetical new *statement shape* would, and
  that is a genuine new capability, not a new issuer.

### Integrity outcome → plain language (FR-017)

Three states, and the third must not be collapsed into either of the other two:

| Engine result | Person sees |
|---|---|
| `ChainStatus::Reconciled` / `ReconcileStatus::Reconciled` | "The figures on this statement add up." |
| `…::NeedsReview` | "Some figures on this statement didn't add up — you may want to check these transactions." + statement flagged `needs_review` (FR-019) |
| `ReconcileStatus::None` (statement prints no totals) | **nothing** — neither a pass nor a fail (FR-017, US5 §3) |

---

## R5 — Absorbing the `first_row_words` asymmetry **without teaching the app about banks**

### The problem

Ledger readers take `first_row_words: Vec<Word>`; card readers take only `(lines, full_text)`.
Worse, the geometry the ledger reader wants is that of **"the first anchor row"** — a row only
the reader can identify (`ledger_reader.rs:135`, `find_anchors`). If the unified entry point
just forwarded a `first_row_words` the *app* had to pick, the app would need reader knowledge
to pick it, violating FR-012.

### Decision

The unified entry point takes **line-indexed geometry for as many lines as the platform can
cheaply supply**, and the *dispatcher* — which knows the reader — selects the row:

```rust
/// Word geometry for one extracted line, keyed by its index in `lines`. Sparse: the platform
/// supplies what it has (typically page 1); an absent index simply has no geometry.
#[derive(uniffi::Record)] pub struct LineWords { pub line_index: u32, pub words: Vec<Word> }
```

Dispatch behaviour:

- **`CreditCard` entry** → ignores `line_words` entirely, calls `read_lines(cfg, &lines, &full_text)`.
- **`BankAccount` entry** → resolves the anchor itself and forwards only that row's words:
  ```rust
  let words = first_anchor_index(cfg, &lines)
      .and_then(|i| line_words.iter().find(|lw| lw.line_index as usize == i))
      .map(|lw| lw.words.clone())
      .unwrap_or_default();
  read_ledger_lines(cfg, &lines, &full_text, &words)
  ```

This needs **one small additive helper** in `ledger_reader.rs` — no change to
`read_ledger_lines`, no change to any of the four `LedgerReaderConfig` impls, no change to the
parity-locked behaviour:

```rust
/// Index in `lines` of the first row the ledger reader will anchor on, if any.
pub(crate) fn first_anchor_index<C: LedgerReaderConfig + ?Sized>(
    cfg: &C, lines: &[String],
) -> Option<usize> {
    find_anchors(cfg, lines).0.first().map(|a| a.index)
}
```

### Rationale

- **The app stays bank-agnostic.** It extracts geometry for every line it can and never learns
  which one mattered. That is the whole point of the slice.
- **Strictly better than the shipped seam.** The existing `first_row_words` parameter silently
  assumes the caller can identify the anchor row; nothing in the ten shipped fixtures exercises
  it (`first_row_words` is absent from all 13 fixture files), so this asymmetry has never been
  paid for. This slice is the first caller that has to.
- **Additive, not a rebuild.** `find_anchors` already exists and is deterministic, so calling
  it once more costs a linear regex pass over the lines and cannot change any outcome. The ten
  existing `read_*_statement` exports and their Swift tests are untouched.
- **Degrades honestly.** When geometry is missing or the anchor has no matching entry,
  `first_row_words` is empty — exactly the documented "pass an empty list when unavailable"
  path. Row 1 then falls back to `DirectionSource::Row1Provisional`, which forces
  `check_balance_chain` to `NeedsReview` (`base.rs:33-35`), which the app surfaces as the
  plain-language warning of FR-017 and records via `needs_review` (FR-019). A missing
  measurement can never become a *confidently wrong* direction.

### Alternatives considered

- **Always pass `[]`.** Rejected: every bank statement without a printed opening balance would
  be permanently flagged needs-review, degrading trust for a whole class of real statements
  when the geometry is right there in the PDF.
- **Change `read_ledger_lines` to take `&[LineWords]`.** Rejected: a wider change to a
  parity-locked signature, for no behavioural gain over the additive helper.
- **A second FFI call `first_anchor_index(issuer, lines) -> Option<u32>` so the app can pick.**
  Rejected: three round trips and it puts the reader's internal notion of "anchor" on the
  public surface.

---

## R6 — Persisting the import: is a **schema v6** needed?

### Decision — **yes, but a minimal one: exactly one `ADD COLUMN`.**

```sql
-- Forward-only schema v6: account identity carries the masked account/card tail.
ALTER TABLE accounts ADD COLUMN last4 TEXT;
```

### Evidence

**FR-026's "record of the import" is already covered by schema v5 — no change needed there.**
`SCHEMA_V5` (`store.rs:146-166`) created:

```sql
CREATE TABLE statements (
    id, account_id, bank_code, period_start, period_end NOT NULL,
    needs_review, source, created_at
) STRICT;
ALTER TABLE transactions ADD COLUMN statement_id TEXT REFERENCES statements(id);
```

Mapping FR-026 onto it, field for field: *account* → `account_id`; *issuer* → `bank_code`;
*statement period* → `period_start` / `period_end`; *needs-review* → `needs_review`. The
`NewStatement` / `StoredStatement` records and `insert_statement` / `list_statements`
(`store.rs:253-278`, `458-493`) are already exported. **Nothing about the import record itself
requires a migration.**

**But account identity does.** FR-021 and FR-024 both key on *issuer + last-4*, and
`accounts` (`SCHEMA_V1`, `store.rs:56-64`) is `id, name, bank_code, is_credit_card, currency,
created_at, updated_at` — **there is no `last4` column**, and neither `NewAccount` nor
`StoredAccount` has the field (`store.rs:218-241`; a repo-wide grep for `last4`/`last_4` in
`store.rs` returns nothing). Today the only place a last-4 could live is inside `accounts.name`
— a *display* string. Matching accounts by substring-searching a display string is exactly the
kind of silent-mis-attribution bug that FR-021/FR-024 exist to prevent, and the spec's Key
Entities list "last-4 where known" and "display name" as **separate** account attributes.

The migration is a constant-default `ADD COLUMN`, which runs on a populated table — the same
shape as the shipped v2, v3 and v4 migrations (`store.rs:96, 124, 134`) — so it slots into the
existing forward-only `PRAGMA user_version` runner (`store.rs:887-905`, `apply_migration` at
`907`) with a `6 => { tx.execute_batch(SCHEMA_V6) }` arm and a
`migrating_v5_to_v6_preserves_existing_rows` test mirroring the four that already exist.

### The `period_end NOT NULL` question — **deliberately left alone**

`statements.period_end` is `NOT NULL`, but the spec's Edge Cases require "a statement whose
period cannot be recovered … must omit the period rather than invent or approximate one".
Resolution, without a migration:

| Case | Behaviour |
|---|---|
| Period recovered (**all 13 golden fixtures**) | Store `period_start` (nullable — already `None` for `icici/credit_card` and `iob/credit_card`) and `period_end`; show the period. |
| No `period_end`, but transactions parsed | Store `period_end` = max parsed `value_date`, `period_start` = `NULL`. **The summary omits the period**, because the app knows `parsed.period_end == nil`. |
| No `period_end` **and** zero transactions | Write **no** `statements` row and no transactions; report a successful import of 0 transactions (FR-020). |

Rationale: the spec's constraint is on *what the person is shown*, not on what is stored. The
derived `period_end` is not a fabrication — it is a month the statement demonstrably contains
rows in, which is exactly the fact `coverage` consumes (`load_statement_coverage`,
`store.rs:1135-1156`). The alternative — making `period_end` nullable — cannot be done with an
`ALTER TABLE` in SQLite; it needs a full 12-step table rebuild, and because
`transactions.statement_id` references `statements(id)` and `PRAGMA foreign_keys` is enabled
(`store.rs:403`), the `DROP TABLE` would have to run with foreign keys **off** — which is a
no-op inside a transaction, so the shared `migrate()` runner itself would have to be
restructured. That is a large, FK-weakening change to the one piece of code that must never
lose data, bought for an edge case no fixture exercises.

> **⚠ Judgement call for the product owner** — the third row (no period *and* no
> transactions ⇒ no `statements` row) is the one place this plan does not write an import
> record. There is nothing to attribute it to and writing an unattributable row would corrupt
> the coverage map. Confirm, or accept the table rebuild as a follow-up slice.

---

## R7 — Atomicity: a new **transactional** store entry point (FR-031, SC-006)

### Decision

```rust
#[uniffi::export] impl Store {
    /// Persist one import run atomically: resolve-or-create the account, write the statement
    /// record, insert every transaction, categorize, and link duplicates — all inside ONE
    /// SQLite transaction. Either every row lands or none does.
    pub fn import_statement(&self, request: ImportRequest) -> Result<ImportOutcome, StoreError>;
}
```

### Rationale

- **The app physically cannot do this itself.** The `Connection` is owned by the Rust `Store`
  behind a `Mutex` (`store.rs:357-359`); Swift has no way to open a transaction across the
  bridge. Today `insert_account`, `insert_statement` and `insert_transaction` each
  auto-commit independently (`store.rs:413, 458, 497`), so a failure after row 40 of 200
  leaves an orphan account, an orphan statement record, and 40 stray transactions. That
  directly violates FR-031 and SC-006 ("byte-identical to its pre-import state").
- **It also delivers three other requirements for free**: the duplicates-skipped count
  (FR-025) and the categorized/uncategorized split (FR-030) come back in the same
  `ImportOutcome`, and the whole write becomes a single cancellation boundary (FR-038).
- This is a **store API addition, not a schema change** — v6 is still just the one `ADD COLUMN`.

### ⚠ Implementation hazard: `std::sync::Mutex` is not reentrant

`categorize_account` (`store.rs:656`) and `find_duplicates` (`store.rs:785`) both call
`self.lock()`. If `import_statement` holds the lock and calls either public method, the thread
**deadlocks** — silently, and only on the happy path with a real import. The refactor is
therefore mandatory, not cosmetic:

```rust
fn categorize_account_in(tx: &rusqlite::Transaction<'_>, account_id: &str) -> Result<CategorizeSummary, StoreError>;
fn find_duplicates_in(tx: &rusqlite::Transaction<'_>) -> Result<DedupSummary, StoreError>;
```

The two existing public methods become thin wrappers (`lock` → `transaction` → `*_in` →
`commit`), preserving their behaviour and their shipped tests (`ios/Tests/StoreTests.swift`,
`core/.../tests/store*.rs`), and `import_statement` calls the `_in` forms on its own `tx`.

### Account resolution stays in Swift — and that is still bank-agnostic

FR-024's "no last-4 recovered" path needs a **human decision** when zero or ≥2 candidate
accounts exist, so the candidate set has to be visible to the UI. The app therefore calls
`list_accounts()` and filters on `bank_code == issuer.bankCode && isCreditCard == (issuer.kind == .creditCard) && last4 == parsed.cardLast4`. Comparing two values the engine handed it is *data
comparison*, not per-issuer branching — the app still contains no bank name and no bank list.
`ImportRequest` then carries the resolved outcome:

```rust
#[derive(uniffi::Enum)] pub enum ImportAccountTarget {
    Existing { id: String },
    New { name: String, bank_code: String, is_credit_card: bool, last4: Option<String>, currency: String },
}
```

---

## R8 — The PDFKit extraction seam

### Decision

A protocol + one concrete implementation in a new `ios/Sources/Import/`:

```swift
protocol StatementTextExtractor {
    func extract(from url: URL, password: String?) throws -> ExtractedText
}
struct ExtractedText { let lines: [String]; let fullText: String; let lineWords: [LineWords] }
struct PDFKitStatementTextExtractor: StatementTextExtractor { … }
```

A protocol because the import pipeline must be testable without a real PDF, and because it is
the single place `import PDFKit` appears.

### Failure taxonomy — each maps to exactly one plain-language message (US3)

| Detection | `ExtractionFailure` | Person sees |
|---|---|---|
| `PDFDocument(url:)` returns `nil` | `.notAPDF` | "This file couldn't be opened as a PDF." (FR-009) |
| `doc.isLocked` after construction | `.passwordRequired` | password prompt (FR-007) |
| `doc.unlock(withPassword:)` returns `false` | `.wrongPassword` | "That password didn't work." + retry/cancel (FR-007) |
| Opens, but every page's text is empty/whitespace | `.noExtractableText` | "This looks like a scanned statement Kaname can't read yet." — **distinct** from unrecognized-issuer (FR-006) |
| `url.startAccessingSecurityScopedResource()` returns `false`, or a read throws | `.unreadable` | "Kaname couldn't read the file you picked." (FR-002, US3 §7) |

**Empty/owner-password PDFs**: PDFKit auto-unlocks a document whose user password is empty, so
`isEncrypted == true` but `isLocked == false`. Keying the prompt on **`isLocked`**, never on
`isEncrypted`, satisfies the "must be treated as openable rather than prompting pointlessly"
edge case for free.

**Security-scoped access**: `startAccessingSecurityScopedResource()` … `defer {
stopAccessingSecurityScopedResource() }` around the *entire* extraction, including the failure
and cancellation paths (FR-002). Extraction reads into memory; the file is never copied
(FR-004).

**Password lifetime (FR-008)**: the password is a `String` parameter passed down the call
stack to `unlock(withPassword:)` and never stored in a property, a `@State`, the Keychain, the
store, or a log. The prompt's binding is cleared in the sheet's `onDisappear`.

### Producing `lines`, `fullText`, `lineWords`

- `fullText` = concatenation of each `PDFPage.string`, page-separated by `\n`.
- `lines` = `fullText` split on newlines. This preserves the exact contract the ten shipped
  readers were written and fixture-locked against.
- `lineWords` = per line, whitespace-split into words; each word's character range is located
  within the page string and mapped through `PDFPage.characterBounds(at:)`, taking `minX` of
  the first character and `maxX` of the last → `Word(text:x0:x1:)`. Geometry is produced for
  **page 1 only** by default: it is the only page whose rows the ledger anchor bootstrap can
  need, and it bounds the cost on a 200-page statement (SC-008).
- **Known PDFKit hazard**: `PDFPage.string` indices and `characterBounds(at:)` indices can
  drift on documents with ligatures or unusual encodings. Mitigation: bounds-check every index
  and, on any mismatch for a line, emit **no** `LineWords` entry for that line rather than a
  wrong one. Per R5 that degrades to `Row1Provisional` → needs-review, never a wrong direction.

---

## R9 — Concurrency, cancellation and store-integrity boundaries

### Decision

```swift
actor ImportService {            // serializes; also enforces FR-032
    private var inFlight: Task<ImportSummary, Error>?
    func run(url: URL, password: String?) async throws -> ImportSummary
}
@MainActor @Observable final class ImportViewModel { … }   // UI state only
```

Every stage runs inside the actor (off the main thread, FR-036). The UI observes a
`@MainActor` view model; the only main-thread work is rendering.

### Cancellation checkpoints (FR-038, SC-008 "within 2 seconds")

`try Task.checkCancellation()` at each stage boundary:

```text
pick → [✓] extract → [✓] detectIssuer → [✓] readStatement → [✓] integrity check
     → [✓] resolve account → ██ import_statement (ATOMIC, uncancellable) ██ → summary
```

The only long stages are extraction and parsing; both precede the write. Once
`import_statement` is entered it runs as a single SQLite transaction — cancelling *inside* it
is meaningless because the transaction is all-or-nothing anyway, and it is the fastest stage.
So "cancel within 2s" is met by checkpointing the slow stages, and "no partial data" (FR-031)
is met by there being exactly one write and it being atomic.

### Store-integrity boundaries — the full failure matrix (SC-006)

| Failure | Where | Store after |
|---|---|---|
| Not a PDF / corrupt / locked / no text / unreadable | before any store call | untouched |
| No issuer claims it (FR-013) | before any store call | untouched |
| Cancelled at any checkpoint | before the write | untouched |
| `import_statement` fails mid-write (disk full, FK, corrupt row) | inside the transaction | **rolled back** by SQLite |
| `Store.open` fails (key ceremony / damaged DB) | before anything | untouched; shown as "Kaname couldn't open your data", never a raw `StoreError` (FR-034) |

### Backgrounding (US6 §4)

The `Task` is owned by the actor, not by a view, so a backgrounded app does not cancel it. On
return the view model reflects the terminal state it reached. No indefinite spinner: every
stage either advances, throws, or is cancelled.

---

## R10 — Money across the boundary

### Decision — already solved; this slice must only avoid breaking it

`rust_decimal::Decimal` → base-10 `String` (`uniffi::custom_type!`, `ffi.rs:35-40`) →
`Foundation.Decimal` in Swift (via `uniffi.toml`). Dates likewise cross as ISO-8601 strings
(`ffi.rs:43-47`). The store persists amounts as `TEXT` (`SCHEMA_V1`) and direction as
`'Debit'`/`'Credit'`, never a signed float (FR-028, FR-029).

Rules for this slice:

- **No `Double`, no `Float`, no `NSNumber` on the import path.** The one legitimate `f64` in
  the domain is `Word.x0`/`x1` — layout points, explicitly not money (`base.rs:38-41`) — and
  `ParsedStatement.confidence`.
- Display formatting via `Decimal.formatted(.currency(code: txn.currency))`; never
  `Double(decimal)`.
- A Swift test asserts a full round trip of `0`, `999999999999.99` and `0.000000001` through
  parse → `import_statement` → `list_transactions` with exact equality (the pattern already
  established in `ios/Tests/StoreTests.swift` / `KanameTests.swift`).

---

## R11 — Testing strategy

### Rust (`cargo test`) — TDD, RED → GREEN, all fixtures synthetic (FR-043, SC-011)

| Test | Proves |
|---|---|
| `registry_ids_are_unique_and_total` | the tie-break order is total (R3 §1) |
| `detect_issuer_resolves_every_golden_fixture_to_its_expected_issuer` | SC-002; **the guard that catches the 3 known collisions** |
| `detect_issuer_returns_none_for_an_unclaimed_document` | FR-013 |
| `ledger_beats_card_on_a_doubly_claimed_document` | FR-014 |
| `detect_issuer_is_deterministic_over_repeated_calls` | FR-015 |
| `read_statement_matches_the_legacy_per_bank_reader_byte_for_byte` (×10) | the dispatcher rebuilds nothing |
| `read_statement_rejects_an_unknown_issuer_id` | `ReaderError::UnknownIssuer` |
| `read_statement_ignores_line_words_for_card_issuers` | R5 |
| `read_statement_forwards_only_the_anchor_row_geometry` | R5 |
| `migrating_v5_to_v6_preserves_existing_rows` | v6 on a populated DB (mirrors the four shipped migration tests) |
| `import_statement_is_atomic_on_failure` | FR-031 / SC-006 — a forced mid-write failure leaves row counts and `user_version` unchanged |
| `import_statement_attaches_to_an_existing_account_by_issuer_and_last4` | FR-021 |
| `importing_the_same_statement_twice_does_not_double_history` | FR-025 / SC-005 |

### Swift Testing (`import Testing`, `@Test`) over the UniFFI bridge

- `ImportPipelineTests` — end-to-end against a temp SQLCipher DB: detect → read → integrity →
  `import_statement` → assert summary counts, exact `Decimal` equality, and persistence across
  a re-`open`.
- `StatementTextExtractorTests` — the five failure paths, against PDFs **generated in-test**
  with `UIGraphicsPDFRenderer` (text-bearing, image-only, password-protected, truncated bytes,
  a `.pdf`-named text file). Generated, not committed, so no binary fixtures and no chance of
  a real statement entering the repo.
- `ImportAccessibilityTests` / snapshot — largest Dynamic Type, Dark Mode, Reduce Transparency
  (FR-044, FR-046, SC-009).
- A message-audit test asserting no user-facing string in the flow contains an issuer *code*,
  a reader identifier, or `StoreError`/`ReaderError` text (FR-034, SC-007).

### ⚠ Build-ordering gotcha (HANDOFF §6)

This slice **changes the FFI surface** (`Issuer`, `StatementKind`, `LineWords`, `ReaderError`,
`detect_issuer`, `read_statement`, `import_statement`, `ImportRequest`, `ImportOutcome`,
`NewAccount.last4`). Therefore `make core-xcframework` **must** run before `tuist generate` —
`make ios-gen` already encodes that dependency, so always go through `make ios-gen` /
`make ios-test`, never a bare `tuist generate`. Also: `rustfmt` reformats edits, so run
`make core-fmt` and re-read a file before the next edit.

### Privacy gate

`make core-privacy-audit` (no networking crate, no `openssl-sys`) plus a review assertion that
the import path imports no networking symbol (FR-041). **No new runtime dependency is
proposed** — see R12.

---

## R12 — Dependencies

### Decision — **zero new runtime dependencies, zero new dev dependencies.**

| Need | Satisfied by |
|---|---|
| Issuer registry, dispatch, tie-break | `std` only |
| Parsing | shipped `regex 1`, `rust_decimal 1`, `chrono 0.4` |
| Persistence / atomic import | shipped `rusqlite` + SQLCipher |
| FFI | shipped `uniffi 0.32` (proc-macro, no UDL) |
| Typed `ReaderError` | shipped `thiserror` (already used by `StoreError`) |
| PDF text + word geometry | **PDFKit**, a first-party Apple SDK framework |
| Document picking | `.fileImporter` (SwiftUI, first-party) |
| Tests | `cargo test`, shipped dev-only `serde_json 1`, Swift Testing |

**PDFKit is not a dependency addition under Constitution I / the Security & Privacy
Constraints.** It is a system framework shipped with iOS — no third-party code, no network
I/O, no fingerprinting, no data collection, nothing added to the crate graph the privacy-egress
audit inspects. The constitution and `docs/kaname-ios-plan.md` both *specify* it as the
platform-side extraction engine ("PDF text extraction is native (e.g. iOS PDFKit)",
Principle II). The only mechanical change is linking it in `ios/Project.swift`:
`.sdk(name: "PDFKit", type: .framework)` on the `Kaname` target.

---

## R13 — Liquid Glass application points

Per `.github/skills/swiftui-liquid-glass/SKILL.md`, iOS 26 baseline, **no `#available` gates
and no `.ultraThinMaterial` fallbacks anywhere** (FR-047).

| Surface | Treatment | Why |
|---|---|---|
| Empty-state **Import** CTA (US7) | `Button(…).buttonStyle(.glassProminent)` in `.safeAreaInset(edge: .bottom)` | a floating primary action above content — the textbook glass case, and the screen's *single* prominent element |
| In-progress **stage + Cancel** capsule (US6) | `GlassEffectContainer(spacing:)` holding a `ProgressView` + stage `Text` + `Button(…).buttonStyle(.glass)`; `.glassEffect(.regular.interactive(), in: .capsule)` applied **after** padding/frame | a floating overlay; `.interactive()` is honest because Cancel is tappable |
| Summary presentation (US1) | a `.sheet` — system chrome gets Liquid Glass **for free**; not re-skinned | the skill's "let the system own its own chrome" rule |
| Summary **figure rows** (counts, period, account) | **plain opaque grouped background — NOT glassed** | dense numeric data; glassing it is the skill's headline anti-pattern (FR-047) |
| Integrity warning (US5) | `Label` + SF Symbol on an opaque background, colour **plus** icon **plus** text | meaning is never carried by material or colour alone (FR-046) |
| Every count / amount | `.monospacedDigit()` | FR-045; figures must not jitter while the material animates |

**Guard**: the summary reports *counts*, not signed amounts, so the "never a red/green amount
on tinted glass" rule is satisfied structurally. If a net figure is ever added to this screen,
it must sit on the opaque rows, never on the glass CTA. At most one tinted element per screen
(the Import CTA).

---

## Open items carried into the plan

All `NEEDS CLARIFICATION` markers are resolved. Two **judgement calls** are flagged for
product-owner confirmation and are called out again in `plan.md`:

1. **R1** — the ten `Issuer.display_name` strings (invented brand copy; one table, one file).
2. **R6** — an import that recovers *neither* a period *nor* any transaction writes no
   `statements` row.
