import AppKit
import SwiftUI
import Combine

// MARK: - AppDelegate
//
// Wires the two surfaces:
//   1. NSStatusItem (menubar) — compact indicator; left-click opens a popover
//      with the full ring gauges; right-click opens a menu (toggle panel, quit).
//   2. Floating NSPanel — the same gauges, always-on-top, draggable.
//
// The app runs as an LSUIElement agent (no dock icon, set in Info.plist).
//
// @MainActor: all of this is main-thread UI work, and it touches the
// @MainActor-isolated QuotaStore / FloatingPanelController. Marking the whole
// delegate keeps it concurrency-clean under stricter checking.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = QuotaStore()
    private let prefs = Prefs()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var panelController: FloatingPanelController!
    private var hostingView: NSHostingView<StatusItemView>!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        panelController = FloatingPanelController(store: store, prefs: prefs)

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

        updateStatusItem()
        panelController.restore()
    }

    /// Providers the user has chosen to show, in display order — drives both the
    /// menubar glyphs and (via GaugeRowView) the popover rings.
    private var visibleProviders: [ProviderView] {
        store.providers.filter { prefs.isVisible($0.id) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        let view = StatusItemView(providers: visibleProviders,
                                  style: prefs.menubarStyle)
        hostingView = NSHostingView(rootView: view)
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
                                               style: prefs.menubarStyle)
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
        // Rebuild content each open so the panel toggle label reflects current
        // state. No fixed width — the view hugs its content (adaptive to N rings).
        let controls = GaugeRowView.Controls(
            panelVisible: panelController.isVisible,
            onTogglePanel: { [weak self] in
                self?.panelController.toggle()
                self?.popover.performClose(nil)
            },
            onQuit: { NSApp.terminate(nil) }
        )
        let content = GaugeRowView(store: store, prefs: prefs, controls: controls)
        popover.contentViewController = NSHostingController(rootView: content)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
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

        // Menu-bar style submenu (Mono / Color), radio-checked.
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
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        // Language toggle — shows the OTHER language as the action label.
        let langItem = NSMenuItem(title: "\(L10n.t(.language, lang)): \(lang.toggled.label)",
                                  action: #selector(toggleLanguage),
                                  keyEquivalent: "")
        langItem.target = self
        menu.addItem(langItem)

        menu.addItem(.separator())

        let panelItem = NSMenuItem(
            title: L10n.t(panelController.isVisible ? .hidePanel : .showPanel, lang),
            action: #selector(togglePanel), keyEquivalent: "")
        panelItem.target = self
        menu.addItem(panelItem)

        let refreshItem = NSMenuItem(title: L10n.t(.refreshNow, lang),
                                     action: #selector(refreshNow),
                                     keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

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

    @objc private func togglePanel() {
        panelController.toggle()
    }

    @objc private func refreshNow() {
        store.refresh()
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

    @objc private func toggleLanguage() {
        prefs.language = prefs.language.toggled
    }
}
