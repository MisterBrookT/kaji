import Foundation

/// Maps Cursor `GetCurrentPeriodUsage` fields onto Kaji's dual-window limits shape.
///
/// Spec: `dev_docs/specs/2026-07-24-cursor-quota.md`
/// Ring geometry: outer ← `five_hour` ← API；inner ← `seven_day` ← Auto.
public enum CursorLimitsLogic {
    public struct WindowLabels: Equatable, Sendable {
        /// Outer ring / `five_hour` caption.
        public let primary: String
        /// Inner ring / `seven_day` caption.
        public let secondary: String

        public init(primary: String, secondary: String) {
            self.primary = primary
            self.secondary = secondary
        }
    }

    /// Default captions for Claude/Codex-style windows.
    public static let standardLabels = WindowLabels(primary: "5h", secondary: "7d")

    /// Cursor-specific captions (product words; not localized).
    public static let cursorLabels = WindowLabels(primary: "API", secondary: "Auto")

    public static func windowLabels(for providerID: String) -> WindowLabels {
        providerID == "cursor" ? cursorLabels : standardLabels
    }

    /// Clamp a raw percent into `[0, 100]`. `nil` stays `nil`.
    public static func clampPercent(_ value: Double?) -> Double? {
        guard let value else { return nil }
        if value.isNaN || value.isInfinite { return nil }
        return min(100, max(0, value))
    }

    /// Convert Cursor billing-cycle end (epoch **milliseconds**) to ISO-8601 UTC.
    public static func resetsAtISO(fromBillingCycleEndMs ms: Double?) -> String? {
        guard let ms, ms.isFinite, ms > 0 else { return nil }
        let date = Date(timeIntervalSince1970: ms / 1000)
        return isoFormatter.string(from: date)
    }

    /// Build the limits dictionary keys expected by `quota.py` / `QuotaModel`.
    /// Missing percents are omitted (not zero-filled).
    public static func limits(
        apiPercentUsed: Double?,
        autoPercentUsed: Double?,
        billingCycleEndMs: Double?
    ) -> [String: Any] {
        var out: [String: Any] = [:]
        let reset = resetsAtISO(fromBillingCycleEndMs: billingCycleEndMs)

        if let api = clampPercent(apiPercentUsed) {
            out["five_hour_used_percent"] = api
            if let reset { out["five_hour_resets_at"] = reset }
        }
        if let auto = clampPercent(autoPercentUsed) {
            out["seven_day_used_percent"] = auto
            if let reset { out["seven_day_resets_at"] = reset }
        }
        return out
    }

    private static nonisolated(unsafe) let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}
