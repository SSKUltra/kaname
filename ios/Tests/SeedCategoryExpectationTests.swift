import Foundation
import KanameCore
import Testing

@testable import Kaname

/// What a seeded scenario *declares* about categories, checked against what the **engine**
/// actually does with it.
///
/// ⚠️ This is the point of the file. `SeedScenario.expectedUncategorizedCount` is derived from
/// `expectedCategory:` annotations somebody wrote by hand, and a declaration checked only
/// against itself agrees with itself forever — including on the day the engine changes which
/// rows it can place. So the scenario is written into a real store through the shipped import
/// call, and the engine's own `uncategorizedCount()` is what the declaration is measured
/// against (T113).
///
/// It runs as an app-hosted unit test rather than a UI test because a UI-test bundle links
/// neither the app nor `KanameCore`, so nothing over there can ask the engine anything.
@Suite("What a seed declares about categories, against what the engine does")
struct SeedCategoryExpectationTests {
    private static let key =
        "2f1c8a9e4b7d6035112233445566778899aabbccddeeff00112233445566aabb"

    private static func tempDatabase() -> (dir: URL, path: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-seed-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("kaname.db").path)
    }

    /// Write a scenario the way `DebugSeed` writes it: declaration order, one `importStatement`
    /// per statement, through the front door and nothing else.
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

    @Test(
        "Every scenario's declared worklist is the worklist the engine actually has",
        arguments: SeedScenario.declared)
    func theDeclaredWorklistIsTheEnginesWorklist(scenario: SeedScenario) throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        try Self.seed(scenario, into: store)

        #expect(
            Int(try store.uncategorizedCount()) == scenario.expectedUncategorizedCount,
            "the declaration and the engine disagree about the worklist of \(scenario.name)"
        )
    }

    /// `unfiled` exists to be a worklist, and a worklist that is *everything* proves nothing:
    /// a narrowed list showing every row would pass against it. So it must hold both kinds of
    /// row, and the engine must be the one that says so.
    @Test("The unfiled scenario holds rows the engine placed and rows it could not")
    func unfiledHoldsBothKindsOfRow() throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)
        let scenario = SeedScenario.unfiled

        try Self.seed(scenario, into: store)
        let unanswered = Int(try store.uncategorizedCount())

        #expect(unanswered > 0, "nothing is left to file")
        #expect(unanswered < scenario.expectedLiveRowCount, "everything is left to file")
        #expect(unanswered == scenario.expectedUncategorizedCount)
    }
}
