import Foundation
import KanameCore
import Testing

@testable import Kaname

/// Builds the corpus the manual performance gate is measured against — as **statement PDFs**,
/// because that is the only door there is.
///
/// T139's G9–G12 need 10,000 transactions across 8 accounts on a real device, and FR-077
/// forbids a DEBUG seeding hook: nothing may put rows into a person's database except an
/// import they asked for. So the corpus is generated the way a person's own data arrives —
/// documents, read by the shipping pipeline, through the document picker. Nothing here runs in
/// the app, nothing is bundled with it, and the files are written outside the repository.
///
/// Each statement is drawn from a **proven layout signature** in `fixtures/geometry/`, so the
/// documents have the geometry the readers were designed against rather than a shape invented
/// here. Every value is synthetic by construction: a signature carries no values, and the ones
/// substituted in are generated (Constitution I, FR-064).
///
/// Every row of the corpus gets a **globally unique amount and description**, which is not
/// cosmetic: research R20 watched a first attempt silently de-duplicate 8,750 of its 10,000
/// rows, and a gate that measures an eighth of the corpus it claims to measure is worse than
/// no gate.
///
/// Run it with `make perf-corpus DIR=/path/to/write/it`. Skipped unless `KANAME_CORPUS_DIR` is
/// set, and ⚠️ it reaches this process only because the Makefile sets
/// `TEST_RUNNER_KANAME_CORPUS_DIR` — `xcodebuild` forwards nothing else into the simulator.
@Suite("Performance corpus generator (local, opt-in)")
struct PerformanceCorpusGenerator {
    private static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment["KANAME_CORPUS_DIR"], !path.isEmpty
        else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// One statement to draw: a layout to borrow, how many rows to print, and — when the same
    /// product appears twice — the card number that makes it a **second account** (FR-022).
    private struct Statement {
        let fixture: String
        let file: String
        let rows: Int
        var last4: String?
    }

    /// Eight accounts, six card products, 10,000 rows. Two products appear twice under a
    /// different card number, which is both how a person really holds two cards on one product
    /// and the only account-identity case a single-card corpus cannot show (FR-003, FR-022).
    private static let large: [Statement] = [
        Statement(fixture: "icici_amazonpay_card.json", file: "01-icici-1002.pdf", rows: 1250),
        Statement(
            fixture: "icici_amazonpay_card.json", file: "02-icici-7742.pdf", rows: 1250,
            last4: "7742"),
        Statement(fixture: "hdfc_swiggy_card.json", file: "03-hdfc-9070.pdf", rows: 1250),
        Statement(fixture: "sbi_cashback_card.json", file: "04-sbi.pdf", rows: 1250),
        Statement(fixture: "yes_kiwi_card.json", file: "05-yes-6686.pdf", rows: 1250),
        Statement(
            fixture: "yes_kiwi_card.json", file: "06-yes-4420.pdf", rows: 1250, last4: "4420"),
        Statement(fixture: "federal_scapia_card.json", file: "07-federal-4836.pdf", rows: 1250),
        Statement(fixture: "iob_rupay_card.json", file: "08-iob-0042.pdf", rows: 1250),
    ]

    /// G11's comparison corpus. Installed into a **fresh** store, never alongside the large
    /// one — the question it answers is whether 200 rows and 10,000 feel like the same app.
    private static let small: [Statement] = [
        Statement(fixture: "icici_amazonpay_card.json", file: "01-icici-1002.pdf", rows: 200)
    ]

