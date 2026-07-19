import Foundation
import KanameCore
import Testing

/// "core ↔ Swift coverage map" — proves the pure rolling-24-month coverage classifier is
/// reachable across the UniFFI bridge and returns exactly what the engine computes. Input is
/// 100% synthetic. The classifier takes a caller-supplied `today` (the core never reads the
/// wall-clock), per-statement facts (period-end + needsReview) and per-transaction facts (date +
/// from-full-statement), and classifies each of the 24 months as GAP / PARTIAL / COVERED.
@Suite("Statement coverage map over the bridge")
struct CoverageTests {
    private static let statements = [
        StatementCoverage(periodEnd: "2026-05-16", needsReview: false),
        StatementCoverage(periodEnd: "2026-02-28", needsReview: true),
    ]
    private static let transactions = [
        TransactionCoverage(date: "2026-04-10", fromFullStatement: false),
        TransactionCoverage(date: "2026-05-05", fromFullStatement: true),
        TransactionCoverage(date: "2026-01-20", fromFullStatement: true),
    ]

    @Test("Classifies the rolling 24 months (GAP/PARTIAL/COVERED + needsReview) over the bridge")
    func classifiesTheReferenceScenario() throws {
        let months = computeCoverage(
            today: "2026-06-14",
            statements: Self.statements,
            transactions: Self.transactions
        )
        #expect(months.count == 24)
        // Oldest first, ending at today's month.
        #expect(months.first?.month == "2024-07")
        #expect(months.last?.month == "2026-06")

        let byMonth = Dictionary(uniqueKeysWithValues: months.map { ($0.month, $0) })

        let may = try #require(byMonth["2026-05"])
        #expect(may.state == .covered)
        #expect(may.needsReview == false)

        let feb = try #require(byMonth["2026-02"])
        #expect(feb.state == .covered)
        // needsReview rides on the flagged statement run.
        #expect(feb.needsReview == true)

        let apr = try #require(byMonth["2026-04"])
        #expect(apr.state == .partial)
        #expect(apr.needsReview == false)

        // COVERED only via a full-statement transaction (no statement record) → needsReview false.
        let jan = try #require(byMonth["2026-01"])
        #expect(jan.state == .covered)
        #expect(jan.needsReview == false)

        let mar = try #require(byMonth["2026-03"])
        #expect(mar.state == .gap)
    }
}
