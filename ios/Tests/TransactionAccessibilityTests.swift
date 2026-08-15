import Foundation
import KanameCore
import SwiftUI
import Testing

@testable import Kaname

/// The half of SC-013 a machine can check.
///
/// The other half — whether a rendered row actually reads well at accessibility sizes, whether
/// a heading stays pinned, whether contrast holds under Increase Contrast — is on the manual
/// gate, because no unit test can measure a frame or a colour on a screen (FR-075). What *is*
/// mechanical is everything the screen is built out of: the sentence each row announces, the
/// fact that every distinction is carried by a word or a glyph rather than by a colour, and
/// that no view invents copy of its own.
///
/// The last one matters more than it looks. A string literal in a view body is a sentence that
/// escaped the copy deck, the honesty audit and the pluralisation helper all at once.
@Suite("The transaction list, with colour and layout removed")
struct TransactionAccessibilityTests {
    private static func row(
        id: String = "row",
        description: String = "SYNTHETIC CAFE",
        category: String? = "Groceries",
        isTransfer: Bool = false,
        last4: String? = "1123"
    ) -> TransactionRow {
        TransactionRow(
            HistoryRow(
                id: id,
                accountId: "account-1",
                accountName: "Everyday Savings",
                accountLast4: last4,
                date: "2026-07-15",
                descriptionRaw: description,
                amount: TransactionCorpus.decimal("450.00"),
                direction: .debit,
                currency: "INR",
                categoryName: category,
                isTransfer: isTransfer
            ))
    }

    // MARK: - Every distinction survives colour being removed entirely

    @Test("Direction is readable with no colour at all")
    func directionIsNotColour() {
        let debit = Self.row()
        let credit = TransactionRow(
            HistoryRow(
                id: "credit", accountId: "account-1", accountName: "Everyday Savings",
                accountLast4: "1123", date: "2026-07-15", descriptionRaw: "SYNTHETIC SALARY",
                amount: TransactionCorpus.decimal("450.00"), direction: .credit, currency: "INR",
                categoryName: nil, isTransfer: false))

        // A sign a person can see, and a word a person can hear. The row carries no colour for
        // direction at all — there is nothing to remove (FR-013, FR-071, SC-014).
        #expect(debit.directionSign == "\u{2212}")
        #expect(credit.directionSign == "+")
        #expect(debit.directionSign != credit.directionSign)
        #expect(debit.directionWord != credit.directionWord)
        #expect(debit.formattedAmount != credit.formattedAmount)
    }

    @Test("The transfer marking, the uncategorized label and the filtered state are all words")
    func everyStateIsCarriedByAString() async throws {
        // Transfer: a word, plus a symbol beside it in the row.
        #expect(Self.row(isTransfer: true).accessibilityLabel.contains("transfer"))
        #expect(!Self.row(isTransfer: false).accessibilityLabel.contains("transfer"))

        // Uncategorized: a word where a blank would be.
        #expect(Self.row(category: nil).categoryLabel == TransactionListStrings.uncategorized)

        // Filtered: a sentence naming the account, not a highlight on a control.
        let model = await TransactionListViewModel(
            history: HistoryDouble(
                pages: [HistoryPage(rows: [historyRow("a", "2026-07-15")], cursor: nil)],
                summaries: [accountSummary(1)]),
            clock: listClock
        )
        await model.onAppear()
        let unfiltered = await model.scopeAnnouncement
        await model.setFilter(.account(id: "account-1", name: "Everyday Savings", last4: "1123"))
        #expect(await model.scopeAnnouncement != unfiltered)
        #expect(await model.scopeAnnouncement.contains("Everyday Savings"))
    }

    // MARK: - One element per row, and it says everything

    @Test("A row announces one sentence, containing every fact it displays")
    func aRowIsOneAnnouncement() {
        let row = Self.row(isTransfer: true)

        // Everything visible in the row is inside the one sentence, so nothing on screen is
        // unreachable to a person who never sees it (FR-015, FR-072).
        for visible in [row.displayDescription, row.categoryLabel, row.accountIdentity] {
            #expect(row.accessibilityLabel.contains(visible), "\(visible) is not announced")
        }
        #expect(row.accessibilityLabel.contains(row.amount.formatted(.currency(code: "INR"))))
        // Commas, not newlines: one sentence read at one breath, not six focus stops. The
        // count of comma-separated pieces is deliberately *not* asserted — the account
        // identity carries a comma of its own ("Everyday Savings, ending 1123"), and a test
        // that counted commas would be asserting the shape of an account name.
        #expect(!row.accessibilityLabel.contains("\n"))
        // What is asserted is the order, which is what makes the sentence a sentence.
        let label = row.accessibilityLabel
        let positions = [
            label.range(of: row.displayDescription)?.lowerBound,
            label.range(of: row.formattedAmount.dropFirst())?.lowerBound,
            label.range(of: row.accountIdentity)?.lowerBound,
            label.range(of: row.categoryLabel)?.lowerBound,
        ].compactMap { $0 }
        #expect(positions.count == 4)
        #expect(positions == positions.sorted())
        #expect(label.hasSuffix(TransactionListStrings.transferAnnouncement))
    }

