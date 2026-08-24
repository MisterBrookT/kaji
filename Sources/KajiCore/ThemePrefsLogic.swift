import Foundation

/// Canonical menubar style raw value after mono-only migration (option B).
public enum MenubarStyleID: String, Sendable {
    case blackWhite
}

/// Color-scheme token used by pure theme resolve (no SwiftUI dependency).
public enum ThemeScheme: String, Sendable {
    case light
    case dark
}

/// Hex color tokens for the Mono light/dark palettes (design-language).
public struct ThemeTokens: Equatable, Sendable {
    public let bg: UInt32
    public let bgTop: UInt32
    public let panel: UInt32
    public let cream: UInt32
    public let mute: UInt32
    public let ash: UInt32
    public let track: UInt32
    public let gold: UInt32
    public let amber: UInt32
    public let sun: UInt32

    public init(
        bg: UInt32, bgTop: UInt32, panel: UInt32, cream: UInt32,
        mute: UInt32, ash: UInt32, track: UInt32, gold: UInt32,
        amber: UInt32, sun: UInt32
    ) {
        self.bg = bg
        self.bgTop = bgTop
        self.panel = panel
        self.cream = cream
        self.mute = mute
        self.ash = ash
        self.track = track
        self.gold = gold
        self.amber = amber
        self.sun = sun
    }
}

/// Prefs / theme helpers for mono-only (no Calm / Playful / Color product path).
///
/// Spec: `dev_docs/specs/2026-07-24-mono-only.md`
public enum ThemePrefsLogic {
    /// Strict mono light palette (design-language).
    public static let monoLight = ThemeTokens(
        bg: 0xF8F8F6,
        bgTop: 0xFFFFFF,
        panel: 0xFFFFFF,
        cream: 0x20201D,
        mute: 0x70706A,
        ash: 0xB2B2AC,
        track: 0xE5E5E1,
        gold: 0x666660,
        amber: 0x3D3D39,
        sun: 0x666660
    )

    /// Strict mono dark palette (design-language).
    public static let monoDark = ThemeTokens(
        bg: 0x161615,
        bgTop: 0x1D1D1B,
        panel: 0x2B2B29,
        cream: 0xF4F4EF,
        mute: 0xB5B5AE,
        ash: 0x777772,
        track: 0x484844,
        gold: 0xD8D8D0,
        amber: 0xF4F4EF,
        sun: 0xD8D8D0
    )

    /// Normalize a stored `menubarStyle` raw value to mono-only.
    ///
    /// - nil / missing / `"color"` / `"mono"` / unknown → `"blackWhite"`
    /// - `"blackWhite"` → `"blackWhite"`
    public static func normalizeMenubarStyle(_ raw: String?) -> String {
        // Option B: every historical product style collapses to blackWhite.
        _ = raw
        return MenubarStyleID.blackWhite.rawValue
    }

    /// Whether UserDefaults should be rewritten after load so the next read
    /// never sees a legacy `"color"` / `"mono"` / garbage value.
    public static func shouldRewriteMenubarStyle(_ raw: String?) -> Bool {
        raw != MenubarStyleID.blackWhite.rawValue
    }

    /// Resolve theme tokens from scheme only — never from menubar style.
    public static func resolveTheme(_ scheme: ThemeScheme) -> ThemeTokens {
        switch scheme {
        case .dark: return monoDark
        case .light: return monoLight
        }
    }
}
