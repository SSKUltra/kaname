import CryptoKit
import Foundation
import KanameCore
import Testing

@testable import Kaname

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

    // MARK: - V3 — an import takes nothing away from the person reading

    @Test("A refresh keeps the filter and the row the person was reading")
    func aRefreshKeepsTheFilterAndThePlace() async throws {
        let fixture = try FilterFixture()
        defer { fixture.cleanUp() }
        let model = await fixture.model()
        await model.onAppear()

        let travel = try fixture.filter(1)
        await model.setFilter(travel)
        await drain(model)
        let anchor = try #require(await rowIDs(model).last)
        await model.anchorChanged(to: anchor)

        // A statement lands in an account this person is not currently looking at.
        try fixture.addRow(to: 0, date: "2026-07-16", index: 90)
        await model.refreshAfterImport()

        // The two things an import may never take: the question being asked, and the place in
        // the answer (FR-056, SC-010).
        #expect(await model.filter == travel)
        #expect(await model.anchorRowID == anchor)
        #expect(await model.scopeTitle == "Travel Card")
    }

    @Test("A refresh the import did not touch renders exactly what it rendered before")
    func aRefreshOfAnUntouchedAccountChangesNothing() async throws {
        let fixture = try FilterFixture()
        defer { fixture.cleanUp() }
        let model = await fixture.model()
        await model.onAppear()
        await model.setFilter(try fixture.filter(1))
        await drain(model)

        let before = await model.groups
        try fixture.addRow(to: 2, date: "2026-07-16", index: 91)
        await model.refreshAfterImport()

        // Byte-identical: the same groups, the same headings, the same rows in the same order.
        // A list that reshuffles itself because something happened elsewhere is a list a
        // person stops trusting (US8 AS-6).
        #expect(await model.groups == before)
        #expect(await model.state == .showing)
    }

    @Test("A refresh reads from the beginning again and duplicates no row")
    func aRefreshDuplicatesNoRow() async throws {
        let fixture = try FilterFixture()
        defer { fixture.cleanUp() }
        let model = await fixture.model()
        await model.onAppear()
        await drain(model)
        let before = await rowIDs(model)
        #expect(before.count == 7)

        try fixture.addRow(to: 0, date: "2026-07-16", index: 92)
        await model.refreshAfterImport()

        let after = await rowIDs(model)
        #expect(Set(after).count == after.count, "a row was read twice")
        #expect(after.count == before.count + 1)
        // The new row is at the newest end, and everything the person had is still under it,
        // in the order it was in.
        #expect(Array(after.dropFirst()) == before)
    }

    @Test("A refresh restarts at the newest end and resumes on its own cursors")
    func aRefreshNeverResumesFromAStaleCursor() async throws {
        let double = HistoryDouble(
            pages: [
                HistoryPage(rows: [historyRow("a", "2026-07-15")], cursor: historyCursor(1)),
                HistoryPage(rows: [historyRow("b", "2026-07-14")], cursor: historyCursor(2)),
                HistoryPage(rows: [historyRow("new", "2026-07-16")], cursor: historyCursor(3)),
                HistoryPage(rows: [historyRow("a", "2026-07-15")], cursor: nil),
            ],
            summaries: [accountSummary(2)]
        )
        let model = await TransactionListViewModel(history: double, clock: listClock, pageSize: 1)
        await model.onAppear()
        await model.loadMoreIfNeeded(currentRowID: "a")
        await model.refreshAfterImport()

        let requests = await double.requests
        try #require(requests.count == 4)
        // Page 1 of the refresh starts at the newest end, and page 2 resumes from the cursor
        // *that* page returned — never from the resume point the old read had reached, which
        // now points into a sequence that has changed underneath it.
        #expect(requests[2].cursor == nil)
        #expect(requests[3].cursor == historyCursor(3))
        #expect(requests[3].cursor != requests[1].cursor)
        #expect(await rowIDs(model) == ["new", "a"])
    }
}
