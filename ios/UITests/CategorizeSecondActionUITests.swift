import XCTest

/// **X5** — the second action, over the scenario built for it.
///
/// `crossing` puts one merchant across **a ledger and a card**, which is the only pair
/// cross-source de-duplication compares — deliberately the side that *can* lose a row, so the
/// distinct amounts and dates keeping its rows apart are load-bearing. Two accounts is the
/// whole point: a radius stated as a bare number is a radius that does not say where the change
/// lands (FR-035c).
///
/// 🚨 The second assertion here is about something that must **not** exist. S2 says the screen
/// offers no choice of which transactions — no checkbox, no multi-select, no "select all" — and
/// an absence is only ever asserted by looking for the thing. ⚠️ It is also **not the
/// enforcement**: that is engine-side set equality (`contracts/engine-categorize.md` §2.4, test
/// M7). A UI without a checkbox proves nothing about a future UI, which is why T138 breaks the
/// caller and watches the engine refuse it.
final class CategorizeSecondActionUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        SeededLaunch.resetContainer()
        super.tearDown()
    }

    /// **X5** — the radius is stated in full before anything is agreed to, and there is nothing
    /// on the screen with which to narrow it.
    func testTheSecondActionStatesItsRadiusAndOffersNoChoiceOfRows() {
        guard let subject = SeedScenario.crossing.expectedMemorySubjectRow,
            let expected = SeedScenario.crossing.expectedMemoryImpact
        else { return XCTFail("the crossing scenario declares no memory") }

        let app = SeededLaunch.launch(scenario: .crossing)
        SeededLaunch.openTransactionList(app)
        SeededLaunch.openRow(app, labelled: subject.accessibilityLabel)

        SeededLaunch.chooseCategory(app, named: "Groceries")
        XCTAssertTrue(
            app.staticTexts[SeededLaunch.memoryOfferTitle].waitForExistence(timeout: 10),
            "no memory offer followed the correction")
        app.buttons[SeededLaunch.memoryOfferAccept].tapWhenSettled()

        XCTAssertTrue(
            app.staticTexts[SeededLaunch.secondActionTitle].waitForExistence(timeout: 15),
            "accepting the offer never led to the second action. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")

        // S1, a — how many. The declared count is settled against the engine's own preview by
        // `SeedMemoryExpectationTests`, so a number that matches here matches the engine.
        let count = expected.rows.count
        let stated = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "\(count) transactions")
        ).firstMatch
        XCTAssertTrue(
            stated.waitForExistence(timeout: 10),
            "the screen never says how many transactions would change")

        // S1, b — and where. Both accounts, by name, before anything is agreed to. ⚠️ Two
        // accounts rather than one is the assertion: a scenario on a single account would pass
        // this with a screen that had quietly dropped the plural.
        XCTAssertEqual(expected.accountNames.count, 2, "the scenario stopped spanning two accounts")
        for name in expected.accountNames {
            let line = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", name)
            ).firstMatch
            XCTAssertTrue(
                line.waitForExistence(timeout: 10),
                "the screen never names \(name). On screen: "
                    + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        }

        // S2 — nothing on this screen narrows the set. Looked for the way a person would find
        // one: a toggle, a switch, a checkbox, or a control offering to select everything.
        XCTAssertEqual(app.switches.count, 0, "the second action offers a toggle")
        XCTAssertEqual(app.checkBoxes.count, 0, "the second action offers a checkbox")
        for wording in ["Select all", "Select", "Choose which", "Deselect"] {
            XCTAssertFalse(
                app.buttons[wording].exists, "the second action offers \"\(wording)\"")
        }
        // The only two answers, and no third.
        XCTAssertTrue(app.buttons["Change them"].exists, "there is no way to agree")
        XCTAssertTrue(
            app.buttons["Leave them as they are"].exists, "there is no way to decline")
    }

    /// **S7** — declining the second action leaves the memory formed and the correction intact.
    /// Only the bulk application is declined.
    func testDecliningTheSecondActionLeavesTheCorrectionAlone() {
        guard let subject = SeedScenario.crossing.expectedMemorySubjectRow else {
            return XCTFail("the crossing scenario declares no memory")
        }

        let app = SeededLaunch.launch(scenario: .crossing)
        SeededLaunch.openTransactionList(app)
        SeededLaunch.openRow(app, labelled: subject.accessibilityLabel)

        SeededLaunch.chooseCategory(app, named: "Groceries")
        XCTAssertTrue(
            app.staticTexts[SeededLaunch.memoryOfferTitle].waitForExistence(timeout: 10))
        app.buttons[SeededLaunch.memoryOfferAccept].tapWhenSettled()
        XCTAssertTrue(
            app.staticTexts[SeededLaunch.secondActionTitle].waitForExistence(timeout: 15))

        app.buttons["Leave them as they are"].tapWhenSettled()

        XCTAssertTrue(
            app.staticTexts["Category: Groceries"].waitForExistence(timeout: 10),
            "declining the second action undid the correction it came from")
    }

    /// Agreeing changes the rows the screen said it would, and says so afterwards.
    func testAgreeingChangesTheRowsItNamed() {
        guard let subject = SeedScenario.crossing.expectedMemorySubjectRow,
            let expected = SeedScenario.crossing.expectedMemoryImpact
        else { return XCTFail("the crossing scenario declares no memory") }

        let app = SeededLaunch.launch(scenario: .crossing)
        SeededLaunch.openTransactionList(app)
        SeededLaunch.openRow(app, labelled: subject.accessibilityLabel)

        SeededLaunch.chooseCategory(app, named: "Groceries")
        XCTAssertTrue(
            app.staticTexts[SeededLaunch.memoryOfferTitle].waitForExistence(timeout: 10))
        app.buttons[SeededLaunch.memoryOfferAccept].tapWhenSettled()
        XCTAssertTrue(
            app.staticTexts[SeededLaunch.secondActionTitle].waitForExistence(timeout: 15))

        app.buttons["Change them"].tapWhenSettled()

        let changed = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "\(expected.rows.count) transactions changed")
        ).firstMatch
        XCTAssertTrue(
            changed.waitForExistence(timeout: 15),
            "the screen never says what changed. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")

        app.buttons["Done"].tapWhenSettled()

        // And the rows themselves: back on the list, every row the radius named now reads the
        // new category. ⚠️ Asserted on the **rendered sentence**, which is where a person would
        // see it — the engine's own count was already settled by `SeedMemoryExpectationTests`.
        app.navigationBars["Transaction"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: 10))
        let walked = SeededLaunch.allRowLabels(app)
        for row in expected.rows {
            let updated = row.accessibilityLabel.replacingOccurrences(
                of: "Uncategorized", with: "Groceries")
            XCTAssertTrue(
                walked.contains(updated),
                "a row the second action named still reads its old category. Rows: \(walked)")
        }
    }
}
