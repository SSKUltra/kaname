import Foundation
import KanameCore
import Testing

/// "core ↔ Swift SBI parse" — proves the ported SBI Card reader is reachable across the
/// UniFFI bridge and returns exactly what the engine computes. Input is 100% synthetic.
@Suite("SBI Card statement parse over the bridge")
struct SBIParseTests {
    private static let lines = [
        "21 Apr 26 CARD CASHBACK CREDIT 643.00 C",
        "20 May 26 APPLE INDIA STORE MUMBAI IN 82,900.00 D",
    ]
    private static let fullText = [
        "GSTIN of SBI Card",
        "Credit Card Number XXXX XXXX XXXX XX61",
        "for Statement Period: 22 Apr 26 to 21 May 26",
        "21 Apr 26 CARD CASHBACK CREDIT 643.00 C",
        "20 May 26 APPLE INDIA STORE MUMBAI IN 82,900.00 D",
    ].joined(separator: "\n")

    @Test("Parses the two synthetic rows exactly; last-4 absent for a 2-digit mask")
    func parsesGoldenStatement() throws {
        let statement = readSbiStatement(lines: Self.lines, fullText: Self.fullText)
        #expect(statement.lines.count == 2)

        let credit = try #require(statement.lines.first)
        #expect(credit.valueDate == "2026-04-21")
        #expect(credit.amount == Decimal(string: "643.00", locale: Locale(identifier: "en_US_POSIX")))
        #expect(credit.direction == .credit)
        #expect(credit.descriptionRaw == "CARD CASHBACK CREDIT")

        let debit = statement.lines[1]
        #expect(debit.valueDate == "2026-05-20")
        #expect(debit.amount == Decimal(string: "82900.00", locale: Locale(identifier: "en_US_POSIX")))
        #expect(debit.direction == .debit)

        #expect(statement.periodStart == "2026-04-22")
        #expect(statement.periodEnd == "2026-05-21")
        #expect(statement.cardLast4 == nil)
    }

    @Test("Recognizes an SBI document and rejects other issuers")
    func claimsGatesByIssuer() {
        #expect(sbiClaims(fullText: Self.fullText))
        #expect(!sbiClaims(fullText: "ICICI Bank Statement"))
    }
}
