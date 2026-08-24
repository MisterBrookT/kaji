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

@main
struct Snap {
    @MainActor
    static func makeMocks() -> [ProviderView] {
        func tokHist(_ seed: [Double]) -> [Double] { seed }
        return [
            ProviderView(id: "claude", mark: "", displayName: "Claude Code",
                         fiveHourPercent: 56, weekPercent: 36, tokensToday: 120_000,
                         resetDate: Date(timeIntervalSinceNow: 72 * 60),
                         weekResetDate: Date(timeIntervalSinceNow: 38 * 3600),
                         plan: "plan",
                         costTodayUSD: 12.4, costIsEstimated: true,
                         history: [20, 28, 22, 40, 55, 48, 60, 52, 68, 56],
                         tokenHistory: tokHist([80, 90, 95, 100, 110, 115, 118, 120, 119, 120])),
            ProviderView(id: "codex", mark: "", displayName: "Codex",
                         fiveHourPercent: 82, weekPercent: 64, tokensToday: 90_000,
                         resetDate: Date(timeIntervalSinceNow: 47 * 60),
                         weekResetDate: Date(timeIntervalSinceNow: 5 * 24 * 3600),
                         plan: "plus",
                         costTodayUSD: 41.2, costIsEstimated: false,
                         history: [30, 45, 50, 62, 70, 75, 80, 78, 85, 82],
                         tokenHistory: tokHist([40, 50, 55, 60, 70, 75, 80, 85, 88, 90])),
            ProviderView(id: "ark-agent", mark: "", displayName: "Ark Agent",
                         fiveHourPercent: 0, weekPercent: 87, tokensToday: 12_000,
                         resetDate: nil,
                         weekResetDate: Date(timeIntervalSinceNow: 13 * 3600),
                         plan: "team",
                         costTodayUSD: 2.1, costIsEstimated: true,
                         history: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                         tokenHistory: tokHist([12, 12, 12, 12, 12, 12, 12, 12, 12, 12])),
            ProviderView(id: "minimax", mark: "", displayName: "MiniMax",
                         fiveHourPercent: 69, weekPercent: 17, tokensToday: 42_000,
                         resetDate: Date(timeIntervalSinceNow: 22 * 60),
                         weekResetDate: Date(timeIntervalSinceNow: 14 * 3600),
                         plan: "plan",
                         costTodayUSD: 6.8, costIsEstimated: true,
                         history: [10, 15, 20, 28, 38, 46, 54, 61, 66, 69],
                         tokenHistory: tokHist([20, 24, 28, 30, 34, 36, 38, 40, 41, 42])),
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
            let aiNewsStore = AIHotNewsStore()
            let mailBriefStore = MailBriefStore(cacheURL: URL(fileURLWithPath: "/tmp/kaji-snapshot-mail.json"))
            let navigation = PopoverNavigation()
            if goalsMode { navigation.panel = .goals }
            if workMode || breakMode { navigation.panel = .work }
            let controls = GaugeRowView.Controls(
                onRefresh: {},
                onUpdate: {},
                onToggleKeepAwake: {},
                onTogglePet: {},
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
                aiNewsStore: aiNewsStore,
                mailBriefStore: mailBriefStore,
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

            let arg = args.first ?? "both"
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
