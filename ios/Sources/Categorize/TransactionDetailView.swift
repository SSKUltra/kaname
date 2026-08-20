import KanameCore
import SwiftUI

/// One transaction, in full, with the one thing a person can change about it.
///
/// The screen answers two questions and no others: *what is this transaction*, and *what does
/// Kaname currently think it is* (D1). It says the second in the app's own words — never in the
/// engine's (D3, FR-029): which stage decided, which rule matched and what provenance was
/// written are true, internal, and no help at all to somebody looking at their own statement.
///
/// It is a plain `List`, opaque, for the same reason the transaction list is (FR-068): figures
/// are read, not decorated. The one glass element is the action, through `Theme`'s
/// `prominentAction()` so the fill and the style cannot come apart (D5, SC-021).
struct TransactionDetailView: View {
    let row: TransactionRow
    /// The category currently on this transaction, by **id** — the picker marks the current
    /// choice by identity, never by matching a display name (K3, FR-005).
    @State private var categoryID: String?
    @State private var categoryName: String?
    @State private var isPicking = false
    @State private var failed = false
    /// What the app can offer to remember, once a correction has been recorded. Presented as
    /// its own sheet rather than as a banner: an offer a person can miss is an offer that
    /// teaches the app nothing, and one they cannot decline is not an offer.
    @State private var offer: MemoryOffer?
    /// The choice the offer is about, kept so accepting it can make the **same** correction
    /// again, asked to be remembered. The engine's write is idempotent, so a person who says
    /// yes gets one category and one memory, not two of either.
    @State private var chosen: CategoryChoice?
    /// Handed over by the offer and presented once its sheet has closed. Two sheets in
    /// sequence, through `onDismiss`, because presenting the second while the first is still
    /// going is how a sheet quietly fails to appear.
    @State private var pendingSecondAction: SecondActionRequest?
    @State private var secondAction: SecondActionRequest?
    private let service: CategorizeWriting
    private let onChange: (String, String?) -> Void

    /// - Parameter onChange: called with `(transactionID, newCategoryName)` after the engine
    ///   has recorded the decision, so the list behind this screen shows the new category
    ///   without the person having to refresh anything (K5, FR-006, SC-003).
    init(
        row: TransactionRow,
        service: CategorizeWriting,
        onChange: @escaping (String, String?) -> Void = { _, _ in }
    ) {
        self.row = row
        self.service = service
        self.onChange = onChange
        _categoryID = State(initialValue: row.categoryID)
        _categoryName = State(initialValue: row.categoryName)
    }

