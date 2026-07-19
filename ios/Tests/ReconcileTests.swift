import Foundation
import KanameCore
import Testing

/// "core ↔ Swift reconciliation" — proves the ported credit-card reconciliation check (the
/// counterpart to the bank-ledger balance-chain) is reachable across the UniFFI bridge and
/// returns exactly what the engine computes. Input is 100% synthetic.
///
/// The check compares the read Debit/Credit sums against the statement's own printed totals
/// (Yes: "Current Purchases … Dr" / "Payment & Credits Received … Cr"; IOB: the ACCOUNT
/// SUMMARY values row) within a ₹1.00 tolerance → RECONCILED. A statement that prints no
/// totals (ICICI) yields a neutral outcome (status nil), distinct from a NEEDS_REVIEW mismatch.
@Suite("Credit-card reconciliation over the bridge")
struct ReconcileTests {
    private static func decimal(_ value: String) -> Decimal? {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static let yesLines = [
        "29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr",
        "19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr",
    ]
    private static let yesFullText = [
        "YES BANK KLICK",
        "Statement for YES BANK Card Number 3561XXXXXXXX6686",
        "Statement Period: 17/04/2026 To 16/05/2026",
        "Current Purchases / Cash Advance & Other Charges : Rs. 100.00 Dr",
        "Payment & Credits Received : Rs. 9,000.00 Cr",
        "29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr",
        "19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr",
    ].joined(separator: "\n")

    // The full IOB fixture: the ACCOUNT SUMMARY values row carries the printed credit (2nd =
    // 1,000.00) and debit (3rd = 3,500.00) totals the check compares the read rows against.
    private static let iobLines = [
        "123456XXXXXX0042 16000 25091.5",
        "ACCOUNT SUMMARY",
        "Previous Balance Payment / Credits Purchases / Debits Fee, Taxes and Interest Charge Total Outstanding",
        "- + + =",
        "345.50 1,000.00 3,500.00 0 2,845.50",
        "31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr",
        "04-APR-2026 ExampleStorePurchase 3,500.00 Dr",
    ]
    private static let iobFullText = [
        "INDIAN OVERSEAS BANK CREDIT CARD DIVISION",
        "Stmt Date: 20-APR-2026 E-Mail: creditcard@iobnet.co.in",
        "Credit Card Number Cash Limit (as part of credit limit) Available Credit Limit",
        "123456XXXXXX0042 16000 25091.5",
        "ACCOUNT SUMMARY",
        "Previous Balance Payment / Credits Purchases / Debits Fee, Taxes and Interest Charge Total Outstanding",
        "- + + =",
        "345.50 1,000.00 3,500.00 0 2,845.50",
        "31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr",
        "04-APR-2026 ExampleStorePurchase 3,500.00 Dr",
    ].joined(separator: "\n")

    private static let iciciLines = [
        "29/04/2026 4262 BBPS Payment received 0 13,628.36 CR",
        "26/05/2026 1814 Fee on gaming transaction 0 10.20",
    ]
    private static let iciciFullText = [
        "ICICI Bank Statement",
        "Statement Date May 28, 2026",
        "4315XXXXXXXX1002",
        "29/04/2026 4262 BBPS Payment received 0 13,628.36 CR",
        "26/05/2026 1814 Fee on gaming transaction 0 10.20",
    ].joined(separator: "\n")

    @Test("Yes: read sums match the printed totals → RECONCILED, with the totals surfaced")
    func yesReconciles() {
        let statement = readYesStatement(lines: Self.yesLines, fullText: Self.yesFullText)
        #expect(statement.printedTotalDebits == Self.decimal("100.00"))
        #expect(statement.printedTotalCredits == Self.decimal("9000.00"))

        let result = reconcileStatement(statement: statement)
        #expect(result.status == .reconciled)
        #expect(result.readDebits == Self.decimal("100.00"))
        #expect(result.readCredits == Self.decimal("9000.00"))
        #expect(result.printedDebits == Self.decimal("100.00"))
        #expect(result.printedCredits == Self.decimal("9000.00"))
    }

    @Test("IOB: the ACCOUNT SUMMARY totals match the read rows → RECONCILED")
    func iobReconciles() {
        let statement = readIobStatement(lines: Self.iobLines, fullText: Self.iobFullText)
        #expect(statement.printedTotalDebits == Self.decimal("3500.00"))
        #expect(statement.printedTotalCredits == Self.decimal("1000.00"))

        let result = reconcileStatement(statement: statement)
        #expect(result.status == .reconciled)
        #expect(result.readDebits == Self.decimal("3500.00"))
        #expect(result.readCredits == Self.decimal("1000.00"))
    }

    @Test("ICICI prints no totals → neutral (status nil), not a NEEDS_REVIEW mismatch")
    func iciciIsNeutral() {
        let statement = readIciciStatement(lines: Self.iciciLines, fullText: Self.iciciFullText)
        #expect(statement.printedTotalDebits == nil)
        #expect(statement.printedTotalCredits == nil)

        let result = reconcileStatement(statement: statement)
        #expect(result.status == nil)
        #expect(result.reason == "no printed totals extracted")
    }
}
