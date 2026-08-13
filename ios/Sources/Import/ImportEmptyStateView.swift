import KanameCore
import SwiftUI

/// The first thing anyone sees. Not a blank screen and not a spinner: what Kaname is for,
/// the promise that makes handing it a bank statement reasonable, and one thing to do next.
struct ImportEmptyStateView: View {
    let onImport: () -> Void

    /// Human-readable engine build, sourced live from `kaname-core` via UniFFI — the single
    /// source of truth for the version (never hardcoded in the app). Spelled out in full so
    /// what is read aloud is exactly what is on screen.
    var versionLabel: String { "Engine version \(engineVersion())" }

    /// The copy deck for the front door. Constants rather than inline literals, because the
    /// privacy promise is the reason a person hands Kaname their statements — it is content,
    /// not decoration a redesign may quietly drop.
    static let title = "Your money, only yours"
    static let explanation =
        "Import a statement PDF from your bank and Kaname reads the transactions in it, "
        + "sorts them into categories, and checks the figures add up."
    static let privacyPromise =
        "Everything happens on this device. Your statements and transactions are stored "
        + "encrypted here, and Kaname never sends them anywhere."
    static let actionTitle = "Import a statement"

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "key.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text(Self.title)
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(Self.explanation)
                    .multilineTextAlignment(.center)

                Label(Self.privacyPromise, systemImage: "lock.shield")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: .rect(cornerRadius: 16))
                    .accessibilityElement(children: .combine)

                // Inside the scrolling content rather than the bottom bar: a small line over
                // a translucent bar cannot hold contrast, and this belongs with the
                // explanation anyway. Shown only when present — never fabricated.
                if !engineVersion().isEmpty {
                    Text(versionLabel)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        // The screen's one prominent element, and the only tap the first run asks for. The
        // bar behind it is opaque: at the largest text sizes the explanation scrolls under
        // the button, and glass refracting a wall of text is exactly where a label stops
        // holding contrast.
        .safeAreaInset(edge: .bottom) {
            Button(Self.actionTitle, action: onImport)
                .buttonStyle(.glassProminent)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.background)
        }
    }
}

#Preview {
    ImportEmptyStateView(onImport: {})
}
