import Foundation

public enum HoverDisclosurePolicy {
    public static let initialOpenDelay: TimeInterval = 0.10
    public static let transitionDelay: TimeInterval = 0
    public static let closeDelay: TimeInterval = 0.35

    public static func openDelay(hasActiveTopic: Bool) -> TimeInterval {
        hasActiveTopic ? transitionDelay : initialOpenDelay
    }
}

public enum HoverSelectionPolicy {
    public static func dismissed<ID: Equatable>(current: ID?, dismissing: ID) -> ID? {
        current == dismissing ? nil : current
    }
}

/// Whether a hover-disclosed note card may close. The card lives inside the
/// popover window, so nothing else dismisses it: every path (pointer leaves
/// the trigger, pointer leaves the card, the note field loses focus) funnels
/// through here, and an active edit is the only veto.
public enum NoteCardHoverPolicy {
    public static func shouldDismiss(
        triggerHovered: Bool,
        cardHovered: Bool,
        editing: Bool
    ) -> Bool {
        !triggerHovered && !cardHovered && !editing
    }
}

/// Height budget for the popover's scrollable panel.
///
/// The panel is `chrome + scrollable content`, and the popover may never be
/// taller than `maxContentHeight`: `AppDelegate.resizePopoverContent` clamps
/// `NSPopover.contentSize` there while the hosting view keeps its full,
/// unclamped SwiftUI height, and the difference shows up as a blank strip at
/// the top of the popover. A hard-coded chrome estimate is what caused that
/// strip repeatedly (it read 104pt against a real 128pt), so the chrome is
/// measured at runtime and only falls back to the estimate for the first
/// layout pass.
public enum PopoverHeightBudget {
    public static let minimumScrollHeight: CGFloat = 180
    public static let initialChromeEstimate: CGFloat = 128

    /// Height the scrollable panel may occupy so that
    /// `chrome + scroll <= maxContentHeight`.
    public static func scrollMaxHeight(maxContentHeight: CGFloat, measuredChrome: CGFloat) -> CGFloat {
        let chrome = measuredChrome > 0 ? measuredChrome : initialChromeEstimate
        return max(minimumScrollHeight, maxContentHeight - chrome)
    }

    /// Everything that is not the scrollable panel: header, dividers, footer,
    /// stack spacing and outer padding.
    public static func chromeHeight(totalHeight: CGFloat, scrollHeight: CGFloat) -> CGFloat {
        max(0, totalHeight - scrollHeight)
    }

    public static func isMeaningfulChange(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) > 0.5
    }
}

public enum GoalControlMetrics {
	public static let diameter: CGFloat = 9
	public static let rowIsCompletionTarget = true
}
