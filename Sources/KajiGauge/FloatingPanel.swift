import AppKit
import SwiftUI
import Combine

// MARK: - DraggablePanel
final class DraggablePanel: NSPanel {
    init(content: NSView) {
        let fitting = content.fittingSize
        let initialSize = NSSize(
            width: max(1, fitting.width),
            height: max(1, fitting.height)
        )
        let container = NSView(frame: NSRect(origin: .zero, size: initialSize))
        container.configureKajiHost()
        content.frame = container.bounds
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)

        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
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

        contentView = container
        // Size to fit the SwiftUI content.
        if fitting.width > 0 {
            setContentSize(fitting)
        }

        setFixedContentSize(initialSize)
    }

    // Borderless windows can't become key by default; allow it so SwiftUI
    // interaction works without forcing app activation.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setFixedContentSize(_ size: NSSize) {
        minSize = size
        maxSize = size
        contentMinSize = size
        contentMaxSize = size
    }
}

// MARK: - PanelState
//
// The floating panel has three visual modes. They are owned by the controller
// (not the view) so SwiftUI sees a single root and we can swap it without
// rebuilding the panel.
//
//   - `.expanded` — fixed-size HUD. Drag body to place.
//   - `.snapped(edge)` — the panel moved within 14pt of a screen edge and
//     we animated it flush to the edge. Same content; just relocated.
//   - `.docked(edge)` — 240ms of stillness after a snap collapsed the panel
//     into a thin 36pt strip (one cell per visible provider: logo + 5h %).
//     Strip sits on the chosen edge. Click arrow → back to expanded.
enum PanelState {
    case expanded
    case snapped(DockEdge)
    case docked(DockEdge)

    var edge: DockEdge? {
        switch self {
        case .expanded:           return nil
        case .snapped(let e):     return e
        case .docked(let e):      return e
        }
    }
    var isDocked: Bool {
        if case .docked = self { return true } else { return false }
    }
}

// MARK: - FloatingPanelController
//
// Owns the panel lifecycle and persists shown/hidden state in UserDefaults.
@MainActor
final class FloatingPanelController {
    private var panel: DraggablePanel?
    private let store: QuotaStore
    private let prefs: Prefs
    private var cancellables = Set<AnyCancellable>()

    /// Number of providers the user has chosen to show. Drives dock tab length.
    private var shownCount: Int {
        store.providers.filter { prefs.isVisible($0.id) }.count
    }

    /// Snap + dock state. Drives the visual mode (regular HUD / flush to edge
    /// / 36pt strip) and the snap timer.
    private var state: PanelState = .expanded

    /// Frame the panel occupied when last in `.expanded`. The dock round-trip
    /// (collapse → expand) restores the user back to where they were.
    private var savedExpandedFrame: NSRect?

    /// Fires 240ms after a snap completes; if the panel is still snapped at
    /// fire-time, it transitions into `.docked(edge)`. Reset on every move.
    private var snapTimer: Timer?

    /// Set during `show()` if `prefs.dockEdge != nil` so the next batch of
    /// plumbing (snap observer installed below) can dock the panel without
    /// making the user drag it on first launch.
    private var pendingStartupDock: DockEdge?

    /// didMoveNotification observer — drives the snap → dock state machine.
    private var moveObserver: NSObjectProtocol?
    private var suppressMoveHandling = false
    private var dockReclampTimer: Timer?

    private static let sideTabWidth: CGFloat = 68
    private static let topTabHeight: CGFloat = 66
    private static let dockCellLength: CGFloat = 42
    private static let dockPadLength: CGFloat = 24
    private static let snapThreshold: CGFloat = 14
    private static let snapAnimationDuration: TimeInterval = 0.18
    private static let dockDelay: TimeInterval = 0.24
    private static let dockAnimationDuration: TimeInterval = 0.22

