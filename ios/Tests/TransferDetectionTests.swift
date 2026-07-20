import Foundation
import KanameCore
import Testing

/// "core ↔ Swift transfer detection" — proves the pure single-pool self-transfer matcher is
/// reachable across the UniFFI bridge and returns exactly what the engine computes. Input is
/// 100% synthetic. The matcher anchors on outflows in (date, id) order and greedily claims the
/// best opposite-direction counterpart on a different account within ±1 day / ±₹1.00; a bank
/// outflow paired with a credit-card "payment received" inflow is flagged as a card bill payment.
@Suite("Transfer detection over the bridge")
struct TransferDetectionTests {
    private static func decimal(_ amount: String) -> Decimal {
        Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private static func out(
        _ id: String, _ account: String, _ date: String, _ amount: String, _ description: String
    ) -> TransferInput {
        TransferInput(
            id: id, accountId: account, isCreditCard: false, date: date,
            amount: decimal(amount), direction: .debit, description: description
        )
    }

    private static func inflow(
        _ id: String, _ account: String, _ date: String, _ amount: String, _ description: String
    ) -> TransferInput {
        TransferInput(
            id: id, accountId: account, isCreditCard: false, date: date,
            amount: decimal(amount), direction: .credit, description: description
        )
    }

    // Three amount-isolated scenarios in one pool: a plain self-transfer, an ambiguous pair
    // resolved by the closer narration, and a credit-card bill payment (its card leg built inline).
    private static let rows = [
        out("a", "acct-a", "2026-06-01", "5000.00", "NEFT TO HDFC"),
        inflow("b", "acct-b", "2026-06-01", "5000.00", "NEFT FROM ICICI"),
        out("s", "acct-a", "2026-06-05", "500.00", "NEFT TO HDFC BANK XX1234"),
        inflow("better", "acct-b", "2026-06-05", "500.00", "NEFT FROM ICICI BANK XX5678"),
        inflow("worse", "acct-b", "2026-06-05", "500.00", "SALARY CREDIT FROM ACME CORP"),
        out("card-out", "acct-a", "2026-06-10", "8000.00", "CC BILL PAYMENT"),
        TransferInput(
            id: "card-in", accountId: "acct-c", isCreditCard: true, date: "2026-06-10",
            amount: decimal("8000.00"), direction: .credit, description: "PAYMENT RECEIVED"
        ),
    ]

    @Test("Pairs, tie-break and the card-payment flag surface exactly over the bridge")
    func detectsTransfersAcrossTheBridge() throws {
        let pairs = detectTransfers(rows: Self.rows)
        // Anchors sort by (date, id): a (06-01) → s (06-05) → card-out (06-10).
        #expect(pairs.count == 3)

        let plain = try #require(pairs.first)
        #expect(plain.outflowId == "a")
        #expect(plain.inflowId == "b")
        #expect(!plain.isCreditCardPayment)
        // sim("neft to hdfc","neft from icici") = 1/5 → score 1 + 0.2·0.2 = 1.04.
        #expect(abs(plain.score - 1.04) < 1e-9)

        let ambiguous = pairs[1]
        #expect(ambiguous.outflowId == "s")
        // The closer narration wins the tie, not "SALARY CREDIT FROM ACME CORP".
        #expect(ambiguous.inflowId == "better")
        #expect(!ambiguous.isCreditCardPayment)

        let cardPayment = pairs[2]
        #expect(cardPayment.outflowId == "card-out")
        #expect(cardPayment.inflowId == "card-in")
        #expect(cardPayment.isCreditCardPayment)

        // "worse" is left unclaimed — every row is paired at most once.
        #expect(!pairs.contains { $0.inflowId == "worse" })
    }
}
