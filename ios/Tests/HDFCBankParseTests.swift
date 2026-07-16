import Foundation
import KanameCore
import Testing

/// "core ↔ Swift HDFC bank-account parse" — proves the ported HDFC Bank balance-ledger
/// reader (both export layouts) and the balance-chain check are reachable across the
/// UniFFI bridge and return exactly what the engine computes. Input is 100% synthetic.
///
/// HDFC issues two layouts behind one reader: a compact one (DD/MM/YY dates, a single
/// printed amount after an alphanumeric reference) and a detailed one (DD/MM/YYYY with
/// explicit Withdrawals/Deposits columns). Direction is derived from the balance delta
/// in both. The reference statements are opening-balance-anchored (empty firstRowWords).
@Suite("HDFC bank-account statement parse over the bridge")
struct HDFCBankParseTests {
    private static func decimal(_ value: String) -> Decimal? {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static let compactLines = [
        "HDFC BANK LIMITED",
        "Statementof account",
        "From : 01/04/2026 To : 30/04/2026",
        "AccountNo : 50100359253425",
        "Date Narration Chq./Ref.No. ValueDt WithdrawalAmt. DepositAmt. ClosingBalance",
        "01/04/26 UPI-EXAMPLEMERCHANT 0000600000000001 01/04/26 5,000.00 95,000.00",
        "16/04/26 NEFTCR-EXAMPLEEMPLOYER CITIN26653417445 16/04/26 50,000.00 1,45,000.00",
        "OpeningBalance DrCount CrCount Debits Credits ClosingBal",
        "1,00,000.00 1 1 5,000.00 50,000.00 1,45,000.00",
    ]

    private static let detailedLines = [
        "HDFC Bank",
        "Savings Account Details",
        "Statement From : 01/04/2026 To 30/04/2026",
        "Account Number : 50100359253425",
        "Opening Balance : 1,00,000.00 Limit : 0.00",
        "Txn Date Narration Withdrawals Deposits Closing Balance",
        "01/04/2026 UPI-EXAMPLEMERCHANT 5,000.00 0.00 95,000.00",
        "20/04/2026 UPI-EXAMPLEEMPLOYER salary 0.00 50,000.00 1,45,000.00",
    ]

    @Test("Compact layout: alphanumeric serial, single amount, opening from the summary")
    func parsesCompactLayout() throws {
        let statement = readHdfcBankStatement(
            lines: Self.compactLines, fullText: Self.compactLines.joined(separator: "\n"), firstRowWords: [])
        #expect(statement.lines.count == 2)

        let debit = try #require(statement.lines.first)
        // The 2-digit compact year resolves to 2026 (DATE_FORMATS order).
        #expect(debit.valueDate == "2026-04-01")
        #expect(debit.amount == Self.decimal("5000.00"))
        #expect(debit.direction == .debit)
        #expect(debit.ledger?.serial == "0000600000000001")

        let credit = statement.lines[1]
        #expect(credit.direction == .credit)
        #expect(credit.amount == Self.decimal("50000.00"))
        // The NEFT row's alphanumeric reference is captured as the serial.
        #expect(credit.ledger?.serial == "CITIN26653417445")

        #expect(statement.printedOpeningBalance == Self.decimal("100000.00"))
        #expect(statement.printedClosingBalance == Self.decimal("145000.00"))
        #expect(statement.cardLast4 == "3425")
        #expect(statement.periodStart == "2026-04-01")
        #expect(statement.periodEnd == "2026-04-30")
        #expect(checkBalanceChain(statement: statement).status == .reconciled)
    }

    @Test("Detailed layout: amount from the non-zero withdrawal/deposit column")
    func parsesDetailedLayout() throws {
        let statement = readHdfcBankStatement(
            lines: Self.detailedLines, fullText: Self.detailedLines.joined(separator: "\n"), firstRowWords: [])
        #expect(statement.lines.count == 2)

        let debit = try #require(statement.lines.first)
        #expect(debit.valueDate == "2026-04-01")
        #expect(debit.amount == Self.decimal("5000.00"))
        // The non-zero withdrawal column is the amount; the balance fell ⇒ debit.
        #expect(debit.direction == .debit)

        let credit = statement.lines[1]
        #expect(credit.valueDate == "2026-04-20")
        #expect(credit.amount == Self.decimal("50000.00"))
        // The non-zero deposit column is the amount; the balance rose ⇒ credit.
        #expect(credit.direction == .credit)
        #expect(credit.descriptionRaw == "UPI-EXAMPLEEMPLOYER salary")

        #expect(statement.printedOpeningBalance == Self.decimal("100000.00"))
        #expect(statement.cardLast4 == "3425")
        #expect(checkBalanceChain(statement: statement).status == .reconciled)
    }

    @Test("Recognizes both HDFC savings layouts and rejects the HDFC credit-card statement")
    func claimsGatesSavingsVsCreditCard() {
        #expect(hdfcBankClaims(fullText: Self.compactLines.joined(separator: "\n")))
        #expect(hdfcBankClaims(fullText: Self.detailedLines.joined(separator: "\n")))
        let creditCard = [
            "HDFC Bank Credit Cards",
            "Card Number XXXX6873XXXXXX9070",
        ].joined(separator: "\n")
        #expect(!hdfcBankClaims(fullText: creditCard))
    }
}
