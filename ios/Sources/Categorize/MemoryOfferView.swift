import KanameCore
import SwiftUI

/// What the app can offer to remember after a correction, and the rule that decides which.
///
/// **M3** lives here rather than inside a view body (FR-027d): "is there anything to remember?"
/// is a question about what is *true* after a correction, not about what is drawn, and a rule
/// that can only be checked by rendering a sheet is a rule that stops being checked. The same
/// argument `CategoryChoice.isCurrent` is made by, one surface over.
enum MemoryOffer: Equatable, Identifiable {
    /// Something specific enough to recognise on another statement, filed somewhere.
    case remember(portion: String, categoryName: String)
    /// Nothing to learn — and the app says so rather than showing an empty offer.
    case nothingToRemember

    var id: String {
        switch self {
        case .remember(let portion, let categoryName): "remember:\(portion):\(categoryName)"
        case .nothingToRemember: "nothing"
        }
    }

    /// **M3** — what a correction leaves the app able to offer.
    ///
    /// Two ways to have nothing, and they are one case because they are one thing to a person:
    /// the engine derived no portion from the narration, and the person deliberately filed the
    /// transaction under **no category** — a memory of blankness would refill the worklist
    /// forever, which is why the engine refuses to form one either.
    ///
    /// ⚠️ A portion that is present but blank is also nothing. The engine does not return one
    /// (`merchant_portion` is trimmed and never empty), and this checks anyway: an offer
    /// quoting `“”` back at a person is the degenerate case FR-027d names, and it would be
    /// indistinguishable from a bug in their own statement.
    static func decide(_ outcome: CorrectionOutcome, chosen: CategoryChoice) -> MemoryOffer {
        guard let categoryName = chosen.name,
            let portion = outcome.merchantPortion,
            !portion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .nothingToRemember }
        return .remember(portion: portion, categoryName: categoryName)
    }
}

/// After a correction: what Kaname would learn from it, in the person's words.
///
/// The screen has one job — to ask (M1) — and one property that matters more than the asking:
/// **declining costs the person nothing** (M2, FR-028). The correction is already recorded with
/// their own provenance by the time this appears, so "Not now" closes a sheet and leaves a
/// transaction filed exactly where they filed it. Nothing here can undo that, and nothing here
/// says it might.
///
/// The merchant portion is the **engine's** (M4, FR-021, FR-076): `merchant_portion` is a
/// closed four-step rule with a fixed stop-list and a fixed segment count, and a second
/// implementation of it in Swift would agree with the first until the day it did not — on
/// somebody's own statement, with a memory keyed on a portion the engine cannot match.
///
/// 🚨 **A memory outranks everything, and the wording here must not promise more than that**
/// (plan § *Judgement calls* §2). The memory is consulted by the store *beside* the stack, so
/// it wins over every stage including the India-specific credit-card narration rules — which is
/// FR-032 working as intended, and a real change in the system's observable precedence. Two
/// things follow for whoever edits these sentences:
///
/// - **The offer may not explain that precedence.** There is no way to say "this outranks the
///   credit-card narration rules" without the engine's vocabulary, which FR-029 bans outright.
///   Whether a person should be told at all is deliberately unanswered by the plan and is not
///   this slice's to decide.
/// - **The offer may not promise more than engine test M2 asserts.** What is actually
///   guaranteed is that a *future import* of a row deriving to this portion lands in this
///   category. It is not a promise about rows already imported — those are the second action's,
///   stated separately and only after the person is told how many and where.
struct MemoryOfferView: View {
    let offer: MemoryOffer
    /// Forms the memory this offer describes: the same correction, asked to be remembered.
    /// Supplied by the surface that made the correction, so this view knows only the words.
    let form: () async -> CorrectionOutcome?
    let service: CategorizeWriting
    /// Hands the blast radius back, for the surface that presents the second action. Called
    /// only when the engine says there is something to state.
    let onImpact: (MemoryImpact) -> Void

    @State private var step = Step.offering
    @Environment(\.dismiss) private var dismiss

    private enum Step: Equatable {
        case offering
        case working
        /// Learned, and there is nothing else to change — so this screen says so itself rather
        /// than closing on a person with no word about what happened.
        case remembered(portion: String)
        case failed
    }

    /// ⚠️ **No `NavigationStack`, and no navigation title.** A sheet does not need a bar, and
    /// putting one here would cost twice: an inline title is a single line that truncates, and
    /// the question this screen asks is a sentence rather than a noun. The headline is a `Text`
    /// in the content, where it wraps at every text size.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text(explanation)
                    .font(.body)
                    .foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        // The actions own their own safe-area inset, the same shape the detail surface uses —
        // and for the same reason: a button drawn below the text is a button the text can push
        // off the bottom of the screen at an accessibility size (D6).
        .safeAreaBar(edge: .bottom) { actions }
    }

    private var title: String {
        switch (step, offer) {
        case (.remembered, _), (_, .remember): CategorizeStrings.memoryOfferTitle
        case (_, .nothingToRemember): CategorizeStrings.nothingToRememberTitle
        }
    }

    private var explanation: String {
        switch (step, offer) {
        case (.remembered(let portion), _):
            CategorizeStrings.memoryRemembered(portion: portion)
        case (.failed, _):
            CategorizeStrings.changeFailed
        case (_, .remember(let portion, let categoryName)):
            CategorizeStrings.memoryOffer(portion: portion, category: categoryName)
        case (_, .nothingToRemember):
            CategorizeStrings.nothingToRememberBody
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 8) {
            switch (step, offer) {
            case (.offering, .remember), (.failed, .remember), (.working, _):
                SheetAnswer(CategorizeStrings.memoryOfferAccept) { Task { await accept() } }
                    .prominentAction()
                    .disabled(step == .working)
                SheetAnswer(CategorizeStrings.memoryOfferDecline) { dismiss() }
            default:
                SheetAnswer(CategorizeStrings.memoryOfferDone) { dismiss() }
                    .prominentAction()
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.background)
    }

    /// Learn it, then ask the engine what that would mean for the rows the person already has.
    ///
    /// The preview is read-only and the *only* source of the blast radius: this view never
    /// counts, filters or guesses at which transactions a memory reaches (S3, FR-078). When the
    /// engine says nothing else would change, nothing else is offered — a second action stating
    /// "0 transactions" is a question with no answer.
    private func accept() async {
        step = .working
        guard case .remember(let portion, _) = offer, let outcome = await form(),
            outcome.memoryFormed
        else {
            step = .failed
            return
        }
        guard let impact = try? await service.previewMemory(portion),
            !impact.transactionIds.isEmpty
        else {
            step = .remembered(portion: portion)
            return
        }
        onImpact(impact)
        dismiss()
    }
}

/// One answer on a sheet: the words, and a control big enough to hit them with (FR-062).
///
/// ⚠️ **A glass button does not give you 44 pt.** The second action's primary answer measured
/// **34.33 pt** tall at the *default* text size — and it was a geometry assertion that said so,
/// not the accessibility auditor, whose own hit-target check has never once fired on this
/// repository's controls (the same finding A12 records for the picker). The minimum has to be
/// on the **label**: `.buttonStyle` draws its background around what the label asks for, so a
/// frame applied outside the styled button sizes the space around a control that stayed small.
struct SheetAnswer: View {
    private let title: String
    private let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}
