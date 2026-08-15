import Foundation
import KanameCore
import Testing

@testable import Kaname

/// A synthetic 256-bit key (64 hex chars). Test-only; never a real device key.
private let livenessKey = "aa11bb22cc33dd44ee55ff6600778899aabbccddeeff00112233445566778899"
/// Fixed, so a heading's year is a decision about the fixture rather than about today.
private let livenessNow = Date(timeIntervalSince1970: 1_786_000_000)

private struct StubExtractor: StatementTextExtractor {
    let text: ExtractedText

    func extract(from url: URL, password: String?) throws -> ExtractedText { text }
}

/// One synthetic statement, as a person would hand it over — twice, if they forget.
private struct Statement {
    let lines: [String]
    let fullText: String
}

/// A Yes card statement: four rows over three dates, two of them on one date, so a page
/// boundary and a date boundary can fall in different places.
private let travelCard = Statement(
    lines: [
        "29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr",
        "19/04/2026 UPI_SYNTHETIC STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr",
        "05/05/2026 UPI_SYNTHETIC GROCERY IND - Ref No: RT0003 Miscellaneous Stores 250.00 Dr",
        "05/05/2026 UPI_SYNTHETIC FUEL IND - Ref No: RT0004 Miscellaneous Stores 400.50 Dr",
    ],
    fullText: [
        "YES BANK KLICK",
        "Statement for YES BANK Card Number 3561XXXXXXXX6686",
        "Statement Period: 17/04/2026 To 16/05/2026",
        "Current Purchases / Cash Advance & Other Charges : Rs. 750.50 Dr",
        "Payment & Credits Received : Rs. 9,000.00 Cr",
        "29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr",
        "19/04/2026 UPI_SYNTHETIC STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr",
        "05/05/2026 UPI_SYNTHETIC GROCERY IND - Ref No: RT0003 Miscellaneous Stores 250.00 Dr",
        "05/05/2026 UPI_SYNTHETIC FUEL IND - Ref No: RT0004 Miscellaneous Stores 400.50 Dr",
    ].joined(separator: "\n")
)

/// A second card, from another issuer, sharing one date with the first — so "no other
/// account was disturbed" is a claim about rows that actually interleave.
private let everydayCard = Statement(
    lines: [
        "ICICI Bank Statement",
        "Statement Date May 28, 2026",
        "4315XXXXXXXX1002",
        "05/05/2026 4262 SYNTHETIC BOOKSHOP 0 320.00",
        "02/05/2026 1814 SYNTHETIC CAB RIDE 0 150.00",
    ],
    fullText: [
        "ICICI Bank Statement",
        "Statement Date May 28, 2026",
        "4315XXXXXXXX1002",
        "05/05/2026 4262 SYNTHETIC BOOKSHOP 0 320.00",
        "02/05/2026 1814 SYNTHETIC CAB RIDE 0 150.00",
    ].joined(separator: "\n")
)

/// A store, its temp directory, and the ability to import into it more than once.
private final class Harness {
    let directory: URL
    let store: Store

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-liveness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try Store.open(
            path: directory.appendingPathComponent("kaname.db").path,
            key: livenessKey
        )
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    /// Run the whole import vertical over a synthetic statement. Only extraction and the
    /// clock are stubbed — issuer detection, parsing, the integrity check, account
    /// resolution and the single atomic write are all the shipped ones.
    @discardableResult
    func runImport(_ statement: Statement) async throws -> ImportSummary {
        let service = ImportService(
            extractor: StubExtractor(
                text: ExtractedText(
                    lines: statement.lines,
                    fullText: statement.fullText,
                    lineWords: []
                )
            ),
            store: store,
            now: { livenessNow }
        )
        let result = try await service.run(
            url: URL(fileURLWithPath: "/dev/null/statement.pdf"),
            password: nil
        ) { _ in }
        // A fixture that starts asking which account it belongs to has stopped testing
        // what this suite is about, and must say so rather than import nothing quietly.
        guard let summary = result.summary else {
            throw ImportFailure.cancelled
        }
        return summary
    }

