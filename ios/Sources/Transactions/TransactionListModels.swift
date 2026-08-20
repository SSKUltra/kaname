import Foundation
import KanameCore
import SwiftUI

/// One transaction, as the screen needs it.
///
/// A faithful mirror of the engine's `HistoryRow` plus the facts a view would otherwise
/// compute inline — every one of them a **pure function of this row alone**, so the wording a
/// person hears can be asserted with nothing rendered (FR-074). Nothing here decides which
/// rows exist, what order they come in, or whether one counts: those belong to the engine, and
/// the moment Swift has an opinion about them, a count and a list can disagree.
struct TransactionRow: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let accountID: String
    let accountName: String
    let accountLast4: String?
    /// The engine's own `YYYY-MM-DD` — the grouping key, compared as text so no calendar or
    /// time zone can move a transaction to the day either side of the one it printed on.
    let isoDate: String
    /// The same date as a `Date`, for formatting only.
    let date: Date
    let descriptionRaw: String
    let amount: Decimal
    let direction: Direction
    let currency: String
    let categoryName: String?
    /// The same category, by id — what the picker marks the current choice with, because two
    /// categories may be renamed to the same words and a mark that matched on words would
    /// follow the rename (K3, FR-005).
    let categoryID: String?
    let isTransfer: Bool

    init(_ row: HistoryRow, calendar: Calendar = .current) {
        id = row.id
        accountID = row.accountId
        accountName = row.accountName
        accountLast4 = row.accountLast4
        isoDate = row.date
        date = Self.date(fromISO: row.date, calendar: calendar)
        descriptionRaw = row.descriptionRaw
        amount = row.amount
        direction = row.direction
        currency = row.currency
        categoryName = row.categoryName
        categoryID = row.categoryId
        isTransfer = row.isTransfer
    }

    /// The description exactly as the statement printed it, or the app's own wording when the
    /// statement printed nothing — never a blank space in the row (FR-020).
    var displayDescription: String {
        descriptionRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? TransactionListStrings.missingDescription
            : descriptionRaw
    }

    /// Direction in words, taken from what the engine recorded and never inferred from the
    /// sign of an amount (FR-014, FR-015).
    var directionWord: String {
        direction == .debit ? TransactionListStrings.debit : TransactionListStrings.credit
    }

    /// The glyph that carries direction on screen. A sign, not a colour — colour is redundant
    /// here and never the only carrier (FR-013, FR-071). U+2212, the typographic minus, so it
    /// aligns with the tabular digits beside it rather than sitting high like a hyphen.
    var directionSign: String { direction == .debit ? "\u{2212}" : "+" }

    /// The amount, always carrying its own currency and never converted into another one
    /// (FR-023, FR-024). A currency the locale has no symbol for renders as its code, which is
    /// unambiguous rather than pretty — and that is the right trade (FR-027).
    var formattedAmount: String {
        "\(directionSign)\(amount.formatted(.currency(code: currency)))"
    }

    /// The category the engine assigned, by name — never blank (FR-017).
    var categoryLabel: String { categoryName ?? TransactionListStrings.uncategorized }

    var accountIdentity: String {
        TransactionListStrings.accountIdentity(name: accountName, last4: accountLast4)
    }

    /// The same account, in the form the row draws: the masked digits first, so that the one
    /// line a row can give the account cannot truncate away the only part of it that tells two
    /// cards of the same product apart (issue 04).
    var accountRowIdentity: String {
        TransactionListStrings.accountRowIdentity(name: accountName, last4: accountLast4)
    }

    /// One sentence, so VoiceOver reads a fact rather than six loose fragments (FR-015).
    /// Always with the year: a row is announced on its own, out of reach of its heading.
    var accessibilityLabel: String {
        var parts = [
            date.formatted(.dateTime.day().month(.wide).year()),
            displayDescription,
            "\(amount.formatted(.currency(code: currency))) \(directionWord)",
            accountIdentity,
            categoryLabel,
        ]
        if isTransfer { parts.append(TransactionListStrings.transferAnnouncement) }
        return parts.joined(separator: ", ")
    }

    /// The date in full, with its year — a transaction opened on its own is out of reach of
    /// the heading that would otherwise have carried the year for it.
    var longDate: String { date.formatted(.dateTime.day().month(.wide).year()) }

    /// `YYYY-MM-DD` to a local-midnight `Date`, for formatting only. The engine's dates are
    /// always well formed; a malformed one would be a bug upstream, and rendering the epoch
    /// makes it visible rather than crashing a person's list.
    private static func date(fromISO iso: String, calendar: Calendar) -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date(timeIntervalSince1970: 0) }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}

