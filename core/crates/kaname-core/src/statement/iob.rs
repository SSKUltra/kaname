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
//! The web reader's `ACCOUNT SUMMARY` block prints per-statement credit/debit totals;
//! enrichment surfaces them (the 2nd figure = credits, the 3rd = debits) for the reconcile
//! check, alongside the statement-date cycle end and card last-4.

use std::sync::LazyLock;

use regex::{Captures, Regex};

use crate::model::Direction;
use crate::statement::base::ParsedStatement;
use crate::statement::common::{find_last4, parse_amount, parse_date};
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

// ACCOUNT SUMMARY values row: Previous | Payment/Credits | Purchases/Debits | Fees… | Total. The
// five figures land on one extracted line; the 2nd is the printed credits total and the 3rd the
// printed debits total (both two-decimal). Case-insensitive + dotall to span the label rows.
static SUMMARY_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?is)ACCOUNT SUMMARY\b.*?(?P<prev>[\d,]+(?:\.\d+)?)\s+(?P<credits>[\d,]+\.\d{2})\s+(?P<debits>[\d,]+\.\d{2})\s+(?P<fees>[\d,]+(?:\.\d+)?)\s+(?P<total>[\d,]+(?:\.\d+)?)",
    )
    .unwrap()
});

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
        if let Some(caps) = SUMMARY_RE.captures(full_text) {
            statement.printed_total_credits = parse_amount(&caps["credits"]);
            statement.printed_total_debits = parse_amount(&caps["debits"]);
        }
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
    fn surfaces_account_summary_printed_totals() {
        // The ACCOUNT SUMMARY values row prints Previous | Credits | Debits | Fees | Total; the
        // 2nd figure (1,000.00) is the credits total and the 3rd (3,500.00) the debits total.
        let lines = vec![
            "31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr".to_string(),
            "04-APR-2026 ExampleStorePurchase 3,500.00 Dr".to_string(),
        ];
        let full_text = "ACCOUNT SUMMARY\nPrevious Balance Payment / Credits Purchases / Debits Fee, Taxes and Interest Charge Total Outstanding\n- + + =\n345.50 1,000.00 3,500.00 0 2,845.50".to_string();
        let st = read_lines(&IobReader, &lines, &full_text);
        assert_eq!(st.printed_total_credits, Some(dec!(1000.00)));
        assert_eq!(st.printed_total_debits, Some(dec!(3500.00)));
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
