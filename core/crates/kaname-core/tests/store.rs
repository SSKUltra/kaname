//! Behavioural tests for the encrypted store (temp-file DBs). The on-device SQLite schema
//! is fresh design, so this proves behaviour — open/migrate/round-trip, wrong-key
//! fail-closed, migration idempotency and seeded categories — rather than porting a web
//! byte-for-byte fixture. All data is synthetic (Constitution I).

use std::path::PathBuf;

use chrono::NaiveDate;
use kaname_core::{Category, CategoryRef, Classification, Direction};
use kaname_core::{NewAccount, NewTransaction, Store, StoreError};
use rust_decimal::Decimal;
use std::str::FromStr;

/// A synthetic 256-bit key (64 hex chars).
const KEY: &str = "2f1c8a9e4b7d6035112233445566778899aabbccddeeff00112233445566aabb";
/// A different, equally valid 256-bit key — used to prove wrong-key fails closed.
const OTHER_KEY: &str = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";

/// A unique temp path per test; the parent dir is created and cleaned up by the guard.
struct TempDb {
    dir: PathBuf,
    path: String,
}

impl TempDb {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!(
            "kaname-store-{}-{}-{:?}",
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

impl Drop for TempDb {
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

fn sample_account() -> NewAccount {
    NewAccount {
        name: "HDFC Savings".to_string(),
        bank_code: "HDFC".to_string(),
        is_credit_card: false,
        currency: "INR".to_string(),
        created_at: "2026-08-08T00:00:00Z".to_string(),
        updated_at: "2026-08-08T00:00:00Z".to_string(),
    }
}

#[test]
fn opens_migrates_and_round_trips_an_account_and_transaction() {
    let db = TempDb::new("roundtrip");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");

    let account_id = store
        .insert_account(sample_account())
        .expect("insert account");

    let accounts = store.list_accounts().expect("list accounts");
    assert_eq!(accounts.len(), 1);
    let stored_account = &accounts[0];
    assert_eq!(stored_account.id, account_id);
    assert_eq!(stored_account.name, "HDFC Savings");
    assert_eq!(stored_account.bank_code, "HDFC");
    assert!(!stored_account.is_credit_card);
    assert_eq!(stored_account.currency, "INR");

    let txn = NewTransaction {
        account_id: account_id.clone(),
        date: date(2026, 7, 4),
        description_raw: "UPI-SWIGGY-123456".to_string(),
        amount: decimal("1234.56"),
        direction: Direction::Debit,
        currency: "INR".to_string(),
        source_category: None,
        category_id: Some("FOOD_AND_DINING".to_string()),
        categorised_by: Some("T2_MERCHANT_MAP".to_string()),
        created_at: "2026-08-08T10:00:00Z".to_string(),
        updated_at: "2026-08-08T10:00:00Z".to_string(),
    };
    let txn_id = store.insert_transaction(txn.clone()).expect("insert txn");

    let stored = store
        .list_transactions(account_id.clone())
        .expect("list txns");
    assert_eq!(stored.len(), 1);
    let got = &stored[0];
    assert_eq!(got.id, txn_id);
    assert_eq!(got.account_id, account_id);
    // Money round-trips as an exact Decimal — no float drift.
    assert_eq!(got.amount, decimal("1234.56"));
    // Date round-trips as a NaiveDate, direction preserved.
    assert_eq!(got.date, date(2026, 7, 4));
    assert_eq!(got.direction, Direction::Debit);
    assert_eq!(got.description_raw, "UPI-SWIGGY-123456");
    assert_eq!(got.currency, "INR");
    assert_eq!(got.category_id.as_deref(), Some("FOOD_AND_DINING"));
    assert_eq!(got.categorised_by.as_deref(), Some("T2_MERCHANT_MAP"));
    assert!(!got.is_deleted);
}

#[test]
fn preserves_high_precision_and_boundary_amounts_exactly() {
    let db = TempDb::new("amounts");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let account_id = store.insert_account(sample_account()).expect("account");

    let amounts = ["0", "0.01", "999999999999.99", "0.000000001", "42"];
    for (index, raw) in amounts.iter().enumerate() {
        store
            .insert_transaction(NewTransaction {
                account_id: account_id.clone(),
                date: date(2026, 1, 1 + index as u32),
                description_raw: format!("txn {index}"),
                amount: decimal(raw),
                direction: if index % 2 == 0 {
                    Direction::Debit
                } else {
                    Direction::Credit
                },
                currency: "INR".to_string(),
                source_category: None,
                category_id: None,
                categorised_by: None,
                created_at: "2026-08-08T00:00:00Z".to_string(),
                updated_at: "2026-08-08T00:00:00Z".to_string(),
            })
            .expect("insert");
    }

    let stored = store.list_transactions(account_id).expect("list");
    let got: Vec<Decimal> = stored.iter().map(|t| t.amount).collect();
    let want: Vec<Decimal> = amounts.iter().map(|a| decimal(a)).collect();
    assert_eq!(got, want);
    // A null category/categoriser round-trips as None.
    assert!(stored
        .iter()
        .all(|t| t.category_id.is_none() && t.categorised_by.is_none()));
}

#[test]
fn wrong_key_fails_closed_on_an_existing_database() {
    let db = TempDb::new("wrongkey");

    // Create + populate with the correct key, then drop the connection.
    {
        let store = Store::open(db.path.clone(), KEY.to_string()).expect("create");
        store.insert_account(sample_account()).expect("seed");
    }

    // Re-opening with a different (valid-format) key must fail closed — no readable DB.
    let err = Store::open(db.path.clone(), OTHER_KEY.to_string()).expect_err("must reject");
    assert!(matches!(err, StoreError::WrongKey), "got {err:?}");

    // The correct key still opens and reads the data back.
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("reopen");
    assert_eq!(store.list_accounts().expect("list").len(), 1);
}

#[test]
fn a_malformed_key_is_rejected_without_touching_the_file() {
    let db = TempDb::new("badkey");
    for bad in ["", "abc", &"z".repeat(64), &"a".repeat(63)] {
        let err = Store::open(db.path.clone(), bad.to_string()).expect_err("reject");
        assert!(matches!(err, StoreError::InvalidKey), "got {err:?}");
    }
}

#[test]
fn migration_is_idempotent_across_reopens() {
    let db = TempDb::new("idempotent");

    let first_id = {
        let store = Store::open(db.path.clone(), KEY.to_string()).expect("open 1");
        assert_eq!(store.schema_version().unwrap(), 4);
        store.insert_account(sample_account()).expect("insert")
    };

    // Re-open: migrations must be a no-op, the version unchanged, and the data intact.
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open 2");
    assert_eq!(store.schema_version().unwrap(), 4);
    let accounts = store.list_accounts().expect("list");
    assert_eq!(
        accounts.len(),
        1,
        "reopening must not duplicate or drop rows"
    );
    assert_eq!(accounts[0].id, first_id);
    // Categories are still exactly the 23 seeded rows (seeding ran once).
    assert_eq!(store.list_categories().expect("categories").len(), 23);
}

#[test]
fn seeds_the_twenty_three_default_categories_with_correct_classifications() {
    let db = TempDb::new("categories");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");

    let seeded = store.list_categories().expect("categories");
    assert_eq!(seeded.len(), 23);

    // The seeded catalog equals the ported defaults exactly (code + name + classification).
    let expected = kaname_core::default_categories();
    assert_eq!(seeded, expected);

    // Spot-check a few known classifications and the money-bucket tally (16/2/1/1/1/2).
    assert_eq!(
        classification_of(&seeded, "GROCERIES"),
        Some(Classification::Spend)
    );
    assert_eq!(
        classification_of(&seeded, "SALARY_INCOME"),
        Some(Classification::Income)
    );
    assert_eq!(
        classification_of(&seeded, "INVESTMENTS"),
        Some(Classification::Investment)
    );
    assert_eq!(
        classification_of(&seeded, "SELF_TRANSFER"),
        Some(Classification::Transfer)
    );
    assert_eq!(
        classification_of(&seeded, "CREDIT_CARD_BILL_PAYMENT"),
        Some(Classification::CcPayment)
    );
    assert_eq!(
        classification_of(&seeded, "REIMBURSEMENT"),
        Some(Classification::Refund)
    );

    let tally = |want: Classification| {
        seeded
            .iter()
            .filter(|c| c.classification == Some(want))
            .count()
    };
    assert_eq!(tally(Classification::Spend), 16);
    assert_eq!(tally(Classification::Income), 2);
    assert_eq!(tally(Classification::Investment), 1);
    assert_eq!(tally(Classification::Transfer), 1);
    assert_eq!(tally(Classification::CcPayment), 1);
    assert_eq!(tally(Classification::Refund), 2);
}

#[test]
fn the_encrypted_file_never_contains_plaintext() {
    let db = TempDb::new("ciphertext");
    {
        let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
        let account_id = store.insert_account(sample_account()).expect("account");
        store
            .insert_transaction(NewTransaction {
                account_id,
                date: date(2026, 7, 4),
                description_raw: "SUPER-SECRET-MERCHANT".to_string(),
                amount: decimal("1234.56"),
                direction: Direction::Debit,
                currency: "INR".to_string(),
                source_category: None,
                category_id: None,
                categorised_by: None,
                created_at: "2026-08-08T00:00:00Z".to_string(),
                updated_at: "2026-08-08T00:00:00Z".to_string(),
            })
            .expect("txn");
    }

    let bytes = std::fs::read(&db.path).expect("read db file");
    for needle in [
        b"SUPER-SECRET-MERCHANT".as_slice(),
        b"HDFC Savings".as_slice(),
    ] {
        assert!(
            !bytes.windows(needle.len()).any(|w| w == needle),
            "plaintext leaked into the on-disk database file"
        );
    }
}

fn classification_of(catalog: &[Category], code: &str) -> Option<Classification> {
    catalog
        .iter()
        .find(|c| matches!(&c.category_ref, CategoryRef::Builtin { code: c } if c == code))
        .and_then(|c| c.classification)
}
