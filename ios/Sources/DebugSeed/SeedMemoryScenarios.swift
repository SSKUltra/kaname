#if DEBUG

import Foundation

// The two scenarios a memory needs, and the one thing each of them declares about it.
//
// ⚠️ **Both can be eaten by de-duplication before anything is asserted**, and neither says so
// when it happens. `repeated` puts one merchant in two statements of **one account**, which is
// the re-import route to a superseded row; `crossing` puts one across **a ledger and a card**,
// which is exactly — and only — the pair cross-source de-duplication compares. So every row in
// both scenarios carries its own amount *and* its own date: the two matchers each require the
// amounts to be equal, so distinct amounts alone would be enough, and the dates differ as well
// because the cost of being wrong here is a blast radius that is quietly short.
//
// ⚠️ Foundation only, and a separate file rather than more of `SeedScenarios.swift`, for the
// two reasons that file already carries: a UI-test bundle links neither the app nor
// `KanameCore`, and `SeedScenarios.swift` is at 370 of SwiftLint's 400 lines.
//
// Every value is synthetic. No real merchant, issuer or account identifier enters this
// repository.

/// What a scenario declares about the memory a test will form in it.
///
/// ⚠️ **Declared here, and deliberately not believed here.** The portion is the *engine's*
/// derivation (`merchant_portion`), which the Swift side may never reimplement (FR-021,
/// FR-076) — so what is written below is an author's claim about what the engine will say, and
/// `SeedMemoryExpectationTests` is where the engine settles it. That test checks the claim in
/// both directions: every description named here must derive to `portion`, and **every other
/// row in the scenario must not** — because a `alsoMatching` that is merely *correct* rather
/// than *complete* would understate the blast radius, which is the one number the second
/// action exists to state.
struct SeedMemorySubject: Sendable {
    /// The row a test corrects. Its own correction is written with a person's provenance, so
    /// the engine excludes it from the impact — the rows below are what is left.
    let subjectDescription: String
    /// The merchant portion the engine derives from every description in this subject.
    let portion: String
    /// Every **other** live row the memory would then change, by description.
    let alsoMatching: [String]
}

/// The impact a scenario declares: the portion, the rows, and the accounts they sit in.
struct SeedMemoryImpact: Sendable, Equatable {
    let portion: String
    let rows: [SeedExpectation]
    /// Account display names, in the order `preview_memory_application` sorts them — by name,
    /// then by id. Stated in the same order the engine states it so a test can compare the two
    /// without either side re-sorting the other's answer.
    let accountNames: [String]
}

// MARK: - `repeated`

extension SeedScenario {
    /// One merchant, twice in one statement and once in a second statement of the **same
    /// account** — the scenario the memory offer is met in (FR-066).
    ///
    /// Two statements rather than one because the memory's whole promise is about rows a person
    /// already has, which arrive across imports rather than within one. The second statement
    /// re-imports into the account the first created, which is the only way a scenario can add
    /// to an account it already declared.
    static let repeated = SeedScenario(
        name: "repeated",
        now: "2026-01-15T09:00:00Z",
        statements: [
            SeedStatement(
                accountName: repeatedAccountName, bankCode: "SYNTH_BANK", isCreditCard: false,
                last4: "0010", currency: "INR", periodStart: "2025-07-01",
                periodEnd: "2025-07-31", reimportsPrevious: false, rows: repeatedFirstRows),
            SeedStatement(
                accountName: repeatedAccountName, bankCode: "SYNTH_BANK", isCreditCard: false,
                last4: "0010", currency: "INR", periodStart: "2025-08-01",
                periodEnd: "2025-08-31", reimportsPrevious: true, rows: repeatedSecondRows),
        ],
        memory: SeedMemorySubject(
            subjectDescription: "POS SYNTHETIC COFFEE 7723",
            portion: "synthetic coffee",
            alsoMatching: ["POS SYNTHETIC COFFEE 4417", "POS SYNTHETIC COFFEE 8891"])
    )

