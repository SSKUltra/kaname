//! HDFC credit-card statement reader, ported from the web engine's `hdfc.py`.
//!
//! HDFC issues two credit-card layouts behind one composite reader:
//!   1. Year-end consolidated: `DD-Mon-YYYY <description> <amount> DR|CR` — the Dr/Cr
//!      marker sits mid-line, immediately after the amount (a trailing masked card
//!      number is ignored).
//!   2. Monthly co-brand: `DD/MM/YYYY| HH:MM <merchant> [+ ]C <amount>` — the Rupee
//!      glyph extracts as a leading "C" (not the amount); a leading "+" marks a credit.
//!
//! [`read_hdfc_statement`] tries the year-end layout first and falls back to the
//! monthly one, so a statement in either format parses without the caller knowing which.

use std::sync::LazyLock;

use chrono::Datelike;
use regex::{Captures, Regex};

use crate::model::Direction;
use crate::statement::base::ParsedStatement;
use crate::statement::common::{find_last4, month_year_end, parse_date};
use crate::statement::line_reader::{claims, read_lines_first_match, LineReaderConfig};
use crate::statement::polarity::classify;

pub const BANK_CODE: &str = "HDFC";

const CLAIM_MARKERS: &[&str] = &["HDFC Bank Credit Card", "HDFC Bank Credit Cards"];

// Layout 1 — year-end consolidated: "16-Apr-2025 <desc> 10,610.00 CR <card>". Not
// anchored at end: the trailing card number after the Dr/Cr marker is ignored.
static ROW_RE_YEAR_END: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^(?P<date>\d{2}-[A-Za-z]{3}-\d{4})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>DR|CR)\b",
    )
    .unwrap()
});

// Layout 2 — monthly co-brand: "15/05/2026| 13:30 <merchant> [+ ]C 1,639.00". The
// Rupee glyph extracts as a leading "C"; a leading "+" marks a payment/credit.
static ROW_RE_MONTHLY: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^(?P<date>\d{2}/\d{2}/\d{4})\s*\|?\s*\d{1,2}:\d{2}\s+(?P<desc>.+?)\s+(?P<dir>\+\s*)?C\s*(?P<amount>[\d,]+\.\d{2})\b",
    )
    .unwrap()
});

// "Account Summary for the period from APRIL-25 to MARCH-26" (year-end).
static PERIOD_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)period from\s+([A-Za-z]+-\d{2})\s+to\s+([A-Za-z]+-\d{2})").unwrap()
});

// "Billing Period 15 May, 2026 - 14 Jun, 2026" (monthly).
static MONTHLY_PERIOD_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)Billing Period\s+(\d{1,2}\s+[A-Za-z]{3,9},?\s+\d{4})\s*-\s*(\d{1,2}\s+[A-Za-z]{3,9},?\s+\d{4})",
    )
    .unwrap()
});

/// Statement-level enrichment shared by both HDFC layouts: the billing period (from the
/// year-end month-year range or the monthly date range) and the card last-4.
fn enrich(statement: &mut ParsedStatement, full_text: &str) {
    if let Some(caps) = PERIOD_RE.captures(full_text) {
        statement.period_end = month_year_end(&caps[2]);
        if let Some(start) = month_year_end(&caps[1]) {
            statement.period_start = start.with_day(1);
        }
    } else if let Some(caps) = MONTHLY_PERIOD_RE.captures(full_text) {
        statement.period_start = parse_date(&caps[1].replace(',', ""));
        statement.period_end = parse_date(&caps[2].replace(',', ""));
    }
    statement.card_last4 = find_last4(full_text, Some("Card Number"));
}

/// Year-end consolidated layout — direction from the explicit `DR`/`CR` marker.
struct HdfcYearEnd;

impl LineReaderConfig for HdfcYearEnd {
    fn bank_code(&self) -> &'static str {
        BANK_CODE
    }
    fn claim_markers(&self) -> &'static [&'static str] {
        CLAIM_MARKERS
    }
    fn row_re(&self) -> &'static Regex {
        &ROW_RE_YEAR_END
    }
    fn direction(&self, caps: &Captures<'_>, description: &str) -> Direction {
        classify(description, caps.name("dir").map(|m| m.as_str()), None)
    }
    fn enrich(&self, statement: &mut ParsedStatement, full_text: &str) {
        enrich(statement, full_text);
    }
}

/// Monthly co-brand layout — a leading `+` before the amount marks a credit; otherwise
/// the row is a spend (debit). The amount's value is never consulted.
struct HdfcMonthly;

impl LineReaderConfig for HdfcMonthly {
    fn bank_code(&self) -> &'static str {
        BANK_CODE
    }
    fn claim_markers(&self) -> &'static [&'static str] {
        CLAIM_MARKERS
    }
    fn row_re(&self) -> &'static Regex {
        &ROW_RE_MONTHLY
    }
    fn direction(&self, caps: &Captures<'_>, _description: &str) -> Direction {
        let is_credit = caps
            .name("dir")
            .is_some_and(|m| m.as_str().trim_start().starts_with('+'));
        if is_credit {
            Direction::Credit
        } else {
            Direction::Debit
        }
    }
    fn enrich(&self, statement: &mut ParsedStatement, full_text: &str) {
        enrich(statement, full_text);
    }
}

