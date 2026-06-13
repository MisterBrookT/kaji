import SwiftUI

// MARK: - GaugeRowView
//
// A horizontal row of ring gauges, one per provider. Shared by both surfaces
// (the menubar popover and the floating panel) so they always render the same
// content from the same store. The view sizes to its content — no fixed width —
// so two providers don't leave a wall of dead space (it adapts to N rings).
struct GaugeRowView: View {
    @ObservedObject var store: QuotaStore

    // When set (the menubar popover), a slim footer is drawn under the rings with
    // a floating-panel toggle + quit. The desktop panel passes nil — no footer.
    var controls: Controls? = nil

    struct Controls {
        let panelVisible: Bool
        let onTogglePanel: () -> Void
        let onQuit: () -> Void
    }

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

            if let controls { footer(controls) }
        }
        .padding(14)
        .background(background)
        .fixedSize()   // hug the content in both axes — adaptive width
    }

    // Lives inside the gradient-backed VStack, so it spans the rings' width with
    // no dead margin. Spacer pushes Quit to the right (same trick as `header`).
    private func footer(_ c: Controls) -> some View {
        VStack(spacing: 9) {
            Rectangle().fill(t.track).frame(height: 1).opacity(0.7)
            HStack(spacing: 12) {
                Button(action: c.onTogglePanel) {
                    HStack(spacing: 5) {
                        Image(systemName: c.panelVisible
                              ? "macwindow" : "macwindow.badge.plus")
                        Text(c.panelVisible ? "Hide desktop panel" : "Float on desktop")
                    }
                }
                Spacer(minLength: 10)
                Button(action: c.onQuit) { Text("Quit") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(t.mute)
        }
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
