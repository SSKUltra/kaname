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
        let pageTexts = pages.map { $0.string ?? "" }
        let fullText = pageTexts.joined(separator: "\n")
        guard fullText.contains(where: { !$0.isWhitespace }) else {
            throw ExtractionFailure.noExtractableText
        }

        return ExtractedText(
            lines: Self.split(fullText),
            fullText: fullText,
            // Page 1 only: it is the only page whose geometry the ledger row-1 bootstrap can
            // need, and it bounds the cost on a 200-page statement.
            lineWords: pages.first.map { Self.lineWords(on: $0) } ?? []
        )
    }

    /// The readers are fixture-locked to plain newline splitting — no trimming, no dropping
    /// of blank lines, no reshaping of any kind.
    static func split(_ fullText: String) -> [String] {
        fullText.components(separatedBy: "\n")
    }

    /// Word x-extents for the lines of a page, used only to bootstrap the direction of a
    /// ledger's first row.
    ///
    /// PDFKit's `string` and its character indices can disagree on documents with ligatures
    /// or unusual encodings, and a wrong x-position would produce a confidently wrong debit
    /// or credit. So every index is bounds-checked and any mismatch simply yields no entry:
    /// the engine then reports the row as provisional and the import is flagged for review,
    /// which is honest.
    static func lineWords(on page: PDFPage) -> [LineWords] {
        guard let text = page.string else { return [] }
        let units = Array(text.utf16)
        guard page.numberOfCharacters == units.count else { return [] }

        var result: [LineWords] = []
        var lineIndex = 0
        var cursor = 0

        while cursor <= units.count {
            let lineStart = cursor
            var lineEnd = cursor
            while lineEnd < units.count, units[lineEnd] != Self.newline {
                lineEnd += 1
            }

            let words = Self.words(in: units[lineStart..<lineEnd], page: page)
            if !words.isEmpty {
                result.append(LineWords(lineIndex: UInt32(lineIndex), words: words))
            }

            lineIndex += 1
            cursor = lineEnd + 1
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
