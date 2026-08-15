import Foundation
import Testing

@testable import Kaname

/// Every sentence this screen can say, audited as data.
///
/// Two failures are being prevented, and neither is cosmetic. The first is "1 transactions" —
/// small, but it is the tell that a person is reading generated text rather than something
/// written for them, on the one screen where they most need to trust what they read. The
/// second is worse: a sentence that says "missing", "lost" or "error" about a statement that
/// genuinely had no transactions in it tells somebody their money went astray inside Kaname.
/// Neither is caught by review, because both read fine in isolation.
@Suite("What the transaction list is allowed to say")
struct TransactionListStringsTests {
    /// Every empty state, in every shape it can take.
    private static let everyEmptyState: [TransactionListStrings.EmptyState] = [
        .nothingImported,
        .noTransactionsAnywhere,
        .nothingToShowAnywhere,
        .accountStatementEmpty(name: "Everyday Savings"),
        .accountNothingToShow(name: "Everyday Savings"),
        .accountEmptyOthersHaveRows(name: "Everyday Savings", statementWasEmpty: true),
        .accountEmptyOthersHaveRows(name: "Everyday Savings", statementWasEmpty: false),
    ].map(TransactionListStrings.emptyState(for:))

    /// Every user-visible string in the file, gathered here so a new one cannot quietly escape
    /// the audit by being added somewhere else.
    private static var everySentence: [String] {
        everyEmptyState.flatMap { [$0.title, $0.message] }
            + [
                TransactionListStrings.title,
                TransactionListStrings.frontDoorLink,
                TransactionListStrings.loadingAnnouncement,
                TransactionListStrings.scopeAll,
                TransactionListStrings.menuHeader,
                TransactionListStrings.clearFilter,
                TransactionListStrings.scopeHint,
                TransactionListStrings.debit,
                TransactionListStrings.credit,
                TransactionListStrings.uncategorized,
                TransactionListStrings.transfer,
                TransactionListStrings.transferAnnouncement,
                TransactionListStrings.missingDescription,
                TransactionListStrings.unavailableTitle,
                TransactionListStrings.unavailableMessage,
                TransactionListStrings.unavailableRetry,
                TransactionListStrings.maskedLast4("1123"),
                TransactionListStrings.accountIdentity(name: "Everyday Savings", last4: "1123"),
                TransactionListStrings.accountIdentity(name: "Cash Wallet", last4: nil),
                TransactionListStrings.scopeAnnouncement(name: nil, last4: nil),
                TransactionListStrings.scopeAnnouncement(name: "Everyday Savings", last4: "1123"),
                TransactionListStrings.transactionCount(0),
                TransactionListStrings.transactionCount(1),
                TransactionListStrings.transactionCount(2),
                TransactionListStrings.groupAnnouncement(heading: "15 July", count: 1),
                TransactionListStrings.groupAnnouncement(heading: "15 July", count: 3),
            ]
    }

    // MARK: - T094 — one pluralisation helper, and it is right

    @Test("A count of one is singular, and every other count is plural")
    func theHelperPluralisesCorrectly() {
        #expect(TransactionListStrings.transactionCount(1) == "1 transaction")
        #expect(TransactionListStrings.transactionCount(0) == "0 transactions")
        #expect(TransactionListStrings.transactionCount(2) == "2 transactions")
        #expect(TransactionListStrings.transactionCount(1_000) == "1000 transactions")
    }

    @Test("Every worded count in the slice comes through that one helper")
    func everyWordedCountUsesTheHelper() {
        // The heading announcement is the helper's real user in this slice (T046). If it ever
        // words a count itself, it will say "1 transactions" here rather than on somebody's
        // screen.
        for count in [0, 1, 2, 11] {
            let announced = TransactionListStrings.groupAnnouncement(heading: "15 July", count: count)
            #expect(announced.hasSuffix(TransactionListStrings.transactionCount(count)))
        }

        // The front door's own sentence too — it is a different file, and the whole point of
        // one helper is that a second one cannot appear beside it (FR-052).
        let account = ImportedAccount(
            id: "account-1", name: "Everyday Savings", last4: "1123", isCreditCard: false,
            transactionCount: 1, hasOnlyExcludedRows: false)
        #expect(ImportedAccountsView.announcement(for: account).hasSuffix("1 transaction"))
    }

