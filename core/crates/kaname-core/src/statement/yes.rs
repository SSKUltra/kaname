//! Yes Bank / Kiwi credit-card statement reader, ported from the web engine's
//! `yes_kiwi.py`.
//!
//! Layout: `DD/MM/YYYY <details ... Ref No> <Merchant Category> <amount> Dr|Cr` — a
//! two-letter Dr/Cr marker at the end of the line, a day-first `%d/%m/%Y` date. Issuer
//! marker "YES BANK"; the billing period reads "Statement Period: <from> To <to>".
//!
//! Enrichment also surfaces the printed per-statement debit total ("Current Purchases … Dr")
//! and credit total ("Payment & Credits Received … Cr") for the reconcile check, alongside the
//! billing period and card last-4.

use std::sync::LazyLock;

use regex::{Captures, Regex};

use crate::model::Direction;
use crate::statement::base::ParsedStatement;
use crate::statement::common::{find_last4, parse_amount, parse_date};
use crate::statement::line_reader::LineReaderConfig;
use crate::statement::polarity::classify;

pub const BANK_CODE: &str = "YES";

static ROW_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^(?P<date>\d{2}/\d{2}/\d{4})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>Dr|Cr)$")
        .unwrap()
});

// "Statement Period: 17/04/2026 To 16/05/2026".
static PERIOD_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)(\d{2}/\d{2}/\d{4})\s+To\s+(\d{2}/\d{2}/\d{4})").unwrap());

// Printed per-statement totals for reconciliation, matched only when the label and value land
// on the same extracted line (otherwise left None → the statement reconciles as neutral).
static DEBITS_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)Purchases[^\n]*?Rs\.?\s*([\d,]+\.\d{2})\s*Dr").unwrap());
static CREDITS_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)Payment\s*&?\s*Credits Received[^\n]*?Rs\.?\s*([\d,]+\.\d{2})\s*Cr").unwrap()
});

const CLAIM_MARKERS: &[&str] = &["YES BANK"];

/// The Yes Bank reader (zero-sized; all state is in the statics above).
pub struct YesReader;

impl LineReaderConfig for YesReader {
    fn bank_code(&self) -> &'static str {
        BANK_CODE
    }

    fn claim_markers(&self) -> &'static [&'static str] {
        CLAIM_MARKERS
    }

    fn row_re(&self) -> &'static Regex {
        &ROW_RE
    }

    fn direction(&self, caps: &Captures<'_>, description: &str) -> Direction {
        classify(description, caps.name("dir").map(|m| m.as_str()), None)
    }

    fn enrich(&self, statement: &mut ParsedStatement, full_text: &str) {
        if let Some(caps) = PERIOD_RE.captures(full_text) {
            statement.period_start = parse_date(&caps[1]);
            statement.period_end = parse_date(&caps[2]);
        }
        statement.card_last4 = find_last4(full_text, Some("Card Number"));
        statement.printed_total_debits = DEBITS_RE
            .captures(full_text)
            .and_then(|c| parse_amount(&c[1]));
        statement.printed_total_credits = CREDITS_RE
            .captures(full_text)
            .and_then(|c| parse_amount(&c[1]));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::statement::line_reader::read_lines;
    use rust_decimal_macros::dec;

    fn sample() -> (Vec<String>, String) {
        let lines = vec![
            "29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr".to_string(),
            "19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr"
                .to_string(),
        ];
        let full_text = format!(
            "YES BANK KLICK\nStatement for YES BANK Card Number 3561XXXXXXXX6686\nStatement Period: 17/04/2026 To 16/05/2026\nCurrent Purchases / Cash Advance & Other Charges : Rs. 100.00 Dr\nPayment & Credits Received : Rs. 9,000.00 Cr\n{}\n{}",
            lines[0], lines[1]
        );
        (lines, full_text)
    }

    #[test]
    fn parses_rows_direction_period_and_last4() {
        let (lines, full_text) = sample();
        let st = read_lines(&YesReader, &lines, &full_text);
        assert_eq!(st.lines.len(), 2);
        assert_eq!(st.lines[0].direction, Direction::Credit); // Cr
        assert_eq!(st.lines[0].amount, dec!(9000.00));
        assert_eq!(
            st.lines[0].description_raw,
            "PAYMENT RECEIVED BBPS - Ref No: RT0001"
        );
        assert_eq!(st.lines[1].direction, Direction::Debit); // Dr
        assert_eq!(
            st.period_start,
            chrono::NaiveDate::from_ymd_opt(2026, 4, 17)
        );
        assert_eq!(st.period_end, chrono::NaiveDate::from_ymd_opt(2026, 5, 16));
        assert_eq!(st.card_last4.as_deref(), Some("6686"));
    }

    #[test]
    fn surfaces_printed_totals_for_reconciliation() {
        let (lines, full_text) = sample();
        let st = read_lines(&YesReader, &lines, &full_text);
        assert_eq!(st.printed_total_debits, Some(dec!(100.00)));
        assert_eq!(st.printed_total_credits, Some(dec!(9000.00)));
    }
}
