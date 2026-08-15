import CryptoKit
import Foundation
import KanameCore
import Testing

@testable import Kaname

// The real-store fixture the filter and refresh suites read through, and the two helpers that
// drive a view model the way a scrolling person does. Separate from the suites because a
// fixture that lives in one suite's file is a fixture the next suite copies.

/// A synthetic 256-bit key (64 hex chars). Test-only; never a real device key.
let filterKey = "0099aabbccddeeff11223344556677889900aabbccddeeff1122334455667788"
let filterNow = Date(timeIntervalSince1970: 1_784_000_000)  // 2026-07-16

/// Three accounts with rows on shared and unshared dates, written straight to a real store.
struct FilterFixture {
    let directory: URL
    let store: Store
    let accountIDs: [String]

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-filter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try Store.open(
            path: directory.appendingPathComponent("kaname.db").path, key: filterKey)

        var ids: [String] = []
        for account in Self.accounts {
            let id = try store.insertAccount(
                account: NewAccount(
                    name: account.name,
                    bankCode: "SYNTHETIC",
                    isCreditCard: false,
                    last4: account.last4,
                    currency: "INR",
                    createdAt: "2026-08-01T00:00:00Z",
                    updatedAt: "2026-08-01T00:00:00Z"
                ))
            ids.append(id)
            for (index, date) in account.dates.enumerated() {
                _ = try store.insertTransaction(
                    txn: NewTransaction(
                        accountId: id,
                        date: date,
                        descriptionRaw: "SYNTHETIC \(account.name.uppercased()) \(index)",
                        amount: TransactionCorpus.decimal("100.0\(index)"),
                        direction: .debit,
                        currency: "INR",
                        sourceCategory: nil,
                        categoryId: nil,
                        categorisedBy: nil,
                        statementId: nil,
                        createdAt: "2026-08-01T00:00:00Z",
                        updatedAt: "2026-08-01T00:00:00Z"
                    ))
            }
        }
        accountIDs = ids
    }

    /// Dates deliberately overlap between accounts, so a filtered read has to be a different
    /// *query* rather than a different slice of the same rows.
    struct Seed {
        let name: String
        let last4: String?
        let dates: [String]
    }

    private static let accounts: [Seed] = [
        Seed(name: "Everyday Savings", last4: "1123", dates: ["2026-07-15", "2026-07-14", "2026-07-02"]),
        Seed(name: "Travel Card", last4: "8890", dates: ["2026-07-15", "2026-07-10"]),
        // No last-4: the scope has to name this account without one (FR-003).
        Seed(name: "Cash Wallet", last4: nil, dates: ["2026-07-15", "2026-06-01"]),
    ]

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    func model(pageSize: UInt32 = 2) async -> TransactionListViewModel {
        await TransactionListViewModel(
            history: TransactionHistoryService(store: store),
            clock: { filterNow },
            pageSize: pageSize
        )
    }

    func filter(_ index: Int) throws -> AccountFilter {
        let account = try store.listAccounts()[index]
        return .account(id: account.id, name: account.name, last4: account.last4)
    }

    /// One more transaction in an account, which is all an import is from the list's point of
    /// view: rows that were not there when the screen was drawn.
    func addRow(to index: Int, date: String, index rowIndex: Int) throws {
        let account = try store.listAccounts()[index]
        _ = try store.insertTransaction(
            txn: NewTransaction(
                accountId: account.id,
                date: date,
                descriptionRaw: "SYNTHETIC IMPORTED \(rowIndex)",
                amount: TransactionCorpus.decimal("2\(rowIndex).00"),
                direction: .debit,
                currency: "INR",
                sourceCategory: nil,
                categoryId: nil,
                categorisedBy: nil,
                statementId: nil,
                createdAt: "2026-08-02T00:00:00Z",
                updatedAt: "2026-08-02T00:00:00Z"
            ))
    }

    /// A digest over every file the store owns, so a write to a journal counts as a write.
    func digest() -> String {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .sorted()
        var hasher = SHA256()
        for name in names {
            hasher.update(data: Data(name.utf8))
            hasher.update(data: (try? Data(contentsOf: directory.appendingPathComponent(name))) ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

func drain(_ model: TransactionListViewModel) async {
    for _ in 0..<100 {
        let rows = await model.groups.flatMap(\.rows)
        guard let last = rows.last else { return }
        await model.loadMoreIfNeeded(currentRowID: last.id)
        if await model.groups.flatMap(\.rows).count == rows.count { return }
    }
}

func rowIDs(_ model: TransactionListViewModel) async -> [String] {
    await model.groups.flatMap(\.rows).map(\.id)
}
