import SwiftUI
import KajiCore

// MARK: - KajiTheme (Mono only, Light / Dark)
//
// One visual language: black / white / gray, following system ColorScheme.
// Calm / Playful / Color product themes are gone — see ThemePrefsLogic.
struct KajiTheme {
    let bg: Color      // window / popover background (bottom of gradient)
    let bgTop: Color   // top of the warm background gradient
    let panel: Color   // cards / floating panel
    let cream: Color   // primary text / big number (ink on Sun)
    let mute: Color    // captions / secondary text
    let ash: Color     // faint / disabled
    let track: Color   // ring background track
    let gold: Color    // normal value arc
    let amber: Color   // near-limit (>=80%): warning accent
    let sun: Color     // identity dot / selected controls

    /// Resolve from system color scheme only (mono-only).
    static func resolve(_ scheme: ColorScheme) -> KajiTheme {
        let tokens = ThemePrefsLogic.resolveTheme(scheme == .dark ? .dark : .light)
        return KajiTheme(tokens: tokens)
    }

    private init(tokens: ThemeTokens) {
        bg = Color(hex: tokens.bg)
        bgTop = Color(hex: tokens.bgTop)
        panel = Color(hex: tokens.panel)
        cream = Color(hex: tokens.cream)
        mute = Color(hex: tokens.mute)
        ash = Color(hex: tokens.ash)
        track = Color(hex: tokens.track)
        gold = Color(hex: tokens.gold)
        amber = Color(hex: tokens.amber)
        sun = Color(hex: tokens.sun)
    }

    static let monoDark = KajiTheme(tokens: ThemePrefsLogic.monoDark)
    static let monoLight = KajiTheme(tokens: ThemePrefsLogic.monoLight)
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
