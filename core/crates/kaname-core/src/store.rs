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
use crate::model::Direction;
use crate::transfer::TransferInput;

/// The schema version this build of the core knows how to run. The migration runner
/// applies every version up to and including this one; re-opening an up-to-date database
/// is a no-op.
const SCHEMA_VERSION: i64 = 3;

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
    pub currency: String,
    pub created_at: String,
    pub updated_at: String,
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
             (id, name, bank_code, is_credit_card, currency, created_at, updated_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                id,
                account.name,
                account.bank_code,
                account.is_credit_card as i64,
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
        let mut stmt = conn.prepare(
            "SELECT id, name, bank_code, is_credit_card, currency, created_at, updated_at \
             FROM accounts ORDER BY rowid",
        )?;
        let rows = stmt
            .query_map([], |row| {
                Ok(StoredAccount {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    bank_code: row.get(2)?,
                    is_credit_card: row.get::<_, i64>(3)? != 0,
                    currency: row.get(4)?,
                    created_at: row.get(5)?,
                    updated_at: row.get(6)?,
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    }

    /// Persist a new transaction against an existing account and return its minted id.
    pub fn insert_transaction(&self, txn: NewTransaction) -> Result<String, StoreError> {
        let conn = self.lock();
        let id = mint_id(&conn)?;
        conn.execute(
            "INSERT INTO transactions \
             (id, account_id, date, description_raw, amount, direction, currency, \
              source_category, category_id, categorised_by, created_at, updated_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
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
                txn.created_at,
                txn.updated_at,
            ],
        )?;
        Ok(id)
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
                    source_category, is_transfer, transfer_group_id \
             FROM transactions WHERE account_id = ?1 ORDER BY rowid",
        )?;
        let rows = stmt
            .query_map(params![account_id], map_transaction)?
            .collect::<rusqlite::Result<Vec<_>>>()?
            .into_iter()
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// The category catalog — the 23 seeded [`crate::default_categories`] plus any user
    /// categories created via [`Store::insert_category`] — ready to feed the categorization
    /// stack. Built-ins surface as [`CategoryRef::Builtin`], user categories as
    /// [`CategoryRef::Custom`].
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
    pub fn categorize_account(&self, account_id: String) -> Result<CategorizeSummary, StoreError> {
        let mut conn = self.lock();

        let account: Option<(String, bool)> = conn
            .query_row(
                "SELECT bank_code, is_credit_card FROM accounts WHERE id = ?1",
                params![account_id],
                |row| Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)? != 0)),
            )
            .optional()?;
        let Some((bank_code, is_credit_card)) = account else {
            return Ok(CategorizeSummary::default());
        };

        let tx = conn.transaction()?;

        let catalog = load_categories(&tx)?;
        let merchants = crate::categorize::prepare_merchants(&load_merchant_rules(&tx)?);
        let rules = crate::categorize::prepare_rules(&load_rules(&tx)?);
        let source_map = load_source_category_mappings(&tx)?;
        let pending = load_account_transactions(&tx, &account_id, &bank_code, is_credit_card)?;

        let mut summary = CategorizeSummary::default();
        {
            let mut update = tx.prepare(
                "UPDATE transactions SET category_id = ?2, categorised_by = ?3 WHERE id = ?1",
            )?;
            for (txn_id, txn) in &pending {
                match crate::categorize::categorize(txn, &catalog, &merchants, &rules, &source_map)
                {
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
        tx.commit()?;
        Ok(summary)
    }

    /// Detect self-transfers across **all** accounts and tag both legs of each pair.
    ///
    /// Loads every non-deleted, not-yet-linked transaction (`transfer_group_id IS NULL`)
    /// joined to its owning account for `is_credit_card`, runs the pure
    /// [`crate::transfer::detect_transfers`] matcher, and for each returned pair mints one
    /// `transfer_group_id` and sets `is_transfer = 1` on both legs. Idempotent: already-linked
    /// rows are excluded from the candidate load and the UPDATE is guarded by
    /// `transfer_group_id IS NULL`, so re-running links nothing new. Writes only the transfer
    /// identity — category assignment is a later slice.
    pub fn detect_transfers(&self) -> Result<TransferSummary, StoreError> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;

        let inputs = load_transfer_inputs(&tx)?;
        let pairs = crate::transfer::detect_transfers(&inputs);

        let mut summary = TransferSummary::default();
        {
            let mut update = tx.prepare(
                "UPDATE transactions SET is_transfer = 1, transfer_group_id = ?2 \
                 WHERE id = ?1 AND transfer_group_id IS NULL",
            )?;
            for pair in &pairs {
                let group_id = mint_id(&tx)?;
                update.execute(params![pair.outflow_id, group_id])?;
                update.execute(params![pair.inflow_id, group_id])?;
                summary.pairs_linked += 1;
                if pair.is_credit_card_payment {
                    summary.credit_card_payments += 1;
                }
            }
        }
        tx.commit()?;
        Ok(summary)
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
        })
    })())
}

/// Load one account's non-deleted transactions as `(id, CategoryTxn)` pairs ready for the
/// categorization stack. `bank_code`/`is_credit_card` come from the owning account; the rest
/// from each row (the issuer's `source_category` hint feeds T1).
fn load_account_transactions(
    conn: &Connection,
    account_id: &str,
    bank_code: &str,
    is_credit_card: bool,
) -> Result<Vec<(String, CategoryTxn)>, StoreError> {
    let mut stmt = conn.prepare(
        "SELECT id, source_category, description_raw, amount, direction \
         FROM transactions WHERE account_id = ?1 AND is_deleted = 0 ORDER BY rowid",
    )?;
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

fn date_from_sql(value: &str) -> Result<NaiveDate, StoreError> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d").map_err(|e| StoreError::Sql {
        message: format!("invalid stored date {value:?}: {e}"),
    })
}

fn amount_from_sql(value: &str) -> Result<Decimal, StoreError> {
    Decimal::from_str(value).map_err(|e| StoreError::Sql {
        message: format!("invalid stored amount {value:?}: {e}"),
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
