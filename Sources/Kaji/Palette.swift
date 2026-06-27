import SwiftUI

// MARK: - KajiTheme (Calm / Playful, Light / Dark)
//
// Kaji has two design modes:
//   - Calm: default, paper + graphite + restrained blue.
//   - Playful: same structure, warmer paper + muted orange.
//   - Mono: same structure, strict black/white/gray.
//
// Views read `@Environment(\.colorScheme)` and a persisted style preference,
// then resolve a plain value type. No NSColor dynamic-resolution quirks.
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

    static func resolve(_ scheme: ColorScheme, _ style: MenubarStyle = .mono) -> KajiTheme {
        switch (scheme, style) {
        case (.dark, .mono):  return .calmDark
        case (_, .mono):      return .calmLight
        case (.dark, .color): return .playfulDark
        case (_, .color):     return .playfulLight
        case (.dark, .blackWhite): return .monoDark
        case (_, .blackWhite):     return .monoLight
        }
    }

    static let calmDark = KajiTheme(
        bg:    Color(hex: 0x111416),
        bgTop: Color(hex: 0x181C1F),
        panel: Color(hex: 0x1D2226),
        cream: Color(hex: 0xEEF2F4),
        mute:  Color(hex: 0x98A2AA),
        ash:   Color(hex: 0x5E6870),
        track: Color(hex: 0x30383F),
        gold:  Color(hex: 0x8FA9BA),
        amber: Color(hex: 0x5F86A2),
        sun:   Color(hex: 0x7EA3BB)
    )

    static let calmLight = KajiTheme(
        bg:    Color(hex: 0xF7F9FA),
        bgTop: Color(hex: 0xFFFFFF),
        panel: Color(hex: 0xFEFFFF),
        cream: Color(hex: 0x22262A),
        mute:  Color(hex: 0x69727A),
        ash:   Color(hex: 0xAEB7BE),
        track: Color(hex: 0xE3E8EB),
        gold:  Color(hex: 0x607D96),
        amber: Color(hex: 0x426C8B),
        sun:   Color(hex: 0x5C86A3)
    )

    static let playfulDark = KajiTheme(
        bg:    Color(hex: 0x151311),
        bgTop: Color(hex: 0x1E1A16),
        panel: Color(hex: 0x242019),
        cream: Color(hex: 0xF0ECE5),
        mute:  Color(hex: 0xA2998F),
        ash:   Color(hex: 0x685E54),
        track: Color(hex: 0x393229),
        gold:  Color(hex: 0xD08A55),
        amber: Color(hex: 0xD46F37),
        sun:   Color(hex: 0xD08A55)
    )

    static let playfulLight = KajiTheme(
        bg:    Color(hex: 0xFAF7F2),
        bgTop: Color(hex: 0xFFFCF7),
        panel: Color(hex: 0xFFFDF8),
        cream: Color(hex: 0x28231F),
        mute:  Color(hex: 0x756B61),
        ash:   Color(hex: 0xB8AEA3),
        track: Color(hex: 0xE8DFD3),
        gold:  Color(hex: 0xB87343),
        amber: Color(hex: 0xD46F37),
        sun:   Color(hex: 0xC67A45)
    )

    static let monoDark = KajiTheme(
        bg:    Color(hex: 0x121212),
        bgTop: Color(hex: 0x191919),
        panel: Color(hex: 0x202020),
        cream: Color(hex: 0xF0F0EC),
        mute:  Color(hex: 0xA0A09A),
        ash:   Color(hex: 0x62625D),
        track: Color(hex: 0x333330),
        gold:  Color(hex: 0xD2D2CC),
        amber: Color(hex: 0xF0F0EC),
        sun:   Color(hex: 0xD2D2CC)
    )

    static let monoLight = KajiTheme(
        bg:    Color(hex: 0xF8F8F6),
        bgTop: Color(hex: 0xFFFFFF),
        panel: Color(hex: 0xFFFFFF),
        cream: Color(hex: 0x20201D),
        mute:  Color(hex: 0x70706A),
        ash:   Color(hex: 0xB2B2AC),
        track: Color(hex: 0xE5E5E1),
        gold:  Color(hex: 0x666660),
        amber: Color(hex: 0x3D3D39),
        sun:   Color(hex: 0x666660)
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
