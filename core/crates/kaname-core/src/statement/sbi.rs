//! SBI Card credit-card statement reader, ported from the web engine's `sbi_card.py`.
//!
//! Layout: `DD Mon YY <details> <amount> C|D` (legend: C=Credit, D=Debit) — a
//! single-letter Dr/Cr marker at the end of the line, a day-first date with a 3-letter
//! month and 2-digit year (e.g. `21 Apr 26`). Issuer marker "SBI Card"; the billing
//! period reads "for Statement Period: <from> to <to>".

use std::sync::LazyLock;

use regex::{Captures, Regex};

use crate::model::Direction;
use crate::statement::base::ParsedStatement;
use crate::statement::common::{find_last4, parse_date};
use crate::statement::line_reader::LineReaderConfig;
use crate::statement::polarity::classify;

pub const BANK_CODE: &str = "SBI_CARD";

static ROW_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^(?P<date>\d{2} [A-Za-z]{3} \d{2})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>[CD])$")
        .unwrap()
});

// "for Statement Period: 22 Apr 26 to 21 May 26".
static PERIOD_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)Statement Period:\s*(\d{2} [A-Za-z]{3} \d{2})\s+to\s+(\d{2} [A-Za-z]{3} \d{2})",
    )
    .unwrap()
});

const CLAIM_MARKERS: &[&str] = &["SBI Card", "GSTIN of SBI Card"];

/// The SBI Card reader (zero-sized; all state is in the statics above).
pub struct SbiReader;

impl LineReaderConfig for SbiReader {
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
            "21 Apr 26 CARD CASHBACK CREDIT 643.00 C".to_string(),
            "20 May 26 APPLE INDIA STORE MUMBAI IN 82,900.00 D".to_string(),
        ];
        let full_text = format!(
            "GSTIN of SBI Card\nCredit Card Number XXXX XXXX XXXX XX61\nfor Statement Period: 22 Apr 26 to 21 May 26\n{}\n{}",
            lines[0], lines[1]
        );
        (lines, full_text)
    }

    #[test]
    fn parses_rows_direction_and_period() {
        let (lines, full_text) = sample();
        let st = read_lines(&SbiReader, &lines, &full_text);
        assert_eq!(st.lines.len(), 2);
        assert_eq!(st.lines[0].direction, Direction::Credit); // C
        assert_eq!(st.lines[0].amount, dec!(643.00));
        assert_eq!(st.lines[1].direction, Direction::Debit); // D
        assert_eq!(st.lines[1].description_raw, "APPLE INDIA STORE MUMBAI IN");
        assert_eq!(
            st.period_start,
            chrono::NaiveDate::from_ymd_opt(2026, 4, 22)
        );
        assert_eq!(st.period_end, chrono::NaiveDate::from_ymd_opt(2026, 5, 21));
    }

    #[test]
    fn last4_absent_when_mask_shows_too_few_digits() {
        // "XXXX XXXX XXXX XX61" exposes only two trailing digits → no last-4.
        let (lines, full_text) = sample();
        let st = read_lines(&SbiReader, &lines, &full_text);
        assert!(st.card_last4.is_none());
    }
}
