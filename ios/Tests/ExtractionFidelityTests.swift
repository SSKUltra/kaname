import Foundation
import KanameCore
import PDFKit
import Testing
import UIKit

@testable import Kaname

/// Does what iOS extracts agree with what the readers were built against?
///
/// The ten readers are fixture-locked to the web engine's extraction (pdfplumber); iOS
/// extracts with PDFKit. Nothing but this suite proves the two produce the same line shapes,
/// and the cost of them disagreeing is not an error — it is a person being told, calmly and
/// wrongly, that their statement had no spending.
///
/// Every document is rendered in the test from synthetic lines and thrown away.
///
/// ⚠️ **Frozen for 017 (FR-028, SC-005).** `cardLines`, `ledgerLines` and every expectation
/// already in this file record how the shipped readers behave on a document the text layer
/// gets *right*. 017 reshapes rows that the text layer gets wrong, and the only way that
/// change can be shown not to have broken the working case is if this file's expectations
/// are not adjusted to fit it. New tests may be **added**; nothing already here may be
/// edited, relaxed or deleted.
@Suite("PDFKit extraction agrees with what the readers expect")
struct ExtractionFidelityTests {
    /// A representative card statement: a credit and a debit.
    private static let cardLines = [
        "ICICI Bank Statement",
        "Statement Date May 28, 2026",
        "4315XXXXXXXX1002",
        "29/04/2026 4262 BBPS Payment received 0 13,628.36 CR",
        "26/05/2026 1814 Fee on gaming transaction 0 10.20",
    ]

    /// A representative bank ledger: a withdrawal and a deposit, opening-balance anchored.
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

    private final class TempDirectory {
        let url: URL

        init() {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("kaname-fidelity-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }

        func file(_ name: String) -> URL { url.appendingPathComponent(name) }
    }

    /// One parsed row reduced to what a person's money actually depends on.
    private struct Row: Equatable, CustomStringConvertible {
        let date: String
        let amount: Decimal
        let direction: Direction

        var description: String { "\(date) \(amount) \(direction)" }
    }

    private static func rows(_ statement: ParsedStatement) -> [Row] {
        statement.lines.map { Row(date: $0.valueDate, amount: $0.amount, direction: $0.direction) }
    }

    /// Parse the lines directly — the contract the golden fixtures pin.
    private static func parseDirectly(_ lines: [String]) throws -> ParsedStatement {
        let fullText = lines.joined(separator: "\n")
        let issuer = try #require(detectIssuer(fullText: fullText))
        return try readStatement(issuer: issuer, lines: lines, fullText: fullText, lineWords: [])
    }

    /// Render those same lines to a PDF, read it back with PDFKit, and parse *that* — the
    /// path a real statement takes.
    private static func parseViaPDF(_ lines: [String]) throws -> (
        extracted: ExtractedText, statement: ParsedStatement?
    ) {
        let temp = TempDirectory()
        let url = temp.file("statement.pdf")
        try StatementTextExtractorTests.writeTextPDF(lines: lines, to: url)

        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)
        guard let issuer = detectIssuer(fullText: extracted.fullText) else {
            return (extracted, nil)
        }
        let statement = try readStatement(
            issuer: issuer,
            lines: extracted.lines,
            fullText: extracted.fullText,
            lineWords: extracted.lineWords
        )
        return (extracted, statement)
    }

    @Test("A card statement read through PDFKit yields the same transactions as its lines")
    func cardStatementSurvivesTheRoundTrip() throws {
        let direct = try Self.parseDirectly(Self.cardLines)
        let viaPDF = try Self.parseViaPDF(Self.cardLines)

        #expect(
            detectIssuer(fullText: viaPDF.extracted.fullText)?.id
                == detectIssuer(fullText: Self.cardLines.joined(separator: "\n"))?.id
        )

        let statement = try #require(viaPDF.statement)
        // Exact decimals, exact dates, exact directions — not a count, and not a tolerance.
        #expect(Self.rows(statement) == Self.rows(direct))
        #expect(statement.cardLast4 == direct.cardLast4)
        #expect(statement.erroredLines.isEmpty)
    }