    @Test("Write both corpora, and prove every document reads back the rows it printed")
    func writeTheCorpora() async throws {
        guard let root = Self.directory else { return }

        for (name, plan) in [("10000-rows", Self.large), ("200-rows", Self.small)] {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            var index = 0
            var total = 0
            for statement in plan {
                let fixture = try Self.draw(statement, startingAt: index)
                let url = folder.appendingPathComponent(statement.file)
                try GeometryFixtureRenderer.render(fixture, to: url)
                index += statement.rows

                // The gate is a person's afternoon: a document that reads back 900 of the
                // 1,250 rows it printed would be found on the device, hours later.
                let read = try Self.readBack(url)
                #expect(
                    read.count == statement.rows,
                    "perf-corpus: \(statement.file) printed \(statement.rows) rows and read back \(read.count)"
                )
                #expect(
                    read.issuer == fixture.expected.issuerId,
                    "perf-corpus: \(statement.file) was read as \(read.issuer)"
                )
                total += read.count
                print("perf-corpus:   \(statement.file) — \(read.issuer), \(read.count) transactions")
            }
            print("perf-corpus: \(name) — \(plan.count) document(s), \(total) transactions")
        }
        print("perf-corpus: written to \(root.path)")

        try await Self.proveItImports(root.appendingPathComponent("10000-rows", isDirectory: true))
    }

    // MARK: - Proving the corpus is the corpus

    /// Import all eight documents into a throwaway store and count what a person would see.
    ///
    /// Reading back a document proves it parses; it does not prove the eight of them become
    /// **eight accounts holding ten thousand live rows**. Two cards on one product could
    /// collapse into one account, and de-duplication could quietly supersede rows across
    /// accounts (R17, R20) — either would be discovered on the device, after the import, with
    /// the afternoon already spent. It also measures what the import itself costs, which is
    /// the one number a person cannot get from the gate.
    private static func proveItImports(_ folder: URL) async throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "pdf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try #require(!files.isEmpty)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-perf-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Store.open(
            path: directory.appendingPathComponent("kaname.db").path, key: TransactionCorpus.key)
        let service = ImportService(
            extractor: PDFKitStatementTextExtractor(),
            store: store,
            now: { Date(timeIntervalSince1970: 1_786_000_000) },
            completions: ImportCompletionSignal()
        )

        for file in files {
            let started = Date()
            let result = try await service.run(url: file, password: nil) { _ in }
            if case .needsAccount = result {
                // The document carries no readable card number, so Kaname asks rather than
                // guessing — which is what the person will have to answer on the device too.
                _ = try await service.resolveAccount(.new(name: "Synthetic Card", last4: nil))
                print("perf-corpus:   \(file.lastPathComponent) asks which account it belongs to")
            }
            let seconds = Date().timeIntervalSince(started)
            print("perf-corpus:   \(file.lastPathComponent) imported in \(String(format: "%.1f", seconds))s")
        }

        let summaries = try store.accountSummaries()
        let live = summaries.reduce(0) { $0 + Int($1.liveTransactionCount) }
        print("perf-corpus: imports as \(summaries.count) account(s), \(live) live transactions")
        #expect(summaries.count == 8, "the corpus must be eight accounts (G9, SC-006)")
        #expect(live == 10_000, "the corpus must hold ten thousand live rows (R20)")

        let started = Date()
        _ = try store.historyPage(query: HistoryQuery(accountId: nil, cursor: nil, limit: 50))
        let page = Date().timeIntervalSince(started) * 1000
        print("perf-corpus: first page of the imported corpus in \(String(format: "%.1f", page)) ms")
    }

    // MARK: - Drawing one statement

    /// A fixture's layout, its claim markers and its own row shapes, with generated rows in
    /// place of its three or four sample ones.
    private static func draw(_ statement: Statement, startingAt start: Int) throws -> GeometryFixture {
        let base = try GeometryFixtureLoader.load(statement.fixture)
        let debit = Self.template(in: base, direction: "Debit") ?? base.rows[0]
        let credit = Self.template(in: base, direction: "Credit")

        let rows = (0..<statement.rows).map { offset -> [String: String] in
            // Roughly one row in ten is a credit, so the direction word on screen is not a
            // constant — G7 asks whether debit and credit stay distinguishable without colour.
            let template = (offset % 10 == 7 ? credit : debit) ?? debit
            return Self.row(from: template, in: base, index: start + offset, of: statement.rows, at: offset)
        }

        let signature = base.signature
        let perPage = Self.rowsPerPage(of: base)
        #expect(perPage >= 5, "\(statement.fixture) fits only \(perPage) rows on a page")
        let pages = Array(
            repeating: perPage, count: Int((statement.rows + perPage - 1) / perPage))

        return GeometryFixture(
            issuerId: base.issuerId,
            kind: base.kind,
            signature: GeometryFixture.Signature(
                pageSize: signature.pageSize,
                fontSize: signature.fontSize,
                rowPitch: signature.rowPitch,
                firstRowY: signature.firstRowY,
                dateFormat: signature.dateFormat,
                columns: signature.columns,
                rowsPerPage: pages
            ),
            headerLines: statement.last4.map { Self.relabel(base.headerLines, as: $0) }
                ?? base.headerLines,
            footerLines: base.footerLines,
            extraLines: base.extraLines,
            rows: rows,
            expected: base.expected
        )
    }

    /// One generated row: the template's own cells, with the three that carry meaning replaced.
    private static func row(
        from template: [String: String],
        in base: GeometryFixture,
        index: Int,
        of count: Int,
        at offset: Int
    ) -> [String: String] {
        var row = template
        if let date = template["date"] {
            row["date"] = Self.dateCell(
                dayOffset: Self.day(offset, of: count), format: base.signature.dateFormat, like: date)
        }
        row["description"] = "SYNTHETIC MERCHANT \(String(format: "%05d", index))"
        if let amount = template["amount"] {
            row["amount"] = Self.amountCell(Self.amount(index), like: amount)
        }
        return row
    }

    /// Which day of the window this row falls on. The rows of one statement are spread across
    /// the **whole** window rather than a month, so a scrolled list crosses a year boundary and
    /// the heading's year rule (FR-035) can be read on the device rather than inferred.
    private static func day(_ offset: Int, of count: Int) -> Int {
        count <= 1 ? 0 : offset * (Self.windowDays - 1) / (count - 1)
    }

    private static let windowDays = 349
    private static let windowStart = DateComponents(year: 2025, month: 9, day: 1)

    /// Unique to the whole corpus, and to two decimal places: `index * 0.97` never repeats a
    /// value, and the range crosses the thousand mark so grouped and ungrouped amounts both
    /// appear (R20, FR-064).
    private static func amount(_ index: Int) -> Decimal {
        Decimal(10_000 + index * 97) / 100
    }

    private static func template(in base: GeometryFixture, direction: String) -> [String: String]? {
        for (row, expected) in zip(base.rows, base.expected.transactions)
        where expected.direction == direction {
            return row
        }
        return nil
    }

    /// The same header block, addressed to a different card. Only the trailing four digits of
    /// the masked number move, so every claim marker the reader identifies the document by is
    /// left exactly as the fixture proved it.
    private static func relabel(_ header: [String], as last4: String) -> [String] {
        header.map { line in
            guard line.range(of: "[X*x•]{2,}", options: .regularExpression) != nil,
                let tail = line.range(of: "[0-9]{4}(?![0-9])[^0-9]*$", options: .regularExpression)
            else { return line }
            return line.replacingCharacters(
                in: tail, with: last4 + line[tail].filter { !$0.isNumber })
        }
    }

    // MARK: - Cells

    private static func amountCell(_ value: Decimal, like template: String) -> String {
        let prefix = String(template.prefix { !$0.isNumber })
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = template.contains(",")
        formatter.groupingSeparator = ","
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let text = formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
        return prefix + text
    }

    /// A date in the fixture's own printed format — including its case, and including anything
    /// it prints beside the date, like the time some cards put in the same cell.
    private static func dateCell(dayOffset: Int, format: String, like template: String) -> String {
        var components = Self.windowStart
        components.day = (Self.windowStart.day ?? 1) + dayOffset
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let date = calendar.date(from: components) else { return template }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = Self.pattern(for: format)
        var text = formatter.string(from: date)

        let letters = template.filter(\.isLetter)
        if !letters.isEmpty, letters == letters.uppercased() {
            text = text.uppercased()
        }
        if let extra = template.range(of: " · ") {
            text += template[extra.lowerBound...]
        }
        return text
    }

    private static func pattern(for format: String) -> String {
        switch format {
        case "DD-MMM-YYYY": "dd-MMM-yyyy"
        case "DD MMM YY": "dd MMM yy"
        case "DD-MM-YYYY": "dd-MM-yyyy"
        default: "dd/MM/yyyy"
        }
    }

    /// How many rows fit below the first one, leaving the footer its own line. Derived from the
    /// signature rather than chosen, so a fixture with a different pitch or a higher table still
    /// produces a document that fits its page.
    private static func rowsPerPage(of base: GeometryFixture) -> Int {
        let signature = base.signature
        let firstRowTop = signature.height - signature.firstRowY
        let usable = signature.height - firstRowTop
        return Int(usable / signature.rowPitch) - 1 - base.footerLines.count
    }

    // MARK: - Reading it back

    private struct ReadBack {
        let issuer: String
        let count: Int
    }

    /// The document read by the **shipping** extractor and the **shipping** readers — the same
    /// path the phone will take, so a document that will not read is found here.
    private static func readBack(_ url: URL) throws -> ReadBack {
        let text = try PDFKitStatementTextExtractor().extract(from: url, password: nil)
        guard let issuer = detectIssuer(fullText: text.fullText) else {
            return ReadBack(issuer: "unrecognised", count: 0)
        }
        let parsed = try readStatement(
            issuer: issuer, lines: text.lines, fullText: text.fullText, lineWords: text.lineWords)
        return ReadBack(issuer: issuer.id, count: parsed.lines.count)
    }
}
