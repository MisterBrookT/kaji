import AppKit
import SwiftUI
import Combine
import KajiCore

// MARK: - AppDelegate
//
// Wires the status-bar surface:
//   NSStatusItem (menubar) — compact indicator; left-click or right-click opens
//   the same popover with quota, provider, update, and system controls.
//
// The app runs as an LSUIElement agent (no dock icon, set in Info.plist).
//
// @MainActor: all of this is main-thread UI work, and it touches the
// @MainActor-isolated QuotaStore. Marking the whole delegate keeps it
// concurrency-clean under stricter checking.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store: QuotaStore
    private let prefs: Prefs
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    private var popoverHostingController: NSHostingController<AnyView>?
    var detailPopover: NSPopover?
    private var settingsWindow: NSWindow?
    var hostingView: KajiHostingView<StatusItemView>!
    private let updateChecker = UpdateChecker()
    private let sleepController = SleepController()
    private lazy var workSession = WorkSessionController(prefs: prefs)
    private let systemMonitor = SystemMonitor()
    let dailyGoals: DailyGoalStore
    private lazy var controlServer: KajiControlServer = {
        let environment = ProcessInfo.processInfo.environment
        let testNonce = environment["KAJI_UI_SMOKE_NONCE"]
        let testPort = environment["KAJI_UI_SMOKE_PORT"].flatMap(UInt16.init)
        let automation = testNonce.map { nonce in
            KajiControlServer.TestAutomation(
                nonce: nonce,
                render: { [weak self] surface, selection, outputPath in
                    guard let self else { throw TestUIAutomationError.appUnavailable }
                    return try self.renderTestSurface(
                        surface: surface,
                        selection: selection,
                        outputPath: outputPath
                    )
                },
                perform: { [weak self] action, target in
                    guard let self else { throw TestUIAutomationError.appUnavailable }
                    return try self.performTestAction(action, target: target)
                }
            )
        }
        return KajiControlServer(
            goals: dailyGoals,
            port: testPort ?? KajiControlServer.port,
            snapshotProvider: { [weak self] in self?.controlSnapshot() ?? [:] },
            testAutomation: automation
        )
    }()
    let fixedPlanStore: FixedPlanStore
    let popoverNavigation = PopoverNavigation()
    private let aiNewsStore: AIHotNewsStore
    private let mailBriefStore: MailBriefStore
    private let launchdJobStore = LaunchdJobStore()
    private var breakWindows: [NSWindow] = []
    private var breakWatchdogTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    override convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults, cacheDirectory: URL? = nil, store: QuotaStore? = nil) {
        self.store = store ?? QuotaStore()
        prefs = Prefs(defaults: defaults)
        dailyGoals = DailyGoalStore(defaults: defaults)
        fixedPlanStore = FixedPlanStore(defaults: defaults)
        aiNewsStore = AIHotNewsStore(
            cacheURL: cacheDirectory?.appendingPathComponent("ai-news-cache-v1.json")
        )
        mailBriefStore = MailBriefStore(
            cacheURL: cacheDirectory?.appendingPathComponent("mail-brief-cache-v1.json")
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Establish the visible app surface before any optional module can probe
        // credentials. A stale keychain ACL must never prevent the status item.
        setupStatusItem()
        setupPopover()

        sleepController.onStateChanged = { [weak self] enabled in
            self?.prefs.preventSleep = enabled
        }
        sleepController.refresh()
        store.start()
        applyModuleLifecycle(prefs.enabledModules)
        controlServer.start()

        // Re-render the menubar indicator whenever data OR the visible-provider /
        // menubar-style prefs change.
        store.$providers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
        prefs.$visibleProviders
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        prefs.$showRemaining
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        prefs.$visibleProviders
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildPopoverContentIfShown() }
            .store(in: &cancellables)
        prefs.$enabledModules
            .receive(on: RunLoop.main)
            .sink { [weak self] modules in
                self?.applyModuleLifecycle(modules)
                self?.updateStatusItem()
                self?.rebuildPopoverContentIfShown()
            }
            .store(in: &cancellables)
        prefs.$aiNewsRefreshHours
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] hours in self?.aiNewsStore.updateRefreshHours(hours) }
            .store(in: &cancellables)
        Publishers.CombineLatest4(prefs.$mailBriefHour, prefs.$mailBriefMinute,
                                  prefs.$mailBriefBatchSize, prefs.$mailBriefConcurrency)
            .receive(on: RunLoop.main)
            .sink { [weak self] hour, minute, batchSize, concurrency in
                guard let self else { return }
                self.mailBriefStore.setEnabled(self.prefs.isModuleEnabled(.mailBrief), hour: hour, minute: minute,
                                               batchSize: batchSize, concurrency: concurrency,
                                               model: self.prefs.mailBriefModel)
            }.store(in: &cancellables)
        prefs.$mailBriefModel
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] model in
                guard let self else { return }
                self.mailBriefStore.setEnabled(self.prefs.isModuleEnabled(.mailBrief),
                    hour: self.prefs.mailBriefHour, minute: self.prefs.mailBriefMinute,
                    batchSize: self.prefs.mailBriefBatchSize, concurrency: self.prefs.mailBriefConcurrency,
                    model: model)
            }.store(in: &cancellables)
        mailBriefStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatusItem() } }
            .store(in: &cancellables)
        launchdJobStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatusItem() } }
            .store(in: &cancellables)
        dailyGoals.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
        fixedPlanStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
        workSession.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.handleWorkPhaseChanged(phase)
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
        // Second-level work clocks drive the menu-bar countdown when work is on.
        workSession.$workElapsed
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        workSession.$breakRemaining
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        prefs.$launchAtLogin
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if !LoginItemManager.setEnabled(enabled) {
                    self?.prefs.launchAtLogin = !enabled
                }
            }
            .store(in: &cancellables)
        prefs.$breakOverlayEnabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled, self.prefs.isModuleEnabled(.work) {
                    self.handleWorkPhaseChanged(self.workSession.phase)
                } else {
                    self.closeBreakOverlay()
                }
            }
            .store(in: &cancellables)
        // Update availability re-renders the glyph (adds/removes the badge dot).
        updateChecker.$available
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
        // Check on launch; re-check when the app is reactivated (cheap, throttled
        // to once per interval inside the checker).
        updateChecker.checkIfDue()
        startBreakWatchdog()

        updateStatusItem()
    }

    private func applyModuleLifecycle(_ modules: Set<KajiModuleID>) {
        if modules.contains(.work) {
            workSession.start()
        } else {
            workSession.stopAndReset()
            closeBreakOverlay()
        }

        if modules.contains(.system) {
            systemMonitor.start()
        } else {
            systemMonitor.stop()
        }
        aiNewsStore.setEnabled(modules.contains(.aiNews), refreshHours: prefs.aiNewsRefreshHours)
        mailBriefStore.setEnabled(modules.contains(.mailBrief), hour: prefs.mailBriefHour, minute: prefs.mailBriefMinute,
                                  batchSize: prefs.mailBriefBatchSize, concurrency: prefs.mailBriefConcurrency,
                                  model: prefs.mailBriefModel)
        let launchdEnabled = modules.contains(.launchd)
        launchdJobStore.setEnabled(launchdEnabled)
        if launchdEnabled { launchdJobStore.refreshStatus() }
    }

    /// Providers the user has chosen to show, in display order — drives both the
    /// menubar glyphs and (via GaugeRowView) the popover rings.
    private var visibleProviders: [ProviderView] {
        store.providers.filter { prefs.isVisible($0.id) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        closeDetailPopover()
        store.stop()
        breakWatchdogTimer?.invalidate()
        closeBreakOverlay()
        aiNewsStore.stop()
        mailBriefStore.stop()
        launchdJobStore.stop()
        controlServer.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Re-check on reactivation; the checker's own once/6h throttle keeps this
        // from hitting the network on every menubar interaction.
        updateChecker.checkIfDue()
        dailyGoals.refreshPeriodBoundaries()
        sleepController.resumePendingApprovalIfAuthorized()
        if prefs.isModuleEnabled(.aiNews) {
            aiNewsStore.setEnabled(true, refreshHours: prefs.aiNewsRefreshHours)
        }
        if prefs.isModuleEnabled(.mailBrief) { mailBriefStore.evaluateSchedule() }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        let view = StatusItemView(providers: visibleProviders,
                                  showRemaining: prefs.showRemaining,
                                  updateAvailable: updateChecker.available != nil,
                                  workSlotLabel: workStatusSlotLabel,
                                  goalsSlotLabel: goalsStatusSlotLabel,
                                  showsAINewsSlot: prefs.isModuleEnabled(.aiNews),
                                  mailBriefSlotLabel: MenuBarSlotLogic.mailBriefLabel(enabled: prefs.isModuleEnabled(.mailBrief), actCount: mailBriefStore.actCount),
                                  showsMailBriefSlot: prefs.isModuleEnabled(.mailBrief),
                                  launchdStatus: launchdStatus,
                                  onQuotaClick: { [weak self] in self?.showPopover(.quota) },
                                  onWorkClick: { [weak self] in self?.showPopover(.work) },
                                  onGoalsClick: { [weak self] in self?.showPopover(.goalsToday) },
                                  onAINewsClick: { [weak self] in self?.showPopover(.aiNews) },
                                  onMailBriefClick: { [weak self] in self?.showPopover(.mailBrief) },
                                  onLaunchdClick: { [weak self] in self?.showPopover(.launchd) })
        hostingView = KajiHostingView(rootView: view)
        hostingView.configureKajiHost()
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
    }

    private func updateStatusItem() {
        hostingView?.rootView = StatusItemView(providers: visibleProviders,
                                               showRemaining: prefs.showRemaining,
                                               updateAvailable: updateChecker.available != nil,
                                               workSlotLabel: workStatusSlotLabel,
                                               goalsSlotLabel: goalsStatusSlotLabel,
                                               showsAINewsSlot: prefs.isModuleEnabled(.aiNews),
                                               mailBriefSlotLabel: MenuBarSlotLogic.mailBriefLabel(enabled: prefs.isModuleEnabled(.mailBrief), actCount: mailBriefStore.actCount),
                                               showsMailBriefSlot: prefs.isModuleEnabled(.mailBrief),
                                               launchdStatus: launchdStatus,
                                               onQuotaClick: { [weak self] in self?.showPopover(.quota) },
                                               onWorkClick: { [weak self] in self?.showPopover(.work) },
                                               onGoalsClick: { [weak self] in self?.showPopover(.goalsToday) },
                                               onAINewsClick: { [weak self] in self?.showPopover(.aiNews) },
                                               onMailBriefClick: { [weak self] in self?.showPopover(.mailBrief) },
                                               onLaunchdClick: { [weak self] in self?.showPopover(.launchd) })
        statusItem.length = statusItemLength
    }

    /// Menu-bar work countdown from `WorkStatusSlotModel` (nil when work off).
    private var workStatusSlotLabel: String? {
        let phase: WorkStatusSlotPhase
        switch workSession.phase {
        case .working: phase = .working
        case .breakDue: phase = .breakDue
        case .breaking: phase = .breaking
        }
        let focusRemaining = max(0, workSession.focusTarget - workSession.workElapsed)
        return WorkStatusSlotModel.label(
            workEnabled: prefs.isModuleEnabled(.work),
            phase: phase,
            focusRemaining: focusRemaining,
            breakRemaining: workSession.breakRemaining
        )
    }

    private var goalsStatusSlotLabel: String? {
        MenuBarSlotLogic.goalsLabel(
            enabled: prefs.isModuleEnabled(.goals),
            goals: dailyGoals.todayGoalEntries,
            scheduledCompleted: fixedPlanStore.todayScheduledCompletedCount,
            scheduledTotal: fixedPlanStore.todayScheduledEntries.count
        )
    }

    private var launchdStatus: LaunchdMenuBarStatus? {
        let summary = launchdJobStore.snapshot.installedSummary
        return MenuBarSlotLogic.launchdStatus(
            enabled: prefs.isModuleEnabled(.launchd),
            runningCount: summary.runningCount,
            failedCount: summary.failedCount
        )
    }

    private var statusItemLength: CGFloat {
        let count = max(1, min(4, visibleProviders.count))
        var length = CGFloat(count) * 26 + 6
        // Compact monospaced `MM:SS` to the right of the rings (~40pt).
        if workStatusSlotLabel != nil {
            length += 40
        }
        if let goalsStatusSlotLabel {
            length += 20 + CGFloat(goalsStatusSlotLabel.count) * 7
        }
        if prefs.isModuleEnabled(.aiNews) { length += 20 }
        if prefs.isModuleEnabled(.mailBrief) {
            length += 22 + CGFloat(MenuBarSlotLogic.mailBriefLabel(enabled: true, actCount: mailBriefStore.actCount)?.count ?? 0) * 7
        }
        if let launchdStatus {
            length += 22 + CGFloat(String(launchdStatus.count).count) * 7
        }
        return length
    }

    // MARK: - Popover

    private func setupPopover() {
        let pop = NSPopover()
        // The child is anchored to a view inside this popover, so AppKit
        // treats it as a nested popover without dismissing this transient
        // parent. Keeping transient preserves click-outside dismissal when
        // the user switches to another app or the desktop.
        pop.behavior = .transient
        pop.animates = true
        pop.delegate = self
        popover = pop
    }

    func showPopover(_ destination: MenuBarDestination) {
        guard let sender = statusItem.button else { return }
        dailyGoals.refreshPeriodBoundaries()
        if popover.isShown {
            if destinationMatchesCurrentPanel(destination) {
                closeDetailPopover()
                popover.performClose(sender)
                return
            }
            applyPopoverDestination(destination)
            return
        }
        popoverNavigation.launchdCategory = .userAgent


        // AppKit's first fitting pass can leave the initial SwiftUI page offset.
        // Fit from another enabled page, then switch after placement so every
        // direct menu-bar destination follows the same path as normal paging.
        let stagingDestination = popoverStagingDestination(for: destination)
        applyPopoverDestination(stagingDestination)
        let requestedDestination = destination

        // Rebuild content each open. Width uses the single standard panel size.
        // so the popover follows S/M; height auto-fits since the popover
        // also shows the settings footer (which the HUD doesn't).
        let controller = makePopoverContentController(maxContentHeight: maxPopoverHeight(on: sender.window?.screen))
        popoverHostingController = controller
        let target = popoverFittingSize(for: controller)
        controller.preferredContentSize = target
        controller.view.frame = NSRect(origin: .zero, size: target)
        controller.view.layoutSubtreeIfNeeded()
        popover.contentSize = target
        popover.contentViewController = controller
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        if requestedDestination != stagingDestination {
            DispatchQueue.main.async { [weak self] in
                self?.applyPopoverDestination(requestedDestination)
            }
        }
    }

    func showDetailPopover(_ content: AnyView, relativeTo sourceView: NSView) {
        closeDetailPopover()

        let controller = NSHostingController(rootView: content)
        let fittingSize = controller.view.fittingSize
        controller.preferredContentSize = fittingSize

        let child = NSPopover()
        child.behavior = .transient
        child.delegate = self
        child.animates = true
        child.contentViewController = controller
        child.contentSize = fittingSize
        detailPopover = child

        let sourceMidX = sourceView.window?.frame.midX ?? 0
        let screenMidX = sourceView.window?.screen?.visibleFrame.midX ?? 0
        child.show(
            relativeTo: sourceView.bounds,
            of: sourceView,
            preferredEdge: sourceMidX < screenMidX ? .maxX : .minX
        )
    }

    func closeDetailPopover() {
        detailPopover?.animates = false
        detailPopover?.performClose(nil)
        detailPopover = nil
    }

    private func popoverStagingDestination(for destination: MenuBarDestination) -> MenuBarDestination {
        switch destination {
        case .quota:
            if prefs.isModuleEnabled(.work) { return .work }
            if prefs.isModuleEnabled(.goals) { return .goalsToday }
            return .quota
        case .work, .goalsToday, .aiNews, .mailBrief, .launchd:
            return .quota
        }
    }

    private func destinationMatchesCurrentPanel(_ destination: MenuBarDestination) -> Bool {
        switch destination {
        case .quota:
            return popoverNavigation.panel == .quota
        case .work:
            return popoverNavigation.panel == .work
        case .goalsToday:
            return popoverNavigation.panel == .goals
        case .aiNews:
            return popoverNavigation.panel == .aiNews
        case .mailBrief:
            return popoverNavigation.panel == .mailBrief
        case .launchd:
            return popoverNavigation.panel == .launchd
        }
    }

    private func applyPopoverDestination(_ destination: MenuBarDestination) {
        switch destination {
        case .quota:
            popoverNavigation.panel = .quota
        case .work:
            guard prefs.isModuleEnabled(.work) else {
                popoverNavigation.panel = .quota
                break
            }
            popoverNavigation.panel = .work
        case .goalsToday:
            guard prefs.isModuleEnabled(.goals) else {
                popoverNavigation.panel = .quota
                break
            }
            popoverNavigation.panel = .goals
            popoverNavigation.goalHorizon = .today
        case .aiNews:
            popoverNavigation.panel = prefs.isModuleEnabled(.aiNews) ? .aiNews : .quota
        case .mailBrief:
            popoverNavigation.panel = prefs.isModuleEnabled(.mailBrief) ? .mailBrief : .quota
        case .launchd:
            popoverNavigation.panel = prefs.isModuleEnabled(.launchd) ? .launchd : .quota
        }
    }

    private func makePopoverContentController(maxContentHeight: CGFloat? = nil) -> NSHostingController<AnyView> {
        let controls = KajiPopoverControls(
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) },
            onShowDetail: { [weak self] sourceView, content in
                self?.showDetailPopover(content, relativeTo: sourceView)
            },
            onDismissDetail: { [weak self] in self?.closeDetailPopover() }
        )
        let content = KajiPopoverView(store: store,
                                      prefs: prefs,
                                      workSession: workSession,
                                      systemMonitor: systemMonitor,
                                      dailyGoals: dailyGoals,
                                      fixedPlanStore: fixedPlanStore,
                                      aiNewsStore: aiNewsStore,
                                      mailBriefStore: mailBriefStore,
                                      launchdJobStore: launchdJobStore,
                                      navigation: popoverNavigation,
                                      controls: controls,
                                      maxContentHeight: maxContentHeight ?? maxPopoverHeight(on: statusItem.button?.window?.screen),
                                      onContentSizeChange: { [weak self] size in
                                          self?.resizePopoverContent(to: size)
                                      })
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        let controller = KajiHostingController(rootView: AnyView(content))
        controller.view.configureKajiHost(cornerRadius: 14)
        return controller
    }

    /// Width is pinned to S/M; height comes from the SwiftUI fitting pass
    /// after the width is fixed (settings footer rows extend the height by
    /// a variable amount per language).
    private func popoverFittingSize(for controller: NSHostingController<AnyView>) -> CGSize {
        let width = PanelSize.medium.frameSize.width
        controller.view.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        controller.view.layoutSubtreeIfNeeded()
        let fittingHeight = controller.view.fittingSize.height
        return CGSize(width: width, height: min(fittingHeight, maxPopoverHeight(on: statusItem.button?.window?.screen)))
    }

    private func resizePopoverContent(to measuredSize: CGSize) {
        guard popover != nil, popover.isShown else { return }
        let width = PanelSize.medium.frameSize.width
        let maxHeight = maxPopoverHeight(on: popover.contentViewController?.view.window?.screen ?? statusItem.button?.window?.screen)
        let target = CGSize(width: width, height: ceil(min(max(1, measuredSize.height), maxHeight)))
        let needsPopoverResize = abs(popover.contentSize.height - target.height) > 0.5 ||
            abs(popover.contentSize.width - target.width) > 0.5
        popoverHostingController?.preferredContentSize = target
        popoverHostingController?.view.frame = NSRect(origin: .zero, size: target)
        popoverHostingController?.view.layoutSubtreeIfNeeded()
        if needsPopoverResize {
            popover.contentSize = target
        }
    }

    private func maxPopoverHeight(on screen: NSScreen?) -> CGFloat {
        let visibleHeight = (screen ?? NSScreen.main)?.visibleFrame.height ?? 760
        // Leave room for NSPopover's arrow, border and AppKit's placement inset.
        // Filling the entire visible frame makes the chrome cross the screen edge,
        // where macOS clips it into a false top padding strip.
        return max(240, visibleHeight - 64)
    }

    /// Rebuild only when layout dimensions change. Normal ObservableObject
    /// updates flow through SwiftUI; rebuilding for every busy/running tick
    /// makes the transient popover visibly jump.
    private func rebuildPopoverContentIfShown() {
        guard popover != nil, popover.isShown else { return }
        let controller = makePopoverContentController(maxContentHeight: maxPopoverHeight(on: popover.contentViewController?.view.window?.screen ?? statusItem.button?.window?.screen))
        popoverHostingController = controller
        let target = popoverFittingSize(for: controller)
        controller.preferredContentSize = target
        controller.view.frame = NSRect(origin: .zero, size: target)
        controller.view.layoutSubtreeIfNeeded()
        popover.contentSize = target
        popover.contentViewController = controller
    }

    private func handleUpdateAction() {
        if updateChecker.available == nil {
            updateChecker.checkIfDue(force: true)
            return
        }
        guard let rel = updateChecker.available else { return }
        do {
            try updateChecker.install(rel)
            NSApp.terminate(nil)
        } catch {
            NSWorkspace.shared.open(rel.url)
        }
    }


    private func controlSnapshot() -> [String: Any] {
        let snapshot = systemMonitor.snapshot
        return [
            "settings": [
                "enabledModules": prefs.enabledModules.map(\.rawValue).sorted(),
                "visibleProviders": prefs.visibleProviders.sorted(),
                "showRemaining": prefs.showRemaining,
                "focusMinutes": prefs.focusMinutes,
                "breakMinutes": prefs.breakMinutes,
                "allowBreakSkip": prefs.allowBreakSkip,
                "breakOverlayEnabled": prefs.breakOverlayEnabled,
                "autoCleanEnabled": prefs.autoCleanEnabled,
                "launchAtLogin": prefs.launchAtLogin,
                "preventSleep": prefs.preventSleep,
                "aiNewsRefreshHours": prefs.aiNewsRefreshHours,
                "mailBriefHour": prefs.mailBriefHour,
                "mailBriefMinute": prefs.mailBriefMinute,
                "mailBriefBatchSize": prefs.mailBriefBatchSize,
                "mailBriefConcurrency": prefs.mailBriefConcurrency,
                "mailBriefModel": prefs.mailBriefModel.rawValue,
            ],
            "sleep": [
                "enabled": sleepController.isEnabled,
                "busy": sleepController.isBusy,
                "targetEnabled": jsonOptional(sleepController.targetEnabled),
                "guidance": jsonOptional(sleepController.approvalFlow.guidance.map(String.init(describing:))),
                "guidancePresented": sleepController.approvalFlow.isGuidancePresented,
                "lastError": jsonOptional(sleepController.lastError),
            ],
            "quota": [
                "providers": store.providers.map {
                    [
                        "id": $0.id,
                        "name": $0.displayName,
                        "fiveHourPercent": jsonOptional($0.fiveHourPercent),
                        "weekPercent": jsonOptional($0.weekPercent),
                        "resetAt": jsonOptional($0.resetDate?.timeIntervalSince1970),
                        "weekResetAt": jsonOptional($0.weekResetDate?.timeIntervalSince1970),
                    ]
                },
                "lastUpdated": jsonOptional(store.lastUpdated?.timeIntervalSince1970),
                "error": jsonOptional(store.lastError),
            ],
            "work": [
                "phase": workSession.phase.rawValue,
                "workElapsed": workSession.workElapsed,
                "breakRemaining": workSession.breakRemaining,
                "skipCountToday": workSession.skipCountToday,
                "completedBreaksToday": workSession.completedBreaksToday,
            ],
            "system": [
                "cpuPercent": snapshot.cpuPercent,
                "memoryPercent": snapshot.memoryPercent,
                "diskPercent": snapshot.diskPercent,
                "processCount": snapshot.processCount,
                "sampledAt": snapshot.sampledAt.timeIntervalSince1970,
                "topProcesses": snapshot.topProcesses.map {
                    ["pid": $0.pid, "cpu": $0.cpu, "memory": $0.memory, "command": $0.command]
                },
                "cleanableItems": systemMonitor.cleanableItems.map {
                    ["id": $0.id, "title": $0.title, "path": $0.path, "bytes": $0.bytes]
                },
                "orphanProcesses": systemMonitor.orphanProcesses.map {
                    ["pid": $0.pid, "ageSeconds": $0.ageSeconds, "command": $0.command]
                },
                "diskInsights": jsonValue(systemMonitor.diskInsights),
            ],
            "goals": [
                "items": dailyGoals.goals(for: .today).map {
                    ["id": $0.id.uuidString.lowercased(), "title": $0.title,
                     "isDone": $0.isDone, "tag": $0.tag, "note": $0.note]
                },
                "tags": dailyGoals.tagDefinitions.map {
                    ["name": $0.name, "colorHex": String(format: "%06X", $0.colorHex)]
                },
                "activity": jsonValue(dailyGoals.heatmapDays),
                "schedules": jsonValue(fixedPlanStore.schedules),
            ],
            "aiNews": [
                "state": String(describing: aiNewsStore.state),
                "topics": jsonValue(aiNewsStore.topics),
                "readTopicIDs": aiNewsStore.readTopicIDs.sorted(),
                "lastSuccessfulRefresh": jsonOptional(aiNewsStore.lastSuccessfulRefresh?.timeIntervalSince1970),
            ],
            "mailBrief": [
                "state": String(describing: mailBriefStore.state),
                "connected": mailBriefStore.isConnected,
                "canModify": mailBriefStore.canModify,
                "nextDue": jsonOptional(mailBriefStore.nextDue?.timeIntervalSince1970),
                "generation": jsonValue(mailBriefStore.generation),
                "replyDrafts": mailBriefStore.replyDrafts,
                "runRecords": jsonValue(mailBriefStore.runRecords),
            ],
            "launchd": [
                "userAgent": controlCategorySnapshot(.userAgent),
                "application": controlCategorySnapshot(.application),
                "appleSystem": controlCategorySnapshot(.appleSystem),
            ],
        ]
    }

    private func controlCategorySnapshot(_ category: LaunchdJobCategory) -> [String: Any] {
        let jobs = launchdJobStore.snapshot.jobs(in: category)
        return [
            "total": jobs.count,
            "running": jobs.count { $0.state == .running },
            "failed": jobs.count { $0.state == .failed },
            "idle": jobs.count { $0.state == .idle },
            "unloaded": jobs.count { $0.state == .unloaded },
        ]
    }

    private func performTestAction(_ action: String, target: Bool?) throws -> [String: Any] {
        guard ProcessInfo.processInfo.environment["KAJI_UI_SMOKE_ARTIFACTS"] != nil else {
            throw TestUIAutomationError.disabled
        }
        switch action {
        case "set-prevent-sleep":
            guard let target else { throw TestUIAutomationError.invalidAction }
            sleepController.setEnabled(target)
        case "perform-sleep-guidance":
            sleepController.performGuidanceAction()
        case "cancel-sleep-guidance":
            sleepController.cancelApprovalRequest()
        default:
            throw TestUIAutomationError.invalidAction
        }
        return [
            "action": action,
            "accepted": true,
        ]
    }

    private func renderTestSurface(
        surface: String,
        selection: String,
        outputPath: String
    ) throws -> [String: Any] {
        guard let artifactRoot = ProcessInfo.processInfo.environment["KAJI_UI_SMOKE_ARTIFACTS"] else {
            throw TestUIAutomationError.disabled
        }
        let rootURL = URL(fileURLWithPath: artifactRoot, isDirectory: true).standardizedFileURL
        let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
        guard outputURL.path.hasPrefix(rootURL.path + "/") else {
            throw TestUIAutomationError.invalidOutputPath
        }

        let size: CGSize
        switch surface {
        case "status":
            updateStatusItem()
            hostingView.layoutSubtreeIfNeeded()
            size = try writePNG(view: hostingView, to: outputURL)
        case "popover":
            let parts = selection.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard let pageID = parts.first,
                  let page = KajiModuleID(rawValue: pageID),
                  prefs.enabledModules.contains(page),
                  parts.count <= 2 else {
                throw TestUIAutomationError.invalidSelection
            }
            if parts.count == 2 {
                guard page == .launchd,
                      let category = LaunchdJobCategory(rawValue: parts[1]) else {
                    throw TestUIAutomationError.invalidSelection
                }
                popoverNavigation.launchdCategory = category
            } else if page == .launchd {
                popoverNavigation.launchdCategory = .userAgent
            }
            popoverNavigation.panel = page
            if page == .goals { popoverNavigation.goalHorizon = .today }
            let controller = makePopoverContentController(maxContentHeight: 640)
            let target = popoverFittingSize(for: controller)
            controller.view.frame = NSRect(origin: .zero, size: target)
            controller.view.layoutSubtreeIfNeeded()
            size = try writePNG(view: controller.view, to: outputURL)
        case "settings":
            guard let section = SettingsSection(rawValue: selection) else {
                throw TestUIAutomationError.invalidSelection
            }
            let view = KajiHostingView(rootView: SettingsView(
                prefs: prefs,
                sleepController: sleepController,
                fixedPlanStore: fixedPlanStore,
                mailBriefStore: mailBriefStore,
                initialSection: section
            ))
            view.configureKajiHost()
            view.frame = NSRect(x: 0, y: 0, width: 760, height: 560)
            view.layoutSubtreeIfNeeded()
            size = try writePNG(view: view, to: outputURL)
        default:
            throw TestUIAutomationError.invalidSurface
        }
        return [
            "surface": surface,
            "selection": selection,
            "path": outputURL.path,
            "width": Int(size.width),
            "height": Int(size.height),
        ]
    }

    private func writePNG(view: NSView, to outputURL: URL) throws -> CGSize {
        guard view.bounds.width > 0, view.bounds.height > 0,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw TestUIAutomationError.renderFailed
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw TestUIAutomationError.renderFailed
        }
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
        return view.bounds.size
    }

    private func jsonValue<T: Encodable>(_ value: T) -> Any {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return NSNull()
        }
        return object
    }

    private func jsonOptional<T>(_ value: T?) -> Any {
        if let value { return value }
        return NSNull()
    }

    private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = KajiHostingController(rootView: SettingsView(prefs: prefs,
                                                                       sleepController: sleepController,
                                                                       fixedPlanStore: fixedPlanStore,
                                                                       mailBriefStore: mailBriefStore))

        controller.view.configureKajiHost()
        let window = NSWindow(contentViewController: controller)
        window.title = "Kaji Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 560))
        window.minSize = NSSize(width: 640, height: 460)
        window.titlebarAppearsTransparent = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }


    private func startBreakWatchdog() {
        breakWatchdogTimer?.invalidate()
        breakWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.handleWorkPhaseChanged(self.workSession.phase)
            }
        }
    }

    private func handleWorkPhaseChanged(_ phase: WorkSessionPhase) {
        guard prefs.isModuleEnabled(.work) else {
            closeBreakOverlay()
            return
        }
        switch phase {
        case .breakDue:
            workSession.startBreak()
            guard prefs.breakOverlayEnabled else {
                closeBreakOverlay()
                return
            }
            showBreakOverlay()
        case .breaking:
            guard prefs.breakOverlayEnabled else {
                closeBreakOverlay()
                return
            }
            showBreakOverlay()
        case .working:
            closeBreakOverlay()
        }
    }

    private func showBreakOverlay() {
        if !breakWindows.isEmpty {
            // The watchdog calls this every second. Only recover windows that
            // somehow became hidden; repeatedly taking key focus prevents the
            // system screenshot UI from staying active.
            breakWindows
                .filter { !$0.isVisible }
                .forEach { $0.orderFrontRegardless() }
            return
        }
        let mainScreen = NSScreen.main
        breakWindows = NSScreen.screens.map { screen in
            let isPrimary = screen == mainScreen
            let view = BreakOverlayView(workSession: workSession,
                                        prefs: prefs,
                                        scene: .windowRain,
                                        isPrimary: isPrimary,
                                        onSkip: { [weak self] in self?.workSession.skipBreak() })
                .ignoresSafeArea()
            let hostingView = KajiHostingView(rootView: view)
            hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
            hostingView.autoresizingMask = [.width, .height]
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

            let window = NSWindow(contentRect: screen.frame,
                                  styleMask: [.borderless],
                                  backing: .buffered,
                                  defer: false,
                                  screen: screen)
            window.contentView = hostingView
            window.isReleasedWhenClosed = false
            window.isOpaque = true
            window.backgroundColor = NSColor.windowBackgroundColor
            window.hasShadow = false
            window.ignoresMouseEvents = !isPrimary
            // Stay above normal/full-screen app windows, but below system UI
            // such as Screenshot's selection overlay and toolbar.
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isMovableByWindowBackground = false
            window.hidesOnDeactivate = false
            if isPrimary {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
            return window
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeBreakOverlay() {
        breakWindows.forEach { $0.close() }
        breakWindows.removeAll()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindow else { return }
        settingsWindow = nil
    }
}
extension AppDelegate: NSPopoverDelegate {
    func popoverWillShow(_ notification: Notification) {
        guard let openingPopover = notification.object as? NSPopover,
              openingPopover === popover else { return }
        launchdJobStore.setPopoverVisible(true)
    }

    func popoverWillClose(_ notification: Notification) {
        guard let closingPopover = notification.object as? NSPopover else { return }
        if closingPopover === detailPopover {
            detailPopover = nil
        } else if closingPopover === popover {
            launchdJobStore.setPopoverVisible(false)
            closeDetailPopover()
        }
    }
}

private enum TestUIAutomationError: Error {
    case appUnavailable
    case disabled
    case invalidOutputPath
    case invalidAction
    case invalidSelection
    case invalidSurface
    case renderFailed
}
