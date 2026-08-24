import XCTest
@testable import Kaji

final class BreakSkipConfirmationTests: XCTestCase {
    func testSkipRequiresThreeSecondConfirmation() {
        var confirmation = BreakSkipConfirmation()

        XCTAssertEqual(confirmation.title, "Skip")
        XCTAssertFalse(confirmation.request())
        XCTAssertEqual(confirmation.remainingSeconds, 3)
        XCTAssertTrue(confirmation.isCoolingDown)

        confirmation.tick()
        confirmation.tick()
        XCTAssertEqual(confirmation.title, "Sure?  1")
        XCTAssertFalse(confirmation.request())

        confirmation.tick()
        XCTAssertEqual(confirmation.title, "Sure?")
        XCTAssertFalse(confirmation.isCoolingDown)
        XCTAssertTrue(confirmation.request())
    }
}
