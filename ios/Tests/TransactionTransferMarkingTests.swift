import Foundation
import KanameCore
import Testing

@testable import Kaname

/// How a row that carries the transfer **flag** is rendered.
///
/// ⚠️ **Kaname does not detect transfers, and nothing here says it does.** `detectTransfers()`
/// is called from no Swift source file, so `is_transfer` is `0` on every row of a real install
/// (research R18, FR-018). Every flag in this suite is set by the test — one of them by the
/// engine's own `detect_transfers` over a real store, invoked here and nowhere in the app.
/// What is proved is the **marking**: that a flagged row says so in a word and a symbol rather
/// than a colour, that it is announced, and — the one a person would actually be hurt by —
/// that it is still *in the list*. A transfer is two real transactions, and hiding them would
/// make the list disagree with the count beside it.
///
/// All data is synthetic (Constitution I).
@Suite("A row carrying the transfer flag is marked, not hidden")
struct TransactionTransferMarkingTests {
    private static let key = "88aa77bb66cc55dd44ee33ff2200119988aabbccddeeff00112233445566aabb"

    private static func row(
        category: String? = nil,
        isTransfer: Bool = false,
        description: String = "SYNTHETIC ROW"
    ) -> TransactionRow {
        TransactionRow(
            HistoryRow(
                id: "row",
                accountId: "account-1",
                accountName: "Everyday Savings",
                accountLast4: "1123",
                date: "2026-07-15",
                descriptionRaw: description,
                amount: TransactionCorpus.decimal("450.00"),
                direction: .debit,
                currency: "INR",
                categoryName: category,
                isTransfer: isTransfer
            ))
    }

    @Test("A row the engine has marked as a transfer carries the marking")
    func aMarkedRowIsMarked() {
        let marked = Self.row(isTransfer: true)

        // A word, and a symbol beside it — never a colour on its own, which is invisible to
        // a person who cannot distinguish it and gone entirely in a screenshot at grayscale
        // (FR-018, FR-071).
        #expect(marked.isTransfer)
        #expect(TransactionListStrings.transfer == "Transfer")
        #expect(marked.accessibilityLabel.hasSuffix(TransactionListStrings.transferAnnouncement))
    }

    @Test("A row with no marking says nothing about transfers at all")
    func anUnmarkedRowIsSilent() {
        let plain = Self.row(isTransfer: false)

        #expect(!plain.isTransfer)
        #expect(!plain.accessibilityLabel.contains(TransactionListStrings.transferAnnouncement))
    }

    @Test("A marked row is still a row, and is never hidden from the list")
    func aMarkedRowIsStillShown() async throws {
        // The marking is a fact about a transaction, not a reason to remove it: a person who
        // moved money between their own accounts still has two transactions, and a list that
        // quietly hid them would be missing rows the front-door count includes (US6 AS-7).
        let rows = [
            historyRow("plain", "2026-07-15"),
            HistoryRow(
                id: "marked", accountId: "account-1", accountName: TransactionCorpus.everyday,
                accountLast4: "1123", date: "2026-07-15", descriptionRaw: "SYNTHETIC TRANSFER",
                amount: TransactionCorpus.decimal("5000.00"), direction: .debit, currency: "INR",
                categoryName: nil, isTransfer: true),
        ]
        let model = await TransactionListViewModel(
            history: HistoryDouble(
                pages: [HistoryPage(rows: rows, cursor: nil)], summaries: [accountSummary(2)]),
            clock: listClock
        )

        await model.onAppear()

        #expect(await model.groups.flatMap(\.rows).map(\.id) == ["plain", "marked"])
        #expect(await model.groups.first?.rows.count == 2)
    }

    @Test("The marking is a bare noun and claims nothing about how it got there")
    func theMarkingClaimsNothing() {
        // The app does not run detection, and no word on screen may suggest it did.
        let words = [TransactionListStrings.transfer, TransactionListStrings.transferAnnouncement]
        for word in words {
            for claim in ["detect", "found", "match", "auto", "identif", "link"] {
                #expect(!word.lowercased().contains(claim), "\"\(word)\" claims \"\(claim)\"")
            }
        }
        #expect(Self.row(isTransfer: true).accessibilityLabel.contains(", transfer"))
    }

    // MARK: - Over the bridge, with the flag set by the engine itself

    @Test("Both legs of a flagged pair reach the list, marked, and neither is hidden")
    func bothLegsOfAFlaggedPairAreShownAndMarked() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaname-marking-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Store.open(
            path: directory.appendingPathComponent("kaname.db").path, key: Self.key)

        let bank = try store.insertAccount(account: Self.account("Everyday Savings", isCreditCard: false))
        let card = try store.insertAccount(account: Self.account("Travel Card", isCreditCard: true))
        _ = try store.insertTransaction(txn: Self.leg(bank, "CREDIT CARD PAYMENT", .debit))
        _ = try store.insertTransaction(txn: Self.leg(card, "PAYMENT RECEIVED", .credit))

        // The flag is set **here**, by the test, exactly as `StoreTransferTests` does. The app
        // never makes this call (research R18).
        let detection = try store.detectTransfers()
        #expect(detection.pairsLinked == 1)

        let model = await TransactionListViewModel(
            history: TransactionHistoryService(store: store), clock: listClock, pageSize: 50)
        await model.onAppear()

        let rows = await model.groups.flatMap(\.rows)
        // Two transactions, both still there. A list that "tidied away" a transfer would show
        // a person fewer rows than the front door counts for them (US6 AS-7, FR-006).
        let count = rows.count
        let everyRowIsMarked = rows.allSatisfy(\.isTransfer)
        #expect(count == 2)
        #expect(everyRowIsMarked)
        for row in rows {
            let announced = row.accessibilityLabel
            let label = row.categoryLabel
            #expect(announced.hasSuffix(TransactionListStrings.transferAnnouncement))
            // The category the engine assigned comes through by name, not as its id.
            #expect(!label.contains("_"))
        }
        let counts = try store.accountSummaries().map(\.liveTransactionCount)
        #expect(counts == [1, 1])
    }

    private static func account(_ name: String, isCreditCard: Bool) -> NewAccount {
        NewAccount(
            name: name,
            bankCode: "SYNTHETIC",
            isCreditCard: isCreditCard,
            last4: nil,
            currency: "INR",
            createdAt: "2026-08-01T00:00:00Z",
            updatedAt: "2026-08-01T00:00:00Z"
        )
    }

    private static func leg(_ accountID: String, _ description: String, _ direction: Direction) -> NewTransaction {
        NewTransaction(
            accountId: accountID,
            date: "2026-07-04",
            descriptionRaw: description,
            amount: TransactionCorpus.decimal("5000.00"),
            direction: direction,
            currency: "INR",
            sourceCategory: nil,
            categoryId: nil,
            categorisedBy: nil,
            statementId: nil,
            createdAt: "2026-08-01T00:00:00Z",
            updatedAt: "2026-08-01T00:00:00Z"
        )
    }
}
