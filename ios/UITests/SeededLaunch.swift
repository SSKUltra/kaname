import XCTest

/// How every seeded suite launches the app — one place, because three of the four inputs are
/// easy to forget and each one fails quietly.
///
/// - The scenario goes on `launchEnvironment` under its **bare** key. The `TEST_RUNNER_` prefix
///   belongs to app-hosted *unit* tests; a prefixed variable here is never delivered.
/// - The **locale** is pinned. `.currency(code:)` takes its symbol from the code but its
///   grouping from the locale, and month names from the language, so an unpinned assertion is
///   an assertion about the region the simulator happens to be set to (research R16).
/// - The launch is asserted to reach the foreground. That single line is *also* the failure
///   detector for a seed that could not be applied: `App.init()` has no UI and no channel to
///   report on, so a failed seed is a failed launch and nothing else
///   (`contracts/seeded-launch.md` §3).
enum SeededLaunch {
    static let key = "KANAME_SEED_SCENARIO"
    static let localeArguments = ["-AppleLocale", "en_IN", "-AppleLanguages", "(en)"]

    /// Launch, optionally seeded, with the locale pinned. Returns the running app.
    @discardableResult
    static func launch(
        scenario: SeedScenario?,
        arguments: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIApplication {
        let app = XCUIApplication()
        if let scenario { app.launchEnvironment[key] = scenario.name }
        app.launchArguments += localeArguments + arguments
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "the app did not reach the foreground — if a scenario was requested, the seed failed",
            file: file, line: line)
        return app
    }

