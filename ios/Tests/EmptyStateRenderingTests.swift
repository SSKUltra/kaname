import Foundation
import KanameCore
import SwiftUI
import Testing
import UIKit

@testable import Kaname

/// The three empty states **no seed can reach**, executed against a real rendered view.
///
/// ⚠️ **This is lesser coverage than the seeded suites, and saying so is the point.**
/// `performAccessibilityAudit` is an `XCUIApplication` API: it cannot be pointed at a hosted
/// view. So these states are *executed and asserted* — the branch runs, the view builds, the
/// screen that comes out is the empty state's shape and not a spinner or a list — but they are
/// **not audited**. Nothing here checks contrast, clipping, hit regions or Dynamic Type.
/// FR-039's coverage of the six `EmptyKind` cases is uneven by construction, and the tally is
/// in `.scratch/019-debug-test-seeding/issues/02`.
///
/// ⚠️ **And a hosted SwiftUI view will not tell a unit test what it says.** Measured while
/// writing this file: the rendered hierarchy for these states contains **no `UILabel` and no
/// accessibility label** — SwiftUI draws its text, and materialises an accessibility tree only
/// when an assistive technology asks for one, which is why XCUITest can read a row's sentence
/// and this cannot. So the wording is asserted where it *is* readable — through
/// `TransactionListStrings.emptyState(for:)`, the same function the view renders — and what the
/// rendering proves is that the branch was taken and produced this state's shape.
///
/// **Why these three cannot be seeded** (`issues/02`, answering T058):
///
/// - `nothingImported` needs zero accounts — and `RootView` hides the list's only entry point
///   under that same `accountSummaries()` call, so no launch can satisfy both conditions at
///   once. The branch is correct and defensive and stays (FR-039a).
/// - `nothingToShowAnywhere` needs zero live rows store-wide *and* an account holding excluded
///   ones. Every supersession the import path can produce leaves a **live winner** — a
///   re-import keeps the row the account already had, cross-source keeps the earlier account's
///   — and `is_deleted` has no write path at all. It describes a store the engine cannot build.
/// - `accountNothingToShow` fails on the same fact from the other side: for one account to hold
///   nothing but excluded rows, another account must hold the winners, so "no other account has
///   rows" is false exactly when the precondition is true.
///
/// Before this file, `nothingImported` had **zero** automated executions of any kind. That is
/// the whole of the claim being made here.
@MainActor
@Suite("The empty states no seed can reach still render")
struct EmptyStateRenderingTests {
    @Test("Nothing imported at all says so, and offers the one thing there is to do")
    func nothingImported() async throws {
        let rendered = try await render(summaries: [], filter: .all, expecting: .nothingImported)

        let copy = TransactionListStrings.emptyState(for: .nothingImported)
        #expect(copy.title == "Nothing imported yet")
        #expect(copy.message == "Import a statement and the transactions in it will appear here.")
        #expect(copy.action == .importStatement)
        // The action is on screen: the state renders its one way out, not a dead end.
        #expect(rendered.hasInteractiveHost)
    }

