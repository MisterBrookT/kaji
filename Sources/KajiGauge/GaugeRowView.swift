import SwiftUI

// MARK: - GaugeRowView
//
// A horizontal row of ring gauges, one per VISIBLE provider. Shared by both
// surfaces (the menubar popover and the floating panel) so they always render
// the same content from the same store. The view sizes to its content — no
// fixed width — so it adapts to N rings.
//
// The popover passes `controls` (a settings footer: provider toggles, language,
// floating-panel toggle, quit). The desktop panel passes nil — gauges only.
struct GaugeRowView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var prefs: Prefs

    var controls: Controls? = nil

    /// When true the view expands to fill its container (used by the resizable
    /// floating HUD — rings scale up with the panel width). Popover leaves
    /// this false so the view still hugs its content and the popover stays
    /// tight around its rings.
    var expandToFill: Bool = false

    /// Minimum / maximum ring diameter when scaling with the panel. Keeps the
    /// gauge readable at small widths and prevents over-stretch at large ones.
    private let minRing: CGFloat = 64
    private let maxRing: CGFloat = 160
    /// Default ring size when the view is hugging its content (popover, or a
    /// panel that's at its natural fitting size).
    private let defaultRing: CGFloat = 84

    struct Controls {
        let panelVisible: Bool
        let onTogglePanel: () -> Void
        let onQuit: () -> Void
    }

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    // All providers that have data (for the toggle pills), and the subset the
    // user has chosen to show (for the rings).
    private var available: [ProviderView] { store.providers }
    private var shown: [ProviderView] {
        store.providers.filter { prefs.isVisible($0.id) }
    }

    /// Pick a ring diameter from BOTH width and height so the gauge never
    /// overflows either axis. When the panel is tall+narrow we wrap to a
    /// vertical stack; the ring then has the full row height to grow into.
    /// - Parameter isTall: true → LazyVStack mode (one ring per row).
    private func ringSize(width w: CGFloat, height h: CGFloat,
                          n: Int, isTall: Bool) -> CGFloat {
        guard n > 0 else { return minRing }
        let rowSpacing: CGFloat = isTall ? 10 : 16
        let padding: CGFloat = 28
        // Chrome above (header) + below (label) the ring within each cell.
        // 22 (header row including dot) + 38 (3-line label VStack at 12/10/10)
        // + 12 (top→rings spacing) = 72. Real chrome in production = ~78 with
        // 14pt top padding. We keep the under-estimate so 3-ring vertical
        // mode still grows the ring at the panel's true min height.
        let verticalChrome: CGFloat = 22 + 38 + 12
        let perRingW = max(0, (w - padding - rowSpacing * CGFloat(n - 1)) / CGFloat(n))
        let rowsHeight = max(0, h - verticalChrome)
        let perRowH = isTall
            ? (rowsHeight - rowSpacing * CGFloat(n - 1)) / CGFloat(n)
            : rowsHeight
        let maxFromHeight = max(0, perRowH - 38 - 7)   // label + VStack spacing
        let raw = min(perRingW, maxFromHeight)
        // Floor: when the panel is too narrow for n rings at minRing, fall
        // back to whatever fits. 36pt keeps the label captions legible (the
        // 3-line label VStack needs ~38pt to render at full size).
        let effectiveMin = max(36, min(minRing,
                                       (w - padding) / CGFloat(n) - rowSpacing))
        return min(max(raw, effectiveMin), maxRing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if shown.isEmpty {
                emptyState
            } else {
                ringsRow
            }

            if let controls { footer(controls) }
        }
        .padding(14)
        .background(background)
        .modifier(FitOrFill(expand: expandToFill))
    }

    @ViewBuilder
    private var ringsRow: some View {
        if expandToFill {
            // GeometryReader drives both axis. Pick a layout that matches the
            // panel's actual aspect: wide/short → HStack row; tall/narrow →
            // LazyVStack (one ring per row) so label text never gets clipped.
            GeometryReader { geo in
                let n = max(1, shown.count)
                // Go tall when the row would overflow horizontally. 130 ≈
                // minRing (64) + padding per slot + label width; if total
                // slots > available width, wrap to one-per-row.
                let slotNeeded: CGFloat = 130
                let totalNeeded = slotNeeded * CGFloat(n) + 16 * CGFloat(n - 1) + 28
                let isTall = n > 1 && geo.size.width < totalNeeded
                let size = ringSize(width: geo.size.width,
                                    height: geo.size.height,
                                    n: n, isTall: isTall)
                Group {
                    if isTall {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(shown) { provider in
                                RingGauge(provider: provider, lang: prefs.language,
                                          ringSize: size)
                            }
                        }
                        .scrollDisabled(true)
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(shown) { provider in
                                RingGauge(provider: provider, lang: prefs.language,
                                          ringSize: size)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                ForEach(shown) { provider in
                    RingGauge(provider: provider, lang: prefs.language,
                              ringSize: defaultRing)
                }
            }
        }
    }

    /// `.fixedSize()` for the popover (hugs content) → removed when the panel
    /// mode is on (fills the panel, rings scale with width).
    private struct FitOrFill: ViewModifier {
        let expand: Bool
        func body(content: Content) -> some View {
            if expand { content } else { content.fixedSize() }
        }
    }

    // MARK: Footer (settings — popover only)

    private func footer(_ c: Controls) -> some View {
        VStack(spacing: 9) {
            Rectangle().fill(t.track).frame(height: 1).opacity(0.7)

            // Settings row: provider toggles on the left, language on the right.
            HStack(spacing: 7) {
                ForEach(available) { p in
                    pill(p.displayName, on: prefs.isVisible(p.id)) {
                        prefs.toggleProvider(p.id)
                    }
                }
                Spacer(minLength: 8)
                langToggle
            }

            // Menu-bar style row: how the menu-bar glyph reads (mono / color).
            HStack(spacing: 7) {
                Text(L10n.t(.menubar, prefs.language))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(t.mute)
                Spacer(minLength: 8)
                segment(L10n.t(.styleMono, prefs.language), on: prefs.menubarStyle == .mono) {
                    prefs.menubarStyle = .mono
                }
                segment(L10n.t(.styleColor, prefs.language), on: prefs.menubarStyle == .color) {
                    prefs.menubarStyle = .color
                }
            }

            // Actions row: floating-panel toggle on the left, quit on the right.
            HStack(spacing: 12) {
                Button(action: c.onTogglePanel) {
                    HStack(spacing: 5) {
                        Image(systemName: c.panelVisible
                              ? "macwindow" : "macwindow.badge.plus")
                        Text(L10n.t(c.panelVisible ? .hidePanel : .floatPanel, prefs.language))
                    }
                }
                Spacer(minLength: 10)
                Button(action: c.onQuit) { Text(L10n.t(.quit, prefs.language)) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(t.mute)
        }
    }

    // A small toggle chip: filled (warm) when on, outlined when off.
    private func pill(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(on ? t.bg : t.mute)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(on ? t.gold : Color.clear)
                        .overlay(Capsule().stroke(on ? Color.clear : t.track, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    // One segment of a small two-option control (filled when selected).
    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(on ? t.bg : t.mute)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(on ? t.gold : Color.clear)
                        .overlay(Capsule().stroke(on ? Color.clear : t.track, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    // EN | 中文 segmented toggle.
    private var langToggle: some View {
        Button(action: { prefs.language = prefs.language.toggled }) {
            Text(prefs.language.label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(t.cream)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().stroke(t.track, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Chrome

    private var background: some View {
        LinearGradient(
            colors: [t.bgTop, t.bg],
            startPoint: .topTrailing, endPoint: .bottomLeading
        )
    }

    // Header chrome: tighter on the right so the legend recedes instead of
    // claiming equal weight with the title. Size scales with visible-ring
    // count (more rings = same; fewer rings = smaller + closer) and shrinks
    // further under tight widths via minimumScaleFactor. The legend is the
    // elastic item: layoutPriority(0) makes it absorb all leftover pressure,
    // and minimumScaleFactor lets it shrink down before any text truncates.
    private var header: some View {
        let isError = store.lastError != nil && !store.providers.isEmpty
        let legend = isError
            ? L10n.t(.stale, prefs.language)
            : "5h \u{00B7} \(L10n.t(.week, prefs.language))"
        let legendColor: Color = isError ? t.amber.opacity(0.9) : t.ash
        // Scale: 0/1 ring → 0.78; 2 rings → 0.90; 3+ → 1.0. Recedes when sparse.
        let density = max(1, shown.count)
        let scale: CGFloat = density >= 3 ? 1.0 : (density == 2 ? 0.90 : 0.78)
        return HStack(spacing: 6) {
            // Theme-aware accent dot: persimmon by day (Sun), ember gold by
            // night (Ember) — matches the rings instead of staying orange.
            Circle().fill(t.gold).frame(width: 7, height: 7)
            Text("Kaji")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(t.cream)
                .layoutPriority(2)
            Text("Gauge")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(t.mute)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text(legend)
                .font(.system(size: 10))
                .foregroundColor(legendColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(0)
        }
        .scaleEffect(scale, anchor: .trailing)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("\u{2014}")
                .font(.system(size: 28))
                .foregroundColor(t.ash)
            Text(store.lastError ?? L10n.t(.waiting, prefs.language))
                .font(.system(size: 11))
                .foregroundColor(t.mute)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 180, minHeight: 96)
    }
}
