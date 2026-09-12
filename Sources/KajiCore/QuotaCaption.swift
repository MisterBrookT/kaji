import Foundation

/// Captions for a single quota window in the popover.
///
/// Lives in `KajiCore` so the "no reading" case is testable without booting a
/// view: a missing percentage and a real 0% must never render the same way.
/// Treating `nil` as zero once hid a broken Claude credential behind a row
/// that looked like healthy, unused quota.
public enum QuotaCaption {
    /// Shown instead of a reset time when the provider returned no reading.
    public static let unavailable = "no data \u{00B7} check sign-in"

    /// Percent text for a window. `nil` is an em dash, never "0%".
    public static func percent(_ value: Double?) -> String {
        guard let value else { return "\u{2014}" }
        return "\(Int(value.rounded()))%"
    }

    /// Whether a window has a usable reading at all.
    public static func hasReading(_ value: Double?) -> Bool {
        guard let value else { return false }
        return !value.isNaN && !value.isInfinite
    }
}
