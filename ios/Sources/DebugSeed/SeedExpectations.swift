#if DEBUG

import Foundation

// What a seeded test expects, derived from `SeedScenarios.swift`'s declaration and from
// nothing else — the second half of FR-010's no-drift rule.
//
// It lives beside the declaration and is compiled into the UI-test bundle with it, so an
// assertion and the rows it is about are always the same literal. ⚠️ It exists as a *second*
// file only because the first one reached SwiftLint's 400-line limit, and `make lint` is
// `--strict`; the split is by role — what a scenario says over there, what a test derives
// here — rather than by size.
//
// ⚠️ Foundation only, for the same reason: a UI-test bundle links neither the app nor
// `KanameCore`.

// MARK: - What a test derives from the declaration

extension SeedScenario {
    /// Every live row, in the order the history must render it: `date DESC`, then the
    /// account's position in `listAccounts()`, then insertion order.
    var expectedLiveRows: [SeedExpectation] {
        placement.live.sorted(by: SeedScenario.precedes).map(\.expectation)
    }

    /// Rows a declared collision supersedes. They must never appear on screen.
    var expectedSupersededRows: [SeedExpectation] {
        placement.superseded.map(\.expectation)
    }

    var expectedLiveRowCount: Int { placement.live.count }

    var expectedSupersededRowCount: Int { placement.superseded.count }

    /// Whether any statement in this scenario creates or re-imports into an account by name.
    func declares(accountNamed name: String) -> Bool {
        statements.contains { $0.accountName == name }
    }

    /// What each date group announces, in the order the groups render: the heading the screen
    /// draws, and how many rows sit under it.
    ///
    /// The heading carries its year only when that year is not the current one, which is the
    /// rule the screen applies and the reason every scenario's dates sit in a prior calendar
    /// year — so the year is always part of the sentence and a run in January cannot change
    /// what this test means.
    var expectedGroupAnnouncements: [String] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for row in expectedLiveRows {
            if counts[row.isoDate] == nil { order.append(row.isoDate) }
            counts[row.isoDate, default: 0] += 1
        }
        return order.map { iso in
            let count = counts[iso] ?? 0
            let transactions = count == 1 ? "1 transaction" : "\(count) transactions"
            return "\(SeedScenario.headingText(iso)), \(transactions)"
        }
    }

    private static func headingText(_ iso: String) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
            let date = Calendar.current.date(
                from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return iso }
        let thisYear = Calendar.current.component(.year, from: Date())
        let style =
            parts[0] == thisYear
            ? Date.FormatStyle.dateTime.day().month(.wide)
            : Date.FormatStyle.dateTime.day().month(.wide).year()
        return date.formatted(style.locale(SeedRow.pinnedLocale))
    }

    /// Every account the scenario creates, in `listAccounts()` order, with the live count the
    /// front door will show for it.
    var expectedAccounts: [SeedAccountExpectation] {
        let live = placement.live
        return placement.accounts.enumerated().map { index, account in
            SeedAccountExpectation(
                name: account.name, last4: account.last4,
                liveRowCount: live.filter { $0.accountIndex == index }.count)
        }
    }

    /// How many live rows nothing has answered yet — the worklist this scenario declares.
    ///
    /// ⚠️ Declared here, but **not believed here**: `SeedContractUITests` asserts it against
    /// `uncategorizedCount()`, the engine's own number. A declaration that merely restated the
    /// author's belief about what the engine would categorize would agree with itself forever,
    /// including on the day the engine changed its mind.
    var expectedUncategorizedCount: Int {
        expectedLiveRows.count - expectedCategorizedRowCount
    }

    /// Live rows the declaration says the engine will place.
    var expectedCategorizedRowCount: Int {
        placement.live.filter { $0.row.expectedCategory != nil }.count
    }

    /// One account by name, as the front door will announce it.
    func expectedAccount(named name: String) -> SeedAccountExpectation? {
        expectedAccounts.first { $0.name == name }
    }

    /// The live rows of one account, in the order the filtered list must render them — which is
    /// the same total order with one account in it, because a filter is the same query with
    /// `k = 1` and never a second sort.
    func expectedLiveRows(inAccountNamed name: String) -> [SeedExpectation] {
        expectedLiveRows.filter { $0.accountName == name }
    }

    /// How the filter menu names an account: the spoken identity, which is also what the scope
    /// chip announces once the filter is applied.
    static func menuLabel(for account: SeedAccountExpectation) -> String {
        account.last4.map { "\(account.name), ending \($0)" } ?? account.name
    }

    private static func precedes(_ lhs: PlacedRow, _ rhs: PlacedRow) -> Bool {
        if lhs.row.date != rhs.row.date { return lhs.row.date > rhs.row.date }
        if lhs.accountIndex != rhs.accountIndex { return lhs.accountIndex < rhs.accountIndex }
        return lhs.rowid < rhs.rowid
    }

    /// Walk the declaration the way the engine walks it, and say which rows survive.
    ///
    /// The rule mirrors the engine's **canonical** layer exactly, and is deliberately stricter
    /// than it: two rows collide only when their date, description, amount and direction are
    /// identical, where the engine also normalises the narration and compares a 60-character
    /// prefix. Fuzzy matching cannot enter into it, because both layers require the amounts to
    /// be equal and no two unrelated rows in any scenario share one.
    private var placement: Placement {
        var accounts: [PlacedAccount] = []
        var live: [PlacedRow] = []
        var superseded: [PlacedRow] = []
        var rowid = 0

        for statement in statements {
            let index: Int
            if let existing = accounts.firstIndex(where: { $0.name == statement.accountName }) {
                index = existing
            } else {
                accounts.append(
                    PlacedAccount(
                        name: statement.accountName, last4: statement.last4,
                        isCreditCard: statement.isCreditCard))
                index = accounts.count - 1
            }
            for row in statement.rows {
                rowid += 1
                let placed = PlacedRow(accountIndex: index, rowid: rowid, row: row, account: accounts[index])
                if live.contains(where: { $0.loses(to: placed) }) {
                    superseded.append(placed)
                } else {
                    live.append(placed)
                }
            }
        }
        return Placement(accounts: accounts, live: live, superseded: superseded)
    }
}

