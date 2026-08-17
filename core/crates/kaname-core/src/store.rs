//! The encrypted on-device store (Constitution III, "Encrypted at rest") — the engine's
//! first **stateful** FFI surface.
//!
//! [`Store`] owns a single **SQLCipher-encrypted SQLite** database (via `rusqlite`). The
//! platform supplies the file path and a 256-bit key (generated + held in the iOS
//! Keychain / Secure Enclave); the core sets the key, runs forward-only schema
//! [`migrate`](Store::open)ations, and reads/writes rows. The core **never persists or
//! logs the key**, performs **zero network I/O**, and reads no wall-clock for logic —
//! timestamps are explicit inputs (Constitution I/II).
//!
//! Money crosses the FFI as an exact base-10 [`Decimal`] string and dates as ISO-8601
//! [`NaiveDate`] (the custom types in [`crate::ffi`]); they are stored as TEXT, never as
//! floats. Every fallible operation returns a typed [`StoreError`] — the crate's first
//! error enum — so the platform can react gracefully instead of catching a panic. In
//! particular, opening an existing database with the wrong key **fails closed** with
//! [`StoreError::WrongKey`].
//!
//! This bootstrap slice ships schema **v1** (`accounts`, `categories` seeded from the 23
//! [`crate::default_categories`], `transactions`) and a transaction/account round-trip.
//! Wiring the engines (categorize/dedup/coverage/transfer) to the store is a later slice.

use std::str::FromStr;
use std::sync::{Arc, Mutex};

use chrono::NaiveDate;
use rusqlite::{params, Connection, ErrorCode, OptionalExtension};
use rust_decimal::Decimal;

use crate::categorize::{
    default_categories, Category, CategoryRef, CategoryTxn, Classification, MerchantMatch,
    MerchantRule, Rule, RuleMatch, SourceCategoryMapping, Stage,
};
use crate::coverage::{MonthCoverage, StatementCoverage, TransactionCoverage};
use crate::dedup::{CrossSourceMatch, DedupLayer};
use crate::model::{Direction, Transaction};
use crate::transfer::TransferInput;

/// The schema version this build of the core knows how to run. The migration runner
/// applies every version up to and including this one; re-opening an up-to-date database
/// is a no-op.
const SCHEMA_VERSION: i64 = 7;

/// The built-in category a bank-to-bank self-transfer's legs are assigned.
const SELF_TRANSFER: &str = "SELF_TRANSFER";
/// The built-in category a credit-card bill payment's legs are assigned.
const CREDIT_CARD_BILL_PAYMENT: &str = "CREDIT_CARD_BILL_PAYMENT";
/// The `categorised_by` provenance written by [`Store::detect_transfers`] — distinct from the
/// categorization stack's stages, so a transfer-assigned category is recognisable as such.
const TRANSFER_DETECTOR: &str = "TRANSFER_DETECTOR";

/// Forward-only schema **v1**: the minimal real foundation the engines will later read
/// from and write to. Money is TEXT (base-10 `Decimal`), dates/timestamps are ISO-8601
/// TEXT, direction is `'Debit'`/`'Credit'`, classification is a stable upper-snake code —
/// never floats or enum ordinals (rename-proof + precision-safe, Constitution IV).
const SCHEMA_V1: &str = r#"
CREATE TABLE accounts (
    id             TEXT PRIMARY KEY,
    name           TEXT NOT NULL,
    bank_code      TEXT NOT NULL,
    is_credit_card INTEGER NOT NULL CHECK (is_credit_card IN (0, 1)),
    currency       TEXT NOT NULL,
    created_at     TEXT NOT NULL,
    updated_at     TEXT NOT NULL
) STRICT;

CREATE TABLE categories (
    id             TEXT PRIMARY KEY,
    name           TEXT NOT NULL,
    classification TEXT NOT NULL,
    is_builtin     INTEGER NOT NULL DEFAULT 1 CHECK (is_builtin IN (0, 1))
) STRICT;

CREATE TABLE transactions (
    id              TEXT PRIMARY KEY,
    account_id      TEXT NOT NULL REFERENCES accounts(id),
    date            TEXT NOT NULL,
    description_raw TEXT NOT NULL,
    amount          TEXT NOT NULL,
    direction       TEXT NOT NULL CHECK (direction IN ('Debit', 'Credit')),
    currency        TEXT NOT NULL,
    category_id     TEXT REFERENCES categories(id),
    categorised_by  TEXT,
    is_deleted      INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1)),
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL
) STRICT;

CREATE INDEX idx_transactions_account ON transactions(account_id);
"#;

/// Forward-only schema **v2**: the facts the categorization stack reads — the T1
/// source-category map, the T2 merchant "memory", and the T3 rules — plus a per-transaction
/// `source_category` column carrying the issuer's own hint that feeds T1. Every fact
/// references a `categories` row (a built-in code or a user-category id) by foreign key, so a
/// fact pointing at a missing category fails closed.
const SCHEMA_V2: &str = r#"
ALTER TABLE transactions ADD COLUMN source_category TEXT;

CREATE TABLE merchant_map (
    id          INTEGER PRIMARY KEY,
    priority    INTEGER NOT NULL,
    match_type  TEXT NOT NULL CHECK (match_type IN ('Literal', 'Regex')),
    pattern     TEXT NOT NULL,
    category_id TEXT NOT NULL REFERENCES categories(id)
) STRICT;

CREATE TABLE source_category_map (
    id              INTEGER PRIMARY KEY,
    bank_code       TEXT NOT NULL,
    source_category TEXT NOT NULL,
    category_id     TEXT NOT NULL REFERENCES categories(id)
) STRICT;

CREATE TABLE rules (
    id          TEXT PRIMARY KEY,
    priority    INTEGER NOT NULL,
    is_system   INTEGER NOT NULL CHECK (is_system IN (0, 1)),
    match_type  TEXT NOT NULL CHECK (match_type IN ('Keyword', 'Regex', 'AmountRange')),
    value       TEXT NOT NULL,
    category_id TEXT NOT NULL REFERENCES categories(id)
) STRICT;
"#;

/// Forward-only schema **v3**: transfer identity. `is_transfer` flags a leg the transfer
/// detector paired; both legs of one self-transfer share a minted `transfer_group_id`. Constant
/// `ADD COLUMN` defaults so the migration runs on a populated table (as v2's did). Category
/// assignment for transfers is a later slice — this slice writes only the identity.
const SCHEMA_V3: &str = r#"
ALTER TABLE transactions ADD COLUMN is_transfer INTEGER NOT NULL DEFAULT 0
    CHECK (is_transfer IN (0, 1));
ALTER TABLE transactions ADD COLUMN transfer_group_id TEXT;
"#;

/// Forward-only schema **v4**: cross-source duplicate identity. `superseded_by` links a
/// duplicate row to the earlier row it duplicates (the survivor), and `dedup_layer` records
/// which matcher layer caught it (`Canonical`/`Fuzzy`). The loser is **linked, not deleted** —
/// `is_deleted` is untouched — so the link stays reversible and the presentation layer decides
/// what to hide. Constant/NULL `ADD COLUMN` defaults, so the migration runs on a populated
/// table (as v2's and v3's did).
const SCHEMA_V4: &str = r#"
ALTER TABLE transactions ADD COLUMN superseded_by TEXT REFERENCES transactions(id);
ALTER TABLE transactions ADD COLUMN dedup_layer TEXT
    CHECK (dedup_layer IS NULL OR dedup_layer IN ('Canonical', 'Fuzzy'));
"#;

/// Forward-only schema **v5**: imported statements as a first-class entity, plus per-transaction
/// provenance. A `statements` row records one import run — its billing period, whether the run
/// needs review (an incomplete parse or a failed reconciliation), and whether it came from a full
/// statement or a piecemeal live alert. `transactions.statement_id` attributes a row to the run
/// that produced it; a live-alert row simply has none. Coverage's `from_full_statement` fact is
/// **derived** from that link (a row is from a full statement when its statement's `source` is
/// `'Statement'`), so there is no redundant flag to drift.
const SCHEMA_V5: &str = r#"
CREATE TABLE statements (
    id           TEXT PRIMARY KEY,
    account_id   TEXT NOT NULL REFERENCES accounts(id),
    bank_code    TEXT NOT NULL,
    period_start TEXT,
    period_end   TEXT NOT NULL,
    needs_review INTEGER NOT NULL DEFAULT 0 CHECK (needs_review IN (0, 1)),
    source       TEXT NOT NULL CHECK (source IN ('Statement', 'Alert')),
    created_at   TEXT NOT NULL
) STRICT;

CREATE INDEX idx_statements_account ON statements(account_id);

ALTER TABLE transactions ADD COLUMN statement_id TEXT REFERENCES statements(id);
"#;

/// Forward-only schema **v6**: accounts carry the masked account/card tail so import
/// resolution keys on data, not display names.
const SCHEMA_V6: &str = "ALTER TABLE accounts ADD COLUMN last4 TEXT;";

/// The live-row predicate as a *literal*, so the schema and every read that must agree with it
/// are built from the same bytes at compile time rather than from someone's memory.
macro_rules! live_predicate {
    () => {
        "is_deleted = 0 AND superseded_by IS NULL"
    };
}

/// The only definition of "a transaction the person actually has". It is also, verbatim, the
/// `WHERE` clause of `idx_txn_live_account_date` — so a read that forgets it does not merely
/// return the wrong rows, it silently loses its index, and the plan-shape gate goes red.
const LIVE: &str = live_predicate!();

/// Forward-only schema **v7**: one partial, descending index over the live rows of an account,
/// so the combined history can be read in its own order without sorting.
///
/// `DESC` and `partial` are both load-bearing (research R4): `DESC` makes the index entry order
/// `(account_id ASC, date DESC, rowid ASC)` — the ordering key with the account fixed — and an
/// ASC index costs `USE TEMP B-TREE FOR LAST TERM OF ORDER BY`; partial keeps the index to the
/// rows a person actually has. Its predicate is [`LIVE`] itself.
const SCHEMA_V7: &str = concat!(
    "CREATE INDEX idx_txn_live_account_date ON transactions(account_id, date DESC) WHERE ",
    live_predicate!(),
    ";"
);

/// The one statement every combined-history read executes — filtered or not, first page or
/// resumed. `?1` is the account, `?2`/`?3` the resume point and `?4` the page size; a first
/// page binds the identity cursor `('9999-12-31', 0)`, so there is no separate first-page code
/// path and no separate filtered one (FR-042).
///
/// Public because the filter's structural proof (F3) and the plan-shape gates (S1, S2) assert
/// against this exact text: a second page statement anywhere would fail them.
pub const PAGE_SQL: &str = concat!(
    "SELECT t.id, t.account_id, t.date, t.description_raw, t.amount, t.direction, \
     t.currency, t.category_id, t.is_transfer, t.rowid \
     FROM transactions t \
     WHERE t.account_id = ?1 AND ",
    live_predicate!(),
    " AND (t.date < ?2 OR (t.date = ?2 AND t.rowid > ?3)) \
     ORDER BY t.date DESC, t.rowid ASC \
     LIMIT ?4"
);

/// A typed, non-panicking error for every fallible store operation (a `uniffi::Error`, so
/// it surfaces in Swift as a throwing `Error`). No variant carries the key or row data.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum StoreError {
    /// The database file could not be opened (bad path, I/O, permissions).
    #[error("failed to open the database: {message}")]
    OpenFailed { message: String },
    /// The supplied key is not a 64-character (256-bit) lowercase/uppercase hex string.
    #[error("the key must be 64 hexadecimal characters (a 256-bit key)")]
    InvalidKey,
    /// The key did not decrypt an existing database — it fails closed (no readable DB).
    #[error("wrong encryption key: the database could not be decrypted")]
    WrongKey,
    /// A schema migration failed to apply.
    #[error("schema migration failed: {message}")]
    Migration { message: String },
    /// Any other SQL/storage failure.
    #[error("storage error: {message}")]
    Sql { message: String },
}

impl From<rusqlite::Error> for StoreError {
    fn from(err: rusqlite::Error) -> Self {
        StoreError::Sql {
            message: err.to_string(),
        }
    }
}

impl StoreError {
    /// Wrap a failure that occurred while opening/keying the database.
    fn open_failed(err: rusqlite::Error) -> Self {
        StoreError::OpenFailed {
            message: err.to_string(),
        }
    }

    /// Wrap a failure that occurred while applying a schema migration.
    fn migration(err: rusqlite::Error) -> Self {
        StoreError::Migration {
            message: err.to_string(),
        }
    }
}

/// A new account to persist. The store mints the id; timestamps are caller-supplied
/// ISO-8601 strings (the core reads no wall-clock).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NewAccount {
    pub name: String,
    pub bank_code: String,
    pub is_credit_card: bool,
    pub last4: Option<String>,
    pub currency: String,
    pub created_at: String,
    pub updated_at: String,
}

/// An account as stored, including its store-minted `id`.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct StoredAccount {
    pub id: String,
    pub name: String,
    pub bank_code: String,
    pub is_credit_card: bool,
    pub last4: Option<String>,
    pub currency: String,
    pub created_at: String,
    pub updated_at: String,
}

