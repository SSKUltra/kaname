# Kaname — task pickup (START HERE)

> **Read order:** this file → `.specify/memory/constitution.md` (wins over everything) →
> the feature you're picking up under `.scratch/<slug>/` (its `spec.md` + `issues/`) →
> `docs/kaname-ios-plan.md` (architecture + P0–P6) → `.github/copilot-instructions.md`.
> Durable "why" reference: `docs/HANDOFF.md` (original scaffold) + `docs/adr/`.

Kaname (要, "the key") is the **privacy-first, local-first** open-source iOS client
(Rust core + SwiftUI) for personal finance, by **BeaconBrain**. The free/core engine runs
**100% on-device with zero network I/O**; premium (AI/AA/sync) is server-gated elsewhere.

---

## 1. Where work is tracked — the `.scratch/` convention

**Tasks live as local markdown in this folder** (git-tracked), one directory per feature
(see `docs/agents/issue-tracker.md`):

- Spec: `.scratch/<feature-slug>/spec.md`
- Tickets: `.scratch/<feature-slug>/issues/<NN>-<slug>.md` (numbered from `01`; one file
  per ticket, never a combined file). A `Status:` line records
  `needs-triage`/`needs-info`/`ready-for-agent`/`ready-for-human`/`wontfix`
  (`docs/agents/triage-labels.md`).

To pick up a task: scan `.scratch/<slug>/issues/` for the lowest-numbered open,
unblocked, `ready-for-agent` ticket, read its `spec.md`, and implement.

**Current feature dirs:**
- `.scratch/categorization/` — deterministic categorization stack. **Shipped.**
- `.scratch/persistence/` — encrypted on-device store. `spec.md` = design of record;
  `issues/01-encrypted-store-bootstrap.md` (slice 01), `issues/02-categorization-write-back.md`
  (slice 02) and `issues/03-transfer-persistence.md` (slice 03) all **shipped**
  (`Status: resolved`). Later slices (dedup/coverage persistence, the deferred
  transfer→category assignment, the key ceremony, …) will be new `issues/NN-*.md` here.

---

## 2. What's DONE

| Layer | Status |
|---|---|
| **P0** bootstrap + gates | ✅ toolchain, CI, privacy-egress gate |
| **P1** UniFFI Rust↔Swift bridge | ✅ `engine_version`, `normalize_transaction`, Decimal/NaiveDate custom types |
| **P2 credit-card readers (6)** | ✅ ICICI, HDFC (2 layouts), SBI, Yes, Federal/Scapia, IOB |
| **P2 bank-account ledger readers (4)** | ✅ ICICI, HDFC (2 layouts), Federal (2 templates), AU |
| **Balance-chain integrity** | ✅ `balance_chain::check` → Reconciled/NeedsReview + suspects |
| **CC reconciliation** | ✅ `reconcile::reconcile` (printed totals → opening/closing fallback → neutral) |
| **Cross-source de-dup** | ✅ `dedup::cross_source_duplicates` (canonical + fuzzy, hand-rolled Jaro-Winkler) |
| **Coverage map** | ✅ `coverage::compute_coverage` (rolling-24-month GAP/PARTIAL/COVERED; clock-free) |
| **Transfer detection** | ✅ `transfer::detect_transfers` (outflow-anchored greedy pairing; ±1 day/±₹1) |
| **Categorization stack** | ✅ `categorize` (CC rules → T1 source-map → T2 merchant-map → T3 rules; T4/LLM excluded); `default_categories()` = 23 builtins |
| **Encrypted store bootstrap** | ✅ `store::Store` (uniffi::Object) — SQLCipher-encrypted SQLite, schema v1 (accounts / seeded categories / transactions), forward-only migrations, wrong-key fail-closed. **No OpenSSL** (CommonCrypto on Apple, LibTomCrypt on Linux/CI). PR #18 |
| **Categorization write-back** | ✅ schema v2 — `merchant_map`/`source_category_map`/`rules` facts + `transactions.source_category`; `store.categorize_account` runs the pure stack over stored rows and persists `category_id`/`categorised_by`. PR #20 |
| **Transfer persistence** | ✅ schema v3 — `transactions.is_transfer` + shared `transfer_group_id`; `store.detect_transfers` (first **cross-account** op) tags both legs of each pair, idempotent (guarded UPDATE). **Tag-only** — category assignment + categorize/transfer precedence deferred. PR #22 |
| **Golden-parity harness** | ✅ `tests/parity.rs` (per-bank + reconcile/dedup/coverage/transfer) |
| **Privacy-egress gate** | ✅ `make core-privacy-audit` (CI-enforced; denylists networking + `openssl`/`openssl-sys`) |

Tests (current): ≈167 Rust (unit + parity + store) + 45 Swift across 17 suites; 0 network
deps. `main` at the transfer-persistence merge: `b846902`.

