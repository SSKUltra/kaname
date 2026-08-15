import Foundation
import KanameCore
import Testing

@testable import Kaname

/// What a date heading says, and where each part of it comes from.
///
/// A heading is the only place the list speaks about a *group* of transactions rather than
/// one, which makes it the one place a figure could appear that belongs to no single row —
/// and a day can hold more than one currency, so any such figure is either meaningless or
/// conditional. The year is the other half: it comes from an injected clock, so "include the
/// year when it is not the current year" is assertable on any day of any year rather than
/// only on the day it happens to break.
@Suite("A date heading is a date")
struct TransactionListHeadingTests {
    // MARK: - V6 — a heading is a date, and the year comes from the clock

    @Test("The year appears in a heading exactly when the date is not in the clock's year")
    func theYearSuffixComesFromTheInjectedClock() async throws {
        // The same two rows, read by two screens whose only difference is what year it is.
        // If a formatter reached for `Date()` instead of the clock, one of these would be
        // wrong on 1 January and right for the rest of the year — the defect that cannot be
        // reproduced on the day it is written (FR-035).
        let rows = [historyRow("thisYear", "2026-07-15"), historyRow("lastYear", "2025-12-31")]
        let inTwentySix = try await headings(for: rows, clock: listClock)
        let inTwentySeven = try await headings(
            for: rows, clock: { Date(timeIntervalSince1970: 1_815_600_000) })  // 2027-07-15

        #expect(inTwentySix.count == 2)
        // The rule itself, not a locale's rendering of it: a date in the clock's own year
        // carries no year, and a date outside it always does.
        #expect(!inTwentySix[0].contains("2026"))
        #expect(inTwentySix[1].contains("2025"))
        #expect(inTwentySeven[0].contains("2026"))
        #expect(inTwentySeven[1].contains("2025"))
        // Still a date: the day survives whichever year it is being read in.
        #expect(inTwentySix[0].contains("15"))
        #expect(inTwentySeven[0].contains("15"))
        // Not one character of the heading may come from the wall clock either: the same
        // store read at two different "now"s differs only where FR-035 says it must.
        #expect(inTwentySix[1] == inTwentySeven[1])
    }

    @Test("A date is one group across every account, never one group per account")
    func aDateIsOneGroupAcrossAccounts() async throws {
        // Three rows on one date from three different accounts — the shape that would come
        // back as three headings if the grouping key had quietly become (date, account).
        let rows = [
            historyRow("a", "2026-07-15", accountID: "account-1", accountName: TransactionCorpus.everyday),
            historyRow("b", "2026-07-15", accountID: "account-2", accountName: TransactionCorpus.travelCard),
            historyRow("c", "2026-07-15", accountID: "account-3", accountName: TransactionCorpus.overseas),
        ]
        let double = HistoryDouble(
            pages: [HistoryPage(rows: rows, cursor: nil)], summaries: [accountSummary(3)])
        let model = await TransactionListViewModel(history: double, clock: listClock)

        await model.onAppear()

        #expect(await model.groups.count == 1, "one group per calendar date, across all accounts (FR-033)")
        #expect(await model.groups.first?.rows.count == 3)
        // And the accounts are still distinguishable *inside* the group, which is what makes
        // one heading honest rather than merely tidier.
        #expect(await Set(model.groups.first?.rows.map(\.accountName) ?? []).count == 3)
    }

    @Test("A heading carries a date, and at most a count — never a figure")
    func aHeadingCarriesNoMoney() async throws {
        let rows = [
            historyRow("a", "2026-07-15", "1234567.89"),
            historyRow("b", "2026-07-15", "0.01"),
        ]
        let double = HistoryDouble(
            pages: [HistoryPage(rows: rows, cursor: nil)], summaries: [accountSummary(2)])
        let model = await TransactionListViewModel(history: double, clock: listClock)
        await model.onAppear()

        let group = try #require(await model.groups.first)
        let announced = TransactionListStrings.groupAnnouncement(
            heading: group.heading, count: group.rows.count)

        for text in [group.heading, announced] {
            // No currency, and no amount from the rows underneath it: a day can hold more
            // than one currency, so any day figure is either meaningless or conditional
            // (FR-025, FR-026).
            #expect(!text.contains("₹"))
            #expect(!text.contains("$"))
            #expect(!text.contains("."))
            for amount in ["1234567", "1,234,567", "0.01"] {
                #expect(!text.contains(amount), "\"\(text)\" carries an amount")
            }
        }
        // The one number a heading may carry is how many rows are under it.
        #expect(announced.contains("2"))
    }

    // MARK: - V7 — a date group cannot hold money

    @Test("A date group has no total, subtotal, balance or average — and no room for one")
    func dateGroupsCarryNoMoney() async throws {
        let double = HistoryDouble(
            pages: [
                HistoryPage(
                    rows: [historyRow("a", "2026-07-15", "10.00"), historyRow("b", "2026-07-15", "20.00")],
                    cursor: nil)
            ],
            summaries: [accountSummary(2)]
        )
        let model = await TransactionListViewModel(history: double, clock: listClock)
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
}
