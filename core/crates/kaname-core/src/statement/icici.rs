//! ICICI credit-card statement reader, ported from the web engine's `icici.py`.
//!
//! Layout (SPENDS OVERVIEW): `DD/MM/YYYY<serial> <details> [<reward pts>] <amount>
//! [CR]` — debits carry no marker, credits a trailing "CR". Issuer marker
//! "ICICI Bank"; the statement (closing) date reads like "May 28, 2026".

use std::sync::LazyLock;

use regex::{Captures, Regex};

use crate::model::Direction;
use crate::statement::base::ParsedStatement;
use crate::statement::common::{find_last4, parse_date};
use crate::statement::line_reader::LineReaderConfig;
use crate::statement::polarity::classify;

pub const BANK_CODE: &str = "ICICI";

// Date may be immediately followed by glued serial digits (`\d*`); a space-separated
// serial stays in `desc`; an optional reward-points integer precedes the amount; an
// optional "CR" marks credits.
static ROW_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^(?P<date>\d{2}/\d{2}/\d{4})\d*\s+(?P<desc>.+?)(?:\s+\d+)?\s+(?P<amount>[\d,]+\.\d{2})(?:\s+(?P<dir>CR))?$",
    )
    .unwrap()
});

// ICICI prints the statement (closing) date, e.g. "May 28, 2026".
static STMT_DATE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\b([A-Z][a-z]{2,8} \d{1,2}, \d{4})\b").unwrap());

const CLAIM_MARKERS: &[&str] = &["ICICI Bank"];

/// The ICICI credit-card reader (zero-sized; all state is in the statics above).
pub struct IciciReader;

impl LineReaderConfig for IciciReader {
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
            // Attribute coverage to the printed statement (closing) date.
            statement.period_end = parse_date(&caps[1]);
        }
        statement.card_last4 = find_last4(full_text, None);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::statement::line_reader::read_lines;

    fn icici_full_text() -> String {
        "ICICI Bank Statement\nStatement Date May 28, 2026\n4315XXXXXXXX1002".to_string()
    }

    #[test]
    fn enriches_period_end_and_card_last4() {
        let statement = read_lines(&IciciReader, &[], &icici_full_text());
        assert_eq!(
            statement.period_end,
            chrono::NaiveDate::from_ymd_opt(2026, 5, 28)
        );
        assert_eq!(statement.card_last4.as_deref(), Some("1002"));
    }

    #[test]
    fn missing_metadata_stays_unset() {
        let statement = read_lines(&IciciReader, &[], "ICICI Bank Statement");
        assert!(statement.period_end.is_none());
        assert!(statement.card_last4.is_none());
    }
}
