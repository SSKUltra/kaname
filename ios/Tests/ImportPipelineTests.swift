import Foundation
import KanameCore
import Testing

@testable import Kaname

/// The whole import vertical over the bridge: extracted text → issuer → parse → integrity →
/// the encrypted store, asserted end to end against the real engine and a real SQLCipher
/// database. Extraction is stubbed (there is no PDF here) so every other stage is genuine.
///
/// All statement text is 100% synthetic.
@Suite("Statement import pipeline")
struct ImportPipelineTests {
    /// A synthetic 256-bit key (64 hex chars).
    private static let key = "9f2c1a7e5b3d40628899aabbccddeeff00112233445566778899aabbccddee01"
    private static let importedAt = "2026-08-12T09:30:00Z"

    private static func decimal(_ value: String) -> Decimal? {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// A fresh temp database directory; the caller removes it when done.
    private static func tempDatabase() -> (dir: URL, path: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-import-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("kaname.db").path)
    }

    /// Stands in for PDFKit: the pipeline is exercised without a file on disk, which is the
    /// whole reason extraction sits behind a protocol.
    private struct StubExtractor: StatementTextExtractor {
        let text: ExtractedText

        func extract(from url: URL, password: String?) throws -> ExtractedText { text }
    }

    private static func extracted(_ lines: [String]) -> ExtractedText {
        ExtractedText(lines: lines, fullText: lines.joined(separator: "\n"), lineWords: [])
    }

    private static func service(lines: [String], store: Store) -> ImportService {
        ImportService(
            extractor: StubExtractor(text: extracted(lines)),
            store: store,
            now: { ISO8601DateFormatter().date(from: importedAt) ?? Date(timeIntervalSince1970: 0) }
        )
    }

    /// A synthetic ICICI credit-card statement: one credit, one debit.
    private static let cardLines = [
        "ICICI Bank Statement",
        "Statement Date May 28, 2026",
        "4315XXXXXXXX1002",
        "29/04/2026 4262 BBPS Payment received 0 13,628.36 CR",
        "26/05/2026 1814 Fee on gaming transaction 0 10.20",
    ]

    /// A synthetic HDFC savings ledger: one withdrawal, one deposit, balance-chain anchored.
    private static let ledgerLines = [
        "HDFC BANK LIMITED",
        "Statementof account",
        "From : 01/04/2026 To : 30/04/2026",
        "AccountNo : 50100359253425",
        "Date Narration Chq./Ref.No. ValueDt WithdrawalAmt. DepositAmt. ClosingBalance",
        "01/04/26 UPI-EXAMPLEMERCHANT 0000600000000001 01/04/26 5,000.00 95,000.00",
        "16/04/26 NEFTCR-EXAMPLEEMPLOYER CITIN26653417445 16/04/26 50,000.00 1,45,000.00",
        "OpeningBalance DrCount CrCount Debits Credits ClosingBal",
        "1,00,000.00 1 1 5,000.00 50,000.00 1,45,000.00",
    ]

    private static let anyURL = URL(fileURLWithPath: "/dev/null/statement.pdf")

    @Test("A supported card statement imports end to end and lands in the encrypted store")
    func importsASupportedCardStatementEndToEnd() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        var stages: [ImportStage] = []
        let result = try await Self.service(lines: Self.cardLines, store: store)
            .run(url: Self.anyURL, password: nil) { stages.append($0) }
        let summary = try #require(result.summary)

        // The issuer's own name is shown, so a tie-break between two readers is visible.
        #expect(summary.issuerDisplayName == "ICICI Amazon Pay Credit Card")
        #expect(summary.last4 == "1002")
        // Nothing existed before this import, so the account was created for it.
        #expect(summary.accountIsNew)
        #expect(summary.transactionsAdded == 2)
        #expect(summary.unreadableRows == 0)
        #expect(stages.first == .reading)
        #expect(stages.contains(.saving))

        let accounts = try store.listAccounts()
        #expect(accounts.count == 1)
        let account = try #require(accounts.first)
        #expect(account.bankCode == "ICICI")
        #expect(account.isCreditCard)
        #expect(account.last4 == "1002")

