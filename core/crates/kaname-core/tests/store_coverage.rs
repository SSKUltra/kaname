//! Behavioural tests for slice 05 — coverage persistence (engine→store wiring). Proves the store
//! persists **statements** as a first-class entity with per-transaction provenance, and feeds the
//! proven pure `compute_coverage` from those stored facts via `coverage` — the GAP / PARTIAL /
//! COVERED classification, the needs-review badge, the `Alert`-vs-`Statement` distinction, the
//! derived `from_full_statement`, and the clock-free window. (The v4→v5 upgrade of an already
//! populated database and the `StatementSource` SQL round-trip are unit tests in `store.rs`.)
//! All data is synthetic (Constitution I).

use std::path::PathBuf;
use std::str::FromStr;

use chrono::NaiveDate;
use kaname_core::{
    CoverageState, Direction, MonthCoverage, NewAccount, NewStatement, NewTransaction,
    StatementSource, Store,
};
use rust_decimal::Decimal;

const KEY: &str = "2f1c8a9e4b7d6035112233445566778899aabbccddeeff00112233445566aabb";

/// The day every test's rolling window ends on — an explicit input, never the wall-clock.
fn today() -> NaiveDate {
    NaiveDate::from_ymd_opt(2026, 8, 12).unwrap()
}

fn date(year: i32, month: u32, day: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(year, month, day).unwrap()
}

struct TempDb {
    dir: PathBuf,
    path: String,
}

impl TempDb {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!(
            "kaname-coverage-{}-{}-{:?}",
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

fn account() -> NewAccount {
    NewAccount {
        name: "HDFC Savings".to_string(),
        bank_code: "HDFC".to_string(),
        is_credit_card: false,
        currency: "INR".to_string(),
        created_at: "2026-01-01T00:00:00Z".to_string(),
        updated_at: "2026-01-01T00:00:00Z".to_string(),
    }
}

fn statement(
    account_id: &str,
    period_end: NaiveDate,
    needs_review: bool,
    source: StatementSource,
) -> NewStatement {
    NewStatement {
        account_id: account_id.to_string(),
        bank_code: "HDFC".to_string(),
        period_start: None,
        period_end,
        needs_review,
        source,
        created_at: "2026-08-12T00:00:00Z".to_string(),
    }
}

fn txn(account_id: &str, date: NaiveDate, statement_id: Option<String>) -> NewTransaction {
    NewTransaction {
        account_id: account_id.to_string(),
        date,
        description_raw: "POS BLUE TOKAI".to_string(),
        amount: Decimal::from_str("250.00").unwrap(),
        direction: Direction::Debit,
        currency: "INR".to_string(),
        source_category: None,
        category_id: None,
        categorised_by: None,
        statement_id,
        created_at: "2026-08-12T00:00:00Z".to_string(),
        updated_at: "2026-08-12T00:00:00Z".to_string(),
    }
}

fn month<'a>(months: &'a [MonthCoverage], label: &str) -> &'a MonthCoverage {
    months
        .iter()
        .find(|m| m.month == label)
        .expect("month is inside the window")
}

#[test]
fn a_statement_round_trips_through_the_store() {
    let db = TempDb::new("round-trip");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let account_id = store.insert_account(account()).unwrap();

    let mut new_statement = statement(
        &account_id,
        date(2026, 7, 31),
        true,
        StatementSource::Statement,
    );
    new_statement.period_start = Some(date(2026, 7, 1));
    let id = store.insert_statement(new_statement).expect("insert");

    let stored = store
        .list_statements(account_id.clone())
        .expect("list statements");
    assert_eq!(stored.len(), 1);
    let got = &stored[0];
    assert_eq!(got.id, id);
    assert_eq!(got.account_id, account_id);
    assert_eq!(got.bank_code, "HDFC");
    assert_eq!(got.period_start, Some(date(2026, 7, 1)));
    assert_eq!(got.period_end, date(2026, 7, 31));
    assert!(got.needs_review);
    assert_eq!(got.source, StatementSource::Statement);
}

#[test]
fn a_period_start_the_reader_could_not_recover_stays_absent() {
    let db = TempDb::new("no-period-start");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let account_id = store.insert_account(account()).unwrap();

    store
        .insert_statement(statement(
            &account_id,
            date(2026, 7, 31),
            false,
            StatementSource::Statement,
        ))
        .expect("insert");

    let stored = store.list_statements(account_id).expect("list");
    assert_eq!(stored[0].period_start, None);
}

