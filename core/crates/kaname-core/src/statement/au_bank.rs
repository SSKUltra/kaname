//! AU Small Finance Bank savings/current statement reader, ported from the web engine's
//! `au_bank.py` — a configuration of the [`ledger_reader`](crate::statement::ledger_reader)
//! base.
//!
//! AU bank statements are running-balance ledgers with NO per-row `Dr`/`Cr` marker: the
//! `UPI/DR` / `UPI/CR` text that appears inside a narration describes the *counterparty*'s
//! leg, never this account's, so direction is derived from the running-balance delta.
//!
//! Layout (single template): a transaction line starts with two `DD Mon YYYY` dates
//! (transaction + value date) and ends in three tokens — a Debit column, a Credit column,
//! and the running Balance. Exactly one of the debit/credit columns carries a money value;
//! the empty side prints a dash (`-`), which the base's amount parser reads as "no value"
//! so the non-dash side becomes the amount. Wrapped UPI/NEFT narration lands on the lines
//! above and below the anchor and is stitched back together.

use std::sync::LazyLock;

use regex::Regex;

use crate::statement::base::ParsedStatement;
use crate::statement::common::{account_tail_last4, parse_date};
use crate::statement::ledger_reader::LedgerReaderConfig;

pub const BANK_CODE: &str = "AU";

// A transaction row: `<txn-date> <value-date> <narration...> <debit|-> <credit|-> <balance>`.
// Both dates are `DD Mon YYYY`. Exactly one of the debit/credit columns is a money token;
// the other prints a dash (read as "no value"). Direction comes from the balance delta.
static ANCHOR_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^(?P<date>\d{2} [A-Za-z]{3} \d{4})\s+\d{2} [A-Za-z]{3} \d{4}\s+(?P<desc>.*?)\s*(?P<withdrawal>[\d,]+\.\d{2}|-)\s+(?P<deposit>[\d,]+\.\d{2}|-)\s+(?P<balance>[\d,]+\.\d{2})\s*$",
    )
    .unwrap()
});

// Header prints "Opening Balance(₹) : 11,570.79" / "Closing Balance(₹) : 223.34" (the
// bracketed currency glyph may extract variably, so match any parenthesised group).
static OPENING_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)Opening Balance\s*\([^)]*\)\s*:\s*([\d,]+\.\d{2})").unwrap());

static CLOSING_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)Closing Balance\s*\([^)]*\)\s*:\s*([\d,]+\.\d{2})").unwrap());

// "Statement Period : 01 Mar 2026 to 31 May 2026".
static PERIOD_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)Statement Period\s*:\s*(\d{2} [A-Za-z]{3} \d{4})\s+to\s+(\d{2} [A-Za-z]{3} \d{4})",
    )
    .unwrap()
});

// "Account Number : 1234567890120042" — only the trailing four is ever persisted.
static ACCOUNT_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)Account\s+Number\s*:?\s*X*([0-9]{6,})").unwrap());

const CLAIM_ALL: &[&str] = &["aubank.in"];
const CLAIM_ANY: &[&str] = &["Savings Account", "Current Account"];

/// The AU Small Finance Bank bank-account reader (zero-sized; state is in the statics).
pub struct AuBankReader;

