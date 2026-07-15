import Foundation
import KanameCore
import Testing

/// "core ↔ Swift HDFC parse" — proves the ported HDFC reader (both statement layouts)
/// is reachable across the UniFFI bridge and returns exactly what the engine computes.
/// A single `readHdfcStatement` auto-selects the layout. Input is 100% synthetic.
@Suite("HDFC statement parse over the bridge")
struct HDFCParseTests {
    private static let yearEndLines = [
        "16-Apr-2025 ONLINE TRF - PYMT RECD - THANK YOU 10,610.00 CR 526873XXXXXX9070",
        "04-Apr-2025 WWW EXAMPLE COM GURGAON 1,071.00 DR 526873XXXXXX9070",
    ]
    private static let yearEndText = [
        "HDFC Bank Credit Cards",
        "Account Summary for the period from APRIL-25 to MARCH-26",
        "Card Number XXXX6873XXXXXX9070",
    ].joined(separator: "\n")

    private static let monthlyLines = [
        "15/05/2026| 13:30 EXAMPLE MERCHANT BANGALORE C 1,639.00",
        "20/05/2026| 09:05 CC PAYMENT RECEIVED + C 6,738.00",
    ]
    private static let monthlyText = [
        "HDFC Bank Credit Card",
        "Billing Period 15 May, 2026 - 14 Jun, 2026",
        "Card Number XXXX1234XXXXXX5678",
    ].joined(separator: "\n")

    private func decimal(_ value: String) throws -> Decimal {
        try #require(Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")))
    }

    @Test("Year-end layout parses exactly, with month-end billing period")
    func parsesYearEndLayout() throws {
        let statement = readHdfcStatement(lines: Self.yearEndLines, fullText: Self.yearEndText)
        #expect(statement.lines.count == 2)

        let credit = try #require(statement.lines.first)
        #expect(credit.valueDate == "2025-04-16")
        #expect(credit.amount == (try decimal("10610.00")))
        #expect(credit.direction == .credit)
        #expect(credit.descriptionRaw == "ONLINE TRF - PYMT RECD - THANK YOU")

        #expect(statement.lines[1].direction == .debit)
        #expect(statement.periodStart == "2025-04-01")
        #expect(statement.periodEnd == "2026-03-31")
        #expect(statement.cardLast4 == "9070")
    }

    @Test("Monthly layout auto-selected; leading + marks the credit")
    func parsesMonthlyLayout() throws {
        let statement = readHdfcStatement(lines: Self.monthlyLines, fullText: Self.monthlyText)
        #expect(statement.lines.count == 2)

        let spend = try #require(statement.lines.first)
        #expect(spend.valueDate == "2026-05-15")
        #expect(spend.amount == (try decimal("1639.00")))
        #expect(spend.direction == .debit)
        #expect(spend.descriptionRaw == "EXAMPLE MERCHANT BANGALORE")

        #expect(statement.lines[1].direction == .credit)
        #expect(statement.lines[1].amount == (try decimal("6738.00")))
        #expect(statement.periodStart == "2026-05-15")
        #expect(statement.periodEnd == "2026-06-14")
        #expect(statement.cardLast4 == "5678")
    }

    @Test("Recognizes an HDFC document and rejects other issuers")
    func claimsGatesByIssuer() {
        #expect(hdfcClaims(fullText: Self.yearEndText))
        #expect(!hdfcClaims(fullText: "ICICI Bank Statement"))
    }
}
