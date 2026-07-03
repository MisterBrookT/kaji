import Foundation
import Combine
import CoreGraphics

// MARK: - Prefs
//
// User-facing preferences, persisted in UserDefaults and published so the
// menubar indicator + popover panel react live. Owned by AppDelegate.
//
//   - visibleProviders: which provider rings to show. Toggleable from the
//     popover footer or the popover. Never empties to zero.
//   - language: EN / 中文. Drives all captions + menu text. First run follows
//     the macOS locale.
//   - menubarStyle: the visual language. `.blackWhite` is the default strict
//     mono mode. `.mono` is Calm. `.color` is Playful.
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
    /// Show the 5h percentage as USED (default, "100% means full") vs
    /// REMAINING ("0% means full"). Persisted; the toggle lives in both the
    /// popover footer segment and the popover on the status item.
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
            menubarStyle = .blackWhite              // strict mono by default
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

// MARK: - Menu-bar style

enum MenubarStyle: String {
    case mono     // Calm: blue/graphite popover
    case color    // Playful: warmer accent mode
    case blackWhite // Mono: black/white popover, default

    var toggled: MenubarStyle {
        switch self {
        case .mono: return .color
        case .color: return .blackWhite
        case .blackWhite: return .mono
        }
    }
}

enum PanelSize: String, CaseIterable {
    case small, medium

    var frameSize: CGSize {
        switch self {
        case .small:  return CGSize(width: 246, height: 278)
        case .medium: return CGSize(width: 360, height: 206)
        }
    }

    var ringSize: CGFloat {
        switch self {
        case .small:  return 50
        case .medium: return 76
        }
    }
}

// MARK: - L10n
//
// Minimal two-language string table, keyed by an enum so callers can't typo a
// key. Product and metric words (Kaji, 5h, 7d) stay untranslated. Word-order-
// sensitive phrases (reset countdowns) are composed in the views, not here.
enum L10n {
    enum K {
        case fiveHQuota, week, quit, stale, waiting, needPython
        case refreshNow, quitApp, settings, language, providers, show
        case menubar, styleMono, styleColor, styleBlackWhite
            case usage, showUsed, showRemaining
            case panelSize, sizeSmall, sizeMedium
            case updateTo, checkUpdates, updateChecking, updateCurrent, updateFailed
            case system, keepAwake, keepAwakeOn, keepAwakeOff, keepAwakeTurningOn, keepAwakeTurningOff, keepAwakeFailed
            case pet, petOn, petOff, petTurningOn, petTurningOff, petFailed
    }

