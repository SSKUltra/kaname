import Foundation
import Testing

@testable import Kaname

/// **U4** — the navigation value carries both questions the list can be asked, and tells them
/// apart.
///
/// The transaction list has exactly one destination. Which account, and whether to show only
/// the rows nobody has answered yet, are two axes of one screen — so they travel as one value.
/// If two scopes differing only in `uncategorizedOnly` compared equal or hashed alike, the
/// navigation stack would treat "all my transactions" and "the ones I have not filed" as the
/// same push: the back button would come back to the wrong screen, and a person tapping the
/// worklist would sometimes get the whole history instead.
@Suite("The value the transaction list is pushed with")
struct TransactionScopeTests {
    @Test("Two scopes differing only in the narrowing are not the same scope")
    func theNarrowingIsPartOfTheIdentity() {
        let everything = TransactionScope(filter: .all, uncategorizedOnly: false)
        let worklist = TransactionScope(filter: .all, uncategorizedOnly: true)

        #expect(everything != worklist)
        #expect(everything.hashValue != worklist.hashValue)
        #expect(Set([everything, worklist]).count == 2, "they collide in the nav stack")
    }

    @Test("Two scopes differing only in the account are not the same scope")
    func theAccountIsPartOfTheIdentity() {
        let all = TransactionScope(filter: .all, uncategorizedOnly: true)
        let one = TransactionScope(
            filter: .account(id: "account-1", name: "Everyday Savings", last4: "1123"),
            uncategorizedOnly: true
        )

        #expect(all != one)
        #expect(Set([all, one]).count == 2)
    }

    @Test("The same scope is the same scope — equal, and one entry in a set")
    func thesameScopeIsOneScope() {
        let filter = AccountFilter.account(id: "a", name: "Everyday Savings", last4: "1123")
        let first = TransactionScope(filter: filter, uncategorizedOnly: true)
        let second = TransactionScope(filter: filter, uncategorizedOnly: true)

        #expect(first == second)
        #expect(Set([first, second]).count == 1)
    }

    @Test("A scope survives a round trip through Codable, both axes intact")
    func aScopeRoundTripsThroughCodable() throws {
        let scopes = [
            TransactionScope(filter: .all, uncategorizedOnly: false),
            TransactionScope(filter: .all, uncategorizedOnly: true),
            TransactionScope(
                filter: .account(id: "a", name: "Everyday Savings", last4: "1123"),
                uncategorizedOnly: true
            ),
            TransactionScope(
                filter: .account(id: "b", name: "Travel Card", last4: nil),
                uncategorizedOnly: false
            ),
        ]

        for scope in scopes {
            let data = try JSONEncoder().encode(scope)
            let decoded = try JSONDecoder().decode(TransactionScope.self, from: data)
            #expect(decoded == scope)
        }
    }
}
