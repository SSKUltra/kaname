//! Issuer-claim matching primitives.
//!
//! A statement is identified by the literals it *prints about itself*, never by what its
//! transaction rows happen to mention. This module supplies the two projections every
//! reader's `claims` fn matches against — the identity region (the document minus its
//! transaction rows) and the header region (the document's title block) — plus the
//! whitespace-insensitive comparison that survives a column-major text layer.
