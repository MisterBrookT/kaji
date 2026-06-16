import AppKit
import SwiftUI
import Combine

// MARK: - DraggablePanel
//
// An always-on-top, borderless HUD panel that the user can drag anywhere on
// the desktop. .nonactivatingPanel so clicking it never steals focus from the
// frontmost app; .floating level so it stays above normal windows.
//
// Borderless NSPanels default to a ~3pt edge hit zone for resizing — the user
// has to park the cursor right on the edge. We widen this to 10pt by
// installing eight invisible `ResizeHandle` views (one per edge + corner)
// that own the resize gesture + cursor and sit ABOVE the SwiftUI host so they
// get first crack at mouse events.
final class DraggablePanel: NSPanel {
    /// Edge width for the resize hit zone. 16pt ≈ a comfortable grab target
    /// + room for a visible 1.5pt track line + L-shape corner indicator. The
    /// handles are still mostly transparent — only the inner-edge track line
    /// is drawn, so the wider hit zone doesn't leak into the content.
    private static let edgeWidth: CGFloat = 16

    init(content: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            // No .hudWindow — its material forces a dark vibrancy that fights the
            // light "Kaji Sun" theme. We paint our own warm gradient instead.
            // .resizable so we can also drag the edges/corners via the
            // ResizeHandle subviews; we paint our own shadow (no native chrome).
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
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

        // Initial bounds use the LARGEST visible-ring case (3-ring vertical
        // wrap, 200x340). The controller narrows the lower bound as visible
        // rings change, via `updateMinSize(forVisibleRings:)`. The upper bound
        // stays at the original 720x360 — that's still where rings stop
        // scaling.
        let maxW: CGFloat = 720
        let maxH: CGFloat = 360
        let defaultMin = DraggablePanel.minSize(forVisibleRings: 3)
        minSize = defaultMin
        maxSize = NSSize(width: maxW, height: maxH)
        contentMinSize = defaultMin
        contentMaxSize = NSSize(width: maxW, height: maxH)

        // Install the eight resize handles. The hosting view is also added so
        // the SwiftUI content still draws (these handles are transparent).
        if let host = contentView {
            host.wantsLayer = true
            host.layer?.backgroundColor = .clear
            installResizeHandles(on: host)
        }
    }

    /// Pick a min size for the panel given how many provider rings the user
    /// currently has visible. 1-2 rings sit in an HStack (need W), 3+ wraps
    /// to a LazyVStack (need H). We never go below the natural chrome — below
    /// that the SwiftUI content starts to clip and the legend truncates.
    static func minSize(forVisibleRings n: Int) -> NSSize {
        if n <= 2 {
            // 1 ring ≈ 84 + label; 2 rings HStack need ~280 to fit 84+84+16+chrome.
            // Height = ring + label + chrome ≈ 160; below that the panel feels
            // squeezed and the popover font starts to shrink.
            let w: CGFloat = n == 1 ? 200 : 280
            return NSSize(width: w, height: 160)
        }
        // 3 rings vertical: ring(36) + label(38) + spacing(7) per cell, 3 cells
        // + 2 inter-cell gaps + top chrome (header+padding ≈ 54) + bottom 14.
        // Round up to 340 so the label VStack never gets squeezed.
        return NSSize(width: 200, height: 340)
    }

    /// Re-apply the lower bound when the user's visible-ring count changes.
    /// Capped to the current frame so we don't SHRINK a live panel the user
    /// is already looking at — only expand the bound so the user can shrink
    /// back down to the new minimum.
    func updateMinSize(forVisibleRings n: Int) {
        let target = DraggablePanel.minSize(forVisibleRings: n)
        // If the panel is already larger than the new min, keep the panel
        // size and just relax the lower bound to the new min.
        minSize = NSSize(width: min(target.width, frame.width),
                         height: min(target.height, frame.height))
        contentMinSize = NSSize(width: min(target.width, frame.width),
                                height: min(target.height, frame.height))
    }

