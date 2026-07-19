//! Deterministic de-duplication helpers.
//!
//! The same transaction is frequently seen across sources (e.g. a bank statement and
//! a card statement, or two overlapping statement PDFs). We compute a stable
//! fingerprint so cross-source duplicates collapse to one row — the on-device
//! equivalent of the web engine's `*_cross_source_dedup` behaviour.

use std::sync::LazyLock;

use regex::Regex;
use serde::{Deserialize, Serialize};

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

// --- Cross-source matcher (ports the web engine's L3 CANONICAL + L4 FUZZY layers) ---------- //

// Leading channel prefix (POS/UPI/NEFT/…) stripped from the head of a narration.
static NARRATION_LEADING_PREFIX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)^(POS\s|UPI[-/]|NEFT/|IMPS/|ACH/|BIL/|RTGS/|INT\.PD\./|TO TRANSFER-|BY TRANSFER-)",
    )
    .unwrap()
});
// An `RRN<digits>` reference token, removed anywhere in the narration.
static NARRATION_RRN: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)\bRRN\d+\b").unwrap());
// A trailing 10–16 digit reference number.
static NARRATION_TRAILING_REFNUM: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\b[0-9]{10,16}\b\s*$").unwrap());
static NARRATION_WHITESPACE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\s+").unwrap());

/// Normalize a bank/card narration for cross-source matching — the port of the web engine's
/// `normalise_narration` (distinct from [`normalize_description`], which upper-cases). Strips a
/// leading channel prefix (POS/UPI/NEFT/…, repeated for stacked prefixes), any `RRN…` token, and
/// a trailing 10–16 digit reference number; collapses whitespace; lower-cases.
pub fn normalize_narration(raw: &str) -> String {
    let mut s = raw.trim().to_string();
    loop {
        let stripped = NARRATION_LEADING_PREFIX.replace(&s, "").trim().to_string();
        if stripped == s {
            break;
        }
        s = stripped;
    }
    let s = NARRATION_RRN.replace_all(&s, "");
    let s = NARRATION_WHITESPACE.replace_all(&s, " ");
    let s = NARRATION_TRAILING_REFNUM.replace(&s, "");
    s.to_lowercase().trim().to_string()
}

/// Classic Jaro similarity of two char slices (match window `max(len)/2 − 1`).
fn jaro(a: &[char], b: &[char]) -> f64 {
    if a == b {
        return 1.0;
    }
    let (len_a, len_b) = (a.len(), b.len());
    if len_a == 0 || len_b == 0 {
        return 0.0;
    }
    let max_dist = (len_a.max(len_b) / 2).saturating_sub(1);
    let mut a_matches = vec![false; len_a];
    let mut b_matches = vec![false; len_b];
    let mut matches = 0usize;
    for i in 0..len_a {
        let start = i.saturating_sub(max_dist);
        let end = (i + max_dist + 1).min(len_b);
        for j in start..end {
            if b_matches[j] || a[i] != b[j] {
                continue;
            }
            a_matches[i] = true;
            b_matches[j] = true;
            matches += 1;
            break;
        }
    }
    if matches == 0 {
        return 0.0;
    }
    let mut transpositions = 0usize;
    let mut k = 0usize;
    for (i, &matched) in a_matches.iter().enumerate() {
        if !matched {
            continue;
        }
        while !b_matches[k] {
            k += 1;
        }
        if a[i] != b[k] {
            transpositions += 1;
        }
        k += 1;
    }
    let transpositions = transpositions / 2;
    let m = matches as f64;
    (m / len_a as f64 + m / len_b as f64 + (m - transpositions as f64) / m) / 3.0
}

/// Jaro-Winkler similarity — Jaro plus a common-prefix bonus (weight `0.1`, prefix capped at 4),
/// applied unconditionally. Reproduces the web engine's `rapidfuzz` Jaro-Winkler byte-for-byte.
fn jaro_winkler(a: &str, b: &str) -> f64 {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let j = jaro(&a, &b);
    let mut prefix = 0usize;
    for (x, y) in a.iter().zip(b.iter()) {
        if x != y || prefix == 4 {
            break;
        }
        prefix += 1;
    }
    j + prefix as f64 * 0.1 * (1.0 - j)
}

/// Which layer of the ladder identified a cross-source duplicate.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum DedupLayer {
    /// Same date, amount, direction, and first-60-char normalized-narration prefix (web L3).
    Canonical,
    /// Same amount and direction, dates within ±1 day, Jaro-Winkler ≥ 0.92 (web L4).
    Fuzzy,
}

