//! Issuer-claim matching primitives.
//!
//! A statement is identified by the literals it *prints about itself*, never by what its
//! transaction rows happen to mention. This module supplies the two projections every
//! reader's `claims` fn matches against — the identity region (the document minus its
//! transaction rows) and the header region (its title block) — plus the
//! whitespace-insensitive comparison that survives a column-major text layer.
//!
//! Both halves are load-bearing and neither is safe alone. Whitespace-insensitivity is what
//! keeps `Statement of Transactions` findable once a column-major page is reshaped into
//! printed rows; but it widens every bare-institution marker at the same time, and
//! `hdfc_bank`'s mandatory marker is literally `HDFC` — a token that appears inside a UPI
//! narration on a measured AU savings statement. Restricting the haystack to the identity
//! region is what makes the widening safe.

use std::sync::LazyLock;

use regex::Regex;

/// How many identity lines a product-level claim may look at. A statement names itself in
/// its title block; a document that has not said what it is within fifteen lines is not
/// about to prove it in a footer.
const HEADER_LINES: usize = 15;

// A transaction row is a line carrying **both** a date and a money amount. Either alone is
// ordinary in a header ("From : 01/04/2026 To : 30/04/2026") or in a summary total
// ("Closing Balance 1,45,000.00"), and both of those lines are allowed to identify the
// document.
static ROW_DATE_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\d{2}/\d{2}/\d{4}|\d{2}/\d{2}/\d{2}|\d{2}-[A-Za-z]{3}-\d{4}")
        .expect("row date pattern is a compile-time constant")
});
static ROW_AMOUNT_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"[\d,]+\.\d{2}").expect("row amount pattern is a compile-time constant")
});

/// Lowercase, then drop every whitespace character.
///
/// ASCII-lowercasing only, and no other rewriting: no punctuation stripping, no Unicode
/// folding, no stemming. Widening one axis at a time is what keeps "this never manufactures
/// a claim" a testable statement rather than a hope.
pub fn normalize_for_claim(s: &str) -> String {
    s.chars()
        .filter(|c| !c.is_whitespace())
        .map(|c| c.to_ascii_lowercase())
        .collect()
}

/// Whether an already-normalized haystack contains `marker`.
///
/// The caller normalizes the haystack once per document; the marker is normalized here, so
/// both sides always pass through the same function and the relation stays symmetric.
pub fn claim_contains(haystack_normalized: &str, marker: &str) -> bool {
    haystack_normalized.contains(&normalize_for_claim(marker))
}

/// The two projections of a document that are allowed to identify it, computed once per
/// detection and handed to every reader's claim fn.
///
/// A single `&str` cannot serve both rules: a bank-level marker is matched against the whole
/// identity region, while a *product* marker is confined to the title block (FR-047), and the
/// identity region has already lost its line boundaries to normalization. So both are built
/// together, in one pass over the document.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Regions {
    identity: String,
    header: String,
}

impl Regions {
    /// Project a document into the regions that may identify it.
    pub fn of(full_text: &str) -> Self {
        let lines: Vec<String> = full_text
            .lines()
            .filter(|line| !is_row_like(line))
            .map(normalize_for_claim)
            .collect();

        Self {
            header: lines.iter().take(HEADER_LINES).cloned().collect(),
            identity: lines.concat(),
        }
    }

    /// Everything the document says about itself, minus its transaction rows.
    pub fn identity(&self) -> &str {
        &self.identity
    }

    /// The document's title block — the first [`HEADER_LINES`] identity lines.
    pub fn header(&self) -> &str {
        &self.header
    }

    /// Whether the document says this anywhere outside its transaction rows.
    pub fn identity_has(&self, marker: &str) -> bool {
        claim_contains(&self.identity, marker)
    }

    /// Whether the document says this in its title block. What a product claim asks.
    pub fn header_has(&self, marker: &str) -> bool {
        claim_contains(&self.header, marker)
    }
}

/// The part of a document that is allowed to identify it: everything except its transaction
/// rows, normalized per [`normalize_for_claim`].
pub fn identity_region(full_text: &str) -> String {
    Regions::of(full_text).identity
}

/// The document's title block — the first [`HEADER_LINES`] identity lines — normalized.
///
/// What a *product* claim is matched against. A card statement names its product on its
/// title line; the same word appearing forty times in the holder's spending is evidence of
/// where they shop, not of which card they hold.
pub fn header_region(full_text: &str) -> String {
    Regions::of(full_text).header
}

