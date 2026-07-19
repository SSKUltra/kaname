//! Per-account statement coverage map, ported from the web engine's `coverage.py`.
//!
//! Classifies each of the rolling [`COVERAGE_MONTHS`] months ending at a caller-supplied
//! `today` as [`CoverageState::Gap`] / [`CoverageState::Partial`] / [`CoverageState::Covered`],
//! with a `needs_review` badge on COVERED months whose statement run was incomplete or failed
//! reconciliation — so a person can see which months of their history are fully imported vs have
//! holes to backfill.
//!
//! The core is pure and deterministic: it **never reads the wall-clock** (`today` is a parameter,
//! Constitution II) and does no I/O. Because there is no on-device store yet, the platform supplies
//! the pre-aggregated facts (one [`StatementCoverage`] per imported statement, one
//! [`TransactionCoverage`] per transaction); the engine owns only the classification.

use std::collections::HashMap;

use chrono::{Datelike, NaiveDate};
use serde::{Deserialize, Serialize};

/// The rolling coverage window length, matching the web engine's `COVERAGE_MONTHS`.
pub const COVERAGE_MONTHS: u32 = 24;

/// How fully one month is imported.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum CoverageState {
    /// No transactions and no statement for the month.
    Gap,
    /// Piecemeal (live-alert) transactions only — no full statement covers the month.
    Partial,
    /// A full statement covers the month (a directly-imported statement whose period-end falls in
    /// it, or any transaction sourced from a full statement).
    Covered,
}

/// One imported statement's coverage fact: the billing period-end (attributes the statement to its
/// calendar month) and whether that run needs review (was incomplete or failed reconciliation).
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StatementCoverage {
    pub period_end: NaiveDate,
    pub needs_review: bool,
}

/// One transaction's coverage fact: its date (attributes it to its calendar month) and whether it
/// came from a full statement (vs a piecemeal live alert).
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct TransactionCoverage {
    pub date: NaiveDate,
    pub from_full_statement: bool,
}

/// One month of the coverage map: the `"YYYY-MM"` label, its state, and the needs-review badge.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct MonthCoverage {
    pub month: String,
    pub state: CoverageState,
    pub needs_review: bool,
}

fn month_key(date: NaiveDate) -> String {
    format!("{:04}-{:02}", date.year(), date.month())
}

/// The `count` `"YYYY-MM"` month labels ending at `today`'s calendar month, oldest first — the pure
/// port of the web `month_window`.
pub fn month_window(today: NaiveDate, count: u32) -> Vec<String> {
    let mut year = today.year();
    let mut month = today.month();
    let mut labels = Vec::with_capacity(count as usize);
    for _ in 0..count {
        labels.push(format!("{year:04}-{month:02}"));
        if month == 1 {
            month = 12;
            year -= 1;
        } else {
            month -= 1;
        }
    }
    labels.reverse();
    labels
}

