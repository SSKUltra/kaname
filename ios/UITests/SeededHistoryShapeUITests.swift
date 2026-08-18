import XCTest

/// The shape of a real history, asserted against the screen: 160 rows over four accounts, four
/// pages, two currencies, a date shared by two accounts, and five rows that lost a
/// de-duplication and must never appear.
///
/// ⚠️ **One walk, many assertions, on purpose.** Walking `deep` to its end takes roughly two
/// minutes of simulator time — it is 160 rows, four page loads and thirty-odd swipes — so
/// splitting these into a test each would have cost the gate ten minutes to answer questions
/// that one traversal already answers. What is *not* shared is the failure message: each
/// assertion names the property it is about, so a red run still says which one broke.
final class SeededHistoryShapeUITests: XCTestCase {
    /// `TransactionListViewModel.pageSize`. Stated here because the paging assertion is about
    /// this number, and a scenario that quietly fell under it would otherwise still pass.
    private let pageSize = 50

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        SeededLaunch.pin(.light, in: self)
    }

    override func tearDown() {
        SeededLaunch.resetContainer()
        super.tearDown()
    }

    func testTheDeepScenarioRendersItsWholeDeclaredHistory() {
        let scenario = SeedScenario.deep
        let declared = scenario.expectedLiveRows
        let expectedLabels = declared.map(\.accessibilityLabel)
        XCTAssertEqual(
            Set(expectedLabels).count, expectedLabels.count,
            "two live rows share a sentence, so a count of sentences is not a count of rows")

        let app = SeededLaunch.launch(scenario: scenario)

        // The engine's own per-account counts, read from the front door before anything is
        // rendered — including the two accounts that must report zero for different reasons.
        for account in scenario.expectedAccounts {
            XCTAssertTrue(
                SeededLaunch.element(app, labelled: account.announcement).waitForExistence(timeout: 10),
                "the engine does not report \(account.announcement)")
        }

        SeededLaunch.openTransactionList(app)
        let walk = SeededLaunch.walk(app)

        // S2 / SC-001 — nothing skipped.
        XCTAssertEqual(walk.rows.count, scenario.expectedLiveRowCount)
        // S5 / FR-016 — nothing reordered. This is the engine's total order (`date DESC`, then
        // the account's position in `listAccounts()`, then insertion order) rendered as a
        // sequence, and it subsumes the same-date cross-account tie-break: the shared date's
        // ledger rows come before its card rows because the ledger was created first.
        XCTAssertEqual(walk.rows, expectedLabels)
        // SC-017 — nothing duplicated. A page boundary that repeats its first row shows that
        // row twice in one screenful, which is the only duplication a walk can honestly see.
        XCTAssertEqual(walk.repeatedOnOneScreen, [])
        // FR-009 — it really did page, more than once. 160 rows against a page size of 50 is
        // four fetches, the last of them partial, which is also the exhausted cursor.
        XCTAssertGreaterThan(
            walk.rows.count, pageSize * 2,
            "the list never paged more than twice, so paging is untested by this walk")

        // S4 — every row that lost a de-duplication is absent. Two of the three routes produce
        // a loser whose sentence is *identical* to its winner's (a re-import, and the echo
        // card's rows only differ by account), so absence is asserted as the whole sequence
        // being exactly the declared one — which the equality above already says — plus this,
        // which names the one loser whose sentence is its own.
        let crossSource = SeedScenario.deepSharedPurchase.accessibilityLabel(
            accountName: SeedScenario.deepCardName, last4: "0002")
        XCTAssertFalse(
            walk.rows.contains(crossSource),
            "a row superseded across sources is on screen: \(crossSource)")
        XCTAssertEqual(scenario.expectedSupersededRowCount, 5)

        assertCurrenciesStayApart(scenario: scenario, walk: walk)
        print("seed-shape: deep rendered \(walk.rows.count) rows in \(walk.swipes) swipes")
    }

    /// FR-023 / FR-025 — a row carries its **own** currency, and nothing anywhere adds two
    /// currencies together.
    private func assertCurrenciesStayApart(scenario: SeedScenario, walk: ListWalk) {
        let declared = scenario.expectedLiveRows
        let byAccount = Dictionary(grouping: declared, by: \.accountName)
        let mixed = byAccount.filter { Set($0.value.map(\.currency)).count > 1 }
        XCTAssertEqual(
            mixed.count, 1, "deep is meant to declare exactly one account holding two currencies")

        for row in declared where row.currency != "INR" {
            XCTAssertTrue(
                walk.rows.contains(row.accessibilityLabel),
                "a row in \(row.currency) is missing or was rendered in another currency: "
                    + row.accessibilityLabel)
        }
        // No figure combines them, and the strongest place to say so is the one element that
        // could hold a total and does not: a date heading spans two accounts and, on the shared
        // date, two currencies. It carries a count and never an amount (FR-026).
        for heading in walk.headings {
            XCTAssertFalse(
                heading.contains("₹") || heading.contains("$"),
                "a date heading carries a figure: \(heading)")
        }
    }
}
