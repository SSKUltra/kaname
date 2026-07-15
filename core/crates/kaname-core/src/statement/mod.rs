//! Statement-parsing subsystem — the on-device port of the web engine's
//! `statement_readers`. Turns already-extracted statement text (lines + full text,
//! produced natively by the platform, e.g. iOS PDFKit) into a [`ParsedStatement`].
//!
//! The core NEVER embeds a PDF engine (constitution: platform boundary). The
//! `read_lines` seam ([`line_reader`]) is the reusable "one transaction per text line"
//! reader that each issuer ([`icici`], and later HDFC/SBI/Yes/Federal) configures.

pub mod base;
pub mod common;
pub mod hdfc;
pub mod icici;
pub mod line_reader;
pub mod polarity;

pub use base::{ParsedStatement, ParsedTransaction};
