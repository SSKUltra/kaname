import Foundation
import KanameCore
import Testing

@testable import Kaname

/// The one sentence an import says out loud, and everything that must be true about it.
///
/// The list has to keep up with an import without a relaunch, and it has to do that without
/// ever showing half a statement. The whole of the second half rests on *when* the signal is
/// sent: after the store's single transaction has committed, and never on a path where
/// nothing was committed at all. A signal sent one line earlier would be indistinguishable in
/// every test that only counts events — so these tests watch what the store held at the
/// moment each event arrived, and watch an import that is held open produce silence.
///
/// The store is real and encrypted; extraction is stubbed. All statement text is synthetic
/// (Constitution I).
@Suite("An import says exactly once that it finished")
struct ImportCompletionSignalTests {
    /// A synthetic 256-bit key (64 hex chars). Test-only; never a real device key.
    private static let key = "1122334455667788990011223344556677889900aabbccddeeff001122334455"

    private static let statementURL = URL(fileURLWithPath: "/dev/null/statement.pdf")

    // MARK: - I1 — the event follows the commit, never precedes it

    @Test("Nothing is said while the import is still running")
    func anImportInFlightSaysNothing() async throws {
        let database = try Database()
        defer { database.cleanUp() }
        let signal = ImportCompletionSignal()
        let watcher = SignalWatcher(signal, observing: database.store)
        defer { watcher.stop() }

        let extractor = HeldExtractor(lines: Self.cardLines)
        let service = database.service(extractor: extractor, completions: signal)
        let running = Task { try await service.run(url: Self.statementURL, password: nil) { _ in } }
        try await extractor.waitUntilEntered()

        // Held open inside extraction: nothing has been written, so there is nothing to say.
        try await Task.sleep(for: .milliseconds(20))
        #expect(watcher.events == 0)

        extractor.release()
        _ = try await running.value
        try await watcher.waitForEvents(1)
    }

    @Test("A subscriber woken by the signal finds the whole statement already in the store")
    func theEventArrivesAfterTheCommit() async throws {
        let database = try Database()
        defer { database.cleanUp() }
        let signal = ImportCompletionSignal()
        let watcher = SignalWatcher(signal, observing: database.store)
        defer { watcher.stop() }

        let service = database.service(
            extractor: StubTextExtractor(lines: Self.cardLines), completions: signal)
        _ = try await service.run(url: Self.statementURL, password: nil) { _ in }
        try await watcher.waitForEvents(1)

        // Every row of the statement, not some of them: the event cannot be observed against a
        // half-written import, because the write is one transaction and the event follows it.
        #expect(watcher.observations == [2])
        #expect(watcher.events == 1)
    }

    @Test("One committed statement is one event, however many times it was asked for")
    func oneStatementIsOneEvent() async throws {
        let database = try Database()
        defer { database.cleanUp() }
        let signal = ImportCompletionSignal()
        let watcher = SignalWatcher(signal, observing: database.store)
        defer { watcher.stop() }

        let extractor = HeldExtractor(lines: Self.cardLines)
        let service = database.service(extractor: extractor, completions: signal)
        let first = Task { try await service.run(url: Self.statementURL, password: nil) { _ in } }
        try await extractor.waitUntilEntered()
        // The same document asked for twice — one import, and so one event. A second event
        // would send the list off to re-read a change that never happened.
        let secondStarted = Started()
        let second = Task {
            secondStarted.set()
            return try await service.run(url: Self.statementURL, password: nil) { _ in }
        }
        // Let the second call reach the actor before the first is allowed to finish, or this
        // would be two sequential imports, which are correctly two events.
        try await waitUntil { secondStarted.isSet }
        try await Task.sleep(for: .milliseconds(10))
        extractor.release()
        _ = try await first.value
        _ = try await second.value

        try await watcher.waitForEvents(1)
        try await Task.sleep(for: .milliseconds(20))
        #expect(watcher.events == 1)
    }

    // MARK: - I2 — silence is what a failure sounds like

    @Test("A cancelled import says nothing at all")
    func aCancelledImportSaysNothing() async throws {
        let database = try Database()
        defer { database.cleanUp() }
        let signal = ImportCompletionSignal()
        let watcher = SignalWatcher(signal, observing: database.store)
        defer { watcher.stop() }

        let extractor = HeldExtractor(lines: Self.cardLines)
        let service = database.service(extractor: extractor, completions: signal)
        let running = Task { try await service.run(url: Self.statementURL, password: nil) { _ in } }
        try await extractor.waitUntilEntered()
        await service.cancel()
        extractor.release()

        await #expect(throws: ImportFailure.cancelled) { try await running.value }
        try await Task.sleep(for: .milliseconds(20))
        #expect(watcher.events == 0)
    }

    @Test("A document Kaname cannot read says nothing either")
    func aFailedImportSaysNothing() async throws {
        let database = try Database()
        defer { database.cleanUp() }
        let signal = ImportCompletionSignal()
        let watcher = SignalWatcher(signal, observing: database.store)
        defer { watcher.stop() }

        let service = database.service(
            extractor: StubTextExtractor(lines: ["A page of prose with no bank in it"]),
            completions: signal
        )
        await #expect(throws: ImportFailure.unrecognizedIssuer) {
            try await service.run(url: Self.statementURL, password: nil) { _ in }
        }

