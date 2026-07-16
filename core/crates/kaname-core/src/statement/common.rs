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
    // `%d/%m/%y` MUST precede `%d/%m/%Y`: Rust's chrono `%Y` greedily accepts a 2-digit
    // year (e.g. `01/04/26` → year 0026), whereas `%d/%m/%y` rejects a 4-digit token, so
    // this order parses both `01/04/26` → 2026 and `01/04/2026` → 2026 correctly.
    "%d/%m/%y",  // 01/04/26 (HDFC savings compact, 2-digit year)
    "%d/%m/%Y",  // 19/04/2026 (ICICI, Yes)
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

// A standalone long-digit run (a bank account number, never a money token — those carry
// decimals). Rust `regex` has no lookaround, but a greedy, non-overlapping `\d{9,}`
// already yields maximal digit runs, matching Python's `(?<!\d)(\d{9,})(?!\d)`.
static DIGIT_RUN_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\d{9,}").unwrap());

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

// Month name (first three letters, upper-case) → month number.
const MONTHS: &[(&str, u32)] = &[
    ("JAN", 1),
    ("FEB", 2),
    ("MAR", 3),
    ("APR", 4),
    ("MAY", 5),
    ("JUN", 6),
    ("JUL", 7),
    ("AUG", 8),
    ("SEP", 9),
    ("OCT", 10),
    ("NOV", 11),
    ("DEC", 12),
];

fn last_day_of_month(year: i32, month: u32) -> Option<NaiveDate> {
    let (y, m) = if month == 12 {
        (year + 1, 1)
    } else {
        (year, month + 1)
    };
    NaiveDate::from_ymd_opt(y, m, 1)?.pred_opt()
}

/// Parse a `"MONTHNAME-YY"` token (e.g. `"MARCH-26"`) to the LAST day of that month
/// (`2026-03-31`). The month is matched on its first three letters (case-insensitive)
/// and the two-digit year is 2000-based. `None` for an unrecognised token. Used by
/// readers whose billing period is printed as month-year ranges (e.g. HDFC year-end).
pub fn month_year_end(token: &str) -> Option<NaiveDate> {
    let (name, yy) = token.split_once('-')?;
    let key: String = name.chars().take(3).collect::<String>().to_uppercase();
    let month = MONTHS.iter().find(|(m, _)| *m == key).map(|(_, n)| *n)?;
    let year = 2000 + yy.trim().parse::<i32>().ok()?;
    last_day_of_month(year, month)
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

/// Trailing 4 characters (bytes) of an ASCII digit string.
fn tail4(digits: &str) -> String {
    digits[digits.len().saturating_sub(4)..].to_string()
}

/// Best-effort bank-ACCOUNT tail: the trailing four of the printed account number.
///
/// Distinct from the credit-card masked-PAN matcher [`find_last4`]. Tries `primary`
/// (its first capture group), else the longest standalone >= 9-digit run; `None` if
/// neither hits. Only the trailing four is ever surfaced — the full number is never
/// logged or persisted.
pub fn account_tail_last4(text: &str, primary: &Regex) -> Option<String> {
    if let Some(caps) = primary.captures(text) {
        if let Some(m) = caps.get(1) {
            return Some(tail4(m.as_str()));
        }
    }
    let best = DIGIT_RUN_RE
        .find_iter(text)
        .map(|m| m.as_str())
        .max_by_key(|run| run.len())?;
    Some(tail4(best))
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
    fn two_and_four_digit_slash_years_both_resolve_to_2026() {
        // Rust chrono's `%Y` greedily accepts a 2-digit year, so `%d/%m/%y` MUST be tried
        // first (regression guard for the HDFC-compact 2-digit dates).
        assert_eq!(parse_date("01/04/26"), NaiveDate::from_ymd_opt(2026, 4, 1));
        assert_eq!(parse_date("16/04/26"), NaiveDate::from_ymd_opt(2026, 4, 16));
        assert_eq!(
            parse_date("01/04/2026"),
            NaiveDate::from_ymd_opt(2026, 4, 1)
        );
    }

    #[test]
    fn account_tail_last4_prefers_primary_then_falls_back_to_digit_run() {
        let re = Regex::new(r"(?i)Account\s*(?:Number|No\.?)\s*:?\s*X*([0-9]{4,})").unwrap();
        assert_eq!(
            account_tail_last4("AccountNo : 50100359253425", &re).as_deref(),
            Some("3425")
        );
        // No primary match → longest standalone >= 9-digit run.
        assert_eq!(
            account_tail_last4("holder 000401000123456 ref", &re).as_deref(),
            Some("3456")
        );
        assert_eq!(account_tail_last4("no account here", &re), None);
    }

    #[test]
    fn extracts_masked_pan_last4() {
        assert_eq!(
            find_last4("4315XXXXXXXX1002", None).as_deref(),
            Some("1002")
        );
        assert_eq!(find_last4("no card here", None), None);
    }

    #[test]
    fn month_year_end_returns_last_day_of_month() {
        assert_eq!(
            month_year_end("MARCH-26"),
            NaiveDate::from_ymd_opt(2026, 3, 31)
        );
        assert_eq!(
            month_year_end("APRIL-25"),
            NaiveDate::from_ymd_opt(2025, 4, 30)
        );
        assert_eq!(
            month_year_end("FEB-24"),
            NaiveDate::from_ymd_opt(2024, 2, 29)
        ); // leap
        assert_eq!(month_year_end("BOGUS-99"), None);
    }
}