    /// The front door's own numbers, read through the path the front door reads them by.
    func frontDoor() async throws -> [ImportedAccount] {
        try await ImportService(
            extractor: StubExtractor(text: ExtractedText(lines: [], fullText: "", lineWords: [])),
            store: store,
            now: { livenessNow }
        ).importedAccounts()
    }

    /// Every raw row the store holds, excluded ones included — the view the list must
    /// never show, kept close by so "invisible" is asserted against something real.
    func rawRows() throws -> [StoredTransaction] {
        try store.listAccounts().flatMap { try store.listTransactions(accountId: $0.id) }
    }

    /// The screen a person would open: a view model over the real service.
    ///
    /// A deliberately tiny page size, so a sequence is assembled from many pages and a
    /// paging or grouping defect shows up as a repeated, missing or re-headed row.
    func openScreen() async -> TransactionListViewModel {
        await TransactionListViewModel(
            history: TransactionHistoryService(store: store),
            clock: { livenessNow },
            pageSize: 2
        )
    }

    /// Read `model` to the very end, as a person scrolling would.
    func scrollToTheEnd(_ model: TransactionListViewModel) async -> [DateGroup] {
        var reads = 0
        while reads < 100 {
            let rows = await model.groups.flatMap(\.rows)
            guard let last = rows.last else { break }
            await model.loadMoreIfNeeded(currentRowID: last.id)
            if await model.groups.flatMap(\.rows).count == rows.count { break }
            reads += 1
        }
        return await model.groups
    }

    /// The whole list, read from a screen just opened.
    func rendered(_ filter: AccountFilter = .all) async -> [DateGroup] {
        let model = await openScreen()
        await model.onAppear()
        if filter != .all {
            await model.setFilter(filter)
        }
        return await scrollToTheEnd(model)
    }

    /// Every filter state there is: the whole list, and each account on its own.
    func everyFilterState() throws -> [AccountFilter] {
        [.all]
            + (try store.listAccounts()).map {
                AccountFilter.account(id: $0.id, name: $0.name, last4: $0.last4)
            }
    }
}

// MARK: - Comparing what was rendered

/// Everything about the rendered list a person could see, as text.
///
/// Row ids are left out on purpose: this is the projection used to compare **two
/// different stores**, where ids cannot match and must not be what makes the comparison
/// pass. Ids are compared directly, within one store, where they are meaningful.
private func shape(_ groups: [DateGroup]) -> String {
    groups.map { group in
        ([group.id, group.heading]
            + group.rows.map {
                [
                    $0.displayDescription, $0.formattedAmount, $0.accountIdentity,
                    $0.categoryLabel, String($0.isTransfer),
                ].joined(separator: "\u{1F}")
            }).joined(separator: "\u{1E}")
    }.joined(separator: "\n")
}

private func rowIDs(_ groups: [DateGroup]) -> [String] {
    groups.flatMap(\.rows).map(\.id)
}

/// What a person sees after importing the same statement twice — asserted end to end, over
/// the real import pipeline, a real encrypted store, the real bridge and the real view model.
///
/// This is the defect the slice exists to prevent, and it has already happened once: the front
/// door counted rows under one rule and the list showed them under another, so a re-import
/// doubled a person's history in front of them (`3ba7890`). Nothing above the engine is
/// stubbed here, because a double would let Swift's opinion of the population pass for the
/// engine's — which is precisely the drift being pinned.
///
/// All statement text is 100% synthetic (Constitution I).
///
/// ⚠️ **One state the platform cannot build: a deleted row.** `is_deleted` has no write path in
/// the store's API, so a Swift test cannot produce one; the deleted half of the live rule is
/// pinned engine-side instead, over a corpus that does hold deleted rows
/// (`core/crates/kaname-core/tests/history_live.rs`, L1 for visibility and L4/L5 for the
/// counts). What Swift proves below is every state a real install can actually reach today:
/// a first import, a re-import that supersedes its own duplicates, and cross-source
/// duplicates linked between two accounts.
@Suite("A re-import changes nothing a person can see")
struct TransactionListLivenessTests {
    // MARK: - T071

