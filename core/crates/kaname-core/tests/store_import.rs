//! Behavioural tests for the statement-import store path. All rows are synthetic.

use std::path::PathBuf;
use std::str::FromStr;
use std::sync::mpsc::{self, RecvTimeoutError};
use std::time::Duration;

use chrono::NaiveDate;
use kaname_core::store::{categorize_account_in, find_duplicates_in};
use kaname_core::{
    CategoryRef, Direction, ImportAccountTarget, ImportRequest, NewAccount, NewImportTransaction,
    NewTransaction, SourceCategoryMapping, StatementSource, Store, StoredTransaction,
};
use rust_decimal::Decimal;

const KEY: &str = "2f1c8a9e4b7d6035112233445566778899aabbccddeeff00112233445566aabb";

struct TestDb {
    dir: PathBuf,
    path: String,
}

impl TestDb {
    fn new(tag: &str) -> Self {
        let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("target")
            .join("test-dbs")
            .join(format!(
                "store-import-{}-{}-{:?}",
                std::process::id(),
                tag,
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            ));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("kaname.db").to_string_lossy().into_owned();
        Self { dir, path }
    }
}

impl Drop for TestDb {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn decimal(value: &str) -> Decimal {
    Decimal::from_str(value).unwrap()
}

fn date(y: i32, m: u32, d: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(y, m, d).unwrap()
}

fn account(name: &str, is_credit_card: bool, created_day: u32) -> NewAccount {
    let created_at = format!("2026-01-{created_day:02}T00:00:00Z");
    NewAccount {
        name: name.to_string(),
        bank_code: "HDFC".to_string(),
        is_credit_card,
        last4: None,
        currency: "INR".to_string(),
        created_at: created_at.clone(),
        updated_at: created_at,
    }
}

fn txn(account_id: &str, description_raw: &str) -> NewTransaction {
    NewTransaction {
        account_id: account_id.to_string(),
        date: date(2026, 7, 4),
        description_raw: description_raw.to_string(),
        amount: decimal("450.00"),
        direction: Direction::Debit,
        currency: "INR".to_string(),
        source_category: Some("FOOD".to_string()),
        category_id: None,
        categorised_by: None,
        statement_id: None,
        created_at: "2026-08-12T10:00:00Z".to_string(),
        updated_at: "2026-08-12T10:00:00Z".to_string(),
    }
}

fn import_txn(description_raw: &str, source_category: Option<&str>) -> NewImportTransaction {
    NewImportTransaction {
        date: date(2026, 7, 4),
        description_raw: description_raw.to_string(),
        amount: decimal("450.00"),
        direction: Direction::Debit,
        currency: "INR".to_string(),
        source_category: source_category.map(str::to_string),
    }
}

fn import_request(
    account: ImportAccountTarget,
    transactions: Vec<NewImportTransaction>,
) -> ImportRequest {
    ImportRequest {
        account,
        bank_code: "HDFC".to_string(),
        period_start: Some(date(2026, 7, 1)),
        period_end: date(2026, 7, 31),
        needs_review: false,
        source: StatementSource::Statement,
        transactions,
        now: "2026-08-12T10:30:00Z".to_string(),
    }
}

fn read(store: &Store, account_id: &str, index: usize) -> StoredTransaction {
    store
        .list_transactions(account_id.to_string())
        .expect("list transactions")[index]
        .clone()
}

fn seed_categorized_duplicate_pair(store: &Store) -> (String, String) {
    let bank = store
        .insert_account(account("HDFC Savings", false, 1))
        .expect("bank account");
    let card = store
        .insert_account(account("HDFC Card", true, 2))
        .expect("card account");

    store
        .insert_source_category_mapping(SourceCategoryMapping {
            bank_code: "HDFC".to_string(),
            source_category: "FOOD".to_string(),
            category: CategoryRef::Builtin {
                code: "FOOD_AND_DINING".to_string(),
            },
        })
        .expect("source category map");
    store
        .insert_transaction(txn(&bank, "POS SWIGGY BANGALORE RRN1234"))
        .expect("bank row");
    store
        .insert_transaction(txn(&card, "SWIGGY BANGALORE 1234567890123"))
        .expect("card row");
    (bank, card)
}

fn count_rows(path: &str, table: &str) -> i64 {
    let conn = open_sqlcipher(path);
    conn.query_row(&format!("SELECT count(*) FROM {table}"), [], |row| {
        row.get(0)
    })
    .unwrap()
}

fn open_sqlcipher(path: &str) -> rusqlite::Connection {
    let conn = rusqlite::Connection::open(path).unwrap();
    conn.pragma_update(None, "key", format!("x'{KEY}'"))
        .unwrap();
    conn.pragma_update(None, "foreign_keys", true).unwrap();
    conn
}

#[test]
fn categorize_then_find_duplicates_over_one_store_is_stable() {
    let db = TestDb::new("characterization");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let (bank, card) = seed_categorized_duplicate_pair(&store);

    let bank_categories = store
        .categorize_account(bank.clone())
        .expect("categorize bank");
    let card_categories = store
        .categorize_account(card.clone())
        .expect("categorize card");
    assert_eq!(bank_categories.categorized, 1);
    assert_eq!(bank_categories.uncategorized, 0);
    assert_eq!(card_categories.categorized, 1);
    assert_eq!(card_categories.uncategorized, 0);

    let duplicates = store.find_duplicates().expect("find duplicates");
    assert_eq!(duplicates.duplicates_linked, 1);
    assert_eq!(duplicates.canonical, 1);
    assert_eq!(duplicates.fuzzy, 0);

    let survivor = read(&store, &bank, 0);
    let duplicate = read(&store, &card, 0);
    assert_eq!(survivor.category_id.as_deref(), Some("FOOD_AND_DINING"));
    assert_eq!(duplicate.category_id.as_deref(), Some("FOOD_AND_DINING"));
    assert_eq!(survivor.superseded_by, None);
    assert_eq!(duplicate.superseded_by, Some(survivor.id));
}

#[test]
fn both_in_helpers_run_on_one_transaction_without_relocking() {
    let db = TestDb::new("deadlock-guard");
    let path = db.path.clone();
    let (tx, rx) = mpsc::channel();

    std::thread::spawn(move || {
        let result = run_in_helpers_on_one_transaction(path).map_err(|err| err.to_string());
        let _ = tx.send(result);
    });

    match rx.recv_timeout(Duration::from_secs(10)) {
        Ok(Ok(())) => {}
        Ok(Err(err)) => panic!("transaction-scoped helpers failed: {err}"),
        Err(RecvTimeoutError::Timeout) => {
            panic!("deadlock: the `*_in` helpers re-locked the connection")
        }
        Err(RecvTimeoutError::Disconnected) => panic!("helper thread exited without a result"),
    }
}

fn run_in_helpers_on_one_transaction(path: String) -> Result<(), Box<dyn std::error::Error>> {
    let store = Store::open(path.clone(), KEY.to_string())?;
    let (bank, _card) = seed_categorized_duplicate_pair(&store);
    drop(store);

    let mut conn = rusqlite::Connection::open(&path)?;
    conn.pragma_update(None, "key", format!("x'{KEY}'"))?;
    conn.pragma_update(None, "foreign_keys", true)?;
    let tx = conn.transaction()?;

    let categories = categorize_account_in(&tx, &bank)?;
    assert_eq!(categories.categorized, 1);
    assert_eq!(categories.uncategorized, 0);

    let duplicates = find_duplicates_in(&tx)?;
    assert_eq!(duplicates.duplicates_linked, 1);

    tx.commit()?;
    Ok(())
}

#[test]
fn import_statement_writes_account_statement_and_transactions_in_one_transaction() {
    let db = TestDb::new("atomic-write");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    store
        .insert_source_category_mapping(SourceCategoryMapping {
            bank_code: "HDFC".to_string(),
            source_category: "FOOD".to_string(),
            category: CategoryRef::Builtin {
                code: "FOOD_AND_DINING".to_string(),
            },
        })
        .expect("source category map");

    let outcome = store
        .import_statement(import_request(
            ImportAccountTarget::New {
                name: "HDFC Credit Card".to_string(),
                bank_code: "HDFC".to_string(),
                is_credit_card: true,
                last4: Some("1234".to_string()),
                currency: "INR".to_string(),
            },
            vec![
                import_txn("POS SWIGGY BANGALORE RRN1234", Some("FOOD")),
                import_txn("UNKNOWN MERCHANT", None),
            ],
        ))
        .expect("import statement");

    assert!(outcome.account_created);
    assert!(outcome.statement_id.is_some());
    assert_eq!(outcome.transactions_inserted, 2);
    assert_eq!(outcome.duplicates_linked, 0);
    assert_eq!(outcome.categorized, 1);
    assert_eq!(outcome.uncategorized, 1);

    let accounts = store.list_accounts().expect("accounts");
    assert_eq!(accounts.len(), 1);
    assert_eq!(accounts[0].id, outcome.account_id);
    assert_eq!(accounts[0].last4.as_deref(), Some("1234"));

    let statements = store
        .list_statements(outcome.account_id.clone())
        .expect("statements");
    assert_eq!(statements.len(), 1);
    assert_eq!(statements[0].id, outcome.statement_id.clone().unwrap());
    assert_eq!(statements[0].bank_code, "HDFC");
    assert_eq!(statements[0].period_start, Some(date(2026, 7, 1)));
    assert_eq!(statements[0].period_end, date(2026, 7, 31));

    let transactions = store
        .list_transactions(outcome.account_id.clone())
        .expect("transactions");
    assert_eq!(transactions.len(), 2);
    assert!(transactions
        .iter()
        .all(|txn| txn.statement_id == outcome.statement_id));
    assert_eq!(
        transactions[0].category_id.as_deref(),
        Some("FOOD_AND_DINING")
    );
    assert_eq!(transactions[1].category_id, None);
}

#[test]
fn import_statement_is_atomic_on_failure() {
    let db = TestDb::new("atomic-failure");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let existing = store
        .insert_account(account("Existing HDFC Savings", false, 1))
        .expect("existing account");
    store
        .insert_transaction(txn(&existing, "CORRUPT ROW"))
        .expect("existing txn");
    drop(store);

    open_sqlcipher(&db.path)
        .execute(
            "UPDATE transactions SET amount = 'not-a-decimal' WHERE description_raw = 'CORRUPT ROW'",
            [],
        )
        .unwrap();

    let before_accounts = count_rows(&db.path, "accounts");
    let before_statements = count_rows(&db.path, "statements");
    let before_transactions = count_rows(&db.path, "transactions");
    let before_version = Store::open(db.path.clone(), KEY.to_string())
        .expect("reopen")
        .schema_version()
        .expect("version");

    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open for import");
    let err = store
        .import_statement(import_request(
            ImportAccountTarget::New {
                name: "New HDFC Card".to_string(),
                bank_code: "HDFC".to_string(),
                is_credit_card: true,
                last4: Some("7777".to_string()),
                currency: "INR".to_string(),
            },
            vec![import_txn("POS SWIGGY BANGALORE RRN1234", None)],
        ))
        .expect_err("corrupt existing row should fail dedup");
    assert!(
        err.to_string().contains("invalid stored amount"),
        "unexpected error: {err:?}"
    );

    assert_eq!(count_rows(&db.path, "accounts"), before_accounts);
    assert_eq!(count_rows(&db.path, "statements"), before_statements);
    assert_eq!(count_rows(&db.path, "transactions"), before_transactions);
    assert_eq!(
        Store::open(db.path.clone(), KEY.to_string())
            .expect("final reopen")
            .schema_version()
            .expect("version"),
        before_version
    );
}

#[test]
fn import_statement_derives_every_timestamp_from_request_now() {
    let db = TestDb::new("timestamps");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");

    let outcome = store
        .import_statement(import_request(
            ImportAccountTarget::New {
                name: "HDFC Savings".to_string(),
                bank_code: "HDFC".to_string(),
                is_credit_card: false,
                last4: Some("4321".to_string()),
                currency: "INR".to_string(),
            },
            vec![import_txn("UPI TEST", None)],
        ))
        .expect("import");

    let account = store.list_accounts().expect("accounts").remove(0);
    assert_eq!(account.created_at, "2026-08-12T10:30:00Z");
    assert_eq!(account.updated_at, "2026-08-12T10:30:00Z");

    let statement = store
        .list_statements(outcome.account_id.clone())
        .expect("statements")
        .remove(0);
    assert_eq!(statement.created_at, "2026-08-12T10:30:00Z");

    let transaction = store
        .list_transactions(outcome.account_id)
        .expect("transactions")
        .remove(0);
    assert_eq!(transaction.created_at, "2026-08-12T10:30:00Z");
    assert_eq!(transaction.updated_at, "2026-08-12T10:30:00Z");
}

#[test]
fn import_statement_writes_no_statements_row_when_no_period_and_no_transactions() {
    let db = TestDb::new("empty-import");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let account_id = store
        .insert_account(account("Existing HDFC Savings", false, 1))
        .expect("account");

    let outcome = store
        .import_statement(import_request(
            ImportAccountTarget::Existing {
                id: account_id.clone(),
            },
            Vec::new(),
        ))
        .expect("empty import");

    assert_eq!(outcome.account_id, account_id);
    assert!(!outcome.account_created);
    assert_eq!(outcome.statement_id, None);
    assert_eq!(outcome.transactions_inserted, 0);
    assert_eq!(
        store.list_statements(account_id.clone()).unwrap(),
        Vec::new()
    );
    assert_eq!(store.list_transactions(account_id).unwrap(), Vec::new());
}
