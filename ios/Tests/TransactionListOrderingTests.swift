import Foundation
import KanameCore
import Testing

@testable import Kaname

/// A synthetic 256-bit key (64 hex chars). Test-only; never a real device key.
private let orderingKey = "5c4b3a29180716253443526170ffeeddccbbaa99887766554433221100aabbcc"
/// Fixed, so a heading's year is a decision about the fixture rather than about today.
private let orderingNow = Date(timeIntervalSince1970: 1_784_000_000)  // 2026-07-16

/// The date three accounts share — the only honest test of the account tie-break, and the
/// place a page boundary is deliberately made to fall.
private let sharedDate = "2026-07-15"

private struct OrderingRow {
    let date: String
    let description: String
    let amount: String
}

private struct OrderingAccount {
    let name: String
    let isCreditCard: Bool
    let currency: String
    let last4: String
    let rows: [OrderingRow]
}

/// Three accounts, nine rows, five calendar dates across eight months and two calendar years,
/// with one date carrying rows from all three accounts — and three rows of the *same* account on
/// that date, printed in an order that matches no other order a defect might reach for, which is
/// the only way printed order can be told apart from any of them.
///
/// Written through `insertAccount`/`insertTransaction` rather than through a parsed statement
/// on purpose: the ordering key is `(date, account position, rowid)`, and only direct inserts
/// let a test say exactly which rowid follows which. What the *import* path does to the order
/// is covered end to end in `TransactionListLivenessTests`.
private let orderingAccounts: [OrderingAccount] = [
    OrderingAccount(
        name: "Everyday Savings", isCreditCard: false, currency: "INR", last4: "1123",
        rows: [
            // Printed in this order, and deliberately in **no** other: not alphabetical
            // either way, not by amount either way, and not the reverse of insertion. A
            // fixture whose printed order coincides with a sort a defect might reach for
            // cannot tell the two apart — this one was found doing exactly that.
            OrderingRow(date: sharedDate, description: "SYNTHETIC MEDLAR 01", amount: "500.00"),
            OrderingRow(date: sharedDate, description: "SYNTHETIC ALMOND 02", amount: "900.00"),
            OrderingRow(date: sharedDate, description: "SYNTHETIC ZEBRA 03", amount: "100.00"),
            OrderingRow(date: "2026-06-30", description: "SYNTHETIC SALARY 04", amount: "345678.90"),
            OrderingRow(date: "2025-12-31", description: "SYNTHETIC GIFT 05", amount: "500.00"),
        ]),
    OrderingAccount(
        name: "Travel Card", isCreditCard: true, currency: "INR", last4: "8890",
        rows: [
            OrderingRow(date: sharedDate, description: "SYNTHETIC FLIGHT 06", amount: "4444.44"),
            OrderingRow(date: "2026-05-02", description: "SYNTHETIC HOTEL 07", amount: "555.55"),
        ]),
    OrderingAccount(
        name: "Overseas Savings", isCreditCard: false, currency: "KWD", last4: "4417",
        rows: [
            OrderingRow(date: sharedDate, description: "SYNTHETIC OVERSEAS 08", amount: "66.660"),
            OrderingRow(date: "2026-01-09", description: "SYNTHETIC OVERSEAS 09", amount: "77.770"),
        ]),
]

/// A fourth account, imported later — rows on a date the list already has, and on one it does
/// not, so "a further import changes nothing about what was already there" is a claim about
/// rows that genuinely interleave rather than append.
private let laterAccount = OrderingAccount(
    name: "Second Card", isCreditCard: true, currency: "INR", last4: "3350",
    rows: [
        OrderingRow(date: sharedDate, description: "SYNTHETIC LATER 10", amount: "99.99"),
        OrderingRow(date: "2026-03-03", description: "SYNTHETIC LATER 11", amount: "10.10"),
    ])

/// The whole combined history in the order the list must render it: date descending, then the
/// account's position on the front door, then printed order within an account.
private let expectedSequence = [
    "SYNTHETIC MEDLAR 01",  // 2026-07-15, account 1, printed first
    "SYNTHETIC ALMOND 02",  // 2026-07-15, account 1, printed second
    "SYNTHETIC ZEBRA 03",  // 2026-07-15, account 1, printed third
    "SYNTHETIC FLIGHT 06",  // 2026-07-15, account 2
    "SYNTHETIC OVERSEAS 08",  // 2026-07-15, account 3
    "SYNTHETIC SALARY 04",  // 2026-06-30
    "SYNTHETIC HOTEL 07",  // 2026-05-02
    "SYNTHETIC OVERSEAS 09",  // 2026-01-09
    "SYNTHETIC GIFT 05",  // 2025-12-31
]

