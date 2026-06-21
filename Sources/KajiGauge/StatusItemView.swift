import SwiftUI

// MARK: - StatusItemView
//
// The compact menubar indicator: one concentric DOUBLE ring per visible
// provider, side by side. Each glyph carries the provider's identity AND two
// quota signals at once:
//   - CENTER  = the provider's logo (Claude burst / OpenAI knot) — this is how
//     you tell Claude from Codex at a glance.
//   - OUTER arc = the 5-hour window.
//   - INNER arc = the 7-day window.
// The exact % lives in the popover (click the item); the arc length already
// shows roughly how full each window is.
//
// Style (Prefs.menubarStyle):
//   - .mono  (default) — adaptive label color, so it sits quietly among the
//     native monochrome menu-bar icons. Near-limit thickens the outer arc.
//   - .color — warm persimmon, for more presence.
struct StatusItemView: View {
    let providers: [ProviderView]
    var style: MenubarStyle = .mono
    /// When a newer release exists, a small accent dot rides the top-trailing
    /// corner of the glyph as a passive "update available" cue (right-click ->
    /// "Update to vX" to act on it). No notification permission needed.
    var updateAvailable: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            if providers.isEmpty {
                DualRing(provider: nil, style: style)
            } else {
                // Show every visible provider — capping at 4 keeps the glyph
                // compact (5+ would crowd the menubar and fight other icons).
                // 4 also matches the max in `Providers.visible` minus hidden
                // ones, so this is a future-proof ceiling, not a guess.
                ForEach(providers.prefix(4)) { p in
                    DualRing(provider: p, style: style)
                }
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 22)
        .overlay(alignment: .topTrailing) {
            if updateAvailable {
                Circle()
                    .fill(KajiTheme.resolve(scheme).gold)
                    .frame(width: 5, height: 5)
                    .overlay(Circle().stroke(.background, lineWidth: 1))
                    .offset(x: 1, y: 1)
            }
        }
    }
}

// MARK: - DualRing
//
// Two concentric trim arcs (outer 5h, inner 7d) around a center provider logo.
// Sized for the menubar (~21pt).
private struct DualRing: View {
    let provider: ProviderView?
    let style: MenubarStyle

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    private let dim: CGFloat = 21
    private let outerLW: CGFloat = 2.3
    private let innerLW: CGFloat = 1.7
    private let gap: CGFloat = 1.3

    // Base color:
    //   - mono  → adaptive label color, to sit with the native monochrome icons.
    //   - color → the Kaji ring color, which is theme-aware on purpose: vibrant
    //     persimmon by day (Kaji Sun), warm ember gold by night (Kaji Ember).
    //     Day = energetic, night = quiet luxury — and it matches the popover ring.
    private var base: Color {
        switch style {
        case .mono:  return scheme == .dark ? .white : .black
        case .color: return t.gold
        }
    }
    private var innerColor: Color { base.opacity(style == .mono ? 0.42 : 0.5) }
    // Track: a faint tint of the base in mono (so the glyph sits quietly with the
    // native monochrome icons), but a NEUTRAL warm-grey track in color — exactly
    // like the popover ring. That way only the arcs read as persimmon and the
    // ring breathes, instead of the whole glyph becoming a solid orange blob.
    private var trackColor: Color {
        switch style {
        case .mono:  return base.opacity(0.22)
        case .color: return t.track.opacity(0.7)
        }
    }

    private var fiveFraction: Double { provider?.usedFraction ?? 0 }
    private var weekFraction: Double { provider?.weekFraction ?? 0 }
    private var nearLimit: Bool { provider?.isNearLimit ?? false }

    var body: some View {
        ZStack {
            ring(inset: 0,
                 lineWidth: nearLimit ? outerLW + 0.9 : outerLW,
                 fraction: fiveFraction, color: base)
            ring(inset: outerLW + gap, lineWidth: innerLW,
                 fraction: weekFraction, color: innerColor)
            if let provider {
                ProviderLogo(key: provider.id, color: base, size: 9)
            }
        }
        .frame(width: dim, height: dim)
    }

    private func ring(inset: CGFloat, lineWidth: CGFloat,
                      fraction: Double, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(trackColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }
}
