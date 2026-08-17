#if DEBUG

/// Placeholder for the DEBUG-only seeding path (`specs/019-debug-test-seeding/`).
///
/// In PR A this file does nothing on purpose. Its only job is to give the two absence proofs
/// something to find: `scripts/import-path-audit.sh`'s tenth scan, which requires every file in
/// this directory to open with `#if DEBUG`, and `scripts/release-absence-audit.sh`, which builds a
/// Release binary and refuses to find any of it there. Both gates are built, wired into CI and
/// watched failing against five deliberate breaks **before** PR B writes a line that fabricates
/// financial history — so the price is paid before the capability is bought.
///
/// The real implementation lands in PR B (T031): read `KANAME_SEED_SCENARIO`, return immediately
/// when it is absent, and otherwise write a named synthetic history through the shipped
/// `Store.importStatement`.
///
/// ⚠️ This must stay Swift, and inside `#if DEBUG`. `core/scripts/build-xcframework.sh` runs
/// `cargo build --release` **once** and links that single artifact into both Xcode
/// configurations, so `#[cfg(debug_assertions)]` is already off in the DEBUG app and a cargo
/// feature would compile straight into Release: there is no Rust construct that is present in
/// DEBUG and absent from Release (research R2).
enum DebugSeed {
    /// Does nothing until PR B. Nothing calls it yet — `KanameApp.swift` is untouched in PR A.
    static func applyIfRequested() {}
}

#endif
