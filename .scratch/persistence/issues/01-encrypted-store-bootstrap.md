# 01 — Encrypted store bootstrap (SQLCipher, no OpenSSL)

**What to build:** the **encrypted-store foundation** in `kaname-core` — a stateful
`Store` object (UniFFI) that opens/creates an **SQLCipher-encrypted SQLite** database at a
caller-supplied path with a caller-supplied **key**, applies **schema v1** (accounts,
categories seeded from the 23 ported defaults, transactions) via a forward-only migration
runner, and round-trips a transaction across the Rust↔Swift bridge. A **wrong key fails to
open** (typed error, no panic). SQLCipher is built **without OpenSSL** — CommonCrypto on
iOS, LibTomCrypt on Linux/CI — so the privacy-egress gate stays strict. Design of record:
`.scratch/persistence/spec.md`; `docs/kaname-ios-plan.md` (persistence); Constitution III.

**Blocked by:** None — can start immediately.

**Status:** resolved (shipped — PR #18: schema v1 + `Store`, migrations, typed `StoreError`, wrong-key fail-closed)

Interface shape (to be confirmed by the build spike):

- `Store::open(path: String, key: /* 32-byte key, hex String */) -> Result<Store, StoreError>`
- `store.insert_account(...) -> Result<String, StoreError>` (returns id)
- `store.insert_transaction(txn) -> Result<String, StoreError>`
- `store.list_transactions(account_id) -> Result<Vec<StoredTransaction>, StoreError>`
- `store.list_categories() -> Result<Vec<Category>, StoreError>` (the seeded 23)
- `StoreError = OpenFailed | WrongKey | Migration{..} | Sql{..}` (`uniffi::Error`)
- Money crosses as a base-10 `Decimal` string; dates as ISO-8601; direction `Debit`/`Credit`.

**Acceptance criteria**

- [ ] **Build spike first (de-risk):** `rusqlite` + SQLCipher compiles and opens an encrypted DB with **LibTomCrypt** on Linux/CI and **CommonCrypto** on an iOS target — **no `openssl-sys`** in the graph; `make core-privacy-audit` stays green.
- [ ] `Store::open(path, key)` creates/opens an SQLCipher-encrypted SQLite; the key is set via SQLCipher and **never persisted or logged** by the core.
- [ ] **Wrong key fails closed** — opening an existing encrypted DB with the wrong key returns `StoreError::WrongKey` (or equivalent), never a panic or a readable DB.
- [ ] A **forward-only migration runner** applies **schema v1** and is **idempotent** (re-open ⇒ no-op, same version, data intact).
- [ ] **Schema v1** creates `accounts`, `categories`, `transactions`; **categories are seeded from `default_categories()`** (23 rows: code + name + classification).
- [ ] **Round-trip:** insert an account + a transaction, read them back **exactly** — money as `Decimal` (no float), date as `NaiveDate`, direction preserved.
- [ ] Store operations return typed `StoreError` (a `uniffi::Error`) — no `unwrap`/`panic` on the FFI path.
- [ ] The `Store` is exposed over UniFFI as a `#[derive(uniffi::Object)]`; **one Swift bridge test** (`ios/Tests/StoreTests.swift`) opens a store at a temp path with a Swift-supplied key, round-trips a transaction, and asserts a wrong key throws (prior art: existing `*Tests.swift`).
- [ ] **Rust tests** (temp DB): open/migrate/round-trip, wrong-key, migration idempotency, seeded-categories count + classifications.
- [ ] Money/date reuse the existing `ffi.rs` `Decimal`/`NaiveDate` custom types (exact strings, never floats).
- [ ] Build integration updated as needed: `core/scripts/build-xcframework.sh`, `ios/Project.swift` (link `Security.framework` for CommonCrypto), and `.github/workflows/ci.yml` (LibTomCrypt on the Linux job) — all green.
- [ ] The **Local Verification Gate** passes: `make core-lint && make core-test && make core-privacy-audit`, then `make lint && make ios-gen && make ios-test`.
- [ ] Shipped per the per-slice workflow (spec → plan → tasks → implement), CI green.

**Explicitly deferred (later slices):** wiring categorize/dedup/coverage/transfer to the
store and saving their results; the full ~38-table schema; learning/write-back; the Secure
Enclave key ceremony + biometric gating; export/backup/sync; tags/budgets.