/// Where to resume a combined-history read. Opaque to the caller: it is produced by
/// [`Store::history_page`] and handed back unchanged. It is never displayed (FR-019).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct HistoryCursor {
    /// One resume point per account that still has rows to give. An exhausted account is
    /// absent, so the cursor shrinks as the person scrolls.
    pub marks: Vec<AccountMark>,
}

/// One account's resume point: the ordering-key suffix of the last row emitted from it.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct AccountMark {
    pub account_id: String,
    pub date: NaiveDate,
    /// `transactions.rowid` — the within-account, within-date tie-break. Internal.
    pub sequence: i64,
}

/// What the screen is asking for.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct HistoryQuery {
    /// `None` = every account, in [`Store::list_accounts`] order. `Some(id)` = that account
    /// only. This is the ONLY difference between a filtered and an unfiltered read (FR-042).
    pub account_id: Option<String>,
    /// `None` = start at the newest end of the sequence.
    pub cursor: Option<HistoryCursor>,
    /// Rows wanted. Clamped to `1..=200`; an out-of-range value is clamped, never an error —
    /// a page of 0 would be an infinite scroll loop in the caller.
    pub limit: u32,
}

/// One live transaction, ready to render. It carries no storage internals — no
/// `superseded_by`, `dedup_layer`, `statement_id`, `categorised_by`, `transfer_group_id`,
/// `is_deleted`, `rowid` or timestamps — so none of them can leak into a view (FR-019,
/// SC-016).
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct HistoryRow {
    pub id: String,
    pub account_id: String,
    pub account_name: String,
    pub account_last4: Option<String>,
    pub date: NaiveDate,
    pub description_raw: String,
    pub amount: Decimal,
    pub direction: Direction,
    /// The **transaction's** currency, never the account's and never the locale's (FR-023).
    pub currency: String,
    /// The category's display name, or `None` for uncategorized (FR-017).
    pub category_name: Option<String>,
    pub is_transfer: bool,
}

/// One screenful of the combined history.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct HistoryPage {
    pub rows: Vec<HistoryRow>,
    /// `None` ⇔ the sequence is exhausted.
    pub cursor: Option<HistoryCursor>,
}

/// One account, with the only count this slice produces.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct AccountSummary {
    pub id: String,
    pub name: String,
    pub last4: Option<String>,
    pub is_credit_card: bool,
    pub currency: String,
    /// Live rows only — neither deleted nor superseded (FR-006, FR-008, FR-046).
    pub live_transaction_count: u32,
    /// True when the account holds rows and every one of them is excluded. A boolean and not
    /// a count, deliberately: FR-008 forbids this slice introducing a count that does not use
    /// the live rule, and a boolean cannot be rendered as one.
    pub has_only_excluded_rows: bool,
}

/// Where an imported run's rows came from: a full statement (a PDF/CSV covering a whole
/// billing period) or a piecemeal live alert. Coverage treats only `Statement` as covering a
/// month.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum StatementSource {
    Statement,
    Alert,
}

/// The account an atomic statement import should attach to.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum ImportAccountTarget {
    Existing {
        id: String,
        /// The last-4 this statement carried, if any. An account created from a statement
        /// that had none learns it here, so the *next* import can match on it instead of
        /// falling back to "the only account for this issuer".
        last4: Option<String>,
    },
    New {
        name: String,
        bank_code: String,
        is_credit_card: bool,
        last4: Option<String>,
        currency: String,
    },
}

/// One parsed transaction row for [`Store::import_statement`].
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct NewImportTransaction {
    pub date: NaiveDate,
    pub description_raw: String,
    pub amount: Decimal,
    pub direction: Direction,
    pub currency: String,
    pub source_category: Option<String>,
}

/// The complete input for one atomic statement import.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
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

/// The summary returned after an atomic statement import commits.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ImportOutcome {
    pub account_id: String,
    pub account_created: bool,
    pub statement_id: Option<String>,
    /// How many rows the reader handed over — every transaction printed in the document.
    ///
    /// Named for what it is. It was `transactions_inserted`, which every caller read as "rows
    /// added to the account", and on a re-import it is not: all of them are written and then
    /// the ones already held are superseded, so a six-row statement re-imported reported six
    /// transactions while the account gained nothing
    /// (`.scratch/016-statement-import-vertical/issues/07`).
    pub rows_read: u32,
    /// How many of those rows the account actually **gained** — this statement's rows that are
    /// still live once re-import supersession and cross-source de-duplication have run.
    ///
    /// This is the number that answers "did anything change?", and it is counted from the
    /// database after every linking pass rather than derived, so no arithmetic can drift from
    /// what the rows actually say.
    pub transactions_added: u32,
    /// The rest: rows of **this statement** that lost to a row already held. `rows_read` is
    /// always `transactions_added + rows_superseded`, so the two figures a person is shown add
    /// up to the document in front of them.
    pub rows_superseded: u32,
    /// Links created across the **whole store** by this import's de-duplication pass, plus the
    /// rows this statement re-imported. Store-wide and therefore **not** a per-statement
    /// figure — it is kept for callers that measure the de-duplicator, and is deliberately not
    /// what the import summary shows.
    pub duplicates_linked: u32,
    pub categorized: u32,
    pub uncategorized: u32,
}

/// A new statement to persist against an existing account — one import run. The store mints the
/// id. `period_start` is optional (not every reader recovers it); `period_end` attributes the
/// statement to its calendar month, and `needs_review` records that the run was incomplete or
/// failed reconciliation.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct NewStatement {
    pub account_id: String,
    pub bank_code: String,
    pub period_start: Option<NaiveDate>,
    pub period_end: NaiveDate,
    pub needs_review: bool,
    pub source: StatementSource,
    pub created_at: String,
}

/// A statement as stored, including its store-minted `id`.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StoredStatement {
    pub id: String,
    pub account_id: String,
    pub bank_code: String,
    pub period_start: Option<NaiveDate>,
    pub period_end: NaiveDate,
    pub needs_review: bool,
    pub source: StatementSource,
    pub created_at: String,
}

/// A new transaction to persist against an existing account. The store mints the id;
/// `date` is the transaction's calendar date, `amount` its exact magnitude (direction
/// carries polarity), and timestamps are caller-supplied ISO-8601 strings.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct NewTransaction {
    pub account_id: String,
    pub date: NaiveDate,
    pub description_raw: String,
    pub amount: Decimal,
    pub direction: Direction,
    pub currency: String,
    pub source_category: Option<String>,
    pub category_id: Option<String>,
    pub categorised_by: Option<String>,
    pub statement_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

/// A transaction as stored, including its store-minted `id` and `is_deleted` flag.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StoredTransaction {
    pub id: String,
    pub account_id: String,
    pub date: NaiveDate,
    pub description_raw: String,
    pub amount: Decimal,
    pub direction: Direction,
    pub currency: String,
    pub source_category: Option<String>,
    pub category_id: Option<String>,
    pub categorised_by: Option<String>,
    pub is_deleted: bool,
    pub is_transfer: bool,
    pub transfer_group_id: Option<String>,
    pub superseded_by: Option<String>,
    pub dedup_layer: Option<DedupLayer>,
    pub statement_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

/// A user category to create — name + money-bucket only. Minimal on purpose: display
/// metadata (colour / emoji / localized names) and full CRUD are a later slice.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NewCategory {
    pub name: String,
    pub classification: Classification,
}

/// The outcome of [`Store::categorize_account`]: how many rows the stack categorized versus
/// left uncategorized.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, uniffi::Record)]
pub struct CategorizeSummary {
    pub categorized: u32,
    pub uncategorized: u32,
}

/// The outcome of [`Store::detect_transfers`]: how many self-transfer pairs were linked, and
/// how many of those had a credit-card leg (a bill payment vs a bank-to-bank self transfer).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, uniffi::Record)]
pub struct TransferSummary {
    pub pairs_linked: u32,
    pub credit_card_payments: u32,
}

/// The outcome of [`Store::find_duplicates`]: how many rows were linked as cross-source
/// duplicates, split by the matcher layer that caught each one.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, uniffi::Record)]
pub struct DedupSummary {
    pub duplicates_linked: u32,
    pub canonical: u32,
    pub fuzzy: u32,
}

/// The encrypted on-device store — a stateful UniFFI object owning one SQLCipher database.
///
/// Shared as an `Arc<Store>`; the `Connection` is guarded by a `Mutex` so the object is
/// `Send + Sync` across the bridge. All SQL lives here; the platform only supplies the key
/// and path and calls methods.
#[derive(uniffi::Object)]
pub struct Store {
    conn: Mutex<Connection>,
}

impl std::fmt::Debug for Store {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Never surface the connection (or, by extension, anything key-derived).
        f.debug_struct("Store").finish_non_exhaustive()
    }
}

#[uniffi::export]
impl Store {
    /// Open (creating if absent) the SQLCipher-encrypted database at `path`, keyed with
    /// `key` (a 64-character hex string = 256 bits), and bring it to the current schema
    /// version. The key is set on the connection and **never persisted or logged**.
    ///
    /// Fails closed: a malformed key is [`StoreError::InvalidKey`]; a wrong key for an
    /// existing database is [`StoreError::WrongKey`] (never a panic or a readable DB).
    #[uniffi::constructor]
    pub fn open(path: String, key: String) -> Result<Arc<Self>, StoreError> {
        validate_key(&key)?;

        let conn = Connection::open(&path).map_err(StoreError::open_failed)?;

        // Set the raw 256-bit key (SQLCipher `PRAGMA key = "x'<hex>'"`). This does not yet
        // touch a page, so it cannot fail on a wrong key here.
        conn.pragma_update(None, "key", format!("x'{key}'"))
            .map_err(StoreError::open_failed)?;

        // Touch the schema to force decryption. On an existing DB a wrong key yields
        // SQLITE_NOTADB — map that (and only that) to WrongKey; a fresh empty file simply
        // becomes a new encrypted DB and reads 0 rows.
        if let Err(err) = conn.query_row("SELECT count(*) FROM sqlite_master", [], |row| {
            row.get::<_, i64>(0)
        }) {
            return Err(match &err {
                rusqlite::Error::SqliteFailure(e, _) if e.code == ErrorCode::NotADatabase => {
                    StoreError::WrongKey
                }
                _ => StoreError::open_failed(err),
            });
        }

        // Enforce foreign keys (off by default in SQLite) so transactions must reference a
        // real account/category.
        conn.pragma_update(None, "foreign_keys", true)?;

        let store = Self {
            conn: Mutex::new(conn),
        };
        store.migrate()?;
        Ok(Arc::new(store))
    }

