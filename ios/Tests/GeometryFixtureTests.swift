import Foundation
import KanameCore
import PDFKit
import Testing
import UIKit

@testable import Kaname

/// The only tests in this repository that exercise **extraction**.
///
/// Every other fixture hands the readers pre-split `lines`, and therefore tests them while
/// *assuming* the extraction that actually failed: eighteen green fixtures coexisted with
/// real statements importing nothing. A geometry fixture is rendered into a real PDF,
/// opened by the real PDF engine, and run through the real dispatcher and the real reader,
/// so the extractor is under test too.
///
/// Assertions A1–A7 are defined by
/// `specs/017-column-major-pdf/contracts/geometry-fixture.md`. **A4 is the load-bearing
/// one**: a vector that also passes against the pre-slice extraction proves nothing, and is
/// fixed or deleted rather than kept.
///
/// Every document is rendered at test time into a temporary directory and deleted with it
/// (contract R4) — nothing binary enters the repository.
@Suite("Geometry fixtures import every printed row")
struct GeometryFixtureTests {
    private final class TempDirectory {
        let url: URL

        init() {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("kaname-geometry-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }

        func file(_ name: String) -> URL { url.appendingPathComponent(name) }
    }

    /// One parsed row reduced to what a person's money depends on, in the fixture's own
    /// vocabulary so a failure reads as the vector wrote it.
    private struct Row: Equatable, CustomStringConvertible {
        let date: String
        let amount: Decimal
        let direction: String
        let descriptionRaw: String

        var description: String { "\(date) \(amount) \(direction) \(descriptionRaw)" }
    }

    private static func rows(_ statement: ParsedStatement) -> [Row] {
        statement.lines.map {
            Row(
                date: $0.valueDate,
                amount: $0.amount,
                direction: $0.direction == .credit ? "Credit" : "Debit",
                descriptionRaw: $0.descriptionRaw
            )
        }
    }

    private static func rows(_ expected: [GeometryFixture.Transaction]) -> [Row] {
        expected.map {
            Row(
                date: $0.date,
                amount: Self.decimal($0.amount) ?? .nan,
                direction: $0.direction,
                descriptionRaw: $0.descriptionRaw
            )
        }
    }

    /// Money is compared as an exact `Decimal`, never as a `Double` and never as the text
    /// either side happened to print.
    private static func decimal(_ text: String) -> Decimal? {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The document exactly as the platform's text layer emitted it — the model of the
    /// **pre-slice** extraction, and the baseline assertion A4 measures against. It is read
    /// from the pages directly, not from `ExtractedText.fullText`, because after the fix
    /// that full text is the reconstruction and comparing it with itself would prove
    /// nothing.
    private static func legacyPageText(of url: URL) throws -> String {
        let document = try #require(PDFDocument(url: url))
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
        return pages.joined(separator: "\n")
    }

    private static func parse(lines: [String], fullText: String, lineWords: [LineWords]) throws -> ParsedStatement? {
        guard let issuer = detectIssuer(fullText: fullText) else { return nil }
        return try readStatement(issuer: issuer, lines: lines, fullText: fullText, lineWords: lineWords)
    }

    private static func nonWhitespaceCounts(_ text: String) -> [Character: Int] {
        text.filter { !$0.isWhitespace }.reduce(into: [:]) { counts, character in
            counts[character, default: 0] += 1
        }
    }

    @Test("Every vector in fixtures/geometry is bundled and readable")
    func fixturesAreBundled() throws {
        #expect(!GeometryFixtureLoader.names.isEmpty, "fixtures/geometry is not reaching the test bundle")
        for name in GeometryFixtureLoader.names {
            let fixture = try GeometryFixtureLoader.load(name)
            #expect(!fixture.rows.isEmpty, "\(name) prints no rows")
            #expect(fixture.issuerId == fixture.expected.issuerId, "\(name) disagrees with itself about its issuer")
            for transaction in fixture.expected.transactions {
                // A malformed expected amount would otherwise surface as a mysterious A2
                // mismatch rather than as the fixture error it is.
                #expect(Self.decimal(transaction.amount) != nil, "\(name): \(transaction.amount) is not a decimal")
            }
        }
    }

    /// The registry's ten readers, spelled as `registry.rs` spells them.
    ///
    /// Hand-kept on purpose: a reader added to the engine without a geometry vector is a
    /// reader nothing proves the extraction works for, and the only way that can fail loudly
    /// here is if this list is what the suite compares against. `core/crates/kaname-core/tests/dispatcher.rs`
    /// pins the same ids on the engine side, so the two cannot drift apart quietly.
    private static let readers = [
        "AU_BANK", "FEDERAL_BANK", "HDFC_BANK", "ICICI_BANK",
        "FEDERAL_SCAPIA_CARD", "HDFC_SWIGGY_CARD", "ICICI_AMAZONPAY_CARD",
        "IOB_RUPAY_CARD", "SBI_CASHBACK_CARD", "YES_KIWI_CARD",
    ]

    @Test("Every reader, both statement kinds and both date shapes are covered")
    func coversEveryReader() throws {
        let vectors = try GeometryFixtureLoader.names.map { try GeometryFixtureLoader.load($0) }

        let covered = Set(vectors.map(\.issuerId))
        for reader in Self.readers {
            #expect(covered.contains(reader), "no geometry vector for \(reader)")
        }
        #expect(Set(vectors.map(\.kind)) == ["credit_card", "bank_account"])

        let shapes = Set(vectors.map(\.signature.dateFormat))
        #expect(shapes.contains("DD/MM/YYYY"))
        #expect(shapes.contains("DD-MMM-YYYY"))

        for vector in vectors {
            // A6 — a vector printing only spends cannot show a direction was inverted.
            let directions = Set(vector.expected.transactions.map(\.direction))
            #expect(directions == ["Debit", "Credit"], "\(vector.issuerId) declares only \(directions)")
            // A4's premise, stated once for the whole family: a vector the pre-slice
            // extraction could already read proves nothing and is fixed or deleted.
            #expect(
                vector.expected.legacyMaxTransactions < vector.expected.transactions.count,
                "\(vector.issuerId) claims the old path could read as much as the new one"
            )
        }
    }

    @Test("A1–A7 hold for every geometry vector", arguments: GeometryFixtureLoader.names)
    func vectorImportsEveryPrintedRow(name: String) throws {
        let fixture = try GeometryFixtureLoader.load(name)
        let temp = TempDirectory()
        let url = temp.file("statement.pdf")
        try GeometryFixtureRenderer.render(fixture, to: url)

        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)

        // A1 — the document is recognised from what it prints about itself.
        let issuer = try #require(detectIssuer(fullText: extracted.fullText), "\(name): no issuer recognised")
        #expect(issuer.id == fixture.expected.issuerId, "\(name): recognised as \(issuer.id)")

        let statement = try readStatement(
            issuer: issuer,
            lines: extracted.lines,
            fullText: extracted.fullText,
            lineWords: extracted.lineWords
        )

        // A2 — every printed row, exactly as printed.
        #expect(Self.rows(statement) == Self.rows(fixture.expected.transactions), "\(name)")

        // A3 — and never more rows than the page prints.
        #expect(statement.lines.count <= fixture.rows.count, "\(name): invented rows")

        assertMoneyKeptItsMeaning(fixture, name: name, extracted: extracted, statement: statement)
        assertNothingElseWasAbsorbed(fixture, name: name, extracted: extracted)
        try assertNonVacuous(fixture, name: name, at: url)
        try assertDeterministic(fixture, name: name, at: url, first: extracted, statement: statement)
        assertDirections(fixture, name: name, statement: statement)
        try assertLossless(name: name, at: url, extracted: extracted)
    }

