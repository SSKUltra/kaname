import Foundation
import KanameCore
import PDFKit

/// The text a statement document yields — the engine's only view of it. The core never
/// opens a PDF; extraction is a platform concern.
struct ExtractedText: Equatable, Sendable {
    /// `fullText` split on newlines, unreshaped: the shipped readers are fixture-locked to
    /// exactly this contract.
    let lines: [String]
    let fullText: String
    /// Word geometry for the lines it could be established for. Sparse by design — a line
    /// with no entry degrades the ledger row-1 bootstrap to "needs review", which is honest,
    /// rather than to a confidently wrong direction.
    let lineWords: [LineWords]
}

/// Why a document yielded no usable text.
enum ExtractionFailure: Error, Equatable, Sendable {
    case notAPDF
    case passwordRequired
    case wrongPassword
    case noExtractableText
    case unreadable
}

/// Turns a picked document into the engine's view of it.
///
/// A protocol so the pipeline is testable without a real file on disk, and so the PDF engine
/// import appears in exactly one type.
protocol StatementTextExtractor: Sendable {
    /// The password is a parameter and never a stored property: it is used to unlock the
    /// document and then dropped.
    func extract(from url: URL, password: String?) throws -> ExtractedText
}

/// The real extractor. PDFKit is the platform's own PDF engine — first-party, offline, and
/// the reason the Rust core never has to open a document.
struct PDFKitStatementTextExtractor: StatementTextExtractor {
    func extract(from url: URL, password: String?) throws -> ExtractedText {
        // A file picked from Files lives outside the app container, so reading it needs a
        // temporary grant. The `defer` releases it on every exit — success, throw or
        // cancellation — and a refused grant is a read failure, not a crash.
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // The boolean itself is not the signal: a file already inside the app's container is
        // perfectly readable and still answers `false`. What matters is whether the bytes can
        // actually be read — a refused grant, a deleted file and a revoked one all land here,
        // and none of them should be reported as "that file isn't a PDF".
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ExtractionFailure.unreadable
        }

        guard let document = PDFDocument(url: url) else { throw ExtractionFailure.notAPDF }

        // `isLocked`, not `isEncrypted`: a document with an empty or owner-only password is
        // already readable, and prompting for one we don't need would be theatre.
        if document.isLocked {
            guard let password, document.unlock(withPassword: password) else {
                throw password == nil
                    ? ExtractionFailure.passwordRequired
                    : ExtractionFailure.wrongPassword
            }
        }