fn is_row_like(line: &str) -> bool {
    ROW_DATE_RE.is_match(line) && ROW_AMOUNT_RE.is_match(line)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn whitespace_is_not_part_of_a_marker() {
        let hay = normalize_for_claim("Statement of Transactions");
        for spelling in [
            "Statement of Transactions",
            "Statement  of Transactions",
            "StatementofTransactions",
            "Statement\nof\tTransactions",
        ] {
            assert!(claim_contains(&hay, spelling), "{spelling}");
        }
    }

    #[test]
    fn a_marker_matches_a_document_whose_spacing_differs_from_its_own() {
        // The direction that matters in practice: the marker keeps its spaces and the
        // extractor lost them, or the other way round.
        assert!(claim_contains(
            &normalize_for_claim("Statementof   account"),
            "Statement of account"
        ));
        assert!(claim_contains(
            &normalize_for_claim("Withdrawal Amt."),
            "WithdrawalAmt"
        ));
    }

    #[test]
    fn normalization_lowercases_ascii_only() {
        assert_eq!(normalize_for_claim("HDFC Bank"), "hdfcbank");
        // A non-ASCII capital is left exactly as it is: folding it would widen matching on
        // an axis nothing has asked for.
        assert_eq!(normalize_for_claim("İSTANBUL"), "İstanbul");
    }

    #[test]
    fn normalization_strips_nothing_but_whitespace() {
        // Punctuation survives, so `iobnetcoin` cannot match `iobnet.co.in`.
        assert_eq!(normalize_for_claim("iobnet.co.in"), "iobnet.co.in");
        assert!(!claim_contains(
            &normalize_for_claim("iobnetcoin"),
            "iobnet.co.in"
        ));
        // No stemming: a marker is a literal, not a word family.
        assert!(!claim_contains(
            &normalize_for_claim("Statements"),
            "Statementof"
        ));
    }

    #[test]
    fn an_empty_marker_matches_and_an_empty_document_does_not() {
        assert!(claim_contains(&normalize_for_claim("anything"), ""));
        assert!(!claim_contains(&normalize_for_claim(""), "HDFC"));
    }

    #[test]
    fn a_transaction_row_cannot_identify_a_document() {
        let text = "AU Small Finance Bank\n\
                    Savings Account\n\
                    01/04/2026 UPI-SOMEONE-HDFC-PAYMENT 5,000.00 95,000.00\n";
        let region = identity_region(text);
        assert!(claim_contains(&region, "Savings Account"));
        assert!(
            !claim_contains(&region, "HDFC"),
            "a bank named inside a transaction description must not identify the document"
        );
    }

    #[test]
    fn a_line_needs_both_a_date_and_an_amount_to_be_a_row() {
        // A header carrying dates but no amount survives.
        assert!(claim_contains(
            &identity_region("From : 01/04/2026 To : 30/04/2026"),
            "From"
        ));
        // A total carrying an amount but no date survives.
        assert!(claim_contains(
            &identity_region("Closing Balance 1,45,000.00"),
            "ClosingBalance"
        ));
        // Both together is a row.
        assert!(identity_region("01/04/2026 SOMETHING 5,000.00").is_empty());
    }

    #[test]
    fn every_supported_row_date_shape_is_recognised() {
        for row in [
            "19/04/2026 MERCHANT 1,234.56",
            "01/04/26 MERCHANT 1,234.56",
            "04-Apr-2025 MERCHANT 1,234.56",
        ] {
            assert!(identity_region(row).is_empty(), "{row}");
        }
    }

    #[test]
    fn the_header_region_stops_after_fifteen_identity_lines() {
        let mut lines: Vec<String> = (1..=HEADER_LINES).map(|n| format!("line {n}")).collect();
        lines.push("Scapia".to_string());
        let text = lines.join("\n");

        assert!(!claim_contains(&header_region(&text), "Scapia"));
        assert!(claim_contains(&identity_region(&text), "Scapia"));
    }

    #[test]
    fn transaction_rows_do_not_consume_the_header_budget() {
        // Rows are dropped before the first fifteen lines are counted, so a statement that
        // starts spending immediately still has its title block read.
        let mut lines = vec!["A Bank".to_string()];
        for day in 1..=20 {
            lines.push(format!("{day:02}/04/2026 SOME MERCHANT 1,234.56"));
        }
        lines.push("Swiggy HDFC Bank Credit Card".to_string());
        let text = lines.join("\n");

        assert!(claim_contains(&header_region(&text), "Swiggy"));
    }

    #[test]
    fn a_phrase_split_across_two_printed_lines_still_matches() {
        // What a column-major page does to a header: the phrase is cut in half and the two
        // halves land on separate lines.
        assert!(claim_contains(
            &identity_region("Statement of\nTransactions"),
            "Statement of Transactions"
        ));
    }

    #[test]
    fn the_regions_are_pure_and_deterministic() {
        let text = "ICICI Bank\nStatement of Transactions\n19/04/2026 MERCHANT 1,234.56\n";
        for _ in 0..3 {
            assert_eq!(identity_region(text), identity_region(text));
            assert_eq!(header_region(text), header_region(text));
            assert_eq!(normalize_for_claim(text), normalize_for_claim(text));
        }
    }

    #[test]
    fn arbitrary_input_is_handled_without_panicking() {
        for text in ["", "\n\n\n", "🧾💳🏦", "\u{202E}drawkcab", "   \t  "] {
            let _ = identity_region(text);
            let _ = header_region(text);
            let _ = claim_contains(&identity_region(text), "HDFC");
        }
    }
}
