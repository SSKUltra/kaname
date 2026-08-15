import Foundation
import KanameCore
import Testing

@testable import Kaname

/// The store, the service and the two statements the account-attribution suites share.
///
/// One copy. `ImportAccountResolutionTests` holds the FR-024 matrix and `ImportStatedLast4Tests`
/// holds what a person may add to it, and a fixture living inside either one is a fixture the
/// other would copy.
///
/// All statement text is 100% synthetic.
enum ImportAccountFixture {
    static let key = "abcd1234ef567890abcd1234ef567890abcd1234ef567890abcd1234ef567890"
    static let anyURL = URL(fileURLWithPath: "/dev/null/statement.pdf")

    private struct StubExtractor: StatementTextExtractor {
        let text: ExtractedText

        func extract(from url: URL, password: String?) throws -> ExtractedText { text }
    }

    static func tempDatabase() -> (dir: URL, path: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-accounts-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("kaname.db").path)
    }

    static func service(lines: [String], store: Store) -> ImportService {
        ImportService(
            extractor: StubExtractor(
                text: ExtractedText(
                    lines: lines,
                    fullText: lines.joined(separator: "\n"),
                    lineWords: []
                )
            ),
            store: store,
            now: { Date(timeIntervalSince1970: 1_786_000_000) }
        )
    }

    /// A card statement that names its last-4.
    static let cardWithLast4 = [
        "ICICI Bank Statement",
        "Statement Date May 28, 2026",
        "4315XXXXXXXX1002",
        "26/05/2026 1814 Fee on gaming transaction 0 10.20",
    ]

    /// A ledger that never names an account number — the FR-024 case. Its reference column
    /// deliberately carries no long digit run either, or the reader would recover a last-4
    /// from that instead.
    static let ledgerWithoutLast4 = [
        "HDFC BANK LIMITED",
        "Statementof account",
        "From : 01/04/2026 To : 30/04/2026",
        "Date Narration Chq./Ref.No. ValueDt WithdrawalAmt. DepositAmt. ClosingBalance",
        "01/04/26 UPI-EXAMPLEMERCHANT REFALPHA 01/04/26 5,000.00 95,000.00",
        "16/04/26 NEFTCR-EXAMPLEEMPLOYER REFBETA 16/04/26 50,000.00 1,45,000.00",
        "OpeningBalance DrCount CrCount Debits Credits ClosingBal",
        "1,00,000.00 1 1 5,000.00 50,000.00 1,45,000.00",
    ]

    static func account(
        _ name: String,
        bankCode: String,
        isCreditCard: Bool,
        last4: String?
    ) -> NewAccount {
        NewAccount(
            name: name,
            bankCode: bankCode,
            isCreditCard: isCreditCard,
            last4: last4,
            currency: "INR",
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

}
