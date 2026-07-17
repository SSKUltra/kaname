//! Federal Bank savings/current statement reader, ported from the web engine's
//! `federal_bank.py` — a configuration of the [`ledger_reader`](crate::statement::ledger_reader)
//! base.
//!
//! Federal bank statements are running-balance ledgers; the printed `Cr`/`Dr` marks the
//! *balance*'s sign, NOT the transaction, so direction is still derived from the balance
//! delta. Two templates ship behind one reader (first-match-wins):
//!   1. **Classic** (direct Federal Bank) — `DD-MON-YYYY` dates, a single printed amount
//!      then the balance and a trailing `Cr`/`Dr` (consumed but ignored). An optional
//!      `S`-prefixed Tran ID is captured as the serial and kept out of the description.
//!   2. **Neobank / Fi (Epifi)** — `DD/MM/YYYY` dates with explicit Withdrawal/Deposit
//!      columns (the empty side is `0`), amounts that may be whole numbers, then the
//!      balance and `Cr`/`Dr`.
//!
//! One reader serves both Federal savings and current accounts and both templates. It
//! shares `bank_code = "FEDERAL"` with the Scapia/Federal credit-card reader
//! ([`federal`](crate::statement::federal)) — one issuer code, two account kinds — and
//! the two are told apart by their `claims` gates (this one additionally requires the
//! savings "Statement of Account" header, so a Scapia card statement is rejected here).

use std::sync::LazyLock;

use regex::Regex;

use crate::statement::base::ParsedStatement;
use crate::statement::common::{account_tail_last4, parse_date};
use crate::statement::ledger_reader::LedgerReaderConfig;

pub const BANK_CODE: &str = "FEDERAL";

// Classic template: `<date> <value-date> <particulars...> [S<id>] <amount> <balance>
// Cr|Dr`. Dates are `DD-MON-YYYY`. The trailing `Cr`/`Dr` marks the balance's sign and
// is consumed but ignored (a non-capturing group) — direction comes from the delta.
static ANCHOR_CLASSIC_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)^(?P<date>\d{2}-[A-Za-z]{3}-\d{4})\s+\d{2}-[A-Za-z]{3}-\d{4}\s+(?P<desc>.*?)(?:\s+(?P<serial>S\d+))?\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s+(?:Cr|Dr)\s*$",
    )
    .unwrap()
});

// Neobank / Fi template: `<date> <value-date> <particulars...> [S<id>] <withdrawal>
// <deposit> <balance> Cr|Dr`. `DD/MM/YYYY` dates; both columns print (one is `0`);
// amounts may be whole numbers, so the column tokens allow an optional decimal while the
// running balance always carries paise. The non-zero column is the amount.
static ANCHOR_FI_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)^(?P<date>\d{2}/\d{2}/\d{4})\s+\d{2}/\d{2}/\d{4}\s+(?P<desc>.*?)(?:\s+(?P<serial>S\d+))?\s+(?P<withdrawal>[\d,]+(?:\.\d{2})?)\s+(?P<deposit>[\d,]+(?:\.\d{2})?)\s+(?P<balance>[\d,]+\.\d{2})\s+(?:Cr|Dr)\s*$",
    )
    .unwrap()
});

// Opening balance: classic "Opening Balance 1,00,000.00 Cr"; Fi "Opening Balance OPNBAL
// 1,00,000.00 CR" (an OPNBAL tran-id sits between).
static OPENING_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)Opening Balance\s+(?:[A-Z]+\s+)?([\d,]+\.\d{2})").unwrap());

// Statement period: classic ISO "for the period 2026-04-01 to 2026-04-30"; Fi
// "for the period of 08/04/2026 to 07/05/2026".
static PERIOD_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)for the period(?:\s+of)?\s+(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})\s+to\s+(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})",
    )
    .unwrap()
});

// Account number: classic prints it in full ("Account Number : 99990100001234"); Fi
// masks all but the last four ("Account Number: XXXXX4222"). Only the trailing four is
// ever persisted.
static ACCOUNT_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)Account\s+Number\s*:?\s*X*([0-9]{4,})").unwrap());

const CLAIM_ALL: &[&str] = &["Federal Bank", "Statement of Account"];

/// The Federal Bank bank-account reader (zero-sized; all state is in the statics above).
pub struct FederalBankReader;

