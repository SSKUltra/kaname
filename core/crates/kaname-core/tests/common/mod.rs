//! The synthetic corpus every combined-history suite reads (`data-model.md` §7, research R20).
//!
//! Two builders, for two different jobs:
//!
//! * [`correctness_corpus`] writes through the **real** [`Store::import_statement`], so what the
//!   history suites read is what an import actually produces — including the rows dedup
//!   supersedes and the categories the stack assigns.
//! * [`perf_corpus`] writes by direct SQL, because the import path costs 11.8 s for the 10,000
//!   rows the plan-shape and wall-clock gates need, against 151 ms for the same rows inserted
//!   straight (research R20).
//!
//! Every row here is invented. No real merchant, no real account identifier, no real statement
//! (FR-064, SC-017).
//!
//! **The fixture contract is load-bearing.** R20's first attempt gave many rows the same amount
//! and description, so cross-source de-duplication quietly superseded 8,750 of its 10,000 rows —
//! a performance gate measuring an eighth of the corpus it claimed. Every row below therefore
//! carries a globally unique amount *and* a globally unique description, and the two places that
//! deliberately break the rule (the echo card, the transfer pair) are named, counted, and
//! asserted by this module's own tests.
#![allow(dead_code)]

use std::path::PathBuf;
use std::str::FromStr;

use chrono::NaiveDate;
use kaname_core::{
    Direction, HistoryCursor, HistoryQuery, HistoryRow, ImportAccountTarget, ImportRequest,
    NewImportTransaction, StatementSource, Store,
};
use rusqlite::Connection;
use rust_decimal::Decimal;

/// A synthetic 256-bit key (64 hex chars). Never a real one — the core never persists a key.
pub const KEY: &str = "2f1c8a9e4b7d6035112233445566778899aabbccddeeff00112233445566aabb";

/// A unique temp database per test, removed when the guard drops.
pub struct TestDb {
    dir: PathBuf,
    pub path: String,
}

