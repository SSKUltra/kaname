import SwiftUI

/// Kaname's own colour, and the only tint in the app.
///
/// A deep ink-teal rather than the system default: the prominent action carries white text,
/// and the system blue sits in the accessibility auditor's borderline contrast band against
/// it. These two values clear 4.5:1 against white by a wide margin in both appearances, so
/// the app's single primary action is legible without depending on what happens to be
/// behind the glass.
extension Color {
    static let kanameAccent = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x17 / 255, green: 0x61 / 255, blue: 0x5B / 255, alpha: 1)
                : UIColor(red: 0x13 / 255, green: 0x4E / 255, blue: 0x4A / 255, alpha: 1)
        }
    )
}
