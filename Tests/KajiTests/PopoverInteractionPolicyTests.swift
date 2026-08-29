import XCTest
import KajiCore

final class PopoverInteractionPolicyTests: XCTestCase {
    func testHoverPolicyOpensFirstItemBrieflyAndSwitchesImmediately() {
        XCTAssertEqual(HoverDisclosurePolicy.openDelay(hasActiveTopic: false), 0.10)
        XCTAssertEqual(HoverDisclosurePolicy.openDelay(hasActiveTopic: true), 0)
        XCTAssertGreaterThan(HoverDisclosurePolicy.closeDelay, HoverDisclosurePolicy.initialOpenDelay)
    }

    func testDismissingOldHoverCannotClearNewSelection() {
        XCTAssertEqual(
            HoverSelectionPolicy.dismissed(current: "new", dismissing: "old"),
            "new"
        )
        XCTAssertNil(HoverSelectionPolicy.dismissed(current: "old", dismissing: "old"))
    }

    func testGoalCompletionControlStaysCompactAndUsesWholeRow() {
        XCTAssertEqual(GoalControlMetrics.diameter, 9)
        XCTAssertTrue(GoalControlMetrics.rowIsCompletionTarget)
    }
}
