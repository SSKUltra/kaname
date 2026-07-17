import Foundation
import KanameCore
import Testing

/// "core ↔ Swift AU bank-account parse" — proves the ported AU Small Finance Bank
/// balance-ledger reader and the balance-chain check are reachable across the UniFFI
/// bridge and return exactly what the engine computes. Input is 100% synthetic.
///
/// AU statements are running-balance ledgers with NO per-row Dr/Cr marker: the UPI/DR /
/// UPI/CR text in a narration is the counterparty's leg and must NOT drive direction,
/// which comes from the balance delta. The empty side of the Debit/Credit pair prints a
/// dash; the reference statement is opening-balance-anchored (empty firstRowWords).
@Suite("AU bank-account statement parse over the bridge")
struct AUBankParseTests {
    private static func decimal(_ value: String) -> Decimal? {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static let lines = [
        "ACCOUNT STATEMENT",
        "Name : Test User Account Number : 1234567890120042",
        "Customer ID : 99999999 Account Type : AU Lite Savings Account",
        "Statement Date : 22 Jun 2026 Opening Balance(₹) : 11,570.79",
        "Statement Period : 01 Mar 2026 to 31 May 2026 Closing Balance(₹) : 223.34",
        "Transaction Cheque/",
        "Value Date Description/Narration Debit (₹) Credit (₹) Balance (₹)",
        "Date Reference No.",
        "UPI/DR/000000000001/EXAMPLE ABC0000000001ref",
        "01 Mar 2026 01 Mar 2026 STORE 1111ref2222tail 5,000.00 - 6,570.79",
        "MERCHANT/UTIB/0000/UPI AU",
        "UPI/CR/000000000002/EXAMPLE XYZ0000000002ref",
        "02 Mar 2026 02 Mar 2026 EMPLOYER 3333ref4444tail - 10,000.00 16,570.79",
        "SALARY/UTIB/0000/UPI AU",
        "1800 1200 1200 www.aubank.in customercare@aubank.in",
    ]
    private static let fullText = lines.joined(separator: "\n")

    @Test("Parses 2 rows; direction from the delta despite UPI/DR-UPI/CR; dash column skipped")
    func parsesGoldenStatement() throws {
        let statement = readAuBankStatement(lines: Self.lines, fullText: Self.fullText, firstRowWords: [])
        #expect(statement.lines.count == 2)

        let debit = try #require(statement.lines.first)
        #expect(debit.valueDate == "2026-03-01")
        // The non-dash (Debit) column is the amount; the balance fell ⇒ debit, even
        // though the narration contains "UPI/DR" (a counterparty leg).
        #expect(debit.amount == Self.decimal("5000.00"))
        #expect(debit.direction == .debit)
        #expect(debit.descriptionRaw.contains("UPI/DR"))

        let credit = statement.lines[1]
        #expect(credit.valueDate == "2026-03-02")
        #expect(credit.amount == Self.decimal("10000.00"))
        #expect(credit.direction == .credit)
        #expect(credit.descriptionRaw.contains("UPI/CR"))

        #expect(statement.printedOpeningBalance == Self.decimal("11570.79"))
        // The last row's running balance, not the header's printed closing (223.34).
        #expect(statement.printedClosingBalance == Self.decimal("16570.79"))
        #expect(statement.cardLast4 == "0042")
        #expect(statement.periodStart == "2026-03-01")
        #expect(statement.periodEnd == "2026-05-31")
        #expect(checkBalanceChain(statement: statement).status == .reconciled)
    }

    @Test("Recognizes an AU savings statement and rejects a credit-card statement")
    func claimsGatesSavingsVsCreditCard() {
        #expect(auBankClaims(fullText: Self.fullText))
        let creditCard = [
            "AU Bank",
            "Your Credit Card Statement",
            "4315XXXXXXXX1002",
        ].joined(separator: "\n")
        #expect(!auBankClaims(fullText: creditCard))
    }
}
