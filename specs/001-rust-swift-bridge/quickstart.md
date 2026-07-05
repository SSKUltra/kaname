# Quickstart: Build & Verify the Rust ↔ Swift Bridge

**Feature**: `001-rust-swift-bridge` | **Date**: 2026-07-05

How to build the engine framework, run the app, and pass the iOS Local Verification Gate
for this feature. Assumes macOS with Xcode 26 (local) / `macos-15` (CI).

---

## 0. One-time setup

```bash
make bootstrap          # rustup + iOS targets, tuist, swiftlint, swift-format
# Local Xcode 26 only: ensure the simulator the gate uses exists.
xcrun simctl create "iPhone 16" "iPhone 16" || true
```

`rust-toolchain.toml` already pins the three iOS targets
(`aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`).

---

## 1. Build the engine XCFramework (must precede project generation)

```bash
make core-xcframework
```

This target:
1. builds `libkaname_core.a` for device + both simulator arches,
2. generates Swift bindings (`KanameCore.swift` + C header + modulemap),
3. `lipo`s the simulator arches into one universal static lib,
4. runs `xcodebuild -create-xcframework` → `ios/Frameworks/KanameCoreFFI.xcframework`,
5. places the generated Swift at `ios/Generated/KanameCore.swift`.

Both outputs are **git-ignored** build artifacts (regenerated on demand).

---

## 2. Generate the Xcode project & run the app

```bash
make ios-gen           # depends on core-xcframework; runs `tuist generate`
```

Open `ios/Kaname.xcworkspace`, run the `Kaname` scheme on the **iPhone 16** simulator.
The root screen shows Kaname branding **plus** the live engine version
(e.g. "Engine v0.1.0") produced by `engineVersion()`.

**Prove it is engine-sourced (SC-002):** bump `version` in
`core/crates/kaname-core/Cargo.toml`, re-run `make core-xcframework ios-gen`, relaunch —
the displayed version changes with **no edit to app UI text**.

**Prove it is local (SC-005):** enable Airplane Mode; the version and round-trip still work.

---

## 3. Run the verification gate (order matters)

```bash
# Core (Rust) — pure engine truth, test-first
make core-test         # cargo test (incl. normalize_transaction + round-trip vectors)
make core-lint         # cargo fmt --check + clippy -D warnings

# iOS — builds the xcframework, generates, then simulator build + tests
make lint              # swiftlint --strict + swift-format lint --strict
make ios-test          # core-xcframework → tuist generate → xcodebuild build+test
```

All must be green (FR-016, SC-007). The key new test is the Swift Testing
**"core ↔ Swift round-trip"** (`import KanameCore`), asserting the app receives exactly
what the engine produced.

---

## 4. What "done" looks like (acceptance)

- [ ] Root screen shows the engine version, sourced from `engineVersion()` (FR-001/FR-002).
- [ ] Changing the crate version changes the displayed value, no UI-text edit (SC-002).
- [ ] Version + round-trip work in Airplane Mode (SC-005).
- [ ] `normalizeTransaction` returns exactly the engine-computed value, incl. boundary
      inputs; money is a Swift `Decimal`, never a float (FR-004/FR-010, SC-003).
- [ ] Version display is Dynamic-Type legible, Dark-Mode correct, VoiceOver-announced (SC-006).
- [ ] Rust + Swift round-trip tests exist and were written test-first (FR-014/FR-015).
- [ ] `cargo fmt/clippy/test`, SwiftLint, swift-format, `tuist generate`, simulator
      build+test all green locally and in CI (SC-007).
- [ ] No network entitlement, telemetry, secrets, or copyleft (GPL/AGPL/LGPL) dep added (SC-008).

---

## 5. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `tuist generate` fails: xcframework not found | Run `make core-xcframework` first (ordering). |
| `xcodebuild` can't find "iPhone 16" | Create it: `xcrun simctl create "iPhone 16" "iPhone 16"`. |
| `import KanameCore` fails | Confirm the `KanameCore` framework target links `KanameCoreFFI.xcframework` and includes `ios/Generated/KanameCore.swift`. |
| Linker: missing `libkaname_core` symbols | Ensure the xcframework device/sim slices built for all three targets and `lipo` merged the sim arches. |
| Decimal parse crash in Swift | Bridge string is en_US_POSIX; verify `uniffi.toml` `lift` uses that locale. |
| CI `tuist` aborts (exit 134) | Runner must be `macos-15` (not `macos-14`). |
