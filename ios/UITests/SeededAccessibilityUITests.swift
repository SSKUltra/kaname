import XCTest

/// The audits 018 could never run, and the two geometry facts an auditor cannot check.
///
/// ⚠️ **Every audit here excludes `.contrast`, and that is a recorded finding rather than a
/// convenience** — `.scratch/019-debug-test-seeding/issues/01`. The first audit of a populated
/// list found two real defects (both fixed) and three `Contrast failed` verdicts that name no
/// element at all; a suppression was rejected because the real defect *also* named no element,
/// so a rule ignoring the unattributable ones would have hidden the finding that proved the
/// audit worth running. Every other audit type runs, including `.textClipped`.
///
/// ⚠️ **`ImportFrontDoorUITests.auditIgnoringContrastOverUnrenderedArea` is deliberately not
/// used here.** It is a narrow suppression, proved in four recorded steps, about the front
/// door's explanation text extending past the bottom of the window. A list scrolls, so its rows
/// are inside the window, and copying it by reflex is how a suppression stops meaning anything.
final class SeededAccessibilityUITests: XCTestCase {
    private static let xxxl = [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    /// What is audited at the **default** text size: everything the instrument can be trusted
    /// on. Only `.contrast` is excluded, and `issues/01` says why.
    private let audited = XCUIAccessibilityAuditType.all.subtracting(.contrast)

    /// What is audited at **accessibility** sizes.
    ///
    /// ⚠️ Two more types come off here, and both are recorded findings rather than
    /// convenience (`.scratch/019-debug-test-seeding/issues/03`). At `AccessibilityXXXL` the
    /// shipping row fires `.textClipped` and `.dynamicType` **by design**: `TransactionRowLayout`
    /// caps the account line at one line so that the masked digits — the only part that tells
    /// two cards of one product apart — survive the truncation
    /// (`.scratch/018-transaction-list/issues/04`), and the amount is `fixedSize` because it may
    /// never yield (FR-021). The auditor is right that the text clips; the app decided that it
    /// should. Neither verdict carries an element, so neither can be scoped, and excluding them
    /// **costs this suite the instrument FR-038 wanted for `018/02`** — which is why that defect
    /// is caught by `testTheFilterChipStatesItsWholeScopeAtTheLargestTextSize` instead, a
    /// sharper instrument that reads what was actually drawn. What still runs at XXXL is what
    /// XXXL actually breaks: elements that vanish, controls too small to hit, and controls a
    /// screen reader cannot name.
    private let auditedAtLargeSizes = XCUIAccessibilityAuditType.all
        .subtracting(.contrast)
        .subtracting(.textClipped)
        .subtracting(.dynamicType)

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        SeededLaunch.resetContainer()
        super.tearDown()
    }

    /// A2 — the largest accessibility text size, in Light. Where clipped text and unreachable
    /// controls break first.
    func testThePopulatedListSurvivesTheLargestTextSize() throws {
        SeededLaunch.pin(.light, in: self)
        try auditPopulatedList(arguments: Self.xxxl, types: auditedAtLargeSizes)
    }

    /// A3 — Dark Mode is its own problem, not a repaint of the light one.
    func testThePopulatedListPassesTheAuditInDarkMode() throws {
        SeededLaunch.pin(.dark, in: self)
        try auditPopulatedList(arguments: [], types: audited)
    }

    /// A4 — both at once, because each one passing alone says nothing about the layout the
    /// other produces.
    func testThePopulatedListPassesTheAuditInDarkModeAtTheLargestTextSize() throws {
        SeededLaunch.pin(.dark, in: self)
        try auditPopulatedList(arguments: Self.xxxl, types: auditedAtLargeSizes)
    }

    /// A5 — the state `.scratch/018-transaction-list/issues/02` failed in: a filter applied, at
    /// the largest accessibility size, where the masked digits and the clear button between
    /// them want more width than the screen has.
    func testTheFilteredListPassesTheAuditAtTheLargestTextSize() throws {
        SeededLaunch.pin(.light, in: self)
        let scenario = SeedScenario.small
        let app = SeededLaunch.launch(scenario: scenario, arguments: Self.xxxl)
        SeededLaunch.openTransactionList(app)
        guard let account = scenario.expectedAccounts.first else {
            return XCTFail("small declares no account")
        }
        SeededLaunch.filter(app, to: account)

        try audit(app, types: auditedAtLargeSizes)
    }

