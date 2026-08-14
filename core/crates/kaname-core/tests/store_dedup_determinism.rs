//! Slice 018, PR A — cross-account de-duplication must be **deterministic**, and it must only
//! ever compare a bank ledger against a credit card.
//!
//! Two defects in shipped code, both found while planning 018's read path and both invisible
//! until this slice put a person's transactions on screen:
//!
//! 1. **The winner was random.** `load_dedup_candidates` ordered account groups by
//!    `a.created_at, a.id`. Two accounts imported in the same second share a `created_at`, so
//!    the tie-break fell through to `a.id` — `lower(hex(randomblob(16)))`. Which of a person's
//!    two cards kept a transaction was decided by 128 random bits, and the same import on a
//!    fresh database superseded the opposite row on the next run.
//! 2. **Two cards were de-duplicated against each other.** `find_duplicates_in` folds every
//!    account against a pool of all earlier ones with no regard to what kind either is. Slice
//!    013 only ever intended "the same purchase appears in two different statements … a
//!    bank-account ledger and a credit-card statement" (`specs/013-cross-source-dedup/spec.md`).
//!    Two cards printing the same coffee on the same day are two real purchases, and one of
//!    them was being hidden.
//!
//! Every row here is invented (Constitution I).

use std::path::{Path, PathBuf};
use std::str::FromStr;

use chrono::NaiveDate;
use kaname_core::{
    Direction, ImportAccountTarget, ImportRequest, NewImportTransaction, StatementSource, Store,
};
use rust_decimal::Decimal;

const KEY: &str = "2f1c8a9e4b7d6035112233445566778899aabbccddeeff00112233445566aabb";

/// The variable the re-executed child looks for. Absent, `dedup_probe_child` returns at once.
const PROBE_ENV: &str = "KANAME_DEDUP_PROBE";

struct TempDb {
    dir: PathBuf,
    path: String,
}

