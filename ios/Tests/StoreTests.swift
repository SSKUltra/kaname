import Foundation
import KanameCore
import Testing

/// "core ↔ Swift encrypted store" — proves the stateful `Store` object is reachable across
/// the UniFFI bridge: a transaction round-trips exactly (money as `Decimal`, date and
/// direction preserved), the seeded catalog crosses as the 23 defaults, and a wrong or
/// malformed key throws instead of returning a readable database. All data is synthetic.
@Suite("Encrypted store over the bridge")
struct StoreTests {
    /// A synthetic 256-bit key (64 hex chars).
    private static let key = "2f1c8a9e4b7d6035112233445566778899aabbccddeeff00112233445566aabb"
    /// A different, valid-format 256-bit key — used to prove wrong-key fails closed.
    private static let otherKey =
        "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"

    private static func decimal(_ amount: String) -> Decimal {
        Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// A fresh temp database path; the caller removes the directory when done.
    private static func tempDatabase() -> (dir: URL, path: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-store-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("kaname.db").path)
    }

    private static func sampleAccount() -> NewAccount {
        NewAccount(
            name: "HDFC Savings",
            bankCode: "HDFC",
            isCreditCard: false,
            currency: "INR",
            createdAt: "2026-08-08T00:00:00Z",
            updatedAt: "2026-08-08T00:00:00Z"
        )
    }

