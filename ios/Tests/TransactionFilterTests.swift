import CryptoKit
import Foundation
import KanameCore
import Testing

@testable import Kaname

/// A synthetic 256-bit key (64 hex chars). Test-only; never a real device key.
private let filterKey = "0099aabbccddeeff11223344556677889900aabbccddeeff1122334455667788"
private let filterNow = Date(timeIntervalSince1970: 1_784_000_000)  // 2026-07-16

/// Three accounts with rows on shared and unshared dates, written straight to a real store.
private struct FilterFixture {
    let directory: URL
    let store: Store
    let accountIDs: [String]

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-filter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try Store.open(
            path: directory.appendingPathComponent("kaname.db").path, key: filterKey)

        var ids: [String] = []
        for account in Self.accounts {
            let id = try store.insertAccount(
                account: NewAccount(
                    name: account.name,
                    bankCode: "SYNTHETIC",
                    isCreditCard: false,
                    last4: account.last4,
                    currency: "INR",
                    createdAt: "2026-08-01T00:00:00Z",
                    updatedAt: "2026-08-01T00:00:00Z"
                ))
            ids.append(id)
            for (index, date) in account.dates.enumerated() {
                _ = try store.insertTransaction(
                    txn: NewTransaction(
                        accountId: id,
                        date: date,
                        descriptionRaw: "SYNTHETIC \(account.name.uppercased()) \(index)",
                        amount: TransactionCorpus.decimal("100.0\(index)"),
                        direction: .debit,
                        currency: "INR",
                        sourceCategory: nil,
                        categoryId: nil,
                        categorisedBy: nil,
                        statementId: nil,
                        createdAt: "2026-08-01T00:00:00Z",
                        updatedAt: "2026-08-01T00:00:00Z"
                    ))
            }
        }
        accountIDs = ids
    }

    /// Dates deliberately overlap between accounts, so a filtered read has to be a different
    /// *query* rather than a different slice of the same rows.
    struct Seed {
        let name: String
        let last4: String?
        let dates: [String]
    }

    private static let accounts: [Seed] = [
        Seed(name: "Everyday Savings", last4: "1123", dates: ["2026-07-15", "2026-07-14", "2026-07-02"]),
        Seed(name: "Travel Card", last4: "8890", dates: ["2026-07-15", "2026-07-10"]),
        // No last-4: the scope has to name this account without one (FR-003).
        Seed(name: "Cash Wallet", last4: nil, dates: ["2026-07-15", "2026-06-01"]),
    ]

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    func model(pageSize: UInt32 = 2) async -> TransactionListViewModel {
        await TransactionListViewModel(
            history: TransactionHistoryService(store: store),
            clock: { filterNow },
            pageSize: pageSize
        )
    }

    func filter(_ index: Int) throws -> AccountFilter {
        let account = try store.listAccounts()[index]
        return .account(id: account.id, name: account.name, last4: account.last4)
    }

    /// A digest over every file the store owns, so a write to a journal counts as a write.
    func digest() -> String {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .sorted()
        var hasher = SHA256()
        for name in names {
            hasher.update(data: Data(name.utf8))
            hasher.update(data: (try? Data(contentsOf: directory.appendingPathComponent(name))) ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private func drain(_ model: TransactionListViewModel) async {
    for _ in 0..<100 {
        let rows = await model.groups.flatMap(\.rows)
        guard let last = rows.last else { return }
        await model.loadMoreIfNeeded(currentRowID: last.id)
        if await model.groups.flatMap(\.rows).count == rows.count { return }
    }
}

private func rowIDs(_ model: TransactionListViewModel) async -> [String] {
    await model.groups.flatMap(\.rows).map(\.id)
}

/// The account filter: the same list with fewer rows in it.
///
/// Three claims, and the whole story is in which of them a defect would break silently. That
/// the filter is **not persisted** is the one a person would meet on a Monday morning, having
/// filtered to one card on Friday: they would open Kaname, see a fraction of their spending,
/// and have no way to know it was a fraction. That a filtered read is *the same read with one
/// field set* is what keeps a filtered list from becoming a second screen with its own
/// ordering and its own idea of which rows exist.
///
/// All data is synthetic (Constitution I).
@Suite("Narrowing the list to one account")
struct TransactionFilterTests {
    // MARK: - V1 — the filter is never remembered

    @Test("The list opens unfiltered, and filtering writes nothing that could outlive it")
    func filteringPersistsNothingAnywhere() async throws {
        let fixture = try FilterFixture()
        defer { fixture.cleanUp() }
        let model = await fixture.model()
        await model.onAppear()

        // The app's own defaults, and the encrypted store, before anything is filtered.
        let domain = Bundle.main.bundleIdentifier ?? "in.beaconbrain.kaname"
        let defaultsBefore = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        let storeBefore = fixture.digest()

        let travel = try fixture.filter(1)
        #expect(await model.filter == .all)
        await model.setFilter(travel)
        #expect(await model.filter == travel)

        // Nothing was written. Not a preference, not a scene-restoration payload, and not a
        // row: a filter is a question being asked, never a fact about a person's data.
        let defaultsAfter = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        #expect(
            (defaultsAfter as NSDictionary).isEqual(to: defaultsBefore),
            "filtering wrote to UserDefaults"
        )
        #expect(fixture.digest() == storeBefore, "filtering wrote to the store")
    }

    @Test("A relaunch shows every account again, whatever was filtered before")
    func aRelaunchIsAlwaysUnfiltered() async throws {
        let fixture = try FilterFixture()
        defer { fixture.cleanUp() }

        let before = await fixture.model()
        await before.onAppear()
        await before.setFilter(try fixture.filter(2))
        await drain(before)
        #expect(await before.groups.flatMap(\.rows).count == 2)

        // The launch: a new view model over a new service over the same database — which is
        // all a relaunch is, from the list's point of view (FR-041).
        let after = await fixture.model()
        await after.onAppear()
        await drain(after)

        #expect(await after.filter == .all)
        #expect(await after.groups.flatMap(\.rows).count == 7)
        #expect(await after.scopeTitle == TransactionListStrings.scopeAll)
    }

    // MARK: - V2 — a filtered read is the same read, with one field set

    @Test("Filtering asks the engine a new question rather than sifting the old answer")
    func filteringIsAQueryNotASift() async throws {
        let rows = [historyRow("a", "2026-07-15"), historyRow("b", "2026-07-14")]
        let double = HistoryDouble(
            pages: [
                HistoryPage(rows: rows, cursor: historyCursor(1)),
                HistoryPage(rows: [historyRow("c", "2026-07-02")], cursor: nil),
                HistoryPage(rows: [historyRow("d", "2026-07-15")], cursor: nil),
            ],
            summaries: [accountSummary(3)]
        )
        let model = await TransactionListViewModel(history: double, clock: listClock, pageSize: 2)
        await model.onAppear()
        await model.loadMoreIfNeeded(currentRowID: "b")
        #expect(await rowIDs(model) == ["a", "b", "c"])

        await model.setFilter(.account(id: "account-9", name: "Travel Card", last4: "8890"))

        // The third request carries the account **and** a nil cursor: the accumulated rows and
        // the resume point are both discarded before page 1, so no row of the previous
        // population can survive into the new one (FR-040).
        let requests = await double.requests
        try #require(requests.count == 3)
        #expect(requests[2].accountID == "account-9")
        #expect(requests[2].cursor == nil)
        #expect(requests[2].limit == 2)
        #expect(await rowIDs(model) == ["d"])
        // And the only difference between the two reads is that one field (FR-042).
        #expect(requests[0].accountID == nil)
        #expect(requests[0].cursor == nil)
        #expect(requests[0].limit == requests[2].limit)
    }

    @Test("Clearing the filter is the same call with no account in it")
    func clearingIsTheSameReadWithoutTheAccount() async throws {
        let double = HistoryDouble(
            pages: [HistoryPage(rows: [historyRow("a", "2026-07-15")], cursor: nil)],
            summaries: [accountSummary(1)]
        )
        let model = await TransactionListViewModel(history: double, clock: listClock)
        await model.onAppear()
        await model.setFilter(.account(id: "account-9", name: "Travel Card", last4: "8890"))
        await model.clearFilter()

        let requests = await double.requests
        try #require(requests.count == 3)
        #expect(requests[2].accountID == nil)
        #expect(requests[2].cursor == nil)
        #expect(await model.filter == .all)
    }

    @Test("A filtered list is the unfiltered list with the other accounts taken out")
    func aFilteredListIsASubsequenceOfTheWholeOne() async throws {
        let fixture = try FilterFixture()
        defer { fixture.cleanUp() }

        let everything = await fixture.model()
        await everything.onAppear()
        await drain(everything)
        let all = await everything.groups.flatMap(\.rows)

        for index in 0..<3 {
            let filter = try fixture.filter(index)
            let model = await fixture.model()
            await model.onAppear()
            await model.setFilter(filter)
            await drain(model)
            let filtered = await model.groups.flatMap(\.rows)

            // Same rows, same order, same content — the unfiltered sequence with the other
            // accounts removed, and nothing else changed (FR-042).
            let expected = all.filter { $0.accountID == filter.accountID }
            #expect(filtered.map(\.id) == expected.map(\.id), "\(filter)")
            #expect(filtered == expected, "\(filter)")

            // And the count a person was shown on the front door is the count they get.
            let summary = try #require(
                try fixture.store.accountSummaries().first { $0.id == filter.accountID })
            #expect(UInt32(filtered.count) == summary.liveTransactionCount)
        }
    }

    @Test("The grouping of a filtered list is the unfiltered grouping with rows removed")
    func filteringChangesNoGrouping() async throws {
        let fixture = try FilterFixture()
        defer { fixture.cleanUp() }

        let model = await fixture.model()
        await model.onAppear()
        await drain(model)
        let unfilteredHeadings = await Dictionary(
            uniqueKeysWithValues: model.groups.map { ($0.id, $0.heading) })

        await model.setFilter(try fixture.filter(0))
        await drain(model)

        for group in await model.groups {
            // A date reads the same whether or not the other accounts' rows are on screen.
            #expect(group.heading == unfilteredHeadings[group.id], "\(group.id)")
            #expect(!group.rows.isEmpty)
        }
        #expect(await model.groups.map(\.id) == ["2026-07-15", "2026-07-14", "2026-07-02"])
    }

    // MARK: - The scope is always named, in words

    @Test("The scope names the filtered account, in the identity the front door uses")
    func theScopeNamesTheAccount() async throws {
        let fixture = try FilterFixture()
        defer { fixture.cleanUp() }
        let model = await fixture.model()
        await model.onAppear()

        #expect(await model.scopeTitle == TransactionListStrings.scopeAll)
        #expect(await model.scopeSubtitle == nil)
        #expect(await model.scopeAnnouncement == "Showing all accounts")
        #expect(await model.isFiltered == false)

        await model.setFilter(try fixture.filter(1))

        #expect(await model.scopeTitle == "Travel Card")
        #expect(await model.scopeSubtitle == TransactionListStrings.maskedLast4("8890"))
        #expect(await model.scopeAnnouncement == "Showing Travel Card, ending 8890 only")
        #expect(await model.isFiltered)

        // An account with no last-4 still names itself, and says nothing about a masked
        // number it does not have (FR-003).
        await model.setFilter(try fixture.filter(2))
        #expect(await model.scopeTitle == "Cash Wallet")
        #expect(await model.scopeSubtitle == nil)
        #expect(await model.scopeAnnouncement == "Showing Cash Wallet only")
    }

    @Test("The filter is carried by words, not by styling")
    func theFilteredStateIsAString() async throws {
        let fixture = try FilterFixture()
        defer { fixture.cleanUp() }
        let model = await fixture.model()
        await model.onAppear()

        let unfiltered = await model.scopeAnnouncement
        await model.setFilter(try fixture.filter(0))
        let filtered = await model.scopeAnnouncement

        // Two different sentences, both naming the state outright: nothing about "this list is
        // showing you less than everything" depends on a colour, a weight or a glass effect
        // (FR-038, FR-071, SC-014).
        #expect(filtered != unfiltered)
        #expect(filtered.contains("Everyday Savings"))
        #expect(filtered.contains("only"))
        #expect(unfiltered.contains("all"))
    }

    @Test("Every account the person has is offered, in the front door's order")
    func everyAccountIsOfferedInFrontDoorOrder() async throws {
        let fixture = try FilterFixture()
        defer { fixture.cleanUp() }
        let model = await fixture.model()
        await model.onAppear()

        let offered = await model.availableFilters
        #expect(offered.count == 3)
        #expect(offered.map(\.accountID) == fixture.accountIDs)
        #expect(offered.map(\.accountName) == ["Everyday Savings", "Travel Card", "Cash Wallet"])
        #expect(offered.map(\.accountLast4) == ["1123", "8890", nil])
    }
}
