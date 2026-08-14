import Foundation
import KanameCore

/// The platform half of the correctness corpus (`specs/018-transaction-list/data-model.md` §7).
///
/// The engine suites build theirs in `core/crates/kaname-core/tests/common/mod.rs`; this is the
/// same fixture contract expressed through the bridge, so a Swift assertion about the combined
/// history is made against a store that actually holds the shapes the history has to survive:
/// more than one account, more than one currency, a date shared by three accounts with three
/// different amounts, an account with no rows at all, an account whose every row is superseded,
/// an empty description, a very long one, and an amount with seven integer digits.
///
/// Every value is **synthetic**. No real merchant, no real account identifier, no fragment of a
/// real statement enters this repository (FR-064).
///
/// ⚠️ **One shape the platform cannot build: a deleted row.** `is_deleted` has no write path in
/// the store's API — the Rust corpus reaches it with direct SQL through SQLCipher, which Swift
/// has no handle on. The `!isDeleted` half of the live rule is therefore pinned engine-side
/// (`core/crates/kaname-core/tests/history_live.rs`, L1–L5, and the `LIVE` byte-identity
/// assertion). What Swift can prove — and does, in `LivenessParityTests` — is the superseded
/// half, end to end.
enum TransactionCorpus {
    /// A synthetic 256-bit key (64 hex chars). Test-only; never a real device key.
    static let key = "2f1c8a9e4b7d6035112233445566778899aabbccddeeff00112233445566aabb"

    /// The date three accounts share, each with a different amount — the account tie-break's
    /// only honest test (FR-030).
    static let sharedDate = "2026-07-15"

    // MARK: - Accounts, in the order `listAccounts()` returns them

    static let everyday = "Everyday Savings"
    static let travelCard = "Travel Card"
    static let overseas = "Overseas Savings"
    static let dormantCard = "Dormant Card"
    static let echoCard = "Echo Card"

    /// One expected row of the combined history, in the order the engine must return it.
    struct Expected: Equatable, Sendable {
        let date: String
        let accountName: String
        let descriptionRaw: String
        let amount: String
        let direction: Direction
        let currency: String
        let last4: String
    }

