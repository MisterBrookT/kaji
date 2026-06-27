import AppKit
import SwiftUI
import Combine

// MARK: - AppDelegate
//
// Wires the status-bar surface:
//   NSStatusItem (menubar) — compact indicator; left-click opens a popover
//   with the full quota panel; right-click opens a quick menu.
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
    private var hostingView: NSHostingView<StatusItemView>!
    private let updateChecker = UpdateChecker()
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
        // S/M/L from the right-click menu (or toggles a provider) while the
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
            .sink { [weak self] _ in self?.updateStatusItem() }
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
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover(sender)
        }
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
        // so the popover follows S/M/L; height auto-fits since the popover
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
            onQuit: { NSApp.terminate(nil) }
        )
        let content = GaugeRowView(store: store, prefs: prefs,
                                   controls: controls,
                                   panelSize: prefs.panelSize)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        let controller = NSHostingController(rootView: AnyView(content))
        controller.view.configureKajiHost(cornerRadius: 14)
        return controller
    }

    /// Width is pinned to S/M/L; height comes from the SwiftUI fitting pass
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
    /// change (S/M/L size, visible providers). Resizes the popover to the
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

    // MARK: - Right-click menu

    private func showMenu() {
        let lang = prefs.language
        let menu = NSMenu()

        // Provider visibility — one checkmarked item per known provider.
        let providersHeader = NSMenuItem(title: L10n.t(.providers, lang),
                                         action: nil, keyEquivalent: "")
        providersHeader.isEnabled = false
        menu.addItem(providersHeader)
        for p in store.providers {
            let item = NSMenuItem(title: "  \(p.displayName)",
                                  action: #selector(toggleProvider(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = p.id
            item.state = prefs.isVisible(p.id) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Visual style submenu (Calm / Playful / Mono), radio-checked.
        let styleItem = NSMenuItem(title: L10n.t(.menubar, lang), action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        let monoItem = NSMenuItem(title: L10n.t(.styleMono, lang),
                                  action: #selector(setMenubarMono), keyEquivalent: "")
        monoItem.target = self
        monoItem.state = prefs.menubarStyle == .mono ? .on : .off
        styleMenu.addItem(monoItem)
        let colorItem = NSMenuItem(title: L10n.t(.styleColor, lang),
                                   action: #selector(setMenubarColor), keyEquivalent: "")
        colorItem.target = self
        colorItem.state = prefs.menubarStyle == .color ? .on : .off
        styleMenu.addItem(colorItem)
        let bwItem = NSMenuItem(title: L10n.t(.styleBlackWhite, lang),
                                action: #selector(setMenubarBlackWhite), keyEquivalent: "")
        bwItem.target = self
        bwItem.state = prefs.menubarStyle == .blackWhite ? .on : .off
        styleMenu.addItem(bwItem)
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        // Usage submenu (Used / Remaining), radio-checked. Mirrors the popover
        // footer segment so the same mode can be flipped without opening the
        // popover (right-clicking the menubar glyph is faster).
        let usageItem = NSMenuItem(title: L10n.t(.usage, lang), action: nil, keyEquivalent: "")
        let usageMenu = NSMenu()
        let usedItem = NSMenuItem(title: L10n.t(.showUsed, lang),
                                  action: #selector(setShowUsed), keyEquivalent: "")
        usedItem.target = self
        usedItem.state = prefs.showRemaining ? .off : .on
        usageMenu.addItem(usedItem)
        let remItem = NSMenuItem(title: L10n.t(.showRemaining, lang),
                                 action: #selector(setShowRemaining), keyEquivalent: "")
        remItem.target = self
        remItem.state = prefs.showRemaining ? .on : .off
        usageMenu.addItem(remItem)
        usageItem.submenu = usageMenu
        menu.addItem(usageItem)

        let sizeItem = NSMenuItem(title: L10n.t(.panelSize, lang), action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for size in PanelSize.allCases {
            let item = NSMenuItem(title: sizeTitle(size, lang),
                                  action: #selector(setPanelSize(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            item.state = prefs.panelSize == size ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        // Language toggle — shows the OTHER language as the action label.
        let langItem = NSMenuItem(title: "\(L10n.t(.language, lang)): \(lang.toggled.label)",
                                  action: #selector(toggleLanguage),
                                  keyEquivalent: "")
        langItem.target = self
        menu.addItem(langItem)

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: L10n.t(.refreshNow, lang),
                                     action: #selector(refreshNow),
                                     keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        // Update row: actionable when a newer release exists, otherwise a passive
        // "check for updates" that forces a fresh check.
        if let rel = updateChecker.available {
            let updateItem = NSMenuItem(title: L10n.t(.updateTo, lang) + " " + rel.tag,
                                        action: #selector(openUpdate),
                                        keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
        } else {
            let checkItem = NSMenuItem(title: L10n.t(.checkUpdates, lang),
                                       action: #selector(checkUpdatesNow),
                                       keyEquivalent: "")
            checkItem.target = self
            menu.addItem(checkItem)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.t(.quitApp, lang),
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        // Attach + pop, then detach so left-click keeps opening the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshNow() {
        store.refresh()
    }

    @objc private func openUpdate() {
        guard let rel = updateChecker.available else { return }
        NSWorkspace.shared.open(rel.url)
    }

    @objc private func checkUpdatesNow() {
        updateChecker.checkIfDue(force: true)
    }

    @objc private func toggleProvider(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        prefs.toggleProvider(key)
    }

    @objc private func setMenubarMono() {
        prefs.menubarStyle = .mono
    }

    @objc private func setMenubarColor() {
        prefs.menubarStyle = .color
    }

    @objc private func setMenubarBlackWhite() {
        prefs.menubarStyle = .blackWhite
    }

    @objc private func setShowUsed() {
        prefs.showRemaining = false
    }

    @objc private func setShowRemaining() {
        prefs.showRemaining = true
    }

    @objc private func setPanelSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = PanelSize(rawValue: raw) else { return }
        prefs.panelSize = size
    }

    @objc private func toggleLanguage() {
        prefs.language = prefs.language.toggled
    }

    private func sizeTitle(_ size: PanelSize, _ lang: Lang) -> String {
        switch size {
        case .small:  return L10n.t(.sizeSmall, lang)
        case .medium: return L10n.t(.sizeMedium, lang)
        }
    }
}