    /// **A5b — the sharper instrument**, and the one that actually catches
    /// `.scratch/018-transaction-list/issues/02`.
    ///
    /// That defect shipped a chip reading `•••• 77…` at `AccessibilityXXXL`: the bar stayed
    /// horizontal, the mask and the collapsed clear button between them wanted ~420 pt of a
    /// 393 pt screen, and the digits were what lost. **Every unit test in the repository passed
    /// against it** — they prove which fact *leads*, and it did; a pure layout decision cannot
    /// see a width. What catches it is reading what was drawn: the chip publishes its rendered
    /// lines as child elements, so the whole mask and the whole account name can be compared
    /// with the declaration, and an ellipsis in either is a truncation nobody has to interpret.
    ///
    /// The width assertion is the same fact from the other side: at accessibility sizes the bar
    /// is a `VStack` precisely so the chip gets the screen, and a chip squeezed into half of it
    /// is the defect by another name.
    func testTheFilterChipStatesItsWholeScopeAtTheLargestTextSize() {
        SeededLaunch.pin(.light, in: self)
        let scenario = SeedScenario.small
        let app = SeededLaunch.launch(scenario: scenario, arguments: Self.xxxl)
        SeededLaunch.openTransactionList(app)
        guard let account = scenario.expectedAccounts.first, let last4 = account.last4 else {
            return XCTFail("small declares no account, or one with no masked digits")
        }
        SeededLaunch.filter(app, to: account)

        let chip = SeededLaunch.scopeChip(app)
        let rendered = chip.staticTexts.allElementsBoundByIndex.map(\.label)
        // The mask's shape is the shipped copy (`TransactionListStrings.maskedLast4`); the
        // digits and the name come from the declaration.
        XCTAssertTrue(
            rendered.contains("•••• \(last4)"),
            "the chip does not show the whole mask: \(rendered)")
        XCTAssertTrue(
            rendered.contains(account.name),
            "the chip does not show the whole account name: \(rendered)")
        for line in rendered {
            XCTAssertFalse(line.contains("…"), "the chip truncated a line: \(line)")
        }

        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(
            chip.frame.width, window.width * 0.6,
            "the chip has less than two thirds of the width at an accessibility size, "
                + "so the bar did not go vertical: chip \(chip.frame), window \(window)")
    }

    /// A7 — **geometry, not audit.** The iOS auditor's seven types contain no occlusion check,
    /// so nothing it reports can tell you a row is underneath the bottom bar
    /// (`.scratch/018-transaction-list/issues/03`). This measures it.
    ///
    /// The bar's own frame is not queryable, so the **scope chip** stands in for its top edge.
    /// That is a generous proxy — the bar's padding sits above the chip — so this assertion can
    /// be falsely green but never falsely red, and the break it exists for (an unbounded bar)
    /// moves the chip up along with everything else.
    func testTheLastRowClearsTheFilterBarAtTheLargestTextSize() {
        SeededLaunch.pin(.light, in: self)
        let scenario = SeedScenario.small
        let app = SeededLaunch.launch(scenario: scenario, arguments: Self.xxxl)
        SeededLaunch.openTransactionList(app)
        guard let account = scenario.expectedAccounts.first,
            let last = scenario.expectedLiveRows.last
        else { return XCTFail("small declares no account or no row") }
        SeededLaunch.filter(app, to: account)

        let walk = SeededLaunch.walk(app)
        print("seed-shape: small at XXXL reached its last row in \(walk.swipes) swipes")
        guard let bottom = walk.rows.last else {
            return XCTFail("no row rendered at all")
        }

        // The geometry first, and against the **bottom-most row the list would show**, not the
        // one the declaration ends with: a bar that has eaten the end of the list leaves a
        // different row down there, and this assertion should describe the screen either way.
        let lastRow = SeededLaunch.element(app, labelled: bottom)
        let chip = SeededLaunch.scopeChip(app)
        XCTAssertTrue(chip.exists, "the filter chip is not on screen")
        XCTAssertLessThanOrEqual(
            lastRow.frame.maxY, chip.frame.minY,
            "a row is underneath the filter bar: row \(lastRow.frame), chip \(chip.frame)")
        // And then the other half of the same promise: scrolling can actually reach the end.
        // A bar with no bound on its height fails this one first, because the rows it covers
        // can never be scrolled clear of it.
        XCTAssertEqual(
            walk.rows.count, scenario.expectedLiveRowCount,
            "the end of the list is unreachable — the bar has taken the room to scroll into")
        XCTAssertEqual(bottom, last.accessibilityLabel)
    }

    /// A8 — the heading a person lands on carries its year, because a row read out of reach of
    /// its heading is a date without one. `small`'s six days sit in a prior calendar year for
    /// exactly this assertion (018 FR-035, gate G4).
    func testTheFirstGroupHeadingCarriesItsYear() {
        SeededLaunch.pin(.light, in: self)
        let scenario = SeedScenario.small
        let app = SeededLaunch.launch(scenario: scenario)
        SeededLaunch.openTransactionList(app)

        guard let expected = scenario.expectedGroupAnnouncements.first else {
            return XCTFail("small declares no date group")
        }
        XCTAssertTrue(expected.contains("2025"), "the fixture's own dates are not in a prior year")
        XCTAssertTrue(
            SeededLaunch.element(app, labelled: expected).waitForExistence(timeout: 10),
            "the first heading is not \(expected)")
    }

    // MARK: - 020 — the surfaces a person changes a category on