/// Classify the rolling [`COVERAGE_MONTHS`] months ending at `today` for one account, from the
/// pre-aggregated `statements` and `transactions` facts. Pure, deterministic, total — never reads
/// the clock, never panics. Returns the month entries oldest first.
pub fn compute_coverage(
    today: NaiveDate,
    statements: &[StatementCoverage],
    transactions: &[TransactionCoverage],
) -> Vec<MonthCoverage> {
    let window = month_window(today, COVERAGE_MONTHS);
    // First day of the oldest window month — facts before this are outside the window.
    let earliest = NaiveDate::from_ymd_opt(
        window[0][..4].parse::<i32>().unwrap(),
        window[0][5..7].parse::<u32>().unwrap(),
        1,
    )
    .unwrap();

    // Per-month transaction presence + whether any row is from a full statement.
    let mut txn_by_month: HashMap<String, bool> = HashMap::new();
    for txn in transactions {
        if txn.date >= earliest {
            let entry = txn_by_month.entry(month_key(txn.date)).or_insert(false);
            *entry = *entry || txn.from_full_statement;
        }
    }
    // Months covered by a directly-imported statement (period-end attribution), OR-ing needs-review.
    let mut stmt_by_month: HashMap<String, bool> = HashMap::new();
    for stmt in statements {
        if stmt.period_end >= earliest {
            let entry = stmt_by_month
                .entry(month_key(stmt.period_end))
                .or_insert(false);
            *entry = *entry || stmt.needs_review;
        }
    }

    window
        .into_iter()
        .map(|label| {
            let has_txn = txn_by_month.contains_key(&label);
            let has_full = txn_by_month.get(&label).copied().unwrap_or(false);
            let covered_by_statement = stmt_by_month.contains_key(&label);
            if covered_by_statement || (has_txn && has_full) {
                let needs_review = stmt_by_month.get(&label).copied().unwrap_or(false);
                MonthCoverage {
                    month: label,
                    state: CoverageState::Covered,
                    needs_review,
                }
            } else if has_txn {
                MonthCoverage {
                    month: label,
                    state: CoverageState::Partial,
                    needs_review: false,
                }
            } else {
                MonthCoverage {
                    month: label,
                    state: CoverageState::Gap,
                    needs_review: false,
                }
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn date(y: i32, m: u32, d: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, d).unwrap()
    }

    fn find<'a>(months: &'a [MonthCoverage], label: &str) -> &'a MonthCoverage {
        months
            .iter()
            .find(|m| m.month == label)
            .expect("month present")
    }

    #[test]
    fn month_window_is_24_labels_oldest_first() {
        let window = month_window(date(2026, 6, 14), COVERAGE_MONTHS);
        assert_eq!(window.len(), 24);
        assert_eq!(window[0], "2024-07");
        assert_eq!(window[23], "2026-06");
    }

    #[test]
    fn month_window_ends_at_today_month_regardless_of_day() {
        assert_eq!(
            *month_window(date(2026, 6, 1), 1).last().unwrap(),
            "2026-06"
        );
        assert_eq!(
            *month_window(date(2026, 1, 31), 2).last().unwrap(),
            "2026-01"
        );
        assert_eq!(month_window(date(2026, 1, 31), 2)[0], "2025-12");
    }

    fn reference() -> Vec<MonthCoverage> {
        let statements = vec![
            StatementCoverage {
                period_end: date(2026, 5, 16),
                needs_review: false,
            },
            StatementCoverage {
                period_end: date(2026, 2, 28),
                needs_review: true,
            },
        ];
        let transactions = vec![
            TransactionCoverage {
                date: date(2026, 4, 10),
                from_full_statement: false,
            },
            TransactionCoverage {
                date: date(2026, 5, 5),
                from_full_statement: true,
            },
            TransactionCoverage {
                date: date(2026, 1, 20),
                from_full_statement: true,
            },
        ];
        compute_coverage(date(2026, 6, 14), &statements, &transactions)
    }

    #[test]
    fn classifies_the_reference_scenario() {
        let months = reference();
        assert_eq!(months.len(), 24);
        // COVERED via a directly-imported statement whose run was OK.
        assert_eq!(find(&months, "2026-05").state, CoverageState::Covered);
        assert!(!find(&months, "2026-05").needs_review);
        // COVERED via a statement whose run needs review → the badge rides along.
        assert_eq!(find(&months, "2026-02").state, CoverageState::Covered);
        assert!(find(&months, "2026-02").needs_review);
        // Alert-only transaction → PARTIAL.
        assert_eq!(find(&months, "2026-04").state, CoverageState::Partial);
        assert!(!find(&months, "2026-04").needs_review);
        // COVERED only via a full-statement transaction (no statement record) → needs_review false.
        assert_eq!(find(&months, "2026-01").state, CoverageState::Covered);
        assert!(!find(&months, "2026-01").needs_review);
        // Everything else is a GAP.
        assert_eq!(find(&months, "2026-03").state, CoverageState::Gap);
        let non_gap = months
            .iter()
            .filter(|m| m.state != CoverageState::Gap)
            .count();
        assert_eq!(non_gap, 4);
    }

    #[test]
    fn empty_input_is_all_gap() {
        let months = compute_coverage(date(2026, 6, 14), &[], &[]);
        assert_eq!(months.len(), 24);
        assert!(months
            .iter()
            .all(|m| m.state == CoverageState::Gap && !m.needs_review));
    }

    #[test]
    fn facts_outside_the_window_are_ignored() {
        // A statement older than the earliest window month (2024-07) is ignored.
        let statements = vec![StatementCoverage {
            period_end: date(2024, 6, 30),
            needs_review: true,
        }];
        let months = compute_coverage(date(2026, 6, 14), &statements, &[]);
        assert!(months.iter().all(|m| m.state == CoverageState::Gap));
    }

    #[test]
    fn is_deterministic() {
        assert_eq!(reference(), reference());
    }
}
