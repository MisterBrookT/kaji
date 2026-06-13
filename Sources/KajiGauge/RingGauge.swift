import SwiftUI

// MARK: - RingGauge
//
// The product's signature visual. Per provider, a single 5-hour ring:
//   - Background track circle; a value arc trimmed to usedFraction from 12 o'clock.
//   - Warm gold normally; same-family deeper AMBER at >= 80% (the "near limit"
//     alert) with a thicker arc. No glow, no stray tick — restrained.
//   - Center: the real provider logo (tinted to the arc) and the big used-%
//     number. No sparkline — quota.py exposes no real history to chart yet.
//   - Below the ring: the provider NAME (kills logo ambiguity) + a clear
//     "周 {week}% · resets {reset}" caption.
struct RingGauge: View {
    let provider: ProviderView

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    // Geometry — compact for a desktop HUD (was 96/12, felt oversized).
    private let ringSize: CGFloat = 84
    private let baseLineWidth: CGFloat = 10

    private var arcColor: Color { provider.isNearLimit ? t.amber : t.gold }

    private var valueLineWidth: CGFloat {
        provider.isNearLimit ? baseLineWidth + 3 : baseLineWidth
    }

    private var percentText: String {
        guard let p = provider.fiveHourPercent else { return "\u{2014}" }
        return "\(Int(p.rounded()))"
    }

    private var numberColor: Color { provider.isNearLimit ? t.amber : t.cream }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(t.track.opacity(0.5),
                            style: StrokeStyle(lineWidth: baseLineWidth, lineCap: .round))

                Circle()
                    .trim(from: 0, to: provider.usedFraction)
                    .stroke(arcColor,
                            style: StrokeStyle(lineWidth: valueLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    ProviderLogo(key: provider.id, color: arcColor, size: 17)

                    Text(percentText)
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .foregroundColor(numberColor)
                        .monospacedDigit()
                }
            }
            .frame(width: ringSize, height: ringSize)

            label
        }
    }

    private var label: some View {
        let week = provider.weekPercent.map { "\(Int($0.rounded()))%" } ?? "\u{2014}"
        let reset = ResetFormat.short(provider.resetDate)
        return VStack(spacing: 2) {
            Text(provider.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(t.cream)
            // 周 {week} · resets {reset} — reset in gold for a touch of warmth.
            (Text("\u{5468} \(week) \u{00B7} resets ").foregroundColor(t.mute)
                + Text(reset).foregroundColor(t.gold))
                .font(.system(size: 11))
                .lineLimit(1)
        }
    }
}

// MARK: - Reset formatting
enum ResetFormat {
    /// "—" when no date; "2h 14m" countdown for the future; "now" when past.
    static func short(_ date: Date?) -> String {
        guard let date = date else { return "\u{2014}" }
        let delta = date.timeIntervalSinceNow
        if delta <= 0 { return "now" }
        let hours = Int(delta) / 3600
        let mins = (Int(delta) % 3600) / 60
        if hours >= 24 {
            let days = hours / 24, rem = hours % 24
            return "\(days)d \(rem)h"
        }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}
