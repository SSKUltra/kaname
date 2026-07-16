//! HDFC Bank savings/current statement reader, ported from the web engine's
//! `hdfc_bank.py` — a configuration of the [`ledger_reader`](crate::statement::ledger_reader)
//! base.
//!
//! HDFC bank statements carry no per-row `Dr`/`Cr` marker (direction from the balance
//! delta) and ship in two export layouts, both handled by one reader via first-match-wins
//! anchors:
//!   1. **Compact** — `DD/MM/YY` dates, one row ending `<ref> <value-date> <amount>
//!      <balance>` (a single printed amount + an alphanumeric reference captured as the
//!      serial). The opening balance is the first figure of the end-of-statement summary.
//!   2. **Detailed** — `DD/MM/YYYY` dates with explicit Withdrawals/Deposits columns (the
//!      empty side prints `0.00`) then the closing balance, and an inline `Opening
//!      Balance :`.
//!
//! One reader serves both HDFC savings and current accounts and both layouts. It sits
//! alongside — never colliding with — the HDFC credit-card reader
//! ([`hdfc`](crate::statement::hdfc)); the two are told apart by their `claims` gates.

use std::sync::LazyLock;

use regex::Regex;

use crate::statement::base::ParsedStatement;
use crate::statement::common::{account_tail_last4, parse_date};
use crate::statement::ledger_reader::LedgerReaderConfig;

pub const BANK_CODE: &str = "HDFC";

// Compact layout: `<date> <narration...> <ref> <value-date> <amount> <balance>`. Dates
// are `DD/MM/YY`; the alphanumeric reference (captured as the serial) is pure digits for
// UPI rows or letters+digits for NEFT rows. A single printed amount sits in either the
// withdrawal or deposit column; direction is read from the balance delta.
static ANCHOR_COMPACT_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^(?P<date>\d{2}/\d{2}/\d{2})\s+(?P<desc>.*?)\s+(?P<serial>[A-Za-z0-9]{6,})\s+\d{2}/\d{2}/\d{2}\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$",
    )
    .unwrap()
});

// Detailed layout: `<date> <narration...> <withdrawal> <deposit> <balance>`. Dates are
// `DD/MM/YYYY`; both columns print (one is `0.00`). The non-zero column is the amount.
static ANCHOR_DETAILED_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^(?P<date>\d{2}/\d{2}/\d{4})\s+(?P<desc>.*?)\s+(?P<withdrawal>[\d,]+\.\d{2})\s+(?P<deposit>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$",
    )
    .unwrap()
});

// Opening balance: detailed prints "Opening Balance : 1,00,000.00"; compact prints it as
// the first figure of the end summary row, under an "OpeningBalance …" header (matched
// across the newline). The capture is group 1 in both alternatives.
static OPENING_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)(?:Opening Balance\s*:\s*|OpeningBalance\b[^\n]*\n\s*)([\d,]+\.\d{2})")
        .unwrap()
});

// Statement period: "From : 01/04/2026 To : 30/04/2026" (the colon before the end date
// is optional). Both layouts use DD/MM/YYYY.
static PERIOD_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)From\s*:\s*(\d{2}/\d{2}/\d{4})\s+To\s*:?\s*(\d{2}/\d{2}/\d{4})").unwrap()
});

// Account number: "AccountNo : 50100359253425" / "Account Number : …". An optional
// masked `X*` prefix precedes the digits; only the trailing four is ever persisted.
static ACCOUNT_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)Account\s*(?:Number|No\.?)\s*:?\s*X*([0-9]{4,})").unwrap());

const CLAIM_ALL: &[&str] = &["HDFC"];
const CLAIM_ANY: &[&str] = &[
    "WithdrawalAmt",
    "Savings Account Details",
    "Statementof account",
];

/// The HDFC bank-account reader (zero-sized; all state is in the statics above).
pub struct HdfcBankReader;

