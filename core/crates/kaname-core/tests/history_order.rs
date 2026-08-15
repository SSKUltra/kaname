//! O1–O7 — the combined history's order (`contracts/engine-history.md` §4).
//!
//! The order is `date` descending, then the account's position in `list_accounts()` ascending,
//! then `transactions.rowid` ascending. It is total, so these are equalities rather than
//! "contains" assertions. All data is synthetic (Constitution I).

mod common;

use common::{correctness_corpus, walk, Corpus, TestDb, EVERYDAY, SHARED_DATE};

fn account_order(corpus: &Corpus) -> Vec<String> {
    corpus.accounts.iter().map(|a| a.id.clone()).collect()
}

fn position(order: &[String], id: &str) -> usize {
    order.iter().position(|a| a == id).expect("known account")
}

#[test]
fn o1_a_page_is_non_increasing_by_date() {
    let db = TestDb::new("o1");
    let store = db.open();
    correctness_corpus(&store, &db.path);

    let rows = walk(&store, None, 7);
    assert!(rows.len() > 7, "the corpus must span more than one page");
    for pair in rows.windows(2) {
        assert!(
            pair[0].date >= pair[1].date,
            "dates must not increase: {} then {}",
            pair[0].date,
            pair[1].date
        );
    }
}

#[test]
fn o2_same_date_rows_of_different_accounts_follow_the_account_list() {
    let db = TestDb::new("o2");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);
    let order = account_order(&corpus);

    let rows = walk(&store, None, 50);
    let on_shared: Vec<usize> = rows
        .iter()
        .filter(|r| r.date == SHARED_DATE)
        .map(|r| position(&order, &r.account_id))
        .collect();
    assert!(
        on_shared.len() >= 3,
        "the fixture puts three accounts on the shared date"
    );
    let mut sorted = on_shared.clone();
    sorted.sort_unstable();
    assert_eq!(
        on_shared, sorted,
        "same-date rows must appear in `list_accounts()` order"
    );
}

#[test]
fn o3_same_date_rows_of_one_account_stay_in_printed_order() {
    let db = TestDb::new("o3");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);
    let everyday = corpus.account(EVERYDAY).id.clone();

    let printed: Vec<String> = store
        .list_transactions(everyday.clone())
        .expect("raw rows")
        .into_iter()
        .filter(|t| !t.is_deleted && t.superseded_by.is_none() && t.date == corpus.crowded_date)
        .map(|t| t.description_raw)
        .collect();
    assert!(printed.len() > 1, "the crowded date must have several rows");

    let read: Vec<String> = walk(&store, Some(&everyday), 50)
        .into_iter()
        .filter(|r| r.date == corpus.crowded_date)
        .map(|r| r.description_raw)
        .collect();
    assert_eq!(read, printed);
}

#[test]
fn o4_every_page_concatenated_equals_a_brute_force_sort_of_every_live_row() {
    let db = TestDb::new("o4");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);

    // Brute force, from the raw view: every live row of every account, sorted by the ordering
    // key. `rowid` is not exposed, but `list_transactions` returns rows in `rowid` order, so a
    // row's index within its account is a faithful stand-in for it.
    let mut expected: Vec<(String, usize, usize, String)> = Vec::new();
    for (account_position, account) in corpus.accounts.iter().enumerate() {
        for (index, txn) in store
            .list_transactions(account.id.clone())
            .expect("raw rows")
            .into_iter()
            .enumerate()
        {
            if txn.is_deleted || txn.superseded_by.is_some() {
                continue;
            }
            expected.push((txn.date.to_string(), account_position, index, txn.id));
        }
    }
    expected.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)).then(a.2.cmp(&b.2)));
    let expected_ids: Vec<String> = expected.into_iter().map(|e| e.3).collect();

    let read: Vec<String> = walk(&store, None, 7).into_iter().map(|r| r.id).collect();
    assert_eq!(read, expected_ids);
    assert_eq!(read.len(), corpus.live_rows());
}

#[test]
fn o5_ten_consecutive_reads_of_an_unchanged_store_are_identical() {
    let db = TestDb::new("o5");
    let store = db.open();
    correctness_corpus(&store, &db.path);

    let first: Vec<String> = walk(&store, None, 13).into_iter().map(|r| r.id).collect();
    for run in 1..10 {
        let again: Vec<String> = walk(&store, None, 13).into_iter().map(|r| r.id).collect();
        assert_eq!(again, first, "read {run} disagreed with the first");
    }
}

#[test]
fn o6_importing_a_further_account_leaves_existing_relative_order_unchanged() {
    let db = TestDb::new("o6");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);

    let before: Vec<String> = walk(&store, None, 50).into_iter().map(|r| r.id).collect();
    common::import_late_account(&store);
    let after: Vec<String> = walk(&store, None, 50).into_iter().map(|r| r.id).collect();

    let surviving: Vec<String> = after
        .iter()
        .filter(|id| before.contains(id))
        .cloned()
        .collect();
    assert_eq!(
        surviving, before,
        "a new account must not reorder rows the person has already seen"
    );
    assert!(after.len() > corpus.live_rows());
}

#[test]
fn o7_the_account_sequence_equals_the_account_list() {
    let db = TestDb::new("o7");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);
    let order = account_order(&corpus);

    let listed: Vec<String> = store
        .list_accounts()
        .expect("accounts")
        .into_iter()
        .map(|a| a.id)
        .collect();
    assert_eq!(
        order, listed,
        "the corpus declares `list_accounts()`'s order"
    );

    let rows = walk(&store, None, 50);

    // Every account the history shows is an account the front door lists, and within any one
    // date they appear in exactly the front door's order.
    let mut contributing: Vec<String> = Vec::new();
    for row in &rows {
        assert!(listed.contains(&row.account_id));
        if !contributing.contains(&row.account_id) {
            contributing.push(row.account_id.clone());
        }
    }
    let expected: Vec<&String> = corpus
        .accounts
        .iter()
        .filter(|a| a.live_rows > 0)
        .map(|a| &a.id)
        .collect();
    let mut contributing_sorted = contributing.clone();
    contributing_sorted.sort_by_key(|id| position(&order, id));
    assert_eq!(
        contributing_sorted.iter().collect::<Vec<_>>(),
        expected,
        "every account with a live row contributes to the history, and only those do"
    );

    for pair in rows.windows(2) {
        if pair[0].date == pair[1].date {
            assert!(
                position(&order, &pair[0].account_id) <= position(&order, &pair[1].account_id),
                "within a date, accounts must follow `list_accounts()`"
            );
        }
    }
}