    @Test("A row is announced with its year, because a row is read away from its heading")
    func aRowCarriesItsOwnDate() {
        // The visible heading may drop the year for the current year; the row may not. A
        // VoiceOver reader can land on a row without ever hearing the heading above it.
        let announced = Self.row().accessibilityLabel
        #expect(announced.contains("2026"))
        #expect(announced.hasPrefix(Self.row().date.formatted(.dateTime.day().month(.wide).year())))
    }

    @Test("Every date heading is announced with how many rows are under it")
    func everyHeadingIsAnnounced() async throws {
        let rows = [
            historyRow("a", "2026-07-15"), historyRow("b", "2026-07-15"),
            historyRow("c", "2026-07-14"),
        ]
        let model = await TransactionListViewModel(
            history: HistoryDouble(
                pages: [HistoryPage(rows: rows, cursor: nil)], summaries: [accountSummary(3)]),
            clock: listClock
        )
        await model.onAppear()

        for group in await model.groups {
            let announced = TransactionListStrings.groupAnnouncement(
                heading: group.heading, count: group.rows.count)
            #expect(announced.hasPrefix(group.heading))
            #expect(announced.hasSuffix(TransactionListStrings.transactionCount(group.rows.count)))
            #expect(!group.heading.isEmpty)
        }
        #expect(await model.groups.count == 2)
    }

    // MARK: - The layout decision at every text size

    @Test("Every text size produces a layout in which the amount does not yield")
    func everyTextSizeKeepsTheAmount() {
        for size in DynamicTypeSize.allCases {
            let layout = TransactionRowLayout(dynamicTypeSize: size)
            #expect(!layout.amountYields, "at \(size)")
            #expect(layout.descriptionLineLimit >= 2, "at \(size)")
            // The account name never disappears: it is what stops a figure being read against
            // the wrong account (FR-022).
            #expect(layout.accountNameLineLimit >= 1, "at \(size)")
        }
    }

    // MARK: - W4 — no view invents a sentence

    @Test("Every user-visible sentence comes from the copy deck, not from a view body")
    func noViewCarriesItsOwnCopy() throws {
        // Read the shipped sources and look for string literals in the view files. Anything a
        // person can read must come from `TransactionListStrings`, so that the honesty audit,
        // the pluralisation helper and the copy deck cannot be bypassed by typing a sentence
        // directly into a `Text` (W4).
        let sources = try Self.transactionViewSources()
        #expect(!sources.isEmpty, "the audit found no sources to read")

        for (name, contents) in sources {
            let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
            for (number, line) in lines.enumerated() {
                let code = String(line).trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///") else { continue }
                for literal in Self.stringLiterals(in: code) {
                    #expect(
                        Self.isPermittedLiteral(literal),
                        "\(name):\(number + 1) carries the literal \"\(literal)\""
                    )
                }
            }
        }
    }

    /// The view sources, read from the repository rather than the bundle — the test target
    /// runs in a simulator, so the path comes from `#filePath`, which is a compile-time
    /// constant pointing at this file.
    private static func transactionViewSources() throws -> [(String, String)] {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let views =
            testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Transactions", isDirectory: true)
        let names = ["TransactionListView.swift", "TransactionRowView.swift"]

        return try names.map { name in
            (name, try String(contentsOf: views.appendingPathComponent(name), encoding: .utf8))
        }
    }

    /// Every double-quoted literal on one line of source.
    private static func stringLiterals(in code: String) -> [String] {
        guard let pattern = try? NSRegularExpression(pattern: "\"([^\"\\\\]*)\"") else { return [] }
        let range = NSRange(code.startIndex..., in: code)
        return pattern.matches(in: code, range: range).compactMap { match in
            Range(match.range(at: 1), in: code).map { String(code[$0]) }
        }
    }

    /// A literal that cannot reach a person's eyes: an SF Symbol name, a glass effect id, a
    /// preview's synthetic data. Anything else in a view body is copy that escaped the deck.
    private static func isPermittedLiteral(_ literal: String) -> Bool {
        let systemImages = ["exclamationmark.triangle", "tray", "arrow.left.arrow.right"]
        let identifiers = ["scope", "clear"]
        let previewData = [
            "1", "a", "Example Bank Credit Card", "1002", "2026-07-15",
            "SYNTHETIC COFFEE SHOP 42", "450.00", "INR",
        ]
        return literal.isEmpty || systemImages.contains(literal) || identifiers.contains(literal)
            || previewData.contains(literal)
    }
}
