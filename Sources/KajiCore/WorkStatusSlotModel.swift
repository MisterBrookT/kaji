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

/// Pure display model for the optional work countdown in the status item.
///
/// Spec: `dev_docs/specs/2026-07-24-work-status-slot.md`
///
/// User-visible states when work is enabled:
/// - `working` → remaining focus `MM:SS`
/// - `breakDue` or `breaking` → remaining break `MM:SS` (never `"BREAK"`)
public enum WorkStatusSlotModel {
    /// Returns the menu-bar label, or `nil` when the work module is off.
    public static func label(
        workEnabled: Bool,
        phase: WorkStatusSlotPhase,
        focusRemaining: TimeInterval,
        breakRemaining: TimeInterval
    ) -> String? {
        guard workEnabled else { return nil }
        switch phase {
        case .working:
            return clock(focusRemaining)
        case .breakDue, .breaking:
            return clock(breakRemaining)
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
