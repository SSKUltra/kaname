# Spec — Encrypted on-device store (kaname-core)

Status: ready-for-agent

> Feature: the P2+ **encrypted local store** the whole engine was carved away from — an
> SQLCipher-encrypted SQLite owned by the Rust core, keyed from the iOS Keychain. Design of
> record: `docs/kaname-ios-plan.md` (§ "Data model + persistence", P1/P2); Constitution
> `v2.0.0` (III "Encrypted at rest": SQLCipher, key in Keychain/Secure Enclave, never
> exported). Governs over any other guidance.

## Problem Statement

Every deterministic engine we've shipped — the 10 statement readers, balance-chain,
reconciliation, cross-source de-dup, coverage, transfer detection, and now the
categorization stack — is **pure over passed-in facts** and persists nothing. There is
nowhere on the device to keep my accounts, transactions and categories, and nothing to
**supply** the facts those engines read (the merchant "memory" and source-category map that
feed categorization, the rows dedup/coverage/transfer compare) or to **save** their results
(`transaction.category_id`, transfer groups). Because it's financial data, it must be
**encrypted at rest** with a key that never leaves the device.

## Solution

Kaname keeps all of a person's financial data in a single **SQLCipher-encrypted SQLite
database owned by the Rust core** (`kaname-core`, via `rusqlite`). The **iOS Keychain
(Secure Enclave-backed) generates and holds a 256-bit key** and hands it to the core to open
the database; the core sets the key, runs forward-only schema **migrations**, reads and
writes rows, and **never persists or exports the key**. The database file is marked
`NSFileProtectionComplete`. Nothing about this touches the network — it is enforced by the
same CI privacy-egress gate as the rest of the free core.

This first slice ships the **encrypted-store bootstrap**: open/create the encrypted DB with
a caller-supplied key, apply **schema v1** (accounts, categories seeded from the ported 23
defaults, transactions), and prove a transaction **round-trips** across the UniFFI bridge —
with a **wrong key failing** to open. It deliberately does **not** wire the engines to the
store yet; that follows once the encrypted foundation is proven.

## User Stories

1. As a Kaname user, I want my financial data stored **encrypted at rest** on my device, so that a lost or stolen phone doesn't expose my accounts and transactions.
2. As a Kaname user, I want the encryption key held in my device's **Keychain / Secure Enclave** and never exported, so that only my device (and my unlock) can open the data.
3. As a Kaname user, I want the database to **fail closed** — a wrong or missing key simply cannot open it — so that the encryption is real, not cosmetic.
4. As a Kaname user, I want my imported **transactions, accounts and categories** persisted, so that they're still there when I reopen the app.
5. As a Kaname user, I want the **23 default categories** available in a fresh database, so that categorization has somewhere to point on day one.
6. As a Kaname user, I want the store to keep working across app updates via **migrations**, so that a new schema never loses or corrupts my existing data.
7. As a Kaname user, I want persistence to stay **100% on-device with zero network**, so that saving my data never phones home (free/core, Constitution I).
8. As a developer, I want the **Rust core to own the database** (open, migrate, CRUD) behind a small stateful FFI object, so that persistence logic is shared and testable, not reimplemented per platform.
9. As a developer, I want money and dates to cross the FFI as **exact strings** (`Decimal` / ISO-8601), never floats, so that no precision is lost on the way to storage (Constitution IV).
10. As a developer, I want store operations to return **typed errors** (not panics) — including "wrong key" and "migration failed" — so that the platform can react gracefully.
11. As a maintainer, I want SQLCipher built **without OpenSSL** — CommonCrypto on iOS, LibTomCrypt on Linux/CI — so that the privacy-egress denylist (`openssl`/`openssl-sys`) stays strict and the dependency graph stays small.
12. As a maintainer, I want the encrypted store proven by **behavioural tests** (round-trip, wrong-key, migration idempotency, seeded categories) rather than a web byte-for-byte port, since the on-device SQLite schema is fresh design, not a port of the web's Postgres.

## Implementation Decisions

- **Core owns the DB.** A new `store` module in `kaname-core` wraps `rusqlite`. It is exposed
  over UniFFI as a **stateful object** (`#[derive(uniffi::Object)]` — the engine's first, vs
  the pure functions so far) with methods that open the DB and read/write rows. All SQL lives
  in the core; the platform only supplies the key + file path and calls methods.
- **Crypto backend: no OpenSSL** (chosen; see Constitution I + the privacy gate). Build
  SQLCipher with **CommonCrypto** on Apple (`SQLCIPHER_CRYPTO_CC`, links `Security`) and
  **LibTomCrypt** on Linux/CI (`SQLCIPHER_CRYPTO_LIBTOMCRYPT`). Do **not** use
  `rusqlite`'s `bundled-sqlcipher-vendored-openssl` (it pulls `openssl-sys`, which the
  privacy-egress audit denylists).
