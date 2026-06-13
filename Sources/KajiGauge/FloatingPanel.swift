import AppKit
import SwiftUI

// MARK: - DraggablePanel
//
// An always-on-top, borderless HUD panel that the user can drag anywhere on
// the desktop. .nonactivatingPanel so clicking it never steals focus from the
// frontmost app; .floating level so it stays above normal windows.
final class DraggablePanel: NSPanel {
    init(content: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            // No .hudWindow — its material forces a dark vibrancy that fights the
            // light "Kaji Sun" theme. We paint our own warm gradient instead.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        // Visible on every Space, even over fullscreen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true   // drag from anywhere on the body
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false

        contentView = content
        // Size to fit the SwiftUI content.
        if let fitting = content.fittingSize as NSSize?, fitting.width > 0 {
            setContentSize(fitting)
        }
    }

    // Borderless windows can't become key by default; allow it so SwiftUI
    // interaction works without forcing app activation.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - FloatingPanelController
//
// Owns the panel lifecycle and persists shown/hidden state in UserDefaults.
@MainActor
final class FloatingPanelController {
    private var panel: DraggablePanel?
    private let store: QuotaStore

    init(store: QuotaStore) {
        self.store = store
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    /// Restore the last shown/hidden state on launch.
    func restore() {
        if UserDefaults.standard.bool(forKey: Config.kPanelVisible) {
            show()
        }
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        if panel == nil {
            // No fixed width — GaugeRowView paints its own warm gradient and
            // hugs its content, so the panel fits N rings without dead space.
            let root = GaugeRowView(store: store)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            let hosting = NSHostingView(rootView: root)
            hosting.layer?.cornerRadius = 14
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            let p = DraggablePanel(content: hosting)
            // Place near the top-right of the main screen on first show.
            if let screen = NSScreen.main {
                let v = screen.visibleFrame
                let size = p.frame.size
                p.setFrameOrigin(NSPoint(x: v.maxX - size.width - 24,
                                         y: v.maxY - size.height - 24))
            }
            panel = p
        }
        panel?.orderFrontRegardless()
        UserDefaults.standard.set(true, forKey: Config.kPanelVisible)
    }

    func hide() {
        panel?.orderOut(nil)
        UserDefaults.standard.set(false, forKey: Config.kPanelVisible)
    }
}
