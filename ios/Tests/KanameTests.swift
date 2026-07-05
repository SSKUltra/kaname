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
}
