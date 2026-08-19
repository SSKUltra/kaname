//! **M1–M11** — the merchant memory: what a person taught the app, and how far it reaches.
//!
//! A memory is **not** a rule (`list_merchant_rules` never grows one, M11) and **not** a tier
//! (`categorize.rs` is not modified). It is consulted by the store *beside* the categorization
//! stack and **before** it, which is what M2 pins: a person who says "this is Groceries" outranks
//! every verdict the engine can reach on its own.
//!
//! Every row here is synthetic (Constitution Principle I).

mod common;

use chrono::NaiveDate;
use common::{open_sqlcipher, TestDb};
use kaname_core::{
    CategoryRef, Direction, ImportAccountTarget, ImportRequest, MerchantMatch, MerchantRule,
    NewAccount, NewImportTransaction, SourceCategoryMapping, StatementSource, Store, StoreError,
};
use rust_decimal::Decimal;
use std::str::FromStr;

fn decimal(value: &str) -> Decimal {
    Decimal::from_str(value).expect("decimal")
}

fn date(y: i32, m: u32, d: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(y, m, d).expect("date")
}

fn account(name: &str, is_credit_card: bool) -> NewAccount {
    NewAccount {
        name: name.to_string(),
        bank_code: "HDFC".to_string(),
        is_credit_card,
        last4: None,
        currency: "INR".to_string(),
        created_at: "2026-01-01T00:00:00Z".to_string(),
        updated_at: "2026-01-01T00:00:00Z".to_string(),
    }
}

fn import_txn(description_raw: &str, amount: &str, day: u32) -> NewImportTransaction {
    NewImportTransaction {
        date: date(2026, 7, day),
        description_raw: description_raw.to_string(),
        amount: decimal(amount),
        direction: Direction::Debit,
        currency: "INR".to_string(),
        source_category: None,
    }
}

fn card_credit(description_raw: &str, amount: &str, day: u32) -> NewImportTransaction {
    NewImportTransaction {
        direction: Direction::Credit,
        ..import_txn(description_raw, amount, day)
    }
}

fn filed_as(description_raw: &str, amount: &str, day: u32, source: &str) -> NewImportTransaction {
    NewImportTransaction {
        source_category: Some(source.to_string()),
        ..import_txn(description_raw, amount, day)
    }
}

fn import(store: &Store, account_id: &str, transactions: Vec<NewImportTransaction>) {
    store
        .import_statement(ImportRequest {
            account: ImportAccountTarget::Existing {
                id: account_id.to_string(),
                last4: None,
            },
            bank_code: "HDFC".to_string(),
            period_start: Some(date(2026, 7, 1)),
            period_end: date(2026, 7, 31),
            needs_review: false,
            source: StatementSource::Statement,
            transactions,
            now: "2026-08-19T10:30:00Z".to_string(),
        })
        .expect("import");
}

fn groceries() -> CategoryRef {
    CategoryRef::Builtin {
        code: "GROCERIES".to_string(),
    }
}

fn shopping() -> CategoryRef {
    CategoryRef::Builtin {
        code: "SHOPPING".to_string(),
    }
}

/// Every memory the store holds, as `(merchant_portion, category_id)` pairs. Read by direct SQL
/// because a memory is deliberately not exposed as a rule (M11) — there is no list API to lean
/// on, and inventing one for a test would be inventing the thing M11 forbids.
fn memories(path: &str) -> Vec<(String, String)> {
    let conn = open_sqlcipher(path);
    let mut stmt = conn
        .prepare(
            "SELECT merchant_portion, category_id FROM merchant_memory ORDER BY merchant_portion",
        )
        .expect("prepare");
    let rows = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("query")
        .collect::<rusqlite::Result<Vec<(String, String)>>>()
        .expect("collect");
    rows
}

