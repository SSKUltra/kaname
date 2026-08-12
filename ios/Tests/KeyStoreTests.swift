import Foundation
import KanameCore
import Testing

@testable import Kaname

/// "key ceremony" — proves the platform half of the encrypted store: a 256-bit key is minted once
/// and re-fetched thereafter from the Keychain, and the locator opens the database in Application
/// Support with the data-protection class applied. No test asserts on key *material* beyond its
/// shape, and every Keychain test uses a unique service name so runs cannot collide.
@Suite("Encrypted store key ceremony")
struct KeyStoreTests {
    /// An in-memory `KeyStore` double: mints once, then returns the same key — the contract the
    /// real Keychain implementation upholds across launches.
    final class FakeKeyStore: KeyStore, @unchecked Sendable {
        private var key: String?
        private(set) var mintCount = 0

        init(key: String? = nil) {
            self.key = key
        }

        func keyHex() throws -> String {
            if let key { return key }
            mintCount += 1
            let minted = String(repeating: "ab", count: 32)
            key = minted
            return minted
        }
    }

    private static func tempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-locator-\(UUID().uuidString)", isDirectory: true)
        return dir
    }

    /// A Keychain service name unique to this run, so tests never read or clobber the app's real
    /// key and never collide with each other.
    private static func uniqueService() -> String {
        "in.beaconbrain.kaname.tests.\(UUID().uuidString)"
    }

    @Test("A minted key is 64 lowercase hex characters — the core's key contract")
    func mintedKeyMatchesTheCoreContract() throws {
        let service = Self.uniqueService()
        let keyStore = KeychainKeyStore(service: service)
        defer { try? keyStore.removeKey() }

        let key = try keyStore.keyHex()
        #expect(key.count == 64)
        #expect(key.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("The same key comes back on every fetch, as it must across launches")
    func keyIsStableAcrossFetches() throws {
        let service = Self.uniqueService()
        let keyStore = KeychainKeyStore(service: service)
        defer { try? keyStore.removeKey() }

        let first = try keyStore.keyHex()
        // A separate instance stands in for a later app launch reading the same Keychain item.
        let second = try KeychainKeyStore(service: service).keyHex()
        #expect(first == second)
    }

    @Test("A fresh install mints a different key")
    func aFreshInstallMintsADifferentKey() throws {
        let firstInstall = KeychainKeyStore(service: Self.uniqueService())
        let secondInstall = KeychainKeyStore(service: Self.uniqueService())
        defer {
            try? firstInstall.removeKey()
            try? secondInstall.removeKey()
        }

        #expect(try firstInstall.keyHex() != secondInstall.keyHex())
    }

    @Test("Removing the key makes the next fetch mint a new one")
    func removingTheKeyMintsANewOne() throws {
        let keyStore = KeychainKeyStore(service: Self.uniqueService())
        defer { try? keyStore.removeKey() }

        let original = try keyStore.keyHex()
        try keyStore.removeKey()
        #expect(try keyStore.keyHex() != original)
    }

    @Test("The locator opens a database that round-trips an account")
    func locatorOpensAUsableDatabase() throws {
        let directory = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let locator = StoreLocator(keyStore: FakeKeyStore(), containerDirectory: directory)
        let store = try locator.open()
        _ = try store.insertAccount(
            account: NewAccount(
                name: "HDFC Savings",
                bankCode: "HDFC",
                isCreditCard: false,
                last4: nil,
                currency: "INR",
                createdAt: "2026-08-12T00:00:00Z",
                updatedAt: "2026-08-12T00:00:00Z"
            )
        )
        #expect(try store.listAccounts().count == 1)
        #expect(FileManager.default.fileExists(atPath: locator.databaseURL.path))
    }

    /// Data protection is a device-only facility: the simulator's filesystem does not implement
    /// protection classes, so `attributesOfItem` reports none no matter what we set. The test is
    /// therefore skipped there and stands as the on-device verification step.
    @Test(
        "The database file carries the data-protection class",
        .enabled(if: ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == nil)
    )
    func databaseFileIsProtected() throws {
        let directory = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let locator = StoreLocator(keyStore: FakeKeyStore(), containerDirectory: directory)
        _ = try locator.open()

        let attributes = try FileManager.default.attributesOfItem(atPath: locator.databaseURL.path)
        let protection = attributes[.protectionKey] as? FileProtectionType
        #expect(protection == StoreLocator.protection)
    }

    @Test("Applying the protection class never fails the open")
    func applyingProtectionDoesNotFailTheOpen() throws {
        let directory = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Runs everywhere: proves the locator's protection step is a no-op-safe part of `open`,
        // even on a filesystem that ignores protection classes.
        let locator = StoreLocator(keyStore: FakeKeyStore(), containerDirectory: directory)
        _ = try locator.open()
        #expect(FileManager.default.fileExists(atPath: locator.databaseURL.path))
        #expect(StoreLocator.protection == .completeUntilFirstUserAuthentication)
    }

    @Test("Re-opening with the same key reads the data back — the key survives a launch")
    func reopeningWithTheSameKeyReadsTheDataBack() throws {
        let directory = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // One shared fake stands in for the Keychain outliving both launches.
        let keyStore = FakeKeyStore()
        do {
            let store = try StoreLocator(keyStore: keyStore, containerDirectory: directory).open()
            _ = try store.insertAccount(
                account: NewAccount(
                    name: "HDFC Savings",
                    bankCode: "HDFC",
                    isCreditCard: false,
                    last4: nil,
                    currency: "INR",
                    createdAt: "2026-08-12T00:00:00Z",
                    updatedAt: "2026-08-12T00:00:00Z"
                )
            )
        }

        let reopened = try StoreLocator(keyStore: keyStore, containerDirectory: directory).open()
        #expect(try reopened.listAccounts().count == 1)
        // The key was minted once and reused, never regenerated behind the app's back.
        #expect(keyStore.mintCount == 1)
    }

    @Test("A different key fails closed against an existing database")
    func aDifferentKeyFailsClosed() throws {
        let directory = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try StoreLocator(keyStore: FakeKeyStore(), containerDirectory: directory).open()

        // A wrong key must never yield a readable database — the core's fail-closed contract,
        // asserted here through the platform wiring.
        let wrongKey = FakeKeyStore(key: String(repeating: "cd", count: 32))
        #expect(throws: StoreError.self) {
            _ = try StoreLocator(keyStore: wrongKey, containerDirectory: directory).open()
        }
    }
}
