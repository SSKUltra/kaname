import Foundation
import KanameCore
import Testing

@testable import Kaname

/// Which account does an imported statement belong to?
///
/// The whole FR-024 matrix. The rule the tests exist to hold: Kaname attaches a statement
/// only when there is exactly one answer, and asks the person otherwise. It never picks
/// between two of somebody's accounts on their behalf.
///
/// All statement text is 100% synthetic.
@Suite("Import account resolution")
struct ImportAccountResolutionTests {
    private static let key = "abcd1234ef567890abcd1234ef567890abcd1234ef567890abcd1234ef567890"
    private static let anyURL = URL(fileURLWithPath: "/dev/null/statement.pdf")

    private struct StubExtractor: StatementTextExtractor {
        let text: ExtractedText

        func extract(from url: URL, password: String?) throws -> ExtractedText { text }
    }

    private static func tempDatabase() -> (dir: URL, path: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-accounts-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("kaname.db").path)
    }

    private static func service(lines: [String], store: Store) -> ImportService {
        ImportService(
            extractor: StubExtractor(
                text: ExtractedText(
                    lines: lines,
                    fullText: lines.joined(separator: "\n"),
                    lineWords: []
                )
            ),
            store: store,
            now: { Date(timeIntervalSince1970: 1_786_000_000) }
        )
    }

    /// A card statement that names its last-4.
    private static let cardWithLast4 = [
        "ICICI Bank Statement",
        "Statement Date May 28, 2026",
        "4315XXXXXXXX1002",
        "26/05/2026 1814 Fee on gaming transaction 0 10.20",
    ]

    /// A ledger that never names an account number — the FR-024 case. Its reference column
    /// deliberately carries no long digit run either, or the reader would recover a last-4
    /// from that instead.
    private static let ledgerWithoutLast4 = [
        "HDFC BANK LIMITED",
        "Statementof account",
        "From : 01/04/2026 To : 30/04/2026",
        "Date Narration Chq./Ref.No. ValueDt WithdrawalAmt. DepositAmt. ClosingBalance",
        "01/04/26 UPI-EXAMPLEMERCHANT REFALPHA 01/04/26 5,000.00 95,000.00",
        "16/04/26 NEFTCR-EXAMPLEEMPLOYER REFBETA 16/04/26 50,000.00 1,45,000.00",
        "OpeningBalance DrCount CrCount Debits Credits ClosingBal",
        "1,00,000.00 1 1 5,000.00 50,000.00 1,45,000.00",
    ]

    private static func account(
        _ name: String,
        bankCode: String,
        isCreditCard: Bool,
        last4: String?
    ) -> NewAccount {
        NewAccount(
            name: name,
            bankCode: bankCode,
            isCreditCard: isCreditCard,
            last4: last4,
            currency: "INR",
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    @Test("A statement whose last-4 matches one account attaches to it")
    func attachesByIssuerAndLast4() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)
        let existing = try store.insertAccount(
            account: Self.account("Everyday card", bankCode: "ICICI", isCreditCard: true, last4: "1002")
        )
        // A second card for the same issuer, so "the only account" cannot be the reason.
        _ = try store.insertAccount(
            account: Self.account("Other card", bankCode: "ICICI", isCreditCard: true, last4: "9999")
        )

        let result = try await Self.service(lines: Self.cardWithLast4, store: store)
            .run(url: Self.anyURL, password: nil) { _ in }

        guard case .finished(let summary) = result else {
            Issue.record("expected the import to finish without asking")
            return
        }
        #expect(!summary.accountIsNew)
        #expect(try store.listTransactions(accountId: existing).count == 1)
        #expect(try store.listAccounts().count == 2)
    }

    @Test("A statement for an issuer with no accounts creates one and says so")
    func createsAnAccountWhenThereIsNone() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        let result = try await Self.service(lines: Self.cardWithLast4, store: store)
            .run(url: Self.anyURL, password: nil) { _ in }

        guard case .finished(let summary) = result else {
            Issue.record("expected the import to finish without asking")
            return
        }
        #expect(summary.accountIsNew)
        #expect(try store.listAccounts().count == 1)
    }

    @Test("A statement with no last-4 attaches when the person has exactly one such account")
    func attachesToTheSoleAccountWhenNoLast4() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)
        let existing = try store.insertAccount(
            account: Self.account("Everyday", bankCode: "HDFC", isCreditCard: false, last4: "3425")
        )

        let result = try await Self.service(lines: Self.ledgerWithoutLast4, store: store)
            .run(url: Self.anyURL, password: nil) { _ in }

        guard case .finished(let summary) = result else {
            Issue.record("expected the import to finish without asking")
            return
        }
        #expect(!summary.accountIsNew)
        #expect(try store.listAccounts().count == 1)
        #expect(try store.listTransactions(accountId: existing).count == 2)
    }

    @Test("A statement with no last-4 and no account asks rather than inventing one")
    func asksWhenThereIsNoAccountAndNoLast4() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        let result = try await Self.service(lines: Self.ledgerWithoutLast4, store: store)
            .run(url: Self.anyURL, password: nil) { _ in }

        guard case .needsAccount(let choice) = result else {
            Issue.record("expected to be asked which account this is")
            return
        }
        #expect(choice.candidates.isEmpty)
        #expect(choice.last4 == nil)
        // Asking costs nothing until it is answered.
        #expect(try store.listAccounts().isEmpty)
    }

    @Test("A statement with no last-4 and two possible accounts asks, and never guesses")
    func asksWhenMoreThanOneAccountCouldBeRight() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)
        _ = try store.insertAccount(
            account: Self.account("Everyday", bankCode: "HDFC", isCreditCard: false, last4: "3425")
        )
        _ = try store.insertAccount(
            account: Self.account("Savings", bankCode: "HDFC", isCreditCard: false, last4: "8899")
        )

        let result = try await Self.service(lines: Self.ledgerWithoutLast4, store: store)
            .run(url: Self.anyURL, password: nil) { _ in }

        guard case .needsAccount(let choice) = result else {
            Issue.record("expected to be asked which account this is")
            return
        }
        #expect(choice.candidates.count == 2)
        // Nothing was written while the question stands.
        for account in try store.listAccounts() {
            #expect(try store.listTransactions(accountId: account.id).isEmpty)
        }
    }

    @Test("The account the person picks is the one the statement lands in")
    func honoursTheAccountThePersonPicks() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)
        _ = try store.insertAccount(
            account: Self.account("Everyday", bankCode: "HDFC", isCreditCard: false, last4: "3425")
        )
        let chosen = try store.insertAccount(
            account: Self.account("Savings", bankCode: "HDFC", isCreditCard: false, last4: "8899")
        )

        let service = Self.service(lines: Self.ledgerWithoutLast4, store: store)
        _ = try await service.run(url: Self.anyURL, password: nil) { _ in }
        let summary = try await service.resolveAccount(.existing(id: chosen))

        #expect(!summary.accountIsNew)
        #expect(summary.transactionsImported == 2)
        #expect(try store.listTransactions(accountId: chosen).count == 2)
    }

    @Test("The account the person names is created, with their name on it")
    func createsTheAccountThePersonNames() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        let service = Self.service(lines: Self.ledgerWithoutLast4, store: store)
        _ = try await service.run(url: Self.anyURL, password: nil) { _ in }
        let summary = try await service.resolveAccount(.new(name: "Rainy day"))

        #expect(summary.accountIsNew)
        let account = try #require(try store.listAccounts().first)
        #expect(account.name == "Rainy day")
        #expect(try store.listTransactions(accountId: account.id).count == 2)
    }

    @Test("An account that never learned its last-4 learns it from the statement that has one")
    func learnsALast4FromALaterStatement() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)
        let existing = try store.insertAccount(
            account: Self.account("My card", bankCode: "ICICI", isCreditCard: true, last4: nil)
        )

        let result = try await Self.service(lines: Self.cardWithLast4, store: store)
            .run(url: Self.anyURL, password: nil) { _ in }

        guard case .finished(let summary) = result else {
            Issue.record("expected the import to finish without asking")
            return
        }
        #expect(!summary.accountIsNew)
        let account = try #require(try store.listAccounts().first { $0.id == existing })
        #expect(account.last4 == "1002")
    }

    @Test("Re-importing the same statement does not double the person's history")
    func reimportingDoesNotDoubleHistory() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        _ = try await Self.service(lines: Self.cardWithLast4, store: store)
            .run(url: Self.anyURL, password: nil) { _ in }
        let again = try await Self.service(lines: Self.cardWithLast4, store: store)
            .run(url: Self.anyURL, password: nil) { _ in }

        guard case .finished(let summary) = again else {
            Issue.record("a re-import is never refused")
            return
        }
        #expect(summary.duplicatesSkipped == 1)

        let account = try #require(try store.listAccounts().first)
        let stored = try store.listTransactions(accountId: account.id)
        // Nothing was deleted or replaced — the repeat is linked, and only one row counts.
        #expect(stored.count == 2)
        #expect(stored.filter { $0.supersededBy == nil }.count == 1)
    }
}
