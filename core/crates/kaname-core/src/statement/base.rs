//! Statement-reader output records ported from the web engine's `base.py`.
//!
//! A reader turns extracted statement text into a [`ParsedStatement`]: the canonical
//! per-line [`ParsedTransaction`] rows plus statement-level metadata (billing period,
//! card last-4). Only the fields this slice needs are ported — the reconciliation
//! `printed_*` totals arrive with a later slice.

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
            confidence: 1.0,
        }
    }
}
