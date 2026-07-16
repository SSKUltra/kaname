//! UniFFI boundary: custom-type bridges and the exported engine functions that carry
//! the real domain (`Transaction`) across to Swift.
//!
//! Money (`rust_decimal::Decimal`) and dates (`chrono::NaiveDate`) cross the FFI as
//! exact `String`s (base-10 / ISO-8601) — never floats — so no precision is lost
//! (constitution: money is never a float). The functions here are pure and
//! deterministic: no clock, no locale, no network, no global state.

use crate::model::Transaction;
use crate::normalize_description;
use crate::statement::balance_chain::{check, ChainResult};
use crate::statement::base::{ParsedStatement, Word};
use crate::statement::federal::FederalReader;
use crate::statement::hdfc_bank::HdfcBankReader;
use crate::statement::icici::IciciReader;
use crate::statement::icici_bank::IciciBankReader;
use crate::statement::ledger_reader::{claims_ledger, read_ledger_lines};
use crate::statement::line_reader::{claims, read_lines};
use crate::statement::sbi::SbiReader;
use crate::statement::yes::YesReader;
use chrono::NaiveDate;
use rust_decimal::Decimal;

// Money crosses the FFI as an exact base-10 string and surfaces in Swift as a native
// Foundation.Decimal (see uniffi.toml) — never a float.
uniffi::custom_type!(Decimal, String, {
    remote,
    lower: |d| d.to_string(),
    try_lift: |s| s.parse::<Decimal>().map_err(Into::into),
});

// A calendar date crosses as an ISO-8601 (YYYY-MM-DD) string.
uniffi::custom_type!(NaiveDate, String, {
    remote,
    lower: |d| d.format("%Y-%m-%d").to_string(),
    try_lift: |s| NaiveDate::parse_from_str(&s, "%Y-%m-%d").map_err(Into::into),
});

/// Normalize a transaction's `description` (Unicode uppercase + internal-whitespace
/// collapse) while preserving `date`, `amount`, and `direction` exactly. Pure and
/// deterministic — the typed round-trip that proves structured data crosses the
/// Rust↔Swift boundary faithfully.
#[uniffi::export]
pub fn normalize_transaction(input: Transaction) -> Transaction {
    Transaction {
        date: input.date,
        description: normalize_description(&input.description),
        amount: input.amount,
        direction: input.direction,
    }
}

/// Parse an ICICI credit-card statement from already-extracted text (lines + full
/// text). The platform (iOS PDFKit) extracts the text natively; the engine never opens
/// a PDF. Pure and total — a row that matches the shape but whose fields will not parse
/// is captured in `errored_lines`, never surfaced as an error.
#[uniffi::export]
pub fn read_icici_statement(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_lines(&IciciReader, &lines, &full_text)
}

/// Whether `full_text` is recognizably an ICICI credit-card statement (the
/// document-plausibility gate); `false` for other issuers.
#[uniffi::export]
pub fn icici_claims(full_text: String) -> bool {
    claims(&IciciReader, &full_text, "ICICI")
}

/// Parse an HDFC credit-card statement from already-extracted text (both the year-end
/// and monthly layouts, auto-selected). Same purity/robustness contract as
/// [`read_icici_statement`].
#[uniffi::export]
pub fn read_hdfc_statement(lines: Vec<String>, full_text: String) -> ParsedStatement {
    crate::statement::hdfc::read_hdfc_statement(&lines, &full_text)
}

/// Whether `full_text` is recognizably an HDFC credit-card statement; `false` for other
/// issuers.
#[uniffi::export]
pub fn hdfc_claims(full_text: String) -> bool {
    crate::statement::hdfc::hdfc_claims(&full_text)
}

/// Parse an SBI Card credit-card statement from already-extracted text. Same
/// purity/robustness contract as [`read_icici_statement`].
#[uniffi::export]
pub fn read_sbi_statement(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_lines(&SbiReader, &lines, &full_text)
}

/// Whether `full_text` is recognizably an SBI Card statement; `false` for other issuers.
#[uniffi::export]
pub fn sbi_claims(full_text: String) -> bool {
    claims(&SbiReader, &full_text, "SBI_CARD")
}

/// Parse a Yes Bank (Kiwi) credit-card statement from already-extracted text. Same
/// purity/robustness contract as [`read_icici_statement`].
#[uniffi::export]
pub fn read_yes_statement(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_lines(&YesReader, &lines, &full_text)
}

