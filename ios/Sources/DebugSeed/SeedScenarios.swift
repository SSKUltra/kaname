#if DEBUG

import Foundation

/// The named synthetic histories a DEBUG launch can ask for, and everything a test expects
/// to see once one has been applied — **one declaration, two readers**.
///
/// This file is compiled into the DEBUG app *and* into `KanameUITests` (`ios/Project.swift`),
/// so the rows the app writes and the rows the suite asserts against are the same literal and
/// drift has nowhere to happen (FR-010, research R11).
///
/// ⚠️ **It may import Foundation and nothing else.** A UI-test bundle links neither the app nor
/// `KanameCore`, so a single `import KanameCore` here would stop the file compiling in the
/// bundle that asserts. That is why direction is `SeedDirection` rather than the engine's
/// `Direction`, why an amount is a base-10 **string** rather than a `Decimal` literal
/// (`Decimal(1234.56)` goes through a `Double`; `Decimal(string:)` is exact), and why the
/// expected-row maths lives here rather than in `SeedScenarioBuilder.swift`, which does import
/// the engine.
///
/// Every value is synthetic. No real merchant, issuer, account identifier or fragment of a real
/// statement enters this repository — and `scripts/import-path-audit.sh` scans this directory
/// for registry literals and networking symbols, so that is enforced rather than promised.
struct SeedScenario: Sendable {
    /// The name a launch asks for. Lowercase, hyphen-free, stable — part of a contract with
    /// the test suite, not a label.
    let name: String
    /// The instant every write in this scenario is stamped with. Declared, never read from a
    /// clock (FR-023).
    let now: String
    /// Applied in order. The order is load-bearing: it fixes account order, the history's
    /// account tie-break, and which row wins a de-duplication.
    let statements: [SeedStatement]
    /// What this scenario declares about the memory a test forms in it, or `nil` when it
    /// declares none. `var` with a default so the scenarios written before memories existed
    /// keep their memberwise initializer unchanged (see `SeedMemoryScenarios.swift`).
    var memory: SeedMemorySubject?
}

/// One statement, as a person's document would have arrived.
struct SeedStatement: Sendable {
    let accountName: String
    let bankCode: String
    let isCreditCard: Bool
    let last4: String?
    /// The **account's** currency. A row may declare a different one.
    let currency: String
    let periodStart: String?
    let periodEnd: String
    /// `true` re-imports into the account an earlier statement of the same name created,
    /// which is one of the two routes to a superseded row.
    let reimportsPrevious: Bool
    /// May be empty — an imported statement that held no transactions is a declared situation,
    /// not a mistake.
    let rows: [SeedRow]
}

/// One printed transaction.
struct SeedRow: Sendable {
    let date: String
    let description: String
    /// A base-10 decimal **string**, always below ₹1,00,000 — `.currency(code:)` takes its
    /// grouping from the locale, so a larger figure would make an assertion about the
    /// simulator's region rather than about the app (research R16).
    let amount: String
    let direction: SeedDirection
    /// The **row's** currency, never the account's.
    let currency: String
    let sourceCategory: String?
    /// The category the engine will assign, declared so the expected spoken label can be
    /// built from this declaration alone. `nil` ⇒ uncategorized.
    ///
    /// A fresh store seeds categories but **no rules, merchants or source-category map**, so
    /// the only stage that can fire on a seeded row is the engine's hard-coded credit-card
    /// stage: a card **inflow** carrying cashback language, or a bank **outflow** carrying a
    /// payment intent beside a card token. Everything else is uncategorized, and declaring the
    /// outcome is what lets a test notice if that ever changes.
    let expectedCategory: String?
}

/// Which way the money went. Spelled out rather than inferred from a sign, exactly as the
/// engine records it.
enum SeedDirection: Sendable {
    case debit
    case credit

    /// The word `TransactionRow.directionWord` puts into a row's spoken label.
    var word: String { self == .debit ? "debit" : "credit" }
}

/// One live row, as the screen will announce it.
struct SeedExpectation: Sendable, Equatable {
    let accountName: String
    let accountLast4: String?
    let isoDate: String
    /// The **row's** currency, carried through so a currency assertion is made against the
    /// declaration rather than against a symbol somebody typed into a test.
    let currency: String
    /// The whole row, as one string — `TransactionRowView` combines its children, so this is
    /// the only per-row text an automated run can see (research R20).
    let accessibilityLabel: String
}

