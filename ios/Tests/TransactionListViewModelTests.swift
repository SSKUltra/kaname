import Foundation
import KanameCore
import Testing

@testable import Kaname

/// The view model, driven by an in-memory double so nothing here needs a database.
///
/// What is being pinned is the division of labour: the engine decides *which* rows and in
/// *what* order, and the view model decides only where the reads are cut and where a date
/// group begins. Every assertion below is a way of asking "did Swift quietly take over a
/// decision that belongs to the engine?" — because that is the defect that would make the
/// front-door count and the list disagree again.
@Suite("The transaction list view model")
struct TransactionListViewModelTests {
    // MARK: - The double

    /// A `TransactionHistoryReading` that serves scripted pages and can be held open, so
    /// "two calls before the first returns" is a fact the test controls rather than a race
    /// it hopes for.
    struct PageRequest: Equatable, Sendable {
        let accountID: String?
        let cursor: HistoryCursor?
        let limit: UInt32
    }

    actor HistoryDouble: TransactionHistoryReading {
        private let pages: [HistoryPage]
        private let summaries: [AccountSummary]
        private var served = 0
        private var isPaused = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var requests: [PageRequest] = []

        init(pages: [HistoryPage], summaries: [AccountSummary] = []) {
            self.pages = pages
            self.summaries = summaries
        }

        var requestCount: Int { requests.count }

        func pause() { isPaused = true }

        func release() {
            isPaused = false
            let held = waiters
            waiters = []
            for waiter in held { waiter.resume() }
        }

        func page(accountID: String?, cursor: HistoryCursor?, limit: UInt32) async throws -> HistoryPage {
            requests.append(PageRequest(accountID: accountID, cursor: cursor, limit: limit))
            if isPaused {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    waiters.append(continuation)
                }
            }
            defer { served += 1 }
            return served < pages.count ? pages[served] : HistoryPage(rows: [], cursor: nil)
        }

