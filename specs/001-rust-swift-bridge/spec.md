# Feature Specification: Prove the App Is Powered by the Shared On-Device Engine

**Feature Branch**: `001-rust-swift-bridge`  
**Created**: 2026-07-05  
**Status**: Draft  
**Milestone**: P1 (roadmap) — the on-device engine bridge  
**Input**: User description: "P1 — Prove the iOS app is powered by the shared on-device engine (wire the Rust↔Swift bridge). Establish the end-to-end path so the app calls real, deterministic functions from the on-device engine and displays a real value it produced."

> **Note on priority labels**: This feature is milestone **P1** in the product roadmap. Separately, the user stories below use the standard spec priority labels (P1/P2/P3) to order the work *within this feature*. "Milestone P1" and "User Story P1" are unrelated numbering schemes.

## User Scenarios & Testing *(mandatory)*

Today the app's root screen shows only static placeholder text, and the shared engine is not yet callable from the app. This feature establishes the end-to-end bridge so the app calls real, deterministic functions from the on-device engine and displays a real value the engine produced. This proves the "local-first shared engine" architecture works end-to-end and is the foundation every later feature (statement parsing, categorization, dedup, reconciliation, dashboards) depends on.

### User Story 1 - See the real engine version in the app (Priority: P1)

A person opens the app and, on the root screen, sees the shared engine's version (for example, "Engine v0.1.0") produced by the on-device engine itself — confirming the app is talking to the real engine rather than showing static placeholder text.

**Why this priority**: This is the visible proof-of-life. It is the smallest change that demonstrates the app is genuinely powered by the shared engine end-to-end. Every later capability depends on this path existing, so it must land first and stand alone.

**Independent Test**: Launch the app on a simulator or device and confirm the root screen shows a version string that originates from the engine. Confirm it is engine-sourced by changing the engine's version, rebuilding, and observing the displayed value change without editing any app UI text.

**Acceptance Scenarios**:

1. **Given** the app is installed with the shared engine embedded, **When** a person launches the app and views the root screen, **Then** the screen displays the engine's version (e.g., "Engine v0.1.0") obtained from the engine.
2. **Given** the engine's version is changed and the app is rebuilt, **When** the person launches the app, **Then** the displayed version reflects the new engine version with no change to the app's UI text.
3. **Given** the device has no network connectivity (airplane mode), **When** the root screen appears, **Then** the engine version still displays, proving the value is produced locally rather than fetched.

---

### User Story 2 - A typed value round-trips through the engine exactly (Priority: P2)

A value that originates in the app is sent to the engine, the engine computes a typed result, and the app receives back exactly what the engine produced — proving that non-trivial, non-constant data crosses the app↔engine boundary faithfully.

**Why this priority**: A version string alone could be a constant. A typed round-trip proves that real, structured data crosses the boundary and returns intact. This de-risks every later feature that must pass transactions, categories, and reconciliation results across the same boundary.

**Independent Test**: Provide known typed inputs from the app, invoke the engine's round-trip, and assert the returned value equals exactly what the engine computed for each input, including boundary inputs.

**Acceptance Scenarios**:

1. **Given** a known typed input value in the app, **When** the app sends it to the engine and receives the result, **Then** the returned value equals exactly the value the engine computed for that input.
2. **Given** the same input is sent multiple times, **When** the round-trip is invoked repeatedly, **Then** the result is identical every time (deterministic).
3. **Given** a boundary input (e.g., empty, zero, very large, or Unicode as applicable to the chosen type), **When** the round-trip runs, **Then** the value is preserved exactly with no lossy or approximate conversion.
4. **Given** the round-trip carries any value capable of representing money, **When** it crosses the boundary, **Then** it is not represented as a floating-point number.

---

### User Story 3 - Automated proof and a green verification gate (Priority: P3)

As a maintainer, I have an automated "core ↔ Swift round-trip" test that asserts the app receives exactly the value the engine produced, and the full verification gate (and CI) stays green — so the architectural bridge is protected against regressions from day one.

