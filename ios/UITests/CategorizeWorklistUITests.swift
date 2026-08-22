import XCTest

/// **X6**, **X7**, **X3** and **X8** — the worklist, over `unfiled` and, for the one state that
/// needs a second account, `crossing`.
///
/// `unfiled` is one card with five live rows, of which the engine can place two: a cashback
/// inflow and a second one. The remaining three are what a person opens this door for, and
/// three is small enough to work to zero inside a test — which is the only way to reach the
/// state SC-011 is about, where the app has to say "you are finished" rather than show a zero.
///
/// ⚠️ Every correction now leads to the memory offer, including the ones made here for another
/// reason entirely; `SeededLaunch.dismissMemoryOffer` is the way through it. ⚠️ And a `List`
/// renders a screenful, not a list — the row counts below come from `SeededLaunch.walk`.
final class CategorizeWorklistUITests: XCTestCase {
    override func tearDown() {
        SeededLaunch.resetContainer()
        super.tearDown()
    }

    /// **X6** — the door states the work, and states the finish in words.
    ///
    /// The count is never asserted against a literal. It is asserted against the scenario's own
    /// declaration, which `SeedCategoryExpectationTests` has already measured against the
    /// engine's `uncategorizedCount()` — so this test is about the door showing the engine's
    /// number, and not about anybody's belief as to what that number is.
    func testTheDoorShowsTheEnginesCountAndThenSaysTheWorkIsFinished() {
        let app = SeededLaunch.launch(scenario: .unfiled)
        let waiting = SeedScenario.unfiled.expectedUncategorizedCount
        XCTAssertGreaterThan(waiting, 0, "the unfiled scenario declares no work to do")

        XCTAssertEqual(
            SeededLaunch.worklistDoorLabel(app), "\(waiting) transactions need a category",
            "the door does not say how much work there is")

        SeededLaunch.openWorklist(app)
        answerEveryRowOfTheWorklist(app, expecting: waiting)

        // The list itself says it, as a finish rather than as an absence.
        let empty = SeededLaunch.emptyState(app)
        XCTAssertEqual(empty?.title, SeededLaunch.allFiledTitle)

        // And so does the door, once the person comes back to it — without a relaunch, and
        // without anything having been reloaded by hand (E5).
        app.navigationBars["Transactions"].buttons.firstMatch.tap()
        XCTAssertTrue(
            app.buttons[SeededLaunch.worklistFinished].waitForExistence(timeout: 10),
            "the door still claims there is work after every row was answered")
        XCTAssertFalse(
            app.buttons["0 transactions need a category"].exists,
            "the door showed a zero instead of saying the work is finished")
    }

    /// **X7** — the worklist holds the unanswered rows and no others, and the account filter
    /// composes with it rather than replacing it.
    func testTheWorklistShowsOnlyUnansweredRowsAndComposesWithTheAccountFilter() throws {
        let app = SeededLaunch.launch(scenario: .unfiled)
        let scenario = SeedScenario.unfiled
        let unanswered = scenario.expectedLiveRows.filter {
            $0.accessibilityLabel.hasSuffix("Uncategorized")
        }
        let answered = scenario.expectedLiveRows.filter {
            !$0.accessibilityLabel.hasSuffix("Uncategorized")
        }
        XCTAssertFalse(answered.isEmpty, "the scenario cannot tell a worklist from a whole list")

        SeededLaunch.openWorklist(app)
        let narrowed = SeededLaunch.walk(app).rows
        XCTAssertEqual(
            narrowed, unanswered.map(\.accessibilityLabel),
            "the worklist is not exactly the rows nobody has answered")
        for row in answered {
            XCTAssertFalse(
                narrowed.contains(row.accessibilityLabel),
                "an answered row is on the worklist")
        }

        // Both narrowings at once. The account is the scenario's only one, so the rows are the
        // same rows — what is being asserted is that neither narrowing cancelled the other.
        let account = try XCTUnwrap(scenario.expectedAccounts.first)
        SeededLaunch.filter(app, to: account)
        XCTAssertEqual(
            SeededLaunch.walk(app).rows, unanswered.map(\.accessibilityLabel),
            "applying the account filter changed which rows the worklist holds")
    }

    /// **X3** — a deliberate blank is an answer, so the row leaves the worklist.
    ///
    /// This is the platform reflection of engine assertions **C5** and **H2**: "no category",
    /// chosen by a person, is a decision the engine records with their provenance and never
    /// re-decides. It cannot be observed anywhere but here — on the whole list a row that left
    /// the worklist is still on screen, which is why contract §11.2 lists X3 among the detail
    /// surface's assertions and this queue executes it in PR F.
    func testChoosingNoCategoryTakesTheRowOffTheWorklist() throws {
        let app = SeededLaunch.launch(scenario: .unfiled)
        SeededLaunch.openWorklist(app)

        let before = SeededLaunch.walk(app).rows
        let subject = try XCTUnwrap(before.first)

        SeededLaunch.openRow(app, labelled: subject)
        SeededLaunch.chooseCategory(app, named: "No category")
        SeededLaunch.dismissMemoryOffer(app)
        app.navigationBars["Transaction"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: 10))

