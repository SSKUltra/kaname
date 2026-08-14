import Foundation
import KanameCore

/// The stages the import pipeline moves through, in order. Each boundary is a
/// cancellation checkpoint, so the person can back out of any slow stage before the
/// single atomic write.
enum ImportStage: Equatable, Sendable, CaseIterable {
    case reading
    case identifying
    case parsing
    case checking
    case saving
    case categorizing
}

/// What the integrity check concluded. Three states, never two: a statement that carries
/// nothing to check against must render as nothing at all — neither a pass nor a fail.
enum IntegrityOutcome: Equatable, Sendable {
    case agrees
    case needsReview
    case nothingToCheck
}

/// Everything the person sees after a successful import.
///
/// `transactionsImported == 0` is a success, not a failure: a statement with no rows in the
/// period imported correctly and there was simply nothing to add.
struct ImportSummary: Equatable, Sendable {
    /// Engine-supplied and rendered verbatim — the only engine string allowed on screen, so a
    /// tie-break between two readers claiming one document is always visible.
    let issuerDisplayName: String
    let last4: String?
    let accountIsNew: Bool
    /// Omitted entirely when the parse recovered no period — never faked from today's date.
    let period: DateInterval?
    let transactionsImported: Int
    let duplicatesSkipped: Int
    let categorized: Int
    let uncategorized: Int
    /// Rows that matched a transaction's shape but whose fields would not parse. Surfaced
    /// rather than silently dropped.
    let unreadableRows: Int
    /// The document carried text and named its issuer, yet no transaction was recognised in
    /// it, and nothing the statement printed confirms it was genuinely empty. Reporting that
    /// as "0 transactions" would tell a person they had no spending — this says the truth
    /// instead. Nothing wrong was written, so it is a notice, not a failure.
    let nothingRecognized: Bool
    let integrity: IntegrityOutcome
}

extension ImportSummary {
    /// What a statement whose transactions could not be recognised says to the person.
    static let nothingRecognizedNotice = IntegrityNotice(
        symbolName: "text.magnifyingglass",
        message: "Kaname opened this statement but couldn't make out any transactions in it. "
            + "Nothing was added. If you know it has spending on it, this layout is one Kaname "
            + "can't read yet.",
        isWarning: true
    )
}

/// What an account looks like to the person choosing one.
struct AccountCandidate: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let last4: String?
}

/// An account the person already has, as the front door shows it: enough to recognise it,
/// and enough to see that the data really is there.
struct ImportedAccount: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let last4: String?
    let isCreditCard: Bool
    let transactionCount: Int
    /// True when the account holds rows and every one of them is deleted or superseded. A
    /// boolean and not a count, deliberately: it is exactly enough to tell "this statement had
    /// no transactions" from "there is nothing to show", and a boolean cannot be rendered as a
    /// number that disagrees with the list (FR-008).
    let hasOnlyExcludedRows: Bool

    init(
        id: String,
        name: String,
        last4: String?,
        isCreditCard: Bool,
        transactionCount: Int,
        hasOnlyExcludedRows: Bool = false
    ) {
        self.id = id
        self.name = name
        self.last4 = last4
        self.isCreditCard = isCreditCard
        self.transactionCount = transactionCount
        self.hasOnlyExcludedRows = hasOnlyExcludedRows
    }
}

extension StoredTransaction {
    /// Is this a transaction the person actually has?
    ///
    /// ⚠️ `Store.listTransactions` is the store's **raw** view: it returns deleted rows, and
    /// it returns the superseded losers of a de-duplication. Both are kept on purpose — a
    /// re-import writes every row again and *links* the repeats rather than dropping them
    /// (FR-025), so the provenance survives. Neither is history, and any screen that counts
    /// or lists transactions must say so, or it will show a person their spending doubling
    /// the moment they import the same statement twice.
    ///
    /// This is **no longer what the front door counts** — that is `account_summaries()` now,
    /// so the count and the list come from one rule in one place. What this remains is the
    /// cross-language mirror of the engine's `LIVE` constant, and the two are asserted to
    /// agree row for row by `ios/Tests/LivenessParityTests.swift`. Deleting it would delete
    /// the only thing that would notice the two definitions drifting apart.
    var isLive: Bool { !isDeleted && supersededBy == nil }
}

/// The import stopped to ask which account this statement belongs to, because more than one
/// answer was possible — or none was. Nothing has been written at this point.
struct AccountChoice: Equatable, Sendable {
    /// Engine-supplied, rendered verbatim, so the person can see what Kaname thinks it read.
    let issuerDisplayName: String
    let last4: String?
    let candidates: [AccountCandidate]
    /// The name to offer for a brand-new account — the issuer's own, which is the only name
    /// Kaname has for it.
    let suggestedName: String
}

/// What the person decided when asked.
enum AccountDecision: Equatable, Sendable {
    case existing(id: String)
    case new(name: String)
}

/// Where an import ended: with a summary, or with a question only a person can answer.
enum ImportResult: Sendable {
    case finished(ImportSummary)
    case needsAccount(AccountChoice)

    /// The summary, when the import ran all the way through.
    var summary: ImportSummary? {
        if case .finished(let summary) = self { return summary }
        return nil
    }
}

