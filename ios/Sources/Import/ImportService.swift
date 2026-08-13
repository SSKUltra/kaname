import Foundation
import KanameCore

/// Runs the whole import vertical off the main thread.
///
/// An actor for two reasons: it serialises the pipeline so a double-tapped Import cannot
/// start a second run, and it owns the in-flight `Task` itself, so backgrounding the app — a
/// view disappearing — never cancels an import in progress.
actor ImportService {
    private var inFlight: Task<ImportSummary, Error>?
    private let pipeline: ImportPipeline

    init(
        extractor: any StatementTextExtractor,
        store: Store,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        // The clock lives on this side, not in the core: the engine reads no wall-clock time,
        // so the timestamp is an input. Injectable so tests are deterministic.
        pipeline = ImportPipeline(extractor: extractor, store: store, now: now)
    }

    /// Import one statement. Throws `ImportFailure` and nothing else: every engine and store
    /// error is mapped at this boundary so no internal text can reach the UI.
    ///
    /// A second call while one is in flight joins the running import rather than starting a
    /// competing one, so a double-tapped Import button imports once and both callers see the
    /// same summary.
    func run(
        url: URL,
        password: String?,
        onStage: @escaping @Sendable (ImportStage) -> Void
    ) async throws -> ImportSummary {
        if let existing = inFlight {
            return try await existing.value
        }

        // An unstructured task, deliberately: it does not inherit the caller's cancellation,
        // so a view going away cannot abandon an import halfway.
        let task = Task { [pipeline] in
            try pipeline.run(url: url, password: password, onStage: onStage)
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    /// Stop the running import. Every checkpoint sits before the single write, so a
    /// cancelled import leaves the store byte-identical.
    func cancel() {
        inFlight?.cancel()
    }
}

/// The stages themselves, as a plain value so each one stays small and separately readable.
/// Every error it throws is already an `ImportFailure`.
private struct ImportPipeline: Sendable {
    let extractor: any StatementTextExtractor
    let store: Store
    let now: @Sendable () -> Date

    func run(
        url: URL,
        password: String?,
        onStage: @Sendable (ImportStage) -> Void
    ) throws -> ImportSummary {
        let text = try read(url: url, password: password, onStage: onStage)
        let (issuer, parsed) = try parse(text, onStage: onStage)

        try Self.checkCancellation()
        onStage(.checking)
        let integrity = IntegrityOutcome(statement: parsed, kind: issuer.kind)

        try Self.checkCancellation()
        onStage(.saving)
        let outcome = try persist(parsed, issuer: issuer, integrity: integrity)

        onStage(.categorizing)
        return ImportSummary(
            issuerDisplayName: issuer.displayName,
            last4: parsed.cardLast4,
            accountIsNew: outcome.accountCreated,
            period: Self.period(from: parsed),
            transactionsImported: Int(outcome.transactionsInserted),
            duplicatesSkipped: Int(outcome.duplicatesLinked),
            categorized: Int(outcome.categorized),
            uncategorized: Int(outcome.uncategorized),
            unreadableRows: parsed.erroredLines.count,
            integrity: integrity
        )
    }

    private func read(
        url: URL,
        password: String?,
        onStage: @Sendable (ImportStage) -> Void
    ) throws -> ExtractedText {
        onStage(.reading)
        do {
            return try extractor.extract(from: url, password: password)
        } catch {
            throw ImportFailure(extraction: error)
        }
    }

    private func parse(
        _ text: ExtractedText,
        onStage: @Sendable (ImportStage) -> Void
    ) throws -> (Issuer, ParsedStatement) {
        try Self.checkCancellation()
        onStage(.identifying)
        guard let issuer = detectIssuer(fullText: text.fullText) else {
            throw ImportFailure.unrecognizedIssuer
        }

        try Self.checkCancellation()
        onStage(.parsing)
        do {
            let parsed = try readStatement(
                issuer: issuer,
                lines: text.lines,
                fullText: text.fullText,
                lineWords: text.lineWords
            )
            return (issuer, parsed)
        } catch {
            // `UnknownIssuer` is unreachable — the issuer came from `detectIssuer` — and is a
            // programmer error, so it must never be reported as "we don't read this bank".
            throw ImportFailure.unreadable
        }
    }

    private func persist(
        _ parsed: ParsedStatement,
        issuer: Issuer,
        integrity: IntegrityOutcome
    ) throws -> ImportOutcome {
        let target = try resolveAccount(parsed, issuer: issuer)
        do {
            return try store.importStatement(
                request: Self.request(
                    parsed,
                    issuer: issuer,
                    target: target,
                    integrity: integrity,
                    now: now()
                )
            )
        } catch {
            throw ImportFailure.storageUnavailable
        }
    }

    /// Which account this statement belongs to, decided by comparing values the engine
    /// supplied. There is no bank name and no bank list here — and so no per-issuer branch.
    private func resolveAccount(_ parsed: ParsedStatement, issuer: Issuer) throws -> ImportAccountTarget {
        let accounts: [StoredAccount]
        do {
            accounts = try store.listAccounts()
        } catch {
            throw ImportFailure.storageUnavailable
        }

        let candidates = accounts.filter {
            $0.bankCode == issuer.bankCode
                && $0.isCreditCard == (issuer.kind == .creditCard)
                && $0.last4 == parsed.cardLast4
        }

        if candidates.count == 1, let existing = candidates.first {
            return .existing(id: existing.id)
        }

        return .new(
            name: issuer.displayName,
            bankCode: issuer.bankCode,
            isCreditCard: issuer.kind == .creditCard,
            last4: parsed.cardLast4,
            currency: parsed.lines.first?.currency ?? "INR"
        )
    }

    private static func request(
        _ parsed: ParsedStatement,
        issuer: Issuer,
        target: ImportAccountTarget,
        integrity: IntegrityOutcome,
        now: Date
    ) -> ImportRequest {
        let timestamp = ISO8601DateFormatter().string(from: now)
        // The store ignores the period entirely when there are no transactions, and writes no
        // statement row at all, so this fallback is never persisted and can never be read by
        // a person as a period the document did not carry.
        let periodEnd =
            parsed.periodEnd ?? parsed.lines.map(\.valueDate).max() ?? String(timestamp.prefix(10))

        return ImportRequest(
            account: target,
            bankCode: issuer.bankCode,
            periodStart: parsed.periodStart,
            periodEnd: periodEnd,
            // Rows that would not parse are as much a reason to look again as figures that
            // don't add up.
            needsReview: integrity == .needsReview || !parsed.erroredLines.isEmpty,
            source: .statement,
            transactions: parsed.lines.map {
                NewImportTransaction(
                    date: $0.valueDate,
                    descriptionRaw: $0.descriptionRaw,
                    amount: $0.amount,
                    direction: $0.direction,
                    currency: $0.currency,
                    sourceCategory: nil
                )
            },
            now: timestamp
        )
    }

    private static func checkCancellation() throws {
        do {
            try Task.checkCancellation()
        } catch {
            throw ImportFailure.cancelled
        }
    }

    /// A period is shown only when both ends were recovered. Half a period rendered as a
    /// range would be an invention, and the summary would rather say nothing.
    private static func period(from parsed: ParsedStatement) -> DateInterval? {
        guard let startText = parsed.periodStart, let endText = parsed.periodEnd,
            let start = dayFormatter.date(from: startText),
            let end = dayFormatter.date(from: endText),
            end >= start
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension ImportFailure {
    /// Maps an extraction error at the actor's boundary. Anything unrecognised is reported as
    /// an unreadable file rather than leaking its own description.
    fileprivate init(extraction error: Error) {
        switch error {
        case ExtractionFailure.notAPDF: self = .notAPDF
        case ExtractionFailure.passwordRequired: self = .passwordRequired
        case ExtractionFailure.wrongPassword: self = .wrongPassword
        case ExtractionFailure.noExtractableText: self = .noExtractableText
        default: self = .unreadable
        }
    }
}

extension IntegrityOutcome {
    /// The engine's verdict, kept in three states. A statement carrying nothing to check
    /// against reports neither a pass nor a fail.
    fileprivate init(statement: ParsedStatement, kind: StatementKind) {
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
