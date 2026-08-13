import Foundation
import Testing

@testable import Kaname

/// Nothing an engine, a database or the system wrote may reach a person's eyes. Every
/// sentence in this flow is hand-written, and this suite is the mechanical proof — the
/// counterpart to `scripts/import-path-audit.sh`, which guards the same promise from the
/// other side by banning bank literals anywhere under `ios/Sources`.
///
/// The one engine-supplied string allowed on screen is `Issuer.display_name`, which is
/// rendered verbatim so a tie-break between two readers claiming one document stays visible.
@Suite("No engine or system text reaches the screen")
struct ImportMessageAuditTests {
    /// Words that only ever appear in text a machine wrote. A sentence containing one of
    /// these is a leak, whatever else it says.
    private static let forbidden = [
        "error", "Error", "exception", "Exception", "nil", "Optional(", "null",
        "StoreError", "ReaderError", "UnknownIssuer", "sqlite", "SQLite", "SQLCipher",
        "UniFFI", "FFI", "Rust", "panic", "unwrap", "bank_code", "bankCode", "last4",
        "0x", "code:", "errno", "localizedDescription", "ParsedStatement", "reconcile",
    ]

    /// Every user-facing sentence the flow can produce, gathered in one place so a new
    /// screen's copy cannot quietly escape the audit.
    private static var everySentence: [String] {
        let failures: [ImportFailure] = [
            .notAPDF, .passwordRequired, .wrongPassword, .noExtractableText, .unreadable,
            .unrecognizedIssuer, .cancelled, .storageUnavailable, .alreadyImporting,
        ]
        return failures.flatMap { [$0.title, $0.message] }
            + [IntegrityOutcome.agrees, .needsReview].compactMap { $0.notice?.message }
            + [ImportSummary.nothingRecognizedNotice.message]
            + ImportStage.allCases.map { ImportProgressView.stageText($0) }
            + [
                ImportEmptyStateView.title,
                ImportEmptyStateView.explanation,
                ImportEmptyStateView.privacyPromise,
                ImportEmptyStateView.actionTitle,
            ]
    }

    @Test("No sentence in the flow contains machine-written text")
    func noSentenceLeaksMachineText() {
        for sentence in Self.everySentence {
            for word in Self.forbidden {
                #expect(
                    sentence.contains(word) == false,
                    "\"\(sentence)\" contains the machine-written word \"\(word)\""
                )
            }
        }
    }

    @Test("No sentence in the flow contains a code a person could not act on")
    func noSentenceLeaksACode() {
        // A run of digits, or a SCREAMING_SNAKE identifier, is what an error code and a
        // reader id look like. A person can act on words; they cannot act on either of these.
        let codeShaped = try? NSRegularExpression(pattern: "\\d{3,}|\\b[A-Z]{2,}_[A-Z_]{2,}\\b")
        for sentence in Self.everySentence {
            let range = NSRange(sentence.startIndex..., in: sentence)
            let matches = codeShaped?.numberOfMatches(in: sentence, range: range) ?? 0
            #expect(matches == 0, "\"\(sentence)\" reads like a code rather than a sentence")
        }
    }

    @Test("Nothing in the flow is left without something to say")
    func nothingIsSpeechless() {
        for sentence in Self.everySentence {
            #expect(sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        }
    }
}
