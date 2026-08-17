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
        app.cells.allElementsBoundByIndex.compactMap { cell in
            let texts = cell.staticTexts.allElementsBoundByIndex
            guard texts.count > 1 else { return nil }
            return texts.first?.label
        }
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
    static func walk(
        _ app: XCUIApplication,
        maximumSwipes: Int = 60
    ) -> (rows: [String], headings: [String]) {
        var rows: [String] = []
        var headings: [String] = []
        var seen = Set<String>()
        let list = app.collectionViews.firstMatch
        for _ in 0...maximumSwipes {
            let before = seen.count
            for (label, isRow) in visibleLabels(app) where !seen.contains(label) {
                seen.insert(label)
                if isRow { rows.append(label) } else { headings.append(label) }
            }
            // A pass that reveals nothing new is the end of the list — and, on the first pass,
            // an empty one.
            if seen.count == before { break }
            list.swipeUp()
        }
        return (rows, headings)
    }

    /// Every labelled cell on screen, and whether it is a row.
    private static func visibleLabels(_ app: XCUIApplication) -> [(String, Bool)] {
        app.cells.allElementsBoundByIndex.compactMap { cell in
            let texts = cell.staticTexts.allElementsBoundByIndex
            guard let label = texts.first?.label else { return nil }
            return (label, texts.count > 1)
        }
    }

    /// Pin the appearance for the length of a test, and put it back.
    ///
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
