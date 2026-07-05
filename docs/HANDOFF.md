# Kaname — Agent Handoff

> Orientation for the next agent/session starting work in **`SSKUltra/kaname`**.
> Read this first, then the three canonical docs it points to. Fresh, session-specific
> facts (exact porting paths, CI gotchas, local env) live here; deep design lives in the plan.

## 0. Canonical references (read these next)
1. **`.specify/memory/constitution.md`** — Kaname Constitution v1.0.0. **Wins over everything.**
   Privacy NON-NEGOTIABLE (free = 100% on-device, zero network); open-core Apache-2.0;
   iOS Local Verification Gate.
2. **`docs/kaname-ios-plan.md`** — the full engineering plan (architecture, OSS+payments,
   feature parity, toolchain, roadmap P0–P6, risks). The "why" behind this scaffold.
3. **`.github/copilot-instructions.md`** — day-to-day conventions + the golden rules.

## 1. Current status (verified)
- Repo: **https://github.com/SSKUltra/kaname** (public, Apache-2.0). Default branch `main`.
- **CI is green** (run 28743357987): Rust job (`cargo fmt`/`clippy -D warnings`/`test`) +
  iOS job (SwiftLint, swift-format, `tuist generate`, simulator build+test) both pass.
- Commits so far: `8a3724d` scaffold → `d5163ca` swiftlint fix → `61a07a2` macos-15 fix.
- **Nothing is built locally** — the scaffold was validated only by CI (toolchains not
  installed on this machine; see §5).

### What exists
```
core/crates/kaname-core/   Rust engine: model.rs (Direction/Transaction), dedup.rs
                           (normalize_description + dedup_fingerprint), lib.rs
                           (engine_version()). FFI-ready (staticlib+cdylib+lib). Tests pass.
ios/                       SwiftUI app via Tuist: Project.swift (app + test targets),
                           Sources/{KanameApp,RootView}.swift, Tests/KanameTests.swift
                           (Swift Testing), .swiftlint.yml, .swift-format.
fixtures/                  README only — golden vectors land in P2.
.specify/ + .github/       Full Spec Kit workflow (mirrored from the web repo).
```

## 2. Locked decisions (do not relitigate)
- **Name**: "Kaname by BeaconBrain" (要 = the key/linchpin). BeaconBrain = umbrella brand.
- **Engine strategy**: shared **Rust core (`kaname-core`)** exposed via **UniFFI** + native
  **SwiftUI**. Reuse the core for Android/desktop later.
- **PDF boundary**: text extraction stays **native** (iOS PDFKit → lines + word
  x-positions) and feeds the Rust parser seam `read_lines(lines, full_text, first_row_words)`.
  The Rust core NEVER embeds a PDF engine.
- **Money**: always `Decimal` / `rust_decimal::Decimal`. Polarity via `Direction`, never sign.
- **Storage**: SQLite + SQLCipher; key in iOS Keychain / Secure Enclave.
- **OSS/payments**: client is Apache-2.0 (NOT GPL — App Store incompatible); backend stays
  closed (open-core); premium is **server-gated**. Purchase = web Razorpay primary +
  StoreKit 2 IAP; entitlement validated server-side per account.

## 3. The web repo is the source of truth for porting
Web app repo: **`SSKUltra/finance-tracker`** (FastAPI + Next.js). Local worktrees on this
machine: `finance-tracker-phase` (phase dev), `finance-tracker-fixes`, `finance-tracker-small-features`.

**Parsers to port** → `backend/app/services/ingestion/statement_readers/`:
- Shared: `base.py`, `_line_reader.py` (LineStatementReader), `_ledger_reader.py`
  (BalanceLedgerStatementReader), `_common.py`, `registry.py`, `polarity.py`, `ai_fallback.py`.
- **Credit-card** readers (use `LineStatementReader` + `reconciliation.reconcile`):
  `icici.py`, `hdfc.py`, `sbi_card.py`, `yes_kiwi.py`, `federal_scapia.py`.
- **Bank-account** readers (use `BalanceLedgerStatementReader`; direction from running-balance
  delta; integrity via `balance_chain.check`): `icici_bank.py`, `hdfc_bank.py`,
  `federal_bank.py`, `au_bank.py`, `iob.py`.
