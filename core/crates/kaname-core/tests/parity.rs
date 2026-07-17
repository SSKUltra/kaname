//! Golden-fixture parity harness — pins the on-device engine byte-for-byte to the
//! proven web engine (Constitution Principle V). This is the reusable mechanism every
//! future reader inherits: add a fixture JSON + one case-table row.
//!
//! Amounts and dates are stored in the fixture as strings and re-parsed via
//! `Decimal::from_str` / `NaiveDate::parse_from_str`, so no `f64` ever touches money
//! and comparison is exact.

use std::str::FromStr;

use chrono::NaiveDate;
use kaname_core::{
    check_balance_chain, federal_claims, hdfc_claims, icici_claims, iob_claims,
    read_au_bank_statement, read_federal_bank_statement, read_federal_statement,
    read_hdfc_bank_statement, read_hdfc_statement, read_icici_bank_statement, read_icici_statement,
    read_iob_statement, read_sbi_statement, read_yes_statement, sbi_claims, yes_claims,
    ChainStatus, Direction, ParsedStatement,
};
use rust_decimal::Decimal;
use serde::Deserialize;

#[derive(Deserialize)]
struct Fixture {
    lines: Vec<String>,
    full_text: String,
    expected: Expected,
}

#[derive(Deserialize)]
struct Expected {
    rows: Vec<ExpectedRow>,
    // Optional so pre-`period_start` fixtures (e.g. ICICI) deserialize unchanged as None.
    #[serde(default)]
    period_start: Option<String>,
    period_end: Option<String>,
    card_last4: Option<String>,
    // Bank-account (ledger) statements only; credit-card fixtures omit these → None.
    #[serde(default)]
    printed_opening_balance: Option<String>,
    #[serde(default)]
    printed_closing_balance: Option<String>,
    #[serde(default)]
    errored_lines: Vec<String>,
}

#[derive(Deserialize)]
struct ExpectedRow {
    date: String,
    amount: String,
    direction: Direction,
    currency: String,
    description_raw: String,
    // Present only for bank-account (ledger) rows; credit-card rows omit it → None.
    #[serde(default)]
    ledger: Option<ExpectedLedger>,
}

#[derive(Deserialize)]
struct ExpectedLedger {
    balance: String,
    #[serde(default)]
    balance_delta: Option<String>,
    amount_matches_delta: bool,
    is_suspect: bool,
    direction_source: String,
    serial: String,
}

/// A reader registered with the parity harness. Adding a future reader is one row.
struct Case {
    label: &'static str,
    parse: fn(Vec<String>, String) -> ParsedStatement,
    rel_path: &'static str,
}

const CASES: &[Case] = &[
    Case {
        label: "ICICI",
        parse: read_icici_statement,
        rel_path: "icici/credit_card/basic.json",
    },
    Case {
        label: "HDFC year-end",
        parse: read_hdfc_statement,
        rel_path: "hdfc/credit_card/year_end.json",
    },
    Case {
        label: "HDFC monthly",
        parse: read_hdfc_statement,
        rel_path: "hdfc/credit_card/monthly.json",
    },
    Case {
        label: "SBI Card",
        parse: read_sbi_statement,
        rel_path: "sbi_card/credit_card/basic.json",
    },
    Case {
        label: "Yes Bank",
        parse: read_yes_statement,
        rel_path: "yes/credit_card/basic.json",
    },
    Case {
        label: "IOB",
        parse: read_iob_statement,
        rel_path: "iob/credit_card/basic.json",
    },
    Case {
        label: "Federal/Scapia",
        parse: read_federal_statement,
        rel_path: "federal/credit_card/basic.json",
    },
    Case {
        label: "ICICI bank",
        parse: parse_icici_bank,
        rel_path: "icici/bank_account/basic.json",
    },
    Case {
        label: "HDFC bank compact",
        parse: parse_hdfc_bank,
        rel_path: "hdfc/bank_account/compact.json",
    },
    Case {
        label: "HDFC bank detailed",
        parse: parse_hdfc_bank,
        rel_path: "hdfc/bank_account/detailed.json",
    },
    Case {
        label: "Federal bank classic",
        parse: parse_federal_bank,
        rel_path: "federal/bank_account/classic.json",
    },
    Case {
        label: "Federal bank fi",
        parse: parse_federal_bank,
        rel_path: "federal/bank_account/fi.json",
    },
    Case {
        label: "AU bank",
        parse: parse_au_bank,
        rel_path: "au/bank_account/savings.json",
    },
];

