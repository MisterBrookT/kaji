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
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var panelController: FloatingPanelController!
    private var hostingView: NSHostingView<StatusItemView>!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        panelController = FloatingPanelController(store: store)

        setupStatusItem()
        setupPopover()

        // Re-render the menubar indicator whenever data changes.
        store.$providers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        updateStatusItem()
        panelController.restore()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        let view = StatusItemView(provider: store.mostConstrained)
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
        hostingView?.rootView = StatusItemView(provider: store.mostConstrained)
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
        // No fixed width — the view hugs its content (adaptive to N rings).
        let content = GaugeRowView(store: store)
        pop.contentViewController = NSHostingController(rootView: content)
        popover = pop
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Right-click menu

    private func showMenu() {
        let menu = NSMenu()

        let panelTitle = panelController.isVisible
            ? "Hide Floating Panel" : "Show Floating Panel"
        let panelItem = NSMenuItem(title: panelTitle,
                                   action: #selector(togglePanel),
                                   keyEquivalent: "")
        panelItem.target = self
        menu.addItem(panelItem)

        let refreshItem = NSMenuItem(title: "Refresh Now",
                                     action: #selector(refreshNow),
                                     keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Kaji Gauge",
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
}