**Why this priority**: Automated proof turns a one-time manual demo into a durable guarantee. The constitution mandates test-first development and a green Local Verification Gate before merge. Without this, the bridge could silently break as later features are added.

**Independent Test**: Run the automated test suite and confirm the round-trip test passes and asserts exact equality; confirm the required gates (core checks, app lint, project generation, simulator build + app tests) pass.

**Acceptance Scenarios**:

1. **Given** the round-trip capability exists, **When** the automated "core ↔ Swift round-trip" test runs, **Then** it asserts and confirms the value received in the app equals exactly the value the engine produced.
2. **Given** a regression that breaks round-trip fidelity is introduced, **When** the test suite runs, **Then** the round-trip test fails, enforcing the guarantee.
3. **Given** the change is submitted, **When** the iOS Local Verification Gate and CI run, **Then** all required checks pass (green).

---

### Edge Cases

- **Engine value unavailable at runtime**: The engine is embedded in the app, so it is expected to always be present. Defensively, if a value cannot be produced, the app MUST remain stable (no crash) and MUST NOT display a fabricated version.
- **Empty version string**: The engine version is expected to be non-empty; an empty value is treated as an error condition rather than displayed as a blank engine identity.
- **Boundary round-trip inputs**: Empty, zero, negative, very large, and Unicode values (as applicable to the chosen type) must be preserved exactly and deterministically.
- **Repeated or concurrent calls**: Results must be deterministic, with no dependence on wall-clock time, locale, or hidden global mutable state.
- **Accessibility extremes**: At the largest Dynamic Type size and with VoiceOver active, the engine value must remain legible and be announced, with no clipping or truncation.
- **Appearance**: The displayed value must render with correct contrast in both light and dark appearances.

## Requirements *(mandatory)*

### Functional Requirements

**Core bridge behavior**

- **FR-001**: The app MUST retrieve the shared engine's version at runtime directly from the engine and display it on the root screen in a human-readable form (e.g., "Engine vX.Y.Z").
- **FR-002**: The displayed version MUST be sourced from the engine as the single source of truth — never hardcoded or duplicated in the app — such that changing the engine version changes the displayed value with no edit to app UI text.
- **FR-003**: The app MUST perform at least one typed round-trip in which a value originates in the app, is processed by the engine, and the engine's computed result is returned to the app.
- **FR-004**: The value returned from the round-trip MUST equal exactly the value the engine computed, with no lossy or approximate conversion across the boundary.
- **FR-005**: The round-trip MUST exercise a typed, structured value (not merely a fixed string) to demonstrate that non-trivial data crosses the boundary.

**Privacy, determinism & boundary constraints (constitution-derived, NON-NEGOTIABLE)**

- **FR-006**: The entire feature path — app launch, version retrieval, and the round-trip — MUST complete 100% on-device with ZERO network I/O.
- **FR-007**: The feature MUST NOT introduce telemetry, analytics, advertising, or crash-reporting components into the app or the engine.
- **FR-008**: Given identical inputs, the engine MUST return identical outputs on every invocation, with no dependence on wall-clock time, locale, or hidden global mutable state (determinism).
- **FR-009**: The shared engine MUST remain pure and platform-agnostic — it MUST NOT perform platform I/O, embed a PDF engine, or contain UI logic. PDF text extraction remains native and is out of scope for this feature.
- **FR-010**: The round-trip MUST NOT represent monetary amounts as floating-point numbers; any money-capable value MUST use an exact decimal representation.
- **FR-011**: The client MUST NOT contain secrets, API keys, or private endpoints, and MUST remain distributable under Apache-2.0 with no copyleft (GPL/AGPL/LGPL) dependencies introduced.

**Native experience & accessibility**

- **FR-012**: The engine-version display and any new UI element MUST follow the latest Human Interface Guidelines and support Dynamic Type, Dark Mode, and full VoiceOver accessibility.
- **FR-013**: If the engine value cannot be produced at runtime, the app MUST remain stable (no crash) and MUST NOT display a fabricated version.

**Test-first & quality gates**

