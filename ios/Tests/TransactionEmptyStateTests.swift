import Foundation
import KanameCore
import Testing

@testable import Kaname

/// Why the list is empty — one of six true things, and telling a person the wrong one is
/// indistinguishable, from where they sit, from the app having lost their money.
///
/// "Nothing imported yet" shown to somebody who imported a statement last week says their
/// import is gone. "The statement had no transactions" shown to somebody whose rows were all
/// superseded says their spending never happened. Both are reachable from the same blank
/// screen, and only `[AccountSummary]` and the filter tell them apart — so the decision is a
/// pure function of exactly those two things, and this suite is the table it must satisfy
/// (`data-model.md` §6).
///
/// ⚠️ **This suite was written after the decision it tests** — `EmptyKind.decide` landed early
/// with US1, because a screen that goes blank when a person has nothing is not shippable. It
/// was therefore **observed failing** against three deliberately broken decisions before it was
/// trusted (see `tasks.md` § "US7 — RECORDED"). A suite that has only ever been green proves
/// nothing about what it would catch.
@Suite("An empty list says which empty it is")
struct TransactionEmptyStateTests {
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

    // MARK: - The six rows of data-model.md §6

    @Test("Row 1 — nothing has been imported at all")
    func nothingImported() {
        #expect(EmptyKind.decide(summaries: [], filter: .all) == .nothingImported)
        // Even filtered: an account that cannot exist yet cannot be the reason (E4).
        #expect(EmptyKind.decide(summaries: [], filter: Self.filter()) == .nothingImported)

        let empty = TransactionListStrings.emptyState(for: .nothingImported)
        #expect(empty.action == .importStatement)
        #expect(empty.title == "Nothing imported yet")
    }

    @Test("Row 2 — everything imported, and no statement had a transaction in it")
    func noTransactionsAnywhere() {
        let summaries = [
            Self.summary(count: 0),
            Self.summary(id: "account-2", name: "Travel Card", count: 0),
        ]

        #expect(EmptyKind.decide(summaries: summaries, filter: .all) == .noTransactionsAnywhere)

        // Not an accusation, and not an offer to import again — the person did import, and
        // the statements really were empty (FR-048).
        let empty = TransactionListStrings.emptyState(for: .noTransactionsAnywhere)
        #expect(empty.action == nil)
        #expect(empty.message.contains("didn't have any transactions"))
    }

