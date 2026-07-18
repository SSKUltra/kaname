# Kaname — Session Handoff (P2 ingestion continuation)

> **Read this first**, then `.specify/memory/constitution.md` (wins over everything),
> then `docs/kaname-ios-plan.md` (architecture + P0–P6), then `.github/copilot-instructions.md`.
> The original scaffold handoff is `docs/HANDOFF.md` (historical "why" + gotchas — still useful).

## 0. TL;DR — where we are
Kaname is the **privacy-first, local-first** open-source iOS client (Rust core + SwiftUI)
for personal finance, by BeaconBrain. The **entire statement-reader porting effort is
DONE**: all **10** readers from the closed web engine are ported, each proven **byte-for-byte**
against golden fixtures and reachable across the Rust↔Swift UniFFI bridge.

- **`main` tip when this handoff was written:** `c361865`.
- **Merged PRs #1 → #12** (11 feature slices + 1 CI-hardening chore). All CI-green.
- **Engine tests on `main`:** 63 Rust unit + 13 Rust parity + 27 Swift (11 suites); 0 network deps.

## 1. What's DONE
| Layer | Status |
|---|---|
| **P0** bootstrap + verify | ✅ toolchain, gates green, Copilot content installed |
| **P1** UniFFI Rust↔Swift bridge | ✅ PR #1 (`engine_version`, `normalize_transaction`, Decimal/NaiveDate custom types) |
| **P2 credit-card readers (6)** | ✅ ICICI, HDFC (2 layouts), SBI, Yes, Federal/Scapia, IOB |
| **P2 bank-account ledger readers (4)** | ✅ ICICI, HDFC (2 layouts), Federal (2 templates), AU |
| **Balance-chain integrity** | ✅ `balance_chain::check` → Reconciled/NeedsReview + suspects |
| **Golden-parity harness** | ✅ `core/crates/kaname-core/tests/parity.rs` (1 fixture + 1 Case row per bank) |
| **Privacy-egress gate** | ✅ `make core-privacy-audit` (CI-enforced) |
| **iOS CI hardening** | ✅ PR #9 — dynamic simulator selection by UDID (`.github/scripts/select-ios-simulator.sh`) |

**Reader source files** (`core/crates/kaname-core/src/statement/`):
- Credit-card (via `LineReaderConfig` + `read_lines`): `icici.rs`, `hdfc.rs`, `sbi.rs`, `yes.rs`, `federal.rs`, `iob.rs`.
- Bank-account (via `LedgerReaderConfig` + `read_ledger_lines` + `balance_chain`): `icici_bank.rs`, `hdfc_bank.rs`, `federal_bank.rs`, `au_bank.rs`.
- Shared seams: `line_reader.rs`, `ledger_reader.rs`, `balance_chain.rs`, `common.rs`, `polarity.rs`, `base.rs`.

## 2. What's NEXT (pick one; user checkpoints at slice boundaries)
The remaining pieces of the web engine's **ingestion** layer
(`/Users/ssk/Projects/finance-tracker-phase/backend/app/services/ingestion/`):

1. **Reconciliation** (`reconciliation.py`) — **recommended next.** The credit-card readers
   currently DEFER the printed debit/credit totals (`printed_total_credits` / `printed_total_debits`
   in web `base.py`; carved out on every CC reader — see the module comments in `yes.rs`/`iob.rs`).
   This slice would: add `printed_total_*` fields to `ParsedStatement`, port each CC reader's
   `ACCOUNT SUMMARY`/totals regex, and add a `reconcile()` check (Σ read debits/credits vs the
   printed totals → RECONCILED/NEEDS_REVIEW). The **ledger** side already has `balance_chain`
   (its analogue), so this is the CC counterpart. Golden fixtures already exist per bank — extend
   their `expected` with the printed totals.
2. **Cross-source dedup** (`deduplicator.py`) — bank ↔ credit-card matching (a card payment shows
   up in both the CC statement and the bank ledger). `core/crates/kaname-core/src/dedup.rs` already
   has `dedup_fingerprint` + `normalize_description` — build the cross-source matcher on top.
