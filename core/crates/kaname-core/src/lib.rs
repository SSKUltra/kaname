//! `kaname-core` — the shared, platform-agnostic finance engine for Kaname.
//!
//! Deterministic parsing, categorization, de-duplication and reconciliation live
//! here so they can be reused across iOS (today), Android and desktop (later) via
//! [UniFFI](https://mozilla.github.io/uniffi-rs/) bindings, while each platform keeps
//! a fully native UI.
//!
//! # Boundaries (see `docs/kaname-ios-plan.md` and the constitution)
//! - **On-device only.** Nothing in the free/core engine performs network I/O.
//! - **PDF text extraction stays native.** The platform (iOS PDFKit) extracts lines
//!   and word x-positions and feeds them to the parser seam
//!   `read_lines(lines, full_text, first_row_words)` — the Rust core never embeds a
//!   PDF rendering engine.
//! - **Money is never a float.** All amounts use [`rust_decimal::Decimal`].
//!
//! ## Swift bindings (UniFFI)
//! `uniffi::setup_scaffolding!()` wires the FFI scaffolding and `#[uniffi::export]`
//! exposes engine functions (e.g. `engine_version()`) to Swift. The
//! `KanameCoreFFI.xcframework` and generated `KanameCore.swift` are produced by
//! `make core-xcframework`.

pub mod dedup;
mod ffi;
pub mod model;
pub mod statement;

pub use dedup::{dedup_fingerprint, normalize_description};
pub use ffi::{
    au_bank_claims, check_balance_chain, federal_bank_claims, federal_claims, hdfc_bank_claims,
    hdfc_claims, icici_bank_claims, icici_claims, iob_claims, read_au_bank_statement,
    read_federal_bank_statement, read_federal_statement, read_hdfc_bank_statement,
    read_hdfc_statement, read_icici_bank_statement, read_icici_statement, read_iob_statement,
    read_sbi_statement, read_yes_statement, sbi_claims, yes_claims,
};
pub use model::{Direction, Transaction};
pub use statement::balance_chain::{ChainResult, ChainStatus, Suspect};
pub use statement::{DirectionSource, LedgerMetadata, ParsedStatement, ParsedTransaction, Word};

uniffi::setup_scaffolding!();

/// Crate version, surfaced to the app so the UI can display the engine build.
///
/// Returns an owned `String` (not `&'static str`) because UniFFI exports cannot
/// return borrowed data; the value is still `CARGO_PKG_VERSION`.
#[uniffi::export]
pub fn engine_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exposes_engine_version() {
        assert!(!engine_version().is_empty());
    }
}
