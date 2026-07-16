//! The reusable balance-ledger reader for bank-account (savings/current) statements,
//! ported from the web engine's `_ledger_reader.py`.
//!
//! A bank-account statement is a **Withdrawal / Deposit / running-Balance ledger with
//! NO `Dr`/`Cr` marker** — the credit-card [`line_reader`](crate::statement::line_reader)
//! (one signed amount + a trailing `Dr`/`Cr`) structurally cannot read it. This reader
//! instead derives each transaction's **direction from the running-balance delta**
//! (debit when the balance falls, credit when it rises) and uses the printed amount as
//! an *independent* integrity check (`amount == |balance delta|`).
//!
//! Design (ported 1:1):
//! - **Anchor lines** — a transaction is a flat-text line ending in two money tokens
//!   `... <amount> <balance>` (a per-issuer [`LedgerReaderConfig::anchor_res`] with named
//!   groups `serial`, `date`, `amount` (or a `withdrawal`/`deposit` pair), `balance`, and
//!   optional `desc`). Per-page headers don't match; cheque numbers carry no decimals so
//!   never match a money group.
//! - **Narration stitching** — wrapped detail is reassembled from the line immediately
//!   above an anchor plus the lines below it up to the next transaction.
//! - **Row-1 bootstrap** — the first row has no predecessor balance; the opening balance
//!   is taken from a printed `Opening Balance`/`B/F` line when present, else from the
//!   amount word's x-position (withdrawal column ⇒ debit) using the natively-supplied
//!   first-row [`Word`] geometry, else a provisional direction — the latter two force the
//!   balance-chain check to `NeedsReview`.
//! - **Chain-break** — a row whose printed amount ≠ its balance delta is **still
//!   persisted** with its delta-derived best-guess direction and flagged a suspect; only
//!   genuinely unparseable rows (bad date/amount/balance) go to `errored_lines`.
//!
//! The reader is pure and total (never panics). The core never opens a PDF: the
//! platform (iOS PDFKit) extracts the lines + first-row word geometry natively.

use std::collections::HashSet;
use std::sync::LazyLock;

use chrono::NaiveDate;
use regex::{Captures, Regex};
use rust_decimal::Decimal;

use crate::model::Direction;
use crate::statement::base::{
    truncate_chars, DirectionSource, LedgerMetadata, ParsedStatement, ParsedTransaction, Word,
    MAX_RAW,
};
use crate::statement::common::{parse_amount, parse_date};

// A withdrawal/deposit column value that may be a bare integer (e.g. `0`, `59`, `50000`)
// or carry decimals (`1,314.90`).
static MONEY_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[\d,]+\.\d{2}$").unwrap());

/// Per-issuer configuration for the balance-ledger reader. Only `bank_code`, `claim_all`
/// and `anchor_res` are required; the rest have sensible defaults.
pub trait LedgerReaderConfig {
    fn bank_code(&self) -> &'static str;

    /// Markers that must ALL be present for [`claims_ledger`] to accept the document —
    /// enough to tell this issuer's savings/current statement from its credit-card one.
    fn claim_all(&self) -> &'static [&'static str];

    /// The anchor row patterns, tried in order (first match wins). A bank may have
    /// several statement templates (classic + neobank/partner); each is one pattern.
    fn anchor_res(&self) -> Vec<&'static Regex>;

    /// Optional markers, ANY of which must also be present (empty ⇒ no such constraint).
    fn claim_any(&self) -> &'static [&'static str] {
        &[]
    }
    fn opening_balance_re(&self) -> Option<&'static Regex> {
        None
    }
    fn closing_balance_re(&self) -> Option<&'static Regex> {
        None
    }
    /// x-coordinate splitting the withdrawal (debit) column from the deposit (credit)
    /// column, for the row-1 geometry bootstrap. `None` disables that fallback.
    fn column_split_x(&self) -> Option<f64> {
        None
    }
    /// Direction assumed for a first row with neither a printed opening balance nor
    /// usable geometry. Defaults to debit; always surfaced `NeedsReview`.
    fn provisional_direction(&self) -> Direction {
        Direction::Debit
    }
    /// Populate statement-level metadata (period, account last-4) from the full text.
    fn enrich(&self, _statement: &mut ParsedStatement, _full_text: &str) {}
    /// Bank-account-aware account tail (trailing 4 of the printed account number) — NOT
    /// the credit-card masked-PAN matcher.
    fn account_tail(&self, _text: &str) -> Option<String> {
        None
    }
}