**Engine source** (`core/crates/kaname-core/src/`): the 10 readers + shared seams under
`statement/`; `dedup.rs`, `coverage.rs`, `transfer.rs`, `categorize.rs`, `store.rs`;
`ffi.rs` (UniFFI boundary + Decimal/NaiveDate custom types); `model.rs`; `lib.rs`.

---

## 3. What's NEXT (candidate slices — user checkpoints at slice boundaries)

The deterministic engine + the encrypted-store foundation are in. Remaining candidates,
roughly in dependency order (each becomes a `.scratch/<slug>/issues/NN-*.md`):

1. **Engine→store wiring: dedup + coverage persistence** — the remaining half of the store's
   stated next step (`persistence/spec.md` "Out of Scope": *"feeding
   categorize/dedup/coverage/transfer from persisted rows and saving their results"*).
   Categorization write-back (slice 02) and **transfer persistence (slice 03)** are **done**;
   what's left is **dedup** (persist statements/transactions as the facts it compares + save
   supersede state) and **coverage** (needs a **new `statements` table** + transaction
   provenance — `from_full_statement`/`statement_id` — that `compute_coverage` reads).
2. **Deferred from slice 03: transfer→category assignment** — assign Self Transfer /
   Credit Card Bill Payment to tagged transfers and settle the **categorize-vs-transfer
   precedence** (which engine wins; don't clobber a transfer tag on `categorize_account`
   re-run). Small, but its own slice by the tag-only decision.
3. **iOS Keychain / Secure Enclave key ceremony** — generate + hold the 256-bit key
   on-device, mark the DB `NSFileProtectionComplete`. The store's FFI contract is fixed;
   this is the platform half. (Deferred by `persistence/issues/01`.)
4. **P3 — Core SwiftUI app** — onboarding → import (PDFKit → readers) → transaction list →
   categorize → dashboard. The coverage map + reconcile/balance-chain verdicts are the
   first natural UI surfaces (apply the `make-interfaces-feel-better` skill;
   `gem-designer-mobile` agent available).

---

## 4. Per-slice workflow (proven on every slice)

Spec Kit, one slice per PR: `speckit.specify` → `speckit.plan` → `speckit.tasks` →
implement directly (faster once the design is locked). For engine slices, **capture ground
truth by RUNNING the live web engine** (`/Users/ssk/Projects/finance-tracker-phase/backend`,
`.venv/bin/python`) — never real data; fixtures stay synthetic. Test-first
(RED → GREEN → `make core-xcframework` → Swift GREEN). Then the full gate → 2 commits
(engine+fixtures+parity; Swift test) → PR → watch CI → `merge --rebase --delete-branch`
→ `git remote prune origin`. Surface sub-agent decisions back to the user; don't self-answer.

---

## 5. Local Verification Gate (MANDATORY before every PR)

```
export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"   # cargo is NOT on the default PATH
make core-lint          # cargo fmt --check + clippy -D warnings
make core-test          # cargo test (unit + parity + store)
make core-privacy-audit # no networking crate / no openssl in the shipped graph
make lint               # swiftlint --strict + swift-format lint + core-lint
make ios-gen            # tuist generate (depends on core-xcframework)
make ios-test           # simulator build + Swift Testing (sim named "iPhone 16")
```
CI (`.github/workflows/ci.yml`): Rust on `ubuntu-latest`, iOS on `macos-15`. Docs-only
changes don't need linting/building/testing.

---

## 6. Environment & gotchas (save yourself the pain)

- **Toolchain PATH:** `cargo`/`rustup` live in `~/.cargo/bin`, NOT on the default PATH.
  Prefix every shell: `export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"`.
- **Cargo workspace is under `core/`** — `cargo` needs `cd core` (or use `make`).
- **SQLCipher is built WITHOUT OpenSSL** (Constitution I; CI-enforced). `bundled-sqlcipher`
  auto-selects **CommonCrypto** on Apple (links `Security`/`CoreFoundation` — added in
  `ios/Project.swift`). On **Linux/CI** we force **LibTomCrypt**:
  `LIBSQLITE3_FLAGS=-DSQLCIPHER_CRYPTO_LIBTOMCRYPT` (set by the `Makefile` Linux guard +
  the `ci.yml` core job, which also `apt-get install libtomcrypt-dev`), and
  `core/crates/kaname-core/build.rs` links `tomcrypt` + shadows the `-lcrypto`
  libsqlite3-sys hard-codes with an **empty stub archive** so zero OpenSSL links. Do **not**
  switch to `bundled-sqlcipher-vendored-openssl` (the privacy audit denylists `openssl-sys`).
- **`build-xcframework.sh` pins `IPHONEOS_DEPLOYMENT_TARGET=18.0`** so SQLCipher's
  `sqlite3.o` (which references `___chkstk_darwin`) links on-device — keep it aligned with
  the app's Tuist deployment target.
- **iOS simulator:** local `make ios-test` targets a sim named **"iPhone 16"** (create once:
  `xcrun simctl create "iPhone 16" "iPhone 16"`). CI selects one **by UDID**
  (`.github/scripts/select-ios-simulator.sh`) — never re-hardcode a device name in CI.
