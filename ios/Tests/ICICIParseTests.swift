import Foundation
import KanameCore
import Testing

/// "core ↔ Swift ICICI parse" — proves the ported ICICI reader is reachable across the
/// UniFFI bridge and returns exactly what the engine computes (dates, exact `Decimal`
/// amounts, direction from the statement, metadata). Input is 100% synthetic.
@Suite("ICICI statement parse over the bridge")
struct ICICIParseTests {
    private static let lines = [
        "29/04/2026 4262 BBPS Payment received 0 13,628.36 CR",
        "26/05/2026 1814 Fee on gaming transaction 0 10.20",
    ]
    private static let fullText = [
        "ICICI Bank Statement",
        "Statement Date May 28, 2026",
        "4315XXXXXXXX1002",
        "29/04/2026 4262 BBPS Payment received 0 13,628.36 CR",
        "26/05/2026 1814 Fee on gaming transaction 0 10.20",
    ].joined(separator: "\n")

    @Test("Parses the two synthetic rows exactly, with metadata")
    func parsesGoldenStatement() throws {
        let statement = readIciciStatement(lines: Self.lines, fullText: Self.fullText)

        #expect(statement.lines.count == 2)

        let credit = try #require(statement.lines.first)
        #expect(credit.valueDate == "2026-04-29")
        #expect(credit.amount == Decimal(string: "13628.36", locale: Locale(identifier: "en_US_POSIX")))
        #expect(credit.direction == .credit)
        #expect(credit.currency == "INR")
        #expect(credit.descriptionRaw == "4262 BBPS Payment received")

        let debit = statement.lines[1]
        #expect(debit.valueDate == "2026-05-26")
        #expect(debit.amount == Decimal(string: "10.20", locale: Locale(identifier: "en_US_POSIX")))
        #expect(debit.direction == .debit)

        #expect(statement.periodEnd == "2026-05-28")
        #expect(statement.cardLast4 == "1002")
        #expect(statement.erroredLines.isEmpty)
    }

    @Test("Recognizes an ICICI document and rejects other issuers")
    func claimsGatesByIssuer() {
        #expect(iciciClaims(fullText: Self.fullText))
        #expect(!iciciClaims(fullText: "HDFC Bank Credit Cards statement"))
    }
}
