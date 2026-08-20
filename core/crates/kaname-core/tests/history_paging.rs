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
            uncategorized_only: false,
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
            uncategorized_only: false,
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
                uncategorized_only: false,
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
            uncategorized_only: false,
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

// ---------------------------------------------------------------------------------------------
// H1–H6 — the uncategorized narrowing (`020/contracts/engine-categorize.md` §4).
//
// The worklist is the same read with one more `WHERE` term, so every assertion here is about the
// narrowing being *only* that: the unnarrowed read does not move (H1), the narrowed one is
// exactly `LIVE ∧ UNANSWERED` including a person's deliberate blank (H2), it composes with the
// account filter rather than replacing it (H3), it pages like everything else (H4), and the count
// the entry point shows is the length of the list it opens (H5).
// ---------------------------------------------------------------------------------------------

/// The rows nothing has answered yet, read straight from the database — the definition H2 and H5
/// are checked against, spelled independently of the store so the two cannot agree by sharing an
/// implementation.
fn unanswered_ids_by_hand(path: &str) -> Vec<String> {
    let conn = common::open_sqlcipher(path);
    let mut stmt = conn
        .prepare(
            "SELECT id FROM transactions \
             WHERE is_deleted = 0 AND superseded_by IS NULL \
             AND category_id IS NULL AND categorised_by IS NULL",
        )
        .expect("prepare");
    let mut ids: Vec<String> = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query")
        .collect::<rusqlite::Result<Vec<_>>>()
        .expect("collect");
    ids.sort();
    ids
}

fn sorted(mut ids: Vec<String>) -> Vec<String> {
    ids.sort();
    ids
}

/// **H1** — the unnarrowed read is byte-identical to the one 018 shipped: the same statement,
/// the same population, the same sequence at every page size (FR-046).
///
/// Green by construction the day it is written. It exists so that the narrowing — and every
/// later change that touches the page statement — has something that goes red if the default
/// path moves even slightly.
#[test]
fn h1_an_unnarrowed_read_is_the_read_018_shipped() {
    assert_eq!(
        kaname_core::PAGE_SQL,
        "SELECT t.id, t.account_id, t.date, t.description_raw, t.amount, t.direction, \
         t.currency, t.category_id, t.is_transfer, t.rowid \
         FROM transactions t \
         WHERE t.account_id = ?1 AND is_deleted = 0 AND superseded_by IS NULL \
         AND (t.date < ?2 OR (t.date = ?2 AND t.rowid > ?3)) \
         ORDER BY t.date DESC, t.rowid ASC \
         LIMIT ?4",
        "the unnarrowed page statement is pinned: a narrowing that edits it is not a narrowing"
    );

    let db = TestDb::new("h1");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);

    let reference = ids(&store, None, 1);
    assert_eq!(reference.len(), corpus.live_rows(), "every live row, still");
    for limit in [7, 200] {
        assert_eq!(ids(&store, None, limit), reference, "page size {limit}");
    }
}

/// **H2** — `uncategorized_only: true` returns exactly `LIVE ∧ UNANSWERED`, and a person's
/// deliberate blank is **not** in it (spec amendment §1).
///
/// The blank is the whole reason the predicate has a provenance arm: a row a person chose to
/// leave uncategorized has been answered, and a worklist that kept offering it back could never
/// reach zero for anyone who used FR-007 as intended.
#[test]
fn h2_the_narrowed_read_is_live_and_unanswered() {
    let db = TestDb::new("h2");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);

    let narrowed = sorted(
        common::walk_unanswered(&store, None, 7)
            .into_iter()
            .map(|r| r.id)
            .collect(),
    );
    assert_eq!(narrowed, unanswered_ids_by_hand(&db.path));
    assert!(
        !narrowed.is_empty(),
        "the fixture must leave rows unanswered"
    );
    assert!(
        narrowed.len() < corpus.live_rows(),
        "the fixture must also leave rows answered, or the narrowing proves nothing"
    );

    let blank = narrowed[0].clone();
    store
        .set_transaction_category(blank.clone(), None, false)
        .expect("a deliberate blank");

    let after = sorted(
        common::walk_unanswered(&store, None, 7)
            .into_iter()
            .map(|r| r.id)
            .collect(),
    );
    assert!(
        !after.contains(&blank),
        "a row a person deliberately left blank has been answered, and is not on the worklist"
    );
    assert_eq!(after.len(), narrowed.len() - 1, "and nothing else moved");
}