    /// US3 — the money still means what the page said it meant.
    ///
    /// A2 already pins the transactions, but it cannot see *why* they came out right. These
    /// assertions read the reconstructed line itself: that a `Dr`/`Cr` marker still sits
    /// where it was printed relative to its amount, that a ledger's figures landed in the
    /// columns they were printed in, and that a row printing only one of withdrawal/deposit
    /// did not shift the rest along by a slot.
    private func assertMoneyKeptItsMeaning(
        _ fixture: GeometryFixture,
        name: String,
        extracted: ExtractedText,
        statement: ParsedStatement
    ) {
        for row in fixture.rows {
            // Every cell of the printed row, in the order it was printed, joined by one
            // space and nothing of another row wedged between two of them.
            let printed = fixture.signature.columns.compactMap { row[$0.role] }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            #expect(extracted.lines.contains(printed), "\(name): [\(printed)] is not a line")
        }

        if let closing = fixture.expected.closingBalance {
            #expect(statement.printedClosingBalance == Self.decimal(closing), "\(name): closing balance")
        }
        if let source = fixture.expected.directionSource {
            let row1 = statement.lines.first?.ledger?.directionSource
            #expect(row1.map(Self.name) == source, "\(name): row-1 direction source")
        }
    }

    /// The direction source as a vector spells it, so a fixture can say `Row1XPosition`
    /// and mean it.
    private static func name(_ source: DirectionSource) -> String {
        switch source {
        case .openingBalance: "OpeningBalance"
        case .balanceDelta: "BalanceDelta"
        case .row1XPosition: "Row1XPosition"
        case .row1Provisional: "Row1Provisional"
        }
    }