    @Test("Importing the same statement twice leaves the rendered list identical")
    func aReImportChangesNothingThePersonCanSee() async throws {
        let harness = try Harness()
        try await harness.runImport(travelCard)
        try await harness.runImport(everydayCard)

        let before = await harness.rendered()
        let beforeIDs = rowIDs(before)
        #expect(beforeIDs.count == 6, "the fixture itself has to hold rows for this to mean anything")

        try await harness.runImport(travelCard)

        let after = await harness.rendered()
        // Contents, count and order, all three, and by id rather than by appearance — a
        // duplicate row renders identically to the row it duplicates (FR-009, SC-003).
        #expect(rowIDs(after) == beforeIDs)
        #expect(shape(after) == shape(before))
        // And the second import really did land: a store that quietly refused the file would
        // pass every assertion above while proving nothing.
        #expect(try harness.rawRows().count == 10)
    }

    @Test("A re-import changes nothing in any filter state either")
    func aReImportChangesNothingUnderAnyFilter() async throws {
        let harness = try Harness()
        try await harness.runImport(travelCard)
        try await harness.runImport(everydayCard)

        var before: [AccountFilter: [String]] = [:]
        for filter in try harness.everyFilterState() {
            before[filter] = rowIDs(await harness.rendered(filter))
        }

        try await harness.runImport(travelCard)

        for filter in try harness.everyFilterState() {
            #expect(rowIDs(await harness.rendered(filter)) == before[filter], "\(filter)")
        }
    }

    @Test("No excluded row is visible in any filter state")
    func noExcludedRowIsVisibleAnywhere() async throws {
        let harness = try Harness()
        try await harness.runImport(travelCard)
        try await harness.runImport(everydayCard)
        try await harness.runImport(travelCard)

        let raw = try harness.rawRows()
        let excluded = Set(raw.filter { !$0.isLive }.map(\.id))
        // Without this the assertions below would hold over an empty difference (FR-007).
        #expect(excluded.count == 4, "the re-import must have superseded the rows it re-read")

        for filter in try harness.everyFilterState() {
            let shown = Set(rowIDs(await harness.rendered(filter)))
            #expect(shown.isDisjoint(with: excluded), "\(filter) showed a superseded row")
        }

        // Nothing was destroyed to achieve that: the raw view still holds every row, which is
        // what keeps a re-import's provenance recoverable.
        #expect(raw.count == 10)
        // The other half of the rule — a deleted row — cannot be built from Swift: the store
        // exposes no write path for `is_deleted`. It is pinned engine-side instead, over a
        // corpus that has one (`history_live.rs`, L1). Asserting the absence here keeps that
        // gap honest rather than letting a future write path go untested by accident.
        #expect(!raw.contains { $0.isDeleted })
    }

    @Test("An excluded row leaves no gap, no blank row and no mark on the grouping")
    func anExcludedRowLeavesNoTraceAtAll() async throws {
        // Two stores, identical but for their history: one that was imported into twice and
        // therefore holds superseded rows, and one that never held an excluded row at all.
        // If an exclusion left a gap, an empty row, a placeholder or an extra heading, the
        // two rendered sequences would differ (FR-010).
        let neverExcluded = try Harness()
        try await neverExcluded.runImport(travelCard)
        try await neverExcluded.runImport(everydayCard)

        let withExclusions = try Harness()
        try await withExclusions.runImport(travelCard)
        try await withExclusions.runImport(everydayCard)
        try await withExclusions.runImport(travelCard)
        try await withExclusions.runImport(everydayCard)

        let clean = await neverExcluded.rendered()
        let excluded = await withExclusions.rendered()

        #expect(shape(excluded) == shape(clean))
        // Said again in the terms FR-010 uses, so a failure names what went wrong rather than
        // handing over two long strings.
        #expect(excluded.map(\.id) == clean.map(\.id), "the date groups themselves differ")
        #expect(excluded.map(\.heading) == clean.map(\.heading))
        #expect(excluded.map { $0.rows.count } == clean.map { $0.rows.count })
        #expect(!excluded.contains { $0.rows.isEmpty }, "an empty group is a gap with a heading on it")
        #expect(try withExclusions.rawRows().count == 2 * neverExcluded.rawRows().count)
    }

