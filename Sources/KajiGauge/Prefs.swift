import Foundation
import Combine
import CoreGraphics

// MARK: - Prefs
//
// User-facing preferences, persisted in UserDefaults and published so BOTH
// surfaces (menubar indicator + popover/panel) react live. Owned by AppDelegate.
//
//   - visibleProviders: which provider rings to show. Toggleable from the
//     popover footer or the right-click menu. Never empties to zero.
//   - language: EN / 中文. Drives all captions + menu text. First run follows
//     the macOS locale.
//   - menubarStyle: how the menu-bar glyph reads. `.mono` (default) draws the
//     rings + provider logo in the adaptive label color, so the app sits quietly
//     among the native monochrome menu-bar icons. `.color` draws them in warm
//     persimmon for more presence. The popover/panel are always in full color.
@MainActor
final class Prefs: ObservableObject {
    @Published var visibleProviders: Set<String> {
        didSet { UserDefaults.standard.set(Array(visibleProviders), forKey: Key.visibleProviders) }
    }
    @Published var language: Lang {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Key.language) }
    }
    @Published var menubarStyle: MenubarStyle {
        didSet { UserDefaults.standard.set(menubarStyle.rawValue, forKey: Key.menubarStyle) }
    }
    @Published var dockEdge: DockEdge? {
        didSet { UserDefaults.standard.set(dockEdge?.rawValue, forKey: Key.dockEdge) }
    }
    /// Show the 5h percentage as USED (default, "100% means full") vs
    /// REMAINING ("0% means full"). Persisted; the toggle lives in both the
    /// popover footer segment and the right-click menu on the status item.
    @Published var showRemaining: Bool {
        didSet { UserDefaults.standard.set(showRemaining, forKey: Key.showRemaining) }
    }
    @Published var panelSize: PanelSize {
        didSet { UserDefaults.standard.set(panelSize.rawValue, forKey: Key.panelSize) }
    }

    enum Key {
        static let visibleProviders = "visibleProviders"
        static let language = "language"
        static let menubarStyle = "menubarStyle"
        static let dockEdge = "panelDockEdge"
        static let showRemaining = "showRemaining"
        static let panelSize = "panelSize"
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
        if let raw = d.string(forKey: Key.menubarStyle), let s = MenubarStyle(rawValue: raw) {
            menubarStyle = s
        } else {
            menubarStyle = .mono                    // quiet + native by default
        }
        // dockEdge defaults to nil (panel is expanded). Restore the persisted
        // edge (if any) so the next launch can dock straight from restore().
        if let raw = d.string(forKey: Key.dockEdge), let e = DockEdge(rawValue: raw) {
            dockEdge = e
        } else {
            dockEdge = nil
        }
        // Default to showing USED — matches what the rings always did and
        // avoids surprising existing users on first launch after upgrade.
        if d.object(forKey: Key.showRemaining) != nil {
            showRemaining = d.bool(forKey: Key.showRemaining)
        } else {
            showRemaining = false
        }
        if let raw = d.string(forKey: Key.panelSize), let size = PanelSize(rawValue: raw) {
            panelSize = size
        } else {
            panelSize = .medium
        }
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

// MARK: - Dock edge
//
// Which screen edge the floating HUD is currently snapped + docked to. nil
// means "expanded" (the regular floating panel). Persisted so the app comes
// back up in the same state — close the lid, open it next morning, panel
// is still where you left it.
enum DockEdge: String, CaseIterable {
    case left, right, top, bottom
}

// MARK: - Menu-bar style

enum MenubarStyle: String {
    case mono     // adaptive label color — sits among native monochrome icons
    case color    // warm persimmon — more presence

    var toggled: MenubarStyle { self == .mono ? .color : .mono }
}

enum PanelSize: String, CaseIterable {
    case small, medium, large

    var frameSize: CGSize {
        switch self {
        case .small:  return CGSize(width: 236, height: 278)
        case .medium: return CGSize(width: 360, height: 206)
        case .large:  return CGSize(width: 520, height: 246)
        }
    }

    var ringSize: CGFloat {
        switch self {
        case .small:  return 52
        case .medium: return 78
        case .large:  return 98
        }
    }
}

// MARK: - L10n
//
// Minimal two-language string table, keyed by an enum so callers can't typo a
// key. Brand words (Claude, Codex, Kaji, 5h, 7d) stay untranslated. Word-order-
// sensitive phrases (reset countdowns) are composed in the views, not here.
enum L10n {
    enum K {
        case fiveHQuota, week, quit, stale, waiting, needPython
        case floatPanel, hidePanel, showPanel
        case refreshNow, quitApp, language, providers, show
        case menubar, styleMono, styleColor
        case dockExpand, dockHint
            case usage, showUsed, showRemaining
            case panelSize, sizeSmall, sizeMedium, sizeLarge
            case updateTo, checkUpdates
    }

    private static let table: [K: (en: String, zh: String)] = [
        .fiveHQuota:   ("5h quota",            "5\u{5C0F}\u{65F6}\u{989D}\u{5EA6}"),       // 5小时额度
        .week:         ("7d",                  "7\u{5929}"),                                // 7天
        .quit:         ("Quit",                "\u{9000}\u{51FA}"),                         // 退出
        .stale:        ("stale",               "\u{5DF2}\u{8FC7}\u{671F}"),                 // 已过期
        .waiting:      ("waiting for quota\u{2026}", "\u{7B49}\u{5F85}\u{989D}\u{5EA6}\u{2026}"), // 等待额度…
        // Shown when no working python3 is found. Kaji Gauge reads local CLI
        // usage via a bundled python script; macOS ships no python3 by default.
        .needPython:   ("Needs Python 3 \u{00B7} run  xcode-select --install",
                        "\u{9700}\u{8981} Python 3 \u{00B7} \u{8FD0}\u{884C}  xcode-select --install"), // 需要 Python 3 · 运行

        .floatPanel:   ("Float on desktop",    "\u{60AC}\u{6D6E}\u{5230}\u{684C}\u{9762}"), // 悬浮到桌面
        .hidePanel:    ("Hide desktop panel",  "\u{9690}\u{85CF}\u{60AC}\u{6D6E}\u{7A97}"), // 隐藏悬浮窗
        .showPanel:    ("Show Floating Panel", "\u{663E}\u{793A}\u{60AC}\u{6D6E}\u{7A97}"), // 显示悬浮窗
        .refreshNow:   ("Refresh Now",         "\u{7ACB}\u{5373}\u{5237}\u{65B0}"),         // 立即刷新
        .updateTo:     ("Update to",           "\u{66F4}\u{65B0}\u{5230}"),                 // 更新到
        .checkUpdates: ("Check for Updates\u{2026}", "\u{68C0}\u{67E5}\u{66F4}\u{65B0}\u{2026}"), // 检查更新…
        .quitApp:      ("Quit Kaji Gauge",     "\u{9000}\u{51FA} Kaji Gauge"),              // 退出 Kaji Gauge
        .language:     ("Language",            "\u{8BED}\u{8A00}"),                         // 语言
        .providers:    ("Providers",           "\u{63D0}\u{4F9B}\u{5546}"),                 // 提供商
        .show:         ("Show",                "\u{663E}\u{793A}"),                         // 显示
        .menubar:      ("Menu bar",           "\u{83DC}\u{5355}\u{680F}"),                 // 菜单栏
        .styleMono:    ("Mono",               "\u{9ED1}\u{767D}"),                         // 黑白
        .styleColor:   ("Color",              "\u{5F69}\u{8272}"),                         // 彩色
        .dockExpand:   ("tap to expand",      "\u{70B9}\u{51FB}\u{5C55}\u{5F00}"),         // 点击展开
        .dockHint:     ("click arrow",        "\u{70B9}\u{7BAD}\u{5934}"),                 // 点箭头
        .usage:        ("Usage",              "\u{7528}\u{91CF}"),                         // 用量
        .showUsed:     ("Used",               "\u{5DF2}\u{7528}"),                         // 已用
        .showRemaining:("Remaining",          "\u{5269}\u{4F59}"),                         // 剩余
        .panelSize:    ("Size",               "\u{5927}\u{5C0F}"),                         // 大小
        .sizeSmall:    ("S",                  "\u{5C0F}"),                                 // 小
        .sizeMedium:   ("M",                  "\u{4E2D}"),                                 // 中
        .sizeLarge:    ("L",                  "\u{5927}"),                                 // 大
    ]

    static func t(_ k: K, _ lang: Lang) -> String {
        guard let pair = table[k] else { return "" }
        return lang == .en ? pair.en : pair.zh
    }
}
