//! Statement-line polarity ported from the web engine's `polarity.py`.
//!
//! Direction is read from the statement's own debit/credit indication and is NEVER
//! inferred from the sign of an amount. Precedence: an explicit Dr/Cr marker wins;
//! then a parenthesised amount (an Indian credit convention); then credit-type
//! language in the description; otherwise the row defaults to a debit (spend).

use crate::model::Direction;

// Explicit single/double-letter Dr/Cr markers a statement column may carry.
const CR_MARKERS: &[&str] = &["CR", "C", "CREDIT", "CRDR-CR"];
const DR_MARKERS: &[&str] = &["DR", "D", "DEBIT", "CRDR-DR"];

// Transaction-type language → credit. Any substring hit classifies the line as credit.
const CREDIT_KEYWORDS: &[&str] = &[
    "payment received",
    "received, thank you",
    "received thank you",
    "refund",
    "reversal",
    "reversed",
    "cashback",
    "cash back",
    "credit adjustment",
    "autopay received",
];

/// Map a raw Dr/Cr cell value to a [`Direction`], or `None` when absent/unrecognised.
pub fn normalise_marker(marker: Option<&str>) -> Option<Direction> {
    let marker = marker?;
    let token: String = marker
        .chars()
        .filter(|c| c.is_ascii_alphabetic() || *c == '-')
        .collect::<String>()
        .to_uppercase();
    if token.is_empty() {
        return None;
    }
    if CR_MARKERS.contains(&token.as_str()) {
        return Some(Direction::Credit);
    }
    if DR_MARKERS.contains(&token.as_str()) {
        return Some(Direction::Debit);
    }
    None
}

/// Indian statements sometimes denote a credit by wrapping the amount in parentheses,
/// e.g. `(1,200.00)`. This is a credit marker, NOT a negative value.
pub fn is_parenthesised_credit(amount_cell: Option<&str>) -> bool {
    match amount_cell {
        Some(cell) => {
            let cell = cell.trim();
            cell.starts_with('(') && cell.ends_with(')')
        }
        None => false,
    }
}

/// Return [`Direction::Credit`] or [`Direction::Debit`] for a statement line. The
/// amount's value/sign is intentionally never consulted.
pub fn classify(
    description: &str,
    dr_cr_marker: Option<&str>,
    amount_cell: Option<&str>,
) -> Direction {
    if let Some(explicit) = normalise_marker(dr_cr_marker) {
        return explicit;
    }
    if is_parenthesised_credit(amount_cell) {
        return Direction::Credit;
    }
    let haystack = description.to_lowercase();
    if CREDIT_KEYWORDS.iter().any(|kw| haystack.contains(kw)) {
        return Direction::Credit;
    }
    Direction::Debit
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn explicit_marker_wins() {
        assert_eq!(classify("anything", Some("CR"), None), Direction::Credit);
        assert_eq!(classify("anything", Some("Dr"), None), Direction::Debit);
    }

    #[test]
    fn credit_language_without_marker() {
        for desc in [
            "Refund received",
            "Reversal of charge",
            "Cashback bonus",
            "Payment received",
        ] {
            assert_eq!(classify(desc, None, None), Direction::Credit, "{desc}");
        }
    }

    #[test]
    fn ordinary_spend_defaults_to_debit() {
        assert_eq!(
            classify("Fee on gaming transaction", None, None),
            Direction::Debit
        );
    }

    #[test]
    fn parenthesised_amount_is_credit() {
        assert_eq!(
            classify("purchase", None, Some("(1,200.00)")),
            Direction::Credit
        );
    }

    #[test]
    fn amount_magnitude_never_changes_direction() {
        // A huge "negative-looking" amount is still a debit — direction ignores amount.
        assert_eq!(
            classify("Big purchase", None, Some("-9,99,999.00")),
            Direction::Debit
        );
    }
}