    /// As long as a real bank's printed name, for the reason `smallAccountName` is.
    static let repeatedAccountName = "SYNTHETIC HIGH STREET SAVINGS BANK"

    private static let repeatedFirstRows: [SeedRow] = [
        Self.memoryRow("2025-07-05", "POS SYNTHETIC COFFEE 8891", "245.00"),
        Self.memoryRow("2025-07-06", "POS SYNTHETIC BOOKSHOP 1102", "899.00"),
        Self.memoryRow("2025-07-07", "POS SYNTHETIC COFFEE 4417", "310.50"),
    ]

    private static let repeatedSecondRows: [SeedRow] = [
        Self.memoryRow("2025-08-04", "POS SYNTHETIC COFFEE 7723", "265.75"),
        Self.memoryRow("2025-08-05", "POS SYNTHETIC LAUNDRY 9004", "1250.00"),
    ]
}

// MARK: - `crossing`

extension SeedScenario {
    /// One merchant across **two accounts** — a bank ledger and a card — so the second action
    /// has more than one account name to state (S1, FR-035c).
    ///
    /// 🚨 A ledger and a card is the pair cross-source de-duplication compares, and two cards
    /// is the pair it silently ignores. This scenario is deliberately on the side that *can*
    /// lose a row, so the amounts and dates keeping its rows apart are load-bearing rather than
    /// decorative — the scenario that would have hidden the mistake is the one where the two
    /// accounts are both cards and nothing collides no matter what is written.
    static let crossing = SeedScenario(
        name: "crossing",
        now: "2026-01-15T09:00:00Z",
        statements: [
            SeedStatement(
                accountName: crossingLedgerName, bankCode: "SYNTH_BANK", isCreditCard: false,
                last4: "0011", currency: "INR", periodStart: "2025-09-01",
                periodEnd: "2025-09-30", reimportsPrevious: false, rows: crossingLedgerRows),
            SeedStatement(
                accountName: crossingCardName, bankCode: "SYNTH_CARD", isCreditCard: true,
                last4: "0012", currency: "INR", periodStart: "2025-09-01",
                periodEnd: "2025-09-30", reimportsPrevious: false, rows: crossingCardRows),
        ],
        memory: SeedMemorySubject(
            subjectDescription: "POS SYNTHETIC GARDEN CENTRE 2214",
            portion: "synthetic garden",
            alsoMatching: [
                "POS SYNTHETIC GARDEN CENTRE 3120", "POS SYNTHETIC GARDEN CENTRE 7788",
            ])
    )

    static let crossingLedgerName = "SYNTHETIC RIVERSIDE COMMUNITY BANK"
    static let crossingCardName = "SYNTHETIC TRAVEL REWARDS CARD"

    private static let crossingLedgerRows: [SeedRow] = [
        Self.memoryRow("2025-09-03", "POS SYNTHETIC GARDEN CENTRE 3120", "1520.00"),
        Self.memoryRow("2025-09-04", "POS SYNTHETIC BOOKSHOP 5561", "640.00"),
    ]

    private static let crossingCardRows: [SeedRow] = [
        Self.memoryRow("2025-09-06", "POS SYNTHETIC GARDEN CENTRE 7788", "980.25"),
        Self.memoryRow("2025-09-08", "POS SYNTHETIC GARDEN CENTRE 2214", "415.50"),
    ]

    /// One ordinary outflow. Every row in both scenarios is one of these, which is what makes
    /// the *unanswered* count of each scenario its whole live count: a fresh store has no
    /// rules and no source-category map, and neither of the two shapes the engine's card stage
    /// can place — a card inflow carrying cashback language, a bank outflow naming a payment
    /// intent beside a card token — appears anywhere below.
    private static func memoryRow(
        _ date: String, _ description: String, _ amount: String
    ) -> SeedRow {
        SeedRow(
            date: date, description: description, amount: amount, direction: .debit,
            currency: "INR", sourceCategory: nil, expectedCategory: nil)
    }
}

#endif
