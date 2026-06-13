import SwiftUI

// MARK: - GaugeRowView
//
// A horizontal row of ring gauges, one per provider. Shared by both surfaces
// (the menubar popover and the floating panel) so they always render the same
// content from the same store. The view sizes to its content — no fixed width —
// so two providers don't leave a wall of dead space (it adapts to N rings).
struct GaugeRowView: View {
    @ObservedObject var store: QuotaStore

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if store.providers.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(store.providers) { provider in
                        RingGauge(provider: provider)
                    }
                }
            }
        }
        .padding(14)
        .background(background)
        .fixedSize()   // hug the content in both axes — adaptive width
    }

    // Warm depth instead of flat black — matches the approved design preview's
    // ember glow, so the native app reads as "Kaji", not generic dark.
    private var background: some View {
        LinearGradient(
            colors: [t.bgTop, t.bg],
            startPoint: .topTrailing, endPoint: .bottomLeading
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            // Persimmon SUN dot — the one true Kaji brand accent.
            Circle().fill(t.sun).frame(width: 7, height: 7)
            Text("Kaji")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(t.cream)
            Text("Gauge")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(t.mute)
            Spacer(minLength: 18)
            // No "updated Ns ago" — the gauge polls on its own; a timestamp is
            // noise. Only flag the abnormal case: stale data after a fetch error.
            if store.lastError != nil, !store.providers.isEmpty {
                Text("stale")
                    .font(.system(size: 10))
                    .foregroundColor(t.amber.opacity(0.9))
            } else {
                Text("5h quota")
                    .font(.system(size: 10))
                    .foregroundColor(t.ash)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("\u{2014}")
                .font(.system(size: 28))
                .foregroundColor(t.ash)
            Text(store.lastError ?? "waiting for quota\u{2026}")
                .font(.system(size: 11))
                .foregroundColor(t.mute)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 180, minHeight: 96)
    }
}
