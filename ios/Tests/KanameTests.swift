import Foundation
import KanameCore
import Testing
@testable import Kaname

/// Smoke tests using Swift Testing (bundled with Xcode 16+). Real coverage arrives
/// with the feature work; snapshot/XCUITest gates are added per the constitution's
/// iOS Local Verification Gate.
@Suite("Kaname app smoke")
struct KanameSmokeTests {
    @Test("Root view can be constructed")
    func rootViewConstructs() {
        _ = RootView()
    }

    @Test("Engine version shown in the app is sourced from the core engine")
    func versionLabelComesFromEngine() {
        let version = engineVersion()
        #expect(!version.isEmpty)
        #expect(RootView().versionLabel == "Engine v\(version)")
    }

    @Test("core ↔ Swift round-trip returns exactly what the engine computed")
    func roundTripIsExact() throws {
        // Boundary inputs: zero, very large, high-precision decimals; Unicode text.
        let cases = [
            RoundTripCase(amount: "0", description: "  Café  René ", expected: "CAFÉ RENÉ"),
            RoundTripCase(amount: "999999999999.99", description: "swiggy  order", expected: "SWIGGY ORDER"),
            RoundTripCase(amount: "0.000000001", description: "  multiple   spaces  ", expected: "MULTIPLE SPACES"),
        ]
        for testCase in cases {
            let amount = try #require(
                Decimal(string: testCase.amount, locale: Locale(identifier: "en_US_POSIX"))
            )
            let input = Transaction(
                date: "2026-07-04",
                description: testCase.description,
                amount: amount,
                direction: .debit
            )
            let output = normalizeTransaction(input: input)
            // description transformed; amount (exact Decimal), date, direction preserved.
            #expect(output.description == testCase.expected)
            #expect(output.amount == input.amount)
            #expect(output.date == input.date)
            #expect(output.direction == input.direction)
        }
    }
}

/// A single round-trip test vector — a named type (rather than a 3-tuple) to satisfy
/// SwiftLint's `large_tuple` rule and to read clearly.
private struct RoundTripCase {
    let amount: String
    let description: String
    let expected: String
}