    @Test("A transaction round-trips exactly through the encrypted store")
    func transactionRoundTripsOverTheBridge() throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }

        let store = try Store.open(path: db.path, key: Self.key)
        let accountId = try store.insertAccount(account: Self.sampleAccount())

        let txn = NewTransaction(
            accountId: accountId,
            date: "2026-07-04",
            descriptionRaw: "UPI-SWIGGY-123456",
            amount: Self.decimal("1234.56"),
            direction: .debit,
            currency: "INR",
            sourceCategory: nil,
            categoryId: "FOOD_AND_DINING",
            categorisedBy: "T2_MERCHANT_MAP",
            statementId: nil,
            createdAt: "2026-08-08T10:00:00Z",
            updatedAt: "2026-08-08T10:00:00Z"
        )
        let txnId = try store.insertTransaction(txn: txn)

        let stored = try store.listTransactions(accountId: accountId)
        #expect(stored.count == 1)
        let got = try #require(stored.first)
        #expect(got.id == txnId)
        #expect(got.accountId == accountId)
        // Money survives as an exact Decimal — no float drift over the bridge or in storage.
        #expect(got.amount == Self.decimal("1234.56"))
        #expect(got.date == "2026-07-04")
        #expect(got.direction == .debit)
        #expect(got.descriptionRaw == "UPI-SWIGGY-123456")
        #expect(got.currency == "INR")
        #expect(got.categoryId == "FOOD_AND_DINING")
        #expect(got.categorisedBy == "T2_MERCHANT_MAP")
        #expect(got.isDeleted == false)
    }

    @Test("The 23 default categories are seeded and cross the bridge")
    func seededCategoriesCrossTheBridge() throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }

        let store = try Store.open(path: db.path, key: Self.key)
        let categories = try store.listCategories()
        #expect(categories.count == 23)

        let groceries = try #require(categories.first { $0.name == "Groceries" })
        guard case .builtin(let code) = groceries.categoryRef else {
            Issue.record("Groceries must be a built-in category")
            return
        }
        #expect(code == "GROCERIES")
        #expect(groceries.classification == .spend)
    }

    @Test("A wrong key fails closed over the bridge")
    func wrongKeyThrowsOverTheBridge() throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }

        // Create + seed with the correct key, then release the connection.
        try Self.seed(path: db.path)

        // Re-opening with a different (valid-format) key must throw WrongKey.
        #expect(throws: StoreError.WrongKey) {
            _ = try Store.open(path: db.path, key: Self.otherKey)
        }

        // The correct key still opens and reads the seeded account back.
        let store = try Store.open(path: db.path, key: Self.key)
        #expect(try store.listAccounts().count == 1)
    }

    @Test("A malformed key throws InvalidKey")
    func malformedKeyThrowsOverTheBridge() {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }

        #expect(throws: StoreError.InvalidKey) {
            _ = try Store.open(path: db.path, key: "too-short")
        }
    }

    @Test("categorize_account persists the stack's results over the bridge")
    func categorizeAccountPersistsResultsOverTheBridge() throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }

        let store = try Store.open(path: db.path, key: Self.key)
        let accountId = try store.insertAccount(account: Self.sampleAccount())

        // A T2 merchant "memory": "swiggy" → Food & Dining (a built-in).
        _ = try store.insertMerchantRule(
            rule: MerchantRule(
                priority: 10,
                matchType: .literal,
                pattern: "swiggy",
                category: .builtin(code: "FOOD_AND_DINING")
            )
        )
        _ = try store.insertTransaction(txn: Self.categoryTxn(accountId, "UPI-SWIGGY-123456"))
        _ = try store.insertTransaction(txn: Self.categoryTxn(accountId, "UNKNOWN VENDOR XYZ"))

        let summary = try store.categorizeAccount(accountId: accountId)
        #expect(summary.categorized == 1)
        #expect(summary.uncategorized == 1)

        let stored = try store.listTransactions(accountId: accountId)
        #expect(stored.count == 2)
        #expect(stored[0].categoryId == "FOOD_AND_DINING")
        #expect(stored[0].categorisedBy == "T2_MERCHANT_MAP")
        #expect(stored[1].categoryId == nil)
        #expect(stored[1].categorisedBy == nil)
    }

    @Test("detect_transfers tags both legs of a self-transfer over the bridge")
    func detectTransfersTagsBothLegsOverTheBridge() throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }

        let store = try Store.open(path: db.path, key: Self.key)
        let bankId = try store.insertAccount(account: Self.sampleAccount())
        let cardId = try store.insertAccount(account: Self.cardAccount())

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
    }

    @Test("find_duplicates links a cross-source duplicate over the bridge")
    func findDuplicatesLinksACrossSourceDuplicateOverTheBridge() throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }

        let store = try Store.open(path: db.path, key: Self.key)
        // The bank account is created first, so its row is the survivor.
        let bankId = try store.insertAccount(account: Self.dedupBankAccount())
        let cardId = try store.insertAccount(account: Self.dedupCardAccount())

        // The same spend seen twice: once on the bank ledger, once on the card statement.
        _ = try store.insertTransaction(
            txn: Self.dedupLeg(bankId, "POS SWIGGY BANGALORE RRN1234"))
        _ = try store.insertTransaction(
            txn: Self.dedupLeg(cardId, "SWIGGY BANGALORE 1234567890123"))

        let summary = try store.findDuplicates()
        #expect(summary.duplicatesLinked == 1)
        #expect(summary.canonical == 1)
        #expect(summary.fuzzy == 0)

        let survivor = try #require(try store.listTransactions(accountId: bankId).first)
        let duplicate = try #require(try store.listTransactions(accountId: cardId).first)
        #expect(survivor.supersededBy == nil)
        #expect(survivor.dedupLayer == nil)
        #expect(duplicate.supersededBy == survivor.id)
        #expect(duplicate.dedupLayer == .canonical)
        // Linked, never deleted — the link is reversible and the UI decides what to hide.
        #expect(duplicate.isDeleted == false)
    }

    private static func cardAccount() -> NewAccount {
        NewAccount(
            name: "HDFC Card",
            bankCode: "HDFC",
            isCreditCard: true,
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
            amount: decimal(amount),
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

    private static func categoryTxn(_ accountId: String, _ description: String) -> NewTransaction {
        NewTransaction(
            accountId: accountId,
            date: "2026-07-04",
            descriptionRaw: description,
            amount: decimal("250.00"),
            direction: .debit,
            currency: "INR",
            sourceCategory: nil,
            categoryId: nil,
            categorisedBy: nil,
            statementId: nil,
            createdAt: "2026-08-08T00:00:00Z",
            updatedAt: "2026-08-08T00:00:00Z"
        )
    }

    /// A bank account created before the card account — account `createdAt` order is what
    /// decides which side of a duplicate survives.
    private static func dedupBankAccount() -> NewAccount {
        NewAccount(
            name: "HDFC Savings",
            bankCode: "HDFC",
            isCreditCard: false,
            currency: "INR",
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    private static func dedupCardAccount() -> NewAccount {
        NewAccount(
            name: "HDFC Card",
            bankCode: "HDFC",
            isCreditCard: true,
            currency: "INR",
            createdAt: "2026-02-01T00:00:00Z",
            updatedAt: "2026-02-01T00:00:00Z"
        )
    }

    private static func dedupLeg(_ accountId: String, _ description: String) -> NewTransaction {
        NewTransaction(
            accountId: accountId,
            date: "2026-07-04",
            descriptionRaw: description,
            amount: decimal("450.00"),
            direction: .debit,
            currency: "INR",
            sourceCategory: nil,
            categoryId: nil,
            categorisedBy: nil,
            statementId: nil,
            createdAt: "2026-08-08T00:00:00Z",
            updatedAt: "2026-08-08T00:00:00Z"
        )
    }

    /// Create the database and seed one account, releasing the `Store` on return so the
    /// Create the database and seed one account, releasing the `Store` on return so the
    /// file is no longer held open when the caller re-opens it.
    private static func seed(path: String) throws {
        let store = try Store.open(path: path, key: key)
        _ = try store.insertAccount(account: sampleAccount())
    }
}
