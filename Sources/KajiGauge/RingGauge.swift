import SwiftUI

// MARK: - RingGauge
//
// The product's signature visual. Per provider, a concentric DOUBLE ring:
//   - OUTER thick arc = the 5-hour window (gold; deeper AMBER + thicker at >=80%).
//   - INNER thin arc  = the 7-day window (dimmer gold; amber at >=80%).
//   - Center: the real provider logo (tinted to the 5h arc) + the big 5h %.
//   - Below: the provider NAME, then two captions — the 5h reset countdown and
//     "7d {week}% · {reset}" — so "how long until reset" is answered for BOTH
//     windows right here in the popover. Localized EN / 中文.
struct RingGauge: View {
    let provider: ProviderView
    var lang: Lang = .en

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    // Geometry — compact for a desktop HUD.
    private let ringSize: CGFloat = 84
    private let baseLineWidth: CGFloat = 10
    private let innerLineWidth: CGFloat = 5
    private let innerInset: CGFloat = 13   // pulls the 7d ring inside the 5h ring

    private var arcColor: Color { provider.isNearLimit ? t.amber : t.gold }
    private var weekColor: Color { provider.weekNearLimit ? t.amber : t.gold.opacity(0.55) }

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
                // Outer 5h ring.
                Circle()
                    .stroke(t.track.opacity(0.5),
                            style: StrokeStyle(lineWidth: baseLineWidth, lineCap: .round))
                Circle()
                    .trim(from: 0, to: provider.usedFraction)
                    .stroke(arcColor,
                            style: StrokeStyle(lineWidth: valueLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                // Inner 7d ring.
                Circle()
                    .stroke(t.track.opacity(0.4),
                            style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .round))
                    .padding(innerInset)
                Circle()
                    .trim(from: 0, to: provider.weekFraction)
                    .stroke(weekColor,
                            style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(innerInset)

                VStack(spacing: 1) {
                    ProviderLogo(key: provider.id, color: arcColor, size: 16)
                    Text(percentText)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
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
        let fiveReset = ResetFormat.phrase(provider.resetDate, lang)
        let weekReset = ResetFormat.phrase(provider.weekResetDate, lang)
        return VStack(spacing: 2) {
            Text(provider.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(t.cream)
            // 5h reset countdown (the outer ring's window).
            (Text("5h \u{00B7} ").foregroundColor(t.mute)
                + Text(fiveReset).foregroundColor(t.gold))
                .font(.system(size: 10))
                .lineLimit(1)
            // 7d used % + its own reset countdown (the inner ring's window).
            (Text("\(L10n.t(.week, lang)) \(week) \u{00B7} ").foregroundColor(t.mute)
                + Text(weekReset).foregroundColor(t.gold.opacity(0.85)))
                .font(.system(size: 10))
                .lineLimit(1)
        }
    }
}

// MARK: - Reset formatting
enum ResetFormat {
    /// Bare duration: "2h 14m" / "1d 6h" / "now"; nil when there is no date.
    static func dur(_ date: Date?) -> String? {
        guard let date = date else { return nil }
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

    /// Localized "resets in {dur}" / "{dur} 后重置". Handles past + missing.
    static func phrase(_ date: Date?, _ lang: Lang) -> String {
        guard let d = dur(date) else { return "\u{2014}" }
        if d == "now" { return lang == .zh ? "\u{5DF2}\u{91CD}\u{7F6E}" : "resets now" } // 已重置
        return lang == .zh ? "\(d) \u{540E}\u{91CD}\u{7F6E}" : "resets in \(d)"          // 后重置
    }

    /// "—" when no date; "2h 14m" countdown otherwise. (compat helper)
    static func short(_ date: Date?) -> String { dur(date) ?? "\u{2014}" }
}
