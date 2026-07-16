//! Balance-chain integrity check for bank-account statements, ported from the web
//! engine's `balance_chain.py`.
//!
//! The trust signal for a bank-account statement. Because direction is derived from the
//! running-balance delta, the credit-card opening→closing identity
//! (`Σdebits − Σcredits ≡ closing − opening`) is **tautological** — it can never fail.
//! This check instead treats the printed **amount** and the printed **balance** as two
//! *independent* numbers and verifies, row by row, that each amount equals its balance
//! delta (within a ₹1.00 rounding tolerance):
//!
//! - contiguous chain + every `amount == |curr_balance − prev_balance|` → [`ChainStatus::Reconciled`]
//! - a dropped/misparsed row, or a row-1 direction that fell back to x-position or a
//!   provisional guess → [`ChainStatus::NeedsReview`], with the suspects recorded.
//!
//! It runs over **all read lines** (before dedup) and is pure (no DB, no clock).

use rust_decimal::Decimal;

use crate::statement::base::{DirectionSource, ParsedStatement, ParsedTransaction};

/// Whether a bank-account statement's running-balance chain reconciles.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ChainStatus {
    Reconciled,
    NeedsReview,
}

/// One row whose printed amount did not reconcile with its balance delta (or that was
/// missing a running balance), recorded for review.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Suspect {
    /// 1-based row number within the statement.
    pub row: u32,
    pub serial: Option<String>,
    pub amount: Decimal,
    pub reason: String,
}

/// The result of a balance-chain check: the status plus an audit detail payload.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ChainResult {
    pub status: ChainStatus,
    pub checked_rows: u32,
    pub suspect_count: u32,
    /// Suspect rows, capped at [`MAX_SUSPECTS`] for a bounded payload.
    pub suspects: Vec<Suspect>,
    /// True when the first row's direction fell back to x-position/provisional (no
    /// reliable predecessor balance) — on its own enough to force `NeedsReview`.
    pub row1_direction_fallback: bool,
    pub derived_opening_balance: Option<Decimal>,
    pub derived_closing_balance: Option<Decimal>,
    /// Set only for the empty-statement case; `None` otherwise.
    pub reason: Option<String>,
}

/// How many suspect rows to record in the detail payload (audit, not unbounded).
pub const MAX_SUSPECTS: usize = 20;

fn is_fallback(source: DirectionSource) -> bool {
    matches!(
        source,
        DirectionSource::Row1XPosition | DirectionSource::Row1Provisional
    )
}

fn row1_fallback(lines: &[ParsedTransaction]) -> bool {
    lines
        .first()
        .and_then(|line| line.ledger.as_ref())
        .is_some_and(|ledger| is_fallback(ledger.direction_source))
}

/// Verify the running-balance chain of `statement` (over all read lines).
pub fn check(statement: &ParsedStatement) -> ChainResult {
    let lines = &statement.lines;
    if lines.is_empty() {
        return ChainResult {
            status: ChainStatus::NeedsReview,
            checked_rows: 0,
            suspect_count: 0,
            suspects: Vec::new(),
            row1_direction_fallback: false,
            derived_opening_balance: statement.printed_opening_balance,
            derived_closing_balance: statement.printed_closing_balance,
            reason: Some("no parsed transactions".to_string()),
        };
    }

    // Rupee-rounding tolerance for the amount-vs-delta comparison (1.00).
    let tolerance = Decimal::new(100, 2);
    let mut suspects: Vec<Suspect> = Vec::new();
    // Independent re-derivation: start from the printed/derived opening balance and walk
    // the chain, comparing each printed amount to its own balance delta.
    let mut prev: Option<Decimal> = statement.printed_opening_balance;

    for (i, line) in lines.iter().enumerate() {
        let row = (i + 1) as u32;
        let ledger = line.ledger.as_ref();
        let Some(ledger) = ledger else {
            suspects.push(suspect(row, line, "missing running balance"));
            continue;
        };
        let balance = ledger.balance;

        // Skip the amount-vs-delta check for a row-1 whose opening balance was derived
        // FROM the row itself (x-position / provisional) — that delta is tautological;
        // the fallback is flagged separately below.
        let derived_row1 = i == 0 && is_fallback(ledger.direction_source);
        if let Some(prev_balance) = prev {
            if !derived_row1 {
                let delta = balance - prev_balance;
                if (line.amount - delta.abs()).abs() > tolerance {
                    suspects.push(suspect(
                        row,
                        line,
                        &format!("amount {} != |balance delta| {}", line.amount, delta.abs()),
                    ));
                }
            }
        }
        prev = Some(balance);
    }

    let fallback = row1_fallback(lines);
    let status = if suspects.is_empty() && !fallback {
        ChainStatus::Reconciled
    } else {
        ChainStatus::NeedsReview
    };

    ChainResult {
        status,
        checked_rows: lines.len() as u32,
        suspect_count: suspects.len() as u32,
        suspects: suspects.into_iter().take(MAX_SUSPECTS).collect(),
        row1_direction_fallback: fallback,
        derived_opening_balance: statement.printed_opening_balance,
        derived_closing_balance: statement.printed_closing_balance,
        reason: None,
    }
}