impl TestDb {
    pub fn new(tag: &str) -> Self {
        let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("target")
            .join("test-dbs")
            .join(format!(
                "history-{}-{}-{:?}",
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

    pub fn open(&self) -> std::sync::Arc<Store> {
        Store::open(self.path.clone(), KEY.to_string()).expect("open store")
    }
}

impl Drop for TestDb {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

/// Open the encrypted database directly. Needed only for the two facts the public store API
/// cannot express: marking a row deleted, and the bulk insert the performance corpus needs.
pub fn open_sqlcipher(path: &str) -> Connection {
    let conn = Connection::open(path).expect("open sqlcipher");
    conn.pragma_update(None, "key", format!("x'{KEY}'"))
        .expect("set key");
    conn.pragma_update(None, "foreign_keys", true)
        .expect("foreign keys");
    conn
}

pub fn decimal(value: &str) -> Decimal {
    Decimal::from_str(value).expect("decimal")
}

pub fn date(y: i32, m: u32, d: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(y, m, d).expect("date")
}

/// What the correctness corpus deliberately contains, so a suite asserts against a declared
/// fact rather than against whatever the builder happened to write.
pub struct Corpus {
    /// Accounts in `list_accounts()` order — which is also the combined history's account
    /// tie-break (FR-030).
    pub accounts: Vec<CorpusAccount>,
    /// Rows the fixture means to have superseded (the echo card's rows).
    pub superseded_rows: usize,
    /// Rows the fixture means to have deleted.
    pub deleted_rows: usize,
    /// Legs the transfer detector is expected to mark.
    pub transfer_rows: usize,
    /// A date carrying rows from more than one account, with different amounts (FR-030).
    pub shared_date: NaiveDate,
    /// A date whose group is larger than the small page sizes the paging suite walks (R13).
    pub crowded_date: NaiveDate,
    /// Live rows on [`Corpus::crowded_date`].
    pub crowded_date_rows: usize,
}

pub struct CorpusAccount {
    pub id: String,
    pub name: String,
    pub currency: String,
    pub is_credit_card: bool,
    /// Rows neither deleted nor superseded.
    pub live_rows: usize,
    /// True when the account holds rows and every one of them is excluded.
    pub only_excluded_rows: bool,
}

impl Corpus {
    pub fn account(&self, name: &str) -> &CorpusAccount {
        self.accounts
            .iter()
            .find(|a| a.name == name)
            .unwrap_or_else(|| panic!("no corpus account named {name}"))
    }

    pub fn live_rows(&self) -> usize {
        self.accounts.iter().map(|a| a.live_rows).sum()
    }
}

/// The bank ledger every other account is defined relative to.
pub const EVERYDAY: &str = "Everyday Savings";
/// A credit card, so the ledger and it are opposite kinds and dedup will compare them.
pub const TRAVEL_CARD: &str = "Travel Card";
/// A second currency — one `en_IN` renders as a code rather than a symbol (FR-027, SC-011).
pub const OVERSEAS: &str = "Overseas Savings";
/// An account whose statement parsed no rows at all (empty state 4).
pub const DORMANT_CARD: &str = "Dormant Card";
/// An account created last, carrying nothing but rows the ledger already had — so every one of
/// its rows is superseded and none is live (empty state 5).
pub const ECHO_CARD: &str = "Echo Card";

/// A date carrying rows from three accounts, each with a different amount.
pub const SHARED_DATE: NaiveDate = match NaiveDate::from_ymd_opt(2026, 7, 15) {
    Some(d) => d,
    None => panic!("valid date"),
};
/// A date whose group spans more than one page at the small sizes the paging suite walks.
pub const CROWDED_DATE: NaiveDate = match NaiveDate::from_ymd_opt(2026, 7, 20) {
    Some(d) => d,
    None => panic!("valid date"),
};
const CROWDED_ROWS_PER_ACCOUNT: usize = 6;
const DELETED_DATE: NaiveDate = match NaiveDate::from_ymd_opt(2026, 7, 6) {
    Some(d) => d,
    None => panic!("valid date"),
};
/// The description of the one row the fixture marks deleted.
const DELETED_DESCRIPTION: &str = "SYNTHETIC WITHDRAWN ROW 24";
/// Both legs of the fixture's transfer share this amount — one of the two places an amount
/// repeats on purpose. The legs are opposite directions, so no dedup layer can match them.
const TRANSFER_AMOUNT: &str = "5000.00";

/// Build the correctness corpus through the real import path.
///
/// `path` is the same database `store` has open; it is needed only to mark one row deleted,
/// which the public store API cannot yet do.
pub fn correctness_corpus(store: &Store, path: &str) -> Corpus {
    let everyday = import_new(store, EVERYDAY, false, "INR", "1123", everyday_rows());
    let travel = import_new(store, TRAVEL_CARD, true, "INR", "8890", travel_rows());
    let overseas = import_new(store, OVERSEAS, false, "KWD", "4417", overseas_rows());
    let dormant = import_new(store, DORMANT_CARD, true, "INR", "3350", vec![]);
    // The echo card carries two of the ledger's rows verbatim. Opposite kinds, so 013's
    // cross-source matcher compares them; the ledger is the earlier `accounts.rowid`, so the
    // ledger's rows survive and every one of the card's is superseded.
    let echo = import_new(store, ECHO_CARD, true, "INR", "6612", echoed_rows());

    // One deleted row on the travel card — the store has no delete yet, and the live rule has
    // to be proven against a row that is deleted rather than superseded.
    let conn = open_sqlcipher(path);
    let deleted = conn
        .execute(
            "UPDATE transactions SET is_deleted = 1 \
             WHERE account_id = ?1 AND description_raw = ?2",
            rusqlite::params![travel, DELETED_DESCRIPTION],
        )
        .expect("mark one row deleted");
    assert_eq!(deleted, 1, "the fixture's deleted row must exist");
    drop(conn);

    let transfers = store.detect_transfers().expect("detect transfers");
    assert_eq!(
        transfers.pairs_linked, 1,
        "the fixture declares exactly one transfer pair"
    );

    Corpus {
        accounts: vec![
            CorpusAccount {
                id: everyday,
                name: EVERYDAY.into(),
                currency: "INR".into(),
                is_credit_card: false,
                live_rows: everyday_rows().len(),
                only_excluded_rows: false,
            },
            CorpusAccount {
                id: travel,
                name: TRAVEL_CARD.into(),
                currency: "INR".into(),
                is_credit_card: true,
                live_rows: travel_rows().len() - 1,
                only_excluded_rows: false,
            },
            CorpusAccount {
                id: overseas,
                name: OVERSEAS.into(),
                currency: "KWD".into(),
                is_credit_card: false,
                live_rows: overseas_rows().len(),
                only_excluded_rows: false,
            },
            CorpusAccount {
                id: dormant,
                name: DORMANT_CARD.into(),
                currency: "INR".into(),
                is_credit_card: true,
                live_rows: 0,
                only_excluded_rows: false,
            },
            CorpusAccount {
                id: echo,
                name: ECHO_CARD.into(),
                currency: "INR".into(),
                is_credit_card: true,
                live_rows: 0,
                only_excluded_rows: true,
            },
        ],
        superseded_rows: echoed_rows().len(),
        deleted_rows: 1,
        transfer_rows: 2,
        shared_date: SHARED_DATE,
        crowded_date: CROWDED_DATE,
        crowded_date_rows: CROWDED_ROWS_PER_ACCOUNT * 2,
    }
}

/// Read every page of the history and concatenate them. `limit` is the page size, so a suite
/// can prove that paging changes nothing but where the reads are cut.
pub fn walk(store: &Store, account_id: Option<&str>, limit: u32) -> Vec<HistoryRow> {
    let mut rows = Vec::new();
    let mut cursor: Option<HistoryCursor> = None;
    loop {
        let page = store
            .history_page(HistoryQuery {
                account_id: account_id.map(str::to_string),
                cursor: cursor.clone(),
                limit,
            })
            .expect("history page");
        rows.extend(page.rows);
        match page.cursor {
            Some(next) => cursor = Some(next),
            None => break,
        }
        assert!(
            rows.len() <= 100_000,
            "a cursor that never terminates is a bug, not a long history"
        );
    }
    rows
}

/// Import the ledger's statement a second time, unchanged — the "I imported the same PDF
/// twice" case (FR-009). Every repeated row is superseded, so the history must not move.
pub fn reimport_everyday(store: &Store) {
    let account = store
        .list_accounts()
        .expect("accounts")
        .into_iter()
        .find(|a| a.name == EVERYDAY)
        .expect("the ledger exists");
    store
        .import_statement(ImportRequest {
            account: ImportAccountTarget::Existing {
                id: account.id,
                last4: account.last4,
            },
            bank_code: "SYNTHETIC".to_string(),
            period_start: Some(date(2026, 7, 1)),
            period_end: date(2026, 7, 31),
            needs_review: false,
            source: StatementSource::Statement,
            transactions: everyday_rows(),
            now: "2026-08-13T09:00:00Z".to_string(),
        })
        .expect("re-import");
}

/// A sixth account, imported after a suite has already read the history — the "someone
/// imported while I was scrolling" case (FR-032, FR-054).
pub fn import_late_account(store: &Store) -> String {
    import_new(
        store,
        "Late Ledger",
        false,
        "INR",
        "9901",
        vec![
            row(
                SHARED_DATE,
                "SYNTHETIC LATE ARRIVAL 71",
                "701.11",
                Direction::Debit,
                "INR",
            ),
            row(
                date(2026, 7, 4),
                "SYNTHETIC LATE ARRIVAL 72",
                "702.22",
                Direction::Credit,
                "INR",
            ),
        ],
    )
}

fn everyday_rows() -> Vec<NewImportTransaction> {
    let mut rows = vec![
        row(
            SHARED_DATE,
            "SYNTHETIC GROCERY HALL 01",
            "101.11",
            Direction::Debit,
            "INR",
        ),
        // An empty description, as printed (FR-020).
        row(date(2026, 7, 12), "", "102.22", Direction::Debit, "INR"),
        // The transfer's outflow leg.
        row(
            date(2026, 7, 10),
            "SYNTHETIC LEDGER TRANSFER OUT 03",
            TRANSFER_AMOUNT,
            Direction::Debit,
            "INR",
        ),
        row(
            date(2026, 7, 8),
            "SYNTHETIC SALARY CREDIT 04",
            "104.44",
            Direction::Credit,
            "INR",
        ),
        row(
            date(2026, 7, 2),
            "SYNTHETIC UTILITY DEBIT 05",
            "105.55",
            Direction::Debit,
            "INR",
        ),
    ];
    rows.extend(echoed_rows());
    rows.extend(crowded_rows("LEDGER", 10, 1));
    rows
}

fn travel_rows() -> Vec<NewImportTransaction> {
    let mut rows = vec![
        row(
            SHARED_DATE,
            "SYNTHETIC FUEL STOP 21",
            "201.11",
            Direction::Debit,
            "INR",
        ),
        // A very long description, kept as printed (FR-021).
        row(
            date(2026, 7, 11),
            "SYNTHETIC MERCHANT WITH AN EXTREMELY LONG PRINTED NARRATION THAT A STATEMENT ROW \
             CAN CARRY WHEN THE ISSUER PADS IT WITH TERMINAL IDENTIFIERS AND A REFERENCE \
             NUMBER 22",
            "202.22",
            Direction::Debit,
            "INR",
        ),
        // The transfer's inflow leg — a card bill payment, so both legs are marked.
        row(
            date(2026, 7, 10),
            "SYNTHETIC CARD PAYMENT RECEIVED 23",
            TRANSFER_AMOUNT,
            Direction::Credit,
            "INR",
        ),
        row(
            DELETED_DATE,
            DELETED_DESCRIPTION,
            "204.44",
            Direction::Debit,
            "INR",
        ),
    ];
    rows.extend(crowded_rows("CARD", 30, 2));
    rows
}

fn overseas_rows() -> Vec<NewImportTransaction> {
    vec![
        row(
            SHARED_DATE,
            "SYNTHETIC HARBOUR FEE 51",
            "301.115",
            Direction::Debit,
            "KWD",
        ),
        // Seven integer digits, to prove an amount never shrinks to fit (FR-021).
        row(
            date(2026, 7, 9),
            "SYNTHETIC PROPERTY SETTLEMENT 52",
            "1234567.890",
            Direction::Debit,
            "KWD",
        ),
        row(
            date(2026, 7, 3),
            "SYNTHETIC DIVIDEND 53",
            "303.335",
            Direction::Credit,
            "KWD",
        ),
    ]
}

/// The two ledger rows the echo card repeats verbatim — the fixture's only supersessions.
fn echoed_rows() -> Vec<NewImportTransaction> {
    vec![
        row(
            date(2026, 7, 7),
            "SYNTHETIC ECHOED PURCHASE 61",
            "601.11",
            Direction::Debit,
            "INR",
        ),
        row(
            date(2026, 7, 5),
            "SYNTHETIC ECHOED PURCHASE 62",
            "602.22",
            Direction::Debit,
            "INR",
        ),
    ]
}

/// Rows on the crowded date. `base` and `thousands` keep every amount and description globally
/// unique across the accounts that share the date.
fn crowded_rows(tag: &str, base: usize, thousands: usize) -> Vec<NewImportTransaction> {
    (0..CROWDED_ROWS_PER_ACCOUNT)
        .map(|i| {
            let n = base + i;
            row(
                CROWDED_DATE,
                &format!("SYNTHETIC {tag} CROWDED ROW {n:03}"),
                &format!("{}.{:02}", thousands * 1000 + n, n % 100),
                Direction::Debit,
                "INR",
            )
        })
        .collect()
}

fn row(
    on: NaiveDate,
    description_raw: &str,
    amount: &str,
    direction: Direction,
    currency: &str,
) -> NewImportTransaction {
    NewImportTransaction {
        date: on,
        description_raw: description_raw.to_string(),
        amount: decimal(amount),
        direction,
        currency: currency.to_string(),
        source_category: None,
    }
}

fn import_new(
    store: &Store,
    name: &str,
    is_credit_card: bool,
    currency: &str,
    last4: &str,
    transactions: Vec<NewImportTransaction>,
) -> String {
    store
        .import_statement(ImportRequest {
            account: ImportAccountTarget::New {
                name: name.to_string(),
                bank_code: "SYNTHETIC".to_string(),
                is_credit_card,
                last4: Some(last4.to_string()),
                currency: currency.to_string(),
            },
            bank_code: "SYNTHETIC".to_string(),
            period_start: Some(date(2026, 7, 1)),
            period_end: date(2026, 7, 31),
            needs_review: false,
            source: StatementSource::Statement,
            transactions,
            now: "2026-08-12T10:30:00Z".to_string(),
        })
        .unwrap_or_else(|e| panic!("import {name}: {e}"))
        .account_id
}

/// The performance corpus: `rows` transactions spread evenly over `accounts` accounts, written
/// by direct SQL. All amounts and descriptions are unique, so nothing here de-duplicates.
pub fn perf_corpus(conn: &mut Connection, accounts: usize, rows: usize) {
    let tx = conn.transaction().expect("begin");
    for a in 0..accounts {
        tx.execute(
            "INSERT INTO accounts \
             (id, name, bank_code, is_credit_card, currency, last4, created_at, updated_at) \
             VALUES (?1, ?2, 'SYNTHETIC', ?3, 'INR', ?4, '2026-01-01T00:00:00Z', \
                     '2026-01-01T00:00:00Z')",
            rusqlite::params![
                format!("perf-account-{a:02}"),
                format!("Synthetic Account {a:02}"),
                i64::from(a % 2 == 1),
                format!("{:04}", 1000 + a),
            ],
        )
        .expect("insert perf account");
    }

    {
        let mut stmt = tx
            .prepare(
                "INSERT INTO transactions \
                 (id, account_id, date, description_raw, amount, direction, currency, \
                  is_deleted, created_at, updated_at) \
                 VALUES (?1, ?2, ?3, ?4, ?5, 'Debit', 'INR', ?6, \
                         '2026-08-12T10:30:00Z', '2026-08-12T10:30:00Z')",
            )
            .expect("prepare perf insert");
        for i in 0..rows {
            let account = i % accounts;
            // Spread over two years of dates, so a date group is a handful of rows rather than
            // all of them and paging crosses group boundaries the way a real history does.
            let day = (i / accounts) % 730;
            let on = date(2024, 1, 1) + chrono::Duration::days(day as i64);
            // Every eleventh row is deleted, so the partial index is doing real work instead of
            // covering the whole table.
            let deleted = i64::from(i % 11 == 10);
            stmt.execute(rusqlite::params![
                format!("perf-txn-{i:06}"),
                format!("perf-account-{account:02}"),
                on.to_string(),
                format!("SYNTHETIC PERF ROW {i:06}"),
                format!("{}.{:02}", 100 + i, i % 100),
                deleted,
            ])
            .expect("insert perf row");
        }
    }

    tx.commit().expect("commit perf corpus");
}

#[cfg(test)]
mod tests {
    use super::*;

    /// R20's first corpus silently collapsed 8,750 of its 10,000 rows, and a gate over an
    /// eighth of its claimed corpus is worse than no gate. This pins every exclusion the
    /// fixture means to have — and, by counting, every one it does not.
    #[test]
    fn the_correctness_corpus_supersedes_exactly_the_rows_it_means_to() {
        let db = TestDb::new("corpus-selfcheck");
        let store = db.open();
        let corpus = correctness_corpus(&store, &db.path);
        let conn = open_sqlcipher(&db.path);

        assert_eq!(
            count(&conn, "superseded_by IS NOT NULL"),
            corpus.superseded_rows,
            "the fixture supersedes only the echo card's rows"
        );
        assert_eq!(count(&conn, "is_deleted = 1"), corpus.deleted_rows);
        assert_eq!(count(&conn, "is_transfer = 1"), corpus.transfer_rows);
        assert_eq!(
            count(&conn, "is_deleted = 0 AND superseded_by IS NULL"),
            corpus.live_rows(),
            "each account's declared live count must add up to what the store holds"
        );
    }

    /// The uniqueness rule the fixture rests on, asserted rather than trusted: apart from the
    /// rows the echo card repeats and the transfer pair's shared amount, no amount and no
    /// description occurs twice.
    #[test]
    fn the_correctness_corpus_repeats_only_what_it_declares() {
        let db = TestDb::new("corpus-uniqueness");
        let store = db.open();
        correctness_corpus(&store, &db.path);
        let conn = open_sqlcipher(&db.path);

        assert_eq!(
            repeated(&conn, "description_raw"),
            vec![
                "SYNTHETIC ECHOED PURCHASE 61".to_string(),
                "SYNTHETIC ECHOED PURCHASE 62".to_string(),
            ],
            "only the echo card repeats a description"
        );
        assert_eq!(
            repeated(&conn, "amount"),
            vec![
                TRANSFER_AMOUNT.to_string(),
                "601.11".to_string(),
                "602.22".to_string(),
            ],
            "only the transfer pair and the echoed rows share an amount"
        );
    }

    #[test]
    fn the_perf_corpus_writes_every_row_it_claims() {
        let db = TestDb::new("perf-selfcheck");
        drop(db.open());
        let mut conn = open_sqlcipher(&db.path);
        perf_corpus(&mut conn, 8, 10_000);

        assert_eq!(count(&conn, "1 = 1"), 10_000);
        assert_eq!(
            count(&conn, "superseded_by IS NOT NULL"),
            0,
            "direct SQL must not de-duplicate anything"
        );
    }

    fn count(conn: &Connection, predicate: &str) -> usize {
        conn.query_row(
            &format!("SELECT count(*) FROM transactions WHERE {predicate}"),
            [],
            |row| row.get::<_, i64>(0),
        )
        .expect("count") as usize
    }

    fn repeated(conn: &Connection, column: &str) -> Vec<String> {
        conn.prepare(&format!(
            "SELECT {column} FROM transactions GROUP BY {column} \
             HAVING count(*) > 1 ORDER BY {column}"
        ))
        .expect("prepare")
        .query_map([], |row| row.get(0))
        .expect("query")
        .collect::<rusqlite::Result<Vec<_>>>()
        .expect("collect")
    }
}
