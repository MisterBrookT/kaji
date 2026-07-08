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
//     mono mode. `.color` is the green accent mode. `.mono` is legacy only.
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

    enum Key {
        static let visibleProviders = "visibleProviders"
        static let language = "language"
        static let menubarStyle = "menubarStyle"
        static let showRemaining = "showRemaining"
        static let panelSize = "panelSize"
        static let petId = "petId"
        static let focusMinutes = "focusMinutes"
        static let breakMinutes = "breakMinutes"
        static let allowBreakSkip = "allowBreakSkip"
        static let breakOverlayEnabled = "breakOverlayEnabled"
        static let visibleProvidersV2 = "visibleProvidersV2"
        static let autoCleanEnabled = "autoCleanEnabled"
        static let launchAtLogin = "launchAtLogin"
    }

    init() {
        let d = UserDefaults.standard
        if let arr = d.array(forKey: Key.visibleProviders) as? [String], !arr.isEmpty {
            let saved = Set(arr)
            if !d.bool(forKey: Key.visibleProvidersV2),
               saved == Set(["claude", "codex", "minimax"]) {
                visibleProviders = Providers.visible
            } else {
                visibleProviders = saved
            }
        } else {
            visibleProviders = Providers.visible   // default: claude + codex
        }
        d.set(true, forKey: Key.visibleProvidersV2)
        if let raw = d.string(forKey: Key.language), let l = Lang(rawValue: raw) {
            language = l
        } else {
            language = Lang.system                  // follow macOS locale on first run
        }
        if let raw = d.string(forKey: Key.menubarStyle), let s = MenubarStyle(rawValue: raw) {
            menubarStyle = s == .mono ? .blackWhite : s
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
            panelSize = .small
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
    case mono     // Legacy stored value; migrated to .blackWhite on load.
    case color    // Green accent mode.
    case blackWhite // Mono: black/white popover, default

    var toggled: MenubarStyle {
        switch self {
        case .mono: return .blackWhite
        case .color: return .blackWhite
        case .blackWhite: return .color
        }
    }
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

// MARK: - L10n
//
// Minimal two-language string table, keyed by an enum so callers can't typo a
// key. Product and metric words (Kaji, 5h, 7d) stay untranslated. Word-order-
// sensitive phrases (reset countdowns) are composed in the views, not here.
enum L10n {
    enum K {
        case fiveHQuota, week, quit, stale, waiting, needPython
        case refreshNow, quitApp, settings, advancedSettings, appearance, language, providers, show
        case menubar, styleMono, styleColor, styleBlackWhite
            case usage, showUsed, showRemaining
            case panelSize, sizeSmall, sizeMedium
            case updateTo, checkUpdates, updateChecking, updateCurrent, updateFailed
            case system, keepAwake, keepAwakeOn, keepAwakeOff, keepAwakeTurningOn, keepAwakeTurningOff, keepAwakeFailed
            case pet, petOn, petOff, petTurningOn, petTurningOff, petFailed, petChoice, petGallery, source
            case work, focusLength, breakLength, skipBreak, breakOverlay
            case launchAtLogin
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
        .advancedSettings: ("Advanced",         "\u{9AD8}\u{7EA7}\u{8BBE}\u{7F6E}"),         // 高级设置
        .appearance:   ("Appearance",          "\u{5916}\u{89C2}"),                         // 外观
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
        .petOn:        ("Pet On",              "\u{5BA0}\u{7269}\u{5DF2}\u{5F00}"),         // 宠物已开
        .petOff:       ("Pet Off",             "\u{5BA0}\u{7269}\u{5173}"),                 // 宠物关
        .petTurningOn: ("Opening\u{2026}",       "\u{5F00}\u{542F}\u{4E2D}\u{2026}"),         // 开启中…
        .petTurningOff: ("Closing\u{2026}",      "\u{5173}\u{95ED}\u{4E2D}\u{2026}"),         // 关闭中…
        .petFailed:    ("Pet Failed",           "\u{5BA0}\u{7269}\u{542F}\u{52A8}\u{5931}\u{8D25}"), // 宠物启动失败
        .petChoice:    ("Pet",                 "\u{5BA0}\u{7269}"),                         // 宠物
        .petGallery:   ("Pet Details",         "\u{5BA0}\u{7269}\u{8BE6}\u{60C5}"),         // 宠物详情
        .source:       ("Source",              "\u{6765}\u{6E90}"),                         // 来源
        .launchAtLogin: ("Launch",             "\u{5F00}\u{673A}\u{542F}\u{52A8}"),         // 开机启动
        .work:         ("Work",                "\u{5DE5}\u{4F5C}"),                         // 工作
        .focusLength:  ("Focus",               "\u{4E13}\u{6CE8}"),                         // 专注
        .breakLength:  ("Break",               "\u{4F11}\u{606F}"),                         // 休息
        .skipBreak:    ("Allow Skip",          "\u{5141}\u{8BB8}\u{8DF3}\u{8FC7}"),         // 允许跳过
        .breakOverlay: ("Hard Break",          "\u{5F3A}\u{5236}\u{4F11}\u{606F}"),         // 强制休息
        .quitApp:      ("Quit Kaji",           "\u{9000}\u{51FA} Kaji"),                    // 退出 Kaji
        .language:     ("Language",            "\u{8BED}\u{8A00}"),                         // 语言
        .providers:    ("Providers",           "\u{63D0}\u{4F9B}\u{5546}"),                 // 提供商
        .show:         ("Show",                "\u{663E}\u{793A}"),                         // 显示
        .menubar:      ("Style",              "\u{98CE}\u{683C}"),                         // 风格
        .styleMono:    ("Legacy",             "\u{65E7}\u{7248}"),                         // 旧版
        .styleColor:   ("Green",              "\u{7EFF}\u{8272}"),                         // 绿色
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
