//! ICICI savings/current bank-account statement reader, ported from the web engine's
//! `icici_bank.py` — a configuration of the [`ledger_reader`](crate::statement::ledger_reader)
//! base.
//!
//! A `Withdrawal / Deposit / running-Balance` ledger with **no `Dr`/`Cr` marker**: the
//! direction is derived from the balance delta. One reader serves both ICICI savings and
//! current accounts. It sits alongside — never colliding with — the existing ICICI
//! credit-card reader ([`icici`](crate::statement::icici)); the two are told apart by
//! their `claims` gates (this one additionally requires "Statement of Transactions" and
//! a Savings/Current marker, so an ICICI credit-card statement is rejected here).

use std::sync::LazyLock;

use regex::Regex;

use crate::statement::base::ParsedStatement;
use crate::statement::common::{account_tail_last4, parse_date};
use crate::statement::ledger_reader::LedgerReaderConfig;

pub const BANK_CODE: &str = "ICICI";

// A transaction row ends in two money tokens `<amount> <balance>`. An optional
// value/transaction date pair and free-text remark / cheque number sit between the
// serial and the amount. Cheque numbers carry no decimals so never match a money group.
static ANCHOR_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^(?P<serial>\d{1,4})\s+(?P<date>\d{2}\.\d{2}\.\d{4})(?:\s+\d{2}\.\d{2}\.\d{4})?\s+(?P<desc>.*?)\s*(?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$",
    )
    .unwrap()
});

static OPENING_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)(?:Opening Balance|BALANCE\s+B/F|B/F)\s+([\d,]+\.\d{2})").unwrap()
});

static CLOSING_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)Closing Balance\s+([\d,]+\.\d{2})").unwrap());

// Full-month statement period header: "... June 16, 2025 to July 15, 2025".
static PERIOD_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)([A-Za-z]+ \d{1,2}, \d{4})\s+to\s+([A-Za-z]+ \d{1,2}, \d{4})").unwrap()
});

// The printed (full) account number is a long pure-digit run; only its trailing 4 is
// ever persisted — the full number is never logged/columned/sent anywhere.
static ACCOUNT_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)Account\s+(?:Number|No\.?)\s*:?\s*([0-9]{6,})").unwrap());

// Withdrawal (debit) column sits left of this x; deposit (credit) column to its right.
// Only consulted for the FIRST row when no opening balance is printed; any such row is
// flagged NeedsReview by the balance-chain check regardless.
const COLUMN_SPLIT_X: f64 = 400.0;

const CLAIM_ALL: &[&str] = &["Statement of Transactions", "ICICI"];
const CLAIM_ANY: &[&str] = &["Saving", "Current"];

/// The ICICI bank-account reader (zero-sized; all state is in the statics above).
pub struct IciciBankReader;

impl LedgerReaderConfig for IciciBankReader {
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

    fn column_split_x(&self) -> Option<f64> {
        Some(COLUMN_SPLIT_X)
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
    use crate::statement::base::DirectionSource;
    use crate::statement::ledger_reader::{claims_ledger, read_ledger_lines};
    use rust_decimal_macros::dec;

    fn sample() -> (Vec<String>, String) {
        let full_text = concat!(
            "ICICI Bank Limited\n",
            "Statement of Transactions in Savings Account\n",
            "Account Number 000401000123456\n",
            "Statement Period June 16, 2025 to July 15, 2025\n",
            "Opening Balance 1,00,000.00\n",
            "S No. Value Date Transaction Date Cheque No. Transaction Remarks Withdrawal Deposit Balance\n",
            "UPI/512345/ALICE STORE/Payment\n",
            "1 16.06.2025 16.06.2025 5,000.00 95,000.00\n",
            "NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY\n",
            "2 18.06.2025 18.06.2025 50,000.00 1,45,000.00\n",
            "3 20.06.2025 20.06.2025 ATM CASH WITHDRAWAL 2,000.00 1,43,000.00\n",
            "Closing Balance 1,43,000.00"
        )
        .to_string();
        let lines: Vec<String> = full_text
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .map(str::to_string)
            .collect();
        (lines, full_text)
    }

    #[test]
    fn parses_delta_directions_narration_and_metadata() {
        let (lines, full_text) = sample();
        let st = read_ledger_lines(&IciciBankReader, &lines, &full_text, &[]);
        assert_eq!(st.lines.len(), 3);

        assert_eq!(st.lines[0].direction, Direction::Debit); // 100000 → 95000
        assert_eq!(st.lines[0].amount, dec!(5000.00));
        assert_eq!(
            st.lines[0].description_raw,
            "UPI/512345/ALICE STORE/Payment"
        );
        let l0 = st.lines[0].ledger.as_ref().unwrap();
        assert_eq!(l0.direction_source, DirectionSource::OpeningBalance);
        assert_eq!(l0.serial, "1");
        assert!(l0.amount_matches_delta);

        assert_eq!(st.lines[1].direction, Direction::Credit); // 95000 → 145000
        assert_eq!(
            st.lines[1].description_raw,
            "NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY"
        );
        assert_eq!(
            st.lines[1].ledger.as_ref().unwrap().direction_source,
            DirectionSource::BalanceDelta
        );

        assert_eq!(st.lines[2].direction, Direction::Debit); // 145000 → 143000
        assert_eq!(st.lines[2].description_raw, "ATM CASH WITHDRAWAL");

        assert_eq!(
            st.period_start,
            chrono::NaiveDate::from_ymd_opt(2025, 6, 16)
        );
        assert_eq!(st.period_end, chrono::NaiveDate::from_ymd_opt(2025, 7, 15));
        assert_eq!(st.card_last4.as_deref(), Some("3456"));
        assert_eq!(st.printed_opening_balance, Some(dec!(100000.00)));
        assert_eq!(st.printed_closing_balance, Some(dec!(143000.00)));
        assert!(st.errored_lines.is_empty());
    }

    #[test]
    fn claims_accepts_savings_and_rejects_credit_card() {
        let (_, full_text) = sample();
        assert!(claims_ledger(&IciciBankReader, &full_text, BANK_CODE));
        // An ICICI credit-card statement is not a bank-account statement.
        let cc = "ICICI Bank\nSPENDS OVERVIEW\nStatement Date May 28, 2026\n4315XXXXXXXX1002\n";
        assert!(!claims_ledger(&IciciBankReader, cc, BANK_CODE));
        // Wrong bank_code is rejected outright.
        assert!(!claims_ledger(&IciciBankReader, &full_text, "HDFC"));
    }

    #[test]
    fn cheque_number_line_is_not_mistaken_for_an_amount() {
        // A cheque-number column carries no decimals, so a row with a cheque number still
        // resolves amount/balance from the two trailing decimal money tokens.
        let lines = vec![
            "ICICI Bank Statement of Transactions in Savings Account".to_string(),
            "Opening Balance 1,00,000.00".to_string(),
            "1 16.06.2025 16.06.2025 100123 5,000.00 95,000.00".to_string(),
        ];
        let st = read_ledger_lines(&IciciBankReader, &lines, &lines.join("\n"), &[]);
        assert_eq!(st.lines.len(), 1);
        assert_eq!(st.lines[0].amount, dec!(5000.00));
    }
}