/// Every way an import can end without writing anything.
///
/// No case carries an engine identifier, an error code, a bank code, a reader name, or raw
/// error text: each maps to exactly one hand-written sentence.
enum ImportFailure: Error, Equatable, Sendable {
    case notAPDF
    case passwordRequired
    case wrongPassword
    case noExtractableText
    case unreadable
    case unrecognizedIssuer
    case cancelled
    case storageUnavailable
    /// A different statement was asked for while one was still importing. Handing back the
    /// running import's summary would report one document's figures for another.
    case alreadyImporting
}

/// The copy deck. Every user-facing sentence in the import flow is hand-written here, so
/// nothing an engine or the system produced can reach the screen: no error code, no bank
/// code, no reader name, no `localizedDescription`.
extension ImportFailure {
    var title: String {
        switch self {
        case .notAPDF: return "That file isn't a PDF"
        case .passwordRequired: return "This statement is locked"
        case .wrongPassword: return "That password didn't work"
        case .noExtractableText: return "This looks like a scan"
        case .unreadable: return "Kaname couldn't open that file"
        case .unrecognizedIssuer: return "Kaname doesn't read this statement yet"
        case .cancelled: return "Import stopped"
        case .storageUnavailable: return "Kaname couldn't open your data"
        case .alreadyImporting: return "One statement at a time"
        }
    }

    var message: String {
        switch self {
        case .notAPDF:
            return "Kaname reads statement PDFs. Pick the PDF your bank sent you."
        case .passwordRequired:
            return "Enter the password your bank uses for this statement to continue."
        case .wrongPassword:
            return "Check the password your bank sent with this statement and try again."
        case .noExtractableText:
            return "There's no text inside this PDF to read. Ask your bank for the original PDF "
                + "rather than a scan or a photo."
        case .unreadable:
            return "The file may be damaged, or Kaname wasn't given permission to read it. "
                + "Try picking it again."
        case .unrecognizedIssuer:
            return "Nothing in Kaname recognises this statement's layout. Support for more "
                + "statements arrives in updates."
        case .cancelled:
            return "Nothing was saved. You can start again whenever you like."
        case .storageUnavailable:
            return "Your transactions are safe and nothing was changed. Try again in a moment."
        case .alreadyImporting:
            return "Kaname is still importing the statement you picked before this one. "
                + "Wait for it to finish, or stop it, and then try this one again."
        }
    }

    /// Icon plus text: meaning is never carried by colour or material alone.
    var symbolName: String {
        switch self {
        case .notAPDF: return "doc.questionmark"
        case .passwordRequired, .wrongPassword: return "lock.doc"
        case .noExtractableText: return "text.viewfinder"
        case .unreadable: return "exclamationmark.triangle"
        case .unrecognizedIssuer: return "questionmark.folder"
        case .cancelled: return "xmark.circle"
        case .storageUnavailable: return "externaldrive.badge.xmark"
        case .alreadyImporting: return "clock.arrow.circlepath"
        }
    }
}

/// What an integrity verdict says to the person, when it says anything at all.
struct IntegrityNotice: Equatable, Sendable {
    let symbolName: String
    let message: String
    /// Icon plus colour plus text — the colour is never the only thing carrying the meaning.
    let isWarning: Bool
}

extension IntegrityOutcome {
    /// `nothingToCheck` renders as nothing at all — neither a pass nor a fail — so it has no
    /// notice by design.
    var notice: IntegrityNotice? {
        switch self {
        case .agrees:
            return IntegrityNotice(
                symbolName: "checkmark.seal",
                message: "Every figure on this statement adds up.",
                isWarning: false
            )
        case .needsReview:
            return IntegrityNotice(
                symbolName: "exclamationmark.triangle",
                message: "Some figures on this statement don't add up. The transactions were "
                    + "imported and are marked for you to review.",
                isWarning: true
            )
        case .nothingToCheck:
            return nil
        }
    }
}

extension ImportFailure {
    /// Maps an extraction error at the actor's boundary. Anything unrecognised is reported as
    /// an unreadable file rather than leaking its own description.
    init(extraction error: Error) {
        switch error {
        case ExtractionFailure.notAPDF: self = .notAPDF
        case ExtractionFailure.passwordRequired: self = .passwordRequired
        case ExtractionFailure.wrongPassword: self = .wrongPassword
        case ExtractionFailure.noExtractableText: self = .noExtractableText
        // Extraction polls for cancellation between pages, and a stop asked for there is the
        // same stop as one asked for anywhere else — never an unreadable document.
        case is CancellationError: self = .cancelled
        default: self = .unreadable
        }
    }
}

extension IntegrityOutcome {
    /// The engine's verdict, kept in three states. A statement carrying nothing to check
    /// against reports neither a pass nor a fail.
    init(statement: ParsedStatement, kind: StatementKind) {
        switch kind {
        case .bankAccount:
            let result = checkBalanceChain(statement: statement)
            // `reason` is set only for the empty statement — the engine's own way of saying
            // there was nothing to walk.
            if result.reason != nil {
                self = .nothingToCheck
            } else {
                self = result.status == .reconciled ? .agrees : .needsReview
            }
        case .creditCard:
            switch reconcileStatement(statement: statement).status {
            case .some(.reconciled): self = .agrees
            case .some(.needsReview): self = .needsReview
            case .none: self = .nothingToCheck
            }
        }
    }
}