    @Test("No sentence in the slice words a count of its own")
    func noSentenceHandRollsAPlural() {
        // A bare "transactions" preceded by a digit anywhere but the helper's own output is a
        // second pluralisation rule being born.
        let handRolled = try? NSRegularExpression(pattern: "\\d+\\s+transactions?\\b")
        let fromTheHelper = Set([0, 1, 2, 3].map(TransactionListStrings.transactionCount))

        for sentence in Self.everySentence where !fromTheHelper.contains(sentence) {
            let range = NSRange(sentence.startIndex..., in: sentence)
            let matches = handRolled?.matches(in: sentence, range: range) ?? []
            for match in matches {
                guard let range = Range(match.range, in: sentence) else { continue }
                #expect(
                    fromTheHelper.contains(String(sentence[range])),
                    "\"\(sentence)\" words a count without the helper"
                )
            }
        }
    }

    // MARK: - T095 — nothing accuses the app of losing anything

    @Test("No empty state blames anyone or suggests data went astray")
    func noEmptyStateAccusesTheAppOfLoss() {
        // The exact words FR-051 names, plus the shapes they arrive in. An empty statement is
        // not a failure, and a superseded row is not a missing one.
        let blame = [
            "lost", "missing", "gone", "error", "failed", "failure", "corrupt", "damaged",
            "couldn't find", "unable", "invalid", "wrong",
        ]
        for empty in Self.everyEmptyState {
            for word in blame {
                #expect(
                    !empty.title.lowercased().contains(word),
                    "\"\(empty.title)\" contains \"\(word)\""
                )
                #expect(
                    !empty.message.lowercased().contains(word),
                    "\"\(empty.message)\" contains \"\(word)\""
                )
            }
        }
    }

    @Test("No sentence carries an identifier, a code, or anything the engine wrote")
    func noSentenceLeaksMachineText() {
        // The vocabulary of the machine: layer names, cursor fields, storage internals, and
        // the words an error message is made of. None of it is actionable by a person, and
        // all of it would be a leak of how Kaname works into what Kaname says (FR-019).
        let machine = [
            "sequence", "cursor", "rowid", "account_id", "accountId", "statement_id",
            "canonical", "dedup", "superseded", "is_deleted", "isDeleted", "predicate",
            "SQL", "SQLite", "SQLCipher", "sqlite", "UniFFI", "FFI", "Rust", "panic",
            "unwrap", "nil", "Optional(", "StoreError", "HistoryQuery", "0x", "errno",
            "localizedDescription", "bank_code", "bankCode",
        ]
        for sentence in Self.everySentence {
            for token in machine {
                #expect(!sentence.contains(token), "\"\(sentence)\" contains \"\(token)\"")
            }
        }
    }

    @Test("No sentence reads like a code a person could not act on")
    func noSentenceReadsLikeACode() {
        // A long run of digits or a SCREAMING_SNAKE identifier is what an id and a reader name
        // look like. The counts and the masked last-4 are the only digits allowed, and both
        // are short and mean something to a person.
        let codeShaped = try? NSRegularExpression(pattern: "\\d{5,}|\\b[A-Z]{2,}_[A-Z_]{2,}\\b")
        for sentence in Self.everySentence {
            let range = NSRange(sentence.startIndex..., in: sentence)
            #expect(
                codeShaped?.numberOfMatches(in: sentence, range: range) == 0,
                "\"\(sentence)\" reads like a code"
            )
        }
    }

    @Test("Nothing claims Kaname detects transfers")
    func nothingClaimsTransfersAreDetected() {
        // The app does not run transfer detection today (research R18). The marking is a bare
        // noun, and no sentence anywhere may imply something was found (FR-018).
        let claims = ["detected", "found", "matched", "automatically", "identified", "linked"]
        for sentence in Self.everySentence {
            for claim in claims {
                #expect(!sentence.lowercased().contains(claim), "\"\(sentence)\" claims \"\(claim)\"")
            }
        }
        #expect(TransactionListStrings.transfer == "Transfer")
        #expect(TransactionListStrings.transferAnnouncement == "transfer")
    }

    @Test("Nothing is speechless, and nothing shouts")
    func everySentenceIsASentence() {
        for sentence in Self.everySentence {
            #expect(!sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(sentence == sentence.trimmingCharacters(in: .whitespacesAndNewlines))
            #expect(!sentence.contains("!"))
        }
    }
}