/// Wrapper so the bank-account ledger reader fits the shared `Case` signature. The
/// reference fixture is opening-balance-anchored, so no first-row word geometry is
/// needed (the native platform supplies it in production).
fn parse_icici_bank(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_icici_bank_statement(lines, full_text, Vec::new())
}

/// Wrapper for the HDFC bank-account reader (both layouts are opening-anchored → no
/// geometry needed).
fn parse_hdfc_bank(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_hdfc_bank_statement(lines, full_text, Vec::new())
}

/// Wrapper for the Federal bank-account reader (both templates are opening-anchored → no
/// geometry needed).
fn parse_federal_bank(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_federal_bank_statement(lines, full_text, Vec::new())
}

/// Wrapper for the AU bank-account reader (opening-anchored → no geometry needed).
fn parse_au_bank(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_au_bank_statement(lines, full_text, Vec::new())
}

fn load_fixture(rel_path: &str) -> Fixture {
    let path = format!(
        "{}/../../../fixtures/{}",
        env!("CARGO_MANIFEST_DIR"),
        rel_path
    );
    let raw = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
    serde_json::from_str(&raw).unwrap_or_else(|e| panic!("parse {path}: {e}"))
}

fn assert_matches_expected(label: &str, statement: &ParsedStatement, expected: &Expected) {
    assert_eq!(
        statement.lines.len(),
        expected.rows.len(),
        "{label}: row count (errored: {:?})",
        statement.errored_lines
    );
    for (i, (got, want)) in statement.lines.iter().zip(&expected.rows).enumerate() {
        let want_date = NaiveDate::parse_from_str(&want.date, "%Y-%m-%d").unwrap();
        let want_amount = Decimal::from_str(&want.amount).unwrap();
        assert_eq!(got.value_date, want_date, "{label} row {i}: date");
        assert_eq!(got.amount, want_amount, "{label} row {i}: amount");
        assert_eq!(got.direction, want.direction, "{label} row {i}: direction");
        assert_eq!(got.currency, want.currency, "{label} row {i}: currency");
        assert_eq!(
            got.description_raw, want.description_raw,
            "{label} row {i}: description_raw"
        );
        assert_ledger(label, i, got, want);
    }
    let parse_iso = |s: &str| NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap();
    let want_period_start = expected.period_start.as_deref().map(parse_iso);
    assert_eq!(
        statement.period_start, want_period_start,
        "{label}: period_start"
    );
    let want_period_end = expected.period_end.as_deref().map(parse_iso);
    assert_eq!(statement.period_end, want_period_end, "{label}: period_end");
    assert_eq!(
        statement.card_last4, expected.card_last4,
        "{label}: card_last4"
    );
    let parse_dec = |s: &str| Decimal::from_str(s).unwrap();
    assert_eq!(
        statement.printed_opening_balance,
        expected.printed_opening_balance.as_deref().map(parse_dec),
        "{label}: printed_opening_balance"
    );
    assert_eq!(
        statement.printed_closing_balance,
        expected.printed_closing_balance.as_deref().map(parse_dec),
        "{label}: printed_closing_balance"
    );
    assert_eq!(
        statement.errored_lines, expected.errored_lines,
        "{label}: errored_lines"
    );
}

