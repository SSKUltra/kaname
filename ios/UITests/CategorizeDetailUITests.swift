import XCTest

/// **X1** and **X2** — opening a transaction, and changing what it is filed under.
///
/// These are the first assertions in this repository that a person can *act* on their own
/// transactions rather than only read them, and both are about what is on screen afterwards:
/// tapping a row must open that row (X1), and choosing a category must be visible on the
/// surface that changed it **and** on the list behind it, with nothing to refresh (X2,
/// FR-006, SC-003).
///
/// ⚠️ The contract names a scenario `basic`, which does not exist — the declared set is
/// `empty`, `small`, `deep`, `barren` and now `unfiled`. `small` is used: one account, six
/// rows, all of them unanswered, which is exactly the starting position these two need.
final class CategorizeDetailUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        // ⚠️ A seeded store outlives the suite that wrote it, and the shipped front-door
        // audits assert a fresh install.
        SeededLaunch.resetContainer()
        super.tearDown()
    }

    /// **X1** — a row opens itself, and the surface shows that row's own facts.
    func testTappingARowOpensThatTransaction() {
        let app = SeededLaunch.launch(scenario: .small)
        SeededLaunch.openTransactionList(app)

        let (row, sentence) = Self.firstRow(app)
        row.tap()

        XCTAssertTrue(
            app.navigationBars["Transaction"].waitForExistence(timeout: 10),
            "tapping a row did not open the transaction")

        // The row's own facts, not some other row's: every one of them is part of the sentence
        // the list read out, which is the only per-row text an automated run can see.
        //
        // ⚠️ Compared with the direction sign removed. A row *says* "₹12,345.67 debit" and
        // *shows* "−₹12,345.67" — the same fact, carried by a word for anyone listening and by
        // a sign for anyone looking, which is 018's FR-013 working exactly as intended. A
        // literal substring check reads that as two different amounts.
        let spoken = Self.withoutDirectionSign(sentence)
        for fact in Self.factsOnScreen(app) {
            XCTAssertTrue(
                spoken.contains(Self.withoutDirectionSign(fact)),
                "the surface shows \"\(fact)\", which is not part of the row that was tapped: "
                    + "\"\(sentence)\"")
        }
        // And the app's one word for having no category — `small`'s rows are all unanswered.
        XCTAssertTrue(
            app.staticTexts["Category: Uncategorized"].waitForExistence(timeout: 5),
            "the transaction does not say what it is currently filed under")
    }

    /// **X2** — the change is visible where it was made and where it came from, immediately.
    func testChangingACategoryShowsUpOnTheSurfaceAndTheList() {
        let app = SeededLaunch.launch(scenario: .small)
        SeededLaunch.openTransactionList(app)

        let (row, before) = Self.firstRow(app)
        row.tap()
        XCTAssertTrue(app.navigationBars["Transaction"].waitForExistence(timeout: 10))

        let chosen = "Groceries"
        SeededLaunch.chooseCategory(app, named: chosen)

        // ⚠️ **Since PR E a correction is followed by the memory offer**, and this test did not
        // change: the sheet sits over the surface below, so reaching for that surface without
        // dismissing it fails as "not hittable" and reads like a layout defect. Declining is
        // also the assertion X2 needs it to be — the change below must survive it (M2, FR-028).
        SeededLaunch.dismissMemoryOffer(app)

        // The surface that changed it, without a refresh.
        XCTAssertTrue(
            app.staticTexts["Category: \(chosen)"].waitForExistence(timeout: 10),
            "the transaction still shows its old category")

        // And the list behind it, also without a refresh (FR-006, SC-003).
        app.navigationBars["Transaction"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: 10))

        let expected = before.replacingOccurrences(of: "Uncategorized", with: chosen)
        let updated = SeededLaunch.element(app, labelled: expected)
        XCTAssertTrue(
            updated.waitForExistence(timeout: 10),
            "the list still reads the old category. Rows on screen: "
                + "\(SeededLaunch.rowLabels(app))")
    }

    /// The first transaction row on screen, and the sentence it announces.
    ///
    /// ⚠️ **The sentence is on neither the cell nor a `StaticText`.** The cell's own `label` is
    /// empty — reading it yields `""`, which then "contains" nothing and passes any assertion
    /// phrased the other way round — and since the row became a link its combined element is
    /// the **button** inside the cell. A date heading is a cell too, and has no button, which
    /// is what tells the two apart here without ever looking at the wording.
    private static func firstRow(_ app: XCUIApplication) -> (XCUIElement, String) {
        for cell in app.cells.allElementsBoundByIndex {
            let link = cell.buttons.allElementsBoundByIndex.first
            if let link, !link.label.isEmpty { return (link, link.label) }
        }
        XCTFail("the seeded list rendered no transaction row")
        return (app.cells.firstMatch, "")
    }

    /// The same text with the typographic minus and the plus removed — see the note in X1.
    private static func withoutDirectionSign(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2212}", with: "")
            .replacingOccurrences(of: "+", with: "")
    }

    /// The values the detail surface is showing, taken from its own labelled facts.
    ///
    /// Each fact is announced as `Heading: value`; the value is what must belong to the row
    /// that was tapped. The category is deliberately excluded — it is the one thing on this
    /// screen that can change.
    private static func factsOnScreen(_ app: XCUIApplication) -> [String] {
        ["Description", "Amount", "Date", "Account"].compactMap { heading in
            let element = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "\(heading): ")
            ).firstMatch
            guard element.waitForExistence(timeout: 5) else { return nil }
            return String(element.label.dropFirst(heading.count + 2))
        }
    }
}