#[test]
fn a_statements_month_is_covered_and_the_rest_of_the_window_is_a_gap() {
    let db = TempDb::new("covered");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let account_id = store.insert_account(account()).unwrap();

    store
        .insert_statement(statement(
            &account_id,
            date(2026, 7, 31),
            false,
            StatementSource::Statement,
        ))
        .expect("insert");

    let months = store.coverage(account_id, today()).expect("coverage");
    assert_eq!(months.len(), 24);
    // Oldest first, ending at `today`'s month.
    assert_eq!(months[0].month, "2024-09");
    assert_eq!(months[23].month, "2026-08");

    let july = month(&months, "2026-07");
    assert_eq!(july.state, CoverageState::Covered);
    assert!(!july.needs_review);
    assert_eq!(month(&months, "2026-06").state, CoverageState::Gap);
}

#[test]
fn piecemeal_rows_with_no_statement_leave_the_month_partial() {
    let db = TempDb::new("partial");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let account_id = store.insert_account(account()).unwrap();

    store
        .insert_transaction(txn(&account_id, date(2026, 6, 14), None))
        .unwrap();

    let months = store.coverage(account_id, today()).expect("coverage");
    let june = month(&months, "2026-06");
    assert_eq!(june.state, CoverageState::Partial);
    assert!(!june.needs_review);
}

#[test]
fn a_row_attributed_to_a_full_statement_covers_its_own_month() {
    let db = TempDb::new("row-covers");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let account_id = store.insert_account(account()).unwrap();

    // The statement's period ends in July, but it also carries a June-dated row: provenance
    // covers June even though no statement's period-end lands there.
    let statement_id = store
        .insert_statement(statement(
            &account_id,
            date(2026, 7, 31),
            false,
            StatementSource::Statement,
        ))
        .expect("insert");
    store
        .insert_transaction(txn(&account_id, date(2026, 6, 14), Some(statement_id)))
        .unwrap();

    let months = store.coverage(account_id, today()).expect("coverage");
    assert_eq!(month(&months, "2026-06").state, CoverageState::Covered);
    assert_eq!(month(&months, "2026-07").state, CoverageState::Covered);
}

#[test]
fn an_alert_sourced_run_never_covers_a_month() {
    let db = TempDb::new("alert");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let account_id = store.insert_account(account()).unwrap();

    // A live-alert run: its rows populate June, but they do not make it fully imported.
    let alert_id = store
        .insert_statement(statement(
            &account_id,
            date(2026, 6, 30),
            false,
            StatementSource::Alert,
        ))
        .expect("insert");
    store
        .insert_transaction(txn(&account_id, date(2026, 6, 14), Some(alert_id)))
        .unwrap();

    let months = store.coverage(account_id, today()).expect("coverage");
    assert_eq!(month(&months, "2026-06").state, CoverageState::Partial);
}

#[test]
fn a_needs_review_statement_badges_its_month() {
    let db = TempDb::new("needs-review");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let account_id = store.insert_account(account()).unwrap();

    store
        .insert_statement(statement(
            &account_id,
            date(2026, 7, 31),
            true,
            StatementSource::Statement,
        ))
        .expect("insert");

    let months = store.coverage(account_id, today()).expect("coverage");
    let july = month(&months, "2026-07");
    assert_eq!(july.state, CoverageState::Covered);
    assert!(july.needs_review);
}

#[test]
fn the_window_follows_the_supplied_today_not_the_clock() {
    let db = TempDb::new("clock-free");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let account_id = store.insert_account(account()).unwrap();

    store
        .insert_statement(statement(
            &account_id,
            date(2026, 7, 31),
            false,
            StatementSource::Statement,
        ))
        .expect("insert");

    // Slide `today` two years on: the same facts now fall outside the rolling window.
    let later = store
        .coverage(account_id.clone(), date(2028, 8, 12))
        .expect("coverage");
    assert_eq!(later[23].month, "2028-08");
    assert!(later.iter().all(|m| m.state == CoverageState::Gap));

    // The original window is unchanged — the call is a pure report over the same rows.
    let now = store.coverage(account_id, today()).expect("coverage");
    assert_eq!(month(&now, "2026-07").state, CoverageState::Covered);
}

#[test]
fn coverage_is_scoped_to_one_account() {
    let db = TempDb::new("scoped");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let first = store.insert_account(account()).unwrap();
    let second = store.insert_account(account()).unwrap();

    store
        .insert_statement(statement(
            &first,
            date(2026, 7, 31),
            false,
            StatementSource::Statement,
        ))
        .expect("insert");

    assert_eq!(
        month(
            &store.coverage(first, today()).expect("coverage"),
            "2026-07"
        )
        .state,
        CoverageState::Covered
    );
    // The other account has no facts of its own, so its July is still a gap.
    assert_eq!(
        month(
            &store.coverage(second, today()).expect("coverage"),
            "2026-07"
        )
        .state,
        CoverageState::Gap
    );
}
