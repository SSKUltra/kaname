import Foundation
import KanameCore

/// Runs the whole import vertical off the main thread.
///
/// An actor for two reasons: it serialises the pipeline so a double-tapped Import cannot
/// start a second run, and it owns the in-flight `Task` itself, so backgrounding the app — a
/// view disappearing — never cancels an import in progress.
actor ImportService {
    /// The import currently running, and the document it is for — a second call can only join
    /// it when it names that same document.
    private var inFlight: (url: URL, task: Task<PipelineOutcome, Error>)?
    private let pipeline: ImportPipeline
    /// The statement waiting on a person to say which account it belongs to. Held only until
    /// they answer or walk away — nothing has been written for it yet.
    private var pendingChoice: PendingImport?

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
    /// Asking for the *same* document while it is already importing joins the running import
    /// rather than starting a competing one, so a double-tapped Import button imports once and
    /// both callers see the same summary. Asking for a *different* one is refused: returning
    /// the running import's summary would report one document's figures for another.
    func run(
        url: URL,
        password: String?,
        onStage: @escaping @Sendable (ImportStage) -> Void
    ) async throws -> ImportResult {
        if let existing = inFlight {
            guard existing.url == url else { throw ImportFailure.alreadyImporting }
            let outcome = try await existing.task.value
            return outcome.result
        }

        // An unstructured task, deliberately: it does not inherit the caller's cancellation,
        // so a view going away cannot abandon an import halfway.
        let task = Task { [pipeline] in
            try pipeline.run(url: url, password: password, onStage: onStage)
        }
        inFlight = (url, task)
        defer { inFlight = nil }
        let outcome = try await task.value
        pendingChoice = outcome.pending
        return outcome.result
    }

    /// Finish the import the person was asked about, against the account they picked or named.
    func resolveAccount(_ decision: AccountDecision) throws -> ImportSummary {
        guard let pending = pendingChoice else { throw ImportFailure.cancelled }
        pendingChoice = nil
        return try pipeline.finish(pending, decision: decision)
    }

    /// Stop the running import. Every checkpoint sits before the single write, so a
    /// cancelled import leaves the store byte-identical.
    func cancel() {
        inFlight?.task.cancel()
        pendingChoice = nil
    }
}

/// A parse waiting on an account decision. Everything needed to finish the import without
/// reading the file — or asking for its password — a second time.
struct PendingImport: Sendable {
    let issuer: Issuer
    let parsed: ParsedStatement
    let integrity: IntegrityOutcome
}

/// What one pipeline run produced: what to show, and what it is still waiting on.
private struct PipelineOutcome: Sendable {
    let result: ImportResult
    let pending: PendingImport?
}

/// The stages themselves, as a plain value so each one stays small and separately readable.
/// Every error it throws is already an `ImportFailure`.
private struct ImportPipeline: Sendable {
    let extractor: any StatementTextExtractor
    let store: Store
    let now: @Sendable () -> Date

    fileprivate func run(
        url: URL,
        password: String?,
        onStage: @Sendable (ImportStage) -> Void
    ) throws -> PipelineOutcome {
        let text = try read(url: url, password: password, onStage: onStage)
        let (issuer, parsed) = try parse(text, onStage: onStage)

        try Self.checkCancellation()
        onStage(.checking)
        let integrity = IntegrityOutcome(statement: parsed, kind: issuer.kind)
        let pending = PendingImport(issuer: issuer, parsed: parsed, integrity: integrity)

        try Self.checkCancellation()
        switch try resolveAccount(parsed, issuer: issuer) {
        case .resolved(let target):
            onStage(.saving)
            let summary = try persist(pending, target: target, onStage: onStage)
            return PipelineOutcome(result: .finished(summary), pending: nil)
        case .ask(let choice):
            // Nothing is written on this path: the question comes before the only write.
            return PipelineOutcome(result: .needsAccount(choice), pending: pending)
        }
    }

    /// Finish an import whose account the person has now chosen.
    fileprivate func finish(
        _ pending: PendingImport,
        decision: AccountDecision
    ) throws -> ImportSummary {
        let target: ImportAccountTarget
        switch decision {
        case .existing(let id):
            target = .existing(id: id, last4: pending.parsed.cardLast4)
        case .new(let name):
            target = Self.newAccount(named: name, issuer: pending.issuer, parsed: pending.parsed)
        }
        return try persist(pending, target: target) { _ in }
    }

