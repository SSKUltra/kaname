import Foundation
import KanameCore
import Testing

/// "core ↔ Swift Federal bank-account parse" — proves the ported Federal Bank
/// balance-ledger reader (both templates) and the balance-chain check are reachable
/// across the UniFFI bridge and return exactly what the engine computes. Synthetic input.
///
/// Federal bank statements are running-balance ledgers; the printed Cr/Dr marks the
/// balance's sign, not the transaction, so direction is derived from the balance delta.
/// Two templates: classic (DD-MON-YYYY, single amount, trailing Cr/Dr, S-serial) and
/// neobank/Fi (DD/MM/YYYY, Withdrawal/Deposit columns, whole-number amounts).
@Suite("Federal bank-account statement parse over the bridge")
struct FederalBankParseTests {
    private static func decimal(_ value: String) -> Decimal? {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static let classicLines = [
        "The Federal Bank Ltd.",
        "Statement of Account for the period 2026-04-01 to 2026-04-30",
        "Account Number : 99990100001234",
        "Type of Account : Savings Account",
        "Date Value Date Particulars Tran Type Tran ID Withdrawals Deposits Balance DR/CR",
        "Opening Balance 1,00,000.00 Cr",
        "08-APR-2026 08-APR-2026 TO ECM/600000000001 TFR S10000001 5,000.00 95,000.00 Cr",
        "/EXAMPLEMERCHANT \\EXAM/07:17",
        "11-APR-2026 11-APR-2026 UPI IN/600000000002 TFR S10000002 50,000.00 1,45,000.00 Cr",
        "/payer@example/Payment/0000",
        "13-APR-2026 13-APR-2026 POS/600000000003/EXAMPLESTORE TFR S10000003 45,000.00 1,00,000.00 Cr",
        "\\EXAM/12:34",
        "GRAND TOTAL 50,000.00 50,000.00",
    ]

    private static let fiLines = [
        "The Federal Bank Ltd. NEO BANKING- EPIFI",
        "Statement of account for the period of 08/04/2026 to 07/05/2026",
        "Account Number: XXXXX4222",
        "Value Tran Cheque Dr/",
        "Opening Balance OPNBAL 1,00,000.00 CR",
        "08/04/2026 08/04/2026 TO ECM/600000000001/EXAMPLE TFR S10000001 5000 0 95,000.00 CR",
        "MERCHANT \\EXAM",
        "20/04/2026 20/04/2026 UPI IN/600000000002/payer TFR S10000002 0 50000 1,45,000.00 CR",
        "Payment f/0000",
    ]

    @Test("Classic template: direction from the delta despite every 'Cr'; S-serial out of the description")
    func parsesClassicTemplate() throws {
        let statement = readFederalBankStatement(
            lines: Self.classicLines, fullText: Self.classicLines.joined(separator: "\n"), firstRowWords: [])
        #expect(statement.lines.count == 3)
        #expect(statement.lines.map(\.direction) == [.debit, .credit, .debit])

        let debit = try #require(statement.lines.first)
        #expect(debit.valueDate == "2026-04-08")
        #expect(debit.amount == Self.decimal("5000.00"))
        // The S-prefixed Tran ID is captured as the serial and kept out of the description.
        #expect(debit.ledger?.serial == "S10000001")
        #expect(debit.descriptionRaw == "TO ECM/600000000001 TFR")
        #expect(!(debit.descriptionRaw.contains("S10000001")))

        #expect(statement.lines[1].amount == Self.decimal("50000.00"))
        #expect(statement.printedOpeningBalance == Self.decimal("100000.00"))
        #expect(statement.printedClosingBalance == Self.decimal("100000.00"))
        #expect(statement.cardLast4 == "1234")
        #expect(statement.periodStart == "2026-04-01")
        #expect(statement.periodEnd == "2026-04-30")
        #expect(checkBalanceChain(statement: statement).status == .reconciled)
    }

    @Test("Fi/neobank template: whole-number amounts from the non-zero column")
    func parsesFiTemplate() throws {
        let statement = readFederalBankStatement(
            lines: Self.fiLines, fullText: Self.fiLines.joined(separator: "\n"), firstRowWords: [])
        #expect(statement.lines.count == 2)
        #expect(statement.lines.map(\.direction) == [.debit, .credit])

        let debit = try #require(statement.lines.first)
        // Whole-number amounts (no decimals printed in the column) still parse.
        #expect(debit.amount == Self.decimal("5000"))
        #expect(statement.lines[1].amount == Self.decimal("50000"))
        #expect(statement.cardLast4 == "4222")
        #expect(statement.printedOpeningBalance == Self.decimal("100000.00"))
        #expect(checkBalanceChain(statement: statement).status == .reconciled)
    }

    @Test("Recognizes a Federal savings statement and rejects the Scapia/Federal credit-card statement")
    func claimsGatesSavingsVsScapiaCard() {
        #expect(federalBankClaims(fullText: Self.classicLines.joined(separator: "\n")))
        #expect(federalBankClaims(fullText: Self.fiLines.joined(separator: "\n")))
        let scapiaCard = [
            "Scapia by Federal Bank",
            "XXXXXXXXXXXX4836 20Apr2026-19May2026",
        ].joined(separator: "\n")
        #expect(!federalBankClaims(fullText: scapiaCard))
    }
}
