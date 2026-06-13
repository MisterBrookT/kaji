import SwiftUI

// MARK: - Sparkline
//
// A thin polyline of the rolling 24h-ish history of 5h used% samples.
// quota.py exposes NO real time series — this is a buffer the gauge fills as it
// polls (persisted in UserDefaults). 5h used% barely moves over minutes, so we
// only draw it once there is genuine movement (see RingGauge.showSpark); a flat
// line is worse than none. Auto-ranged to the data so real variation is visible
// rather than squashed against a 0–100 axis.
private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard values.count >= 2 else { return }
                let w = geo.size.width, h = geo.size.height
                let minV = values.min() ?? 0
                let maxV = values.max() ?? 100
                let span = max(maxV - minV, 1)         // auto-range
                let step = w / CGFloat(values.count - 1)
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * step
                    let norm = (v - minV) / span
                    let y = h - CGFloat(norm) * h
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color.opacity(0.85),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - RingGauge
//
// The product's signature visual. Per provider, a single 5-hour ring:
//   - Background track circle; a value arc trimmed to usedFraction from 12 o'clock.
//   - Warm gold normally; same-family deeper AMBER at >= 80% (the "near limit"
//     alert) with a thicker arc + a color-independent alert tick. No glow.
//   - Center: the real provider logo (tinted to the arc), the big used-% number,
//     and — only when there's genuine movement — a thin sparkline.
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

    // Only draw the sparkline when there are enough real samples AND they
    // actually move — otherwise it's a misleading flat line.
    private var showSpark: Bool {
        let h = provider.history
        guard h.count >= 4, let lo = h.min(), let hi = h.max() else { return false }
        return (hi - lo) >= 1.0
    }

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

                if provider.isNearLimit && provider.usedFraction > 0 {
                    AlertTick(fraction: provider.usedFraction,
                              ringSize: ringSize, lineWidth: valueLineWidth)
                        .stroke(t.cream,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }

                VStack(spacing: 1) {
                    ProviderLogo(key: provider.id, color: arcColor, size: 17)

                    Text(percentText)
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .foregroundColor(numberColor)
                        .monospacedDigit()

                    if showSpark {
                        Sparkline(values: provider.history, color: arcColor)
                            .frame(width: 30, height: 8)
                    }
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

// MARK: - AlertTick
//
// A short radial line at the arc head — a color-independent second signal that
// the ring is in alert state.
private struct AlertTick: Shape {
    let fraction: Double
    let ringSize: CGFloat
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let angle = Angle.degrees(-90 + fraction * 360).radians
        let inner = radius - lineWidth / 2 - 3
        let outer = radius + lineWidth / 2 + 3
        p.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * inner,
                           y: center.y + CGFloat(sin(angle)) * inner))
        p.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * outer,
                              y: center.y + CGFloat(sin(angle)) * outer))
        return p
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