    /// Persist a new account and return its store-minted id.
    pub fn insert_account(&self, account: NewAccount) -> Result<String, StoreError> {
        let conn = self.lock();
        let id = mint_id(&conn)?;
        conn.execute(
            "INSERT INTO accounts \
             (id, name, bank_code, is_credit_card, last4, currency, created_at, updated_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                id,
                account.name,
                account.bank_code,
                account.is_credit_card as i64,
                account.last4,
                account.currency,
                account.created_at,
                account.updated_at,
            ],
        )?;
        Ok(id)
    }

    /// All accounts, oldest first (insertion order).
    pub fn list_accounts(&self) -> Result<Vec<StoredAccount>, StoreError> {
        let conn = self.lock();
        list_accounts_in(&conn)
    }

    /// Persist a new statement — one import run — against an existing account, and return its
    /// minted id. Transactions produced by the run reference it via `NewTransaction.statement_id`.
    pub fn insert_statement(&self, statement: NewStatement) -> Result<String, StoreError> {
        let conn = self.lock();
        let id = mint_id(&conn)?;
        conn.execute(
            "INSERT INTO statements \
             (id, account_id, bank_code, period_start, period_end, needs_review, source, \
              created_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                id,
                statement.account_id,
                statement.bank_code,
                statement.period_start.map(date_to_sql),
                date_to_sql(statement.period_end),
                statement.needs_review as i64,
                statement_source_to_sql(statement.source),
                statement.created_at,
            ],
        )?;
        Ok(id)
    }

    /// All statements for `account_id`, oldest first (insertion order).
    pub fn list_statements(&self, account_id: String) -> Result<Vec<StoredStatement>, StoreError> {
        let conn = self.lock();
        let mut stmt = conn.prepare(
            "SELECT id, account_id, bank_code, period_start, period_end, needs_review, source, \
                    created_at \
             FROM statements WHERE account_id = ?1 ORDER BY rowid",
        )?;
        let rows = stmt
            .query_map(params![account_id], map_statement)?
            .collect::<rusqlite::Result<Vec<_>>>()?
            .into_iter()
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// Persist a new transaction against an existing account and return its minted id.
    pub fn insert_transaction(&self, txn: NewTransaction) -> Result<String, StoreError> {
        let conn = self.lock();
        let id = mint_id(&conn)?;
        conn.execute(
            "INSERT INTO transactions \
             (id, account_id, date, description_raw, amount, direction, currency, \
              source_category, category_id, categorised_by, statement_id, created_at, updated_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
            params![
                id,
                txn.account_id,
                date_to_sql(txn.date),
                txn.description_raw,
                txn.amount.to_string(),
                direction_to_sql(txn.direction),
                txn.currency,
                txn.source_category,
                txn.category_id,
                txn.categorised_by,
                txn.statement_id,
                txn.created_at,
                txn.updated_at,
            ],
        )?;
        Ok(id)
    }

    /// Persist one statement import atomically: account, statement row, transactions,
    /// categorization, and cross-source duplicate links all commit or roll back together.
    pub fn import_statement(&self, request: ImportRequest) -> Result<ImportOutcome, StoreError> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;

        let (account_id, account_created) = match request.account {
            ImportAccountTarget::Existing { id, last4 } => {
                let exists = tx
                    .query_row("SELECT 1 FROM accounts WHERE id = ?1", params![id], |_| {
                        Ok(())
                    })
                    .optional()?
                    .is_some();
                if !exists {
                    return Err(StoreError::Sql {
                        message: "import account does not exist".to_string(),
                    });
                }
                // Only ever fills a blank: a statement never overwrites a last-4 the account
                // already has, because that would silently re-label somebody's account.
                if last4.is_some() {
                    tx.execute(
                        "UPDATE accounts SET last4 = ?2, updated_at = ?3 \
                         WHERE id = ?1 AND last4 IS NULL",
                        params![id, last4, request.now],
                    )?;
                }
                (id, false)
            }
            ImportAccountTarget::New {
                name,
                bank_code,
                is_credit_card,
                last4,
                currency,
            } => {
                let id = mint_id(&tx)?;
                tx.execute(
                    "INSERT INTO accounts \
                     (id, name, bank_code, is_credit_card, last4, currency, created_at, updated_at) \
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7)",
                    params![
                        id,
                        name,
                        bank_code,
                        is_credit_card as i64,
                        last4,
                        currency,
                        request.now,
                    ],
                )?;
                (id, true)
            }
        };

        if request.transactions.is_empty() {
            tx.commit()?;
            return Ok(ImportOutcome {
                account_id,
                account_created,
                statement_id: None,
                rows_read: 0,
                transactions_added: 0,
                rows_superseded: 0,
                duplicates_linked: 0,
                categorized: 0,
                uncategorized: 0,
            });
        }

        let statement_id = mint_id(&tx)?;
        tx.execute(
            "INSERT INTO statements \
             (id, account_id, bank_code, period_start, period_end, needs_review, source, \
              created_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                statement_id,
                account_id,
                request.bank_code,
                request.period_start.map(date_to_sql),
                date_to_sql(request.period_end),
                request.needs_review as i64,
                statement_source_to_sql(request.source),
                request.now,
            ],
        )?;

        {
            let mut insert = tx.prepare(
                "INSERT INTO transactions \
                 (id, account_id, date, description_raw, amount, direction, currency, \
                  source_category, category_id, categorised_by, statement_id, created_at, updated_at) \
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, NULL, NULL, ?9, ?10, ?10)",
            )?;
            for txn in &request.transactions {
                let id = mint_id(&tx)?;
                insert.execute(params![
                    id,
                    account_id,
                    date_to_sql(txn.date),
                    txn.description_raw,
                    txn.amount.to_string(),
                    direction_to_sql(txn.direction),
                    txn.currency,
                    txn.source_category,
                    statement_id,
                    request.now,
                ])?;
            }
        }

        let reimported = link_reimported_rows_in(&tx, &account_id, &statement_id)?;
        let categorized = categorize_account_in(&tx, &account_id)?;
        let duplicates = find_duplicates_in(&tx)?;
        // Counted **after** every linking pass and from the rows themselves, because that is
        // the only way the figure survives a change to how linking works. Deriving it from
        // `reimported` would have missed a row this statement lost to cross-source
        // de-duplication, and deriving it from `duplicates_linked` would have counted links
        // made elsewhere in the store (issues/07).
        let rows_read = request.transactions.len() as u32;
        let transactions_added = count_live_statement_rows_in(&tx, &statement_id)?;
        tx.commit()?;

        Ok(ImportOutcome {
            account_id,
            account_created,
            statement_id: Some(statement_id),
            rows_read,
            transactions_added,
            rows_superseded: rows_read.saturating_sub(transactions_added),
            duplicates_linked: duplicates.duplicates_linked + reimported,
            categorized: categorized.categorized,
            uncategorized: categorized.uncategorized,
        })
    }

    /// All (non-deleted and deleted) transactions for `account_id`, oldest first.
    pub fn list_transactions(
        &self,
        account_id: String,
    ) -> Result<Vec<StoredTransaction>, StoreError> {
        let conn = self.lock();
        let mut stmt = conn.prepare(
            "SELECT id, account_id, date, description_raw, amount, direction, currency, \
                    category_id, categorised_by, is_deleted, created_at, updated_at, \
                    source_category, is_transfer, transfer_group_id, superseded_by, dedup_layer, \
                    statement_id \
             FROM transactions WHERE account_id = ?1 ORDER BY rowid",
        )?;
        let rows = stmt
            .query_map(params![account_id], map_transaction)?
            .collect::<rusqlite::Result<Vec<_>>>()?
            .into_iter()
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// One screenful of every account's **live** transactions, in the combined history's
    /// order: `date` descending, then the account's position in [`Store::list_accounts`],
    /// then `transactions.rowid` (FR-028–FR-031, `data-model.md` §2).
    ///
    /// One prepared statement ([`PAGE_SQL`]) is run once per account in scope — k already
    /// sorted streams — and merged here by [`history_order`]. Filtering is the same read with
    /// k = 1 (FR-042); an `account_id` naming nothing is an empty page, not an error.
    ///
    /// Paging is **keyset**, not offset: the returned cursor resumes exactly after the last
    /// row emitted, so an import landing mid-scroll can neither repeat nor skip a row the
    /// person has already seen (FR-054, FR-056). `cursor == None` ⇔ exhausted.
    ///
    /// Takes the connection lock exactly once and reads the account list and category catalog
    /// through `*_in` helpers thereafter — `std::sync::Mutex` is not reentrant.
    pub fn history_page(&self, query: HistoryQuery) -> Result<HistoryPage, StoreError> {
        let conn = self.lock();
        let limit = query.limit.clamp(1, MAX_PAGE) as usize;
        let accounts = list_accounts_in(&conn)?;

        // Scope: the accounts the query asks for, still in the front door's order. A resumed
        // read drops the accounts the cursor has already exhausted.
        let scope: Vec<(usize, &StoredAccount)> = accounts
            .iter()
            .enumerate()
            .filter(|(_, a)| query.account_id.as_ref().is_none_or(|id| *id == a.id))
            .filter(|(_, a)| match &query.cursor {
                Some(cursor) => cursor.marks.iter().any(|m| m.account_id == a.id),
                None => true,
            })
            .collect();
        if scope.is_empty() {
            return Ok(HistoryPage {
                rows: Vec::new(),
                cursor: None,
            });
        }

        let categories = category_names_in(&conn)?;
        let mut stmt = conn.prepare(PAGE_SQL)?;

        // One already-sorted buffer per account, each read from the resume point the cursor
        // carries — or from the identity cursor, which is what makes a first page the same
        // code path as every later one.
        let mut streams: Vec<Stream> = Vec::with_capacity(scope.len());
        for (position, account) in scope {
            let mark = query.cursor.as_ref().and_then(|c| {
                c.marks
                    .iter()
                    .find(|m| m.account_id == account.id)
                    .map(|m| (date_to_sql(m.date), m.sequence))
            });
            let (from_date, from_sequence) = mark.unwrap_or_else(|| (IDENTITY_DATE.into(), 0));
            let rows = stmt
                .query_map(
                    params![account.id, from_date, from_sequence, limit as i64],
                    |row| {
                        Ok(map_history_row(row, account, &categories)
                            .map(|(row, rowid)| Pending { row, rowid }))
                    },
                )?
                .collect::<rusqlite::Result<Vec<_>>>()?
                .into_iter()
                .collect::<Result<Vec<_>, StoreError>>()?;

            streams.push(Stream {
                account_id: account.id.clone(),
                position,
                exhausted: rows.len() < limit,
                pending: rows.into_iter().collect(),
                resume: (from_date, from_sequence),
            });
        }

        // Merge the k streams: repeatedly take whichever head comes first in the history's
        // order. k is the account count, which is small, so a linear scan beats a heap.
        let mut rows = Vec::with_capacity(limit);
        while rows.len() < limit {
            let Some(next) = streams
                .iter()
                .enumerate()
                .filter(|(_, s)| !s.pending.is_empty())
                .min_by(|(_, a), (_, b)| {
                    let (a_head, b_head) = (&a.pending[0], &b.pending[0]);
                    history_order(
                        (a_head.row.date, a.position, a_head.rowid),
                        (b_head.row.date, b.position, b_head.rowid),
                    )
                })
                .map(|(index, _)| index)
            else {
                break;
            };
            let stream = &mut streams[next];
            let taken = stream.pending.pop_front().expect("a non-empty stream");
            stream.resume = (date_to_sql(taken.row.date), taken.rowid);
            rows.push(taken.row);
        }

        // An account with nothing left to give leaves the cursor entirely, so the cursor
        // shrinks as the person scrolls; an empty cursor is the end of the sequence.
        let marks: Vec<AccountMark> = streams
            .iter()
            .filter(|s| !(s.exhausted && s.pending.is_empty()))
            .map(|s| {
                Ok(AccountMark {
                    account_id: s.account_id.clone(),
                    date: date_from_sql(&s.resume.0)?,
                    sequence: s.resume.1,
                })
            })
            .collect::<Result<Vec<_>, StoreError>>()?;

        Ok(HistoryPage {
            rows,
            cursor: (!marks.is_empty()).then_some(HistoryCursor { marks }),
        })
    }

    /// Every account, in the front door's order, each with its **live** transaction count —
    /// the only count this slice produces, under the same predicate and the same index the
    /// history itself reads (FR-006, FR-008, FR-046).
    pub fn account_summaries(&self) -> Result<Vec<AccountSummary>, StoreError> {
        let conn = self.lock();
        let accounts = list_accounts_in(&conn)?;

        let live = grouped_counts(&conn, LIVE)?;
        let held = grouped_counts(&conn, "1 = 1")?;

        Ok(accounts
            .into_iter()
            .map(|account| {
                let live_transaction_count = live.get(&account.id).copied().unwrap_or(0);
                let held_rows = held.get(&account.id).copied().unwrap_or(0);
                AccountSummary {
                    id: account.id,
                    name: account.name,
                    last4: account.last4,
                    is_credit_card: account.is_credit_card,
                    currency: account.currency,
                    live_transaction_count,
                    has_only_excluded_rows: held_rows > 0 && live_transaction_count == 0,
                }
            })
            .collect())
    }

    /// The category catalog — the 23 seeded [`crate::default_categories`] plus any user
    /// categories created via [`Store::insert_category`] — ready to feed the categorization
    /// stack. Built-ins surface as [`CategoryRef::Builtin`], user categories as    /// [`CategoryRef::Custom`].
    pub fn list_categories(&self) -> Result<Vec<Category>, StoreError> {
        load_categories(&self.lock())
    }

    /// Create a user (non-built-in) category and return its store-minted id. A minimal
    /// primitive for the categorization loop; full category CRUD + display metadata
    /// (colour / emoji / localized names) is a later slice.
    pub fn insert_category(&self, category: NewCategory) -> Result<String, StoreError> {
        let conn = self.lock();
        let id = mint_id(&conn)?;
        conn.execute(
            "INSERT INTO categories (id, name, classification, is_builtin) \
             VALUES (?1, ?2, ?3, 0)",
            params![
                id,
                category.name,
                classification_to_sql(category.classification)
            ],
        )?;
        Ok(id)
    }

    /// Persist a T2 merchant-map entry (the "memory") and return its row id. The referenced
    /// category must already exist (built-in or user) or the insert fails closed (FK).
    pub fn insert_merchant_rule(&self, rule: MerchantRule) -> Result<i64, StoreError> {
        let conn = self.lock();
        conn.execute(
            "INSERT INTO merchant_map (priority, match_type, pattern, category_id) \
             VALUES (?1, ?2, ?3, ?4)",
            params![
                rule.priority,
                merchant_match_to_sql(rule.match_type),
                rule.pattern,
                category_ref_to_id(&rule.category),
            ],
        )?;
        Ok(conn.last_insert_rowid())
    }

    /// All T2 merchant-map entries, priority order (lowest first).
    pub fn list_merchant_rules(&self) -> Result<Vec<MerchantRule>, StoreError> {
        load_merchant_rules(&self.lock())
    }

    /// Persist a T1 source-category-map entry (the issuer's own hint → a Kaname category)
    /// and return its row id. The referenced category must already exist.
    pub fn insert_source_category_mapping(
        &self,
        mapping: SourceCategoryMapping,
    ) -> Result<i64, StoreError> {
        let conn = self.lock();
        conn.execute(
            "INSERT INTO source_category_map (bank_code, source_category, category_id) \
             VALUES (?1, ?2, ?3)",
            params![
                mapping.bank_code,
                mapping.source_category,
                category_ref_to_id(&mapping.category),
            ],
        )?;
        Ok(conn.last_insert_rowid())
    }

    /// All T1 source-category-map entries, insertion order.
    pub fn list_source_category_mappings(&self) -> Result<Vec<SourceCategoryMapping>, StoreError> {
        load_source_category_mappings(&self.lock())
    }

    /// Persist a T3 rule (keyword / regex / amount-range). Uses the rule's own id when
    /// present, otherwise mints one; returns the id. The referenced category must exist.
    pub fn insert_rule(&self, rule: Rule) -> Result<String, StoreError> {
        let conn = self.lock();
        let id = match rule.id {
            Some(id) => id,
            None => mint_id(&conn)?,
        };
        conn.execute(
            "INSERT INTO rules (id, priority, is_system, match_type, value, category_id) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                id,
                rule.priority,
                rule.is_system as i64,
                rule_match_to_sql(rule.match_type),
                rule.value,
                category_ref_to_id(&rule.category),
            ],
        )?;
        Ok(id)
    }

    /// All T3 rules, priority order (lowest first).
    pub fn list_rules(&self) -> Result<Vec<Rule>, StoreError> {
        load_rules(&self.lock())
    }

    /// Categorize an account's non-deleted transactions with the deterministic first-wins
    /// stack (CC rules → T1 source-category map → T2 merchant map → T3 rules) from the stored
    /// catalog + facts, and persist each result (`category_id` + the `categorised_by` stage).
    /// Recomputes every row, so it is idempotent; a row no stage matches is left
    /// uncategorized (both columns `NULL`). Reuses the pure engine verbatim — no network, no
    /// clock. Returns how many rows were categorized vs left uncategorized.
    ///
    /// **Rows already tagged as transfers are skipped** (and counted in neither total):
    /// [`Store::detect_transfers`] assigns those their `SELF_TRANSFER` /
    /// `CREDIT_CARD_BILL_PAYMENT` category, and a confirmed cross-account pair outranks a
    /// keyword match — so re-running this can never clobber a transfer's category.
    pub fn categorize_account(&self, account_id: String) -> Result<CategorizeSummary, StoreError> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let summary = categorize_account_in(&tx, &account_id)?;
        tx.commit()?;
        Ok(summary)
    }

    /// Detect self-transfers across **all** accounts, tag both legs of each pair, and assign the
    /// pair's category.
    ///
    /// Loads every non-deleted, not-yet-linked transaction (`transfer_group_id IS NULL`)
    /// joined to its owning account for `is_credit_card`, runs the pure
    /// [`crate::transfer::detect_transfers`] matcher, and for each returned pair mints one
    /// `transfer_group_id`, sets `is_transfer = 1` on both legs, and assigns the built-in
    /// category — `CREDIT_CARD_BILL_PAYMENT` when the pair has a credit-card leg, else
    /// `SELF_TRANSFER` — with `categorised_by = 'TRANSFER_DETECTOR'`. Detection and assignment
    /// share one write transaction, so a linked pair is never left uncategorized.
    ///
    /// **Transfer wins over the categorization stack**: a confirmed cross-account pair is
    /// stronger evidence than a keyword match, so [`Store::categorize_account`] skips
    /// `is_transfer` rows and can never clobber what this writes — in either running order.
    /// Idempotent: already-linked rows are excluded from the candidate load and the UPDATE is
    /// guarded by `transfer_group_id IS NULL`, so re-running links (and assigns) nothing new.
    pub fn detect_transfers(&self) -> Result<TransferSummary, StoreError> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;

        let inputs = load_transfer_inputs(&tx)?;
        let pairs = crate::transfer::detect_transfers(&inputs);

        let mut summary = TransferSummary::default();
        {
            let mut update = tx.prepare(
                "UPDATE transactions \
                 SET is_transfer = 1, transfer_group_id = ?2, category_id = ?3, \
                     categorised_by = ?4 \
                 WHERE id = ?1 AND transfer_group_id IS NULL",
            )?;
            for pair in &pairs {
                let group_id = mint_id(&tx)?;
                let category = if pair.is_credit_card_payment {
                    CREDIT_CARD_BILL_PAYMENT
                } else {
                    SELF_TRANSFER
                };
                update.execute(params![
                    pair.outflow_id,
                    group_id,
                    category,
                    TRANSFER_DETECTOR
                ])?;
                update.execute(params![
                    pair.inflow_id,
                    group_id,
                    category,
                    TRANSFER_DETECTOR
                ])?;
                summary.pairs_linked += 1;
                if pair.is_credit_card_payment {
                    summary.credit_card_payments += 1;
                }
            }
        }
        tx.commit()?;
        Ok(summary)
    }

    /// Link cross-source duplicate transactions across **all** accounts.
    ///
    /// The same spend often lands in the store twice — once from a bank ledger and once from
    /// the card statement it settled on. Candidate rows (non-deleted, not already superseded)
    /// are grouped by account and walked **oldest account first** (by the account's
    /// `created_at`, tie-broken on `id`): each account's rows are the matcher's `incoming`,
    /// compared against the accumulated rows of every earlier-created account (`existing`).
    /// The survivor is therefore always the row from the account that was imported first, which
    /// keeps the outcome stable across re-runs. Rows on the **same** account are never compared
    /// — a genuine repeat within one statement is not a cross-source duplicate.
    ///
    /// Each duplicate is **linked, not deleted**: the loser gets `superseded_by` = the
    /// survivor's id and `dedup_layer` = the layer that caught it. A survivor that is itself
    /// consumed by a match is withdrawn from the pool, so multiplicity is respected globally
    /// (two real repeats can only absorb two duplicates). Idempotent: already-linked rows are
    /// excluded from the candidate load and the UPDATE is guarded by `superseded_by IS NULL`.
    pub fn find_duplicates(&self) -> Result<DedupSummary, StoreError> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let summary = find_duplicates_in(&tx)?;
        tx.commit()?;
        Ok(summary)
    }

    /// The rolling 24-month coverage map for one account — which months are GAP / PARTIAL /
    /// COVERED, and which COVERED months carry a needs-review badge.
    ///
    /// A **report, not a write-back**: it loads the account's statements and its non-deleted
    /// transactions, derives each row's `from_full_statement` from its `statement_id` (a row
    /// counts as fully-covered only when its statement's `source` is `Statement`, never an
    /// `Alert`), and runs the pure [`crate::coverage::compute_coverage`]. `today` is an explicit
    /// parameter — the core never reads the wall-clock (Constitution II), so the platform decides
    /// where the window ends and the result is reproducible.
    pub fn coverage(
        &self,
        account_id: String,
        today: NaiveDate,
    ) -> Result<Vec<MonthCoverage>, StoreError> {
        let conn = self.lock();
        let statements = load_statement_coverage(&conn, &account_id)?;
        let transactions = load_transaction_coverage(&conn, &account_id)?;
        Ok(crate::coverage::compute_coverage(
            today,
            &statements,
            &transactions,
        ))
    }
}

