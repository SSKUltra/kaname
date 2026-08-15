import Foundation

/// The one sentence an import says out loud: *a statement is now committed*.
///
/// It carries `Void` deliberately. A subscriber learns that something changed and has to ask
/// the engine what — so the engine stays the single source of which rows exist, and the front
/// door's count and the list's rows can never be built from two different answers (FR-045,
/// FR-057). A payload here would be a second population, arriving by a second route.
///
/// It is sent **after** `import_statement` returns, which is after the store's single
/// transaction has committed, and on no other path: a failed, cancelled or unanswered import
/// says nothing at all, so a filtered, scrolled list does not twitch for something that never
/// happened (FR-054, FR-055).
///
/// Broadcast rather than a single stream, because two screens listen: the list and the front
/// door. Each subscriber gets its own stream, and a stream that is dropped — a screen that
/// went away — removes itself.
final class ImportCompletionSignal: Sendable {
    /// The app's one signal, for the life of the process — the same reasoning as
    /// `StoreProvider`: two of these would be two halves of the app listening to different
    /// imports.
    static let shared = ImportCompletionSignal()

    /// Guards the subscriber table. An import yields from an actor's executor while a screen
    /// subscribes on the main one, so this is a real race rather than a theoretical one.
    private let lock = NSLock()
    private nonisolated(unsafe) var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// A new stream per subscriber, live from the moment it is created — an import that
    /// commits between `.task` starting and the loop's first suspension is still heard.
    ///
    /// The buffer keeps only the newest event: two imports that complete before the screen
    /// gets to re-read are one re-read, because the re-read reads *everything* either of them
    /// wrote.
    var events: AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            lock.lock()
            subscribers[id] = continuation
            lock.unlock()
            // A screen that goes away takes its stream with it, and the table forgets it —
            // otherwise every visit to the list leaves a continuation behind holding a closure
            // over a view that no longer exists.
            continuation.onTermination = { [weak self] _ in
                self?.remove(id)
            }
        }
    }

    /// How many screens are listening. Exposed so a test can prove a subscription really dies
    /// with the task that owns it, rather than leaking a continuation per visit.
    var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return subscribers.count
    }

    /// Say it once. Called only from the import's success path.
    func send() {
        lock.lock()
        let listeners = Array(subscribers.values)
        lock.unlock()
        for listener in listeners {
            listener.yield()
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        subscribers[id] = nil
        lock.unlock()
    }
}