3. **Coverage** (`coverage.py`) — statement date-range completeness / gap detection.
4. **Beyond ingestion (P3+)** — categorization (T1 history + T2 rules), encrypted persistence
   (SQLCipher, arrives P2+ per the plan), then UI surfaces.

**Web parity tests to port as Rust golden vectors** (in `finance-tracker-phase/backend/tests/integration/`):
`test_statement_reconciliation.py`, `test_statement_coverage.py`, `test_statement_cross_source_dedup.py`,
`test_bank_statement_cross_source_dedup.py`.

## 3. The per-slice workflow (proven 11× this session — follow it exactly)
Use the **Spec Kit** flow, one slice per PR:
1. `speckit.specify` (sub-agent) → new numbered branch `NNN-slug` + `spec.md` + checklist. Commit spec.
2. `speckit.plan` (sub-agent, pass the locked Rust design + ground truth in the prompt) → `plan.md` +
   research/data-model/contracts. **Fix the `update-agent-context.sh` "iOS 18 targe" typo** (see gotchas). Commit plan.
3. `speckit.tasks` (sub-agent) → `tasks.md`. Commit tasks.
4. **Implement directly** (don't delegate — it's faster once the design is locked):
   - Capture **ground truth** from the web engine first:
     `cd /Users/ssk/Projects/finance-tracker-phase/backend && .venv/bin/python -c "..."` — run the real
     web reader/function and dump exact expected values to JSON. This is how every fixture was made
     byte-perfect. (Generate fixtures from the dumped JSON with a small Python script for backslash/unicode safety.)
   - Test-first: golden fixture → parity `Case` row + claims/chain test (RED) → Swift `*Tests.swift` (RED) →
     engine (GREEN) → `make core-xcframework` (regenerates Swift bindings) → Swift GREEN.
   - Run the full gate, then **2 commits** (engine+fixtures+parity; Swift test) → PR → watch CI → `merge --rebase --delete-branch` → `git remote prune origin`.
5. **Surface any sub-agent decision that needs user input back to the user** (`ask_user`) — never self-answer on their behalf.

## 4. Local Verification Gate (MANDATORY before every PR) — all must be green
```
make core-lint          # cargo fmt --check + clippy -D warnings
make core-test          # cargo test (unit + parity)
make core-privacy-audit # no networking crate in the shipped graph
make lint               # swiftlint --strict + swift-format lint + core-lint
make ios-gen            # tuist generate (depends on core-xcframework)
make ios-test           # simulator build + Swift Testing (depends on ios-gen)
```
CI (`.github/workflows/ci.yml`) mirrors these: Rust on `ubuntu-latest`, iOS on `macos-15`.

## 5. Environment & gotchas (learned the hard way — save yourself the pain)
- **Toolchain PATH:** `cargo`/`rustup` live in `~/.cargo/bin` but are NOT on the default non-login
  PATH (root-owned `~/.bash_profile`). **Prefix every shell:** `export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"`.
- **Cargo workspace is under `core/`** — `cargo` commands need `cd core` (or use the `make` targets from repo root).
- **iOS simulator:** local `make ios-test` targets a sim named **"iPhone 16"** (create once:
  `xcrun simctl create "iPhone 16" "iPhone 16"`). CI now selects a sim **dynamically by UDID**
  (`.github/scripts/select-ios-simulator.sh`) — never re-hardcode a device name in the workflow.
- **CI iOS job MUST stay on `macos-15`** (Homebrew `tuist` cask breaks on `macos-14`). Xcode pinned to newest 16.x in CI.
- **swift-format `[Spacing]` rejects trailing inline comments** after code (e.g. `#expect(...) // note`).
  Put explanatory comments on their **own line above** the statement. (Bit us on ~4 test files.)
- **`DATE_FORMATS` order matters** (`common.rs`): `%d/%m/%y` MUST precede `%d/%m/%Y` — Rust chrono's `%Y`
  greedily accepts a 2-digit year. chrono's `%b` **is** case-insensitive (uppercase `MAR` parses).
