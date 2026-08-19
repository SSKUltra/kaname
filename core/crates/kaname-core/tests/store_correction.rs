//! What happens to a category **a person chose**, on every path the engine later takes over
//! the same row. All rows are synthetic (Constitution I).
//!
//! The two assertions this file exists for:
//!
//! * **C1** — a correction survives a re-import. It failed against shipped behaviour:
//!   `categorize_account_in`'s `UPDATE` was unconditional and wrote `NULL, NULL` over it.
//! * **C2** — a fresh import still categorizes *something*. 🚨 It is a separate test from C1 on
//!   purpose: the naive guard `categorised_by NOT IN ('PERSON', 'PERSON_MEMORY')` is `NULL` for
//!   every row an import has just inserted, so it discards all of them — and **C1 stays green
//!   against that break**. A slice carrying only C1 would ship research R10's trap with a green
//!   suite.

use std::path::PathBuf;
use std::str::FromStr;

use chrono::NaiveDate;
use kaname_core::{
    CategoryRef, Direction, ImportAccountTarget, ImportRequest, NewAccount, NewImportTransaction,
    SourceCategoryMapping, StatementSource, Store, StoreError,
};
use rust_decimal::Decimal;

const KEY: &str = "2f1c8a9e4b7d6035112233445566778899aabbccddeeff00112233445566aabb";

/// Open the encrypted database directly — needed for the two facts the public API deliberately
/// does not express: reading the memory table (a memory is not a rule, M11) and installing the
/// trigger C7 uses to force the second write to fail.
fn open_sqlcipher(path: &str) -> rusqlite::Connection {
    let conn = rusqlite::Connection::open(path).expect("open sqlcipher");
    conn.pragma_update(None, "key", format!("x'{KEY}'"))
        .expect("set key");
    conn.pragma_update(None, "foreign_keys", true)
        .expect("foreign keys");
    conn
}

/// Every memory the store holds, as `(merchant_portion, category_id)` pairs.
fn memories(path: &str) -> Vec<(String, String)> {
    let conn = open_sqlcipher(path);
    let mut stmt = conn
        .prepare("SELECT merchant_portion, category_id FROM merchant_memory ORDER BY 1")
        .expect("prepare");
    let rows = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("query")
        .collect::<rusqlite::Result<Vec<(String, String)>>>()
        .expect("collect");
    rows
}

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
                "store-correction-{}-{}-{:?}",
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

fn account() -> NewAccount {
    NewAccount {
        name: "Synthetic Bank One Savings".to_string(),
        bank_code: "HDFC".to_string(),
        is_credit_card: false,
        last4: None,
        currency: "INR".to_string(),
        created_at: "2026-01-01T00:00:00Z".to_string(),
        updated_at: "2026-01-01T00:00:00Z".to_string(),
    }
}

fn import_txn(
    description_raw: &str,
    amount: &str,
    source_category: Option<&str>,
) -> NewImportTransaction {
    NewImportTransaction {
        date: date(2026, 7, 4),
        description_raw: description_raw.to_string(),
        amount: decimal(amount),
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
        now: "2026-08-18T10:30:00Z".to_string(),
    }
}

/// An account holding two imported rows, one of which the source map has categorized. Returns
/// `(account_id, categorized_row_id)`.
fn imported_account(store: &Store) -> (String, String) {
    let account_id = store.insert_account(account()).expect("account");
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
        .import_statement(import_request(
            ImportAccountTarget::Existing {
                id: account_id.clone(),
                last4: None,
            },
            vec![
                import_txn("UPI-SYNTHCAFE-100001", "410.00", Some("FOOD")),
                import_txn("UPI-SYNTHFUEL-100002", "820.00", None),
            ],
        ))
        .expect("import");

    let rows = store
        .list_transactions(account_id.clone())
        .expect("list transactions");
    let categorized = rows
        .iter()
        .find(|row| row.description_raw.contains("SYNTHCAFE"))
        .expect("the cafe row")
        .id
        .clone();
    (account_id, categorized)
}

/// Re-import the same statement — the path that used to erase a correction.
fn reimport(store: &Store, account_id: &str) {
    store
        .import_statement(import_request(
            ImportAccountTarget::Existing {
                id: account_id.to_string(),
                last4: None,
            },
            vec![
                import_txn("UPI-SYNTHCAFE-100001", "410.00", Some("FOOD")),
                import_txn("UPI-SYNTHFUEL-100002", "820.00", None),
            ],
        ))
        .expect("re-import");
}