/// **H3** — the narrowing composes with the account filter. Two axes, one query (FR-039).
#[test]
fn h3_the_narrowing_composes_with_the_account_filter() {
    let db = TestDb::new("h3");
    let store = db.open();
    let corpus = correctness_corpus(&store, &db.path);
    let everyday = corpus.account(EVERYDAY).id.clone();

    let expected: Vec<String> = common::walk_unanswered(&store, None, 9)
        .into_iter()
        .filter(|r| r.account_id == everyday)
        .map(|r| r.id)
        .collect();
    let both_axes: Vec<String> = common::walk_unanswered(&store, Some(&everyday), 9)
        .into_iter()
        .map(|r| r.id)
        .collect();

    assert!(!expected.is_empty(), "the ledger must have unanswered rows");
    assert_eq!(
        both_axes, expected,
        "the filter narrows the worklist in place"
    );
    assert!(
        both_axes.len() < walk(&store, Some(&everyday), 9).len(),
        "and the account's own read still holds rows the worklist does not"
    );
}

/// **H4** — paging across a narrowed set is stable and complete: no row twice, none skipped
/// (FR-040). The narrowing changes which rows the sequence holds, not how it is cut.
#[test]
fn h4_a_narrowed_walk_pages_like_every_other_walk() {
    let db = TestDb::new("h4");
    let store = db.open();
    correctness_corpus(&store, &db.path);

    let reference: Vec<String> = common::walk_unanswered(&store, None, 1)
        .into_iter()
        .map(|r| r.id)
        .collect();
    for limit in [3, 7, 200] {
        let paged: Vec<String> = common::walk_unanswered(&store, None, limit)
            .into_iter()
            .map(|r| r.id)
            .collect();
        assert_eq!(paged, reference, "page size {limit} changed the sequence");
    }

    let mut unique = reference.clone();
    unique.dedup();
    assert_eq!(unique.len(), reference.len(), "a row was returned twice");
    assert_eq!(
        sorted(reference),
        unanswered_ids_by_hand(&db.path),
        "a row was skipped"
    );
}

/// **H5** — `uncategorized_count()` is the length of the list it opens. The two are the same
/// question asked once: both are spelled from the `UNANSWERED` constant, and this is the proof
/// that neither has grown a second spelling.
#[test]
fn h5_the_count_is_the_length_of_the_narrowed_walk() {
    let db = TestDb::new("h5");
    let store = db.open();
    correctness_corpus(&store, &db.path);

    let walked = common::walk_unanswered(&store, None, 7).len() as u32;
    assert!(walked > 0, "the fixture must leave rows unanswered");
    assert_eq!(store.uncategorized_count().expect("count"), walked);

    // And it follows the worklist down as the person works through it.
    let first = common::walk_unanswered(&store, None, 7)[0].id.clone();
    store
        .set_transaction_category(
            first,
            Some(kaname_core::CategoryRef::Builtin {
                code: "GROCERIES".to_string(),
            }),
            false,
        )
        .expect("correction");
    assert_eq!(store.uncategorized_count().expect("count"), walked - 1);
}

/// **H6** — a row carries its category's **id** as well as its display name, and the two agree.
///
/// The id is what lets the picker mark the current category by identity rather than by matching
/// a display name — two categories may legitimately be renamed to the same words, and a mark
/// that depended on the words would follow the rename.
#[test]
fn h6_a_row_carries_its_category_id_and_it_agrees_with_the_name() {
    let db = TestDb::new("h6");
    let store = db.open();
    correctness_corpus(&store, &db.path);

    let names: std::collections::HashMap<String, String> = store
        .list_categories()
        .expect("categories")
        .into_iter()
        .map(|c| {
            let id = match c.category_ref {
                kaname_core::CategoryRef::Builtin { code } => code,
                kaname_core::CategoryRef::Custom { id } => id,
            };
            (id, c.name)
        })
        .collect();

    let rows = walk(&store, None, 7);
    let mut categorized = 0;
    for row in &rows {
        match (&row.category_id, &row.category_name) {
            (Some(id), Some(name)) => {
                assert_eq!(
                    names.get(id),
                    Some(name),
                    "row {} names two categories",
                    row.id
                );
                categorized += 1;
            }
            (None, None) => {}
            other => panic!("row {} carries half a category: {other:?}", row.id),
        }
    }
    assert!(categorized > 0, "the fixture must categorize something");
}