- **FR-014**: The engine behavior introduced by this feature MUST be developed test-first (a failing test precedes the behavior).
- **FR-015**: An automated "core ↔ Swift round-trip" test MUST assert that the value received in the app equals exactly the value the engine produced.
- **FR-016**: The change MUST keep the iOS Local Verification Gate and CI green: core formatting, linting, and tests; app linting; project generation; and a simulator build with passing app tests.

### Key Entities *(include if feature involves data)*

- **Engine Version**: The shared engine's build identifier, produced by the engine and surfaced in the app. It is non-empty, deterministic for a given build, and is the single source of truth for the value the app displays.
- **Round-Trip Value**: A typed value that travels app → engine → app. It has an app-provided input and an engine-computed output that MUST match exactly; if it can represent money, it MUST NOT be a floating-point number.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On 100% of launches, the root screen shows an engine version sourced from the shared engine, visible on first render (within ~1 second of the screen appearing).
- **SC-002**: Changing the engine's version and rebuilding changes the version shown in the app with zero edits to app UI text, demonstrating the value is engine-sourced.
- **SC-003**: For 100% of tested inputs (including boundary inputs), the round-trip value received by the app equals exactly the value the engine computed.
- **SC-004**: The round-trip produces identical output for identical input across repeated runs (100% reproducible).
- **SC-005**: Zero outbound network connections occur during launch, version retrieval, and the round-trip (verified by network monitoring / the privacy-egress expectation).
- **SC-006**: A person using assistive technology can perceive the engine version: it is announced by VoiceOver, remains legible at the largest Dynamic Type size without clipping, and renders correctly in both light and dark appearances.
- **SC-007**: All automated quality checks required to merge pass (green), including the new "core ↔ Swift round-trip" test.
- **SC-008**: No secrets, network entitlements, telemetry, or copyleft-licensed dependencies are added by the feature (verified by review of manifests and dependencies).

## Assumptions

- **Binding & delivery (locked decisions, mechanics deferred to planning)**: The app↔engine binding is realized with UniFFI; the compiled engine is delivered as a prebuilt binary framework (an XCFramework) covering real-device and simulator targets and wired into the Tuist-managed iOS project as a binary dependency. These are locked technical decisions per `docs/kaname-ios-plan.md` and `docs/HANDOFF.md`; their concrete realization belongs in `/speckit.plan`, not this spec.
- **First functions exposed**: The engine functions surfaced first are (a) the version string and (b) one small deterministic typed call. The exact signature/shape of the typed call is finalized during planning.
- **Engine always present**: The engine framework is embedded in the app bundle and therefore always present at runtime; "engine unavailable" is treated as a defensive edge case, not an expected state.
- **Display placement**: The engine-version display augments the existing branded root screen (Kaname branding is retained rather than removed); the exact placement and format is a design detail resolved during planning.
- **Money not exercised**: Money is not functionally exercised by this thin slice; the only related constraint is that the round-trip must not reintroduce floating-point money.
- **Starting point**: Work builds on the current repository scaffold — the engine already exposes a version function and core domain types, the app has a placeholder root screen, and the Tuist project and CI are green.
- **Toolchains**: Developer toolchains are provisioned via the repository's bootstrap flow, and CI runs the gates on macOS runners.

### Dependencies

- **Kaname Constitution v1.0.0** — privacy (zero-network free/core), determinism, pure platform-agnostic core, decimal money, Apache-2.0 open-core, native HIG/accessibility, and the test-first iOS Local Verification Gate.
- **Existing scaffold** — the shared engine crate (with its version function and domain types) and the iOS app scaffold (placeholder root screen, generated project, green CI).

## Out of Scope

Deferred to later milestones (P2+):

- Real bank/card statement parsing and the native-PDF-text → engine bridge.
- Categorization (T1/T2), de-duplication and transfer detection, balance-chain integrity, and reconciliation.
- Encrypted SQLite/SQLCipher storage and Keychain/Secure Enclave key management.
- Premium/cloud features: cross-device sync, managed AI, Account Aggregator one-click, and broker/CAS import.
- Full app experience: navigation flows, dashboards and charts, budgets, tags, search, and export.
