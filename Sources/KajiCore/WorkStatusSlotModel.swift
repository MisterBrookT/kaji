import Foundation

/// Session phase for the menu-bar work countdown slot.
///
/// Mirrors `WorkSessionPhase` in the app target. Kept in KajiCore so
/// `WorkStatusSlotModel` stays unit-testable without AppKit.
public enum WorkStatusSlotPhase: String, Sendable, Equatable {
    case working
    case breakDue
    case breaking
}
public enum WorkTimeDisplayStyle: String, Codable, Sendable, Equatable {
    case minutesOnly
    case exactSeconds
}


/// Pure display model for the optional work countdown in the status item.
///
/// Spec: `dev_docs/specs/2026-07-24-work-status-slot.md`
///
/// - `working` → remaining focus in the selected display style
/// - `breakDue` or `breaking` → remaining break in the selected display style
/// Minutes-only rounds up so a running session never displays `0m`.
public enum WorkStatusSlotModel {
    /// Returns the menu-bar label, or `nil` when the work module is off.
    public static func label(
        workEnabled: Bool,
        phase: WorkStatusSlotPhase,
        focusRemaining: TimeInterval,
        breakRemaining: TimeInterval,
        displayStyle: WorkTimeDisplayStyle = .exactSeconds
    ) -> String? {
        guard workEnabled else { return nil }
        let remaining: TimeInterval
        switch phase {
        case .working:
            remaining = focusRemaining
        case .breakDue, .breaking:
            remaining = breakRemaining
        }
        switch displayStyle {
        case .minutesOnly:
            return minutes(remaining)
        case .exactSeconds:
            return clock(remaining)
        }
    }

    private static func minutes(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        return "\(Int(ceil(clamped / 60)))m"
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