impl Store {
    /// Lock the connection. The mutex is only poisoned if a prior holder panicked while
    /// holding it; recover the guard rather than propagating the panic across the FFI.
    fn lock(&self) -> std::sync::MutexGuard<'_, Connection> {
        self.conn.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// The database's current schema version (`PRAGMA user_version`). Not part of the FFI
    /// surface; useful for diagnostics and migration tests.
    pub fn schema_version(&self) -> Result<i64, StoreError> {
        let conn = self.lock();
        Ok(conn.pragma_query_value(None, "user_version", |row| row.get(0))?)
    }

    /// Apply every pending forward-only migration inside a transaction, bumping
    /// `PRAGMA user_version`. Idempotent: an up-to-date database is a no-op.
    fn migrate(&self) -> Result<(), StoreError> {
        let mut conn = self.lock();
        let mut version: i64 = conn.pragma_query_value(None, "user_version", |row| row.get(0))?;

        while version < SCHEMA_VERSION {
            let next = version + 1;
            let tx = conn.transaction().map_err(StoreError::migration)?;
            apply_migration(&tx, next)?;
            // user_version participates in the transaction (header page) and is rolled
            // back with it on failure.
            tx.pragma_update(None, "user_version", next)
                .map_err(StoreError::migration)?;
            tx.commit().map_err(StoreError::migration)?;
            version = next;
        }
        Ok(())
    }
}

/// Categorize account rows inside an already-open SQLite transaction.
#[doc(hidden)]
pub fn categorize_account_in(
    tx: &rusqlite::Transaction<'_>,
    account_id: &str,
) -> Result<CategorizeSummary, StoreError> {
    let account: Option<(String, bool)> = tx
        .query_row(
            "SELECT bank_code, is_credit_card FROM accounts WHERE id = ?1",
            params![account_id],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)? != 0)),
        )
        .optional()?;
    let Some((bank_code, is_credit_card)) = account else {
        return Ok(CategorizeSummary::default());
    };

    let catalog = load_categories(tx)?;
    let merchants = crate::categorize::prepare_merchants(&load_merchant_rules(tx)?);
    let rules = crate::categorize::prepare_rules(&load_rules(tx)?);
    let source_map = load_source_category_mappings(tx)?;
    let pending = load_account_transactions(tx, account_id, &bank_code, is_credit_card)?;

    let mut summary = CategorizeSummary::default();
    {
        let mut update = tx.prepare(
            "UPDATE transactions SET category_id = ?2, categorised_by = ?3 WHERE id = ?1",
        )?;
        for (txn_id, txn) in &pending {
            match crate::categorize::categorize(txn, &catalog, &merchants, &rules, &source_map) {
                Some(decision) => {
                    update.execute(params![
                        txn_id,
                        category_ref_to_id(&decision.category_ref),
                        stage_to_sql(decision.stage),
                    ])?;
                    summary.categorized += 1;
                }
                None => {
                    update.execute(params![
                        txn_id,
                        Option::<String>::None,
                        Option::<String>::None,
                    ])?;
                    summary.uncategorized += 1;
                }
            }
        }
    }
    Ok(summary)
}

/// How many rows of one statement the person actually has, right now.
///
/// Counted from the rows rather than derived from what linking reported, and built from
/// `live_predicate!()` so it cannot drift from every other read that means "the rows the person
/// has" (`.scratch/016-statement-import-vertical/issues/07`).
fn count_live_statement_rows_in(
    tx: &rusqlite::Transaction<'_>,
    statement_id: &str,
) -> Result<u32, StoreError> {
    let count: i64 = tx.query_row(
        concat!(
            "SELECT COUNT(*) FROM transactions WHERE statement_id = ?1 AND ",
            live_predicate!()
        ),
        params![statement_id],
        |row| row.get(0),
    )?;
    Ok(count as u32)
}

/// Link the rows of a just-inserted statement to rows the same account already had.
///
/// The cross-source de-duplication in [`find_duplicates_in`] compares accounts against each
/// other and never an account against itself, which is right for a spend seen on both a bank
/// ledger and a card — but it leaves the commonest mistake unanswered: picking the same
/// statement twice. Without this, a person's month quietly doubles.
///
/// Only the **canonical** layer counts here — same date, same amount, same direction, same
/// narration — because within one account the fuzzy layer (±1 day, near-identical text) would
/// happily merge two genuine purchases of the same thing. Two identical rows *inside* one
/// statement stay separate: they are both incoming, and only earlier statements are candidates.
fn link_reimported_rows_in(
    tx: &rusqlite::Transaction<'_>,
    account_id: &str,
    statement_id: &str,
) -> Result<u32, StoreError> {
    let existing = load_account_rows(tx, account_id, statement_id, false)?;
    let incoming = load_account_rows(tx, account_id, statement_id, true)?;
    if existing.is_empty() || incoming.is_empty() {
        return Ok(0);
    }

    let existing_txns: Vec<Transaction> = existing.iter().map(|(_, t)| t.clone()).collect();
    let incoming_txns: Vec<Transaction> = incoming.iter().map(|(_, t)| t.clone()).collect();

    let mut update = tx.prepare(
        "UPDATE transactions SET superseded_by = ?2, dedup_layer = ?3 \
         WHERE id = ?1 AND superseded_by IS NULL",
    )?;
    let mut linked = 0;
    for m in crate::dedup::cross_source_duplicates(&existing_txns, &incoming_txns) {
        if m.layer != DedupLayer::Canonical {
            continue;
        }
        let (loser_id, _) = &incoming[m.incoming_index as usize];
        let (winner_id, _) = &existing[m.existing_index as usize];
        linked += update.execute(params![
            loser_id,
            winner_id,
            dedup_layer_to_sql(DedupLayer::Canonical)
        ])? as u32;
    }
    Ok(linked)
}

