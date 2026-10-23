import SwiftUI
import KajiCore

// MARK: - StatusItemView
//
// The compact menubar indicator: one concentric DOUBLE ring per visible
// provider, side by side — up to three, most-constrained first. Each glyph
// carries the provider's identity AND two quota signals at once:
//   - CENTER = the provider mark.
//   - OUTER arc = the 7-day window (dimmer — supportive context).
//   - INNER arc = the 5-hour window (bright, near-limit thickened — the
//     actionable number).
// The exact % lives in the popover (click the item); the arc length already
// shows roughly how full each window is.
//
// Glyphs are always adaptive mono (system Light / Dark) — no Color product path.
struct StatusItemView: View {
    let providers: [ProviderView]
    /// When a newer release exists, a small accent dot rides the top-trailing
    /// corner of the glyph as a passive "update available" cue (open popover ->
    /// "Update to vX" to act on it). No notification permission needed.
    var updateAvailable: Bool = false
    /// Optional work countdown in the user's selected display style.
    /// `nil` when the work module is disabled — no slot rendered.
    var workSlotLabel: String? = nil
    var workSlotShowsIcon: Bool = false
    /// Optional Goals summary when Goals is enabled.
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
                        DualRing(provider: nil)
                    } else {
                        ForEach(providers.prefix(4)) { p in
                            DualRing(provider: p)
                                .help("\(p.displayName): \(p.percentLeft.map { "\(Int($0.rounded()))% left" } ?? "unknown")\(p.isActiveAccount ? " · in use" : "")")
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("kaji.status.quota")
            if let workSlotLabel {
                Button(action: onWorkClick) {
                    WorkStatusSlot(label: workSlotLabel,
                                   showsIcon: workSlotShowsIcon)
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
    let showsIcon: Bool

    @Environment(\.colorScheme) private var scheme

    private var color: Color {
        scheme == .dark ? .white : .black
    }

    var body: some View {
        HStack(spacing: 2) {
            if showsIcon {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .medium))
            }
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - DualRing
//
// Two concentric trim arcs around a center provider logo, sized for the
// menubar (~21pt). OUTER = the 7-day window (dimmer — supportive context);
// INNER = the 5-hour window (bright `base`, thickened when near-limit — the
// actionable number). The 5-hour signal sits at the center of the glyph, so
// the urgent number stays the visually dominant one.
struct DualRing: View {
    let provider: ProviderView?

    @Environment(\.colorScheme) private var scheme

    private let dim: CGFloat = 18

    private var base: Color { scheme == .dark ? .white : .black }
    private var trackColor: Color { base.opacity(0.22) }

    static func arcFraction(usedPercent: Double?) -> Double {
        guard let usedPercent else { return 0 }
        let used = min(max(usedPercent / 100, 0), 1)
        return 1 - used
    }

    /// Binding limit: the tighter of 5h/7d, as % left (nil = no reading).
    private var left: Double? { provider?.percentLeft }
    private var low: Bool { (left ?? 100) <= 20 }

    var body: some View {
        ZStack {
            // At 0% left there is no arc to colour, so the warning also
            // tints the track and logo.
            ring(inset: 0, lineWidth: 2,
                 fraction: (left ?? 0) / 100,
                 color: low ? Color.orange : base,
                 track: low ? Color.orange.opacity(0.45) : trackColor)
            if let provider {
                ProviderLogo(key: provider.logo, color: low ? Color.orange : base, size: 9)
            }
        }
        .frame(width: dim, height: dim)
        .frame(width: 21, height: 22, alignment: .top)
        .overlay(alignment: .bottom) {
            if provider?.isActiveAccount == true {
                Capsule().fill(base).frame(width: 7, height: 2)
                    .accessibilityLabel("active account")
            }
        }
    }

    private func ring(inset: CGFloat, lineWidth: CGFloat,
                      fraction: Double, color: Color, track: Color) -> some View {
        ZStack {
            Circle()
                .stroke(track,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }
}
