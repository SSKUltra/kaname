<!--
SYNC IMPACT REPORT
Version: (none) → 1.0.0
Rationale: Initial ratification for the Kaname open-source iOS client. Adapts the
FinTrack India Constitution (web, v1.5.0) to a privacy-first, local-first mobile
client with a shared Rust core. Principle I is strengthened from "privacy" to
"free/core features are 100% on-device with zero network I/O". The Local Verification
Gate is retargeted from Playwright (web) to an iOS simulator + snapshot/XCUITest gate.

Principles:
  I.   Data Privacy & Sovereignty (NON-NEGOTIABLE) — strengthened: on-device, no-network
  II.  Local-First Shared Engine — new (Rust core, deterministic, parity)
  III. Open-Core & Permissive Licensing — new (Apache-2.0 client, server-gated premium)
  IV.  Native Experience & Accessibility — new (latest HIG, SwiftUI, a11y)
  V.   Test-First & Parity — new (golden fixtures, cargo/Swift Testing)

Added sections: Development Workflow & Quality Gates (incl. iOS Local Verification Gate),
  Security & Privacy Constraints, Governance.

Templates requiring updates:
  ✅ .specify/templates/plan-template.md — Constitution Check references generic gates
  ✅ .specify/templates/spec-template.md — no change needed
  ✅ .specify/templates/tasks-template.md — no change needed
  ⚠ Ensure feature plans cite the iOS Local Verification Gate (not Playwright).

Deferred TODOs: none.
-->

# Kaname Constitution

**Kaname (要) by BeaconBrain — the privacy-first, local-first personal finance client.**

This constitution governs the open-source Kaname client (iOS today; Android/desktop
later). It supersedes ad-hoc conventions. Where any guidance conflicts with this
document, this document wins.

## Core Principles

### I. Data Privacy & Sovereignty (NON-NEGOTIABLE)

The user's financial data belongs to the user and stays on the user's device.

- **Free/core features run 100% on-device with ZERO network I/O.** Statement import,
  parsing, categorization, dedup, reconciliation, analytics and storage MUST complete
  without contacting any server. There is no telemetry, analytics, ad SDK, or crash
  reporter in free/core paths — not even "anonymous" pings.
- **Encrypted at rest.** Local data is stored in an encrypted store (SQLCipher); the key
  lives in the iOS Keychain / Secure Enclave and is never exported.
- **No account required** to use the core app. Any optional account (for premium or
  social features) stores only account identity — never the user's finance data —
  unless the user explicitly opts into an encrypted cloud feature.
- **Premium/cloud features are opt-in and minimized.** One-click Account Aggregator
  sync, broker/mutual-fund import, cross-device sync and AI assist are the ONLY paths
  that may use the network, MUST be explicitly enabled by the user, MUST minimize data
  sent, and MUST be validated server-side (never client-trusted).
- **Compliance.** Aligns with India's DPDP Act 2023 and RBI Account Aggregator consent
  norms. Consent is explicit, purpose-limited, and revocable.
- This principle is enforced by an automated **privacy-egress test** (see Principle V).

### II. Local-First Shared Engine

All deterministic finance logic lives in a single, platform-agnostic core.

- The Rust crate **`kaname-core`** owns parsing, categorization, de-duplication and
  reconciliation. It is reused across platforms (iOS now; Android/desktop later) via
  **UniFFI** bindings. Platforms provide only native UI and platform I/O.
- **The core is pure and deterministic.** No network, no clock/locale surprises, no
  hidden global state. Given the same input it MUST produce the same output.
- **Platform boundary is explicit.** PDF text extraction is native (e.g. iOS PDFKit
  extracts lines + word x-positions) and feeds the Rust parser seam
  `read_lines(lines, full_text, first_row_words)`. The core MUST NOT embed a PDF engine.
- **Money is never a floating-point number.** Use `rust_decimal::Decimal` (core) and
  `Decimal` (Swift). Polarity is carried by an explicit direction, never by amount sign
  conventions that vary per reader.

