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

    var panelSize: PanelSize? = nil
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
        .modifier(PanelOrPopoverFrame(panelSize: panelSize, hasControls: controls != nil))
    }

    @ViewBuilder
    private var ringsRow: some View {
        if let panelSize {
            // Popover (has the settings footer): ALWAYS one horizontal row,
            // ring size computed to fill the width for N providers — S/M/L just
            // scales the whole row proportionally. The floating HUD keeps its
            // own resize-aware layout (panelRings).
            if controls != nil {
                popoverRings(panelSize)
            } else {
                panelRings(panelSize)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                ForEach(shown) { provider in
                    RingGauge(provider: provider, lang: prefs.language,
                              showRemaining: prefs.showRemaining,
                              ringSize: defaultRing)
                }
            }
        }
    }

    /// One horizontal row that always fits: ring diameter is derived from the
    /// (known, pinned) popover width and the provider count so N rings fill the
    /// row exactly — 3 fill it, 4 fill it — and S/M/L scale it as a unit. No
    /// GeometryReader (it would break the popover's vertical fitting pass).
    private func popoverRings(_ size: PanelSize) -> some View {
        let n = CGFloat(max(1, shown.count))
        let content = size.frameSize.width - 28          // outer padding (14 * 2)
        let spacing: CGFloat = n >= 4 ? 9 : 14
        let raw = (content - spacing * (n - 1)) / n
        // Floor keeps tiny counts readable; cap at the size's natural ring so a
        // single provider doesn't balloon.
        let ring = min(size.ringSize, max(40, raw))
        return HStack(alignment: .top, spacing: spacing) {
            ForEach(shown) { provider in
                RingGauge(provider: provider, lang: prefs.language,
                          showRemaining: prefs.showRemaining,
                          ringSize: ring)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func panelRings(_ size: PanelSize) -> some View {
        if size == .small {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(shown) { provider in
                    CompactRingRow(provider: provider,
                                   lang: prefs.language,
                                   showRemaining: prefs.showRemaining,
                                   ringSize: size.ringSize)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: size == .medium ? 14 : 18) {
                ForEach(shown) { provider in
                    RingGauge(provider: provider, lang: prefs.language,
                              showRemaining: prefs.showRemaining,
                              ringSize: size.ringSize)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private struct PanelOrPopoverFrame: ViewModifier {
        let panelSize: PanelSize?
        let hasControls: Bool
        func body(content: Content) -> some View {
            if let panelSize {
                if hasControls {
                    // Popover: width is pinned to S/M/L, but height grows
                    // to fit the settings footer. Floating HUD has no
                    // footer, so it's free to take the full frame.
                    content.frame(width: panelSize.frameSize.width,
                                  alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    content.frame(width: panelSize.frameSize.width,
                                  height: panelSize.frameSize.height,
                                  alignment: .topLeading)
                }
            } else {
                content.fixedSize()
            }
        }
    }

    // A wrapping row: lays children left-to-right, breaking to a new line when
    // the next child would overflow the proposed width. Used for the provider
    // toggle pills so a narrow popover wraps them (2x2, 3+2, …) instead of
    // crushing each pill into vertical text. macOS 13+ Layout protocol.
    private struct FlowLayout: Layout {
        var spacing: CGFloat = 7
        var lineSpacing: CGFloat = 7

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let maxW = proposal.width ?? .infinity
            var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
            for s in subviews {
                let sz = s.sizeThatFits(.unspecified)
                if x > 0 && x + sz.width > maxW {
                    widest = max(widest, x - spacing)
                    x = 0; y += lineH + lineSpacing; lineH = 0
                }
                x += sz.width + spacing
                lineH = max(lineH, sz.height)
            }
            widest = max(widest, x - spacing)
            let w = maxW.isFinite ? maxW : widest
            return CGSize(width: w, height: y + lineH)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let maxW = bounds.width
            var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
            for s in subviews {
                let sz = s.sizeThatFits(.unspecified)
                if x > 0 && x + sz.width > maxW {
                    x = 0; y += lineH + lineSpacing; lineH = 0
                }
                s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                        anchor: .topLeading, proposal: ProposedViewSize(sz))
                x += sz.width + spacing
                lineH = max(lineH, sz.height)
            }
        }
    }

    // MARK: Footer (settings — popover only)

    private func footer(_ c: Controls) -> some View {
        VStack(spacing: 9) {
            Rectangle().fill(t.track).frame(height: 1).opacity(0.7)

            // Settings row: provider toggles + language. A flow layout wraps to
            // the next line when the popover is too narrow for one row (small
            // size + 4-5 providers) — so pills never get crushed into vertical
            // text. Each pill keeps its natural width (lineLimit 1 + fixedSize).
            FlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(available) { p in
                    pill(p.displayName, on: prefs.isVisible(p.id)) {
                        prefs.toggleProvider(p.id)
                    }
                }
                langToggle
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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

            // Usage row: show 5h as USED vs REMAINING. Defaults to USED, which
            // matches the historical ring direction; REMAINING reads "0% means
            // full" with a reversed trim. The dock strip + menubar follow along.
            HStack(spacing: 7) {
                Text(L10n.t(.usage, prefs.language))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(t.mute)
                Spacer(minLength: 8)
                segment(L10n.t(.showUsed, prefs.language), on: !prefs.showRemaining) {
                    prefs.showRemaining = false
                }
                segment(L10n.t(.showRemaining, prefs.language), on: prefs.showRemaining) {
                    prefs.showRemaining = true
                }
            }

            HStack(spacing: 7) {
                Text(L10n.t(.panelSize, prefs.language))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(t.mute)
                Spacer(minLength: 8)
                segment(L10n.t(.sizeSmall, prefs.language), on: prefs.panelSize == .small) {
                    prefs.panelSize = .small
                }
                segment(L10n.t(.sizeMedium, prefs.language), on: prefs.panelSize == .medium) {
                    prefs.panelSize = .medium
                }
                segment(L10n.t(.sizeLarge, prefs.language), on: prefs.panelSize == .large) {
                    prefs.panelSize = .large
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
                .lineLimit(1)
                .fixedSize()
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
                .lineLimit(1)
                .fixedSize()
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
        // No working python3 → actionable onboarding. Any other failure (or a
        // first poll still in flight) reads as a neutral "waiting" rather than a
        // raw subprocess error string, which would look broken to end users.
        let message: String
        if store.lastError == Config.noPythonSentinel {
            message = L10n.t(.needPython, prefs.language)
        } else {
            message = L10n.t(.waiting, prefs.language)
        }
        return VStack(spacing: 6) {
            Text("\u{2014}")
                .font(.system(size: 28))
                .foregroundColor(t.ash)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(t.mute)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 180, minHeight: 96)
    }
}

// MARK: - CompactRingRow
//
// List-row layout used by the floating HUD when it's been stretched tall +
// narrow. Same product signature (concentric ring + logo + %), but the label
// moves to the RIGHT of the ring instead of below it. Pattern after iStat
// Menus / MonitorControl / Spotify compact card: [icon] + [text] horizontal,
// so the text column gets the full panel width and names never truncate to
// "Clau" / "Cod" / "Mini".
//
// Ring size stays fixed at 56pt here — the panel's vertical chrome math is
// irrelevant in this layout (no label below the ring), so passing a stable
// value keeps the geometry predictable regardless of how tall the user drags.
private struct CompactRingRow: View {
    let provider: ProviderView
    var lang: Lang = .en
    var showRemaining: Bool = false
    var ringSize: CGFloat = 56

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    // Same ring math as RingGauge, scaled by ringSize.
    private var baseLineWidth: CGFloat { ringSize * (10.0 / 84.0) }
    private var innerLineWidth: CGFloat { ringSize * (5.0 / 84.0) }
    private var innerInset: CGFloat    { ringSize * (13.0 / 84.0) }
    private var logoSize: CGFloat      { ringSize * (16.0 / 84.0) }
    private var percentFont: CGFloat   { ringSize * (22.0 / 84.0) }

    private var arcColor: Color { provider.isNearLimit ? t.amber : t.gold }
    private var weekColor: Color { provider.weekNearLimit ? t.amber : t.gold.opacity(0.55) }
    private var valueLineWidth: CGFloat {
        provider.isNearLimit ? baseLineWidth + (ringSize * (3.0 / 84.0)) : baseLineWidth
    }
    private var trimFraction: Double {
        showRemaining ? 1.0 - provider.usedFraction : provider.usedFraction
    }
    private var weekTrimFraction: Double {
        showRemaining ? 1.0 - provider.weekFraction : provider.weekFraction
    }
    private var percentText: String {
        guard let p = provider.fiveHourPercent else { return "\u{2014}" }
        let shown = showRemaining ? (100.0 - p) : p
        return "\(Int(shown.rounded()))"
    }
    private var numberColor: Color { provider.isNearLimit ? t.amber : t.cream }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Ring face on the left — same concentric ring + logo + % as
            // RingGauge, just sized for a 56pt slot in a vertical list.
            ZStack {
                Circle()
                    .stroke(t.track.opacity(0.5),
                            style: StrokeStyle(lineWidth: baseLineWidth, lineCap: .round))
                Circle()
                    .trim(from: 0, to: trimFraction)
                    .stroke(arcColor,
                            style: StrokeStyle(lineWidth: valueLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Circle()
                    .stroke(t.track.opacity(0.4),
                            style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .round))
                    .padding(innerInset)
                Circle()
                    .trim(from: 0, to: weekTrimFraction)
                    .stroke(weekColor,
                            style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(innerInset)

                VStack(spacing: 1) {
                    ProviderLogo(key: provider.id, color: arcColor, size: logoSize)
                    Text(percentText)
                        .font(.system(size: percentFont, weight: .semibold, design: .rounded))
                        .foregroundColor(numberColor)
                        .monospacedDigit()
                }
            }
            .frame(width: ringSize, height: ringSize)

            // Text column on the right — takes ALL remaining width via
            // maxWidth: .infinity, so the name "MiniMax" never truncates.
            textColumn
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textColumn: some View {
        let weekRaw = provider.weekPercent
        let weekDisplayed = weekRaw.map { showRemaining ? (100 - $0) : $0 }
        let week = weekDisplayed.map { "\(Int($0.rounded()))%" } ?? "\u{2014}"
        let fiveReset = ResetFormat.phrase(provider.resetDate, lang)
        let weekReset = ResetFormat.phrase(provider.weekResetDate, lang)
        return VStack(alignment: .leading, spacing: 4) {
            // Primary: provider name (semibold 13pt, cream).
            Text(provider.displayName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(t.cream)
                .lineLimit(1)
            // Secondary: 5h window — "5h" mute label + gold reset countdown.
            HStack(spacing: 4) {
                Text("5h")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(t.mute)
                Text(fiveReset)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(t.gold)
            }
            .lineLimit(1)
            // Tertiary: 7d window — "7d 23% · " mute + gold reset.
            HStack(spacing: 4) {
                Text("\(L10n.t(.week, lang)) \(week)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(t.mute)
                Text("\u{00B7}")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(t.ash)
                Text(weekReset)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(t.gold.opacity(0.85))
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
