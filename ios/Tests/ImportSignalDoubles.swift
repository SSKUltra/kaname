import Foundation
import KanameCore
import Testing

@testable import Kaname

// What it takes to watch a signal honestly: a subscriber that records *when* it woke, an
// extractor that can hold an import open at an exact moment, and a way to wait for something
// to become true without blocking a thread the code under test needs.

/// Subscribes the way a screen does, and records what the store held at the moment each event
/// arrived — so "after the commit" is measured rather than assumed.
final class SignalWatcher: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [Int] = []
    private var task: Task<Void, Never>?

    init(_ signal: ImportCompletionSignal, observing store: Store) {
        let events = signal.events
        task = Task { [weak self] in
            for await _ in events {
                self?.record(Self.transactionCount(in: store))
            }
        }
    }

    /// What the store held at each event, in order.
    var observations: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }

    var events: Int { observations.count }

    func stop() { task?.cancel() }

    func waitForEvents(_ count: Int) async throws {
        try await waitUntil { self.events >= count }
    }

    private func record(_ count: Int) {
        lock.lock()
        seen.append(count)
        lock.unlock()
    }

    private static func transactionCount(in store: Store) -> Int {
        let accounts = (try? store.listAccounts()) ?? []
        return accounts.reduce(0) { total, account in
            total + (((try? store.listTransactions(accountId: account.id)) ?? []).count)
        }
    }
}

/// Holds the pipeline open inside extraction until the test lets it go, so "mid-import" is an
/// exact moment rather than a guess at a duration.
final class HeldExtractor: StatementTextExtractor, @unchecked Sendable {
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

    func waitUntilEntered() async throws {
        try await waitUntil { self.hasEntered }
    }
}

/// A one-way flag one task raises and another waits on, without blocking a thread.
final class Started: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return raised
    }

    func set() {
        lock.lock()
        raised = true
        lock.unlock()
    }
}

/// Polls a condition without blocking a thread the code under test may need.
func waitUntil(
    _ condition: @Sendable () -> Bool,
    within seconds: Double = 2,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    Issue.record("condition never became true", sourceLocation: sourceLocation)
}
