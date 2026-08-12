# 07 — iOS Keychain / Secure Enclave key ceremony (platform half of the store)

**Status:** resolved (shipped — `KeychainKeyStore` + `StoreLocator`; the file-protection assertion is device-only, see below)

**What to build:** the **platform half** of the encrypted store, deferred by
`01-encrypted-store-bootstrap.md`. The Rust core's FFI contract is fixed — `Store.open(path,
key)` takes a 64-char hex (256-bit) key and fails closed on a wrong key. This slice is the
**iOS (Swift) side**: generate a 256-bit key, hold it in the **Keychain (Secure Enclave-backed)**
never exported, hand its hex to `Store.open`, and mark the DB file **`NSFileProtectionComplete`**.
No Rust changes. Design of record: `.specify/memory/constitution.md` (I "Encrypted at rest" +
III), `docs/kaname-ios-plan.md` (P1/P2 persistence); `01-encrypted-store-bootstrap.md`.

**Blocked by:** #01 encrypted-store bootstrap (done — the FFI contract this calls).

## Settled decisions (triage)

> **Correction to the premise above:** the Secure Enclave only holds **P-256 EC** keys, so a
> 256-bit *symmetric* SQLCipher key cannot literally live in it. "Secure Enclave-backed" would
> mean SE-*wrapped*. We chose the simpler correct thing instead:

1. **Key storage → a Keychain generic-password item.** 32 random bytes from
   `SecRandomCopyBytes`, stored under `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — so the
   item is protected by the device passcode, **never syncs to iCloud**, and never leaves the
   device. **No biometric/LAContext gate in v1**: `kSecAccessControlBiometryCurrentSet` is
   destroyed by a Face ID re-enrolment, which would make the user's own database permanently
   unreadable. The key is generated once on first run, fetched thereafter, and never logged.
2. **File location + protection → App Support, `completeUntilFirstUserAuthentication`.** The DB
   lives in the app container's Application Support directory (not an App Group — no extension
   needs it yet). `NSFileProtectionComplete` would kill any write while the phone is locked;
   since the key itself is `WhenUnlockedThisDeviceOnly`, the database is already unreadable
   without an unlock, so `CompleteUntilFirstUserAuthentication` is the right trade.
3. **Testability → a protocol seam.** A `KeyStore` protocol with the real `KeychainKeyStore` and
   an in-memory fake. The lifecycle and the store wiring are unit-tested against the fake; the
   real Keychain path is exercised with a **unique per-run service name** (the simulator does
   support generic-password items), so CI covers it without cross-test pollution.

## Sketch

- `ios/Sources/Persistence/KeyStore.swift` — the protocol + `KeychainKeyStore` (generate-or-fetch,
  returning the 64-char lowercase hex the core's `Store.open` contract requires) + `KeyStoreError`.
- `ios/Sources/Persistence/StoreLocator.swift` — resolves the App Support DB path, creates the
  directory, applies the protection class, and opens `Store` with the fetched key.
- Tests: hex encoding is 64 chars; generate-then-fetch returns the *same* key; a second locator
  on the same Keychain opens the same database; a fresh service name mints a different key; the
  core still fails closed on a wrong key; the DB file carries the expected protection class.

## Deferred
Cross-device key sync (Pro/later); key rotation/re-encrypt; passphrase/recovery flows.

## Needs human verification (on device)

The simulator's filesystem does not implement data-protection classes, so
`attributesOfItem` reports none regardless of what is set. The
`databaseFileIsProtected` test is therefore gated to real hardware
(`.enabled(if: SIMULATOR_UDID == nil)`) and stands as the on-device check: run the
suite on a passcode-protected device and confirm the database file reports
`NSFileProtectionCompleteUntilFirstUserAuthentication`.
