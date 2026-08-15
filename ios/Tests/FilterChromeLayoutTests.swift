import Foundation
import SwiftUI
import Testing

@testable import Kaname

/// The filter bar's layout decision, proved with nothing on screen.
///
/// The same trade `TransactionRowLayoutTests` makes: a unit test cannot measure a rendered
/// frame, so the *decision* is extracted into a pure value and the rendering stays on the
/// manual gate (FR-074/FR-075). What the gate found, and what these tests now hold, is that at
/// accessibility sizes the bar had no decision to make — two hard `lineLimit(1)`s and a button
/// with no limit at all — so the only thing that could give was the string, and what it gave
/// up was the account's identity (`.scratch/018-transaction-list/issues/02`, `03`).
@Suite("The filter chrome's layout decision")
struct FilterChromeLayoutTests {
    private static let mask = TransactionListStrings.maskedLast4("7742")
    private static let name = "ICICI Amazon Pay Credit Card"

    // MARK: - Issue 02 — the last four is never the thing that is dropped

    @Test("At every accessibility size the chip leads with the masked digits")
    func theMaskLeadsWhereThereIsNoRoomForTheName() {
        for size in DynamicTypeSize.allCases where size.isAccessibilitySize {
            let lines = FilterChromeLayout(dynamicTypeSize: size)
                .scopeLines(title: Self.name, subtitle: Self.mask)

            // First, so it is drawn before the name has spent the width; on one line, so it is
            // never the thing that wraps; and never truncated in the middle, because a mask
            // with its middle removed is a different mask.
            #expect(lines.first?.role == .mask, "at \(size)")
            #expect(lines.first?.text == Self.mask, "at \(size)")
            #expect(lines.first?.isPrimary == true, "at \(size)")
            #expect(lines.first?.lineLimit == 1, "at \(size)")
            #expect(lines.first?.truncatesInTheMiddle == false, "at \(size)")

            // The digits are in the chip at all — the failure was `·····…`, a mask that had
            // become a row of dots.
            #expect(lines.contains { $0.text.contains("7742") }, "at \(size)")
        }
    }

    @Test("At every size the chip carries both the name and the digits")
    func nothingAboutTheAccountIsEverDropped() {
        for size in DynamicTypeSize.allCases {
            let lines = FilterChromeLayout(dynamicTypeSize: size)
                .scopeLines(title: Self.name, subtitle: Self.mask)

            #expect(lines.count == 2, "at \(size)")
            #expect(Set(lines.map(\.role)) == [.mask, .name], "at \(size)")
            #expect(lines.filter(\.isPrimary).count == 1, "at \(size)")
            #expect(lines.contains { $0.text == Self.name }, "at \(size)")
            #expect(lines.contains { $0.text == Self.mask }, "at \(size)")
        }
    }

    @Test("The standard sizes keep the shape that already reads correctly")
    func theStandardSizesAreUnchanged() {
        for size in DynamicTypeSize.allCases where !size.isAccessibilitySize {
            let layout = FilterChromeLayout(dynamicTypeSize: size)
            let lines = layout.scopeLines(title: Self.name, subtitle: Self.mask)

            // Name above mask, one line each — what the gate verified as correct at the
            // default size. The fix is not permitted to "improve" a surface that passed.
            #expect(lines.map(\.role) == [.name, .mask], "at \(size)")
            #expect(lines.allSatisfy { $0.lineLimit == 1 }, "at \(size)")
            #expect(lines.first?.isPrimary == true, "at \(size)")
            #expect(layout.clearButtonShowsTitle, "at \(size)")
        }
    }

    @Test("An unfiltered chip is one line and says so")
    func theUnfilteredChipIsOneLine() {
        for size in DynamicTypeSize.allCases {
            let lines = FilterChromeLayout(dynamicTypeSize: size)
                .scopeLines(title: TransactionListStrings.scopeAll, subtitle: nil)

            #expect(lines.count == 1, "at \(size)")
            #expect(lines.first?.role == .name, "at \(size)")
            #expect(lines.first?.text == TransactionListStrings.scopeAll, "at \(size)")
        }
    }

    // MARK: - Issue 03 — the bar's height is bounded, at every size

    @Test("The bar goes vertical exactly where the chip needs the whole width")
    func theBarStacksAtTheAccessibilitySizes() {
        for size in DynamicTypeSize.allCases {
            let layout = FilterChromeLayout(dynamicTypeSize: size)
            let expected: Axis = size.isAccessibilitySize ? .vertical : .horizontal
            #expect(layout.axis == expected, "at \(size)")
        }

        // Why it cannot be a taste question: at the largest size the masked digits alone want
        // roughly 280 pt and the collapsed clear button roughly 110 pt, which with the bar's
        // 32 pt of horizontal padding overruns a 393 pt screen. The first fix for issue 02
        // kept the bar horizontal, and G5 failed a second time with the chip reading
        // `•••• 77…` — the digits truncated, which was the entire thing being fixed.
        #expect(FilterChromeLayout(dynamicTypeSize: .accessibility5).axis == .vertical)
        #expect(FilterChromeLayout(dynamicTypeSize: .large).axis == .horizontal)
    }

    @Test("The clear button drops its words exactly at the accessibility sizes")
    func theClearButtonCollapsesWhereItWouldOtherwiseWrap() {
        for size in DynamicTypeSize.allCases {
            let layout = FilterChromeLayout(dynamicTypeSize: size)
            #expect(layout.clearButtonShowsTitle == !size.isAccessibilitySize, "at \(size)")
        }
    }

    @Test("The chip can never grow past three lines, at any size")
    func theBarsHeightIsBounded() {
        for size in DynamicTypeSize.allCases {
            let layout = FilterChromeLayout(dynamicTypeSize: size)
            let drawn = layout.scopeLines(title: Self.name, subtitle: Self.mask)

            // A bottom bar that grows without bound eats the list above it, and that is how a
            // row's amount came to be sliced through the glyphs (issue 03). The bound is not a
            // comment: the lines the chip will draw sum to no more than the layout's own
            // stated maximum, and that maximum is small.
            #expect(layout.maximumScopeLines <= 3, "at \(size)")
            #expect(drawn.reduce(0) { $0 + $1.lineLimit } <= layout.maximumScopeLines, "at \(size)")
        }
    }

    // MARK: - Purity

    @Test("The decision depends on the text size and nothing else")
    func theLayoutIsAFunctionOfItsInput() {
        for size in DynamicTypeSize.allCases {
            #expect(FilterChromeLayout(dynamicTypeSize: size) == FilterChromeLayout(dynamicTypeSize: size))
        }
        #expect(
            FilterChromeLayout(dynamicTypeSize: .large) != FilterChromeLayout(dynamicTypeSize: .accessibility1))
    }
}