        let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }

        var lines: [String] = []
        var lineWords: [LineWords] = []
        for (pageIndex, page) in pages.enumerated() {
            let ranges = Self.lineRanges(on: page)
            // Page 1 only: it is the only page whose geometry the ledger row-1 bootstrap can
            // need, and it bounds the cost on a 200-page statement. Its line indices are the
            // first ones in `lines`, so they need no offset.
            if pageIndex == 0 {
                lineWords = Self.lineWords(on: page, ranges: ranges)
            }
            lines.append(contentsOf: ranges.map(\.text))
        }

        let fullText = lines.joined(separator: "\n")
        guard fullText.contains(where: { !$0.isWhitespace }) else {
            throw ExtractionFailure.noExtractableText
        }

        return ExtractedText(lines: lines, fullText: fullText, lineWords: lineWords)
    }

    /// One line of a page: its text, and the UTF-16 range it occupies in the page's string.
    struct LineRange {
        let text: String
        let range: Range<Int>
    }

    /// The readers are fixture-locked to plain newline splitting — no trimming, no dropping
    /// of blank lines, no reshaping of any kind. Used when a page's geometry cannot be
    /// trusted, and by callers that only have text.
    ///
    /// ⚠️ **Frozen, and permanent.** This is the model of the pre-017 extraction — the text
    /// layer's own newlines, exactly as they arrived. `ios/Tests/GeometryFixtureTests.swift`
    /// parses through it to assert **A4, non-vacuity**: every geometry fixture must yield
    /// strictly fewer transactions through this path than through the reshaping one, which
    /// is what stops a fixture that would have passed *before* the fix from being mistaken
    /// for proof of it. Keep it `static` and test-visible; do not delete or alter it when
    /// the extractor around it is rewritten.
    static func split(_ fullText: String) -> [String] {
        fullText.components(separatedBy: "\n")
    }

    /// Where the lines of a page actually are.
    ///
    /// PDFKit reports the line breaks *it* inferred, and on a tightly-laid-out statement it
    /// joins adjacent rows into one string. That is not a cosmetic problem: a reader handed
    /// `"29/04 … 13,628.36 CR 26/05 … 10.20"` matched one row's date to the other's amount
    /// and imported a single, confidently wrong transaction. So the breaks are re-derived
    /// from where the glyphs sit on the page — the same thing the web engine's extractor
    /// does — and PDFKit's own newlines are kept as hard breaks on top.
    ///
    /// A page whose character indices and bounds cannot be trusted falls back to PDFKit's
    /// newlines unchanged: fewer breaks is a parse that reads nothing, which is honest,
    /// where a wrong break is a number in the wrong row.
    ///
    /// Two properties make this safe on real documents. Words are atomic: PDFKit hands back
    /// a stray, far-off rect for the last glyph or two of a drawn run, and no word is ever
    /// split across rows, so a word joins a row if *any* of its glyphs sits in it. And a
    /// row's band only ever grows by glyphs that were already in it, so one stray rect
    /// cannot stretch the band far enough to swallow the row below.
    static func lineRanges(on page: PDFPage) -> [LineRange] {
        guard let text = page.string else { return [] }
        let units = Array(text.utf16)
        guard page.numberOfCharacters == units.count else {
            return Self.fallbackRanges(text)
        }
        guard let extents = Self.glyphExtents(on: page, units: units) else {
            return Self.fallbackRanges(text)
        }

        var ranges: [LineRange] = []
        var start = 0
        var band: ClosedRange<CGFloat>?
        var index = 0

        while index < units.count {
            if units[index] == newline {
                ranges.append(Self.lineRange(units, start..<index))
                start = index + 1
                band = nil
                index += 1
                continue
            }
            guard !isSeparator(units[index]) else {
                index += 1
                continue
            }

            let wordEnd = Self.endOfWord(units, from: index)
            let word = (index..<wordEnd).compactMap { extents[$0] }
            let onThisRow = band.map { current in word.filter { Self.sharesARow($0, current) } }

            if let onThisRow, onThisRow.isEmpty, !word.isEmpty {
                // A row PDFKit merged into the one before it.
                ranges.append(Self.lineRange(units, start..<index))
                start = index
                band = Self.union(word)
            } else if let onThisRow, let current = band {
                band = Self.union(onThisRow + [current])
            } else {
                band = Self.union(word)
            }

            index = wordEnd
        }
        ranges.append(Self.lineRange(units, start..<units.count))

        return ranges
    }

    /// The vertical extent of every glyph on a page, or `nil` if the page yielded no usable
    /// geometry at all.
    ///
    /// Glyph *ink* bounds: a comma, a capital and an x-height letter on one row have wildly
    /// different midpoints, which is why rows are grouped by whether extents overlap rather
    /// than by how far apart their centres are.
    private static func glyphExtents(on page: PDFPage, units: [UInt16]) -> [ClosedRange<CGFloat>?]? {
        var extents = [ClosedRange<CGFloat>?](repeating: nil, count: units.count)
        var sawGeometry = false
        for index in units.indices where !isSeparator(units[index]) {
            let bounds = page.characterBounds(at: index)
            guard !bounds.isNull, bounds.minY.isFinite, bounds.maxY.isFinite, bounds.height > 0.5
            else { continue }
            extents[index] = bounds.minY...bounds.maxY
            sawGeometry = true
        }
        return sawGeometry ? extents : nil
    }

    private static func endOfWord(_ units: [UInt16], from start: Int) -> Int {
        var end = start
        while end < units.count, !isSeparator(units[end]) {
            end += 1
        }
        return end
    }

    private static func union(_ extents: [ClosedRange<CGFloat>]) -> ClosedRange<CGFloat>? {
        guard let first = extents.first else { return nil }
        return extents.dropFirst().reduce(first) {
            min($0.lowerBound, $1.lowerBound)...max($0.upperBound, $1.upperBound)
        }
    }

    /// Does a glyph sit on the row a band describes? It must overlap by a real fraction of
    /// the shorter of the two — a full stop inside a row's band does, and the row below,
    /// which at worst grazes it by a fraction of a point, does not.
    private static func sharesARow(_ extent: ClosedRange<CGFloat>, _ band: ClosedRange<CGFloat>) -> Bool {
        let overlap = min(extent.upperBound, band.upperBound) - max(extent.lowerBound, band.lowerBound)
        let shorter = min(extent.upperBound - extent.lowerBound, band.upperBound - band.lowerBound)
        return overlap > shorter / 4
    }

    private static func fallbackRanges(_ text: String) -> [LineRange] {
        var cursor = 0
        return Self.split(text).map { line in
            let range = cursor..<(cursor + line.utf16.count)
            cursor = range.upperBound + 1
            return LineRange(text: line, range: range)
        }
    }

    /// A line's own text. Trailing whitespace is dropped because a break re-derived from
    /// geometry lands on the space that used to join two rows, and a reader anchored at the
    /// end of a line would otherwise miss the last figure on it.
    private static func lineRange(_ units: [UInt16], _ range: Range<Int>) -> LineRange {
        var end = range.upperBound
        while end > range.lowerBound, isSeparator(units[end - 1]) {
            end -= 1
        }
        let trimmed = range.lowerBound..<end
        return LineRange(
            text: String(decoding: units[trimmed], as: UTF16.self),
            range: trimmed
        )
    }

    /// Word x-extents for the lines of a page, used only to bootstrap the direction of a
    /// ledger's first row.
    ///
    /// PDFKit's `string` and its character indices can disagree on documents with ligatures
    /// or unusual encodings, and a wrong x-position would produce a confidently wrong debit
    /// or credit. So every index is bounds-checked and any mismatch simply yields no entry:
    /// the engine then reports the row as provisional and the import is flagged for review,
    /// which is honest.
    static func lineWords(on page: PDFPage, ranges: [LineRange]) -> [LineWords] {
        guard let text = page.string else { return [] }
        let units = Array(text.utf16)
        guard page.numberOfCharacters == units.count else { return [] }

        var result: [LineWords] = []
        for (lineIndex, line) in ranges.enumerated() {
            guard line.range.upperBound <= units.count else { continue }
            let words = Self.words(in: units[line.range], page: page)
            if !words.isEmpty {
                result.append(LineWords(lineIndex: UInt32(lineIndex), words: words))
            }
        }

        return result
    }

    private static let newline: UInt16 = 0x000A
    private static let space: UInt16 = 0x0020
    private static let nonBreakingSpace: UInt16 = 0x00A0

    private static func isSeparator(_ unit: UInt16) -> Bool {
        unit <= space || unit == nonBreakingSpace
    }

    /// Whitespace-split one line, giving each word the x-extent of its first and last
    /// character. A word whose bounds cannot be trusted discards the whole line's geometry.
    private static func words(in slice: ArraySlice<UInt16>, page: PDFPage) -> [Word] {
        var words: [Word] = []
        var index = slice.startIndex

        while index < slice.endIndex {
            while index < slice.endIndex, isSeparator(slice[index]) {
                index += 1
            }
            guard index < slice.endIndex else { break }

            let start = index
            while index < slice.endIndex, !isSeparator(slice[index]) {
                index += 1
            }
            let end = index - 1

            guard start >= 0, end < page.numberOfCharacters else { return [] }
            let first = page.characterBounds(at: start)
            let last = page.characterBounds(at: end)
            guard !first.isNull, !last.isNull, first.minX.isFinite, last.maxX.isFinite else {
                return []
            }

            words.append(
                Word(
                    text: String(decoding: slice[start...end], as: UTF16.self),
                    x0: Double(first.minX),
                    x1: Double(last.maxX)
                )
            )
        }

        return words
    }
}
