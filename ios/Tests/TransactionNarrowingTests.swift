import Foundation
import KanameCore
import Testing

@testable import Kaname

/// **L1**, **L2**, **L3** — the worklist is the same list, asked a different question.
///
/// There is one transaction list in this app, and "just the ones with no category" is a
/// narrowing handed to the engine rather than a second screen, a second renderer or a second
/// definition of which rows count. The difference between the whole history and the worklist is
/// **one field of one query** — which is the same thing 018 proved about the account filter,
/// one axis over (FR-038, FR-039, FR-076, SC-024).
@Suite("The worklist is one field of the same query")
struct TransactionNarrowingTests {
    private static func page(_ ids: [String]) -> HistoryPage {
        HistoryPage(rows: ids.map { historyRow($0, "2026-07-15") }, cursor: nil)
    }

    /// **L1** — the narrowing goes *to* the engine. Every row that comes back is rendered.
    @Test("The narrowing is carried into the query, and the page that returns is never filtered")
    func theNarrowingReachesTheEngine() async throws {
        let double = HistoryDouble(
            pages: [Self.page(["a", "b", "c"])], summaries: [accountSummary(3)])
        let model = await TransactionListViewModel(
            history: double, clock: listClock, uncategorizedOnly: true)

        await model.onAppear()

        let requests = await double.requests
        try #require(requests.count == 1)
        #expect(requests[0].uncategorizedOnly)
        // Three rows asked for, three rows shown. A screen that re-decided which of them were
        // unanswered would be a second definition of the set the entry point counts in SQL.
        #expect(await model.groups.flatMap(\.rows).map(\.id) == ["a", "b", "c"])
    }

    /// **L2** — both axes, one query. The account filter and the narrowing compose; neither
    /// replaces the other, and neither is applied on this side of the bridge.
    @Test("The account filter and the narrowing are two fields of one read")
    func bothNarrowingsCompose() async throws {
        let double = HistoryDouble(
            pages: [Self.page(["a"]), Self.page(["b"])],
            summaries: [accountSummary(1)]
        )
        let model = await TransactionListViewModel(
            history: double, clock: listClock, uncategorizedOnly: true)
        await model.onAppear()

        await model.setFilter(.account(id: "account-9", name: "Travel Card", last4: "8890"))

        let requests = await double.requests
        try #require(requests.count == 2)
        // The only difference between the two reads is the account. The narrowing did not
        // move, was not cleared by filtering, and was not re-applied afterwards.
        #expect(requests[0].accountID == nil)
        #expect(requests[1].accountID == "account-9")
        #expect(requests[0].uncategorizedOnly)
        #expect(requests[1].uncategorizedOnly)
    }

    /// **L3** — paging is 018's. The narrowing changes which rows the engine returns and
    /// nothing about how they are asked for.
    @Test("Paging, cursors and the page size are 018's, narrowed or not")
    func pagingIsUnchanged() async throws {
        let cursor = historyCursor(4)
        let double = HistoryDouble(
            pages: [
                HistoryPage(rows: [historyRow("a", "2026-07-15")], cursor: cursor),
                HistoryPage(rows: [historyRow("b", "2026-07-14")], cursor: nil),
            ],
            summaries: [accountSummary(2)]
        )
        let model = await TransactionListViewModel(
            history: double, clock: listClock, pageSize: 1, uncategorizedOnly: true)
        await model.onAppear()

        await model.loadMoreIfNeeded(currentRowID: "a")

        let requests = await double.requests
        try #require(requests.count == 2)
        #expect(requests[0].cursor == nil)
        #expect(requests[1].cursor == cursor)
        let limits = requests.map(\.limit)
        let narrowings = requests.map(\.uncategorizedOnly)
        #expect(limits == [1, 1])
        #expect(narrowings == [true, true])
        #expect(await model.groups.flatMap(\.rows).map(\.id) == ["a", "b"])
    }

    /// **L6**, at the seam. A model nobody told about the narrowing asks the engine for exactly
    /// what 018 asked for — which is what makes "018's list is unchanged" a fact about the
    /// query rather than a claim about a screenshot (FR-046, SC-023).
    @Test("With the narrowing off, the read is byte-identical to 018's")
    func theUnnarrowedReadIsUnchanged() async throws {
        let double = HistoryDouble(pages: [Self.page(["a"])], summaries: [accountSummary(1)])
        let model = await TransactionListViewModel(history: double, clock: listClock)

        await model.onAppear()

        let requests = await double.requests
        try #require(requests.count == 1)
        #expect(requests[0].uncategorizedOnly == false)
    }

    /// The worklist worked to zero is a finish, and it is the **model** that says so — the
    /// same state the unit table proves, reached through a real read rather than by calling
    /// the decision directly (L4, FR-042b).
    @Test("A worklist with nothing left in it lands on the finished wording")
    func anEmptyWorklistIsAFinish() async {
        let double = HistoryDouble(
            pages: [HistoryPage(rows: [], cursor: nil)],
            summaries: [accountSummary(12)]
        )
        let model = await TransactionListViewModel(
            history: double, clock: listClock, uncategorizedOnly: true)

        await model.onAppear()

        #expect(await model.state == .empty(.allAnswered))
        // Twelve live rows and an empty page: the rows are all there and all answered, which
        // is not any of 018's six sentences about absence.
        #expect(await model.state != .empty(.noTransactionsAnywhere))
        #expect(await model.state != .empty(.nothingToShowAnywhere))
    }

    @Test("The same list, unnarrowed and empty, still says what 018 said")
    func anEmptyUnnarrowedListIsUnchanged() async {
        let double = HistoryDouble(
            pages: [HistoryPage(rows: [], cursor: nil)],
            summaries: [accountSummary(12)]
        )
        let model = await TransactionListViewModel(history: double, clock: listClock)

        await model.onAppear()

        #expect(await model.state == .empty(.noTransactionsAnywhere))
    }
}
