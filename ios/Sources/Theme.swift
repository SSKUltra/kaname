import SwiftUI
import UIKit

/// Kaname's colour, as **two** tokens — because one colour cannot do both of its jobs.
///
/// The accent is drawn two ways. It is a **fill** behind a prominent action's white label, and
/// it is a **foreground** — the words of every plain and toolbar button, and the symbol on the
/// empty state. Those two roles want opposite things from Dark Mode: a fill carrying white text
/// must stay *dark*, and a foreground on a dark background must go *light*. One token served
/// only the first, and the second measured **2.35:1** on a device — a WCAG AA failure a person
/// reported before any test did (`.scratch/016-statement-import-vertical/issues/02-…`).
///
/// So there are two, and each is measured against the surfaces it is actually drawn on by
/// `ios/Tests/ThemeContrastTests.swift`, which computes the ratio from the token itself. A
/// later palette change cannot quietly reintroduce this: it has to go red first.
extension Color {
    /// The app's tint: everything that draws the accent as **text or a symbol**.
    static let kanameAccent = Color(uiColor: .kanameAccentText)

    /// The fill behind a prominent action's **white** label. Never a foreground.
    static let kanameAccentFill = Color(uiColor: .kanameAccentFill)
}

extension UIColor {
    /// Ink-teal, light enough in Dark Mode to be *read*.
    ///
    /// | Appearance | Value | Worst surface it is drawn on |
    /// |---|---|---|
    /// | Light | `#134E4A` | 8.49:1 on grouped `#F2F2F7` |
    /// | Light, Increase Contrast | `#0B3634` | higher still |
    /// | Dark | `#3FBFAF` | 5.02:1 on tertiary `#3A3A3C` |
    /// | Dark, Increase Contrast | `#5EEAD4` | 7.67:1 on tertiary |
    static let kanameAccentText = UIColor { traits in
        let highContrast = traits.accessibilityContrast == .high
        return traits.userInterfaceStyle == .dark
            ? (highContrast ? UIColor(kanameHex: 0x5E_EA_D4) : UIColor(kanameHex: 0x3F_BF_AF))
            : (highContrast ? UIColor(kanameHex: 0x0B_36_34) : UIColor(kanameHex: 0x13_4E_4A))
    }

    /// The deep ink-teal a prominent button is filled with, unchanged: white on it measures
    /// 9.48:1 in light and 7.25:1 in dark. It stays dark in Dark Mode **on purpose** —
    /// lightening it is exactly what would break the white label sitting on it.
    static let kanameAccentFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(kanameHex: 0x17_61_5B)
            : UIColor(kanameHex: 0x13_4E_4A)
    }

    fileprivate convenience init(kanameHex hex: Int) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// The app's one prominent action: the glass fill, and the token that fill was measured
    /// for, applied **together**.
    ///
    /// They travel as a pair deliberately. `.buttonStyle(.glassProminent)` alone inherits the
    /// app tint — which is now the *text* colour — and filling a button with it puts a white
    /// label on light teal at 2.26:1. `scripts/import-path-audit.sh` fails the build if
    /// `.glassProminent` appears anywhere but here, so the two cannot come apart.
    func prominentAction() -> some View {
        buttonStyle(.glassProminent).tint(.kanameAccentFill)
    }
}