        let after = SeededLaunch.walk(app).rows
        XCTAssertFalse(
            after.contains(subject),
            "a transaction a person deliberately left blank is still on the worklist")
        XCTAssertEqual(after.count, before.count - 1)
    }

    /// **X8** — one account finished while another still has work.
    ///
    /// The state `EmptyKind.accountAnswered` names: *this* card is done, and the app has to say
    /// so about the card rather than congratulate the person for finishing everything. It was
    /// asserted twice as a value and once as a sentence and **rendered by nothing** until this
    /// test existed (`.scratch/020-categorize/issues/02`), which is a hole in SC-018 rather than
    /// one of FR-070's unreachable states — a seed constructs it in fifteen taps.
    ///
    /// ⚠️ **Clearing the filter and still finding work is the assertion**, not the wording. It
    /// is the entire difference between this state and `allAnswered`; a test that stopped at the
    /// sentence would be testing copy, and would stay green if the two states swapped.
    ///
    /// `crossing` is the scenario for it: two accounts, every row unanswered, and a ledger/card
    /// pair — the only pair cross-source de-duplication compares, so the rows that survive here
    /// survive on purpose.
    func testFinishingOneAccountSaysSoAndClearingTheFilterStillFindsWork() throws {
        let scenario = SeedScenario.crossing
        XCTAssertEqual(
            scenario.expectedAccounts.count, 2,
            "the crossing scenario stopped spanning two accounts, so no account can finish alone")
        let finishing = try XCTUnwrap(scenario.expectedAccounts.first)
        let untouched = try XCTUnwrap(scenario.expectedAccounts.last)
        let mine = scenario.expectedLiveRows(inAccountNamed: finishing.name)
        let theirs = scenario.expectedLiveRows(inAccountNamed: untouched.name)
        XCTAssertFalse(mine.isEmpty, "there is nothing to answer in \(finishing.name)")
        XCTAssertFalse(
            theirs.isEmpty, "no work would be left over, so this is `allAnswered` in disguise")

        let app = SeededLaunch.launch(scenario: .crossing)
        SeededLaunch.openWorklist(app)
        SeededLaunch.filter(app, to: finishing)
        answerEveryRowOfTheWorklist(app, expecting: mine.count)

        let expected = SeededLaunch.accountFiledTitle(finishing.name)
        waitUntil("the account that finished never said so") {
            SeededLaunch.emptyState(app)?.title == expected
        }
        XCTAssertEqual(
            SeededLaunch.emptyState(app)?.title, expected,
            "the finished account is not named. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")

        // The half that makes it a different state: the filter was the reason, and dropping it
        // finds the other account's rows still waiting.
        SeededLaunch.clearFilter(app)
        XCTAssertEqual(
            SeededLaunch.walk(app).rows, theirs.map(\.accessibilityLabel),
            "clearing the filter did not leave exactly the other account's unanswered rows")
    }

    /// Work the whole list to zero, one row at a time, always taking whatever is at the top.
    ///
    /// ⚠️ It re-reads the list on every pass rather than holding the labels it saw first: each
    /// answer changes the row's own sentence *and* removes it, so a list captured up front is
    /// a list of things that no longer exist by the third correction.
    ///
    /// ⚠️ And it **waits for the list to be the length it should be** before reaching for the
    /// next row. The correction, the offer's dismissal and the list's re-read are three
    /// animations deep; a row tapped while the one above it is still leaving is a tap that
    /// lands on nothing and reports "tapping a row did not open the transaction" — a sentence
    /// that reads exactly like a broken row and is not.
    private func answerEveryRowOfTheWorklist(_ app: XCUIApplication, expecting count: Int) {
        for step in 0..<count {
            let remaining = count - step
            guard let next = firstRow(app, whenListHolds: remaining) else {
                return XCTFail("the worklist emptied after \(step) of \(count) answers")
            }
            SeededLaunch.openRow(app, labelled: next)
            SeededLaunch.chooseCategory(app, named: "Groceries")
            SeededLaunch.dismissMemoryOffer(app)
            waitUntil("the memory offer never went away") {
                !SeededLaunch.memoryOffer(app).exists
            }
            app.navigationBars["Transaction"].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: 10))
        }
    }

    /// The top row, once the list is showing the number of rows it should be showing.
    ///
    /// `SeededLaunch.rowLabels` rather than `walk`: a walk ends at the *bottom* of the list,
    /// and the row this then reaches for is at the top.
    private func firstRow(_ app: XCUIApplication, whenListHolds expected: Int) -> String? {
        waitUntil("the worklist never settled at \(expected) rows") {
            SeededLaunch.rowLabels(app).count == expected
        }
        return SeededLaunch.rowLabels(app).first
    }

    private func waitUntil(
        _ message: String,
        timeout: TimeInterval = 10,
        _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail(message)
    }
}