/// One account's live rows, either from the statement just imported or from every other
/// source it already had. Oldest first, so the row a person already has always wins.
fn load_account_rows(
    tx: &rusqlite::Transaction<'_>,
    account_id: &str,
    statement_id: &str,
    from_this_statement: bool,
) -> Result<Vec<(String, Transaction)>, StoreError> {
    let sql = if from_this_statement {
        "SELECT id, date, description_raw, amount, direction FROM transactions \
         WHERE account_id = ?1 AND statement_id = ?2 \
           AND is_deleted = 0 AND superseded_by IS NULL ORDER BY rowid"
    } else {
        "SELECT id, date, description_raw, amount, direction FROM transactions \
         WHERE account_id = ?1 AND (statement_id IS NULL OR statement_id != ?2) \
           AND is_deleted = 0 AND superseded_by IS NULL ORDER BY rowid"
    };
    let mut stmt = tx.prepare(sql)?;
    let raw = stmt
        .query_map(params![account_id, statement_id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;

    raw.into_iter()
        .map(|(id, date, description, amount, direction)| {
            Ok((
                id,
                Transaction::new(
                    date_from_sql(&date)?,
                    description,
                    amount_from_sql(&amount)?,
                    direction_from_sql(&direction)?,
                ),
            ))
        })
        .collect()
}

/// Link duplicate rows inside an already-open SQLite transaction.
#[doc(hidden)]
pub fn find_duplicates_in(tx: &rusqlite::Transaction<'_>) -> Result<DedupSummary, StoreError> {
    let by_account = load_dedup_candidates(tx)?;
    let mut links: Vec<(String, String, DedupLayer)> = Vec::new();
    let mut pool: Vec<(String, Transaction, bool)> = Vec::new();

    for DedupGroup {
        is_credit_card: incoming_is_card,
        rows: incoming,
    } in by_account
    {
        // ⚠️ Only a bank ledger against a credit card, never two of a kind. Slice 013 exists
        // for one purchase that appears in *two different sources* — a spend showing up on
        // both a ledger and a card statement. Two cards printing the same coffee on the same
        // day are two real purchases, and collapsing them hides money a person actually spent.
        // The matcher itself is untouched; this decides only which pairs it is asked about.
        let candidates: Vec<usize> = pool
            .iter()
            .enumerate()
            .filter(|(_, (_, _, is_card))| *is_card != incoming_is_card)
            .map(|(index, _)| index)
            .collect();

        let existing_txns: Vec<Transaction> = candidates
            .iter()
            .map(|&index| pool[index].1.clone())
            .collect();
        let incoming_txns: Vec<Transaction> = incoming.iter().map(|(_, t)| t.clone()).collect();
        let matches = crate::dedup::cross_source_duplicates(&existing_txns, &incoming_txns);

        let mut consumed = vec![false; pool.len()];
        let mut superseded = vec![false; incoming.len()];
        for CrossSourceMatch {
            incoming_index,
            existing_index,
            layer,
        } in matches
        {
            // `existing_index` indexes the filtered list handed to the matcher, not the pool.
            let winner = candidates[existing_index as usize];
            let (loser_id, _) = &incoming[incoming_index as usize];
            let (winner_id, _, _) = &pool[winner];
            links.push((loser_id.clone(), winner_id.clone(), layer));
            consumed[winner] = true;
            superseded[incoming_index as usize] = true;
        }

        let mut kept = 0;
        pool.retain(|_| {
            let keep = !consumed[kept];
            kept += 1;
            keep
        });
        pool.extend(
            incoming
                .into_iter()
                .zip(superseded)
                .filter(|(_, dup)| !dup)
                .map(|((id, txn), _)| (id, txn, incoming_is_card)),
        );
    }

    let mut summary = DedupSummary::default();
    {
        let mut update = tx.prepare(
            "UPDATE transactions SET superseded_by = ?2, dedup_layer = ?3 \
             WHERE id = ?1 AND superseded_by IS NULL",
        )?;
        for (loser_id, winner_id, layer) in &links {
            update.execute(params![loser_id, winner_id, dedup_layer_to_sql(*layer)])?;
            summary.duplicates_linked += 1;
            match layer {
                DedupLayer::Canonical => summary.canonical += 1,
                DedupLayer::Fuzzy => summary.fuzzy += 1,
            }
        }
    }
    Ok(summary)
}

/// Apply the single migration that lifts the schema to `version`.
fn apply_migration(tx: &rusqlite::Transaction<'_>, version: i64) -> Result<(), StoreError> {
    match version {
        1 => {
            tx.execute_batch(SCHEMA_V1).map_err(StoreError::migration)?;
            seed_categories(tx)?;
            Ok(())
        }
        2 => {
            tx.execute_batch(SCHEMA_V2).map_err(StoreError::migration)?;
            Ok(())
        }
        3 => {
            tx.execute_batch(SCHEMA_V3).map_err(StoreError::migration)?;
            Ok(())
        }
        4 => {
            tx.execute_batch(SCHEMA_V4).map_err(StoreError::migration)?;
            Ok(())
        }
        5 => {
            tx.execute_batch(SCHEMA_V5).map_err(StoreError::migration)?;
            Ok(())
        }
        6 => {
            tx.execute_batch(SCHEMA_V6).map_err(StoreError::migration)?;
            Ok(())
        }
        7 => {
            tx.execute_batch(SCHEMA_V7).map_err(StoreError::migration)?;
            Ok(())
        }
        other => Err(StoreError::Migration {
            message: format!("no migration defined for schema version {other}"),
        }),
    }
}

/// Seed the `categories` table from the ported [`default_categories`] (the 23 builtins:
/// stable code as id + display name + classification).
fn seed_categories(tx: &rusqlite::Transaction<'_>) -> Result<(), StoreError> {
    let mut stmt = tx.prepare(
        "INSERT INTO categories (id, name, classification, is_builtin) VALUES (?1, ?2, ?3, 1)",
    )?;
    for category in default_categories() {
        let CategoryRef::Builtin { code } = &category.category_ref else {
            continue;
        };
        let classification = category
            .classification
            .map(classification_to_sql)
            .ok_or_else(|| StoreError::Migration {
                message: format!("builtin category {code} has no classification"),
            })?;
        stmt.execute(params![code, category.name, classification])?;
    }
    Ok(())
}

/// The largest page the history will hand back at once. A larger one defeats the point of
/// paging; a smaller one is the caller's business.
const MAX_PAGE: u32 = 200;

/// The identity cursor's date — later than any date a statement can carry, so a first page is
/// the same statement, with the same bindings, as every page after it.
const IDENTITY_DATE: &str = "9999-12-31";

/// One account's slice of the merge: rows already read and sorted, and where to resume.
struct Stream {
    account_id: String,
    /// The account's index in [`Store::list_accounts`] — the history's account tie-break.
    position: usize,
    /// True when the account's own query returned fewer rows than asked for, so there is
    /// nothing beyond what is already in `pending`.
    exhausted: bool,
    pending: std::collections::VecDeque<Pending>,
    /// `(date, rowid)` of the last row emitted from this account — the resume point.
    resume: (String, i64),
}

/// A row read from one account's stream, with the `rowid` the order needs and the caller
/// must never see.
struct Pending {
    row: HistoryRow,
    rowid: i64,
}

/// The combined history's order, and the only place it is expressed outside SQL: `date`
/// descending, then the account's position in [`Store::list_accounts`] ascending, then
/// `transactions.rowid` ascending (`data-model.md` §2).
///
/// Every component is present on every live row and `rowid` is unique, so the order is strict
/// and total — which is what makes "the same store always reads the same way" provable rather
/// than argued.
fn history_order(
    left: (NaiveDate, usize, i64),
    right: (NaiveDate, usize, i64),
) -> std::cmp::Ordering {
    right
        .0
        .cmp(&left.0)
        .then(left.1.cmp(&right.1))
        .then(left.2.cmp(&right.2))
}

/// Map one [`PAGE_SQL`] row to a [`HistoryRow`] plus its `rowid`. The account's name and last-4
/// and the category's display name are resolved from maps read once per call — a JOIN would
/// change the query plan and cost the page its index.
fn map_history_row(
    row: &rusqlite::Row<'_>,
    account: &StoredAccount,
    categories: &std::collections::HashMap<String, String>,
) -> Result<(HistoryRow, i64), StoreError> {
    let date: String = row.get(2)?;
    let amount: String = row.get(4)?;
    let direction: String = row.get(5)?;
    let category_id: Option<String> = row.get(7)?;
    Ok((
        HistoryRow {
            id: row.get(0)?,
            account_id: row.get(1)?,
            account_name: account.name.clone(),
            account_last4: account.last4.clone(),
            date: date_from_sql(&date)?,
            description_raw: row.get(3)?,
            amount: amount_from_sql(&amount)?,
            direction: direction_from_sql(&direction)?,
            currency: row.get(6)?,
            category_name: category_id.and_then(|id| categories.get(&id).cloned()),
            is_transfer: row.get::<_, i64>(8)? != 0,
        },
        row.get(9)?,
    ))
}

/// Every account in `accounts.rowid` order — the front door's order, and the history's
/// account tie-break. Takes a connection rather than the lock, so a read that already holds
/// it cannot deadlock against itself.
fn list_accounts_in(conn: &Connection) -> Result<Vec<StoredAccount>, StoreError> {
    let mut stmt = conn.prepare(
        "SELECT id, name, bank_code, is_credit_card, last4, currency, created_at, updated_at \
         FROM accounts ORDER BY rowid",
    )?;
    let rows = stmt
        .query_map([], map_account)?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

/// Map one `accounts` row. Nothing here can fail to parse, so it is infallible.
fn map_account(row: &rusqlite::Row<'_>) -> rusqlite::Result<StoredAccount> {
    Ok(StoredAccount {
        id: row.get(0)?,
        name: row.get(1)?,
        bank_code: row.get(2)?,
        is_credit_card: row.get::<_, i64>(3)? != 0,
        last4: row.get(4)?,
        currency: row.get(5)?,
        created_at: row.get(6)?,
        updated_at: row.get(7)?,
    })
}

/// Category id → display name, read once per history page.
fn category_names_in(
    conn: &Connection,
) -> Result<std::collections::HashMap<String, String>, StoreError> {
    let mut stmt = conn.prepare("SELECT id, name FROM categories")?;
    let rows = stmt
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows.into_iter().collect())
}

/// Transactions per account under `predicate`, which is either [`LIVE`] or nothing at all.
fn grouped_counts(
    conn: &Connection,
    predicate: &str,
) -> Result<std::collections::HashMap<String, u32>, StoreError> {
    let mut stmt = conn.prepare(&format!(
        "SELECT account_id, count(*) FROM transactions WHERE {predicate} GROUP BY account_id"
    ))?;
    let rows = stmt
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)? as u32))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows.into_iter().collect())
}

/// Mint a fresh 128-bit opaque id (lowercase hex) using SQLite's own PRNG, so the core
/// needs no random-number dependency of its own.
fn mint_id(conn: &Connection) -> Result<String, StoreError> {
    let id = conn.query_row("SELECT lower(hex(randomblob(16)))", [], |row| row.get(0))?;
    Ok(id)
}

/// Map one `transactions` row to a [`StoredTransaction`]. The inner `Result` carries a
/// parse failure (a corrupt amount/date/direction) as a [`StoreError`] without panicking.
type RowResult = Result<StoredTransaction, StoreError>;

fn map_transaction(row: &rusqlite::Row<'_>) -> rusqlite::Result<RowResult> {
    let amount: String = row.get(4)?;
    let date: String = row.get(2)?;
    let direction: String = row.get(5)?;
    Ok((|| {
        Ok(StoredTransaction {
            id: row.get(0)?,
            account_id: row.get(1)?,
            date: date_from_sql(&date)?,
            description_raw: row.get(3)?,
            amount: amount_from_sql(&amount)?,
            direction: direction_from_sql(&direction)?,
            currency: row.get(6)?,
            category_id: row.get(7)?,
            categorised_by: row.get(8)?,
            is_deleted: row.get::<_, i64>(9)? != 0,
            created_at: row.get(10)?,
            updated_at: row.get(11)?,
            source_category: row.get(12)?,
            is_transfer: row.get::<_, i64>(13)? != 0,
            transfer_group_id: row.get(14)?,
            superseded_by: row.get(15)?,
            dedup_layer: row
                .get::<_, Option<String>>(16)?
                .map(|l| dedup_layer_from_sql(&l))
                .transpose()?,
            statement_id: row.get(17)?,
        })
    })())
}