    /// A9 — the transaction surface and the picker, at the default size in Light.
    func testTheTransactionSurfaceAndPickerPassTheAudit() throws {
        SeededLaunch.pin(.light, in: self)
        try auditCategorizeSurfaces(arguments: [], types: audited)
    }

    /// A10 — the same two surfaces at the largest accessibility size, where a picker of two
    /// dozen categories and a surface of four facts each have to survive the text growing.
    func testTheTransactionSurfaceAndPickerSurviveTheLargestTextSize() throws {
        SeededLaunch.pin(.light, in: self)
        try auditCategorizeSurfaces(arguments: Self.xxxl, types: auditedAtLargeSizes)
    }

    /// A11 — and in Dark Mode, which is its own problem rather than a repaint of the light one.
    func testTheTransactionSurfaceAndPickerPassTheAuditInDarkMode() throws {
        SeededLaunch.pin(.dark, in: self)
        try auditCategorizeSurfaces(arguments: [], types: audited)
    }

    /// A12 — **geometry, not audit** (K7, R4, FR-062). The auditor's own hit-target check has
    /// never fired on this repository's controls, and a category row that is too short to hit
    /// is a control a person cannot use however well it is labelled. Measured on the row a
    /// person taps most: the deliberate blank, which is the first thing the picker offers.
    func testEveryPickerChoiceIsBigEnoughToHit() {
        SeededLaunch.pin(.light, in: self)
        let app = SeededLaunch.launch(scenario: .small)
        SeededLaunch.openTransactionList(app)
        Self.openPicker(app)

        // ⚠️ Matched by prefix. The blank's spoken label carries its mark when it *is* the
        // current choice — "No category, Current category" — and a seeded row is unfiled, so
        // an exact match finds nothing and reads as a missing control.
        let blank = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "No category")
        ).firstMatch
        XCTAssertTrue(blank.waitForExistence(timeout: 10), "the picker does not offer the blank")
        XCTAssertGreaterThanOrEqual(blank.frame.height, 44, "a choice is too short to hit")
        XCTAssertGreaterThanOrEqual(blank.frame.width, 44, "a choice is too narrow to hit")
    }

    /// Open a transaction, then the picker over it, and audit both — one launch, because the
    /// picker is only reachable through the surface and auditing them apart would audit the
    /// second one out of the state the first one puts it in.
    private func auditCategorizeSurfaces(
        arguments: [String], types: XCUIAccessibilityAuditType
    ) throws {
        let app = SeededLaunch.launch(scenario: .small, arguments: arguments)
        SeededLaunch.openTransactionList(app)

        guard let row = Self.firstRowLink(app) else {
            return XCTFail("the audit would be running against an empty list")
        }
        row.tap()
        XCTAssertTrue(
            app.navigationBars["Transaction"].waitForExistence(timeout: 10),
            "the transaction surface did not open")
        try audit(app, types: types)

        Self.openPicker(app)
        try audit(app, types: types)
    }

    private static func openPicker(_ app: XCUIApplication) {
        if !app.navigationBars["Transaction"].exists, let row = firstRowLink(app) {
            row.tap()
            _ = app.navigationBars["Transaction"].waitForExistence(timeout: 10)
        }
        // ⚠️ Scrolled to at accessibility sizes. FR-004 asks for the action to be reachable
        // **without scrolling at the default text size**, which it is; at XXXL four facts and
        // a category take the screen, and a test that refused to scroll would be asserting a
        // requirement nobody made.
        let change = app.buttons["Change category"].firstMatch
        if !change.waitForExistence(timeout: 5) || !change.isHittable {
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(change.waitForExistence(timeout: 10), "the surface offers no way to change")
        change.tap()
        XCTAssertTrue(
            app.navigationBars["Choose a category"].waitForExistence(timeout: 10),
            "the picker did not open")
    }

    /// The first row, as the link it now is — the sentence hangs on the button inside the cell.
    private static func firstRowLink(_ app: XCUIApplication) -> XCUIElement? {
        for cell in app.cells.allElementsBoundByIndex {
            if let link = cell.buttons.allElementsBoundByIndex.first, !link.label.isEmpty {
                return link
            }
        }
        return nil
    }

    private func auditPopulatedList(arguments: [String], types: XCUIAccessibilityAuditType) throws {
        let app = SeededLaunch.launch(scenario: .small, arguments: arguments)
        SeededLaunch.openTransactionList(app)
        XCTAssertFalse(
            SeededLaunch.rowLabels(app).isEmpty, "the audit would be running against an empty list")
        try audit(app, types: types)
    }

    private func audit(_ app: XCUIApplication, types: XCUIAccessibilityAuditType) throws {
        try app.performAccessibilityAudit(for: types) { issue in
            print(
                "AUDIT ISSUE type=\(issue.auditType) detail=\(issue.detailedDescription) "
                    + "element=\(String(describing: issue.element))"
            )
            return false
        }
    }
}
