import Foundation
import KanameCore
import Testing

/// "core ↔ Swift cross-source de-dup" — proves the pure in-memory cross-source matcher is
/// reachable across the UniFFI bridge and returns exactly what the engine computes. Input is
/// 100% synthetic. The matcher pairs an incoming list (e.g. a card statement) against an
/// existing list (e.g. a bank ledger): a same-date/amount/direction row with the same
/// normalised-narration prefix is a Canonical duplicate; a ±1-day, same-amount row whose
/// narration is Jaro-Winkler ≥ 0.92 similar is a Fuzzy duplicate; each existing row is
/// consumed at most once, so a surplus repeat survives.
@Suite("Cross-source de-duplication over the bridge")
struct CrossSourceDedupTests {
    private static func txn(
        _ date: String,
        _ description: String,
        _ amount: String,
        _ direction: Direction
    ) -> Transaction {
        Transaction(
            date: date,
            description: description,
            amount: Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0,
            direction: direction
        )
    }

    private static let existing = [
        txn("2026-07-04", "Swiggy Bangalore", "250.00", .debit),
        txn("2026-07-10", "swiggy bangalore", "500.00", .debit),
        txn("2026-07-25", "uber", "200.00", .debit),
    ]
    private static let incoming = [
        txn("2026-07-04", "swiggy   bangalore", "250.00", .debit),
        txn("2026-07-11", "swiggy bangaluru", "500.00", .debit),
        txn("2026-07-25", "uber", "200.00", .debit),
        txn("2026-07-25", "uber", "200.00", .debit),
    ]

    @Test("Canonical + fuzzy + multiplicity matches surface exactly over the bridge")
    func matchesCanonicalFuzzyAndMultiplicity() throws {
        let matches = crossSourceDuplicates(existing: Self.existing, incoming: Self.incoming)
        // I0→E0 canonical, I1→E1 fuzzy, I2→E2 canonical; I3 (surplus uber) survives.
        #expect(matches.count == 3)

        let canonical = try #require(matches.first)
        #expect(canonical.incomingIndex == 0)
        #expect(canonical.existingIndex == 0)
        #expect(canonical.layer == .canonical)

        let fuzzy = matches[1]
        #expect(fuzzy.incomingIndex == 1)
        #expect(fuzzy.existingIndex == 1)
        #expect(fuzzy.layer == .fuzzy)

        let multiplicity = matches[2]
        #expect(multiplicity.incomingIndex == 2)
        #expect(multiplicity.existingIndex == 2)
        #expect(multiplicity.layer == .canonical)
        // The 4th incoming "uber" finds no unconsumed existing row and is not matched.
        #expect(!matches.contains { $0.incomingIndex == 3 })
    }
}
