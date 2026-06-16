import SwiftUI

// MARK: - DockStripView
//
// The visual shown when the floating HUD is `.docked` against a screen edge.
// A 36pt thin strip with the mostConstrained provider's logo + 5h percentage
// + reset countdown, so the user keeps an at-a-glance read of their tightest
// quota even with the panel collapsed out of the way.
//
// The strip rotates the content 90° on left/right docks so reading flows
// top→bottom (matches QQ-style edge docks). On top/bottom the strip is short
// + wide and reads horizontally (no rotation).
//
// Tap or hover the strip → `onExpand()` fires; the controller animates the
// panel back to its saved expanded frame.
struct DockStripView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var prefs: Prefs
    let edge: DockEdge
    let onExpand: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    /// The provider currently closest to its 5h limit. Falls back to the
    /// first available if none have data (we always show *something*).
    private var provider: ProviderView? {
        if let m = store.mostConstrained { return m }
        return store.providers.first
    }

    var body: some View {
        // The frame is set by the controller (panel width/height after snap).
        // Content is rotated on left/right edges so the strip reads top-down.
        ZStack {
            background
            content
                .rotationEffect(rotation, anchor: .center)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: onExpand)
    }

    // MARK: Background chrome

    private var background: some View {
        ZStack {
            // Same warm paper/ink gradient as the full HUD so the docked
            // strip doesn't look like a foreign object on the desktop.
            LinearGradient(
                colors: [t.bgTop, t.bg],
                startPoint: .topTrailing, endPoint: .bottomLeading
            )
            // 1pt gold outline — matches the HUD's accent ring so docked
            // mode reads as a continuation, not a separate widget.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(t.gold.opacity(0.55), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Content

    private var content: some View {
        // VStack along the strip's long axis (will be rotated for left/right).
        // Spacing is tight — the strip is 36pt wide so we have ~30pt usable.
        VStack(spacing: 3) {
            logo
            percentLabel
            countdownLabel
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var logo: some View {
        if let p = provider {
            ProviderLogo(key: p.id, color: t.cream, size: 13)
        } else {
            // No providers yet — a tiny dot to mark the strip as ours.
            Circle().fill(t.ash).frame(width: 5, height: 5)
        }
    }

    private var percentLabel: some View {
        let text: String = {
            guard let p = provider, let pct = p.fiveHourPercent else { return "—" }
            return "\(Int(pct.rounded()))%"
        }()
        return Text(text)
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundColor(t.gold)
            .lineLimit(1)
            .fixedSize()  // don't shrink — readability wins in a 36pt strip
    }

    private var countdownLabel: some View {
        Text(countdownText)
            .font(.system(size: 8.5, weight: .regular, design: .monospaced))
            .foregroundColor(t.cream.opacity(0.55))
            .lineLimit(1)
            .fixedSize()
    }

    /// "5h12m" or "12m" or "" when no data. Matches the menubar's compact
    /// style — short enough to fit a rotated 36pt strip without truncation.
    private var countdownText: String {
        guard let p = provider, let reset = p.resetDate else { return "·" }
        let secs = max(0, Int(reset.timeIntervalSinceNow))
        if secs <= 0 { return "now" }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }

    // MARK: Rotation

    /// Left/right docks rotate content 90° so the strip reads top→bottom;
    /// top/bottom docks keep horizontal reading.
    private var rotation: Angle {
        switch edge {
        case .left:   return .degrees(90)
        case .right:  return .degrees(-90)
        case .top, .bottom: return .degrees(0)
        }
    }
}
