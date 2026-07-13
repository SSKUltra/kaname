//! The reusable "one transaction per text line" reader, ported from the web engine's
//! `_line_reader.py`. Most issuer statements list one transaction per text line as
//! `<date> <description> <amount> <Dr/Cr>`. A per-issuer [`LineReaderConfig`] supplies
//! the row regex, direction rule, and enrichment; every credit-card reader reuses this
//! seam.

use regex::{Captures, Regex};

use crate::model::Direction;
use crate::statement::base::{truncate_chars, ParsedStatement, ParsedTransaction, MAX_RAW};
use crate::statement::common::{parse_amount, parse_date};

/// Per-issuer configuration for the line reader.
pub trait LineReaderConfig {
    fn bank_code(&self) -> &'static str;
    fn claim_markers(&self) -> &'static [&'static str];
    fn row_re(&self) -> &'static Regex;
    /// Direction for a matched row, from the statement's own Dr/Cr indication.
    fn direction(&self, caps: &Captures<'_>, description: &str) -> Direction;
    /// Populate statement-level metadata from the full text. Defaults to a no-op.
    fn enrich(&self, _statement: &mut ParsedStatement, _full_text: &str) {}

    fn date_group(&self) -> &'static str {
        "date"
    }
    fn desc_group(&self) -> &'static str {
        "desc"
    }
    fn amount_group(&self) -> &'static str {
        "amount"
    }
}

/// True when `cfg` recognises `text` as a statement for `bank_code` (document-type +
/// issuer plausibility).
pub fn claims<C: LineReaderConfig>(cfg: &C, text: &str, bank_code: &str) -> bool {
    if bank_code != cfg.bank_code() {
        return false;
    }
    let hay = text.to_lowercase();
    cfg.claim_markers()
        .iter()
        .any(|marker| hay.contains(&marker.to_lowercase()))
}

/// Parse already-extracted text `lines` (+ `full_text` for enrichment) into a
/// [`ParsedStatement`]. Pure and total: a row that matches the shape but whose date or
/// amount will not parse is captured in `errored_lines` — never panics, never drops a
/// good row.
pub fn read_lines<C: LineReaderConfig>(
    cfg: &C,
    lines: &[String],
    full_text: &str,
) -> ParsedStatement {
    let mut statement = ParsedStatement::new(cfg.bank_code());
    let row_re = cfg.row_re();
    for line in lines {
        let Some(caps) = row_re.captures(line) else {
            // Not a transaction row (header/summary/balance/total) — skip silently.
            continue;
        };
        let txn_date = caps
            .name(cfg.date_group())
            .and_then(|m| parse_date(m.as_str()));
        let amount = caps
            .name(cfg.amount_group())
            .and_then(|m| parse_amount(m.as_str()));
        let (Some(txn_date), Some(amount)) = (txn_date, amount) else {
            statement.errored_lines.push(truncate_chars(line, MAX_RAW));
            continue;
        };
        let description = caps
            .name(cfg.desc_group())
            .map_or("", |m| m.as_str())
            .trim();
        let direction = cfg.direction(&caps, description);
        statement.lines.push(ParsedTransaction {
            value_date: txn_date,
            amount,
            direction,
            currency: "INR".to_string(),
            description_raw: truncate_chars(description, MAX_RAW),
            bank_code: cfg.bank_code().to_string(),
        });
    }
    cfg.enrich(&mut statement, full_text);
    statement
}

#[cfg(test)]
mod tests {
    use super::read_lines;
    use crate::statement::base::MAX_RAW;
    use crate::statement::icici::IciciReader;

    #[test]
    fn matched_row_with_unparseable_date_is_captured_not_dropped() {
        let lines = vec![
            "99/99/9999 4262 Impossible date 0 100.00".to_string(),
            "26/05/2026 1814 Fee on gaming transaction 0 10.20".to_string(),
        ];
        let st = read_lines(&IciciReader, &lines, "ICICI Bank");
        assert_eq!(st.lines.len(), 1, "the valid row is still returned");
        assert_eq!(st.errored_lines.len(), 1, "the bad row is captured");
    }

    #[test]
    fn errored_line_is_truncated_by_codepoint_without_panicking() {
        // A matched-but-unparseable multibyte line longer than the cap must be
        // truncated on a char boundary (never a byte slice mid-character).
        let long_desc = "café ".repeat(80); // 400 codepoints, multibyte 'é'
        let line = format!("99/99/9999 {long_desc} 10.00");
        let st = read_lines(&IciciReader, &[line], "ICICI Bank");
        assert_eq!(st.errored_lines.len(), 1);
        assert_eq!(st.errored_lines[0].chars().count(), MAX_RAW);
    }

    #[test]
    fn non_transaction_lines_and_empty_input_yield_nothing() {
        let lines = vec![
            "ICICI Bank Statement".to_string(),
            "Summary of your account".to_string(),
            "Total Amount Due 12,345.67".to_string(),
            String::new(),
        ];
        let st = read_lines(&IciciReader, &lines, "ICICI Bank");
        assert!(st.lines.is_empty(), "no rows from header/summary lines");
        assert!(st.errored_lines.is_empty(), "and none reported as errors");

        let empty = read_lines(&IciciReader, &[], "");
        assert!(empty.lines.is_empty() && empty.errored_lines.is_empty());
    }
}
