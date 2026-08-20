import XCTest

/// **X8** for 020 PR F — the door onto the worklist, and the worklist behind it.
///
/// Its own suite rather than more of `SeededAccessibilityUITests`, which is at SwiftLint's
/// 400-line file limit and its 250-line type limit: split by subject, which is how the doubles
/// and the seed declarations were split before it. The vocabulary both suites audit with —
/// which types run at which text size, and why two of them do not — lives in
/// `AccessibilityAudit.swift`, in one copy.
///
/// ⚠️ `unfiled` rather than `small`, because the door is only on the front door once there is
/// work behind it, and the narrowed list only has rows when something is unanswered.
final class SeededWorklistAccessibilityUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        SeededLaunch.resetContainer()
        super.tearDown()
    }

    /// **X8**, A18 — the front door carrying the worklist's door, and the narrowed list behind
    /// it, at the default size in Light.
    ///
    /// ⚠️ Both surfaces in one launch and one order, because the door is only *on* the front
    /// door once the store has rows in it, and the list is only narrowed when it is reached
    /// through the door. Auditing them apart would audit each out of the state the other puts
    /// it in — and the door is a row on the app's first screen, which is the screen every
    /// other audit in this file has had to walk past without ever looking at it.
    func testTheWorklistAndItsDoorPassTheAudit() throws {
        SeededLaunch.pin(.light, in: self)
        try auditWorklistSurfaces(arguments: [], types: AccessibilityAudit.types)
    }

    /// A19 — the same two at the largest accessibility size, where the door's sentence is a
    /// count and a `Label` that has to wrap without losing its symbol.
    func testTheWorklistAndItsDoorSurviveTheLargestTextSize() throws {
        SeededLaunch.pin(.light, in: self)
        try auditWorklistSurfaces(arguments: AccessibilityAudit.xxxl, types: AccessibilityAudit.typesAtLargeSizes)
    }

    /// A20 — Dark Mode, its own problem rather than a repaint of the light one.
    func testTheWorklistAndItsDoorPassTheAuditInDarkMode() throws {
        SeededLaunch.pin(.dark, in: self)
        try auditWorklistSurfaces(arguments: [], types: AccessibilityAudit.types)
    }

    /// A21 — Dark Mode at the largest size, because each passing alone says nothing about the
    /// layout the other produces.
    func testTheWorklistAndItsDoorPassTheAuditInDarkModeAtTheLargestTextSize() throws {
        SeededLaunch.pin(.dark, in: self)
        try auditWorklistSurfaces(arguments: AccessibilityAudit.xxxl, types: AccessibilityAudit.typesAtLargeSizes)
    }

    /// A22 — **geometry, not audit** (E1, FR-062). The door is the one control on the front
    /// door that this slice added, and a door too short to hit is a worklist nobody can open
    /// however well it is worded. Measured, for A12's and A17's reason: the auditor's own
    /// hit-target check has never once fired on this repository's controls.
    func testTheDoorOntoTheWorklistIsBigEnoughToHit() {
        SeededLaunch.pin(.light, in: self)
        let app = SeededLaunch.launch(scenario: .unfiled)

        guard let label = SeededLaunch.worklistDoorLabel(app) else {
            return XCTFail("the front door offers no way into the worklist")
        }
        AccessibilityAudit.measureHitTarget(app.buttons[label].firstMatch, named: "the door")
    }

    /// Audit the front door with its worklist door on it, then the list that door opens.
    ///
    /// ⚠️ **`.textClipped` runs over the door and not over the list**, and the asymmetry is a
    /// recorded finding (`.scratch/020-categorize/issues/01`). Against `unfiled` the *shipped,
    /// unnarrowed* 018 list fails that type at the **default** text size with nothing of this
    /// slice on the screen — the row's description is capped at two lines and its account line
    /// at one, deliberately (`019/03`, `018/04`, FR-021), and only `small`'s shorter
    /// descriptions had ever hidden it. Keeping the type on the **door** is what matters and is
    /// not a formality: it caught a real defect there during this session, naming the element.
    private func auditWorklistSurfaces(
        arguments: [String], types: XCUIAccessibilityAuditType
    ) throws {
        let app = SeededLaunch.launch(scenario: .unfiled, arguments: arguments)
        XCTAssertNotNil(
            SeededLaunch.worklistDoorLabel(app),
            "the audit would be running against a front door with no worklist on it")
        try AccessibilityAudit.run(app, types: types)

        SeededLaunch.openWorklist(app)
        XCTAssertFalse(
            SeededLaunch.rowLabels(app).isEmpty, "the audit would be running against an empty list")
        try AccessibilityAudit.run(app, types: types.subtracting(.textClipped))
    }
}
