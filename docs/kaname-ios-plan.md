# Kaname (by BeaconBrain) — Open-Source iOS App Plan

> **Kaname** (要 — "the key / the fan-pivot that holds everything together"), a product under the **BeaconBrain** umbrella.
> The privacy-first, **local-first** personal-finance app — native iOS, all data on device.
> Engine strategy: **shared Rust core + native SwiftUI** (write the engine once; reuse for Android/desktop later).

---

## 0. Executive summary

- Build the **Kaname iOS app** as a **native SwiftUI** client powered by a **shared Rust core** (`kaname-core`) that owns the deterministic engine — bank/card statement parsers, categorization, dedup, balance-chain/reconciliation, the local encrypted store, analytics, and export — exposed to Swift via **UniFFI**.
- **Open-source the client** under **Apache-2.0**; keep the **backend closed** (open-core). Premium features stay **server-gated**, so a forked client can never unlock them.
- Reuse the **same Spec Kit + agentic workflow** as the web repo (constitution, `speckit.*` prompts/agents), plus iOS-specific tooling.
- **Feature parity**: every current web *free* feature runs on-device; premium cloud features (cross-device sync, managed AI, AA one-click, broker/CAS auto-sync, split hosting) arrive later, server-gated.
- **De-risk the port** by reusing the web app's parser **golden fixtures** as Rust test vectors → the on-device engine must reproduce production output byte-for-byte.

---

## 1. Guiding principles (constitution — inherit + strengthen)

Mirror the web repo's `FinTrack India Constitution`, adapted for on-device mobile:

