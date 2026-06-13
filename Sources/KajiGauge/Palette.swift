import SwiftUI

// MARK: - KajiTheme (Auto: Kaji Ember dark / Kaji Sun light)
//
// The two Kaji palettes as plain value types, selected by the SwiftUI
// `\.colorScheme` environment. Views read `@Environment(\.colorScheme)` and call
// `KajiTheme.resolve(scheme)` — so the whole gauge flips with macOS Auto/Light/
// Dark, deterministically (no NSColor dynamic-resolution quirks).
//
// Hexes are the product's ground truth:
//   - dark  "Kaji Ember": warm charcoal + cream + ember gold.
//   - light "Kaji Sun":   warm paper + ink + ochre gold.
// SUN persimmon is the one brand accent, identical in both.
struct KajiTheme {
    let bg: Color      // window / popover background (bottom of gradient)
    let bgTop: Color   // top of the warm background gradient
    let panel: Color   // cards / floating panel
    let cream: Color   // primary text / big number (ink on Sun)
    let mute: Color    // captions / secondary text
    let ash: Color     // faint / disabled
    let track: Color   // ring background track
    let gold: Color    // normal ring value arc
    let amber: Color   // near-limit (>=80%): deeper, same warm family
    let sun: Color     // Kaji brand persimmon — header dot

    static func resolve(_ scheme: ColorScheme) -> KajiTheme {
        scheme == .dark ? .dark : .light
    }

    static let dark = KajiTheme(
        bg:    Color(hex: 0x16100B),
        bgTop: Color(hex: 0x1F170F),
        panel: Color(hex: 0x1D160F),
        cream: Color(hex: 0xECE4D6),
        mute:  Color(hex: 0x9C9283),
        ash:   Color(hex: 0x665E53),
        track: Color(hex: 0x3A3026),
        gold:  Color(hex: 0xD8A657),
        amber: Color(hex: 0xC87A2A),
        sun:   Color(hex: 0xF25C05)
    )

    static let light = KajiTheme(
        bg:    Color(hex: 0xFBF8F2),
        bgTop: Color(hex: 0xFFFDF8),
        panel: Color(hex: 0xFEFBF5),
        cream: Color(hex: 0x211C15), // ink
        mute:  Color(hex: 0x8A8174),
        ash:   Color(hex: 0xB5AB9C),
        track: Color(hex: 0xE2D8C6),
        gold:  Color(hex: 0xA16207),
        amber: Color(hex: 0xB45309),
        sun:   Color(hex: 0xF25C05)
    )
}

// MARK: - Hex initializer
extension Color {
    /// Build a Color from a 0xRRGGBB integer (full opacity).
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue:  Double(hex & 0xFF) / 255.0,
                  opacity: 1.0)
    }
}
