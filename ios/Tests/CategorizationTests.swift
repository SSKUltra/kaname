import Foundation
import KanameCore
import Testing

/// "core ↔ Swift categorization" — proves the pure first-wins categorization stack is reachable
/// across the UniFFI bridge and returns exactly what the engine computes. Input is 100% synthetic.
/// The stack assigns one category per transaction in the fixed order CC rules → T1 source-category
/// map → T2 merchant map → T3 rules, naming the winner with a stable `CategoryRef` (a built-in code
/// for the 23 defaults, or a caller-supplied custom id) and the stage that fired, or `nil` when
/// nothing matches. Direction is the statement's own Dr/Cr, never the amount's sign.
@Suite("Deterministic categorization over the bridge")
struct CategorizationTests {
    private static func decimal(_ amount: String) -> Decimal {
        Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private static func txn(
        bankCode: String = "ICICI",
        isCreditCard: Bool = false,
        sourceCategory: String? = nil,
        _ description: String,
        _ amount: String,
        _ direction: Direction
    ) -> CategoryTxn {
        CategoryTxn(
            bankCode: bankCode,
            isCreditCard: isCreditCard,
            sourceCategory: sourceCategory,
            description: description,
            amount: decimal(amount),
            direction: direction
        )
    }

    /// The 23 ported defaults, seeded from the engine itself.
    private static let catalog = defaultCategories()

    @Test("The 23 default categories cross the bridge")
    func defaultCatalogCrossesTheBridge() throws {
        #expect(Self.catalog.count == 23)
        // A known built-in surfaces with its stable code and money-bucket classification.
        let groceries = try #require(Self.catalog.first { $0.name == "Groceries" })
        guard case .builtin(let code) = groceries.categoryRef else {
            Issue.record("Groceries must be a built-in category")
            return
        }
        #expect(code == "GROCERIES")
        #expect(groceries.classification == .spend)
    }

    @Test("A credit-card bill-payment inflow fires the CC rule over the bridge")
    func creditCardBillPaymentFiresCcRule() throws {
        let decision = try #require(
            categorize(
                txn: Self.txn(
                    isCreditCard: true,
                    "ONLINE TRF - PYMT RECD - THANK YOU",
                    "5000.00",
                    .credit
                ),
                catalog: Self.catalog,
                merchants: [],
                rules: [],
                sourceMap: []
            )
        )
        #expect(decision.stage == .ccRule)
        #expect(decision.matchedRuleId == nil)
        guard case .builtin(let code) = decision.categoryRef else {
            Issue.record("CC bill payment must map to a built-in category")
            return
        }
        #expect(code == "CREDIT_CARD_BILL_PAYMENT")
    }

    @Test("A merchant-map (T2) hit returns a usable Decision over the bridge")
    func merchantMapHitReturnsDecision() throws {
        let merchants = [
            MerchantRule(
                priority: 10,
                matchType: .literal,
                pattern: "swiggy",
                category: .builtin(code: "FOOD_AND_DINING")
            )
        ]
        // "UPI-SWIGGY-123456" normalizes to "swiggy-123456" → the literal "swiggy" matches.
        let decision = try #require(
            categorize(
                txn: Self.txn("UPI-SWIGGY-123456", "250.00", .debit),
                catalog: Self.catalog,
                merchants: merchants,
                rules: [],
                sourceMap: []
            )
        )
        #expect(decision.stage == .t2MerchantMap)
        guard case .builtin(let code) = decision.categoryRef else {
            Issue.record("merchant hit must map to the built-in food category")
            return
        }
        #expect(code == "FOOD_AND_DINING")
    }

    @Test("A T3 rule echoes its id and a custom category id over the bridge")
    func t3RuleEchoesIdAndCustomCategory() throws {
        let rules = [
            Rule(
                id: "r-tuition",
                priority: 100,
                isSystem: false,
                matchType: .keyword,
                value: "tuition",
                category: .custom(id: "user-school-fees")
            )
        ]
        let decision = try #require(
            categorize(
                txn: Self.txn("TUITION FEE BANGALORE", "5000.00", .debit),
                catalog: Self.catalog,
                merchants: [],
                rules: rules,
                sourceMap: []
            )
        )
        #expect(decision.stage == .t3Rule)
        #expect(decision.matchedRuleId == "r-tuition")
        guard case .custom(let id) = decision.categoryRef else {
            Issue.record("a user rule must echo the caller-supplied custom id")
            return
        }
        #expect(id == "user-school-fees")
    }

    @Test("An unrecognised transaction is left uncategorized (nil) over the bridge")
    func unrecognisedTransactionIsUncategorized() {
        let decision = categorize(
            txn: Self.txn("UNKNOWN VENDOR XYZ", "123.00", .debit),
            catalog: Self.catalog,
            merchants: [],
            rules: [],
            sourceMap: []
        )
        #expect(decision == nil)
    }
}
