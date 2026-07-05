//! Deterministic de-duplication helpers.
//!
//! The same transaction is frequently seen across sources (e.g. a bank statement and
//! a card statement, or two overlapping statement PDFs). We compute a stable
//! fingerprint so cross-source duplicates collapse to one row — the on-device
//! equivalent of the web engine's `*_cross_source_dedup` behaviour.

use crate::model::Transaction;

/// Collapse runs of whitespace and upper-case a merchant/narration string so that
/// cosmetically different renderings of the same merchant produce an identical key.
pub fn normalize_description(raw: &str) -> String {
    raw.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_uppercase()
}

/// A stable, deterministic fingerprint for cross-source duplicate detection.
///
/// Amounts are [`rust_decimal::Decimal::normalize`]d so `250.00` and `250.0` match.
pub fn dedup_fingerprint(txn: &Transaction) -> String {
    format!(
        "{}|{}|{}|{:?}",
        txn.date,
        txn.amount.normalize(),
        normalize_description(&txn.description),
        txn.direction
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Direction, Transaction};
    use chrono::NaiveDate;
    use rust_decimal_macros::dec;

    #[test]
    fn normalizes_whitespace_and_case() {
        assert_eq!(normalize_description("  Swiggy   Order  "), "SWIGGY ORDER");
    }

    #[test]
    fn same_txn_across_sources_shares_fingerprint() {
        let d = NaiveDate::from_ymd_opt(2026, 7, 4).unwrap();
        let from_bank = Transaction::new(d, "Swiggy  Order", dec!(250.00), Direction::Debit);
        let from_card = Transaction::new(d, "SWIGGY ORDER", dec!(250.0), Direction::Debit);
        assert_eq!(dedup_fingerprint(&from_bank), dedup_fingerprint(&from_card));
    }

    #[test]
    fn different_direction_is_not_a_duplicate() {
        let d = NaiveDate::from_ymd_opt(2026, 7, 4).unwrap();
        let debit = Transaction::new(d, "ACME", dec!(100.00), Direction::Debit);
        let credit = Transaction::new(d, "ACME", dec!(100.00), Direction::Credit);
        assert_ne!(dedup_fingerprint(&debit), dedup_fingerprint(&credit));
    }
}
