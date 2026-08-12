import Foundation
import Security

/// Supplies the 256-bit key that unlocks the SQLCipher database, as the 64-character lowercase
/// hex string the Rust core's `Store.open(path:key:)` contract requires.
///
/// A protocol so the persistence wiring can be exercised against an in-memory double; the real
/// implementation is ``KeychainKeyStore``.
protocol KeyStore {
    /// The database key, generating and persisting one on first call and returning that same key
    /// on every call thereafter.
    func keyHex() throws -> String
}

/// What can go wrong fetching or minting the database key. No case carries key material.
enum KeyStoreError: Error, Equatable {
    /// The system CSPRNG refused to produce bytes.
    case randomGenerationFailed
    /// A Keychain operation failed; `status` is the raw `OSStatus` for diagnosis.
    case keychain(OSStatus)
    /// The stored item was not a 256-bit key — the Keychain entry is corrupt or foreign.
    case malformedStoredKey
}

/// The real key ceremony: a 256-bit key held in the iOS Keychain as a generic-password item.
///
/// The key is 32 bytes from the system CSPRNG, generated once on first launch and fetched on
/// every launch after. It is stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so it is
/// protected by the device passcode, **never syncs to iCloud**, and never leaves the device; it
/// is never logged and never surfaced outside this type.
///
/// It is deliberately **not** gated on biometry: `kSecAccessControlBiometryCurrentSet` is
/// invalidated by a Face ID / Touch ID re-enrolment, which would leave the person permanently
/// locked out of their own financial history with no recovery path (the core fails closed on a
/// wrong key by design). Nor is it Secure Enclave-*resident* — the Enclave holds only P-256 EC
/// keys, never a symmetric one.
struct KeychainKeyStore: KeyStore {
    /// 256 bits, the key size SQLCipher is configured for.
    private static let keyByteCount = 32

    /// The Keychain service the item is filed under. Injectable so tests can use a unique name
    /// per run instead of colliding on the app's real key.
    let service: String
    let account: String

    init(service: String = "in.beaconbrain.kaname.database", account: String = "sqlcipher-key") {
        self.service = service
        self.account = account
    }

    func keyHex() throws -> String {
        if let existing = try loadKey() {
            return Self.hex(existing)
        }
        let minted = try Self.randomKey()
        do {
            try store(minted)
        } catch KeyStoreError.keychain(errSecDuplicateItem) {
            // Another launch path won the race; adopt whatever landed in the Keychain so the
            // database is never opened with two different keys.
            guard let winner = try loadKey() else { throw KeyStoreError.malformedStoredKey }
            return Self.hex(winner)
        }
        return Self.hex(minted)
    }

    /// Delete the stored key. Only used to keep tests from leaking Keychain items between runs —
    /// the app never destroys a key, because doing so orphans the database.
    func removeKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyStoreError.keychain(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func loadKey() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == Self.keyByteCount else {
                throw KeyStoreError.malformedStoredKey
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeyStoreError.keychain(status)
        }
    }

    private func store(_ key: Data) throws {
        var attributes = baseQuery()
        attributes[kSecValueData as String] = key
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyStoreError.keychain(status) }
    }

    private static func randomKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: keyByteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw KeyStoreError.randomGenerationFailed
        }
        return Data(bytes)
    }

    /// The core's key contract is 64 lowercase hex characters.
    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
