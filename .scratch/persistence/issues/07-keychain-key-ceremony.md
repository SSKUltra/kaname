# 07 — iOS Keychain / Secure Enclave key ceremony (platform half of the store)

**Status:** needs-triage

**What to build:** the **platform half** of the encrypted store, deferred by
`01-encrypted-store-bootstrap.md`. The Rust core's FFI contract is fixed — `Store.open(path,
key)` takes a 64-char hex (256-bit) key and fails closed on a wrong key. This slice is the
**iOS (Swift) side**: generate a 256-bit key, hold it in the **Keychain (Secure Enclave-backed)**
never exported, hand its hex to `Store.open`, and mark the DB file **`NSFileProtectionComplete`**.
No Rust changes. Design of record: `.specify/memory/constitution.md` (I "Encrypted at rest" +
III), `docs/kaname-ios-plan.md` (P1/P2 persistence); `01-encrypted-store-bootstrap.md`.

**Blocked by:** #01 encrypted-store bootstrap (done — the FFI contract this calls).

## Open decision (settle with the user before implementing)

1. **Key storage + accessibility.** Keychain item with
   `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, Secure Enclave-backed; **biometric/LAContext
   gate** on v1 or not? First-run generates via `SecRandomCopyBytes`; never exported/logged.
2. **File protection + location.** DB path (app container / app group?) marked
   `NSFileProtectionComplete`; behaviour when the device is locked mid-write.
3. **Testability.** Secure Enclave can't be fully exercised on the simulator — decide the
   split: unit-test the key-lifecycle logic where possible, and mark the device-only parts
   `ready-for-human` for on-device verification.

## Sketch (post-triage)

- A Swift `KeyStore` (generate-or-fetch the hex key from Keychain) feeding `Store.open`.
- Set `NSFileProtectionComplete` on the DB file; wrong-key path already fails closed in core.
- Tests: key persists across launches (round-trip via Keychain); a fresh install generates a
  new key; the store opens with the fetched key and rejects a wrong one (core contract).

## Deferred
Cross-device key sync (Pro/later); key rotation/re-encrypt; passphrase/recovery flows.