/// The store a declaration describes: its accounts in creation order, the rows that survive,
/// and the rows a declared collision supersedes.
private struct Placement {
    let accounts: [PlacedAccount]
    let live: [PlacedRow]
    let superseded: [PlacedRow]
}

/// One account, as the declaration order creates it.
private struct PlacedAccount {
    let name: String
    let last4: String?
    let isCreditCard: Bool
}

/// One declared row, placed in the store the declaration describes.
private struct PlacedRow {
    let accountIndex: Int
    let rowid: Int
    let row: SeedRow
    let account: PlacedAccount

    /// Would `incoming` be superseded by this row already being here?
    ///
    /// Two routes, both the engine's own: a re-import into the same account, where the row a
    /// person already has always wins; and a cross-source duplicate, which the engine only
    /// ever looks for between a **bank ledger and a card** — two cards never de-duplicate, and
    /// they do not say so.
    func loses(to incoming: PlacedRow) -> Bool {
        guard row.date == incoming.row.date, row.description == incoming.row.description,
            row.amount == incoming.row.amount, row.direction == incoming.row.direction
        else { return false }
        if accountIndex == incoming.accountIndex { return true }
        return accountIndex < incoming.accountIndex
            && account.isCreditCard != incoming.account.isCreditCard
    }

    var expectation: SeedExpectation {
        SeedExpectation(
            accountName: account.name, accountLast4: account.last4, isoDate: row.date,
            currency: row.currency,
            accessibilityLabel: row.accessibilityLabel(
                accountName: account.name, last4: account.last4))
    }
}

// MARK: - The spoken row, built the way the screen builds it

extension SeedRow {
    /// The one sentence `TransactionRowView` announces, assembled from this declaration.
    ///
    /// ⚠️ Every part is formatted against a **pinned** `en_IN` locale, because the test runner
    /// is a different process from the app and inherits the simulator's region rather than the
    /// `-AppleLocale` the seeded launch pins. An expectation formatted against the runner's own
    /// locale would be an assertion about the machine (research R16).
    func accessibilityLabel(accountName: String, last4: String?) -> String {
        let identity = last4.map { "\(accountName), ending \($0)" } ?? accountName
        return [
            Self.dateText(date),
            description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "No description" : description,
            "\(amountText) \(direction.word)",
            identity,
            expectedCategory ?? "Uncategorized",
        ].joined(separator: ", ")
    }

    /// The amount as the row prints it, without its direction sign — the spoken label carries
    /// the direction in words instead.
    var amountText: String {
        decimalAmount.formatted(.currency(code: currency).locale(Self.pinnedLocale))
    }

    /// Exact, because `Decimal(string:)` parses base-10 and `Decimal(1234.56)` does not.
    var decimalAmount: Decimal {
        Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? .zero
    }

    static let pinnedLocale = Locale(identifier: "en_IN")

    static func dateText(_ iso: String) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
            let date = Calendar.current.date(
                from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return iso }
        return date.formatted(.dateTime.day().month(.wide).year().locale(pinnedLocale))
    }
}

#endif
