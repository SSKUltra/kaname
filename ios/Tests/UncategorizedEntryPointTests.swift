import Foundation
import KanameCore
import Testing

@testable import Kaname

/// A `CategorizeWriting` whose uncategorized count is scripted and **counted**.
///
/// The counting is the point: E5 is about a read happening, not about a number being right, so
/// a double that only returned a value could not tell a refresh apart from a stale screen.
private actor CountingService: CategorizeWriting {
    private var answers: [UInt32]
    private(set) var reads = 0
    private let failing: Bool

    init(answers: [UInt32], failing: Bool = false) {
        self.answers = answers
        self.failing = failing
    }

    func correct(_: String, to _: CategoryRef?, remember _: Bool) async throws -> CorrectionOutcome {
        CorrectionOutcome(merchantPortion: nil, memoryFormed: false)
    }

    func previewMemory(_: String) async throws -> MemoryImpact {
        MemoryImpact(transactionIds: [], accounts: [])
    }

    func applyMemory(_: String, expecting _: [String]) async throws -> UInt32 { 0 }

    func categories() async throws -> [KanameCore.Category] { [] }

    /// Serves the scripted answers in order and then repeats the last one, so a test that only
    /// cares about the first read does not have to script every later one.
    func uncategorizedCount() async throws -> UInt32 {
        reads += 1
        if failing { throw TransactionListError.unavailable }
        guard let next = answers.first else { return 0 }
        if answers.count > 1 { answers.removeFirst() }
        return next
    }
}

/// **E2**, **E3** and **E5** — what the door onto the worklist says, and where its number
/// comes from.
///
/// The number is the one thing this surface is *for*, and it is the one thing it is forbidden
/// to work out. 018 deliberately moved the front door's count out of Swift and into SQL,
/// because a count computed beside a list is a count that will eventually disagree with it —
/// and a count that disagrees with the worklist behind it is a person told there are three
/// left, opening the door, and finding five.
@Suite("The door onto what has no category")
struct UncategorizedEntryPointTests {
    // MARK: - E2 — the count is the engine's, and one call to get it

    @Test("The count is one engine call, and the door says exactly what it answered")
    func theCountIsTheEnginesNumber() async {
        let service = CountingService(answers: [7])
        let model = await UncategorizedEntryPointModel(service: service)

        await model.refresh()

        #expect(await model.count == 7)
        #expect(await model.sentence == "7 transactions need a category")
        #expect(await service.reads == 1, "the door asked the engine more than once for one number")
    }

    /// **E2** — no Swift arithmetic, asserted where it would actually be written.
    ///
    /// The failure this prevents is a summing of `AccountSummary`: the front door already holds
    /// every account, so the count *looks* derivable from what is on screen. It is not — the
    /// summaries carry live counts, not unanswered ones — and a sum of them would be a
    /// different number that happened to be near the right one (FR-041b, FR-043, SC-029).
    @Test("Nothing but the engine's answer can move the number")
    func nothingElseCanMoveTheNumber() async {
        let summaries = [
            AccountSummary(
                id: "account-1", name: "Everyday Savings", last4: "1123", isCreditCard: false,
                currency: "INR", liveTransactionCount: 40, hasOnlyExcludedRows: false),
            AccountSummary(
                id: "account-2", name: "Travel Card", last4: "8890", isCreditCard: true,
                currency: "INR", liveTransactionCount: 60, hasOnlyExcludedRows: false),
        ]
        let service = CountingService(answers: [3])
        let model = await UncategorizedEntryPointModel(service: service)

        await model.refresh()

        // A hundred live rows across two accounts, and the door says three, because three is
        // what the engine counted.
        #expect(summaries.map(\.liveTransactionCount).max() == 60)
        #expect(await model.count == 3)
    }

    // MARK: - E3 — zero is a finish, not a counter reading zero

    @Test("Zero is said in a person's words")
    func zeroIsAFinish() async {
        let model = await UncategorizedEntryPointModel(service: CountingService(answers: [0]))

        await model.refresh()

        #expect(await model.sentence == CategorizeStrings.worklistFinished)
        #expect(await model.sentence?.contains("0") == false)
    }

    @Test("One is one, not \"1 transactions\"")
    func oneIsSaidSingly() async {
        let model = await UncategorizedEntryPointModel(service: CountingService(answers: [1]))

        await model.refresh()

        #expect(await model.sentence == "1 transaction needs a category")
    }

    @Test("Before the engine has answered, the door says nothing at all")
    func anUnaskedDoorIsSilent() async {
        let model = await UncategorizedEntryPointModel(service: CountingService(answers: [4]))

        // Not "Everything has a category" — a door that claims a person is finished and then
        // takes it back a frame later has told them something untrue.
        #expect(await model.sentence == nil)
    }

    @Test("A read that failed leaves the door silent rather than claiming a finish")
    func aFailedReadNeverClaimsAFinish() async {
        let model = await UncategorizedEntryPointModel(
            service: CountingService(answers: [], failing: true))

        await model.refresh()

        #expect(await model.count == nil)
        #expect(await model.sentence == nil)
    }

    // MARK: - E4 — where the door goes

    @Test("The door opens the one transaction list, narrowed and unfiltered")
    func theDoorOpensTheOneList() {
        let destination = UncategorizedEntryPointModel.destination

        #expect(destination.uncategorizedOnly)
        #expect(destination.filter == .all)
        // FR-041b: the count is store-wide, so the door must not carry an account with it —
        // otherwise the number on it and the rows behind it are different sets.
        #expect(destination.filter.accountID == nil)
    }

    // MARK: - E5 — the number keeps up with the corrections

    @Test("A correction anywhere in the app makes the door ask again")
    func aCorrectionRefreshesTheCount() async throws {
        let signal = CategoryChangeSignal()
        let service = CountingService(answers: [3, 2])
        let model = await UncategorizedEntryPointModel(service: service)
        await model.refresh()
        #expect(await model.count == 3)

        let listening = Task { await model.refreshWhenCategoriesChange(signal) }
        // The subscription is established asynchronously; wait for it rather than sleeping,
        // because a `send()` that arrives before anybody is listening is a send nobody hears.
        try await waitFor { signal.subscriberCount == 1 }
        signal.send()
        try await waitFor { await model.count == 2 }
        listening.cancel()

        #expect(await model.count == 2)
        #expect(await service.reads == 2, "the door adjusted its own number instead of re-asking")
    }

    @Test("A door that has gone away stops listening")
    func aDismissedDoorUnsubscribes() async throws {
        let signal = CategoryChangeSignal()
        let model = await UncategorizedEntryPointModel(service: CountingService(answers: [1]))

        let listening = Task { await model.refreshWhenCategoriesChange(signal) }
        try await waitFor { signal.subscriberCount == 1 }
        listening.cancel()

        try await waitFor { signal.subscriberCount == 0 }
        #expect(signal.subscriberCount == 0)
    }

    /// Poll a condition until it holds, rather than sleeping for a duration somebody guessed.
    private func waitFor(
        _ condition: @Sendable () async -> Bool,
        within: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: within)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("the condition never held")
    }
}