    @Test("Row 3 — everything imported, and every row there was is excluded")
    func nothingToShowAnywhere() {
        let summaries = [
            Self.summary(count: 0),
            Self.summary(id: "account-2", name: "Travel Card", count: 0, onlyExcluded: true),
        ]

        // One excluded account is enough: "no transactions anywhere" would be a claim about
        // rows this person's statements demonstrably had (FR-050).
        #expect(EmptyKind.decide(summaries: summaries, filter: .all) == .nothingToShowAnywhere)
        #expect(
            EmptyKind.decide(summaries: summaries, filter: .all)
                != EmptyKind.decide(summaries: [Self.summary(count: 0)], filter: .all)
        )
    }

    @Test("Row 4 — this account's statement genuinely had no transactions")
    func accountStatementEmpty() {
        let summaries = [Self.summary(count: 0)]

        let kind = EmptyKind.decide(summaries: summaries, filter: Self.filter())
        #expect(kind == .accountStatementEmpty(name: "Everyday Savings"))

        // Neither an error nor "nothing imported": the statement is imported and it is empty.
        let empty = TransactionListStrings.emptyState(for: kind)
        #expect(empty.title != "Nothing imported yet")
        #expect(empty.message.contains("Everyday Savings"))
        #expect(!empty.message.lowercased().contains("error"))
    }

    @Test("Row 5 — this account holds rows and shows none")
    func accountNothingToShow() {
        let summaries = [Self.summary(count: 0, onlyExcluded: true)]

        let kind = EmptyKind.decide(summaries: summaries, filter: Self.filter())
        #expect(kind == .accountNothingToShow(name: "Everyday Savings"))

        // Clearing the filter is offered, because the filter is the only thing a person can
        // act on here (FR-049).
        #expect(TransactionListStrings.emptyState(for: kind).action == .clearFilter)
        // And rows 4 and 5 are different sentences: "the statement was empty" and "there is
        // nothing to show" are different facts about a person's money (FR-048 vs FR-050).
        #expect(
            TransactionListStrings.emptyState(for: kind).message
                != TransactionListStrings.emptyState(
                    for: .accountStatementEmpty(name: "Everyday Savings")
                ).message
        )
    }

    @Test("Row 6 — the filter is the reason, and it says so")
    func accountEmptyWhileOthersHaveRows() {
        let others = Self.summary(id: "account-2", name: "Travel Card", count: 4)

        // Row 6 *refines* rows 4 and 5 — it keeps the account's own reason in the sentence
        // rather than replacing it (design note E3).
        let statementWasEmpty = EmptyKind.decide(
            summaries: [Self.summary(count: 0), others], filter: Self.filter())
        #expect(
            statementWasEmpty
                == .accountEmptyOthersHaveRows(name: "Everyday Savings", statementWasEmpty: true))

        let allExcluded = EmptyKind.decide(
            summaries: [Self.summary(count: 0, onlyExcluded: true), others], filter: Self.filter())
        #expect(
            allExcluded
                == .accountEmptyOthersHaveRows(name: "Everyday Savings", statementWasEmpty: false))

        for kind in [statementWasEmpty, allExcluded] {
            let empty = TransactionListStrings.emptyState(for: kind)
            #expect(empty.action == .clearFilter)
            #expect(empty.message.contains("Other accounts have transactions"))
            #expect(empty.title.contains("Everyday Savings"))
        }
        // The two row-6 sentences are still different from one another: which of the two
        // reasons this account is empty survives being refined.
        #expect(
            TransactionListStrings.emptyState(for: statementWasEmpty).message
                != TransactionListStrings.emptyState(for: allExcluded).message
        )
    }

    // MARK: - The six are six

    @Test("Every row of the table is its own state, and no two collapse into one")
    func theSixStatesAreDistinct() {
        let kinds: [EmptyKind] = [
            .nothingImported,
            .noTransactionsAnywhere,
            .nothingToShowAnywhere,
            .accountStatementEmpty(name: "Everyday Savings"),
            .accountNothingToShow(name: "Everyday Savings"),
            .accountEmptyOthersHaveRows(name: "Everyday Savings", statementWasEmpty: true),
        ]

        let sentences = kinds.map { kind -> String in
            let empty = TransactionListStrings.emptyState(for: kind)
            return "\(empty.title)|\(empty.message)"
        }
        #expect(Set(sentences).count == kinds.count, "two empty states say the same thing")
        // And the cases themselves are distinguishable, not merely worded differently.
        for (index, kind) in kinds.enumerated() {
            for other in kinds[(index + 1)...] {
                #expect(kind != other)
            }
        }
    }

    // MARK: - Which empty state may be prominent (design note D2)

    @Test("The import action is prominent only where it is the screen's one glass element")
    func onlyTheUnimportedStateIsProminent() async throws {
        // Nothing imported: no filter bar, so the import button is the only glass on screen.
        let fresh = await TransactionListViewModel(
            history: HistoryDouble(pages: [HistoryPage(rows: [], cursor: nil)], summaries: []),
            clock: listClock
        )
        await fresh.onAppear()
        #expect(await fresh.state == .empty(.nothingImported))
        #expect(await fresh.emptyActionIsProminent)
        #expect(await fresh.showsFilterChrome == false)

        // Everything imported and every row excluded: the same import action, but the filter
        // bar is on screen with it, and two prominent controls make prominence meaningless.
        let excluded = await TransactionListViewModel(
            history: HistoryDouble(
                pages: [HistoryPage(rows: [], cursor: nil)],
                summaries: [Self.summary(count: 0, onlyExcluded: true)]
            ),
            clock: listClock
        )
        await excluded.onAppear()
        #expect(await excluded.state == .empty(.nothingToShowAnywhere))
        #expect(TransactionListStrings.emptyState(for: .nothingToShowAnywhere).action == .importStatement)
        #expect(await excluded.emptyActionIsProminent == false)
        #expect(await excluded.showsFilterChrome)
    }

    // MARK: - Purity
    @Test("The decision depends on the summaries and the filter, and on nothing else")
    func theDecisionIsAPureFunction() {
        let summaries = [Self.summary(count: 0, onlyExcluded: true), Self.summary(id: "b", count: 3)]

        // Same inputs, same answer, however many times it is asked and in whatever order the
        // questions come — no clock, no store, no accumulated state.
        let first = EmptyKind.decide(summaries: summaries, filter: Self.filter())
        _ = EmptyKind.decide(summaries: [], filter: .all)
        _ = EmptyKind.decide(summaries: summaries, filter: .all)
        #expect(EmptyKind.decide(summaries: summaries, filter: Self.filter()) == first)
    }

    @Test("An account the summaries have never heard of still has a destination")
    func anUnknownAccountIsStillAnswerable() {
        // Unreachable today — there is no delete path, and an unknown id reads as an empty
        // page rather than an error — but a decision table with a hole in it is a crash
        // waiting for the slice that adds one (design note E4).
        let kind = EmptyKind.decide(
            summaries: [Self.summary(id: "account-2", name: "Travel Card", count: 2)],
            filter: Self.filter("ghost", name: "Ghost Account", last4: nil)
        )

        #expect(kind == .accountEmptyOthersHaveRows(name: "Ghost Account", statementWasEmpty: false))
        #expect(TransactionListStrings.emptyState(for: kind).action == .clearFilter)
    }
}
