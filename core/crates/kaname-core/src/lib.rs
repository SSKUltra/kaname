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
//! ## P1 TODO
//! Wire UniFFI (`uniffi::setup_scaffolding!()` + `#[uniffi::export]`) and produce the
//! `KanameCore.xcframework` consumed by `ios/`. The crate-type is already FFI-ready.

pub mod dedup;
pub mod model;

pub use dedup::{dedup_fingerprint, normalize_description};
pub use model::{Direction, Transaction};

/// Crate version, surfaced to the app so the UI can display the engine build.
pub fn engine_version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exposes_engine_version() {
        assert!(!engine_version().is_empty());
    }
}