/// One account, as the front door will announce it.
struct SeedAccountExpectation: Sendable, Equatable {
    let name: String
    let last4: String?
    let liveRowCount: Int
    /// The sentence `ImportedAccountsView.announcement(for:)` builds.
    var announcement: String {
        let identity = last4.map { "\(name), ending \($0)" } ?? name
        let count = liveRowCount == 1 ? "1 transaction" : "\(liveRowCount) transactions"
        return "\(identity): \(count)"
    }
}

// MARK: - The declared set

extension SeedScenario {
    /// Every scenario a launch may name. An unrecognised name fails the launch (FR-006).
    static let declared: [SeedScenario] = [
        .empty, .small, .deep, .barren, .unfiled, .repeated, .crossing,
    ]

    static func named(_ name: String) -> SeedScenario? {
        declared.first { $0.name == name }
    }

    static var declaredNames: String {
        declared.map(\.name).joined(separator: ", ")
    }

    /// A store with nothing in it — the reset without the seed.
    ///
    /// Declared, rather than left to the runner, because a seeded store **outlives the suite
    /// that wrote it**: the shipped front-door audits assert a fresh install, and they would
    /// audit an accounts list instead if a seeded suite that ran before them left its rows
    /// behind. `make ios-test` uninstalls once before the whole run; this is the same
    /// protection one layer down, expressible from inside a test.
    static let empty = SeedScenario(name: "empty", now: "2026-01-15T09:00:00Z", statements: [])

    /// Six rows, one account, one currency, six consecutive days in a **prior calendar year**
    /// so a group heading has to carry its year.
    ///
    /// Six because the questions it answers are about the *end* of a list at the largest
    /// accessibility text size, where the 10,000-row corpus put the end some hundreds of
    /// flicks away and made the gate unrunnable (`.scratch/018-transaction-list/issues/03`).
    static let small = SeedScenario(
        name: "small",
        now: "2026-01-15T09:00:00Z",
        statements: [
            SeedStatement(
                accountName: smallAccountName,
                bankCode: "SYNTH_BANK",
                isCreditCard: false,
                last4: "0006",
                currency: "INR",
                periodStart: "2025-02-01",
                periodEnd: "2025-02-28",
                reimportsPrevious: false,
                rows: smallRows
            )
        ]
    )

    /// ⚠️ **Long on purpose.** `.scratch/018-transaction-list/issues/02` and `03` are both
    /// defects of a *long account name* at an accessibility text size: a chip that cannot fit
    /// one truncates the digits away, and a bar with no bound on its height grows until it eats
    /// the row above it. A fixture named `SYNTHETIC BANK ONE` cannot reproduce either — three
    /// short words fit anywhere — and a suite built on one would have watched both breaks stay
    /// green. This is the length of a real card product's printed name.
    static let smallAccountName = "SYNTHETIC INTERNATIONAL REWARDS BANK"

    private static let smallRows: [SeedRow] = [
        ("2025-02-10", "SYNTHETIC MERCHANT 01", "450.00"),
        ("2025-02-11", "SYNTHETIC MERCHANT 02", "1250.75"),
        ("2025-02-12", "SYNTHETIC MERCHANT 03", "99.50"),
        ("2025-02-13", "SYNTHETIC MERCHANT 04", "3410.20"),
        ("2025-02-14", "SYNTHETIC MERCHANT 05", "780.00"),
        ("2025-02-15", "SYNTHETIC MERCHANT 06", "12345.67"),
    ].map {
        SeedRow(
            date: $0.0, description: $0.1, amount: $0.2, direction: .debit, currency: "INR",
            sourceCategory: nil, expectedCategory: nil)
    }

    /// Two accounts, two imported statements, and **no transactions at all** — a person who
    /// imported two genuinely quiet months.
    ///
    /// ⚠️ It exists because a **third** empty state turned out to need it, and neither `small`
    /// nor `deep` can express it. `EmptyKind.decide`'s unfiltered branch is consulted only when
    /// the store holds no live rows *anywhere*, and any scenario with a transaction in it has at
    /// least one live row — the engine's de-duplication always keeps a winner. So
    /// `noTransactionsAnywhere` needs a store that imported statements and got rows from none of
    /// them. Filtering to either account reaches `accountStatementEmpty` for the same reason:
    /// the other account has nothing live either, so the filter is not what is hiding anything.
    ///
    /// Adding it costs nothing outside a DEBUG build (FR-013, SC-015), and `data-model.md` §6
    /// anticipates it in as many words.
    static let barren = SeedScenario(
        name: "barren",
        now: "2026-01-15T09:00:00Z",
        statements: [
            SeedStatement(
                accountName: barrenFirstName, bankCode: "SYNTH_BANK", isCreditCard: false,
                last4: "0007", currency: "INR", periodStart: "2025-03-01",
                periodEnd: "2025-03-31", reimportsPrevious: false, rows: []),
            SeedStatement(
                accountName: barrenSecondName, bankCode: "SYNTH_CARD", isCreditCard: true,
                last4: "0008", currency: "INR", periodStart: "2025-03-01",
                periodEnd: "2025-03-31", reimportsPrevious: false, rows: []),
        ]
    )

