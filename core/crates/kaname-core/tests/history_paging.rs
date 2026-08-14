//! P1–P5 and F1–F3 — paging and the account filter (`contracts/engine-history.md` §4).
//!
//! Paging is keyset, not offset: what the person has already seen cannot shift under them when
//! an import lands mid-scroll. The filter is the same read with one account in scope — not a
//! second query, a second ordering or a second population. All data is synthetic.

mod common;

use common::{correctness_corpus, walk, TestDb, ECHO_CARD, EVERYDAY};
use kaname_core::{HistoryQuery, Store};

fn ids(store: &Store, account_id: Option<&str>, limit: u32) -> Vec<String> {
    walk(store, account_id, limit)
        .into_iter()
        .map(|r| r.id)
        .collect()
}

#[test]
fn p1_every_page_size_yields_the_same_sequence() {
    let db = TestDb::new("p1");
    let store = db.open();
    correctness_corpus(&store, &db.path);

    let reference = ids(&store, None, 1);
    for limit in [7, 30, 200] {
        assert_eq!(
            ids(&store, None, limit),
            reference,
            "page size {limit} changed the sequence"
        );
    }
}

#[test]
fn p2_no_row_is_repeated_and_none_is_skipped() {
    let db = TestDb::new("p2");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);

    let paged = ids(&store, None, 3);
    let mut unique = paged.clone();
    unique.sort();
    unique.dedup();
    assert_eq!(unique.len(), paged.len(), "a row was returned twice");
    assert_eq!(paged.len(), corpus.live_rows(), "a row was skipped");
}

#[test]
fn p3_a_short_page_ends_the_sequence() {
    let db = TestDb::new("p3");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);

    let limit = (corpus.live_rows() + 10) as u32;
    let page = store
        .history_page(HistoryQuery {
            account_id: None,
            cursor: None,
            limit,
        })
        .expect("history page");
    assert!(page.rows.len() < limit as usize);
    assert!(
        page.cursor.is_none(),
        "a page shorter than its limit is the last page"
    );
}

#[test]
fn p4_an_import_between_two_pages_neither_duplicates_nor_skips_a_seen_row() {
    let db = TestDb::new("p4");
    let store = db.open();
    correctness_corpus(&store, &db.path);
    let before: Vec<String> = ids(&store, None, 200);

    let first = store
        .history_page(HistoryQuery {
            account_id: None,
            cursor: None,
            limit: 5,
        })
        .expect("first page");
    let seen: Vec<String> = first.rows.iter().map(|r| r.id.clone()).collect();
    assert_eq!(seen.len(), 5);

    // Someone imports while the person is mid-scroll. Keyset paging means the rows already on
    // screen keep their place; an offset would have shifted them.
    common::import_late_account(&store);

    let mut rest: Vec<String> = Vec::new();
    let mut cursor = first.cursor;
    while let Some(mark) = cursor {
        let page = store
            .history_page(HistoryQuery {
                account_id: None,
                cursor: Some(mark),
                limit: 5,
            })
            .expect("next page");
        rest.extend(page.rows.iter().map(|r| r.id.clone()));
        cursor = page.cursor;
    }

    for id in &seen {
        assert!(
            !rest.contains(id),
            "a row already shown was returned again after an import"
        );
    }
    let mut unique = rest.clone();
    unique.sort();
    unique.dedup();
    assert_eq!(unique.len(), rest.len(), "a row was returned twice");

    let complete: Vec<String> = seen.iter().chain(rest.iter()).cloned().collect();
    for id in &before {
        assert!(
            complete.contains(id),
            "a row that existed before the import went missing"
        );
    }
}

#[test]
fn p5_an_unknown_account_is_an_empty_page_not_an_error() {
    let db = TestDb::new("p5");
    let store = db.open();
    correctness_corpus(&store, &db.path);

    let page = store
        .history_page(HistoryQuery {
            account_id: Some("no-such-account".to_string()),
            cursor: None,
            limit: 50,
        })
        .expect("an unknown account is not an error");
    assert!(page.rows.is_empty());
    assert!(page.cursor.is_none());
}

#[test]
fn f1_a_filtered_read_returns_exactly_that_accounts_live_rows() {
    let db = TestDb::new("f1");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);

    for account in &corpus.accounts {
        let rows = walk(&store, Some(&account.id), 7);
        assert_eq!(rows.len(), account.live_rows, "{}", account.name);
        assert!(rows.iter().all(|r| r.account_id == account.id));
    }
    assert!(walk(&store, Some(&corpus.account(ECHO_CARD).id), 7).is_empty());
}

#[test]
fn f2_a_filtered_read_is_the_unfiltered_read_with_the_others_removed() {
    let db = TestDb::new("f2");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);
    let everyday = corpus.account(EVERYDAY).id.clone();

    let expected: Vec<String> = walk(&store, None, 9)
        .into_iter()
        .filter(|r| r.account_id == everyday)
        .map(|r| r.id)
        .collect();
    assert_eq!(ids(&store, Some(&everyday), 9), expected);
}

/// F3 — structural: a filter is a bound parameter, not a second code path. There is exactly
/// one page statement, [`kaname_core::PAGE_SQL`], and running it by hand reproduces both the
/// filtered read and — merged across accounts — the unfiltered one.
#[test]
fn f3_the_filtered_and_unfiltered_reads_execute_the_same_sql() {
    let db = TestDb::new("f3");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);

    assert!(
        kaname_core::PAGE_SQL.contains("is_deleted = 0 AND superseded_by IS NULL"),
        "the one page statement carries the live rule"
    );

    let conn = common::open_sqlcipher(&db.path);
    let mut stmt = conn.prepare(kaname_core::PAGE_SQL).expect("prepare");
    let mut by_hand: Vec<(String, usize, String)> = Vec::new();
    for (position, account) in corpus.accounts.iter().enumerate() {
        // The identity cursor: the newest end of the sequence, so a first page needs no
        // separate statement either.
        let rows = stmt
            .query_map(
                rusqlite::params![account.id, "9999-12-31", 0_i64, 1_000_i64],
                |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(2)?)),
            )
            .expect("query")
            .collect::<rusqlite::Result<Vec<_>>>()
            .expect("collect");

        let filtered = ids(&store, Some(&account.id), 7);
        assert_eq!(
            rows.iter().map(|r| r.0.clone()).collect::<Vec<_>>(),
            filtered,
            "the filtered read of {} is that one statement, k = 1",
            account.name
        );
        by_hand.extend(rows.into_iter().map(|(id, date)| (date, position, id)));
    }

    by_hand.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
    assert_eq!(
        by_hand.into_iter().map(|r| r.2).collect::<Vec<_>>(),
        ids(&store, None, 7),
        "the unfiltered read is the same statement, once per account, merged"
    );
}
