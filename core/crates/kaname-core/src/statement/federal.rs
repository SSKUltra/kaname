//! Scapia / Federal Bank credit-card statement reader, ported from the web engine's
//! `federal_scapia.py`.
//!
//! Layout: `DD-MM-YYYY·HH:MM <description> [+]₹<amount>` — the separator between the
//! date and time renders as a middle dot (U+00B7) and the amount is prefixed by the
//! Rupee sign (U+20B9). A leading `+` is Scapia's own credit marker (not an arithmetic
//! sign on the amount); otherwise the transaction-type language decides. Issuer marker
//! "Scapia"; the billing cycle reads like "20Apr2026-19May2026" and the card is fully
//! masked (e.g. `XXXXXXXXXXXX4836`).

use std::sync::LazyLock;

use regex::{Captures, Regex};

use crate::model::Direction;
use crate::statement::base::ParsedStatement;
use crate::statement::common::{find_last4, parse_date};
use crate::statement::line_reader::LineReaderConfig;
use crate::statement::polarity::classify;

pub const BANK_CODE: &str = "FEDERAL";

// "29-04-2026·16:18 Billpayment Payment +₹324.45". The unescaped "." matches the
// date/time separator encoding-robustly (it renders as a middle dot, U+00B7); the ₹
// (U+20B9) literal precedes the amount and is not part of the amount group.
static ROW_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^(?P<date>\d{2}-\d{2}-\d{4}).\d{2}:\d{2}\s+(?P<desc>.+?)\s+(?P<sign>\+)?₹(?P<amount>[\d,]+\.\d{2})$",
    )
    .unwrap()
});

// "XXXXXXXXXXXX4836 20Apr2026-19May2026".
static CYCLE_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(\d{1,2}[A-Za-z]{3}\d{4})\s*-\s*(\d{1,2}[A-Za-z]{3}\d{4})").unwrap()
});

const CLAIM_MARKERS: &[&str] = &["Scapia", "Federal Bank"];

/// The Scapia / Federal Bank reader (zero-sized; all state is in the statics above).
pub struct FederalReader;

impl LineReaderConfig for FederalReader {
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
        if caps.name("sign").is_some() {
            Direction::Credit
        } else {
            classify(description, None, None)
        }
    }

    fn enrich(&self, statement: &mut ParsedStatement, full_text: &str) {
        if let Some(caps) = CYCLE_RE.captures(full_text) {
            statement.period_start = parse_date(&caps[1]);
            statement.period_end = parse_date(&caps[2]);
        }
        statement.card_last4 = find_last4(full_text, None);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::statement::line_reader::read_lines;
    use rust_decimal_macros::dec;

    fn sample() -> (Vec<String>, String) {
        let lines = vec![
            "29-04-2026·16:18 Billpayment Payment +₹324.45".to_string(),
            "24-04-2026·06:03 ExampleMerchantTokyo ₹2,353.13".to_string(),
        ];
        let full_text = format!(
            "Scapia by Federal Bank\nXXXXXXXXXXXX4836 20Apr2026-19May2026\n{}\n{}",
            lines[0], lines[1]
        );
        (lines, full_text)
    }

    #[test]
    fn parses_rows_direction_cycle_and_last4() {
        let (lines, full_text) = sample();
        let st = read_lines(&FederalReader, &lines, &full_text);
        assert_eq!(st.lines.len(), 2);
        assert_eq!(st.lines[0].direction, Direction::Credit); // leading '+'
        assert_eq!(st.lines[0].amount, dec!(324.45));
        assert_eq!(st.lines[0].description_raw, "Billpayment Payment");
        assert_eq!(st.lines[1].direction, Direction::Debit); // no '+', ordinary spend
        assert_eq!(st.lines[1].amount, dec!(2353.13));
        assert_eq!(st.lines[1].description_raw, "ExampleMerchantTokyo");
        assert_eq!(
            st.period_start,
            chrono::NaiveDate::from_ymd_opt(2026, 4, 20)
        );
        assert_eq!(st.period_end, chrono::NaiveDate::from_ymd_opt(2026, 5, 19));
        assert_eq!(st.card_last4.as_deref(), Some("4836"));
    }

    #[test]
    fn credit_without_plus_falls_back_to_transaction_type() {
        // No leading '+', but the description carries credit language → Credit via the
        // shared classifier, never from the amount's magnitude.
        let lines = vec!["10-04-2026·11:00 Refund reversal received ₹500.00".to_string()];
        let st = read_lines(&FederalReader, &lines, "Scapia by Federal Bank");
        assert_eq!(st.lines.len(), 1);
        assert_eq!(st.lines[0].direction, Direction::Credit);
    }

    #[test]
    fn claims_gates_by_issuer() {
        let (_, full_text) = sample();
        assert!(crate::statement::line_reader::claims(
            &FederalReader,
            &full_text,
            BANK_CODE
        ));
        assert!(!crate::statement::line_reader::claims(
            &FederalReader,
            "ICICI Bank Statement",
            BANK_CODE
        ));
    }
}
