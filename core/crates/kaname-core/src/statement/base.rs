//! Statement-reader output records ported from the web engine's `base.py`.
//!
//! A reader turns extracted statement text into a [`ParsedStatement`]: the canonical
//! per-line [`ParsedTransaction`] rows plus statement-level metadata (billing period,
//! card last-4) and the printed balances/totals that drive reconciliation.

use chrono::NaiveDate;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};

use crate::model::Direction;

/// Raw statement rows and captured errored lines are bounded to this many codepoints.
pub const MAX_RAW: usize = 240;

/// Codepoint-safe truncation (never slices in the middle of a multibyte character).
pub fn truncate_chars(s: &str, max: usize) -> String {
    s.chars().take(max).collect()
}

/// How a bank-account (ledger) row's [`Direction`] was decided — the trust signal the
/// balance-chain check consults. `BalanceDelta` (and an `OpeningBalance`-anchored first
/// row) are reliable; the two `Row1*` fallbacks mean no predecessor balance was
/// available, so the run is surfaced for review rather than silently trusted.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum DirectionSource {
    /// First row anchored by a printed opening balance.
    OpeningBalance,
    /// Derived from the running-balance delta against the previous row.
    BalanceDelta,
    /// First row bootstrapped from the amount word's x-position (withdrawal vs deposit
    /// column) — a fallback that forces the balance-chain to `NeedsReview`.
    Row1XPosition,
    /// First row fell back to a provisional direction — also forces `NeedsReview`.
    Row1Provisional,
}

/// One word of the first anchor row's text plus its horizontal extent, supplied by the
/// native platform (iOS PDFKit) for the row-1 x-position bootstrap. The x-coordinates
/// are layout points (not money), so `f64` is appropriate here — amounts stay
/// [`Decimal`]. The core never opens a PDF (constitution: platform boundary).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct Word {
    pub text: String,
    pub x0: f64,
    pub x1: f64,
}

/// Ledger-specific per-row metadata for bank-account statements: the printed running
/// balance, its delta from the previous row, whether the printed amount reconciles with
/// that delta (`amount == |delta|`), and how the direction was decided. Absent (`None`)
/// on credit-card rows, whose direction comes from an explicit `Dr`/`Cr` marker.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct LedgerMetadata {
    pub balance: Decimal,
    pub balance_delta: Option<Decimal>,
    pub amount_matches_delta: bool,
    pub is_suspect: bool,
    pub direction_source: DirectionSource,
    pub serial: String,
}

/// One successfully-parsed statement row. Distinct from the normalized
/// [`crate::model::Transaction`] used by dedup — this is the raw reader output; a later
/// slice maps it into a `Transaction`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct ParsedTransaction {
    pub value_date: NaiveDate,
    pub amount: Decimal,
    pub direction: Direction,
    pub currency: String,
    pub description_raw: String,
    pub bank_code: String,
    /// Present only for bank-account (ledger) rows; `None` for credit-card rows.
    pub ledger: Option<LedgerMetadata>,
}

/// The full result of reading one statement.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct ParsedStatement {
    pub bank_code: String,
    /// Cleanly-parsed rows, in input order. May be empty (no rows → empty, no error).
    pub lines: Vec<ParsedTransaction>,
    /// Raw text of rows that matched the shape but whose fields would not parse, so the
    /// caller can surface them for review rather than dropping them silently.
    pub errored_lines: Vec<String>,
    pub period_start: Option<NaiveDate>,
    pub period_end: Option<NaiveDate>,
    pub card_last4: Option<String>,
    /// Printed (or, when only derivable, back-derived) opening balance of a bank-account
    /// statement — the anchor the balance-chain check walks from. `None` for credit-card
    /// statements and bank statements with no recoverable opening balance.
    pub printed_opening_balance: Option<Decimal>,
    /// Printed closing balance of a bank-account statement (the last row's running
    /// balance). `None` for credit-card statements.
    pub printed_closing_balance: Option<Decimal>,
    /// Printed per-statement debit total, as printed by the issuer (an `ACCOUNT SUMMARY`
    /// block or a "Purchases … Dr" figure). Surfaced only by the Yes/Kiwi and IOB
    /// credit-card readers; `None` otherwise. Drives the primary reconcile check.
    pub printed_total_debits: Option<Decimal>,
    /// Printed per-statement credit total (a "Payment & Credits Received … Cr" figure, or the
    /// `ACCOUNT SUMMARY` credits column). Surfaced only by Yes/Kiwi and IOB; `None` otherwise.
    pub printed_total_credits: Option<Decimal>,
    pub confidence: f64,
}

impl ParsedStatement {
    /// An empty statement for `bank_code`, with `confidence` defaulting to `1.0`.
    pub fn new(bank_code: impl Into<String>) -> Self {
        Self {
            bank_code: bank_code.into(),
            lines: Vec::new(),
            errored_lines: Vec::new(),
            period_start: None,
            period_end: None,
            card_last4: None,
            printed_opening_balance: None,
            printed_closing_balance: None,
            printed_total_debits: None,
            printed_total_credits: None,
            confidence: 1.0,
        }
    }
}
