import Foundation
import KanameCore
import Testing

/// "core ↔ Swift Yes Bank parse" — proves the ported Yes Bank (Kiwi) reader is reachable
/// across the UniFFI bridge and returns exactly what the engine computes. Synthetic input.
@Suite("Yes Bank statement parse over the bridge")
struct YesParseTests {
    private static let lines = [
        "29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr",
        "19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr",
    ]
    private static let fullText = [
        "YES BANK KLICK",
        "Statement for YES BANK Card Number 3561XXXXXXXX6686",
        "Statement Period: 17/04/2026 To 16/05/2026",
        "29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr",
        "19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr",
    ].joined(separator: "\n")

    @Test("Parses the two synthetic rows exactly, with period and last-4")
    func parsesGoldenStatement() throws {
        let statement = readYesStatement(lines: Self.lines, fullText: Self.fullText)
        #expect(statement.lines.count == 2)

        let credit = try #require(statement.lines.first)
        #expect(credit.valueDate == "2026-04-29")
        #expect(credit.amount == Decimal(string: "9000.00", locale: Locale(identifier: "en_US_POSIX")))
        #expect(credit.direction == .credit)
        #expect(credit.descriptionRaw == "PAYMENT RECEIVED BBPS - Ref No: RT0001")

        let debit = statement.lines[1]
        #expect(debit.valueDate == "2026-04-19")
        #expect(debit.amount == Decimal(string: "100.00", locale: Locale(identifier: "en_US_POSIX")))
        #expect(debit.direction == .debit)

        #expect(statement.periodStart == "2026-04-17")
        #expect(statement.periodEnd == "2026-05-16")
        #expect(statement.cardLast4 == "6686")
    }

    @Test("Recognizes a Yes Bank document and rejects other issuers")
    func claimsGatesByIssuer() {
        #expect(yesClaims(fullText: Self.fullText))
        #expect(!yesClaims(fullText: "ICICI Bank Statement"))
    }
}
