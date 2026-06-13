import Foundation
import Combine

// MARK: - Prefs
//
// User-facing preferences, persisted in UserDefaults and published so BOTH
// surfaces (menubar indicator + popover/panel) react live. Owned by AppDelegate.
//
//   - visibleProviders: which provider rings to show. Toggleable from the
//     popover footer or the right-click menu. Never empties to zero.
//   - language: EN / 中文. Drives all captions + menu text (the menubar glyph
//     itself stays text-free aside from the optional center number). First run
//     follows the macOS locale.
//   - showCenterNumber: draw the 5h % in the middle of each ring (menubar +
//     popover). On by default.
@MainActor
final class Prefs: ObservableObject {
    @Published var visibleProviders: Set<String> {
        didSet { UserDefaults.standard.set(Array(visibleProviders), forKey: Key.visibleProviders) }
    }
    @Published var language: Lang {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Key.language) }
    }
    @Published var showCenterNumber: Bool {
        didSet { UserDefaults.standard.set(showCenterNumber, forKey: Key.showCenterNumber) }
    }

    enum Key {
        static let visibleProviders = "visibleProviders"
        static let language = "language"
        static let showCenterNumber = "showCenterNumber"
    }

    init() {
        let d = UserDefaults.standard
        if let arr = d.array(forKey: Key.visibleProviders) as? [String], !arr.isEmpty {
            visibleProviders = Set(arr)
        } else {
            visibleProviders = Providers.visible   // default: claude + codex
        }
        if let raw = d.string(forKey: Key.language), let l = Lang(rawValue: raw) {
            language = l
        } else {
            language = Lang.system                  // follow macOS locale on first run
        }
        showCenterNumber = (d.object(forKey: Key.showCenterNumber) as? Bool) ?? true
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
}

// MARK: - Language

enum Lang: String {
    case en, zh

    /// Pick from the macOS preferred-language list on first run.
    static var system: Lang {
        let pref = Locale.preferredLanguages.first ?? "en"
        return pref.hasPrefix("zh") ? .zh : .en
    }

    var toggled: Lang { self == .en ? .zh : .en }
    var label: String { self == .en ? "EN" : "\u{4E2D}\u{6587}" }   // 中文
}

// MARK: - L10n
//
// Minimal two-language string table, keyed by an enum so callers can't typo a
// key. Brand words (Claude, Codex, Kaji, 5h, 7d) stay untranslated. Word-order-
// sensitive phrases (reset countdowns) are composed in the views, not here.
enum L10n {
    enum K {
        case fiveHQuota, week, quit, stale, waiting
        case floatPanel, hidePanel, showPanel
        case refreshNow, quitApp, language, centerNumber, providers, show
    }

    private static let table: [K: (en: String, zh: String)] = [
        .fiveHQuota:   ("5h quota",            "5\u{5C0F}\u{65F6}\u{989D}\u{5EA6}"),       // 5小时额度
        .week:         ("7d",                  "7\u{5929}"),                                // 7天
        .quit:         ("Quit",                "\u{9000}\u{51FA}"),                         // 退出
        .stale:        ("stale",               "\u{5DF2}\u{8FC7}\u{671F}"),                 // 已过期
        .waiting:      ("waiting for quota\u{2026}", "\u{7B49}\u{5F85}\u{989D}\u{5EA6}\u{2026}"), // 等待额度…
        .floatPanel:   ("Float on desktop",    "\u{60AC}\u{6D6E}\u{5230}\u{684C}\u{9762}"), // 悬浮到桌面
        .hidePanel:    ("Hide desktop panel",  "\u{9690}\u{85CF}\u{60AC}\u{6D6E}\u{7A97}"), // 隐藏悬浮窗
        .showPanel:    ("Show Floating Panel", "\u{663E}\u{793A}\u{60AC}\u{6D6E}\u{7A97}"), // 显示悬浮窗
        .refreshNow:   ("Refresh Now",         "\u{7ACB}\u{5373}\u{5237}\u{65B0}"),         // 立即刷新
        .quitApp:      ("Quit Kaji Gauge",     "\u{9000}\u{51FA} Kaji Gauge"),              // 退出 Kaji Gauge
        .language:     ("Language",            "\u{8BED}\u{8A00}"),                         // 语言
        .centerNumber: ("Center Number",       "\u{4E2D}\u{5FC3}\u{6570}\u{5B57}"),         // 中心数字
        .providers:    ("Providers",           "\u{63D0}\u{4F9B}\u{5546}"),                 // 提供商
        .show:         ("Show",                "\u{663E}\u{793A}"),                         // 显示
    ]

    static func t(_ k: K, _ lang: Lang) -> String {
        guard let pair = table[k] else { return "" }
        return lang == .en ? pair.en : pair.zh
    }
}