impl LedgerReaderConfig for HdfcBankReader {
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
        vec![&ANCHOR_COMPACT_RE, &ANCHOR_DETAILED_RE]
    }

    fn opening_balance_re(&self) -> Option<&'static Regex> {
        Some(&OPENING_RE)
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

    fn lines_of(full_text: &str) -> Vec<String> {
        full_text
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .map(str::to_string)
            .collect()
    }

    fn compact() -> String {
        concat!(
            "HDFC BANK LIMITED\n",
            "Statementof account\n",
            "From : 01/04/2026 To : 30/04/2026\n",
            "AccountNo : 50100359253425\n",
            "Date Narration Chq./Ref.No. ValueDt WithdrawalAmt. DepositAmt. ClosingBalance\n",
            "01/04/26 UPI-EXAMPLEMERCHANT 0000600000000001 01/04/26 5,000.00 95,000.00\n",
            "16/04/26 NEFTCR-EXAMPLEEMPLOYER CITIN26653417445 16/04/26 50,000.00 1,45,000.00\n",
            "OpeningBalance DrCount CrCount Debits Credits ClosingBal\n",
            "1,00,000.00 1 1 5,000.00 50,000.00 1,45,000.00"
        )
        .to_string()
    }

    fn detailed() -> String {
        concat!(
            "HDFC Bank\n",
            "Savings Account Details\n",
            "Statement From : 01/04/2026 To 30/04/2026\n",
            "Account Number : 50100359253425\n",
            "Opening Balance : 1,00,000.00 Limit : 0.00\n",
            "Txn Date Narration Withdrawals Deposits Closing Balance\n",
            "01/04/2026 UPI-EXAMPLEMERCHANT 5,000.00 0.00 95,000.00\n",
            "20/04/2026 UPI-EXAMPLEEMPLOYER salary 0.00 50,000.00 1,45,000.00"
        )
        .to_string()
    }

    #[test]
    fn compact_layout_reads_alphanumeric_serial_and_summary_opening() {
        let full_text = compact();
        let st = read_ledger_lines(&HdfcBankReader, &lines_of(&full_text), &full_text, &[]);
        assert_eq!(st.lines.len(), 2, "{:?}", st.errored_lines);
        assert_eq!(st.lines[0].direction, Direction::Debit); // 100000 → 95000
        assert_eq!(st.lines[0].amount, dec!(5000.00));
        assert_eq!(st.lines[1].direction, Direction::Credit); // 95000 → 145000
        assert_eq!(st.lines[1].amount, dec!(50000.00));
        // The opening balance comes from the summary row, not row 1.
        assert_eq!(st.printed_opening_balance, Some(dec!(100000.00)));
        assert_eq!(st.printed_closing_balance, Some(dec!(145000.00)));
        // The NEFT row's alphanumeric reference is captured as the serial.
        let l1 = st.lines[1].ledger.as_ref().unwrap();
        assert_eq!(l1.serial, "CITIN26653417445");
        assert_eq!(
            st.lines[0].ledger.as_ref().unwrap().direction_source,
            DirectionSource::OpeningBalance
        );
        assert_eq!(st.card_last4.as_deref(), Some("3425"));
        assert_eq!(st.period_start, chrono::NaiveDate::from_ymd_opt(2026, 4, 1));
        assert_eq!(st.period_end, chrono::NaiveDate::from_ymd_opt(2026, 4, 30));
    }

    #[test]
    fn detailed_layout_resolves_nonzero_withdrawal_deposit_column() {
        let full_text = detailed();
        let st = read_ledger_lines(&HdfcBankReader, &lines_of(&full_text), &full_text, &[]);
        assert_eq!(st.lines.len(), 2, "{:?}", st.errored_lines);
        assert_eq!(st.lines[0].direction, Direction::Debit); // withdrawal side
        assert_eq!(st.lines[0].amount, dec!(5000.00));
        assert_eq!(st.lines[1].direction, Direction::Credit); // deposit side
        assert_eq!(st.lines[1].amount, dec!(50000.00));
        assert_eq!(st.lines[1].description_raw, "UPI-EXAMPLEEMPLOYER salary");
        assert_eq!(st.printed_opening_balance, Some(dec!(100000.00)));
        assert_eq!(st.card_last4.as_deref(), Some("3425"));
    }

    #[test]
    fn claims_accepts_both_savings_layouts_and_rejects_credit_card() {
        assert!(claims_ledger(&HdfcBankReader, &compact(), BANK_CODE));
        assert!(claims_ledger(&HdfcBankReader, &detailed(), BANK_CODE));
        // An HDFC credit-card statement is not a bank-account statement.
        let cc = "HDFC Bank Credit Cards\nCard Number XXXX6873XXXXXX9070\n";
        assert!(!claims_ledger(&HdfcBankReader, cc, BANK_CODE));
        // Wrong issuer code is rejected outright.
        assert!(!claims_ledger(&HdfcBankReader, &compact(), "ICICI"));
    }
}
