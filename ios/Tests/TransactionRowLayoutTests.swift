import Foundation
import KanameCore
import SwiftUI
import Testing

@testable import Kaname

/// The row's layout decision, proved with nothing on screen.
///
/// A unit test cannot measure a rendered frame, so the *decision* is extracted into a pure
/// value and the *rendering* goes to the manual gate (FR-074/FR-075, research R12). What that
/// buys is the one rule this screen cannot get wrong quietly: an amount is never the thing
/// that yields. A truncated description is a small annoyance; a truncated amount is a wrong
/// number on a screen whose only job is to be right about numbers.
@Suite("The transaction row's layout decision")
struct TransactionRowLayoutTests {
    // MARK: - A1 — the amount never yields, at any size

    @Test("The amount yields at no text size whatsoever")
    func theAmountNeverYields() {
        // All twelve, iterated rather than listed, so a thirteenth size added by a future SDK
        // is covered the day it appears instead of the day someone remembers.
        #expect(DynamicTypeSize.allCases.count == 12)
        for size in DynamicTypeSize.allCases {
            let layout = TransactionRowLayout(dynamicTypeSize: size)
            #expect(layout.amountYields == false, "the amount yielded at \(size)")
        }
    }

    // MARK: - A2 — the axis is the accessibility-size question and nothing else

    @Test("The row lays out vertically exactly at the accessibility sizes")
    func theAxisFollowsTheAccessibilitySizes() {
        for size in DynamicTypeSize.allCases {
            let layout = TransactionRowLayout(dynamicTypeSize: size)
            let expected: Axis = size.isAccessibilitySize ? .vertical : .horizontal
            #expect(layout.axis == expected, "wrong axis at \(size)")
        }
    }

    @Test("The five accessibility sizes are vertical and the seven standard ones are not")
    func theSplitIsWhereTheSystemPutsIt() {
        let vertical = DynamicTypeSize.allCases.filter {
            TransactionRowLayout(dynamicTypeSize: $0).axis == .vertical
        }
        #expect(vertical == [.accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5])
    }

    // MARK: - A3 — the yield order, encoded rather than commented

    @Test("The description yields first, the account name second")
    func theDescriptionYieldsBeforeTheAccountName() {
        for size in DynamicTypeSize.allCases {
            let layout = TransactionRowLayout(dynamicTypeSize: size)
            // More lines for the description than for the account name at every size: when
            // space runs out, the description is what gives way, and the account name — which
            // is what stops a transaction being read against the wrong account (FR-022) —
            // holds its single line.
            #expect(layout.descriptionLineLimit > layout.accountNameLineLimit, "at \(size)")
            #expect(layout.accountNameLineLimit == 1, "at \(size)")
            #expect(layout.descriptionLineLimit > 0, "at \(size)")
        }
    }

    @Test("The description is allowed more room once the row goes vertical")
    func theDescriptionGrowsWithTheAxis() {
        let standard = TransactionRowLayout(dynamicTypeSize: .large)
        let accessible = TransactionRowLayout(dynamicTypeSize: .accessibility3)

        #expect(standard.descriptionLineLimit == 2)
        #expect(accessible.descriptionLineLimit == 3)
    }

    // MARK: - The row's edges (FR-020, FR-021)

    private static func row(
        description: String,
        accountName: String = "Everyday Savings",
        last4: String? = "1123",
        amount: String = "1234567.89"
    ) -> TransactionRow {
        TransactionRow(
            HistoryRow(
                id: "row",
                accountId: "account-1",
                accountName: accountName,
                accountLast4: last4,
                date: "2026-07-15",
                descriptionRaw: description,
                amount: TransactionCorpus.decimal(amount),
                direction: .debit,
                currency: "INR",
                categoryName: nil,
                isTransfer: false
            ))
    }

    @Test("A statement that printed no description still produces a complete, announceable row")
    func anEmptyDescriptionStillRendersAWholeRow() {
        // Blank, and blank-looking: a statement that printed spaces is as empty as one that
        // printed nothing, and both must be named rather than left as a gap (FR-020).
        for printed in ["", "   ", "\n", "\t "] {
            let row = Self.row(description: printed)

            #expect(row.displayDescription == TransactionListStrings.missingDescription)
            #expect(!row.displayDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            // Nothing else about the row is missing either: the announcement still carries the
            // date, the amount, the direction in words, the account and the category, so a
            // person using VoiceOver hears a complete transaction rather than a fragment.
            let announced = row.accessibilityLabel
            #expect(announced.contains(TransactionListStrings.missingDescription))
            #expect(announced.contains("2026"))
            #expect(announced.contains(TransactionListStrings.debit))
            #expect(announced.contains(row.accountIdentity))
            #expect(announced.contains(TransactionListStrings.uncategorized))
            // And the amount is there in full — the one thing that may never be abbreviated.
            #expect(announced.contains(row.amount.formatted(.currency(code: "INR"))))
        }
    }