        let stored = try store.listTransactions(accountId: account.id)
        #expect(stored.count == 2)
        // Every row is attached to the statement it came from, so an import is reversible.
        #expect(stored.allSatisfy { $0.statementId != nil })
        let credit = try #require(stored.first { $0.direction == .credit })
        #expect(credit.amount == Self.decimal("13628.36"))
        let debit = try #require(stored.first { $0.direction == .debit })
        #expect(debit.amount == Self.decimal("10.20"))
    }

    @Test("A supported bank ledger imports with the directions the balance chain implies")
    func importsASupportedBankLedgerWithCorrectDirections() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        let summary = try #require(
            (try await Self.service(lines: Self.ledgerLines, store: store)
                .run(url: Self.anyURL, password: nil) { _ in }).summary)

        #expect(summary.issuerDisplayName == "HDFC Bank Account")
        #expect(summary.transactionsAdded == 2)
        // The statement's figures all agree, so the import is not flagged for review.
        #expect(summary.integrity == .agrees)

        let account = try #require(try store.listAccounts().first)
        #expect(account.isCreditCard == false)
        #expect(account.bankCode == "HDFC")

        let stored = try store.listTransactions(accountId: account.id)
        #expect(stored.count == 2)
        // Direction comes from the balance delta, never from the amount's sign.
        let withdrawal = try #require(stored.first { $0.amount == Self.decimal("5000.00") })
        #expect(withdrawal.direction == .debit)
        let deposit = try #require(stored.first { $0.amount == Self.decimal("50000.00") })
        #expect(deposit.direction == .credit)
    }

    @Test("Imported transactions survive closing and reopening the store")
    func persistsAcrossAReopenOfTheStore() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }

        let accountId: String
        do {
            let store = try Store.open(path: db.path, key: Self.key)
            _ = try await Self.service(lines: Self.cardLines, store: store)
                .run(url: Self.anyURL, password: nil) { _ in }
            accountId = try #require(try store.listAccounts().first).id
        }

        // A second open of the same file: the rows were persisted, not held in memory.
        let reopened = try Store.open(path: db.path, key: Self.key)
        let stored = try reopened.listTransactions(accountId: accountId)
        #expect(stored.count == 2)
        #expect(stored.contains { $0.amount == Self.decimal("13628.36") })
    }

    @Test("The summary reports how the imported rows were categorized")
    func reportsTheCategorizedSplit() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        let summary = try #require(
            (try await Self.service(lines: Self.ledgerLines, store: store)
                .run(url: Self.anyURL, password: nil) { _ in }).summary)

        // Every imported row is accounted for on one side of the split or the other.
        #expect(summary.categorized + summary.uncategorized == summary.transactionsAdded)

        let account = try #require(try store.listAccounts().first)
        let stored = try store.listTransactions(accountId: account.id)
        let persistedCategorized = stored.filter { $0.categoryId != nil }.count
        #expect(persistedCategorized == summary.categorized)
    }

    @Test("Amounts cross the bridge and the store as exact decimals")
    func carriesAmountsAsExactDecimals() throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)

        // Zero, a value beyond a Double's exact integer range, and a sub-paisa fraction.
        let amounts = ["0", "999999999999.99", "0.000000001"]
        let transactions = try amounts.map { value in
            NewImportTransaction(
                date: "2026-04-01",
                descriptionRaw: "SYNTHETIC ROW \(value)",
                amount: try #require(Self.decimal(value)),
                direction: .debit,
                currency: "INR",
                sourceCategory: nil
            )
        }

        let outcome = try store.importStatement(
            request: ImportRequest(
                account: .new(
                    name: "Synthetic",
                    bankCode: "ICICI",
                    isCreditCard: true,
                    last4: "1002",
                    currency: "INR"
                ),
                bankCode: "ICICI",
                periodStart: "2026-04-01",
                periodEnd: "2026-04-30",
                needsReview: false,
                source: .statement,
                transactions: transactions,
                now: Self.importedAt
            )
        )
        #expect(outcome.rowsRead == 3)
        #expect(outcome.transactionsAdded == 3)

        let stored = try store.listTransactions(accountId: outcome.accountId)
        for value in amounts {
            let expected = try #require(Self.decimal(value))
            // Exact equality, not a tolerance: money never becomes a float on this path.
            #expect(stored.contains { $0.amount == expected })
        }
    }

    // MARK: - Through a real document

    /// The suites above stub extraction so the stages after it are genuine. These do the
    /// opposite: a real file, opened by the real PDF engine, its rows recovered from the
    /// page geometry. Slice 017 changed the text every judgement below is made from, so the
    /// honest-failure behaviour has to be shown to survive the change — not just the happy
    /// path.
    private final class Rendered {
        let directory: URL

        init() {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("kaname-rendered-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        var url: URL { directory.appendingPathComponent("statement.pdf") }
    }

    private static func realService(store: Store) -> ImportService {
        ImportService(
            extractor: PDFKitStatementTextExtractor(),
            store: store,
            now: { ISO8601DateFormatter().date(from: importedAt) ?? Date(timeIntervalSince1970: 0) }
        )
    }

    private static func writeLines(_ lines: [String], to url: URL) throws {
        try StatementTextExtractorTests.writeTextPDF(lines: lines, to: url)
    }

    @Test("A real document with no text to read fails honestly and writes nothing")
    func aRenderedScanFailsHonestlyAndWritesNothing() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)
        let rendered = Rendered()
        // A real page with nothing printed on it: no words to reshape and no geometry to
        // trust. Reshaping must not turn that into an empty statement.
        try Self.writeLines([], to: rendered.url)

        await #expect(throws: ImportFailure.noExtractableText) {
            _ = try await Self.realService(store: store).run(url: rendered.url, password: nil) { _ in }
        }
        #expect(try store.listAccounts().isEmpty)
    }

    @Test("A real document no reader claims is unrecognized, and the store is untouched")
    func aRenderedUnclaimedDocumentWritesNothing() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)
        let rendered = Rendered()
        try Self.writeLines(
            [
                "EXAMPLE COOPERATIVE SOCIETY",
                "Passbook extract for April 2026",
                "01/04/2026 Subscription 500.00",
            ],
            to: rendered.url
        )

        await #expect(throws: ImportFailure.unrecognizedIssuer) {
            _ = try await Self.realService(store: store).run(url: rendered.url, password: nil) { _ in }
        }
        #expect(try store.listAccounts().isEmpty)
    }

    @Test("A real statement whose rows cannot be read says so rather than reporting no spending")
    func aRenderedStatementWithNoReadableRowsIsNotReportedAsEmpty() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)
        let rendered = Rendered()
        // A document a reader claims, printed with nothing it can parse as a row. This is
        // what a lost extraction looks like from here, and it is the one thing that must
        // never come back as "no spending".
        try Self.writeLines(
            [
                "ICICI Bank Statement",
                "Statement Date May 28, 2026",
                "4315XXXXXXXX1002",
            ],
            to: rendered.url
        )

        let summary = try #require(
            (try await Self.realService(store: store).run(url: rendered.url, password: nil) { _ in }).summary
        )

        #expect(summary.transactionsAdded == 0)
        #expect(summary.nothingRecognized)
    }
}
