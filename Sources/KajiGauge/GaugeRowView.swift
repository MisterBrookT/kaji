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
                HStack(alignment: .top, spacing: 16) {
                    ForEach(shown) { provider in
                        RingGauge(provider: provider, lang: prefs.language)
                    }
                }
            }

            if let controls { footer(controls) }
        }
        .padding(14)
        .background(background)
        .fixedSize()
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

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(t.sun).frame(width: 7, height: 7)
            Text("Kaji")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(t.cream)
            Text("Gauge")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(t.mute)
            Spacer(minLength: 18)
            if store.lastError != nil, !store.providers.isEmpty {
                Text(L10n.t(.stale, prefs.language))
                    .font(.system(size: 10))
                    .foregroundColor(t.amber.opacity(0.9))
            } else {
                // Legend for the double ring: outer 5h, inner 7d.
                Text("5h \u{00B7} \(L10n.t(.week, prefs.language))")
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
            Text(store.lastError ?? L10n.t(.waiting, prefs.language))
                .font(.system(size: 11))
                .foregroundColor(t.mute)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 180, minHeight: 96)
    }
}
