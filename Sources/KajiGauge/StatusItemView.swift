import SwiftUI

// MARK: - StatusItemView
//
// The compact menubar indicator: one tiny ring per visible provider (Claude,
// Codex), side by side. No numbers — the menubar stays quiet; the arc fill and
// its color carry the signal (gold normally, deeper amber once a provider is
// near its limit). Click the item for the full popover. Falls back to a single
// neutral ring when there is no data yet.
struct StatusItemView: View {
    let providers: [ProviderView]

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    var body: some View {
        HStack(spacing: 5) {
            if providers.isEmpty {
                MiniRing(fraction: 0, color: t.ash)
            } else {
                ForEach(providers.prefix(2)) { p in
                    MiniRing(fraction: p.usedFraction,
                             color: p.isNearLimit ? t.amber : t.gold)
                }
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 22)
    }
}

// A single 14pt menubar ring: faint track + a value arc from 12 o'clock.
private struct MiniRing: View {
    let fraction: Double
    let color: Color

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(t.track.opacity(0.6),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
    }
}
