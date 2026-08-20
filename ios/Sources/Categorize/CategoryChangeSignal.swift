import Foundation

/// The one sentence a correction says out loud: *a category was decided*.
///
/// It exists for the count on the front door. A person opens the worklist, answers three
/// transactions, and comes back — and the door they came through has to say three fewer,
/// without their having to reload anything (E5). The screen that made the change is two pushes
/// away from the screen that shows the count, so nothing on the way back can carry it.
///
/// ⚠️ **Deliberately not `ImportCompletionSignal`.** The shape is the same and the duplication
/// is real, but the *sentence* is not: an import says a statement was committed, and the
/// transaction list re-reads its whole population when it hears one. A correction changes one
/// row, or the rows one memory names, and the surfaces that care are not the same surfaces.
/// Sending a correction on the import's signal would make every category change look, to every
/// listener, exactly like a statement arriving.
///
/// It carries `Void`, for `ImportCompletionSignal`'s reason and with more force here: a
/// subscriber learns that something changed and must ask the **engine** what. A payload would
/// be a count travelling by a second route, and the whole point of FR-043 is that there is one.
final class CategoryChangeSignal: Sendable {
    /// The app's one signal, for the life of the process. Two of these would be two halves of
    /// the app listening to different corrections.
    static let shared = CategoryChangeSignal()

    /// Guards the subscriber table. The write happens on an actor's executor while a screen
    /// subscribes on the main one, so this is a real race rather than a theoretical one.
    private let lock = NSLock()
    private nonisolated(unsafe) var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// A new stream per subscriber, live from the moment it is created.
    ///
    /// The buffer keeps only the newest event: two corrections that land before the front door
    /// gets to re-read are one re-read, because the re-read asks for the count *now* rather
    /// than for the difference either of them made.
    var events: AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            lock.lock()
            subscribers[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.remove(id)
            }
        }
    }

    /// How many screens are listening. Exposed so a test can prove a subscription dies with
    /// the task that owns it rather than leaking a continuation per visit.
    var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return subscribers.count
    }

    /// Say it once. Called only after the engine has recorded a decision.
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
