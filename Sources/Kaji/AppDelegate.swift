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
    private var hostingView: NSHostingView<StatusItemView>!
    private let updateChecker = UpdateChecker()
    private let sleepController = SleepController()
    private let petRunner = PetRunner()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()

        setupStatusItem()
        setupPopover()

        // Re-render the menubar indicator whenever data OR the visible-provider /
        // menubar-style prefs change.
        store.$providers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
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
            .sink { [weak self] _ in self?.refreshPopoverContentIfShown() }
            .store(in: &cancellables)
        prefs.$visibleProviders
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPopoverContentIfShown() }
            .store(in: &cancellables)
        // Update availability re-renders the glyph (adds/removes the badge dot).
        updateChecker.$available
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
                self?.refreshPopoverContentIfShown()
            }
            .store(in: &cancellables)
        sleepController.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPopoverContentIfShown() }
            .store(in: &cancellables)
        sleepController.$isBusy
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPopoverContentIfShown() }
            .store(in: &cancellables)
        petRunner.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPopoverContentIfShown() }
            .store(in: &cancellables)
        petRunner.$isBusy
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPopoverContentIfShown() }
            .store(in: &cancellables)
        petRunner.$lastError
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPopoverContentIfShown() }
            .store(in: &cancellables)
        // Check on launch; re-check when the app is reactivated (cheap, throttled
        // to once per interval inside the checker).
        updateChecker.checkIfDue()

        updateStatusItem()
    }

    /// Providers the user has chosen to show, in display order — drives both the
    /// menubar glyphs and (via GaugeRowView) the popover rings.
    private var visibleProviders: [ProviderView] {
        store.providers.filter { prefs.isVisible($0.id) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        petRunner.stop()
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
                                  style: prefs.menubarStyle,
                                  showRemaining: prefs.showRemaining,
                                  updateAvailable: updateChecker.available != nil)
        hostingView = NSHostingView(rootView: view)
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
                                               style: prefs.menubarStyle,
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
        let controller = makePopoverContentController()
        popoverHostingController = controller
        let target = popoverFittingSize(for: controller)
        controller.preferredContentSize = target
        popover.contentSize = target
        popover.contentViewController = controller
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makePopoverContentController() -> NSHostingController<AnyView> {
        let controls = GaugeRowView.Controls(
            onRefresh: { [weak self] in self?.store.refresh() },
            onUpdate: { [weak self] in self?.handleUpdateAction() },
            onToggleKeepAwake: { [weak self] in self?.sleepController.toggle() },
            onTogglePet: { [weak self] in self?.petRunner.toggle() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        let content = GaugeRowView(store: store, prefs: prefs,
                                   updateChecker: updateChecker,
                                   sleepController: sleepController,
                                   petRunner: petRunner,
                                   controls: controls,
                                   panelSize: prefs.panelSize)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        let controller = NSHostingController(rootView: AnyView(content))
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
        return CGSize(width: width, height: fittingHeight)
    }

    /// Live-rebuild the popover content view when prefs that affect layout
    /// change (S/M size, visible providers). Resizes the popover to the
    /// new target frame so the change is visible without re-opening.
    private func refreshPopoverContentIfShown() {
        guard popover != nil, popover.isShown else { return }
        let controller = makePopoverContentController()
        popoverHostingController = controller
        let target = popoverFittingSize(for: controller)
        controller.preferredContentSize = target
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
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: SettingsView(prefs: prefs))
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
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindow else { return }
        settingsWindow = nil
    }
}