/// True when `cfg` recognises `text` as a bank-account statement for `bank_code`:
/// the issuer `bank_code` plus all of `claim_all` and (when set) any of `claim_any`.
pub fn claims_ledger<C: LedgerReaderConfig + ?Sized>(cfg: &C, text: &str, bank_code: &str) -> bool {
    if bank_code != cfg.bank_code() {
        return false;
    }
    let hay = text.to_lowercase();
    if !cfg
        .claim_all()
        .iter()
        .all(|m| hay.contains(&m.to_lowercase()))
    {
        return false;
    }
    cfg.claim_any().is_empty()
        || cfg
            .claim_any()
            .iter()
            .any(|m| hay.contains(&m.to_lowercase()))
}

/// A parsed transaction anchor line and its position in the page text.
struct Anchor {
    index: usize,
    serial: String,
    date: NaiveDate,
    amount: Decimal,
    balance: Decimal,
    inline_desc: String,
}

/// Parse already-extracted `lines` (+ `full_text` for enrichment and `first_row_words`
/// for the row-1 geometry bootstrap) into a [`ParsedStatement`]. Pure and total: an
/// anchor-shaped row whose date/amount/balance will not parse is captured in
/// `errored_lines`; a row whose amount ≠ its balance delta is flagged suspect but kept.
pub fn read_ledger_lines<C: LedgerReaderConfig + ?Sized>(
    cfg: &C,
    lines: &[String],
    full_text: &str,
    first_row_words: &[Word],
) -> ParsedStatement {
    let mut statement = ParsedStatement::new(cfg.bank_code());

    let opening = extract_balance(full_text, cfg.opening_balance_re());
    let (anchors, mut errored_indices) = find_anchors(cfg, lines);
    errored_indices.sort_unstable();
    for i in errored_indices {
        statement
            .errored_lines
            .push(truncate_chars(&lines[i], MAX_RAW));
    }
    if anchors.is_empty() {
        cfg.enrich(&mut statement, full_text);
        return statement;
    }

    let anchor_indices: HashSet<usize> = anchors.iter().map(|a| a.index).collect();
    let mut prev_balance: Option<Decimal> = opening;

    for k in 0..anchors.len() {
        let anchor = &anchors[k];
        let balance = anchor.balance;
        let amount = anchor.amount;
        let narration = stitch_narration(cfg, lines, &anchors, k, &anchor_indices);

        let (direction, source) = if k == 0 {
            let (direction, source, prev) =
                row1_direction(cfg, amount, balance, opening, first_row_words);
            prev_balance = Some(prev);
            (direction, source)
        } else if let Some(prev) = prev_balance {
            let direction = if balance < prev {
                Direction::Debit
            } else {
                Direction::Credit
            };
            (direction, DirectionSource::BalanceDelta)
        } else {
            (cfg.provisional_direction(), DirectionSource::BalanceDelta)
        };

        let delta = prev_balance.map(|prev| balance - prev);
        let amount_matches = delta.is_some_and(|d| amount == d.abs());

        statement.lines.push(ParsedTransaction {
            value_date: anchor.date,
            amount,
            direction,
            currency: "INR".to_string(),
            description_raw: truncate_chars(&narration, MAX_RAW),
            bank_code: cfg.bank_code().to_string(),
            ledger: Some(LedgerMetadata {
                balance,
                balance_delta: delta,
                amount_matches_delta: amount_matches,
                is_suspect: !amount_matches,
                direction_source: source,
                serial: anchor.serial.clone(),
            }),
        });
        prev_balance = Some(balance);
    }

    statement.printed_opening_balance = opening.or_else(|| derived_opening(&statement.lines[0]));
    statement.printed_closing_balance = Some(anchors[anchors.len() - 1].balance);

    cfg.enrich(&mut statement, full_text);
    statement
}

