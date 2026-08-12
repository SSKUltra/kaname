import Foundation
import KanameCore
import Testing

/// "store transfers over the bridge" — proves `detect_transfers` tags both legs of a
/// cross-account self-transfer and assigns the pair's category in the same pass, and that the
/// categorization stack cannot clobber it (transfer wins). All data is synthetic.
@Suite("Store transfers over the bridge")
struct StoreTransferTests {
    /// A synthetic 256-bit key (64 hex chars).
    private static let key = "2f1c8a9e4b7d6035112233445566778899aabbccddeeff00112233445566aabb"

    private static func tempDatabase() -> (dir: URL, path: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-transfer-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("kaname.db").path)
    }

    private static func account(_ name: String, isCreditCard: Bool) -> NewAccount {
        NewAccount(
            name: name,
            bankCode: "HDFC",
            isCreditCard: isCreditCard,
            currency: "INR",
            createdAt: "2026-08-08T00:00:00Z",
            updatedAt: "2026-08-08T00:00:00Z"
        )
    }

    private static func transferLeg(
        _ accountId: String,
        _ description: String,
        _ amount: String,
        _ direction: Direction
    ) -> NewTransaction {
        NewTransaction(
            accountId: accountId,
            date: "2026-07-04",
            descriptionRaw: description,
            amount: Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0,
            direction: direction,
            currency: "INR",
            sourceCategory: nil,
            categoryId: nil,
            categorisedBy: nil,
            statementId: nil,
            createdAt: "2026-08-08T00:00:00Z",
            updatedAt: "2026-08-08T00:00:00Z"
        )
    }

    @Test("detect_transfers tags and categorizes both legs of a self-transfer over the bridge")
    func detectTransfersTagsBothLegsOverTheBridge() throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }

        let store = try Store.open(path: db.path, key: Self.key)
        let bankId = try store.insertAccount(account: Self.account("HDFC Savings", isCreditCard: false))
        let cardId = try store.insertAccount(account: Self.account("HDFC Card", isCreditCard: true))

        // A credit-card bill payment: a bank Debit paired with the card's Credit.
        _ = try store.insertTransaction(
            txn: Self.transferLeg(bankId, "CREDIT CARD PAYMENT", "5000.00", .debit))
        _ = try store.insertTransaction(
            txn: Self.transferLeg(cardId, "PAYMENT RECEIVED", "5000.00", .credit))

        let summary = try store.detectTransfers()
        #expect(summary.pairsLinked == 1)
        #expect(summary.creditCardPayments == 1)

        let outflow = try #require(try store.listTransactions(accountId: bankId).first)
        let inflow = try #require(try store.listTransactions(accountId: cardId).first)
        #expect(outflow.isTransfer)
        #expect(inflow.isTransfer)
        let group = try #require(outflow.transferGroupId)
        // Both legs of the pair share one minted group id.
        #expect(inflow.transferGroupId == group)
        // Detection assigns the pair's category in the same pass.
        #expect(outflow.categoryId == "CREDIT_CARD_BILL_PAYMENT")
        #expect(inflow.categoryId == "CREDIT_CARD_BILL_PAYMENT")
        #expect(outflow.categorisedBy == "TRANSFER_DETECTOR")

        // A categorize re-run cannot clobber it — transfer wins over the stack.
        _ = try store.categorizeAccount(accountId: bankId)
        let after = try #require(try store.listTransactions(accountId: bankId).first)
        #expect(after.categoryId == "CREDIT_CARD_BILL_PAYMENT")
        #expect(after.categorisedBy == "TRANSFER_DETECTOR")
    }
}
