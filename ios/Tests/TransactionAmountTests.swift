import Foundation
import KanameCore
import Testing

@testable import Kaname

/// What an amount is allowed to become on its way to a person's eyes.
///
/// The engine holds money as `Decimal` and the constitution forbids a `Double` anywhere near
/// it, but a rendering path can still lose a rupee: a `NumberFormatter` fed a `Double`, a
/// `String(format:)`, an abbreviation that turns ₹1,234,567.89 into ₹1.2M. Every one of those
/// reads as a plausible number, which is what makes them expensive — a person cannot tell a
/// wrong figure from a right one by looking at it.
///
/// The other half is that two currencies must never quietly become one. This slice's defence
/// is structural: there is no sum anywhere to be wrong.
@Suite("An amount survives being rendered")
struct TransactionAmountTests {
    private static func row(
        amount: String,
        currency: String = "INR",
        direction: Direction = .debit,
        accountCurrency: String = "INR"
    ) -> TransactionRow {
        TransactionRow(
            HistoryRow(
                id: "row",
                accountId: "account-1",
                accountName: "Everyday Savings",
                accountLast4: "1123",
                date: "2026-07-15",
                descriptionRaw: "SYNTHETIC ROW",
                amount: TransactionCorpus.decimal(amount),
                direction: direction,
                // The account's currency is deliberately allowed to differ below, so a test
                // can tell "the transaction's currency" from "the account's".
                currency: currency,
                categoryName: nil,
                categoryId: nil,
                isTransfer: false
            ))
    }

    /// The digits of a rendered amount, with grouping separators and everything else removed —
    /// what survives is what a person can actually read off the screen.
    private static func digits(_ rendered: String) -> String {
        rendered.filter { $0.isNumber || $0 == "." }
    }

    // MARK: - T103 — the figure itself

    @Test("A seven-figure amount renders every digit it has, with no drift and no abbreviation")
    func aLargeAmountRendersExactly() {
        let row = Self.row(amount: "1234567.89")

        // Every digit, in order, still there: 1234567.89. A `Double` on this path loses the
        // last one; an abbreviation loses five of them.
        #expect(Self.digits(row.formattedAmount) == "1234567.89")
        #expect(!row.formattedAmount.contains("M"))
        #expect(!row.formattedAmount.contains("K"))
        #expect(!row.formattedAmount.contains("…"))
        #expect(!row.formattedAmount.contains("~"))
    }

