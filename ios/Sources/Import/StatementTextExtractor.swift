import Foundation
import KanameCore

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
