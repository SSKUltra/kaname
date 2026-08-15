import XCTest

/// The accessibility audit the front door has to pass on a real simulator: clipped text,
/// elements too small to hit, contrast that fails, and controls VoiceOver cannot name are all
/// found by the system's own auditor rather than by a person remembering to look.
///
/// It covers the screens a launch reaches — the empty state and the import action. The
/// screens behind an import (summary, failure, password, account picker) would need the app
/// to carry test-only entry points to reach from here, so their copy and labels are pinned in
/// `ios/Tests/ImportAccessibilityTests.swift` and their appearance by the manual gate in the
/// feature's quickstart.
///
/// **Increase Contrast is the one axis no test here can set** — there is no XCUITest API for
/// it, and it is read from the accessibility daemon rather than from `UserDefaults`, so a
/// launch argument will not do it either. `make a11y-sweep` sets it with `simctl` and runs
/// this suite underneath. Reduce Transparency has neither, and stays with the manual gate.
final class ImportFrontDoorUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTheFrontDoorPassesTheSystemAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        try app.performAccessibilityAudit { issue in
            print(
                "AUDIT ISSUE type=\(issue.auditType) detail=\(issue.detailedDescription) "
                    + "element=\(String(describing: issue.element))"
            )
            return false
        }
    }

    func testTheFrontDoorSurvivesTheLargestAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        // At this size clipped text and unreachable controls are what break first, so the
        // audit is worth more here than anywhere else.
        try auditIgnoringContrastOverUnrenderedArea(app)
    }

    /// Dark Mode is its own contrast problem, not a repaint of the light one: the accent has
    /// to clear the threshold against a dark background too, and it is a different ratio.
    func testTheFrontDoorPassesTheAuditInDarkMode() throws {
        let previous = XCUIDevice.shared.appearance
        XCUIDevice.shared.appearance = .dark
        addTeardownBlock { XCUIDevice.shared.appearance = previous }

        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        try app.performAccessibilityAudit { issue in
            print(
                "AUDIT ISSUE type=\(issue.auditType) detail=\(issue.detailedDescription) "
                    + "element=\(String(describing: issue.element))"
            )
            return false
        }
    }

    /// Dark Mode *and* the largest text at once — the combination, because each one alone
    /// passing says nothing about the layout the other produces.
    func testTheFrontDoorPassesTheAuditInDarkModeAtTheLargestTextSize() throws {
        let previous = XCUIDevice.shared.appearance
        XCUIDevice.shared.appearance = .dark
        addTeardownBlock { XCUIDevice.shared.appearance = previous }

        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        try auditIgnoringContrastOverUnrenderedArea(app)
    }

    // MARK: - The one verdict this suite does not accept

    /// Run the audit, ignoring **contrast** issues raised against an element that extends
    /// beyond the window — because the auditor then measures pixels that were never drawn.
    ///
    /// This is a suppression, and suppressions are how an audit stops meaning anything, so it
    /// is deliberately narrow and it was **proved rather than assumed** (016 issue 01):
    ///
    /// 1. The failing element is the front door's explanation. At
    ///    `AccessibilityXXXL` it is 621 pt tall with its top at y=467 — on an 852 pt screen, so
    ///    236 pt of it is below the bottom of the display.
    /// 2. It fails in **both** appearances, which a colour problem would not do.
    /// 3. Dropping one text size to `AccessibilityXL` — **same colours, same layout, same
    ///    everything but the height** — makes both tests pass. Height is the only variable.
    /// 4. A screenshot of the failing state shows white text on black, unfaded: the visible
    ///    pixels measure about 21:1, an order of magnitude clear of the 4.5:1 threshold.
    ///
    /// Two things keep it honest. It applies only to `.contrast`, so a clipped label or an
    /// unlabelled control at the largest size still fails. And it applies only to the two
    /// largest-text tests: `testTheFrontDoorPassesTheSystemAccessibilityAudit` and
    /// `testTheFrontDoorPassesTheAuditInDarkMode` audit with **no** suppression at all, so a
    /// genuine contrast regression at ordinary sizes has nowhere to hide.
    ///
    /// ⚠️ If the copy ever shrinks enough to fit, this stops firing on its own — and every
    /// ignored issue is printed, so a screen quietly relying on it is visible in the log.
    private func auditIgnoringContrastOverUnrenderedArea(_ app: XCUIApplication) throws {
        let window = app.windows.firstMatch.frame
        try app.performAccessibilityAudit { issue in
            let frame = issue.element?.frame
            let overflows = frame.map { !window.contains($0) } ?? false
            let ignored = issue.auditType == .contrast && overflows

            print(
                "AUDIT ISSUE\(ignored ? " (ignored: measured outside the window)" : "") "
                    + "type=\(issue.auditType) detail=\(issue.detailedDescription) "
                    + "element=\(String(describing: issue.element))"
            )
            return ignored
        }
    }

    func testTheImportActionIsOneTapFromLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        let importButton = app.buttons["Import a statement"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 10))
        XCTAssertTrue(importButton.isHittable)
    }

    /// ⚠️ **The transaction list cannot be reached by an automated run at all** — and this test
    /// is the proof of that, rather than an audit of the list.
    ///
    /// T118 asked for the unfiltered list to be pushed from a fresh install via the toolbar
    /// item and audited. It cannot be: the toolbar item is shown only once at least one
    /// account exists (`RootView`), an account exists only once a real statement has been
    /// imported, and importing requires the system document picker, which no automated run can
    /// drive. Closing that gap would take a DEBUG-only seeding hook, which FR-077 forbids
    /// outright — a test-only path into a person's financial data is exactly the thing that
    /// must not exist.
    ///
    /// So what is asserted here is the reachability fact itself, in both appearances and at
    /// the largest text size: a launch with nothing imported offers the import action and
    /// **not** a link to an empty list. The transaction list's own appearance stays on the
    /// manual gate (SC-012, FR-075, FR-076), where the quickstart walks it.
    func testAFreshInstallOffersNoRouteToAnEmptyTransactionList() throws {
        for appearance in [XCUIDevice.Appearance.light, .dark] {
            let previous = XCUIDevice.shared.appearance
            XCUIDevice.shared.appearance = appearance
            addTeardownBlock { XCUIDevice.shared.appearance = previous }

            let app = XCUIApplication()
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

            XCTAssertTrue(app.buttons["Import a statement"].waitForExistence(timeout: 10))
            // The list is one list and an account is a filter on it — but with nothing
            // imported there is nothing to filter, and the front door says so itself.
            XCTAssertFalse(app.buttons["All transactions"].exists)
            XCTAssertFalse(app.navigationBars["Transactions"].exists)
        }
    }
}