/// Assert a row's bank-account ledger metadata when the fixture pins it (credit-card
/// fixtures omit it, so the row's `ledger` must then be `None`).
fn assert_ledger(label: &str, i: usize, got: &kaname_core::ParsedTransaction, want: &ExpectedRow) {
    match (&got.ledger, &want.ledger) {
        (None, None) => {}
        (Some(_), None) => panic!("{label} row {i}: unexpected ledger metadata on a CC row"),
        (None, Some(_)) => panic!("{label} row {i}: missing ledger metadata"),
        (Some(got_l), Some(want_l)) => {
            assert_eq!(
                got_l.balance,
                Decimal::from_str(&want_l.balance).unwrap(),
                "{label} row {i}: ledger.balance"
            );
            assert_eq!(
                got_l.balance_delta,
                want_l
                    .balance_delta
                    .as_deref()
                    .map(|s| Decimal::from_str(s).unwrap()),
                "{label} row {i}: ledger.balance_delta"
            );
            assert_eq!(
                got_l.amount_matches_delta, want_l.amount_matches_delta,
                "{label} row {i}: ledger.amount_matches_delta"
            );
            assert_eq!(
                got_l.is_suspect, want_l.is_suspect,
                "{label} row {i}: ledger.is_suspect"
            );
            assert_eq!(
                format!("{:?}", got_l.direction_source),
                want_l.direction_source,
                "{label} row {i}: ledger.direction_source"
            );
            assert_eq!(
                got_l.serial, want_l.serial,
                "{label} row {i}: ledger.serial"
            );
        }
    }
}

#[test]
fn golden_fixtures_match_expected_output() {
    for case in CASES {
        let fx = load_fixture(case.rel_path);
        let statement = (case.parse)(fx.lines.clone(), fx.full_text.clone());
        assert_matches_expected(case.label, &statement, &fx.expected);
    }
}

#[test]
fn parse_is_deterministic() {
    for case in CASES {
        let fx = load_fixture(case.rel_path);
        let first = (case.parse)(fx.lines.clone(), fx.full_text.clone());
        let second = (case.parse)(fx.lines.clone(), fx.full_text.clone());
        assert_eq!(first, second, "{}: parse must be deterministic", case.label);
    }
}

#[test]
fn icici_claims_accepts_own_document_and_rejects_others() {
    let fx = load_fixture("icici/credit_card/basic.json");
    assert!(
        icici_claims(fx.full_text),
        "ICICI must claim its own statement"
    );
    assert!(
        !icici_claims("HDFC Bank Credit Cards statement".to_string()),
        "ICICI must not claim an HDFC statement"
    );
}

#[test]
fn hdfc_claims_accepts_own_document_and_rejects_others() {
    let fx = load_fixture("hdfc/credit_card/year_end.json");
    assert!(
        hdfc_claims(fx.full_text),
        "HDFC must claim its own statement"
    );
    assert!(
        !hdfc_claims("ICICI Bank Statement".to_string()),
        "HDFC must not claim an ICICI statement"
    );
}

#[test]
fn sbi_claims_accepts_own_document_and_rejects_others() {
    let fx = load_fixture("sbi_card/credit_card/basic.json");
    assert!(sbi_claims(fx.full_text), "SBI must claim its own statement");
    assert!(
        !sbi_claims("ICICI Bank Statement".to_string()),
        "SBI must not claim an ICICI statement"
    );
}

#[test]
fn yes_claims_accepts_own_document_and_rejects_others() {
    let fx = load_fixture("yes/credit_card/basic.json");
    assert!(yes_claims(fx.full_text), "Yes must claim its own statement");
    assert!(
        !yes_claims("ICICI Bank Statement".to_string()),
        "Yes must not claim an ICICI statement"
    );
}

#[test]
fn iob_claims_accepts_own_document_and_rejects_others() {
    let fx = load_fixture("iob/credit_card/basic.json");
    assert!(iob_claims(fx.full_text), "IOB must claim its own statement");
    assert!(
        !iob_claims("HDFC Bank Credit Cards statement".to_string()),
        "IOB must not claim an HDFC statement"
    );
}