    @Test("A bank ledger read through PDFKit yields the same transactions as its lines")
    func bankLedgerSurvivesTheRoundTrip() throws {
        let direct = try Self.parseDirectly(Self.ledgerLines)
        let viaPDF = try Self.parseViaPDF(Self.ledgerLines)

        let statement = try #require(viaPDF.statement)
        // Direction on a ledger comes from the balance chain, so a shifted line would show up
        // here as a debit that became a credit — the worst possible silent corruption.
        #expect(Self.rows(statement) == Self.rows(direct))
        #expect(statement.printedClosingBalance == direct.printedClosingBalance)
        #expect(statement.erroredLines.isEmpty)
    }

    @Test("Tightly-spaced rows PDFKit merges are recovered from the page geometry")
    func tightlySpacedRowsAreRecoveredRatherThanMerged() throws {
        let temp = TempDirectory()
        let url = temp.file("tight.pdf")
        // 8pt of leading for a 9pt font: the layout that made PDFKit join adjacent rows.
        try StatementTextExtractorTests.writeTextPDF(lines: Self.cardLines, lineSpacing: 8, to: url)

        // The premise: PDFKit's own line breaks lose two of the five rows, and the reader
        // handed that text matched one row's date to the other's amount — a single,
        // confidently wrong transaction. That is what the geometry pass exists to prevent.
        let document = try #require(PDFDocument(url: url))
        let page = try #require(document.page(at: 0))
        let pdfKitLines = PDFKitStatementTextExtractor.split(try #require(page.string))
        #expect(pdfKitLines.count < Self.cardLines.count)

        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)
        #expect(extracted.lines == Self.cardLines)

        let direct = try Self.parseDirectly(Self.cardLines)
        let issuer = try #require(detectIssuer(fullText: extracted.fullText))
        let statement = try readStatement(
            issuer: issuer,
            lines: extracted.lines,
            fullText: extracted.fullText,
            lineWords: extracted.lineWords
        )
        #expect(Self.rows(statement) == Self.rows(direct))
    }

    /// A geometry vector's rows, written the way the printed page reads them: every cell of
    /// the row, left to right, single-spaced.
    private static func printedLines(of fixture: GeometryFixture) -> [String] {
        fixture.rows.map { row in
            fixture.signature.columns.compactMap { row[$0.role] }.joined(separator: " ")
        }
    }

    private static func render(_ name: String, in directory: TempDirectory) throws -> GeometryFixture {
        let fixture = try GeometryFixtureLoader.load(name)
        try GeometryFixtureRenderer.render(fixture, to: directory.file("statement.pdf"))
        return fixture
    }

    @Test("A document that merges rows and splits columns at once resolves both in one pass")
    func resolvesBothHazardsInOnePass() throws {
        // Eight points of leading under a nine-point font, so the text layer joins adjacent
        // rows — and drawn column-major, so it splits every row across four lines. Neither
        // capability may re-open the other's bug.
        let temp = TempDirectory()
        let fixture = try Self.render("both_hazards.json", in: temp)
        let printed = Self.printedLines(of: fixture)

        let extracted = try PDFKitStatementTextExtractor().extract(from: temp.file("statement.pdf"), password: nil)
        let issuer = try #require(detectIssuer(fullText: extracted.fullText))
        let statement = try readStatement(
            issuer: issuer,
            lines: extracted.lines,
            fullText: extracted.fullText,
            lineWords: extracted.lineWords
        )

        // Every printed row came back as one line, and the parse agrees with parsing those
        // lines directly — the same equality the round-trip tests above pin.
        #expect(printed.allSatisfy { extracted.lines.contains($0) })
        let asPrinted = fixture.headerLines + printed + fixture.footerLines
        #expect(Self.rows(statement) == Self.rows(try Self.parseDirectly(asPrinted)))
    }

    @Test("A document the text layer already got right is handed back unchanged")
    func leavesACorrectlyExtractedDocumentAlone() throws {
        // Generous leading, one column, nothing to fix. Reshaping must be a no-op here: a
        // document that already read correctly is the one thing a change like this could
        // most easily break, and the proof is byte equality with the source lines.
        let temp = TempDirectory()
        let url = temp.file("plain.pdf")
        try StatementTextExtractorTests.writeTextPDF(lines: Self.cardLines, to: url)

        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)

        #expect(extracted.lines == Self.cardLines)
    }
}