- `registry` is keyed by **`(bank_code, account_kind)`**; `register()` defaults
  `account_kind="credit_card"`. **ICICI has BOTH** a CC and a bank reader.

**Ingestion siblings** → `backend/app/services/ingestion/`: `reconciliation.py`,
`balance_chain.py`, `coverage.py`, `deduplicator.py`.

**Parity fixtures/tests to port as Rust golden vectors** → `backend/tests/integration/`:
`test_statement_export_parity.py`, `test_bank_statement_export_parity.py`,
`test_statement_reconciliation.py`, `test_statement_coverage.py`,
`test_statement_cross_source_dedup.py`, `test_bank_statement_cross_source_dedup.py`,
`test_statement_privacy_egress.py`, `test_bank_statement_privacy_egress.py`.
Contract shape: `backend/tests/contract/test_statements_contract.py` +
`test_statements_bank_account_contract.py`. Fixture generator:
`backend/tests/fixtures/statement_pdf.py`. **Fixtures MUST be synthetic/redacted — no real data.**

## 4. Do this next (immediate roadmap)
Use the Spec Kit flow per feature: `speckit.specify` → `speckit.plan` → `speckit.tasks` →
`speckit.implement`. Suggested first three milestones:

- **P0 — Bootstrap & verify locally.** Run `make bootstrap` (installs Rust, Tuist, SwiftLint,
  swift-format). Confirm `make core-test`, `make ios-gen`, `make ios-test`, `make lint` all
  pass on the machine. Then run `suggest-awesome-github-copilot-{skills,instructions,agents}`
  inside the repo to pull Swift/iOS content.
- **P1 — Wire the Rust↔Swift bridge (UniFFI).** Add UniFFI to `kaname-core` (export
  `engine_version()` + a first parse type), build `KanameCore.xcframework`
  (aarch64-apple-ios + sim targets — already in `rust-toolchain.toml`), add it as a Tuist
  binary dependency in `ios/Project.swift`, and call it from `RootView` to prove the bridge
  end-to-end. This is currently the only "deferred" scaffold piece.
- **P2 — First parser + parity + privacy gate.** Port ONE reader end-to-end (recommend a CC
  reader, e.g. ICICI) into `kaname-core` with golden fixtures under `fixtures/`. Add a
  **privacy-egress test** (Rust test asserting zero network in the parse path) — this is the
  constitution's automated gate.

## 5. Environment & gotchas (learned this session — save yourself the pain)
- **Local toolchain is missing**: no `cargo`/`rustc`/`rustup`, `tuist`, `swiftlint`,
  `swift-format`. Run `make bootstrap`. Present: `swift`, `xcodebuild`, `git`, `gh`, `specify`,
  `uv`. Local macOS is 26.x (newer than CI).
- **CI iOS job MUST stay on `macos-15`.** Homebrew's `tuist` cask (4.200.5) is built for
  macOS 15; on `macos-14` it aborts with `dyld: Library not loaded: libswiftSynchronization.dylib`
  (exit 134). Do not downgrade the runner.
- **Do not re-enable SwiftLint's `trailing_comma` rule** — it conflicts with `swift-format`
  and Xcode 16 defaults; it's intentionally disabled in `ios/.swiftlint.yml`.
- **`specify init` is broken upstream** (release-asset fetch returns empty). The Spec Kit
  framework here was **mirrored from the web repo**, not generated by `specify init`. If you
  ever need to refresh it, copy from `SSKUltra/finance-tracker` (`.specify/` + `.github/prompts|agents`).
- **Tuist generates `Kaname.xcworkspace`** (git-ignored). Run `make ios-gen` before opening
  Xcode. Tests use **Swift Testing** (`import Testing`) → needs Xcode 16+ / iOS 18 sim.
- Commit trailer: append `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`.

## 6. Brand / ops to-dos (non-code)
- Create a **BeaconBrain GitHub org** and transfer this repo (currently under `SSKUltra`; `gh`
  can't create orgs — do it in the GitHub UI).
- Grab domains **`kaname.money` / `.co` / `.io`** (`.com` and `.app` are taken).
- File the **KANAME** wordmark trademark in India (Classes 9 / 36 / 42).
- App Store seller name = **BeaconBrain**.

---
_Generated 2026-07-05 at the end of the scaffolding session. Update this file as milestones land._
