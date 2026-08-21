import XCTest

/// **X4** — the memory offer, over the scenario built for it.
///
/// `repeated` puts one merchant in **two statements of one account** and gives every row its
/// own amount and date, because both of the engine's de-duplication layers require equal
/// amounts and a superseded row is one the memory can no longer reach. A scenario that quietly
/// lost a copy would still pass the assertion below about the *offer* and fail nothing at all
/// about the *radius* — which is why `SeedMemoryExpectationTests` settles the declaration
/// against the engine before any of this runs.
///
/// What this suite is actually for is the promise in FR-028: a person can say no. Declining is
/// the path most likely to be got wrong quietly, because everything about it looks like
/// cancelling — and cancelling a correction is precisely what it must not do.
final class CategorizeMemoryUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        // A seeded store outlives the suite that wrote it.
        SeededLaunch.resetContainer()
        super.tearDown()
    }

    /// **X4** — the offer names the portion the engine derived, can be declined, and the
    /// correction is untouched afterwards.
    func testTheMemoryOfferNamesTheMerchantAndCanBeDeclined() {
        guard let subject = SeedScenario.repeated.expectedMemorySubjectRow,
            let memory = SeedScenario.repeated.memory
        else { return XCTFail("the repeated scenario declares no memory") }

        let app = SeededLaunch.launch(scenario: .repeated)
        SeededLaunch.openTransactionList(app)
        SeededLaunch.openRow(app, labelled: subject.accessibilityLabel)

        let chosen = "Groceries"
        SeededLaunch.chooseCategory(app, named: chosen)

        // M1 — the offer arrives, and says what it would learn.
        XCTAssertTrue(
            app.staticTexts[SeededLaunch.memoryOfferTitle].waitForExistence(timeout: 10),
            "no memory offer followed the correction")

        // M4 — and the merchant it names is the **engine's** derivation, quoted verbatim.
        // ⚠️ Asserted as a substring of a rendered sentence rather than against a sentence
        // this bundle rebuilt: rebuilding it here would be a second copy of the wording, which
        // would agree with the app's copy until somebody edited one of them.
        let quoting = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", memory.portion)
        ).firstMatch
        XCTAssertTrue(
            quoting.waitForExistence(timeout: 10),
            "the offer never says \"\(memory.portion)\". On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(quoting.label.contains(chosen), "the offer does not say where it would file")

        // M2 — declining is a decline, not a cancellation.
        app.buttons[SeededLaunch.memoryOfferDecline].tapWhenSettled()

        XCTAssertTrue(
            app.staticTexts["Category: \(chosen)"].waitForExistence(timeout: 10),
            "declining the offer undid the correction")
        XCTAssertFalse(
            app.staticTexts[SeededLaunch.memoryOfferTitle].exists, "the offer is still up")
        // And nothing was applied to anything else: the second action was never offered.
        XCTAssertFalse(
            app.staticTexts[SeededLaunch.secondActionTitle].exists,
            "declining led to the second action anyway")
    }

    /// **M3** on a real screen — a deliberate blank has nothing to remember, and the app says
    /// so instead of quoting an empty merchant back at somebody.
    ///
    /// The unit assertion in `MemoryOfferTests` covers the rule; this covers the sentence, which
    /// is the half a rule cannot check.
    func testFilingUnderNoCategoryOffersNothingToRemember() {
        guard let subject = SeedScenario.repeated.expectedMemorySubjectRow else {
            return XCTFail("the repeated scenario declares no memory")
        }

        let app = SeededLaunch.launch(scenario: .repeated)
        SeededLaunch.openTransactionList(app)
        SeededLaunch.openRow(app, labelled: subject.accessibilityLabel)

        SeededLaunch.chooseCategory(app, named: "No category")

        XCTAssertTrue(
            app.staticTexts[SeededLaunch.nothingToRememberTitle].waitForExistence(timeout: 10),
            "a deliberate blank was offered as something to remember")
        XCTAssertFalse(
            app.buttons[SeededLaunch.memoryOfferAccept].exists,
            "there is nothing to remember, and the app offered to remember it anyway")
    }
}
