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
//
// `showRemaining` flips BOTH the ring trim direction (1-usedFraction) and the
// center % text (100-used) — "0% means full" instead of "100% means full".
// The "near limit" threshold is ALWAYS based on USED, so an empty (remaining
// 100%) ring never reads as amber; a low-remaining ring always does.
struct RingGauge: View {
    let provider: ProviderView
    var lang: Lang = .en
    /// When true, the ring + % read as REMAINING (100% used → empty ring + 0%).
    var showRemaining: Bool = false

    /// Outer ring diameter. Scales the ring + the logo + the big % together so
    /// the visual mass stays proportional when the floating HUD is resized.
    /// 84 = the legacy fixed size used by the popover + first-launch HUD.
    var ringSize: CGFloat = 84

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    // All ring geometry is derived from ringSize so the gauge scales as a unit.
    private var baseLineWidth: CGFloat { ringSize * (10.0 / 84.0) }
    private var innerLineWidth: CGFloat { ringSize * (5.0 / 84.0) }
    private var innerInset: CGFloat    { ringSize * (13.0 / 84.0) }
    private var logoSize: CGFloat      { ringSize * (16.0 / 84.0) }
    private var percentFont: CGFloat   { ringSize * (22.0 / 84.0) }

    /// "Near limit" is always USED-based regardless of display direction —
    /// we don't want the ring color to flip just because the user toggled
    /// between used/remaining. (>=80% used = amber in both modes.)
    private var arcColor: Color { provider.isNearLimit ? t.amber : t.gold }
    private var weekColor: Color { provider.weekNearLimit ? t.amber : t.gold.opacity(0.55) }

    private var valueLineWidth: CGFloat {
        provider.isNearLimit ? baseLineWidth + (ringSize * (3.0 / 84.0)) : baseLineWidth
    }

    /// Fraction of the ring's TRIM, given the current display direction.
    private var trimFraction: Double {
        showRemaining ? 1.0 - provider.usedFraction : provider.usedFraction
    }

    /// 7-day inner ring, also direction-flipped for symmetry.
    private var weekTrimFraction: Double {
        showRemaining ? 1.0 - provider.weekFraction : provider.weekFraction
    }

    /// Center % text — shown as USED or REMAINING per the toggle.
    private var percentText: String {
        guard let p = provider.fiveHourPercent else { return "\u{2014}" }
        let shown = showRemaining ? (100.0 - p) : p
        return "\(Int(shown.rounded()))"
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
                    .trim(from: 0, to: trimFraction)
                    .stroke(arcColor,
                            style: StrokeStyle(lineWidth: valueLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                // Inner 7d ring.
                Circle()
                    .stroke(t.track.opacity(0.4),
                            style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .round))
                    .padding(innerInset)
                Circle()
                    .trim(from: 0, to: weekTrimFraction)
                    .stroke(weekColor,
                            style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(innerInset)

                VStack(spacing: 1) {
                    ProviderLogo(key: provider.id, color: arcColor, size: logoSize)
                    Text(percentText)
                        .font(.system(size: percentFont, weight: .semibold, design: .rounded))
                        .foregroundColor(numberColor)
                        .monospacedDigit()
                }
            }
            .frame(width: ringSize, height: ringSize)

            label
        }
    }

    private var label: some View {
        let weekRaw = provider.weekPercent
        let weekDisplayed = weekRaw.map { showRemaining ? (100 - $0) : $0 }
        let week = weekDisplayed.map { "\(Int($0.rounded()))%" } ?? "\u{2014}"
        // When the ring is small, drop the "5h · " and "周 {n}% · " prefixes.
        // The rings themselves encode the window visually; the countdown is
        // the load-bearing info and must remain readable in full.
        let narrow = ringSize < 78
        // Very small rings (adaptive popover with many providers): even the
        // "{dur} 后重置" phrase won't fit — fall back to the bare duration so
        // the number itself stays legible.
        let tiny = ringSize < 58
        let fiveReset = tiny ? ResetFormat.short(provider.resetDate)
                             : ResetFormat.phrase(provider.resetDate, lang)
        let weekReset = tiny ? ResetFormat.short(provider.weekResetDate)
                             : ResetFormat.phrase(provider.weekResetDate, lang)
        // Fonts scale with ringSize too, so the whole row shrinks as a unit.
        let nameFont = min(13, max(8.5, ringSize * (12.0 / 84.0)))
        let capFont  = min(11, max(7.0, ringSize * (10.0 / 84.0)))
        return VStack(spacing: 2) {
            Text(provider.displayName)
                .font(.system(size: nameFont, weight: .semibold, design: .rounded))
                .foregroundColor(t.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // 5h reset countdown (the outer ring's window).
            (Text(narrow ? "" : "5h \u{00B7} ").foregroundColor(t.mute)
                + Text(fiveReset).foregroundColor(t.gold))
                .font(.system(size: capFont, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.7)
            // 7d used % — the ONLY numeric readout of the inner ring, so it stays
            // visible at EVERY size (amber when near the weekly limit, so a maxed
            // week is obvious at a glance). Only the trailing reset countdown is
            // dropped when the ring is narrow.
            (Text("\(L10n.t(.week, lang)) ").foregroundColor(t.mute)
                + Text(week).foregroundColor(provider.weekNearLimit ? t.amber : t.gold)
                + Text(narrow ? "" : "  \u{00B7} \(weekReset)").foregroundColor(t.gold.opacity(0.85)))
                .font(.system(size: capFont, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.7)
        }
        .fixedSize(horizontal: false, vertical: true)
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