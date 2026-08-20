import Foundation
import KanameCore
import Testing

@testable import Kaname

/// **U2**, the second half — the two rows 020's narrowing added to `data-model.md` §6, and the
/// two it deliberately did **not** add.
///
/// A separate suite from `TransactionEmptyStateTests` for the reason the doubles are a separate
/// file: split by subject rather than by size. That one is about 018's six sentences for an
/// absence; this one is about the one sentence that is a **finish**, and about the rows where
/// "you are finished" would be a lie — an empty store, and an account that has no rows to have
/// answered.
///
/// ⚠️ Several of the situations below **cannot be reached by a seed**, and that is exactly why
/// they are here: a state only a unit test can construct is still a state, and FR-042a asks for
/// every reachable combination to be covered and every unreachable one to be named.
@Suite("A worklist worked to zero says so")
struct TransactionWorklistEmptyStateTests {
    private static func summary(
        id: String = "account-1",
        name: String = "Everyday Savings",
        last4: String? = "1123",
        count: UInt32,
        onlyExcluded: Bool = false
    ) -> AccountSummary {
        AccountSummary(
            id: id,
            name: name,
            last4: last4,
            isCreditCard: false,
            currency: "INR",
            liveTransactionCount: count,
            hasOnlyExcludedRows: onlyExcluded
        )
    }

    private static func filter(
        _ id: String = "account-1",
        name: String = "Everyday Savings",
        last4: String? = "1123"
    ) -> AccountFilter {
        .account(id: id, name: name, last4: last4)
    }

    // MARK: - The two rows the narrowing added (data-model.md §6)
    @Test("Narrowed across every account, with rows that are all answered, is a finish")
    func everythingIsAnswered() {
        let summaries = [
            Self.summary(count: 4),
            Self.summary(id: "account-2", name: "Travel Card", count: 9),
        ]

        // The rows are all there — this is not an absence of transactions, and none of 018's
        // six sentences is true about it (FR-042b).
        #expect(
            EmptyKind.decide(summaries: summaries, filter: .all, uncategorizedOnly: true)
                == .allAnswered)

        let empty = TransactionListStrings.emptyState(for: .allAnswered)
        #expect(empty.action == nil)
        #expect(!empty.title.lowercased().contains("nothing to show"))
        #expect(!empty.message.lowercased().contains("didn't have any transactions"))
    }

    @Test("Narrowed to one account whose rows are all answered names that account")
    func oneAccountIsAnswered() {
        let summaries = [
            Self.summary(count: 4),
            Self.summary(id: "account-2", name: "Travel Card", count: 9),
        ]

        let kind = EmptyKind.decide(
            summaries: summaries, filter: Self.filter(), uncategorizedOnly: true)
        #expect(kind == .accountAnswered(name: "Everyday Savings"))

        // Clearing the account is the one act that can still find work: this account is
        // finished, another may not be.
        let empty = TransactionListStrings.emptyState(for: kind)
        #expect(empty.action == .clearFilter)
        #expect(empty.title.contains("Everyday Savings"))
        #expect(empty.message.contains("Everyday Savings"))
    }

    @Test("Nothing imported at all beats \"all done\", narrowed or not")
    func anEmptyStoreIsNeverAFinish() {
        // Row 4 of the table. A person with nothing in the store has not finished anything,
        // and congratulating them would be the app congratulating itself.
        #expect(
            EmptyKind.decide(summaries: [], filter: .all, uncategorizedOnly: true)
                == .nothingImported)
        #expect(
            EmptyKind.decide(summaries: [], filter: Self.filter(), uncategorizedOnly: true)
                == .nothingImported)

        // Statements imported, no live rows anywhere: still 018's states, because there is
        // nothing to have answered.
        let quiet = [Self.summary(count: 0), Self.summary(id: "account-2", count: 0)]
        #expect(
            EmptyKind.decide(summaries: quiet, filter: .all, uncategorizedOnly: true)
                == .noTransactionsAnywhere)
        let excluded = [Self.summary(count: 0, onlyExcluded: true)]
        #expect(
            EmptyKind.decide(summaries: excluded, filter: .all, uncategorizedOnly: true)
                == .nothingToShowAnywhere)
    }

    @Test("An account with no live rows keeps 018's wording, narrowed or not")
    func anEmptyAccountIsNotAFinish() {
        // Last row of the table: the narrowing is not why this account is empty, so saying
        // "nothing left to file" would answer a question the person did not ask.
        let statementEmpty = [Self.summary(count: 0)]
        #expect(
            EmptyKind.decide(
                summaries: statementEmpty, filter: Self.filter(), uncategorizedOnly: true)
                == .accountStatementEmpty(name: "Everyday Savings"))

        let allExcluded = [Self.summary(count: 0, onlyExcluded: true)]
        #expect(
            EmptyKind.decide(
                summaries: allExcluded, filter: Self.filter(), uncategorizedOnly: true)
                == .accountNothingToShow(name: "Everyday Savings"))

        let othersHaveRows = [
            Self.summary(count: 0),
            Self.summary(id: "account-2", name: "Travel Card", count: 4),
        ]
        #expect(
            EmptyKind.decide(
                summaries: othersHaveRows, filter: Self.filter(), uncategorizedOnly: true)
                == .accountEmptyOthersHaveRows(name: "Everyday Savings", statementWasEmpty: true))
    }

    @Test("The narrowing is an input: off, every answer is exactly 018's")
    func theNarrowingOffChangesNothing() {
        let cases: [[AccountSummary]] = [
            [],
            [Self.summary(count: 0)],
            [Self.summary(count: 0, onlyExcluded: true)],
            [Self.summary(count: 4), Self.summary(id: "account-2", name: "Travel Card", count: 9)],
            [Self.summary(count: 0), Self.summary(id: "account-2", name: "Travel Card", count: 4)],
        ]
        for summaries in cases {
            for filter in [AccountFilter.all, Self.filter()] {
                // The defaulted call and the explicit `false` are the same decision — which is
                // what lets every caller written before this slice keep its behaviour
                // (L6, FR-046, SC-024).
                #expect(
                    EmptyKind.decide(summaries: summaries, filter: filter)
                        == EmptyKind.decide(
                            summaries: summaries, filter: filter, uncategorizedOnly: false))
            }
        }
    }

    // MARK: - L5 — no new `AccountSummary` field, and none is needed

    /// **L5** — "this account has live rows but the narrowed page came back empty" ⇒ every row
    /// in it is answered. The inference is exact, because the page and this decision are about
    /// the same rows, so a stored "all answered" flag would be a second source of truth able to
    /// disagree with the page a person is looking at (FR-078).
    ///
    /// Asserted **structurally**: the field would have to exist to be read, so the assertion is
    /// that it does not exist. A test that merely avoided using one would pass on the day
    /// somebody added it.
    @Test("The decision reads no fact about an account that the engine did not already give it")
    func noNewAccountSummaryField() {
        let fields = Set(
            Mirror(reflecting: Self.summary(count: 3)).children.compactMap(\.label))

        #expect(
            fields == [
                "id", "name", "last4", "isCreditCard", "currency",
                "liveTransactionCount", "hasOnlyExcludedRows",
            ],
            "AccountSummary grew a field: an 'all answered' flag would be a second source of truth"
        )
    }
}
