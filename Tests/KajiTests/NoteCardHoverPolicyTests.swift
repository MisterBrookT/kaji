import XCTest
@testable import KajiCore

/// The goal note card lives inside the popover's own window, so nothing in the
/// system dismisses it: if this policy says "keep", the card stays on screen
/// until the popover closes. The stranded-card path was exactly that — the
/// note field losing focus while the pointer already sat outside both the
/// trigger icon and the card.
final class NoteCardHoverPolicyTests: XCTestCase {
    func testDismissesWhenPointerLeftBothSurfacesAndEditingEnded() {
        XCTAssertTrue(
            NoteCardHoverPolicy.shouldDismiss(triggerHovered: false, cardHovered: false, editing: false)
        )
    }

    func testKeepsCardWhilePointerRestsOnTrigger() {
        XCTAssertFalse(
            NoteCardHoverPolicy.shouldDismiss(triggerHovered: true, cardHovered: false, editing: false)
        )
    }

    func testKeepsCardWhilePointerRestsOnCard() {
        XCTAssertFalse(
            NoteCardHoverPolicy.shouldDismiss(triggerHovered: false, cardHovered: true, editing: false)
        )
    }

    func testEditingVetoesDismissalEvenWithPointerAway() {
        XCTAssertFalse(
            NoteCardHoverPolicy.shouldDismiss(triggerHovered: false, cardHovered: false, editing: true)
        )
    }

    /// Hover-out during an edit is deferred; the later focus loss re-evaluates
    /// with the pointer still away, and the card must then go.
    func testFocusLossAfterHoverOutDismisses() {
        XCTAssertFalse(
            NoteCardHoverPolicy.shouldDismiss(triggerHovered: false, cardHovered: false, editing: true)
        )
        XCTAssertTrue(
            NoteCardHoverPolicy.shouldDismiss(triggerHovered: false, cardHovered: false, editing: false)
        )
    }

    func testAdjacentRowsSwitchInstantlyWhileFirstOpenIsDelayed() {
        XCTAssertEqual(HoverDisclosurePolicy.openDelay(hasActiveTopic: true), 0)
        XCTAssertGreaterThan(HoverDisclosurePolicy.openDelay(hasActiveTopic: false), 0)
    }
}