    private static let table: [K: (en: String, zh: String)] = [
        .fiveHQuota:   ("5h quota",            "5\u{5C0F}\u{65F6}\u{989D}\u{5EA6}"),       // 5小时额度
        .week:         ("7d",                  "7\u{5929}"),                                // 7天
        .quit:         ("Quit",                "\u{9000}\u{51FA}"),                         // 退出
        .stale:        ("stale",               "\u{5DF2}\u{8FC7}\u{671F}"),                 // 已过期
        .waiting:      ("waiting for quota\u{2026}", "\u{7B49}\u{5F85}\u{989D}\u{5EA6}\u{2026}"), // 等待额度…
        // Shown when no working python3 is found. Kaji reads local CLI
        // usage via a bundled python script; macOS ships no python3 by default.
        .needPython:   ("Needs Python 3 \u{00B7} run  xcode-select --install",
                        "\u{9700}\u{8981} Python 3 \u{00B7} \u{8FD0}\u{884C}  xcode-select --install"), // 需要 Python 3 · 运行

        .refreshNow:   ("Refresh Now",         "\u{7ACB}\u{5373}\u{5237}\u{65B0}"),         // 立即刷新
        .settings:     ("Settings",            "\u{8BBE}\u{7F6E}"),                         // 设置
        .updateTo:     ("Update to",           "\u{66F4}\u{65B0}\u{5230}"),                 // 更新到
        .checkUpdates: ("Check for Updates\u{2026}", "\u{68C0}\u{67E5}\u{66F4}\u{65B0}\u{2026}"), // 检查更新…
        .updateChecking: ("Checking\u{2026}",   "\u{68C0}\u{67E5}\u{4E2D}\u{2026}"),         // 检查中…
        .updateCurrent: ("Up to date",          "\u{5DF2}\u{662F}\u{6700}\u{65B0}"),         // 已是最新
        .updateFailed:  ("Update check failed", "\u{68C0}\u{67E5}\u{5931}\u{8D25}"),         // 检查失败
        .system:       ("System",              "\u{7CFB}\u{7EDF}"),                         // 系统
        .keepAwake:    ("Keep Awake",          "\u{4E0D}\u{4F11}\u{7720}"),                 // 不休眠
        .keepAwakeOn:  ("Awake On",             "\u{4E0D}\u{4F11}\u{7720}\u{5DF2}\u{5F00}"), // 不休眠已开
        .keepAwakeOff: ("Awake Off",            "\u{4E0D}\u{4F11}\u{7720}\u{5173}"),         // 不休眠关
        .keepAwakeTurningOn: ("Turning On\u{2026}", "\u{5F00}\u{542F}\u{4E2D}\u{2026}"),     // 开启中…
        .keepAwakeTurningOff: ("Turning Off\u{2026}", "\u{5173}\u{95ED}\u{4E2D}\u{2026}"),   // 关闭中…
        .keepAwakeFailed: ("Awake Failed",      "\u{8BBE}\u{7F6E}\u{5931}\u{8D25}"),         // 设置失败
        .pet:          ("Pet",                 "\u{5BA0}\u{7269}"),                         // 宠物
        .petOn:        ("Xiaochai On",          "\u{5C0F}\u{67F4}\u{5DF2}\u{5F00}"),         // 小柴已开
        .petOff:       ("Xiaochai Off",         "\u{5C0F}\u{67F4}\u{5173}"),                 // 小柴关
        .petTurningOn: ("Opening\u{2026}",       "\u{5F00}\u{542F}\u{4E2D}\u{2026}"),         // 开启中…
        .petTurningOff: ("Closing\u{2026}",      "\u{5173}\u{95ED}\u{4E2D}\u{2026}"),         // 关闭中…
        .petFailed:    ("Pet Failed",           "\u{5BA0}\u{7269}\u{542F}\u{52A8}\u{5931}\u{8D25}"), // 宠物启动失败
        .quitApp:      ("Quit Kaji",           "\u{9000}\u{51FA} Kaji"),                    // 退出 Kaji
        .language:     ("Language",            "\u{8BED}\u{8A00}"),                         // 语言
        .providers:    ("Providers",           "\u{63D0}\u{4F9B}\u{5546}"),                 // 提供商
        .show:         ("Show",                "\u{663E}\u{793A}"),                         // 显示
        .menubar:      ("Style",              "\u{98CE}\u{683C}"),                         // 风格
        .styleMono:    ("Calm",               "\u{6C89}\u{7A33}"),                         // 沉稳
        .styleColor:   ("Playful",            "\u{6D3B}\u{6CFC}"),                         // 活泼
        .styleBlackWhite: ("Mono",            "\u{9ED1}\u{767D}"),                         // 黑白
        .usage:        ("Usage",              "\u{7528}\u{91CF}"),                         // 用量
        .showUsed:     ("Used",               "\u{5DF2}\u{7528}"),                         // 已用
        .showRemaining:("Remaining",          "\u{5269}\u{4F59}"),                         // 剩余
        .panelSize:    ("Size",               "\u{5927}\u{5C0F}"),                         // 大小
        .sizeSmall:    ("S",                  "\u{5C0F}"),                                 // 小
        .sizeMedium:   ("M",                  "\u{4E2D}"),                                 // 中
    ]

    static func t(_ k: K, _ lang: Lang) -> String {
        guard let pair = table[k] else { return "" }
        return lang == .en ? pair.en : pair.zh
    }
}
