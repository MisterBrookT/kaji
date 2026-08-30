import SwiftUI
import AppKit
import KajiCore

@MainActor
func render(_ view: some View, appearance name: NSAppearance.Name,
            scheme: ColorScheme, to path: String) {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
    renderer.scale = 2
    var image: NSImage?
    if let app = NSAppearance(named: name) {
        app.performAsCurrentDrawingAppearance { image = renderer.nsImage }
    } else {
        image = renderer.nsImage
    }
    guard let img = image,
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("render failed: \(path)"); return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) size=\(img.size)")
}

@MainActor
func renderHosting(
    _ view: some View,
    appearance name: NSAppearance.Name,
    scheme: ColorScheme,
    size: NSSize,
    to path: String
) {
    let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
    host.appearance = NSAppearance(named: name)
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
        contentRect: host.frame,
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentView = host
    window.orderFrontRegardless()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        print("render failed: \(path)")
        return
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("render failed: \(path)")
        return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    window.orderOut(nil)
    print("wrote \(path) size=\(size)")
}

@main
struct Snap {
    @MainActor
    static func makeMocks() -> [ProviderView] {
        return [
            ProviderView(id: "claude", mark: "", displayName: "Claude Code",
                         fiveHourPercent: 56, weekPercent: 36,
                         resetDate: Date(timeIntervalSinceNow: 72 * 60),
                         weekResetDate: Date(timeIntervalSinceNow: 38 * 3600)),
            ProviderView(id: "codex", mark: "", displayName: "Codex",
                         fiveHourPercent: 82, weekPercent: nil,
                         resetDate: Date(timeIntervalSinceNow: 47 * 60),
                         weekResetDate: nil),
            ProviderView(id: "ark-agent", mark: "", displayName: "Ark Agent",
                         fiveHourPercent: 0, weekPercent: 87,
                         resetDate: nil,
                         weekResetDate: Date(timeIntervalSinceNow: 13 * 3600)),
            ProviderView(id: "minimax", mark: "", displayName: "MiniMax",
                         fiveHourPercent: 69, weekPercent: 17,
                         resetDate: Date(timeIntervalSinceNow: 22 * 60),
                         weekResetDate: Date(timeIntervalSinceNow: 14 * 3600)),
        ]
    }

    @MainActor
    static func makePrefs(_ lang: Lang) -> Prefs {
        let p = Prefs()
        p.language = lang
        p.visibleProviders = ["claude", "codex", "ark-agent", "minimax"]
        p.menubarStyle = .blackWhite
        p.showRemaining = false
        // Slim default — quota only (matches shipped lean modules).
        p.enabledModules = [.quota]
        return p
    }

    @MainActor
    static func makeGoalsStore() -> DailyGoalStore {
        let suite = "dev.kaji.snapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = DailyGoalStore(defaults: defaults)

        func add(_ title: String, tag: GoalTag, horizon: GoalHorizon, done: Bool = false, note: String = "") {
            let id = store.addGoal(in: horizon)
            guard let goal = store.goals(for: horizon).first(where: { $0.id == id }) else { return }
            store.updateTitle(goal, title: title, in: horizon)
            store.updateTag(goal, tag: tag.rawValue, in: horizon)
            if !note.isEmpty { store.updateNote(goal, note: note, in: horizon) }
            if done, let updated = store.goals(for: horizon).first(where: { $0.id == id }) {
                store.toggle(updated, in: horizon)
            }
        }

        add("全身拉伸 + 核心", tag: .health, horizon: .today)
        add("吃药", tag: .health, horizon: .today, done: true)
        add("完成第一个版本并推荐给朋友内测", tag: .work, horizon: .week)
        add("收拾好寝室 make it clean", tag: .home, horizon: .week)
        add("录制一期长视频", tag: .work, horizon: .week)
        add("思考未来四个月研究方向", tag: .work, horizon: .week, note: "收敛成三个可验证方向")
        add("寝室持续保持干净", tag: .home, horizon: .longTerm)
        add("戒烟", tag: .health, horizon: .longTerm)
        return store
    }


