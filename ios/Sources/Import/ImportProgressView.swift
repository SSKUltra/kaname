import SwiftUI

/// The one thing on screen while a statement is being read: what stage the import has
/// reached, and a way out of it.
///
/// A floating control over whatever it covers, so glass is honest here — and `.interactive()`
/// is honest too, because Cancel is a real tap target rather than decoration.
struct ImportProgressView: View {
    let stage: ImportStage?
    let onCancel: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                ProgressView()
                Text(Self.stageText(stage))
                Button("Cancel", action: onCancel)
                    .buttonStyle(.glass)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .accessibilityElement(children: .contain)
    }

    /// Each stage in the person's own terms. A stage that has not been reported yet reads as
    /// the first one, because that is what the import is about to do.
    static func stageText(_ stage: ImportStage?) -> String {
        switch stage {
        case .reading, nil: return "Reading the statement…"
        case .identifying: return "Working out who issued it…"
        case .parsing: return "Reading the transactions…"
        case .checking: return "Checking the figures…"
        case .saving: return "Saving to your device…"
        case .categorizing: return "Sorting into categories…"
        }
    }
}

#Preview {
    ImportProgressView(stage: .parsing, onCancel: {})
}
