import Foundation
import PDFKit
import Testing
import UIKit

@testable import Kaname

/// The invariants a reconstructed page must hold, whatever it was printed like.
///
/// These are stated as layouts rather than as line-spacing parameters: a stair of
/// barely-overlapping runs, two panels either side of a gutter, a page with no text between
/// two that have it. Every document is drawn in the test and thrown away with the temp
/// directory, so nothing binary enters the repository.
@Suite("Printed-row reconstruction invariants")
struct PrintedRowsTests {
    private final class TempDirectory {
        let url: URL

        init() {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("kaname-rows-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }

        func file(_ name: String) -> URL { url.appendingPathComponent(name) }
    }

    private static let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

    private static let statementLines = [
        "EXAMPLE BANK CREDIT CARD STATEMENT",
        "Statement Date May 28, 2026",
        "4315XXXXXXXX1002",
        "29/04/2026 4262 Payment received 13,628.36 CR",
        "26/05/2026 1814 Fee on a transaction 10.20",
    ]

    /// A run of text drawn at an exact spot on a page, so a test can state a layout instead
    /// of hoping one comes out of a line-spacing parameter.
    struct Placed {
        let text: String
        let left: CGFloat
        let top: CGFloat
    }

    /// Draw pages of exactly-placed runs. Used by the geometry invariants, which need
    /// layouts — tight leading, side-by-side panels, a page with no text at all — that a
    /// line-by-line writer cannot express.
    private static func writePlacedPDF(pages: [[Placed]], to url: URL) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        try renderer.writePDF(to: url) { context in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular)
            ]
            for page in pages {
                context.beginPage()
                for run in page {
                    (run.text as NSString).draw(
                        at: CGPoint(x: run.left, y: run.top),
                        withAttributes: attributes
                    )
                }
            }
        }
    }

    /// Every non-whitespace character of a page's own text, counted.
    private static func inkCounts(_ text: String) -> [Character: Int] {
        text.filter { !$0.isWhitespace }.reduce(into: [:]) { counts, character in
            counts[character, default: 0] += 1
        }
    }

    private static func pageText(of url: URL) throws -> String {
        let document = try #require(PDFDocument(url: url))
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    @Test("Reshaping moves characters between lines but never loses one")
    func losesNoCharacterOfThePage() throws {
        let temp = TempDirectory()
        let url = temp.file("statement.pdf")
        try StatementTextExtractorTests.writeTextPDF(lines: Self.statementLines, lineSpacing: 8, to: url)

        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)

        #expect(Self.inkCounts(extracted.lines.joined()) == Self.inkCounts(try Self.pageText(of: url)))
    }

    @Test("The same file always extracts to the same lines and the same positions")
    func extractsTheSameFileIdentically() throws {
        let temp = TempDirectory()
        let url = temp.file("statement.pdf")
        try StatementTextExtractorTests.writeTextPDF(lines: Self.statementLines, to: url)

        let first = try PDFKitStatementTextExtractor().extract(from: url, password: nil)
        let second = try PDFKitStatementTextExtractor().extract(from: url, password: nil)

        #expect(first.lines == second.lines)
        #expect(first.lineWords == second.lineWords)
    }

    @Test("A chain of barely-overlapping words cannot grow into one enormous row")
    func capsHowFarARowCanGrow() throws {
        let temp = TempDirectory()
        let url = temp.file("stair.pdf")
        // Each run overlaps the one before it by more than a quarter of its height, so an
        // uncapped band would swallow the lot — twenty-two points of page, three rows deep.
        let stair = ["AAA", "BBB", "CCC", "DDD", "EEE"].enumerated().map {
            Placed(text: $1, left: 36, top: 80 + CGFloat($0) * 4)
        }
        try Self.writePlacedPDF(pages: [stair], to: url)

        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)

        #expect(!extracted.lines.contains { $0.contains("AAA") && $0.contains("EEE") })
    }

    @Test("A page that yields nothing leaves its siblings' rows and positions untouched")
    func readsEachPageIndependently() throws {
        let temp = TempDirectory()
        let url = temp.file("mixed.pdf")
        let first = [Placed(text: "29/04/2026 4262 Payment received 13,628.36 CR", left: 36, top: 80)]
        let third = [Placed(text: "26/05/2026 1814 Fee on a transaction 10.20", left: 36, top: 80)]
        try Self.writePlacedPDF(pages: [first, [], third], to: url)

        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)

        // The blank page contributes no line, so it cannot shift the indices its siblings'
        // word positions are reported against.
        #expect(extracted.lines == [first[0].text, third[0].text])
        #expect(extracted.lineWords.map(\.lineIndex) == [0, 1])
    }

    @Test("Reported word positions belong to the line they are reported against")
    func reportsEachLinesOwnWords() throws {
        let temp = TempDirectory()
        let url = temp.file("statement.pdf")
        try StatementTextExtractorTests.writeTextPDF(lines: Self.statementLines, to: url)

        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)

        #expect(!extracted.lineWords.isEmpty)
        for entry in extracted.lineWords {
            let line = try #require(extracted.lines[safe: Int(entry.lineIndex)])
            #expect(entry.words.map(\.text) == line.split(separator: " ").map(String.init))
            #expect(entry.words.map(\.x0) == entry.words.map(\.x0).sorted())
            #expect(entry.words.allSatisfy { $0.x0 < $0.x1 })
        }
    }

    @Test("Word positions are reported for later pages too, not page one alone")
    func reportsWordsOnEveryPage() throws {
        let temp = TempDirectory()
        let url = temp.file("long.pdf")
        let first = [Placed(text: "PAGE ONE ROW", left: 36, top: 80)]
        let second = [Placed(text: "PAGE TWO ROW", left: 36, top: 80)]
        try Self.writePlacedPDF(pages: [first, second], to: url)

        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)

        let secondPage = try #require(extracted.lines.firstIndex(of: "PAGE TWO ROW"))
        #expect(extracted.lineWords.contains { $0.lineIndex == UInt32(secondPage) })
    }

    @Test("A block printed level with a row joins that row, and is never invented as a row of its own")
    func joinsALevelBlockRatherThanInventingARow() throws {
        let temp = TempDirectory()
        let url = temp.file("level.pdf")
        // An address block level with the rows is, to a page, a column of those rows: there
        // is no geometry that tells the two apart, and the rule that keeps a ledger's
        // continuation page whole — a gap crossed by rows is a column gap — necessarily
        // keeps this one whole too. What must hold is the thing money depends on: the page
        // still yields exactly the rows it printed, never one more. The readers' anchored
        // row patterns then decline the polluted line, so a figure is lost rather than
        // invented.
        let page = [
            Placed(text: "29/04/2026 4262 Payment received 13,628.36 CR", left: 36, top: 80),
            Placed(text: "26/05/2026 1814 Fee on a transaction 10.20", left: 36, top: 100),
            Placed(text: "EXAMPLE TOWER PLOT 42", left: 420, top: 80),
            Placed(text: "SAMPLE CITY 560001", left: 420, top: 100),
        ]
        try Self.writePlacedPDF(pages: [page], to: url)

        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)

        // Two printed heights, two lines — the block was joined, not turned into rows.
        #expect(extracted.lines.count == 2)
        #expect(extracted.lines.allSatisfy { $0.contains("EXAMPLE TOWER") || $0.contains("SAMPLE CITY") })
    }

    @Test("Two columns all but touching stay two values")
    func keepsAdjacentColumnValuesSeparable() throws {
        let temp = TempDirectory()
        let url = temp.file("columns.pdf")
        // Five points between one column's last glyph and the next column's first — a real
        // statement's tightest gap, and the case where a reshaping that joined with nothing
        // would leave "1,234.567,890.12": one token no reader can ever split again.
        let row = [
            Placed(text: "01/04/2026", left: 36, top: 80),
            Placed(text: "1,234.56", left: 100, top: 80),
            Placed(text: "7,890.12", left: 148, top: 80),
        ]
        try Self.writePlacedPDF(pages: [row], to: url)

        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)

        #expect(extracted.lines == ["01/04/2026 1,234.56 7,890.12"])
    }

    @Test("An amount keeps its shape, whatever shape the statement printed it in")
    func keepsAmountsWhole() throws {
        let temp = TempDirectory()
        let url = temp.file("amounts.pdf")
        // A currency symbol, an Indian parenthesised credit, and a trailing minus. Each is
        // one printed value and must arrive as one token — split in two, a parenthesised
        // credit becomes a debit.
        let row = [
            Placed(text: "01/04/2026", left: 36, top: 80),
            Placed(text: "\u{20B9}1,234.56", left: 110, top: 80),
            Placed(text: "(1,200.00)", left: 200, top: 80),
            Placed(text: "500.00-", left: 300, top: 80),
        ]
        try Self.writePlacedPDF(pages: [row], to: url)

        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)

        #expect(extracted.lines == ["01/04/2026 \u{20B9}1,234.56 (1,200.00) 500.00-"])
    }

    @Test("Two panels either side of a gutter stay two panels")
    func keepsSideBySidePanelsApart() throws {
        let temp = TempDirectory()
        let url = temp.file("panels.pdf")
        let panels = [
            Placed(text: "LEFT ONE", left: 36, top: 80),
            Placed(text: "LEFT TWO", left: 36, top: 100),
            Placed(text: "LEFT THREE", left: 36, top: 120),
            Placed(text: "RIGHT ONE", left: 350, top: 85),
            Placed(text: "RIGHT TWO", left: 350, top: 105),
        ]
        try Self.writePlacedPDF(pages: [panels], to: url)

        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)

        #expect(!extracted.lines.contains { $0.contains("LEFT") && $0.contains("RIGHT") })
        let lastLeft = try #require(extracted.lines.lastIndex { $0.contains("LEFT") })
        let firstRight = try #require(extracted.lines.firstIndex { $0.contains("RIGHT") })
        #expect(lastLeft < firstRight)
    }

    /// A statement long enough to be worth waiting for, so the promises about waiting can be
    /// stated about a real one.
    private static func longDocument(pages count: Int, in temp: TempDirectory) throws -> URL {
        let url = temp.file("long.pdf")
        let page = (0..<28).map { row in
            Placed(
                text: "0\(row % 9 + 1)/04/2026 4262 EXAMPLE MERCHANT \(row) 1,234.56 CR",
                left: 36,
                top: 60 + CGFloat(row) * 22
            )
        }
        try writePlacedPDF(pages: Array(repeating: page, count: count), to: url)
        return url
    }

    @Test("A long statement already asked to stop never finishes extracting")
    func stopsExtractingWhenAsked() async throws {
        let temp = TempDirectory()
        let url = try Self.longDocument(pages: 42, in: temp)

        let task = Task {
            try PDFKitStatementTextExtractor().extract(from: url, password: nil)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("A forty-two page statement extracts in well under the time a person would wait")
    func extractsALongStatementPromptly() throws {
        let temp = TempDirectory()
        let url = try Self.longDocument(pages: 42, in: temp)

        let started = ContinuousClock.now
        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)
        let took = ContinuousClock.now - started

        #expect(extracted.lines.count == 42 * 28)
        #expect(took < .seconds(10), "extraction took \(took)")
    }

    @Test("A page's glyphs are measured once each, however many words they make up")
    func measuresEachGlyphOnce() throws {
        let temp = TempDirectory()
        let url = temp.file("counted.pdf")
        try Self.writePlacedPDF(
            pages: [[Placed(text: "29/04/2026 4262 Payment received 13,628.36 CR", left: 36, top: 80)]],
            to: url
        )

        let document = try #require(PDFDocument(url: url))
        let delegate = CountingDelegate()
        document.delegate = delegate
        let page = try #require(document.page(at: 0) as? CountingPage)
        CountingPage.calls = 0

        _ = PrintedRows.of(page)

        // Asking PDFKit for a glyph's box is the dominant cost of reading a statement, so
        // every glyph is asked about once and the answer reused. A per-word re-query would
        // multiply the work on a forty-two page document by the length of its words.
        #expect(CountingPage.calls <= page.numberOfCharacters)
        #expect(CountingPage.calls > 0)
    }
}

/// Counts what PDFKit is asked, so the cost of reading a page can be asserted rather than
/// assumed.
final class CountingPage: PDFPage {
    nonisolated(unsafe) static var calls = 0

    override func characterBounds(at index: Int) -> CGRect {
        Self.calls += 1
        return super.characterBounds(at: index)
    }
}

final class CountingDelegate: NSObject, PDFDocumentDelegate {
    func classForPage() -> AnyClass { CountingPage.self }
}

extension Array {
    /// Indexing that answers `nil` instead of trapping, so a wrong index fails as an
    /// expectation rather than as a crashed test run.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