impl LedgerReaderConfig for AuBankReader {
    fn bank_code(&self) -> &'static str {
        BANK_CODE
    }

    fn claim_all(&self) -> &'static [&'static str] {
        CLAIM_ALL
    }

    fn claim_any(&self) -> &'static [&'static str] {
        CLAIM_ANY
    }

    fn anchor_res(&self) -> Vec<&'static Regex> {
        vec![&ANCHOR_RE]
    }

    fn opening_balance_re(&self) -> Option<&'static Regex> {
        Some(&OPENING_RE)
    }

    fn closing_balance_re(&self) -> Option<&'static Regex> {
        Some(&CLOSING_RE)
    }

    fn account_tail(&self, text: &str) -> Option<String> {
        account_tail_last4(text, &ACCOUNT_RE)
    }

    fn enrich(&self, statement: &mut ParsedStatement, full_text: &str) {
        if let Some(caps) = PERIOD_RE.captures(full_text) {
            statement.period_start = parse_date(&caps[1]);
            statement.period_end = parse_date(&caps[2]);
        }
        statement.card_last4 = self.account_tail(full_text);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Direction;
    use crate::statement::ledger_reader::{claims_ledger, read_ledger_lines};
    use rust_decimal_macros::dec;

    fn lines_of(full_text: &str) -> Vec<String> {
        full_text
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .map(str::to_string)
            .collect()
    }

    fn savings() -> String {
        concat!(
            "ACCOUNT STATEMENT\n",
            "Name : Test User Account Number : 1234567890120042\n",
            "Customer ID : 99999999 Account Type : AU Lite Savings Account\n",
            "Statement Date : 22 Jun 2026 Opening Balance(\u{20b9}) : 11,570.79\n",
            "Statement Period : 01 Mar 2026 to 31 May 2026 Closing Balance(\u{20b9}) : 223.34\n",
            "Transaction Cheque/\n",
            "Value Date Description/Narration Debit (\u{20b9}) Credit (\u{20b9}) Balance (\u{20b9})\n",
            "Date Reference No.\n",
            "UPI/DR/000000000001/EXAMPLE ABC0000000001ref\n",
            "01 Mar 2026 01 Mar 2026 STORE 1111ref2222tail 5,000.00 - 6,570.79\n",
            "MERCHANT/UTIB/0000/UPI AU\n",
            "UPI/CR/000000000002/EXAMPLE XYZ0000000002ref\n",
            "02 Mar 2026 02 Mar 2026 EMPLOYER 3333ref4444tail - 10,000.00 16,570.79\n",
            "SALARY/UTIB/0000/UPI AU\n",
            "1800 1200 1200 www.aubank.in customercare@aubank.in"
        )
        .to_string()
    }

    #[test]
    fn direction_from_delta_not_the_upi_dr_cr_narration() {
        let full_text = savings();
        let st = read_ledger_lines(&AuBankReader, &lines_of(&full_text), &full_text, &[]);
        assert_eq!(st.lines.len(), 2, "{:?}", st.errored_lines);
        // Row 0's narration contains "UPI/DR" but the balance rose→fell → debit; row 1's
        // narration contains "UPI/CR" and the balance rose → credit. The text is inert.
        assert_eq!(st.lines[0].direction, Direction::Debit); // 11570.79 → 6570.79
        assert_eq!(st.lines[1].direction, Direction::Credit); // 6570.79 → 16570.79
        assert!(st.lines[0].description_raw.contains("UPI/DR"));
        assert!(st.lines[1].description_raw.contains("UPI/CR"));
    }

    #[test]
    fn dash_marked_empty_column_yields_the_nonzero_side_as_amount() {
        let full_text = savings();
        let st = read_ledger_lines(&AuBankReader, &lines_of(&full_text), &full_text, &[]);
        assert_eq!(st.lines[0].amount, dec!(5000.00)); // debit col; deposit is "-"
        assert_eq!(st.lines[1].amount, dec!(10000.00)); // credit col; withdrawal is "-"
        assert!(st
            .lines
            .iter()
            .all(|l| !l.ledger.as_ref().unwrap().is_suspect));
    }

    #[test]
    fn header_and_footer_lines_are_not_transactions_and_metadata_is_extracted() {
        let full_text = savings();
        let st = read_ledger_lines(&AuBankReader, &lines_of(&full_text), &full_text, &[]);
        assert_eq!(st.lines.len(), 2);
        assert!(st.errored_lines.is_empty());
        assert_eq!(st.printed_opening_balance, Some(dec!(11570.79)));
        // The last row's running balance, NOT the header's printed closing (223.34).
        assert_eq!(st.printed_closing_balance, Some(dec!(16570.79)));
        assert_eq!(st.card_last4.as_deref(), Some("0042"));
        assert_eq!(st.period_start, chrono::NaiveDate::from_ymd_opt(2026, 3, 1));
        assert_eq!(st.period_end, chrono::NaiveDate::from_ymd_opt(2026, 5, 31));
    }

    #[test]
    fn claims_accepts_au_savings_and_rejects_credit_card() {
        assert!(claims_ledger(&AuBankReader, &savings(), BANK_CODE));
        let cc = "AU Bank\nYour Credit Card Statement\n4315XXXXXXXX1002\n";
        assert!(!claims_ledger(&AuBankReader, cc, BANK_CODE));
        assert!(!claims_ledger(&AuBankReader, &savings(), "HDFC"));
    }
}
