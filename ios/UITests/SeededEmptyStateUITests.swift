import XCTest

/// The filter, and what a screen says when the filter — or the store — leaves it with nothing
/// to show.
///
/// Every one of these states shipped in 018 with unit coverage only, because reaching them on a
/// real screen needed a store with a particular shape in it and no automated run could make
/// one. A person had to be told *which of six true things* is the case, and until now nobody
/// could check that the right sentence appeared on the right screen.
final class SeededEmptyStateUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        SeededLaunch.pin(.light, in: self)
    }

    override func tearDown() {
        SeededLaunch.resetContainer()
        super.tearDown()
    }

    /// E3 — the filter's four states, in one journey, on the scenario that has enough accounts
    /// to make each of them mean something. And **S6** with it: the count the front door shows
    /// for an account is the number of rows the list shows when it is narrowed to that account.
    func testTheFilterReachesItsFourStates() {
        let scenario = SeedScenario.deep
        let app = SeededLaunch.launch(scenario: scenario)
        SeededLaunch.openTransactionList(app)

        // 1 — unfiltered. The chip says so, and the clear button is not offered, because there
        // is nothing to clear.
        XCTAssertTrue(app.buttons["Showing all accounts"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Show all accounts"].exists)

        // 2 — filtered to an account that has rows. S6: the engine's count and the screen agree.
        guard let card = scenario.expectedAccount(named: SeedScenario.deepCardName) else {
            return XCTFail("deep does not declare \(SeedScenario.deepCardName)")
        }
        SeededLaunch.filter(app, to: card)
        let filtered = SeededLaunch.walk(app)
        XCTAssertEqual(filtered.rows.count, card.liveRowCount)
        XCTAssertEqual(
            filtered.rows, scenario.expectedLiveRows(inAccountNamed: card.name).map(\.accessibilityLabel),
            "a filtered list is the same query with one account in it, not a second sort")

        // 3 — filtered to an account with nothing live. The bar is still there, so the screen
        // has somewhere to go back to.
        guard let empty = scenario.expectedAccount(named: SeedScenario.deepEmptyCardName) else {
            return XCTFail("deep does not declare \(SeedScenario.deepEmptyCardName)")
        }
        SeededLaunch.filter(app, to: empty)
        XCTAssertEqual(SeededLaunch.rowLabels(app), [])

        // 4 — cleared, in one tap, without leaving the screen.
        SeededLaunch.clearFilter(app)
        XCTAssertTrue(app.buttons["Showing all accounts"].exists)
        XCTAssertFalse(SeededLaunch.rowLabels(app).isEmpty)
    }

    /// E1 — an account whose statement genuinely had no transactions in it, while other
    /// accounts have rows. The sentence has to carry **both** facts: the statement was empty,
    /// *and* clearing the filter would show something.
    func testAnAccountWhoseStatementWasEmptySaysSoAndSaysTheFilterIsHiding() {
        let scenario = SeedScenario.deep
        let app = SeededLaunch.launch(scenario: scenario)
        SeededLaunch.openTransactionList(app)
        guard let account = scenario.expectedAccount(named: SeedScenario.deepEmptyCardName) else {
            return XCTFail("deep does not declare \(SeedScenario.deepEmptyCardName)")
        }

        SeededLaunch.filter(app, to: account)

        guard let state = SeededLaunch.emptyState(app) else {
            return XCTFail("no empty state rendered for \(account.name)")
        }
        XCTAssertEqual(state.title, "No transactions for \(account.name)")
        XCTAssertEqual(
            state.message,
            "The statement you imported for \(account.name) didn't have any transactions in it. "
                + "Other accounts have transactions.")
    }

    /// E2 — an account that holds rows and shows none of them, because every one lost a
    /// de-duplication to a row the person already had on another account.
    ///
    /// ⚠️ **This renders `accountEmptyOthersHaveRows(statementWasEmpty: false)`, not
    /// `accountNothingToShow`** — and the difference is a finding, not a slip. See
    /// `.scratch/019-debug-test-seeding/issues/02`: for an account to hold nothing but excluded
    /// rows, some *other* account must hold the winners, so "other accounts have transactions"
    /// is true by construction and the refinement always wins.
    func testAnAccountWhoseEveryRowWasSupersededSaysThereIsNothingToShow() {
        let scenario = SeedScenario.deep
        let app = SeededLaunch.launch(scenario: scenario)
        SeededLaunch.openTransactionList(app)
        guard let account = scenario.expectedAccount(named: SeedScenario.deepEchoCardName) else {
            return XCTFail("deep does not declare \(SeedScenario.deepEchoCardName)")
        }
        XCTAssertEqual(account.liveRowCount, 0, "the echo card is meant to have nothing live")

        SeededLaunch.filter(app, to: account)

        guard let state = SeededLaunch.emptyState(app) else {
            return XCTFail("no empty state rendered for \(account.name)")
        }
        XCTAssertEqual(state.title, "No transactions for \(account.name)")
        XCTAssertEqual(
            state.message,
            "There's nothing to show for \(account.name). Other accounts have transactions.")
    }

    /// E5 — two imported statements, no transactions anywhere. The screen says what happened
    /// rather than implying nothing was imported, and it offers **no** action, because there is
    /// nothing for a person to do about a quiet month.
    func testAStoreWithStatementsAndNoTransactionsSaysSo() {
        let scenario = SeedScenario.barren
        let app = SeededLaunch.launch(scenario: scenario)
        SeededLaunch.openTransactionList(app)

        guard let state = SeededLaunch.emptyState(app) else {
            return XCTFail("no empty state rendered for barren")
        }
        XCTAssertEqual(state.title, "No transactions")
        XCTAssertEqual(
            state.message, "The statements you imported didn't have any transactions in them.")
        XCTAssertFalse(app.buttons["Import a statement"].exists)
    }

    /// The fourth reachable case: filtered to an empty account when **no** account has anything
    /// live, so the filter is not what is hiding it and the sentence must not blame the filter.
    func testAnEmptyAccountWithNoOthersHoldingRowsBlamesTheStatement() {
        let scenario = SeedScenario.barren
        let app = SeededLaunch.launch(scenario: scenario)
        SeededLaunch.openTransactionList(app)
        guard let account = scenario.expectedAccount(named: SeedScenario.barrenFirstName) else {
            return XCTFail("barren does not declare \(SeedScenario.barrenFirstName)")
        }

        SeededLaunch.filter(app, to: account)

        guard let state = SeededLaunch.emptyState(app) else {
            return XCTFail("no empty state rendered for \(account.name)")
        }
        XCTAssertEqual(state.title, "No transactions")
        XCTAssertEqual(
            state.message,
            "The statement you imported for \(account.name) didn't have any transactions in it.")
    }
}
