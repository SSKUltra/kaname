//! Credit-card statement reconciliation, ported from the web engine's `reconciliation.py`.
//!
//! The trust signal for a credit-card statement — the counterpart to the bank-account
//! [`crate::statement::balance_chain`] check. After a statement is read, it compares the
//! transactions the engine extracted against the statement's own printed figures, so a
//! mis-parse or a dropped row is caught before the data is trusted. Over **all** read rows,
//! using exact [`Decimal`] money, it sums the debit rows and the credit rows and classifies the
//! run in three tiers:
//!
//! 1. **Primary** — against the printed per-statement debit/credit totals (within a ₹1.00
//!    tolerance): every printed total present within tolerance → [`ReconcileStatus::Reconciled`],
//!    else [`ReconcileStatus::NeedsReview`].
//! 2. **Fallback** — when no printed totals are present but both a printed opening and closing
//!    balance are, the read balance change (`Σdebits − Σcredits`) is compared to the printed
//!    change (`closing − opening`) within the same tolerance.
//! 3. **Neutral** — no printed totals at all → `status: None`: a neutral "not reconciled (no
//!    balance)" outcome, explicitly distinct from a mismatch (a statement whose totals could not
//!    be extracted is an *unknown*, never a *failure*).
//!
//! It runs over **all** read lines (before dedup), never drops or mutates a row, and is pure
//! (no DB, no clock, no network).

use rust_decimal::Decimal;

use crate::model::Direction;
use crate::statement::base::ParsedStatement;

/// Whether a credit-card statement's read rows reconcile with its printed figures. Mirrors
/// [`crate::statement::balance_chain::ChainStatus`]; carried as an `Option` in
/// [`ReconcileResult`] so the neutral "no printed totals" outcome (`None`) stays distinct from
/// `NeedsReview`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ReconcileStatus {
    Reconciled,
    NeedsReview,
}

/// The result of a reconciliation check: the verdict plus a typed audit detail explaining it.
///
/// `status` is `None` for the neutral "not reconciled (no balance)" outcome — distinct from
/// `Some(NeedsReview)`. `read_debits`/`read_credits` are set in **every** outcome; the remaining
/// fields are set only by the tier that produced the verdict (printed_* on the primary path,
/// `*_balance_change` on the fallback path, `reason` on the neutral path).
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ReconcileResult {
    /// `Some(Reconciled)` / `Some(NeedsReview)`, or `None` for the neutral "no balance" outcome.
    pub status: Option<ReconcileStatus>,
    /// Sum of the read DEBIT-direction amounts (always set; `0` when there are none).
    pub read_debits: Decimal,
    /// Sum of the read CREDIT-direction amounts (always set; `0` when there are none).
    pub read_credits: Decimal,
    /// The printed debit total compared against `read_debits` (primary path); else `None`.
    pub printed_debits: Option<Decimal>,
    /// The printed credit total compared against `read_credits` (primary path); else `None`.
    pub printed_credits: Option<Decimal>,
    /// The printed balance change `closing − opening` (fallback path); else `None`.
    pub expected_balance_change: Option<Decimal>,
    /// The read balance change `read_debits − read_credits` (fallback path); else `None`.
    pub computed_balance_change: Option<Decimal>,
    /// Set only for the neutral outcome (`"no printed totals extracted"`); `None` otherwise.
    pub reason: Option<String>,
}

fn sum_by_direction(statement: &ParsedStatement, direction: Direction) -> Decimal {
    statement
        .lines
        .iter()
        .filter(|line| line.direction == direction)
        .map(|line| line.amount)
        .sum()
}

