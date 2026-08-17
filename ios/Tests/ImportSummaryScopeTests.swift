import Foundation
import Testing

@testable import Kaname

/// Which set of transactions each figure on the import summary counts.
///
/// The summary shipped with four figures under one heading and **two** scopes:
/// `Transactions` and `Duplicates skipped` describe the statement just handed over, while
/// `Categorized` and `Left uncategorized` describe the whole account, because
/// `categorize_account_in` recomputes every row by design. Three imports of one 3-row statement
/// therefore read `Transactions 3` beside `Left uncategorized 6` — four numbers under one
/// heading that do not sum, on the one screen whose purpose is that a person can trust it
/// (`.scratch/016-statement-import-vertical/issues/05`).
///
/// A first import into a new account cannot tell the two apart, which is why it shipped, and
/// why the grouping is now **data**: where a `Section` happens to put a row is not something a
/// test can see, but which list a figure is in is.
@Suite("What each figure on the import summary counts")
struct ImportSummaryScopeTests {
    private static func summary(
        imported: Int = 3, duplicates: Int = 0, categorized: Int = 1, uncategorized: Int = 2,
        unreadable: Int = 0
    ) -> ImportSummary {
        ImportSummary(
            issuerDisplayName: "Example Bank Credit Card",
            last4: "1002",
            accountIsNew: false,
            period: nil,
            transactionsAdded: imported,
            rowsAlreadyHeld: duplicates,
            categorized: categorized,
            uncategorized: uncategorized,
            unreadableRows: unreadable,
            nothingRecognized: false,
            integrity: .nothingToCheck
        )
    }

    @Test("The account's own position is never counted as an outcome of the import")
    func theTwoScopesAreNeverInTheSameSet() {
        let summary = Self.summary(imported: 3, duplicates: 3, categorized: 3, uncategorized: 6)

        let imported = summary.importedFigures.map(\.label)
        let account = summary.accountFigures.map(\.label)

        // The exact mix that shipped: every account-wide figure out of the imported set, and
        // every per-import figure out of the account set.
        #expect(!imported.contains("Categorized"))
        #expect(!imported.contains("Left uncategorized"))
        #expect(!account.contains("Transactions added"))
        #expect(!account.contains("Already in Kaname"))
        #expect(Set(imported).isDisjoint(with: Set(account)))
    }

    @Test("Every figure the summary can show belongs to exactly one scope")
    func nothingIsUncountedAndNothingIsCountedTwice() {
        let summary = Self.summary(imported: 5, duplicates: 2, categorized: 4, uncategorized: 9, unreadable: 1)
        let all = summary.importedFigures + summary.accountFigures

        // Nothing was dropped in the split: all five figures are still on the screen.
        #expect(all.count == 5)
        #expect(Set(all.map(\.label)).count == all.count, "a figure is in both sets")
        for expected in [
            "Transactions added", "Already in Kaname", "Rows Kaname couldn't read", "Categorized",
            "Left uncategorized",
        ] {
            #expect(all.contains { $0.label == expected }, "\(expected) is not shown at all")
        }
    }

    @Test("The figures carry the counts they are given, and in the reading order")
    func eachFigureCarriesItsOwnCount() {
        let summary = Self.summary(imported: 5, duplicates: 2, categorized: 4, uncategorized: 9, unreadable: 1)

        #expect(summary.importedFigures.map(\.count) == [5, 2, 1])
        #expect(summary.accountFigures.map(\.count) == [4, 9])
        // `Transactions` leads: it is what the person just did.
        #expect(summary.importedFigures.first?.label == "Transactions added")
    }

    @Test("A clean import shows neither a duplicate nor an unreadable row")
    func theQuietFiguresStayQuiet() {
        // Zero is not a fact worth a row here — "Duplicates skipped 0" invites a question the
        // person did not have. Both rows appear only when they have something to report.
        let clean = Self.summary(duplicates: 0, unreadable: 0)
        #expect(clean.importedFigures.map(\.label) == ["Transactions added"])

        // ...and the account's position is always shown, because "0 categorized" is a real
        // state of an account and the reason the next screen looks the way it does.
        #expect(clean.accountFigures.count == 2)
    }

    @Test("The account's figures are captioned with the set they count")
    func theSecondScopeSaysWhatItCounts() {
        // The headings are what make the split legible; a second unlabelled section would only
        // move the confusion. The caption states the scope outright rather than leaving it to
        // be inferred from a heading of two words.
        #expect(ImportSummary.accountSectionTitle != ImportSummary.importedSectionTitle)
        #expect(ImportSummary.accountSectionCaption.contains("not only the statement"))
        #expect(ImportSummary.accountSectionCaption.contains("this account"))
    }
}