/// The shared date once the later account exists — five accounts' worth of tie-break in one
/// place, and the only row that moves is the new one, onto the end.
private let expectedSharedDate = [
    "SYNTHETIC MEDLAR 01", "SYNTHETIC ALMOND 02", "SYNTHETIC ZEBRA 03",
    "SYNTHETIC FLIGHT 06", "SYNTHETIC OVERSEAS 08", "SYNTHETIC LATER 10",
]

/// A store on a temp path that can be closed and opened again — which is what makes "identical
/// across a relaunch" a claim about a database rather than about an object still in memory.
private final class OrderingStore {
    let directory: URL
    let path: String

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-ordering-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("kaname.db").path
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func open() throws -> Store {
        try Store.open(path: path, key: orderingKey)
    }

    @discardableResult
    func write(_ account: OrderingAccount, into store: Store) throws -> String {
        let id = try store.insertAccount(
            account: NewAccount(
                name: account.name,
                bankCode: "SYNTHETIC",
                isCreditCard: account.isCreditCard,
                last4: account.last4,
                currency: account.currency,
                createdAt: "2026-08-01T00:00:00Z",
                updatedAt: "2026-08-01T00:00:00Z"
            ))
        for row in account.rows {
            _ = try store.insertTransaction(
                txn: NewTransaction(
                    accountId: id,
                    date: row.date,
                    descriptionRaw: row.description,
                    amount: TransactionCorpus.decimal(row.amount),
                    direction: .debit,
                    currency: account.currency,
                    sourceCategory: nil,
                    categoryId: nil,
                    categorisedBy: nil,
                    statementId: nil,
                    createdAt: "2026-08-01T00:00:00Z",
                    updatedAt: "2026-08-01T00:00:00Z"
                ))
        }
        return id
    }
}

/// Read a whole list from a screen just opened over `store`, one page at a time.
private func renderedGroups(_ store: Store, pageSize: UInt32 = 2) async -> [DateGroup] {
    let model = await TransactionListViewModel(
        history: TransactionHistoryService(store: store),
        clock: { orderingNow },
        pageSize: pageSize
    )
    await model.onAppear()
    for _ in 0..<100 {
        let rows = await model.groups.flatMap(\.rows)
        guard let last = rows.last else { break }
        await model.loadMoreIfNeeded(currentRowID: last.id)
        if await model.groups.flatMap(\.rows).count == rows.count { break }
    }
    return await model.groups
}

private func renderedRows(_ store: Store, pageSize: UInt32 = 2) async -> [TransactionRow] {
    await renderedGroups(store, pageSize: pageSize).flatMap(\.rows)
}

/// The rendered sequence as text — descriptions, since row ids are minted and cannot be
/// written down in advance, and the description is what a person actually reads.
private func sequence(_ rows: [TransactionRow]) -> [String] {
    rows.map(\.displayDescription)
}

/// The order of a person's history, asserted over the real bridge and a real encrypted store.
///
/// The engine owns this order and proves it in `history_order.rs`; what is proved here is that
/// nothing between the engine and the person's eyes re-decides it. A list that quietly re-sorts
/// what it was handed is indistinguishable from a correct one until the day two rows share a
/// date — which is why every assertion below is about a date more than one row lands on.
///
/// All data is synthetic (Constitution I).
@Suite("The list is one history, newest first")
struct TransactionListOrderingTests {
    /// A store holding the fixture, open and ready to read.
    private func withSeededStore(_ body: (OrderingStore, Store) async throws -> Void) async throws {
        let database = try OrderingStore()
        let store = try database.open()
        for account in orderingAccounts {
            try database.write(account, into: store)
        }
        try await body(database, store)
    }

    // MARK: - O1 — newest first, across accounts

    @Test("The whole history reads newest first, in one sequence across every account")
    func theSequenceIsTheEnginesAndNewestFirst() async throws {
        try await withSeededStore { _, store in
            let rows = await renderedRows(store)

            #expect(sequence(rows) == expectedSequence)
            // Said again as a property, so a failure distinguishes "wrongly ordered" from
            // "wrong rows": no row may be newer than the row above it (FR-028).
            let dates = rows.map(\.isoDate)
            #expect(dates == dates.sorted(by: >))
            // And the groups are the dates, in the same order, one per calendar date.
            let groups = await renderedGroups(store)
            #expect(groups.map(\.id) == ["2026-07-15", "2026-06-30", "2026-05-02", "2026-01-09", "2025-12-31"])
        }
    }

    // MARK: - O2 — the same-date tie-breaks

