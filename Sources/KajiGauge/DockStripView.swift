import SwiftUI

// MARK: - DockStripView
//
// The visual shown when the floating HUD is `.docked` against a screen edge.
// A 36pt thin strip hosting:
//   - one cell per VISIBLE provider (logo + 5h %) along the SCREEN-edge side.
//   - a curved handle ("ear") on the PANEL-facing side, with a chevron
//     pointing the way the panel will unfold. Click handle (or anywhere on
//     the strip) → `onExpand()`.
//
// Layout is done natively via HStack / VStack — no rotation. The strip's
// long axis (height for left/right docks, width for top/bottom docks) is laid
// out the way the eye reads it, so the chevron + cells never need a transform.
struct DockStripView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var prefs: Prefs
    let edge: DockEdge
    let onExpand: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    /// All providers the user has chosen to show — we render one cell per
    /// provider in the strip (the strip is long enough to fit them along its
    /// long axis; cross axis stays 36pt). Order matches Providers.order so
    /// Claude / Codex / MiniMax are visually consistent across surfaces.
    private var providers: [ProviderView] {
        store.providers.filter { prefs.isVisible($0.id) }
    }

    var body: some View {
        // Handle sits on the PANEL-facing side, content on the SCREEN-edge
        // side. No rotation — the long axis is laid out natively.
        Group {
            switch edge {
            case .left:
                HStack(spacing: 0) { handle; content }
            case .right:
                HStack(spacing: 0) { content; handle }
            case .top:
                VStack(spacing: 0) { handle; content }
            case .bottom:
                VStack(spacing: 0) { content; handle }
            }
        }
        .background(stripBg)
        .overlay(stripOutline)
        .clipShape(stripShape)
        .contentShape(stripShape)
        .onTapGesture(perform: onExpand)
    }

    // MARK: Background + shape

    private var stripBg: some View {
        // Same warm paper/ink gradient as the full HUD so the docked strip
        // doesn't look like a foreign object on the desktop.
        LinearGradient(
            colors: [t.bgTop, t.bg],
            startPoint: .topTrailing, endPoint: .bottomLeading
        )
    }

    private var stripOutline: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(t.gold.opacity(0.55), lineWidth: 1)
    }

    /// Capsule on both ends — the panel-facing edge already curves gracefully,
    /// and the dedicated handle View on top of it pops as the affordance.
    private var stripShape: some Shape {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    // MARK: Content (all visible providers, one cell each)

    /// All visible providers laid out along the strip's long axis:
    /// - left/right dock (36pt wide): VStack of 3 cells, each ~24pt tall.
    /// - top/bottom dock (36pt high): HStack of 3 cells, each ~24pt wide.
    /// The cross axis is the strip's fixed 36pt thickness, so the cells stay
    /// compact. Each cell is just a logo + the 5h % — the countdowns are
    /// dropped here on purpose; the full HUD shows them on expand.
    private var content: some View {
        Group {
            if providers.isEmpty {
                // No providers yet — a tiny dot to mark the strip as ours.
                Circle().fill(t.ash).frame(width: 5, height: 5)
                    .padding(.vertical, 8)
            } else {
                switch edge {
                case .left, .right:
                    VStack(alignment: .center, spacing: 4) {
                        ForEach(providers) { p in cell(p) }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                case .top, .bottom:
                    HStack(alignment: .center, spacing: 8) {
                        ForEach(providers) { p in cell(p) }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    /// One compact cell: tiny provider logo on top, % below. Sized so 3 of
    /// them stack along the long axis of a 36pt strip without crowding.
    private func cell(_ p: ProviderView) -> some View {
        VStack(spacing: 2) {
            ProviderLogo(key: p.id, color: t.cream, size: 11)
            Text(percentText(p))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(p.isNearLimit ? t.amber : t.gold)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()  // don't shrink — readability wins in a 36pt strip
        }
        .frame(minWidth: 22, minHeight: 24)
    }

    private func percentText(_ p: ProviderView) -> String {
        guard let raw = p.fiveHourPercent else { return "\u{2014}" }
        let shown = prefs.showRemaining ? (100 - raw) : raw
        return "\(Int(shown.rounded()))%"
    }

    // MARK: Handle (panel-facing side)

    /// Curved pill on the inner side of the strip. The chevron points the
    /// way the panel will unfold. Has its own gold-tinted backdrop so it
    /// visually pops as "this is the button" against the warm-paper strip.
    /// The whole strip is also tappable as a fallback.
    private var handle: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(t.gold.opacity(0.18))
                .overlay(Capsule(style: .continuous)
                    .stroke(t.gold.opacity(0.7), lineWidth: 1))
            Image(systemName: chevronName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(t.gold)
        }
        .frame(width: handleSize.width, height: handleSize.height)
        .padding(3)
        .contentShape(Rectangle())
        .onTapGesture(perform: onExpand)
    }

    /// Tall thin pill on left/right docks, short wide pill on top/bottom.
    /// Sized so it reads as a "tab" inside the strip without competing with
    /// the logo / percentage content.
    private var handleSize: CGSize {
        switch edge {
        case .left, .right:
            return CGSize(width: 14, height: 44)
        case .top, .bottom:
            return CGSize(width: 44, height: 14)
        }
    }

    /// Chevron points WHERE the panel will unfold toward when the user clicks.
    private var chevronName: String {
        switch edge {
        case .left:   return "chevron.right"   // panel unrolls to the right
        case .right:  return "chevron.left"    // panel unrolls to the left
        case .top:    return "chevron.down"    // panel unrolls down
        case .bottom: return "chevron.up"      // panel unrolls up
        }
    }
}