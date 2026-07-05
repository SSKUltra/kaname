import SwiftUI

/// Placeholder root screen. Real flows (import → transactions → dashboard) land in P3.
///
/// Design note: follow the latest HIG — SF Symbols, Dynamic Type, Dark Mode and
/// VoiceOver are first-class from day one (see the constitution's Native Experience
/// principle and the `make-interfaces-feel-better` skill).
struct RootView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Kaname",
                systemImage: "key.fill",
                description: Text("The key to your money. On-device, private by design.")
            )
            .navigationTitle("Kaname")
        }
    }
}

#Preview {
    RootView()
}