fn row_id(store: &Store, account_id: &str, needle: &str) -> String {
    store
        .list_transactions(account_id.to_string())
        .expect("list transactions")
        .into_iter()
        .find(|row| row.description_raw.contains(needle))
        .unwrap_or_else(|| panic!("no row matching {needle}"))
        .id
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

/// **M3** — a person who changes their mind about a merchant has **one** memory, naming the
/// newest choice (FR-031, FR-033). The `PRIMARY KEY` is what makes this true: newest-wins is
/// achieved by replacing the row, which is also why the table carries no timestamp and why the
/// engine still reads no clock.
#[test]
fn correcting_the_same_merchant_twice_leaves_one_memory_naming_the_newest_choice() {
    let db = TestDb::new("m3");
    let store = db.open();
    let account_id = store
        .insert_account(account("Synthetic Savings", false))
        .expect("account");
    import(
        &store,
        &account_id,
        vec![
            import_txn("UPI-SYNTHCAFE-100001", "410.00", 4),
            import_txn("UPI-SYNTHCAFE-100002", "620.00", 9),
        ],
    );

    let first = row_id(&store, &account_id, "100001");
    let second = row_id(&store, &account_id, "100002");
    store
        .set_transaction_category(first, Some(shopping()), true)
        .expect("first correction");
    store
        .set_transaction_category(second, Some(groceries()), true)
        .expect("second correction");

    assert_eq!(
        memories(&db.path),
        vec![("synthcafe".to_string(), "GROCERIES".to_string())],
        "one merchant is one memory, and the newest choice is the one that stands"
    );
}

/// **M11** — a memory is **not** a rule, and must not appear as one. `list_merchant_rules()` is
/// already exported to the platform (the T2 merchant map); if a memory showed up there it would
/// become editable, orderable and deletable through a surface built for a different thing, and
/// the two would drift.
#[test]
fn a_memory_never_appears_among_the_merchant_rules() {
    let db = TestDb::new("m11");
    let store = db.open();
    store
        .insert_merchant_rule(MerchantRule {
            priority: 10,
            match_type: MerchantMatch::Literal,
            pattern: "synthfuel".to_string(),
            category: shopping(),
        })
        .expect("rule");
    let before = store.list_merchant_rules().expect("rules before");

    let account_id = store
        .insert_account(account("Synthetic Savings", false))
        .expect("account");
    import(
        &store,
        &account_id,
        vec![import_txn("UPI-SYNTHCAFE-100001", "410.00", 4)],
    );
    let txn_id = row_id(&store, &account_id, "100001");
    store
        .set_transaction_category(txn_id, Some(groceries()), true)
        .expect("correction");

    assert_eq!(
        memories(&db.path).len(),
        1,
        "the memory was formed, so this test is looking at the right store"
    );
    let after = store.list_merchant_rules().expect("rules after");
    assert_eq!(before.len(), after.len(), "a memory must not become a rule");
    assert_eq!(
        after
            .iter()
            .map(|rule| rule.pattern.clone())
            .collect::<Vec<_>>(),
        vec!["synthfuel".to_string()]
    );
}

/// **M1** — the app remembers. A merchant taught once lands in the remembered category on the
/// **next import**, carrying `PERSON_MEMORY` so that its provenance says where it came from and
/// [`ENGINE_MAY_DECIDE`] leaves it alone afterwards (FR-030).
#[test]
fn a_remembered_merchant_lands_in_its_category_on_the_next_import() {
    let db = TestDb::new("m1");
    let store = db.open();
    let account_id = store
        .insert_account(account("Synthetic Savings", false))
        .expect("account");
    import(
        &store,
        &account_id,
        vec![import_txn("UPI-SYNTHCAFE-100001", "410.00", 4)],
    );

    let taught = row_id(&store, &account_id, "100001");
    let outcome = store
        .set_transaction_category(taught, Some(groceries()), true)
        .expect("correction");
    assert!(outcome.memory_formed, "the memory is the premise of M1");

    // A different reference, a different day and a different amount: a new row, not a duplicate
    // of the row the person corrected.
    import(
        &store,
        &account_id,
        vec![import_txn("UPI-SYNTHCAFE-200002", "777.00", 19)],
    );

    let arrived = row_id(&store, &account_id, "200002");
    assert_eq!(
        provenance(&store, &account_id, &arrived),
        (
            Some("GROCERIES".to_string()),
            Some("PERSON_MEMORY".to_string())
        ),
        "a merchant taught once must not have to be taught again"
    );
}

/// **M2** — the memory outranks everything the engine can decide on its own: a credit-card
/// narration rule (the top of the stack) and a T1 source-category mapping (the issuer's own
/// label).
///
/// This is the judgement call, written as an assertion: *the engine's rules describe what it
/// could work out; a memory records what the person told it, and the second is better evidence
/// about their intent than the first.* Consulting the memory **after** the stack would leave a
/// person correcting the same merchant every month while the app kept overruling them — the
/// exact complaint this slice exists to answer.
#[test]
fn a_memory_beats_a_card_rule_and_the_issuers_own_label() {
    let db = TestDb::new("m2");
    let store = db.open();
    let card_id = store
        .insert_account(account("Synthetic Card", true))
        .expect("card");
    let bank_id = store
        .insert_account(account("Synthetic Savings", false))
        .expect("bank");
    store
        .insert_source_category_mapping(SourceCategoryMapping {
            bank_code: "HDFC".to_string(),
            source_category: "FOOD".to_string(),
            category: CategoryRef::Builtin {
                code: "FOOD_AND_DINING".to_string(),
            },
        })
        .expect("source category map");

    import(
        &store,
        &card_id,
        vec![card_credit("10% SYNTHCAFE Cashback", "150.00", 4)],
    );
    import(
        &store,
        &bank_id,
        vec![filed_as("UPI-SYNTHFUEL-100003", "300.00", 5, "FOOD")],
    );

    let cashback = row_id(&store, &card_id, "10%");
    let fuel = row_id(&store, &bank_id, "SYNTHFUEL");
    assert_eq!(
        provenance(&store, &card_id, &cashback).1,
        Some("CC_RULE".to_string()),
        "the premise: the card rule claims this row when nothing else does"
    );
    assert_eq!(
        provenance(&store, &bank_id, &fuel).1,
        Some("T1_SOURCE_CATEGORY".to_string()),
        "the premise: the issuer's own label claims this row when nothing else does"
    );

    store
        .set_transaction_category(cashback, Some(groceries()), true)
        .expect("teach the card row");
    store
        .set_transaction_category(fuel, Some(shopping()), true)
        .expect("teach the bank row");

    import(
        &store,
        &card_id,
        vec![card_credit("12% SYNTHCAFE Cashback", "260.00", 18)],
    );
    import(
        &store,
        &bank_id,
        vec![filed_as("UPI-SYNTHFUEL-200004", "480.00", 19, "FOOD")],
    );

    let new_cashback = row_id(&store, &card_id, "12%");
    let new_fuel = row_id(&store, &bank_id, "200004");
    assert_eq!(
        provenance(&store, &card_id, &new_cashback),
        (
            Some("GROCERIES".to_string()),
            Some("PERSON_MEMORY".to_string())
        ),
        "a memory must outrank the card rule"
    );
    assert_eq!(
        provenance(&store, &bank_id, &new_fuel),
        (
            Some("SHOPPING".to_string()),
            Some("PERSON_MEMORY".to_string())
        ),
        "a memory must outrank the issuer's own label"
    );
}

/// One row's provenance by id, wherever it lives — the "nothing was written" assertions span
/// accounts, and `list_transactions` is per-account.
fn row_provenance(path: &str, txn_id: &str) -> Option<String> {
    let conn = open_sqlcipher(path);
    conn.query_row(
        "SELECT categorised_by FROM transactions WHERE id = ?1",
        [txn_id],
        |row| row.get(0),
    )
    .expect("the row is still there")
}

/// The rows a preview says it would change, in the order it reports them.
fn preview_ids(store: &Store, portion: &str) -> Vec<String> {
    store
        .preview_memory_application(portion.to_string())
        .expect("preview")
        .transaction_ids
}

/// Two accounts holding four rows of one merchant, plus one row of another. Returns
/// `(bank_id, card_id)`.
fn two_accounts_of_one_merchant(store: &Store) -> (String, String) {
    let bank_id = store
        .insert_account(account("Synthetic Savings", false))
        .expect("bank");
    let card_id = store
        .insert_account(account("Synthetic Card", true))
        .expect("card");
    import(
        store,
        &bank_id,
        vec![
            import_txn("UPI-SYNTHCAFE-100001", "410.00", 4),
            import_txn("UPI-SYNTHCAFE-100002", "620.00", 9),
            import_txn("UPI-SYNTHFUEL-100003", "300.00", 11),
        ],
    );
    import(
        store,
        &card_id,
        vec![
            import_txn("UPI-SYNTHCAFE-100004", "155.00", 6),
            import_txn("UPI-SYNTHCAFE-100005", "265.00", 14),
        ],
    );
    (bank_id, card_id)
}

/// **M4** — a hand correction is never collateral. `'PERSON'` rows are neither counted in the
/// blast radius nor written by the apply (FR-035d): the person already answered for that row,
/// and a bulk action must not quietly reverse an answer they gave one at a time.
#[test]
fn a_preview_never_includes_a_row_the_person_corrected_by_hand() {
    let db = TestDb::new("m4");
    let store = db.open();
    let (bank_id, _) = two_accounts_of_one_merchant(&store);

    let by_hand = row_id(&store, &bank_id, "100001");
    store
        .set_transaction_category(by_hand.clone(), Some(shopping()), false)
        .expect("hand correction");
    let taught = row_id(&store, &bank_id, "100002");
    store
        .set_transaction_category(taught.clone(), Some(groceries()), true)
        .expect("teach");

    let previewed = preview_ids(&store, "synthcafe");
    assert!(
        !previewed.contains(&by_hand),
        "a hand-corrected row is not collateral"
    );
    assert!(
        !previewed.contains(&taught),
        "the row that formed the memory is a 'PERSON' row too"
    );
    assert_eq!(previewed.len(), 2, "the two card rows, and nothing else");
}

/// **M5** — the second action applies **exactly** what the preview stated: the same rows, the
/// `PERSON_MEMORY` provenance, and a count that matches what the person was shown (FR-035e).
#[test]
fn apply_writes_exactly_the_rows_the_preview_named() {
    let db = TestDb::new("m5");
    let store = db.open();
    let (bank_id, card_id) = two_accounts_of_one_merchant(&store);
    let taught = row_id(&store, &bank_id, "100001");
    store
        .set_transaction_category(taught, Some(groceries()), true)
        .expect("teach");

    let impact = store
        .preview_memory_application("synthcafe".to_string())
        .expect("preview");
    assert_eq!(impact.transaction_ids.len(), 3);
    assert_eq!(
        impact
            .accounts
            .iter()
            .map(|a| (a.display_name.clone(), a.count))
            .collect::<Vec<_>>(),
        vec![
            ("Synthetic Card".to_string(), 2),
            ("Synthetic Savings".to_string(), 1),
        ],
        "the blast radius is stated in a person's terms, by account name"
    );

    let written = store
        .apply_memory("synthcafe".to_string(), impact.transaction_ids.clone())
        .expect("apply");
    assert_eq!(written, impact.transaction_ids.len() as u32);
    for id in &impact.transaction_ids {
        let account = if id == &row_id(&store, &card_id, "100004")
            || id == &row_id(&store, &card_id, "100005")
        {
            &card_id
        } else {
            &bank_id
        };
        assert_eq!(
            provenance(&store, account, id),
            (
                Some("GROCERIES".to_string()),
                Some("PERSON_MEMORY".to_string())
            )
        );
    }
}

/// **M7** 🚨 — a trimmed list is **refused**, not obeyed.
///
/// This is where FR-035b is enforced, and it is enforced in the *engine* on purpose: a caller
/// that says "apply to just these three" gets `StaleSet`. There is no arrangement of any
/// interface — hostile, or merely mistaken — that turns the second action into a bulk
/// recategorize, because the engine will not accept a chosen subset. A test against a UI that
/// happens to have no checkbox would prove nothing about the next UI.
#[test]
fn apply_refuses_a_trimmed_set_rather_than_obeying_it() {
    let db = TestDb::new("m7");
    let store = db.open();
    let (bank_id, _) = two_accounts_of_one_merchant(&store);
    let taught = row_id(&store, &bank_id, "100001");
    store
        .set_transaction_category(taught, Some(groceries()), true)
        .expect("teach");

    let previewed = preview_ids(&store, "synthcafe");
    assert_eq!(previewed.len(), 3);
    let trimmed = previewed[..2].to_vec();

    let err = store
        .apply_memory("synthcafe".to_string(), trimmed)
        .expect_err("a chosen subset must be refused");
    assert!(
        matches!(
            err,
            StoreError::StaleSet {
                expected: 2,
                found: 3
            }
        ),
        "got {err:?}"
    );
    for id in &previewed {
        assert!(
            row_provenance(&db.path, id) != Some("PERSON_MEMORY".to_string()),
            "nothing may be written when the set is refused"
        );
    }
}

/// **M6** — the set the person agreed to is the set that is written. A row that appears between
/// the preview and the apply makes the agreement stale, and staleness is refused rather than
/// resolved (FR-035f).
///
/// A count-only token could not catch this: one row added and one removed leaves the count
/// unchanged and the *set* different, and it is the set the person was shown.
#[test]
fn a_set_that_changed_between_preview_and_apply_is_refused() {
    let db = TestDb::new("m6");
    let store = db.open();
    let (bank_id, _) = two_accounts_of_one_merchant(&store);
    let taught = row_id(&store, &bank_id, "100001");
    store
        .set_transaction_category(taught, Some(groceries()), true)
        .expect("teach");
    let previewed = preview_ids(&store, "synthcafe");

    // A row leaves the set, by the one route the public API deliberately does not offer.
    // ⚠️ Not by importing another matching row: an import re-categorizes the account's
    // undecided rows through the same memory, so the rows would change for a legitimate reason
    // and the assertion below could not tell that apart from a partial apply.
    {
        let conn = open_sqlcipher(&db.path);
        conn.execute(
            "UPDATE transactions SET is_deleted = 1 WHERE id = ?1",
            [previewed.first().expect("a previewed row")],
        )
        .expect("delete a row");
    }

    let err = store
        .apply_memory("synthcafe".to_string(), previewed.clone())
        .expect_err("the agreed set no longer exists");
    assert!(matches!(err, StoreError::StaleSet { .. }), "got {err:?}");
    for id in &previewed {
        assert!(
            row_provenance(&db.path, id) != Some("PERSON_MEMORY".to_string()),
            "a refused apply writes nothing at all"
        );
    }
}

/// **M8** — applying twice is a genuine no-op, not a harmless repeat: the second preview is
/// empty because the rows already carry this memory for this category (FR-035h).
#[test]
fn applying_twice_writes_nothing_the_second_time() {
    let db = TestDb::new("m8");
    let store = db.open();
    let (bank_id, _) = two_accounts_of_one_merchant(&store);
    let taught = row_id(&store, &bank_id, "100001");
    store
        .set_transaction_category(taught, Some(groceries()), true)
        .expect("teach");

    let first = preview_ids(&store, "synthcafe");
    store
        .apply_memory("synthcafe".to_string(), first.clone())
        .expect("first apply");

    let second = preview_ids(&store, "synthcafe");
    assert!(second.is_empty(), "there is nothing left to change");
    let written = store
        .apply_memory("synthcafe".to_string(), second)
        .expect("second apply");
    assert_eq!(written, 0);
}

/// **M9** — all or nothing (FR-035g). One row's write is forced to fail; not one of the others
/// may survive it, or the person's agreed blast radius silently became a partial one.
#[test]
fn a_failure_part_way_through_writes_nothing() {
    let db = TestDb::new("m9");
    let store = db.open();
    let (bank_id, _) = two_accounts_of_one_merchant(&store);
    let taught = row_id(&store, &bank_id, "100001");
    store
        .set_transaction_category(taught, Some(groceries()), true)
        .expect("teach");
    let previewed = preview_ids(&store, "synthcafe");

    {
        let conn = open_sqlcipher(&db.path);
        // A trigger body cannot carry a bound parameter, so the id is inlined.
        conn.execute_batch(&format!(
            "CREATE TRIGGER refuse_one BEFORE UPDATE ON transactions \
             WHEN NEW.id = '{}' BEGIN SELECT RAISE(ABORT, 'refused'); END;",
            previewed.last().expect("a previewed row")
        ))
        .expect("trigger");
    }

    let err = store
        .apply_memory("synthcafe".to_string(), previewed.clone())
        .expect_err("one refused write fails the whole apply");
    assert!(matches!(err, StoreError::Sql { .. }), "got {err:?}");
    for id in &previewed {
        assert!(
            row_provenance(&db.path, id) != Some("PERSON_MEMORY".to_string()),
            "a partial apply is worse than none"
        );
    }
}

/// **M10** — a memory can never point at a category that does not exist, and when it is gone
/// nothing is applied on its behalf (FR-034).
///
/// The foreign key is the whole mechanism: the first half of this test is the database
/// *refusing* to orphan the memory, and the second is what the engine does once the memory
/// really has been removed.
#[test]
fn a_memory_cannot_outlive_its_category() {
    let db = TestDb::new("m10");
    let store = db.open();
    let (bank_id, _) = two_accounts_of_one_merchant(&store);
    let taught = row_id(&store, &bank_id, "100001");
    store
        .set_transaction_category(taught, Some(groceries()), true)
        .expect("teach");
    let previewed = preview_ids(&store, "synthcafe");
    assert_eq!(previewed.len(), 3);

    {
        let conn = open_sqlcipher(&db.path);
        conn.execute("DELETE FROM categories WHERE id = 'GROCERIES'", [])
            .expect_err("the foreign key must refuse to orphan the memory");
        conn.execute(
            "DELETE FROM merchant_memory WHERE merchant_portion = 'synthcafe'",
            [],
        )
        .expect("removing the memory first is allowed");
    }

    assert!(
        preview_ids(&store, "synthcafe").is_empty(),
        "a portion with no memory has no blast radius"
    );
    let err = store
        .apply_memory("synthcafe".to_string(), previewed.clone())
        .expect_err("there is no memory to apply");
    assert!(matches!(err, StoreError::StaleSet { .. }), "got {err:?}");
    for id in &previewed {
        assert!(
            row_provenance(&db.path, id) != Some("PERSON_MEMORY".to_string()),
            "nothing is written on a departed memory's behalf"
        );
    }
}