    var body: some View {
        List {
            Section {
                fact(CategorizeStrings.descriptionHeading, row.displayDescription)
                fact(CategorizeStrings.amountHeading, row.formattedAmount, monospaced: true)
                fact(CategorizeStrings.dateHeading, row.longDate)
                fact(CategorizeStrings.accountHeading, row.accountIdentity, monospaced: true)
            }

            Section {
                // The category and the action that changes it, together: the primary action is
                // the first thing under the fact it acts on, so it is reachable without
                // scrolling at the default text size (D6, FR-004).
                // Drawn as a fact like the other four, rather than as a bare `Text` carrying
                // an `.accessibilityLabel`.
                //
                // ⚠️ Not a tidy-up. A `Text` with an accessibility label applied directly to it
                // becomes a node the system auditor reports as **"User will not be able to
                // change the font size of this element"**, even with `.font(.body)` on it —
                // watched, twice, at the default text size in Light and in Dark. The combined
                // element the other facts use does not have that problem, which is the whole
                // reason this screen has one way of stating a fact instead of two.
                fact(
                    CategorizeStrings.categoryHeading,
                    categoryName ?? CategorizeStrings.uncategorized)
            }

            if failed {
                Section {
                    Text(CategorizeStrings.changeFailed)
                        .font(.footnote)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(CategorizeStrings.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        // The one action, in a bar that owns its own safe-area inset — the same shape the
        // front door uses, and the only arrangement that satisfies D6 at *every* text size
        // rather than at the default one: a button inside the list is a button that four
        // facts can push off the bottom of the screen (FR-004).
        //
        // ⚠️ It is also what the system auditor required. Inside a `List` row the prominent
        // button was reported as **"User will not be able to change the font size of this
        // element"**, at the default text size, in Light and in Dark. Watched three times, on
        // three different elements, before this shape passed.
        .safeAreaBar(edge: .bottom) { action }
        .sheet(isPresented: $isPicking) {
            CategoryPickerView(currentCategoryID: categoryID, service: service) { chosen in
                Task { await apply(chosen) }
            }
        }
        // ⚠️ The hand-over happens in `onDismiss`, not at the moment the offer decides. A
        // sheet presented while another is still dismissing is a sheet that sometimes never
        // appears, and "sometimes" here means a person is silently never asked.
        .sheet(item: $offer, onDismiss: presentSecondActionIfAny) { offer in
            MemoryOfferView(
                offer: offer, form: formMemory, service: service,
                onImpact: { impact in
                    guard case .remember(let portion, let categoryName) = offer else { return }
                    pendingSecondAction = SecondActionRequest(
                        portion: portion, categoryName: categoryName, impact: impact)
                })
        }
        .sheet(item: $secondAction) { request in
            SecondActionView(request: request, service: service) { _ in
                // ⚠️ **A second action changes rows this screen is not showing**, and the list
                // behind it is holding a copy of every one of them. Without this the person
                // agrees to a change, goes back, and reads their old categories — the exact
                // defect K5 exists to prevent, one action over. The list re-reads through the
                // same seam a single correction uses; it never patches its own rows.
                onChange(row.id, categoryName)
            }
        }
    }

    /// The screen's one action, and its one piece of glass — through `Theme`'s
    /// `prominentAction()`, so the style and the fill it was measured with cannot come apart
    /// (D5, SC-021). The bar itself is opaque: a glass label over a person's own figures is
    /// where contrast goes (FR-068).
    private var action: some View {
        Button(CategorizeStrings.changeCategory) { isPicking = true }
            .prominentAction()
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.background)
    }

    /// One fact, as a label and its value. Not `LabeledContent`, for 018's reason: it picks its
    /// own axis and renders the value in a de-emphasised style, which is content demoted to
    /// decoration (FR-066).
    private func fact(_ heading: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(heading)
                .font(.caption)
                .foregroundStyle(Color.secondary)
            Text(value)
                .font(.body)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(heading): \(value)")
        .padding(.vertical, 2)
        .modifier(MonospacedIfMoney(enabled: monospaced))
    }

    /// Record the decision, then show what the engine recorded — never what was asked for. A
    /// screen that shows the chosen category before the engine confirmed it is a screen that
    /// can lie about a person's own data.
    ///
    /// The correction is written **without** a memory (M2, FR-028): what the app would learn
    /// from it is a second question, asked separately, and a person who never answers it still
    /// gets the change they made. The engine populates `merchant_portion` either way, which is
    /// what lets the offer state exactly what it would remember without having remembered it.
    private func apply(_ chosen: CategoryChoice) async {
        do {
            let outcome = try await service.correct(row.id, to: chosen.reference, remember: false)
            categoryID = chosen.id
            categoryName = chosen.name
            failed = false
            onChange(row.id, chosen.name)
            self.chosen = chosen
            offer = MemoryOffer.decide(outcome, chosen: chosen)
        } catch {
            failed = true
        }
        isPicking = false
    }

    /// Make the same correction again, this time asked to be remembered. Idempotent in the
    /// engine — one `UPDATE` to the same category, one upsert of one memory.
    private func formMemory() async -> CorrectionOutcome? {
        guard let chosen else { return nil }
        return try? await service.correct(row.id, to: chosen.reference, remember: true)
    }

    private func presentSecondActionIfAny() {
        secondAction = pendingSecondAction
        pendingSecondAction = nil
    }
}

/// Tabular figures for money, and nothing else — the same treatment 018 gives an amount, so a
/// column of digits lines up wherever it is drawn (D4, Constitution II).
private struct MonospacedIfMoney: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.monospacedDigit()
        } else {
            content
        }
    }
}