    // Borderless windows can't become key by default; allow it so SwiftUI
    // interaction works without forcing app activation.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func installResizeHandles(on host: NSView) {
        let w = DraggablePanel.edgeWidth
        // Corners first (drawn last so they sit on top of the edge handles
        // and own the cursor at the intersection). Each corner is square of
        // side `w`; edges are thin strips.
        let corners: [(ResizeHandle.Kind, CGRect)] = [
            (.topLeft,     CGRect(x: 0, y: host.bounds.maxY - w,
                                  width: w, height: w)),
            (.topRight,    CGRect(x: host.bounds.maxX - w, y: host.bounds.maxY - w,
                                  width: w, height: w)),
            (.bottomLeft,  CGRect(x: 0, y: 0, width: w, height: w)),
            (.bottomRight, CGRect(x: host.bounds.maxX - w, y: 0,
                                  width: w, height: w)),
        ]
        let edges: [(ResizeHandle.Kind, CGRect)] = [
            (.top,    CGRect(x: w, y: host.bounds.maxY - w,
                             width: max(0, host.bounds.width - 2 * w), height: w)),
            (.bottom, CGRect(x: w, y: 0,
                             width: max(0, host.bounds.width - 2 * w), height: w)),
            (.left,   CGRect(x: 0, y: w, width: w,
                             height: max(0, host.bounds.height - 2 * w))),
            (.right,  CGRect(x: host.bounds.maxX - w, y: w, width: w,
                             height: max(0, host.bounds.height - 2 * w))),
        ]
        for (kind, rect) in edges + corners {
            let handle = ResizeHandle(kind: kind, panel: self)
            handle.frame = rect
            handle.autoresizingMask = autoresizeMask(for: kind, in: host)
            host.addSubview(handle)
        }
    }

    private func autoresizeMask(for kind: ResizeHandle.Kind,
                                in host: NSView) -> NSView.AutoresizingMask {
        // Edges/corners move with their adjacent sides when the panel resizes.
        switch kind {
        case .topLeft:     return [.maxXMargin, .minYMargin]
        case .topRight:    return [.minXMargin, .minYMargin]
        case .bottomLeft:  return [.maxXMargin, .maxYMargin]
        case .bottomRight: return [.minXMargin, .maxYMargin]
        case .top:         return [.width, .minYMargin]
        case .bottom:      return [.width, .maxYMargin]
        case .left:        return [.maxXMargin, .height]
        case .right:       return [.minXMargin, .height]
        }
    }

    /// Tear down + reinstall all eight ResizeHandle subviews. Called by the
    /// controller after swapping the SwiftUI hosting view (dock ↔ HUD) so
    /// the handles always sit on top of the new content with the right z-order.
    func reinstallResizeHandles() {
        guard let host = contentView else { return }
        host.subviews
            .compactMap { $0 as? ResizeHandle }
            .forEach { $0.removeFromSuperview() }
        installResizeHandles(on: host)
    }
}

// MARK: - ResizeHandle
//
// An NSView that owns one of the eight panel edges/corners. The hit zone is
// 16pt wide. Cursor changes on enter so the user reads the affordance from
// the cursor shape alone — we deliberately paint NOTHING here, so the chrome
// stays out of the way of the SwiftUI content. Earlier iterations drew a 1.5pt
// track + a gold hover line; both were dropped after user feedback said they
// felt more like glitches than affordances.
final class ResizeHandle: NSView {
    enum Kind {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
    }
    private let kind: Kind
    private weak var panel: NSPanel?
    private var startOrigin: NSPoint = .zero
    private var startSize: NSSize = .zero
    private var startFrame: NSRect = .zero