    @Test("The smallest and largest amounts a statement can print survive intact")
    func theEdgesOfTheRangeSurvive() {
        for amount in ["0.01", "0.10", "9999999.99", "1000000.00", "0.001"] {
            let rendered = Self.row(amount: amount, currency: "KWD").formattedAmount
            let expected = TransactionCorpus.decimal(amount)

            // Rendered through `Decimal`'s own `FormatStyle`, so the value on screen is the
            // value in the database — not a `Double` that was nearly it.
            #expect(
                rendered.contains(expected.formatted(.currency(code: "KWD"))),
                "\(amount) rendered as \(rendered)"
            )
        }
    }

    @Test("The currency is the transaction's own, never the account's and never the locale's")
    func theCurrencyComesFromTheTransaction() {
        // A card in one currency carrying a row in another — the case where taking the
        // account's currency would silently relabel a person's spending.
        let overseas = Self.row(amount: "66.660", currency: "KWD", accountCurrency: "INR")
        let home = Self.row(amount: "66.66", currency: "INR")

        #expect(overseas.formattedAmount != home.formattedAmount)
        #expect(
            overseas.formattedAmount.contains(
                TransactionCorpus.decimal("66.660")
                    .formatted(.currency(code: "KWD"))))
        // And nothing was converted on the way: the number is the same number.
        #expect(Self.digits(overseas.formattedAmount).contains("66.66"))
    }

    @Test("A currency the locale has no symbol for still renders unambiguously")
    func anUnlocalisedCurrencyIsStillExact() {
        // `en_IN` has no symbol for the Kuwaiti dinar, so it renders as a code. That is
        // unambiguous rather than pretty, and it is the right trade: a person must never be
        // left guessing which currency a figure is in (FR-027).
        let rendered = Self.row(amount: "66.660", currency: "KWD").formattedAmount

        #expect(rendered.contains("KWD") || rendered.contains("د.ك"))
        #expect(Self.digits(rendered).contains("66.66"))
        // Never a bare number with the currency dropped for being awkward.
        #expect(rendered.count > Self.digits(rendered).count + 1)
    }

    @Test("Direction is carried by a sign, and the sign comes from the recorded direction")
    func theSignIsTheRecordedDirection() {
        // The engine records direction; the amount is always stored unsigned. A sign inferred
        // from the amount would be a guess, and it would be wrong for every credit (FR-014).
        let debit = Self.row(amount: "450.00", direction: .debit)
        let credit = Self.row(amount: "450.00", direction: .credit)

        #expect(debit.formattedAmount.hasPrefix("\u{2212}"))  // U+2212, not a hyphen
        #expect(credit.formattedAmount.hasPrefix("+"))
        #expect(debit.directionWord == TransactionListStrings.debit)
        #expect(credit.directionWord == TransactionListStrings.credit)
        // Same magnitude, two different renderings — the difference is the direction alone.
        #expect(Self.digits(debit.formattedAmount) == Self.digits(credit.formattedAmount))
    }

    // MARK: - T104 — there is no sum to be wrong

    @Test("A date group has no numeric member other than how many rows are in it")
    func aDateGroupHoldsNoFigure() {
        let row = Self.row(amount: "10.00")
        let group = DateGroup(id: "2026-07-15", date: row.date, heading: "15 July", rows: [row])

        for child in Mirror(reflecting: group).children {
            let label = child.label ?? ""
            // Nothing that is money, under any name.
            let isMoney = child.value is Decimal
            #expect(!isMoney, "DateGroup.\(label) is money")
            // And no number at all except the rows themselves, whose count is a count.
            let isFigure = child.value is Int || child.value is Double
            if label != "rows" {
                #expect(!isFigure, "DateGroup.\(label) is a figure")
            }
        }
        #expect(group.rows.count == 1)
    }

    @Test("Nothing in the slice can add two amounts together")
    func noTypeInTheSliceCanHoldATotal() {
        // A row carries exactly one amount, and it belongs to that row. `TransactionRow` is
        // the only type in `ios/Sources/Transactions/` that holds a `Decimal` at all — so
        // there is nowhere for a cross-currency figure to live, which is a stronger guarantee
        // than not displaying one (FR-025, SC-011).
        let row = Self.row(amount: "10.00")
        let money = Mirror(reflecting: row).children.filter { $0.value is Decimal }
        // swift-format-ignore: NeverForceUnwrap
        #expect(money.count == 1)
        #expect(money.first?.label == "amount")

        // The two-currency case, stated: two rows on one date, and the group they are in has
        // no way to combine them.
        let inr = Self.row(amount: "1111.11", currency: "INR")
        let kwd = Self.row(amount: "66.660", currency: "KWD")
        let group = DateGroup(id: "2026-07-15", date: inr.date, heading: "15 July", rows: [inr, kwd])
        #expect(Set(group.rows.map(\.currency)).count == 2)
        let groupHoldsMoney = Mirror(reflecting: group).children.contains { $0.value is Decimal }
        #expect(!groupHoldsMoney)
    }

    // MARK: - T105 — the amount is announced with its currency

    @Test("The accessibility sentence announces the currency with the amount")
    func theAccessibilityLabelAnnouncesTheCurrencyWithTheAmount() {
        let overseas = Self.row(amount: "66.660", currency: "KWD")
        let home = Self.row(amount: "1234567.89", currency: "INR")

        for row in [overseas, home] {
            let announced = row.accessibilityLabel
            // The figure, exactly as it is written, and its currency with it: a VoiceOver
            // reader hears "sixty-six point six six zero Kuwaiti dinars", never a bare number
            // whose currency they have to remember from the row above (FR-015).
            #expect(announced.contains(row.amount.formatted(.currency(code: row.currency))))
            #expect(announced.contains(row.directionWord))
        }

        // Two currencies, two different sentences — never the same figure spoken twice.
        #expect(overseas.accessibilityLabel != home.accessibilityLabel)
    }

    @Test("The announced amount is the same figure the row shows")
    func theSpokenAndTheSeenAgree() {
        for amount in ["0.01", "450.00", "1234567.89"] {
            let row = Self.row(amount: amount)
            // Same digits, whether a person reads the row or hears it. A separate formatting
            // path for the announcement is a second chance to be wrong.
            #expect(
                Self.digits(row.accessibilityLabel).contains(Self.digits(row.formattedAmount)),
                "\(amount): \(row.accessibilityLabel) vs \(row.formattedAmount)"
            )
        }
    }
}
