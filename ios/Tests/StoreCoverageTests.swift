import Foundation
import KanameCore
import Testing

/// "store coverage over the bridge" — proves statements persist as a first-class entity and the
/// rolling 24-month coverage map is computed from those stored facts, with `today` supplied by the
/// platform (the core never reads the wall-clock). All data is synthetic.
@Suite("Store coverage over the bridge")
struct StoreCoverageTests {
    /// A synthetic 256-bit key (64 hex chars).
    private static let key = "2f1c8a9e4b7d6035112233445566778899aabbccddeeff00112233445566aabb"

    private static func tempDatabase() -> (dir: URL, path: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-coverage-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("kaname.db").path)
    }

    private static func account() -> NewAccount {
        NewAccount(
            name: "HDFC Savings",
            bankCode: "HDFC",
            isCreditCard: false,
            last4: nil,
            currency: "INR",
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    private static func liveAlertTxn(_ accountId: String, _ date: String) -> NewTransaction {
        NewTransaction(
            accountId: accountId,
            date: date,
            descriptionRaw: "POS BLUE TOKAI",
            amount: Decimal(string: "250.00", locale: Locale(identifier: "en_US_POSIX")) ?? 0,
            direction: .debit,
            currency: "INR",
            sourceCategory: nil,
            categoryId: nil,
            categorisedBy: nil,
            statementId: nil,
            createdAt: "2026-08-12T00:00:00Z",
            updatedAt: "2026-08-12T00:00:00Z"
        )
    }

    @Test("A statement round-trips and its month reports as covered over the bridge")
    func coverageClassifiesMonthsOverTheBridge() throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }

        let store = try Store.open(path: db.path, key: Self.key)
        let accountId = try store.insertAccount(account: Self.account())

        // July is covered by a full statement whose run needed review; June has only a
        // piecemeal live-alert row, so it stays partial.
        let statementId = try store.insertStatement(
            statement: NewStatement(
                accountId: accountId,
                bankCode: "HDFC",
                periodStart: "2026-07-01",
                periodEnd: "2026-07-31",
                needsReview: true,
                source: .statement,
                createdAt: "2026-08-12T00:00:00Z"
            )
        )
        _ = try store.insertTransaction(txn: Self.liveAlertTxn(accountId, "2026-06-14"))

        let statements = try store.listStatements(accountId: accountId)
        #expect(statements.count == 1)
        let stored = try #require(statements.first)
        #expect(stored.id == statementId)
        #expect(stored.periodStart == "2026-07-01")
        #expect(stored.periodEnd == "2026-07-31")
        #expect(stored.source == .statement)
        #expect(stored.needsReview)

        // `today` is an explicit input — the core never reads the wall-clock.
        let months = try store.coverage(accountId: accountId, today: "2026-08-12")
        #expect(months.count == 24)
        #expect(months.last?.month == "2026-08")

        let july = try #require(months.first { $0.month == "2026-07" })
        #expect(july.state == .covered)
        #expect(july.needsReview)

        let june = try #require(months.first { $0.month == "2026-06" })
        #expect(june.state == .partial)
        #expect(!june.needsReview)

        let may = try #require(months.first { $0.month == "2026-05" })
        #expect(may.state == .gap)
    }
}