- **Key management split.** The **iOS Keychain (Secure Enclave)** generates and stores a
  256-bit key and marks the file `NSFileProtectionComplete` (platform). The core's
  `Store::open(path, key)` sets the key (SQLCipher `PRAGMA key` / raw-key form) and verifies
  it by touching the schema; a wrong key yields a typed `StoreError`, never a panic. The core
  **never persists or logs the key**.
- **Schema v1 (minimal, real foundation).** `schema_migrations` (or `PRAGMA user_version`)
  for forward-only migrations; **`accounts`**; **`categories`** seeded from the ported
  `default_categories()` (23 rows: code, name, classification); **`transactions`** (a core
  column subset: id, account_id, date, description_raw, amount, direction, currency,
  category_id?, categorised_by?, is_deleted, created_at, updated_at). Money is stored as a
  **base-10 TEXT** `Decimal`, dates as **ISO-8601 TEXT**, direction as `'Debit'`/`'Credit'`
  — never floats.
- **Migrations are forward-only and idempotent.** Re-opening an up-to-date DB is a no-op;
  each migration bumps the version transactionally.
- **Typed errors.** A `StoreError` (`uniffi::Error`) — the crate's first error enum —
  covers open/key/migration/SQL failures with meaningful messages.
- **One slice.** The bootstrap (open + key + schema v1 + migrations + a transaction/account
  round-trip + seeded categories) ships together; engine wiring is later slices.

## Testing Decisions

- **Behavioural, not byte-for-byte.** The SQLite schema is fresh design (not a port of the
  web Postgres models), so there is **no golden web fixture** here. Prove behaviour:
  - **Rust unit/integration tests** (temp file DB): open→migrate→insert account+transaction→
    read back exactly; **wrong key fails** to open (typed error, no panic); **migration
    idempotency** (open twice → same version, data intact); **seeded categories** = the 23
    defaults with the right classifications.
  - **One Swift bridge test** (`ios/Tests/StoreTests.swift`): open a `Store` over UniFFI at a
    temp path with a Swift-supplied key, round-trip a transaction, and confirm a wrong key
    throws. Prior art: the existing `*Tests.swift` bridge suites.
- **Privacy-egress stays green.** `make core-privacy-audit` must still pass — assert the
  SQLCipher/LibTomCrypt path pulls **no** networking crate and **no** `openssl-sys`.
- **Determinism.** Given a key + path, operations are deterministic; the core never reads the
  wall-clock for logic (timestamps are explicit inputs or a single injected "now").

## Out of Scope

- **Wiring the engines to the store** — feeding categorize/dedup/coverage/transfer from
  persisted rows and saving their results (`category_id`, `transfer_group_id`). Own slices.
- **The full schema** (~38 web models: tags, budgets, import batches, audit logs, merchant
  aliases, source-category mappings as tables, …). Added as the features that need them land.
- **Learning / write-back** (turning a manual correction into a merchant-map/source-map row).
- **The Secure Enclave key ceremony details** and biometric gating (platform; this slice
  fixes only the FFI contract the platform calls).
- **Export / backup / cloud sync** (Pro/later).
- **Tags and budgets.**

## Further Notes

- **De-risk the build first.** The hard part is not the SQL — it's compiling/linking
  SQLCipher **without OpenSSL** across `aarch64-apple-ios`, `aarch64-apple-ios-sim`,
  `x86_64-apple-ios` (CommonCrypto, `Security.framework`) **and** `x86_64/aarch64 Linux` CI
  (LibTomCrypt), inside the static-lib xcframework pipeline (`core/scripts/build-xcframework.sh`)
  and Tuist (`ios/Project.swift`), with `ci.yml` still green. **Task 1 is a build spike**:
  get `rusqlite` + SQLCipher + LibTomCrypt to compile and open an encrypted DB on Linux with
  the privacy audit green, and the same on an iOS target, before any schema/FFI work.
- **The store is stateful** — the first `uniffi::Object` in the crate. Confirm the UniFFI
  0.32 object + error-enum ergonomics early (a throwaway `Store::open` + one method) so the
  bridge shape is settled before the schema grows.
- **Money/date custom types already cross the FFI** as exact strings (`ffi.rs` `Decimal`/
  `NaiveDate` custom types) — reuse them for row columns.
- **Local Verification Gate** (Constitution): `make core-lint && make core-test &&
  make core-privacy-audit`, then `make lint && make ios-gen && make ios-test`, all green
  before the PR.
