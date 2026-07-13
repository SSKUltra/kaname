//! Golden-fixture parity harness — pins the on-device engine byte-for-byte to the
//! proven web engine (Constitution Principle V). This is the reusable mechanism every
//! future reader inherits: add a fixture JSON + one case-table row.
//!
//! Amounts and dates are stored in the fixture as strings and re-parsed via
//! `Decimal::from_str` / `NaiveDate::parse_from_str`, so no `f64` ever touches money
//! and comparison is exact.

use std::str::FromStr;

use chrono::NaiveDate;
use kaname_core::{icici_claims, read_icici_statement, Direction, ParsedStatement};
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
    period_end: Option<String>,
    card_last4: Option<String>,
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
}

/// A reader registered with the parity harness. Adding a future reader is one row.
struct Case {
    label: &'static str,
    parse: fn(Vec<String>, String) -> ParsedStatement,
    rel_path: &'static str,
}

const CASES: &[Case] = &[Case {
    label: "ICICI",
    parse: read_icici_statement,
    rel_path: "icici/credit_card/basic.json",
}];

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
    }
    let want_period_end = expected
        .period_end
        .as_deref()
        .map(|s| NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap());
    assert_eq!(statement.period_end, want_period_end, "{label}: period_end");
    assert_eq!(
        statement.card_last4, expected.card_last4,
        "{label}: card_last4"
    );
    assert_eq!(
        statement.errored_lines, expected.errored_lines,
        "{label}: errored_lines"
    );
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
