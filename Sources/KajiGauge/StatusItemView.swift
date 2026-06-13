import SwiftUI

// MARK: - StatusItemView
//
// The compact menubar indicator: one concentric DOUBLE ring per visible
// provider (Claude, Codex), side by side. The menubar can't hold text, so each
// glyph carries two signals at once:
//   - OUTER arc = the 5-hour window
//   - INNER arc = the 7-day window
// plus an optional tiny center number (the 5h %), toggleable in Prefs. Color
// stays warm gold normally and deepens to amber once a window passes 80%.
// Click the item for the full popover (reset countdowns, toggles, language).
struct StatusItemView: View {
    let providers: [ProviderView]
    var showCenterNumber: Bool = true

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    var body: some View {
        HStack(spacing: 5) {
            if providers.isEmpty {
                DualRing(fiveFraction: 0, weekFraction: 0,
                         fiveColor: t.ash, weekColor: t.ash, centerText: nil)
            } else {
                ForEach(providers.prefix(2)) { p in
                    DualRing(
                        fiveFraction: p.usedFraction,
                        weekFraction: p.weekFraction,
                        fiveColor: p.isNearLimit ? t.amber : t.gold,
                        weekColor: p.weekNearLimit ? t.amber : t.gold.opacity(0.62),
                        centerText: centerText(p)
                    )
                }
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 22)
    }

    private func centerText(_ p: ProviderView) -> String? {
        guard showCenterNumber, let v = p.fiveHourPercent else { return nil }
        return "\(Int(v.rounded()))"
    }
}

// MARK: - DualRing
//
// Two concentric trim arcs (outer = 5h, inner = 7d) sharing a center. Sized for
// the menubar (~20pt). The center number is the 5h % — kept bold + monospaced so
// two digits stay legible at this size.
private struct DualRing: View {
    let fiveFraction: Double
    let weekFraction: Double
    let fiveColor: Color
    let weekColor: Color
    let centerText: String?

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    private let dim: CGFloat = 21
    private let outerLW: CGFloat = 2.3
    private let innerLW: CGFloat = 1.8
    private let gap: CGFloat = 1.3

    var body: some View {
        ZStack {
            ring(inset: 0, lineWidth: outerLW, fraction: fiveFraction, color: fiveColor)
            ring(inset: outerLW + gap, lineWidth: innerLW, fraction: weekFraction, color: weekColor)
            if let centerText {
                Text(centerText)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(t.cream)
            }
        }
        .frame(width: dim, height: dim)
    }

    private func ring(inset: CGFloat, lineWidth: CGFloat,
                      fraction: Double, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(t.track.opacity(0.55),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }
}
