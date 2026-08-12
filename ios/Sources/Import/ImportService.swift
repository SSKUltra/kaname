import Foundation
import KanameCore

/// Runs the whole import vertical off the main thread.
///
/// An actor for two reasons: it serialises the pipeline so a double-tapped Import cannot
/// start a second run, and it owns the in-flight `Task` itself, so backgrounding the app — a
/// view disappearing — never cancels an import in progress.
actor ImportService {
    private var inFlight: Task<ImportSummary, Error>?

    private let extractor: any StatementTextExtractor
    private let store: Store
    /// The clock lives here, not in the core: the engine reads no wall-clock time, so the
    /// timestamp is a caller-supplied input. Injectable so tests are deterministic.
    private let now: @Sendable () -> Date

    init(
        extractor: any StatementTextExtractor,
        store: Store,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.extractor = extractor
        self.store = store
        self.now = now
    }

    /// Import one statement. Throws `ImportFailure` and nothing else: every engine and store
    /// error is mapped at this boundary so no internal text can reach the UI.
    func run(
        url: URL,
        password: String?,
        onStage: @escaping @Sendable (ImportStage) -> Void
    ) async throws -> ImportSummary {
        _ = (url, password, onStage)
        throw ImportFailure.cancelled
    }
}
