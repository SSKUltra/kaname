import Foundation
import KanameCore

/// Every sentence the categorize surfaces can say.
///
/// Declared here rather than in a view body for the same reason 018's list strings are: what a
/// person reads about their own money is a fact worth asserting, and a literal inside a
/// `Text(...)` can only be checked by looking at it (T1, FR-064).
///
/// The words are chosen against one rule: a person reading them should recognise a sentence
/// about *their* transaction, not a report about how Kaname arrived at something. The engine's
/// own vocabulary — its stages, its tiers, its rules and its provenance — is precise, internal,
/// and completely meaningless here (T3, T4, FR-029). `CategorizeStringsTests` asserts that over
/// the whole table.
enum CategorizeStrings {
    // MARK: - The transaction

    /// The detail surface's title. Deliberately not the description: the description is on the
    /// screen already, at full length, and a title repeating it is a title saying nothing.
    static let detailTitle = "Transaction"

    /// The heading over what the app currently thinks this transaction is.
    static let categoryHeading = "Category"

    /// The word for a transaction nothing has filed yet.
    ///
    /// ⚠️ **Referenced, never redeclared** (T2, FR-002, SC-002). The list already has this word;
    /// a second spelling of it would be two names for one state, with nothing on either screen
    /// to say they are the same thing.
    static let uncategorized = TransactionListStrings.uncategorized

    // MARK: - The facts a transaction carries

    static let dateHeading = "Date"
    static let amountHeading = "Amount"
    static let accountHeading = "Account"
    static let descriptionHeading = "Description"

    // MARK: - The one action

    /// The primary action on the detail surface (D6, FR-004).
    static let changeCategory = "Change category"

    /// What the picker calls itself.
    static let pickerTitle = "Choose a category"

    /// Leaving the picker without changing anything.
    static let cancel = "Cancel"

    /// **K4** — having no category is a choice a person can make, not only a state they can be
    /// left in (FR-007). It is offered in the picker beside every real category.
    static let noCategoryChoice = "No category"

    /// What the picker says under that choice, so choosing it is not mistaken for cancelling.
    static let noCategoryExplanation = "Leave this transaction without a category."

    /// Spoken beside the category that is currently on the transaction, so a screen reader
    /// carries the mark a sighted person sees (K3, K7, FR-060).
    static let currentCategoryAnnouncement = "Current category"

    /// The hint on a row: what tapping it does, said plainly.
    static let rowHint = "Opens this transaction"

    /// Shown when the category could not be changed. It says what happened to the person's
    /// transaction — nothing — rather than what happened inside the app.
    static let changeFailed = "That category could not be saved. Your transaction is unchanged."

    /// The groups the picker draws, named as a person would name a kind of money rather than
    /// as the engine names a classification.
    static func groupHeading(_ classification: Classification?) -> String {
        switch classification {
        case .spend: "Spending"
        case .income: "Income"
        case .investment: "Investments"
        case .transfer: "Transfers"
        case .ccPayment: "Card payments"
        case .refund: "Refunds and cashback"
        case nil: "Everything else"
        }
    }

    /// Every classification, in the order the picker draws them, so the heading table and the
    /// grouping cannot disagree about which groups exist.
    static let everyGroupHeading: [String] =
        (CategoryCatalog.classificationOrder.map { Optional($0) } + [nil])
        .map(groupHeading)

    /// Every sentence in this table, gathered in one place so a new string cannot escape the
    /// audit by being added somewhere else.
    static var everySentence: [String] {
        [
            detailTitle, categoryHeading, uncategorized,
            dateHeading, amountHeading, accountHeading, descriptionHeading,
            changeCategory, pickerTitle, cancel,
            noCategoryChoice, noCategoryExplanation,
            currentCategoryAnnouncement, rowHint, changeFailed,
        ] + everyGroupHeading
    }
}