    /// Put the container back to a fresh install, by asking for the scenario that declares
    /// nothing: the reset without the seed.
    ///
    /// A seeded store outlives the suite that wrote it, and the shipped front-door audits
    /// assert a fresh install — so without this, running a seeded suite before them audits an
    /// accounts list and reports a failure that has nothing to do with the code.
    static func resetContainer() {
        let app = XCUIApplication()
        app.launchEnvironment[key] = SeedScenario.empty.name
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)
        app.terminate()
    }

    /// The one element carrying `label`, whatever kind of element the framework decided it is.
    ///
    /// A combined row is a cell on the transaction list and a cell on the accounts list today,
    /// but the assertions here are about **what a person hears**, not about which container
    /// SwiftUI chose, so they are written against the label rather than the element type.
    static func element(_ app: XCUIApplication, labelled label: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    /// Open the combined list from the front door — the same control a person taps.
    ///
    /// ⚠️ `All transactions` is the toolbar link's title; `Transactions` is the navigation-bar
    /// title of the screen it opens, and tapping that finds nothing.
    static func openTransactionList(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let link = app.buttons["All transactions"]
        XCTAssertTrue(
            link.waitForExistence(timeout: 10), "the front door offers no route to the list",
            file: file, line: line)
        link.tap()
        XCTAssertTrue(
            app.navigationBars["Transactions"].waitForExistence(timeout: 10),
            "the transaction list did not open", file: file, line: line)
    }

    /// Every transaction row currently rendered, by the sentence it announces.
    ///
    /// `TransactionRowView` combines its children, so one row is one element carrying the whole
    /// sentence. ⚠️ **A date heading is a cell too**, and neither a heading nor a row puts its
    /// label on the cell itself — both hang it on a `StaticText` inside. They are told apart
    /// structurally: a row's combined element still has its parts underneath it (description,
    /// account, category, amount), and a heading is one line with nothing under it. Filtering
    /// on the *wording* of a heading would have been a filter on copy, and would have quietly
    /// started counting a row the day a description ended in the word "transactions".
    static func rowLabels(_ app: XCUIApplication) -> [String] {
        visibleLabels(app).filter(\.1).map(\.0)
    }

    /// Every row of the whole list, in the order it is rendered, by scrolling to the end.
    ///
    /// ⚠️ A `List` renders what is on screen and no more, so `rowLabels` alone counts a
    /// *screenful*, not a list — even six rows do not all fit above the filter bar. Rows are
    /// collected in encounter order and only ever scrolled downwards, so the sequence returned
    /// is the sequence rendered, which is what an ordering assertion needs.
    static func allRowLabels(_ app: XCUIApplication, maximumSwipes: Int = 60) -> [String] {
        walk(app, maximumSwipes: maximumSwipes).rows
    }

    /// The whole list — every row and every date heading — in the order it renders.
    ///
    /// One walk rather than two, because a walk ends at the bottom of the list: a second query
    /// afterwards sees only the last screenful, which is how the first version of the date
    /// assertion came to look for a heading that had scrolled off half a minute earlier.
    static func walk(_ app: XCUIApplication, maximumSwipes: Int = 60) -> ListWalk {
        var rows: [String] = []
        var headings: [String] = []
        var repeated: [String] = []
        var seen = Set<String>()
        var swipes = 0
        let list = app.collectionViews.firstMatch
        for _ in 0...maximumSwipes {
            let before = seen.count
            let visible = visibleLabels(app)
            // ⚠️ The only duplication a walk can honestly detect. Rows are collected into a set
            // across passes, because a row stays on screen while the list scrolls past it — so
            // "seen twice" across passes says nothing. Seen twice **in one screenful** does: it
            // is a row rendered twice, which is what a page boundary repeating its first row
            // looks like.
            var thisScreen = Set<String>()
            for (label, _) in visible where !thisScreen.insert(label).inserted {
                repeated.append(label)
            }
            for (label, isRow) in visible where !seen.contains(label) {
                seen.insert(label)
                if isRow { rows.append(label) } else { headings.append(label) }
            }
            // A pass that reveals nothing new is the end of the list — and, on the first pass,
            // an empty one.
            if seen.count == before { break }
            list.swipeUp()
            swipes += 1
        }
        return ListWalk(
            rows: rows, headings: headings, repeatedOnOneScreen: repeated, swipes: swipes)
    }

    /// Every labelled cell on screen, and whether it is a row.
    ///
    /// ⚠️ **A row's sentence is not on its cell, and since 020 it is not on a `StaticText`
    /// either.** The row became a `NavigationLink`, so its combined accessibility element
    /// surfaces as a **button** carrying the whole announcement; the description, account,
    /// category and amount remain underneath it as separate texts. A date heading is a cell
    /// too, and has neither a button nor a second text — which is still how the two are told
    /// apart, structurally rather than by wording.
    ///
    /// Reading `cell.staticTexts.first` here is what made every 018 row assertion go red the
    /// moment the row gained a link, while VoiceOver's own reading had not changed at all.
    private static func visibleLabels(_ app: XCUIApplication) -> [(String, Bool)] {
        app.cells.allElementsBoundByIndex.compactMap { cell in
            let announcement = cell.buttons.allElementsBoundByIndex.first?.label
            if let announcement, !announcement.isEmpty { return (announcement, true) }
            let texts = cell.staticTexts.allElementsBoundByIndex
            guard let label = texts.first?.label else { return nil }
            return (label, texts.count > 1)
        }
    }

    /// Narrow the list to one account, through the bar a person uses.
    static func filter(
        _ app: XCUIApplication,
        to account: SeedAccountExpectation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let label = SeedScenario.menuLabel(for: account)
        // ⚠️ Not `app.buttons["Showing all accounts"]`. The scope chip announces the scope, so
        // its label changes the moment a filter is applied — and a second `filter(…)` in the
        // same test then taps a control that no longer exists.
        scopeChip(app).tap()
        let option = app.buttons[label]
        XCTAssertTrue(
            option.waitForExistence(timeout: 10), "the filter menu does not offer \(label)",
            file: file, line: line)
        option.tap()
        XCTAssertTrue(
            app.buttons["Showing \(label) only"].waitForExistence(timeout: 10),
            "the scope chip does not say the filter was applied", file: file, line: line)
    }

    /// Put the list back to every account, through the button that exists for it.
    static func clearFilter(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        app.buttons["Show all accounts"].firstMatch.tap()
        XCTAssertTrue(
            app.buttons["Showing all accounts"].waitForExistence(timeout: 10),
            "the filter was not cleared", file: file, line: line)
    }

    /// The scope chip, whatever scope it is currently announcing.
    static func scopeChip(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Showing '")).firstMatch
    }

    /// What an empty list is saying: the title and the message of the state it rendered.
    static func emptyState(_ app: XCUIApplication) -> (title: String, message: String)? {
        let texts = app.staticTexts.allElementsBoundByIndex.map(\.label)
        guard
            let index = texts.firstIndex(where: { text in
                emptyTitlePrefixes.contains { text.hasPrefix($0) }
            })
        else { return nil }
        return (texts[index], texts.dropFirst(index + 1).first ?? "")
    }

    /// How every title `TransactionListStrings.emptyState(for:)` can produce begins — three of
    /// the six name the account, so this matches a prefix rather than a whole sentence.
    /// Duplicated here on purpose: this bundle cannot see the app's strings, and an assertion
    /// made against the **rendered** sentence is what notices when copy and state come apart.
    private static let emptyTitlePrefixes = [
        "No transactions", "Nothing to show", "Nothing imported yet",
    ]

    // MARK: - Correcting a transaction, and what follows it

    /// One transaction row, by the sentence it announces — the only per-row text an automated
    /// run can see.
    static func row(_ app: XCUIApplication, labelled label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Open one transaction from the list, walking to it if it is below the fold.
    static func openRow(
        _ app: XCUIApplication,
        labelled label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let target = row(app, labelled: label)
        var swipes = 0
        while !target.exists && swipes < 20 {
            app.collectionViews.firstMatch.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(
            target.waitForExistence(timeout: 10), "the list never showed \(label)",
            file: file, line: line)
        target.tap()
        XCTAssertTrue(
            app.navigationBars["Transaction"].waitForExistence(timeout: 10),
            "tapping a row did not open the transaction", file: file, line: line)
    }

    /// File the open transaction under `category`, through the picker a person uses.
    ///
    /// ⚠️ At an accessibility text size the action is below four facts, which is why this
    /// scrolls before giving up — FR-004 asks for it to be reachable without scrolling **at the
    /// default size**, and a helper that refused to scroll would assert a requirement nobody
    /// made.
    static func chooseCategory(
        _ app: XCUIApplication,
        named category: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let change = app.buttons["Change category"].firstMatch
        if !change.waitForExistence(timeout: 10) || !change.isHittable {
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(
            change.waitForExistence(timeout: 10), "the surface offers no way to change",
            file: file, line: line)
        change.tap()
        XCTAssertTrue(
            app.navigationBars["Choose a category"].waitForExistence(timeout: 10),
            "the picker did not open", file: file, line: line)
        // ⚠️ Not `app.buttons[category]`. The picker marks the **current** choice by appending
        // a spoken word to its label, so the one row a person is most likely to be looking at
        // is the one row an exact match cannot find — and on an unanswered transaction that is
        // "No category", which is exactly what a test of the deliberate blank reaches for.
        let choice = app.buttons.matching(
            NSPredicate(
                format: "label == %@ OR label BEGINSWITH %@", category, "\(category), ")
        ).firstMatch
        XCTAssertTrue(
            choice.waitForExistence(timeout: 10), "the picker does not offer \(category)",
            file: file, line: line)
        choice.tap()
    }

    /// The sentences the memory offer can lead with.
    ///
    /// ⚠️ Duplicated from `CategorizeStrings` on purpose, exactly as `emptyTitlePrefixes` is:
    /// this bundle links neither the app nor the engine, and an assertion made against the
    /// **rendered** sentence is what notices when the copy and the state come apart.
    static let memoryOfferTitle = "Remember this for next time?"
    static let nothingToRememberTitle = "Nothing to remember here"
    static let memoryOfferDecline = "Not now"
    static let memoryOfferAccept = "Remember it"
    static let secondActionTitle = "Change the ones you already have?"

    /// Whatever the memory offer is currently saying, or a non-existent element.
    static func memoryOffer(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(
                format: "label == %@ OR label == %@", memoryOfferTitle, nothingToRememberTitle)
        ).firstMatch
    }

    /// Decline whatever the offer is offering — the path that must leave a correction intact.
    ///
    /// ⚠️ **Every correction now leads here**, including ones a test makes for another reason
    /// entirely. A test that changes a category and then reaches for the surface underneath is
    /// reaching through a sheet, which fails as "the element is not hittable" and reads like a
    /// layout defect.
    static func dismissMemoryOffer(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            memoryOffer(app).waitForExistence(timeout: 10),
            "no memory offer followed the correction", file: file, line: line)
        for label in [memoryOfferDecline, "Done"] {
            let button = app.buttons[label].firstMatch
            if button.exists {
                button.tap()
                return
            }
        }
        XCTFail("the memory offer cannot be declined", file: file, line: line)
    }

    /// Pin the appearance for the length of a test, and put it back.    ///
    /// ⚠️ `XCUIDevice.shared.appearance` is a **simulator-wide** setting that outlives the test
    /// that set it, so an audit that does not state which appearance it wants audits whichever
    /// one the last run happened to leave behind — this suite was written against a screen that
    /// was Dark for that reason. It is the same trap `make ios-test` pins `content_size` for,
    /// one axis over.
    static func pin(_ appearance: XCUIDevice.Appearance, in testCase: XCTestCase) {
        let previous = XCUIDevice.shared.appearance
        XCUIDevice.shared.appearance = appearance
        testCase.addTeardownBlock { XCUIDevice.shared.appearance = previous }
    }
}

/// What one walk of the list saw.
struct ListWalk {
    /// Every transaction row, in the order it rendered.
    let rows: [String]
    /// Every date heading, in the order it rendered.
    let headings: [String]
    /// Labels that appeared **twice in a single screenful** — a row rendered twice, which is
    /// what a page boundary repeating itself looks like. Always empty on a correct list.
    let repeatedOnOneScreen: [String]
    /// How many swipes it took to reach the end — the number SC-017's "a handful" is about,
    /// and the one a later scenario author watches grow.
    let swipes: Int
}
