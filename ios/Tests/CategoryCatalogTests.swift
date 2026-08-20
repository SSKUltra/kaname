import Foundation
import KanameCore
import Testing

@testable import Kaname

/// **U1** — the picker's grouping is a pure function of the catalog, and a deterministic one.
///
/// The grouping is where a taxonomy gets quietly invented. The engine already decides which
/// categories exist and which money bucket each one belongs to; the only thing the platform is
/// allowed to do is put them in that order and draw them (K1, K2, FR-016). Asserting it here —
/// with no simulator, no seeded store and no engine call — is what stops "Spend" becoming a
/// word the app made up, and stops the order of a person's own categories changing between two
/// launches for no reason they could ever see (K6, FR-017).
@Suite("How the category picker groups what the engine knows")
struct CategoryCatalogTests {
    private static func category(
        _ id: String,
        _ name: String,
        _ classification: Classification?
    ) -> KanameCore.Category {
        KanameCore.Category(
            categoryRef: .builtin(code: id),
            name: name,
            classification: classification
        )
    }

    private static let full: [KanameCore.Category] = [
        category("GROCERIES", "Groceries", .spend),
        category("SALARY", "Salary", .income),
        category("MUTUAL_FUNDS", "Mutual Funds", .investment),
        category("SELF_TRANSFER", "Self Transfer", .transfer),
        category("CREDIT_CARD_BILL_PAYMENT", "Credit Card Bill Payment", .ccPayment),
        category("REFUNDS", "Refunds", .refund),
        category("FOOD_AND_DINING", "Food and Dining", .spend),
    ]

    @Test("An empty catalog groups into nothing at all, rather than into an empty group")
    func anEmptyCatalogHasNoGroups() {
        #expect(CategoryCatalog.grouped([]).isEmpty)
    }

    @Test("A catalog of one classification is exactly one group, holding all of it")
    func oneClassificationIsOneGroup() {
        let spend = Self.full.filter { $0.classification == .spend }
        let groups = CategoryCatalog.grouped(spend)

        #expect(groups.count == 1)
        #expect(groups.first?.classification == .spend)
        #expect(groups.first?.categories.count == spend.count)
    }

    @Test("Every category the engine knows appears exactly once, under its own classification")
    func everyCategoryIsPlacedUnderItsOwnClassification() {
        let groups = CategoryCatalog.grouped(Self.full)

        let placed = groups.flatMap(\.categories)
        #expect(placed.count == Self.full.count, "a category was dropped or duplicated")
        for group in groups {
            for category in group.categories {
                #expect(
                    category.classification == group.classification,
                    "\(category.name) is filed under \(group.classification)"
                )
            }
        }
    }

    /// K6 — the same catalog renders the same way every time.
    ///
    /// ⚠️ Stated as "the same catalog, twice", not "the catalog in any order": the engine reads
    /// its catalog `ORDER BY rowid`, so what arrives is already fixed, and a platform-side sort
    /// on top of it would be a second opinion about an order the engine settled. What is
    /// asserted instead is that the grouping **preserves** the engine's order — which is the
    /// property that actually keeps a person's categories where they left them, and the one a
    /// `Dictionary(grouping:)` used carelessly would break.
    @Test("The same catalog groups the same way every time, in the engine's own order")
    func groupingIsDeterministic() {
        let once = CategoryCatalog.grouped(Self.full)
        let twice = CategoryCatalog.grouped(Self.full)

        #expect(once == twice)
        #expect(once.map(\.classification) == [.spend, .income, .investment, .transfer, .ccPayment, .refund])
        #expect(
            once.first?.categories.map(\.name) == ["Groceries", "Food and Dining"],
            "the engine's order within a group was not preserved"
        )
    }

    @Test("A category the engine gives no classification is still offered, never dropped")
    func anUnclassifiedCategoryIsStillOffered() {
        // `Category.classification` is optional in the engine, and a category a person cannot
        // see is a category they cannot choose — which reads as the app having lost it.
        let catalog = Self.full + [Self.category("CUSTOM", "Weekend Market", nil)]
        let placed = CategoryCatalog.grouped(catalog).flatMap(\.categories)

        #expect(placed.count == catalog.count)
        #expect(placed.contains { $0.name == "Weekend Market" })
    }
}
