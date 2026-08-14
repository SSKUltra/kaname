import Foundation
import KanameCore
import Observation

/// The transaction list's state: what has been read so far, where the next read resumes, and
/// which population is being read.
///
/// Everything it owns is presentational. The order the rows arrive in is the engine's and is
/// never touched; the filter is a value handed *to* the engine, not a predicate applied after
/// it; and the only thing this type genuinely decides is where a page boundary falls and where
/// a date group begins.
@MainActor
@Observable
final class TransactionListViewModel {
    enum State: Equatable {
        case loading
        case showing
        case empty(EmptyKind)
        case unavailable
    }

    private(set) var state: State = .loading
    private(set) var groups: [DateGroup] = []
    /// Always `.all` at init, and never written anywhere that survives a launch: a person who
    /// filtered three days ago must not open the app to a subset of their own spending and
    /// mistake it for all of it (FR-041).
    private(set) var filter: AccountFilter = .all
    private(set) var isLoadingMore = false

    private let history: any TransactionHistoryReading
    private let clock: @Sendable () -> Date
    private let pageSize: UInt32

    /// The resume point, held here and nowhere else. Opaque: no code reads a field of it.
    private var cursor: HistoryCursor?
    private var isExhausted = false
    private var summaries: [AccountSummary] = []

    /// How close to the end a row has to be before the next page is worth asking for.
    private static let prefetchDistance = 10

    init(
        history: any TransactionHistoryReading,
        clock: @escaping @Sendable () -> Date = { Date() },
        pageSize: UInt32 = 50
    ) {
        self.history = history
        self.clock = clock
        self.pageSize = pageSize
    }

    // MARK: - Reading

    func onAppear() async {
        guard groups.isEmpty else { return }
        await reload()
    }

    /// Restrict the list to one account — the same list with fewer rows in it, read back from
    /// the engine rather than filtered here, so nothing of the previous population can survive
    /// (FR-040, FR-042).
    func setFilter(_ filter: AccountFilter) async {
        self.filter = filter
        await reload()
    }

    func clearFilter() async {
        await setFilter(.all)
    }

    /// Ask for the next page when the person has scrolled near the end.
    ///
    /// Idempotent per cursor: a `List` calls this several times a second while scrolling, and
    /// every call after the first for a given resume point returns without touching the
    /// engine. The guard is set **before** the first suspension, so two calls that arrive
    /// while a read is in flight cannot both get past it (FR-044).
    func loadMoreIfNeeded(currentRowID: String) async {
        guard case .showing = state, !isLoadingMore, !isExhausted, let cursor else { return }
        guard isNearTheEnd(currentRowID) else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            apply(try await history.page(accountID: filter.accountID, cursor: cursor, limit: pageSize))
        } catch {
            // A page that failed must not throw away what the person is already reading. The
            // cursor is left intact, so the next scroll retries rather than ending the list
            // early and quietly.
        }
    }

    private func reload() async {
        state = .loading
        groups = []
        cursor = nil
        isExhausted = false
        isLoadingMore = false
        do {
            summaries = try await history.accountSummaries()
            apply(try await history.page(accountID: filter.accountID, cursor: nil, limit: pageSize))
            state =
                groups.isEmpty
                ? .empty(EmptyKind.decide(summaries: summaries, filter: filter))
                : .showing
        } catch {
            state = .unavailable
        }
    }

    // MARK: - Grouping

    /// Fold a page into the groups already on screen.
    ///
    /// **Incrementally**, seeded with the open group: a page boundary that falls inside a date
    /// appends to the group already showing rather than starting a second one with the same
    /// heading. Grouping the whole sequence at once and grouping it a page at a time therefore
    /// give the same answer, which is what makes the heading a person sees independent of how
    /// far they happened to scroll before it appeared.
    private func apply(_ page: HistoryPage) {
        let now = clock()
        var incoming: [DateGroup] = []
        for historyRow in page.rows {
            let row = TransactionRow(historyRow)
            if let open = incoming.last, open.id == row.isoDate {
                incoming[incoming.count - 1] = open.appending([row])
            } else {
                incoming.append(
                    DateGroup(
                        id: row.isoDate,
                        date: row.date,
                        heading: DateGroup.heading(for: row.date, now: now),
                        rows: [row]
                    ))
            }
        }

        if let first = incoming.first, let open = groups.last, open.id == first.id {
            groups[groups.count - 1] = open.appending(first.rows)
            groups.append(contentsOf: incoming.dropFirst())
        } else {
            groups.append(contentsOf: incoming)
        }

        cursor = page.cursor
        isExhausted = page.cursor == nil
    }

    private func isNearTheEnd(_ rowID: String) -> Bool {
        let ids = groups.flatMap(\.rows).map(\.id)
        guard let index = ids.lastIndex(of: rowID) else { return false }
        return ids.count - index <= Self.prefetchDistance
    }
}

extension DateGroup {
    /// The same group with more rows in it. Nothing is recomputed — the heading and the date
    /// belong to the date, not to how many rows have arrived under it.
    func appending(_ more: [TransactionRow]) -> DateGroup {
        DateGroup(id: id, date: date, heading: heading, rows: rows + more)
    }
}

extension TransactionListViewModel {
    /// The real wiring: the process's one `Store`, read through an actor.
    ///
    /// A store that cannot be opened is a screen that says so, not a crash and not an empty
    /// list — an empty list would tell a person their transactions are gone.
    static func live() -> TransactionListViewModel {
        let history: any TransactionHistoryReading
        do {
            history = TransactionHistoryService(store: try StoreProvider.shared())
        } catch {
            history = UnavailableHistory()
        }
        return TransactionListViewModel(history: history)
    }
}

/// Stands in when the database could not be opened at all, so the screen reaches
/// `.unavailable` through exactly the same path a later failure would.
private struct UnavailableHistory: TransactionHistoryReading {
    func page(accountID: String?, cursor: HistoryCursor?, limit: UInt32) async throws -> HistoryPage {
        throw TransactionListError.unavailable
    }

    func accountSummaries() async throws -> [AccountSummary] {
        throw TransactionListError.unavailable
    }
}
