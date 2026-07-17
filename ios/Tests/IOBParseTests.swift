import Foundation
import KanameCore
import Testing

/// "core ↔ Swift IOB parse" — proves the ported Indian Overseas Bank (IOB) credit-card
/// reader is reachable across the UniFFI bridge and returns exactly what the engine
/// computes. Input is 100% synthetic. Direction is read from the trailing Dr/Cr marker.
@Suite("IOB statement parse over the bridge")
struct IOBParseTests {
    private static let lines = [
        "31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr",
        "04-APR-2026 ExampleStorePurchase 3,500.00 Dr",
    ]
    private static let fullText = [
        "INDIAN OVERSEAS BANK CREDIT CARD DIVISION",
        "Stmt Date: 20-APR-2026 E-Mail: creditcard@iobnet.co.in",
        "Credit Card Number Cash Limit (as part of credit limit) Available Credit Limit",
        "123456XXXXXX0042 16000 25091.5",
        "ACCOUNT SUMMARY",
        "31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr",
        "04-APR-2026 ExampleStorePurchase 3,500.00 Dr",
        "Total Purchase : 2845.50",
    ].joined(separator: "\n")

    @Test("Parses the two synthetic rows exactly, with cycle-end and inline last-4")
    func parsesGoldenStatement() throws {
        let statement = readIobStatement(lines: Self.lines, fullText: Self.fullText)
        #expect(statement.lines.count == 2)

        let credit = try #require(statement.lines.first)
        #expect(credit.valueDate == "2026-03-31")
        #expect(credit.amount == Decimal(string: "1000.00", locale: Locale(identifier: "en_US_POSIX")))
        // Direction is read from the "Cr" marker, not the amount.
        #expect(credit.direction == .credit)
        #expect(credit.descriptionRaw == "ExampleRefundMerchant")

        let debit = statement.lines[1]
        #expect(debit.valueDate == "2026-04-04")
        #expect(debit.amount == Decimal(string: "3500.00", locale: Locale(identifier: "en_US_POSIX")))
        // Direction is read from the "Dr" marker, even though the amount is larger.
        #expect(debit.direction == .debit)

        // IOB prints no period range; only the "Stmt Date" cycle end.
        #expect(statement.periodStart == nil)
        #expect(statement.periodEnd == "2026-04-20")
        // The inline masked PAN's last-4, not digits from the adjacent limit figures.
        #expect(statement.cardLast4 == "0042")
    }

    @Test("Recognizes an IOB document and rejects other issuers")
    func claimsGatesByIssuer() {
        #expect(iobClaims(fullText: Self.fullText))
        #expect(!iobClaims(fullText: "HDFC Bank Credit Cards statement"))
    }
}
