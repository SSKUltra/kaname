import Foundation
import KanameCore
import Testing

/// "core ↔ Swift ICICI bank-account parse" — proves the ported balance-ledger reader and
/// the balance-chain integrity check are reachable across the UniFFI bridge and return
/// exactly what the engine computes. Input is 100% synthetic.
///
/// A bank-account statement is a Withdrawal/Deposit/running-Balance ledger with NO Dr/Cr
/// marker: direction is derived from the balance delta and the printed amount is an
/// independent integrity check. The reference statement is opening-balance-anchored, so
/// no first-row word geometry is needed (an empty `firstRowWords`).
@Suite("ICICI bank-account statement parse over the bridge")
struct ICICIBankParseTests {
    private static let lines = [
        "ICICI Bank Limited",
        "Statement of Transactions in Savings Account",
        "Account Number 000401000123456",
        "Statement Period June 16, 2025 to July 15, 2025",
        "Opening Balance 1,00,000.00",
        "S No. Value Date Transaction Date Cheque No. Transaction Remarks Withdrawal Deposit Balance",
        "UPI/512345/ALICE STORE/Payment",
        "1 16.06.2025 16.06.2025 5,000.00 95,000.00",
        "NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY",
        "2 18.06.2025 18.06.2025 50,000.00 1,45,000.00",
        "3 20.06.2025 20.06.2025 ATM CASH WITHDRAWAL 2,000.00 1,43,000.00",
        "Closing Balance 1,43,000.00",
    ]
    private static let fullText = lines.joined(separator: "\n")

    private static func decimal(_ value: String) -> Decimal? {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    @Test("Parses 3 rows with delta-derived directions, ledger metadata and printed balances")
    func parsesGoldenStatement() throws {
        let statement = readIciciBankStatement(lines: Self.lines, fullText: Self.fullText, firstRowWords: [])
        #expect(statement.lines.count == 3)

        let debit = try #require(statement.lines.first)
        #expect(debit.valueDate == "2025-06-16")
        #expect(debit.amount == Self.decimal("5000.00"))
        // Balance falls 100000 → 95000, so a debit.
        #expect(debit.direction == .debit)
        #expect(debit.descriptionRaw == "UPI/512345/ALICE STORE/Payment")
        let debitLedger = try #require(debit.ledger)
        #expect(debitLedger.balance == Self.decimal("95000.00"))
        #expect(debitLedger.directionSource == .openingBalance)
        #expect(debitLedger.serial == "1")
        #expect(debitLedger.amountMatchesDelta)
        #expect(!debitLedger.isSuspect)

        let credit = statement.lines[1]
        // Balance rises 95000 → 145000, so a credit.
        #expect(credit.direction == .credit)
        #expect(credit.amount == Self.decimal("50000.00"))
        #expect(credit.ledger?.directionSource == .balanceDelta)
        #expect(credit.ledger?.serial == "2")

        // Balance falls 145000 → 143000, so a debit.
        #expect(statement.lines[2].direction == .debit)
        #expect(statement.lines[2].descriptionRaw == "ATM CASH WITHDRAWAL")

        #expect(statement.periodStart == "2025-06-16")
        #expect(statement.periodEnd == "2025-07-15")
        // The account-number tail (not a masked credit-card PAN).
        #expect(statement.cardLast4 == "3456")
        #expect(statement.printedOpeningBalance == Self.decimal("100000.00"))
        #expect(statement.printedClosingBalance == Self.decimal("143000.00"))
        #expect(statement.erroredLines.isEmpty)
    }

    @Test("The balance-chain check reconciles the reference statement")
    func balanceChainReconciles() {
        let statement = readIciciBankStatement(lines: Self.lines, fullText: Self.fullText, firstRowWords: [])
        let result = checkBalanceChain(statement: statement)
        #expect(result.status == .reconciled)
        #expect(result.suspectCount == 0)
        #expect(!result.row1DirectionFallback)
        #expect(result.checkedRows == 3)
    }

    @Test("Recognizes an ICICI savings document and rejects the ICICI credit-card statement")
    func claimsGatesSavingsVsCreditCard() {
        #expect(iciciBankClaims(fullText: Self.fullText))
        let creditCard = [
            "ICICI Bank",
            "SPENDS OVERVIEW",
            "Statement Date May 28, 2026",
            "4315XXXXXXXX1002",
        ].joined(separator: "\n")
        #expect(!iciciBankClaims(fullText: creditCard))
    }
}
