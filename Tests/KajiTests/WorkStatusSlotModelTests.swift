import XCTest
import KajiCore

/// Unit tests for work status slot pure logic.
/// Spec cases: `dev_docs/specs/2026-07-24-work-status-slot.md` §6.
final class WorkStatusSlotModelTests: XCTestCase {

    // MARK: - §6 acceptance

    func testCase1_workDisabled_yieldsNil() {
        let label = WorkStatusSlotModel.label(
            workEnabled: false,
            phase: .working,
            focusRemaining: 12 * 60 + 5,
            breakRemaining: 4 * 60 + 30
        )
        XCTAssertNil(label)
    }

    func testCase2_working_showsFocusRemaining() {
        let label = WorkStatusSlotModel.label(
            workEnabled: true,
            phase: .working,
            focusRemaining: 12 * 60 + 5,
            breakRemaining: 5 * 60
        )
        XCTAssertEqual(label, "12:05")
    }

    func testCase3_tick_updatesFocusRemaining() {
        let label = WorkStatusSlotModel.label(
            workEnabled: true,
            phase: .working,
            focusRemaining: 12 * 60 + 4,
            breakRemaining: 5 * 60
        )
        XCTAssertEqual(label, "12:04")
    }

    func testCase4_breaking_showsBreakRemaining() {
        let label = WorkStatusSlotModel.label(
            workEnabled: true,
            phase: .breaking,
            focusRemaining: 0,
            breakRemaining: 4 * 60 + 30
        )
        XCTAssertEqual(label, "04:30")
    }

    func testCase5_breakDue_showsBreakRemaining_notBREAK() {
        let label = WorkStatusSlotModel.label(
            workEnabled: true,
            phase: .breakDue,
            focusRemaining: 0,
            breakRemaining: 5 * 60
        )
        XCTAssertEqual(label, "05:00")
        XCTAssertNotEqual(label, "BREAK")
        XCTAssertFalse(label?.contains("BREAK") == true)
    }

    func testCase6_breakEnds_returnsToFocusRemaining() {
        let label = WorkStatusSlotModel.label(
            workEnabled: true,
            phase: .working,
            focusRemaining: 25 * 60,
            breakRemaining: 0
        )
        XCTAssertEqual(label, "25:00")
    }

    func testCase7_disableWhileShowing_slotDisappears() {
        let showing = WorkStatusSlotModel.label(
            workEnabled: true,
            phase: .working,
            focusRemaining: 10 * 60,
            breakRemaining: 5 * 60
        )
        XCTAssertEqual(showing, "10:00")

        let hidden = WorkStatusSlotModel.label(
            workEnabled: false,
            phase: .working,
            focusRemaining: 10 * 60,
            breakRemaining: 5 * 60
        )
        XCTAssertNil(hidden)
    }

    func testCase8_reenable_restoresMatchingPhase() {
        let focus = WorkStatusSlotModel.label(
            workEnabled: true,
            phase: .working,
            focusRemaining: 8 * 60 + 15,
            breakRemaining: 5 * 60
        )
        XCTAssertEqual(focus, "08:15")

        let onBreak = WorkStatusSlotModel.label(
            workEnabled: true,
            phase: .breaking,
            focusRemaining: 0,
            breakRemaining: 3 * 60 + 1
        )
        XCTAssertEqual(onBreak, "03:01")
    }

    // MARK: - Boundaries

    func testB1_focusClampedToZero() {
        let label = WorkStatusSlotModel.label(
            workEnabled: true,
            phase: .working,
            focusRemaining: -3,
            breakRemaining: 5 * 60
        )
        XCTAssertEqual(label, "00:00")
    }

    func testB2_breakClampedToZero_noNegativeSign() {
        let label = WorkStatusSlotModel.label(
            workEnabled: true,
            phase: .breaking,
            focusRemaining: 0,
            breakRemaining: -1.5
        )
        XCTAssertEqual(label, "00:00")
        XCTAssertFalse(label?.contains("-") == true)
    }

    func testWorkDisabled_ignoresPhaseAndTimes() {
        for phase in [WorkStatusSlotPhase.working, .breakDue, .breaking] {
            let label = WorkStatusSlotModel.label(
                workEnabled: false,
                phase: phase,
                focusRemaining: 99,
                breakRemaining: 99
            )
            XCTAssertNil(label)
        }
    }
}
