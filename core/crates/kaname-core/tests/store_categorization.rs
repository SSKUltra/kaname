//! Behavioural tests for slice 02 — categorization write-back (engine→store wiring). Proves
//! the store persists the categorization facts (T1 source-category map, T2 merchant map, T3
//! rules), runs the proven pure stack over stored rows via `categorize_account`, and saves
//! `category_id` + `categorised_by` — including custom categories, T3 precedence, the
//! uncategorized fall-through, idempotency, and schema v2. (The v1→v2 upgrade of an already
//! populated database is a unit test in `store.rs`.) All data is synthetic (Constitution I).

use std::path::PathBuf;
use std::str::FromStr;

use chrono::NaiveDate;
use kaname_core::{
    CategoryRef, Classification, Direction, MerchantMatch, MerchantRule, NewAccount, NewCategory,
    NewTransaction, Rule, RuleMatch, SourceCategoryMapping, Store, StoreError, StoredTransaction,
};
use rust_decimal::Decimal;

const KEY: &str = "2f1c8a9e4b7d6035112233445566778899aabbccddeeff00112233445566aabb";

struct TempDb {
    dir: PathBuf,
    path: String,
}

impl TempDb {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!(
            "kaname-cat-{}-{}-{:?}",
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

fn account(is_credit_card: bool) -> NewAccount {
    NewAccount {
        name: if is_credit_card {
            "ICICI Amazon Pay"
        } else {
            "HDFC Savings"
        }
        .to_string(),
        bank_code: "ICICI".to_string(),
        is_credit_card,
        last4: None,
        currency: "INR".to_string(),
        created_at: "2026-08-08T00:00:00Z".to_string(),
        updated_at: "2026-08-08T00:00:00Z".to_string(),
    }
}

/// A transaction template; `source_category` feeds T1, `is_credit_card` the account's kind.
fn txn(
    account_id: &str,
    description_raw: &str,
    amount: &str,
    direction: Direction,
    source_category: Option<&str>,
) -> NewTransaction {
    NewTransaction {
        account_id: account_id.to_string(),
        date: NaiveDate::from_ymd_opt(2026, 7, 4).unwrap(),
        description_raw: description_raw.to_string(),
        amount: decimal(amount),
        direction,
        currency: "INR".to_string(),
        source_category: source_category.map(str::to_string),
        category_id: None,
        categorised_by: None,
        statement_id: None,
        created_at: "2026-08-08T00:00:00Z".to_string(),
        updated_at: "2026-08-08T00:00:00Z".to_string(),
    }
}

fn builtin(catalog_id: &str) -> CategoryRef {
    CategoryRef::Builtin {
        code: catalog_id.to_string(),
    }
}

fn read(store: &Store, account_id: &str, index: usize) -> StoredTransaction {
    store
        .list_transactions(account_id.to_string())
        .expect("list")[index]
        .clone()
}

#[test]
fn categorize_account_fires_each_stage_and_leaves_no_match_uncategorized() {
    let db = TempDb::new("stages");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");

    // A bank account (for CC-payment debit + T1/T2/T3) and a card account (for the CC inflow).
    let bank = store.insert_account(account(false)).expect("bank");
    let card = store.insert_account(account(true)).expect("card");

    // Facts: a T1 issuer hint, a T2 merchant memory, a T3 keyword rule.
    store
        .insert_source_category_mapping(SourceCategoryMapping {
            bank_code: "ICICI".to_string(),
            source_category: "FUEL".to_string(),
            category: builtin("FUEL"),
        })
        .expect("t1");
    store
        .insert_merchant_rule(MerchantRule {
            priority: 10,
            match_type: MerchantMatch::Literal,
            pattern: "swiggy".to_string(),
            category: builtin("FOOD_AND_DINING"),
        })
        .expect("t2");
    store
        .insert_rule(Rule {
            id: Some("r-tuition".to_string()),
            priority: 100,
            is_system: false,
            match_type: RuleMatch::Keyword,
            value: "tuition".to_string(),
            category: builtin("EDUCATION"),
        })
        .expect("t3");

    // Bank rows: a CC bill-payment debit (CC rule), a T1 hit, a T2 hit, a T3 hit, a no-match.
    store
        .insert_transaction(txn(
            &bank,
            "CREDIT CARD PAYMENT",
            "5000.00",
            Direction::Debit,
            None,
        ))
        .expect("cc");
    store
        .insert_transaction(txn(
            &bank,
            "HPCL FUEL STATION",
            "2000.00",
            Direction::Debit,
            Some("FUEL"),
        ))
        .expect("t1row");
    store
        .insert_transaction(txn(
            &bank,
            "UPI-SWIGGY-123456",
            "250.00",
            Direction::Debit,
            None,
        ))
        .expect("t2row");
    store
        .insert_transaction(txn(
            &bank,
            "TUITION FEE BANGALORE",
            "8000.00",
            Direction::Debit,
            None,
        ))
        .expect("t3row");
    store
        .insert_transaction(txn(
            &bank,
            "UNKNOWN VENDOR XYZ",
            "123.00",
            Direction::Debit,
            None,
        ))
        .expect("nomatch");
    // A card inflow → CC bill-payment via the CC-credit rule.
    store
        .insert_transaction(txn(
            &card,
            "PAYMENT RECEIVED, THANK YOU",
            "5000.00",
            Direction::Credit,
            None,
        ))
        .expect("ccinflow");

    let summary = store
        .categorize_account(bank.clone())
        .expect("categorize bank");
    assert_eq!(summary.categorized, 4);
    assert_eq!(summary.uncategorized, 1);

    // CC rule → CREDIT_CARD_BILL_PAYMENT.
    let cc = read(&store, &bank, 0);
    assert_eq!(cc.category_id.as_deref(), Some("CREDIT_CARD_BILL_PAYMENT"));
    assert_eq!(cc.categorised_by.as_deref(), Some("CC_RULE"));
    // T1 issuer hint → FUEL.
    let t1 = read(&store, &bank, 1);
    assert_eq!(t1.category_id.as_deref(), Some("FUEL"));
    assert_eq!(t1.categorised_by.as_deref(), Some("T1_SOURCE_CATEGORY"));
    // T2 merchant memory → FOOD_AND_DINING.
    let t2 = read(&store, &bank, 2);
    assert_eq!(t2.category_id.as_deref(), Some("FOOD_AND_DINING"));
    assert_eq!(t2.categorised_by.as_deref(), Some("T2_MERCHANT_MAP"));
    // T3 rule → EDUCATION.
    let t3 = read(&store, &bank, 3);
    assert_eq!(t3.category_id.as_deref(), Some("EDUCATION"));
    assert_eq!(t3.categorised_by.as_deref(), Some("T3_RULE"));
    // No match → left uncategorized.
    let none = read(&store, &bank, 4);
    assert_eq!(none.category_id, None);
    assert_eq!(none.categorised_by, None);

    let card_summary = store
        .categorize_account(card.clone())
        .expect("categorize card");
    assert_eq!(card_summary.categorized, 1);
    let inflow = read(&store, &card, 0);
    assert_eq!(
        inflow.category_id.as_deref(),
        Some("CREDIT_CARD_BILL_PAYMENT")
    );
    assert_eq!(inflow.categorised_by.as_deref(), Some("CC_RULE"));
}

#[test]
fn t3_rule_precedence_is_honoured_through_the_store() {
    let db = TempDb::new("t3prec");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let bank = store.insert_account(account(false)).expect("bank");

    // Two T3 rules match the same narration at equal priority; the user rule (is_system =
    // false) must win over the system rule.
    store
        .insert_rule(Rule {
            id: Some("sys".to_string()),
            priority: 50,
            is_system: true,
            match_type: RuleMatch::Keyword,
            value: "gym".to_string(),
            category: builtin("HEALTH_AND_MEDICAL"),
        })
        .expect("system rule");
    store
        .insert_rule(Rule {
            id: Some("usr".to_string()),
            priority: 50,
            is_system: false,
            match_type: RuleMatch::Keyword,
            value: "gym".to_string(),
            category: builtin("ENTERTAINMENT"),
        })
        .expect("user rule");
    store
        .insert_transaction(txn(
            &bank,
            "CULT GYM MEMBERSHIP",
            "1500.00",
            Direction::Debit,
            None,
        ))
        .expect("row");

    store.categorize_account(bank.clone()).expect("categorize");
    let row = read(&store, &bank, 0);
    assert_eq!(row.category_id.as_deref(), Some("ENTERTAINMENT"));
    assert_eq!(row.categorised_by.as_deref(), Some("T3_RULE"));
}

#[test]
fn categorize_account_is_idempotent() {
    let db = TempDb::new("idempotent");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let bank = store.insert_account(account(false)).expect("bank");
    store
        .insert_merchant_rule(MerchantRule {
            priority: 10,
            match_type: MerchantMatch::Literal,
            pattern: "swiggy".to_string(),
            category: builtin("FOOD_AND_DINING"),
        })
        .expect("t2");
    store
        .insert_transaction(txn(&bank, "UPI-SWIGGY-1", "250.00", Direction::Debit, None))
        .expect("row");
    store
        .insert_transaction(txn(&bank, "UNKNOWN", "1.00", Direction::Debit, None))
        .expect("row");

    let first = store.categorize_account(bank.clone()).expect("first");
    let before = store.list_transactions(bank.clone()).expect("before");
    let second = store.categorize_account(bank.clone()).expect("second");
    let after = store.list_transactions(bank.clone()).expect("after");

    assert_eq!(first, second);
    assert_eq!(before, after, "re-running must not churn rows");
    assert_eq!(first.categorized, 1);
    assert_eq!(first.uncategorized, 1);
}

#[test]
fn custom_categories_round_trip_through_facts_and_write_back() {
    let db = TempDb::new("custom");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    let bank = store.insert_account(account(false)).expect("bank");

    // A user category, then a merchant rule pointing at it.
    let custom_id = store
        .insert_category(NewCategory {
            name: "School Fees".to_string(),
            classification: Classification::Spend,
        })
        .expect("custom category");
    store
        .insert_merchant_rule(MerchantRule {
            priority: 5,
            match_type: MerchantMatch::Literal,
            pattern: "greenwood".to_string(),
            category: CategoryRef::Custom {
                id: custom_id.clone(),
            },
        })
        .expect("t2 custom");
    store
        .insert_transaction(txn(
            &bank,
            "UPI-GREENWOOD-SCHOOL",
            "12000.00",
            Direction::Debit,
            None,
        ))
        .expect("row");

    let summary = store.categorize_account(bank.clone()).expect("categorize");
    assert_eq!(summary.categorized, 1);
    let row = read(&store, &bank, 0);
    assert_eq!(row.category_id.as_deref(), Some(custom_id.as_str()));

    // The fact reloads as a Custom ref, and the catalog now includes the user category.
    let merchants = store.list_merchant_rules().expect("merchants");
    assert_eq!(merchants.len(), 1);
    assert_eq!(
        merchants[0].category,
        CategoryRef::Custom {
            id: custom_id.clone()
        }
    );
    let catalog = store.list_categories().expect("catalog");
    assert!(catalog
        .iter()
        .any(|c| matches!(&c.category_ref, CategoryRef::Custom { id } if id == &custom_id)));
    assert_eq!(catalog.len(), 24, "23 built-ins + 1 user category");
}

#[test]
fn facts_round_trip_and_a_missing_category_fails_closed() {
    let db = TempDb::new("facts");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");

    let merchant = MerchantRule {
        priority: 20,
        match_type: MerchantMatch::Regex,
        pattern: r"amazon|amzn".to_string(),
        category: builtin("SHOPPING"),
    };
    store
        .insert_merchant_rule(merchant.clone())
        .expect("merchant");
    assert_eq!(store.list_merchant_rules().expect("list"), vec![merchant]);

    let mapping = SourceCategoryMapping {
        bank_code: "HDFC".to_string(),
        source_category: "DINING".to_string(),
        category: builtin("FOOD_AND_DINING"),
    };
    store
        .insert_source_category_mapping(mapping.clone())
        .expect("mapping");
    assert_eq!(
        store.list_source_category_mappings().expect("list"),
        vec![mapping]
    );

    let rule = Rule {
        id: Some("r1".to_string()),
        priority: 50,
        is_system: true,
        match_type: RuleMatch::AmountRange,
        value: "0,100".to_string(),
        category: builtin("MISCELLANEOUS"),
    };
    store.insert_rule(rule.clone()).expect("rule");
    assert_eq!(store.list_rules().expect("list"), vec![rule]);

    // A fact referencing a category that does not exist must fail closed (FK), not panic.
    let err = store
        .insert_merchant_rule(MerchantRule {
            priority: 1,
            match_type: MerchantMatch::Literal,
            pattern: "x".to_string(),
            category: CategoryRef::Custom {
                id: "does-not-exist".to_string(),
            },
        })
        .expect_err("missing category must be rejected");
    assert!(matches!(err, StoreError::Sql { .. }), "got {err:?}");
}

#[test]
fn schema_is_at_current_version_and_migration_is_idempotent() {
    let db = TempDb::new("schema");
    {
        let store = Store::open(db.path.clone(), KEY.to_string()).expect("open 1");
        assert_eq!(store.schema_version().expect("version"), 8);
        let bank = store.insert_account(account(false)).expect("bank");
        store
            .insert_transaction(txn(
                &bank,
                "UPI-SWIGGY",
                "1.00",
                Direction::Debit,
                Some("FOOD"),
            ))
            .expect("row");
    }
    // Re-open: the migration is a no-op and the v1 data + the new source_category survive.
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open 2");
    assert_eq!(store.schema_version().expect("version"), 8);
    let accounts = store.list_accounts().expect("accounts");
    assert_eq!(accounts.len(), 1);
    let rows = store
        .list_transactions(accounts[0].id.clone())
        .expect("rows");
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].source_category.as_deref(), Some("FOOD"));
}