    static let barrenFirstName = "SYNTHETIC BANK SIX"
    static let barrenSecondName = "SYNTHETIC CARD SEVEN"

    /// A card statement whose rows are mostly **unanswered**, with two the engine can place —
    /// the worklist, small enough to be worked to zero by hand in a test (FR-066).
    ///
    /// ⚠️ The two categorized rows are not decoration. A scenario where *everything* is
    /// unanswered cannot tell "the worklist shows what nobody has answered" apart from "the
    /// worklist shows everything", which is the assertion PR F actually needs. A fresh store
    /// seeds categories but no rules and no source-category map, so the only stage that can
    /// fire is the engine's hard-coded card stage: a card **inflow** carrying cashback
    /// language, and a bank **outflow** naming a payment intent beside a card token. Those are
    /// the two shapes below, and declaring their outcome is what lets a test notice if the
    /// engine ever stops placing them.
    static let unfiled = SeedScenario(
        name: "unfiled",
        now: "2026-01-15T09:00:00Z",
        statements: [
            SeedStatement(
                accountName: unfiledCardName,
                bankCode: "SYNTH_CARD",
                isCreditCard: true,
                last4: "0009",
                currency: "INR",
                periodStart: "2025-05-01",
                periodEnd: "2025-05-31",
                reimportsPrevious: false,
                rows: unfiledRows
            )
        ]
    )

    /// As long as a real card product's printed name, for the reason `smallAccountName` is.
    static let unfiledCardName = "SYNTHETIC INTERNATIONAL REWARDS CARD"

    private static let unfiledRows: [SeedRow] = [
        SeedRow(
            date: "2025-05-10", description: "SYNTHETIC UNFILED MERCHANT 01", amount: "310.00",
            direction: .debit, currency: "INR", sourceCategory: nil, expectedCategory: nil),
        SeedRow(
            date: "2025-05-11", description: "SYNTHETIC UNFILED MERCHANT 02", amount: "1420.50",
            direction: .debit, currency: "INR", sourceCategory: nil, expectedCategory: nil),
        SeedRow(
            date: "2025-05-12", description: "SYNTHETIC CASHBACK 009", amount: "75.00",
            direction: .credit, currency: "INR", sourceCategory: nil,
            expectedCategory: "Cashbacks & Refunds"),
        SeedRow(
            date: "2025-05-13", description: "SYNTHETIC UNFILED MERCHANT 04", amount: "88.25",
            direction: .debit, currency: "INR", sourceCategory: nil, expectedCategory: nil),
        SeedRow(
            date: "2025-05-14", description: "SYNTHETIC CASHBACK 014", amount: "120.00",
            direction: .credit, currency: "INR", sourceCategory: nil,
            expectedCategory: "Cashbacks & Refunds"),
    ]
}

// MARK: - `deep`