fn find_anchors<C: LedgerReaderConfig + ?Sized>(
    cfg: &C,
    lines: &[String],
) -> (Vec<Anchor>, Vec<usize>) {
    let patterns = cfg.anchor_res();
    let mut anchors: Vec<Anchor> = Vec::new();
    let mut errored: Vec<usize> = Vec::new();
    for (index, line) in lines.iter().enumerate() {
        let Some(caps) = patterns.iter().find_map(|re| re.captures(line)) else {
            continue;
        };
        let txn_date = caps.name("date").and_then(|m| parse_date(m.as_str()));
        let amount = anchor_amount(&caps);
        let balance = caps.name("balance").and_then(|m| parse_amount(m.as_str()));
        let (Some(txn_date), Some(amount), Some(balance)) = (txn_date, amount, balance) else {
            // Anchor-shaped but a field would not parse — capture for review.
            errored.push(index);
            continue;
        };
        let desc = caps.name("desc").map_or("", |m| m.as_str()).trim();
        let serial = caps.name("serial").map_or("", |m| m.as_str());
        anchors.push(Anchor {
            index,
            serial: serial.to_string(),
            date: txn_date,
            amount,
            balance,
            inline_desc: desc.to_string(),
        });
    }
    (anchors, errored)
}

/// The transaction amount. A single-amount template captures `amount`; a two-column
/// template captures a `withdrawal`/`deposit` pair where exactly one side is non-zero
/// (the other prints `0`/`0.00`/blank) — that non-zero side is the amount. Direction is
/// still derived from the balance delta, so the printed amount stays an independent check.
fn anchor_amount(caps: &Captures<'_>) -> Option<Decimal> {
    if let Some(m) = caps.name("amount") {
        return parse_amount(m.as_str());
    }
    let withdrawal = caps
        .name("withdrawal")
        .and_then(|m| loose_amount(m.as_str()));
    let deposit = caps.name("deposit").and_then(|m| loose_amount(m.as_str()));
    if let Some(w) = withdrawal {
        if !w.is_zero() {
            return Some(w);
        }
    }
    if let Some(d) = deposit {
        if !d.is_zero() {
            return Some(d);
        }
    }
    withdrawal.or(deposit)
}

/// Parse a withdrawal/deposit column value that may be a bare integer or carry decimals.
/// The anchor regex has already constrained the token shape, so we just strip Indian
/// grouping and parse.
fn loose_amount(token: &str) -> Option<Decimal> {
    let cleaned = token.replace(',', "");
    let cleaned = cleaned.trim();
    if cleaned.is_empty() {
        return None;
    }
    Decimal::from_str_exact(cleaned).ok()
}

fn stitch_narration<C: LedgerReaderConfig + ?Sized>(
    cfg: &C,
    lines: &[String],
    anchors: &[Anchor],
    k: usize,
    anchor_indices: &HashSet<usize>,
) -> String {
    let idx_k = anchors[k].index;
    let mut candidates: Vec<usize> = Vec::new();
    // Part A — the payer/VPA line immediately above this anchor.
    if idx_k >= 1 {
        candidates.push(idx_k - 1);
    }
    // Part B — detail lines below this anchor, up to (but excluding) the line immediately
    // above the next anchor, which belongs to the next transaction.
    let end = if k + 1 < anchors.len() {
        anchors[k + 1].index.saturating_sub(1)
    } else {
        lines.len()
    };
    candidates.extend((idx_k + 1)..end);

    let mut parts: Vec<String> = Vec::new();
    if !anchors[k].inline_desc.is_empty() {
        parts.push(anchors[k].inline_desc.clone());
    }
    for j in candidates {
        if anchor_indices.contains(&j) || j >= lines.len() {
            continue;
        }
        let text = lines[j].trim();
        if text.is_empty() || is_balance_line(cfg, text) {
            continue;
        }
        parts.push(text.to_string());
    }
    parts.join(" ").trim().to_string()
}

