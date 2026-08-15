import Foundation
import KanameCore
import Testing

@testable import Kaname

/// What the engine already worked out, as a person sees it.
///
/// Two facts reach the row from the engine and neither may arrive as an identifier: the
/// category it assigned, and whether the row is marked as a transfer. A blank where a category
/// should be reads as "Kaname doesn't know what this is"; a `category_id` reads as a fault.
/// Both are worse than the plain word.
///
/// ⚠️ **Nothing here — no test name, no assertion, no string — says Kaname *detects* transfers.**
/// It does not: `detectTransfers()` is called from no Swift source file, and `is_transfer` is
/// `0` on every row of a real install (research R18, FR-018). What is tested is the **marking**
/// of a flag the engine may set, and the flag is set by these tests themselves.
@Suite("Categories and the transfer marking, as rendered")
struct TransactionCategoryTests {
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

    // MARK: - T110 — a category is a name

    @Test("A categorized row shows the category by name")
    func aCategorizedRowShowsItsName() {
        let row = Self.row(category: "Groceries")

        #expect(row.categoryLabel == "Groceries")
        #expect(row.accessibilityLabel.contains("Groceries"))
    }

    @Test("An uncategorized row says so in words rather than showing a blank")
    func anUncategorizedRowSaysSo() {
        let row = Self.row(category: nil)

        // A blank cell is indistinguishable from a rendering bug, and from a person's point
        // of view it reads as something having gone wrong with their transaction (FR-017).
        #expect(row.categoryLabel == TransactionListStrings.uncategorized)
        #expect(!row.categoryLabel.isEmpty)
        #expect(row.accessibilityLabel.contains(TransactionListStrings.uncategorized))
    }

    @Test("No row surfaces an identifier or anything else the engine keeps to itself")
    func noRowLeaksAnEngineInternal() {
        // Everything the row can put on screen or into an announcement, for a row carrying
        // every optional fact it can carry.
        let row = Self.row(category: "Groceries", isTransfer: true)
        let surfaces = [
            row.displayDescription, row.categoryLabel, row.accountIdentity,
            row.formattedAmount, row.directionWord, row.accessibilityLabel,
        ]
        let internals = [
            "account-1", "row", "category_id", "categoryId", "categorised_by", "categorisedBy",
            "canonical", "dedup", "layer", "statement_id", "rowid", "sequence", "superseded",
        ]

        for surface in surfaces {
            for leak in internals where leak != "row" {
                #expect(!surface.contains(leak), "\"\(surface)\" leaked \"\(leak)\"")
            }
        }
        // The row's own id, specifically: it is a database key and it means nothing to a
        // person, so it may not appear in anything they can read or hear (FR-019, SC-016).
        #expect(!row.accessibilityLabel.contains(row.id))
        #expect(!row.accessibilityLabel.contains(row.accountID))
    }

    // MARK: - The whole sentence

    @Test("The row's announcement is one sentence carrying every fact the row shows")
    func theAnnouncementIsTheWholeRow() {
        let row = Self.row(category: "Groceries", isTransfer: true, description: "SYNTHETIC CAFE")

        // Date, description, amount with currency, direction in words, account identity,
        // category, and the marking — in that order, as one sentence, so VoiceOver reads a
        // transaction rather than seven fragments (FR-015, T046).
        #expect(
            row.accessibilityLabel
                == [
                    row.date.formatted(.dateTime.day().month(.wide).year()),
                    "SYNTHETIC CAFE",
                    "\(row.amount.formatted(.currency(code: "INR"))) \(TransactionListStrings.debit)",
                    row.accountIdentity,
                    "Groceries",
                    TransactionListStrings.transferAnnouncement,
                ].joined(separator: ", "))
    }

    @Test("A row with nothing optional still announces every fact it does have")
    func theAnnouncementSurvivesEveryFactBeingAbsent() {
        let bare = TransactionRow(
            HistoryRow(
                id: "row", accountId: "account-1", accountName: "Cash Wallet", accountLast4: nil,
                date: "2026-07-15", descriptionRaw: "", amount: TransactionCorpus.decimal("1.00"),
                direction: .credit, currency: "INR", categoryName: nil, isTransfer: false))

        let announced = bare.accessibilityLabel
        #expect(announced.contains(TransactionListStrings.missingDescription))
        #expect(announced.contains(TransactionListStrings.uncategorized))
        #expect(announced.contains(TransactionListStrings.credit))
        #expect(announced.contains("Cash Wallet"))
        // No last-4 to speak of, and nothing invented in its place.
        #expect(!announced.contains("ending"))
        #expect(!announced.contains("nil"))
    }
}