    /// A fresh temp database path; the caller removes the directory when done.
    static func temporaryDatabase() -> (dir: URL, path: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-history-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("kaname.db").path)
    }

    static func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// Seed `store` with the corpus and link its cross-source duplicates, exactly as an import
    /// would. Returns the account ids in `listAccounts()` order.
    @discardableResult
    static func seed(_ store: Store) throws -> [String: String] {
        var ids: [String: String] = [:]
        for account in accounts {
            let id = try store.insertAccount(account: account.newAccount)
            ids[account.name] = id
            for row in account.rows {
                _ = try store.insertTransaction(txn: row.newTransaction(accountId: id))
            }
        }
        // The echo card carries two of the ledger's rows verbatim. Opposite kinds, so 013's
        // cross-source matcher compares them; the ledger has the earlier `accounts.rowid`, so
        // the ledger's rows survive and every one of the card's is superseded.
        _ = try store.findDuplicates()
        return ids
    }

    /// The whole combined history, in the order `historyPage` must produce it: date descending,
    /// then the account's position in `listAccounts()`, then insertion order within an account.
    static let expectedLiveRows: [Expected] = [
        Expected(
            date: "2026-07-15", accountName: everyday, descriptionRaw: "SYNTHETIC GROCERY 01",
            amount: "1111.11", direction: .debit, currency: "INR", last4: "1123"),
        Expected(
            date: "2026-07-15", accountName: travelCard, descriptionRaw: "SYNTHETIC FLIGHT 05",
            amount: "4444.44", direction: .debit, currency: "INR", last4: "8890"),
        Expected(
            date: "2026-07-15", accountName: overseas, descriptionRaw: "SYNTHETIC OVERSEAS 07",
            amount: "66.660", direction: .debit, currency: "KWD", last4: "4417"),
        Expected(
            date: "2026-07-14", accountName: everyday, descriptionRaw: "SYNTHETIC SALARY 02",
            amount: "1234567.89", direction: .credit, currency: "INR", last4: "1123"),
        Expected(
            date: "2026-07-10", accountName: travelCard, descriptionRaw: "SYNTHETIC HOTEL 06",
            amount: "555.55", direction: .debit, currency: "INR", last4: "8890"),
        Expected(
            date: "2026-07-08", accountName: overseas, descriptionRaw: "SYNTHETIC OVERSEAS 08",
            amount: "77.770", direction: .credit, currency: "KWD", last4: "4417"),
        Expected(
            date: "2026-07-06", accountName: everyday, descriptionRaw: "",
            amount: "22.22", direction: .debit, currency: "INR", last4: "1123"),
        Expected(
            date: "2026-07-02", accountName: everyday, descriptionRaw: longDescription,
            amount: "33.33", direction: .debit, currency: "INR", last4: "1123"),
    ]

    /// Live rows per account, keyed by name — what `accountSummaries()` must report.
    static let expectedLiveCounts: [String: UInt32] = [
        everyday: 4, travelCard: 2, overseas: 2, dormantCard: 0, echoCard: 0,
    ]

    /// A description long enough that a row has to wrap or truncate it rather than lay it out.
    static let longDescription =
        "SYNTHETIC MERCHANT WITH AN EXCEPTIONALLY LONG PRINTED DESCRIPTION LINE THAT NO ROW "
        + "CAN LAY OUT ON ONE LINE AT ANY TEXT SIZE 09"

    // MARK: - The fixture itself

    struct Account {
        let name: String
        let isCreditCard: Bool
        let currency: String
        let last4: String
        let rows: [Row]

        var newAccount: NewAccount {
            NewAccount(
                name: name,
                bankCode: "SYNTHETIC",
                isCreditCard: isCreditCard,
                last4: last4,
                currency: currency,
                createdAt: "2026-08-01T00:00:00Z",
                updatedAt: "2026-08-01T00:00:00Z"
            )
        }
    }

    struct Row {
        let date: String
        let descriptionRaw: String
        let amount: String
        let direction: Direction
        let currency: String

        func newTransaction(accountId: String) -> NewTransaction {
            NewTransaction(
                accountId: accountId,
                date: date,
                descriptionRaw: descriptionRaw,
                amount: TransactionCorpus.decimal(amount),
                direction: direction,
                currency: currency,
                sourceCategory: nil,
                categoryId: nil,
                categorisedBy: nil,
                statementId: nil,
                createdAt: "2026-08-01T00:00:00Z",
                updatedAt: "2026-08-01T00:00:00Z"
            )
        }
    }

    static let accounts: [Account] = [
        Account(
            name: everyday, isCreditCard: false, currency: "INR", last4: "1123",
            rows: [
                Row(
                    date: "2026-07-15", descriptionRaw: "SYNTHETIC GROCERY 01", amount: "1111.11",
                    direction: .debit, currency: "INR"),
                Row(
                    date: "2026-07-14", descriptionRaw: "SYNTHETIC SALARY 02", amount: "1234567.89",
                    direction: .credit, currency: "INR"),
                // An empty description still has to render a complete row (FR-020).
                Row(date: "2026-07-06", descriptionRaw: "", amount: "22.22", direction: .debit, currency: "INR"),
                Row(
                    date: "2026-07-02", descriptionRaw: longDescription, amount: "33.33",
                    direction: .debit, currency: "INR"),
            ]),
        Account(
            name: travelCard, isCreditCard: true, currency: "INR", last4: "8890",
            rows: [
                Row(
                    date: "2026-07-15", descriptionRaw: "SYNTHETIC FLIGHT 05", amount: "4444.44",
                    direction: .debit, currency: "INR"),
                Row(
                    date: "2026-07-10", descriptionRaw: "SYNTHETIC HOTEL 06", amount: "555.55",
                    direction: .debit, currency: "INR"),
            ]),
        // A second currency, and one `en_IN` renders as a code rather than a symbol (FR-027).
        Account(
            name: overseas, isCreditCard: false, currency: "KWD", last4: "4417",
            rows: [
                Row(
                    date: "2026-07-15", descriptionRaw: "SYNTHETIC OVERSEAS 07", amount: "66.660",
                    direction: .debit, currency: "KWD"),
                Row(
                    date: "2026-07-08", descriptionRaw: "SYNTHETIC OVERSEAS 08", amount: "77.770",
                    direction: .credit, currency: "KWD"),
            ]),
        // An account whose statement parsed no rows at all — empty state 4.
        Account(name: dormantCard, isCreditCard: true, currency: "INR", last4: "3350", rows: []),
        // Nothing but rows the ledger already had, so every one of its rows is superseded and
        // none is live — empty state 5.
        Account(
            name: echoCard, isCreditCard: true, currency: "INR", last4: "6612",
            rows: [
                Row(
                    date: "2026-07-15", descriptionRaw: "SYNTHETIC GROCERY 01", amount: "1111.11",
                    direction: .debit, currency: "INR"),
                Row(
                    date: "2026-07-14", descriptionRaw: "SYNTHETIC SALARY 02", amount: "1234567.89",
                    direction: .credit, currency: "INR"),
            ]),
    ]
}