impl TempDb {
    fn new(tag: &str) -> Self {
        let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("target")
            .join("test-dbs")
            .join(format!(
                "dedup-determinism-{}-{}-{:?}",
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

fn date(y: i32, m: u32, d: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(y, m, d).unwrap()
}

/// The row both accounts carry. Same date, same amount, same direction, same narration — the
/// canonical layer's exact target.
fn shared_row() -> NewImportTransaction {
    NewImportTransaction {
        date: date(2025, 3, 4),
        description_raw: "COFFEE SHOP".to_string(),
        amount: decimal("250.00"),
        direction: Direction::Debit,
        currency: "INR".to_string(),
        source_category: None,
    }
}

/// A row unique to one account, so neither account is empty once the shared row is linked.
fn unique_row(description: &str, amount: &str) -> NewImportTransaction {
    NewImportTransaction {
        date: date(2025, 3, 4),
        description_raw: description.to_string(),
        amount: decimal(amount),
        direction: Direction::Debit,
        currency: "INR".to_string(),
        source_category: None,
    }
}

fn import(store: &Store, name: &str, is_credit_card: bool, rows: Vec<NewImportTransaction>) {
    store
        .import_statement(ImportRequest {
            account: ImportAccountTarget::New {
                name: name.to_string(),
                bank_code: "EXAMPLE".to_string(),
                is_credit_card,
                last4: None,
                currency: "INR".to_string(),
            },
            bank_code: "EXAMPLE".to_string(),
            period_start: Some(date(2025, 3, 1)),
            period_end: date(2025, 3, 31),
            needs_review: false,
            source: StatementSource::Statement,
            transactions: rows,
            now: "2025-04-01T10:00:00Z".to_string(),
        })
        .expect("import");
}

/// Import two accounts of the given kinds, each carrying the shared row plus one of its own,
/// and report which account names survived and which were superseded.
fn run_probe(
    db_path: &str,
    first_is_card: bool,
    second_is_card: bool,
) -> (Vec<String>, Vec<String>) {
    let store = Store::open(db_path.to_string(), KEY.to_string()).expect("open");
    import(
        &store,
        "First",
        first_is_card,
        vec![shared_row(), unique_row("FIRST ONLY", "11.00")],
    );
    import(
        &store,
        "Second",
        second_is_card,
        vec![shared_row(), unique_row("SECOND ONLY", "12.00")],
    );

    let mut survived = Vec::new();
    let mut superseded = Vec::new();
    for account in store.list_accounts().expect("accounts") {
        for txn in store
            .list_transactions(account.id.clone())
            .expect("transactions")
            .into_iter()
            .filter(|t| t.description_raw == "COFFEE SHOP")
        {
            if txn.superseded_by.is_some() {
                superseded.push(account.name.clone());
            } else {
                survived.push(account.name.clone());
            }
        }
    }
    (survived, superseded)
}

/// Which account lost its shared row, when the two accounts are a bank ledger and a card.
fn supersession_loser(db_path: &Path) -> String {
    let (_, superseded) = run_probe(&db_path.to_string_lossy(), false, true);
    assert_eq!(
        superseded.len(),
        1,
        "a ledger and a card must collapse the shared row to exactly one survivor"
    );
    superseded[0].clone()
}

#[test]
fn the_same_import_supersedes_the_same_row_on_every_fresh_database() {
    let mut losers = Vec::new();
    for run in 0..10 {
        let db = TempDb::new(&format!("repeat-{run}"));
        losers.push(supersession_loser(Path::new(&db.path)));
    }

    let first = &losers[0];
    assert!(
        losers.iter().all(|loser| loser == first),
        "the same import superseded different accounts across fresh databases: {losers:?}"
    );
}

/// Ten runs inside one process share an address space and an allocator. The shipped defect was
/// driven by `randomblob(16)`, which is seeded per connection — so the guarantee that actually
/// matters is that a *separate process* agrees. A single-process assertion would have passed
/// against the defect on any run where luck held.
#[test]
fn the_supersession_winner_is_the_same_in_a_re_executed_process() {
    if std::env::var(PROBE_ENV).is_ok() {
        return;
    }

    let db = TempDb::new("parent");
    let ours = supersession_loser(Path::new(&db.path));

    let output = std::process::Command::new(std::env::current_exe().expect("test binary"))
        .args(["--exact", "dedup_probe_child", "--nocapture", "--ignored"])
        .env(PROBE_ENV, "1")
        .output()
        .expect("re-exec the test binary");
    assert!(
        output.status.success(),
        "child probe failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );

    let theirs = String::from_utf8_lossy(&output.stdout)
        .lines()
        .find_map(|line| line.strip_prefix("PROBE LOSER: "))
        .expect("child printed no verdict")
        .trim()
        .to_string();

    assert_eq!(
        ours, theirs,
        "two processes disagreed about which account loses its row"
    );
}

/// The child half of the cross-process proof. Ignored so a normal run never executes it; the
/// parent invokes it by name with `--ignored`.
#[test]
#[ignore = "invoked by the parent test via re-exec; not a standalone assertion"]
fn dedup_probe_child() {
    if std::env::var(PROBE_ENV).is_err() {
        return;
    }
    let db = TempDb::new("child");
    println!("PROBE LOSER: {}", supersession_loser(Path::new(&db.path)));
}

/// US1 AS-6, as the spec words it: "neither is mistaken for, merged with, or hidden by the
/// other". Two cards printing the same coffee on the same day are two real purchases.
#[test]
fn two_credit_cards_each_keep_their_own_identical_row() {
    let db = TempDb::new("two-cards");
    let (survived, superseded) = run_probe(&db.path, true, true);

    assert_eq!(
        superseded,
        Vec::<String>::new(),
        "a card's row was hidden by another card's identical row"
    );
    assert_eq!(survived.len(), 2, "both cards must keep their own row");
}

/// Two bank ledgers are the same case seen from the other side.
#[test]
fn two_bank_accounts_each_keep_their_own_identical_row() {
    let db = TempDb::new("two-banks");
    let (survived, superseded) = run_probe(&db.path, false, false);

    assert_eq!(
        superseded,
        Vec::<String>::new(),
        "a ledger's row was hidden by another ledger's identical row"
    );
    assert_eq!(survived.len(), 2, "both ledgers must keep their own row");
}

/// The fence around the narrowing: slice 013 exists so that a purchase appearing on both a bank
/// ledger and a card statement is counted once. Narrowing the guard must not delete that.
#[test]
fn a_bank_ledger_and_a_card_still_collapse_the_same_purchase() {
    let db = TempDb::new("ledger-and-card");
    let (survived, superseded) = run_probe(&db.path, false, true);

    assert_eq!(
        superseded.len(),
        1,
        "the same purchase on a ledger and a card must still collapse to one row"
    );
    assert_eq!(survived.len(), 1);
}

/// One account ordering in the app, asserted rather than assumed: the row that survives belongs
/// to whichever account `list_accounts()` yields first — the order the front door shows.
#[test]
fn the_surviving_row_is_on_the_account_list_accounts_returns_first() {
    let db = TempDb::new("survivor-is-first");
    let store = Store::open(db.path.clone(), KEY.to_string()).expect("open");
    import(
        &store,
        "First",
        false,
        vec![shared_row(), unique_row("FIRST ONLY", "11.00")],
    );
    import(
        &store,
        "Second",
        true,
        vec![shared_row(), unique_row("SECOND ONLY", "12.00")],
    );

    let accounts = store.list_accounts().expect("accounts");
    let first = accounts.first().expect("at least one account").clone();
    let survivor = store
        .list_transactions(first.id.clone())
        .expect("transactions")
        .into_iter()
        .find(|t| t.description_raw == "COFFEE SHOP")
        .expect("the first account still has the shared row");

    assert!(
        survivor.superseded_by.is_none(),
        "the account shown first lost its row to one shown later"
    );
}