fn row1_direction<C: LedgerReaderConfig + ?Sized>(
    cfg: &C,
    amount: Decimal,
    balance: Decimal,
    opening: Option<Decimal>,
    first_row_words: &[Word],
) -> (Direction, DirectionSource, Decimal) {
    if let Some(opening) = opening {
        let direction = if balance < opening {
            Direction::Debit
        } else {
            Direction::Credit
        };
        return (direction, DirectionSource::OpeningBalance, opening);
    }
    if let Some(x_direction) = direction_from_x_position(cfg, amount, first_row_words) {
        let prev = if x_direction == Direction::Debit {
            balance + amount
        } else {
            balance - amount
        };
        return (x_direction, DirectionSource::Row1XPosition, prev);
    }
    let direction = cfg.provisional_direction();
    let prev = if direction == Direction::Debit {
        balance + amount
    } else {
        balance - amount
    };
    (direction, DirectionSource::Row1Provisional, prev)
}

fn direction_from_x_position<C: LedgerReaderConfig + ?Sized>(
    cfg: &C,
    amount: Decimal,
    first_row_words: &[Word],
) -> Option<Direction> {
    let split = cfg.column_split_x()?;
    if first_row_words.is_empty() {
        return None;
    }
    // Money words: those whose text is a `[\d,]+\.\d{2}` token.
    let money: Vec<(usize, Decimal)> = first_row_words
        .iter()
        .enumerate()
        .filter_map(|(i, w)| {
            let t = w.text.trim();
            if MONEY_RE.is_match(t) {
                parse_amount(t).map(|v| (i, v))
            } else {
                None
            }
        })
        .collect();
    if money.is_empty() {
        return None;
    }
    // The rightmost money word is the running balance; the amount sits to its left in
    // either the withdrawal (debit) or deposit (credit) column.
    let balance_idx = money
        .iter()
        .max_by(|a, b| {
            first_row_words[a.0]
                .x1
                .partial_cmp(&first_row_words[b.0].x1)
                .unwrap_or(std::cmp::Ordering::Equal)
        })
        .map(|(i, _)| *i)?;
    for (idx, value) in &money {
        if *idx == balance_idx {
            continue;
        }
        if *value == amount {
            let w = &first_row_words[*idx];
            let center = (w.x0 + w.x1) / 2.0;
            return Some(if center < split {
                Direction::Debit
            } else {
                Direction::Credit
            });
        }
    }
    None
}

fn is_balance_line<C: LedgerReaderConfig + ?Sized>(cfg: &C, text: &str) -> bool {
    if cfg.opening_balance_re().is_some_and(|re| re.is_match(text)) {
        return true;
    }
    cfg.closing_balance_re().is_some_and(|re| re.is_match(text))
}

fn extract_balance(full_text: &str, pattern: Option<&Regex>) -> Option<Decimal> {
    let caps = pattern?.captures(full_text)?;
    parse_amount(caps.get(1)?.as_str())
}