/// Parse an HDFC credit-card statement, auto-selecting the layout (year-end first,
/// monthly fallback).
pub fn read_hdfc_statement(lines: &[String], full_text: &str) -> ParsedStatement {
    let configs: [&dyn LineReaderConfig; 2] = [&HdfcYearEnd, &HdfcMonthly];
    read_lines_first_match(&configs, lines, full_text, BANK_CODE)
}

/// Whether `full_text` is recognizably an HDFC credit-card statement.
pub fn hdfc_claims(full_text: &str) -> bool {
    claims(&HdfcYearEnd, full_text, BANK_CODE)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    fn year_end() -> (Vec<String>, String) {
        let lines = vec![
            "16-Apr-2025 ONLINE TRF - PYMT RECD - THANK YOU 10,610.00 CR 526873XXXXXX9070"
                .to_string(),
            "04-Apr-2025 WWW EXAMPLE COM GURGAON 1,071.00 DR 526873XXXXXX9070".to_string(),
        ];
        let full_text = format!(
            "HDFC Bank Credit Cards\nAccount Summary for the period from APRIL-25 to MARCH-26\nCard Number XXXX6873XXXXXX9070\n{}\n{}",
            lines[0], lines[1]
        );
        (lines, full_text)
    }

    #[test]
    fn year_end_direction_from_marker_and_month_end_period() {
        let (lines, full_text) = year_end();
        let st = read_hdfc_statement(&lines, &full_text);
        assert_eq!(st.lines.len(), 2);
        assert_eq!(st.lines[0].direction, Direction::Credit); // CR
        assert_eq!(st.lines[0].amount, dec!(10610.00));
        assert_eq!(st.lines[1].direction, Direction::Debit); // DR
        assert_eq!(st.period_start, chrono::NaiveDate::from_ymd_opt(2025, 4, 1));
        assert_eq!(st.period_end, chrono::NaiveDate::from_ymd_opt(2026, 3, 31));
        assert_eq!(st.card_last4.as_deref(), Some("9070"));
    }

    #[test]
    fn monthly_layout_is_the_fallback_and_plus_marks_credit() {
        let lines = vec![
            "15/05/2026| 13:30 EXAMPLE MERCHANT BANGALORE C 1,639.00".to_string(),
            "20/05/2026| 09:05 CC PAYMENT RECEIVED + C 6,738.00".to_string(),
        ];
        let full_text = format!(
            "HDFC Bank Credit Card\nBilling Period 15 May, 2026 - 14 Jun, 2026\nCard Number XXXX1234XXXXXX5678\n{}\n{}",
            lines[0], lines[1]
        );
        let st = read_hdfc_statement(&lines, &full_text);
        assert_eq!(st.lines.len(), 2);
        assert_eq!(st.lines[0].direction, Direction::Debit); // no '+'
        assert_eq!(st.lines[0].description_raw, "EXAMPLE MERCHANT BANGALORE");
        assert_eq!(st.lines[1].direction, Direction::Credit); // leading '+'
        assert_eq!(st.lines[1].amount, dec!(6738.00));
        assert_eq!(
            st.period_start,
            chrono::NaiveDate::from_ymd_opt(2026, 5, 15)
        );
        assert_eq!(st.period_end, chrono::NaiveDate::from_ymd_opt(2026, 6, 14));
        assert_eq!(st.card_last4.as_deref(), Some("5678"));
    }

    #[test]
    fn claims_gates_by_issuer() {
        let (_, full_text) = year_end();
        assert!(hdfc_claims(&full_text));
        assert!(!hdfc_claims("ICICI Bank Statement"));
    }

    #[test]
    fn year_end_shaped_bad_row_is_captured_not_fatal() {
        // Matches the year-end shape but the date will not parse → errored_lines; the
        // valid row is still returned (the shared read_lines seam, reused unchanged).
        let lines = vec![
            "99-Zzz-2025 BROKEN DATE ROW 100.00 DR".to_string(),
            "04-Apr-2025 WWW EXAMPLE COM GURGAON 1,071.00 DR 526873XXXXXX9070".to_string(),
        ];
        let st = read_hdfc_statement(&lines, "HDFC Bank Credit Cards");
        assert_eq!(st.lines.len(), 1);
        assert_eq!(st.errored_lines.len(), 1);
    }

    #[test]
    fn neither_layout_yields_empty_without_error() {
        let lines = vec!["Some summary line that is not a transaction".to_string()];
        let st = read_hdfc_statement(&lines, "HDFC Bank Credit Cards");
        assert!(st.lines.is_empty());
        assert!(st.errored_lines.is_empty());
        assert_eq!(st.bank_code, BANK_CODE);
    }
}
