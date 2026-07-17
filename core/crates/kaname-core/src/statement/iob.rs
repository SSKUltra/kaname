//! Indian Overseas Bank (IOB) credit-card statement reader, ported from the web engine's
//! `iob.py`.
//!
//! Layout: one transaction per line as `DD-MON-YYYY <merchant> <amount> Dr|Cr` (e.g.
//! `31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr`). Direction is read from the trailing
//! `Dr`/`Cr` marker, never from the amount. Anchoring on a leading `DD-MON-YYYY` date and
//! a trailing `Dr`/`Cr` naturally skips the header, `ACCOUNT SUMMARY`, and total lines.
//! Issuer markers "INDIAN OVERSEAS BANK" / "iobnet.co.in"; the statement date reads
//! "Stmt Date: 20-APR-2026" and gives the cycle end (no explicit period range is printed).
//!
//! The web reader also scrapes the `ACCOUNT SUMMARY` printed credit/debit totals for
//! reconciliation; those `printed_total_*` fields are out of scope for this slice and are
//! intentionally not ported — enrichment here is the statement-date cycle end + card
//! last-4 only (the same carve-out already applied to the Yes reader).

use std::sync::LazyLock;

use regex::{Captures, Regex};

use crate::model::Direction;
use crate::statement::base::ParsedStatement;
use crate::statement::common::{find_last4, parse_date};
use crate::statement::line_reader::LineReaderConfig;
use crate::statement::polarity::classify;

pub const BANK_CODE: &str = "IOB";

static ROW_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^(?P<date>\d{2}-[A-Za-z]{3}-\d{4})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>Dr|Cr)$")
        .unwrap()
});

// "Stmt Date: 20-APR-2026" — the statement covers the cycle ending on this date (no
// explicit period range is printed).
static STMT_DATE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)Stmt Date\s*:\s*(\d{2}-[A-Za-z]{3}-\d{4})").unwrap());

const CLAIM_MARKERS: &[&str] = &["INDIAN OVERSEAS BANK", "iobnet.co.in"];

/// The IOB reader (zero-sized; all state is in the statics above).
pub struct IobReader;

impl LineReaderConfig for IobReader {
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
        if let Some(caps) = STMT_DATE_RE.captures(full_text) {
            statement.period_end = parse_date(&caps[1]);
        }
        statement.card_last4 = find_last4(full_text, Some("Credit Card Number"));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::statement::line_reader::read_lines;
    use rust_decimal_macros::dec;

    fn sample() -> (Vec<String>, String) {
        let lines = vec![
            "31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr".to_string(),
            "04-APR-2026 ExampleStorePurchase 3,500.00 Dr".to_string(),
        ];
        let full_text = format!(
            "INDIAN OVERSEAS BANK CREDIT CARD DIVISION\nStmt Date: 20-APR-2026 E-Mail: creditcard@iobnet.co.in\nCredit Card Number Cash Limit (as part of credit limit) Available Credit Limit\n123456XXXXXX0042 16000 25091.5\nACCOUNT SUMMARY\n{}\n{}\nTotal Purchase : 2845.50",
            lines[0], lines[1]
        );
        (lines, full_text)
    }

    #[test]
    fn parses_rows_direction_from_marker_and_statement_date() {
        let (lines, full_text) = sample();
        let st = read_lines(&IobReader, &lines, &full_text);
        assert_eq!(st.lines.len(), 2);
        assert_eq!(st.lines[0].direction, Direction::Credit); // Cr
        assert_eq!(st.lines[0].amount, dec!(1000.00));
        assert_eq!(st.lines[0].description_raw, "ExampleRefundMerchant");
        assert_eq!(st.lines[1].direction, Direction::Debit); // Dr
        assert_eq!(st.lines[1].amount, dec!(3500.00));
        assert_eq!(st.period_start, None);
        assert_eq!(st.period_end, chrono::NaiveDate::from_ymd_opt(2026, 4, 20));
    }

    #[test]
    fn inline_masked_pan_last4_ignores_adjacent_limit_figures() {
        // "123456XXXXXX0042 16000 25091.5" — last-4 is the card's, not the limits'.
        let (lines, full_text) = sample();
        let st = read_lines(&IobReader, &lines, &full_text);
        assert_eq!(st.card_last4.as_deref(), Some("0042"));
    }

    #[test]
    fn claims_gates_by_issuer() {
        let (_, full_text) = sample();
        assert!(crate::statement::line_reader::claims(
            &IobReader, &full_text, BANK_CODE
        ));
        assert!(!crate::statement::line_reader::claims(
            &IobReader,
            "HDFC Bank Credit Cards statement",
            BANK_CODE
        ));
    }
}
