import Foundation
import KanameCore
import Testing

@testable import Kaname

/// What a memory scenario *declares*, checked against what the **engine** actually derives
/// (T124).
///
/// ⚠️ This is the whole point of the file, and it is the same argument
/// `SeedCategoryExpectationTests` makes one field over: `SeedMemorySubject.portion` is a string
/// somebody wrote, and a declaration checked only against itself agrees with itself forever.
/// The Swift side may never derive a merchant portion of its own (FR-021, FR-076), so the only
/// honest check is to ask the engine.
///
/// It asks twice, in opposite directions. **Correct**: every description the subject names
/// derives to the declared portion. **Complete**: no other row in the scenario does. The second
/// is the one that matters — an `alsoMatching` that is merely correct understates the blast
/// radius, and the blast radius is the one number the second action exists to state before a
/// person agrees to anything.
@Suite("What a memory scenario declares, against what the engine derives")
struct SeedMemoryExpectationTests {
    private static let key =
        "9d3c7f1a2b6e5048ffeeddccbbaa99887766554433221100aabbccddeeff0011"

    /// The scenarios that declare a memory. Derived from the declared set rather than listed,
    /// so a scenario added tomorrow is adjudicated without anybody remembering to add it here.
    private static let withMemory = SeedScenario.declared.filter { $0.memory != nil }

    private static func tempStore() throws -> (dir: URL, store: Store) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-memory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = try Store.open(
            path: dir.appendingPathComponent("kaname.db").path, key: key)
        return (dir, store)
    }

    /// Write a scenario the way `DebugSeed` writes it — declaration order, one
    /// `importStatement` per statement, through the front door and nothing else.
    private static func seed(_ scenario: SeedScenario, into store: Store) throws {
        var accountIDs: [String: String] = [:]
        for statement in scenario.statements {
            let request = SeedScenarioBuilder.request(
                for: statement, in: scenario,
                existingAccountID: accountIDs[statement.accountName])
            let outcome = try store.importStatement(request: request)
            accountIDs[statement.accountName] = outcome.accountId
        }
    }

    private static func liveRows(_ store: Store) throws -> [HistoryRow] {
        try store.historyPage(
            query: HistoryQuery(
                accountId: nil, cursor: nil, limit: 500, uncategorizedOnly: false)
        ).rows
    }

    /// Both directions of the declaration, over every scenario that makes one.
    @Test(
        "A declared merchant portion is the engine's, and no other row shares it",
        arguments: withMemory)
    func theDeclaredPortionIsTheEngines(scenario: SeedScenario) throws {
        guard let memory = scenario.memory else {
            Issue.record("\(scenario.name) declares no memory")
            return
        }

        let named = Set([memory.subjectDescription] + memory.alsoMatching)
        for description in named {
            #expect(
                merchantPortion(narration: description) == memory.portion,
                """
                \(scenario.name): the engine reads \(description) as \
                \(merchantPortion(narration: description) ?? "nothing")
                """)
        }
        for description in scenario.everyDeclaredDescription where !named.contains(description) {
            #expect(
                merchantPortion(narration: description) != memory.portion,
                """
                \(scenario.name): \(description) shares the declared portion and is not \
                declared as sharing it — the blast radius is understated
                """)
        }
    }

    /// ⚠️ Nothing in either scenario may be de-duplicated. `repeated` re-imports into one
    /// account and `crossing` spans a ledger and a card, which are precisely the two routes to
    /// a superseded row — and a superseded row is one the memory can no longer reach, which
    /// makes the impact quietly short with nothing on screen or in a log to say so.
    @Test("Nothing in a memory scenario is de-duplicated away", arguments: withMemory)
    func nothingCollides(scenario: SeedScenario) throws {
        let temporary = try Self.tempStore()
        defer { try? FileManager.default.removeItem(at: temporary.dir) }
        try Self.seed(scenario, into: temporary.store)

        #expect(scenario.expectedSupersededRowCount == 0, "\(scenario.name) declares a collision")
        #expect(
            try Self.liveRows(temporary.store).count == scenario.expectedLiveRowCount,
            "\(scenario.name): the engine kept a different number of rows than declared")
    }

    /// The declared impact, against `preview_memory_application` on a real store — after the
    /// subject has been corrected exactly as a person corrects it.
    @Test("The declared impact is the impact the engine previews", arguments: withMemory)
    func theDeclaredImpactIsTheEngines(scenario: SeedScenario) throws {
        guard let memory = scenario.memory, let expected = scenario.expectedMemoryImpact else {
            Issue.record("\(scenario.name) declares no memory")
            return
        }
        let temporary = try Self.tempStore()
        defer { try? FileManager.default.removeItem(at: temporary.dir) }
        let store = temporary.store
        try Self.seed(scenario, into: store)

        guard
            let subject = try Self.liveRows(store).first(where: {
                $0.descriptionRaw == memory.subjectDescription
            })
        else {
            Issue.record("\(scenario.name): the subject row is not live")
            return
        }
        let outcome = try store.setTransactionCategory(
            transactionId: subject.id, category: .builtin(code: "GROCERIES"), remember: true)

        #expect(outcome.merchantPortion == memory.portion)
        #expect(outcome.memoryFormed, "the correction formed no memory to preview")

        let impact = try store.previewMemoryApplication(merchantPortion: memory.portion)
        #expect(
            impact.transactionIds.count == expected.rows.count,
            """
            \(scenario.name): the engine would change \(impact.transactionIds.count) rows, \
            the declaration says \(expected.rows.count)
            """)
        #expect(impact.accounts.map(\.displayName) == expected.accountNames)
        // The corrected row is a person's own decision and must never be in its own blast
        // radius — the engine's rule, asserted here because it is the one that keeps a second
        // offer from quietly rewriting the first.
        #expect(!impact.transactionIds.contains(subject.id))
    }
}