        func accountSummaries() async throws -> [AccountSummary] { summaries }
    }

    // MARK: - Fixtures

    private static let clock: @Sendable () -> Date = {
        Date(timeIntervalSince1970: 1_784_000_000)  // 2026-07-16, inside the corpus's dates.
    }

    private static func row(_ id: String, _ date: String, _ amount: String = "10.00") -> HistoryRow {
        HistoryRow(
            id: id,
            accountId: "account-1",
            accountName: TransactionCorpus.everyday,
            accountLast4: "1123",
            date: date,
            descriptionRaw: "SYNTHETIC ROW \(id)",
            amount: TransactionCorpus.decimal(amount),
            direction: .debit,
            currency: "INR",
            categoryName: nil,
            isTransfer: false
        )
    }

    private static func cursor(_ sequence: Int64) -> HistoryCursor {
        HistoryCursor(
            marks: [AccountMark(accountId: "account-1", date: "2026-07-10", sequence: sequence)])
    }

    private static func summary(_ count: UInt32, onlyExcluded: Bool = false) -> AccountSummary {
        AccountSummary(
            id: "account-1",
            name: TransactionCorpus.everyday,
            last4: "1123",
            isCreditCard: false,
            currency: "INR",
            liveTransactionCount: count,
            hasOnlyExcludedRows: onlyExcluded
        )
    }

    // MARK: - The first screenful

    @Test("Opening the list shows the first screenful")
    func onAppearReachesShowing() async throws {
        let double = HistoryDouble(
            pages: [HistoryPage(rows: [Self.row("a", "2026-07-15"), Self.row("b", "2026-07-14")], cursor: nil)],
            summaries: [Self.summary(2)]
        )
        let model = await TransactionListViewModel(history: double, clock: Self.clock)

        await model.onAppear()

        #expect(await model.state == .showing)
        #expect(await model.groups.flatMap(\.rows).map(\.id) == ["a", "b"])
        // The filter is `.all` at init and nothing about opening the screen changes it (V1).
        #expect(await model.filter == .all)
    }

    @Test("An empty first page is an empty state, not an empty list")
    func onAppearWithNoRowsReachesEmpty() async throws {
        let double = HistoryDouble(
            pages: [HistoryPage(rows: [], cursor: nil)],
            summaries: [Self.summary(0)]
        )
        let model = await TransactionListViewModel(history: double, clock: Self.clock)

        await model.onAppear()

        let state = await model.state
        guard case .empty = state else {
            Issue.record("expected an empty state, got \(state)")
            return
        }
        #expect(await model.groups.isEmpty)
    }

    // MARK: - H2 — the engine decides the order, the view model does not

    @Test("Rows arrive in the engine's order and the view model re-sorts nothing")
    func theViewModelPreservesTheEnginesOrder() async throws {
        // Deliberately not in date order. A view model that "helpfully" sorts would produce a
        // tidier answer than the engine's — and a different one from the front door's count.
        let scrambled = [
            Self.row("first", "2026-07-02"),
            Self.row("second", "2026-07-15"),
            Self.row("third", "2026-07-08"),
        ]
        let double = HistoryDouble(
            pages: [HistoryPage(rows: scrambled, cursor: nil)], summaries: [Self.summary(3)])
        let model = await TransactionListViewModel(history: double, clock: Self.clock)

        await model.onAppear()

        #expect(await model.groups.flatMap(\.rows).map(\.id) == ["first", "second", "third"])
    }

    @Test("A page is requested with the view model's page size and the engine's own cursor")
    func theViewModelHandsBackTheCursorItWasGiven() async throws {
        let given = Self.cursor(11)
        let double = HistoryDouble(
            pages: [
                HistoryPage(rows: [Self.row("a", "2026-07-15")], cursor: given),
                HistoryPage(rows: [Self.row("b", "2026-07-14")], cursor: nil),
            ],
            summaries: [Self.summary(2)]
        )
        let model = await TransactionListViewModel(history: double, clock: Self.clock, pageSize: 7)

        await model.onAppear()
        await model.loadMoreIfNeeded(currentRowID: "a")

        let requests = await double.requests
        #expect(requests.count == 2)
        // A first page binds no cursor; the second binds exactly what the first returned,
        // unread and unmodified — the cursor is opaque to Swift (FR-019).
        #expect(requests.first?.cursor == nil)
        #expect(requests.last?.cursor == given)
        #expect(requests.allSatisfy { $0.limit == 7 })
        #expect(requests.allSatisfy { $0.accountID == nil })
    }

    // MARK: - V5 — one request per cursor, however many times the list asks

    @Test("Two loads before the first returns issue one request")
    func loadMoreIsIdempotentPerCursor() async throws {
        let double = HistoryDouble(
            pages: [
                HistoryPage(rows: [Self.row("a", "2026-07-15")], cursor: Self.cursor(11)),
                HistoryPage(rows: [Self.row("b", "2026-07-14")], cursor: nil),
            ],
            summaries: [Self.summary(2)]
        )
        let model = await TransactionListViewModel(history: double, clock: Self.clock)
        await model.onAppear()

        await double.pause()
        let inFlight = Task { await model.loadMoreIfNeeded(currentRowID: "a") }
        await waitFor(double, requestCount: 2)

        // The list asks again while the first read is still inside the engine — which is what
        // a scroll actually does, several times a second.
        let second = Task { await model.loadMoreIfNeeded(currentRowID: "a") }
        for _ in 0..<64 { await Task.yield() }
        #expect(await double.requestCount == 2, "a second read was issued for a cursor already in flight")

        await double.release()
        _ = await (inFlight.value, second.value)
        #expect(await double.requestCount == 2)
        #expect(await model.groups.flatMap(\.rows).map(\.id) == ["a", "b"])
    }

    @Test("An exhausted sequence is never asked again")
    func loadMoreStopsWhenTheCursorClears() async throws {
        let double = HistoryDouble(
            pages: [HistoryPage(rows: [Self.row("a", "2026-07-15")], cursor: nil)],
            summaries: [Self.summary(1)]
        )
        let model = await TransactionListViewModel(history: double, clock: Self.clock)
        await model.onAppear()

        await model.loadMoreIfNeeded(currentRowID: "a")
        await model.loadMoreIfNeeded(currentRowID: "a")

        #expect(await double.requestCount == 1)
    }

    // MARK: - V7 — a date group cannot hold money

    @Test("A date group has no total, subtotal, balance or average — and no room for one")
    func dateGroupsCarryNoMoney() async throws {
        let double = HistoryDouble(
            pages: [
                HistoryPage(
                    rows: [Self.row("a", "2026-07-15", "10.00"), Self.row("b", "2026-07-15", "20.00")],
                    cursor: nil)
            ],
            summaries: [Self.summary(2)]
        )
        let model = await TransactionListViewModel(history: double, clock: Self.clock)
        await model.onAppear()

        let group = try #require(await model.groups.first)
        let banned = ["total", "subtotal", "balance", "average", "sum", "amount", "net"]
        for child in Mirror(reflecting: group).children {
            let label = (child.label ?? "").lowercased()
            #expect(!banned.contains { label.contains($0) }, "DateGroup.\(label) could hold a figure")
            // Nor a bare `Decimal` under any name: FR-025 forbids the *possibility*, not just
            // the display, of a figure combining amounts of more than one currency.
            let holdsMoney = child.value is Decimal
            #expect(!holdsMoney, "DateGroup.\(label) is money")
        }
    }

    // MARK: - V4 — a date is a date, however the pages happened to fall

    @Test("A date split across pages is one group, not one per page")
    func groupingFoldsAcrossPageBoundaries() async throws {
        // Five rows on one date, delivered one per page — the most hostile cut there is.
        let rows = (1...5).map { Self.row("r\($0)", "2026-07-15") }
        let pages = rows.enumerated().map { index, row in
            HistoryPage(rows: [row], cursor: index == rows.count - 1 ? nil : Self.cursor(Int64(index)))
        }
        let double = HistoryDouble(pages: pages, summaries: [Self.summary(5)])
        let model = await TransactionListViewModel(history: double, clock: Self.clock, pageSize: 1)

        await model.onAppear()
        try await drain(model)

        #expect(await model.groups.count == 1, "a page boundary inside a date started a second group")
        #expect(await model.groups.first?.rows.count == 5)
        #expect(await model.groups.flatMap(\.rows).map(\.id) == ["r1", "r2", "r3", "r4", "r5"])
    }

    @Test("Folding page by page gives the same groups as folding the whole sequence at once")
    func groupingIsIndependentOfPageSize() async throws {
        let sequence = [
            Self.row("a", "2026-07-15"), Self.row("b", "2026-07-15"), Self.row("c", "2026-07-15"),
            Self.row("d", "2026-07-14"), Self.row("e", "2026-07-14"),
            Self.row("f", "2026-07-02"),
        ]

        let whole = HistoryDouble(
            pages: [HistoryPage(rows: sequence, cursor: nil)], summaries: [Self.summary(6)])
        let wholeModel = await TransactionListViewModel(history: whole, clock: Self.clock, pageSize: 200)
        await wholeModel.onAppear()

        let cuts = stride(from: 0, to: sequence.count, by: 2).map { start in
            Array(sequence[start..<min(start + 2, sequence.count)])
        }
        let paged = HistoryDouble(
            pages: cuts.enumerated().map { index, rows in
                HistoryPage(rows: rows, cursor: index == cuts.count - 1 ? nil : Self.cursor(Int64(index)))
            },
            summaries: [Self.summary(6)]
        )
        let pagedModel = await TransactionListViewModel(history: paged, clock: Self.clock, pageSize: 2)
        await pagedModel.onAppear()
        try await drain(pagedModel)

        #expect(await pagedModel.groups == wholeModel.groups)
    }

    // MARK: - Helpers

    /// Keep asking for the next page until the sequence is exhausted. Bounded — a view model
    /// that never stops asking fails the test rather than hanging the suite.
    private func drain(_ model: TransactionListViewModel) async throws {
        for _ in 0..<64 {
            let before = await model.groups.flatMap(\.rows).count
            guard let last = await model.groups.last?.rows.last?.id else { return }
            await model.loadMoreIfNeeded(currentRowID: last)
            if await model.groups.flatMap(\.rows).count == before { return }
        }
        Issue.record("the list never stopped asking for more pages")
    }

    /// Wait until the double has recorded `requestCount` requests, or give up. Bounded, so a
    /// defect fails the test rather than hanging the suite.
    private func waitFor(_ double: HistoryDouble, requestCount: Int) async {
        for _ in 0..<10_000 {
            if await double.requestCount >= requestCount { return }
            await Task.yield()
        }
        Issue.record("the double never received \(requestCount) request(s)")
    }
}