    // MARK: - T072

    @Test("Every front-door count equals the filtered row count, in every state")
    func frontDoorCountEqualsTheFilteredRowCountInEveryState() async throws {
        let harness = try Harness()

        /// The comparison SC-004 asks for, made once per state.
        func countsAgree(_ state: String) async throws {
            let accounts = try await harness.frontDoor()
            #expect(!accounts.isEmpty, "\(state): nothing to compare")
            var summed = 0
            for account in accounts {
                let filter = AccountFilter.account(
                    id: account.id, name: account.name, last4: account.last4)
                let shown = rowIDs(await harness.rendered(filter)).count
                let disagreement =
                    "the front door says \(account.transactionCount)"
                    + " for \(account.name), the list shows \(shown)"
                #expect(account.transactionCount == shown, "\(state): \(disagreement)")
                summed += account.transactionCount
            }
            // And the unfiltered list is exactly the accounts added up — a count that agreed
            // account by account while disagreeing in total would still mislead (FR-046).
            #expect(summed == rowIDs(await harness.rendered()).count, "\(state): the totals differ")
        }

        try await harness.runImport(travelCard)
        try await harness.runImport(everydayCard)
        try await countsAgree("after a first import")

        try await harness.runImport(travelCard)
        try await countsAgree("after a re-import that supersedes duplicates")

        // A third state, reached the other way: rows duplicated *across* two accounts, linked
        // by the cross-source matcher rather than by the re-import path. The engine's
        // deletion state is pinned in `history_live.rs` (L4, L5) for the reason given above.
        _ = try harness.store.findDuplicates()
        try await countsAgree("after cross-source duplicates are linked")
    }

    // MARK: - T074

    @Test("An import into one account disturbs no other account's rows")
    func anImportLeavesEveryOtherAccountExactlyAsItWas() async throws {
        let harness = try Harness()
        try await harness.runImport(travelCard)

        let travel = try #require(try harness.store.listAccounts().first)
        let travelFilter = AccountFilter.account(
            id: travel.id, name: travel.name, last4: travel.last4)

        // **One** screen, held open across the import — the state that would drift if a
        // refresh mutated the rows it already had instead of re-reading them (FR-011).
        let screen = await harness.openScreen()
        await screen.onAppear()
        await screen.setFilter(travelFilter)
        let before = await harness.scrollToTheEnd(screen)
        #expect(rowIDs(before).count == 4)

        // A different issuer, a different account, and a row on a date the travel card
        // already has — the case where a defect would interleave rather than append.
        try await harness.runImport(everydayCard)

        // The same screen, told to show the same account again.
        await screen.setFilter(travelFilter)
        let after = await harness.scrollToTheEnd(screen)
        #expect(rowIDs(after) == rowIDs(before))
        #expect(shape(after) == shape(before))

        // Attribution too: not one row of the travel card may now name the other account.
        await screen.clearFilter()
        let everything = await harness.scrollToTheEnd(screen)
        let travelRows = everything.flatMap(\.rows).filter { $0.accountID == travel.id }
        #expect(travelRows.map(\.id) == rowIDs(before))
        #expect(travelRows.allSatisfy { $0.accountName == travel.name })

        // And the pre-existing rows keep their *relative* order inside the combined list,
        // which is the part an in-place mutation would get wrong (FR-011, FR-032).
        let combinedIDs = rowIDs(everything)
        #expect(combinedIDs.filter { rowIDs(before).contains($0) } == rowIDs(before))
        // A freshly opened screen agrees with the one that has been open all along, so
        // nothing about the population depends on how long a person has been looking at it.
        #expect(shape(everything) == shape(await harness.rendered()))
    }
}