/// One calendar date's transactions, across every account (FR-033).
///
/// **It carries no amount, and has no member that could hold one.** Any per-day figure would
/// be a sum, and a day can hold more than one currency, so a heading total would be either
/// meaningless or conditional. Removing the possibility is cheaper than getting the condition
/// right — a later slice that wants one has to add the field deliberately (FR-025, FR-026).
struct DateGroup: Identifiable, Equatable, Sendable {
    /// The ISO date. Also the grouping key.
    let id: String
    let date: Date
    let heading: String
    let rows: [TransactionRow]

    /// The date as a heading, with its year whenever that year is not the current one
    /// (FR-035). "Now" is passed in rather than read, so the rule is testable at a fixed date.
    static func heading(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        let sameYear =
            calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear
            ? date.formatted(.dateTime.day().month(.wide))
            : date.formatted(.dateTime.day().month(.wide).year())
    }
}

/// Which population the list is showing. A single account is a **filter on the one list**, not
/// a second screen with its own ordering, empty states or row treatment (FR-036).
enum AccountFilter: Equatable, Hashable, Codable, Sendable {
    case all
    case account(id: String, name: String, last4: String?)

    /// What the engine is asked for — the only difference between a filtered and an
    /// unfiltered read (FR-042).
    var accountID: String? {
        if case .account(let id, _, _) = self { return id }
        return nil
    }

    var accountName: String? {
        if case .account(_, let name, _) = self { return name }
        return nil
    }

    var accountLast4: String? {
        if case .account(_, _, let last4) = self { return last4 }
        return nil
    }
}

/// Why the list is empty — one case per row of `data-model.md` §6.
///
/// A pure function of `[AccountSummary]` and the filter, and of nothing else: no count beyond
/// `liveTransactionCount` is consulted, so this cannot become a second population (FR-008).
enum EmptyKind: Equatable, Sendable {
    /// Nothing has been imported at all.
    case nothingImported
    /// Everything imported, and no statement had a transaction in it.
    case noTransactionsAnywhere
    /// Everything imported, and every row there was is excluded.
    case nothingToShowAnywhere
    /// Filtered to an account whose statement genuinely held no transactions (FR-048).
    case accountStatementEmpty(name: String)
    /// Filtered to an account whose every row is deleted or superseded (FR-050).
    case accountNothingToShow(name: String)
    /// Filtered to an empty account while other accounts have rows, so the filter is the
    /// reason and clearing it would show something (FR-049). `statementWasEmpty` keeps the
    /// account's own reason in the sentence — this case *refines* the two above rather than
    /// replacing them, which is the only reading under which FR-048's distinct state stays
    /// reachable (design note E3).
    case accountEmptyOthersHaveRows(name: String, statementWasEmpty: Bool)

    static func decide(summaries: [AccountSummary], filter: AccountFilter) -> EmptyKind {
        guard !summaries.isEmpty else { return .nothingImported }

        guard let filtered = filter.accountID else {
            return summaries.contains(where: \.hasOnlyExcludedRows)
                ? .nothingToShowAnywhere
                : .noTransactionsAnywhere
        }

        let name = filter.accountName ?? ""
        let othersHaveRows = summaries.contains {
            $0.id != filtered && $0.liveTransactionCount > 0
        }
        // An account the summaries do not know is unreachable today — there is no delete path,
        // and an unknown id reads as an empty page rather than an error. It still needs a
        // destination, and the honest one is the filter itself (design note E4).
        guard let mine = summaries.first(where: { $0.id == filtered }) else {
            return .accountEmptyOthersHaveRows(name: name, statementWasEmpty: false)
        }
        if othersHaveRows {
            return .accountEmptyOthersHaveRows(name: name, statementWasEmpty: !mine.hasOnlyExcludedRows)
        }
        return mine.hasOnlyExcludedRows
            ? .accountNothingToShow(name: name)
            : .accountStatementEmpty(name: name)
    }
}

/// The layout choice for one row, as data.
///
/// Pure — no `View`, no environment, no rendering — because SC-013 requires the automatable
/// half of the accessibility criteria to be covered without a screen, and no unit test can
/// measure a rendered frame. Extracting the *decision* makes the decision provable; the
/// rendering stays on the manual gate.
struct TransactionRowLayout: Equatable, Sendable {
    let axis: Axis
    let descriptionLineLimit: Int
    let accountNameLineLimit: Int
    /// **Always false.** Where space is contested the description yields first and the account
    /// name second; the amount never yields, at any size, for any magnitude (FR-021).
    let amountYields: Bool

    init(dynamicTypeSize: DynamicTypeSize) {
        let isAccessibility = dynamicTypeSize.isAccessibilitySize
        axis = isAccessibility ? .vertical : .horizontal
        descriptionLineLimit = isAccessibility ? 3 : 2
        accountNameLineLimit = 1
        amountYields = false
    }
}

