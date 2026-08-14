import Foundation
import KanameCore
import Testing

@testable import Kaname

/// The cross-language mirror of the engine's `LIVE` constant.
///
/// The store's `listTransactions` is a **raw** view: it returns deleted rows and it returns the
/// superseded losers of a de-duplication, both deliberately, so a re-import's provenance
/// survives. `StoredTransaction.isLive` is Swift's copy of the rule that turns that raw view
/// into what a person actually has — and a copy of a rule is exactly the thing that drifts.
/// This suite is why `isLive` is kept rather than deleted once the count moves into SQL: it
/// asserts, against a real database, that Swift's copy and the engine's `LIVE` predicate agree
/// row for row.
///
/// The front-door count already got this wrong once, and a person watched their transaction
/// count double the moment they re-imported the same statement (`3ba7890`). That defect would
/// have been a red test here.
///
/// ⚠️ **What this suite cannot reach: a deleted row.** `is_deleted` has no write path in the
/// store's public API — the Rust corpus sets it with direct SQL through SQLCipher, which Swift
/// has no handle on. The `!isDeleted` half of the rule is pinned engine-side instead
/// (`core/crates/kaname-core/tests/history_live.rs`). Everything below is the superseded half,
/// end to end, which is the half a real install can actually produce today.
@Suite("Liveness parity between Swift and the engine")
struct LivenessParityTests {
    private func withSeededStore(_ body: (Store) throws -> Void) throws {
        let db = TransactionCorpus.temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: TransactionCorpus.key)
        try TransactionCorpus.seed(store)
        try body(store)
    }

    @Test("The fixture really does hold superseded rows")
    func theCorpusIsWorthAssertingAgainst() throws {
        try withSeededStore { store in
            let all = try store.listAccounts().flatMap { try store.listTransactions(accountId: $0.id) }

            // Without this, every assertion below would pass against a store where nothing was
            // ever excluded — a parity proof over an empty difference proves nothing.
            #expect(all.contains { $0.supersededBy != nil })
            #expect(all.count > all.filter(\.isLive).count)
        }
    }

    @Test("Swift's live rule and the engine's live count agree, account by account")
    func isLiveMatchesTheEnginesCount() throws {
        try withSeededStore { store in
            let summaries = try store.accountSummaries()
            #expect(!summaries.isEmpty)

            for summary in summaries {
                let swiftSide = try store.listTransactions(accountId: summary.id).filter(\.isLive).count
                #expect(
                    UInt32(swiftSide) == summary.liveTransactionCount,
                    "\(summary.name): Swift counted \(swiftSide), the engine counted \(summary.liveTransactionCount)"
                )
            }
        }
    }

    @Test("The rows the history returns are exactly the rows Swift calls live")
    func theHistoryIsTheSetOfLiveRows() throws {
        try withSeededStore { store in
            let liveInSwift = Set(
                try store.listAccounts()
                    .flatMap { try store.listTransactions(accountId: $0.id) }
                    .filter(\.isLive)
                    .map(\.id)
            )

            var fromHistory: Set<String> = []
            var cursor: HistoryCursor?
            var pages = 0
            repeat {
                let page = try store.historyPage(
                    query: HistoryQuery(accountId: nil, cursor: cursor, limit: 3))
                fromHistory.formUnion(page.rows.map(\.id))
                cursor = page.cursor
                pages += 1
            } while cursor != nil && pages < 200

            #expect(fromHistory == liveInSwift)
        }
    }

    @Test("A filtered history is the live rows of that account and no other")
    func aFilteredHistoryIsThatAccountsLiveRows() throws {
        try withSeededStore { store in
            for account in try store.listAccounts() {
                let liveInSwift = Set(
                    try store.listTransactions(accountId: account.id).filter(\.isLive).map(\.id))
                let page = try store.historyPage(
                    query: HistoryQuery(accountId: account.id, cursor: nil, limit: 200))

                #expect(Set(page.rows.map(\.id)) == liveInSwift, "\(account.name)")
            }
        }
    }

    @Test("The account whose every row is superseded reports itself as such, and shows nothing")
    func anAccountOfNothingButExcludedRowsIsDistinguishable() throws {
        try withSeededStore { store in
            let summaries = try store.accountSummaries()
            let echo = try #require(summaries.first { $0.name == TransactionCorpus.echoCard })
            let dormant = try #require(summaries.first { $0.name == TransactionCorpus.dormantCard })

            // Both show a person an empty list; they are not the same fact, and the empty
            // states that explain them must not be the same sentence (FR-048 vs FR-050).
            #expect(echo.liveTransactionCount == 0)
            #expect(dormant.liveTransactionCount == 0)
            #expect(echo.hasOnlyExcludedRows)
            #expect(!dormant.hasOnlyExcludedRows)

            let page = try store.historyPage(
                query: HistoryQuery(accountId: echo.id, cursor: nil, limit: 200))
            #expect(page.rows.isEmpty)
            // And the raw view still holds them, so nothing was destroyed to achieve that.
            #expect(try store.listTransactions(accountId: echo.id).count == 2)
        }
    }
}
