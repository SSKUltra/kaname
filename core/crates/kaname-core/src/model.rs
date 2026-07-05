//! Core domain types shared across every Kaname platform.

use chrono::NaiveDate;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};

/// Whether money moved out of (`Debit`) or into (`Credit`) an account.
///
/// For bank-account (savings/current) statements the direction is derived from the
/// running-balance delta; for credit-card statements it comes from an explicit
/// `Dr`/`Cr` marker. Mirrors the polarity model in the web engine.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum Direction {
    Debit,
    Credit,
}

/// A single normalized financial transaction produced by a statement reader.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct Transaction {
    pub date: NaiveDate,
    pub description: String,
    pub amount: Decimal,
    pub direction: Direction,
}

impl Transaction {
    /// Construct a transaction. `amount` is always the absolute magnitude; the sign
    /// is carried by [`Direction`] so we never mix polarity conventions.
    pub fn new(
        date: NaiveDate,
        description: impl Into<String>,
        amount: Decimal,
        direction: Direction,
    ) -> Self {
        Self {
            date,
            description: description.into(),
            amount,
            direction,
        }
    }

    /// Signed amount: negative for debits, positive for credits.
    pub fn signed_amount(&self) -> Decimal {
        match self.direction {
            Direction::Debit => -self.amount,
            Direction::Credit => self.amount,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    #[test]
    fn signed_amount_respects_direction() {
        let d = NaiveDate::from_ymd_opt(2026, 7, 4).unwrap();
        let debit = Transaction::new(d, "Swiggy", dec!(250.00), Direction::Debit);
        let credit = Transaction::new(d, "Salary", dec!(1000.00), Direction::Credit);
        assert_eq!(debit.signed_amount(), dec!(-250.00));
        assert_eq!(credit.signed_amount(), dec!(1000.00));
    }
}