    @Test("Same-date rows of different accounts follow the front door's account order")
    func sameDateRowsFollowTheFrontDoorsAccountOrder() async throws {
        try await withSeededStore { _, store in
            let rows = await renderedRows(store)
            let shared = rows.filter { $0.isoDate == sharedDate }
            #expect(shared.count == 5, "the fixture must actually share a date")

            // The accounts, in the order they first appear on the shared date, de-duplicated.
            var appearance: [String] = []
            for row in shared where !appearance.contains(row.accountID) {
                appearance.append(row.accountID)
            }
            let frontDoor = try store.listAccounts().map(\.id)
            #expect(appearance == frontDoor.filter { appearance.contains($0) })
            // A person sees one account order in the app, not one per screen (FR-030).
            #expect(appearance == frontDoor)
        }
    }

    @Test("Same-date rows of one account stay in the order the statement printed them")
    func sameDateRowsOfOneAccountKeepPrintedOrder() async throws {
        try await withSeededStore { _, store in
            let rows = await renderedRows(store)
            let everyday = try #require(try store.listAccounts().first)
            let sharedForAccount =
                rows
                .filter { $0.isoDate == sharedDate }
                .filter { $0.accountID == everyday.id }
                .map(\.displayDescription)

            // Inserted in this order, and therefore printed in this order (data-model §2).
            #expect(
                sharedForAccount == [
                    "SYNTHETIC MEDLAR 01", "SYNTHETIC ALMOND 02", "SYNTHETIC ZEBRA 03",
                ])
        }
    }

    // MARK: - O5's app-side mirror — the same sequence, every time

    @Test("Reading the same store again gives a byte-identical sequence")
    func rebuildingOverAnUnchangedStoreIsIdentical() async throws {
        try await withSeededStore { _, store in
            let first = await renderedGroups(store)
            let second = await renderedGroups(store)

            // `DateGroup` is `Equatable` all the way down to the row, so this compares the
            // headings, the grouping and every rendered field, not just the order (SC-009).
            #expect(second == first)
        }
    }

    @Test("Where the pages happen to fall changes nothing about the sequence")
    func everyPageSizeGivesTheSameSequence() async throws {
        try await withSeededStore { _, store in
            let whole = await renderedGroups(store, pageSize: 200)

            // 1 and 3 both cut inside the four-row shared date; 2 cuts it in half. A defect
            // that re-sorted or re-grouped a page would show up as a different sequence at
            // one size and not another.
            for pageSize: UInt32 in [1, 2, 3, 5] {
                #expect(await renderedGroups(store, pageSize: pageSize) == whole, "page size \(pageSize)")
            }
        }
    }

    @Test("Closing the app and opening it again shows the same sequence")
    func theSequenceSurvivesARelaunch() async throws {
        let database = try OrderingStore()
        let before: [DateGroup]
        do {
            let store = try database.open()
            for account in orderingAccounts {
                try database.write(account, into: store)
            }
            before = await renderedGroups(store)
        }

        // A second `Store` over the same file: everything in memory is gone, and the order
        // now has to come back out of the database (FR-031, SC-009).
        let reopened = try database.open()
        #expect(await renderedGroups(reopened) == before)
        #expect(sequence(await renderedRows(reopened)) == expectedSequence)
    }

    // MARK: - FR-032 — a further account disturbs nothing

    @Test("Importing a further account leaves every existing row where it was")
    func afurtherAccountLeavesTheExistingOrderUntouched() async throws {
        try await withSeededStore { database, store in
            let before = sequence(await renderedRows(store))

            try database.write(laterAccount, into: store)

            let rows = await renderedRows(store)
            let after = sequence(rows)
            // Every pre-existing row is still there, in the same relative order — the part an
            // ordering that depended on what had been imported most recently would break.
            #expect(after.filter { before.contains($0) } == before)
            #expect(after.count == before.count + 2)

            // And the new account's shared-date row sits after the three accounts that were
            // already there, because it is last on the front door — not first because it is
            // newest (FR-030).
            #expect(sequence(rows.filter { $0.isoDate == sharedDate }) == expectedSharedDate)
            // Absolutely, not only relatively: the whole sequence is still the one the
            // ordering key dictates, with the two new rows in the two places it puts them.
            #expect(
                after == [
                    "SYNTHETIC MEDLAR 01", "SYNTHETIC ALMOND 02", "SYNTHETIC ZEBRA 03",
                    "SYNTHETIC FLIGHT 06", "SYNTHETIC OVERSEAS 08", "SYNTHETIC LATER 10",
                    "SYNTHETIC SALARY 04", "SYNTHETIC HOTEL 07", "SYNTHETIC LATER 11",
                    "SYNTHETIC OVERSEAS 09", "SYNTHETIC GIFT 05",
                ])
        }
    }
}
