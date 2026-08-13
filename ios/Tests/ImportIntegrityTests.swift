import Foundation
import KanameCore
import Testing

@testable import Kaname

/// Whether a person can trust an import. The engine's integrity checks are shipped and
/// tested; what this pins is what they mean on screen — three states, never two — and that a
/// statement failing its check is still imported and recorded as needing review.
///
/// The store is real and encrypted; only extraction is stubbed. All statement text is 100%
/// synthetic.
@Suite("The import tells the truth about whether the figures add up")
struct ImportIntegrityTests {
    /// A synthetic 256-bit key (64 hex chars).
    private static let key = "3311ffee00ddccbbaa99887766554433221100ffeeddccbbaa99887766554433"
    private static let importedAt = "2026-08-13T09:30:00Z"

    private static func tempDatabase() -> (dir: URL, path: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-integrity-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("kaname.db").path)
    }

    private struct StubExtractor: StatementTextExtractor {
        let text: ExtractedText

        func extract(from url: URL, password: String?) throws -> ExtractedText { text }
    }

    private static func service(lines: [String], fullText: String?, store: Store) -> ImportService {
        ImportService(
            extractor: StubExtractor(
                text: ExtractedText(
                    lines: lines,
                    fullText: fullText ?? lines.joined(separator: "\n"),
                    lineWords: []
                )
            ),
            store: store,
            now: { ISO8601DateFormatter().date(from: importedAt) ?? Date(timeIntervalSince1970: 0) }
        )
    }

    private static let anyURL = URL(fileURLWithPath: "/dev/null/statement.pdf")

    /// What one import produced, on both sides of the write: what the person was shown, and
    /// what the encrypted store now holds.
    private struct Imported {
        let summary: ImportSummary
        let statement: StoredStatement
        let transactions: [StoredTransaction]
    }

    private static func importStatement(
        lines: [String],
        fullText: String? = nil
    ) async throws -> Imported {
        let db = tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: key)

        let result = try await service(lines: lines, fullText: fullText, store: store)
            .run(url: anyURL, password: nil) { _ in }
        let summary = try #require(result.summary)
        let account = try #require(try store.listAccounts().first)
        return Imported(
            summary: summary,
            statement: try #require(try store.listStatements(accountId: account.id).first),
            transactions: try store.listTransactions(accountId: account.id)
        )
    }

    /// The Yes card statement whose rows agree with its own printed totals.
    private static let reconcilingLines = [
        "29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr",
        "19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr",
    ]

    private static func yesFullText(printedPurchases: String) -> String {
        let header = [
            "YES BANK KLICK",
            "Statement for YES BANK Card Number 3561XXXXXXXX6686",
            "Statement Period: 17/04/2026 To 16/05/2026",
            "Current Purchases / Cash Advance & Other Charges : Rs. \(printedPurchases) Dr",
            "Payment & Credits Received : Rs. 9,000.00 Cr",
        ]
        return (header + reconcilingLines).joined(separator: "\n")
    }

    @Test("A statement whose figures agree says so, and is not flagged for review")
    func aReconcilingStatementConfirmsItself() async throws {
        let imported = try await Self.importStatement(
            lines: Self.reconcilingLines,
            fullText: Self.yesFullText(printedPurchases: "100.00")
        )

        #expect(imported.summary.integrity == .agrees)
        let notice = try #require(imported.summary.integrity.notice)
        // Icon plus text, and a tone that is a confirmation rather than a warning.
        #expect(notice.isWarning == false)
        #expect(notice.symbolName.isEmpty == false)
        #expect(imported.statement.needsReview == false)
    }

    @Test("A statement whose figures don't add up still imports, and is marked for review")
    func aMismatchedStatementIsImportedAndFlagged() async throws {
        // The same two rows, against a printed purchases total of 4,750.00 — as if a purchase
        // row never reached the reader. Mirrors fixtures/yes/credit_card/mismatched_totals.json.
        let imported = try await Self.importStatement(
            lines: Self.reconcilingLines,
            fullText: Self.yesFullText(printedPurchases: "4,750.00")
        )

        #expect(imported.summary.integrity == .needsReview)
        let notice = try #require(imported.summary.integrity.notice)
        #expect(notice.isWarning)
        // A failed check withholds nothing: every row it did read is still the person's data.
        #expect(imported.summary.transactionsImported == 2)
        #expect(imported.transactions.count == 2)
        #expect(imported.statement.needsReview)
    }

    @Test("A statement with nothing to check against says nothing at all")
    func aStatementWithoutPrintedTotalsSaysNothing() async throws {
        // An ICICI card statement prints no per-statement totals, so there is no verdict to
        // give. Silence is the third state: neither a pass a person could lean on nor a
        // warning they would have to act on.
        let imported = try await Self.importStatement(lines: [
            "ICICI Bank Statement",
            "Statement Date May 28, 2026",
            "4315XXXXXXXX1002",
            "29/04/2026 4262 BBPS Payment received 0 13,628.36 CR",
            "26/05/2026 1814 Fee on gaming transaction 0 10.20",
        ])

        #expect(imported.summary.integrity == .nothingToCheck)
        #expect(imported.summary.integrity.notice == nil)
        #expect(imported.summary.transactionsImported == 2)
        #expect(imported.statement.needsReview == false)
    }

    @Test("Rows the engine could not read are counted, and make the import reviewable")
    func unreadableRowsAreReportedAndFlagged() async throws {
        // One row matches the statement's shape but carries an impossible date. Dropping it
        // silently would present an incomplete import as a complete one.
        let imported = try await Self.importStatement(lines: [
            "ICICI Bank Statement",
            "4315XXXXXXXX1002",
            "99/99/9999 4262 Bad date row 0 100.00",
            "26/05/2026 1814 Fee on gaming transaction 0 10.20",
        ])

        #expect(imported.summary.unreadableRows == 1)
        #expect(imported.summary.transactionsImported == 1)
        // Rows that would not parse are as much a reason to look again as figures that don't
        // add up — even though this statement had no figures to check.
        #expect(imported.summary.integrity == .nothingToCheck)
        #expect(imported.statement.needsReview)
    }
}
