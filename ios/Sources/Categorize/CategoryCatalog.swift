import Foundation
import KanameCore

/// The category catalog, arranged for the picker — and nothing else.
///
/// **Pure**: `[Category]` in, groups out (K2, FR-076). It holds no state, makes no engine call
/// and knows nothing about a transaction. That is what lets the whole of the picker's ordering
/// be asserted in `ios/Tests` with no simulator and no seeded store.
///
/// The taxonomy is the **engine's**. This type decides only the sequence the groups are drawn
/// in — a person's categories appearing in a different order on a different launch is a screen
/// they have to re-read every time (K6, FR-017), and `Dictionary(grouping:)` alone would do
/// exactly that.
enum CategoryCatalog {
    /// One classification's worth of categories, ready to draw.
    struct Group: Identifiable, Equatable {
        /// The engine's classification, or `nil` for categories it gives none — which are
        /// still offered, because a category a person cannot see is one they cannot choose.
        let classification: Classification?
        let categories: [KanameCore.Category]

        /// Stable across launches: derived from the classification, never from an index.
        var id: String { classification.map(String.init(describing:)) ?? "unclassified" }
    }

    /// The order the groups are drawn in: money coming in and going out first, because that is
    /// what most transactions are, then the movements that are not spending at all.
    ///
    /// A fixed list rather than a sort, so adding a classification to the engine is a compile
    /// error here rather than a silent change to where a person's categories appear.
    static let classificationOrder: [Classification] = [
        .spend, .income, .investment, .transfer, .ccPayment, .refund,
    ]

    /// Everything the picker draws, in the order it draws it.
    ///
    /// Pure, and it exists so that **K4** — "no category" is an *offered choice*, not only a
    /// state a person can be left in (FR-007) — is assertable without rendering anything. The
    /// blank is a member of the offering rather than a row the view happens to add, so a
    /// refactor that drops it fails a test instead of quietly removing a person's ability to
    /// say "this one belongs nowhere".
    struct Offering: Equatable {
        /// The deliberate blank. Always offered, always first: a person deciding a
        /// transaction has no category is deciding, and the engine records it as such.
        let blank: CategoryChoice
        let groups: [Group]

        static let empty = Offering(blank: .none, groups: [])
    }

    static func offering(_ catalog: [KanameCore.Category]) -> Offering {
        Offering(blank: .none, groups: grouped(catalog))
    }

    /// Group `catalog` by the engine's classification, in `classificationOrder`, keeping each
    /// group's categories **in the order the engine handed them over**.
    ///
    /// ⚠️ The categories are deliberately **not** re-ordered here. `list_categories()` reads
    /// `ORDER BY rowid`, so the catalog already arrives in one fixed sequence every launch, and
    /// a sort applied on top would be the platform having a second opinion about an order the
    /// engine already fixed — the same mistake, in miniature, that 018 spent a slice removing
    /// from the transaction list. `import-path-audit.sh`'s fifth scan now covers this directory
    /// and bans the spelling outright, which is how the question got asked at all.
    ///
    /// Empty groups are omitted — a heading with nothing under it is a category set a person
    /// would go looking for.
    static func grouped(_ catalog: [KanameCore.Category]) -> [Group] {
        let byClassification: [Classification?: [KanameCore.Category]] =
            Dictionary(grouping: catalog) { $0.classification }
        let hasUnclassified = byClassification[Classification?.none] != nil
        let order: [Classification?] =
            classificationOrder.map { Optional($0) } + (hasUnclassified ? [nil] : [])

        return order.compactMap { classification in
            guard let members = byClassification[classification], !members.isEmpty else {
                return nil
            }
            return Group(classification: classification, categories: members)
        }
    }
}
