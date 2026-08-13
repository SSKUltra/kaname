import Foundation
import KanameCore
import PDFKit
import Testing

@testable import Kaname

/// The only gate no fixture can close: does this actually read the statements a person has?
///
/// Synthetic geometry vectors prove the extraction does what it was designed to do. They
/// cannot prove the design matched a real bank's layout — a vector that models a layout
/// slightly wrong passes while the real file still fails. Only the real files can close
/// that, and the real files may never enter this repository.
///
/// So this suite is **skipped unless `KANAME_REFERENCE_DIR` is set**, points at a directory
/// that stays on the operator's own machine, and prints exactly two facts per file: which
/// issuer was recognised, and how many transactions were read. It writes **nothing** — not
/// to the repository, not to the store, not to a file, not to the network — and it never
/// prints a line of statement text, a merchant, an amount, a date, an account number or a
/// file name. Counts are the whole output, and counts are what goes in the pull request.
///
/// Run it with `make reference-check DIR=/path/to/your/own/statements`.
///
/// ⚠️ The variable reaches this process only because the Makefile sets
/// `TEST_RUNNER_KANAME_REFERENCE_DIR`: `xcodebuild` forwards nothing else of the shell's
/// environment into the simulator. Set it without that prefix and the suite is *skipped*,
/// which reports as a passing test run with no counts — a silence that reads exactly like a
/// clean result. That is why the Makefile fails when it sees no counts.
@Suite("Reference-set verification (local, opt-in)")
struct ReferenceSetVerification {
    private static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment["KANAME_REFERENCE_DIR"],
            !path.isEmpty
        else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Whether to describe the *shape* of a document that read nothing. Off unless
    /// `KANAME_REFERENCE_SHAPES` is set, because it is only ever wanted while diagnosing.
    private static var wantsShapes: Bool {
        ProcessInfo.processInfo.environment["KANAME_REFERENCE_SHAPES"].map { !$0.isEmpty } ?? false
    }

    /// What one document yielded, reduced to the facts that may be spoken aloud.
    private struct Outcome {
        let issuer: String
        let transactions: Int
        let shapes: [String]
    }

    /// A line with every value stripped out: digits become `9`, letters become `A` or `a`,
    /// and everything else — the punctuation, the currency marks, the spaces the columns
    /// left behind — stays exactly where it was.
    ///
    /// What survives is the *shape* of the line and nothing that was ever true about
    /// anybody: no merchant, no amount, no date, no account number. It is the same
    /// signature-not-values principle the geometry fixtures are built on
    /// (`docs/adr/0004-unknown-bank-ingestion.md`), pointed the other way — a person can
    /// read a layout off their own screen, and paste it into a bug report, without handing
    /// over a line of their statement.
    private static func shape(of line: String) -> String {
        String(
            line.map { character in
                if character.isNumber { return "9" }
                if character.isUppercase { return "A" }
                if character.isLowercase { return "a" }
                return character
            }
        )
    }

    private static func read(_ url: URL) -> Outcome {
        do {
            let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)
            let shapes = Self.wantsShapes ? extracted.lines.map(Self.shape) : []
            guard let issuer = detectIssuer(fullText: extracted.fullText) else {
                return Outcome(issuer: "not recognised", transactions: 0, shapes: shapes)
            }
            let statement = try readStatement(
                issuer: issuer,
                lines: extracted.lines,
                fullText: extracted.fullText,
                lineWords: extracted.lineWords
            )
            return Outcome(
                issuer: issuer.displayName,
                transactions: statement.lines.count,
                shapes: shapes
            )
        } catch {
            // Deliberately not the error: an extraction failure carries the document's own
            // text in some cases, and no diagnostic here may.
            return Outcome(issuer: "could not be read", transactions: 0, shapes: [])
        }
    }

    /// The shape of a document that read nothing — the only case where a shape is any use,
    /// and the only case it is printed.
    private static func describe(_ outcome: Outcome) {
        guard !outcome.shapes.isEmpty else { return }
        print("      shape of the first \(min(shapeLimit, outcome.shapes.count)) of \(outcome.shapes.count) line(s):")
        for line in outcome.shapes.prefix(shapeLimit) {
            print("      | \(line)")
        }
    }

    private static let shapeLimit = 40

    @Test(
        "Every statement in the reference directory is read, and its counts reported",
        .enabled(if: ReferenceSetVerification.directory != nil)
    )
    func readsTheReferenceSet() throws {
        let directory = try #require(Self.directory)
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var empty = 0
        var unrecognised = 0
        print("reference-check: \(files.count) document(s)")
        for (number, file) in files.enumerated() {
            let outcome = Self.read(file)
            // The index, never the file name: a statement is often named for its holder.
            print("  [\(number + 1)] \(outcome.issuer) — \(outcome.transactions) transaction(s)")
            if outcome.transactions == 0 {
                empty += 1
                Self.describe(outcome)
            }
            if outcome.issuer == "not recognised" { unrecognised += 1 }
        }
        print("reference-check: \(empty) read zero transactions, \(unrecognised) unrecognised")

        // No assertion on the counts: this suite reports, and a person judges. Failing here
        // on a number would only tempt someone to tune a fixture until it passed.
        #expect(files.isEmpty == false, "KANAME_REFERENCE_DIR contains no PDFs")
    }
}