fn provenance(store: &Store, account_id: &str, txn_id: &str) -> (Option<String>, Option<String>) {
    let rows = store
        .list_transactions(account_id.to_string())
        .expect("list transactions");
    let row = rows
        .iter()
        .find(|row| row.id == txn_id)
        .expect("the transaction is still there");
    (row.category_id.clone(), row.categorised_by.clone())
}

/// 🔴 **C1** — a person's correction survives the next import of the same account.
#[test]
fn a_correction_survives_a_reimport() {
    let db = TestDb::new("c1");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let (account_id, txn_id) = imported_account(&store);

    store
        .set_transaction_category(
            txn_id.clone(),
            Some(CategoryRef::Builtin {
                code: "GROCERIES".to_string(),
            }),
            false,
        )
        .expect("correction");

    reimport(&store, &account_id);

    assert_eq!(
        provenance(&store, &account_id, &txn_id),
        (Some("GROCERIES".to_string()), Some("PERSON".to_string())),
        "an import must not overwrite what a person decided"
    );
}

/// 🚨 **C2** — a fresh import still categorizes the rows the stack can answer.
///
/// Green today. It is written now so that the naive `NOT IN` spelling of `ENGINE_MAY_DECIDE`
/// has something to turn red: that spelling evaluates to `NULL` for every row the import has
/// just inserted, so it silently discards all of them. **C1 passes against that break** —
/// which is the entire reason this assertion is a test of its own.
#[test]
fn a_fresh_import_still_categorizes_what_the_stack_can_answer() {
    let db = TestDb::new("c2");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let (account_id, _) = imported_account(&store);

    let categorized = store
        .list_transactions(account_id)
        .expect("list transactions")
        .iter()
        .filter(|row| row.category_id.is_some())
        .count();

    assert!(
        categorized > 0,
        "a guard that excludes NULL provenance leaves every imported row uncategorized, \
         and nothing errors"
    );
}

/// **C3** — a deliberate blank is a decision, and is protected exactly as a category is.
#[test]
fn a_deliberate_blank_is_protected_like_a_category() {
    let db = TestDb::new("c3");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let (account_id, txn_id) = imported_account(&store);

    store
        .set_transaction_category(txn_id.clone(), None, false)
        .expect("blank");

    assert_eq!(
        provenance(&store, &account_id, &txn_id),
        (None, Some("PERSON".to_string()))
    );

    reimport(&store, &account_id);

    assert_eq!(
        provenance(&store, &account_id, &txn_id),
        (None, Some("PERSON".to_string())),
        "the source map would re-fill this row if the blank were not a decision"
    );
}

/// **C8** — the summary counts only the rows the engine was allowed to decide about.
///
/// This is what the *load-site* guard is for, and it is worth its own assertion because the
/// write-site guard already makes C1 pass without it: with only the write guard, the stack
/// loads a corrected row, decides a category for it, reports it as `categorized`, and then
/// writes nothing — a summary describing work it did not do. Removing the load-site guard
/// leaves C1 green and turns this red, which is the only reason anyone would keep it.
#[test]
fn the_summary_counts_only_rows_the_engine_may_decide() {
    let db = TestDb::new("c8");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let (account_id, txn_id) = imported_account(&store);

    store
        .set_transaction_category(
            txn_id,
            Some(CategoryRef::Builtin {
                code: "GROCERIES".to_string(),
            }),
            false,
        )
        .expect("correction");

    let summary = store
        .categorize_account(account_id)
        .expect("categorize the account again");

    assert_eq!(
        (summary.categorized, summary.uncategorized),
        (0, 1),
        "the corrected row belongs in neither bucket: the engine did not decide it"
    );
}

/// **C6** — an unknown transaction id is `NotFound`, and nothing is written.
#[test]
fn correcting_an_unknown_transaction_is_not_found() {
    let db = TestDb::new("c6");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let (account_id, txn_id) = imported_account(&store);
    let before = provenance(&store, &account_id, &txn_id);

    let err = store
        .set_transaction_category(
            "no-such-transaction".to_string(),
            Some(CategoryRef::Builtin {
                code: "GROCERIES".to_string(),
            }),
            false,
        )
        .expect_err("an unknown id must not silently succeed");

    assert!(matches!(err, StoreError::NotFound { .. }), "got {err:?}");
    assert_eq!(
        provenance(&store, &account_id, &txn_id),
        before,
        "a failed correction must not touch another row"
    );
}

