//! Shared, pure parsing helpers ported from the web engine's `_common.py`.
//!
//! Indian-format amount parsing, multi-format date parsing, and masked-PAN last-4
//! extraction. Deliberately does NOT port the PDF text-extraction helpers
//! (`extract_lines`/`extract_tables`/`full_text`) — extraction is a native platform
//! concern; the engine receives already-extracted text.

use std::str::FromStr;
use std::sync::LazyLock;

use chrono::NaiveDate;
use regex::Regex;
use rust_decimal::Decimal;

// Indian money token: optional sign/paren/currency, then the grouped digits + 2dp.
static AMOUNT_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)-?\(?\s*(?:₹|rs\.?|inr)?\s*([\d,]+\.\d{2})\s*\)?").unwrap());

// Date formats seen across the issuers' statements (ported in order from `_common.py`).
const DATE_FORMATS: &[&str] = &[
    "%d/%m/%Y",  // 19/04/2026 (ICICI, Yes)
    "%d/%m/%y",  // 01/04/26 (HDFC savings, 2-digit year — tried after %d/%m/%Y)
    "%Y-%m-%d",  // 2026-04-19 (ISO)
    "%d-%m-%Y",  // 24-04-2026 (Scapia/Federal)
    "%d-%b-%Y",  // 04-Apr-2025 (HDFC)
    "%d %b %y",  // 21 Apr 26 (SBI)
    "%d %b %Y",  // 21 Apr 2026
    "%b %d, %Y", // May 28, 2026 (ICICI header)
    "%B %d, %Y", // June 16, 2025 (ICICI savings full-month header)
    "%d.%m.%Y",  // 16.06.2025 (ICICI savings dotted anchor date)
    "%d%b%Y",    // 20Apr2026 (Scapia billing cycle, space-stripped)
    "%d %B %Y",  // 21 May 2026
];

// Contiguous masked PAN core: leading digits, a run of mask chars, four trailing
// digits. Rust `regex` has no lookaround, so the Python neighbour assertions
// `(?<![0-9Xx*])…(?![0-9Xx*])` are applied manually in `find_last4_in`.
static STRICT_PAN_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"[0-9]{2,6}[Xx*]{2,}[0-9]{4}").unwrap());

// Looser near-full masked PAN (>= 12 leading card chars then four digits).
static LOOSE_PAN_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?:[0-9Xx*][ \-]?){12,}[0-9]{4}").unwrap());

/// Parse an Indian-formatted money token to a non-negative [`Decimal`].
///
/// Strips ₹/Rs/INR, thousands separators (incl. the Indian `1,23,456` grouping),
/// surrounding parentheses and any sign — direction is decided separately from the
/// statement's Dr/Cr indication, never from the amount. Returns `None` on no match.
pub fn parse_amount(raw: &str) -> Option<Decimal> {
    let caps = AMOUNT_RE.captures(raw)?;
    let cleaned = caps.get(1)?.as_str().replace(',', "");
    Decimal::from_str(&cleaned).ok()
}

/// Parse a date token using the known issuer formats; `None` on no match. `chrono`'s
/// `%b`/`%B` use built-in English month tables, so parsing is locale-independent.
pub fn parse_date(raw: &str) -> Option<NaiveDate> {
    let token = raw.trim();
    DATE_FORMATS
        .iter()
        .find_map(|fmt| NaiveDate::parse_from_str(token, fmt).ok())
}

fn is_pan_char(c: char) -> bool {
    c.is_ascii_digit() || c == 'X' || c == 'x' || c == '*'
}

fn find_last4_in(haystack: &str) -> Option<String> {
    // Prefer a strict contiguous masked PAN whose neighbours are not PAN chars, so an
    // inline card number printed next to other figures does not bleed across spaces.
    for m in STRICT_PAN_RE.find_iter(haystack) {
        let before_ok = haystack[..m.start()]
            .chars()
            .next_back()
            .is_none_or(|c| !is_pan_char(c));
        let after_ok = haystack[m.end()..]
            .chars()
            .next()
            .is_none_or(|c| !is_pan_char(c));
        if before_ok && after_ok {
            let matched = m.as_str();
            return Some(matched[matched.len() - 4..].to_string());
        }
    }
    // Fallback: a near-full masked PAN that contains at least one mask char.
    for m in LOOSE_PAN_RE.find_iter(haystack) {
        let token = m.as_str();
        if !token.contains(['X', 'x', '*']) {
            continue;
        }
        let digits: String = token.chars().filter(char::is_ascii_digit).collect();
        if digits.len() >= 4 {
            return Some(digits[digits.len() - 4..].to_string());
        }
    }
    None
}

/// Best-effort card last-4 from a masked PAN (e.g. `4315XXXXXXXX1002` → `1002`).
///
/// `anchor`, when given, restricts the first pass to lines containing it, falling back
/// to the whole document.
pub fn find_last4(text: &str, anchor: Option<&str>) -> Option<String> {
    if let Some(anchor) = anchor {
        let needle = anchor.to_lowercase();
        let anchored: String = text
            .lines()
            .filter(|line| line.to_lowercase().contains(&needle))
            .collect::<Vec<_>>()
            .join("\n");
        if !anchored.is_empty() {
            if let Some(found) = find_last4_in(&anchored) {
                return Some(found);
            }
        }
    }
    find_last4_in(text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    #[test]
    fn parses_indian_amounts_preserving_scale() {
        assert_eq!(parse_amount("13,628.36"), Some(dec!(13628.36)));
        assert_eq!(parse_amount("10.20"), Some(dec!(10.20)));
        assert_eq!(parse_amount("Rs 1,23,456.78"), Some(dec!(123456.78)));
        assert_eq!(parse_amount("(1,200.00)"), Some(dec!(1200.00)));
        assert_eq!(parse_amount("no amount here"), None);
    }

    #[test]
    fn parses_issuer_date_formats() {
        assert_eq!(
            parse_date("29/04/2026"),
            NaiveDate::from_ymd_opt(2026, 4, 29)
        );
        assert_eq!(
            parse_date("May 28, 2026"),
            NaiveDate::from_ymd_opt(2026, 5, 28)
        );
        assert_eq!(parse_date("not a date"), None);
    }

    #[test]
    fn extracts_masked_pan_last4() {
        assert_eq!(
            find_last4("4315XXXXXXXX1002", None).as_deref(),
            Some("1002")
        );
        assert_eq!(find_last4("no card here", None), None);
    }
}