/// Load one account's non-deleted, non-transfer transactions as `(id, CategoryTxn)` pairs ready
/// for the categorization stack. `bank_code`/`is_credit_card` come from the owning account; the
/// rest from each row (the issuer's `source_category` hint feeds T1). Transfer legs are excluded
/// so the stack never overwrites the category the transfer detector assigned them.
fn load_account_transactions(
    conn: &Connection,
    account_id: &str,
    bank_code: &str,
    is_credit_card: bool,
) -> Result<Vec<(String, CategoryTxn)>, StoreError> {
    let mut stmt = conn.prepare(concat!(
        "SELECT id, source_category, description_raw, amount, direction \
         FROM transactions \
         WHERE account_id = ?1 AND ",
        // Built from the same literal as the v7 index and `PAGE_SQL`, because this load ran for
        // a long time with only half the rule and reported superseded losers as part of the
        // account (`.scratch/016-statement-import-vertical/issues/04`).
        live_predicate!(),
        " AND is_transfer = 0 ORDER BY rowid",
    ))?;
    let raw = stmt
        .query_map(params![account_id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, Option<String>>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    raw.into_iter()
        .map(|(id, source_category, description, amount, direction)| {
            Ok((
                id,
                CategoryTxn {
                    bank_code: bank_code.to_string(),
                    is_credit_card,
                    source_category,
                    description,
                    amount: amount_from_sql(&amount)?,
                    direction: direction_from_sql(&direction)?,
                },
            ))
        })
        .collect()
}

/// Load every non-deleted, not-yet-linked transaction across **all** accounts as
/// [`TransferInput`]s for the transfer matcher, joined to each row's owning account for
/// `is_credit_card`. Already-linked rows (`transfer_group_id` set) are excluded so re-running
/// detection is idempotent. Oldest first (deterministic input order).
fn load_transfer_inputs(conn: &Connection) -> Result<Vec<TransferInput>, StoreError> {
    let mut stmt = conn.prepare(
        "SELECT t.id, t.account_id, a.is_credit_card, t.date, t.amount, t.direction, \
                t.description_raw \
         FROM transactions t JOIN accounts a ON a.id = t.account_id \
         WHERE t.is_deleted = 0 AND t.transfer_group_id IS NULL \
         ORDER BY t.rowid",
    )?;
    let raw = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)? != 0,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, String>(5)?,
                row.get::<_, String>(6)?,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    raw.into_iter()
        .map(
            |(id, account_id, is_credit_card, date, amount, direction, description)| {
                Ok(TransferInput {
                    id,
                    account_id,
                    is_credit_card,
                    date: date_from_sql(&date)?,
                    amount: amount_from_sql(&amount)?,
                    direction: direction_from_sql(&direction)?,
                    description,
                })
            },
        )
        .collect()
}

/// One account's de-duplication candidates, tagged with the kind of account they came from.
///
/// The tag is load-bearing: [`find_duplicates_in`] may only compare a bank ledger against a
/// credit card, never two of a kind.
struct DedupGroup {
    is_credit_card: bool,
    rows: Vec<(String, Transaction)>,
}

/// Load the de-duplication candidates — every non-deleted row that is not already linked as a
/// duplicate — as one [`DedupGroup`] per account, **in the order the person sees their
/// accounts**.
///
/// The grouping is what turns the pure matcher's two-list contract into a store-wide sweep, and
/// the group order decides which side of a duplicate survives. That order is `accounts.rowid` —
/// the same single ordering [`Store::list_accounts`] uses, so the row that survives always
/// belongs to the account shown first.
///
/// ⚠️ It used to be `a.created_at, a.id`. Two accounts created by one import share a
/// `created_at` to the second, so the tie-break fell through to `a.id`, which is
/// `lower(hex(randomblob(16)))` — and *which* of a person's rows disappeared was decided by 128
/// random bits, differently on every fresh database. `rowid` is total and monotonic, so there is
/// nothing left to tie-break.
fn load_dedup_candidates(conn: &Connection) -> Result<Vec<DedupGroup>, StoreError> {
    let mut stmt = conn.prepare(
        "SELECT t.account_id, t.id, t.date, t.description_raw, t.amount, t.direction, \
                a.is_credit_card \
         FROM transactions t JOIN accounts a ON a.id = t.account_id \
         WHERE t.is_deleted = 0 AND t.superseded_by IS NULL \
         ORDER BY a.rowid, t.rowid",
    )?;
    let raw = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, String>(5)?,
                row.get::<_, i64>(6)? != 0,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;

    let mut grouped: Vec<DedupGroup> = Vec::new();
    let mut current_account: Option<String> = None;
    for (account_id, id, date, description, amount, direction, is_credit_card) in raw {
        let txn = Transaction::new(
            date_from_sql(&date)?,
            description,
            amount_from_sql(&amount)?,
            direction_from_sql(&direction)?,
        );
        if current_account.as_deref() != Some(account_id.as_str()) {
            grouped.push(DedupGroup {
                is_credit_card,
                rows: Vec::new(),
            });
            current_account = Some(account_id);
        }
        grouped
            .last_mut()
            .expect("a group was just pushed for this account")
            .rows
            .push((id, txn));
    }
    Ok(grouped)
}

/// Load one account's statements as [`StatementCoverage`] facts. Only the period-end (which
/// attributes the statement to its calendar month) and the needs-review badge matter to the
/// coverage classifier; `Alert`-sourced runs are excluded because a live alert does not cover a
/// month, it merely populates one.
fn load_statement_coverage(
    conn: &Connection,
    account_id: &str,
) -> Result<Vec<StatementCoverage>, StoreError> {
    let mut stmt = conn.prepare(
        "SELECT period_end, needs_review FROM statements \
         WHERE account_id = ?1 AND source = 'Statement' ORDER BY rowid",
    )?;
    let raw = stmt
        .query_map(params![account_id], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)? != 0))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    raw.into_iter()
        .map(|(period_end, needs_review)| {
            Ok(StatementCoverage {
                period_end: date_from_sql(&period_end)?,
                needs_review,
            })
        })
        .collect()
}

/// Load one account's non-deleted transactions as [`TransactionCoverage`] facts.
/// `from_full_statement` is **derived**, never stored: a row qualifies when its `statement_id`
/// resolves to a statement whose `source` is `'Statement'`, so a live-alert row (no statement, or
/// an `Alert` run) leaves its month PARTIAL.
fn load_transaction_coverage(
    conn: &Connection,
    account_id: &str,
) -> Result<Vec<TransactionCoverage>, StoreError> {
    let mut stmt = conn.prepare(
        "SELECT t.date, s.id IS NOT NULL \
         FROM transactions t \
         LEFT JOIN statements s ON s.id = t.statement_id AND s.source = 'Statement' \
         WHERE t.account_id = ?1 AND t.is_deleted = 0 ORDER BY t.rowid",
    )?;
    let raw = stmt
        .query_map(params![account_id], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)? != 0))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    raw.into_iter()
        .map(|(date, from_full_statement)| {
            Ok(TransactionCoverage {
                date: date_from_sql(&date)?,
                from_full_statement,
            })
        })
        .collect()
}

/// The category catalog (built-ins + user categories), oldest first.
fn load_categories(conn: &Connection) -> Result<Vec<Category>, StoreError> {
    let mut stmt =
        conn.prepare("SELECT id, name, classification, is_builtin FROM categories ORDER BY rowid")?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, i64>(3)? != 0,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    rows.into_iter()
        .map(|(id, name, classification, is_builtin)| {
            Ok(Category {
                category_ref: category_ref_from_parts(id, is_builtin),
                name,
                classification: Some(classification_from_sql(&classification)?),
            })
        })
        .collect()
}

/// The T2 merchant map, priority order (lowest first), with each entry's `CategoryRef`
/// reconstructed from the joined category's `is_builtin` flag.
fn load_merchant_rules(conn: &Connection) -> Result<Vec<MerchantRule>, StoreError> {
    let mut stmt = conn.prepare(
        "SELECT m.priority, m.match_type, m.pattern, m.category_id, c.is_builtin \
         FROM merchant_map m JOIN categories c ON c.id = m.category_id \
         ORDER BY m.priority, m.id",
    )?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, i64>(4)? != 0,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    rows.into_iter()
        .map(|(priority, match_type, pattern, category_id, is_builtin)| {
            Ok(MerchantRule {
                priority,
                match_type: merchant_match_from_sql(&match_type)?,
                pattern,
                category: category_ref_from_parts(category_id, is_builtin),
            })
        })
        .collect()
}

/// The T1 source-category map, insertion order.
fn load_source_category_mappings(
    conn: &Connection,
) -> Result<Vec<SourceCategoryMapping>, StoreError> {
    let mut stmt = conn.prepare(
        "SELECT s.bank_code, s.source_category, s.category_id, c.is_builtin \
         FROM source_category_map s JOIN categories c ON c.id = s.category_id \
         ORDER BY s.id",
    )?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, i64>(3)? != 0,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    rows.into_iter()
        .map(|(bank_code, source_category, category_id, is_builtin)| {
            Ok(SourceCategoryMapping {
                bank_code,
                source_category,
                category: category_ref_from_parts(category_id, is_builtin),
            })
        })
        .collect()
}

/// The T3 rules, priority order (lowest first). Each stored id surfaces as `Some(id)`.
fn load_rules(conn: &Connection) -> Result<Vec<Rule>, StoreError> {
    let mut stmt = conn.prepare(
        "SELECT r.id, r.priority, r.is_system, r.match_type, r.value, r.category_id, \
                c.is_builtin \
         FROM rules r JOIN categories c ON c.id = r.category_id \
         ORDER BY r.priority, r.id",
    )?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, i64>(2)? != 0,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, String>(5)?,
                row.get::<_, i64>(6)? != 0,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    rows.into_iter()
        .map(
            |(id, priority, is_system, match_type, value, category_id, is_builtin)| {
                Ok(Rule {
                    id: Some(id),
                    priority,
                    is_system,
                    match_type: rule_match_from_sql(&match_type)?,
                    value,
                    category: category_ref_from_parts(category_id, is_builtin),
                })
            },
        )
        .collect()
}

/// Reconstruct a [`CategoryRef`] from a stored `category_id` + its `is_builtin` flag: a
/// built-in id *is* its stable code, a user id is opaque.
fn category_ref_from_parts(id: String, is_builtin: bool) -> CategoryRef {
    if is_builtin {
        CategoryRef::Builtin { code: id }
    } else {
        CategoryRef::Custom { id }
    }
}

/// The `categories.id` a [`CategoryRef`] stores as (the built-in code, or the user id).
fn category_ref_to_id(category: &CategoryRef) -> &str {
    match category {
        CategoryRef::Builtin { code } => code,
        CategoryRef::Custom { id } => id,
    }
}

fn merchant_match_to_sql(match_type: MerchantMatch) -> &'static str {
    match match_type {
        MerchantMatch::Literal => "Literal",
        MerchantMatch::Regex => "Regex",
    }
}

fn merchant_match_from_sql(value: &str) -> Result<MerchantMatch, StoreError> {
    match value {
        "Literal" => Ok(MerchantMatch::Literal),
        "Regex" => Ok(MerchantMatch::Regex),
        other => Err(StoreError::Sql {
            message: format!("unknown merchant match type {other:?}"),
        }),
    }
}

fn rule_match_to_sql(match_type: RuleMatch) -> &'static str {
    match match_type {
        RuleMatch::Keyword => "Keyword",
        RuleMatch::Regex => "Regex",
        RuleMatch::AmountRange => "AmountRange",
    }
}

fn rule_match_from_sql(value: &str) -> Result<RuleMatch, StoreError> {
    match value {
        "Keyword" => Ok(RuleMatch::Keyword),
        "Regex" => Ok(RuleMatch::Regex),
        "AmountRange" => Ok(RuleMatch::AmountRange),
        other => Err(StoreError::Sql {
            message: format!("unknown rule match type {other:?}"),
        }),
    }
}

fn stage_to_sql(stage: Stage) -> &'static str {
    match stage {
        Stage::CcRule => "CC_RULE",
        Stage::T1SourceCategory => "T1_SOURCE_CATEGORY",
        Stage::T2MerchantMap => "T2_MERCHANT_MAP",
        Stage::T3Rule => "T3_RULE",
    }
}

/// Validate a 256-bit hex key: exactly 64 ASCII hex digits.
fn validate_key(key: &str) -> Result<(), StoreError> {
    if key.len() == 64 && key.bytes().all(|b| b.is_ascii_hexdigit()) {
        Ok(())
    } else {
        Err(StoreError::InvalidKey)
    }
}

fn direction_to_sql(direction: Direction) -> &'static str {
    match direction {
        Direction::Debit => "Debit",
        Direction::Credit => "Credit",
    }
}

fn direction_from_sql(value: &str) -> Result<Direction, StoreError> {
    match value {
        "Debit" => Ok(Direction::Debit),
        "Credit" => Ok(Direction::Credit),
        other => Err(StoreError::Sql {
            message: format!("unknown direction {other:?}"),
        }),
    }
}

/// Map one `statements` row to a [`StoredStatement`], carrying a corrupt date as a typed error
/// rather than panicking (the same inner-`Result` shape as [`map_transaction`]).
fn map_statement(row: &rusqlite::Row<'_>) -> rusqlite::Result<Result<StoredStatement, StoreError>> {
    let period_start: Option<String> = row.get(3)?;
    let period_end: String = row.get(4)?;
    let source: String = row.get(6)?;
    Ok((|| {
        Ok(StoredStatement {
            id: row.get(0)?,
            account_id: row.get(1)?,
            bank_code: row.get(2)?,
            period_start: period_start.as_deref().map(date_from_sql).transpose()?,
            period_end: date_from_sql(&period_end)?,
            needs_review: row.get::<_, i64>(5)? != 0,
            source: statement_source_from_sql(&source)?,
            created_at: row.get(7)?,
        })
    })())
}

/// `StatementSource` crosses SQL as its stable variant name, matching the v5 CHECK constraint.
fn statement_source_to_sql(source: StatementSource) -> &'static str {
    match source {
        StatementSource::Statement => "Statement",
        StatementSource::Alert => "Alert",
    }
}