1. **Data Privacy & Sovereignty (NON-NEGOTIABLE)** — free features run **100% on device, no network**. Data encrypted at rest. Enforced by an automated **privacy-egress test** (port of `test_statement_privacy_egress.py`) asserting zero outbound network in free paths.
2. **Local Verification Gate (iOS)** — before any PR: Rust `cargo test`, a **simulator build + run**, and **snapshot/XCUITest** must pass (the iOS analog of the web repo's Playwright gate).
3. **No secrets in the OSS client** — all secrets server-side; AI via BYO-key or a server proxy.
4. **Design & accessibility as a gate** — latest HIG, full Dynamic Type + VoiceOver.
5. **Permissive licensing** — Apache-2.0 only; never GPL/AGPL in the client.

---

## 2. Open-source + payments (locked decisions)

| Topic | Decision | Rationale |
|---|---|---|
| Client license | **Apache-2.0** | Permissive + patent grant; GPL/AGPL are **App-Store-incompatible** (VLC/FSF precedent). |
| Open/closed split | **Open-core**: client OSS, backend closed | Clean boundary; premium lives server-side. |
| Premium protection | **Server-gated entitlement** | A fork flipping `isPaid` gets nothing — sync/AI/AA/split are served only to server-validated subscribers. |
| Purchase paths | **Web (Razorpay) primary** + StoreKit 2 IAP | Web checkout avoids Apple's cut; IAP (15% Small Business) for in-app convenience. |
| Entitlement model | **Account-based, cross-platform**, validated server-side | Buy on web/desktop/iOS → works everywhere. Server checks App Store Server API receipts + Razorpay subscription state. |
| Free-rider risk | **Low on iOS** | Sideloading needs Xcode + $99/yr account + weekly re-sign; Apple rejects clones (Guideline 4.3). |
| Trust dividend | OSS **proves** the privacy claim | "Read the code — verify your data never leaves the device." |

---

## 3. Architecture

### 3.1 `kaname-core` (Rust)
Deterministic, platform-agnostic engine:
- **Parsers** — port of the Python `statement_readers`:
  - Credit-card (LineStatementReader + reconciliation): `icici`, `hdfc`, `sbi_card`, `yes_kiwi`, `federal_scapia`.
  - Bank-account (BalanceLedgerStatementReader + balance-chain): `icici_bank`, `hdfc_bank`, `federal_bank`, `au_bank`, `iob`.
  - Registry keyed by `(bank_code, account_kind)`; shared `base` / `_ledger_reader` / `_line_reader` / `polarity` / `_common`.
- **Categorization** — T1 (history) + T2 (rules): deterministic, offline, free.
- **Dedup + transfer detection**, **balance-chain integrity**, **reconciliation**.
- **Data model + persistence** — SQLite via `rusqlite`, encrypted with **SQLCipher**; key stored in the **iOS Keychain** (Secure Enclave-backed), files marked `NSFileProtectionComplete`.
- **Analytics aggregations** + **export** (CSV/JSON).
- **Money** — `rust_decimal` everywhere (never floats).
- **Bindings** — **UniFFI** → Swift now; Kotlin (Android) and JS/WASM (desktop/web) later from the *same* core.

### 3.2 PDF / text-extraction split (the key simplification)
The Python readers already operate on **text lines + word x-positions** (`read_lines(lines, full_text, first_row_words)`), so:
- **Platform layer extracts text** — iOS **PDFKit** produces lines + word positions.
- **Rust owns parsing logic** — receives the extracted text via the reader seam.
- This avoids reimplementing a PDF engine in Rust. (Android later: PdfBox/pdfium; desktop: pdfium.)
- AI-fallback parsing (`ai_fallback.py`) stays **optional / BYO-key**, out of the free deterministic core.

### 3.3 `ios/` (SwiftUI app)
Owns everything platform-native and calls `kaname-core` through the generated Swift bindings:
- Navigation (`NavigationStack`), all screens, **Swift Charts** dashboards, **WidgetKit** widgets, **App Intents**/Siri.
- File import (`UIDocumentPicker` + a **Share Extension** for "share statement to Kaname"), **StoreKit 2** purchases, Keychain key management, local notifications, onboarding, settings.

### 3.4 Categorization tiers (free/paid line preserved)
- **T1 + T2** → Rust core, offline, **free**.
- **T4 (LLM)** → optional: BYO-key on-device call (**free**) or server-proxied managed AI (**paid**) — not part of the free deterministic core.

---

## 4. Feature parity (current web *free* features → on-device)

| Web feature | iOS/core owner |
|---|---|
| CSV import | Rust parser + Swift file picker |
| PDF statement import | PDFKit (extract) → Rust parsers |
| Dedup / transfer detection | Rust core |
| T1/T2 categorization | Rust core |
| Accounts / transactions / categories / tags / budgets | Rust core (encrypted SQLite) |
| Dashboard / trends / category breakdown / top merchants | Swift Charts over core aggregations |
| Search / filter / month views | Rust queries + SwiftUI |
| Manual entry, edit, bulk recategorize | Rust core + SwiftUI |
| Export (CSV/PDF) | Rust export + Swift share sheet |
| Optional on-device AI | BYO-key (free) |
| **Premium/cloud (later, server-gated)** | AA one-click, broker/CAS auto-sync, managed AI, cross-device E2E sync, split hosting, encrypted backup |

---

## 5. Repo & Spec Kit parity

- **Monorepo** `kaname/`:
  - `core/` — Rust cargo workspace (`kaname-core`).
  - `ios/` — SwiftUI app (Tuist-generated project).
  - `fixtures/` — shared golden vectors (ported from the web repo) used by both Rust tests and iOS snapshot baselines.
  - `.specify/`, `.github/` — Spec Kit + agent wiring.
- `specify init` → same `.specify/` (memory, templates, scripts, workflows) + `.github/prompts/speckit.*` + `.github/agents/speckit.*`.
- **Adapt the constitution** via `speckit.constitution` (see §1).
- **Update templates** (`plan`, `spec`, `tasks`, `agent-file`) for the Swift/Rust stack.
- **Copilot enablement:**
  - `.github/copilot-instructions.md` — Swift/SwiftUI conventions (latest iOS, Observation/MVVM, async/await, SF Symbols, accessibility), the Rust-core boundary, "no secrets" rule.
  - **Port** the `make-interfaces-feel-better` skill (UI polish) + the `ui-ux-pro-max` prompt.
  - Run **`suggest-awesome-github-copilot-{instructions,skills,agents}`** *inside the new repo* to pull Swift/SwiftUI instructions & chatmodes from `github/awesome-copilot` (they match repo context + dedupe).
  - Optional custom agents: an **iOS design-review** agent and a **Fastlane release** agent.

---

## 6. Toolchain

**Rust core**
- cargo workspace; `uniffi` (bindings); `rusqlite` + bundled **SQLCipher**; `csv`; `regex`; `chrono`/`time`; **`rust_decimal`**; `serde`.
- Ship as an **XCFramework** (via `cargo-swift` / `uniffi-bindgen`) consumed by the iOS target.
- Gates: `cargo test`, `cargo clippy`, `cargo fmt --check`.

**iOS**
- **SwiftUI**, **Swift Charts**, **WidgetKit**, **App Intents**, **StoreKit 2**, **PDFKit**.
- Project generation: **Tuist** (Swift DSL) — multi-target (app + widget + share-extension + tests) without `.pbxproj` merge pain.
- Gates: **SwiftLint** + **swift-format**; **Swift Testing** (`@Test`) + **swift-snapshot-testing** (Point-Free); **XCUITest** smoke.

**Agentic / MCP**
- **XcodeBuildMCP** — lets the coding agent build/run/test + drive the simulator + capture screenshots.
- **SourceKit-LSP** / xcode-build-server for code intelligence.

**CI/CD**
- **GitHub Actions** on **macOS runners**; **Fastlane** (build, sign, snapshot, TestFlight, App Store); cache Rust + SPM.
- **Local Verification Gate** = simulator build/run + snapshot/XCUITest + `cargo test`, required before merge.

---

## 7. iOS design (latest HIG)

SwiftUI-first, following the current Human Interface Guidelines (incl. the iOS 26 "Liquid Glass" material language where it fits):
- **SF Symbols**, **Dynamic Type**, **Dark Mode**, `NavigationStack`, `.sheet` + `.presentationDetents`.
- **Swift Charts** for every visualization (native, no dependency).
- **WidgetKit** — net-worth / spend-this-month widgets; Lock Screen + Control Center widgets.
- **App Intents** + Siri/Shortcuts ("add expense", "what did I spend on groceries?").
- Haptics, ProMotion-smooth transitions, full **VoiceOver** + accessibility.
- Reuse the `make-interfaces-feel-better` skill + `ui-ux-pro-max` prompt for polish passes.

---

## 8. Parity test strategy (de-risk the Rust port)

Port these web fixtures/golden tests into `fixtures/` and assert identical Rust output:
- `test_statement_export_parity` / `test_bank_statement_export_parity` — canonical parsed output.
- `test_statement_reconciliation` — CC reconciliation.
- `test_statement_coverage` — coverage timeline.
- `test_statement_cross_source_dedup` / `test_bank_statement_cross_source_dedup` — dedup.
- `test_statement_privacy_egress` — **zero network** in free paths (also a constitution gate).
- Fixture generator: `backend/tests/fixtures/statement_pdf.py`.

Approach: **fixtures-driven, incremental by bank** — port the top banks first, expand parser-by-parser, each new bank landing with its golden vectors green.

---

## 9. Roadmap (as Spec Kit features `NNN-...`)

- **P0 — Repo bootstrap.** Monorepo, Apache-2.0 LICENSE, `specify init`, adapted constitution, Tuist, GitHub Actions + Fastlane, SwiftLint/swift-format, Swift Testing, XcodeBuildMCP, `copilot-instructions.md` + ported skills.
- **P1 — Rust core skeleton.** cargo workspace + UniFFI + XCFramework wired into the iOS app; encrypted SQLite; data model; a "core ↔ Swift" round-trip test.
- **P2 — Engine port.** Top-5 bank/card parsers + T1/T2 + dedup + balance-chain + reconciliation; PDFKit→Rust text bridge; golden-fixture parity **green**.
- **P3 — Core SwiftUI app.** Onboarding → import → transaction list → categorize → dashboard (Swift Charts) → budgets → tags → search → export; latest-HIG polish.
- **P4 — Account + entitlement + purchase.** Web (Razorpay) + StoreKit 2 IAP; account-based cross-platform entitlement; server-side receipt validation; gated premium hooks.
- **P5 — Expand + ship.** Remaining parsers; WidgetKit; App Intents; accessibility pass; TestFlight → App Store.
- **P6 — Premium on iOS (later).** Cross-device E2E sync, managed AI, AA one-click, broker/CAS sync, split hosting → then **Android** via the shared Rust core.

---

## 10. Open decisions (recommended defaults)

| # | Decision | Default |
|---|---|---|
| 1 | Repo shape | **Monorepo** (core + ios + fixtures) |
| 2 | Repo name | **`kaname`** (under BeaconBrain org/owner) |
| 3 | Rust↔Swift bindings | **UniFFI** |
| 4 | PDF text extraction | **Native PDFKit → Rust** |
| 5 | Local DB | **SQLCipher-encrypted SQLite in Rust** |
| 6 | License | **Apache-2.0** |
| 7 | Project generation | **Tuist** |

---

## 11. Risks & mitigations

| Risk | Mitigation |
|---|---|
| PDF layout variance across banks | Native extraction + golden fixtures + optional BYO-key AI fallback |
| Rust / UniFFI ramp-up | Start with a thin core + one parser to validate the toolchain end-to-end (P1) |
| App Review (finance + on-device) | Clear privacy story, no account required for free tier, StoreKit compliance, no private APIs |
| Parser port effort | Fixtures-driven, incremental by bank; parity tests catch regressions |
| Cross-platform later (Android) | The Rust core is designed platform-agnostic from day one (UniFFI) |

---

*Status: plan drafted after locking (a) product name **Kaname by BeaconBrain** and (b) engine strategy **shared Rust core + SwiftUI**. Next: scaffold the `kaname` repo (Spec Kit + Tuist + cargo workspace + CI) and run `speckit.constitution` + `speckit.specify` for P0/P1.*
