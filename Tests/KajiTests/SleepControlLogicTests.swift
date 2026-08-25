import XCTest
@testable import KajiCore
@testable import Kaji

final class SleepControlLogicTests: XCTestCase {
    func testParsesEnabledState() {
        XCTAssertTrue(SleepControlLogic.parseSleepDisabled("""
        System-wide power settings:
         SleepDisabled          1
        """))
    }

    func testMissingOrDisabledStateIsFalse() {
        XCTAssertFalse(SleepControlLogic.parseSleepDisabled(" SleepDisabled 0"))
        XCTAssertFalse(SleepControlLogic.parseSleepDisabled("sleep 1"))
    }

    func testSuccessfulMatchingRequestCommitsObservedState() {
        XCTAssertEqual(
            try SleepControlLogic.resolvedState(
                requested: true,
                commandSucceeded: true,
                observed: true
            ).get(),
            true
        )
    }

    func testFailedRequestDoesNotCommitRequestedState() {
        XCTAssertThrowsError(
            try SleepControlLogic.resolvedState(
                requested: true,
                commandSucceeded: false,
                observed: false
            ).get()
        ) { error in
            XCTAssertEqual(error as? SleepControlError, .commandFailed)
        }
    }

    func testObservedMismatchIsReported() {
        XCTAssertThrowsError(
            try SleepControlLogic.resolvedState(
                requested: true,
                commandSucceeded: true,
                observed: false
            ).get()
        ) { error in
            XCTAssertEqual(error as? SleepControlError, .stateMismatch(observed: false))
        }
    }
    func testSleepRequestGateCompletesOnlyOnce() {
        let gate = SleepRequestGate()
        XCTAssertTrue(gate.claim())
        XCTAssertFalse(gate.claim())
        XCTAssertFalse(gate.claim())
    }

}
