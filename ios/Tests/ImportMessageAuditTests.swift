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
                ImportSummary.importedSectionTitle,
                ImportSummary.accountSectionTitle,
                ImportSummary.accountSectionCaption,
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

    // MARK: - The summary's title has room to be read

    @Test("Nothing shares the summary's title bar with it")
    func theSummaryKeepsOneToolbarAction() throws {
        // `ImportSummaryView` states, in four words, what just happened to a person's bank
        // statement. It shipped rendering `Import comp…` at the **default** text size, because
        // an inline title is given whatever width the toolbar leaves it and a wide
        // "Import another" sat opposite "Done" (`issues/06`). The action was not removed —
        // FR-035 requires that another import can be started from this screen — it was moved
        // into the content, where it is a next action rather than a control competing with the
        // title. This is the pin, and what it pins is the *toolbar*: the regression is not a
        // typo but anything placed beside the title.
        //
        // Watched failing against the shipped toolbar before it was trusted.
        let source = try Self.summaryCode()

        #expect(source.contains("ToolbarItem(placement: .confirmationAction)"))
        for competitor in [
            ".cancellationAction", ".navigationBarLeading", ".topBarLeading", ".principal",
        ] {
            #expect(!source.contains(competitor), "\(competitor) is back beside the title")
        }
        // One `ToolbarItem`, counted rather than assumed: a second trailing item crowds the
        // title just as surely as a leading one.
        #expect(source.components(separatedBy: "ToolbarItem").count - 1 == 1)

        // FR-035 still holds, and from this screen: the action is in the content, and the view
        // still takes something to run. A pin that only banned the toolbar button would be
        // satisfied by deleting the capability altogether.
        #expect(source.contains("Button(\"Import another statement\", action: onImportAnother)"))
        #expect(source.contains("let onImportAnother: () -> Void"))
    }

    /// The summary's **code**, with its comments removed — the test target runs in a simulator,
    /// so the path comes from `#filePath`, a compile-time constant pointing at this file.
    ///
    /// Comments are stripped because the fix's own explanation names the button it removed, and
    /// an audit that cannot tell a banned control from the sentence describing why it went is an
    /// audit that punishes writing things down.
    private static func summaryCode() throws -> String {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Import/ImportSummaryView.swift")
        return try String(contentsOf: sources, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
