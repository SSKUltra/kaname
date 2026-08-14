//! L1–L5 and Z2 — the live-row rule (`contracts/engine-history.md` §4).
//!
//! "A transaction the person actually has" is one predicate: neither deleted nor superseded.
//! These assertions hold it in place from the outside — a read that forgets the rule shows a
//! row that was withdrawn, or counts one twice. All data is synthetic (Constitution I).

mod common;

use common::{correctness_corpus, open_sqlcipher, walk, TestDb, ECHO_CARD, TRAVEL_CARD};
use kaname_core::{HistoryQuery, Store};

fn excluded_ids(store: &Store, account_id: &str) -> Vec<String> {
    store
        .list_transactions(account_id.to_string())
        .expect("raw rows")
        .into_iter()
        .filter(|t| t.is_deleted || t.superseded_by.is_some())
        .map(|t| t.id)
        .collect()
}

#[test]
fn l1_a_deleted_row_never_appears_filtered_or_not() {
    let db = TestDb::new("l1");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);
    let travel = corpus.account(TRAVEL_CARD).id.clone();

    let deleted: Vec<String> = store
        .list_transactions(travel.clone())
        .expect("raw rows")
        .into_iter()
        .filter(|t| t.is_deleted)
        .map(|t| t.id)
        .collect();
    assert_eq!(deleted.len(), corpus.deleted_rows);

    for id in deleted {
        assert!(!walk(&store, None, 7).iter().any(|r| r.id == id));
        assert!(!walk(&store, Some(&travel), 7).iter().any(|r| r.id == id));
    }
}

#[test]
fn l2_a_superseded_row_never_appears_filtered_or_not() {
    let db = TestDb::new("l2");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);
    let echo = corpus.account(ECHO_CARD).id.clone();

    let superseded = excluded_ids(&store, &echo);
    assert_eq!(superseded.len(), corpus.superseded_rows);

    let everything = walk(&store, None, 7);
    let filtered = walk(&store, Some(&echo), 7);
    assert!(
        filtered.is_empty(),
        "every row of the echo card is excluded"
    );
    for id in superseded {
        assert!(!everything.iter().any(|r| r.id == id));
    }
}

#[test]
fn l3_importing_the_same_statement_twice_leaves_the_sequence_identical() {
    let db = TestDb::new("l3");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);

    let before: Vec<String> = walk(&store, None, 9).into_iter().map(|r| r.id).collect();
    common::reimport_everyday(&store);
    let after: Vec<String> = walk(&store, None, 9).into_iter().map(|r| r.id).collect();

    assert_eq!(
        after, before,
        "a re-import must change neither the contents, the count, nor the order"
    );
    assert_eq!(after.len(), corpus.live_rows());
}

#[test]
fn l4_the_summed_live_counts_equal_a_full_read() {
    let db = TestDb::new("l4");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);

    let summed: u32 = store
        .account_summaries()
        .expect("summaries")
        .iter()
        .map(|s| s.live_transaction_count)
        .sum();
    assert_eq!(summed as usize, walk(&store, None, 50).len());
    assert_eq!(summed as usize, corpus.live_rows());
}

#[test]
fn l5_each_accounts_live_count_equals_its_filtered_read() {
    let db = TestDb::new("l5");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);

    let summaries = store.account_summaries().expect("summaries");
    assert_eq!(
        summaries.iter().map(|s| s.id.clone()).collect::<Vec<_>>(),
        corpus
            .accounts
            .iter()
            .map(|a| a.id.clone())
            .collect::<Vec<_>>(),
        "summaries follow the front door's account order"
    );

    for (summary, declared) in summaries.iter().zip(corpus.accounts.iter()) {
        let filtered = walk(&store, Some(&summary.id), 5);
        assert_eq!(
            summary.live_transaction_count as usize,
            filtered.len(),
            "{}'s count disagrees with its rows",
            summary.name
        );
        assert_eq!(summary.live_transaction_count as usize, declared.live_rows);
        assert_eq!(
            summary.has_only_excluded_rows, declared.only_excluded_rows,
            "{} holds rows and shows none",
            summary.name
        );
    }
}

/// Z2 — a storage failure must surface as an error that says nothing about the row that
/// caused it (FR-063).
#[test]
fn no_history_error_carries_a_description_amount_date_or_account_id() {
    let db = TestDb::new("z2");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);

    // Corrupt one stored amount so the read cannot parse it. `map_transaction` already fails
    // this way for the raw view; the history reads must fail the same way, and as quietly.
    let conn = open_sqlcipher(&db.path);
    conn.execute(
        "UPDATE transactions SET amount = 'not-a-decimal' WHERE description_raw = ?1",
        rusqlite::params!["SYNTHETIC GROCERY HALL 01"],
    )
    .expect("corrupt one amount");
    drop(conn);

    let error = store
        .history_page(HistoryQuery {
            account_id: None,
            cursor: None,
            limit: 50,
        })
        .expect_err("a corrupt amount must be an error, never a panic");
    let rendered = error.to_string();

    let mut secrets: Vec<String> = vec![
        "SYNTHETIC GROCERY HALL 01".to_string(),
        "101.11".to_string(),
        "not-a-decimal".to_string(),
        corpus.shared_date.to_string(),
    ];
    secrets.extend(corpus.accounts.iter().map(|a| a.id.clone()));
    for secret in secrets {
        assert!(
            !rendered.contains(&secret),
            "the error leaked {secret:?}: {rendered}"
        );
    }
}
