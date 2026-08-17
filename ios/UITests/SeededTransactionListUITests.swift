import XCTest

/// The first suite in this repository that sees a transaction.
///
/// Every accessibility audit before it ran against an empty screen, because the list is behind
/// an import, the import is behind the system document picker, and no automated run can drive
/// that picker. A DEBUG-only seeded launch is what closes the gap — and the assertions here are
/// made through XCUITest only: no model is constructed, no row is injected, and nothing stands
/// between the store and the screen (FR-015).
final class SeededTransactionListUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        // Stated rather than inherited: the appearance is a simulator-wide setting, and an
        // audit that does not say which one it wants audits the last one somebody left behind.
        SeededLaunch.pin(.light, in: self)
    }

    override func tearDown() {
        SeededLaunch.resetContainer()
        super.tearDown()
    }

    /// S1 — the list is reached from the front door's own toolbar control. There is no
    /// test-only screen, deep link or alternate root, and this is the assertion that says so.
    func testTheListIsReachedFromTheFrontDoorTheWayAPersonReachesIt() {
        let app = SeededLaunch.launch(scenario: .small)

        SeededLaunch.openTransactionList(app)

        XCTAssertTrue(app.navigationBars["Transactions"].exists)
    }

    /// S2 — the screen's rows, the fixture's declaration and the engine's own count are three
    /// readings of one number, and they agree.
    func testTheRowCountMatchesTheDeclarationAndTheEnginesOwnCount() {
        let scenario = SeedScenario.small
        let app = SeededLaunch.launch(scenario: scenario)

        for account in scenario.expectedAccounts {
            XCTAssertTrue(
                SeededLaunch.element(app, labelled: account.announcement).waitForExistence(timeout: 10),
                "the front door does not report \(account.announcement)")
        }

        SeededLaunch.openTransactionList(app)

        XCTAssertEqual(SeededLaunch.allRowLabels(app).count, scenario.expectedLiveRowCount)
    }

    /// S3 — every declared live row is on screen, matched on the whole sentence a screen reader
    /// speaks: date with year, description, amount with its own currency, direction in words,
    /// account identity and category. And nothing that was superseded is there.
    func testEverySeededRowIsOnScreenExactlyAsDeclared() {
        let scenario = SeedScenario.small
        let app = SeededLaunch.launch(scenario: scenario)
        SeededLaunch.openTransactionList(app)

        let onScreen = Set(SeededLaunch.allRowLabels(app))
        for row in scenario.expectedLiveRows {
            XCTAssertTrue(
                onScreen.contains(row.accessibilityLabel),
                "missing row: \(row.accessibilityLabel)\non screen: \(onScreen.sorted())")
        }
        for row in scenario.expectedSupersededRows {
            XCTAssertFalse(
                onScreen.contains(row.accessibilityLabel),
                "a superseded row is on screen: \(row.accessibilityLabel)")
        }
    }

    /// A1 — the system's own auditor over a **populated** list, at the default text size in
    /// Light. The one thing 018 could never run.
    ///
    /// ⚠️ **It audits every type except `.contrast`, and that exclusion is a recorded finding,
    /// not a convenience** (`.scratch/019-debug-test-seeding/issues/01`). The first run of this
    /// audit found three things: a date heading rendering grey because `.foregroundStyle
    /// (.primary)` is the *hierarchical* style and resolved to a no-op; a heading with nothing
    /// behind it where the rows scroll under; and four `Contrast failed` verdicts that **no
    /// element is attached to**. The first two are fixed. The third could not be attributed:
    /// removing the bottom filter bar removes every one of them, the bar's own text measures
    /// **9.48:1** on the audit's own screenshot (`#134E4A` on `#FFFFFF`, computed from the
    /// pixels), and changing that text's colour changes nothing — so the verdict is about the
    /// glass the system draws, not about a colour this app chose.
    ///
    /// A suppression was rejected on purpose. Every contrast issue on this screen arrives with
    /// `element == nil`, **including the real heading defect above**, so an "ignore the ones it
    /// cannot name" rule would have hidden the very defect that proved this audit was worth
    /// running. Excluding the type outright is the honest half-measure: `.textClipped`,
    /// `.dynamicType`, `.elementDetection`, `.hitRegion`, `.sufficientElementDescription` and
    /// `.trait` all still run, and the contrast question goes to PR C's T074, which is already
    /// the task for deciding what this instrument can and cannot see.
    func testThePopulatedListPassesTheSystemAccessibilityAudit() throws {
        let app = SeededLaunch.launch(scenario: .small)
        SeededLaunch.openTransactionList(app)
        XCTAssertFalse(
            SeededLaunch.rowLabels(app).isEmpty, "the audit would be running against an empty list")

        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.contrast)) { issue in
            print(
                "AUDIT ISSUE type=\(issue.auditType) detail=\(issue.detailedDescription) "
                    + "element=\(String(describing: issue.element))"
            )
            return false
        }
    }
}
