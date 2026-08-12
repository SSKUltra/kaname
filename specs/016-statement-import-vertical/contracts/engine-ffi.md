# Contract — Engine FFI surface added by `016-statement-import-vertical`

The public interface `kaname-core` exposes to every platform. UniFFI 0.32 proc-macro
(no UDL). **Additive only**: every existing export keeps its signature and behaviour.

Two custom types already govern the boundary and are unchanged:
`Decimal ⇄ base-10 String` and `NaiveDate ⇄ ISO-8601 String` (`ffi.rs:35-47`).

---

## 1. Types

```rust
/// The two statement shapes the engine reads. CLOSED — exhaustive matching is intended.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum StatementKind { CreditCard, BankAccount }

/// Which reader produced (or will produce) a statement. OPEN — the app treats `id` as
/// opaque and renders `display_name` verbatim. Adding an issuer adds a registry row and
/// changes zero app code (SC-010).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct Issuer {
    pub id: String,
    pub display_name: String,
    pub bank_code: String,
    pub kind: StatementKind,
}

/// Word geometry for ONE extracted line, keyed by its index in `lines`. Sparse: supply the
/// lines you have (typically page 1). `Word.x0`/`x1` are layout points, never money.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct LineWords { pub line_index: u32, pub words: Vec<Word> }

/// A programmer error, never a user-facing message.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum ReaderError {
    #[error("no reader is registered for issuer id {id}")]
    UnknownIssuer { id: String },
}
```

---

## 2. `detect_issuer` (FR-010, FR-013, FR-014, FR-015)

```rust
#[uniffi::export]
pub fn detect_issuer(full_text: String) -> Option<Issuer>;
```

**Contract**

| | |
|---|---|
| **Input** | the whole extracted document text; the engine never sees the PDF |
| **Returns** | `Some(issuer)` — the winning reader; `None` — no reader claims it (FR-013) |
| **Purity** | no clock, no locale, no network, no global mutable state, no allocation of the input |
| **Determinism** | same `full_text` ⇒ same result, always (FR-015) |
| **Totality** | never panics; any input, including empty and non-UTF-8-shaped garbage, returns |

**Algorithm**

1. Evaluate every registry entry's `claims(full_text)`.
2. If zero claim → `None`.
3. Otherwise return the claimant minimising `(kind_rank(kind), id)` where
   `kind_rank(BankAccount) = 0`, `kind_rank(CreditCard) = 1`.

**Tie-break guarantees** (research R3): total (`id` unique ⇒ no ties); content-independent;
monotone under registry growth. **Ledger beats card** because a ledger claim is conjunctive
(`claim_all`) and a card claim disjunctive (`claim_markers`), so the ledger claim is strictly
stronger evidence. This fires on 3 of the 13 shipped golden fixtures today.

**Guarantee**: a losing candidate's parse is never produced, let alone persisted (FR-014).

---

## 3. `read_statement` (FR-011, FR-016, FR-018, FR-020)

```rust
#[uniffi::export]
pub fn read_statement(
    issuer: Issuer,
    lines: Vec<String>,
    full_text: String,
    line_words: Vec<LineWords>,
) -> Result<ParsedStatement, ReaderError>;
```

**Contract**

| | |
|---|---|
| **`issuer`** | must have come from `detect_issuer`; only `id` is read. Unknown ⇒ `Err(UnknownIssuer)` |
| **`line_words`** | may be empty. Ignored entirely for `CreditCard` issuers |
| **Returns** | `Ok(ParsedStatement)` — including an **empty** one, which is a success (FR-020) |
| **Never** | returns `Err` for a bad *document* — an unparseable row lands in `errored_lines` (FR-018) |
| **Purity** | as `detect_issuer` |

**How the `first_row_words` asymmetry is absorbed** — by the dispatcher, never by the app:

```rust
match entry.kind {
    StatementKind::CreditCard  => read_lines(cfg, &lines, &full_text),
    StatementKind::BankAccount => {
        // Only the reader knows which row it anchors on; the app must never need to.
        let words = first_anchor_index(cfg, &lines)
            .and_then(|i| line_words.iter().find(|lw| lw.line_index as usize == i))
            .map(|lw| lw.words.clone())
            .unwrap_or_default();
        read_ledger_lines(cfg, &lines, &full_text, &words)
    }
}
```

Requires one additive `pub(crate)` helper in `ledger_reader.rs`:

```rust
pub(crate) fn first_anchor_index<C: LedgerReaderConfig + ?Sized>(
    cfg: &C, lines: &[String],
) -> Option<usize>;
```

`read_lines`, `read_ledger_lines` and all ten `LedgerReaderConfig`/`LineReaderConfig` impls are
**unchanged**.

