import Foundation
import KanameCore
import PDFKit

/// The text a statement document yields — the engine's only view of it. The core never
/// opens a PDF; extraction is a platform concern.
struct ExtractedText: Equatable, Sendable {
    /// One **printed row** per element, its words joined by a single space.
    ///
    /// Not the text layer's own newlines: those are wrong in both directions on a real
    /// statement, and reconstruction both splits rows it merged and joins rows it split.
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
        for page in pages {
            // Between pages, never inside one: a 42-page statement is seconds of work, and a
            // person who has changed their mind should not wait for all of it. A page is
            // small enough to be the unit of that promise.
            try Task.checkCancellation()

            for row in PrintedRows.of(page) {
                // Sparse by design: a page whose geometry could not be trusted contributes
                // lines but no positions, so the ledger row-1 bootstrap degrades to "needs
                // review" — honest — rather than to a confidently wrong direction.
                if let words = row.words, !words.isEmpty {
                    lineWords.append(LineWords(lineIndex: UInt32(lines.count), words: words))
                }
                lines.append(row.text)
            }
        }

        let fullText = lines.joined(separator: "\n")
        guard fullText.contains(where: { !$0.isWhitespace }) else {
            throw ExtractionFailure.noExtractableText
        }

        return ExtractedText(lines: lines, fullText: fullText, lineWords: lineWords)
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
}
