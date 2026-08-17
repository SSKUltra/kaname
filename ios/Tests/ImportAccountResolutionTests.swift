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
    @Test("A statement whose last-4 matches one account attaches to it")
    func attachesByIssuerAndLast4() async throws {
        let db = ImportAccountFixture.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: ImportAccountFixture.key)
        let existing = try store.insertAccount(
            account: ImportAccountFixture.account("Everyday card", bankCode: "ICICI", isCreditCard: true, last4: "1002")
        )
        // A second card for the same issuer, so "the only account" cannot be the reason.
        _ = try store.insertAccount(
            account: ImportAccountFixture.account("Other card", bankCode: "ICICI", isCreditCard: true, last4: "9999")
        )

        let result = try await ImportAccountFixture.service(lines: ImportAccountFixture.cardWithLast4, store: store)
            .run(url: ImportAccountFixture.anyURL, password: nil) { _ in }

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
        let db = ImportAccountFixture.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: ImportAccountFixture.key)

        let result = try await ImportAccountFixture.service(lines: ImportAccountFixture.cardWithLast4, store: store)
            .run(url: ImportAccountFixture.anyURL, password: nil) { _ in }

        guard case .finished(let summary) = result else {
            Issue.record("expected the import to finish without asking")
            return
        }
        #expect(summary.accountIsNew)
        #expect(try store.listAccounts().count == 1)
    }

    @Test("A statement with no last-4 attaches when the person has exactly one such account")
    func attachesToTheSoleAccountWhenNoLast4() async throws {
        let db = ImportAccountFixture.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: ImportAccountFixture.key)
        let existing = try store.insertAccount(
            account: ImportAccountFixture.account("Everyday", bankCode: "HDFC", isCreditCard: false, last4: "3425")
        )

        let result = try await ImportAccountFixture.service(
            lines: ImportAccountFixture.ledgerWithoutLast4, store: store
        )
        .run(url: ImportAccountFixture.anyURL, password: nil) { _ in }

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
        let db = ImportAccountFixture.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: ImportAccountFixture.key)

        let result = try await ImportAccountFixture.service(
            lines: ImportAccountFixture.ledgerWithoutLast4, store: store
        )
        .run(url: ImportAccountFixture.anyURL, password: nil) { _ in }

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
        let db = ImportAccountFixture.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: ImportAccountFixture.key)
        _ = try store.insertAccount(
            account: ImportAccountFixture.account("Everyday", bankCode: "HDFC", isCreditCard: false, last4: "3425")
        )
        _ = try store.insertAccount(
            account: ImportAccountFixture.account("Savings", bankCode: "HDFC", isCreditCard: false, last4: "8899")
        )

        let result = try await ImportAccountFixture.service(
            lines: ImportAccountFixture.ledgerWithoutLast4, store: store
        )
        .run(url: ImportAccountFixture.anyURL, password: nil) { _ in }

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
        let db = ImportAccountFixture.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: ImportAccountFixture.key)
        _ = try store.insertAccount(
            account: ImportAccountFixture.account("Everyday", bankCode: "HDFC", isCreditCard: false, last4: "3425")
        )
        let chosen = try store.insertAccount(
            account: ImportAccountFixture.account("Savings", bankCode: "HDFC", isCreditCard: false, last4: "8899")
        )

        let service = ImportAccountFixture.service(lines: ImportAccountFixture.ledgerWithoutLast4, store: store)
        _ = try await service.run(url: ImportAccountFixture.anyURL, password: nil) { _ in }
        let summary = try await service.resolveAccount(.existing(id: chosen))

        #expect(!summary.accountIsNew)
        #expect(summary.transactionsAdded == 2)
        #expect(try store.listTransactions(accountId: chosen).count == 2)
    }

    @Test("The account the person names is created, with their name on it")
    func createsTheAccountThePersonNames() async throws {
        let db = ImportAccountFixture.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: ImportAccountFixture.key)

        let service = ImportAccountFixture.service(lines: ImportAccountFixture.ledgerWithoutLast4, store: store)
        _ = try await service.run(url: ImportAccountFixture.anyURL, password: nil) { _ in }
        let summary = try await service.resolveAccount(.new(name: "Rainy day", last4: nil))

        #expect(summary.accountIsNew)
        let account = try #require(try store.listAccounts().first)
        #expect(account.name == "Rainy day")
        #expect(try store.listTransactions(accountId: account.id).count == 2)
    }

    @Test("An account that never learned its last-4 learns it from the statement that has one")
    func learnsALast4FromALaterStatement() async throws {
        let db = ImportAccountFixture.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: ImportAccountFixture.key)
        let existing = try store.insertAccount(
            account: ImportAccountFixture.account("My card", bankCode: "ICICI", isCreditCard: true, last4: nil)
        )

        let result = try await ImportAccountFixture.service(lines: ImportAccountFixture.cardWithLast4, store: store)
            .run(url: ImportAccountFixture.anyURL, password: nil) { _ in }

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
        let db = ImportAccountFixture.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: ImportAccountFixture.key)

        _ = try await ImportAccountFixture.service(lines: ImportAccountFixture.cardWithLast4, store: store)
            .run(url: ImportAccountFixture.anyURL, password: nil) { _ in }
        let again = try await ImportAccountFixture.service(lines: ImportAccountFixture.cardWithLast4, store: store)
            .run(url: ImportAccountFixture.anyURL, password: nil) { _ in }

        guard case .finished(let summary) = again else {
            Issue.record("a re-import is never refused")
            return
        }
        #expect(summary.rowsAlreadyHeld == 1)

        let account = try #require(try store.listAccounts().first)
        let stored = try store.listTransactions(accountId: account.id)
        // Nothing was deleted or replaced — the repeat is linked, and only one row counts.
        #expect(stored.count == 2)
        #expect(stored.filter { $0.supersededBy == nil }.count == 1)
    }

    @Test("The front door counts what a person has, not what was written to reach it")
    func reimportDoesNotInflateTheAccountsList() async throws {
        let db = ImportAccountFixture.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: ImportAccountFixture.key)

        let service = ImportAccountFixture.service(lines: ImportAccountFixture.cardWithLast4, store: store)
        _ = try await service.run(url: ImportAccountFixture.anyURL, password: nil) { _ in }
        let afterFirst = try #require(try await service.importedAccounts().first)
        #expect(afterFirst.transactionCount == 1)

        _ = try await ImportAccountFixture.service(lines: ImportAccountFixture.cardWithLast4, store: store)
            .run(url: ImportAccountFixture.anyURL, password: nil) { _ in }

        // The superseded repeat is still in the database, on purpose. It is not history.
        let afterSecond = try #require(try await service.importedAccounts().first)
        #expect(afterSecond.transactionCount == 1)
    }
}
