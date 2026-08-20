import Foundation
import KanameCore
import Testing

@testable import Kaname

/// A `CategorizeWriting` that answers whatever a test needs and **records what it was asked**.
///
/// The recording is the point. Two of the rules in this file are about a call that must not
/// happen — a second attempt after a refusal, and an id that must never be sent — and a double
/// that only returns values cannot see either of them.
private actor RecordingService: CategorizeWriting {
    private(set) var appliedPortions: [String] = []
    private(set) var appliedIDs: [[String]] = []
    private let result: Result<UInt32, Error>

    init(applying result: Result<UInt32, Error>) {
        self.result = result
    }

    var applyCallCount: Int { appliedPortions.count }

    func correct(
        _: String, to _: CategoryRef?, remember _: Bool
    ) async throws -> CorrectionOutcome {
        CorrectionOutcome(merchantPortion: nil, memoryFormed: false)
    }

    func previewMemory(_: String) async throws -> MemoryImpact {
        MemoryImpact(transactionIds: [], accounts: [])
    }

    func applyMemory(_ portion: String, expecting ids: [String]) async throws -> UInt32 {
        appliedPortions.append(portion)
        appliedIDs.append(ids)
        return try result.get()
    }

    func categories() async throws -> [KanameCore.Category] { [] }

    func uncategorizedCount() async throws -> UInt32 { 0 }
}

/// **S5** and **S6** — what the second action does with what the engine tells it, and what it
/// never does on its own.
@Suite("What the second action sends, and what it does when the engine refuses")
struct CategorizeServiceTests {
    private static func request(
        ids: [String], accounts: [AccountImpact] = []
    ) -> SecondActionRequest {
        SecondActionRequest(
            portion: "synthetic garden", categoryName: "Groceries",
            impact: MemoryImpact(transactionIds: ids, accounts: accounts))
    }

    private static func account(_ id: String, _ name: String, _ count: UInt32) -> AccountImpact {
        AccountImpact(accountId: id, displayName: name, count: count)
    }

    /// **S5** — the refusal a person can act on (FR-035f, SC-027).
    ///
    /// Three things are asserted, and the third is the one that matters: the outcome is the
    /// *named* one rather than a generic failure; the sentence a person reads says their data
    /// changed rather than that the app broke; and the engine was called **exactly once**. A
    /// silent retry with a freshly computed set is the bulk edit nobody agreed to, and it is
    /// the single most natural thing to write in response to a `StaleSet`.
    @Test("A refused set is surfaced as things having changed, and is never retried")
    func aStaleSetIsSurfacedAndNotRetried() async {
        let service = RecordingService(applying: .failure(MemoryApplicationError.setChanged))

        let outcome = await SecondActionOutcome.apply(
            Self.request(ids: ["a", "b", "c"]), through: service)

        #expect(outcome == .setChanged)
        #expect(await service.applyCallCount == 1, "the refusal was retried")
        // Nothing was written, and the *engine* is what makes that true — the double simply
        // records that only one attempt was ever made against it.
        if case .applied = outcome { Issue.record("a refused application reported a count") }
    }

    /// The sentence itself, because "person-legible" is a claim about words. It says what
    /// happened to the person's transactions — nothing — rather than what happened in the app.
    @Test("What a person is told when the set changed names their data, not the app")
    func theStaleSentenceIsAboutTheirData() {
        let sentence = CategorizeStrings.secondActionStale

        #expect(sentence.lowercased().contains("changed"))
        #expect(!sentence.lowercased().contains("error"))
        #expect(!sentence.lowercased().contains("failed"))
        #expect(sentence != CategorizeStrings.secondActionFailed, "one failure for two things")
    }

