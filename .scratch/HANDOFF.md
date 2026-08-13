# Kaname — task pickup (START HERE)

> **Read order:** this file → `.specify/memory/constitution.md` (wins over everything) →
> **the feature you're picking up (§3 names it)** → `docs/kaname-ios-plan.md` (architecture +
> P0–P6) → `.github/copilot-instructions.md`.
> Durable "why" reference: `docs/HANDOFF.md` (original scaffold) + `docs/adr/`.

Kaname (要, "the key") is the **privacy-first, local-first** open-source iOS client
(Rust core + SwiftUI) for personal finance, by **BeaconBrain**. The free/core engine runs
**100% on-device with zero network I/O**; premium (AI/AA/sync) is server-gated elsewhere.

---

## 1. Where work is tracked — TWO trackers, know which one

**→ §3 always names the live one. Read it before scanning either.**

**A. `specs/NNN-<slug>/` — Spec Kit. This is where current work lives.** Every UI/engine
slice from 016 onward is specified here: `spec.md` → `plan.md` → `research.md` →
`contracts/` → **`tasks.md`** (the executable queue, checkbox per task) → `quickstart.md`.
A feature here is picked up by working `tasks.md` in order, respecting its PR split.

**B. `.scratch/<feature-slug>/` — the older local ticket convention** (see
`docs/agents/issue-tracker.md`): `spec.md` plus `issues/<NN>-<slug>.md`, each with a
`Status:` line (`needs-triage`/`needs-info`/`ready-for-agent`/`ready-for-human`/`wontfix`,
per `docs/agents/triage-labels.md`). Used by `.scratch/categorization/` and
`.scratch/persistence/` — **both fully resolved; nothing open there.** Kept for history.

⚠️ **Don't conclude "no work left" from an empty `.scratch/` queue** — that is the older
tracker. Check §3.

---

## 2. What exists — read the source, don't cache it here

A hand-maintained status table drifts every slice, so this section points at the sources of
truth instead of copying them:

- **The engine + store API that's built** → §7 "Key reusable seams" (names the functions,
  points at the code); the P0–P6 phase map → `docs/kaname-ios-plan.md`.
- **Which slices shipped** → the `Status: resolved` line in each `.scratch/*/issues/NN-*.md`,
  the unchecked boxes in the live `specs/NNN-*/tasks.md`, and the merged PRs
  (`gh pr list --state merged`).
- **Test counts / current `main`** → `make core-test` && `make ios-test`; `git rev-parse main`.
- **Source layout** → §8 repo map, or `ls core/crates/kaname-core/src/`.

Orientation in one line: the deterministic engine (10 readers + balance-chain, reconcile,
dedup, coverage, transfer, categorize), the UniFFI bridge, and the SQLCipher encrypted store
are all in and fully wired together — **P2 is done; P3 (the SwiftUI app) is now the work**,
and the app's first real screen — the statement-import flow in `ios/Sources/Import/` plus
`RootView` — has landed with 016 PR C (§3).

---

## 3. What's next

**Right now: implement `016-statement-import-vertical` — PR A, B and C are MERGED; start
with PR D.**