fn suspect(row: u32, line: &ParsedTransaction, reason: &str) -> Suspect {
    Suspect {
        row,
        serial: line.ledger.as_ref().map(|l| l.serial.clone()),
        amount: line.amount,
        reason: reason.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Direction;
    use crate::statement::base::LedgerMetadata;
    use chrono::NaiveDate;
    use rust_decimal_macros::dec;

    fn row(
        amount: Decimal,
        balance: Decimal,
        delta: Option<Decimal>,
        source: DirectionSource,
    ) -> ParsedTransaction {
        let matches = delta.is_some_and(|d| amount == d.abs());
        ParsedTransaction {
            value_date: NaiveDate::from_ymd_opt(2025, 6, 16).unwrap(),
            amount,
            direction: Direction::Debit,
            currency: "INR".to_string(),
            description_raw: "x".to_string(),
            bank_code: "ICICI".to_string(),
            ledger: Some(LedgerMetadata {
                balance,
                balance_delta: delta,
                amount_matches_delta: matches,
                is_suspect: !matches,
                direction_source: source,
                serial: "1".to_string(),
            }),
        }
    }

    fn statement(lines: Vec<ParsedTransaction>, opening: Decimal) -> ParsedStatement {
        let mut st = ParsedStatement::new("ICICI");
        st.printed_opening_balance = Some(opening);
        st.printed_closing_balance = lines
            .last()
            .and_then(|l| l.ledger.as_ref())
            .map(|l| l.balance);
        st.lines = lines;
        st
    }

    #[test]
    fn clean_opening_anchored_chain_reconciles() {
        let lines = vec![
            row(
                dec!(5000.00),
                dec!(95000.00),
                Some(dec!(-5000.00)),
                DirectionSource::OpeningBalance,
            ),
            row(
                dec!(2000.00),
                dec!(93000.00),
                Some(dec!(-2000.00)),
                DirectionSource::BalanceDelta,
            ),
        ];
        let result = check(&statement(lines, dec!(100000.00)));
        assert_eq!(result.status, ChainStatus::Reconciled);
        assert_eq!(result.suspect_count, 0);
        assert!(!result.row1_direction_fallback);
        assert_eq!(result.checked_rows, 2);
    }

    #[test]
    fn amount_not_matching_delta_is_a_suspect_but_row_is_still_present() {
        // Second row's printed amount (999) disagrees with its balance delta (2000).
        let lines = vec![
            row(
                dec!(5000.00),
                dec!(95000.00),
                Some(dec!(-5000.00)),
                DirectionSource::OpeningBalance,
            ),
            row(
                dec!(999.00),
                dec!(93000.00),
                Some(dec!(-2000.00)),
                DirectionSource::BalanceDelta,
            ),
        ];
        let st = statement(lines, dec!(100000.00));
        let result = check(&st);
        assert_eq!(result.status, ChainStatus::NeedsReview);
        assert_eq!(result.suspect_count, 1);
        assert_eq!(result.suspects[0].row, 2);
        // The suspect row was not dropped from the statement itself.
        assert_eq!(st.lines.len(), 2);
    }

    #[test]
    fn within_one_rupee_tolerance_still_reconciles() {
        // Amount 5000.50 vs |delta| 5000.00 → 0.50 ≤ ₹1.00 tolerance.
        let lines = vec![row(
            dec!(5000.50),
            dec!(95000.00),
            Some(dec!(-5000.00)),
            DirectionSource::OpeningBalance,
        )];
        let result = check(&statement(lines, dec!(100000.00)));
        assert_eq!(result.status, ChainStatus::Reconciled);
    }

    #[test]
    fn row1_provisional_fallback_forces_needs_review() {
        let lines = vec![row(
            dec!(5000.00),
            dec!(95000.00),
            Some(dec!(-5000.00)),
            DirectionSource::Row1Provisional,
        )];
        // Opening derived from the row itself; the amount check is skipped, but the
        // fallback alone forces NEEDS_REVIEW.
        let mut st = statement(lines, dec!(100000.00));
        st.printed_opening_balance = Some(dec!(100000.00));
        let result = check(&st);
        assert_eq!(result.status, ChainStatus::NeedsReview);
        assert!(result.row1_direction_fallback);
        assert_eq!(result.suspect_count, 0);
    }

    #[test]
    fn empty_statement_needs_review_with_reason() {
        let result = check(&ParsedStatement::new("ICICI"));
        assert_eq!(result.status, ChainStatus::NeedsReview);
        assert_eq!(result.checked_rows, 0);
        assert_eq!(result.reason.as_deref(), Some("no parsed transactions"));
    }
}
