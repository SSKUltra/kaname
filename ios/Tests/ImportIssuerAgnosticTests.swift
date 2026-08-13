import Foundation
import KanameCore
import Testing

@testable import Kaname

/// The app must never need to know which bank a document came from. What it may do is ask
/// the engine and render the answer; what it may not do is branch on it, name one, or leak
/// an engine identifier into a sentence a person reads.
///
/// All statement text is 100% synthetic.
@Suite("Import stays issuer-agnostic")
struct ImportIssuerAgnosticTests {
    private static let key = "1c4b7ae0d9f83526bb11cc22dd33ee44ff5566778899aabbccddeeff00112233"
    private static let anyURL = URL(fileURLWithPath: "/dev/null/statement.pdf")

    private struct StubExtractor: StatementTextExtractor {
        let text: ExtractedText

        func extract(from url: URL, password: String?) throws -> ExtractedText { text }
    }

    private struct FailingExtractor: StatementTextExtractor {
        let failure: ExtractionFailure

        func extract(from url: URL, password: String?) throws -> ExtractedText { throw failure }
    }

    private static func tempDatabase() -> (dir: URL, path: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-agnostic-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("kaname.db").path)
    }

    /// Every byte of every file the store owns — the database and any journal beside it.
    /// Compared literally rather than by size or row count, because "nothing was written"
    /// has to mean nothing at all.
    private static func storeBytes(in dir: URL) -> [String: Data] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.reduce(into: [:]) { snapshot, name in
            snapshot[name] = try? Data(contentsOf: dir.appendingPathComponent(name))
        }
    }

    private static func service(
        extractor: any StatementTextExtractor,
        store: Store
    ) -> ImportService {
        ImportService(
            extractor: extractor,
            store: store,
            now: { Date(timeIntervalSince1970: 1_786_000_000) }
        )
    }

    private static func extracted(_ lines: [String]) -> ExtractedText {
        ExtractedText(lines: lines, fullText: lines.joined(separator: "\n"), lineWords: [])
    }

    /// A document with real text that no reader claims: a utility bill, not a statement.
    private static let unclaimedLines = [
        "MUNICIPAL WATER SUPPLY",
        "Consumer Number 88213344",
        "Billing Period 01 Jun 2026 to 30 Jun 2026",
        "Units consumed 14",
        "Amount payable 612.00",
    ]

    /// Claimed by both an account reader and a card reader — the tie-break case. The engine
    /// resolves it to the ledger, and the app must simply show whatever won.
    private static let doublyClaimedLines = [
        "ICICI Bank Limited",
        "Statement of Transactions in Savings Account",
        "Account Number 000401000123456",
        "Statement Period June 16, 2025 to July 15, 2025",
        "Opening Balance 1,00,000.00",
        "S No. Value Date Transaction Date Cheque No. Transaction Remarks Withdrawal Deposit Balance",
        "1 16.06.2025 16.06.2025 UPI/512345/EXAMPLE STORE/Payment 5,000.00 95,000.00",
        "2 18.06.2025 18.06.2025 NEFT-N123-EXAMPLE EMPLOYER-SALARY 50,000.00 1,45,000.00",
        "Closing Balance 1,45,000.00",
    ]

    @Test("A document no reader claims fails as unrecognized and writes nothing")
    func unclaimedDocumentLeavesTheStoreByteIdentical() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        let before = Self.storeBytes(in: db.dir)
        let service = Self.service(
            extractor: StubExtractor(text: Self.extracted(Self.unclaimedLines)),
            store: store
        )

        await #expect(throws: ImportFailure.unrecognizedIssuer) {
            try await service.run(url: Self.anyURL, password: nil) { _ in }
        }

        #expect(Self.storeBytes(in: db.dir) == before)
        #expect(try store.listAccounts().isEmpty)
    }

    @Test("An unrecognized layout is never reported as an unreadable scan")
    func unrecognizedIsDistinctFromNoExtractableText() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        // Text came out, but nobody claims it: the file was fine, Kaname just doesn't read it.
        await #expect(throws: ImportFailure.unrecognizedIssuer) {
            try await Self.service(
                extractor: StubExtractor(text: Self.extracted(Self.unclaimedLines)),
                store: store
            ).run(url: Self.anyURL, password: nil) { _ in }
        }

        // No text came out at all: a different thing to say, with a different remedy.
        await #expect(throws: ImportFailure.noExtractableText) {
            try await Self.service(
                extractor: FailingExtractor(failure: .noExtractableText),
                store: store
            ).run(url: Self.anyURL, password: nil) { _ in }
        }
    }

    @Test("A document two readers claim resolves to one, and the winner is on screen")
    func doublyClaimedDocumentShowsTheWinningIssuer() async throws {
        // Both a ledger and a card reader recognise this text: the premise of the test.
        #expect(iciciBankClaims(fullText: Self.doublyClaimedLines.joined(separator: "\n")))
        #expect(iciciClaims(fullText: Self.doublyClaimedLines.joined(separator: "\n")))

        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        let summary = try #require(
            (try await Self.service(
                extractor: StubExtractor(text: Self.extracted(Self.doublyClaimedLines)),
                store: store
            ).run(url: Self.anyURL, password: nil) { _ in }).summary)

        // Whatever the engine picked is what the person is told — the app never renames it.
        let winner = try #require(detectIssuer(fullText: Self.doublyClaimedLines.joined(separator: "\n")))
        #expect(winner.kind == .bankAccount)
        #expect(summary.issuerDisplayName == winner.displayName)

        // The losing reader's parse was never produced, let alone persisted: a card reader
        // winning here would have produced a credit-card account.
        let account = try #require(try store.listAccounts().first)
        #expect(account.isCreditCard == false)
        #expect(summary.transactionsImported == 2)
    }

    @Test("Every failure says its own thing — no shared generic message")
    func everyFailureHasItsOwnSentence() {
        let failures: [ImportFailure] = [
            .notAPDF, .passwordRequired, .wrongPassword, .noExtractableText, .unreadable,
            .unrecognizedIssuer, .cancelled, .storageUnavailable,
        ]

        // A person is told what happened to *their* file, so no two failures may share a
        // sentence or a title.
        #expect(Set(failures.map(\.title)).count == failures.count)
        #expect(Set(failures.map(\.message)).count == failures.count)
        // Symbols may repeat only where the situation genuinely is the same one: a locked
        // statement and a rejected password are both "this document needs its password".
        #expect(ImportFailure.passwordRequired.symbolName == ImportFailure.wrongPassword.symbolName)
        #expect(Set(failures.map(\.symbolName)).count == failures.count - 1)
    }

    @Test("A statement whose rows could not be read says so, rather than reporting no spending")
    func aStatementWithNoRecognisedRowsIsNotReportedAsEmpty() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        // Enough for a reader to claim the document, with nothing it can parse as a row —
        // what an extraction that lost the transactions looks like from here.
        let summary = try #require(
            (try await Self.service(
                extractor: StubExtractor(
                    text: Self.extracted([
                        "ICICI Bank Statement",
                        "Statement Date May 28, 2026",
                        "4315XXXXXXXX1002",
                    ])
                ),
                store: store
            ).run(url: Self.anyURL, password: nil) { _ in }).summary)

        #expect(summary.transactionsImported == 0)
        #expect(summary.nothingRecognized)
        #expect(!ImportSummary.nothingRecognizedNotice.message.isEmpty)
    }

    @Test("A statement that really had no transactions is reported as the success it is")
    func aGenuinelyEmptyStatementIsNotFlagged() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        // A billing period with no activity, where the statement's own printed totals say so:
        // zero spent, zero paid. That is the statement vouching for its own emptiness, and it
        // is the only thing that earns a quiet "0 transactions".
        let summary = try #require(
            (try await Self.service(
                extractor: StubExtractor(
                    text: Self.extracted([
                        "YES BANK",
                        "Card Number XXXX XXXX XXXX 6686",
                        "Statement Period: 17/04/2026 To 16/05/2026",
                        "Current Purchases Rs. 0.00 Dr",
                        "Payment & Credits Received Rs. 0.00 Cr",
                    ])
                ),
                store: store
            ).run(url: Self.anyURL, password: nil) { _ in }).summary)

        #expect(summary.transactionsImported == 0)
        #expect(summary.integrity == .agrees)
        #expect(!summary.nothingRecognized)
    }

    /// A bank ledger with no rows cannot be told apart from an extraction that lost them:
    /// the reader records no printed balance at all when it finds no anchor row. So the
    /// cautious answer is the only honest one — a quiet month is told "Kaname couldn't make
    /// out any transactions", which is never a lie, where "you had no spending" could be.
    @Test("A ledger with no readable rows is told cautiously, never as an empty month")
    func aLedgerWithNoRowsIsAlwaysTreatedCautiously() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        let summary = try #require(
            (try await Self.service(
                extractor: StubExtractor(
                    text: Self.extracted([
                        "HDFC BANK LIMITED",
                        "Statementof account",
                        "From : 01/04/2026 To : 30/04/2026",
                        "AccountNo : 50100359253425",
                        "Date Narration Chq./Ref.No. ValueDt WithdrawalAmt. DepositAmt. ClosingBalance",
                    ])
                ),
                store: store
            ).run(url: Self.anyURL, password: nil) { _ in }).summary)

        #expect(summary.transactionsImported == 0)
        #expect(summary.nothingRecognized)
    }

    @Test("No failure sentence names a bank, a reader or an error code")
    func failureCopyLeaksNoEngineDetail() {
        // Identifier and code shapes: an engine id (`ICICI_BANK`), a Swift error's own text,
        // or a bare numeric code would all read as noise to a person.
        let forbiddenShapes = ["_", "Error", "error", "nil", "Optional", "()", "kaname", "Rust"]
        // Names the app must not know. The mechanical, registry-derived version of this check
        // is `scripts/import-path-audit.sh`; this one guards the sentences themselves.
        let bankWords = [
            "ICICI", "HDFC", "SBI", "AU ", "IOB", "Federal", "Scapia", "Kiwi", "Overseas", "YES",
        ]

        let failures: [ImportFailure] = [
            .notAPDF, .passwordRequired, .wrongPassword, .noExtractableText, .unreadable,
            .unrecognizedIssuer, .cancelled, .storageUnavailable,
        ]

        for failure in failures {
            for text in [failure.title, failure.message] {
                #expect(!text.isEmpty)
                for shape in forbiddenShapes {
                    #expect(!text.contains(shape), "\(failure) leaks \(shape): \(text)")
                }
                for word in bankWords {
                    #expect(!text.contains(word), "\(failure) names a bank: \(text)")
                }
                #expect(
                    text.rangeOfCharacter(from: .decimalDigits) == nil,
                    "\(failure) carries a numeric code: \(text)"
                )
            }
        }

        // The same rule holds for what an integrity verdict says.
        for outcome in [IntegrityOutcome.agrees, .needsReview] {
            let message = try? #require(outcome.notice?.message)
            for shape in forbiddenShapes {
                #expect(!(message ?? "").contains(shape))
            }
        }
    }
}