    private func persist(
        _ pending: PendingImport,
        target: ImportAccountTarget,
        onStage: @Sendable (ImportStage) -> Void
    ) throws -> ImportSummary {
        let parsed = pending.parsed
        let outcome = try store(parsed, issuer: pending.issuer, target: target, integrity: pending.integrity)

        onStage(.categorizing)
        return ImportSummary(
            issuerDisplayName: pending.issuer.displayName,
            last4: parsed.cardLast4,
            accountIsNew: outcome.accountCreated,
            period: Self.period(from: parsed),
            transactionsImported: Int(outcome.transactionsInserted),
            duplicatesSkipped: Int(outcome.duplicatesLinked),
            categorized: Int(outcome.categorized),
            uncategorized: Int(outcome.uncategorized),
            unreadableRows: parsed.erroredLines.count,
            nothingRecognized: Self.recognisedNothing(parsed, integrity: pending.integrity),
            integrity: pending.integrity
        )
    }

    /// Did this parse come back empty without the statement itself vouching for that?
    ///
    /// A statement really can have no transactions in its period, and that is a success. But
    /// an extraction that lost the rows looks identical from here, so "no transactions" may
    /// only be reported as such when the statement's own printed figures agree — which is
    /// what an `agrees` verdict over zero rows means.
    ///
    /// A bank ledger cannot reach that state: with no anchor row the reader records no
    /// printed balance at all, so a quiet month and a lost extraction are indistinguishable
    /// and both take the cautious answer. Saying "Kaname couldn't make out any transactions"
    /// about a genuinely empty month is a small annoyance; saying "you had no spending"
    /// about a lost one is the thing this slice exists to prevent.
    private static func recognisedNothing(
        _ parsed: ParsedStatement,
        integrity: IntegrityOutcome
    ) -> Bool {
        parsed.lines.isEmpty && integrity != .agrees
    }

    private func read(
        url: URL,
        password: String?,
        onStage: @Sendable (ImportStage) -> Void
    ) throws -> ExtractedText {
        try Self.checkCancellation()
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

    private func store(
        _ parsed: ParsedStatement,
        issuer: Issuer,
        target: ImportAccountTarget,
        integrity: IntegrityOutcome
    ) throws -> ImportOutcome {
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

    /// Either the account this statement plainly belongs to, or the question to put to the
    /// person. There is no third option: Kaname never picks between two accounts itself.
    private enum AccountResolution {
        case resolved(ImportAccountTarget)
        case ask(AccountChoice)
    }

    /// Which account this statement belongs to, decided by comparing values the engine
    /// supplied. There is no bank name and no bank list here — and so no per-issuer branch.
    ///
    /// The matrix (FR-021, FR-022, FR-024), in order:
    ///
    /// - the statement's last-4 matches exactly one account → attach to it;
    /// - it matches none, but exactly one account for this issuer never learned its own
    ///   last-4 → attach, and the store fills that blank in;
    /// - the statement has a last-4 and no account for this issuer at all → create one;
    /// - anything else — no last-4 to go on, or more than one account it could be — → ask.
    private func resolveAccount(_ parsed: ParsedStatement, issuer: Issuer) throws -> AccountResolution {
        let accounts: [StoredAccount]
        do {
            accounts = try store.listAccounts()
        } catch {
            throw ImportFailure.storageUnavailable
        }

        let forIssuer = accounts.filter {
            $0.bankCode == issuer.bankCode && $0.isCreditCard == (issuer.kind == .creditCard)
        }

        if let last4 = parsed.cardLast4 {
            let byLast4 = forIssuer.filter { $0.last4 == last4 }
            if byLast4.count == 1, let match = byLast4.first {
                return .resolved(.existing(id: match.id, last4: last4))
            }
            if byLast4.isEmpty {
                let unnamed = forIssuer.filter { $0.last4 == nil }
                if unnamed.count == 1, let match = unnamed.first {
                    return .resolved(.existing(id: match.id, last4: last4))
                }
                if unnamed.isEmpty {
                    return .resolved(Self.newAccount(named: issuer.displayName, issuer: issuer, parsed: parsed))
                }
            }
        } else if forIssuer.count == 1, let only = forIssuer.first {
            return .resolved(.existing(id: only.id, last4: nil))
        }

        return .ask(
            AccountChoice(
                issuerDisplayName: issuer.displayName,
                last4: parsed.cardLast4,
                candidates: forIssuer.map {
                    AccountCandidate(id: $0.id, name: $0.name, last4: $0.last4)
                },
                suggestedName: issuer.displayName
            )
        )
    }

    private static func newAccount(
        named name: String,
        issuer: Issuer,
        parsed: ParsedStatement
    ) -> ImportAccountTarget {
        .new(
            name: name,
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
