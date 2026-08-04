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
    private let store = QuotaStore()
    private let prefs = Prefs()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var popoverHostingController: NSHostingController<AnyView>?
    private var settingsWindow: NSWindow?
    private var hostingView: KajiHostingView<StatusItemView>!
    private let updateChecker = UpdateChecker()
    private let sleepController = SleepController()
    private let petCatalog = PetCatalogStore()
    private lazy var workSession = WorkSessionController(prefs: prefs)
    private let systemMonitor = SystemMonitor()
    private let dailyGoals = DailyGoalStore()
    private let fixedPlanStore = FixedPlanStore()
    private let popoverNavigation = PopoverNavigation()
    private let aiNewsStore = AIHotNewsStore()
    private var breakWindows: [NSWindow] = []
    private var breakSceneSeed: UInt64?
    private var breakWatchdogTimer: Timer?
    private var petStateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        sleepController.onStateChanged = { [weak self] enabled in
            self?.prefs.preventSleep = enabled
        }
        sleepController.refresh()
        store.start()
        applyModuleLifecycle(prefs.enabledModules)
        refreshPetCatalogSelection()

        setupStatusItem()
        setupPopover()

        // Re-render the menubar indicator whenever data OR the visible-provider /
        // menubar-style prefs change.
        store.$providers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
                self?.publishPetState()
            }
            .store(in: &cancellables)
        store.$lastError
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.publishPetState() }
            .store(in: &cancellables)
        prefs.$visibleProviders
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        prefs.$showRemaining
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        // Popover size + visible-providers reactive: when the user flips
        // S/M from the popover (or toggles a provider) while the
        // popover is open, the host content rebuilds with the new size.
        prefs.$panelSize
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildPopoverContentIfShown() }
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
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.publishPetState() }
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
        prefs.$autoCleanEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled, self.prefs.isModuleEnabled(.system) {
                    self.systemMonitor.runAutoMaintenanceIfNeeded()
                }
            }
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
        systemMonitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self,
                      self.prefs.autoCleanEnabled,
                      self.prefs.isModuleEnabled(.system) else { return }
                self.systemMonitor.runAutoMaintenanceIfNeeded()
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
        startPetStateTimer()

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
    }

    /// Providers the user has chosen to show, in display order — drives both the
    /// menubar glyphs and (via GaugeRowView) the popover rings.
    private var visibleProviders: [ProviderView] {
        store.providers.filter { prefs.isVisible($0.id) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        breakWatchdogTimer?.invalidate()
        petStateTimer?.invalidate()
        closeBreakOverlay()
        aiNewsStore.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Re-check on reactivation; the checker's own once/6h throttle keeps this
        // from hitting the network on every menubar interaction.
        updateChecker.checkIfDue()
        dailyGoals.refreshPeriodBoundaries()
        if prefs.isModuleEnabled(.aiNews) {
            aiNewsStore.setEnabled(true, refreshHours: prefs.aiNewsRefreshHours)
        }
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
                                  onQuotaClick: { [weak self] in self?.showPopover(.quota) },
                                  onWorkClick: { [weak self] in self?.showPopover(.work) },
                                  onGoalsClick: { [weak self] in self?.showPopover(.goalsToday) },
                                  onAINewsClick: { [weak self] in self?.showPopover(.aiNews) })
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
                                               onQuotaClick: { [weak self] in self?.showPopover(.quota) },
                                               onWorkClick: { [weak self] in self?.showPopover(.work) },
                                               onGoalsClick: { [weak self] in self?.showPopover(.goalsToday) },
                                               onAINewsClick: { [weak self] in self?.showPopover(.aiNews) })
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
            goals: dailyGoals.goals,
            fixedPlanCompleted: fixedPlanStore.isTodayCompleted
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
        return length
    }

    // MARK: - Popover

    private func setupPopover() {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        popover = pop
    }

    private func showPopover(_ destination: MenuBarDestination) {
        guard let sender = statusItem.button else { return }
        dailyGoals.refreshPeriodBoundaries()
        if popover.isShown {
            if destinationMatchesCurrentPanel(destination) {
                popover.performClose(sender)
                return
            }
            applyPopoverDestination(destination)
            return
        }

        // AppKit's first fitting pass can leave the initial SwiftUI page offset.
        // Fit from another enabled page, then switch after placement so every
        // direct menu-bar destination follows the same path as normal paging.
        let stagingDestination = popoverStagingDestination(for: destination)
        applyPopoverDestination(stagingDestination)
        let requestedDestination = destination

        // Rebuild content each open. Width is pinned to `prefs.panelSize`
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

    private func popoverStagingDestination(for destination: MenuBarDestination) -> MenuBarDestination {
        switch destination {
        case .quota:
            if prefs.isModuleEnabled(.work) { return .work }
            if prefs.isModuleEnabled(.goals) { return .goalsToday }
            return .quota
        case .work, .goalsToday, .aiNews:
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
        }
    }

    private func makePopoverContentController(maxContentHeight: CGFloat? = nil) -> NSHostingController<AnyView> {
        let controls = GaugeRowView.Controls(
            onRefresh: { [weak self] in self?.store.refresh() },
            onUpdate: { [weak self] in self?.handleUpdateAction() },
            onToggleKeepAwake: { [weak self] in self?.sleepController.toggle() },
            onTogglePet: {},
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        let content = KajiPopoverView(store: store,
                                      prefs: prefs,
                                      workSession: workSession,
                                      systemMonitor: systemMonitor,
                                      dailyGoals: dailyGoals,
                                      fixedPlanStore: fixedPlanStore,
                                      aiNewsStore: aiNewsStore,
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
        let width = prefs.panelSize.frameSize.width
        controller.view.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        controller.view.layoutSubtreeIfNeeded()
        let fittingHeight = controller.view.fittingSize.height
        return CGSize(width: width, height: min(fittingHeight, maxPopoverHeight(on: statusItem.button?.window?.screen)))
    }

    private func resizePopoverContent(to measuredSize: CGSize) {
        guard popover != nil, popover.isShown else { return }
        let width = prefs.panelSize.frameSize.width
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
        return max(360, visibleHeight - 28)
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

    private func openSettings() {
        refreshPetCatalogSelection()
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = KajiHostingController(rootView: SettingsView(prefs: prefs,
                                                                       sleepController: sleepController,
                                                                       petCatalog: petCatalog,
                                                                       fixedPlanStore: fixedPlanStore,
                                                                       onFixedPlanEditorChange: { [weak self] shown in
                                                                           self?.resizeSettingsWindow(showingDetail: shown)
                                                                       }))
        controller.view.configureKajiHost(cornerRadius: 12)
        let window = NSWindow(contentViewController: controller)
        window.title = "Kaji Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func resizeSettingsWindow(showingDetail: Bool) {
        guard let window = settingsWindow else { return }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        let width: CGFloat = showingDetail ? 701 : 360
        window.setContentSize(NSSize(width: width, height: window.contentLayoutRect.height))
        window.setFrameTopLeftPoint(topLeft)
    }

    private func refreshPetCatalogSelection() {
        let resolvedPetId = petCatalog.refresh(selectedPetId: prefs.petId)
        guard !resolvedPetId.isEmpty, prefs.petId != resolvedPetId else { return }
        prefs.petId = resolvedPetId
    }

    private func publishPetState() {
        PetBridge.write(providers: store.providers,
                        lastError: store.lastError,
                        generatedAt: store.lastUpdated ?? Date())
    }

    private func startPetStateTimer() {
        petStateTimer?.invalidate()
        petStateTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.publishPetState()
            }
        }
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
        let sceneSeed = breakSceneSeed ?? UInt64.random(in: UInt64.min...UInt64.max)
        breakSceneSeed = sceneSeed
        let scene = BreakSceneModel.scene(sessionSeed: sceneSeed)
        breakWindows = NSScreen.screens.map { screen in
            let isPrimary = screen == mainScreen
            let view = BreakOverlayView(prefs: prefs,
                                        workSession: workSession,
                                        scene: scene,
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
        breakSceneSeed = nil
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindow else { return }
        settingsWindow = nil
    }
}