/// Reconcile a credit-card statement's read rows against its own printed totals (or, as a
/// fallback, its opening→closing balance change). Pure and total — never panics, never mutates
/// `statement`, and always returns one of the three outcomes.
pub fn reconcile(statement: &ParsedStatement) -> ReconcileResult {
    // Rupee-rounding tolerance for the sum-vs-printed comparison (1.00) — the same value and the
    // same inclusive `<=` comparison the balance-chain check uses.
    let tolerance = Decimal::new(100, 2);
    let read_debits = sum_by_direction(statement, Direction::Debit);
    let read_credits = sum_by_direction(statement, Direction::Credit);

    let printed_debits = statement.printed_total_debits;
    let printed_credits = statement.printed_total_credits;

    // Primary — against the printed per-statement debit/credit totals. Each present total must be
    // within tolerance of its read sum; an absent total is simply not checked.
    if printed_debits.is_some() || printed_credits.is_some() {
        let debits_ok = printed_debits.is_none_or(|p| (read_debits - p).abs() <= tolerance);
        let credits_ok = printed_credits.is_none_or(|p| (read_credits - p).abs() <= tolerance);
        let status = if debits_ok && credits_ok {
            ReconcileStatus::Reconciled
        } else {
            ReconcileStatus::NeedsReview
        };
        return ReconcileResult {
            status: Some(status),
            read_debits,
            read_credits,
            printed_debits,
            printed_credits,
            expected_balance_change: None,
            computed_balance_change: None,
            reason: None,
        };
    }

    // Fallback — reconcile against the opening→closing balance change (debits raise the balance
    // owed, credits lower it), used only when both balances are printed.
    if let (Some(opening), Some(closing)) = (
        statement.printed_opening_balance,
        statement.printed_closing_balance,
    ) {
        let expected = closing - opening;
        let computed = read_debits - read_credits;
        let status = if (computed - expected).abs() <= tolerance {
            ReconcileStatus::Reconciled
        } else {
            ReconcileStatus::NeedsReview
        };
        return ReconcileResult {
            status: Some(status),
            read_debits,
            read_credits,
            printed_debits: None,
            printed_credits: None,
            expected_balance_change: Some(expected),
            computed_balance_change: Some(computed),
            reason: None,
        };
    }

    // Neutral — no printed totals at all: "not reconciled (no balance)", distinct from a mismatch.
    ReconcileResult {
        status: None,
        read_debits,
        read_credits,
        printed_debits: None,
        printed_credits: None,
        expected_balance_change: None,
        computed_balance_change: None,
        reason: Some("no printed totals extracted".to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::statement::base::ParsedTransaction;
    use chrono::NaiveDate;
    use rust_decimal_macros::dec;

    fn line(amount: Decimal, direction: Direction) -> ParsedTransaction {
        ParsedTransaction {
            value_date: NaiveDate::from_ymd_opt(2026, 5, 1).unwrap(),
            amount,
            direction,
            currency: "INR".to_string(),
            description_raw: "MERCHANT".to_string(),
            bank_code: "YES".to_string(),
            ledger: None,
        }
    }

    fn statement(lines: Vec<ParsedTransaction>) -> ParsedStatement {
        let mut st = ParsedStatement::new("YES");
        st.lines = lines;
        st
    }

    #[test]
    fn reconciled_when_both_totals_match() {
        let mut st = statement(vec![
            line(dec!(100.00), Direction::Debit),
            line(dec!(250.50), Direction::Debit),
            line(dec!(900.00), Direction::Credit),
        ]);
        st.printed_total_debits = Some(dec!(350.50));
        st.printed_total_credits = Some(dec!(900.00));
        let r = reconcile(&st);
        assert_eq!(r.status, Some(ReconcileStatus::Reconciled));
        assert_eq!(r.read_debits, dec!(350.50));
        assert_eq!(r.read_credits, dec!(900.00));
        assert_eq!(r.printed_debits, Some(dec!(350.50)));
        assert_eq!(r.printed_credits, Some(dec!(900.00)));
    }

    #[test]
    fn needs_review_when_debits_mismatch_with_detail() {
        let mut st = statement(vec![
            line(dec!(100.00), Direction::Debit),
            line(dec!(250.50), Direction::Debit),
        ]);
        st.printed_total_debits = Some(dec!(999.99));
        let r = reconcile(&st);
        assert_eq!(r.status, Some(ReconcileStatus::NeedsReview));
        assert_eq!(r.read_debits, dec!(350.50));
        assert_eq!(r.printed_debits, Some(dec!(999.99)));
    }

    #[test]
    fn half_rupee_difference_is_within_tolerance() {
        let mut st = statement(vec![
            line(dec!(100.00), Direction::Debit),
            line(dec!(250.00), Direction::Debit),
        ]);
        st.printed_total_debits = Some(dec!(350.50)); // 0.50 < ₹1.00
        assert_eq!(reconcile(&st).status, Some(ReconcileStatus::Reconciled));
    }

    #[test]
    fn exactly_one_rupee_is_within_tolerance() {
        let mut st = statement(vec![line(dec!(100.00), Direction::Debit)]);
        st.printed_total_debits = Some(dec!(101.00)); // exactly 1.00 off → within
        assert_eq!(reconcile(&st).status, Some(ReconcileStatus::Reconciled));
    }

    #[test]
    fn just_over_one_rupee_needs_review() {
        let mut st = statement(vec![line(dec!(100.00), Direction::Debit)]);
        st.printed_total_debits = Some(dec!(101.01)); // 1.01 off → out of tolerance
        assert_eq!(reconcile(&st).status, Some(ReconcileStatus::NeedsReview));
    }

    #[test]
    fn only_one_total_present_ignores_the_absent_side() {
        // Only a credit total is printed; the (large) read debits are not checked.
        let mut st = statement(vec![
            line(dec!(5000.00), Direction::Debit),
            line(dec!(900.00), Direction::Credit),
        ]);
        st.printed_total_credits = Some(dec!(900.00));
        let r = reconcile(&st);
        assert_eq!(r.status, Some(ReconcileStatus::Reconciled));
        assert_eq!(r.printed_debits, None);
        assert_eq!(r.printed_credits, Some(dec!(900.00)));
    }

    #[test]
    fn both_present_one_mismatch_needs_review() {
        let mut st = statement(vec![
            line(dec!(100.00), Direction::Debit),
            line(dec!(900.00), Direction::Credit),
        ]);
        st.printed_total_debits = Some(dec!(100.00));
        st.printed_total_credits = Some(dec!(950.00)); // off by 50
        assert_eq!(reconcile(&st).status, Some(ReconcileStatus::NeedsReview));
    }

    #[test]
    fn balance_change_fallback_reconciles() {
        // Debits raise the balance owed, credits lower it: +300 == 1300 − 1000.
        let mut st = statement(vec![
            line(dec!(500.00), Direction::Debit),
            line(dec!(200.00), Direction::Credit),
        ]);
        st.printed_opening_balance = Some(dec!(1000.00));
        st.printed_closing_balance = Some(dec!(1300.00));
        let r = reconcile(&st);
        assert_eq!(r.status, Some(ReconcileStatus::Reconciled));
        assert_eq!(r.expected_balance_change, Some(dec!(300.00)));
        assert_eq!(r.computed_balance_change, Some(dec!(300.00)));
    }

    #[test]
    fn balance_change_fallback_flags_mismatch() {
        let mut st = statement(vec![
            line(dec!(500.00), Direction::Debit),
            line(dec!(200.00), Direction::Credit),
        ]);
        st.printed_opening_balance = Some(dec!(1000.00));
        st.printed_closing_balance = Some(dec!(1500.00)); // +500 != +300
        assert_eq!(reconcile(&st).status, Some(ReconcileStatus::NeedsReview));
    }

    #[test]
    fn printed_totals_take_precedence_over_balance_fallback() {
        // Both printed totals and balances present → the primary path runs; the fallback fields
        // stay None even though the balances alone would fail.
        let mut st = statement(vec![line(dec!(100.00), Direction::Debit)]);
        st.printed_total_debits = Some(dec!(100.00));
        st.printed_opening_balance = Some(dec!(1000.00));
        st.printed_closing_balance = Some(dec!(9999.00));
        let r = reconcile(&st);
        assert_eq!(r.status, Some(ReconcileStatus::Reconciled));
        assert_eq!(r.expected_balance_change, None);
        assert_eq!(r.computed_balance_change, None);
    }

    #[test]
    fn one_balance_only_is_neutral() {
        let mut st = statement(vec![line(dec!(100.00), Direction::Debit)]);
        st.printed_opening_balance = Some(dec!(1000.00)); // closing missing
        assert_eq!(reconcile(&st).status, None);
    }

    #[test]
    fn no_printed_totals_is_neutral_none_distinct_from_needs_review() {
        let st = statement(vec![line(dec!(100.00), Direction::Debit)]);
        let r = reconcile(&st);
        assert_eq!(r.status, None);
        assert_ne!(r.status, Some(ReconcileStatus::NeedsReview));
        assert_eq!(r.reason.as_deref(), Some("no printed totals extracted"));
    }

    #[test]
    fn empty_rows_sum_to_zero_and_reconcile_against_zero_totals() {
        let mut st = statement(vec![]);
        st.printed_total_debits = Some(dec!(0.00));
        st.printed_total_credits = Some(dec!(0.00));
        let r = reconcile(&st);
        assert!(r.read_debits.is_zero());
        assert!(r.read_credits.is_zero());
        assert_eq!(r.status, Some(ReconcileStatus::Reconciled));
    }

    #[test]
    fn rows_are_never_dropped_on_needs_review() {
        let mut st = statement(vec![
            line(dec!(100.00), Direction::Debit),
            line(dec!(250.50), Direction::Debit),
            line(dec!(900.00), Direction::Credit),
        ]);
        st.printed_total_debits = Some(dec!(9999.00)); // mismatch
        let r = reconcile(&st);
        assert_eq!(r.status, Some(ReconcileStatus::NeedsReview));
        // reconcile borrowed &st, so every read row is retained.
        assert_eq!(st.lines.len(), 3);
    }

    #[test]
    fn is_deterministic() {
        let mut st = statement(vec![line(dec!(100.00), Direction::Debit)]);
        st.printed_total_debits = Some(dec!(100.00));
        assert_eq!(reconcile(&st), reconcile(&st));
    }
}
