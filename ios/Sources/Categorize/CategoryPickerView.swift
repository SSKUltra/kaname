import KanameCore
import SwiftUI

/// One thing a person can choose in the picker: a category the engine knows, or no category
/// at all.
///
/// "No category" is a **choice**, not the absence of one (K4, FR-007). Modelling it as a case
/// rather than as `nil` is what makes it something the picker can draw, announce and mark as
/// current — a person who deliberately files a transaction under nothing has decided, and the
/// engine records that decision as firmly as it records a category.
enum CategoryChoice: Equatable {
    case category(id: String, name: String, reference: CategoryRef)
    case none

    /// The engine's id, or `nil` for the deliberate blank.
    var id: String? {
        if case .category(let id, _, _) = self { return id }
        return nil
    }

    /// What the detail surface shows after the change lands.
    var name: String? {
        if case .category(_, let name, _) = self { return name }
        return nil
    }

    /// What is handed to the engine. `nil` **is** the deliberate blank — the engine writes a
    /// person's provenance either way, so the blank is protected exactly as a category is.
    var reference: CategoryRef? {
        if case .category(_, _, let reference) = self { return reference }
        return nil
    }

    init(_ category: KanameCore.Category) {
        self = .category(
            id: CategoryChoice.identifier(of: category.categoryRef),
            name: category.name,
            reference: category.categoryRef
        )
    }

    /// The `categories.id` a `CategoryRef` stores as — the built-in code, or the user id. The
    /// same identity the engine puts in `HistoryRow.category_id`, which is what lets the mark
    /// be an identity comparison rather than a string match on a display name.
    static func identifier(of reference: CategoryRef) -> String {
        switch reference {
        case .builtin(let code): code
        case .custom(let id): id
        }
    }

    /// **K3** — whether this is the choice currently on the transaction.
    ///
    /// An identity comparison, never a display-name match (FR-005). Two categories may
    /// legitimately be renamed to the same words; a mark resolved by name would then tick both
    /// of them, and after a rename it would tick the wrong one — telling a person their
    /// transaction is filed somewhere it is not.
    func isCurrent(_ currentCategoryID: String?) -> Bool {
        id == currentCategoryID
    }
}

/// Every category the engine knows, grouped the way the engine classifies them.
///
/// The view invents no taxonomy and no order (K1, K6): `CategoryCatalog` arranges what
/// `listCategories()` returned, and this draws it. The current category is marked by **id**
/// (K3, FR-005) — a mark resolved by display name would follow a rename onto the wrong row, and
/// would mark two categories at once the moment a person named two of them the same thing.
struct CategoryPickerView: View {
    let currentCategoryID: String?
    let service: CategorizeWriting
    let onChoose: (CategoryChoice) -> Void

    @State private var offering = CategoryCatalog.Offering.empty
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    choiceRow(offering.blank, label: CategorizeStrings.noCategoryChoice)
                } footer: {
                    Text(CategorizeStrings.noCategoryExplanation)
                }

                ForEach(offering.groups) { group in
                    Section {
                        ForEach(group.categories, id: \.name) { category in
                            choiceRow(CategoryChoice(category), label: category.name)
                        }
                    } header: {
                        // An explicit `Text` for the reason the detail surface's header is one:
                        // `Section("…")` renders a header that does not scale, and the system
                        // auditor says so in as many words.
                        Text(CategorizeStrings.groupHeading(group.classification))
                            .font(.subheadline)
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(CategorizeStrings.pickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // ⚠️ No `.buttonStyle(.glass)`. A toolbar in iOS 26 is already Liquid
                    // Glass, so applying the style again is not just redundant — the system
                    // auditor reported the result as **"User will not be able to change the
                    // font size of this element"**, at the default text size. The bar's own
                    // treatment scales; a style re-applied on top of it did not.
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(CategorizeStrings.cancel)
                }
            }
            .task { await load() }
        }
    }

    /// One choice. The whole row is the target — ≥44pt by construction, because a `Button` in
    /// a `List` row takes the row's height (K7, FR-062).
    private func choiceRow(_ choice: CategoryChoice, label: String) -> some View {
        Button {
            onChoose(choice)
            dismiss()
        } label: {
            HStack {
                Text(label)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                if isCurrent(choice) {
                    // A symbol, and a word for anyone who cannot see it — never a colour
                    // alone (FR-061, FR-071).
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(
            isCurrent(choice) ? "\(label), \(CategorizeStrings.currentCategoryAnnouncement)" : label
        )
    }

    /// **K3** — identity, never display name. The rule itself lives on `CategoryChoice`, so
    /// it can be asserted without rendering a picker.
    private func isCurrent(_ choice: CategoryChoice) -> Bool {
        choice.isCurrent(currentCategoryID)
    }

    private func load() async {
        offering = CategoryCatalog.offering((try? await service.categories()) ?? [])
    }
}