P3 (the Core SwiftUI app) has begun. Its first slice is fully specified, planned and
broken into tasks; **do not re-run `speckit.specify`/`plan`/`tasks` for it** — the design is
locked and its four product decisions are settled (see the spec's `## Clarifications`).

Read, in order:
`specs/016-statement-import-vertical/spec.md` → `plan.md` → `research.md` (R1–R13, the
decisions with source-line evidence) → `contracts/` → **`tasks.md`** (136 tasks, the actual
queue) → `quickstart.md` (build order + smoke test).

**It ships as five PRs, not one** (rationale + task ranges in `tasks.md` § "Recommended PR
split"). Take the lowest unstarted one — **that is now PR D**:

| PR | Tasks | What | Status |
|----|-------|------|--------|
| **A** | T001, T006–T017, T035–T046 | Store hardening: the ⚠️ deadlock refactor, schema v6, atomic `import_statement` | ✅ **merged** (#31) |
| **B** | T003, T005, T018–T034 | The issuer dispatcher (`detect_issuer` / `read_statement`) | ✅ **merged** (#32) |
| **C** | T002, T004, T047–T069 | 🎯 The MVP vertical — first demoable build | ✅ **merged** (#33) |
| **D** | T070–T097 | Honest failures & account attribution (US2–US4) | ⬅️ **NEXT** |
| **E** | T098–T136 | Trust, responsiveness, front door (US5–US7 + polish) | |

**State of `main` after A + B + C** (verified `ee0f9a7`, full gate green):
`make core-test` = **221 passing / 0 failing**; `make ios-test` = **61 tests / 21 suites**;
`make lint` = 0 violations / 32 files; `make import-audit` + `make core-privacy-audit` OK.
**The MVP vertical is live** — the app is no longer a placeholder: `ios/Sources/Import/`
holds `PDFKitStatementTextExtractor`, the `ImportService` actor, `ImportViewModel`,
`ImportSummaryView` and `ImportFailureView`, and `RootView` is the real
pick → progress → summary flow.

**PR D starts here** (`tasks.md` Phase 4 → 6): T070–T071 RED → T072–T078 (US2, the
issuer-agnostic guarantees) → T079–T090 (US3, honest failures) → **T137–T139 (the extraction
fidelity gap found while smoke-testing PR C — see below)** → T091–T097 (US4, the FR-024
account-attribution matrix + `AccountPickerView`). Note that US1 deliberately implements only
the unambiguous account cases — exactly one candidate attaches, zero creates — so **T093 is
where the `nil`-last-4 and ≥2-candidate branches finally get their human decision**; until
then the code must never silently guess.

> ⚠️ **Known gap, highest-value thing in PR D — the silent empty import.** The ten readers are
> fixture-locked to the **web engine's** extraction (pdfplumber); iOS extracts with **PDFKit**,
> and nothing yet proves the two agree. Smoke-testing PR C against a differently-generated PDF
> found PDFKit **merging adjacent lines**: the document was still identified as HDFC, but zero
> rows parsed and the app reported *"0 transactions"* — a success under FR-020. A person whose
> statement PDFKit merges would be told they had no spending. **T137** is the parity proof
> (render fixture lines → PDF → extract → parse → must equal parsing the lines directly);
> **T138** makes the empty result honest. A known-good synthetic demo PDF can be regenerated
> the way T137 does it — render fixture lines with `UIGraphicsPDFRenderer` at ~22pt line
> spacing (tighter spacing is what triggers the merge).

> ⚠️ **Still live in PR D:** never call a bare `tuist generate` — always `make ios-gen` /
> `make ios-test`, and run `make core-xcframework` first whenever the FFI surface moves.
> `make import-audit` is the mechanical SC-004 proof that **zero networking symbols** exist
> under `ios/Sources/Import/` — run it on every PR that touches that directory. The only
> engine-supplied string allowed on screen is `Issuer.display_name` (FR-033/FR-034); the copy
> deck for every failure and integrity state lives in `ios/Sources/Import/ImportModels.swift`.
> The T053/T055 design-gate outcomes (Liquid Glass application points, the four settled
> state-machine edges) are recorded in `tasks.md` § Phase 2.5 — read them before adding UI.

> ⚠️ **Worktree gotcha (learned the hard way):** Tuist cannot resolve its root inside a
> `git worktree` (there `.git` is a *file*, not a directory), so `make ios-gen` fails there.
> Do Swift work in the primary checkout. Adding an `ios/Tuist.swift` "fixes" it but changes
> root resolution for everyone — don't commit one.

**After 016**, the rest of P3 (transaction list, dashboard, budgets, tags, search, export —
see the spec's Out of Scope) gets specified slice by slice via `speckit.specify`.

The older `.scratch/persistence/` and `.scratch/categorization/` queues are **fully
resolved** — the engine→store wiring and the Keychain key ceremony all shipped. Nothing is
open there.

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
make import-audit       # no networking symbol under ios/Sources/Import (Swift half of the same gate)
make lint               # swiftlint --strict + swift-format lint + core-lint
make ios-gen            # tuist generate (depends on core-xcframework)
make ios-test           # simulator build + Swift Testing (sim named "iPhone 16")
```
CI (`.github/workflows/ci.yml`): Rust on `ubuntu-latest`, iOS on `macos-26`. Docs-only
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
- **`build-xcframework.sh` pins `IPHONEOS_DEPLOYMENT_TARGET=26.0`** so SQLCipher's
  `sqlite3.o` (which references `___chkstk_darwin`) links on-device — keep it aligned with
  the app's Tuist deployment target.
- **Deployment target is iOS 26.0** (`ios/Project.swift`, all three targets). Chosen so
  **Liquid Glass is unconditional** — never write `#available(iOS 26, *)` or a
  `.ultraThinMaterial` fallback. See the `swiftui-liquid-glass` skill.
- **iOS simulator:** local `make ios-test` targets a sim named **"iPhone 16"** (create once:
  `xcrun simctl create "iPhone 16" "iPhone 16"`). CI selects one **by UDID**
  (`.github/scripts/select-ios-simulator.sh`) — never re-hardcode a device name in CI.
- **CI iOS job runs on `macos-26`** and selects the newest **Xcode 26.x** — the iOS 26 SDK is
  required by the deployment target. Never drop below `macos-15` (Homebrew `tuist` cask breaks
  on `macos-14`).
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
- `statement/registry.rs` — the ten-entry issuer registry (private `REGISTRY`, no bank list is
  ever exported — FR-012). `detect_issuer(full_text) -> Option<Issuer>` picks the minimum under
  `(kind_rank, id)` with **ledger before card**, so the 3 doubly-claimed fixtures resolve to the
  bank reader (pinned by `tests/dispatcher.rs`). `read_statement(issuer, lines, full_text,
  line_words)` is the single parse front door — cards ignore `line_words`; ledgers get only the
  anchor row's geometry via `ledger_reader::first_anchor_index`. The ten legacy
  `read_<bank>_statement` exports still exist and are unchanged.
- `store.rs` — `Store::open(path, key)` (SQLCipher, forward-only `PRAGMA user_version`
  migrations to **schema v6**, `StoreError` typed errors, wrong-key fail-closed);
  `insert_account`/`insert_transaction`/`list_*`; the categorization facts
  (`insert_merchant_rule`/`insert_source_category_mapping`/`insert_rule`/`insert_category`
  + their `list_*`); `categorize_account` (runs the pure stack over stored rows and
  persists `category_id`/`categorised_by`); and `detect_transfers` (cross-account — runs the
  pure matcher over stored rows and tags both legs `is_transfer`/`transfer_group_id`).
  **⚠️ `Store` methods take a non-reentrant `std::sync::Mutex`.** Any *composite* write must
  call the transaction-scoped helpers `categorize_account_in(tx, account_id)` /
  `find_duplicates_in(tx)` — **never** the public `categorize_account` / `find_duplicates`,
  which re-lock and deadlock. `tests/store_import.rs` holds a 10s-timeout guard that fails
  fast and legibly if that rule is broken.
  `Store::import_statement(ImportRequest) -> ImportOutcome` is the atomic composite: one
  transaction doing resolve-or-create account → `statements` row → transactions →
  `categorize_account_in` → `find_duplicates_in` → COMMIT, rolling back entirely on failure.
  No `statements` row is written when there is neither a period nor a transaction (R6).
  **Timestamps are explicit inputs** (the core reads no wall-clock); the platform owns the
  Keychain key + file path + NSFileProtection.
- `common.rs` / `polarity.rs` — `parse_amount`/`parse_date`/`find_last4`/…; `classify`.
- `ios/Sources/Import/` — the platform vertical (016 PR C). `StatementTextExtractor` is the
  PDFKit seam (a protocol, so the pipeline is provable without a PDF — see
  `ios/Tests/ImportPipelineTests.swift`); `ImportService` is the actor owning the whole
  pipeline and the in-flight `Task`; `ImportModels.swift` holds **the copy deck** — every
  user-facing sentence for `ImportFailure` and `IntegrityOutcome` lives there, and
  `Issuer.display_name` is the only engine string allowed on screen.
- `tests/parity.rs` — the golden harness (readers + reconcile/dedup/coverage/transfer).

---

## 8. Repo map

```
core/crates/kaname-core/   Rust engine (kaname-core)
  src/statement/           the 10 readers + shared seams
  src/{model,dedup,coverage,transfer,categorize,store,ffi,lib}.rs
  build.rs                 non-Apple SQLCipher/LibTomCrypt linking (no OpenSSL)
  tests/                   parity golden harness + store behavioural tests (store*.rs)
ios/                       SwiftUI app (Tuist). Tests/*Tests.swift = per-bank + engine + store bridge tests
fixtures/<bank>/<kind>/    synthetic golden vectors (NO real data — Constitution I)
specs/NNN-<slug>/          Spec Kit: spec/plan/research/contracts/tasks  ← CURRENT work (§3)
.scratch/<slug>/           older ticket tracker: spec.md + issues/NN-*.md (all resolved)
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