#[test]
fn federal_claims_accepts_own_document_and_rejects_others() {
    let fx = load_fixture("federal/credit_card/basic.json");
    assert!(
        federal_claims(fx.full_text),
        "Federal must claim its own statement"
    );
    assert!(
        !federal_claims("ICICI Bank Statement".to_string()),
        "Federal must not claim an ICICI statement"
    );
}

#[test]
fn icici_bank_statement_balance_chain_reconciles() {
    // The reference savings vector is opening-balance-anchored and every printed amount
    // equals its balance delta, so the independent balance-chain check reconciles.
    let fx = load_fixture("icici/bank_account/basic.json");
    let statement = read_icici_bank_statement(fx.lines, fx.full_text, Vec::new());
    let result = check_balance_chain(statement);
    assert_eq!(result.status, ChainStatus::Reconciled);
    assert_eq!(result.suspect_count, 0, "no suspect rows");
    assert!(
        !result.row1_direction_fallback,
        "row-1 was opening-anchored"
    );
    assert_eq!(result.checked_rows, 3);
}

#[test]
fn hdfc_bank_statements_balance_chain_reconciles() {
    for rel_path in [
        "hdfc/bank_account/compact.json",
        "hdfc/bank_account/detailed.json",
    ] {
        let fx = load_fixture(rel_path);
        let statement = read_hdfc_bank_statement(fx.lines, fx.full_text, Vec::new());
        let result = check_balance_chain(statement);
        assert_eq!(result.status, ChainStatus::Reconciled, "{rel_path}");
        assert_eq!(result.suspect_count, 0, "{rel_path}: no suspects");
        assert!(
            !result.row1_direction_fallback,
            "{rel_path}: opening-anchored"
        );
        assert_eq!(result.checked_rows, 2, "{rel_path}");
    }
}

#[test]
fn federal_bank_statements_balance_chain_reconciles() {
    for (rel_path, rows) in [
        ("federal/bank_account/classic.json", 3),
        ("federal/bank_account/fi.json", 2),
    ] {
        let fx = load_fixture(rel_path);
        let statement = read_federal_bank_statement(fx.lines, fx.full_text, Vec::new());
        let result = check_balance_chain(statement);
        assert_eq!(result.status, ChainStatus::Reconciled, "{rel_path}");
        assert_eq!(result.suspect_count, 0, "{rel_path}: no suspects");
        assert!(
            !result.row1_direction_fallback,
            "{rel_path}: opening-anchored"
        );
        assert_eq!(result.checked_rows, rows, "{rel_path}");
    }
}

#[test]
fn au_bank_statement_balance_chain_reconciles() {
    let fx = load_fixture("au/bank_account/savings.json");
    let statement = read_au_bank_statement(fx.lines, fx.full_text, Vec::new());
    let result = check_balance_chain(statement);
    assert_eq!(result.status, ChainStatus::Reconciled);
    assert_eq!(result.suspect_count, 0, "no suspect rows");
    assert!(
        !result.row1_direction_fallback,
        "row-1 was opening-anchored"
    );
    assert_eq!(result.checked_rows, 2);
}

#[test]
fn malformed_row_is_captured_not_fatal() {
    // A line matching the ICICI shape but with an unparseable date must land in
    // errored_lines while the valid row is still returned — never a panic.
    let lines = vec![
        "99/99/9999 4262 Bad date row 0 100.00".to_string(),
        "26/05/2026 1814 Fee on gaming transaction 0 10.20".to_string(),
    ];
    let statement = read_icici_statement(lines, "ICICI Bank".to_string());
    assert_eq!(statement.lines.len(), 1, "the one valid row is returned");
    assert_eq!(statement.errored_lines.len(), 1, "the bad row is captured");
    assert!(statement.errored_lines[0].starts_with("99/99/9999"));
}
