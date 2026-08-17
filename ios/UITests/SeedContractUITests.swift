import XCTest

/// The seeded launch's own contract (`specs/019-debug-test-seeding/contracts/seeded-launch.md`
/// §4, assertions L1–L6) — what a launch does when it is asked for a history, and, just as
/// importantly, what it does when it is not.
///
/// ⚠️ **The key is set bare on `launchEnvironment`.** The `TEST_RUNNER_` prefix rule that
/// `make reference-check` and `make perf-corpus` rely on applies to *unit* tests hosted inside
/// the app, where `xcodebuild` forwards only prefixed variables and strips the prefix.
/// `launchEnvironment` is set on the app process by XCUITest and needs no prefix — a prefixed
/// variable here is never delivered, and the suite runs silently unseeded, which looks exactly
/// like a pass.
final class SeedContractUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        // A seeded store outlives the suite that wrote it, and the shipped front-door audits
        // assert a fresh install. Put the container back the way this suite found it.
        SeededLaunch.resetContainer()
        super.tearDown()
    }

    /// L1 — no request, no seed: the app is the app, and the route to the list is still absent.
    func testALaunchWithNoScenarioIsAnOrdinaryFirstRun() {
        SeededLaunch.resetContainer()

        let app = SeededLaunch.launch(scenario: nil)

        XCTAssertTrue(app.buttons["Import a statement"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["All transactions"].exists)
    }

    /// L2 — the declared account is on the front door, with the count the engine reports.
    func testASeededLaunchShowsTheSeededAccountOnTheFrontDoor() {
        let app = SeededLaunch.launch(scenario: .small)

        guard let account = SeedScenario.small.expectedAccounts.first else {
            return XCTFail("the small scenario declares no account")
        }
        XCTAssertTrue(
            SeededLaunch.element(app, labelled: account.announcement).waitForExistence(timeout: 10),
            "the front door does not show \(account.announcement)")
    }

    /// L3 — nothing was picked. A seeded launch never presents the document picker, which is
    /// the interaction no automated run can drive and the reason this slice exists.
    ///
    /// The picker is another process, so what is asserted is what this process can see: the
    /// app's own screen is frontmost, and no sheet is up.
    func testASeededLaunchPresentsNoDocumentPicker() {
        let app = SeededLaunch.launch(scenario: .small)

        XCTAssertTrue(app.navigationBars["Kaname"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.sheets.count, 0)
        XCTAssertFalse(app.buttons["Cancel"].exists)
    }

    /// L4 — an unrecognised name fails the **launch**. There is no fallback to an empty app,
    /// because an accessibility audit reporting success against a blank screen is the worst
    /// thing this slice could ship (FR-006, SC-016).
    func testAnUnrecognisedScenarioNameNeverReachesTheForeground() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchEnvironment[SeededLaunch.key] = "does-not-exist"
        app.launchArguments += SeededLaunch.localeArguments

        // The launch itself is what fails, and XCUITest reports the crash as a test failure of
        // its own — after `launch()` has returned, which is why the expectation is registered
        // for the remainder of the test rather than around a block. ⚠️ The matcher is narrow on
        // purpose: **only** the crash report is absorbed, so the assertion below is still a real
        // assertion. Without it, an expectation covering the rest of the test would swallow the
        // very verdict this test exists to reach.
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        options.issueMatcher = { $0.compactDescription.contains("crashed") }
        XCTExpectFailure("an unrecognised scenario must fail the launch", options: options)
        app.launch()

        XCTAssertNotEqual(app.state, .runningForeground)
    }

    /// L5 — the whole point, measured: launch to a row on screen, inside SC-009's five seconds.
    func testASeededLaunchReachesThePopulatedListWithinFiveSeconds() {
        let started = Date()
        let app = SeededLaunch.launch(scenario: .small)
        app.buttons["All transactions"].tap()

        guard let first = SeedScenario.small.expectedLiveRows.first else {
            return XCTFail("the small scenario declares no live row")
        }
        XCTAssertTrue(
            SeededLaunch.element(app, labelled: first.accessibilityLabel).waitForExistence(timeout: 10))
        let elapsed = Date().timeIntervalSince(started)
        print("seed-timing: small reached its first row in \(String(format: "%.2f", elapsed))s")
        XCTAssertLessThan(elapsed, 5.0, "a seeded launch took \(elapsed)s to show a row")
    }

    /// L6 — the reset lives inside the request. A launch that asks for nothing deletes nothing,
    /// so a developer's own DEBUG build with their own imported statements is safe (FR-022).
    func testANonSeededLaunchAfterASeededOneDeletesNothing() {
        _ = SeededLaunch.launch(scenario: .small)

        let app = SeededLaunch.launch(scenario: nil)

        guard let account = SeedScenario.small.expectedAccounts.first else {
            return XCTFail("the small scenario declares no account")
        }
        XCTAssertTrue(
            SeededLaunch.element(app, labelled: account.announcement).waitForExistence(timeout: 10),
            "the store the previous launch wrote is gone")
        // The route to the list is back for the same reason: the rows are still there.
        XCTAssertTrue(app.buttons["All transactions"].exists)
    }
}
