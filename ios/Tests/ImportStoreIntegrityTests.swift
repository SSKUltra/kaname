import CryptoKit
import Foundation
import KanameCore
import PDFKit
import Testing
import UIKit

@testable import Kaname

/// An import that cannot finish must leave a person's history exactly as it found it. Not
/// "no visible change" and not "no rows added" — the encrypted database file, byte for
/// byte, hashed before and after every way an import can fail.
///
/// Every document here is generated in the test and thrown away with the temp directory.
@Suite("A failed import leaves the store byte-identical")
struct ImportStoreIntegrityTests {
    private static let key = "77ee55cc33aa11ff99bb88dd44662200aabbccddeeff00112233445566778899"
    private static let password = "correct-horse-battery-staple"

    private final class TempDirectory {
        let url: URL

        init() {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("kaname-integrity-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }

        func file(_ name: String) -> URL { url.appendingPathComponent(name) }
    }

    /// A digest over every file the store owns — the database and any journal beside it —
    /// so a change to a write-ahead log counts as a change too.
    private static func digest(of directory: URL) -> String {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .sorted()
        var hasher = SHA256()
        for name in names {
            hasher.update(data: Data(name.utf8))
            hasher.update(data: (try? Data(contentsOf: directory.appendingPathComponent(name))) ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A store holding real history, so "unchanged" is a claim about actual data rather
    /// than about an empty file.
    private static func seededStore(in directory: URL) throws -> Store {
        let store = try Store.open(path: directory.appendingPathComponent("kaname.db").path, key: key)
        let account = try store.insertAccount(
            account: NewAccount(
                name: "Existing",
                bankCode: "EXAMPLE",
                isCreditCard: true,
                last4: "9999",
                currency: "INR",
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-01-01T00:00:00Z"
            )
        )
        _ = try store.insertTransaction(
            txn: NewTransaction(
                accountId: account,
                date: "2026-04-02",
                descriptionRaw: "EXISTING ROW",
                amount: Decimal(string: "1234.56", locale: Locale(identifier: "en_US_POSIX")) ?? 0,
                direction: .debit,
                currency: "INR",
                sourceCategory: nil,
                categoryId: nil,
                categorisedBy: nil,
                statementId: nil,
                createdAt: "2026-04-02T00:00:00Z",
                updatedAt: "2026-04-02T00:00:00Z"
            )
        )
        return store
    }

    private static func service(store: Store) -> ImportService {
        ImportService(
            extractor: PDFKitStatementTextExtractor(),
            store: store,
            now: { Date(timeIntervalSince1970: 1_786_000_000) }
        )
    }

    /// The full pipeline over a real PDF, asserting the failure and the byte-identity in one
    /// place — the two halves of "failed honestly" belong together.
    private static func expectFailureLeavesStoreIntact(
        _ expected: ImportFailure,
        document: (TempDirectory) throws -> URL,
        password: String? = nil
    ) async throws {
        let temp = TempDirectory()
        let dbDirectory = temp.url.appendingPathComponent("db", isDirectory: true)
        try FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
        let store = try seededStore(in: dbDirectory)
        let url = try document(temp)

        let before = digest(of: dbDirectory)
        await #expect(throws: expected) {
            try await service(store: store).run(url: url, password: password) { _ in }
        }
        #expect(digest(of: dbDirectory) == before)

        // The history that was already there is still readable, not merely still present.
        let account = try #require(try store.listAccounts().first)
        #expect(try store.listTransactions(accountId: account.id).count == 1)
    }

    @Test("A file that was never a PDF changes nothing")
    func notAPDFLeavesTheStoreIntact() async throws {
        try await Self.expectFailureLeavesStoreIntact(.notAPDF) { temp in
            let url = temp.file("not-really.pdf")
            try Data("This was never a PDF.".utf8).write(to: url)
            return url
        }
    }

    @Test("A file that cannot be read changes nothing")
    func unreadableLeavesTheStoreIntact() async throws {
        try await Self.expectFailureLeavesStoreIntact(.unreadable) { temp in
            temp.file("gone.pdf")
        }
    }

    @Test("A scan changes nothing")
    func noExtractableTextLeavesTheStoreIntact() async throws {
        try await Self.expectFailureLeavesStoreIntact(.noExtractableText) { temp in
            let url = temp.file("scan.pdf")
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                UIColor.darkGray.setFill()
                context.cgContext.fill(CGRect(x: 40, y: 40, width: 400, height: 220))
            }
            return url
        }
    }

    @Test("A locked statement changes nothing while it waits for its password")
    func passwordRequiredLeavesTheStoreIntact() async throws {
        try await Self.expectFailureLeavesStoreIntact(.passwordRequired) { temp in
            try Self.writeLockedPDF(in: temp)
        }
    }

    @Test("A wrong password changes nothing")
    func wrongPasswordLeavesTheStoreIntact() async throws {
        try await Self.expectFailureLeavesStoreIntact(
            .wrongPassword,
            document: { temp in try Self.writeLockedPDF(in: temp) },
            password: "not-the-password"
        )
    }

    @Test("A statement Kaname does not read changes nothing")
    func unrecognizedIssuerLeavesTheStoreIntact() async throws {
        try await Self.expectFailureLeavesStoreIntact(.unrecognizedIssuer) { temp in
            let url = temp.file("water-bill.pdf")
            try StatementTextExtractorTests.writeTextPDF(
                lines: [
                    "MUNICIPAL WATER SUPPLY",
                    "Consumer Number 88213344",
                    "Amount payable 612.00",
                ],
                to: url
            )
            return url
        }
    }

    private static func writeLockedPDF(in temp: TempDirectory) throws -> URL {
        let plain = temp.file("plain.pdf")
        try StatementTextExtractorTests.writeTextPDF(
            lines: ["EXAMPLE BANK CREDIT CARD STATEMENT", "4315XXXXXXXX1002"],
            to: plain
        )
        let locked = temp.file("locked.pdf")
        let document = try #require(PDFDocument(url: plain))
        #expect(
            document.write(
                to: locked,
                withOptions: [.userPasswordOption: password, .ownerPasswordOption: password]
            )
        )
        return locked
    }
}
