import Foundation

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
    let integrity: IntegrityOutcome
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
        }
    }
}

extension IntegrityOutcome {
    /// `nothingToCheck` renders as nothing at all — neither a pass nor a fail — so it has no
    /// sentence by design.
    var message: String? {
        switch self {
        case .agrees:
            return "Every figure on this statement adds up."
        case .needsReview:
            return "Some figures on this statement don't add up. The transactions were imported "
                + "and are marked for you to review."
        case .nothingToCheck:
            return nil
        }
    }

    var symbolName: String? {
        switch self {
        case .agrees: return "checkmark.seal"
        case .needsReview: return "exclamationmark.triangle"
        case .nothingToCheck: return nil
        }
    }
}
