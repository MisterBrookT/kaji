import SwiftUI

// MARK: - GaugeRowView
//
// A status-bar popover panel, one ring per visible provider. S/M presets keep
// layout bounded; there is no draggable floating window surface.
//
// The popover passes `controls` (a settings footer: provider toggles, language,
// refresh, quit). Snapshot views may pass nil — gauges only.
struct GaugeRowView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var prefs: Prefs
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var sleepController: SleepController
    @ObservedObject var petRunner: PetRunner

    var controls: Controls? = nil

    var panelSize: PanelSize? = nil
    /// Default ring size when the view is hugging its content (popover, or a
    /// panel that's at its natural fitting size).
    private let defaultRing: CGFloat = 84

    struct Controls {
        let onRefresh: () -> Void
        let onUpdate: () -> Void
        let onToggleKeepAwake: () -> Void
        let onTogglePet: () -> Void
        let onOpenSettings: () -> Void
        let onQuit: () -> Void
    }

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme, prefs.menubarStyle) }

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
            // ring size computed to fill the width for N providers — S/M just
            // scales the whole row proportionally.
            if controls != nil {
                popoverRings(panelSize)
            } else {
                panelRings(panelSize)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                ForEach(shown) { provider in
                    RingGauge(provider: provider, lang: prefs.language,
                              style: prefs.menubarStyle,
                              showRemaining: prefs.showRemaining,
                              ringSize: defaultRing)
                }
            }
        }
    }

    /// One horizontal row that always fits: ring diameter is derived from the
    /// (known, pinned) popover width and the provider count so N rings fill the
    /// row exactly — 3 fill it, 4 fill it — and S/M scale it as a unit. No
    /// GeometryReader (it would break the popover's vertical fitting pass).
    private func popoverRings(_ size: PanelSize) -> some View {
        if size == .small {
            return AnyView(
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(shown) { provider in
                        CompactRingRow(provider: provider,
                                       lang: prefs.language,
                                       style: prefs.menubarStyle,
                                       showRemaining: prefs.showRemaining,
                                       ringSize: size.ringSize)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            )
        }

        if shown.count <= 2 {
            return AnyView(
                HStack(alignment: .top, spacing: 18) {
                    ForEach(shown) { provider in
                        RingGauge(provider: provider, lang: prefs.language,
                                  style: prefs.menubarStyle,
                                  showRemaining: prefs.showRemaining,
                                  ringSize: size.ringSize)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            )
        }

        let columns = [
            GridItem(.flexible(), spacing: 12, alignment: .leading),
            GridItem(.flexible(), spacing: 12, alignment: .leading),
        ]
        return AnyView(
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(shown) { provider in
                    CompactRingRow(provider: provider,
                                   lang: prefs.language,
                                   style: prefs.menubarStyle,
                                   showRemaining: prefs.showRemaining,
                                   ringSize: 52)
                }
            }
        )
    }

    @ViewBuilder
    private func panelRings(_ size: PanelSize) -> some View {
        if size == .small {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(shown) { provider in
                    CompactRingRow(provider: provider,
                                   lang: prefs.language,
                                   style: prefs.menubarStyle,
                                   showRemaining: prefs.showRemaining,
                                   ringSize: size.ringSize)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: size == .medium ? 14 : 18) {
                ForEach(shown) { provider in
                    RingGauge(provider: provider, lang: prefs.language,
                              style: prefs.menubarStyle,
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
                    // Popover: width is pinned to S/M, but height grows
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

    // MARK: Footer (popover controls)

    private func footer(_ c: Controls) -> some View {
        VStack(spacing: 9) {
            Rectangle().fill(t.track).frame(height: 1).opacity(0.7)

            // Provider toggles stay in the main popover because they directly
            // affect the visible quota surface. Slower preferences live in the
            // Settings window.
            FlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(available) { p in
                    pill(p.displayName, on: prefs.isVisible(p.id)) {
                        prefs.toggleProvider(p.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 7) {
                Text(L10n.t(.system, prefs.language))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(t.mute)
                Spacer(minLength: 8)
                statusChip(keepAwakeTitle,
                           filled: keepAwakeIsActive,
                           emphasized: sleepController.isBusy || sleepController.lastError != nil) {
                    c.onToggleKeepAwake()
                }
                .disabled(sleepController.isBusy)
                Button(action: c.onUpdate) {
                    Text(updateTitle)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(updateChecker.available == nil ? t.mute : t.bg)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(updateChecker.available == nil ? Color.clear : t.gold)
                                .overlay(Capsule().stroke(updateChecker.available == nil ? t.track : Color.clear, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .disabled(updateChecker.isChecking)
            }

            HStack(spacing: 7) {
                Text(L10n.t(.pet, prefs.language))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(t.mute)
                Spacer(minLength: 8)
                statusChip(petTitle,
                           filled: petRunner.isRunning,
                           emphasized: petRunner.isBusy || petRunner.lastError != nil) {
                    c.onTogglePet()
                }
                .disabled(petRunner.isBusy)
            }

            // Actions row: refresh on the left, quit on the right.
            HStack(spacing: 12) {
                Button(action: c.onRefresh) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                        Text(L10n.t(.refreshNow, prefs.language))
                    }
                }
                Button(action: c.onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityLabel(Text(L10n.t(.settings, prefs.language)))
                }
                Spacer(minLength: 10)
                Button(action: c.onQuit) { Text(L10n.t(.quit, prefs.language)) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(t.mute)
        }
    }

    private var updateTitle: String {
        if let release = updateChecker.available {
            return L10n.t(.updateTo, prefs.language) + " " + release.tag
        }
        if updateChecker.isChecking {
            return L10n.t(.updateChecking, prefs.language)
        }
        if updateChecker.lastError != nil {
            return L10n.t(.updateFailed, prefs.language)
        }
        if updateChecker.lastChecked != nil {
            return L10n.t(.updateCurrent, prefs.language)
        }
        return L10n.t(.checkUpdates, prefs.language)
    }

    private var keepAwakeTitle: String {
        if let target = sleepController.targetEnabled, sleepController.isBusy {
            return target
                ? L10n.t(.keepAwakeTurningOn, prefs.language)
                : L10n.t(.keepAwakeTurningOff, prefs.language)
        }
        if sleepController.lastError != nil {
            return L10n.t(.keepAwakeFailed, prefs.language)
        }
        return sleepController.isEnabled
            ? L10n.t(.keepAwakeOn, prefs.language)
            : L10n.t(.keepAwakeOff, prefs.language)
    }

    private var keepAwakeIsActive: Bool {
        sleepController.targetEnabled ?? sleepController.isEnabled
    }

    private var petTitle: String {
        if petRunner.isBusy {
            return petRunner.isRunning
                ? L10n.t(.petTurningOff, prefs.language)
                : L10n.t(.petTurningOn, prefs.language)
        }
        if petRunner.lastError != nil {
            return L10n.t(.petFailed, prefs.language)
        }
        return petRunner.isRunning
            ? L10n.t(.petOn, prefs.language)
            : L10n.t(.petOff, prefs.language)
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

    private func statusChip(_ title: String, filled: Bool, emphasized: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(filled ? t.bg : t.mute)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(filled ? t.gold : Color.clear)
                        .overlay(
                            Capsule()
                                .stroke(emphasized ? t.gold.opacity(0.75) : (filled ? Color.clear : t.track),
                                        lineWidth: 1)
                        )
                )
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
            // Theme-aware accent dot, kept smaller than data.
            Circle().fill(t.sun).frame(width: 7, height: 7)
            Text("Kaji")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(t.cream)
                .layoutPriority(2)
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
// List-row layout retained for compact snapshots / future narrow popovers.
// Same product signature (concentric ring + logo + %), but the label
// moves to the RIGHT of the ring instead of below it. Pattern after iStat
// Menus / MonitorControl / Spotify compact card: [icon] + [text] horizontal,
// so the text column gets the full panel width and names never truncate to
// "Clau" / "Cod" / "Mini".
//
// Ring size stays fixed at 56pt here, so compact rows stay predictable.
private struct CompactRingRow: View {
    let provider: ProviderView
    var lang: Lang = .en
    var style: MenubarStyle = .mono
    var showRemaining: Bool = false
    var ringSize: CGFloat = 56

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme, style) }

    // Same ring math as RingGauge, scaled by ringSize.
    private var baseLineWidth: CGFloat { ringSize * (10.0 / 84.0) }
    private var innerLineWidth: CGFloat { ringSize * (5.0 / 84.0) }
    private var innerInset: CGFloat    { ringSize * (13.0 / 84.0) }
    private var logoSize: CGFloat      { ringSize * (13.0 / 84.0) }
    private var percentFont: CGFloat   { ringSize * (14.0 / 84.0) }
    private var metricLabelFont: CGFloat { ringSize * (7.0 / 84.0) }

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
    private func displayPercent(_ raw: Double?) -> String {
        guard let p = raw else { return "\u{2014}" }
        let shown = showRemaining ? (100.0 - p) : p
        return "\(Int(shown.rounded()))"
    }
    private var fivePercentText: String { displayPercent(provider.fiveHourPercent) }
    private var weekPercentText: String { displayPercent(provider.weekPercent) }
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

                VStack(spacing: 0) {
                    ProviderLogo(key: provider.id, color: arcColor, size: logoSize)
                    metric("5h", fivePercentText, color: numberColor)
                    metric(L10n.t(.week, lang), weekPercentText,
                           color: provider.weekNearLimit ? t.amber : t.gold)
                }
            }
            .frame(width: ringSize, height: ringSize)

            // Text column on the right takes all remaining width via
            // maxWidth: .infinity, so provider names do not truncate.
            textColumn
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ label: String, _ value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1.5) {
            Text(label)
                .font(.system(size: metricLabelFont, weight: .medium, design: .rounded))
                .foregroundColor(t.mute)
            Text(value)
                .font(.system(size: percentFont, weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.55)
    }

    private var textColumn: some View {
        let fiveReset = ResetFormat.short(provider.resetDate)
        let weekReset = ResetFormat.absolute(provider.weekResetDate)
        return VStack(alignment: .leading, spacing: 4) {
            // Primary: provider name (semibold 13pt, cream).
            Text(provider.displayName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(t.cream)
                .lineLimit(1)
            // Secondary: reset timing. Percentages live in the ring.
            HStack(spacing: 4) {
                Text("5h \(fivePercentText)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(t.mute)
                Text(fiveReset)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(t.gold)
            }
            .lineLimit(1)
            HStack(spacing: 4) {
                Text("\(L10n.t(.week, lang)) \(weekPercentText)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(t.mute)
                Text(weekReset)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(t.gold.opacity(0.85))
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
