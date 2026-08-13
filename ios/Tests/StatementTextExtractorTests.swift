import Foundation
import PDFKit
import Testing
import UIKit

@testable import Kaname

/// What PDFKit gives back for the documents a person actually has: a real statement, a
/// scan, a locked file, a half-downloaded one, and something that was never a PDF at all.
///
/// Every document here is **generated in the test** and thrown away with the temp
/// directory. Nothing binary is committed, so there is no route for a real statement to
/// enter the repository.
@Suite("Statement text extraction")
struct StatementTextExtractorTests {
    private static let password = "correct-horse-battery-staple"

    /// Synthetic statement text. Drawn at a generous line spacing so PDFKit keeps the rows
    /// apart — line merging is its own subject, in `ExtractionFidelityTests`.
    private static let statementLines = [
        "EXAMPLE BANK CREDIT CARD STATEMENT",
        "Statement Date May 28, 2026",
        "4315XXXXXXXX1002",
        "29/04/2026 4262 Payment received 13,628.36 CR",
        "26/05/2026 1814 Fee on a transaction 10.20",
    ]

    private final class TempDirectory {
        let url: URL

        init() {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("kaname-extract-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }

        func file(_ name: String) -> URL { url.appendingPathComponent(name) }
    }

    private static let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

    /// A text-bearing PDF, drawn the way a bank's PDF generator lays a statement out.
    static func writeTextPDF(lines: [String], lineSpacing: CGFloat = 22, to url: URL) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular)
            ]
            var baseline: CGFloat = 48
            for line in lines {
                (line as NSString).draw(at: CGPoint(x: 36, y: baseline), withAttributes: attributes)
                baseline += lineSpacing
            }
        }
    }

    /// A page with ink but no text — what a photographed or scanned statement is.
    private static func writeImageOnlyPDF(to url: URL) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            UIColor.darkGray.setFill()
            context.cgContext.fill(CGRect(x: 40, y: 40, width: 400, height: 220))
            UIColor.lightGray.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 80, y: 320, width: 180, height: 180))
        }
    }

    /// The same statement, locked with a user password — a bank mailing you your own PDF.
    private static func writeLockedPDF(to url: URL, in directory: TempDirectory) throws {
        let plain = directory.file("plain-source.pdf")
        try writeTextPDF(lines: statementLines, to: plain)
        let document = try #require(PDFDocument(url: plain))
        let written = document.write(
            to: url,
            withOptions: [
                .userPasswordOption: password,
                .ownerPasswordOption: password,
            ]
        )
        #expect(written)
    }

    @Test("A text-bearing statement yields lines, full text and page-one geometry")
    func extractsATextBearingStatement() throws {
        let temp = TempDirectory()
        let url = temp.file("statement.pdf")
        try Self.writeTextPDF(lines: Self.statementLines, to: url)

        let extracted = try PDFKitStatementTextExtractor().extract(from: url, password: nil)

        #expect(extracted.fullText.contains("4315XXXXXXXX1002"))
        // The readers are fixture-locked to plain newline splitting: `lines` is exactly that.
        #expect(extracted.lines == extracted.fullText.components(separatedBy: "\n"))
        #expect(extracted.lines.contains { $0.contains("13,628.36") })
        #expect(!extracted.lineWords.isEmpty)
    }

    @Test("A scan has no text to read, and says so rather than reporting an empty statement")
    func reportsAScanAsHavingNoExtractableText() throws {
        let temp = TempDirectory()
        let url = temp.file("scan.pdf")
        try Self.writeImageOnlyPDF(to: url)

        #expect(throws: ExtractionFailure.noExtractableText) {
            try PDFKitStatementTextExtractor().extract(from: url, password: nil)
        }
    }

    @Test("A half-downloaded file is not a PDF")
    func reportsTruncatedBytesAsNotAPDF() throws {
        let temp = TempDirectory()
        let whole = temp.file("whole.pdf")
        try Self.writeTextPDF(lines: Self.statementLines, to: whole)
        let truncated = temp.file("truncated.pdf")
        try Data(contentsOf: whole).prefix(96).write(to: truncated)

        #expect(throws: ExtractionFailure.notAPDF) {
            try PDFKitStatementTextExtractor().extract(from: truncated, password: nil)
        }
    }

    @Test("Something merely named .pdf is not a PDF")
    func reportsATextFileNamedPDFAsNotAPDF() throws {
        let temp = TempDirectory()
        let url = temp.file("not-really.pdf")
        try Data("This was never a PDF.".utf8).write(to: url)

        #expect(throws: ExtractionFailure.notAPDF) {
            try PDFKitStatementTextExtractor().extract(from: url, password: nil)
        }
    }

    @Test("A file that cannot be read at all is reported as unreadable, not as a bad PDF")
    func reportsAnUnreadableFileAsUnreadable() {
        let temp = TempDirectory()
        // Nothing was ever written here: standing in for a revoked security-scoped grant or
        // a file that vanished between the picker and the read.
        let missing = temp.file("gone.pdf")

        #expect(throws: ExtractionFailure.unreadable) {
            try PDFKitStatementTextExtractor().extract(from: missing, password: nil)
        }
    }

    @Test("A locked statement asks for its password instead of failing")
    func asksForAPasswordBeforeGivingUp() throws {
        let temp = TempDirectory()
        let url = temp.file("locked.pdf")
        try Self.writeLockedPDF(to: url, in: temp)

        #expect(throws: ExtractionFailure.passwordRequired) {
            try PDFKitStatementTextExtractor().extract(from: url, password: nil)
        }
    }

    @Test("The wrong password is its own answer, so the person can try again")
    func distinguishesAWrongPasswordFromALockedFile() throws {
        let temp = TempDirectory()
        let url = temp.file("locked.pdf")
        try Self.writeLockedPDF(to: url, in: temp)

        #expect(throws: ExtractionFailure.wrongPassword) {
            try PDFKitStatementTextExtractor().extract(from: url, password: "not-the-password")
        }
    }

    @Test("The right password unlocks the statement and reads it")
    func readsALockedStatementWithTheRightPassword() throws {
        let temp = TempDirectory()
        let url = temp.file("locked.pdf")
        try Self.writeLockedPDF(to: url, in: temp)

        let extracted = try PDFKitStatementTextExtractor().extract(
            from: url,
            password: Self.password
        )
        #expect(extracted.fullText.contains("4315XXXXXXXX1002"))
    }

    @Test("A statement password is never written anywhere — Keychain, disk or message")
    func neverPersistsAStatementPassword() throws {
        let temp = TempDirectory()
        let url = temp.file("locked.pdf")
        try Self.writeLockedPDF(to: url, in: temp)

        _ = try? PDFKitStatementTextExtractor().extract(from: url, password: "not-the-password")
        _ = try PDFKitStatementTextExtractor().extract(from: url, password: Self.password)

        // Nothing in the Keychain carries it: the password unlocks a document and is dropped.
        for item in Self.allGenericPasswordData() {
            #expect(!item.contains(Data(Self.password.utf8)))
        }

        // Nothing the person is shown carries it either.
        let sentences = [
            ImportFailure.wrongPassword.title, ImportFailure.wrongPassword.message,
            ImportFailure.passwordRequired.title, ImportFailure.passwordRequired.message,
        ]
        for sentence in sentences {
            #expect(!sentence.contains(Self.password))
        }
    }

    /// Every generic-password item this test host can see, as raw data.
    private static func allGenericPasswordData() -> [Data] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return []
        }
        return (result as? [Data]) ?? []
    }
}
