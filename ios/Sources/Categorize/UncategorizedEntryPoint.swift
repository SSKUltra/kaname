import SwiftUI

/// The single door onto the transactions nobody has answered yet (E1, FR-041a).
///
/// One door, on the app's front door, opening the **same** transaction list by the same route
/// with the narrowing already in force — never a second renderer of transactions, and never a
/// second screen with its own ordering, paging or empty states (contract §2, FR-041a).
///
/// 🚨 **The number is the engine's.** It is one call to `uncategorizedCount()`, which counts in
/// the same SQL that defines the set (E2, FR-043, FR-043a). It is not a sum of
/// `AccountSummary`, not a length of anything this screen is holding, and not a tally kept
/// beside one: 018 deliberately moved the front door's count out of Swift and into SQL because
/// a count computed next to a list is a count that will eventually disagree with it, and this
/// is precisely the surface where it would creep back.
struct UncategorizedEntryPoint: View {
    let model: UncategorizedEntryPointModel

    var body: some View {
        // ⚠️ Nothing at all until the engine has answered. A door that renders "Everything has
        // a category" for the moment before the first read finishes tells a person they are
        // finished and then takes it back, which is worse than a door that arrives a frame
        // late. The reads themselves belong to the front door, which outlives every push made
        // from it — a `.task` attached here would be a subscription that dies with a row.
        if let sentence = model.sentence {
            NavigationLink(value: UncategorizedEntryPointModel.destination) {
                // ⚠️ **A plain `Text`, and not a `Label` with an SF Symbol.** Drawn as
                // `Label(sentence, systemImage: "tray.full")` this door was reported by the
                // system auditor as *"text may be clipped at larger Dynamic Type sizes"*, **at
                // the default text size**, in Light and in Dark — naming its own `StaticText`,
                // which is the rare attributable verdict. It is the same finding 020 PR D took
                // twice: state the fact the way the other facts on the screen are stated. The
                // account rows beside it are a `Text` in a combined element, and they pass.
                Text(sentence)
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(sentence)
            .accessibilityHint(CategorizeStrings.worklistHint)
        }
    }
}

/// What the door says, and when it says something else.
@MainActor
@Observable
final class UncategorizedEntryPointModel {
    /// Where the door goes: the whole store, narrowed to what nobody has answered (E4,
    /// FR-038, FR-041b). Both narrowings are set by this one route, which is what makes the
    /// count on the door and the rows behind it the same set.
    static let destination = TransactionScope(filter: .all, uncategorizedOnly: true)

    /// The engine's number, or `nil` until it has been asked. `nil` is also where a failed
    /// read lands: a door that cannot say how much work there is says nothing, rather than
    /// claiming a person is finished.
    private(set) var count: UInt32?

    private let service: CategorizeWriting

    init(service: CategorizeWriting) {
        self.service = service
    }

    /// The door's sentence — the count in words, or the finish in words (E3, FR-042b).
    ///
    /// **Zero is never rendered as "0".** Somebody who has filed everything is being told they
    /// are done; a counter reading zero is the app reporting the absence of work as though it
    /// were the absence of data.
    var sentence: String? {
        guard let count else { return nil }
        return count == 0
            ? CategorizeStrings.worklistFinished
            : CategorizeStrings.worklistWaiting(Int(count))
    }

    /// Ask the engine. One call, and whatever it says is what the door says.
    func refresh() async {
        count = try? await service.uncategorizedCount()
    }

    /// Keep the number current with whatever a correction or a memory commits (E5).
    ///
    /// The loop is the caller's — the door's own `.task` — so the subscription is cancelled
    /// with the screen and nothing outlives the view that asked for it. It re-**asks** rather
    /// than adjusting: the signal says something changed, and how much is a question only the
    /// engine can answer, particularly after a memory that changed rows in several accounts.
    func refreshWhenCategoriesChange(_ signal: CategoryChangeSignal = .shared) async {
        for await _ in signal.events {
            await refresh()
        }
    }
}

extension UncategorizedEntryPointModel {
    /// The app's own door, over the app's own encrypted store.
    static func live() -> UncategorizedEntryPointModel {
        UncategorizedEntryPointModel(service: CategorizeService.live())
    }
}