/// Whether `full_text` is recognizably a Yes Bank statement; `false` for other issuers.
#[uniffi::export]
pub fn yes_claims(full_text: String) -> bool {
    claims(&YesReader, &full_text, "YES")
}

/// Parse a Scapia / Federal Bank credit-card statement from already-extracted text. Same
/// purity/robustness contract as [`read_icici_statement`].
#[uniffi::export]
pub fn read_federal_statement(lines: Vec<String>, full_text: String) -> ParsedStatement {
    read_lines(&FederalReader, &lines, &full_text)
}

/// Whether `full_text` is recognizably a Scapia / Federal Bank statement; `false` for
/// other issuers.
#[uniffi::export]
pub fn federal_claims(full_text: String) -> bool {
    claims(&FederalReader, &full_text, "FEDERAL")
}

/// Parse an ICICI savings/current bank-account statement from already-extracted text.
///
/// Bank-account statements are running-balance ledgers with no `Dr`/`Cr` marker, so
/// direction comes from the balance delta. `first_row_words` carries the first anchor
/// row's word geometry (text + x-extents), extracted natively by the platform (iOS
/// PDFKit), for the row-1 bootstrap when no opening balance is printed; pass an empty
/// list when unavailable. Same purity/robustness contract as [`read_icici_statement`].
#[uniffi::export]
pub fn read_icici_bank_statement(
    lines: Vec<String>,
    full_text: String,
    first_row_words: Vec<Word>,
) -> ParsedStatement {
    read_ledger_lines(&IciciBankReader, &lines, &full_text, &first_row_words)
}

/// Whether `full_text` is recognizably an ICICI *bank-account* (savings/current)
/// statement; `false` for other issuers and for an ICICI *credit-card* statement.
#[uniffi::export]
pub fn icici_bank_claims(full_text: String) -> bool {
    claims_ledger(&IciciBankReader, &full_text, "ICICI")
}

/// Verify a bank-account statement's running-balance chain: that each printed amount
/// equals its balance delta (within ₹1.00) and the first row's direction was reliably
/// anchored. Reports `Reconciled` or `NeedsReview` with the suspect rows. Pure.
#[uniffi::export]
pub fn check_balance_chain(statement: ParsedStatement) -> ChainResult {
    check(&statement)
}

/// Parse an HDFC Bank savings/current statement from already-extracted text (both the
/// compact and detailed layouts, auto-selected). `first_row_words` carries the first
/// anchor row's word geometry for the row-1 bootstrap; pass an empty list when
/// unavailable. Same purity/robustness contract as [`read_icici_bank_statement`].
#[uniffi::export]
pub fn read_hdfc_bank_statement(
    lines: Vec<String>,
    full_text: String,
    first_row_words: Vec<Word>,
) -> ParsedStatement {
    read_ledger_lines(&HdfcBankReader, &lines, &full_text, &first_row_words)
}

/// Whether `full_text` is recognizably an HDFC *bank-account* (savings/current)
/// statement; `false` for other issuers and for an HDFC *credit-card* statement.
#[uniffi::export]
pub fn hdfc_bank_claims(full_text: String) -> bool {
    claims_ledger(&HdfcBankReader, &full_text, "HDFC")
}

#[cfg(test)]
mod tests {
    use super::normalize_transaction;
    use crate::model::{Direction, Transaction};
    use chrono::NaiveDate;
    use rust_decimal_macros::dec;

    fn date() -> NaiveDate {
        NaiveDate::from_ymd_opt(2026, 7, 4).unwrap()
    }

    #[test]
    fn normalizes_description_and_preserves_the_rest() {
        let input = Transaction::new(date(), "  Café  René ", dec!(250.00), Direction::Debit);
        let out = normalize_transaction(input.clone());
        assert_eq!(out.description, "CAFÉ RENÉ");
        assert_eq!(out.date, input.date);
        assert_eq!(out.amount, input.amount);
        assert_eq!(out.direction, input.direction);
    }

    #[test]
    fn preserves_boundary_amounts_exactly() {
        for amount in [dec!(0), dec!(999999999999.99), dec!(0.000000001)] {
            let out =
                normalize_transaction(Transaction::new(date(), "x", amount, Direction::Credit));
            assert_eq!(out.amount, amount);
        }
    }

    #[test]
    fn is_deterministic() {
        let input = Transaction::new(date(), "swiggy  order", dec!(12.50), Direction::Debit);
        assert_eq!(
            normalize_transaction(input.clone()),
            normalize_transaction(input)
        );
    }
}
