//! The **derived merchant portion** of a narration — what a memory is keyed on (FR-027).
//!
//! A memory formed from a whole normalized narration matches exactly one row forever, because a
//! UPI narration carries a per-transaction reference. A memory formed from too *little* of it
//! matches merchants the person never meant, and this slice has no undo surface to rescue them.
//! The rule below is the moderate point between those two, fixed in full so it can be
//! implemented one way only (FR-027a) and pinned by `fixtures/categorization/merchant_portion.json`.
//!
//! **Additive, and that is contractual (FR-027c).** [`crate::dedup::normalize_narration`] is
//! *called*, never changed: de-duplication depends on it and its fixtures carry zero expectation
//! edits across this slice. The cost of that decision is research R15's three priced
//! limitations, which are asserted as they behave in `tests/merchant_portion.rs` rather than
//! quietly wished away.
//!
//! Pure: no store, no clock, no locale, no global state. The same input yields the same output
//! in any process, on any machine (FR-027e).

use crate::dedup::normalize_narration;

/// The closed separator set, in addition to whitespace.
///
/// ⚠️ **`@` and `.` are deliberately absent.** A VPA is one token that is stable across every
/// transaction of a merchant, which is exactly what a memory needs; splitting `shop@examplebank`
/// would leave a bare PSP handle as a segment, and the handles that would then need suppressing
/// are themselves merchant names — putting a merchant name in the stop-list, which FR-027a
/// forbids outright. `.` stays out for the same reason at smaller scale: `examplemart.in`
/// survives whole rather than yielding `in`.
const SEPARATORS: &[char] = &[
    '-', '/', '\\', '|', '*', ':', ';', ',', '#', '_', '%', '(', ')', '[', ']', '"', '\'',
];

/// The closed stop-list — channel, instrument and narration-scaffold words, in five groups, one
/// per line. **Zero merchant names** (FR-027a), which is the property that makes it safe to
/// extend: a word here can never suppress a shop.
///
/// ⚠️ Research R14 calls this "69 words" and lists these; the list is what is fixed in full, and
/// its actual length is asserted by [`tests::the_stop_list_is_closed_and_contains_no_duplicates`]
/// so that a word added by hand cannot pass unremarked.
const STOP_WORDS: &[&str] = &[
    // 1 — channel.
    "upi",
    "pos",
    "neft",
    "neftcr",
    "neftdr",
    "imps",
    "rtgs",
    "ach",
    "nach",
    "ecs",
    "ecm",
    "eft",
    "ift",
    "bil",
    "bbps",
    "atm", //
    // 2 — channel modifier.
    "tfr",
    "trf",
    "transfer",
    "transaction",
    "txn",
    "chq",
    "cheque",
    "inf",
    "mps",
    "ib",
    "imb",
    "onl",
    "online",
    "www",
    "net",
    "mobile", //
    // 3 — instrument.
    "ref",
    "refno",
    "rrn",
    "no",
    "dr",
    "cr",
    "cc",
    "card",
    "credit",
    "debit",
    "emi",
    "fee",
    "fees",
    "charge",
    "charges",
    "gst",
    "int", //
    // 4 — payment scaffolding.
    "payment",
    "payments",
    "pymt",
    "pmt",
    "paid",
    "recd",
    "received",
    "recvd",
    "autopay",
    "bpay",
    "purchase",
    "withdrawal",
    "cash", //
    // 5 — the narration function words that survive because `normalize_narration` did not strip
    // the prefix they belong to.
    "thank",
    "you",
    "to",
    "by",
    "in",
    "ind",
    "at",
    "on",
    "for",
    "from",
    "via",
    "and",
    "the",
    "of",
];

/// How many surviving segments make up a portion.
///
/// **Two, and the direction of the risk is why** (research R14). Fewer segments generalize
/// *more*, and over-broad is the failure that cannot be rescued in this slice: 1 collapses
/// `blue tokai` to `blue`. 3 keeps the city, splitting one chain into a memory per outlet.
const MAX_SEGMENTS: usize = 2;

/// The digit count at which a mixed token is read as a per-transaction reference rather than as
/// part of a name (FR-027a step 3). Four, not three — and R15 (2) is the price: a merchant whose
/// own name carries four digits loses it.
const REFERENCE_DIGITS: usize = 4;

/// Whether `c` ends a segment: whitespace, or one of the closed [`SEPARATORS`].
fn is_separator(c: char) -> bool {
    c.is_whitespace() || SEPARATORS.contains(&c)
}

/// The normalized narration split into ordered segments, empties included — they are discarded
/// downstream, so two adjacent separators need no special case here.
fn segments(normalized: &str) -> impl Iterator<Item = &str> {
    normalized.split(is_separator)
}

/// Whether a segment carries nothing a shop can be named by (FR-027a step 3).
fn is_discarded(segment: &str) -> bool {
    segment.chars().count() <= 1
        || segment.chars().all(|c| c.is_ascii_digit())
        || segment.chars().filter(char::is_ascii_digit).count() >= REFERENCE_DIGITS
        || STOP_WORDS.contains(&segment)
}

/// The stable merchant portion of `narration`, or `None` when nothing specific enough to
/// remember survives (FR-027d — the app then says it has nothing to remember rather than
/// remembering something meaningless).
///
/// Four ordered steps, and no others: normalize, split, discard, keep the first
/// [`MAX_SEGMENTS`] joined by one space.
pub fn merchant_portion(narration: &str) -> Option<String> {
    let normalized = normalize_narration(narration);
    let kept: Vec<&str> = segments(&normalized)
        .filter(|segment| !is_discarded(segment))
        .take(MAX_SEGMENTS)
        .collect();
    if kept.is_empty() {
        None
    } else {
        Some(kept.join(" "))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The stop-list is *closed*: it is read as a fixed set, so a duplicate or a stray uppercase
    /// entry is a word that silently does nothing (segments are lower-cased by normalization).
    #[test]
    fn the_stop_list_is_closed_and_contains_no_duplicates() {
        let mut sorted = STOP_WORDS.to_vec();
        sorted.sort_unstable();
        let mut unique = sorted.clone();
        unique.dedup();
        assert_eq!(sorted, unique, "a stop word is listed twice");
        assert_eq!(STOP_WORDS.len(), 76, "the stop-list changed size");
        for word in STOP_WORDS {
            assert_eq!(*word, word.to_lowercase(), "{word} would never match");
        }
    }

    /// A portion is never empty, never padded and never upper-case — the interface shows it to a
    /// person verbatim (FR-026a), and the memory is matched on exact equality (FR-027b).
    #[test]
    fn a_portion_is_always_trimmed_and_lower_case() {
        for narration in ["  POS   SYNTHETIC   MART  ", "UPI-SYNTHETICMART-778899"] {
            let portion = merchant_portion(narration).expect("a shop is named here");
            assert_eq!(portion, portion.trim());
            assert_eq!(portion, portion.to_lowercase());
            assert!(!portion.is_empty());
        }
    }
}
