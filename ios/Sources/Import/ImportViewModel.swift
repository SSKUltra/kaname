import Foundation
import KanameCore
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
        /// Waiting on the person to say which account this statement belongs to. Nothing has
        /// been written yet, and nothing will be until they answer.
        case askingForAccount(AccountChoice)
    }

    private(set) var phase: Phase = .idle

    /// What the person has imported so far. Empty means a genuinely fresh install, which is
    /// the one thing the front door needs to know.
    private(set) var accounts: [ImportedAccount] = []

    /// Bound to the password prompt's `SecureField`. Cleared the moment the prompt goes away,
    /// so a statement password is never held beyond the unlock attempt that needs it.
    var passwordEntry: String = ""
    var isPromptingForPassword: Bool = false
    /// Set when a password was wrong, so the prompt can say so without becoming a failure
    /// screen that sends the person off to pick a different file.
    private(set) var passwordPromptMessage: String?

    private let makeService: @Sendable () throws -> ImportService
    private var service: ImportService?
    /// The document awaiting a password. Held only until the prompt is answered or dismissed.
    private var pendingURL: URL?

    init(
        makeService: @escaping @Sendable () throws -> ImportService = { try ImportViewModel.liveService() }
    ) {
        self.makeService = makeService
    }

    /// The real wiring: PDFKit for extraction, and the encrypted store this device already
    /// holds the key for — the *same* `Store` the transaction list reads through, so a page
    /// read can never land inside an import's transaction. Deliberately off the main actor:
    /// opening the database is I/O.
    nonisolated static func liveService() throws -> ImportService {
        ImportService(
            extractor: PDFKitStatementTextExtractor(),
            store: try StoreProvider.shared()
        )
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    var stage: ImportStage? {
        if case .running(let stage) = phase { return stage }
        return nil
    }

    var summary: ImportSummary? {
        if case .finished(let summary) = phase { return summary }
        return nil
    }

    var failure: ImportFailure? {
        if case .failed(let failure) = phase { return failure }
        return nil
    }

    var accountChoice: AccountChoice? {
        if case .askingForAccount(let choice) = phase { return choice }
        return nil
    }

    /// Finish an import against the account the person just picked or named.
    func chooseAccount(_ decision: AccountDecision) async {
        guard let service else { return }
        phase = .running(.saving)
        do {
            phase = .finished(try await service.resolveAccount(decision))
            await refreshAccounts()
        } catch let failure as ImportFailure {
            phase = .failed(failure)
        } catch {
            phase = .failed(.storageUnavailable)
        }
        pendingURL = nil
    }

    /// Reload what the person has imported. A store that will not open leaves the list alone
    /// rather than emptying it: telling someone their accounts are gone would be a lie, and
    /// the failure they can act on is the one the import itself reports.
    func refreshAccounts() async {
        guard let service = try? resolveService() else { return }
        accounts = (try? await service.importedAccounts()) ?? accounts
    }

    func importStatement(at url: URL) async {
        pendingURL = url
        await run(url: url, password: nil)
    }

    /// Retry the pending document with the password the person just typed.
    func submitPassword() async {
        guard let url = pendingURL else { return }
        let password = passwordEntry
        clearPassword()
        await run(url: url, password: password)
    }

    func cancel() async {
        await service?.cancel()
    }

    /// Dismissing the document picker, or the password prompt, is not a failed import — the
    /// person simply chose not to import anything.
    func reset() {
        phase = .idle
        pendingURL = nil
        clearPassword()
    }

    func clearPassword() {
        passwordEntry = ""
        isPromptingForPassword = false
    }

    private func run(url: URL, password: String?) async {
        phase = .running(.reading)
        do {
            let service = try resolveService()
            let result = try await service.run(url: url, password: password) { stage in
                Task { @MainActor [weak self] in
                    // A stage arriving after the import finished must not reopen progress.
                    guard let self, self.isRunning else { return }
                    self.phase = .running(stage)
                }
            }
            pendingURL = nil
            switch result {
            case .finished(let summary):
                phase = .finished(summary)
                await refreshAccounts()
            case .needsAccount(let choice): phase = .askingForAccount(choice)
            }
        } catch ImportFailure.passwordRequired {
            promptForPassword(message: nil)
        } catch ImportFailure.wrongPassword {
            promptForPassword(message: ImportFailure.wrongPassword.message)
        } catch let failure as ImportFailure {
            pendingURL = nil
            phase = .failed(failure)
        } catch {
            pendingURL = nil
            phase = .failed(.unreadable)
        }
    }

    private func promptForPassword(message: String?) {
        passwordPromptMessage = message
        passwordEntry = ""
        isPromptingForPassword = true
        phase = .idle
    }

    private func resolveService() throws -> ImportService {
        if let service { return service }
        do {
            let service = try makeService()
            self.service = service
            return service
        } catch {
            throw ImportFailure.storageUnavailable
        }
    }
}