fn statement_source_from_sql(value: &str) -> Result<StatementSource, StoreError> {
    match value {
        "Statement" => Ok(StatementSource::Statement),
        "Alert" => Ok(StatementSource::Alert),
        other => Err(StoreError::Sql {
            message: format!("unknown statement source {other:?}"),
        }),
    }
}

/// `DedupLayer` crosses SQL as its stable variant name, matching the v4 CHECK constraint.
fn dedup_layer_to_sql(layer: DedupLayer) -> &'static str {
    match layer {
        DedupLayer::Canonical => "Canonical",
        DedupLayer::Fuzzy => "Fuzzy",
    }
}

fn dedup_layer_from_sql(value: &str) -> Result<DedupLayer, StoreError> {
    match value {
        "Canonical" => Ok(DedupLayer::Canonical),
        "Fuzzy" => Ok(DedupLayer::Fuzzy),
        other => Err(StoreError::Sql {
            message: format!("unknown dedup layer {other:?}"),
        }),
    }
}

fn classification_to_sql(classification: Classification) -> &'static str {
    match classification {
        Classification::Spend => "SPEND",
        Classification::Income => "INCOME",
        Classification::Investment => "INVESTMENT",
        Classification::Transfer => "TRANSFER",
        Classification::CcPayment => "CC_PAYMENT",
        Classification::Refund => "REFUND",
    }
}

fn classification_from_sql(value: &str) -> Result<Classification, StoreError> {
    match value {
        "SPEND" => Ok(Classification::Spend),
        "INCOME" => Ok(Classification::Income),
        "INVESTMENT" => Ok(Classification::Investment),
        "TRANSFER" => Ok(Classification::Transfer),
        "CC_PAYMENT" => Ok(Classification::CcPayment),
        "REFUND" => Ok(Classification::Refund),
        other => Err(StoreError::Sql {
            message: format!("unknown classification {other:?}"),
        }),
    }
}

fn date_to_sql(date: NaiveDate) -> String {
    date.format("%Y-%m-%d").to_string()
}

/// A stored date that will not parse. The **value is never rendered** — a date is the
/// person's data, and an error message is the one place data leaks without anyone deciding
/// to show it (Constitution I, FR-063).
fn date_from_sql(value: &str) -> Result<NaiveDate, StoreError> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d").map_err(|_| StoreError::Sql {
        message: "invalid stored date".to_string(),
    })
}

