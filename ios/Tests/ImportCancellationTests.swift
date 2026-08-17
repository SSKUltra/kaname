import CryptoKit
import Foundation
import KanameCore
import Testing

@testable import Kaname

/// An import a person abandons, and an import they ask for twice. Both are about the same
/// promise: Kaname never writes something the person did not ask for, and never reports one
/// document's figures for another.
///
/// The store is real and encrypted; extraction is stubbed so a run can be held open at a
/// known point. All statement text is 100% synthetic.
@Suite("An import can be abandoned, and never runs twice at once")
struct ImportCancellationTests {
    /// A synthetic 256-bit key (64 hex chars).
    private static let key = "aa11bb22cc33dd44ee55ff6600778899aabbccddeeff00112233445566778899"

    private static func tempDatabase() -> (dir: URL, path: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-cancel-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("kaname.db").path)
    }

    /// A digest over every file the store owns, so a change to a journal counts as a change.
    private static func digest(of directory: URL) -> String {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .sorted()
        var hasher = SHA256()
        for name in names {
            hasher.update(data: Data(name.utf8))
            hasher.update(data: (try? Data(contentsOf: directory.appendingPathComponent(name))) ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Holds the pipeline open inside extraction until the test lets it go, so "mid-import"
    /// is an exact moment rather than a guess at a duration.
    private final class BlockingExtractor: StatementTextExtractor, @unchecked Sendable {
        private let lock = NSLock()
        private let gate = DispatchSemaphore(value: 0)
        private var entered = false
        private let text: ExtractedText

        init(lines: [String]) {
            text = ExtractedText(lines: lines, fullText: lines.joined(separator: "\n"), lineWords: [])
        }

        var hasEntered: Bool {
            lock.lock()
            defer { lock.unlock() }
            return entered
        }

        func release() { gate.signal() }

        func extract(from url: URL, password: String?) throws -> ExtractedText {
            lock.lock()
            entered = true
            lock.unlock()
            gate.wait()
            return text
        }

        /// Waits for the pipeline to reach extraction without blocking a thread the pipeline
        /// itself may need.
        func waitUntilEntered() async throws {
            while !hasEntered {
                try await Task.sleep(for: .milliseconds(2))
            }
        }
    }

    /// A one-way flag a task can raise and another can wait on, without blocking a thread.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false

        func set() {
            lock.lock()
            raised = true
            lock.unlock()
        }

        func wait() async throws {
            while true {
                lock.lock()
                let raised = self.raised
                lock.unlock()
                if raised { return }
                try await Task.sleep(for: .milliseconds(2))
            }
        }
    }

    private static func service(extractor: any StatementTextExtractor, store: Store) -> ImportService {
        ImportService(
            extractor: extractor,
            store: store,
            now: { Date(timeIntervalSince1970: 1_786_000_000) }
        )
    }

    /// A synthetic ICICI credit-card statement.
    private static let cardLines = [
        "ICICI Bank Statement",
        "Statement Date May 28, 2026",
        "4315XXXXXXXX1002",
        "29/04/2026 4262 BBPS Payment received 0 13,628.36 CR",
        "26/05/2026 1814 Fee on gaming transaction 0 10.20",
    ]

    /// The same statement with 200 synthetic rows, for the promptness target. Generated
    /// rather than stored: it pins a duration, not a parse, so there is nothing golden about
    /// its contents.
    private static func largeCardLines(rows: Int) -> [String] {
        let header = [
            "ICICI Bank Statement",
            "Statement Date May 28, 2026",
            "4315XXXXXXXX1002",
        ]
        return header
            + (1...rows).map { index in
                let day = String(format: "%02d", (index % 28) + 1)
                return "\(day)/04/2026 \(4000 + index) Example merchant \(index) 0 1\(index).50"
            }
    }

    private static let firstURL = URL(fileURLWithPath: "/dev/null/first.pdf")
    private static let secondURL = URL(fileURLWithPath: "/dev/null/second.pdf")

    @Test("Cancelling mid-import stops it and leaves the store byte-identical")
    func cancellingLeavesTheStoreUntouched() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)
        let extractor = BlockingExtractor(lines: Self.cardLines)
        let service = Self.service(extractor: extractor, store: store)

        let before = Self.digest(of: db.dir)
        let running = Task { try await service.run(url: Self.firstURL, password: nil) { _ in } }
        try await extractor.waitUntilEntered()
        await service.cancel()
        extractor.release()

        await #expect(throws: ImportFailure.cancelled) { try await running.value }
        #expect(Self.digest(of: db.dir) == before)
        #expect(try store.listAccounts().isEmpty)
    }

    @Test("A double-tapped Import imports once, and both taps see the same result")
    func aDoubleTapImportsOnce() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)
        let extractor = BlockingExtractor(lines: Self.cardLines)
        let service = Self.service(extractor: extractor, store: store)

        let first = Task { try await service.run(url: Self.firstURL, password: nil) { _ in } }
        try await extractor.waitUntilEntered()
        // The same document, asked for a second time: the person tapped twice, they did not
        // ask for two imports.
        let secondStarted = Flag()
        let second = Task {
            secondStarted.set()
            return try await service.run(url: Self.firstURL, password: nil) { _ in }
        }
        // Let the second call reach the actor before the first is allowed to finish —
        // otherwise this would be testing two sequential imports, which is a different thing.
        try await secondStarted.wait()
        extractor.release()

        let firstSummary = try #require(try await first.value.summary)
        let secondSummary = try #require(try await second.value.summary)
        #expect(firstSummary == secondSummary)

        // One import happened, not two: the second tap joined the first rather than racing it.
        let account = try #require(try store.listAccounts().first)
        #expect(try store.listTransactions(accountId: account.id).count == 2)
        #expect(try store.listStatements(accountId: account.id).count == 1)
    }

    @Test("A different statement asked for mid-import is refused, not silently swapped")
    func aSecondDocumentIsRefusedWhileOneIsRunning() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)
        let extractor = BlockingExtractor(lines: Self.cardLines)
        let service = Self.service(extractor: extractor, store: store)

        let first = Task { try await service.run(url: Self.firstURL, password: nil) { _ in } }
        try await extractor.waitUntilEntered()

        // Handing back the running import's summary here would report one document's figures
        // for another — worse than refusing.
        await #expect(throws: ImportFailure.alreadyImporting) {
            try await service.run(url: Self.secondURL, password: nil) { _ in }
        }

        extractor.release()
        // The refusal cost the running import nothing.
        #expect(try await first.value.summary != nil)
    }

    @Test("A view going away does not abandon the import it started")
    func backgroundingDoesNotCancelTheImport() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)
        let extractor = BlockingExtractor(lines: Self.cardLines)
        let service = Self.service(extractor: extractor, store: store)

        // The caller stands in for a view that disappears: its task is cancelled outright.
        let caller = Task { try await service.run(url: Self.firstURL, password: nil) { _ in } }
        try await extractor.waitUntilEntered()
        caller.cancel()
        extractor.release()

        // The import owned by the actor runs to completion, so the person comes back to a
        // finished import rather than a progress bar that never resolves.
        let summary = try #require(try await caller.value.summary)
        #expect(summary.transactionsAdded == 2)
        let account = try #require(try store.listAccounts().first)
        #expect(try store.listTransactions(accountId: account.id).count == 2)
    }

    @Test("Cancelling a 200-transaction import takes effect within two seconds")
    func cancellingALargeImportIsPrompt() async throws {
        let db = Self.tempDatabase()
        defer { try? FileManager.default.removeItem(at: db.dir) }
        let store = try Store.open(path: db.path, key: Self.key)
        let extractor = BlockingExtractor(lines: Self.largeCardLines(rows: 200))
        let service = Self.service(extractor: extractor, store: store)

        let running = Task { try await service.run(url: Self.firstURL, password: nil) { _ in } }
        try await extractor.waitUntilEntered()

        let asked = ContinuousClock.now
        await service.cancel()
        extractor.release()
        await #expect(throws: ImportFailure.cancelled) { try await running.value }
        #expect(ContinuousClock.now - asked < .seconds(2))

        #expect(try store.listAccounts().isEmpty)
    }
}