**Equivalence guarantee (tested, ×10)**: for every issuer,
`read_statement(issuer, lines, full_text, words)` is byte-identical to the corresponding
legacy `read_<bank>_statement(...)`. The dispatcher rebuilds nothing.

---

## 4. `Store::import_statement` (FR-025, FR-026, FR-030, FR-031, SC-006)

```rust
#[derive(uniffi::Enum)]
pub enum ImportAccountTarget {
    Existing { id: String },
    New { name: String, bank_code: String, is_credit_card: bool,
          last4: Option<String>, currency: String },
}

#[derive(uniffi::Record)]
pub struct NewImportTransaction {
    pub date: NaiveDate,
    pub description_raw: String,
    pub amount: Decimal,
    pub direction: Direction,
    pub currency: String,
    pub source_category: Option<String>,
}

#[derive(uniffi::Record)]
pub struct ImportRequest {
    pub account: ImportAccountTarget,
    pub bank_code: String,
    pub period_start: Option<NaiveDate>,
    pub period_end: NaiveDate,
    pub needs_review: bool,
    pub source: StatementSource,
    pub transactions: Vec<NewImportTransaction>,
    pub now: String,
}

#[derive(uniffi::Record)]
pub struct ImportOutcome {
    pub account_id: String,
    pub account_created: bool,
    pub statement_id: Option<String>,
    pub transactions_inserted: u32,
    pub duplicates_linked: u32,
    pub categorized: u32,
    pub uncategorized: u32,
}

#[uniffi::export]
impl Store {
    pub fn import_statement(&self, request: ImportRequest) -> Result<ImportOutcome, StoreError>;
}
```

**Contract — one SQLite transaction, no exceptions**

```text
BEGIN
  1. resolve-or-create account (mint last4 from the parse)
  2. INSERT statements row                                    (FR-026)
  3. INSERT every transaction with statement_id + timestamps  (FR-028, FR-029)
  4. categorize_account_in(tx, account_id)                    (FR-030)
  5. find_duplicates_in(tx)                                   (FR-025)
COMMIT   -- any failure at any step ⇒ full ROLLBACK, store byte-identical (FR-031, SC-006)
```

| Guarantee | |
|---|---|
| **Atomic** | every row lands or none does. Verified by a forced mid-write failure test |
| **No clock** | every timestamp derives from `request.now` (FR-027) |
| **Money** | `Decimal` in, `TEXT` on disk, `Decimal` out — no float at any hop (FR-028) |
| **Non-destructive** | duplicates are *linked* via `superseded_by`, never deleted or replaced (FR-025) |
| **Idempotent-safe** | re-importing the same file inserts rows, then links them as duplicates, so period totals do not double (SC-005) |

**⚠ Mandatory refactor — `std::sync::Mutex` is not reentrant.** `categorize_account`
(`store.rs:656`) and `find_duplicates` (`store.rs:785`) both call `self.lock()`. Calling them
from inside `import_statement` while the lock is held **deadlocks**. Extract
`categorize_account_in(tx, …)` and `find_duplicates_in(tx, …)`; the existing public methods
become thin `lock → transaction → *_in → commit` wrappers, preserving their behaviour and
their shipped tests.

---

## 5. Schema v6

```sql
-- SCHEMA_VERSION: 5 -> 6
ALTER TABLE accounts ADD COLUMN last4 TEXT;
```

Constant (NULL) default ⇒ runs on a populated table, exactly like the v2/v3/v4 migrations.
`apply_migration` gains a `6 => { tx.execute_batch(SCHEMA_V6).map_err(StoreError::migration) }`
arm. `NewAccount` and `StoredAccount` gain `last4: Option<String>`.

**No change to `statements`.** The v5 table already satisfies FR-026 field-for-field
(research R6).

---

## 6. Backward compatibility

| Surface | Status |
|---|---|
| `read_<bank>_statement` × 10, `<bank>_claims` × 10 | **unchanged** — still exported, still tested by `ios/Tests/*ParseTests.swift` |
| `check_balance_chain`, `reconcile_statement` | unchanged |
| `cross_source_duplicates`, `detect_transfers`, `compute_coverage` | unchanged |
| `categorize`, `categorize_batch`, `default_categories` | unchanged |
| `Store::open/insert_*/list_*/categorize_account/detect_transfers/find_duplicates/coverage` | unchanged behaviour; `NewAccount`/`StoredAccount` gain one optional field |
| `read_lines`, `read_ledger_lines`, all reader configs | unchanged |

**Build order**: this changes the FFI surface, so `make core-xcframework` **must** run before
`tuist generate`. Use `make ios-gen` / `make ios-test`, which already encode the dependency.
