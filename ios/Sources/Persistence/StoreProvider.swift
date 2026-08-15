import Foundation
import KanameCore

/// The app's one `Store`, for the life of the process.
///
/// This is a correctness requirement, not tidiness. `Store` wraps a `Mutex<Connection>`, and
/// `import_statement` writes an account, a statement, its transactions, the re-import links,
/// the categorization and the dedup links inside **one** SQLite transaction. Two `Store`
/// instances over the same file would be two connections with two independent locks, and a
/// page read could land in the middle of that write — SQLite would either block or hand back
/// `SQLITE_BUSY`, and "a person never sees half an imported statement" would be a property of
/// timing rather than of the code. One `Store` makes the engine's own mutex serialise every
/// read against the atomic import, and the guarantee becomes structural.
enum StoreProvider {
    /// Guards the memo. Opening the database is I/O and can be reached from more than one
    /// task at launch, so the first-open race is closed here rather than hoped away.
    private static let lock = NSLock()
    private nonisolated(unsafe) static var opened: Store?

    /// The process's `Store`, opened on first use and reused thereafter.
    static func shared() throws -> Store {
        lock.lock()
        defer { lock.unlock() }
        if let opened { return opened }
        let store = try StoreLocator(keyStore: KeychainKeyStore()).open()
        opened = store
        return store
    }

    /// Hand in a store built over a temporary database, so a test exercises the same single
    /// instance the app does without touching the Keychain or the real container.
    static func use(_ store: Store?) {
        lock.lock()
        defer { lock.unlock() }
        opened = store
    }
}
