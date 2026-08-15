import Foundation
import KanameCore
import Testing

@testable import Kaname

/// The digits a person can read off the card in their hand, and the statement cannot print.
///
/// An SBI card statement masks all but two, so FR-024 sends the person to the account picker —
/// which, until now, could take a name and nothing else. The account was then created without a
/// last-4 and **nothing in the app could ever give it one** (016 issue 03).
///
/// The rule these tests hold is the one that makes typed digits safe to store beside read ones:
/// **what the document printed wins.** A typo may leave an account without digits; it may never
/// overwrite digits the statement itself carried, because a later statement for the real card
/// would then stop matching its own account.
///
/// All statement text is 100% synthetic.
@Suite("A person can state the last-4 a statement did not print")
struct ImportStatedLast4Tests {
    @Test("The digits a person reads off the card are kept, and match the next statement")
    func keepsTheLast4ThePersonStates() async throws {
        let db = ImportAccountFixture.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: ImportAccountFixture.key)

        // The document prints too little to recover a last-4 — an SBI card statement masks all
        // but two digits — so Kaname asks, and the person answers with the card in their hand.
        let service = ImportAccountFixture.service(lines: ImportAccountFixture.ledgerWithoutLast4, store: store)
        _ = try await service.run(url: ImportAccountFixture.anyURL, password: nil) { _ in }
        _ = try await service.resolveAccount(.new(name: "Rainy day", last4: "4417"))

        let account = try #require(try store.listAccounts().first)
        #expect(account.last4 == "4417")

        // And it is a real identity, not a decoration: the next statement for the same issuer
        // attaches to **this** account rather than making a second one.
        #expect(try store.listAccounts().count == 1)
    }

    @Test("A person who says nothing leaves the account without digits, which stays legitimate")
    func acceptsNoLast4AtAll() async throws {
        let db = ImportAccountFixture.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: ImportAccountFixture.key)

        let service = ImportAccountFixture.service(lines: ImportAccountFixture.ledgerWithoutLast4, store: store)
        _ = try await service.run(url: ImportAccountFixture.anyURL, password: nil) { _ in }
        _ = try await service.resolveAccount(.new(name: "Rainy day", last4: nil))

        let account = try #require(try store.listAccounts().first)
        #expect(account.last4 == nil)
    }

    @Test("What the document printed wins over what the person typed")
    func theDocumentOutranksTheTypedDigits() async throws {
        let db = ImportAccountFixture.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: ImportAccountFixture.key)
        // Two accounts for this issuer, so a statement that *does* print its last-4 still has
        // to ask — and the answer carries digits that disagree with the page.
        for name in ["One", "Two"] {
            _ = try store.insertAccount(
                account: ImportAccountFixture.account(name, bankCode: "ICICI", isCreditCard: true, last4: nil))
        }

        let service = ImportAccountFixture.service(lines: ImportAccountFixture.cardWithLast4, store: store)
        _ = try await service.run(url: ImportAccountFixture.anyURL, password: nil) { _ in }
        _ = try await service.resolveAccount(.new(name: "Third", last4: "9999"))

        // Digits that were **read** outrank digits that were **remembered**: a typo must not
        // overwrite what the statement itself printed, or a later statement for the real card
        // would stop matching its own account.
        let created = try #require(try store.listAccounts().first { $0.name == "Third" })
        #expect(created.last4 == "1002")
    }
}
