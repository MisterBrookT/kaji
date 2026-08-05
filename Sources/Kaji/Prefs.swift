import Foundation
import Combine
import CoreGraphics
import KajiCore

// MARK: - Prefs
//
// User-facing preferences, persisted in UserDefaults and published so the
// menubar indicator + popover panel react live. Owned by AppDelegate.
//
//   - visibleProviders: which provider rings to show. Toggleable from the
//     popover footer or the popover. Never empties to zero.
//   - enabledModules: which first-party panels are on (lean-modules-v1).
//     Quota is always forced on. First migration writes slim default (quota).
//   - language: EN / 中文 / PT-BR / ES. Drives all captions + menu text.
//     Fresh installs default to English; existing selections are preserved.
//   - menubarStyle: kept for prefs migration (option B). Always `.blackWhite`;
//     legacy `"color"` / `"mono"` are normalized and written back on load.
@MainActor
final class Prefs: ObservableObject {
    @Published var visibleProviders: Set<String> {
        didSet { UserDefaults.standard.set(Array(visibleProviders), forKey: Key.visibleProviders) }
    }
    @Published var enabledModules: Set<KajiModuleID> {
        didSet {
            let raw = enabledModules.map(\.rawValue).sorted()
            UserDefaults.standard.set(raw, forKey: Key.enabledModules)
        }
    }
    @Published var language: Lang {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Key.language) }
    }
    @Published var menubarStyle: MenubarStyle {
        didSet { UserDefaults.standard.set(menubarStyle.rawValue, forKey: Key.menubarStyle) }
    }
    /// Show the 5h percentage as USED (default, "100% means full") vs
    /// REMAINING ("0% means full"). Persisted; the toggle lives in both the
    /// popover footer segment and the popover on the status item.
    @Published var showRemaining: Bool {
        didSet { UserDefaults.standard.set(showRemaining, forKey: Key.showRemaining) }
    }
    @Published var petId: String {
        didSet { UserDefaults.standard.set(petId, forKey: Key.petId) }
    }
    @Published var focusMinutes: Int {
        didSet { UserDefaults.standard.set(focusMinutes, forKey: Key.focusMinutes) }
    }
    @Published var breakMinutes: Int {
        didSet { UserDefaults.standard.set(breakMinutes, forKey: Key.breakMinutes) }
    }
    @Published var allowBreakSkip: Bool {
        didSet { UserDefaults.standard.set(allowBreakSkip, forKey: Key.allowBreakSkip) }
    }
    @Published var breakOverlayEnabled: Bool {
        didSet { UserDefaults.standard.set(breakOverlayEnabled, forKey: Key.breakOverlayEnabled) }
    }
    @Published var autoCleanEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCleanEnabled, forKey: Key.autoCleanEnabled) }
    }
    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }
    @Published var preventSleep: Bool {
        didSet { UserDefaults.standard.set(preventSleep, forKey: Key.preventSleep) }
    }
    @Published var aiNewsRefreshHours: Int {
        didSet {
            let normalized = AIHotRefreshPolicy.normalize(hours: aiNewsRefreshHours)
            if normalized != aiNewsRefreshHours { aiNewsRefreshHours = normalized; return }
            UserDefaults.standard.set(normalized, forKey: Key.aiNewsRefreshHours)
        }
    }

    enum Key {
        static let visibleProviders = "visibleProviders"
        static let enabledModules = "enabledModules"
        static let language = "language"
        static let menubarStyle = "menubarStyle"
        static let showRemaining = "showRemaining"
        static let petId = "petId"
        static let focusMinutes = "focusMinutes"
        static let breakMinutes = "breakMinutes"
        static let allowBreakSkip = "allowBreakSkip"
        static let breakOverlayEnabled = "breakOverlayEnabled"
        static let visibleProvidersV2 = "visibleProvidersV2"
        /// One-shot: insert `cursor` into saved visible set on upgrade to 0.6.1.
        static let visibleProvidersCursor = "visibleProvidersCursor"
        static let autoCleanEnabled = "autoCleanEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let preventSleep = "preventSleep"
        static let preferencesInitialized = "preferencesInitialized"
        static let aiNewsRefreshHours = "aiNewsRefreshHours"

        static let existingPreferenceKeys = [
            visibleProviders, enabledModules, language, menubarStyle,
            showRemaining, petId, focusMinutes, breakMinutes,
            allowBreakSkip, breakOverlayEnabled, visibleProvidersV2,
            visibleProvidersCursor, autoCleanEnabled, launchAtLogin, preventSleep, aiNewsRefreshHours
        ]
    }

    init() {
        let d = UserDefaults.standard
        let hadExistingPreferences = Key.existingPreferenceKeys.contains {
            d.object(forKey: $0) != nil
        }
        var visible: Set<String>
        if let arr = d.array(forKey: Key.visibleProviders) as? [String], !arr.isEmpty {
            let saved = Set(arr)
            if !d.bool(forKey: Key.visibleProvidersV2),
               saved == Set(["claude", "codex", "minimax"]) {
                visible = Providers.visible
            } else {
                visible = saved
            }
        } else {
            visible = Providers.visible   // default: claude + cursor + codex
        }
        // cursor-quota: once, add Cursor alongside Claude/Codex for upgraders.
        // After this flag is set, toggling Cursor off is respected.
        if !d.bool(forKey: Key.visibleProvidersCursor) {
            visible.insert("cursor")
            d.set(true, forKey: Key.visibleProvidersCursor)
        }
        visibleProviders = visible
        d.set(true, forKey: Key.visibleProvidersV2)

        // lean-modules-v1: first time key is missing → slim default (quota only).
        if d.object(forKey: Key.enabledModules) == nil {
            enabledModules = ModulePrefsLogic.slimDefault
            d.set(Array(ModulePrefsLogic.slimDefault.map(\.rawValue)), forKey: Key.enabledModules)
        } else {
            let raw = d.array(forKey: Key.enabledModules) as? [String]
            enabledModules = ModulePrefsLogic.normalizeEnabledModules(raw)
        }

        let languageResolution = LanguagePrefsLogic.resolve(
            storedRawValue: d.string(forKey: Key.language),
            hadExistingPreferences: hadExistingPreferences,
            preferredLanguages: Locale.preferredLanguages
        )
        language = languageResolution.language
        if languageResolution.shouldPersist {
            d.set(languageResolution.language.rawValue, forKey: Key.language)
        }
        // Mono-only: collapse legacy color/mono/unknown → blackWhite and write back.
        let storedStyle = d.string(forKey: Key.menubarStyle)
        let normalizedStyle = ThemePrefsLogic.normalizeMenubarStyle(storedStyle)
        menubarStyle = MenubarStyle(rawValue: normalizedStyle) ?? .blackWhite
        if ThemePrefsLogic.shouldRewriteMenubarStyle(storedStyle) {
            d.set(normalizedStyle, forKey: Key.menubarStyle)
        }
        // Default to showing USED — matches what the rings always did and
        // avoids surprising existing users on first launch after upgrade.
        if d.object(forKey: Key.showRemaining) != nil {
            showRemaining = d.bool(forKey: Key.showRemaining)
        } else {
            showRemaining = false
        }
        petId = "navi"
        d.set("navi", forKey: Key.petId)
        let savedFocus = d.integer(forKey: Key.focusMinutes)
        focusMinutes = savedFocus > 0 ? savedFocus : 45
        let savedBreak = d.integer(forKey: Key.breakMinutes)
        breakMinutes = savedBreak > 0 ? savedBreak : 2
        if d.object(forKey: Key.allowBreakSkip) != nil {
            allowBreakSkip = d.bool(forKey: Key.allowBreakSkip)
        } else {
            allowBreakSkip = true
        }
        if d.object(forKey: Key.breakOverlayEnabled) != nil {
            breakOverlayEnabled = d.bool(forKey: Key.breakOverlayEnabled)
        } else {
            breakOverlayEnabled = true
        }
        if d.object(forKey: Key.autoCleanEnabled) != nil {
            autoCleanEnabled = d.bool(forKey: Key.autoCleanEnabled)
        } else {
            autoCleanEnabled = false
        }
        if d.object(forKey: Key.launchAtLogin) != nil {
            launchAtLogin = d.bool(forKey: Key.launchAtLogin)
        } else {
            launchAtLogin = LoginItemManager.isEnabled
        }
        if d.object(forKey: Key.preventSleep) != nil {
            preventSleep = d.bool(forKey: Key.preventSleep)
        } else {
            preventSleep = false
        }
        aiNewsRefreshHours = AIHotRefreshPolicy.normalize(hours: d.object(forKey: Key.aiNewsRefreshHours) == nil ? 5 : d.integer(forKey: Key.aiNewsRefreshHours))
        d.set(aiNewsRefreshHours, forKey: Key.aiNewsRefreshHours)
        d.set(true, forKey: Key.preferencesInitialized)
    }

    /// Toggle a provider, but never let the set empty out — at least one ring
    /// must remain or the menubar goes blank.
    func toggleProvider(_ key: String) {
        if visibleProviders.contains(key) {
            if visibleProviders.count > 1 { visibleProviders.remove(key) }
        } else {
            visibleProviders.insert(key)
        }
    }

    func isVisible(_ key: String) -> Bool { visibleProviders.contains(key) }

    func isModuleEnabled(_ id: KajiModuleID) -> Bool {
        enabledModules.contains(id)
    }

    /// Enable/disable a module. Quota cannot be turned off.
    func setModule(_ id: KajiModuleID, enabled: Bool) {
        guard id != .quota else {
            enabledModules = ModulePrefsLogic.normalizeEnabledModules(
                Array(enabledModules.map(\.rawValue))
            )
            return
        }
        var next = enabledModules
        if enabled {
            next.insert(id)
        } else {
            next.remove(id)
        }
        enabledModules = ModulePrefsLogic.normalizeEnabledModules(Array(next.map(\.rawValue)))
    }

    var popoverModulePages: [KajiModuleID] {
        ModulePrefsLogic.popoverPages(enabled: enabledModules)
    }
}

// MARK: - Menu-bar style (option B: single meaningful case)

enum MenubarStyle: String {
    /// Strict mono — the only product style after mono-only.
    case blackWhite
}

enum PanelSize: String, CaseIterable {
    case small, medium

    var frameSize: CGSize {
        switch self {
        case .small:  return CGSize(width: 300, height: 420)
        case .medium: return CGSize(width: 340, height: 460)
        }
    }

    var ringSize: CGFloat {
        switch self {
        case .small:  return 50
        case .medium: return 76
        }
    }
}