    /// ⚠️ **The mapping, asserted where it actually happens.** The double above throws what
    /// the *seam* throws, because that is what a view can ever see — so the translation from
    /// the engine's `StaleSet` into the one thing a person can act on needs its own assertion,
    /// or it is covered by nothing at all.
    ///
    /// This is the second time a `_: Error` mapping has quietly lost a case in this app
    /// (`TransactionListError` collapses `NotFound` and `StaleSet` alike, deliberately). Here
    /// it may not: a `default` arm swallowing `StaleSet` turns "your data changed" into
    /// "something went wrong", and a person told the latter tries the same thing twice.
    @Test("The engine's refusal keeps its identity; every other failure collapses")
    func theRefusalKeepsItsIdentity() {
        #expect(
            MemoryApplicationError(mapping: StoreError.StaleSet(expected: 3, found: 2))
                == .setChanged)
        for error in [
            StoreError.WrongKey, StoreError.NotFound(kind: "transaction"),
            StoreError.Sql(message: "disk"), StoreError.InvalidKey,
            StoreError.Migration(message: "v8"), StoreError.OpenFailed(message: "path"),
        ] {
            #expect(
                MemoryApplicationError(mapping: error) == .unavailable,
                "\(error) was read as a stale set")
        }
    }

    /// Any other failure is exactly that, and stays distinguishable from a stale set.
    @Test("Every other failure ends the second action as a plain failure")
    func everyOtherFailureIsNotTheStaleOne() async {
        let service = RecordingService(applying: .failure(MemoryApplicationError.unavailable))

        let outcome = await SecondActionOutcome.apply(Self.request(ids: ["a"]), through: service)

        #expect(outcome == .failed)
    }

    /// **S4** — the ids the preview handed over, sent unmodified.
    @Test("The ids sent are the preview's own, in the preview's own order")
    func theIdsSentAreThePreviewsOwn() async {
        let service = RecordingService(applying: .success(3))
        let ids = ["txn-3", "txn-1", "txn-2"]

        let outcome = await SecondActionOutcome.apply(Self.request(ids: ids), through: service)

        #expect(outcome == .applied(count: 3))
        #expect(await service.appliedIDs == [ids], "the list was reordered or trimmed")
        #expect(await service.appliedPortions == ["synthetic garden"])
    }

    /// **S6** — FR-035d, SC-031. A row a person corrected by hand is not in the preview, and
    /// this screen has no other source: it neither counts it nor sends it.
    ///
    /// ⚠️ The exclusion itself is the **engine's** (its affected-set predicate excludes a
    /// person's own provenance; engine test M4). What is asserted here is the thing the
    /// platform could get wrong on its own — deriving the radius from somewhere other than the
    /// preview. There is exactly one place a hand-corrected row could re-enter: a view that
    /// counted rows itself instead of reading the list it was given.
    @Test("A row the person corrected by hand is neither counted nor sent")
    func handCorrectedRowsAreNeitherCountedNorSent() async {
        // The engine previewed two rows. A third, corrected by hand, is absent — as it must be.
        let handCorrected = "txn-by-hand"
        let request = Self.request(
            ids: ["txn-1", "txn-2"],
            accounts: [Self.account("acc-1", "SYNTHETIC RIVERSIDE COMMUNITY BANK", 2)])
        let service = RecordingService(applying: .success(2))

        #expect(request.statedCount == 2, "the screen states a count that is not the engine's")
        #expect(request.statedSummary.contains("2 transactions"))
        #expect(
            request.statedAccountLines
                == ["SYNTHETIC RIVERSIDE COMMUNITY BANK: 2 transactions"])

        _ = await SecondActionOutcome.apply(request, through: service)

        #expect(await service.appliedIDs.first?.contains(handCorrected) == false)
    }

    /// **S1** — the radius names both facts, and it names them before anything is written. One
    /// transaction is spelled as one, because "1 transactions" is the kind of thing that ships.
    @Test("The radius states a count and every account, and reads as a person would say it")
    func theRadiusStatesBothFacts() {
        let one = Self.request(
            ids: ["txn-1"], accounts: [Self.account("acc-1", "SYNTHETIC TRAVEL REWARDS CARD", 1)])

        #expect(one.statedSummary.contains("1 transaction"))
        #expect(!one.statedSummary.contains("1 transactions"))
        #expect(one.statedAccountLines == ["SYNTHETIC TRAVEL REWARDS CARD: 1 transaction"])
        #expect(one.statedSummary.contains("synthetic garden"), "the merchant is not named")
        #expect(one.statedSummary.contains("Groceries"), "where it would land is not named")
    }

    /// **S3** — two accounts stay two accounts, in the engine's order. This is the assertion
    /// that goes red if the view ever starts grouping, sorting or merging the list it was
    /// handed.
    @Test("Two accounts are stated as two, in the order the engine stated them")
    func twoAccountsStayTwo() {
        let request = Self.request(
            ids: ["txn-1", "txn-2"],
            accounts: [
                Self.account("acc-1", "SYNTHETIC RIVERSIDE COMMUNITY BANK", 1),
                Self.account("acc-2", "SYNTHETIC TRAVEL REWARDS CARD", 1),
            ])

        #expect(
            request.statedAccountLines == [
                "SYNTHETIC RIVERSIDE COMMUNITY BANK: 1 transaction",
                "SYNTHETIC TRAVEL REWARDS CARD: 1 transaction",
            ])
    }
}