fn derived_opening(first_line: &ParsedTransaction) -> Option<Decimal> {
    let balance = first_line.ledger.as_ref()?.balance;
    Some(if first_line.direction == Direction::Debit {
        balance + first_line.amount
    } else {
        balance - first_line.amount
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    static TWO_COL_ANCHOR: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(
            r"^(?P<serial>\d{1,4})\s+(?P<date>\d{2}\.\d{2}\.\d{4})\s+(?P<desc>.*?)\s+(?P<withdrawal>[\d,]+(?:\.\d{2})?)\s+(?P<deposit>[\d,]+(?:\.\d{2})?)\s+(?P<balance>[\d,]+\.\d{2})\s*$",
        )
        .unwrap()
    });
    static TWO_COL_OPENING: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"(?i)Opening Balance\s+([\d,]+\.\d{2})").unwrap());

    struct TwoColumnReader;

    impl LedgerReaderConfig for TwoColumnReader {
        fn bank_code(&self) -> &'static str {
            "TEST2COL"
        }
        fn claim_all(&self) -> &'static [&'static str] {
            &["Test Bank"]
        }
        fn anchor_res(&self) -> Vec<&'static Regex> {
            vec![&TWO_COL_ANCHOR]
        }
        fn opening_balance_re(&self) -> Option<&'static Regex> {
            Some(&TWO_COL_OPENING)
        }
    }

    #[test]
    fn two_column_loose_integer_amount_picks_the_nonzero_side() {
        // Withdrawal column prints a bare integer `0`; the deposit side is the amount.
        let lines = vec![
            "Opening Balance 1,000.00".to_string(),
            "1 16.06.2025 SALARY 0 5000.00 6,000.00".to_string(),
            "2 17.06.2025 ATM 200.00 0 5,800.00".to_string(),
        ];
        let st = read_ledger_lines(&TwoColumnReader, &lines, &lines.join("\n"), &[]);
        assert_eq!(st.lines.len(), 2);
        // Deposit side (bare integer 5000) is the amount; balance rose ⇒ credit.
        assert_eq!(st.lines[0].amount, dec!(5000));
        assert_eq!(st.lines[0].direction, Direction::Credit);
        // Withdrawal side (200.00) is the amount; balance fell ⇒ debit.
        assert_eq!(st.lines[1].amount, dec!(200.00));
        assert_eq!(st.lines[1].direction, Direction::Debit);
    }

    #[test]
    fn direction_flips_with_the_balance_delta_not_the_amount() {
        // Same amount, opposite balance movement ⇒ opposite direction.
        let lines = vec![
            "Opening Balance 1,000.00".to_string(),
            "1 16.06.2025 X 500.00 500.00 500.00".to_string(), // withdrawal 500 → 500 (debit)
            "2 17.06.2025 Y 500.00 500.00 1,000.00".to_string(), // deposit 500 → 1000 (credit)
        ];
        let st = read_ledger_lines(&TwoColumnReader, &lines, &lines.join("\n"), &[]);
        assert_eq!(st.lines[0].direction, Direction::Debit);
        assert_eq!(st.lines[1].direction, Direction::Credit);
    }

    #[test]
    fn anchor_shaped_row_with_bad_balance_is_errored_not_dropped() {
        let lines = vec![
            "Opening Balance 1,000.00".to_string(),
            "1 16.06.2025 GOOD 200.00 0 800.00".to_string(),
            "2 99.99.9999 BADDATE 100.00 0 700.00".to_string(),
        ];
        let st = read_ledger_lines(&TwoColumnReader, &lines, &lines.join("\n"), &[]);
        assert_eq!(st.lines.len(), 1);
        assert_eq!(st.errored_lines.len(), 1);
        assert!(st.errored_lines[0].starts_with("2 99.99.9999"));
    }

    #[test]
    fn row1_provisional_source_when_no_opening_and_no_geometry() {
        let lines = vec!["1 16.06.2025 X 200.00 0 800.00".to_string()];
        let st = read_ledger_lines(&TwoColumnReader, &lines, "Test Bank", &[]);
        assert_eq!(st.lines.len(), 1);
        let ledger = st.lines[0].ledger.as_ref().unwrap();
        assert_eq!(ledger.direction_source, DirectionSource::Row1Provisional);
    }

    #[test]
    fn row1_xposition_uses_first_row_word_geometry() {
        // No opening balance; the amount word (200.00) sits left of the split ⇒ debit.
        let lines = vec!["1 16.06.2025 X 200.00 0 800.00".to_string()];
        struct GeomReader;
        impl LedgerReaderConfig for GeomReader {
            fn bank_code(&self) -> &'static str {
                "TEST2COL"
            }
            fn claim_all(&self) -> &'static [&'static str] {
                &["Test Bank"]
            }
            fn anchor_res(&self) -> Vec<&'static Regex> {
                vec![&TWO_COL_ANCHOR]
            }
            fn column_split_x(&self) -> Option<f64> {
                Some(400.0)
            }
        }
        let words = vec![
            Word {
                text: "200.00".to_string(),
                x0: 300.0,
                x1: 340.0,
            },
            Word {
                text: "800.00".to_string(),
                x0: 500.0,
                x1: 540.0,
            },
        ];
        let st = read_ledger_lines(&GeomReader, &lines, "Test Bank", &words);
        let ledger = st.lines[0].ledger.as_ref().unwrap();
        assert_eq!(ledger.direction_source, DirectionSource::Row1XPosition);
        assert_eq!(st.lines[0].direction, Direction::Debit); // left of split
    }

    #[test]
    fn claims_requires_bank_code_and_markers() {
        assert!(claims_ledger(
            &TwoColumnReader,
            "Test Bank statement",
            "TEST2COL"
        ));
        assert!(!claims_ledger(&TwoColumnReader, "Test Bank", "OTHER"));
        assert!(!claims_ledger(
            &TwoColumnReader,
            "Some other bank",
            "TEST2COL"
        ));
    }
}
