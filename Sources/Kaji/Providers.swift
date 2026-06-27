import Foundation

// MARK: - Provider configuration
//
// Per-provider display metadata. The glyph marks are neutral placeholders.
// This map is the single place to add/remove a
// provider's display config; the data layer surfaces whatever quota.py emits.
enum Providers {
    /// Unicode fallback marks. Provider-specific keys may render vector marks
    /// via `ProviderLogo`; these marks are used when no vector mark exists.
    static let marks: [String: String] = [
        "claude":  "\u{2733}",   // ✳
        "codex":   "\u{273B}",   // ✻
        "minimax": "\u{272A}",   // ✪
        "gemini":  "\u{2726}",   // ✦
        "ark-agent": "\u{25C7}",  // ◇
        "kiro":    "\u{25C9}",   // ◉
        "opencode": "\u{25B3}",  // △
    ]

    /// Human-facing display names inside the app. Public repo copy can stay
    /// vendor-neutral, but the actual control surface should name what users
    /// recognize.
    static let displayNames: [String: String] = [
        "claude":  "Claude Code",
        "codex":   "Codex",
        "minimax": "MiniMax",
        "ark-agent": "Ark Agent",
        "gemini":  "Gemini",
        "kiro":    "Kiro",
        "opencode": "OpenCode",
    ]

    /// Preferred left-to-right display order. Providers not listed here are
    /// appended afterward in alphabetical order.
    static let order: [String] = [
        "claude", "codex", "ark-agent",
        "minimax", "gemini", "kiro", "opencode"
    ]

    /// Providers surfaced by default on a fresh install. Optional providers are
    /// available in the toggle list when configured, but stay opt-in until the
    /// quota source is trustworthy.
    static let visible: Set<String> = ["claude", "codex", "minimax"]
    static func isVisible(_ key: String) -> Bool { visible.contains(key) }

    /// Providers allowed into UI controls when quota.py emits them. This is
    /// intentionally broader than the default-visible set, but narrower than
    /// every diagnostic row quota.py can output.
    static let available: Set<String> = ["claude", "codex", "minimax", "ark-agent"]
    static func isAvailable(_ key: String) -> Bool { available.contains(key) }

    static func mark(for key: String) -> String {
        marks[key] ?? "\u{2022}" // • bullet fallback
    }

    static func displayName(for key: String) -> String {
        displayNames[key] ?? key.capitalized
    }

    /// Sort provider keys by the preferred order, then alphabetically.
    static func sorted(_ keys: [String]) -> [String] {
        keys.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? Int.max
            let ib = order.firstIndex(of: b) ?? Int.max
            if ia != ib { return ia < ib }
            return a < b
        }
    }
}
