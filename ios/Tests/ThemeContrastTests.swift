import SwiftUI
import Testing
import UIKit

@testable import Kaname

/// The palette, measured rather than admired.
///
/// A person found this defect before any test did: in Dark Mode the words "Done" and "Import
/// another" were barely visible, and the accent they were drawn in measured **2.35:1** against
/// the sheet behind them — against the 4.5:1 that WCAG AA asks of text. The cause was not a
/// badly chosen colour. It was one colour doing two jobs: the value had been checked as a
/// **fill** carrying white text, which it passes comfortably, and then also used as a
/// **foreground**, where Dark Mode needs it to move the other way entirely.
///
/// So the ratios are computed here from the tokens themselves, in every appearance the system
/// can put them in. Changing a hex literal without changing what it is for turns this red.
@Suite("The accent is legible in both appearances")
struct ThemeContrastTests {
    /// WCAG 2.1 normal-text contrast. Large text and non-text UI may use 3:1; nothing here
    /// takes that allowance, because a toolbar button's label is normal text.
    private static let aa = 4.5

    /// The surfaces the tint is actually drawn on, darkest last — a grouped row and a raised
    /// control are lighter than the window behind them, and the tint has to survive all of them.
    private static let darkSurfaces = [
        ("black", 0x00_00_00), ("sheet", 0x1C_1C_1E),
        ("secondary", 0x2C_2C_2E), ("tertiary", 0x3A_3A_3C),
    ]

    private static let lightSurfaces = [("white", 0xFF_FF_FF), ("grouped", 0xF2_F2_F7)]

    @Test("The tint can be read as text, in every appearance the system offers")
    func theTintIsReadableAsText() {
        for (style, surfaces) in [
            (UIUserInterfaceStyle.dark, Self.darkSurfaces), (.light, Self.lightSurfaces),
        ] {
            for contrast in [UIAccessibilityContrast.normal, .high] {
                let tint = UIColor.kanameAccentText.resolvedColor(
                    with: Self.traits(style: style, contrast: contrast))
                for (name, surface) in surfaces {
                    let ratio = Self.contrast(tint, Self.color(surface))
                    #expect(
                        ratio >= Self.aa,
                        "the tint measures \(Self.rounded(ratio)):1 on \(name) — \(style), \(contrast)"
                    )
                }
            }
        }
    }

    @Test("A prominent button's white label can be read on the fill beneath it")
    func theFillCarriesItsLabel() {
        for style in [UIUserInterfaceStyle.dark, .light] {
            for contrast in [UIAccessibilityContrast.normal, .high] {
                let fill = UIColor.kanameAccentFill.resolvedColor(
                    with: Self.traits(style: style, contrast: contrast))
                let ratio = Self.contrast(.white, fill)
                #expect(
                    ratio >= Self.aa,
                    "white on the fill measures \(Self.rounded(ratio)):1 — \(style), \(contrast)"
                )
            }
        }
    }

    /// The two tokens are not interchangeable, and the reason is a number.
    ///
    /// Filling a button with the **text** token would put a white label on light teal, and
    /// drawing text in the **fill** token is the defect this suite exists for. Asserting they
    /// differ in Dark Mode is what stops a well-meaning simplification collapsing them back into
    /// one.
    @Test("The fill and the text tokens are different colours in Dark Mode, and must be")
    func theTwoTokensAreNotOneToken() {
        let dark = Self.traits(style: .dark, contrast: .normal)
        let text = UIColor.kanameAccentText.resolvedColor(with: dark)
        let fill = UIColor.kanameAccentFill.resolvedColor(with: dark)
        #expect(text != fill)

        // Each fails the other's job, which is the whole argument for having two.
        #expect(Self.contrast(.white, text) < Self.aa)
        #expect(Self.contrast(fill, Self.color(0x1C_1C_1E)) < Self.aa)
    }

    @Test("Dark Mode's tint is lighter than Light Mode's, which is what was wrong before")
    func theDarkTintIsTheLighterOne() {
        let dark = UIColor.kanameAccentText.resolvedColor(
            with: Self.traits(style: .dark, contrast: .normal))
        let light = UIColor.kanameAccentText.resolvedColor(
            with: Self.traits(style: .light, contrast: .normal))

        // A foreground separates from its background by moving away from it. The old palette
        // moved the Dark Mode value barely at all — 2.35:1 — because it had been reasoned about
        // as a fill, where staying dark is correct.
        #expect(Self.luminance(dark) > Self.luminance(light))
    }

    // MARK: - WCAG 2.1

    private static func traits(
        style: UIUserInterfaceStyle,
        contrast: UIAccessibilityContrast
    ) -> UITraitCollection {
        UITraitCollection { mutable in
            mutable.userInterfaceStyle = style
            mutable.accessibilityContrast = contrast
        }
    }

    private static func color(_ hex: Int) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func contrast(_ one: UIColor, _ other: UIColor) -> Double {
        let first = luminance(one)
        let second = luminance(other)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// Relative luminance, sRGB, exactly as WCAG 2.1 defines it.
    private static func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let linear = [red, green, blue].map { channel -> Double in
            let value = Double(channel)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    private static func rounded(_ ratio: Double) -> String {
        String(format: "%.2f", ratio)
    }
}
