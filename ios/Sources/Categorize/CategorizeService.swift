import Foundation
import KanameCore

/// The one way the categorize surfaces reach the engine.
///
/// A protocol so the views' tests need no SQLCipher database, and so the actor below is the
/// only place in the app that holds a `Store` for changing a category.
protocol CategorizeWriting: Sendable {
    /// Record the person's decision. `category == nil` is a **deliberate blank** — a decision,
    /// not an absence of one — and the engine protects it exactly as it protects a category.
    func correct(_ id: String, to category: CategoryRef?, remember: Bool) async throws
        -> CorrectionOutcome

    /// Every category the engine knows, in the engine's own order.
    func categories() async throws -> [KanameCore.Category]

    /// How many transactions, store-wide, nobody has answered yet — **the engine's number**.
    func uncategorizedCount() async throws -> UInt32
}

/// The engine's only caller for a correction — and deliberately nothing more than that.
///
/// It is an `actor` so no engine call happens on the main thread, and a **transport**: every
/// method is a thin pass-through to exactly one engine call. It must not filter, count, sum,
/// group, sort by a derived key, or take a second opinion about anything the engine returned
/// (FR-076, FR-077, FR-078).
///
/// `uncategorizedCount()` in particular hands back the engine's number verbatim. 018 moved the
/// front door's count out of Swift and into SQL precisely because a count computed beside a
/// list is a count that will eventually disagree with it; this is the seam where it would creep
/// back, and `import-path-audit.sh` scans 5–8 now watch this directory for exactly that.
actor CategorizeService: CategorizeWriting {
    private let open: @Sendable () throws -> Store
    private var opened: Store?

    init(store: Store) {
        open = { store }
    }

    /// Opened on first use, **inside the actor** — the same shape as
    /// `TransactionHistoryService`, and for the same reason: opening the encrypted database is
    /// I/O, and these surfaces are reached from a view body (FR-057).
    init(opening open: @escaping @Sendable () throws -> Store) {
        self.open = open
    }

    func correct(
        _ id: String, to category: CategoryRef?, remember: Bool
    ) throws -> CorrectionOutcome {
        do {
            return try store().setTransactionCategory(
                transactionId: id, category: category, remember: remember)
        } catch {
            // Mapped at the boundary: nothing the store says about a row travels further than
            // this line.
            throw TransactionListError(mapping: error)
        }
    }

    func categories() throws -> [KanameCore.Category] {
        do {
            return try store().listCategories()
        } catch {
            throw TransactionListError(mapping: error)
        }
    }

    func uncategorizedCount() throws -> UInt32 {
        do {
            return try store().uncategorizedCount()
        } catch {
            throw TransactionListError(mapping: error)
        }
    }

    private func store() throws -> Store {
        if let opened { return opened }
        let store = try open()
        opened = store
        return store
    }
}

extension CategorizeService {
    /// The app's own service, over the app's own encrypted store — opened lazily, inside the
    /// actor, exactly as the history service is.
    static func live() -> CategorizeService {
        CategorizeService(opening: { try StoreProvider.shared() })
    }
}
