//! Behavioural tests for the statement-import store path. All rows are synthetic.

use std::path::PathBuf;
use std::str::FromStr;
use std::sync::mpsc::{self, RecvTimeoutError};
use std::time::Duration;

use chrono::NaiveDate;
use kaname_core::store::{categorize_account_in, find_duplicates_in};
use kaname_core::{
    CategoryRef, Direction, NewAccount, NewTransaction, SourceCategoryMapping, Store,
    StoredTransaction,
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
