import Foundation
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

    // MARK: - Purity

    @Test("The decision depends on the text size and nothing else")
    func theLayoutIsAFunctionOfItsInput() {
        for size in DynamicTypeSize.allCases {
            #expect(TransactionRowLayout(dynamicTypeSize: size) == TransactionRowLayout(dynamicTypeSize: size))
        }
        #expect(TransactionRowLayout(dynamicTypeSize: .large) != TransactionRowLayout(dynamicTypeSize: .accessibility1))
    }
}