- **CI iOS job MUST stay on `macos-15`** (Homebrew `tuist` cask breaks on `macos-14`).
- **swift-format `[Spacing]` rejects trailing inline comments** after code — put comments on
  their own line above the statement.
- **`DATE_FORMATS` order matters** (`common.rs`): `%d/%m/%y` before `%d/%m/%Y`. chrono's
  `%b` is case-insensitive.
- **Money is never a float:** `rust_decimal::Decimal` in Rust, crosses UniFFI as an exact
  base-10 `String`, surfaces as `Foundation.Decimal` in Swift. Direction from a Dr/Cr marker
  or balance delta — never the amount's sign.
- **PDF text extraction is NATIVE** (iOS PDFKit); the core never opens a PDF.
- **UniFFI 0.32** proc-macro (no UDL). `make core-xcframework` rebuilds the xcframework +
  regenerates `ios/Generated/` (git-ignored) — run it **before** `tuist generate` whenever
  the FFI surface changes.
- **rustfmt reformats your edits:** after an `edit`, run `make core-fmt` then re-view before
  the next `edit` (old_str may no longer match).
- **`update-agent-context.sh` typo:** on `speckit.plan`, it writes "iOS 18 targe" into
  `.github/copilot-instructions.md`. Fix before committing the plan:
  `sed -i '' 's/iOS 18 targe$/iOS 18 target/g; s/iOS 18 targe /iOS 18 target /g' .github/copilot-instructions.md`.

---

## 7. Key reusable seams

- `line_reader.rs` — `LineReaderConfig` + `read_lines` + `claims` (every CC reader is one config).
- `ledger_reader.rs` — `LedgerReaderConfig` + `read_ledger_lines` + `claims_ledger`
  (direction from balance delta; every bank reader is one config).
- `balance_chain.rs` — `check(&ParsedStatement) -> ChainResult`.
- `reconcile.rs` — `reconcile(&ParsedStatement) -> ReconcileResult` (printed totals →
  opening/closing fallback → neutral `None`; ₹1.00 tolerance).
- `dedup.rs` — `cross_source_duplicates`; `normalize_narration` (≠ `normalize_description`).
- `coverage.rs` — `compute_coverage(today, …)` + `month_window` (clock-free; `today` is a param).
- `transfer.rs` — `detect_transfers(&[TransferInput]) -> Vec<TransferPair>`.
- `categorize.rs` — `categorize` / `categorize_batch` (first-wins stack), `default_categories()`
  (23 builtins: code + name + `Classification`), `prepare_merchants`/`prepare_rules`.
- `store.rs` — `Store::open(path, key)` (SQLCipher, forward-only `PRAGMA user_version`
  migrations to **schema v3**, `StoreError` typed errors, wrong-key fail-closed);
  `insert_account`/`insert_transaction`/`list_*`; the categorization facts
  (`insert_merchant_rule`/`insert_source_category_mapping`/`insert_rule`/`insert_category`
  + their `list_*`); `categorize_account` (runs the pure stack over stored rows and
  persists `category_id`/`categorised_by`); and `detect_transfers` (cross-account — runs the
  pure matcher over stored rows and tags both legs `is_transfer`/`transfer_group_id`).
  **Timestamps are explicit inputs** (the core reads no wall-clock); the platform owns the
  Keychain key + file path + NSFileProtection.
- `common.rs` / `polarity.rs` — `parse_amount`/`parse_date`/`find_last4`/…; `classify`.
- `tests/parity.rs` — the golden harness (readers + reconcile/dedup/coverage/transfer).

---

## 8. Repo map

```
core/crates/kaname-core/   Rust engine (kaname-core)
  src/statement/           the 10 readers + shared seams
  src/{model,dedup,coverage,transfer,categorize,store,ffi,lib}.rs
  build.rs                 non-Apple SQLCipher/LibTomCrypt linking (no OpenSSL)
  tests/{parity,store,store_categorization}.rs  golden harness + store behavioural tests
ios/                       SwiftUI app (Tuist). Tests/*Tests.swift = per-bank + engine + store bridge tests
fixtures/<bank>/<kind>/    synthetic golden vectors (NO real data — Constitution I)
.scratch/<slug>/           THE task tracker: spec.md + issues/NN-*.md   ← pick up work here
.specify/memory/constitution.md   THE rules (privacy non-negotiable; wins over all)
docs/kaname-ios-plan.md    architecture + P0–P6 (durable)
docs/adr/                  architecture decision records (durable)
docs/HANDOFF.md            original scaffold handoff (historical "why")
docs/agents/               issue-tracker / triage-labels / domain conventions
```

---

## 9. The web engine (source of truth for porting — read-only)

`/Users/ssk/Projects/finance-tracker-phase/backend/` (working `.venv/bin/python`).
Ingestion under `app/services/ingestion/`. Always capture ground truth by RUNNING the real
web code, then port to Rust and prove parity. **Fixtures must be synthetic/redacted.**
