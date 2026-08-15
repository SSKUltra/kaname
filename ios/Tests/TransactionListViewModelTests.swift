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
    // MARK: - The first screenful

    @Test("Opening the list shows the first screenful")
    func onAppearReachesShowing() async throws {
        let double = HistoryDouble(
            pages: [HistoryPage(rows: [historyRow("a", "2026-07-15"), historyRow("b", "2026-07-14")], cursor: nil)],
            summaries: [accountSummary(2)]
        )
        let model = await TransactionListViewModel(history: double, clock: listClock)

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
            summaries: [accountSummary(0)]
        )
        let model = await TransactionListViewModel(history: double, clock: listClock)

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
            historyRow("first", "2026-07-02"),
            historyRow("second", "2026-07-15"),
            historyRow("third", "2026-07-08"),
        ]
        let double = HistoryDouble(
            pages: [HistoryPage(rows: scrambled, cursor: nil)], summaries: [accountSummary(3)])
        let model = await TransactionListViewModel(history: double, clock: listClock)

        await model.onAppear()

        #expect(await model.groups.flatMap(\.rows).map(\.id) == ["first", "second", "third"])
    }

    @Test("A page is requested with the view model's page size and the engine's own cursor")
    func theViewModelHandsBackTheCursorItWasGiven() async throws {
        let given = historyCursor(11)
        let double = HistoryDouble(
            pages: [
                HistoryPage(rows: [historyRow("a", "2026-07-15")], cursor: given),
                HistoryPage(rows: [historyRow("b", "2026-07-14")], cursor: nil),
            ],
            summaries: [accountSummary(2)]
        )
        let model = await TransactionListViewModel(history: double, clock: listClock, pageSize: 7)

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
                HistoryPage(rows: [historyRow("a", "2026-07-15")], cursor: historyCursor(11)),
                HistoryPage(rows: [historyRow("b", "2026-07-14")], cursor: nil),
            ],
            summaries: [accountSummary(2)]
        )
        let model = await TransactionListViewModel(history: double, clock: listClock)
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
            pages: [HistoryPage(rows: [historyRow("a", "2026-07-15")], cursor: nil)],
            summaries: [accountSummary(1)]
        )
        let model = await TransactionListViewModel(history: double, clock: listClock)
        await model.onAppear()

        await model.loadMoreIfNeeded(currentRowID: "a")
        await model.loadMoreIfNeeded(currentRowID: "a")

        #expect(await double.requestCount == 1)
    }

    // MARK: - V4 — a date is a date, however the pages happened to fall

    @Test("A date split across pages is one group, not one per page")
    func groupingFoldsAcrossPageBoundaries() async throws {
        // Five rows on one date, delivered one per page — the most hostile cut there is.
        let rows = (1...5).map { historyRow("r\($0)", "2026-07-15") }
        let pages = rows.enumerated().map { index, row in
            HistoryPage(rows: [row], cursor: index == rows.count - 1 ? nil : historyCursor(Int64(index)))
        }
        let double = HistoryDouble(pages: pages, summaries: [accountSummary(5)])
        let model = await TransactionListViewModel(history: double, clock: listClock, pageSize: 1)

        await model.onAppear()
        try await drain(model)

        #expect(await model.groups.count == 1, "a page boundary inside a date started a second group")
        #expect(await model.groups.first?.rows.count == 5)
        #expect(await model.groups.flatMap(\.rows).map(\.id) == ["r1", "r2", "r3", "r4", "r5"])
    }

    @Test("Folding page by page gives the same groups as folding the whole sequence at once")
    func groupingIsIndependentOfPageSize() async throws {
        let sequence = [
            historyRow("a", "2026-07-15"), historyRow("b", "2026-07-15"), historyRow("c", "2026-07-15"),
            historyRow("d", "2026-07-14"), historyRow("e", "2026-07-14"),
            historyRow("f", "2026-07-02"),
        ]

        let whole = HistoryDouble(
            pages: [HistoryPage(rows: sequence, cursor: nil)], summaries: [accountSummary(6)])
        let wholeModel = await TransactionListViewModel(history: whole, clock: listClock, pageSize: 200)
        await wholeModel.onAppear()

        let cuts = stride(from: 0, to: sequence.count, by: 2).map { start in
            Array(sequence[start..<min(start + 2, sequence.count)])
        }
        let paged = HistoryDouble(
            pages: cuts.enumerated().map { index, rows in
                HistoryPage(rows: rows, cursor: index == cuts.count - 1 ? nil : historyCursor(Int64(index)))
            },
            summaries: [accountSummary(6)]
        )
        let pagedModel = await TransactionListViewModel(history: paged, clock: listClock, pageSize: 2)
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
