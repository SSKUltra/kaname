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
        try app.performAccessibilityAudit { issue in
            print(
                "AUDIT ISSUE type=\(issue.auditType) detail=\(issue.detailedDescription) "
                    + "element=\(String(describing: issue.element))"
            )
            return false
        }
    }

    func testTheImportActionIsOneTapFromLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        let importButton = app.buttons["Import a statement"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 10))
        XCTAssertTrue(importButton.isHittable)
    }
}
