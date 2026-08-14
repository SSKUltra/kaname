import Foundation
import KanameCore
import Testing

@testable import Kaname

/// The engine's only caller, asserted over the real bridge against a real SQLCipher database.
///
/// This is the seam where a wrong answer would be invisible: everything above it — grouping,
/// paging, the row — is a faithful rendering of whatever arrives here, so if the transport
/// re-orders, drops, or quietly re-counts a row, every screen above it is wrong in a way no
/// higher test can distinguish from correct data. It is therefore tested against the engine
/// itself and not a double.
///
/// All data is synthetic (`TransactionCorpus`).
@Suite("The transaction history service")
struct TransactionHistoryServiceTests {
    /// Open a store on a fresh temp database, seeded with the corpus. The caller's `body` runs
    /// with it; the directory goes away afterwards either way.
    private func withSeededStore(_ body: (Store) async throws -> Void) async throws {
        let db = TransactionCorpus.temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: TransactionCorpus.key)
        try TransactionCorpus.seed(store)
        try await body(store)
    }

    private func match(_ row: HistoryRow, _ expected: TransactionCorpus.Expected) {
        #expect(row.date == expected.date)
        #expect(row.accountName == expected.accountName)
        // The description as the statement printed it — not trimmed, not titlecased, not
        // substituted. The app's "No description" wording is a *rendering* of an empty string
        // and must not have happened by the time it gets here.
        #expect(row.descriptionRaw == expected.descriptionRaw)
        // Exact to the last place, as a `Decimal`. A float anywhere on this path would show up
        // here as a value that is nearly right.
        #expect(row.amount == TransactionCorpus.decimal(expected.amount))
        #expect(row.direction == expected.direction)
        // The transaction's currency, never the account's and never the locale's (FR-023).
        #expect(row.currency == expected.currency)
        #expect(row.accountLast4 == expected.last4)
    }

    @Test("The first page is the newest rows of every account, in the combined order")
    func firstPageMatchesTheFixtureExactly() async throws {
        try await withSeededStore { store in
            let service = TransactionHistoryService(store: store)
            let page = try await service.page(accountID: nil, cursor: nil, limit: 4)

            #expect(page.rows.count == 4)
            for (row, expected) in zip(page.rows, TransactionCorpus.expectedLiveRows.prefix(4)) {
                match(row, expected)
            }
            // Three accounts share the newest date with three different amounts, so the first
            // page is only correct if the account tie-break is the front door's own order.
            #expect(page.rows.prefix(3).allSatisfy { $0.date == TransactionCorpus.sharedDate })
            #expect(page.cursor != nil)
        }
    }

    @Test("Every page concatenated is the live history, and nothing else")
    func walkingEveryPageYieldsExactlyTheLiveRows() async throws {
        try await withSeededStore { store in
            let service = TransactionHistoryService(store: store)

            // Deliberately a page size that cuts inside the shared date, so a paging defect
            // shows up as a repeated or a vanished row rather than as a reordering.
            let walked = try await walk(service, accountID: nil, limit: 2)

            #expect(walked.count == TransactionCorpus.expectedLiveRows.count)
            for (row, expected) in zip(walked, TransactionCorpus.expectedLiveRows) {
                match(row, expected)
            }
            // No row appears twice, and no superseded row appears at all.
            #expect(Set(walked.map(\.id)).count == walked.count)
            #expect(!walked.contains { $0.accountName == TransactionCorpus.echoCard })
        }
    }

    @Test("Paging changes where the reads are cut and nothing else")
    func everyPageSizeYieldsTheSameSequence() async throws {
        try await withSeededStore { store in
            let service = TransactionHistoryService(store: store)
            let byOne = try await walk(service, accountID: nil, limit: 1).map(\.id)
            let byThree = try await walk(service, accountID: nil, limit: 3).map(\.id)
            let whole = try await walk(service, accountID: nil, limit: 200).map(\.id)

            #expect(byOne == whole)
            #expect(byThree == whole)
        }
    }

    @Test("A filtered read is the same list with fewer rows in it")
    func filteringIsTheEnginesJobAndNotTheServices() async throws {
        try await withSeededStore { store in
            let service = TransactionHistoryService(store: store)
            let travelID = try #require(
                try store.listAccounts().first { $0.name == TransactionCorpus.travelCard }?.id)

            let filtered = try await walk(service, accountID: travelID, limit: 2)
            let combined = try await walk(service, accountID: nil, limit: 2)

            // H2: the service filters nothing itself. The proof is that the engine's filtered
            // answer is exactly the combined answer restricted to that account, in order —
            // if Swift were doing the filtering, the two could drift apart silently.
            #expect(filtered.map(\.id) == combined.filter { $0.accountId == travelID }.map(\.id))
            #expect(filtered.allSatisfy { $0.accountName == TransactionCorpus.travelCard })
        }
    }

    @Test("An account that names nothing is an empty page, not a failure")
    func anUnknownAccountReadsEmpty() async throws {
        try await withSeededStore { store in
            let service = TransactionHistoryService(store: store)
            let page = try await service.page(accountID: "no-such-account", cursor: nil, limit: 50)

            #expect(page.rows.isEmpty)
            #expect(page.cursor == nil)
        }
    }

    @Test("Account summaries are the front door's order, with the live counts")
    func accountSummariesMatchTheFixture() async throws {
        try await withSeededStore { store in
            let service = TransactionHistoryService(store: store)
            let summaries = try await service.accountSummaries()

            #expect(summaries.map(\.id) == (try store.listAccounts()).map(\.id))
            for summary in summaries {
                #expect(summary.liveTransactionCount == TransactionCorpus.expectedLiveCounts[summary.name])
            }
            // The echo card holds rows and every one of them is superseded — the one bit that
            // tells "this statement had no transactions" from "there is nothing to show".
            let echo = try #require(summaries.first { $0.name == TransactionCorpus.echoCard })
            #expect(echo.hasOnlyExcludedRows)
            let dormant = try #require(summaries.first { $0.name == TransactionCorpus.dormantCard })
            #expect(!dormant.hasOnlyExcludedRows)
        }
    }

    // MARK: - H4 — nothing about a person's money survives an error

    @Test("A store failure becomes an error carrying none of the row that caused it")
    func aStoreFailureLeaksNothing() {
        // A message of the shape SQLite actually produces, carrying every kind of fact the
        // person owns: their description, their amount, the date they spent it, and the
        // identifier of the account it happened on.
        let leaky = StoreError.Sql(
            message: "no such column: SYNTHETIC GROCERY 01 1111.11 2026-07-15 acct-9f3c1e")
        let mapped = TransactionListError(mapping: leaky)

        #expect(mapped == .unavailable)
        let forms = [
            String(describing: mapped), String(reflecting: mapped), mapped.localizedDescription,
        ]
        for form in forms {
            #expect(!form.contains("SYNTHETIC GROCERY 01"))
            #expect(!form.contains("1111.11"))
            #expect(!form.contains("2026-07-15"))
            #expect(!form.contains("acct-9f3c1e"))
            // Nor the raw text itself, in any part (FR-019, FR-063).
            #expect(!form.contains("no such column"))
        }
    }

    @Test("Every store failure maps to the one error, whatever it was")
    func everyStoreFailureMapsToTheSameThing() {
        let failures: [StoreError] = [
            .OpenFailed(message: "/private/var/.../kaname.db"),
            .InvalidKey,
            .WrongKey,
            .Migration(message: "v7"),
            .Sql(message: "database is locked"),
        ]
        for failure in failures {
            #expect(TransactionListError(mapping: failure) == .unavailable)
        }
    }

    // MARK: - Helpers

    /// Read every page and concatenate them, so a suite can prove that paging changes nothing
    /// but where the reads are cut.
    private func walk(
        _ service: TransactionHistoryService, accountID: String?, limit: UInt32
    ) async throws -> [HistoryRow] {
        var rows: [HistoryRow] = []
        var cursor: HistoryCursor?
        var pages = 0
        repeat {
            let page = try await service.page(accountID: accountID, cursor: cursor, limit: limit)
            rows.append(contentsOf: page.rows)
            cursor = page.cursor
            pages += 1
            // A cursor that never clears is an infinite scroll; fail loudly rather than hang.
            #expect(pages < 200)
        } while cursor != nil && pages < 200
        return rows
    }
}