    @Test("A store whose every row is excluded says there is nothing to show, not that nothing was imported")
    func nothingToShowAnywhere() async throws {
        let rendered = try await render(
            summaries: [excluded()], filter: .all, expecting: .nothingToShowAnywhere)

        let copy = TransactionListStrings.emptyState(for: .nothingToShowAnywhere)
        #expect(copy.title == "Nothing to show")
        #expect(
            copy.message
                == "There's nothing to show here yet. Import another statement to see transactions.")
        // Never "Nothing imported yet": this person imported a statement, and telling them
        // otherwise says their import is gone.
        #expect(copy.title != "Nothing imported yet")
        #expect(rendered.hasInteractiveHost)
    }

    @Test("One account whose every row is excluded names that account and offers the filter back")
    func accountNothingToShow() async throws {
        let account = excluded()
        let expected = EmptyKind.accountNothingToShow(name: account.name)
        let rendered = try await render(
            summaries: [account],
            filter: .account(id: account.id, name: account.name, last4: account.last4),
            expecting: expected)

        let copy = TransactionListStrings.emptyState(for: expected)
        #expect(copy.title == "Nothing to show")
        #expect(copy.message == "There's nothing to show for \(account.name).")
        #expect(copy.action == .clearFilter)
        #expect(rendered.hasInteractiveHost)
    }

    // MARK: - Rendering

    private func excluded() -> AccountSummary {
        AccountSummary(
            id: "account-1", name: "Everyday Savings", last4: "1123", isCreditCard: false,
            currency: "INR", liveTransactionCount: 0, hasOnlyExcludedRows: true)
    }

    /// What a rendered screen turned out to be, in the only terms a unit test can read it.
    private struct Rendered {
        /// Some tappable host is on screen. ⚠️ **Which** host depends on the button's style, and
        /// that difference is design note D2 showing through: the state with no accounts has no
        /// filter bar to compete with, so its action is the screen's one prominent glass element
        /// and renders as a `UIPlatformGlassInteractionView`; the other two sit above a filter
        /// bar, take the plain glass style, and render as a hosted `UIButton`. Matching either
        /// keeps this assertion about *an action being present* rather than about which
        /// SwiftUI style produced it.
        let hasInteractiveHost: Bool
        let hasSpinner: Bool
        let types: [String]
    }

    /// Decide the state, put the real view on screen for it, and report what came out.
    ///
    /// The model is driven **before** the view is built and its state is asserted first, so a
    /// rendering failure and a state-machine failure cannot be mistaken for one another.
    private func render(
        summaries: [AccountSummary],
        filter: AccountFilter,
        expecting kind: EmptyKind
    ) async throws -> Rendered {
        let history = HistoryDouble(
            pages: [HistoryPage(rows: [], cursor: nil)], summaries: summaries)
        let model = TransactionListViewModel(history: history, clock: listClock)
        if filter == .all {
            await model.onAppear()
        } else {
            await model.setFilter(filter)
        }
        #expect(model.state == .empty(kind))

        let controller = UIHostingController(
            rootView: NavigationStack {
                TransactionListView(filter: filter, model: model) {}
            })
        // ⚠️ The window is attached to the **host app's own scene**. A detached `UIWindow` has
        // no display link, so SwiftUI renders it once and then stops: the view's `.task` sets
        // the state back to `.loading`, finishes, and nothing ever draws the result — the first
        // version of this file watched a spinner for two seconds while the model beside it was
        // already in the state under test.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive }
        window.windowScene = active ?? scenes.first
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        // ⚠️ **Suspend, do not block.** The view's own `.task` re-runs `onAppear()` when it
        // appears, so the screen is a `ProgressView` until that finishes — and the first
        // version of this file waited with `RunLoop.main.run(until:)`, which occupies the main
        // actor and so guarantees the continuation it is waiting for can never resume. It
        // rendered a spinner for two seconds and failed for a reason that had nothing to do
        // with the state under test.
        var rendered = Self.describe(controller.view)
        for _ in 0..<40 where rendered.hasSpinner || !rendered.hasInteractiveHost {
            try await Task.sleep(for: .milliseconds(50))
            controller.view.layoutIfNeeded()
            rendered = Self.describe(controller.view)
        }
        #expect(rendered.hasSpinner == false, "still loading: \(rendered.types)")
        return rendered
    }

    /// Walk the UIKit hierarchy SwiftUI produced and name what is in it.
    ///
    /// Type names, because they are the only thing this hierarchy publishes: a
    /// `ContentUnavailableView` renders its title and message as drawn text, so the presence of
    /// a hosted button and the absence of an activity indicator is the whole of what a unit
    /// test can see. It is enough to tell "the empty state built" from "the view is still
    /// loading" and from "a list rendered instead", which is what this file claims.
    private static func describe(_ view: UIView) -> Rendered {
        var types: [String] = []
        collectTypes(view, into: &types)
        return Rendered(
            hasInteractiveHost: types.contains {
                $0.contains("Button") || $0.contains("GlassInteraction")
            },
            hasSpinner: types.contains { $0.contains("ActivityIndicator") },
            types: types)
    }

    private static func collectTypes(_ view: UIView, into types: inout [String]) {
        types.append(String(describing: type(of: view)))
        for subview in view.subviews { collectTypes(subview, into: &types) }
    }
}