    init(store: QuotaStore, prefs: Prefs) {
        self.store = store
        self.prefs = prefs
        store.$providers
            .sink { [weak self] _ in self?.refreshCurrentMode() }
            .store(in: &cancellables)
        prefs.$visibleProviders
            .sink { [weak self] _ in self?.refreshCurrentMode() }
            .store(in: &cancellables)
        prefs.$panelSize
            .sink { [weak self] _ in self?.refreshCurrentMode() }
            .store(in: &cancellables)
        // prefs.dockEdge is persisted via its own didSet; no controller-side
        // hook needed today, but we keep a sink registered for future
        // dock-edge side effects (analytics, menu rebuild) without touching
        // Prefs again.
        prefs.$dockEdge
            .sink { _ in }
            .store(in: &cancellables)
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    /// Restore the last shown/hidden state on launch. If the user was docked
    /// (prefs.dockEdge != nil), show() in the regular frame then defer the
    /// dock transition to the snap listener installed below.
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
            let root = GaugeRowView(store: store, prefs: prefs, panelSize: prefs.panelSize)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            let hosting = NSHostingView(rootView: root)
            hosting.configureKajiHost(cornerRadius: 14)
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            // Track the panel's content size on resize (width + height), so
            // the SwiftUI view reflows instead of staying anchored top-left.
            hosting.autoresizingMask = [.width, .height]
            let p = DraggablePanel(content: hosting)
            // Place near the top-right of the main screen on first show.
            if let screen = NSScreen.main {
                let v = screen.visibleFrame
                let size = p.frame.size
                p.setFrameOrigin(NSPoint(x: v.maxX - size.width - 24,
                                         y: v.maxY - size.height - 24))
            }
            panel = p
            installMoveObserver(on: p)
            // If the user was docked at quit time, mark it so the snap
            // observer (installed next batch) can dock straight from launch.
            pendingStartupDock = prefs.dockEdge
        }
        panel?.orderFrontRegardless()
        refreshCurrentMode()
        // Defer startup-dock to the next runloop tick so the panel's content
        // view is fully wired up before we swap in the dock strip.
        if let edge = pendingStartupDock {
            pendingStartupDock = nil
            DispatchQueue.main.async { [weak self] in
                self?.enterDockedMode(edge: edge, animated: false)
            }
        }
        UserDefaults.standard.set(true, forKey: Config.kPanelVisible)
    }

    func hide() {
        // Stop the snap → dock state machine so the panel can't auto-dock
        // while hidden.
        snapTimer?.invalidate()
        snapTimer = nil
        dockReclampTimer?.invalidate()
        dockReclampTimer = nil
        if let obs = moveObserver {
            NotificationCenter.default.removeObserver(obs)
            moveObserver = nil
        }
        panel?.orderOut(nil)
        // Hiding always clears the dock memory — there's no "hidden but
        // docked" semantic, the next show starts fresh from prefs.dockEdge.
        prefs.dockEdge = nil
        state = .expanded
        savedExpandedFrame = nil
        UserDefaults.standard.set(false, forKey: Config.kPanelVisible)
    }

    private func refreshCurrentMode() {
        guard let panel else { return }
        switch state {
        case .expanded, .snapped:
            swapContentToGaugeRow()
            let target = frameKeepingTopRight(panel.frame, size: prefs.panelSize.frameSize)
            panel.setFixedContentSize(target.size)
            setPanelFrame(target, animated: false)
        case .docked(let edge):
            swapContentToDockStrip(for: edge)
            let target = makeDockFrame(for: edge, base: panel.frame)
            panel.setFixedContentSize(target.size)
            setPanelFrame(target, animated: false)
        }
    }

    // MARK: - Snap + dock state machine
    //
    // Watch NSWindow.didMoveNotification and decide what to do:
    //   - panel near a screen edge  → snap flush to that edge, start 240ms
    //     timer to commit a dock.
    //   - panel moved away from edge → if we were snapped/docked, expand
    //     back to the saved expanded frame.
    //   - panel already docked      → any move = expand (user grabbed the
    //     strip to undock).

    private func installMoveObserver(on panel: DraggablePanel) {
        // Tear down a prior observer in case show() is called twice without
        // a hide() (defensive — the typical path goes through hide() first).
        if let obs = moveObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            // Bounce onto MainActor — the observer fires on the main queue
            // already, but the controller is @MainActor and the closure is
            // not, so a Task hop keeps Swift's actor isolation happy.
            Task { @MainActor in self?.handlePanelMoved() }
        }
    }

    private enum EdgeDetection { case far; case near(DockEdge) }

    private func detectNearestEdge(panel: NSPanel) -> EdgeDetection {
        guard let screen = panel.screen ?? NSScreen.main else { return .far }
        let v = screen.visibleFrame
        let f = panel.frame
        let dLeft = f.minX - v.minX
        let dRight = v.maxX - f.maxX
        let dTop = v.maxY - f.maxY
        let dBottom = f.minY - v.minY
        // We pick the SMALLEST non-negative distance (any negative means
        // the panel is past the visible frame; treat as already at edge).
        let ds = [dLeft, dRight, dTop, dBottom]
        let minD = ds.min() ?? .greatestFiniteMagnitude
        guard minD < Self.snapThreshold else { return .far }
        let edges: [DockEdge] = [.left, .right, .top, .bottom]
        let edge = edges[ds.firstIndex(of: minD) ?? 0]
        return .near(edge)
    }

    private func handlePanelMoved() {
        guard !suppressMoveHandling else { return }
        guard let panel else { return }
        let detection = detectNearestEdge(panel: panel)
        switch detection {
        case .far:
            // Dragged away from the edge. Snap + dock collapse back to HUD.
            switch state {
            case .expanded:
                snapTimer?.invalidate(); snapTimer = nil
            case .snapped:
                expandFromDock(animated: true)
            case .docked(let edge):
                scheduleDockReclamp(edge)
            }
        case .near(let edge):
            switch state {
            case .expanded:
                // First time near an edge — remember the frame so we can
                // restore on expand, then snap + start the dock timer.
                savedExpandedFrame = panel.frame
                state = .snapped(edge)
                animateSnap(to: edge, panel: panel)
                scheduleDockTimer(for: edge)
            case .snapped(let prev):
                if prev != edge {
                    // Switched edges mid-snap — re-snap, reset timer.
                    state = .snapped(edge)
                    animateSnap(to: edge, panel: panel)
                    scheduleDockTimer(for: edge)
                } else {
                    // Same edge, just fidgeting — keep the snap, reset the
                    // dock timer so 240ms of stillness commits the dock.
                    scheduleDockTimer(for: edge)
                }
            case .docked(let edge):
                scheduleDockReclamp(edge)
            }
        }
    }

    // MARK: - Snap animation

    /// Animate the panel flush against the given screen edge. Y origin is
    /// preserved on left/right (only X moves); X origin is preserved on
    /// top/bottom (only Y moves). The user keeps their dragged position
    /// along the long axis.
    private func animateSnap(to edge: DockEdge, panel: NSPanel) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        let f = panel.frame
        let target: NSRect
        switch edge {
        case .left:   target = NSRect(x: v.minX,           y: f.minY, width: f.width, height: f.height)
        case .right:  target = NSRect(x: v.maxX - f.width, y: f.minY, width: f.width, height: f.height)
        case .top:    target = NSRect(x: f.minX, y: v.maxY - f.height, width: f.width, height: f.height)
        case .bottom: target = NSRect(x: f.minX, y: v.minY,           width: f.width, height: f.height)
        }
        setPanelFrame(target, animated: true, duration: Self.snapAnimationDuration)
    }

    private func scheduleDockTimer(for edge: DockEdge) {
        snapTimer?.invalidate()
        snapTimer = Timer.scheduledTimer(withTimeInterval: Self.dockDelay,
                                         repeats: false) { [weak self] _ in
            Task { @MainActor in self?.commitDockIfSnapped(edge: edge) }
        }
    }

    private func commitDockIfSnapped(edge: DockEdge) {
        guard case .snapped(let e) = state, e == edge else { return }
        enterDockedMode(edge: edge, animated: true)
    }

    // MARK: - Dock mode

    /// Transition the panel into `.docked(edge)` — collapse to 36pt strip,
    /// swap the SwiftUI root to DockStripView, and persist the edge. Called
    /// by the snap timer (animated) and at launch when restoring dock.
    private func enterDockedMode(edge: DockEdge, animated: Bool) {
        guard let panel else { return }
        snapTimer?.invalidate(); snapTimer = nil
        if savedExpandedFrame == nil {
            savedExpandedFrame = panel.frame
        }
        state = .docked(edge)
        prefs.dockEdge = edge
        panel.isMovableByWindowBackground = true
        swapContentToDockStrip(for: edge)
        let target = makeDockFrame(for: edge, base: panel.frame)
        panel.setFixedContentSize(target.size)
        setPanelFrame(target, animated: animated, duration: Self.dockAnimationDuration)
    }

    private func scheduleDockReclamp(_ edge: DockEdge) {
        dockReclampTimer?.invalidate()
        dockReclampTimer = Timer.scheduledTimer(withTimeInterval: 0.16,
                                                repeats: false) { [weak self] _ in
            Task { @MainActor in self?.reclampDockedTab(edge) }
        }
    }

    private func reclampDockedTab(_ edge: DockEdge) {
        guard let panel else { return }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            scheduleDockReclamp(edge)
            return
        }
        let target = makeDockFrame(for: edge, base: panel.frame)
        panel.setFixedContentSize(target.size)
        setPanelFrame(target, animated: true, duration: 0.12)
    }

    /// Restore the panel to `.expanded` at the saved frame. The saved frame
    /// is cleared so the NEXT dock round-trip captures the new position.
    private func expandFromDock(animated: Bool) {
        guard let panel else { return }
        snapTimer?.invalidate(); snapTimer = nil
        dockReclampTimer?.invalidate(); dockReclampTimer = nil
        let edge = state.edge
        // Startup-dock path may lack a saved HUD frame.
        let base = savedExpandedFrame ?? fallbackExpandedFrame(from: panel.frame, edge: edge)
        let target = clampExpandedFrame(NSRect(origin: base.origin, size: prefs.panelSize.frameSize))
        state = .expanded
        prefs.dockEdge = nil
        panel.isMovableByWindowBackground = true
        swapContentToGaugeRow()
        panel.setFixedContentSize(target.size)
        savedExpandedFrame = nil
        setPanelFrame(target, animated: animated, duration: Self.dockAnimationDuration)
    }

    /// Frame a docked panel should occupy: fully visible, flush to edge.
    private func makeDockFrame(for edge: DockEdge, base: NSRect) -> NSRect {
        guard let screen = panel?.screen ?? NSScreen.main else { return base }
        let v = screen.visibleFrame
        let count = max(1, shownCount)
        let long = max(132, CGFloat(count) * Self.dockCellLength + Self.dockPadLength)
        switch edge {
        case .left:
            let h = min(long, v.height - 16)
            let y = clamp(base.midY - h / 2, v.minY + 8, v.maxY - h - 8)
            return NSRect(x: v.minX, y: y, width: Self.sideTabWidth, height: h)
        case .right:
            let h = min(long, v.height - 16)
            let y = clamp(base.midY - h / 2, v.minY + 8, v.maxY - h - 8)
            return NSRect(x: v.maxX - Self.sideTabWidth, y: y, width: Self.sideTabWidth, height: h)
        case .top:
            let w = min(long, v.width - 16)
            let x = clamp(base.midX - w / 2, v.minX + 8, v.maxX - w - 8)
            return NSRect(x: x, y: v.maxY - Self.topTabHeight, width: w, height: Self.topTabHeight)
        case .bottom:
            let w = min(long, v.width - 16)
            let x = clamp(base.midX - w / 2, v.minX + 8, v.maxX - w - 8)
            return NSRect(x: x, y: v.minY, width: w, height: Self.topTabHeight)
        }
    }

    private func fallbackExpandedFrame(from strip: NSRect, edge: DockEdge?) -> NSRect {
        guard let screen = panel?.screen ?? NSScreen.main else { return strip }
        let v = screen.visibleFrame
        let size = prefs.panelSize.frameSize
        let margin: CGFloat = 8
        let x: CGFloat
        let y: CGFloat
        switch edge {
        case .left:
            x = v.minX + margin
            y = clamp(strip.midY - size.height / 2, v.minY + margin, v.maxY - size.height - margin)
        case .right:
            x = v.maxX - size.width - margin
            y = clamp(strip.midY - size.height / 2, v.minY + margin, v.maxY - size.height - margin)
        case .top:
            x = clamp(strip.midX - size.width / 2, v.minX + margin, v.maxX - size.width - margin)
            y = v.maxY - size.height - margin
        case .bottom:
            x = clamp(strip.midX - size.width / 2, v.minX + margin, v.maxX - size.width - margin)
            y = v.minY + margin
        case .none:
            x = clamp(strip.minX, v.minX + margin, v.maxX - size.width - margin)
            y = clamp(strip.minY, v.minY + margin, v.maxY - size.height - margin)
        }
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func clampExpandedFrame(_ frame: NSRect) -> NSRect {
        guard let screen = panel?.screen ?? NSScreen.main else { return frame }
        let v = screen.visibleFrame
        let margin: CGFloat = 8
        let x = clamp(frame.minX, v.minX + margin, v.maxX - frame.width - margin)
        let y = clamp(frame.minY, v.minY + margin, v.maxY - frame.height - margin)
        return NSRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    private func frameKeepingTopRight(_ frame: NSRect, size: CGSize) -> NSRect {
        let origin = NSPoint(x: frame.maxX - size.width, y: frame.maxY - size.height)
        return clampExpandedFrame(NSRect(origin: origin, size: size))
    }

    private func setPanelFrame(_ frame: NSRect, animated: Bool, duration: TimeInterval = 0) {
        guard let panel else { return }
        suppressMoveHandling = true
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in self?.suppressMoveHandling = false }
            }
        } else {
            panel.setFrame(frame, display: true)
            suppressMoveHandling = false
        }
    }

    private func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), high)
    }

    // MARK: - Content swap (HUD ↔ dock strip)
    //
    // We rebuild the SwiftUI hosting view because the SwiftUI root differs.

    private func swapContentToDockStrip(for edge: DockEdge) {
        guard let panel, let host = panel.contentView else { return }
        host.subviews.forEach { $0.removeFromSuperview() }
        let root = DockStripView(store: store, prefs: prefs, edge: edge) { [weak self] in
            Task { @MainActor in self?.expandFromDock(animated: true) }
        }
        let hosting = NSHostingView(rootView: root)
        hosting.configureKajiHost(cornerRadius: 14)
        hosting.frame = host.bounds
        hosting.autoresizingMask = [.width, .height]
        host.addSubview(hosting)
    }

    private func swapContentToGaugeRow() {
        guard let panel, let host = panel.contentView else { return }
        host.subviews.forEach { $0.removeFromSuperview() }
        let root = GaugeRowView(store: store, prefs: prefs, panelSize: prefs.panelSize)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        let hosting = NSHostingView(rootView: root)
        hosting.configureKajiHost(cornerRadius: 14)
        hosting.frame = host.bounds
        hosting.autoresizingMask = [.width, .height]
        host.addSubview(hosting)
    }
}
