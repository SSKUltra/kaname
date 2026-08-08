<!--
SYNC IMPACT REPORT
Version: 1.0.0 → 2.0.0
Rationale: MAJOR amendment redefining Principle I (a NON-NEGOTIABLE principle) and the
free/paid model. (1) An account is now REQUIRED to use the app (identity + entitlement +
minimal first-party usage), replacing "no account required". (2) The non-negotiable
privacy boundary is re-scoped from "not even anonymous pings anywhere" to "the core
engine is always network-free AND financial data stays on-device on every free path";
minimal first-party, account-scoped, non-financial usage signals are now permitted (still
no third-party analytics/ad/crash SDKs, no data sale). (3) AI is Pro-only and
server-proxied (no BYOK). (4) New Principle VI (Free/Paid Boundary): on-device-capable
features are free, server-requiring features (AI, AA, sync) are Pro.

Principles:
  I.   Data Privacy & Sovereignty (NON-NEGOTIABLE) — REDEFINED: engine always offline +
       financial data on-device on free paths; account required; networked features Pro/opt-in
  II.  Local-First Shared Engine — unchanged
  III. Open-Core & Permissive Licensing — unchanged
  IV.  Native Experience & Accessibility — unchanged
  V.   Test-First & Parity — unchanged
  VI.  Free/Paid Boundary — new (on-device = free; server = Pro; AI is Pro, no BYOK)

Added sections: Principle VI; a first-party-usage clause under Security & Privacy Constraints.

Templates requiring updates:
  ✅ .specify/templates/plan-template.md — Constitution Check still valid
  ✅ .specify/templates/spec-template.md — no change needed
  ✅ .specify/templates/tasks-template.md — no change needed
  ⚠ Feature plans touching AI, account, sync or AA MUST cite Principle I (networked =
    Pro/opt-in) and Principle VI.
  ⚠ Docs updated alongside: README.md, docs/kaname-ios-plan.md, docs/adr/0001–0003.

Deferred TODOs: define Pro tier pricing/packaging; confirm AA gating vs AA pricing.
-->

# Kaname Constitution

**Kaname (要) by BeaconBrain — the privacy-first, local-first personal finance client.**

This constitution governs the open-source Kaname client (iOS today; Android/desktop
later). It supersedes ad-hoc conventions. Where any guidance conflicts with this
document, this document wins.

## Core Principles

### I. Data Privacy & Sovereignty (NON-NEGOTIABLE)

The user's **financial data** belongs to the user and stays on the user's device. What is
non-negotiable is the *financial-data* boundary and the purity of the engine — not the
absence of an account.

- **The core engine is always on-device.** `kaname-core` performs ZERO network I/O.
  Statement parsing, categorization, dedup, reconciliation, analytics and storage run
  fully on-device. Enforced by an automated **privacy-egress test** (see Principle V);
  this never regresses.
- **Financial data stays local on every free path.** No free feature transmits the
  user's statements or transactions off the device. Financial data leaves the device
  ONLY through a Pro networked feature the user has explicitly enabled (below).
- **Encrypted at rest.** Local data is stored in an encrypted store (SQLCipher); the key
  lives in the iOS Keychain / Secure Enclave and is never exported.
- **An account is required** to use the app. The account holds ONLY identity, entitlement
  (free/Pro) and minimal, first-party, account-scoped feature-usage signals — NEVER the
  user's financial data. No third-party analytics, ad, fingerprinting or crash-reporting
  SDKs; data is never sold; usage signals are disclosed in the privacy policy.
- **Networked features are Pro, opt-in, and minimized.** AI parsing/assist, one-click
  Account Aggregator onboarding, and cross-device sync are the ONLY paths that may use
  the network. Each MUST be explicitly enabled per use, MUST minimize and redact data
  sent (e.g. card numbers masked before AI parsing), and MUST be validated server-side
  (never client-trusted).
- **Compliance.** Aligns with India's DPDP Act 2023 and RBI Account Aggregator consent
  norms. Consent is explicit, purpose-limited, and revocable.

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
- A **privacy-egress test** asserts zero network access in the core engine (and every
  free finance path) and MUST pass.

### VI. Free/Paid Boundary

The line between free and paid follows capability, not artificial gating.

- **Free = anything that runs fully on-device.** Statement import, parsing, categorization,
  dedup, reconciliation, the manual column-mapper for unrecognized statements, analytics,
  search and export are free.
- **Pro (paid) = anything that requires a server.** AI parsing/assist, one-click Account
  Aggregator onboarding, and cross-device sync are Pro — the networked features of
  Principle I, gated by the closed entitlement server.
- **AI is Pro and server-proxied.** There is no bring-your-own-key (BYOK) path in the
  client; managed AI is metered and validated server-side.

## Security & Privacy Constraints

- No third-party SDK may be added to a free/core path if it performs any network I/O,
  fingerprinting, or data collection.
- First-party, account-scoped feature-usage signals (free/Pro entitlement, coarse feature
  counters) are permitted for product and billing decisions; they carry NO financial data,
  use no third-party SDK, and are disclosed in the privacy policy. The core engine stays
  network-free regardless.
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

**Version**: 2.0.0 | **Ratified**: 2026-07-04 | **Last Amended**: 2026-08-08
