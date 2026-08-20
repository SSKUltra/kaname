import Foundation
import Testing

@testable import Kaname

/// **U3** — nothing this feature says to a person is written in the engine's language.
///
/// The engine's vocabulary is precise and completely meaningless to somebody looking at their
/// own bank statement: a stage, a tier, a rule, a merchant map and a provenance are internal
/// facts about how a category was arrived at, and none of them is an answer to "why is this
/// filed here?". A single leaked word turns a screen about a person's money into a screen
/// about Kaname's implementation (T3, FR-029, SC-007).
///
/// Asserted over the **whole table**, not a sample: a string that escapes the audit by being
/// added somewhere else is exactly the string that will leak.
@Suite("What the categorize surfaces are allowed to say")
struct CategorizeStringsTests {
    /// Words that mean something inside the engine and nothing to a person.
    private static let banned = [
        "T1", "T2", "T3", "T4",
        "stage", "rule", "heuristic", "merchant map", "provenance", "tier",
    ]

    @Test("No sentence carries a word from the engine's vocabulary")
    func noSentenceCarriesEngineVocabulary() {
        for sentence in CategorizeStrings.everySentence {
            for word in Self.banned {
                #expect(
                    !sentence.lowercased().contains(word.lowercased()),
                    "\"\(sentence)\" leaked \"\(word)\""
                )
            }
        }
    }

    @Test("Every sentence is non-empty and starts as a person would read it")
    func everySentenceIsSomethingAPersonCouldRead() {
        for sentence in CategorizeStrings.everySentence {
            #expect(!sentence.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(sentence != sentence.uppercased(), "\"\(sentence)\" is shouted, not said")
        }
    }

    /// **T2** — the word for "no category" has exactly one spelling in the app.
    ///
    /// Two spellings is the defect FR-002 exists to prevent: a row that reads `Uncategorized`
    /// in the list and something else on the surface that changes it, with nothing on either
    /// screen to say they are the same state.
    @Test("The word for having no category is the list's word, not a second one")
    func theWordForNoCategoryIsShared() {
        #expect(CategorizeStrings.uncategorized == TransactionListStrings.uncategorized)
    }
}