    @Test("A description or account name too long to lay out costs the amount nothing")
    func longTextYieldsAndTheAmountDoesNot() {
        let row = Self.row(
            description: TransactionCorpus.longDescription,
            accountName: String(repeating: "SYNTHETIC LONG ACCOUNT NAME ", count: 4)
        )

        // The row still renders both in full to a screen reader, however little room the
        // screen has: truncation is a layout event, never a content one.
        #expect(row.accessibilityLabel.contains(TransactionCorpus.longDescription))
        #expect(row.accessibilityLabel.contains(row.accountIdentity))
        #expect(row.formattedAmount.contains("1,234,567.89") || row.formattedAmount.contains("12,34,567.89"))

        // And at every text size the yield order is unchanged by the length of what is in the
        // row: the description gives way first, the account name second, the amount never.
        for size in DynamicTypeSize.allCases {
            let layout = TransactionRowLayout(dynamicTypeSize: size)
            #expect(layout.amountYields == false, "the amount yielded at \(size)")
            #expect(layout.descriptionLineLimit > layout.accountNameLineLimit, "at \(size)")
        }
    }

    @Test("An account with no last four still identifies itself")
    func anAccountWithoutALastFourStillIdentifiesItself() {
        let row = Self.row(description: "SYNTHETIC ROW", last4: nil)

        #expect(row.accountIdentity == "Everyday Savings")
        #expect(!row.accountIdentity.contains("ending"))
        #expect(row.accessibilityLabel.contains("Everyday Savings"))
        // And the drawn form says nothing about a mask it does not have: no dots, no
        // separator, no space where digits would be (FR-003).
        #expect(row.accountRowIdentity == "Everyday Savings")
    }

    // MARK: - Issue 04 — the row's one line keeps the part that discriminates

    @Test("Two cards of the same product render different account lines")
    func twoCardsOfOneProductAreToldApartOnScreen() {
        // The exact shape the perf corpus has and the manual gate caught: two
        // `ICICI_AMAZONPAY_CARD` accounts, identical in every respect but their last four.
        let product = "ICICI Amazon Pay Credit Card"
        let one = Self.row(description: "SYNTHETIC ROW", accountName: product, last4: "1002")
        let other = Self.row(description: "SYNTHETIC ROW", accountName: product, last4: "7742")

        #expect(one.accountRowIdentity != other.accountRowIdentity)

        // Different is not enough — a row truncated to `ICICI Amazon Pay Credit Card, endin…`
        // is also "different" from nothing at all. The digits have to survive the truncation,
        // which means they have to come before the name, which is the whole fix.
        #expect(one.accountRowIdentity.hasPrefix(TransactionListStrings.maskedLast4("1002")))
        #expect(other.accountRowIdentity.hasPrefix(TransactionListStrings.maskedLast4("7742")))

        // The prefixes diverge inside the first dozen characters, so the two rows read
        // differently even where the column is narrowest.
        #expect(one.accountRowIdentity.prefix(12) != other.accountRowIdentity.prefix(12))

        // The spoken form is untouched. A screen reader hears a sentence; only the drawing
        // changed (issue 04, "the VoiceOver label must keep its current sentence form").
        #expect(one.accessibilityLabel.contains("\(product), ending 1002"))
        #expect(other.accessibilityLabel.contains("\(product), ending 7742"))
    }

    // MARK: - Purity
    @Test("The decision depends on the text size and nothing else")
    func theLayoutIsAFunctionOfItsInput() {
        for size in DynamicTypeSize.allCases {
            #expect(TransactionRowLayout(dynamicTypeSize: size) == TransactionRowLayout(dynamicTypeSize: size))
        }
        #expect(TransactionRowLayout(dynamicTypeSize: .large) != TransactionRowLayout(dynamicTypeSize: .accessibility1))
    }
}
