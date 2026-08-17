import XCTest

/// The same run, twice, is the same run — and a run that asks for nothing inherits nothing.
///
/// A fixture that quietly collapses, or a store that accumulates across runs, produces exactly
/// the failures nobody can reproduce: a suite that passes on a clean machine and fails on the
/// one that ran it yesterday. These are the assertions that make "deterministic" a property of
/// the code rather than a hope about the container.
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

    /// ⚠️ **The corpus must not eat itself.** A synthetic history built from repeated rows
    /// collapses under the engine's own de-duplication and comes out short — 018 learned this
    /// the hard way, from an ordering fixture whose printed order happened to coincide with
    /// descending amount and let a deliberate break slip past.
    ///
    /// So the declaration's arithmetic is checked against two independent readings of the same
    /// store: the rows the screen renders, and the live count the **engine** reports per
    /// account at the front door. If `deep` ever loses a row to a collision it did not declare,
    /// all three numbers stop agreeing here rather than silently in a later assertion that was
    /// only ever testing a fraction of what it claimed.
    func testTheDeepScenarioDoesNotDeDuplicateItself() {
        let scenario = SeedScenario.deep
        let declared = scenario.expectedLiveRows.map(\.accessibilityLabel)
        XCTAssertEqual(
            Set(declared).count, declared.count,
            "two live rows share a sentence, so a count of sentences is not a count of rows")

        let app = SeededLaunch.launch(scenario: scenario)
        for account in scenario.expectedAccounts {
            XCTAssertTrue(
                SeededLaunch.element(app, labelled: account.announcement).waitForExistence(timeout: 10),
                "the engine does not report \(account.announcement)")
        }

        SeededLaunch.openTransactionList(app)
        let onScreen = SeededLaunch.allRowLabels(app)

        XCTAssertEqual(onScreen.count, scenario.expectedLiveRowCount)
        XCTAssertEqual(Set(onScreen), Set(declared))
        // Exactly the collisions the scenario declares, and no others: one re-import and one
        // cross-source pair. ⚠️ Two credit cards never de-duplicate — the engine compares a
        // ledger against a card and nothing else — so a scenario that declared this pair as two
        // cards would lose its supersession **silently**, and this number is what would notice.
        XCTAssertEqual(scenario.expectedSupersededRowCount, 2)
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
