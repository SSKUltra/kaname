//! Deterministic transfer (self-transfer) detection.
//!
//! When a person moves money between their own accounts — a credit-card bill payment
//! (a bank Debit paired with a card "payment received" Credit) or a bank-to-bank NEFT —
//! two rows appear, one Debit (outflow) and one Credit (inflow), on two different
//! accounts, close in date and amount. This matcher pairs those opposite-direction
//! cross-account rows so the platform can tag them as an internal transfer instead of
//! double-counting them as spend and income — the on-device equivalent of the web
//! engine's `transfer_detector.py` pure pairing subset.
//!
//! Pure, deterministic, read-only: no network, no clock, no locale, no database. All
//! persistence (`transfer_group_id`, category assignment, audit) stays platform-side.

use chrono::NaiveDate;
use rust_decimal::prelude::ToPrimitive;
use rust_decimal::Decimal;
use std::collections::HashSet;

use crate::model::Direction;

/// One already-parsed, still-unpaired transaction handed to the matcher. `id` and
/// `account_id` are platform-supplied stable identifiers; `is_credit_card` marks a
/// credit-card account (the faithful reduction of the web `account_type == "credit_card"`,
/// its only use). `Direction::Debit` is an outflow, `Direction::Credit` an inflow.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct TransferInput {
    pub id: String,
    pub account_id: String,
    pub is_credit_card: bool,
    pub date: NaiveDate,
    pub amount: Decimal,
    pub direction: Direction,
    pub description: String,
}

/// One detected self-transfer: the `outflow_id` (Debit anchor) paired with the
/// `inflow_id` (Credit counterpart). `is_credit_card_payment` is true when either leg is a
/// credit-card account (the web's "Credit Card Bill Payment" vs "Self Transfer" split).
/// `score` is the confidence metric (a float, not money).
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct TransferPair {
    pub outflow_id: String,
    pub inflow_id: String,
    pub is_credit_card_payment: bool,
    pub score: f64,
}

/// Date drift (inclusive) at which two legs may still be one transfer.
const DATE_TOLERANCE_DAYS: i64 = 1;

/// Token-level Jaccard similarity of two narrations (case-insensitive, whitespace-split) —
/// the port of the web `_narration_similarity`. `0.0` when either side is empty or yields
/// no tokens. Deliberately distinct from `dedup::normalize_narration` + Jaro-Winkler.
fn narration_similarity(a: &str, b: &str) -> f64 {
    if a.is_empty() || b.is_empty() {
        return 0.0;
    }
    let a_low = a.to_lowercase();
    let b_low = b.to_lowercase();
    let tokens_a: HashSet<&str> = a_low.split_whitespace().collect();
    let tokens_b: HashSet<&str> = b_low.split_whitespace().collect();
    if tokens_a.is_empty() || tokens_b.is_empty() {
        return 0.0;
    }
    let intersection = tokens_a.intersection(&tokens_b).count();
    let union = tokens_a.union(&tokens_b).count();
    intersection as f64 / union as f64
}

/// Confidence score for a pair — the port of the web `_score`. Floored at `0.0` but
/// deliberately **not** capped at `1.0` (a same-day/same-amount, similarly-narrated pair
/// exceeds 1.0). The left-to-right operation order matches the Python so the f64 is
/// reproduced bit-for-bit.
fn score(date_diff: i64, amount_diff: Decimal, sim: f64) -> f64 {
    let amount_diff = amount_diff.to_f64().unwrap_or(0.0);
    (1.0 - 0.2 * date_diff as f64 - 0.2 * amount_diff + 0.2 * sim).max(0.0)
}

