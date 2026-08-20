import Foundation
import KanameCore
import Testing

@testable import Kaname

/// **M3** — what a correction leaves the app able to offer, and the two ways it leaves nothing
/// (FR-027d, plan § *Spec amendments* §3).
///
/// Asserted here rather than on a rendered sheet, for the reason `CategoryPickerTests` gives
/// one surface over: "is there anything to remember?" is a question about what is *true* after
/// a correction, and a rule that can only be checked by presenting a sheet is a rule that stops
/// being checked.
///
/// ⚠️ The failure this guards against is quiet and embarrassing rather than dangerous: an offer
/// reading `When a transaction says “”, Kaname will file it under Groceries.` A person shown
/// that has no way to tell it from a fault in their own statement.
@Suite("What the app can offer to remember after a correction")
struct MemoryOfferTests {
    private static func groceries() -> CategoryChoice {
        CategoryChoice(
            KanameCore.Category(
                categoryRef: .builtin(code: "GROCERIES"), name: "Groceries",
                classification: .spend))
    }

    private static func outcome(_ portion: String?) -> CorrectionOutcome {
        CorrectionOutcome(merchantPortion: portion, memoryFormed: false)
    }

    @Test("A correction with a portion behind it is something the app offers to remember")
    func aPortionIsOffered() {
        let offer = MemoryOffer.decide(Self.outcome("synthetic coffee"), chosen: Self.groceries())

        #expect(offer == .remember(portion: "synthetic coffee", categoryName: "Groceries"))
    }

    /// The engine derived nothing a shop could be named by — a narration that was all channel
    /// words and reference numbers.
    @Test("When the engine derives nothing, the app says so and offers nothing")
    func noPortionIsNothingToRemember() {
        #expect(
            MemoryOffer.decide(Self.outcome(nil), chosen: Self.groceries())
                == .nothingToRemember)
    }

    /// **The second way to have nothing**, and the one an implementation is most likely to
    /// miss: the person deliberately filed the transaction under *no category*. A memory of
    /// blankness would refill the worklist forever, which is why the engine refuses to form one
    /// — and why an offer to form one would be a promise the engine will not keep.
    @Test("A deliberate blank is a decision to remember nothing")
    func aDeliberateBlankIsNothingToRemember() {
        #expect(
            MemoryOffer.decide(Self.outcome("synthetic coffee"), chosen: .none)
                == .nothingToRemember)
        #expect(MemoryOffer.decide(Self.outcome(nil), chosen: .none) == .nothingToRemember)
    }

    /// ⚠️ A portion that exists but says nothing. `merchant_portion` is trimmed and never
    /// empty, so this cannot arrive today — and it is asserted anyway, because "the engine
    /// never sends one" is a claim about a function on the other side of an FFI boundary and
    /// the cost of being wrong is a person reading empty quotation marks about their own money.
    @Test("A blank portion is never quoted back at a person")
    func aDegeneratePortionIsNothingToRemember() {
        for portion in ["", " ", "\n", "   \t "] {
            #expect(
                MemoryOffer.decide(Self.outcome(portion), chosen: Self.groceries())
                    == .nothingToRemember,
                "a portion of \"\(portion)\" was offered")
        }
    }

    /// M1/M4 — what the offer says, with the engine's portion in it verbatim.
    @Test("The offer quotes the engine's portion, and names where it would file it")
    func theOfferNamesThePortionAndTheCategory() {
        let sentence = CategorizeStrings.memoryOffer(
            portion: "synthetic coffee", category: "Groceries")

        #expect(sentence.contains("synthetic coffee"))
        #expect(sentence.contains("Groceries"))
    }
}
