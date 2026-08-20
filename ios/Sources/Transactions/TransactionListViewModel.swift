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

    /// The row at the top of the viewport, as the view last reported it.
    ///
    /// Captured before a refresh and written back after, so an import cannot take a person's
    /// place in their own history away from them (FR-056). It is a row **id**, not an offset:
    /// an import inserts rows above, and any number would be pointing somewhere else by the
    /// time it was restored.
    private(set) var anchorRowID: String?

    private let history: any TransactionHistoryReading
    private let clock: @Sendable () -> Date
    private let pageSize: UInt32
    /// Whether this screen is the worklist. Fixed for the life of the model, because it is
    /// which list a person opened rather than something they change while reading it — the
    /// account filter is the axis that moves.
    ///
    /// 🚨 It is **handed to the engine** and never used to filter a page that has come back
    /// (L1, FR-038, FR-076, SC-024). A screen that filtered its own page would be a second
    /// definition of "unanswered", and the entry point's count — which is SQL — would then be
    /// a count of a different set from the one on screen.
    private let uncategorizedOnly: Bool

    /// The resume point, held here and nowhere else. Opaque: no code reads a field of it.
    private var cursor: HistoryCursor?
    private var isExhausted = false
    private var summaries: [AccountSummary] = []
    /// How many pages have been read into what is on screen — the size of the re-read a
    /// refresh has to do to hand back what the person already had.
    private var pagesHeld = 0
    /// Bumped whenever the population changes underneath an in-flight page read. A page that
    /// was asked for before a filter change or a refresh belongs to a list that no longer
    /// exists, and appending it would put another account's rows under this one's heading.
    private var generation = 0

    // MARK: - The scope, as words

    /// Which account is being shown, said outright. The filtered state is carried by this
    /// string and never by styling, a colour or the glass the button happens to wear
    /// (FR-038, FR-071).
    var scopeTitle: String {
        filter.accountName ?? TransactionListStrings.scopeAll
    }

    /// The masked last four beneath the name — the same identity shape the front door shows,
    /// and absent entirely for an account that never learned its own last four (FR-003).
    var scopeSubtitle: String? {
        filter.accountLast4.map(TransactionListStrings.maskedLast4)
    }

    var scopeAnnouncement: String {
        TransactionListStrings.scopeAnnouncement(name: filter.accountName, last4: filter.accountLast4)
    }

    var isFiltered: Bool { filter.accountID != nil }

    /// Every account a person can narrow to, in the front door's own order — the same order
    /// the combined list breaks ties with, so one screen never contradicts another (FR-030).
    var availableFilters: [AccountFilter] {
        summaries.map { .account(id: $0.id, name: $0.name, last4: $0.last4) }
    }

    /// Whether an empty state's action is the screen's **only** glass, and may therefore be
    /// prominent (design note D2).
    ///
    /// True in exactly one state: nothing imported at all, where there is no filter bar to
    /// compete with it. Everywhere else the bar is on screen, and two prominent elements make
    /// prominence mean nothing.
    var emptyActionIsProminent: Bool { !showsFilterChrome }

    /// The filter chrome has nothing to say when there are no accounts to choose between: a
    /// bar reading "All accounts" above a screen saying nothing was imported is a
    /// contradiction (design note D3).
    var showsFilterChrome: Bool { !summaries.isEmpty }

    /// How close to the end a row has to be before the next page is worth asking for.
    private static let prefetchDistance = 10

    init(
        history: any TransactionHistoryReading,
        clock: @escaping @Sendable () -> Date = { Date() },
        pageSize: UInt32 = 50,
        uncategorizedOnly: Bool = false
    ) {
        self.history = history
        self.clock = clock
        self.pageSize = pageSize
        self.uncategorizedOnly = uncategorizedOnly
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
        let token = generation
        do {
            let page = try await history.page(
                accountID: filter.accountID, uncategorizedOnly: uncategorizedOnly,
                cursor: cursor, limit: pageSize)
            // The population may have been replaced while this page was in flight — by a
            // filter, or by an import's refresh. This page describes the old one.
            guard token == generation else { return }
            apply(page)
        } catch {
            // A page that failed must not throw away what the person is already reading. The
            // cursor is left intact, so the next scroll retries rather than ending the list
            // early and quietly.
        }
    }

    /// The row the person is reading, as the view reports it while they scroll.
    func anchorChanged(to id: String?) {
        anchorRowID = id
    }

    /// Keep the list current with whatever an import commits (FR-053).
    ///
    /// The loop is the caller's — the screen's `.task` — so the subscription is cancelled with
    /// the screen and nothing outlives the view that asked for it.
    func refreshWhenImportsComplete(_ signal: ImportCompletionSignal = .shared) async {
        for await _ in signal.events {
            await refreshAfterImport()
        }
    }

    /// Re-read what is already on screen, as **one** change.
    ///
    /// Everything the person is holding is read again from page 1 with the same filter, and
    /// swapped in at the end — so the list never trickles new rows in a few at a time, and a
    /// person is never reading a sequence that is half of one moment and half of another
    /// (FR-053, FR-054). The filter is not touched at all, which is the strongest form of
    /// FR-056's promise, and the anchor is put back exactly as it was found.
    ///
    /// A failed re-read leaves the screen precisely as it was: an import is not a reason to
    /// take a person's transactions away.
    func refreshAfterImport() async {
        let anchor = anchorRowID
        let held = max(pagesHeld, 1)
        generation += 1
        let token = generation
        let now = clock()
        var fresh: [DateGroup] = []
        var resume: HistoryCursor?
        var read = 0

        do {
            let latest = try await history.accountSummaries()
            repeat {
                let page = try await history.page(
                    accountID: filter.accountID, uncategorizedOnly: uncategorizedOnly,
                    cursor: resume, limit: pageSize)
                guard token == generation else { return }
                fresh = Self.fold(page, into: fresh, now: now)
                resume = page.cursor
                read += 1
                // Read past what was held only when the anchor has been pushed down by rows
                // that arrived above it — otherwise the person's own row would be off the end
                // of what was re-read, and restoring it would be restoring nothing.
            } while resume != nil && (read < held || !Self.contains(anchor, in: fresh))

            summaries = latest
            groups = fresh
            cursor = resume
            isExhausted = resume == nil
            pagesHeld = read
            state = fresh.isEmpty ? .empty(emptyKind(for: latest)) : .showing
            // Written back last, and written even when it has not changed: the write is what
            // tells the scroll position where to go after the rows underneath it moved.
            anchorRowID = anchor
        } catch {
            // Nothing is assigned on this path — the screen keeps every row it had.
        }
    }

    /// Re-read after a person changed a category — the same single-change re-read an import
    /// gets, for the same reason: something the engine knows about these rows changed, and the
    /// screen's job is to show what the engine now says rather than to edit its own copy.
    func refreshAfterCorrection() async {
        await refreshAfterImport()
    }

    private func reload() async {
        state = .loading
        groups = []
        cursor = nil
        isExhausted = false
        isLoadingMore = false
        pagesHeld = 0
        generation += 1
        let token = generation
        do {
            let latest = try await history.accountSummaries()
            let page = try await history.page(
                accountID: filter.accountID, uncategorizedOnly: uncategorizedOnly,
                cursor: nil, limit: pageSize)
            guard token == generation else { return }
            summaries = latest
            apply(page)
            state = groups.isEmpty ? .empty(emptyKind(for: summaries)) : .showing
        } catch {
            state = .unavailable
        }
    }

    /// Which empty this is, asked the same way from both read paths — with the narrowing
    /// included, so a worklist that has been worked to zero says so instead of borrowing one
    /// of 018's six sentences about absence (L4, FR-042a, FR-042b).
    private func emptyKind(for summaries: [AccountSummary]) -> EmptyKind {
        EmptyKind.decide(
            summaries: summaries, filter: filter, uncategorizedOnly: uncategorizedOnly)
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
        groups = Self.fold(page, into: groups, now: clock())
        cursor = page.cursor
        isExhausted = page.cursor == nil
        pagesHeld += 1
    }

    /// One page folded onto the groups already read. Pure, so the refresh can build a whole
    /// replacement sequence off to one side and swap it in as a single change.
    private static func fold(_ page: HistoryPage, into groups: [DateGroup], now: Date) -> [DateGroup] {
        var folded = groups
        for historyRow in page.rows {
            let row = TransactionRow(historyRow)
            if let open = folded.last, open.id == row.isoDate {
                folded[folded.count - 1] = open.appending([row])
            } else {
                folded.append(
                    DateGroup(
                        id: row.isoDate,
                        date: row.date,
                        heading: DateGroup.heading(for: row.date, now: now),
                        rows: [row]
                    ))
            }
        }
        return folded
    }

    /// Whether the row the person was reading is among the rows read back. A `nil` anchor —
    /// nothing scrolled yet — is satisfied by anything.
    private static func contains(_ rowID: String?, in groups: [DateGroup]) -> Bool {
        guard let rowID else { return true }
        return groups.contains { $0.rows.contains { $0.id == rowID } }
    }

    /// Whether this row is among the last few — asked several times a second while a person
    /// scrolls, so it walks backwards by index over at most `prefetchDistance` rows rather
    /// than flattening every page read so far. A list ten thousand rows deep would otherwise
    /// allocate ten thousand ids to answer a question about ten of them (FR-057, FR-061).
    ///
    /// It re-decides nothing: the sequence is exactly the one the engine returned, walked from
    /// the end it already has.
    private func isNearTheEnd(_ rowID: String) -> Bool {
        var remaining = Self.prefetchDistance
        var groupIndex = groups.count - 1
        while groupIndex >= 0 {
            let rows = groups[groupIndex].rows
            var rowIndex = rows.count - 1
            while rowIndex >= 0 {
                if rows[rowIndex].id == rowID { return true }
                remaining -= 1
                if remaining <= 0 { return false }
                rowIndex -= 1
            }
            groupIndex -= 1
        }
        return false
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
    /// The store is *opened* inside that actor too. This is called from a view body, and a
    /// database that opens on the main thread is a screen that hitches on the way in — a
    /// store that cannot be opened at all then reaches `.unavailable` through exactly the
    /// same path a later read failure would, because an empty list would tell a person their
    /// transactions are gone.
    ///
    /// - Parameter uncategorizedOnly: the scope the screen was pushed with. There is one
    ///   transaction list and one view model behind it; the worklist is this flag, not a
    ///   second screen (contract §2).
    static func live(uncategorizedOnly: Bool = false) -> TransactionListViewModel {
        TransactionListViewModel(
            history: TransactionHistoryService(opening: { try StoreProvider.shared() }),
            uncategorizedOnly: uncategorizedOnly)
    }
}
