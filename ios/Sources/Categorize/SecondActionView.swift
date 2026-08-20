import KanameCore
import SwiftUI

/// One memory, and everything the engine says applying it to the rows a person already has
/// would change.
///
/// Carried as one value so the screen cannot be presented without its blast radius: a second
/// action that renders before it knows how much it would change is a second action that can
/// ask the question wrongly, however briefly.
struct SecondActionRequest: Identifiable, Equatable {
    let portion: String
    let categoryName: String
    let impact: MemoryImpact

    var id: String { portion }

    /// **S1**, **S3** — the radius as the screen states it, in the engine's numbers.
    ///
    /// The count is the length of the list the engine returned. It is not a sum, not a
    /// re-count of the accounts, and not a second query — those three would agree with this
    /// one right up until a row was corrected by hand between the preview and the render, at
    /// which point the screen would state a number nobody could act on.
    var statedCount: Int { impact.transactionIds.count }

    var statedSummary: String {
        CategorizeStrings.secondActionSummary(
            count: statedCount, portion: portion, category: categoryName)
    }

    /// One line per `AccountImpact`, in the engine's order, each carrying that account's own
    /// name and number (**S1**, FR-035c).
    var statedAccountLines: [String] {
        impact.accounts.map {
            CategorizeStrings.secondActionAccount(name: $0.displayName, count: Int($0.count))
        }
    }
}

/// How applying one memory ended.
///
/// A named outcome rather than a `Bool` and a thrown error, because the three endings mean
/// three different things to a person and exactly one of them is worth acting on: `setChanged`
/// says *your data moved*, and it is the ending this type exists to keep distinguishable
/// (S5, FR-035f, SC-027).
enum SecondActionOutcome: Equatable {
    case applied(count: UInt32)
    case setChanged
    case failed

    /// **S4**, **S5** — one call, with the ids the preview handed over, unmodified.
    ///
    /// 🚨 There is deliberately no retry arm and no second call site. Recomputing the set after
    /// a refusal, or trimming it before the first attempt, would each look reasonable and each
    /// break the one promise the screen makes: that what a person was shown is what changes.
    /// The engine refuses both; this is where a caller would be tempted to work around it, so
    /// this is where the absence is asserted (**S5**, test in `CategorizeServiceTests`).
    static func apply(
        _ request: SecondActionRequest, through service: CategorizeWriting
    ) async -> SecondActionOutcome {
        do {
            let changed = try await service.applyMemory(
                request.portion, expecting: request.impact.transactionIds)
            return .applied(count: changed)
        } catch MemoryApplicationError.setChanged {
            return .setChanged
        } catch {
            return .failed
        }
    }
}

/// The second action: applying one memory — the one just formed — to the transactions a person
/// already has.
///
/// 🚨 **This is the surface most able to become something the spec forbids.** Everything below
/// exists to keep it from becoming a bulk editor:
///
/// - It states the radius **before** the person agrees, in the engine's own numbers and account
///   names (S1, FR-035a, FR-035c). Nothing here counts, filters, sorts or re-derives — the
///   count is the length of the list the engine returned and the accounts are the list the
///   engine returned (S3, FR-043, FR-078).
/// - It offers **no choice of which transactions** (S2, FR-035b). There is no checkbox, no
///   multi-select and no "select all", and there is nowhere for one to be added: the only thing
///   this view can hand the engine is the whole list it was given.
/// - ⚠️ **S2 is a rule about this screen; it is not the enforcement.** The enforcement is
///   engine-side set equality (`contracts/engine-categorize.md` §2.4, test M7): `apply_memory`
///   recomputes the affected set inside its own transaction and refuses **any** difference,
///   including a caller that trimmed the list. A UI without a checkbox proves nothing about a
///   future UI, which is exactly why the guarantee does not live here (SC-028).
/// - Rows a person corrected **by hand** are neither counted nor changed (S6, FR-035d). That is
///   also the engine's doing — its affected-set predicate excludes a person's own provenance —
///   and this screen displays that truth rather than reproducing the rule.
struct SecondActionView: View {
    let request: SecondActionRequest
    let service: CategorizeWriting
    /// Called once rows have actually changed, with the engine's own count, so the surface
    /// behind this one can show what a person now has.
    var onApplied: (UInt32) -> Void = { _ in }

    @State private var step = Step.asking
    @Environment(\.dismiss) private var dismiss

    private enum Step: Equatable {
        case asking
        case working
        case applied(count: UInt32)
        /// 🚨 The rows moved while the offer was open. **Nothing was written**, and nothing is
        /// retried: a silent retry with a fresh set is precisely the bulk edit a person never
        /// agreed to (S5, FR-035f, SC-027).
        case setChanged
        case failed
    }

    /// ⚠️ No navigation bar, for `MemoryOfferView`'s reason: the headline is a question, and a
    /// question truncated to one inline line is a question a person cannot answer.
    var body: some View {
        List {
            Section {
                Text(CategorizeStrings.secondActionTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text(summary)
                    .font(.body)
                    .foregroundStyle(Color.primary)
            }

            if isAsking {
                accountsSection
            }
        }
        .listStyle(.plain)
        .safeAreaBar(edge: .bottom) { actions }
    }

    /// **S1** — where the change lands. One row per `AccountImpact`, in the order the engine
    /// listed them, each carrying that account's own count.
    private var accountsSection: some View {
        Section {
            ForEach(request.statedAccountLines, id: \.self) { line in
                Text(line)
                    .font(.body)
            }
        } header: {
            // An explicit `Text`, not `Section("…")`: the system auditor reports a string
            // header as an element whose font size a person cannot change.
            Text(CategorizeStrings.secondActionAccountsHeading)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
        }
    }

    /// Whether the question is still being asked — the two steps that still show the radius.
    private var isAsking: Bool { step == .asking || step == .working }

    private var summary: String {
        switch step {
        case .applied(let count): CategorizeStrings.secondActionChanged(count: Int(count))
        case .setChanged: CategorizeStrings.secondActionStale
        case .failed: CategorizeStrings.secondActionFailed
        case .asking, .working: request.statedSummary
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 8) {
            switch step {
            case .asking, .working:
                SheetAnswer(CategorizeStrings.secondActionApply) { Task { await apply() } }
                    .prominentAction()
                    .disabled(step == .working)
                // **S7** — declining leaves the memory formed and the correction intact. Only
                // the bulk application is declined, and the wording says nothing else is.
                SheetAnswer(CategorizeStrings.secondActionDecline) { dismiss() }
            default:
                SheetAnswer(CategorizeStrings.memoryOfferDone) { dismiss() }
                    .prominentAction()
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.background)
    }

    /// **S4**, **S5** — one call, through the rule that owns it.
    ///
    /// The view decides what to draw; it does not decide what to send. `SecondActionOutcome`
    /// carries the whole of that, which is why a test can watch a refusal without rendering a
    /// sheet — and why there is nowhere here for a retry to be added.
    private func apply() async {
        step = .working
        switch await SecondActionOutcome.apply(request, through: service) {
        case .applied(let count):
            step = .applied(count: count)
            onApplied(count)
        case .setChanged: step = .setChanged
        case .failed: step = .failed
        }
    }
}
