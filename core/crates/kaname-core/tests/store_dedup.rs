//! Behavioural tests for slice 04 — dedup persistence (engine→store wiring). Proves the store
//! runs the proven pure `cross_source_duplicates` matcher over stored rows **across accounts**
//! via `find_duplicates`, and links each duplicate to the row it duplicates with
//! `superseded_by` + `dedup_layer` — including the oldest-account-wins survivor rule, the
//! canonical/fuzzy split, same-account repeats being left alone, multiplicity, the
//! no-false-positive cases, idempotent re-runs, and readback. (The v3→v4 upgrade of an already
//! populated database, and the `load_dedup_candidates` grouping + deleted/already-linked
//! exclusions, are unit tests in `store.rs`.) All data is synthetic (Constitution I).

use std::path::PathBuf;
use std::str::FromStr;

use chrono::NaiveDate;
use kaname_core::{DedupLayer, Direction, NewAccount, NewTransaction, Store, StoredTransaction};
use rust_decimal::Decimal;

const KEY: &str = "2f1c8a9e4b7d6035112233445566778899aabbccddeeff00112233445566aabb";

struct TempDb {
    dir: PathBuf,
    path: String,
}

impl TempDb {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!(
            "kaname-dedup-{}-{}-{:?}",
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

/// An account created on `created_day` of Jan 2026 — the day is what orders the accounts, and
/// therefore which side of a duplicate survives.
fn account(name: &str, is_credit_card: bool, created_day: u32) -> NewAccount {
    let created_at = format!("2026-01-{created_day:02}T00:00:00Z");
    NewAccount {
        name: name.to_string(),
        bank_code: "HDFC".to_string(),
        is_credit_card,
        currency: "INR".to_string(),
        updated_at: created_at.clone(),
        created_at,
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

/// A bank account created first plus a card account created later — the standard fixture: the
/// bank row is the survivor, the card row is the candidate duplicate.
fn bank_and_card(store: &Store) -> (String, String) {
    let bank = store
        .insert_account(account("HDFC Savings", false, 1))
        .unwrap();
    let card = store.insert_account(account("HDFC Card", true, 2)).unwrap();
    (bank, card)
}

#[test]
fn canonical_duplicate_links_the_newer_accounts_row_to_the_older() {
    let db = TempDb::new("canonical");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let (bank, card) = bank_and_card(&store);

    // Same date + amount + direction, cosmetically different narrations that normalize equal.
    store
        .insert_transaction(txn(
            &bank,
            4,
            "POS SWIGGY BANGALORE RRN1234",
            "450.00",
            Direction::Debit,
        ))
        .unwrap();
    store
        .insert_transaction(txn(
            &card,
            4,
            "SWIGGY BANGALORE 1234567890123",
            "450.00",
            Direction::Debit,
        ))
        .unwrap();

    let summary = store.find_duplicates().expect("dedup");
    assert_eq!(summary.duplicates_linked, 1);
    assert_eq!(summary.canonical, 1);
    assert_eq!(summary.fuzzy, 0);

    let survivor = read(&store, &bank, 0);
    let duplicate = read(&store, &card, 0);
    // The older account's row survives untouched; the newer one points at it.
    assert_eq!(survivor.superseded_by, None);
    assert_eq!(survivor.dedup_layer, None);
    assert_eq!(duplicate.superseded_by, Some(survivor.id.clone()));
    assert_eq!(duplicate.dedup_layer, Some(DedupLayer::Canonical));
    // Linked, never deleted — the link stays reversible and the UI decides what to hide.
    assert!(!duplicate.is_deleted);
}

#[test]
fn fuzzy_duplicate_links_across_a_one_day_skew() {
    let db = TempDb::new("fuzzy");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let (bank, card) = bank_and_card(&store);

    store
        .insert_transaction(txn(
            &bank,
            4,
            "SWIGGY BANGALORE",
            "450.00",
            Direction::Debit,
        ))
        .unwrap();
    store
        .insert_transaction(txn(
            &card,
            5,
            "SWIGGY BANGALURU",
            "450.00",
            Direction::Debit,
        ))
        .unwrap();

    let summary = store.find_duplicates().expect("dedup");
    assert_eq!(summary.duplicates_linked, 1);
    assert_eq!(summary.canonical, 0);
    assert_eq!(summary.fuzzy, 1);

    let survivor = read(&store, &bank, 0);
    let duplicate = read(&store, &card, 0);
    assert_eq!(duplicate.superseded_by, Some(survivor.id));
    assert_eq!(duplicate.dedup_layer, Some(DedupLayer::Fuzzy));
}

#[test]
fn a_genuine_repeat_on_the_same_account_is_not_a_duplicate() {
    let db = TempDb::new("same-account");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let bank = store
        .insert_account(account("HDFC Savings", false, 1))
        .unwrap();

    // Two identical coffees on one statement are two real spends, not a cross-source dup.
    for _ in 0..2 {
        store
            .insert_transaction(txn(&bank, 4, "POS BLUE TOKAI", "250.00", Direction::Debit))
            .unwrap();
    }

    let summary = store.find_duplicates().expect("dedup");
    assert_eq!(summary.duplicates_linked, 0);
    for index in 0..2 {
        assert_eq!(read(&store, &bank, index).superseded_by, None);
    }
}

#[test]
fn multiplicity_is_respected_across_accounts() {
    let db = TempDb::new("multiplicity");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let (bank, card) = bank_and_card(&store);

    // Two real repeats on the bank; three lookalikes on the card. Only two can be absorbed —
    // the third is a genuinely distinct spend and must survive.
    for _ in 0..2 {
        store
            .insert_transaction(txn(&bank, 4, "POS BLUE TOKAI", "250.00", Direction::Debit))
            .unwrap();
    }
    for _ in 0..3 {
        store
            .insert_transaction(txn(&card, 4, "BLUE TOKAI", "250.00", Direction::Debit))
            .unwrap();
    }

    let summary = store.find_duplicates().expect("dedup");
    assert_eq!(summary.duplicates_linked, 2);

    let linked = (0..3)
        .filter(|i| read(&store, &card, *i).superseded_by.is_some())
        .count();
    assert_eq!(linked, 2);
    // Every survivor on the bank side is still a survivor.
    for index in 0..2 {
        assert_eq!(read(&store, &bank, index).superseded_by, None);
    }
}

#[test]
fn a_row_already_superseded_cannot_absorb_a_third_duplicate() {
    let db = TempDb::new("chain");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let bank = store
        .insert_account(account("HDFC Savings", false, 1))
        .unwrap();
    let card = store.insert_account(account("HDFC Card", true, 2)).unwrap();
    let wallet = store
        .insert_account(account("HDFC Wallet", false, 3))
        .unwrap();

    for id in [&bank, &card, &wallet] {
        store
            .insert_transaction(txn(id, 4, "POS BLUE TOKAI", "250.00", Direction::Debit))
            .unwrap();
    }

    let summary = store.find_duplicates().expect("dedup");
    // Bank absorbs the card row; the bank row is then consumed, so the wallet row has no
    // remaining survivor to attach to and stays independent (no supersede chains).
    assert_eq!(summary.duplicates_linked, 1);
    let bank_row = read(&store, &bank, 0);
    assert_eq!(read(&store, &card, 0).superseded_by, Some(bank_row.id));
    assert_eq!(read(&store, &wallet, 0).superseded_by, None);
}

#[test]
fn a_different_amount_or_direction_is_never_a_duplicate() {
    let db = TempDb::new("no-false-positives");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let (bank, card) = bank_and_card(&store);

    store
        .insert_transaction(txn(&bank, 4, "POS BLUE TOKAI", "250.00", Direction::Debit))
        .unwrap();
    store
        .insert_transaction(txn(&bank, 6, "POS AMAZON", "999.00", Direction::Debit))
        .unwrap();
    // Same narration, a rupee off.
    store
        .insert_transaction(txn(&card, 4, "POS BLUE TOKAI", "251.00", Direction::Debit))
        .unwrap();
    // Same narration and amount, opposite direction (a refund, not a duplicate).
    store
        .insert_transaction(txn(&card, 6, "POS AMAZON", "999.00", Direction::Credit))
        .unwrap();

    let summary = store.find_duplicates().expect("dedup");
    assert_eq!(summary.duplicates_linked, 0);
    for index in 0..2 {
        assert_eq!(read(&store, &card, index).superseded_by, None);
        assert_eq!(read(&store, &card, index).dedup_layer, None);
    }
}

#[test]
fn re_running_detection_links_nothing_new() {
    let db = TempDb::new("idempotent");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let (bank, card) = bank_and_card(&store);

    store
        .insert_transaction(txn(&bank, 4, "POS BLUE TOKAI", "250.00", Direction::Debit))
        .unwrap();
    store
        .insert_transaction(txn(&card, 4, "BLUE TOKAI", "250.00", Direction::Debit))
        .unwrap();

    let first = store.find_duplicates().expect("dedup");
    assert_eq!(first.duplicates_linked, 1);
    let linked_to = read(&store, &card, 0).superseded_by;

    let second = store.find_duplicates().expect("dedup again");
    assert_eq!(second.duplicates_linked, 0);
    assert_eq!(second.canonical, 0);
    assert_eq!(second.fuzzy, 0);
    // The existing link is left exactly as it was.
    assert_eq!(read(&store, &card, 0).superseded_by, linked_to);
    assert_eq!(read(&store, &bank, 0).superseded_by, None);
}

#[test]
fn money_and_dates_survive_the_dedup_round_trip_exactly() {
    let db = TempDb::new("round-trip");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let (bank, card) = bank_and_card(&store);

    store
        .insert_transaction(txn(&bank, 4, "POS BLUE TOKAI", "1234.56", Direction::Debit))
        .unwrap();
    store
        .insert_transaction(txn(&card, 4, "BLUE TOKAI", "1234.56", Direction::Debit))
        .unwrap();

    assert_eq!(store.find_duplicates().expect("dedup").duplicates_linked, 1);

    let duplicate = read(&store, &card, 0);
    assert_eq!(duplicate.amount, decimal("1234.56"));
    assert_eq!(duplicate.date, NaiveDate::from_ymd_opt(2026, 7, 4).unwrap());
    assert_eq!(duplicate.direction, Direction::Debit);
}