impl LedgerReaderConfig for FederalBankReader {
    fn bank_code(&self) -> &'static str {
        BANK_CODE
    }

    fn claim_all(&self) -> &'static [&'static str] {
        CLAIM_ALL
    }

    fn anchor_res(&self) -> Vec<&'static Regex> {
        vec![&ANCHOR_CLASSIC_RE, &ANCHOR_FI_RE]
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

    fn classic() -> String {
        concat!(
            "The Federal Bank Ltd.\n",
            "Statement of Account for the period 2026-04-01 to 2026-04-30\n",
            "Account Number : 99990100001234\n",
            "Type of Account : Savings Account\n",
            "Date Value Date Particulars Tran Type Tran ID Withdrawals Deposits Balance DR/CR\n",
            "Opening Balance 1,00,000.00 Cr\n",
            "08-APR-2026 08-APR-2026 TO ECM/600000000001 TFR S10000001 5,000.00 95,000.00 Cr\n",
            "/EXAMPLEMERCHANT \\EXAM/07:17\n",
            "11-APR-2026 11-APR-2026 UPI IN/600000000002 TFR S10000002 50,000.00 1,45,000.00 Cr\n",
            "/payer@example/Payment/0000\n",
            "13-APR-2026 13-APR-2026 POS/600000000003/EXAMPLESTORE TFR S10000003 45,000.00 1,00,000.00 Cr\n",
            "\\EXAM/12:34\n",
            "GRAND TOTAL 50,000.00 50,000.00"
        )
        .to_string()
    }

    fn fi() -> String {
        concat!(
            "The Federal Bank Ltd. NEO BANKING- EPIFI\n",
            "Statement of account for the period of 08/04/2026 to 07/05/2026\n",
            "Account Number: XXXXX4222\n",
            "Value Tran Cheque Dr/\n",
            "Opening Balance OPNBAL 1,00,000.00 CR\n",
            "08/04/2026 08/04/2026 TO ECM/600000000001/EXAMPLE TFR S10000001 5000 0 95,000.00 CR\n",
            "MERCHANT \\EXAM\n",
            "20/04/2026 20/04/2026 UPI IN/600000000002/payer TFR S10000002 0 50000 1,45,000.00 CR\n",
            "Payment f/0000"
        )
        .to_string()
    }

    #[test]
    fn classic_direction_from_delta_despite_every_cr_marker() {
        let full_text = classic();
        let st = read_ledger_lines(&FederalBankReader, &lines_of(&full_text), &full_text, &[]);
        assert_eq!(st.lines.len(), 3, "{:?}", st.errored_lines);
        // Every balance prints "Cr", yet direction follows the delta.
        let dirs: Vec<_> = st.lines.iter().map(|l| l.direction).collect();
        assert_eq!(
            dirs,
            [Direction::Debit, Direction::Credit, Direction::Debit]
        );
        assert_eq!(st.lines[1].amount, dec!(50000.00));
        // The S-prefixed Tran ID is the serial and is kept out of the description.
        let l0 = st.lines[0].ledger.as_ref().unwrap();
        assert_eq!(l0.serial, "S10000001");
        assert_eq!(st.lines[0].description_raw, "TO ECM/600000000001 TFR");
        assert!(!st.lines[0].description_raw.contains("S10000001"));
        assert_eq!(st.printed_opening_balance, Some(dec!(100000.00)));
        assert_eq!(st.printed_closing_balance, Some(dec!(100000.00)));
        assert_eq!(st.card_last4.as_deref(), Some("1234"));
        assert_eq!(st.period_start, chrono::NaiveDate::from_ymd_opt(2026, 4, 1));
        assert_eq!(st.period_end, chrono::NaiveDate::from_ymd_opt(2026, 4, 30));
    }

    #[test]
    fn grand_total_line_is_not_a_transaction() {
        // The GRAND TOTAL line carries two money tokens but no leading date and no Cr/Dr
        // suffix, so it never matches an anchor.
        let full_text = classic();
        let st = read_ledger_lines(&FederalBankReader, &lines_of(&full_text), &full_text, &[]);
        assert_eq!(st.lines.len(), 3);
        assert!(st.errored_lines.is_empty());
    }

    #[test]
    fn fi_two_column_whole_number_amounts() {
        let full_text = fi();
        let st = read_ledger_lines(&FederalBankReader, &lines_of(&full_text), &full_text, &[]);
        assert_eq!(st.lines.len(), 2, "{:?}", st.errored_lines);
        assert_eq!(st.lines[0].direction, Direction::Debit); // withdrawal side
        assert_eq!(st.lines[0].amount, dec!(5000));
        assert_eq!(st.lines[1].direction, Direction::Credit); // deposit side
        assert_eq!(st.lines[1].amount, dec!(50000));
        assert_eq!(st.card_last4.as_deref(), Some("4222"));
        assert_eq!(st.printed_opening_balance, Some(dec!(100000.00)));
    }

    #[test]
    fn claims_accepts_federal_savings_and_rejects_scapia_credit_card() {
        assert!(claims_ledger(&FederalBankReader, &classic(), BANK_CODE));
        assert!(claims_ledger(&FederalBankReader, &fi(), BANK_CODE));
        // A Scapia/Federal credit-card statement lacks the "Statement of Account" header.
        let cc = "Scapia by Federal Bank\nXXXXXXXXXXXX4836 20Apr2026-19May2026\n";
        assert!(!claims_ledger(&FederalBankReader, cc, BANK_CODE));
        assert!(!claims_ledger(&FederalBankReader, &classic(), "ICICI"));
    }
}