/// **C4** — a deliberate blank teaches nothing. There is no way to say "always leave this
/// merchant undecided", because that is not a thing a person can mean: `remember` is honoured
/// only when a category was actually chosen (spec amendment §3, judgement call §4).
///
/// The portion is still reported, so the interface can say what it *would* have remembered
/// rather than going quiet for a reason the person cannot see.
#[test]
fn a_deliberate_blank_forms_no_memory_even_when_remembering_was_asked_for() {
    let db = TestDb::new("c4");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let (_, txn_id) = imported_account(&store);

    let outcome = store
        .set_transaction_category(txn_id, None, true)
        .expect("correction to no category");

    assert!(
        !outcome.memory_formed,
        "a blank is a decision about a row, never about a merchant"
    );
    assert_eq!(
        outcome.merchant_portion,
        Some("synthcafe".to_string()),
        "the app must still be able to name what it did not remember"
    );
    assert_eq!(
        memories(&db.path),
        Vec::<(String, String)>::new(),
        "the memory table must be untouched"
    );
}

/// **C7** — the row and the memory are one transaction. The second write is forced to fail by a
/// trigger, and the first must be gone with it (FR-023).
///
/// A memory that outlived the correction that formed it would go on teaching the app a category
/// the person is no longer looking at — and nothing in the app would ever show them why.
#[test]
fn a_failed_memory_write_rolls_the_correction_back() {
    let db = TestDb::new("c7");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let (account_id, txn_id) = imported_account(&store);
    let before = provenance(&store, &account_id, &txn_id);

    // The only way to make the *second* write fail while the first succeeds: no constraint on
    // `merchant_memory` can be violated by a row whose category the transaction update has
    // already accepted.
    {
        let conn = open_sqlcipher(&db.path);
        conn.execute_batch(
            "CREATE TRIGGER refuse_memory BEFORE INSERT ON merchant_memory \
             BEGIN SELECT RAISE(ABORT, 'refused'); END;",
        )
        .expect("trigger");
    }

    let err = store
        .set_transaction_category(
            txn_id.clone(),
            Some(CategoryRef::Builtin {
                code: "GROCERIES".to_string(),
            }),
            true,
        )
        .expect_err("the memory write was refused");
    assert!(matches!(err, StoreError::Sql { .. }), "got {err:?}");

    assert_eq!(
        provenance(&store, &account_id, &txn_id),
        before,
        "the correction must not survive the memory that failed to form"
    );
    assert_eq!(
        memories(&db.path),
        Vec::<(String, String)>::new(),
        "and neither must a half-written memory"
    );
}

/// A **source-level** assertion: no statement in `store.rs` updates a transaction's category or
/// its provenance without either the engine guard or an explicit declaration that it is writing
/// the person's own decision.
///
/// Behavioural tests can only cover the write paths someone thought to exercise. This one
/// covers the write path nobody has written yet — which is the one that will quietly undo this
/// pull request.
#[test]
fn every_category_update_in_the_store_is_guarded() {
    const SOURCE: &str = include_str!("../src/store.rs");

    // Only the shipping code: the unit tests below `mod tests` write rows deliberately.
    let shipping = SOURCE
        .split_once("#[cfg(test)]")
        .map(|(before, _)| before)
        .unwrap_or(SOURCE);

    let mut unguarded = Vec::new();
    for (offset, _) in shipping.match_indices("UPDATE transactions") {
        let rest = &shipping[offset..];
        let statement = match rest.find(")?;") {
            Some(end) => &rest[..end],
            None => rest,
        };
        let touches_category =
            statement.contains("category_id = ") || statement.contains("categorised_by = ");
        if !touches_category {
            continue;
        }
        let guarded = statement.contains("{ENGINE_MAY_DECIDE}")
            // The one statement allowed to write over anything: it *is* the person deciding.
            || statement.contains("{PERSON}");
        if !guarded {
            unguarded.push(statement.lines().next().unwrap_or(statement).trim());
        }
    }

    assert!(
        unguarded.is_empty(),
        "these statements write a category without saying whose decision it is: {unguarded:#?}"
    );
}