    static func main() {
        MainActor.assumeIsolated {
            let mocks = makeMocks()
            let args = Array(CommandLine.arguments.dropFirst())
            let goalsMode = args.contains("goals")
            let workMode = args.contains("work")
            let breakMode = args.contains("break")
            let settingsMode = args.contains("settings")
            let lang: Lang = args.contains("zh") ? .zh : .en
            let showRemaining = args.contains("remaining")
            let prefs = makePrefs(lang)
            prefs.showRemaining = showRemaining
            if goalsMode { prefs.enabledModules = [.quota, .goals] }
            if workMode || breakMode { prefs.enabledModules = [.quota, .work] }

            let store = QuotaStore(previewProviders: mocks, updated: Date())
            let workSession = WorkSessionController(prefs: prefs)
            if breakMode { workSession.startBreak() }
            let systemMonitor = SystemMonitor()
            let dailyGoals = goalsMode ? makeGoalsStore() : DailyGoalStore()
            let fixedPlanStore = FixedPlanStore()
            let navigation = PopoverNavigation()
            if goalsMode { navigation.panel = .goals }
            if workMode || breakMode { navigation.panel = .work }
            let controls = KajiPopoverControls(
                onOpenSettings: {},
                onQuit: {}
            )

            let popover = KajiPopoverView(
                store: store,
                prefs: prefs,
                workSession: workSession,
                systemMonitor: systemMonitor,
                dailyGoals: dailyGoals,
                fixedPlanStore: fixedPlanStore,
                navigation: navigation,
                controls: controls,
                maxContentHeight: 720,
                onContentSizeChange: nil,
                scrollsContent: false
            )
            .frame(width: PanelSize.medium.frameSize.width)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            func statusStrip(_ scheme: ColorScheme) -> some View {
                let glyph: Color = scheme == .dark
                    ? Color.white.opacity(0.82) : Color.black.opacity(0.78)
                func sys(_ name: String, _ size: CGFloat = 14) -> some View {
                    Image(systemName: name)
                        .font(.system(size: size, weight: .regular))
                        .foregroundColor(glyph)
                }
                return HStack(spacing: 13) {
                    StatusItemView(providers: mocks, showRemaining: showRemaining)
                    sys("switch.2", 13)
                    sys("wifi", 13)
                    sys("battery.75", 16)
                    Text("Thu 24 Jul  9:41")
                        .font(.system(size: 13.5))
                        .foregroundColor(glyph)
                }
                .padding(.leading, 16).padding(.trailing, 14)
                .frame(height: 26)
                .background(
                    ZStack {
                        (scheme == .dark
                            ? LinearGradient(colors: [Color(hex: 0x2C2C2A), Color(hex: 0x1E1E1C)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(hex: 0xF7F5F1), Color(hex: 0xE7E1D6)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                )
            }

            let settings = SettingsView(
                prefs: prefs,
                sleepController: SleepController(previewEnabled: false),
                fixedPlanStore: fixedPlanStore
            )
            .frame(width: 760, height: 560)

            let arg = args.first ?? "both"
            if settingsMode {
                let size = NSSize(width: 760, height: 560)
                renderHosting(settings, appearance: .darkAqua, scheme: .dark, size: size, to: "/tmp/settings-dark.png")
                renderHosting(settings, appearance: .aqua, scheme: .light, size: size, to: "/tmp/settings-light.png")
                return
            }
            if goalsMode {
                render(popover, appearance: .darkAqua, scheme: .dark, to: "/tmp/goals-dark.png")
            } else if workMode {
                render(popover, appearance: .darkAqua, scheme: .dark, to: "/tmp/work-dark.png")
            } else if breakMode {
                render(popover, appearance: .darkAqua, scheme: .dark, to: "/tmp/break-dark.png")
                let overlay = BreakOverlayView(
                    workSession: workSession,
                    prefs: prefs,
                    scene: .windowRain,
                    isPrimary: true,
                    onSkip: {}
                )
                .frame(width: 1280, height: 720)
                render(overlay, appearance: .darkAqua, scheme: .dark, to: "/tmp/break-overlay-dark.png")
            } else {
                if arg == "dark" || arg == "both" {
                    render(statusStrip(.dark), appearance: .darkAqua, scheme: .dark, to: "/tmp/status-dark.png")
                    render(popover, appearance: .darkAqua, scheme: .dark, to: "/tmp/popover-dark.png")
                }
                if arg == "light" || arg == "both" {
                    render(statusStrip(.light), appearance: .aqua, scheme: .light, to: "/tmp/status-light.png")
                    render(popover, appearance: .aqua, scheme: .light, to: "/tmp/popover-light.png")
                }
            }
        }
    }
}