    init(kind: Kind, panel: NSPanel) {
        self.kind = kind
        self.panel = panel
        super.init(frame: .zero)
        // Transparent — cursor change is the only affordance.
        wantsLayer = true
        layer?.backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Block any hits in our rect so the SwiftUI host doesn't steal them.
        // We still let the panel's own isMovableByWindowBackground handle the
        // background drag (we only sit on the edges).
        bounds.contains(point) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor())
    }

    override func draw(_ dirtyRect: NSRect) {
        // Intentional no-op — see file header.
    }

    override func mouseDown(with event: NSEvent) {
        guard let panel = panel else { return }
        startFrame = panel.frame
        startOrigin = startFrame.origin
        startSize = startFrame.size
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let panel = panel else { return }
        // Location in window coords; convert to delta in screen coords (Y up).
        let loc = event.locationInWindow
        let start = window?.mouseLocationOutsideOfEventStream ?? loc
        let dx = loc.x - start.x
        let dy = loc.y - start.y
        apply(dx: dx, dy: dy, to: panel)
    }

    private func apply(dx: CGFloat, dy: CGFloat, to panel: NSPanel) {
        var origin = startOrigin
        var size = startSize
        // NSPanel resize: edges/corners modify origin + size according to which
        // side the user grabbed. Y is screen-up here (dy > 0 = drag up).
        switch kind {
        case .topLeft:
            origin.x += dx; origin.y += dy
            size.width -= dx; size.height += dy
        case .topRight:
            origin.y += dy
            size.width += dx; size.height += dy
        case .bottomLeft:
            origin.x += dx
            size.width -= dx; size.height -= dy
        case .bottomRight:
            size.width += dx; size.height -= dy
        case .top:
            origin.y += dy
            size.height += dy
        case .bottom:
            size.height -= dy
        case .left:
            origin.x += dx
            size.width -= dx
        case .right:
            size.width += dx
        }
        // Clamp to the same bounds the panel's minSize / maxSize enforce.
        let minS = panel.minSize, maxS = panel.maxSize
        size.width = min(max(size.width, minS.width),  maxS.width)
        size.height = min(max(size.height, minS.height), maxS.height)
        // Re-derive origin for the clamped size so the grabbed edge stays
        // anchored to the cursor (only the non-anchored corners move).
        switch kind {
        case .topLeft:
            origin.x = startOrigin.x + (startSize.width - size.width)
            origin.y = startOrigin.y + (startSize.height - size.height)
        case .topRight:
            origin.y = startOrigin.y + (startSize.height - size.height)
        case .bottomLeft:
            origin.x = startOrigin.x + (startSize.width - size.width)
        case .top:
            origin.y = startOrigin.y + (startSize.height - size.height)
        case .left:
            origin.x = startOrigin.x + (startSize.width - size.width)
        default: break
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func cursor() -> NSCursor {
        switch kind {
        case .topLeft, .bottomRight: return .crosshair
        case .topRight, .bottomLeft: return .crosshair
        case .top, .bottom:          return .resizeUpDown
        case .left, .right:          return .resizeLeftRight
        }
    }
}

// MARK: - PanelState
//
// The floating panel has three visual modes. They are owned by the controller
// (not the view) so SwiftUI sees a single root and we can swap it without
// rebuilding the panel.
//
//   - `.expanded` — the regular HUD: rings, labels, header. Drag from any
//     inner pixel; resize from the 8 invisible ResizeHandles on the border.
//   - `.snapped(edge)` — the panel moved within 14pt of a screen edge and
//     we animated it flush to the edge. Same content; just relocated.
//   - `.docked(edge)` — 240ms of stillness after a snap collapsed the panel
//     into a thin 36pt strip (one cell per visible provider: logo + 5h %).
//     Strip sits on the chosen edge. Hover or drag the strip → back to expanded.
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

    /// Number of providers the user has chosen to show. Drives the panel's
    /// min size — see `DraggablePanel.minSize(forVisibleRings:)`.
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

    /// Snap + dock constants. Kept on the controller so the behavior is
    /// self-contained; if these ever need user-tunable, lift to Prefs.
    private static let stripThickness: CGFloat = 36
    private static let snapThreshold: CGFloat = 14
    private static let snapAnimationDuration: TimeInterval = 0.18
    private static let dockDelay: TimeInterval = 0.24
    private static let dockAnimationDuration: TimeInterval = 0.22

    init(store: QuotaStore, prefs: Prefs) {
        self.store = store
        self.prefs = prefs
        // Re-apply the min size whenever the user's visible-ring set changes
        // (provider toggle in the popover/menu) OR the store reports new data
        // (a provider that was previously "no data" now has a row to show).
        // MainActor: all UI work; no need to hop.
        store.$providers
            .sink { [weak self] _ in self?.applyMinSize() }
            .store(in: &cancellables)
        prefs.$visibleProviders
            .sink { [weak self] _ in self?.applyMinSize() }
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
            // Resizable HUD: GaugeRowView runs in `expandToFill` mode so the
            // SwiftUI view tracks the panel's width and rings scale together.
            let root = GaugeRowView(store: store, prefs: prefs, expandToFill: true)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            let hosting = NSHostingView(rootView: root)
            hosting.layer?.cornerRadius = 14
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
        applyMinSize()  // covers the show-after-data-arrived case
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

    /// Push the current visible-ring count down to the panel as a min-size
    /// floor. No-op if the panel isn't shown yet (it'll fire on first show()).
    private func applyMinSize() {
        guard let panel else { return }
        panel.updateMinSize(forVisibleRings: shownCount)
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
        guard let panel else { return }
        let detection = detectNearestEdge(panel: panel)
        switch detection {
        case .far:
            // Dragged away from the edge. Snap + dock collapse back to HUD.
            switch state {
            case .expanded:
                snapTimer?.invalidate(); snapTimer = nil
            case .snapped, .docked:
                expandFromDock(animated: true)
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
            case .docked:
                // User grabbed the docked strip and dragged — pop back to
                // expanded immediately. The next edge detection re-arms.
                expandFromDock(animated: true)
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
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.snapAnimationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }
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
        state = .docked(edge)
        prefs.dockEdge = edge
        swapContentToDockStrip(for: edge)
        let target = makeDockFrame(for: edge, base: panel.frame)
        // Lock the panel to the strip thickness so the user can't drag it
        // wider from a docked handle. Expanded mode restores the proper min
        // in expandFromDock().
        panel.minSize = NSSize(width: Self.stripThickness, height: Self.stripThickness)
        panel.contentMinSize = panel.minSize
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.dockAnimationDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    /// Restore the panel to `.expanded` at the saved frame. The saved frame
    /// is cleared so the NEXT dock round-trip captures the new position.
    private func expandFromDock(animated: Bool) {
        guard let panel else { return }
        snapTimer?.invalidate(); snapTimer = nil
        // If we were never saved (e.g. direct dock from launch), fall back
        // to the current frame so the panel doesn't teleport to stale state.
        let target = savedExpandedFrame ?? panel.frame
        state = .expanded
        prefs.dockEdge = nil
        swapContentToGaugeRow()
        // Restore the proper min size for the user's current ring count.
        panel.updateMinSize(forVisibleRings: shownCount)
        savedExpandedFrame = nil
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.dockAnimationDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    /// Frame a docked panel should occupy: flush to the edge, with the
    /// strip thickness on the cross axis. Long axis (height for left/right,
    /// width for top/bottom) keeps the user's snap-time size.
    private func makeDockFrame(for edge: DockEdge, base: NSRect) -> NSRect {
        guard let screen = panel?.screen ?? NSScreen.main else { return base }
        let v = screen.visibleFrame
        let t = Self.stripThickness
        switch edge {
        case .left:   return NSRect(x: v.minX,           y: base.minY, width: t, height: base.height)
        case .right:  return NSRect(x: v.maxX - t,       y: base.minY, width: t, height: base.height)
        case .top:    return NSRect(x: base.minX, y: v.maxY - t,       width: base.width, height: t)
        case .bottom: return NSRect(x: base.minX, y: v.minY,           width: base.width, height: t)
        }
    }

    // MARK: - Content swap (HUD ↔ dock strip)
    //
    // We rebuild the SwiftUI hosting view because the SwiftUI root differs
    // (GaugeRowView vs DockStripView). The 8 ResizeHandle subviews stay —
    // we just re-stack them on top of the new host so hit-testing still
    // works on the edges.

    private func swapContentToDockStrip(for edge: DockEdge) {
        guard let panel, let host = panel.contentView else { return }
        // Remove the existing hosting view; keep the resize handles.
        host.subviews
            .filter { !($0 is ResizeHandle) }
            .forEach { $0.removeFromSuperview() }
        let root = DockStripView(store: store, prefs: prefs, edge: edge) { [weak self] in
            Task { @MainActor in self?.expandFromDock(animated: true) }
        }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = host.bounds
        hosting.autoresizingMask = [.width, .height]
        host.addSubview(hosting)
        // Bring resize handles to the front (z-order) so they win edge hits.
        panel.reinstallResizeHandles()
    }

    private func swapContentToGaugeRow() {
        guard let panel, let host = panel.contentView else { return }
        host.subviews
            .filter { !($0 is ResizeHandle) }
            .forEach { $0.removeFromSuperview() }
        let root = GaugeRowView(store: store, prefs: prefs, expandToFill: true)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        let hosting = NSHostingView(rootView: root)
        hosting.layer?.cornerRadius = 14
        hosting.frame = host.bounds
        hosting.autoresizingMask = [.width, .height]
        host.addSubview(hosting)
        panel.reinstallResizeHandles()
    }
}