/// Pair opposite-direction cross-account rows into self-transfers — the pure port of the
/// web `detect_pairs_for_user` + `_best_counterpart`, minus all SQL/persistence.
///
/// Anchors on outflows (`Direction::Debit`) in ascending `(date, id)` order; for each
/// still-unclaimed anchor, greedily claims the best opposite-direction (`Direction::Credit`)
/// counterpart on a *different* account within ±1 day and ±₹1.00 (both inclusive). Ambiguity
/// is resolved by the deterministic tuple `(date_diff, amount_diff, -narration_similarity,
/// id)` — lowest wins. Each row is claimed at most once; the returned pairs are ordered by
/// the anchor's `(date, id)`.
pub fn detect_transfers(rows: &[TransferInput]) -> Vec<TransferPair> {
    let mut anchors: Vec<usize> = (0..rows.len())
        .filter(|&i| rows[i].direction == Direction::Debit)
        .collect();
    anchors.sort_by(|&i, &j| {
        rows[i]
            .date
            .cmp(&rows[j].date)
            .then_with(|| rows[i].id.cmp(&rows[j].id))
    });

    let mut consumed = vec![false; rows.len()];
    let mut pairs = Vec::new();

    for &a in &anchors {
        if consumed[a] {
            continue;
        }
        let anchor = &rows[a];

        let best = (0..rows.len())
            .filter(|&c| {
                !consumed[c]
                    && rows[c].direction == Direction::Credit
                    && rows[c].account_id != anchor.account_id
                    && (anchor.date - rows[c].date).num_days().abs() <= DATE_TOLERANCE_DAYS
                    && (anchor.amount - rows[c].amount).abs() <= Decimal::ONE
            })
            .min_by(|&i, &j| {
                let di = (anchor.date - rows[i].date).num_days().abs();
                let dj = (anchor.date - rows[j].date).num_days().abs();
                let ai = (anchor.amount - rows[i].amount).abs();
                let aj = (anchor.amount - rows[j].amount).abs();
                let si = narration_similarity(&anchor.description, &rows[i].description);
                let sj = narration_similarity(&anchor.description, &rows[j].description);
                di.cmp(&dj)
                    .then(ai.cmp(&aj))
                    // Higher similarity wins (the web tuple negates similarity).
                    .then(sj.partial_cmp(&si).expect("finite similarity"))
                    .then_with(|| rows[i].id.cmp(&rows[j].id))
            });

        let Some(c) = best else {
            continue;
        };

        let date_diff = (anchor.date - rows[c].date).num_days().abs();
        let amount_diff = (anchor.amount - rows[c].amount).abs();
        let sim = narration_similarity(&anchor.description, &rows[c].description);
        consumed[a] = true;
        consumed[c] = true;
        pairs.push(TransferPair {
            outflow_id: anchor.id.clone(),
            inflow_id: rows[c].id.clone(),
            is_credit_card_payment: anchor.is_credit_card || rows[c].is_credit_card,
            score: score(date_diff, amount_diff, sim),
        });
    }

    pairs
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    fn d(s: &str) -> NaiveDate {
        NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap()
    }

    fn row(
        id: &str,
        account_id: &str,
        is_credit_card: bool,
        date: &str,
        amount: Decimal,
        direction: Direction,
        description: &str,
    ) -> TransferInput {
        TransferInput {
            id: id.to_string(),
            account_id: account_id.to_string(),
            is_credit_card,
            date: d(date),
            amount,
            direction,
            description: description.to_string(),
        }
    }

    fn out(id: &str, acct: &str, date: &str, amount: Decimal, desc: &str) -> TransferInput {
        row(id, acct, false, date, amount, Direction::Debit, desc)
    }

    fn inflow(id: &str, acct: &str, date: &str, amount: Decimal, desc: &str) -> TransferInput {
        row(id, acct, false, date, amount, Direction::Credit, desc)
    }

    #[test]
    fn pairs_same_day_same_amount_across_accounts() {
        let rows = vec![
            out("a", "icici", "2026-06-01", dec!(5000.00), "NEFT TO HDFC"),
            inflow("b", "hdfc", "2026-06-01", dec!(5000.00), "NEFT FROM ICICI"),
        ];
        let pairs = detect_transfers(&rows);
        assert_eq!(pairs.len(), 1);
        assert_eq!(pairs[0].outflow_id, "a");
        assert_eq!(pairs[0].inflow_id, "b");
        assert!(!pairs[0].is_credit_card_payment);
    }

    #[test]
    fn pairs_within_one_day_and_one_rupee() {
        let rows = vec![
            out("a", "icici", "2026-06-01", dec!(1000.00), "x"),
            inflow("b", "hdfc", "2026-06-02", dec!(1000.50), "y"),
        ];
        assert_eq!(detect_transfers(&rows).len(), 1);
    }

    #[test]
    fn rejects_amount_drift_over_one_rupee() {
        let rows = vec![
            out("a", "icici", "2026-06-01", dec!(1000.00), "x"),
            inflow("b", "hdfc", "2026-06-01", dec!(1001.01), "y"),
        ];
        assert!(detect_transfers(&rows).is_empty());
    }

    #[test]
    fn rejects_date_drift_over_one_day() {
        let rows = vec![
            out("a", "icici", "2026-06-01", dec!(1000.00), "x"),
            inflow("b", "hdfc", "2026-06-05", dec!(1000.00), "y"),
        ];
        assert!(detect_transfers(&rows).is_empty());
    }

    #[test]
    fn rejects_same_direction_and_same_account() {
        let same_dir = vec![
            out("a", "icici", "2026-06-01", dec!(1000.00), "x"),
            out("b", "hdfc", "2026-06-01", dec!(1000.00), "y"),
        ];
        assert!(detect_transfers(&same_dir).is_empty());

        let same_acct = vec![
            out("a", "icici", "2026-06-01", dec!(1000.00), "x"),
            inflow("b", "icici", "2026-06-01", dec!(1000.00), "y"),
        ];
        assert!(detect_transfers(&same_acct).is_empty());
    }

    #[test]
    fn ambiguity_resolves_to_closer_narration() {
        let rows = vec![
            out(
                "s",
                "icici",
                "2026-06-01",
                dec!(500.00),
                "NEFT TO HDFC BANK XX1234",
            ),
            inflow(
                "better",
                "hdfc",
                "2026-06-01",
                dec!(500.00),
                "NEFT FROM ICICI BANK XX5678",
            ),
            inflow(
                "worse",
                "hdfc",
                "2026-06-01",
                dec!(500.00),
                "SALARY CREDIT FROM ACME CORP",
            ),
        ];
        let pairs = detect_transfers(&rows);
        assert_eq!(pairs.len(), 1);
        assert_eq!(pairs[0].inflow_id, "better");
    }

    #[test]
    fn identical_candidates_resolve_to_lowest_id() {
        let rows = vec![
            out("h1", "icici", "2026-06-01", dec!(700.00), "SELF TRANSFER"),
            inflow("h3", "sbi", "2026-06-01", dec!(700.00), "SELF TRANSFER"),
            inflow("h2", "hdfc", "2026-06-01", dec!(700.00), "SELF TRANSFER"),
        ];
        let pairs = detect_transfers(&rows);
        assert_eq!(pairs.len(), 1);
        assert_eq!(pairs[0].inflow_id, "h2");
    }

    #[test]
    fn flags_credit_card_bill_payment() {
        let rows = vec![
            out(
                "bank",
                "icici",
                "2026-06-10",
                dec!(8000.00),
                "CREDIT CARD PAYMENT",
            ),
            row(
                "card",
                "icici_cc",
                true,
                "2026-06-10",
                dec!(8000.00),
                Direction::Credit,
                "PAYMENT RECEIVED THANK YOU",
            ),
        ];
        let pairs = detect_transfers(&rows);
        assert_eq!(pairs.len(), 1);
        assert!(pairs[0].is_credit_card_payment);
    }

    #[test]
    fn earlier_anchor_claims_a_contested_inflow() {
        let rows = vec![
            out("late", "icici", "2026-06-02", dec!(900.00), "x"),
            out("early", "sbi", "2026-06-01", dec!(900.00), "x"),
            inflow("shared", "hdfc", "2026-06-01", dec!(900.00), "x"),
        ];
        let pairs = detect_transfers(&rows);
        assert_eq!(pairs.len(), 1);
        assert_eq!(pairs[0].outflow_id, "early");
        assert_eq!(pairs[0].inflow_id, "shared");
    }

    #[test]
    fn score_is_not_capped_at_one() {
        let rows = vec![
            out("a", "icici", "2026-06-01", dec!(700.00), "SELF TRANSFER"),
            inflow("b", "hdfc", "2026-06-01", dec!(700.00), "SELF TRANSFER"),
        ];
        let pairs = detect_transfers(&rows);
        assert_eq!(pairs[0].score, 1.2);
    }

    #[test]
    fn score_reference_values() {
        // date_diff=1, amount_diff=0.5, sim=0 — the ±1 day / ±₹0.50 pair.
        assert_eq!(super::score(1, dec!(0.50), 0.0), 0.7000000000000001);
        // Perfect same-day/same-amount with no narration overlap.
        assert_eq!(super::score(0, dec!(0), 0.0), 1.0);
        // A large drift would go negative but is floored at zero.
        assert_eq!(super::score(5, dec!(0), 0.0), 0.0);
    }

    #[test]
    fn amount_and_date_boundaries_are_inclusive() {
        // Exactly +1 day and exactly +₹1.00 are both inside the window.
        let rows = vec![
            out("a", "icici", "2026-06-01", dec!(1000.00), "x"),
            inflow("b", "hdfc", "2026-06-02", dec!(1001.00), "y"),
        ];
        assert_eq!(detect_transfers(&rows).len(), 1);
    }
}