### III. Open-Core & Permissive Licensing

The client is open source; the business is protected server-side.

- The client is licensed **Apache-2.0**. Copyleft licenses (GPL/AGPL/LGPL) are FORBIDDEN
  in the client because they are incompatible with App Store distribution.
- **No secrets in the client.** No API keys, private endpoints, or entitlements logic
  that could be unlocked by a fork. Premium is gated by a closed server that validates
  entitlements per account.
- The backend and premium services remain closed source (open-core model).

### IV. Native Experience & Accessibility

Kaname must feel like a best-in-class, modern iOS app.

- Follow the **latest Human Interface Guidelines**. Build in **SwiftUI**. Use SF Symbols,
  support **Dynamic Type**, **Dark Mode**, and full **VoiceOver** accessibility.
- UI polish is a feature: apply the `make-interfaces-feel-better` design principles
  (optical alignment, motion, tabular numbers for money, etc.).
- Accessibility is a release gate, not an afterthought (see Quality Gates).

### V. Test-First & Parity

Behaviour is proven by tests before it ships, and matches the proven web engine.

- **Golden-fixture parity.** The core is validated against golden vectors ported from
  the web engine (`fixtures/`): statement export parity, reconciliation, coverage,
  cross-source dedup, and privacy egress. These vectors are the source of truth.
- **Test-first for the engine.** New parsing/reconciliation logic starts with a failing
  fixture/test. Core is tested with `cargo test`; the app with **Swift Testing**
  (`import Testing`) plus snapshot/XCUITest for UI.
- A **privacy-egress test** asserts zero network access in free/core paths and MUST pass.

## Security & Privacy Constraints

- No third-party SDK may be added to a free/core path if it performs any network I/O,
  fingerprinting, or data collection.
- Fixtures and test data MUST be synthetic or fully redacted — never real account data.
- Secrets are never committed. `.env*` files are git-ignored (except `.env.example`).
- Dependencies are reviewed before adding; prefer the standard library and small,
  audited crates/packages. New runtime dependencies require justification in the plan.

## Development Workflow & Quality Gates

Kaname uses **GitHub Spec Kit** for spec-driven development:
`speckit.specify` → `speckit.plan` → `speckit.tasks` → `speckit.implement`.
Every feature plan MUST include a Constitution Check and pass the gates below.

### iOS Local Verification Gate (MANDATORY before every PR)

Replaces the web app's Playwright gate. A change is not "done" until:

1. **Core**: `cargo fmt --check`, `cargo clippy -D warnings`, and `cargo test` all pass.
2. **iOS**: `swiftlint --strict` and `swift-format lint --strict` pass;
   `tuist generate` succeeds; the app **builds and runs on an iOS simulator**; and
   Swift Testing + snapshot/XCUITest suites pass.
3. **Privacy gate**: the privacy-egress test passes (no network in free/core paths).
4. **Accessibility gate**: new/changed screens are verified for Dynamic Type and
   VoiceOver.

`make lint`, `make core-test`, and `make ios-test` are the canonical commands.

### Change discipline

- Small, surgical, reviewed changes. Follow existing conventions.
- CI (`.github/workflows/ci.yml`) runs the core and iOS gates on every PR; a red CI
  blocks merge.

## Governance

- This constitution supersedes other practices. Amendments are made via pull request,
  require an updated Sync Impact Report, and bump the version below per semantic
  versioning:
  - **MAJOR**: remove/redefine a principle or an incompatible governance change.
  - **MINOR**: add a principle/section or materially expand guidance.
  - **PATCH**: clarifications and wording that do not change requirements.
- Every PR description MUST confirm compliance with the applicable gates. Complexity that
  violates a principle MUST be justified in the plan's Complexity Tracking, or the
  approach MUST be simplified.

**Version**: 1.0.0 | **Ratified**: 2026-07-04 | **Last Amended**: 2026-07-04
