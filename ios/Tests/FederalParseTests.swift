import Foundation
import KanameCore
import Testing

/// "core ↔ Swift Federal/Scapia parse" — proves the ported Scapia / Federal Bank reader
/// is reachable across the UniFFI bridge and returns exactly what the engine computes.
/// Input is 100% synthetic. The date/time separator is a middle dot (U+00B7) and the
/// amount is prefixed by the rupee sign (U+20B9); a leading "+" is Scapia's credit marker.
@Suite("Federal/Scapia statement parse over the bridge")
struct FederalParseTests {
    private static let lines = [
        "29-04-2026·16:18 Billpayment Payment +₹324.45",
        "24-04-2026·06:03 ExampleMerchantTokyo ₹2,353.13",
    ]
    private static let fullText = [
        "Scapia by Federal Bank",
        "XXXXXXXXXXXX4836 20Apr2026-19May2026",
        "29-04-2026·16:18 Billpayment Payment +₹324.45",
        "24-04-2026·06:03 ExampleMerchantTokyo ₹2,353.13",
    ].joined(separator: "\n")

    @Test("Parses the two synthetic rows exactly, with cycle and fully-masked last-4")
    func parsesGoldenStatement() throws {
        let statement = readFederalStatement(lines: Self.lines, fullText: Self.fullText)
        #expect(statement.lines.count == 2)

        let credit = try #require(statement.lines.first)
        #expect(credit.valueDate == "2026-04-29")
        #expect(credit.amount == Decimal(string: "324.45", locale: Locale(identifier: "en_US_POSIX")))
        // A leading '+' is Scapia's own credit marker.
        #expect(credit.direction == .credit)
        #expect(credit.descriptionRaw == "Billpayment Payment")

        let debit = statement.lines[1]
        #expect(debit.valueDate == "2026-04-24")
        #expect(debit.amount == Decimal(string: "2353.13", locale: Locale(identifier: "en_US_POSIX")))
        // No '+' and no credit language → an ordinary spend.
        #expect(debit.direction == .debit)

        #expect(statement.periodStart == "2026-04-20")
        #expect(statement.periodEnd == "2026-05-19")
        #expect(statement.cardLast4 == "4836")
    }

    @Test("Recognizes a Federal/Scapia document and rejects other issuers")
    func claimsGatesByIssuer() {
        #expect(federalClaims(fullText: Self.fullText))
        #expect(!federalClaims(fullText: "ICICI Bank Statement"))
    }
}
