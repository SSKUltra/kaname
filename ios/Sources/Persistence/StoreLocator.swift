import Foundation
import KanameCore

/// Resolves where the encrypted database lives and opens it with the Keychain-held key — the
/// platform half of the store the Rust core deliberately does not own.
///
/// The core takes a path and a key and knows nothing about the filesystem or the Keychain; this
/// type supplies both, creates the containing directory, and applies the data-protection class.
struct StoreLocator {
    /// Application Support inside the app container. Not an App Group: no extension shares the
    /// database yet, and a group container would widen the blast radius for no benefit.
    private static let directoryName = "Kaname"
    private static let databaseFileName = "kaname.db"

    /// The protection class applied to the database file and its directory.
    ///
    /// `.complete` would make the file unreadable — and any in-flight write fail — the moment the
    /// screen locks, which breaks background import. `.completeUntilFirstUserAuthentication`
    /// keeps the data encrypted at rest until the person unlocks the device once after boot; the
    /// key itself is `WhenUnlockedThisDeviceOnly`, so the database is unreadable without an
    /// unlock regardless.
    static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    let keyStore: KeyStore
    /// The directory holding the database. Injectable so tests can point at a temp directory
    /// instead of the real container.
    let containerDirectory: URL

    init(keyStore: KeyStore, containerDirectory: URL? = nil) {
        self.keyStore = keyStore
        self.containerDirectory =
            containerDirectory ?? Self.defaultContainerDirectory()
    }

    var databaseURL: URL {
        containerDirectory.appendingPathComponent(Self.databaseFileName)
    }

    /// Open the encrypted store, creating the database on first run.
    ///
    /// The key never touches disk, a log, or a `description` — it is fetched, handed to the core,
    /// and dropped. An existing database opened with the wrong key fails closed inside the core.
    func open() throws -> Store {
        try prepareDirectory()
        let store = try Store.open(path: databaseURL.path, key: keyStore.keyHex())
        try applyProtection(to: databaseURL)
        return store
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: containerDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: Self.protection]
        )
    }

    /// Re-assert the protection class on the database file itself: SQLCipher creates the file, so
    /// it is not covered by the attributes passed at directory creation on every OS version.
    private func applyProtection(to url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.setAttributes(
            [.protectionKey: Self.protection],
            ofItemAtPath: url.path
        )
    }

    private static func defaultContainerDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let root = base.first ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent(directoryName, isDirectory: true)
    }
}
