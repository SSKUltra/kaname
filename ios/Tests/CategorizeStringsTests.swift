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

    /// **T170** — U3's reach, one layer further out: the seed declarations.
    ///
    /// ⚠️ A scenario's descriptions and account names are **drawn on the screen** during every
    /// seeded run, and its expectation labels are the sentences the UI tests assert. A banned
    /// word there cannot ship — `DebugSeed` is `#if DEBUG` and `make release-audit` proves its
    /// absence — but it can do something subtler and worse: enshrine the engine's vocabulary in
    /// what a UI test *expects a person to read*, so the day a surface leaks that word the
    /// suite agrees with it.
    @Test("No seed declaration puts the engine's vocabulary on a screen")
    func noSeedDeclarationCarriesEngineVocabulary() {
        for scenario in SeedScenario.declared {
            var visible = scenario.statements.map(\.accountName)
            visible += scenario.everyDeclaredDescription
            visible += scenario.statements.flatMap { $0.rows.compactMap(\.expectedCategory) }
            visible += scenario.expectedLiveRows.map(\.accessibilityLabel)

            for text in visible {
                for word in Self.banned {
                    #expect(
                        !text.lowercased().contains(word.lowercased()),
                        "\(scenario.name) declares \"\(text)\", which leaked \"\(word)\""
                    )
                }
            }
        }
    }
}