/// One identified cross-source duplicate: `incoming[incoming_index]` duplicates the earlier
/// `existing[existing_index]`, caught by `layer`.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CrossSourceMatch {
    pub incoming_index: u32,
    pub existing_index: u32,
    pub layer: DedupLayer,
}

/// Jaro-Winkler similarity at or above which two normalized narrations are a fuzzy match.
const JARO_WINKLER_THRESHOLD: f64 = 0.92;
/// Canonical-key narration prefix length (codepoints), matching the web `canonical_hash`.
const CANONICAL_PREFIX: usize = 60;

fn prefix60(normalized: &str) -> String {
    normalized.chars().take(CANONICAL_PREFIX).collect()
}

/// Identify cross-source duplicate transactions between two already-parsed lists (e.g. a bank
/// ledger and a credit-card statement). Ports the web de-duplicator's portable L3 CANONICAL +
/// L4 FUZZY layers: for each `incoming` row in order, the canonical layer is tried before the
/// fuzzy layer, and the first still-unconsumed `existing` row wins. Each existing row is consumed
/// by at most one incoming row (multiplicity-aware), so surplus genuine repeats survive. Pure,
/// deterministic, read-only — neither list is mutated.
pub fn cross_source_duplicates(
    existing: &[Transaction],
    incoming: &[Transaction],
) -> Vec<CrossSourceMatch> {
    let existing_norm: Vec<String> = existing
        .iter()
        .map(|t| normalize_narration(&t.description))
        .collect();
    let existing_prefix: Vec<String> = existing_norm.iter().map(|n| prefix60(n)).collect();
    let mut consumed = vec![false; existing.len()];
    let mut matches = Vec::new();

    for (i, inc) in incoming.iter().enumerate() {
        let inc_norm = normalize_narration(&inc.description);
        let inc_prefix = prefix60(&inc_norm);
        let inc_amount = inc.amount.normalize();
        let mut hit: Option<(usize, DedupLayer)> = None;

        // L3 CANONICAL — same date + amount + direction + 60-char normalized prefix.
        for (e, ex) in existing.iter().enumerate() {
            if consumed[e] {
                continue;
            }
            if ex.date == inc.date
                && ex.amount.normalize() == inc_amount
                && ex.direction == inc.direction
                && existing_prefix[e] == inc_prefix
            {
                hit = Some((e, DedupLayer::Canonical));
                break;
            }
        }

        // L4 FUZZY — same amount + direction, dates within ±1 day, Jaro-Winkler ≥ 0.92.
        if hit.is_none() {
            for (e, ex) in existing.iter().enumerate() {
                if consumed[e] {
                    continue;
                }
                if ex.amount.normalize() == inc_amount
                    && ex.direction == inc.direction
                    && (ex.date - inc.date).num_days().abs() <= 1
                    && jaro_winkler(&existing_norm[e], &inc_norm) >= JARO_WINKLER_THRESHOLD
                {
                    hit = Some((e, DedupLayer::Fuzzy));
                    break;
                }
            }
        }

        if let Some((e, layer)) = hit {
            consumed[e] = true;
            matches.push(CrossSourceMatch {
                incoming_index: i as u32,
                existing_index: e as u32,
                layer,
            });
        }
    }
    matches
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

    fn txn(ymd: (i32, u32, u32), desc: &str, amount: rust_decimal::Decimal) -> Transaction {
        Transaction::new(
            NaiveDate::from_ymd_opt(ymd.0, ymd.1, ymd.2).unwrap(),
            desc,
            amount,
            Direction::Debit,
        )
    }

    #[test]
    fn normalize_narration_matches_web_reference_outputs() {
        assert_eq!(normalize_narration("UPI-SWIGGY-RRN1234"), "swiggy-");
        assert_eq!(
            normalize_narration("POS SWIGGY BANGALORE 12345678901234"),
            "swiggy bangalore"
        );
        assert_eq!(
            normalize_narration("NEFT/ACME CORP/REF999"),
            "acme corp/ref999"
        );
        assert_eq!(
            normalize_narration("  TO TRANSFER- Rent   Payment  "),
            "rent payment"
        );
        assert_eq!(
            normalize_narration("BY TRANSFER-Salary Credit RRN5678"),
            "salary credit"
        );
        assert_eq!(
            normalize_narration("SWIGGY  ORDER   9988776655"),
            "swiggy order"
        );
    }

    #[test]
    fn jaro_winkler_matches_rapidfuzz_reference_values() {
        let round4 = |x: f64| (x * 10_000.0).round() / 10_000.0;
        assert_eq!(jaro_winkler("swiggy bangalore", "swiggy bangalore"), 1.0);
        assert_eq!(
            round4(jaro_winkler("swiggy bangalore", "swiggy bangaluru")),
            0.95
        );
        assert_eq!(
            round4(jaro_winkler("acme corp", "acme corporation")),
            0.9125
        );
        assert_eq!(round4(jaro_winkler("fine dining", "fine dine")), 0.9232);
        assert_eq!(
            round4(jaro_winkler("swiggy order", "swiggy orders")),
            0.9846
        );
        // The exactly-0.92 boundary is inclusive (matches rapidfuzz's 0.92).
        assert!(jaro_winkler("amazon", "amazon pay") >= 0.92);
        assert_eq!(round4(jaro_winkler("amazon", "amazon pay")), 0.92);
        assert!(jaro_winkler("uber trip", "ola trip") < 0.92);
    }

    #[test]
    fn canonical_match_on_same_day_amount_and_prefix() {
        let existing = vec![txn(
            (2026, 7, 4),
            "POS SWIGGY BANGALORE 12345678901234",
            dec!(250.00),
        )];
        let incoming = vec![txn((2026, 7, 4), "swiggy   bangalore", dec!(250.0))];
        assert_eq!(
            cross_source_duplicates(&existing, &incoming),
            vec![CrossSourceMatch {
                incoming_index: 0,
                existing_index: 0,
                layer: DedupLayer::Canonical,
            }]
        );
    }

    #[test]
    fn fuzzy_match_within_one_day_above_threshold() {
        let existing = vec![txn((2026, 7, 10), "swiggy bangalore", dec!(500.00))];
        let incoming = vec![txn((2026, 7, 11), "swiggy bangaluru", dec!(500.00))];
        let m = cross_source_duplicates(&existing, &incoming);
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].layer, DedupLayer::Fuzzy);
    }

    #[test]
    fn below_threshold_and_guards_are_survivors() {
        // Below the JW threshold (0.9125 < 0.92) and prefixes differ → no match.
        assert!(cross_source_duplicates(
            &[txn((2026, 7, 15), "acme corp", dec!(400.00))],
            &[txn((2026, 7, 15), "acme corporation", dec!(400.00))],
        )
        .is_empty());
        // Direction guard: identical but opposite direction.
        let credit = Transaction::new(
            NaiveDate::from_ymd_opt(2026, 7, 20).unwrap(),
            "netflix",
            dec!(600.00),
            Direction::Credit,
        );
        assert!(
            cross_source_duplicates(&[txn((2026, 7, 20), "netflix", dec!(600.00))], &[credit])
                .is_empty()
        );
        // Amount guard.
        assert!(cross_source_duplicates(
            &[txn((2026, 7, 20), "netflix", dec!(600.00))],
            &[txn((2026, 7, 20), "netflix", dec!(601.00))],
        )
        .is_empty());
        // Date-window guard: 2 days apart (> ±1).
        assert!(cross_source_duplicates(
            &[txn((2026, 7, 15), "swiggy bangalore", dec!(500.00))],
            &[txn((2026, 7, 17), "swiggy bangaluru", dec!(500.00))],
        )
        .is_empty());
    }

    #[test]
    fn multiplicity_consumes_each_existing_at_most_once() {
        let existing = vec![txn((2026, 7, 25), "uber", dec!(200.00))];
        let incoming = vec![
            txn((2026, 7, 25), "uber", dec!(200.00)),
            txn((2026, 7, 25), "uber", dec!(200.00)),
        ];
        let m = cross_source_duplicates(&existing, &incoming);
        assert_eq!(
            m.len(),
            1,
            "only the first incoming matches the single existing"
        );
        assert_eq!(m[0].incoming_index, 0);
    }

    #[test]
    fn canonical_precedes_fuzzy_and_is_deterministic() {
        let existing = vec![txn((2026, 7, 4), "swiggy bangalore", dec!(250.00))];
        let incoming = vec![txn((2026, 7, 4), "swiggy bangalore", dec!(250.00))];
        let first = cross_source_duplicates(&existing, &incoming);
        let second = cross_source_duplicates(&existing, &incoming);
        assert_eq!(first, second);
        assert_eq!(first[0].layer, DedupLayer::Canonical);
    }
}