- **Money is never a float:** `rust_decimal::Decimal` in Rust, crosses UniFFI as an exact base-10
  `String`, surfaces as `Foundation.Decimal` in Swift. Direction comes from a `Dr`/`Cr` marker or the
  balance delta — **never** the amount's sign. (Geometry x-coords in `Word` are legitimately `f64` layout points.)
- **PDF text extraction is NATIVE** (iOS PDFKit). The core never opens a PDF; readers take already-extracted
  `lines` + `full_text` (+ `first_row_words` geometry for the ledger row-1 bootstrap).
- **`update-agent-context.sh` typo:** on every `speckit.plan`, the script writes "iOS 18 targe" (drops the
  trailing "t") into `.github/copilot-instructions.md`. Fix before committing the plan:
  `sed -i '' 's/iOS 18 targe$/iOS 18 target/g; s/iOS 18 targe /iOS 18 target /g' .github/copilot-instructions.md`.
- **rustfmt reformats your edits:** after `edit`, run `make core-fmt` then re-`view` before the next `edit`
  (asserts/imports/arrays get re-wrapped, so old_str may no longer match).
- **UniFFI:** 0.32 proc-macro (no UDL). `#[uniffi::export]` fns, `#[derive(uniffi::Record/Enum)]`.
  `make core-xcframework` rebuilds `KanameCoreFFI.xcframework` + regenerates `ios/Generated/` (git-ignored) —
  run it **before** `tuist generate` whenever the FFI surface changes.

## 6. Key reusable seams (for building on the parsers)
- `line_reader.rs`: `LineReaderConfig` (bank_code, claim_markers, row_re, direction, enrich) +
  `read_lines` + `claims`. Every CC reader is one config.
- `ledger_reader.rs`: `LedgerReaderConfig` (+ `anchor_res` first-match-wins, `opening/closing_balance_re`,
  `column_split_x`, `account_tail`) + `read_ledger_lines` + `claims_ledger`. Direction from balance delta;
  the empty debit/credit column may be `0`, `0.00`, or `-` (all handled). Every ledger reader is one config.
- `balance_chain.rs`: `check(&ParsedStatement) -> ChainResult` (Reconciled/NeedsReview + Suspect list).
- `common.rs`: `parse_amount`, `parse_date`, `find_last4(text, anchor)`, `account_tail_last4(text, primary_re)`,
  `month_year_end`.
- `polarity.rs`: `classify(desc, dr_cr_marker, amount_cell) -> Direction`.
- `tests/parity.rs`: the golden harness. Adding a reader = 1 fixture (`fixtures/<bank>/{credit_card,bank_account}/*.json`)
  + 1 `Case` row + 1 claims (or balance-chain) test. `Expected`/`ExpectedRow` fields are `#[serde(default)]`-optional
  so old fixtures never need migration.

## 7. Repo map
```
core/crates/kaname-core/   Rust engine (kaname-core)
  src/statement/           the 10 readers + shared seams (see §1/§6)
  src/{model,dedup,ffi,lib}.rs   Direction/Transaction, dedup fingerprint, UniFFI boundary, crate root
  tests/parity.rs          golden-fixture harness
ios/                       SwiftUI app (Tuist). Tests/*ParseTests.swift = per-bank bridge tests
fixtures/<bank>/<kind>/    synthetic golden vectors (NO real data — Constitution I)
specs/NNN-slug/            per-slice Spec Kit artifacts (spec/plan/tasks/…)
.specify/memory/constitution.md   THE rules (privacy non-negotiable; wins over all)
.github/scripts/select-ios-simulator.sh   CI simulator selector
docs/{HANDOFF.md, kaname-ios-plan.md}      original scaffold handoff + full plan
```

## 8. The web engine (source of truth for porting — read-only)
`/Users/ssk/Projects/finance-tracker-phase/backend/` (has a working `.venv/bin/python`). The ingestion
code is under `app/services/ingestion/`; its unit tests under `tests/unit/ingestion/`. Always capture
ground truth by RUNNING the real web code, then port to Rust and prove parity byte-for-byte. **Fixtures
must be synthetic/redacted — never real statement data.**
