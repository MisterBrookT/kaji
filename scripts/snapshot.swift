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

    static func makeMailGeneration() -> MailBriefGeneration {
        let entries = [
            MailBriefEntry(threadID: "1", subject: "Message to KDD 2026 Workshop Authors Accepted",
                           sender: "AIDataSci 2026", gmailURL: nil, level: 3, bucket: .act,
                           summaryZH: "KDD 2026 Workshop 投稿已接收，需要确认作者信息。",
                           reasonZH: "录用通知，需要在截止日前完成确认。", suggestedAction: .reply,
                           deadline: Date(timeIntervalSinceNow: 2 * 86_400), confidence: .high,
                           goalTitleZH: "确认 KDD Workshop 作者信息"),
            MailBriefEntry(threadID: "2", subject: "Tuesday Poster Session",
                           sender: "KDD Events Team", gmailURL: nil, level: 3, bucket: .act,
                           summaryZH: "周二 Poster Session 时间与展位安排已更新。",
                           reasonZH: "行程发生变化。", suggestedAction: .createGoal,
                           deadline: nil, confidence: .high, goalTitleZH: "更新 KDD Poster 行程"),
            MailBriefEntry(threadID: "3", subject: "WISE 2026 Invitation Letter Request for Visa Support",
                           sender: "Microsoft CMT", gmailURL: nil, level: 2, bucket: .act,
                           summaryZH: "WISE 2026 签证邀请函需要补充护照信息。",
                           reasonZH: "材料不完整会影响签证进度。", suggestedAction: .reply,
                           deadline: Date(timeIntervalSinceNow: 5 * 86_400), confidence: .high,
                           goalTitleZH: "补充 WISE 签证材料"),
            MailBriefEntry(threadID: "4", subject: "AAAI 2027 revision received",
                           sender: "OpenReview", gmailURL: nil, level: 2, bucket: .watch,
                           summaryZH: "AAAI 2027 修订稿已成功提交，无需立即操作。",
                           reasonZH: "系统回执。", suggestedAction: .none,
                           deadline: nil, confidence: .high, goalTitleZH: nil),
            MailBriefEntry(threadID: "5", subject: "Your Nexitaly service expires in 3 days",
                           sender: "Nexitaly", gmailURL: nil, level: 1, bucket: .watch,
                           summaryZH: "Nexitaly 服务将在 3 天后到期。",
                           reasonZH: "可能需要续费。", suggestedAction: .watch,
                           deadline: Date(timeIntervalSinceNow: 3 * 86_400), confidence: .medium,
                           goalTitleZH: nil),
        ]
        return MailBriefGeneration(briefDay: "2026-08-25", entries: entries,
                                   snapshotInboxThreadCount: 32, classifierModelID: MailBriefModel.defaultValue.rawValue)
    }

    static func main() {
        MainActor.assumeIsolated {
            let mocks = makeMocks()
            let args = Array(CommandLine.arguments.dropFirst())
            let goalsMode = args.contains("goals")
            let workMode = args.contains("work")
            let breakMode = args.contains("break")
            let mailMode = args.contains("mail")
            let launchdMode = args.contains("launchd")
            let settingsMode = args.contains("settings")
            let lang: Lang = args.contains("zh") ? .zh : .en
            let showRemaining = args.contains("remaining")
            let prefs = makePrefs(lang)
            prefs.showRemaining = showRemaining
            if goalsMode { prefs.enabledModules = [.quota, .goals] }
            if workMode || breakMode { prefs.enabledModules = [.quota, .work] }
            if mailMode { prefs.enabledModules = [.quota, .mailBrief] }
            if launchdMode { prefs.enabledModules = [.quota, .launchd] }

            let store = QuotaStore(previewProviders: mocks, updated: Date())
            let workSession = WorkSessionController(prefs: prefs)
            if breakMode { workSession.startBreak() }
            let systemMonitor = SystemMonitor()
            let dailyGoals = goalsMode ? makeGoalsStore() : DailyGoalStore()
            let fixedPlanStore = FixedPlanStore()
            let aiNewsStore = AIHotNewsStore()
            let mailBriefStore = mailMode
                ? MailBriefStore(previewGeneration: makeMailGeneration())
                : MailBriefStore(cacheURL: URL(fileURLWithPath: "/tmp/kaji-snapshot-mail.json"))
            let launchdJobStore = LaunchdJobStore(initialSnapshot: LaunchdJobSnapshot(jobs: [
                LaunchdJob(label: "com.bubu.lisa-daemon", pid: 65368, lastExitCode: 0, isInstalledUserAgent: true, state: .running),
                LaunchdJob(label: "dev.bubu.hub-sync", pid: 842, lastExitCode: 0, isInstalledUserAgent: true, state: .running),
                LaunchdJob(label: "com.openai.atlas.update-helper", pid: nil, lastExitCode: 78, isInstalledUserAgent: true, state: .failed),
                LaunchdJob(label: "com.google.keystone.agent", pid: nil, lastExitCode: nil, isInstalledUserAgent: true, state: .unloaded),
                LaunchdJob(label: "com.apple.coreservices.uiagent", pid: 321, lastExitCode: 0, isInstalledUserAgent: false, state: .running),
            ]))
            let navigation = PopoverNavigation()
            if goalsMode { navigation.panel = .goals }
            if workMode || breakMode { navigation.panel = .work }
            if mailMode { navigation.panel = .mailBrief }
            if launchdMode { navigation.panel = .launchd }
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
                aiNewsStore: aiNewsStore,
                mailBriefStore: mailBriefStore,
                launchdJobStore: launchdJobStore,
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
                fixedPlanStore: fixedPlanStore,
                mailBriefStore: mailBriefStore
            )
            .frame(width: 760, height: 560)

            let arg = args.first ?? "both"
            if settingsMode {
                let size = NSSize(width: 760, height: 560)
                renderHosting(settings, appearance: .darkAqua, scheme: .dark, size: size, to: "/tmp/settings-dark.png")
                renderHosting(settings, appearance: .aqua, scheme: .light, size: size, to: "/tmp/settings-light.png")
                return
            }
            if mailMode {
                render(popover, appearance: .darkAqua, scheme: .dark, to: "/tmp/mail-dark.png")
                render(popover, appearance: .aqua, scheme: .light, to: "/tmp/mail-light.png")
                return
            }
            if launchdMode {
                render(popover, appearance: .darkAqua, scheme: .dark, to: "/tmp/launchd-dark.png")
                render(popover, appearance: .aqua, scheme: .light, to: "/tmp/launchd-light.png")
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
