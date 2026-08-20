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

    // MARK: - The memory offer

    /// **M1** — what the app is asking, before it learns anything (FR-026).
    static let memoryOfferTitle = "Remember this for next time?"

    /// **M1**, **M4** — the offer itself, showing the portion the **engine** derived, verbatim
    /// and in quotation marks so a person can see exactly how much of their description Kaname
    /// took (FR-026a). Nothing here is derived on this side of the bridge.
    static func memoryOffer(portion: String, category: String) -> String {
        "When a transaction says “\(portion)”, Kaname will file it under \(category)."
    }

    static let memoryOfferAccept = "Remember it"

    /// **M2** — declining, said as a person would decline: not an error, not a cancellation,
    /// and with nothing in the wording to suggest the correction is at stake (FR-028).
    static let memoryOfferDecline = "Not now"

    /// **M3** — nothing was specific enough to recognise again, or the person deliberately
    /// filed the transaction under nothing. Either way the app says so plainly and offers
    /// nothing (FR-027d).
    static let nothingToRememberTitle = "Nothing to remember here"

    static let nothingToRememberBody =
        "There is nothing in this transaction Kaname could recognise on another statement. "
        + "Your change is saved."

    /// What the offer says once it has learned something and there is nothing else to change.
    static func memoryRemembered(portion: String) -> String {
        "Kaname will remember “\(portion)” from now on."
    }

    static let memoryOfferDone = "Done"

    // MARK: - The second action

    /// **S1** — the question, asked before anything is written (FR-035a).
    static let secondActionTitle = "Change the ones you already have?"

    /// **S1**, **S3** — the blast radius, in the engine's numbers. `count` is the length of the
    /// list the engine returned; nothing on this side counts anything.
    static func secondActionSummary(count: Int, portion: String, category: String) -> String {
        let transactions = count == 1 ? "1 transaction" : "\(count) transactions"
        return "\(transactions) already say “\(portion)”. Kaname can file them under "
            + "\(category) too."
    }

    /// **S1** — which accounts they are in, so a person is told where the change lands and not
    /// only how much of it there is (FR-035c).
    static let secondActionAccountsHeading = "Where they are"

    /// One account's share, from `AccountImpact` — its name and its own count, both the
    /// engine's.
    static func secondActionAccount(name: String, count: Int) -> String {
        let transactions = count == 1 ? "1 transaction" : "\(count) transactions"
        return "\(name): \(transactions)"
    }

    static let secondActionApply = "Change them"

    /// **S7** — declining changes nothing that was already decided: the correction stands and
    /// the memory stays learned (FR-028).
    static let secondActionDecline = "Leave them as they are"

    static func secondActionChanged(count: Int) -> String {
        count == 1 ? "1 transaction changed." : "\(count) transactions changed."
    }

    /// **S5** — the one failure a person can act on, said as a fact about *their* data rather
    /// than about the app: the rows moved while the offer was open, so the offer is no longer
    /// about what it said it was (FR-035f, SC-027).
    ///
    /// ⚠️ Deliberately not "something went wrong". Told that things changed, a person looks
    /// again; told that something went wrong, they try the same thing twice.
    static let secondActionStale =
        "These transactions changed while this was open, so nothing here was changed. "
        + "Take another look."

    static let secondActionFailed =
        "Those transactions could not be changed. Nothing was changed."

    // MARK: - The worklist

    /// **E2**, **E3** — the door onto the transactions nobody has answered yet.
    ///
    /// The number is the **engine's**, counted in the same query that defines the set
    /// (FR-043). This sentence only says it, which is why it takes a count rather than
    /// anything it could count for itself.
    static func worklistWaiting(_ count: Int) -> String {
        count == 1 ? "1 transaction needs a category" : "\(count) transactions need a category"
    }

    /// **E3** — nothing is waiting. Said as the finish it is, and never as a "0": a person who
    /// has filed everything is being told they are done, not shown an empty counter (FR-042b,
    /// SC-011).
    static let worklistFinished = "Everything has a category"

    /// What the door does, spoken — so it is a sentence a screen reader can act on rather than
    /// a number somebody has to guess the meaning of.
    static let worklistHint = "Opens the transactions that have no category"

    /// **The narrowed list, empty across every account** — FR-042b's reward.
    ///
    /// Deliberately not one of 018's six. "Nothing to show" would read as damage, and
    /// "no transactions" would be a false claim about a person who has plenty of them: the
    /// rows are all there, and every one of them has been answered.
    static let allFiledTitle = "Nothing left to file"

    static let allFiledMessage = "Every transaction Kaname has imported has a category."

    /// The same for one account. It keeps the account's name, because "nothing left to file"
    /// about one card is a different fact from the same sentence about everything.
    static func accountFiledTitle(_ name: String) -> String { "Nothing left to file in \(name)" }

    static func accountFiledMessage(_ name: String) -> String {
        "Every transaction in \(name) has a category."
    }

    /// The worklist worked to zero, as the empty state 018's table now has two more rows for.
    ///
    /// Assembled here rather than in `TransactionListStrings.emptyState(for:)` because the
    /// sentences are this slice's: that table is 018's six, and a state added to it is added
    /// beside them rather than written into them (FR-042, T1).
    ///
    /// - Parameter accountName: `nil` for the whole store. When an account is named, clearing
    ///   the account filter is the one act that can still find work — this account is
    ///   finished, and another one may not be.
    static func finishedState(accountName: String?) -> TransactionListStrings.EmptyState {
        guard let accountName else {
            return TransactionListStrings.EmptyState(
                title: allFiledTitle, message: allFiledMessage, action: nil)
        }
        return TransactionListStrings.EmptyState(
            title: accountFiledTitle(accountName),
            message: accountFiledMessage(accountName),
            action: .clearFilter
        )
    }

    /// Every classification, in the order the picker draws them, so the heading table and the
    /// grouping cannot disagree about which groups exist.
    static let everyGroupHeading: [String] =
        (CategoryCatalog.classificationOrder.map { Optional($0) } + [nil])
        .map(groupHeading)

    /// Every sentence this table *builds*, rendered with stand-in values.
    ///
    /// ⚠️ A sentence assembled at runtime is a sentence the audit would otherwise never see —
    /// and the memory surfaces are almost entirely assembled, because both of them quote a
    /// person's own merchant back at them. Both counts of every pluralised sentence are here,
    /// because "1 transactions" is exactly the kind of thing nobody notices in a table of
    /// constants.
    static var everyBuiltSentence: [String] {
        [
            memoryOffer(portion: "a shop", category: "a category"),
            memoryRemembered(portion: "a shop"),
            secondActionSummary(count: 1, portion: "a shop", category: "a category"),
            secondActionSummary(count: 4, portion: "a shop", category: "a category"),
            secondActionAccount(name: "an account", count: 1),
            secondActionAccount(name: "an account", count: 4),
            secondActionChanged(count: 1),
            secondActionChanged(count: 4),
            worklistWaiting(1),
            worklistWaiting(4),
            accountFiledTitle("an account"),
            accountFiledMessage("an account"),
        ]
    }

    /// Every sentence in this table, gathered in one place so a new string cannot escape the
    /// audit by being added somewhere else.
    static var everySentence: [String] {
        [
            detailTitle, categoryHeading, uncategorized,
            dateHeading, amountHeading, accountHeading, descriptionHeading,
            changeCategory, pickerTitle, cancel,
            noCategoryChoice, noCategoryExplanation,
            currentCategoryAnnouncement, rowHint, changeFailed,
            memoryOfferTitle, memoryOfferAccept, memoryOfferDecline,
            nothingToRememberTitle, nothingToRememberBody, memoryOfferDone,
            secondActionTitle, secondActionAccountsHeading,
            secondActionApply, secondActionDecline,
            secondActionStale, secondActionFailed,
            worklistFinished, worklistHint, allFiledTitle, allFiledMessage,
        ] + everyGroupHeading + everyBuiltSentence
    }
}