        try await Task.sleep(for: .milliseconds(20))
        #expect(watcher.events == 0)
        #expect(try database.store.listAccounts().isEmpty)
    }

    @Test("A statement waiting on an account question says nothing until the person answers")
    func anUnansweredQuestionSaysNothing() async throws {
        let database = try Database()
        defer { database.cleanUp() }
        // An account already exists with no last-4, and a second one for the same issuer, so
        // the statement cannot be placed without asking.
        for name in ["Synthetic Card A", "Synthetic Card B"] {
            _ = try database.store.insertAccount(
                account: NewAccount(
                    name: name,
                    bankCode: "ICICI",
                    isCreditCard: true,
                    last4: nil,
                    currency: "INR",
                    createdAt: "2026-08-01T00:00:00Z",
                    updatedAt: "2026-08-01T00:00:00Z"
                ))
        }
        let signal = ImportCompletionSignal()
        let watcher = SignalWatcher(signal, observing: database.store)
        defer { watcher.stop() }

        let service = database.service(
            extractor: StubTextExtractor(lines: Self.cardLines), completions: signal)
        let result = try await service.run(url: Self.statementURL, password: nil) { _ in }
        guard case .needsAccount = result else {
            Issue.record("the statement should have been ambiguous")
            return
        }

        // Nothing has been written, so nothing is announced.
        try await Task.sleep(for: .milliseconds(20))
        #expect(watcher.events == 0)

        // Answering the question is what commits the statement — and that does announce itself.
        let accountID = try #require(try database.store.listAccounts().first?.id)
        _ = try await service.resolveAccount(.existing(id: accountID))
        try await watcher.waitForEvents(1)
        #expect(watcher.observations == [2])
    }

    // MARK: - I3 — the signal carries the fact, and nothing else

    @Test("The signal carries no rows, no counts and no account")
    func theSignalCarriesNothingButTheFact() throws {
        let signal = ImportCompletionSignal()
        let stream: Any = signal.events

        // `Void` is the whole point: a subscriber learns only that something changed, and has
        // to ask the engine what. Anything richer would be a second source of the population,
        // and two sources are how a count and a list come to disagree (I3, FR-045).
        #expect(type(of: stream) == AsyncStream<Void>.self)

        let source = try Self.signalSource()
        let streams = source.components(separatedBy: "AsyncStream<").dropFirst()
        #expect(!streams.isEmpty, "the audit found no stream to read")
        for declaration in streams {
            #expect(declaration.hasPrefix("Void>"), "a stream carries \(declaration.prefix(20))")
        }
    }

    // MARK: - I4 — the subscription dies with the screen

    @Test("A subscription ends when the task that owns it is cancelled")
    func aSubscriptionDiesWithItsTask() async throws {
        let signal = ImportCompletionSignal()
        #expect(signal.subscriberCount == 0)

        // The shape of a screen's `.task`: an unbounded loop over the events, cancelled when
        // the view goes away.
        let started = AsyncStream<Void>.makeStream()
        let screen = Task {
            started.continuation.yield()
            for await _ in signal.events { continue }
        }
        var iterator = started.stream.makeAsyncIterator()
        await iterator.next()
        try await waitUntil { signal.subscriberCount == 1 }

        screen.cancel()
        await screen.value

        // No continuation is left behind holding a closure over a screen that is gone, and a
        // later import writes into nothing.
        try await waitUntil { signal.subscriberCount == 0 }
        signal.send()
        #expect(signal.subscriberCount == 0)
    }

    // MARK: - T124 — a cancelled import produces no transition at all

    @Test("A cancelled import moves the list through no state at all")
    func aCancelledImportProducesNoTransitionAtAll() async throws {
        let database = try Database()
        defer { database.cleanUp() }
        let signal = ImportCompletionSignal()

        let double = HistoryDouble(
            pages: [HistoryPage(rows: [historyRow("a", "2026-07-15")], cursor: nil)],
            summaries: [accountSummary(1)]
        )
        let model = await TransactionListViewModel(history: double, clock: listClock)
        await model.onAppear()
        let listening = Task { await model.refreshWhenImportsComplete(signal) }
        try await waitUntil { signal.subscriberCount == 1 }

        let before = await model.state
        let rowsBefore = await model.groups.flatMap(\.rows)
        let requestsBefore = await double.requestCount

        let extractor = HeldExtractor(lines: Self.cardLines)
        let service = database.service(extractor: extractor, completions: signal)
        let running = Task { try await service.run(url: Self.statementURL, password: nil) { _ in } }
        try await extractor.waitUntilEntered()
        await service.cancel()
        extractor.release()
        await #expect(throws: ImportFailure.cancelled) { try await running.value }
        try await Task.sleep(for: .milliseconds(30))

        // No event, so no refresh, so no read — the list did not so much as ask a question
        // (`data-model.md` §5 invariant 5, FR-055).
        #expect(await double.requestCount == requestsBefore)
        #expect(await model.state == before)
        #expect(await model.groups.flatMap(\.rows) == rowsBefore)
        listening.cancel()
    }

    // MARK: - Fixtures

    /// A synthetic ICICI credit-card statement: two rows, no real merchant, no real card.
    private static let cardLines = [
        "ICICI Bank Statement",
        "Statement Date May 28, 2026",
        "4315XXXXXXXX1002",
        "29/04/2026 4262 BBPS Payment received 0 13,628.36 CR",
        "26/05/2026 1814 Fee on gaming transaction 0 10.20",
    ]

    private static func signalSource() throws -> String {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Transactions/ImportCompletionSignal.swift")
        return try String(contentsOf: sources, encoding: .utf8)
    }

    /// A real encrypted store in a temporary directory, and the service that writes to it.
    private struct Database {
        let directory: URL
        let store: Store

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("kaname-signal-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            store = try Store.open(
                path: directory.appendingPathComponent("kaname.db").path,
                key: ImportCompletionSignalTests.key
            )
        }

        func service(
            extractor: any StatementTextExtractor,
            completions: ImportCompletionSignal
        ) -> ImportService {
            ImportService(
                extractor: extractor,
                store: store,
                now: { Date(timeIntervalSince1970: 1_786_000_000) },
                completions: completions
            )
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
