//! Behavioural tests for slice 03 — transfer persistence (engine→store wiring). Proves the
//! store runs the proven pure `detect_transfers` matcher over stored rows **across accounts**
//! via `detect_transfers`, and tags both legs of each self-transfer with `is_transfer` + a
//! shared `transfer_group_id` — including the credit-card bill-payment vs bank-to-bank split,
//! the no-false-positive cases, idempotent re-runs, and readback. (The v2→v3 upgrade of an
//! already populated database, and the `load_transfer_inputs` exclusions, are unit tests in
//! `store.rs`.) All data is synthetic (Constitution I).

use std::path::PathBuf;
use std::str::FromStr;

use chrono::NaiveDate;
use kaname_core::{Direction, NewAccount, NewTransaction, Store, StoredTransaction};
use rust_decimal::Decimal;

const KEY: &str = "2f1c8a9e4b7d6035112233445566778899aabbccddeeff00112233445566aabb";

struct TempDb {
    dir: PathBuf,
    path: String,
}

impl TempDb {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!(
            "kaname-xfer-{}-{}-{:?}",
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

fn account(name: &str, is_credit_card: bool) -> NewAccount {
    NewAccount {
        name: name.to_string(),
        bank_code: "HDFC".to_string(),
        is_credit_card,
        currency: "INR".to_string(),
        created_at: "2026-08-08T00:00:00Z".to_string(),
        updated_at: "2026-08-08T00:00:00Z".to_string(),
    }
}

fn txn(
    account_id: &str,
    day: u32,
    description_raw: &str,
    amount: &str,
    direction: Direction,
) -> NewTransaction {
    NewTransaction {
        account_id: account_id.to_string(),
        date: NaiveDate::from_ymd_opt(2026, 7, day).unwrap(),
        description_raw: description_raw.to_string(),
        amount: decimal(amount),
        direction,
        currency: "INR".to_string(),
        source_category: None,
        category_id: None,
        categorised_by: None,
        statement_id: None,
        created_at: "2026-08-08T00:00:00Z".to_string(),
        updated_at: "2026-08-08T00:00:00Z".to_string(),
    }
}

fn read(store: &Store, account_id: &str, index: usize) -> StoredTransaction {
    store
        .list_transactions(account_id.to_string())
        .expect("list")[index]
        .clone()
}

#[test]
fn credit_card_bill_payment_links_both_legs() {
    let db = TempDb::new("cc-payment");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");

    let bank = store
        .insert_account(account("HDFC Savings", false))
        .unwrap();
    let card = store.insert_account(account("HDFC Card", true)).unwrap();

    store
        .insert_transaction(txn(
            &bank,
            4,
            "CREDIT CARD PAYMENT",
            "5000.00",
            Direction::Debit,
        ))
        .unwrap();
    store
        .insert_transaction(txn(
            &card,
            4,
            "PAYMENT RECEIVED",
            "5000.00",
            Direction::Credit,
        ))
        .unwrap();

    let summary = store.detect_transfers().expect("detect");
    assert_eq!(summary.pairs_linked, 1);
    assert_eq!(summary.credit_card_payments, 1);

    let outflow = read(&store, &bank, 0);
    let inflow = read(&store, &card, 0);
    assert!(outflow.is_transfer);
    assert!(inflow.is_transfer);
    assert!(outflow.transfer_group_id.is_some());
    // Both legs of the pair share one minted group id.
    assert_eq!(outflow.transfer_group_id, inflow.transfer_group_id);
}

#[test]
fn bank_to_bank_self_transfer_links_without_cc_flag() {
    let db = TempDb::new("bank-to-bank");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");

    let a = store
        .insert_account(account("HDFC Savings", false))
        .unwrap();
    let b = store
        .insert_account(account("ICICI Savings", false))
        .unwrap();

    store
        .insert_transaction(txn(&a, 10, "NEFT TO SELF", "2000.00", Direction::Debit))
        .unwrap();
    store
        .insert_transaction(txn(&b, 10, "NEFT FROM SELF", "2000.00", Direction::Credit))
        .unwrap();

    let summary = store.detect_transfers().expect("detect");
    assert_eq!(summary.pairs_linked, 1);
    assert_eq!(summary.credit_card_payments, 0);

    assert!(read(&store, &a, 0).is_transfer);
    assert!(read(&store, &b, 0).is_transfer);
}

#[test]
fn amount_beyond_tolerance_is_not_a_transfer() {
    let db = TempDb::new("amount-gap");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");

    let a = store
        .insert_account(account("HDFC Savings", false))
        .unwrap();
    let b = store
        .insert_account(account("ICICI Savings", false))
        .unwrap();

    // ₹100 apart — beyond the matcher's ±₹1.00 tolerance.
    store
        .insert_transaction(txn(&a, 10, "NEFT", "2000.00", Direction::Debit))
        .unwrap();
    store
        .insert_transaction(txn(&b, 10, "NEFT", "2100.00", Direction::Credit))
        .unwrap();

    let summary = store.detect_transfers().expect("detect");
    assert_eq!(summary.pairs_linked, 0);
    assert!(!read(&store, &a, 0).is_transfer);
    assert_eq!(read(&store, &a, 0).transfer_group_id, None);
    assert!(!read(&store, &b, 0).is_transfer);
}

#[test]
fn same_direction_rows_are_not_a_transfer() {
    let db = TempDb::new("same-dir");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");

    let a = store
        .insert_account(account("HDFC Savings", false))
        .unwrap();
    let b = store
        .insert_account(account("ICICI Savings", false))
        .unwrap();

    // Two outflows — a transfer needs one Debit and one Credit.
    store
        .insert_transaction(txn(&a, 10, "NEFT", "2000.00", Direction::Debit))
        .unwrap();
    store
        .insert_transaction(txn(&b, 10, "NEFT", "2000.00", Direction::Debit))
        .unwrap();

    let summary = store.detect_transfers().expect("detect");
    assert_eq!(summary.pairs_linked, 0);
    assert!(!read(&store, &a, 0).is_transfer);
    assert!(!read(&store, &b, 0).is_transfer);
}

#[test]
fn opposite_legs_on_the_same_account_are_not_a_transfer() {
    let db = TempDb::new("same-account");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");

    let a = store
        .insert_account(account("HDFC Savings", false))
        .unwrap();

    // A Debit and a Credit within the *same* account: not a cross-account transfer.
    store
        .insert_transaction(txn(&a, 10, "ATM WITHDRAWAL", "2000.00", Direction::Debit))
        .unwrap();
    store
        .insert_transaction(txn(&a, 10, "CASH DEPOSIT", "2000.00", Direction::Credit))
        .unwrap();

    let summary = store.detect_transfers().expect("detect");
    assert_eq!(summary.pairs_linked, 0);
    assert!(!read(&store, &a, 0).is_transfer);
    assert!(!read(&store, &a, 1).is_transfer);
}

#[test]
fn rerunning_detection_links_nothing_new_and_keeps_group_ids() {
    let db = TempDb::new("idempotent");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");

    let a = store
        .insert_account(account("HDFC Savings", false))
        .unwrap();
    let b = store
        .insert_account(account("ICICI Savings", false))
        .unwrap();
    store
        .insert_transaction(txn(&a, 10, "NEFT TO SELF", "2000.00", Direction::Debit))
        .unwrap();
    store
        .insert_transaction(txn(&b, 10, "NEFT FROM SELF", "2000.00", Direction::Credit))
        .unwrap();

    let first = store.detect_transfers().expect("first");
    assert_eq!(first.pairs_linked, 1);
    let group_after_first = read(&store, &a, 0).transfer_group_id;
    assert!(group_after_first.is_some());

    // A second pass finds no unlinked candidates and changes nothing.
    let second = store.detect_transfers().expect("second");
    assert_eq!(second.pairs_linked, 0);
    assert_eq!(second.credit_card_payments, 0);
    assert_eq!(read(&store, &a, 0).transfer_group_id, group_after_first);
    assert!(read(&store, &a, 0).is_transfer);
}

#[test]
fn detects_nothing_when_there_are_no_rows() {
    let db = TempDb::new("empty");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let summary = store.detect_transfers().expect("detect");
    assert_eq!(summary.pairs_linked, 0);
    assert_eq!(summary.credit_card_payments, 0);
}
