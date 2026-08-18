import XCTest

/// The same run, twice, is the same run — and a run that asks for nothing inherits nothing.
///
/// A fixture that quietly collapses, or a store that accumulates across runs, produces exactly
/// the failures nobody can reproduce: a suite that passes on a clean machine and fails on the
/// one that ran it yesterday. These are the assertions that make "deterministic" a property of
/// the code rather than a hope about the container.
///
/// ⚠️ **The corpus-does-not-eat-itself assertion moved** to `SeededHistoryShapeUITests`, where
/// the one expensive walk of `deep` now answers every question about that scenario at once.
/// It is the same assertion — the screen's rows, the declaration's arithmetic and the engine's
/// own per-account counts agreeing — and it is still the thing that notices when a scenario
/// loses a row to a collision it did not declare.
final class SeededDeterminismUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        SeededLaunch.pin(.light, in: self)
    }

    override func tearDown() {
        SeededLaunch.resetContainer()
        super.tearDown()
    }

    /// D1 — ten consecutive seeded launches on a container nobody cleans produce one screen.
    func testTenConsecutiveSeededLaunchesProduceTheSameScreen() {
        let scenario = SeedScenario.small
        let expected = scenario.expectedLiveRows.map(\.accessibilityLabel)
        for run in 1...10 {
            let app = SeededLaunch.launch(scenario: scenario)
            SeededLaunch.openTransactionList(app)
            XCTAssertEqual(
                SeededLaunch.allRowLabels(app), expected,
                "run \(run) of 10 rendered a different list")
            app.terminate()
        }
    }

    /// D2 — a seeded launch inherits nothing from the seeded launch before it, in both
    /// directions.
    func testASeededLaunchInheritsNothingFromADifferentSeededLaunch() {
        for (first, second) in [(SeedScenario.small, SeedScenario.deep), (.deep, .small)] {
            _ = SeededLaunch.launch(scenario: first)
            let app = SeededLaunch.launch(scenario: second)

            for account in second.expectedAccounts {
                XCTAssertTrue(
                    SeededLaunch.element(app, labelled: account.announcement)
                        .waitForExistence(timeout: 10),
                    "\(second.name) after \(first.name) is missing \(account.announcement)")
            }
            for account in first.expectedAccounts where !second.declares(accountNamed: account.name) {
                XCTAssertFalse(
                    SeededLaunch.element(app, labelled: account.announcement).exists,
                    "\(first.name)'s \(account.name) survived into \(second.name)")
            }
            app.terminate()
        }
    }

    /// D3 — a declared date renders as that date, on a machine in any region and at any time of
    /// day. The dates are declared, never relative to today, and the locale is pinned on the
    /// launch **and** in the expectation, because the test runner is a different process from
    /// the app and inherits the simulator's region rather than the app's.
    func testEveryDeclaredDateRendersAsDeclared() {
        let scenario = SeedScenario.small
        let app = SeededLaunch.launch(scenario: scenario)
        SeededLaunch.openTransactionList(app)

        let headings = Set(SeededLaunch.walk(app).headings)
        for expected in scenario.expectedGroupAnnouncements {
            XCTAssertTrue(headings.contains(expected), "missing heading: \(expected)")
        }
    }

    /// D4 — the declaration is the expectation. Change a declared amount or description and
    /// this is what goes red, rather than an assertion quietly passing against a stale copy of
    /// what the fixture used to say.
    func testTheScreenIsExactlyWhatTheDeclarationSays() {
        let scenario = SeedScenario.small
        let app = SeededLaunch.launch(scenario: scenario)
        SeededLaunch.openTransactionList(app)

        XCTAssertEqual(
            SeededLaunch.allRowLabels(app), scenario.expectedLiveRows.map(\.accessibilityLabel))
    }
}
