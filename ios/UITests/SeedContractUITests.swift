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
        // purpose: **only** the report that the app is gone is absorbed, so the assertion below
        // is still a real assertion. Without it, an expectation covering the rest of the test
        // would swallow the very verdict this test exists to reach.
        //
        // 🚨 **Two spellings, one event** (`.scratch/020-categorize/issues/04`). Which one arrives
        // depends on how far the launch got before the runner noticed: normally
        // `… crashed in <external symbol>`, but on a slow runner the app can die before the
        // automation session ever gets a background assertion for it, and the report is then
        // `Failed to get background assertion for target app with pid N`. Matching only "crashed"
        // made this test flaky on CI — red at 37m42s, green on re-run of the identical commit.
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        options.issueMatcher = { issue in
            let text = issue.compactDescription
            return text.contains("crashed")
                || text.contains("Failed to get background assertion")
        }
        XCTExpectFailure("an unrecognised scenario must fail the launch", options: options)
        app.launch()

        XCTAssertNotEqual(app.state, .runningForeground)
    }

    /// L5 / SC-009 — a seeded launch reaches the populated list quickly, and the thing actually
    /// measured is **the seed's own cost**.
    ///
    /// ⚠️ **Two corrections, both from a red gate** (`019/issues/04`).
    ///
    /// The first version asserted a bare wall clock — launch to first row, under five seconds.
    /// It measured **4.65 s** in an ordinary gate run and **7.98 s** in `make a11y-sweep`, where
    /// the same code runs eleven minutes into a loaded machine: same build, same six rows, a 70%
    /// spread. That is the `history_perf::s5` lesson one language over.
    ///
    /// The second version compared it against an unseeded launch — right idea, wrong endpoints.
    /// It timed the seeded run all the way to a **row on the list**, so the difference carried a
    /// navigation push and an element query as well as the seed, and on CI's slower runner it
    /// came to `3.0005640983581543` against a 3.0 bound. **Failing by six ten-thousandths of a
    /// second is not a measurement, it is a coin toss.**
    ///
    /// So both launches are now timed to **the same screen** — the front door, ready — and the
    /// difference is the seed and nothing else: one of them had to write a history first. That
    /// is what SC-009 is about, and it is the number that grows if a scenario grows. The whole
    /// journey to a row is still measured and still asserted, but generously: it is there to
    /// catch a collapse, not to police a millisecond.
    func testSeedingDoesNotMakeTheLaunchSlow() {
        guard let account = SeedScenario.small.expectedAccounts.first,
            let first = SeedScenario.small.expectedLiveRows.first
        else { return XCTFail("the small scenario declares no account or no row") }

        // Launch to a ready front door, with nothing to write.
        let baselineStart = Date()
        let unseeded = SeededLaunch.launch(scenario: nil)
        XCTAssertTrue(unseeded.buttons["Import a statement"].waitForExistence(timeout: 30))
        let baseline = Date().timeIntervalSince(baselineStart)
        unseeded.terminate()

        // Launch to a ready front door again — same screen, same query — having written a
        // six-row history through `Store.importStatement` on the way.
        let seededStart = Date()
        let app = SeededLaunch.launch(scenario: .small)
        XCTAssertTrue(
            SeededLaunch.element(app, labelled: account.announcement).waitForExistence(timeout: 30))
        let toFrontDoor = Date().timeIntervalSince(seededStart)

        app.buttons["All transactions"].tap()
        XCTAssertTrue(
            SeededLaunch.element(app, labelled: first.accessibilityLabel).waitForExistence(timeout: 30))
        let toFirstRow = Date().timeIntervalSince(seededStart)

        print(
            "seed-timing: unseeded launch \(String(format: "%.2f", baseline))s, "
                + "seeded launch \(String(format: "%.2f", toFrontDoor))s "
                + "(the seed itself \(String(format: "%.2f", toFrontDoor - baseline))s), "
                + "and on to the first row \(String(format: "%.2f", toFirstRow))s")
        XCTAssertLessThan(
            toFrontDoor - baseline, 3.0,
            "seeding cost \(toFrontDoor - baseline)s over an unseeded launch of the same screen")
        // ⚠️ **Relative to the machine, never absolute** (`.scratch/020-categorize/issues/05`).
        //
        // This was `XCTAssertLessThan(toFirstRow, 20.0)` and it went red on CI at **20.21 s** —
        // by 1%, on a run where the seed itself cost **0.45 s** of its 3 s budget. The bound was
        // failing on a number that is almost entirely the machine: 6.93 s of cold simulator
        // start, plus a tap-to-row leg dominated by XCUITest's own full-tree query.
        //
        // The ratio is measured, not guessed: **1.22 on a developer's machine, 2.92 on the CI
        // runner that failed**. `K` is 5, which clears the worst observed by 71%.
        //
        // 🚨 **The real collapse detector is the `waitForExistence(timeout: 30)` above**, which
        // fails on its own if a row never arrives. This bound only covers the narrow band between
        // "degrading" and "gone", so it is deliberately generous: it is here to notice a journey
        // sliding toward that timeout, not to police a duration.
        XCTAssertLessThan(
            toFirstRow, baseline * 5,
            "a seeded launch took \(toFirstRow)s to show a row, against an unseeded launch of "
                + "\(baseline)s for the same machine — a ratio of \(toFirstRow / baseline)")
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
