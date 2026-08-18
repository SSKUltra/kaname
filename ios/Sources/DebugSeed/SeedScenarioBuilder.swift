#if DEBUG

import Foundation
import KanameCore

/// Turns one declared statement into the exact `ImportRequest` the shipped import path builds,
/// so a seeded row goes into the store through the front door and through nothing else.
///
/// The whole point of this type is that it produces **an input to `Store.importStatement`** and
/// nothing more. It writes no SQL, opens no database, sets no flag the import pipeline cannot
/// set, and holds no power a person's own import does not have — which is why a seeded store is
/// a store a person could actually have, and why an audit of a seeded screen means something.
///
/// Two clauses of a scenario are deliberately not expressible here, and neither is worked
/// around: a **deleted** row (`is_deleted` has no write path in the store's API at all) and a
/// **transfer-flagged** row (written only by `detect_transfers`, which
/// `scripts/import-path-audit.sh` forbids the app from calling). Acquiring either would be
/// seeding holding a power the import pipeline lacks.
enum SeedScenarioBuilder {
    /// The request for one declared statement.
    ///
    /// `existingAccountID` is the id an earlier statement of the same account name created; a
    /// re-import needs it, and a first import must not have one. The request's `now` is the
    /// scenario's declared instant — never a clock, so two runs a day apart write the same
    /// timestamps (FR-023).
    static func request(
        for statement: SeedStatement,
        in scenario: SeedScenario,
        existingAccountID: String?
    ) -> ImportRequest {
        ImportRequest(
            account: target(for: statement, existingAccountID: existingAccountID),
            bankCode: statement.bankCode,
            periodStart: statement.periodStart,
            periodEnd: statement.periodEnd,
            needsReview: false,
            source: .statement,
            transactions: statement.rows.map(transaction),
            now: scenario.now
        )
    }

    private static func target(
        for statement: SeedStatement,
        existingAccountID: String?
    ) -> ImportAccountTarget {
        if statement.reimportsPrevious {
            guard let existingAccountID else {
                fatalError(
                    "\(statement.accountName): reimportsPrevious, but no earlier statement "
                        + "created that account. Statements are applied in declaration order.")
            }
            return .existing(id: existingAccountID, last4: statement.last4)
        }
        if existingAccountID != nil {
            fatalError(
                "\(statement.accountName): a second statement for one account must declare "
                    + "reimportsPrevious, or it would create a duplicate account.")
        }
        return .new(
            name: statement.accountName,
            bankCode: statement.bankCode,
            isCreditCard: statement.isCreditCard,
            last4: statement.last4,
            currency: statement.currency
        )
    }

    private static func transaction(_ row: SeedRow) -> NewImportTransaction {
        NewImportTransaction(
            date: row.date,
            descriptionRaw: row.description,
            // Exact: the declaration is a base-10 string precisely so no `Double` is on the
            // path between what a scenario says and what the store holds.
            amount: row.decimalAmount,
            // Stated, never inferred from the sign of an amount — the same rule the engine
            // records a direction by.
            direction: row.direction == .debit ? .debit : .credit,
            // The **row's** currency, never the account's.
            currency: row.currency,
            sourceCategory: row.sourceCategory
        )
    }
}

#endif
