import KanameCore
import SwiftUI

/// Root screen: Kaname branding plus the live engine version produced by `kaname-core`
/// (proof the app is powered by the shared on-device engine). Real flows
/// (import → transactions → dashboard) land in P3.
///
/// Design note: follow the latest HIG — SF Symbols, Dynamic Type, Dark Mode and
/// VoiceOver are first-class from day one (see the constitution's Native Experience
/// principle and the `make-interfaces-feel-better` skill).
struct RootView: View {
    /// Human-readable engine build, sourced live from `kaname-core` via UniFFI — the
    /// single source of truth for the version (never hardcoded in the app).
    var versionLabel: String { "Engine v\(engineVersion())" }

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Kaname",
                systemImage: "key.fill",
                description: Text("The key to your money. On-device, private by design.")
            )
            .navigationTitle("Kaname")
            .safeAreaInset(edge: .bottom) {
                // Show the engine version only when present — never fabricate one (FR-013).
                if !engineVersion().isEmpty {
                    Text(versionLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                        .accessibilityLabel("Engine version \(engineVersion())")
                }
            }
        }
    }
}

#Preview {
    RootView()
}
