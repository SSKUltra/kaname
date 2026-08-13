import Foundation
import KanameCore
import Testing

@testable import Kaname

/// The front door, and the promise that every screen in the flow can be read and heard.
///
/// The visual half of that promise — clipping at the largest Dynamic Type size, contrast
/// under Reduce Transparency, VoiceOver's own reading of the front door — is audited by
/// `ios/UITests/ImportFrontDoorUITests.swift` and by the manual gate in the feature's
/// quickstart. What lives here is the half a unit test can honestly prove: that no screen
/// can be built without the words and the icon that make it announceable.
@Suite("Every screen in the import flow can be read and heard")
struct ImportAccessibilityTests {
    /// A synthetic 256-bit key (64 hex chars).
    private static let key = "5c4b3a2918070605040302010f0e0d0c0b0a09080706050403020100ffeeddcc"

    @Test("Every failure says something, and says it with an icon as well as words")
    func everyFailureIsAnnounceable() {
        let failures: [ImportFailure] = [
            .notAPDF, .passwordRequired, .wrongPassword, .noExtractableText, .unreadable,
            .unrecognizedIssuer, .cancelled, .storageUnavailable, .alreadyImporting,
        ]

        for failure in failures {
            #expect(failure.title.isEmpty == false)
            #expect(failure.message.isEmpty == false)
            // Colour never carries meaning alone: there is always a symbol and a sentence.
            #expect(failure.symbolName.isEmpty == false)
        }

        // Each failure earns its own sentence — a shared generic message would tell the
        // person nothing they could act on.
        #expect(Set(failures.map(\.title)).count == failures.count)
        #expect(Set(failures.map(\.message)).count == failures.count)
    }

    @Test("Every integrity verdict that speaks has both a symbol and a sentence")
    func everyIntegrityVerdictIsAnnounceable() {
        for outcome in [IntegrityOutcome.agrees, .needsReview] {
            let notice = outcome.notice
            #expect(notice?.symbolName.isEmpty == false)
            #expect(notice?.message.isEmpty == false)
        }
        // The third state is silence, and silence is announced as nothing at all.
        #expect(IntegrityOutcome.nothingToCheck.notice == nil)
    }

    @Test("Every stage of an import can be said out loud")
    func everyStageHasWords() {
        let spoken = ImportStage.allCases.map { ImportProgressView.stageText($0) }
        for text in spoken {
            #expect(text.isEmpty == false)
        }
        // A stage that reused another's words would leave the person unable to tell where the
        // import had got to.
        #expect(Set(spoken).count == ImportStage.allCases.count)
        // A stage that has not been reported yet still reads as something, never as blank.
        #expect(ImportProgressView.stageText(nil).isEmpty == false)
    }

    @Test("The empty state says what Kaname does and that the data stays on the device")
    func theEmptyStateKeepsItsPromise() {
        #expect(ImportEmptyStateView.title.isEmpty == false)
        #expect(ImportEmptyStateView.explanation.isEmpty == false)
        // The privacy promise is the reason a person hands Kaname their statements; it is
        // part of the copy deck, not a line a redesign may quietly drop.
        #expect(ImportEmptyStateView.privacyPromise.localizedCaseInsensitiveContains("device"))
        #expect(ImportEmptyStateView.actionTitle.isEmpty == false)
    }

    @Test("A fresh install shows the empty state, and an imported one shows the account")
    func theFrontDoorFollowsWhatHasBeenImported() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-frontdoor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try Store.open(path: dir.appendingPathComponent("kaname.db").path, key: Self.key)

        let lines = [
            "ICICI Bank Statement",
            "Statement Date May 28, 2026",
            "4315XXXXXXXX1002",
            "29/04/2026 4262 BBPS Payment received 0 13,628.36 CR",
            "26/05/2026 1814 Fee on gaming transaction 0 10.20",
        ]
        let service = ImportService(
            extractor: StubTextExtractor(lines: lines),
            store: store,
            now: { Date(timeIntervalSince1970: 1_786_000_000) }
        )
        let model = await ImportViewModel(makeService: { service })

        await model.refreshAccounts()
        // Nothing imported yet, so the front door has nothing to show but itself.
        #expect(await model.accounts.isEmpty)

        await model.importStatement(at: URL(fileURLWithPath: "/dev/null/statement.pdf"))
        #expect(await model.summary != nil)

        // After an import the person sees their data, not the pitch that got them here.
        let accounts = await model.accounts
        let account = try #require(accounts.first)
        #expect(accounts.count == 1)
        #expect(account.name.isEmpty == false)
        #expect(account.last4 == "1002")
        // Evidence the data is really there, rather than an account that might be empty.
        #expect(account.transactionCount == 2)
    }
}

/// Stands in for PDFKit so the front door can be exercised without a file on disk.
struct StubTextExtractor: StatementTextExtractor {
    let text: ExtractedText

    init(lines: [String]) {
        text = ExtractedText(lines: lines, fullText: lines.joined(separator: "\n"), lineWords: [])
    }

    func extract(from url: URL, password: String?) throws -> ExtractedText { text }
}
