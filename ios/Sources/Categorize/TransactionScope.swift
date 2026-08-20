import Foundation

/// What the transaction list is being asked for: which account, and whether to show only the
/// rows nobody has answered yet.
///
/// **One value, two axes** — because there is exactly one transaction list, and both of these
/// are questions being asked of it rather than screens of their own (contract §2). A second
/// `.navigationDestination` for "just the unfiled ones" would give one screen two identities,
/// two back-stack behaviours and, eventually, two sets of empty states.
///
/// 018's `AccountFilter` is reused unchanged rather than reimplemented; this type wraps it.
/// It lives here rather than beside `AccountFilter` because `TransactionListModels.swift` is at
/// 332 lines against a hard 400-line limit and is the next file at risk (contract preamble).
struct TransactionScope: Hashable, Codable, Sendable {
    var filter: AccountFilter
    /// The narrowing, passed to the engine verbatim as `HistoryQuery.uncategorizedOnly`. The
    /// platform never decides which rows are unanswered — it asks (FR-039, FR-078).
    var uncategorizedOnly: Bool

    init(filter: AccountFilter, uncategorizedOnly: Bool = false) {
        self.filter = filter
        self.uncategorizedOnly = uncategorizedOnly
    }

    /// The whole history, unnarrowed — what the front door's link asks for.
    static let everything = TransactionScope(filter: .all, uncategorizedOnly: false)
}
