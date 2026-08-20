import Foundation
import KanameCore
import Testing

@testable import Kaname

/// **K3** and **K4** — what the picker offers, and which one of them it marks.
///
/// Both are asserted here rather than on a rendered picker, because both are decisions about
/// *what is true*, not about what is drawn: "no category is something a person can choose" and
/// "the current category is the one with this id". A test that had to render a sheet to check
/// either would be a test that stops being run.
@Suite("What the category picker offers, and what it marks as current")
struct CategoryPickerTests {
    private static func category(
        _ id: String, _ name: String, _ classification: Classification?
    ) -> KanameCore.Category {
        KanameCore.Category(
            categoryRef: .builtin(code: id), name: name, classification: classification)
    }

    private static let catalog: [KanameCore.Category] = [
        category("GROCERIES", "Groceries", .spend),
        category("SALARY", "Salary", .income),
    ]

    /// **K4** — FR-007. A person can say "this belongs nowhere", and that is a decision the
    /// engine records with their own provenance, not an absence of one.
    @Test("No category is an offered choice, not only a state a transaction can be left in")
    func noCategoryIsOffered() {
        let offering = CategoryCatalog.offering(Self.catalog)

        #expect(offering.blank == .none)
        #expect(offering.blank.reference == nil, "the blank must reach the engine as a blank")
        #expect(offering.blank.name == nil)
        // And it is offered even when the engine knows no categories at all — the one choice
        // that cannot depend on the catalog.
        #expect(CategoryCatalog.offering([]).blank == .none)
    }

    @Test("The offering holds every category the engine knows, beside the blank")
    func theOfferingIsTheEnginesCatalog() {
        let offering = CategoryCatalog.offering(Self.catalog)
        let names = offering.groups.flatMap { $0.categories.map(\.name) }

        #expect(names == ["Groceries", "Salary"])
    }

    /// **K3** — FR-005. The mark is an identity, and this is the assertion that fails if it
    /// ever becomes a display-name match.
    @Test("The current category is marked by id, and a shared display name marks only one")
    func theMarkIsAnIdentityNotAName() {
        // Two categories, one name. Legitimate — a person may rename a custom category to a
        // built-in's words — and fatal to any mark resolved by matching text.
        let groceries = CategoryChoice(Self.category("GROCERIES", "Groceries", .spend))
        let ownGroceries = CategoryChoice(
            KanameCore.Category(
                categoryRef: .custom(id: "custom-1"), name: "Groceries", classification: .spend))

        #expect(groceries.isCurrent("GROCERIES"))
        #expect(!ownGroceries.isCurrent("GROCERIES"), "a display-name match marked both")
        #expect(ownGroceries.isCurrent("custom-1"))
    }

    @Test("A transaction with no category marks the blank, and nothing else")
    func anUnfiledTransactionMarksTheBlank() {
        let offering = CategoryCatalog.offering(Self.catalog)

        #expect(offering.blank.isCurrent(nil))
        for group in offering.groups {
            for category in group.categories {
                #expect(!CategoryChoice(category).isCurrent(nil))
            }
        }
    }
}
