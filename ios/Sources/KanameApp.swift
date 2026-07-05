import SwiftUI

/// App entry point. All data is produced on-device by `kaname-core` (Rust) via
/// UniFFI bindings (wired in P1); this shell has zero network dependencies.
@main
struct KanameApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
