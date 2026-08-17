#if DEBUG

import Foundation
import KanameCore

/// The DEBUG-only seeding path: a launch that names a scenario gets that history, written into
/// the app's own encrypted store through the app's own import call, before any screen exists.
///
/// It is the answer to a gap 018 measured rather than guessed at. The transaction list is
/// behind an import, the import is behind the system document picker, and no automated run can
/// drive that picker — so every accessibility audit in this repository had only ever run
/// against an empty screen, and both defects a person found on a populated list were found by
/// hand. This is how a machine reaches that screen.
///
/// ⚠️ **It must stay Swift, and it must stay inside `#if DEBUG`.**
/// `core/scripts/build-xcframework.sh` runs `cargo build --release` **once** and links that
/// single artifact into both Xcode configurations, so `#[cfg(debug_assertions)]` is already off
/// in the DEBUG app and a cargo feature would compile straight into Release: there is no Rust
/// construct present in DEBUG and absent from Release (research R2). Two gates hold the
/// boundary — `scripts/import-path-audit.sh`'s tenth scan over these sources, and
/// `scripts/release-absence-audit.sh`, which builds a Release binary and refuses to find any of
/// this in it.
enum DebugSeed {
    static let environmentKey = "KANAME_SEED_SCENARIO"

    /// Apply the requested history, or do nothing at all.
    ///
    /// Called from `KanameApp.init()`, because the history has to be complete before the first
    /// `View` body is evaluated: a screen that renders while rows are still arriving is a race
    /// with the first screenshot, and an asynchronous seed would make every seeded assertion
    /// timing-dependent (FR-002).
    static func applyIfRequested() {
        guard let name = ProcessInfo.processInfo.environment[environmentKey] else { return }
        guard let scenario = SeedScenario.named(name) else {
            // ⚠️ Deliberate, and the single most important line here. Falling back to an empty
            // app would mean an accessibility audit reporting success against a blank screen —
            // the exact failure this slice exists to remove. `App.init()` has no UI and no
            // channel to report on, so the only signal a test can observe is the app failing to
            // reach the foreground, which every UI test in this repository already asserts
            // (FR-006, SC-016, research R13).
            fatalError(
                "\(environmentKey)=\(name): no such scenario. "
                    + "Declared: \(SeedScenario.declaredNames)")
        }
        reset()
        apply(scenario)
    }

    /// Delete the database and its sidecars — **inside** the same request as the seed.
    ///
    /// The Keychain key is deliberately left alone, so the next open mints a fresh database
    /// encrypted under the app's **own** key, fetched the app's own way. No test key exists in
    /// any target, and none is needed (FR-017, SC-013).
    ///
    /// `-wal` and `-shm` are removed defensively: `Store::open` sets no `journal_mode`, so the
    /// live sidecar today is `-journal`, but a stale `-wal` left beside a deleted database by a
    /// later slice is a corruption report nobody would connect to this file.
    private static func reset() {
        let database = StoreLocator(keyStore: KeychainKeyStore()).databaseURL
        for suffix in ["", "-journal", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: database.path + suffix)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                fatalError("\(environmentKey): could not reset the store before seeding.")
            }
        }
    }

    /// Write the declared statements, in declaration order, one `importStatement` each.
    ///
    /// Declaration order is the only ordering input, and it is written down: it fixes the
    /// accounts' `rowid`s — and so the front door's order and the history's account tie-break —
    /// and it decides which of two matching rows survives a de-duplication.
    private static func apply(_ scenario: SeedScenario) {
        do {
            let store = try StoreProvider.shared()
            var accountIDs: [String: String] = [:]
            for statement in scenario.statements {
                let request = SeedScenarioBuilder.request(
                    for: statement, in: scenario,
                    existingAccountID: accountIDs[statement.accountName])
                let outcome = try store.importStatement(request: request)
                accountIDs[statement.accountName] = outcome.accountId
            }
        } catch {
            // Nothing is caught and degraded. `import_statement` is one SQLite transaction, so
            // a throw has already rolled the whole statement back — this makes the non-event
            // observable instead of leaving a partly-seeded screen to be audited. The message
            // carries a store error, which names SQL and never a transaction's own fields.
            fatalError("\(environmentKey)=\(scenario.name): the seed failed. \(error)")
        }
    }
}

#endif
