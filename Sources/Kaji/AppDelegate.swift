import AppKit
import SwiftUI
import Combine

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
    private let petRunner = PetRunner()
    private let petCatalog = PetCatalogStore()
    private lazy var workSession = WorkSessionController(prefs: prefs)
    private let systemMonitor = SystemMonitor()
    private let dailyGoals = DailyGoalStore()
    private var breakWindows: [NSWindow] = []
    private var breakWatchdogTimer: Timer?
    private var petStateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        systemMonitor.start()
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
        prefs.$menubarStyle
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
        prefs.$petId
            .receive(on: RunLoop.main)
            .sink { [weak self] petId in
                self?.handlePetSelectionChanged(petId)
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
            }
            .store(in: &cancellables)
        prefs.$autoCleanEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.systemMonitor.runAutoMaintenanceIfNeeded() }
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
                if enabled {
                    self.handleWorkPhaseChanged(self.workSession.phase)
                } else {
                    self.closeBreakOverlay()
                }
            }
            .store(in: &cancellables)
        systemMonitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.prefs.autoCleanEnabled else { return }
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

    /// Providers the user has chosen to show, in display order — drives both the
    /// menubar glyphs and (via GaugeRowView) the popover rings.
    private var visibleProviders: [ProviderView] {
        store.providers.filter { prefs.isVisible($0.id) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        breakWatchdogTimer?.invalidate()
        petStateTimer?.invalidate()
        petRunner.stop(force: true)
        closeBreakOverlay()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Re-check on reactivation; the checker's own once/6h throttle keeps this
        // from hitting the network on every menubar interaction.
        updateChecker.checkIfDue()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        let view = StatusItemView(providers: visibleProviders,
                                  style: .blackWhite,
                                  showRemaining: prefs.showRemaining,
                                  updateAvailable: updateChecker.available != nil)
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

        button.target = self
        button.action = #selector(statusButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func updateStatusItem() {
        hostingView?.rootView = StatusItemView(providers: visibleProviders,
                                               style: .blackWhite,
                                               showRemaining: prefs.showRemaining,
                                               updateAvailable: updateChecker.available != nil)
        statusItem.length = statusItemLength
    }

    private var statusItemLength: CGFloat {
        let count = max(1, min(4, visibleProviders.count))
        return CGFloat(count) * 26 + 6
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        togglePopover(sender)
    }

    // MARK: - Popover

    private func setupPopover() {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        popover = pop
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
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
    }

    private func makePopoverContentController(maxContentHeight: CGFloat? = nil) -> NSHostingController<AnyView> {
        let controls = GaugeRowView.Controls(
            onRefresh: { [weak self] in self?.store.refresh() },
            onUpdate: { [weak self] in self?.handleUpdateAction() },
            onToggleKeepAwake: { [weak self] in self?.sleepController.toggle() },
            onTogglePet: { [weak self] in
                guard let self else { return }
                self.petRunner.toggle(petId: self.prefs.petId)
            },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        let content = KajiPopoverView(store: store,
                                      prefs: prefs,
                                      updateChecker: updateChecker,
                                      sleepController: sleepController,
                                      petRunner: petRunner,
                                      petCatalog: petCatalog,
                                      workSession: workSession,
                                      systemMonitor: systemMonitor,
                                      dailyGoals: dailyGoals,
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

        let controller = KajiHostingController(rootView: SettingsView(prefs: prefs, petCatalog: petCatalog))
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

    private func refreshPetCatalogSelection() {
        let resolvedPetId = petCatalog.refresh(selectedPetId: prefs.petId)
        guard !resolvedPetId.isEmpty, prefs.petId != resolvedPetId else { return }
        prefs.petId = resolvedPetId
    }

    private func handlePetSelectionChanged(_ petId: String) {
        guard petRunner.isRunning,
              !petRunner.isBusy,
              petRunner.runningPetId != petId else {
            return
        }
        petRunner.toggle(petId: petId)
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
            for window in breakWindows {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let mainScreen = NSScreen.main
        breakWindows = NSScreen.screens.map { screen in
            let isPrimary = screen == mainScreen
            let view = BreakOverlayView(prefs: prefs,
                                        workSession: workSession,
                                        petCatalog: petCatalog,
                                        dailyGoals: dailyGoals,
                                        isPrimary: isPrimary,
                                        onStartBreak: { [weak self] in self?.workSession.startBreak() },
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
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isMovableByWindowBackground = false
            window.hidesOnDeactivate = false
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
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
