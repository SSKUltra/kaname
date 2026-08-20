import Foundation

/// Every user-visible string on the transaction list, in one file.
///
/// One file rather than inline literals because these sentences are the feature. A person
/// reading an empty list has to be told which of six different true things is the case — that
/// nothing was imported, that a statement genuinely had no transactions in it, or that a
/// filter they set is the reason — and telling them the wrong one is indistinguishable, from
/// where they sit, from the app having lost their money. The copy deck is
/// `specs/018-transaction-list/tasks.md` § "Design contract — RECORDED", T046.
///
/// The only engine-supplied strings that reach the screen are the account name, the
/// description as the statement printed it, and the category name. Everything else is here.
enum TransactionListStrings {
    // MARK: - The screen

    static let title = "Transactions"
    static let frontDoorLink = "All transactions"
    static let loadingAnnouncement = "Loading transactions"

    // MARK: - The filter chrome

    static let scopeAll = "All accounts"
    static let menuHeader = "Show transactions from"
    static let clearFilter = "Show all accounts"
    static let scopeHint = "Choose which account to show"

    /// The masked identity, in the same shape the front door already shows.
    static func maskedLast4(_ last4: String) -> String { "•••• \(last4)" }

    /// One account, named the way it is spoken rather than the way it is printed.
    static func accountIdentity(name: String, last4: String?) -> String {
        guard let last4 else { return name }
        return "\(name), ending \(last4)"
    }

    /// One account, named the way a **row** has to show it: the digits first.
    ///
    /// A row's account line is one trailing-truncated line, and the spoken form appends the
    /// last four *last* — so truncation removed precisely the only part that discriminates,
    /// and two cards of the same product both read `<the product name>, endin…`
    /// (`.scratch/018-transaction-list/issues/04`). Leading with the mask spends the truncation
    /// on the product name instead, which repeats down the whole column anyway, and it aligns
    /// the discriminator at the same x on every row so a person can scan it rather than read
    /// to the end of each line. The spoken form is unchanged: `accessibilityLabel` still
    /// announces the sentence, because a sentence is what a screen reader should hear.
    static func accountRowIdentity(name: String, last4: String?) -> String {
        guard let last4 else { return name }
        return "\(maskedLast4(last4)) · \(name)"
    }

    /// The scope, announced. The filtered state is carried by these words and never by
    /// styling alone (FR-038, FR-071).
    static func scopeAnnouncement(name: String?, last4: String?) -> String {
        guard let name else { return "Showing all accounts" }
        return "Showing \(accountIdentity(name: name, last4: last4)) only"
    }

    // MARK: - A row

    static let debit = "debit"
    static let credit = "credit"
    static let uncategorized = "Uncategorized"

    /// The marking, and only the marking. The app does not run transfer detection today, so
    /// nothing here may read as though it found anything (FR-018).
    static let transfer = "Transfer"
    static let transferAnnouncement = "transfer"

    /// A description the statement left blank still has to produce a complete, announceable
    /// row (FR-020) — so the blank is named rather than rendered as a gap.
    static let missingDescription = "No description"

    // MARK: - Date groups

    /// The one pluralisation helper. Every worded count in this slice comes through it, so
    /// "1 transactions" is a test failure rather than a screenshot someone notices later.
    static func transactionCount(_ count: Int) -> String {
        count == 1 ? "1 transaction" : "\(count) transactions"
    }

    /// The heading, announced with how much is under it. The **visible** heading carries no
    /// count and no figure: a day can hold more than one currency, so a heading that could
    /// hold a sum is a heading that will eventually hold a wrong one (FR-026).
    static func groupAnnouncement(heading: String, count: Int) -> String {
        "\(heading), \(transactionCount(count))"
    }

    // MARK: - Empty states

    /// What an empty screen offers to do about itself.
    enum EmptyAction: Equatable, Sendable {
        case importStatement
        case clearFilter
    }

    /// What an empty screen says.
    struct EmptyState: Equatable, Sendable {
        let title: String
        let message: String
        let action: EmptyAction?
    }

    static func emptyState(for kind: EmptyKind) -> EmptyState {
        switch kind {
        // The two the uncategorized narrowing added, worded **and assembled** in
        // `CategorizeStrings`: this table is 018's six, and a slice that adds a state adds it
        // beside them rather than inside them (FR-042, T1).
        case .allAnswered:
            CategorizeStrings.finishedState(accountName: nil)
        case .accountAnswered(let name):
            CategorizeStrings.finishedState(accountName: name)
        case .nothingImported:
            EmptyState(
                title: "Nothing imported yet",
                message: "Import a statement and the transactions in it will appear here.",
                action: .importStatement
            )
        case .noTransactionsAnywhere:
            EmptyState(
                title: "No transactions",
                message: "The statements you imported didn't have any transactions in them.",
                action: nil
            )
        case .nothingToShowAnywhere:
            EmptyState(
                title: "Nothing to show",
                message: "There's nothing to show here yet. Import another statement to see transactions.",
                action: .importStatement
            )
        case .accountStatementEmpty(let name):
            EmptyState(
                title: "No transactions",
                message: "The statement you imported for \(name) didn't have any transactions in it.",
                action: nil
            )
        case .accountNothingToShow(let name):
            EmptyState(
                title: "Nothing to show",
                message: "There's nothing to show for \(name).",
                action: .clearFilter
            )
        case .accountEmptyOthersHaveRows(let name, let statementWasEmpty):
            EmptyState(
                title: "No transactions for \(name)",
                message: statementWasEmpty
                    ? "The statement you imported for \(name) didn't have any transactions in it. "
                        + "Other accounts have transactions."
                    : "There's nothing to show for \(name). Other accounts have transactions.",
                action: .clearFilter
            )
        }
    }

    // MARK: - When the store cannot be read

    /// Not an empty state: something went wrong reading, and the person is owed the one fact
    /// that matters to them — their data is still where they put it. No identifier, no raw
    /// error text, nothing about a row (FR-019, FR-063).
    static let unavailableTitle = "Transactions are unavailable"
    static let unavailableMessage =
        "Kaname couldn't open your transactions just now. Everything is still stored on this device."
    static let unavailableRetry = "Try again"
}
