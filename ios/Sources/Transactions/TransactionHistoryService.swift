import Foundation
import KanameCore

/// The one way the transaction list reaches the engine.
///
/// A protocol so the view model's tests need no SQLCipher database, and so the concrete actor
/// below is the only place in the app that holds a `Store` for reading history.
protocol TransactionHistoryReading: Sendable {
    /// One page. `cursor == nil` starts at the newest end of the sequence.
    func page(accountID: String?, cursor: HistoryCursor?, limit: UInt32) async throws -> HistoryPage

    /// Every account, in the front door's order, with their live counts.
    func accountSummaries() async throws -> [AccountSummary]
}

/// The engine's only caller — and deliberately nothing more than that.
///
/// It is an `actor` so no engine call ever happens on the main thread, and a **transport** so
/// there is exactly one place that decides which rows exist and in what order: the engine. It
/// filters nothing, sorts nothing, groups nothing, de-duplicates nothing and counts nothing of
/// its own, and it holds no cache. Every one of those would be a second opinion about a
/// person's transactions, and the whole point of this slice is that there is only one.
actor TransactionHistoryService: TransactionHistoryReading {
    private let open: @Sendable () throws -> Store
    private var opened: Store?

    init(store: Store) {
        open = { store }
    }

    /// Opened on first use, **inside the actor**. Opening the encrypted database is the one
    /// piece of I/O on this path that is not a read, and the list is reached from a view body
    /// — so handing the actor a way to open rather than an open store is what keeps SQLCipher
    /// off the main thread (FR-057).
    init(opening open: @escaping @Sendable () throws -> Store) {
        self.open = open
    }

    func page(accountID: String?, cursor: HistoryCursor?, limit: UInt32) throws -> HistoryPage {
        do {
            return try store().historyPage(
                query: HistoryQuery(accountId: accountID, cursor: cursor, limit: limit))
        } catch {
            // Mapped at the boundary: nothing the store says about a row travels any further
            // than this line (FR-063).
            throw TransactionListError(mapping: error)
        }
    }

    func accountSummaries() throws -> [AccountSummary] {
        do {
            return try store().accountSummaries()
        } catch {
            throw TransactionListError(mapping: error)
        }
    }

    /// A database that will not open is a screen that says so — reached through the same path
    /// a later read failure takes, so there is one way for this screen to be unavailable.
    private func store() throws -> Store {
        if let opened { return opened }
        let store = try open()
        opened = store
        return store
    }
}