/// One line of the filter chrome's scope button, in the order it is drawn.
///
/// Top level rather than nested inside `FilterChromeLayout` only because the repo's nesting
/// limit is one deep and its `Role` has to live somewhere.
struct ScopeLine: Equatable, Sendable, Identifiable {
    enum Role: Hashable, Sendable { case name, mask }

    let role: Role
    let text: String
    /// The headline of the chip — larger, heavier, and first. Exactly one line is primary.
    let isPrimary: Bool
    let lineLimit: Int
    /// Middle truncation keeps both ends of a name that cannot fit, which is worth more
    /// than a tail: bank names share their beginnings and card products their endings.
    let truncatesInTheMiddle: Bool

    var id: Role { role }
}

/// The filter chrome's layout choice, as data — pure, for the same reason
/// `TransactionRowLayout` is.
///
/// The bar shipped with both of its labels on a hard `lineLimit(1)` and its clear button on no
/// limit at all, so at accessibility sizes the button expanded without bound and squeezed the
/// scope chip down to four letters over `·····…`: a filter a person could not identify, and a
/// mask degraded into a row of dots (`.scratch/018-transaction-list/issues/02`). Truncating
/// harder is not available to us — at the largest size the widest chip this bar can offer
/// holds a handful of characters, and no truncation of a card product's full name is a name.
/// So the decision this type makes is **which fact gets the space**, and at accessibility
/// sizes that is the last four digits: the only part of an account's identity that
/// discriminates between two cards of the same product.
struct FilterChromeLayout: Equatable, Sendable {
    /// Which way the bar lays its two controls out.
    ///
    /// Horizontal until the accessibility sizes, where it **must** go vertical: at the largest
    /// size the masked digits alone want roughly 280 pt and the collapsed clear button roughly
    /// 110 pt, which with the bar's own padding overruns a 393 pt screen. There is no ordering
    /// of the two facts that fits them side by side, so the chip has to have the full width —
    /// this was measured on a screen, after a first attempt that kept the bar horizontal
    /// shipped a chip reading `•••• 77…` and failed G5 a second time.
    let axis: Axis

    /// Whether the clear button shows its words. At accessibility sizes it does not — it
    /// collapses to a symbol carrying the same sentence as its accessibility label, because a
    /// button reading `Show all ac-count s` over four lines is both unreadable in itself and
    /// the reason nothing beside it has any room (issue 02, and the bar height behind
    /// issue 03).
    let clearButtonShowsTitle: Bool

    /// The most text lines the chip can ever grow to. The bar's height is bounded by this and
    /// the clear button, and a bottom bar that grows without bound eats the list above it.
    let maximumScopeLines: Int

    private let isAccessibilitySize: Bool

    init(dynamicTypeSize: DynamicTypeSize) {
        isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        axis = isAccessibilitySize ? .vertical : .horizontal
        clearButtonShowsTitle = !isAccessibilitySize
        maximumScopeLines = isAccessibilitySize ? 3 : 2
    }

    /// The chip's lines, in the order they are drawn.
    ///
    /// At standard sizes this is the shape the screen already shipped and which reads
    /// correctly: the account's name, with its masked digits beneath. At accessibility sizes
    /// the order inverts — the mask leads, on its own short line that always fits, and the
    /// name follows in the space that is left. Unfiltered there is no mask and no inversion to
    /// make: "All accounts" is the whole fact.
    func scopeLines(title: String, subtitle: String?) -> [ScopeLine] {
        guard let subtitle else {
            return [
                ScopeLine(
                    role: .name, text: title, isPrimary: true,
                    lineLimit: isAccessibilitySize ? maximumScopeLines : 1,
                    truncatesInTheMiddle: isAccessibilitySize)
            ]
        }
        let mask = ScopeLine(
            role: .mask, text: subtitle, isPrimary: isAccessibilitySize, lineLimit: 1,
            truncatesInTheMiddle: false)
        let name = ScopeLine(
            role: .name, text: title, isPrimary: !isAccessibilitySize,
            lineLimit: isAccessibilitySize ? maximumScopeLines - 1 : 1,
            truncatesInTheMiddle: isAccessibilitySize)
        return isAccessibilitySize ? [mask, name] : [name, mask]
    }
}

/// Everything that can go wrong reading the history, from the screen's point of view.
///
/// One case, on purpose. A store failure is not something a person can act on differently
/// depending on which SQL statement produced it, and every variant that carried detail would
/// be a place a description, an amount or an account id could reach a log or a screen
/// (FR-019, FR-063).
enum TransactionListError: Error, Equatable, Sendable {
    case unavailable

    /// Map anything the store threw. The original is deliberately dropped, not wrapped.
    init(mapping _: Error) {
        self = .unavailable
    }
}
