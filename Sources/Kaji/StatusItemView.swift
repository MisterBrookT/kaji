import SwiftUI

// MARK: - StatusItemView
//
// The compact menubar indicator: one concentric DOUBLE ring per visible
// provider, side by side. Each glyph carries the provider's identity AND two
// quota signals at once:
//   - CENTER  = the provider mark.
//   - OUTER arc = the 5-hour window.
//   - INNER arc = the 7-day window.
// The exact % lives in the popover (click the item); the arc length already
// shows roughly how full each window is.
//
// Glyphs are always adaptive mono (system Light / Dark) — no Color product path.
struct StatusItemView: View {
    let providers: [ProviderView]
    var showRemaining: Bool = false
    /// When a newer release exists, a small accent dot rides the top-trailing
    /// corner of the glyph as a passive "update available" cue (open popover ->
    /// "Update to vX" to act on it). No notification permission needed.
    var updateAvailable: Bool = false
    /// Optional work countdown (`MM:SS`) to the right of the rings.
    /// `nil` when the work module is disabled — no slot rendered.
    var workSlotLabel: String? = nil
    /// Optional today's completion summary (`n/n`) when Goals is enabled.
    var goalsSlotLabel: String? = nil
    var onQuotaClick: () -> Void = {}
    var onWorkClick: () -> Void = {}
    var onGoalsClick: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            Button(action: onQuotaClick) {
                HStack(spacing: 5) {
                    if providers.isEmpty {
                        DualRing(provider: nil, showRemaining: showRemaining)
                    } else {
                        ForEach(providers.prefix(4)) { p in
                            DualRing(provider: p, showRemaining: showRemaining)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let workSlotLabel {
                Button(action: onWorkClick) {
                    WorkStatusSlot(label: workSlotLabel)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let goalsSlotLabel {
                Button(action: onGoalsClick) {
                    GoalsStatusSlot(label: goalsSlotLabel)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 22)
        .overlay(alignment: .topTrailing) {
            if updateAvailable {
                Circle()
                    .fill(KajiTheme.resolve(scheme).sun)
                    .frame(width: 5, height: 5)
                    .overlay(Circle().stroke(.background, lineWidth: 1))
                    .offset(x: 1, y: 1)
            }
        }
    }
}

private struct GoalsStatusSlot: View {
    let label: String

    @Environment(\.colorScheme) private var scheme

    private var color: Color {
        scheme == .dark ? .white : .black
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .medium))
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 2)
    }
}

// MARK: - WorkStatusSlot
//
// Compact remaining-time label beside the quota rings. Mono only;
// never shows the string "BREAK" (spec §4).
private struct WorkStatusSlot: View {
    let label: String

    @Environment(\.colorScheme) private var scheme

    private var color: Color {
        scheme == .dark ? .white : .black
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - DualRing
//
// Two concentric trim arcs (outer 5h, inner 7d) around a center provider logo.
// Sized for the menubar (~21pt).
private struct DualRing: View {
    let provider: ProviderView?
    let showRemaining: Bool

    @Environment(\.colorScheme) private var scheme

    private let dim: CGFloat = 21
    private let outerLW: CGFloat = 2.0
    private let innerLW: CGFloat = 1.7
    private let gap: CGFloat = 1.3

    private var base: Color { scheme == .dark ? .white : .black }
    private var innerColor: Color { base.opacity(0.65) }
    private var trackColor: Color { base.opacity(0.22) }

    private var fiveFraction: Double {
        guard let provider else { return 0 }
        return showRemaining ? 1.0 - provider.usedFraction : provider.usedFraction
    }
    private var weekFraction: Double {
        guard let provider else { return 0 }
        return showRemaining ? 1.0 - provider.weekFraction : provider.weekFraction
    }
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
