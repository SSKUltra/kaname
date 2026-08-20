import XCTest

/// What every seeded accessibility audit in this bundle runs, and what it deliberately does
/// not — in one place, because an exclusion that is worth a paragraph is worth exactly one
/// paragraph.
///
/// It was extracted from `SeededAccessibilityUITests` when a second suite needed the same
/// vocabulary. Copying the two type sets into that suite would have been the drift this
/// repository keeps finding: the day one exclusion is narrowed, the other copy still has it.
enum AccessibilityAudit {
    /// The largest accessibility text size, as launch arguments.
    static let xxxl = [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]

    /// What is audited at the **default** text size: everything the instrument can be trusted
    /// on. Only `.contrast` is excluded.
    ///
    /// ⚠️ That exclusion is a recorded finding rather than a convenience —
    /// `.scratch/019-debug-test-seeding/issues/01`. The first audit of a populated list found
    /// two real defects (both fixed) and three `Contrast failed` verdicts that name no element
    /// at all; a suppression was rejected because the real defect *also* named no element, so a
    /// rule ignoring the unattributable ones would have hidden the finding that proved the
    /// audit worth running. Every other audit type runs, including `.textClipped`.
    static let types = XCUIAccessibilityAuditType.all.subtracting(.contrast)

    /// What is audited at **accessibility** sizes.
    ///
    /// ⚠️ Two more types come off here, and both are recorded findings rather than convenience
    /// (`.scratch/019-debug-test-seeding/issues/03`). At `AccessibilityXXXL` the shipping row
    /// fires `.textClipped` and `.dynamicType` **by design**: `TransactionRowLayout` caps the
    /// account line at one line so that the masked digits — the only part that tells two cards
    /// of one product apart — survive the truncation
    /// (`.scratch/018-transaction-list/issues/04`), and the amount is `fixedSize` because it
    /// may never yield (FR-021). The auditor is right that the text clips; the app decided that
    /// it should. Neither verdict carries an element, so neither can be scoped, and excluding
    /// them **costs this bundle the instrument FR-038 wanted for `018/02`** — which is why that
    /// defect is caught by `testTheFilterChipStatesItsWholeScopeAtTheLargestTextSize` instead, a
    /// sharper instrument that reads what was actually drawn. What still runs at XXXL is what
    /// XXXL actually breaks: elements that vanish, controls too small to hit, and controls a
    /// screen reader cannot name.
    static let typesAtLargeSizes = XCUIAccessibilityAuditType.all
        .subtracting(.contrast)
        .subtracting(.textClipped)
        .subtracting(.dynamicType)

    /// ⚠️ **`ImportFrontDoorUITests.auditIgnoringContrastOverUnrenderedArea` is deliberately not
    /// used by any seeded audit.** It is a narrow suppression, proved in four recorded steps,
    /// about the front door's explanation text extending past the bottom of the window. A list
    /// scrolls, so its rows are inside the window, and copying it by reflex is how a suppression
    /// stops meaning anything.
    static func run(
        _ app: XCUIApplication, types: XCUIAccessibilityAuditType
    ) throws {
        try app.performAccessibilityAudit(for: types) { issue in
            print(
                "AUDIT ISSUE type=\(issue.auditType) detail=\(issue.detailedDescription) "
                    + "element=\(String(describing: issue.element))"
            )
            return false
        }
    }

    /// A control big enough for a person to hit, measured rather than audited.
    ///
    /// ⚠️ **The auditor's own hit-target check has never once fired on this repository's
    /// controls**, and it stayed green through a real 34.33 pt defect at the default text size
    /// (020 PR E, A17). On these surfaces hit targets are measured or they are not checked.
    static func measureHitTarget(
        _ control: XCUIElement,
        named label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            control.frame.height, 44, "\(label) is too short to hit", file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            control.frame.width, 44, "\(label) is too narrow to hit", file: file, line: line)
    }
}