extension SeedScenario {
    /// 160 live rows over four accounts — a bank ledger, a card, a card whose statement held
    /// nothing, and a card whose every row loses to the ledger — in five statements, one of
    /// which re-imports the first.
    ///
    /// 160 because `TransactionListViewModel.pageSize` is 50: four pages, the last partial,
    /// which also exercises the exhausted cursor.
    ///
    /// ⚠️ **The corpus must not eat itself.** Exactly the rows declared to collide may collide;
    /// every other row differs from every row anywhere else by **amount**, which is the one
    /// field both de-duplication layers require to be equal. The intended collisions are
    /// `deepSharedPurchase` (cross-source, bank ↔ card), the re-import, and `SYNTHETIC CARD
    /// FIVE`'s three rows. ⚠️ They must also collide with **different** ledger rows from each
    /// other: the engine removes a winning row from its candidate pool once something has
    /// matched it, so two incoming rows aiming at the same ledger row would leave the second
    /// one live and the count short.
    static let deep = SeedScenario(
        name: "deep",
        now: "2026-01-15T09:00:00Z",
        statements: [
            SeedStatement(
                accountName: deepLedgerName, bankCode: "SYNTH_BANK", isCreditCard: false,
                last4: "0001", currency: "INR", periodStart: "2025-04-01",
                periodEnd: "2025-06-30", reimportsPrevious: false, rows: deepLedgerRows),
            SeedStatement(
                accountName: deepCardName, bankCode: "SYNTH_CARD", isCreditCard: true,
                last4: "0002", currency: "INR", periodStart: "2025-04-01",
                periodEnd: "2025-05-31", reimportsPrevious: false, rows: deepCardRows),
            SeedStatement(
                accountName: deepEmptyCardName, bankCode: "SYNTH_CARD", isCreditCard: true,
                last4: "0003", currency: "INR", periodStart: "2025-04-01",
                periodEnd: "2025-04-30", reimportsPrevious: false, rows: []),
            SeedStatement(
                accountName: deepLedgerName, bankCode: "SYNTH_BANK", isCreditCard: false,
                last4: "0001", currency: "INR", periodStart: "2025-04-01",
                periodEnd: "2025-06-30", reimportsPrevious: true, rows: [deepLedgerRows[0]]),
            // A card whose every row the ledger already had. It ends up holding rows and
            // showing none of them — the only way an account reaches `hasOnlyExcludedRows`
            // through the import path, and the state the filter's third empty case needs.
            SeedStatement(
                accountName: deepEchoCardName, bankCode: "SYNTH_CARD", isCreditCard: true,
                last4: "0004", currency: "INR", periodStart: "2025-04-01",
                periodEnd: "2025-04-30", reimportsPrevious: false,
                rows: [deepLedgerRows[10], deepLedgerRows[20], deepLedgerRows[30]]),
        ]
    )

    static let deepLedgerName = "SYNTHETIC BANK TWO"
    static let deepCardName = "SYNTHETIC CARD THREE"
    static let deepEmptyCardName = "SYNTHETIC CARD FOUR"
    static let deepEchoCardName = "SYNTHETIC CARD FIVE"

    /// The one purchase that appears on both a ledger and a card — the cross-source pair. It
    /// is declared **on the ledger first**, because the engine's de-duplication keeps the row
    /// held by the account with the lower `rowid` and supersedes the later one.
    static let deepSharedPurchase = SeedRow(
        date: "2025-04-15", description: "SYNTHETIC SHARED PURCHASE 42", amount: "3777.33",
        direction: .debit, currency: "INR", sourceCategory: nil, expectedCategory: nil)

    private static let deepLedgerRows: [SeedRow] = (0..<100).map { index in
        if index == 42 { return deepSharedPurchase }
        // A bank **outflow** naming a payment intent beside a card token is the one row the
        // engine's card rules categorize on this side of the ledger.
        let categorized = index == 50
        return SeedRow(
            date: deepDate(daysAfterApril: index % 50),
            description: categorized
                ? "SYNTHETIC CREDIT CARD PAYMENT 050"
                : "SYNTHETIC LEDGER MERCHANT \(String(format: "%03d", index))",
            amount: "\(1101 + index).11",
            direction: index % 7 == 0 ? .credit : .debit,
            currency: "INR",
            sourceCategory: nil,
            expectedCategory: categorized ? "Credit Card Bill Payment" : nil)
    }

    private static let deepCardRows: [SeedRow] =
        (0..<60).map { index in
            // A card **inflow** carrying cashback language is the other categorized row, and the
            // two together are why `deep` holds both categorized and uncategorized rows.
            let cashback = index == 7
            return SeedRow(
                date: deepDate(daysAfterApril: index % 30),
                description: cashback
                    ? "SYNTHETIC CASHBACK 007"
                    : "SYNTHETIC CARD MERCHANT \(String(format: "%03d", index))",
                amount: "\(2101 + index).22",
                direction: cashback ? .credit : .debit,
                // A second currency, on rows of the **same** account: the row's currency is never
                // the account's, and no figure anywhere may combine the two.
                currency: index % 10 == 0 ? "USD" : "INR",
                sourceCategory: nil,
                expectedCategory: cashback ? "Cashbacks & Refunds" : nil)
        } + [deepSharedPurchase]

    /// `2025-04-01` plus `days`, formed from calendar components so no time zone can move a
    /// declared date to the day either side of it.
    private static func deepDate(daysAfterApril days: Int) -> String {
        let month = 4 + (days / 30)
        let day = 1 + (days % 30)
        return String(format: "2025-%02d-%02d", month, day)
    }
}

#endif
