import Foundation
import Observation

/// The UI's view of an import. Holds presentation state only — no pipeline logic — so the
/// only work on the main thread is rendering.
@MainActor
@Observable
final class ImportViewModel {
    enum Phase: Equatable {
        case idle
        case running(ImportStage)
        case finished(ImportSummary)
        case failed(ImportFailure)
    }

    private(set) var phase: Phase = .idle

    /// Bound to the password prompt's `SecureField`. Cleared the moment the prompt goes away,
    /// so a statement password is never held beyond the unlock attempt that needs it.
    var passwordEntry: String = ""
    var isPromptingForPassword: Bool = false

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    var summary: ImportSummary? {
        if case .finished(let summary) = phase { return summary }
        return nil
    }

    var failure: ImportFailure? {
        if case .failed(let failure) = phase { return failure }
        return nil
    }

    func reset() {
        phase = .idle
        clearPassword()
    }

    func clearPassword() {
        passwordEntry = ""
        isPromptingForPassword = false
    }
}