/// A stored amount that will not parse. As with [`date_from_sql`], the value stays out of the
/// message: money is the most sensitive field the store holds.
fn amount_from_sql(value: &str) -> Result<Decimal, StoreError> {
    Decimal::from_str(value).map_err(|_| StoreError::Sql {
        message: "invalid stored amount".to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_key_accepts_64_hex_and_rejects_the_rest() {
        assert!(validate_key(&"a".repeat(64)).is_ok());
        assert!(validate_key(&"A1B2".repeat(16)).is_ok()); // mixed case, 64 chars
        assert!(matches!(validate_key(""), Err(StoreError::InvalidKey)));
        assert!(matches!(
            validate_key(&"a".repeat(63)),
            Err(StoreError::InvalidKey)
        ));
        assert!(matches!(
            validate_key(&"a".repeat(65)),
            Err(StoreError::InvalidKey)
        ));
        assert!(matches!(
            validate_key(&"g".repeat(64)),
            Err(StoreError::InvalidKey)
        ));
    }

    #[test]
    fn direction_round_trips_through_sql_text() {
        for direction in [Direction::Debit, Direction::Credit] {
            assert_eq!(
                direction_from_sql(direction_to_sql(direction)).unwrap(),
                direction
            );
        }
        assert!(direction_from_sql("Sideways").is_err());
    }

    #[test]
    fn classification_round_trips_through_sql_text() {
        for classification in [
            Classification::Spend,
            Classification::Income,
            Classification::Investment,
            Classification::Transfer,
            Classification::CcPayment,
            Classification::Refund,
        ] {
            assert_eq!(
                classification_from_sql(classification_to_sql(classification)).unwrap(),
                classification
            );
        }
        assert!(classification_from_sql("MYSTERY").is_err());
    }

    #[test]
    fn migrating_v1_to_v2_preserves_existing_rows() {
        let mut conn = Connection::open_in_memory().expect("in-memory db");

        // Build a populated v1 database, as an older app version would have left it.
        {
            let tx = conn.transaction().unwrap();
            apply_migration(&tx, 1).expect("apply v1");
            tx.pragma_update(None, "user_version", 1).unwrap();
            tx.execute(
                "INSERT INTO accounts \
                 (id, name, bank_code, is_credit_card, currency, created_at, updated_at) \
                 VALUES ('a1', 'Savings', 'HDFC', 0, 'INR', 't', 't')",
                [],
            )
            .unwrap();
            tx.execute(
                "INSERT INTO transactions \
                 (id, account_id, date, description_raw, amount, direction, currency, \
                  is_deleted, created_at, updated_at) \
                 VALUES ('t1', 'a1', '2026-07-04', 'desc', '1.00', 'Debit', 'INR', 0, 't', 't')",
                [],
            )
            .unwrap();
            tx.commit().unwrap();
        }

        // Upgrade v1 → v2: the `ALTER TABLE … ADD COLUMN` runs on a *populated* table.
        {
            let tx = conn.transaction().unwrap();
            apply_migration(&tx, 2).expect("apply v2");
            tx.pragma_update(None, "user_version", 2).unwrap();
            tx.commit().unwrap();
        }

        // The pre-existing row survived; its new `source_category` is NULL.
        let source_category: Option<String> = conn
            .query_row(
                "SELECT source_category FROM transactions WHERE id = 't1'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(source_category, None);
        let accounts: i64 = conn
            .query_row("SELECT count(*) FROM accounts", [], |row| row.get(0))
            .unwrap();
        assert_eq!(accounts, 1);
        // The new fact tables exist and their FK to a seeded category resolves.
        conn.execute(
            "INSERT INTO merchant_map (priority, match_type, pattern, category_id) \
             VALUES (1, 'Literal', 'x', 'GROCERIES')",
            [],
        )
        .expect("merchant_map usable after upgrade");
    }

    #[test]
    fn migrating_v2_to_v3_preserves_existing_rows() {
        let mut conn = Connection::open_in_memory().expect("in-memory db");

        // Build a populated v2 database (v1 schema + v2 facts), as an older app would leave it.
        {
            let tx = conn.transaction().unwrap();
            apply_migration(&tx, 1).expect("apply v1");
            apply_migration(&tx, 2).expect("apply v2");
            tx.pragma_update(None, "user_version", 2).unwrap();
            tx.execute(
                "INSERT INTO accounts \
                 (id, name, bank_code, is_credit_card, currency, created_at, updated_at) \
                 VALUES ('a1', 'Savings', 'HDFC', 0, 'INR', 't', 't')",
                [],
            )
            .unwrap();
            tx.execute(
                "INSERT INTO transactions \
                 (id, account_id, date, description_raw, amount, direction, currency, \
                  is_deleted, created_at, updated_at) \
                 VALUES ('t1', 'a1', '2026-07-04', 'desc', '1.00', 'Debit', 'INR', 0, 't', 't')",
                [],
            )
            .unwrap();
            tx.commit().unwrap();
        }

        // Upgrade v2 → v3: the transfer-identity `ADD COLUMN`s run on a *populated* table.
        {
            let tx = conn.transaction().unwrap();
            apply_migration(&tx, 3).expect("apply v3");
            tx.pragma_update(None, "user_version", 3).unwrap();
            tx.commit().unwrap();
        }

        // The pre-existing row survived; it defaults to a non-transfer with no group.
        let (is_transfer, group): (i64, Option<String>) = conn
            .query_row(
                "SELECT is_transfer, transfer_group_id FROM transactions WHERE id = 't1'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(is_transfer, 0);
        assert_eq!(group, None);
        let accounts: i64 = conn
            .query_row("SELECT count(*) FROM accounts", [], |row| row.get(0))
            .unwrap();
        assert_eq!(accounts, 1);
    }

    #[test]
    fn migrating_v3_to_v4_preserves_existing_rows() {
        let mut conn = Connection::open_in_memory().expect("in-memory db");

        // Build a populated v3 database, as an older app version would have left it.
        {
            let tx = conn.transaction().unwrap();
            for v in 1..=3 {
                apply_migration(&tx, v).expect("apply migration");
            }
            tx.pragma_update(None, "user_version", 3).unwrap();
            tx.execute(
                "INSERT INTO accounts \
                 (id, name, bank_code, is_credit_card, currency, created_at, updated_at) \
                 VALUES ('a1', 'Savings', 'HDFC', 0, 'INR', 't', 't')",
                [],
            )
            .unwrap();
            tx.execute(
                "INSERT INTO transactions \
                 (id, account_id, date, description_raw, amount, direction, currency, \
                  is_deleted, created_at, updated_at) \
                 VALUES ('t1', 'a1', '2026-07-04', 'desc', '1.00', 'Debit', 'INR', 0, 't', 't')",
                [],
            )
            .unwrap();
            tx.commit().unwrap();
        }

        // Upgrade v3 → v4: the duplicate-link `ADD COLUMN`s run on a *populated* table.
        {
            let tx = conn.transaction().unwrap();
            apply_migration(&tx, 4).expect("apply v4");
            tx.pragma_update(None, "user_version", 4).unwrap();
            tx.commit().unwrap();
        }

        // The pre-existing row survived and is nobody's duplicate.
        let (superseded_by, layer): (Option<String>, Option<String>) = conn
            .query_row(
                "SELECT superseded_by, dedup_layer FROM transactions WHERE id = 't1'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(superseded_by, None);
        assert_eq!(layer, None);
        let accounts: i64 = conn
            .query_row("SELECT count(*) FROM accounts", [], |row| row.get(0))
            .unwrap();
        assert_eq!(accounts, 1);
        // The CHECK constraint rejects a layer the core doesn't know.
        assert!(conn
            .execute(
                "UPDATE transactions SET dedup_layer = 'Telepathic' WHERE id = 't1'",
                [],
            )
            .is_err());
    }

    #[test]
    fn migrating_v4_to_v5_preserves_existing_rows() {
        let mut conn = Connection::open_in_memory().expect("in-memory db");

        // Build a populated v4 database, as an older app version would have left it.
        {
            let tx = conn.transaction().unwrap();
            for v in 1..=4 {
                apply_migration(&tx, v).expect("apply migration");
            }
            tx.pragma_update(None, "user_version", 4).unwrap();
            tx.execute(
                "INSERT INTO accounts \
                 (id, name, bank_code, is_credit_card, currency, created_at, updated_at) \
                 VALUES ('a1', 'Savings', 'HDFC', 0, 'INR', 't', 't')",
                [],
            )
            .unwrap();
            tx.execute(
                "INSERT INTO transactions \
                 (id, account_id, date, description_raw, amount, direction, currency, \
                  is_deleted, created_at, updated_at) \
                 VALUES ('t1', 'a1', '2026-07-04', 'desc', '1.00', 'Debit', 'INR', 0, 't', 't')",
                [],
            )
            .unwrap();
            tx.commit().unwrap();
        }

        // Upgrade v4 → v5: the new table + the provenance `ADD COLUMN` run on a *populated* DB.
        {
            let tx = conn.transaction().unwrap();
            apply_migration(&tx, 5).expect("apply v5");
            tx.pragma_update(None, "user_version", 5).unwrap();
            tx.commit().unwrap();
        }

        // The pre-existing row survived with no provenance (it predates statements).
        let statement_id: Option<String> = conn
            .query_row(
                "SELECT statement_id FROM transactions WHERE id = 't1'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(statement_id, None);
        // The new table is usable and its FK to the surviving account resolves.
        conn.execute(
            "INSERT INTO statements \
             (id, account_id, bank_code, period_start, period_end, needs_review, source, \
              created_at) \
             VALUES ('s1', 'a1', 'HDFC', NULL, '2026-07-31', 0, 'Statement', 't')",
            [],
        )
        .expect("statements usable after upgrade");
        // The CHECK constraint rejects a source the core doesn't know.
        assert!(conn
            .execute(
                "UPDATE statements SET source = 'Telepathy' WHERE id = 's1'",
                []
            )
            .is_err());
    }

    #[test]
    fn migrating_v5_to_v6_preserves_existing_rows() {
        let mut conn = Connection::open_in_memory().expect("in-memory db");

        {
            let tx = conn.transaction().unwrap();
            for v in 1..=5 {
                apply_migration(&tx, v).expect("apply migration");
            }
            tx.pragma_update(None, "user_version", 5).unwrap();
            tx.execute(
                "INSERT INTO accounts \
                 (id, name, bank_code, is_credit_card, currency, created_at, updated_at) \
                 VALUES ('a1', 'Savings', 'HDFC', 0, 'INR', 't', 't')",
                [],
            )
            .unwrap();
            tx.execute(
                "INSERT INTO statements \
                 (id, account_id, bank_code, period_start, period_end, needs_review, source, \
                  created_at) \
                 VALUES ('s1', 'a1', 'HDFC', '2026-07-01', '2026-07-31', 0, 'Statement', 't')",
                [],
            )
            .unwrap();
            tx.execute(
                "INSERT INTO transactions \
                 (id, account_id, date, description_raw, amount, direction, currency, \
                  is_deleted, statement_id, created_at, updated_at) \
                 VALUES ('t1', 'a1', '2026-07-04', 'desc', '1.00', 'Debit', 'INR', 0, 's1', 't', 't')",
                [],
            )
            .unwrap();
            tx.commit().unwrap();
        }

        {
            let tx = conn.transaction().unwrap();
            apply_migration(&tx, 6).expect("apply v6");
            tx.pragma_update(None, "user_version", 6).unwrap();
            tx.commit().unwrap();
        }

        let version: i64 = conn
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .unwrap();
        assert_eq!(version, 6);
        let last4: Option<String> = conn
            .query_row("SELECT last4 FROM accounts WHERE id = 'a1'", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(last4, None);
        let statement_count: i64 = conn
            .query_row("SELECT count(*) FROM statements", [], |row| row.get(0))
            .unwrap();
        assert_eq!(statement_count, 1);
        let transaction_statement_id: Option<String> = conn
            .query_row(
                "SELECT statement_id FROM transactions WHERE id = 't1'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(transaction_statement_id.as_deref(), Some("s1"));
    }

    #[test]
    fn migrating_v6_to_v7_preserves_existing_rows() {
        let mut conn = Connection::open_in_memory().expect("in-memory db");

        {
            let tx = conn.transaction().unwrap();
            for v in 1..=6 {
                apply_migration(&tx, v).expect("apply migration");
            }
            tx.pragma_update(None, "user_version", 6).unwrap();
            tx.execute(
                "INSERT INTO accounts \
                 (id, name, bank_code, is_credit_card, currency, last4, created_at, updated_at) \
                 VALUES ('a1', 'Savings', 'HDFC', 0, 'INR', '4321', 't', 't')",
                [],
            )
            .unwrap();
            tx.execute(
                "INSERT INTO statements \
                 (id, account_id, bank_code, period_start, period_end, needs_review, source, \
                  created_at) \
                 VALUES ('s1', 'a1', 'HDFC', '2026-07-01', '2026-07-31', 0, 'Statement', 't')",
                [],
            )
            .unwrap();
            tx.execute(
                "INSERT INTO transactions \
                 (id, account_id, date, description_raw, amount, direction, currency, \
                  is_deleted, statement_id, created_at, updated_at) \
                 VALUES ('t1', 'a1', '2026-07-04', 'desc', '1.00', 'Debit', 'INR', 0, 's1', 't', 't')",
                [],
            )
            .unwrap();
            tx.commit().unwrap();
        }

        {
            let tx = conn.transaction().unwrap();
            apply_migration(&tx, 7).expect("apply v7");
            tx.pragma_update(None, "user_version", 7).unwrap();
            tx.commit().unwrap();
        }

        let version: i64 = conn
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .unwrap();
        assert_eq!(version, 7);

        // M1: every pre-existing row survives byte-identically.
        let account: (String, String, Option<String>) = conn
            .query_row(
                "SELECT name, currency, last4 FROM accounts WHERE id = 'a1'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .unwrap();
        assert_eq!(
            account,
            ("Savings".into(), "INR".into(), Some("4321".into()))
        );
        let txn: (String, String, String, String, Option<String>) = conn
            .query_row(
                "SELECT date, description_raw, amount, direction, statement_id \
                 FROM transactions WHERE id = 't1'",
                [],
                |row| {
                    Ok((
                        row.get(0)?,
                        row.get(1)?,
                        row.get(2)?,
                        row.get(3)?,
                        row.get(4)?,
                    ))
                },
            )
            .unwrap();
        assert_eq!(
            txn,
            (
                "2026-07-04".into(),
                "desc".into(),
                "1.00".into(),
                "Debit".into(),
                Some("s1".into())
            )
        );
        let statement_count: i64 = conn
            .query_row("SELECT count(*) FROM statements", [], |row| row.get(0))
            .unwrap();
        assert_eq!(statement_count, 1);

        // M2: the v7 index exists, and carries its partial predicate.
        let index_sql: String = conn
            .query_row(
                "SELECT sql FROM sqlite_master \
                 WHERE type = 'index' AND name = 'idx_txn_live_account_date'",
                [],
                |row| row.get(0),
            )
            .expect("the v7 index exists");
        assert!(
            index_sql.contains("WHERE"),
            "the index must be partial, not whole-table: {index_sql}"
        );
        assert!(
            index_sql.contains("date DESC"),
            "the index must be descending by date: {index_sql}"
        );
    }

    #[test]
    fn the_live_constant_is_byte_identical_to_the_v7_index_predicate() {
        let mut conn = Connection::open_in_memory().expect("in-memory db");
        {
            let tx = conn.transaction().unwrap();
            for v in 1..=SCHEMA_VERSION {
                apply_migration(&tx, v).expect("apply migration");
            }
            tx.commit().unwrap();
        }

        let index_sql: String = conn
            .query_row(
                "SELECT sql FROM sqlite_master \
                 WHERE type = 'index' AND name = 'idx_txn_live_account_date'",
                [],
                |row| row.get(0),
            )
            .expect("the v7 index exists");

        let predicate = index_sql
            .split_once("WHERE")
            .expect("the index is partial")
            .1
            .trim()
            .trim_end_matches(';')
            .trim();
        assert_eq!(
            predicate, LIVE,
            "a read that paraphrases the live rule silently loses its index"
        );
    }

    #[test]
    fn the_history_order_is_total_and_antisymmetric() {
        use std::cmp::Ordering;

        let day = |d: u32| NaiveDate::from_ymd_opt(2026, 7, d).unwrap();
        let keys = [
            (day(4), 0, 1),
            (day(4), 0, 2),
            (day(4), 1, 1),
            (day(5), 0, 1),
            (day(5), 2, 9),
        ];

        for &left in &keys {
            assert_eq!(history_order(left, left), Ordering::Equal);
            for &right in &keys {
                if left == right {
                    continue;
                }
                // Total: no two distinct keys compare equal, because `rowid` is unique.
                assert_ne!(history_order(left, right), Ordering::Equal);
                // Antisymmetric.
                assert_eq!(
                    history_order(left, right).reverse(),
                    history_order(right, left)
                );
            }
        }

        // Level 1 — the later date comes first.
        assert_eq!(
            history_order((day(5), 3, 9), (day(4), 0, 1)),
            Ordering::Less
        );
        // Level 2 — same date, the account the front door lists first comes first.
        assert_eq!(
            history_order((day(4), 0, 9), (day(4), 1, 1)),
            Ordering::Less
        );
        // Level 3 — same date and account, printed (insertion) order.
        assert_eq!(
            history_order((day(4), 0, 1), (day(4), 0, 2)),
            Ordering::Less
        );
    }

    #[test]
    fn the_history_order_is_transitive_across_its_three_levels() {
        use std::cmp::Ordering;

        let day = |d: u32| NaiveDate::from_ymd_opt(2026, 7, d).unwrap();
        let mut keys = vec![
            (day(4), 1, 2),
            (day(6), 0, 1),
            (day(4), 0, 7),
            (day(6), 0, 3),
            (day(4), 1, 1),
        ];
        keys.sort_by(|a, b| history_order(*a, *b));
        assert_eq!(
            keys,
            vec![
                (day(6), 0, 1),
                (day(6), 0, 3),
                (day(4), 0, 7),
                (day(4), 1, 1),
                (day(4), 1, 2),
            ]
        );
        for pair in keys.windows(2) {
            assert_eq!(history_order(pair[0], pair[1]), Ordering::Less);
        }
    }

    #[test]
    fn statement_source_round_trips_through_sql_text() {
        for source in [StatementSource::Statement, StatementSource::Alert] {
            assert_eq!(
                statement_source_from_sql(statement_source_to_sql(source)).unwrap(),
                source
            );
        }
        assert!(statement_source_from_sql("Hearsay").is_err());
    }

    #[test]
    fn dedup_layer_round_trips_through_sql_text() {
        for layer in [DedupLayer::Canonical, DedupLayer::Fuzzy] {
            assert_eq!(
                dedup_layer_from_sql(dedup_layer_to_sql(layer)).unwrap(),
                layer
            );
        }
        assert!(dedup_layer_from_sql("Psychic").is_err());
    }

    #[test]
    fn load_dedup_candidates_groups_by_account_rowid_and_excludes_linked() {
        let mut conn = Connection::open_in_memory().expect("in-memory db");
        {
            let tx = conn.transaction().unwrap();
            for v in 1..=SCHEMA_VERSION {
                apply_migration(&tx, v).expect("apply migration");
            }
            tx.pragma_update(None, "user_version", SCHEMA_VERSION)
                .unwrap();
            // `newer` is inserted first and carries the later `created_at`. Ordering follows
            // `accounts.rowid` — insertion order, the same order `list_accounts` returns and
            // the person sees — so `newer` comes first and nothing is left to tie-break.
            tx.execute(
                "INSERT INTO accounts \
                 (id, name, bank_code, is_credit_card, currency, created_at, updated_at) \
                 VALUES ('newer', 'Card', 'HDFC', 1, 'INR', '2026-02-01', 't'), \
                        ('older', 'Savings', 'HDFC', 0, 'INR', '2026-01-01', 't')",
                [],
            )
            .unwrap();
            tx.execute_batch(
                "INSERT INTO transactions \
                   (id, account_id, date, description_raw, amount, direction, currency, \
                    is_deleted, superseded_by, created_at, updated_at) VALUES \
                   ('n1', 'newer', '2026-07-04', 'd', '1.00', 'Debit', 'INR', 0, NULL, 't', 't'), \
                   ('o1', 'older', '2026-07-04', 'd', '1.00', 'Debit', 'INR', 0, NULL, 't', 't'), \
                   ('o2', 'older', '2026-07-05', 'd', '2.00', 'Debit', 'INR', 1, NULL, 't', 't'), \
                   ('o3', 'older', '2026-07-06', 'd', '3.00', 'Debit', 'INR', 0, 'o1', 't', 't');",
            )
            .unwrap();
            tx.commit().unwrap();
        }

        let grouped = load_dedup_candidates(&conn).expect("load");
        let ids: Vec<(bool, Vec<&str>)> = grouped
            .iter()
            .map(|group| {
                (
                    group.is_credit_card,
                    group.rows.iter().map(|(id, _)| id.as_str()).collect(),
                )
            })
            .collect();
        // Insertion order, each group carrying its account's kind so `find_duplicates_in` can
        // refuse to compare two of a kind; the deleted (`o2`) and already-linked (`o3`) rows
        // are excluded.
        assert_eq!(ids, vec![(true, vec!["n1"]), (false, vec!["o1"])]);
    }

    #[test]
    fn load_transfer_inputs_excludes_deleted_and_linked_and_joins_card_flag() {
        let mut conn = Connection::open_in_memory().expect("in-memory db");
        {
            let tx = conn.transaction().unwrap();
            for v in 1..=SCHEMA_VERSION {
                apply_migration(&tx, v).expect("apply migration");
            }
            tx.pragma_update(None, "user_version", SCHEMA_VERSION)
                .unwrap();
            tx.execute(
                "INSERT INTO accounts \
                 (id, name, bank_code, is_credit_card, currency, created_at, updated_at) \
                 VALUES ('bank', 'Savings', 'HDFC', 0, 'INR', 't', 't'), \
                        ('card', 'Card', 'HDFC', 1, 'INR', 't', 't')",
                [],
            )
            .unwrap();
            // A live bank row (fed), a deleted row (excluded), an already-linked row (excluded),
            // and a live card row (fed, is_credit_card = 1 via the account join).
            tx.execute_batch(
                "INSERT INTO transactions \
                   (id, account_id, date, description_raw, amount, direction, currency, \
                    is_deleted, transfer_group_id, created_at, updated_at) VALUES \
                   ('live', 'bank', '2026-07-04', 'd', '1.00', 'Debit',  'INR', 0, NULL, 't', 't'), \
                   ('del',  'bank', '2026-07-04', 'd', '1.00', 'Debit',  'INR', 1, NULL, 't', 't'), \
                   ('done', 'bank', '2026-07-04', 'd', '1.00', 'Debit',  'INR', 0, 'g1', 't', 't'), \
                   ('cardc','card', '2026-07-04', 'd', '1.00', 'Credit', 'INR', 0, NULL, 't', 't');",
            )
            .unwrap();
            tx.commit().unwrap();
        }

        let inputs = load_transfer_inputs(&conn).expect("load");
        let ids: Vec<&str> = inputs.iter().map(|i| i.id.as_str()).collect();
        assert_eq!(ids, vec!["live", "cardc"]);
        let card = inputs.iter().find(|i| i.id == "cardc").unwrap();
        assert!(card.is_credit_card);
        let bank = inputs.iter().find(|i| i.id == "live").unwrap();
        assert!(!bank.is_credit_card);
    }
}
