//! S1–S6 — plan shape and wall clock (`contracts/engine-history.md` §4, research R9).
//!
//! S1 and S2 are the assertions that make the live rule *structural*: the page statement is
//! served by the v7 partial index, so a read that paraphrases the rule loses the index and this
//! goes red before anyone sees a wrong row. S3–S6 hold the cost of scrolling flat as a history
//! grows. All data is synthetic (Constitution I).

mod common;

use std::time::{Duration, Instant};

use common::{open_sqlcipher, perf_corpus, TestDb};
use kaname_core::{HistoryCursor, HistoryQuery, Store};

/// The budget every wall-clock gate is measured against (SC-006, SC-007).
const BUDGET: Duration = Duration::from_millis(25);

/// A corpus of `rows` transactions over `accounts` accounts, plus the store that reads it.
fn perf_store(tag: &str, accounts: usize, rows: usize) -> (TestDb, std::sync::Arc<Store>) {
    let db = TestDb::new(tag);
    drop(db.open());
    let mut conn = open_sqlcipher(&db.path);
    perf_corpus(&mut conn, accounts, rows);
    drop(conn);
    let store = db.open();
    (db, store)
}

fn query_plan(path: &str, account_id: &str) -> Vec<String> {
    let conn = open_sqlcipher(path);
    let mut stmt = conn
        .prepare(&format!("EXPLAIN QUERY PLAN {}", kaname_core::PAGE_SQL))
        .expect("prepare plan");
    stmt.query_map(
        rusqlite::params![account_id, "9999-12-31", 0_i64, 50_i64],
        |row| row.get::<_, String>(3),
    )
    .expect("plan")
    .collect::<rusqlite::Result<Vec<_>>>()
    .expect("collect plan")
}

fn first_page(store: &Store, account_id: Option<&str>, limit: u32) -> Duration {
    let started = Instant::now();
    store
        .history_page(HistoryQuery {
            account_id: account_id.map(str::to_string),
            cursor: None,
            limit,
        })
        .expect("first page");
    started.elapsed()
}

#[test]
fn s1_the_page_plan_neither_scans_nor_sorts() {
    for (tag, accounts, rows) in [("s1-small", 2, 200), ("s1-large", 8, 10_000)] {
        let (db, _store) = perf_store(tag, accounts, rows);
        let plan = query_plan(&db.path, "perf-account-00");
        for step in &plan {
            assert!(
                !step.contains("SCAN"),
                "{tag}: the page query scans: {step}"
            );
            assert!(
                !step.contains("TEMP B-TREE"),
                "{tag}: the page query sorts: {step}"
            );
        }
    }
}

#[test]
fn s2_the_page_plan_names_the_live_index() {
    let (db, _store) = perf_store("s2", 8, 10_000);
    let plan = query_plan(&db.path, "perf-account-03");
    assert!(
        plan.iter()
            .any(|step| step.contains("idx_txn_live_account_date")),
        "the live rule must be enforced by the planner, not by remembering it: {plan:?}"
    );
}

#[test]
fn s3_the_first_page_of_a_large_history_is_within_budget() {
    let (_db, store) = perf_store("s3", 8, 10_000);
    // One warm read first: the gate is the cost of a page, not of opening the database.
    first_page(&store, None, 50);
    let elapsed = first_page(&store, None, 50);
    eprintln!("S3 first page, 10,000 rows / 8 accounts: {elapsed:?}");
    assert!(elapsed < BUDGET, "first page took {elapsed:?}");
}

#[test]
fn s4_no_page_of_a_full_walk_exceeds_the_budget() {
    let (_db, store) = perf_store("s4", 8, 10_000);

    let mut worst = Duration::ZERO;
    let mut every = Vec::new();
    let mut cursor: Option<HistoryCursor> = None;
    let mut pages = 0;
    loop {
        let started = Instant::now();
        let page = store
            .history_page(HistoryQuery {
                account_id: None,
                cursor: cursor.clone(),
                limit: 50,
            })
            .expect("page");
        let elapsed = started.elapsed();
        worst = worst.max(elapsed);
        every.push(elapsed);
        pages += 1;
        match page.cursor {
            Some(next) => cursor = Some(next),
            None => break,
        }
    }
    every.sort();
    eprintln!(
        "S4 full walk of {pages} pages: worst {worst:?}, median {:?}",
        every[every.len() / 2]
    );
    assert!(pages > 100, "the walk must cover the whole corpus");
    assert!(worst < BUDGET, "the slowest page took {worst:?}");
}

#[test]
fn s5_the_per_account_cost_does_not_grow_with_the_history() {
    let (_db_small, small) = perf_store("s5-small", 2, 200);
    let (_db_large, large) = perf_store("s5-large", 8, 10_000);

    // Per account, so the comparison is like for like: the large corpus reads four times as
    // many streams, and that is the only difference the caller pays for.
    let small_cost = median(|| first_page(&small, None, 50)).as_secs_f64() / 2.0;
    let large_cost = median(|| first_page(&large, None, 50)).as_secs_f64() / 8.0;

    // One-sided, because the claim is that page cost does not **grow** with the corpus
    // (SC-008b, research R9, which measured the larger corpus 13% cheaper per account — its
    // index pages are warmer). Through `history_page` the gap is wider still and in the same
    // direction: a page's fixed cost — one lock, one account list, one category catalog —
    // is divided by two accounts on the small corpus and by eight on the large one. Fifty
    // times more rows making a page *dearer* per account is the regression worth catching.
    let growth = (large_cost - small_cost) / small_cost;
    eprintln!(
        "S5 per-account first page: {small_cost:.6}s (200/2) vs {large_cost:.6}s (10,000/8), \
         spread {:.0}%",
        growth * 100.0
    );
    assert!(
        growth <= 0.20,
        "per-account first-page cost grew {:.0}% with the corpus \
         ({small_cost:.6}s vs {large_cost:.6}s per account)",
        growth * 100.0
    );
}

#[test]
fn s6_a_filtered_page_of_a_large_history_is_within_budget() {
    let (_db, store) = perf_store("s6", 8, 10_000);
    first_page(&store, Some("perf-account-05"), 50);
    let elapsed = first_page(&store, Some("perf-account-05"), 50);
    eprintln!("S6 filtered first page, 10,000 rows / 8 accounts: {elapsed:?}");
    assert!(elapsed < BUDGET, "a filtered first page took {elapsed:?}");
}

/// Wall-clock measurements on a shared machine are noisy; the median of nine short reads is
/// stable enough to compare two corpora without being a flake.
fn median(mut read: impl FnMut() -> Duration) -> Duration {
    let mut samples: Vec<Duration> = (0..9).map(|_| read()).collect();
    samples.sort();
    samples[samples.len() / 2]
}

#[test]
fn s7_the_front_door_count_is_one_grouped_read() {
    let (db, store) = perf_store("s7", 8, 10_000);
    store.account_summaries().expect("warm");
    let elapsed = median(|| {
        let started = Instant::now();
        store.account_summaries().expect("summaries");
        started.elapsed()
    });
    let file = std::fs::metadata(&db.path).map(|m| m.len()).unwrap_or(0);
    eprintln!("S7 account_summaries(), 10,000 rows / 8 accounts: {elapsed:?}; db file {file} B");
    assert!(elapsed < BUDGET, "the front-door count took {elapsed:?}");
}
