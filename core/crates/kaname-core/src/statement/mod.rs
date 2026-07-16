//! Statement-parsing subsystem — the on-device port of the web engine's
//! `statement_readers`. Turns already-extracted statement text (lines + full text,
//! produced natively by the platform, e.g. iOS PDFKit) into a [`ParsedStatement`].
//!
//! The core NEVER embeds a PDF engine (constitution: platform boundary). The
//! `read_lines` seam ([`line_reader`]) is the reusable "one transaction per text line"
//! reader that each issuer ([`icici`], HDFC, SBI, Yes, [`federal`]) configures.

pub mod balance_chain;
pub mod base;
pub mod common;
pub mod federal;
pub mod hdfc;
pub mod hdfc_bank;
pub mod icici;
pub mod icici_bank;
pub mod ledger_reader;
pub mod line_reader;
pub mod polarity;
pub mod sbi;
pub mod yes;

pub use base::{DirectionSource, LedgerMetadata, ParsedStatement, ParsedTransaction, Word};