    /// A page carries more than its table, and none of it may be swallowed by a row or
    /// mistaken for one.
    ///
    /// An address block printed beside the rows at exactly their heights, a narration that
    /// wrapped onto its own visual row, a page footer printed hard under the last row: each
    /// was printed as its own line and must arrive as its own line. A2 catches the case
    /// where one of them is absorbed *and* corrupts a transaction; this catches the case
    /// where it is absorbed quietly.
    private func assertNothingElseWasAbsorbed(
        _ fixture: GeometryFixture,
        name: String,
        extracted: ExtractedText
    ) {
        for line in fixture.extraLines ?? [] {
            #expect(extracted.lines.contains(line.text), "\(name): [\(line.text)] did not survive as its own line")
        }
    }

    /// A4 — **non-vacuity**. The same document read the way the extractor read it *before*
    /// this slice must recover strictly fewer transactions. Without this, a fixture drawn
    /// row-major would pass on both sides of the fix and stand as evidence of nothing.
    private func assertNonVacuous(_ fixture: GeometryFixture, name: String, at url: URL) throws {
        let expected = fixture.expected.transactions.count
        #expect(
            fixture.expected.legacyMaxTransactions < expected,
            "\(name): legacy_max_transactions must be strictly less than the expected count"
        )

        let legacyFullText = try Self.legacyPageText(of: url)
        let legacy = try Self.parse(
            lines: PDFKitStatementTextExtractor.split(legacyFullText),
            fullText: legacyFullText,
            lineWords: []
        )
        #expect(
            (legacy?.lines.count ?? 0) <= fixture.expected.legacyMaxTransactions,
            "\(name): the pre-slice path already read this vector — it proves nothing"
        )
    }

    /// A5 — the same file always yields the same lines and the same money.
    private func assertDeterministic(
        _ fixture: GeometryFixture,
        name: String,
        at url: URL,
        first: ExtractedText,
        statement: ParsedStatement
    ) throws {
        let second = try PDFKitStatementTextExtractor().extract(from: url, password: nil)
        #expect(second.lines == first.lines, "\(name): extraction is not deterministic")
        #expect(second.lineWords == first.lineWords, "\(name): word geometry is not deterministic")

        let reparsed = try Self.parse(lines: second.lines, fullText: second.fullText, lineWords: second.lineWords)
        #expect(Self.rows(try #require(reparsed)) == Self.rows(statement), "\(name): re-import differs")
    }

    /// A6 — a vector that prints only spends cannot show a direction was inverted, so every
    /// vector declares both, and every parsed direction must match the printed one.
    private func assertDirections(_ fixture: GeometryFixture, name: String, statement: ParsedStatement) {
        let declared = fixture.expected.transactions.map(\.direction)
        #expect(declared.contains("Debit"), "\(name): declares no debit")
        #expect(declared.contains("Credit"), "\(name): declares no credit")
        #expect(Self.rows(statement).map(\.direction) == declared, "\(name): a direction was inverted")
    }

    /// A7 — reshaping moves characters between lines; it may never lose one.
    private func assertLossless(name: String, at url: URL, extracted: ExtractedText) throws {
        let printed = Self.nonWhitespaceCounts(try Self.legacyPageText(of: url))
        let reconstructed = Self.nonWhitespaceCounts(extracted.lines.joined())
        #expect(reconstructed == printed, "\(name): reshaping lost or duplicated characters")
    }
}
